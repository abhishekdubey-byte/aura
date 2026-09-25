import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Posture and body findings from one ML Kit pose. Only landmarks the model
/// is reasonably sure about are used; ML Kit returns a (low-likelihood)
/// skeleton even for photos without people.
class PoseMetrics {
  PoseMetrics({
    required this.visibleLandmarks,
    required this.coreConfidence,
    required this.isConfidentPerson,
    required this.hasTorso,
    this.shoulderTiltDeg,
    this.spineTiltDeg,
    this.headOffset,
    required this.energy,
    this.bodyHeightFraction,
  });

  static const double minLikelihood = 0.6;

  /// Landmarks (of 33) seen with at least [minLikelihood].
  final int visibleLandmarks;
  /// Mean likelihood of nose, eyes, shoulders and hips.
  final double coreConfidence;
  /// Enough confident core landmarks to count as a real person.
  final bool isConfidentPerson;
  /// Both shoulders and both hips confidently visible.
  final bool hasTorso;
  /// Shoulder line vs horizontal (degrees).
  final double? shoulderTiltDeg;
  /// Shoulder-to-hip line vs vertical (degrees).
  final double? spineTiltDeg;
  /// Nose offset from the shoulder centre, in shoulder widths.
  final double? headOffset;
  /// 0 (static) .. 1 (very dynamic): raised arms, bent limbs, wide stance, lean.
  final double energy;
  /// Visible body height / image height.
  final double? bodyHeightFraction;

  double get visibility => visibleLandmarks / 33.0;

  static PoseMetrics fromPose(Pose pose, int imageWidth, int imageHeight) {
    PoseLandmark? get(PoseLandmarkType t) {
      final l = pose.landmarks[t];
      return l != null && l.likelihood >= minLikelihood ? l : null;
    }

    final visible = pose.landmarks.values.where((l) => l.likelihood >= minLikelihood).toList();
    const core = [
      PoseLandmarkType.nose,
      PoseLandmarkType.leftEye,
      PoseLandmarkType.rightEye,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ];
    final coreLikelihoods = core.map((t) => pose.landmarks[t]?.likelihood ?? 0.0).toList();
    final double coreConfidence = coreLikelihoods.reduce((a, b) => a + b) / core.length;
    final int confidentCore = coreLikelihoods.where((l) => l >= 0.75).length;

    final ls = get(PoseLandmarkType.leftShoulder), rs = get(PoseLandmarkType.rightShoulder);
    final lh = get(PoseLandmarkType.leftHip), rh = get(PoseLandmarkType.rightHip);
    final nose = get(PoseLandmarkType.nose);
    final bool shoulders = ls != null && rs != null;
    final bool hasTorso = shoulders && lh != null && rh != null;
    final bool isConfidentPerson = shoulders && confidentCore >= 4;

    double? shoulderTilt, spineTilt, headOffset;
    double energy = 0;
    if (shoulders) {
      shoulderTilt = (atan2(rs.y - ls.y, rs.x - ls.x) * 180 / pi).abs();
      if (shoulderTilt > 90) shoulderTilt = 180 - shoulderTilt;
      final double shoulderWidth = sqrt(pow(rs.x - ls.x, 2) + pow(rs.y - ls.y, 2));
      final double midX = (ls.x + rs.x) / 2, midY = (ls.y + rs.y) / 2;
      if (nose != null && shoulderWidth > 1) headOffset = (nose.x - midX).abs() / shoulderWidth;
      if (hasTorso) {
        final double hipX = (lh.x + rh.x) / 2, hipY = (lh.y + rh.y) / 2;
        spineTilt = (atan2(midX - hipX, hipY - midY) * 180 / pi).abs();
        if (spineTilt >= 5 && spineTilt <= 25) energy += 0.1; // deliberate lean
      }

      // Raised arms and bent elbows
      for (final side in [
        (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
        (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
      ]) {
        final s = get(side.$1), e = get(side.$2), w = get(side.$3);
        if (s != null && w != null && w.y < s.y) energy += 0.3;
        if (s != null && e != null && w != null) {
          final double bend = 180 - _angle(s, e, w);
          if (bend > 35) energy += 0.1;
        }
      }
      // Stance and knee bend
      final la = get(PoseLandmarkType.leftAnkle), ra = get(PoseLandmarkType.rightAnkle);
      if (hasTorso && la != null && ra != null) {
        final double hipWidth = max((lh.x - rh.x).abs(), 1.0);
        if ((la.x - ra.x).abs() / hipWidth > 1.6) energy += 0.15;
      }
      for (final side in [
        (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
        (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
      ]) {
        final h = get(side.$1), k = get(side.$2), a = get(side.$3);
        if (h != null && k != null && a != null && 180 - _angle(h, k, a) > 25) energy += 0.1;
      }
    }

    double? bodyHeight;
    if (visible.length >= 4) {
      final ys = visible.map((l) => l.y);
      bodyHeight = ((ys.reduce(max) - ys.reduce(min)) / imageHeight).clamp(0.0, 1.0);
    }

    return PoseMetrics(
      visibleLandmarks: visible.length,
      coreConfidence: coreConfidence,
      isConfidentPerson: isConfidentPerson,
      hasTorso: hasTorso,
      shoulderTiltDeg: shoulderTilt,
      spineTiltDeg: spineTilt,
      headOffset: headOffset,
      energy: energy.clamp(0.0, 1.0),
      bodyHeightFraction: bodyHeight,
    );
  }

  /// Angle at [b] between [a] and [c], in degrees.
  static double _angle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final double v1x = a.x - b.x, v1y = a.y - b.y, v2x = c.x - b.x, v2y = c.y - b.y;
    final double d = sqrt(v1x * v1x + v1y * v1y) * sqrt(v2x * v2x + v2y * v2y);
    if (d == 0) return 180;
    return acos(((v1x * v2x + v1y * v2y) / d).clamp(-1.0, 1.0)) * 180 / pi;
  }
}
