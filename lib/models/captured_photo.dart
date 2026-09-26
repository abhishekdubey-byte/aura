import 'package:flutter/foundation.dart';

/// A photo taken in Normal mode during this session.
class CapturedPhoto {
  CapturedPhoto({
    required this.originalPath,
    required this.mirrored,
    this.aspect,
  });

  /// File written by the camera, available immediately after capture.
  final String originalPath;

  /// Whether [originalPath] must be mirrored to look like the preview
  /// (front camera). The saved file already has this applied.
  final bool mirrored;

  /// Framing (width / height) the saved file is cropped to, or null for the
  /// full frame. Used to show the original with the same crop until saved.
  final double? aspect;

  /// Final processed file, set once the photo has been saved to the gallery.
  final ValueNotifier<String?> savedPath = ValueNotifier(null);
  final ValueNotifier<String?> saveError = ValueNotifier(null);
  VoidCallback? retrySave;
}
