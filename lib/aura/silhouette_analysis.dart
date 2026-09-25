import 'dart:typed_data';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Subject silhouette from the ML Kit segmentation mask (one confidence per
/// analysis-image pixel), combined with the pose skeleton for body widths.
class SilhouetteMetrics {
  SilhouetteMetrics({
    required this.coverage,
    required this.crispness,
    this.shoulderWidth,
    this.waistWidth,
    this.hipWidth,
  });

  /// Share of the image that is the subject.
  final double coverage;
  /// Share of mask pixels the model is sure about (clean subject separation).
  final double crispness;
  /// Body widths in pixels, measured on the silhouette.
  final double? shoulderWidth, waistWidth, hipWidth;

  double? get shoulderToWaist => shoulderWidth != null && waistWidth != null && waistWidth! > 0 ? shoulderWidth! / waistWidth! : null;
  double? get hipToWaist => hipWidth != null && waistWidth != null && waistWidth! > 0 ? hipWidth! / waistWidth! : null;
  double? get hipToShoulder => hipWidth != null && shoulderWidth != null && shoulderWidth! > 0 ? hipWidth! / shoulderWidth! : null;

  static SilhouetteMetrics fromMask(List<double> maskValues, int width, int height, Pose? pose) {
    final mask = maskValues is Float32List ? maskValues : Float32List.fromList(maskValues);
    final int n = width * height;
    if (mask.length < n) {
      return SilhouetteMetrics(coverage: 0, crispness: 0);
    }
    int fg = 0, sure = 0;
    for (int i = 0; i < n; i += 2) {
      final double v = mask[i];
      if (v > 0.5) fg++;
      if (v < 0.1 || v > 0.9) sure++;
    }
    final double coverage = fg / (n / 2);
    final double crispness = sure / (n / 2);

    double? shoulderW, waistW, hipW;
    PoseLandmark? get(PoseLandmarkType t) {
      final l = pose?.landmarks[t];
      return l != null && l.likelihood >= 0.6 ? l : null;
    }

    final ls = get(PoseLandmarkType.leftShoulder), rs = get(PoseLandmarkType.rightShoulder);
    final lh = get(PoseLandmarkType.leftHip), rh = get(PoseLandmarkType.rightHip);
    if (ls != null && rs != null && lh != null && rh != null) {
      final int midX = ((ls.x + rs.x + lh.x + rh.x) / 4).round().clamp(0, width - 1);
      final int shoulderY = ((ls.y + rs.y) / 2).round();
      final int hipY = ((lh.y + rh.y) / 2).round();
      final int radius = (width * 0.45).round();
      final int step = (height / 200).ceil().clamp(1, 8);

      double widthAt(int y) => _rowWidth(mask, width, height, y, midX, radius);

      shoulderW = widthAt(shoulderY);
      // Waist: narrowest row in the lower 2/3 of the torso
      double narrowest = double.infinity;
      for (int y = shoulderY + ((hipY - shoulderY) / 3).round(); y <= hipY; y += step) {
        final double w = widthAt(y);
        if (w > 0 && w < narrowest) narrowest = w;
      }
      if (narrowest.isFinite) waistW = narrowest;
      // Hips: widest row around the hip joints
      double widest = 0;
      final int band = ((hipY - shoulderY).abs() * 0.25).round();
      for (int y = hipY - band; y <= hipY + band; y += step) {
        final double w = widthAt(y);
        if (w > widest) widest = w;
      }
      if (widest > 0) hipW = widest;
    }

    return SilhouetteMetrics(
      coverage: coverage,
      crispness: crispness,
      shoulderWidth: shoulderW != null && shoulderW > 0 ? shoulderW : null,
      waistWidth: waistW,
      hipWidth: hipW,
    );
  }

  /// Width of the continuous subject run through (startX, y).
  static double _rowWidth(Float32List mask, int width, int height, int y, int startX, int radius) {
    if (y < 0 || y >= height) return 0;
    final int row = y * width;
    if (mask[row + startX] <= 0.5) return 0;
    int left = startX, right = startX;
    while (left > 0 && startX - left < radius && mask[row + left - 1] > 0.5) {
      left--;
    }
    while (right < width - 1 && right - startX < radius && mask[row + right + 1] > 0.5) {
      right++;
    }
    return (right - left + 1).toDouble();
  }
}
