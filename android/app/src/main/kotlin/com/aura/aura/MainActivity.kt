package com.aura.aura

import android.media.MediaActionSound
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aura.aura/volume"
    private val SHUTTER_CHANNEL = "com.aura.aura/shutter"
    private val IMAGE_CHANNEL = "com.aura.aura/image"
    private var eventSink: EventChannel.EventSink? = null
    private var mediaActionSound: MediaActionSound? = null
    private var imageProcessor: ImageProcessor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        // Preload system camera sounds so playback is instant on capture
        val sound = MediaActionSound().apply {
            load(MediaActionSound.SHUTTER_CLICK)
            load(MediaActionSound.START_VIDEO_RECORDING)
            load(MediaActionSound.STOP_VIDEO_RECORDING)
        }
        mediaActionSound = sound

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHUTTER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "shutter" -> sound.play(MediaActionSound.SHUTTER_CLICK)
                "videoStart" -> sound.play(MediaActionSound.START_VIDEO_RECORDING)
                "videoStop" -> sound.play(MediaActionSound.STOP_VIDEO_RECORDING)
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            result.success(null)
        }

        val processor = ImageProcessor()
        imageProcessor = processor
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IMAGE_CHANNEL).setMethodCallHandler(processor)
    }

    override fun onDestroy() {
        mediaActionSound?.release()
        mediaActionSound = null
        imageProcessor?.shutdown()
        imageProcessor = null
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                if (event.repeatCount == 0) {
                    eventSink?.success("down")
                }
            } else if (event.action == KeyEvent.ACTION_UP) {
                eventSink?.success("up")
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
