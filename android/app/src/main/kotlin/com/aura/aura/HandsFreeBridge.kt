package com.aura.aura

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import java.util.Locale
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Inference never owns the camera: it inspects reduced preview snapshots so
 * video/audio capture keeps its existing native session and resolution. */
class HandsFreeBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var detector: GestureRecognizer? = null
    private var events: EventChannel.EventSink? = null
    private var speech: SpeechRecognizer? = null
    private var voiceOwner: String? = null
    private var speechGeneration = 0
    private var failures = 0
    private var preferSystem = false
    private var recreateSpeech = false
    private var closed = false
    private val method = MethodChannel(messenger, "com.aura.aura/hands_free")
    private val stream = EventChannel(messenger, "com.aura.aura/hands_free_events")

    init { method.setMethodCallHandler(this); stream.setStreamHandler(this) }
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { events = sink }
    override fun onCancel(arguments: Any?) { events = null; stopVoice() }

    private fun onDevice(): Boolean = Build.VERSION.SDK_INT >= 31 &&
        SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(mapOf(
                "gestures" to true,
                "voice" to (onDevice() || SpeechRecognizer.isRecognitionAvailable(context)),
                "onDeviceVoice" to onDevice()))
            "prepareGestures" -> worker.execute {
                try {
                    prepareDetector()
                    main.post { result.success(null) }
                } catch (e: Throwable) {
                    main.post { result.error("gesture_unavailable", "Hand recognition is unavailable on this device.", null) }
                }
            }
            "analyze" -> {
                val bytes = call.argument<ByteArray>("image")
                if (bytes == null || bytes.size > 4 * 1024 * 1024) {
                    result.error("invalid_frame", "Invalid preview frame", null)
                    return
                }
                worker.execute {
                    try {
                        val recognizer = prepareDetector()
                        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            ?: throw IllegalArgumentException("Invalid image")
                        val image = BitmapImageBuilder(bitmap).build()
                        try {
                            val recognized = recognizer.recognize(image)
                            val hands = recognized.landmarks().mapIndexed { index, points ->
                                val gesture = recognized.gestures().getOrNull(index)?.maxByOrNull { it.score() }
                                mapOf("gesture" to (gesture?.categoryName() ?: "None"),
                                    "score" to (gesture?.score()?.toDouble() ?: 0.0),
                                    "points" to points.map { listOf(it.x().toDouble() * bitmap.width / bitmap.height, it.y().toDouble(), it.z().toDouble()) })
                            }
                            main.post { result.success(hands) }
                        } finally { image.close(); bitmap.recycle() }
                    } catch (e: Throwable) {
                        main.post { result.error("gesture_frame_failed", "Could not read this preview frame.", null) }
                    }
                }
            }
            "startVoice" -> {
                val owner = call.argument<String>("owner") ?: ""
                if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    result.error("microphone_denied", "Allow microphone access to use voice commands.", null)
                } else if (!onDevice() && !SpeechRecognizer.isRecognitionAvailable(context)) {
                    result.error("voice_unavailable", "No speech recognition service is installed.", null)
                } else {
                    stopVoice()
                    voiceOwner = owner
                    failures = 0
                    try { listen(); result.success(null) }
                    catch (e: Exception) { stopVoice(); result.error("voice_unavailable", "Could not start voice commands.", null) }
                }
            }
            "stopVoice" -> {
                if (call.argument<String>("owner") == voiceOwner) stopVoice()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun prepareDetector(): GestureRecognizer {
        detector?.let { return it }
        check(!closed)
        return GestureRecognizer.createFromOptions(context,
            GestureRecognizer.GestureRecognizerOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath("gesture_recognizer.task").build())
                .setRunningMode(RunningMode.IMAGE).setNumHands(2)
                .setMinHandDetectionConfidence(0.65f)
                .setMinHandPresenceConfidence(0.65f)
                .setMinTrackingConfidence(0.6f).build()).also { detector = it }
    }

    private fun emit(type: String, text: String? = null) {
        events?.success(mapOf("owner" to voiceOwner, "type" to type, "text" to text))
    }

    private fun listen() {
        if (closed || voiceOwner == null) return
        val generation = ++speechGeneration
        if (recreateSpeech) {
            speech?.destroy()
            speech = null
            recreateSpeech = false
        }
        val recognizer = speech ?: run {
            if (!preferSystem && onDevice() && Build.VERSION.SDK_INT >= 31) {
                try { SpeechRecognizer.createOnDeviceSpeechRecognizer(context) }
                catch (_: Exception) {
                    preferSystem = true
                    SpeechRecognizer.createSpeechRecognizer(context)
                }
            } else SpeechRecognizer.createSpeechRecognizer(context)
        }.also { speech = it }
        recognizer.setRecognitionListener(object : RecognitionListener {
            private fun current() = !closed && voiceOwner != null && generation == speechGeneration
            override fun onReadyForSpeech(params: Bundle?) { if (current()) emit("listening") }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() { if (current()) emit("processing") }
            override fun onPartialResults(partialResults: Bundle?) {} // Only complete utterances can capture.
            override fun onEvent(eventType: Int, params: Bundle?) {}
            override fun onResults(results: Bundle?) {
                if (!current()) return
                failures = 0
                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.let { emit("words", it) }
                restart(generation)
            }
            override fun onError(error: Int) {
                if (!current()) return
                Log.w("AuraHandsFree", "Speech error=$error, onDevice=${!preferSystem && onDevice()}")
                if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                    emit("error", "Voice is enabled. Allow microphone access in Android settings; listening will retry automatically.")
                    stopVoice()
                    return
                }
                val quiet = error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                if (quiet) {
                    failures = 0
                    restart(generation)
                    return
                }
                failures++
                // An installed on-device recognizer does not guarantee its
                // English model is downloaded or that the service is usable.
                if (!preferSystem && onDevice() && SpeechRecognizer.isRecognitionAvailable(context)) {
                    preferSystem = true
                    recreateSpeech = true
                    restart(generation, 1200, "Switching to Android speech service…")
                    return
                }
                recreateSpeech = error == SpeechRecognizer.ERROR_SERVER_DISCONNECTED ||
                    error == SpeechRecognizer.ERROR_CLIENT
                val delay = minOf(30000L, 1500L * (1L shl minOf(failures, 4)))
                val explanation = when (error) {
                    SpeechRecognizer.ERROR_AUDIO -> "Microphone busy"
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Speech service busy"
                    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                    SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "English speech model unavailable; check your Android speech settings"
                    SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Speech service connection unavailable"
                    else -> "Speech service temporarily unavailable"
                }
                restart(generation, delay, "$explanation. Retrying in ${delay / 1000}s…")
            }
        })
        recognizer.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, if (Locale.getDefault().language == "en") Locale.getDefault().toLanguageTag() else "en-US")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            if (!preferSystem && onDevice()) putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        })
    }

    private fun restart(generation: Int, delay: Long = 800, message: String? = null) {
        if (message == null) emit("waiting") else emit("retrying", message)
        main.postDelayed({
            if (voiceOwner != null && !closed && generation == speechGeneration) {
                try { listen() } catch (_: Exception) {
                    recreateSpeech = true
                    restart(speechGeneration, 30000, "Speech service unavailable. Retrying in 30s…")
                }
            }
        }, delay)
    }

    fun stopVoice() {
        speechGeneration++
        voiceOwner = null
        speech?.cancel()
        speech?.destroy()
        speech = null
    }

    fun pause() { stopVoice() }
    fun close() {
        closed = true
        stopVoice()
        main.removeCallbacksAndMessages(null)
        method.setMethodCallHandler(null)
        stream.setStreamHandler(null)
        worker.execute { detector?.close(); detector = null }
        worker.shutdown()
    }
}
