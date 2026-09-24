import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceGeometry {
  static double calculateFaceRatio(Face face) {
    return face.boundingBox.height / math.max(face.boundingBox.width, 1.0);
  }

  static double? calculateEyeSpacingRatio(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    if (leftEye != null && rightEye != null) {
      double eyeSpacing = leftEye.position.distanceTo(rightEye.position);
      return eyeSpacing / math.max(face.boundingBox.width, 1.0);
    }
    return null;
  }

  static double calculateSymmetry(Face face) {
    // Basic symmetry via bounding box and euler angles
    double yaw = (face.headEulerAngleY ?? 0.0).abs();
    double roll = (face.headEulerAngleZ ?? 0.0).abs();
    
    // Ideal is 0 yaw, 0 roll
    double error = (yaw / 45.0) + (roll / 45.0);
    return math.max(0.0, 1.0 - (error / 2));
  }

  static math.Rectangle<int>? calculateEyeRect(Face face, bool left) {
    final eye = left ? face.landmarks[FaceLandmarkType.leftEye] : face.landmarks[FaceLandmarkType.rightEye];
    if (eye == null) return null;
    
    // Crop a square around the eye for the Iris Tracker TFLite model (64x64)
    int padding = (face.boundingBox.width * 0.1).toInt();
    int x = math.max(0, eye.position.x - padding);
    int y = math.max(0, eye.position.y - padding);
    int width = padding * 2;
    int height = padding * 2;
    
    return math.Rectangle<int>(x, y, width, height);
  }
}

extension PointDistance on math.Point<int> {
  double distanceTo(math.Point<int> other) {
    return math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));
  }
}
