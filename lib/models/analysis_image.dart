import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// One upright, downscaled copy of a photo shared by every model in the Aura
/// pipeline, so face, pose, segmentation and pixel measurements all use the
/// same coordinates (the originals are up to 16MP and may carry EXIF
/// rotation, which each detector used to handle differently).
class AnalysisImage {
  AnalysisImage({
    required this.path,
    String? detectorPath,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
  }) : detectorPath = detectorPath ?? path;

  /// The downscaled JPEG, used for pixel measurements (exposure, focus).
  final String path;
  /// What the ML detectors read: same as [path], or a brightened copy when
  /// the photo is very dark (detectors fail on near-black faces).
  final String detectorPath;
  final int width;
  final int height;

  /// Upright size of the original photo.
  final int sourceWidth;
  final int sourceHeight;

  /// Multiply analysis coordinates by this to get original-photo coordinates.
  double get toSourceScale => sourceWidth / width;

  InputImage? _inputImage;
  InputImage get inputImage => _inputImage ??= InputImage.fromFilePath(detectorPath);

  static const MethodChannel _channel = MethodChannel('com.aura.aura/image');

  static Future<AnalysisImage> create(String imagePath, {int maxSide = 1024}) async {
    final String output = '${(await getTemporaryDirectory()).path}/aura_analysis_${DateTime.now().microsecondsSinceEpoch}.jpg';
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('prepareAnalysis', {
        'input': imagePath,
        'output': output,
        'maxSide': maxSide,
      });
      if (info != null) {
        return AnalysisImage(
          path: info['path'] as String,
          detectorPath: info['detectorPath'] as String?,
          width: info['width'] as int,
          height: info['height'] as int,
          sourceWidth: info['sourceWidth'] as int,
          sourceHeight: info['sourceHeight'] as int,
        );
      }
    } on MissingPluginException {
      // No native implementation on this platform
    } catch (e) {
      debugPrint('AnalysisImage: native preparation failed, using Dart: $e');
    }
    return compute(_prepareInDart, (imagePath, output, maxSide));
  }

  /// Decodes the small analysis JPEG for pixel-level work.
  Future<img.Image> decode() => compute(_decodeSmall, path);

  void deleteFile() {
    File(path).delete().ignore();
    if (detectorPath != path) File(detectorPath).delete().ignore();
  }
}

img.Image _decodeSmall(String path) {
  final image = img.decodeJpg(File(path).readAsBytesSync());
  if (image == null) throw Exception('Could not decode $path');
  return image;
}

AnalysisImage _prepareInDart((String, String, int) args) {
  final (input, output, maxSide) = args;
  img.Image? image = img.decodeImage(File(input).readAsBytesSync());
  if (image == null) throw Exception('Could not decode $input');
  image = img.bakeOrientation(image);
  final int sourceWidth = image.width, sourceHeight = image.height;
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height ? img.copyResize(image, width: maxSide) : img.copyResize(image, height: maxSide);
  }
  File(output).writeAsBytesSync(img.encodeJpg(image, quality: 92));
  return AnalysisImage(
    path: output,
    width: image.width,
    height: image.height,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
  );
}
