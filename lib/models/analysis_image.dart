import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class AnalysisImage {
  final String path;
  final int width;
  final int height;
  final img.Image decodedImage;
  
  // Lazily initialized representations
  InputImage? _inputImage;

  AnalysisImage({
    required this.path,
    required this.width,
    required this.height,
    required this.decodedImage,
  });

  /// Factory method to process an image path within an isolate
  static Future<AnalysisImage> create(String imagePath, {int maxWidth = 1024, int maxHeight = 1024}) async {
    return await compute(_decodeAndResizeWorker, _DecodeParams(imagePath, maxWidth, maxHeight));
  }

  /// Get ML Kit InputImage representation (cached)
  InputImage get inputImage {
    if (_inputImage == null) {
      _inputImage = InputImage.fromFilePath(path);
    }
    return _inputImage!;
  }
}

class _DecodeParams {
  final String path;
  final int maxWidth;
  final int maxHeight;

  _DecodeParams(this.path, this.maxWidth, this.maxHeight);
}

Future<AnalysisImage> _decodeAndResizeWorker(_DecodeParams params) async {
  final bytes = File(params.path).readAsBytesSync();
  img.Image? decoded = img.decodeImage(bytes);
  
  if (decoded == null) {
    throw Exception("Failed to decode image at ${params.path}");
  }

  // Resize if it exceeds max dimensions
  if (decoded.width > params.maxWidth || decoded.height > params.maxHeight) {
    decoded = img.copyResize(
      decoded, 
      width: decoded.width > decoded.height ? params.maxWidth : null,
      height: decoded.height > decoded.width ? params.maxHeight : null,
    );
  }

  return AnalysisImage(
    path: params.path,
    width: decoded.width,
    height: decoded.height,
    decodedImage: decoded,
  );
}
