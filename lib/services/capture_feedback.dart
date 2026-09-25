import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Instant shutter/recording feedback (system camera sounds + haptics).
/// All calls are fire-and-forget so they never delay the capture path.
class CaptureFeedback {
  static const MethodChannel _channel = MethodChannel('com.aura.aura/shutter');

  static void shutter() {
    HapticFeedback.lightImpact();
    _play('shutter');
  }

  static void videoStart() {
    HapticFeedback.mediumImpact();
    _play('videoStart');
  }

  /// Haptic on release. Call [videoStopSound] once the recording is closed so
  /// the sound is not captured at the end of the clip.
  static void videoStop() {
    HapticFeedback.mediumImpact();
  }

  static void videoStopSound() {
    _play('videoStop');
  }

  static void _play(String method) {
    _channel.invokeMethod<void>(method).catchError((Object e) {
      debugPrint('CaptureFeedback: $method failed: $e');
    });
  }
}
