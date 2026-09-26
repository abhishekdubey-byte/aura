import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Read the existing texture; never add a competing camera stream/use case.
/// No snapshot is saved to disk or sent to the upload service.
Future<Uint8List?> sampleCameraPreview(GlobalKey boundaryKey) async {
  final boundary = boundaryKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary ||
      boundary.debugNeedsPaint ||
      boundary.size.isEmpty) {
    return null;
  }
  final image = await boundary.toImage(
    pixelRatio: (640 / boundary.size.longestSide).clamp(.1, 1.0),
  );
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
