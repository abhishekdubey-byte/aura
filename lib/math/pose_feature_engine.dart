import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'math_utils.dart';
import 'dart:math';

class PoseFeatureEngine {
  static MeasuredValue calculateShoulderToHipRatio(Pose pose) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];

    if (ls == null || rs == null || lh == null || rh == null) {
      return MeasuredValue(raw: 0.0, normalized: 0.0, confidence: 0.0);
    }

    double shoulderWidth = (ls.x - rs.x).abs();
    double hipWidth = (lh.x - rh.x).abs();

    if (shoulderWidth < MathUtils.epsilon || hipWidth < MathUtils.epsilon) {
      return MeasuredValue(raw: 0.0, normalized: 0.0, confidence: 0.0);
    }

    double ratio = shoulderWidth / hipWidth;
    // Normalized based on expected ranges
    double normalized = MathUtils.normalize(ratio, 0.8, 2.0);
    
    return MeasuredValue(raw: ratio, normalized: normalized, confidence: 1.0);
  }

  static MeasuredValue calculateSpineAngle(Pose pose) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];

    if (ls == null || rs == null || lh == null || rh == null) {
      return MeasuredValue(raw: 0.0, normalized: 0.0, confidence: 0.0);
    }

    Point<double> shoulderMid = Point((ls.x + rs.x) / 2, (ls.y + rs.y) / 2);
    Point<double> hipMid = Point((lh.x + rh.x) / 2, (lh.y + rh.y) / 2);

    double dx = shoulderMid.x - hipMid.x;
    double dy = shoulderMid.y - hipMid.y;
    
    double angle = atan2(dy, dx) * (180 / pi);
    // 90 degrees or -90 degrees is straight vertical
    double error = (angle.abs() - 90).abs();
    
    double normalized = MathUtils.clamp(1.0 - (error / 45.0), 0.0, 1.0);

    return MeasuredValue(raw: angle, normalized: normalized, confidence: 1.0);
  }
}
