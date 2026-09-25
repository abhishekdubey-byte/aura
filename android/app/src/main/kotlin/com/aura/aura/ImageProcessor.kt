package com.aura.aura

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Typeface
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors

/**
 * Mirrors and/or watermarks captured photos using Android's native bitmap
 * pipeline, which is an order of magnitude faster than pure-Dart JPEG
 * decode/encode on full-resolution images. Jobs run one at a time on a
 * background thread to bound memory use.
 */
class ImageProcessor : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "prepareAnalysis") {
            prepareAnalysis(call, result)
            return
        }
        if (call.method != "process") {
            result.notImplemented()
            return
        }
        val input = call.argument<String>("input")
        val output = call.argument<String>("output")
        val mirror = call.argument<Boolean>("mirror") ?: false
        val watermark = call.argument<String>("watermark")
        // Target width / height for a centred crop, or null to keep the full frame
        val aspect = call.argument<Double>("aspect")
        if (input == null || output == null) {
            result.error("bad_args", "input and output are required", null)
            return
        }

        executor.execute {
            try {
                process(input, output, mirror, watermark, aspect)
                mainHandler.post { result.success(output) }
            } catch (e: Throwable) {
                mainHandler.post { result.error("process_failed", e.message, null) }
            }
        }
    }

    /**
     * Writes an upright, downscaled JPEG (longest side <= maxSide) for the ML
     * models, decoding at reduced resolution so it stays fast on 16MP photos.
     * Returns the output size and the original (upright) size.
     */
    private fun prepareAnalysis(call: MethodCall, result: MethodChannel.Result) {
        val input = call.argument<String>("input")
        val output = call.argument<String>("output")
        val maxSide = call.argument<Int>("maxSide") ?: 1024
        if (input == null || output == null) {
            result.error("bad_args", "input and output are required", null)
            return
        }
        executor.execute {
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(input, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw IOException("Could not read $input")

                // Largest power-of-two subsample that still leaves >= maxSide
                var sample = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
                var bitmap = BitmapFactory.decodeFile(input, BitmapFactory.Options().apply { inSampleSize = sample })
                    ?: throw IOException("Could not decode $input")

                val orientation = try {
                    ExifInterface(input).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                } catch (e: IOException) {
                    ExifInterface.ORIENTATION_NORMAL
                }
                val matrix = orientationMatrix(orientation)
                val scale = maxSide.toFloat() / maxOf(bitmap.width, bitmap.height)
                if (scale < 1f) matrix.postScale(scale, scale)
                if (!matrix.isIdentity) {
                    val transformed = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                    if (transformed !== bitmap) bitmap.recycle()
                    bitmap = transformed
                }
                FileOutputStream(output).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }

                // Dark photos: give the detectors a brightened copy (the natural
                // one is still used to judge exposure)
                var detectorPath = output
                val brightened = brightenIfDark(bitmap)
                if (brightened != null) {
                    detectorPath = output.removeSuffix(".jpg") + "_ml.jpg"
                    FileOutputStream(detectorPath).use { brightened.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                    brightened.recycle()
                }

                val swapped = orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                    orientation == ExifInterface.ORIENTATION_ROTATE_270 ||
                    orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
                    orientation == ExifInterface.ORIENTATION_TRANSVERSE
                val info = mapOf(
                    "path" to output,
                    "detectorPath" to detectorPath,
                    "width" to bitmap.width,
                    "height" to bitmap.height,
                    "sourceWidth" to if (swapped) bounds.outHeight else bounds.outWidth,
                    "sourceHeight" to if (swapped) bounds.outWidth else bounds.outHeight,
                )
                bitmap.recycle()
                mainHandler.post { result.success(info) }
            } catch (e: Throwable) {
                mainHandler.post { result.error("prepare_failed", e.message, null) }
            }
        }
    }

    /**
     * Auto-levels plus gamma for under-exposed images (mean luma < 70), so face
     * and pose detection still work in low light. Returns null when the image
     * is bright enough.
     */
    private fun brightenIfDark(bitmap: Bitmap): Bitmap? {
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)

        val histogram = IntArray(256)
        var count = 0
        var sum = 0L
        for (i in pixels.indices step 3) {
            val c = pixels[i]
            val y = (299 * ((c shr 16) and 0xff) + 587 * ((c shr 8) and 0xff) + 114 * (c and 0xff)) / 1000
            histogram[y]++
            sum += y
            count++
        }
        val mean = sum.toDouble() / count
        if (mean >= 70) return null

        fun percentile(p: Double): Int {
            val target = (count * p).toInt()
            var acc = 0
            for (v in 0..255) {
                acc += histogram[v]
                if (acc >= target) return v
            }
            return 255
        }
        val black = percentile(0.005)
        val white = maxOf(percentile(0.995), black + 24)
        val stretchedMean = ((mean - black) / (white - black)).coerceIn(0.02, 0.98)
        // Gamma that lifts the stretched mean to ~0.45
        val gamma = (Math.log(0.45) / Math.log(stretchedMean)).coerceIn(0.3, 1.0)
        val lut = IntArray(256) { v ->
            val x = ((v - black).toDouble() / (white - black)).coerceIn(0.0, 1.0)
            (Math.pow(x, gamma) * 255).toInt().coerceIn(0, 255)
        }
        for (i in pixels.indices) {
            val c = pixels[i]
            pixels[i] = (c and 0xff000000.toInt()) or
                (lut[(c shr 16) and 0xff] shl 16) or
                (lut[(c shr 8) and 0xff] shl 8) or
                lut[c and 0xff]
        }
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(pixels, 0, w, 0, 0, w, h)
        return out
    }

    fun shutdown() {
        executor.shutdown()
    }

    private fun process(input: String, output: String, mirror: Boolean, watermark: String?, aspect: Double?) {
        var bitmap = BitmapFactory.decodeFile(input, BitmapFactory.Options().apply { inMutable = true })
            ?: throw IOException("Could not decode $input")

        val sourceExif = ExifInterface(input)
        val matrix = orientationMatrix(
            sourceExif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        )
        if (mirror) {
            matrix.postScale(-1f, 1f)
        }
        if (!matrix.isIdentity) {
            // Only exact 90° rotations and flips, so no filtering: pixels are moved, not resampled
            val transformed = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, false)
            if (transformed !== bitmap) bitmap.recycle()
            bitmap = transformed
        }

        if (aspect != null && aspect > 0) {
            bitmap = centerCrop(bitmap, aspect)
        }

        if (!watermark.isNullOrEmpty()) {
            if (!bitmap.isMutable) {
                val mutable = bitmap.copy(Bitmap.Config.ARGB_8888, true)
                bitmap.recycle()
                bitmap = mutable
            }
            drawWatermark(bitmap, watermark)
        }

        // Maximum quality so re-saving adds no visible loss over the camera original
        FileOutputStream(output).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }
        bitmap.recycle()

        copyExif(sourceExif, output)
    }

    /** Largest centred region of the given width / height ratio (even sizes). */
    private fun centerCrop(bitmap: Bitmap, aspect: Double): Bitmap {
        val w = bitmap.width
        val h = bitmap.height
        var cw = w
        var ch = h
        if (w.toDouble() / h > aspect) cw = (h * aspect).toInt() else ch = (w / aspect).toInt()
        cw -= cw % 2
        ch -= ch % 2
        if (cw >= w && ch >= h) return bitmap
        val cropped = Bitmap.createBitmap(bitmap, (w - cw) / 2, (h - ch) / 2, cw, ch)
        if (cropped !== bitmap) bitmap.recycle()
        return cropped
    }

    /** Pixels are written upright, so the output keeps the capture metadata with a normal orientation. */
    private fun copyExif(source: ExifInterface, output: String) {
        try {
            val target = ExifInterface(output)
            for (tag in EXIF_TAGS) {
                source.getAttribute(tag)?.let { target.setAttribute(tag, it) }
            }
            target.setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
            target.saveAttributes()
        } catch (e: IOException) {
            // Metadata is best-effort; the image itself is already saved
        }
    }

    private fun drawWatermark(bitmap: Bitmap, text: String) {
        val textSize = maxOf(24f, bitmap.width / 40f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            this.textSize = textSize
            typeface = Typeface.DEFAULT_BOLD
            setShadowLayer(textSize / 8f, 0f, 0f, Color.argb(160, 0, 0, 0))
        }
        val margin = textSize * 0.8f
        Canvas(bitmap).drawText(text, margin, bitmap.height - margin, paint)
    }

    private fun orientationMatrix(orientation: Int): Matrix {
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { m.setRotate(90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> m.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { m.setRotate(-90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> m.setRotate(-90f)
        }
        return m
    }

    companion object {
        private val EXIF_TAGS = arrayOf(
            ExifInterface.TAG_DATETIME,
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED,
            ExifInterface.TAG_SUBSEC_TIME,
            ExifInterface.TAG_MAKE,
            ExifInterface.TAG_MODEL,
            ExifInterface.TAG_EXPOSURE_TIME,
            ExifInterface.TAG_F_NUMBER,
            ExifInterface.TAG_ISO_SPEED_RATINGS,
            ExifInterface.TAG_FOCAL_LENGTH,
            ExifInterface.TAG_FLASH,
            ExifInterface.TAG_WHITE_BALANCE,
            ExifInterface.TAG_GPS_LATITUDE,
            ExifInterface.TAG_GPS_LATITUDE_REF,
            ExifInterface.TAG_GPS_LONGITUDE,
            ExifInterface.TAG_GPS_LONGITUDE_REF,
            ExifInterface.TAG_GPS_ALTITUDE,
            ExifInterface.TAG_GPS_ALTITUDE_REF,
        )
    }
}
