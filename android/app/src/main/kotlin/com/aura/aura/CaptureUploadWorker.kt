package com.aura.aura

import android.content.Context
import android.util.Base64
import androidx.work.Worker
import androidx.work.WorkerParameters
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

class UploadResponseException(val status: Int) : IOException("Upload server returned HTTP $status")

/** Standard uploads stream small files; TUS checkpoints large files in 6 MiB chunks. */
class CaptureUploadTransport(
    private val store: CaptureUploadStore,
    private val stopped: () -> Boolean = { false },
    private val client: OkHttpClient = http,
) {
    private val config = store.config()
    private val base = config.first.toHttpUrl()
    private val bucket = config.third
    private val deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(7)

    private fun checkRunning() {
        if (stopped() || System.nanoTime() >= deadline) throw IOException("Upload paused; will resume")
    }

    private fun request(url: HttpUrl): Request.Builder {
        val directHost = base.host.removeSuffix(".supabase.co") + ".storage.supabase.co"
        require(url.scheme == base.scheme && (url.host == base.host ||
            (base.host.endsWith(".supabase.co") && url.host == directHost))) { "Unexpected upload host" }
        require(url.port == base.port) { "Unexpected upload port" }
        return Request.Builder().url(url).header("apikey", config.second)
            .header("Authorization", "Bearer ${config.second}").header("x-upsert", "false")
    }

    private fun body(file: File, offset: Long, length: Long, mime: String) = object : RequestBody() {
        override fun contentType() = mime.toMediaType()
        override fun contentLength() = length
        override fun writeTo(sink: BufferedSink) {
            RandomAccessFile(file, "r").use { input ->
                input.seek(offset)
                val bytes = ByteArray(64 * 1024)
                var remaining = length
                while (remaining > 0) {
                    checkRunning()
                    val count = input.read(bytes, 0, minOf(bytes.size.toLong(), remaining).toInt())
                    if (count < 0) throw IOException("Capture file changed during upload")
                    sink.write(bytes, 0, count)
                    remaining -= count
                }
            }
        }
    }

    fun upload(row: JSONObject) {
        val file = File(store.root, row.getString("id"))
        if (!file.isFile || file.length() != row.getLong("bytes")) throw java.io.FileNotFoundException("Original capture is unavailable")
        checkRunning()
        if (file.length() > chunkSize) resumable(row, file) else standard(row, file)
    }

    private fun standard(row: JSONObject, file: File) {
        val url = base.newBuilder().addPathSegments("storage/v1/object").addPathSegment(bucket)
            .addPathSegment(row.getString("id")).build()
        client.newCall(request(url).post(body(file, 0, file.length(), row.getString("mime"))).build())
            .execute().use { response ->
                if (!response.isSuccessful && !alreadyStored(response)) throw UploadResponseException(response.code)
            }
    }

    private fun resumable(row: JSONObject, file: File) {
        var uploadUrl = row.optString("uploadUrl").takeIf { it.isNotBlank() }?.toHttpUrl()
        var offset = 0L
        if (uploadUrl != null) {
            client.newCall(request(uploadUrl).header("Tus-Resumable", "1.0.0").head().build()).execute().use { response ->
                if (response.code == 404 || response.code == 410) {
                    uploadUrl = null
                    row.remove("uploadUrl")
                    store.write(row)
                } else {
                    if (!response.isSuccessful) throw UploadResponseException(response.code)
                    offset = response.header("Upload-Offset")?.toLongOrNull() ?: throw IOException("Missing upload offset")
                }
            }
        }
        if (uploadUrl == null) {
            val metadata = mapOf("bucketName" to bucket, "objectName" to row.getString("id"),
                "contentType" to row.getString("mime"), "cacheControl" to "3600")
                .entries.joinToString(",") { "${it.key} ${Base64.encodeToString(it.value.toByteArray(), Base64.NO_WRAP)}" }
            val endpoint = base.newBuilder().addPathSegments("storage/v1/upload/resumable").build()
            client.newCall(request(endpoint).header("Tus-Resumable", "1.0.0")
                .header("Upload-Length", file.length().toString()).header("Upload-Metadata", metadata)
                .post(ByteArray(0).toRequestBody()).build()).execute().use { response ->
                if (alreadyStored(response)) return
                if (response.code != 201) throw UploadResponseException(response.code)
                uploadUrl = response.header("Location")?.let { endpoint.resolve(it) }
                    ?: throw IOException("Missing resumable upload URL")
                // Validate before retaining or sending credentials to a returned location.
                request(uploadUrl!!)
                row.put("uploadUrl", uploadUrl.toString())
                store.write(row)
            }
        }
        require(offset in 0..file.length()) { "Invalid upload offset" }
        while (offset < file.length()) {
            checkRunning()
            val count = minOf(chunkSize, file.length() - offset)
            client.newCall(request(uploadUrl!!).header("Tus-Resumable", "1.0.0")
                .header("Upload-Offset", offset.toString())
                .patch(body(file, offset, count, "application/offset+octet-stream")).build()).execute().use { response ->
                // A 409 can mean an offset conflict, not a completed object. HEAD on the
                // next attempt determines what actually reached the server.
                if (response.code != 204) throw UploadResponseException(response.code)
                val confirmed = response.header("Upload-Offset")?.toLongOrNull()
                if (confirmed != offset + count) throw IOException("Unexpected upload offset")
                offset = confirmed
                row.put("offset", offset)
                store.write(row)
            }
        }
    }

    private fun alreadyStored(response: Response): Boolean {
        if (response.code !in listOf(400, 409)) return false
        // An insert-only retry may find the exact hash-keyed object already stored.
        val message = response.peekBody(2048).string()
        return message.contains("ResourceAlreadyExists") || message.contains("Duplicate") ||
            message.contains("Asset Already Exists") || message.contains("The resource already exists")
    }

    companion object {
        const val chunkSize = 6L * 1024 * 1024
        val http = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(90, TimeUnit.SECONDS).writeTimeout(90, TimeUnit.SECONDS)
            .callTimeout(2, TimeUnit.MINUTES).followRedirects(false).followSslRedirects(false)
            .retryOnConnectionFailure(false).build()
    }
}

class CaptureUploadWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val scope = inputData.getString("scope") ?: return Result.failure()
        val id = inputData.getString("id") ?: return Result.failure()
        if (!CaptureUploadStore.validScope(scope) || !CaptureUploadStore.validId(id)) return Result.failure()
        val store = CaptureUploadStore(applicationContext, scope)
        val row = store.read(id) ?: return Result.failure()
        if (row.optString("status") == "uploaded") return Result.success()
        if (!slots.tryAcquire()) return Result.retry()
        try {
            row.put("status", "uploading").put("attempts", row.optInt("attempts") + 1)
            store.write(row)
            CaptureUploadTransport(store, { isStopped }).upload(row)
            row.put("status", "uploaded").put("completedAt", System.currentTimeMillis())
            row.remove("error")
            row.remove("uploadUrl")
            store.write(row) // Commit receipt before deleting the durable original.
            File(store.root, id).delete()
            return Result.success()
        } catch (e: Exception) {
            val missing = e is java.io.FileNotFoundException
            val serverBlocked = e is UploadResponseException && e.status in listOf(400, 401, 403, 404, 413, 415)
            row.put("status", if (missing) "missing" else if (serverBlocked) "blocked" else "retrying")
            row.put("error", when {
                missing -> "Original file is unavailable. Capture or import it again."
                serverBlocked -> "Server rejected this upload. The original is retained; check server access and file limits."
                else -> "Waiting to retry. Your original is stored on this device."
            })
            try { store.write(row) } catch (_: Exception) { /* Existing journal and original remain. */ }
            return if (missing) Result.failure() else Result.retry()
        } finally { slots.release() }
    }
    companion object { private val slots = Semaphore(2) }
}
