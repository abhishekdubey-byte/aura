import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Applies front-camera mirroring and the optional watermark to a captured
/// photo. Uses Android's native bitmap pipeline (well under a second for a
/// 16MP shot) and falls back to pure Dart in a background isolate elsewhere.
class PhotoProcessor {
  static const MethodChannel _channel = MethodChannel('com.aura.aura/image');

  static bool needsProcessing({
    required bool mirror,
    String? watermark,
    double? aspect,
  }) => mirror || aspect != null || (watermark != null && watermark.isNotEmpty);

  /// Returns the path of the processed JPEG, or [imagePath] when nothing needs
  /// to change or processing fails. [aspect] (width / height) crops the
  /// centre of the frame to that shape.
  static Future<String> process(
    String imagePath, {
    required bool mirror,
    String? watermark,
    double? aspect,
  }) async {
    if (!needsProcessing(mirror: mirror, watermark: watermark, aspect: aspect)) {
      return imagePath;
    }

    final tempDir = (await getTemporaryDirectory()).path;
    final outputPath =
        '$tempDir/aura_${DateTime.now().microsecondsSinceEpoch}.jpg';

    try {
      final result = await _channel.invokeMethod<String>('process', {
        'input': imagePath,
        'output': outputPath,
        'mirror': mirror,
        'watermark': watermark,
        'aspect': aspect,
      });
      if (result != null) return result;
    } on MissingPluginException {
      // No native implementation on this platform
    } catch (e) {
      debugPrint(
        'PhotoProcessor: native processing failed, using Dart fallback: $e',
      );
    }

    return compute(_processInDart, {
      'imagePath': imagePath,
      'outputPath': outputPath,
      'mirror': mirror,
      'watermark': watermark ?? '',
      'aspect': aspect,
    });
  }
}

/// Single decode → edit → JPEG encode pass (slow on full-resolution images).
Future<String> _processInDart(Map<String, dynamic> args) async {
  final String imagePath = args['imagePath'];
  final String outputPath = args['outputPath'];
  final bool mirror = args['mirror'];
  final String watermark = args['watermark'];
  final double? aspect = args['aspect'];

  try {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return imagePath;

    // Apply EXIF rotation to the pixels first so the mirror uses the right axis
    image = img.bakeOrientation(image);

    if (mirror) {
      image = img.flipHorizontal(image);
    }

    if (aspect != null) {
      final int w = image.width, h = image.height;
      int cw = w, ch = h;
      if (w / h > aspect) {
        cw = (h * aspect).floor();
      } else {
        ch = (w / aspect).floor();
      }
      cw -= cw % 2;
      ch -= ch % 2;
      image = img.copyCrop(
        image,
        x: (w - cw) ~/ 2,
        y: (h - ch) ~/ 2,
        width: cw,
        height: ch,
      );
    }

    if (watermark.isNotEmpty) {
      img.drawString(
        image,
        watermark,
        font: img.arial24,
        x: 20,
        y: image.height - 40,
        color: img.ColorRgb8(255, 255, 255),
      );
    }

    await File(outputPath).writeAsBytes(img.encodeJpg(image, quality: 100));
    return outputPath;
  } catch (e) {
    debugPrint('Error processing image: $e');
    return imagePath;
  }
}
