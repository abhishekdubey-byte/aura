import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'math_utils.dart';

class GeometryEngine {
  // Face Geometry
  static MeasuredValue calculateFaceSymmetry(Face face) {
    double yaw = (face.headEulerAngleY ?? 0.0).abs();
    double roll = (face.headEulerAngleZ ?? 0.0).abs();
    
    double error = (yaw / 45.0) + (roll / 45.0);
    double normalized = MathUtils.clamp(1.0 - (error / 2.0), 0.0, 1.0);
    
    return MeasuredValue(raw: error, normalized: normalized, confidence: 1.0);
  }
  
  static MeasuredValue calculateFaceRatio(Face face) {
    double width = max(face.boundingBox.width, MathUtils.epsilon);
    double ratio = face.boundingBox.height / width;
    
    // Ideal ratio roughly 1.3 to 1.6
    double normalized = MathUtils.normalize(ratio, 1.0, 2.0);
    return MeasuredValue(raw: ratio, normalized: normalized, confidence: 1.0);
  }

  static MeasuredValue? calculateEyeSpacingRatio(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    
    if (leftEye != null && rightEye != null) {
      double distance = MathUtils.euclideanDistance(
        Point<double>(leftEye.position.x.toDouble(), leftEye.position.y.toDouble()),
        Point<double>(rightEye.position.x.toDouble(), rightEye.position.y.toDouble())
      );
      double width = max(face.boundingBox.width, MathUtils.epsilon);
      double ratio = distance / width;
      double normalized = MathUtils.normalize(ratio, 0.2, 0.6);
      return MeasuredValue(raw: ratio, normalized: normalized, confidence: 1.0);
    }
    return null;
  }

  // Body Geometry
  static MeasuredValue calculatePostureScore(Pose pose) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    
    if (ls == null || rs == null) {
      return MeasuredValue(raw: 0.0, normalized: 0.5, confidence: 0.0);
    }
    
    double dx = rs.x - ls.x;
    double dy = rs.y - ls.y;
    double dist = sqrt(dx * dx + dy * dy);
    
    if (dist < MathUtils.epsilon) {
      return MeasuredValue(raw: 0.0, normalized: 0.5, confidence: 0.0);
    }
    
    double tiltError = dy.abs() / dist;
    double normalized = MathUtils.clamp(1.0 - tiltError, 0.0, 1.0);
    
    return MeasuredValue(raw: tiltError, normalized: normalized, confidence: ls.likelihood * rs.likelihood);
  }
}

class MathLogger {
  final Map<String, dynamic> _logs = {};

  void logMeasuredValue(String metricName, MeasuredValue value) {
    _logs[metricName] = {
      'raw': value.raw,
      'normalized': value.normalized,
      'confidence': value.confidence,
    };
  }

  void log(String key, dynamic value) {
    _logs[key] = value;
  }

  Map<String, dynamic> export() {
    return Map.unmodifiable(_logs);
  }
}
