import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'math_utils.dart';
import 'dart:math';

class FaceFeatureEngine {
  static MeasuredValue calculateGoldenRatio(Face face) {
    // True golden ratio phi ~ 1.618
    double width = max(face.boundingBox.width, MathUtils.epsilon);
    double ratio = face.boundingBox.height / width;
    
    double error = (ratio - 1.618).abs();
    double normalized = MathUtils.clamp(1.0 - error, 0.0, 1.0);
    
    return MeasuredValue(raw: ratio, normalized: normalized, confidence: 1.0);
  }

  static MeasuredValue calculateJawlineAngularity(Face face) {
    final jawContour = face.contours[FaceContourType.face];
    if (jawContour != null && jawContour.points.length >= 10) {
      final leftCheek = jawContour.points[0];
      final rightCheek = jawContour.points[jawContour.points.length - 1];
      double faceWidth = (rightCheek.x - leftCheek.x).abs().toDouble();
      
      final leftJaw = jawContour.points[8];
      final rightJaw = jawContour.points[jawContour.points.length - 9];
      double jawWidth = (rightJaw.x - leftJaw.x).abs().toDouble();
      
      if (faceWidth > MathUtils.epsilon) {
        double angularity = jawWidth / faceWidth;
        double normalized = MathUtils.normalize(angularity, 0.6, 1.0);
        return MeasuredValue(raw: angularity, normalized: normalized, confidence: 1.0);
      }
    }
    
    return MeasuredValue(raw: 0.0, normalized: 0.5, confidence: 0.0);
  }
}
