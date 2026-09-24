import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class BodyGeometry {
  // Helper for 3D distance
  static double _distance3D(PoseLandmark p1, PoseLandmark p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2) + pow(p1.z - p2.z, 2));
  }

  static double? calculateShoulderWidth(Pose pose) {
    final left = pose.landmarks[PoseLandmarkType.leftShoulder];
    final right = pose.landmarks[PoseLandmarkType.rightShoulder];
    if (left != null && right != null && left.likelihood > 0.6 && right.likelihood > 0.6) {
      return _distance3D(left, right);
    }
    return null;
  }

  static double? calculateHipWidth(Pose pose) {
    final left = pose.landmarks[PoseLandmarkType.leftHip];
    final right = pose.landmarks[PoseLandmarkType.rightHip];
    if (left != null && right != null && left.likelihood > 0.6 && right.likelihood > 0.6) {
      return _distance3D(left, right);
    }
    return null;
  }

  static double? calculateTorsoLength(Pose pose) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];
    
    if (ls != null && lh != null && rs != null && rh != null) {
       double leftLength = _distance3D(ls, lh);
       double rightLength = _distance3D(rs, rh);
       return (leftLength + rightLength) / 2.0;
    }
    return null;
  }

  static double calculatePostureScore(Pose pose) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];
    
    double score = 0.5; // Base average posture
    
    if (ls != null && rs != null && lh != null && rh != null) {
      // 1. Z-axis leaning (is the user slouching forward or leaning back confidently?)
      double avgShoulderZ = (ls.z + rs.z) / 2.0;
      double avgHipZ = (lh.z + rh.z) / 2.0;
      
      // If shoulders are significantly closer to the camera than hips, it's a slouch (bad posture)
      // Note: In ML Kit, negative Z means closer to camera.
      double zDiff = avgShoulderZ - avgHipZ;
      if (zDiff < -50) {
        score -= 0.2; // Slouch penalty
      } else if (zDiff > 20 && zDiff < 100) {
        score += 0.2; // Confident stance
      }

      // 2. Dynamic shoulder tilt
      double shoulderTilt = (ls.y - rs.y).abs();
      if (shoulderTilt > 20) {
        score += 0.1; // Bonus for dynamic pose
      }
    }
    return min(1.0, max(0.0, score));
  }
}
