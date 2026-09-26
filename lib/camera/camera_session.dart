import 'dart:io';

import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Prefer full detail where supported; gracefully fall back on constrained
/// hardware. Denying the microphone must not disable still photography.
class CameraSession {
  static Future<bool>? _lowMemory;
  static Future<bool> _isLowMemory() => _lowMemory ??= (() async {
    try {
      return Platform.isAndroid &&
          (await DeviceInfoPlugin().androidInfo).isLowRamDevice;
    } catch (_) {
      return false;
    }
  })();

  static Future<CameraController> open(
    CameraDescription camera, {
    ResolutionPreset preferred = ResolutionPreset.max,
  }) async {
    final lowMemory = await _isLowMemory();
    final presets = <ResolutionPreset>{
      if (!lowMemory) preferred,
      if (!lowMemory && preferred == ResolutionPreset.max)
        ResolutionPreset.veryHigh,
      ResolutionPreset.high,
      ResolutionPreset.medium,
    };
    Object? lastError;
    bool audio = true;
    for (final preset in presets) {
      for (int attempt = 0; attempt < 2; attempt++) {
        final controller = CameraController(
          camera,
          preset,
          enableAudio: audio,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        try {
          await controller.initialize();
          return controller;
        } catch (e) {
          lastError = e;
          try {
            await controller.dispose();
          } catch (_) {}
          if (e is CameraException && e.code.startsWith('CameraAccess')) {
            rethrow;
          }
          if (audio &&
              e is CameraException &&
              e.code.startsWith('AudioAccess')) {
            audio = false;
            continue;
          }
          break;
        }
      }
    }
    throw lastError ??
        CameraException(
          'CameraUnavailable',
          'No supported camera configuration',
        );
  }

  static Future<(double, double)> zoomRange(CameraController camera) async {
    try {
      final values = await Future.wait([
        camera.getMinZoomLevel(),
        camera.getMaxZoomLevel(),
      ]);
      if (values[0].isFinite &&
          values[1].isFinite &&
          values[0] > 0 &&
          values[1] >= values[0]) {
        return (values[0], values[1]);
      }
    } catch (e) {
      debugPrint('Camera zoom limits unavailable: $e');
    }
    return (1.0, 1.0);
  }

  static Future<bool> flash(CameraController camera, FlashMode mode) async {
    try {
      await camera.setFlashMode(mode);
      return true;
    } catch (_) {
      return false;
    }
  }
}
