import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class GenderPredictor {
  /// Returns a probability between 0.0 (highly likely Male) and 1.0 (highly likely Female)
  static double calculateGenderProbability(Face face, Pose? pose) {
    double probability = 0.5;

    // 1. Skeletal Ratios
    if (pose != null) {
      final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
      final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
      final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

      if (leftShoulder != null && rightShoulder != null && leftHip != null && rightHip != null) {
        // Enforce a minimum likelihood so we don't use noisy/hallucinated landmarks for sideways poses
        if (leftShoulder.likelihood > 0.6 && rightShoulder.likelihood > 0.6 && leftHip.likelihood > 0.6 && rightHip.likelihood > 0.6) {
          double shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
          double hipWidth = (leftHip.x - rightHip.x).abs();
          
          if (hipWidth > 0) {
            double ratio = shoulderWidth / hipWidth;
            // V-taper (Male) usually has ratio > 1.3
            // Hourglass/Pear (Female) usually has ratio < 1.15
            if (ratio > 1.35) { 
              probability -= 0.25; // Lean male
            } else if (ratio < 1.15) {
              probability += 0.25; // Lean female
            }
          }
        }
      }
    }

    // 2. Facial Contours (Jawline, Lips, Face shape)
    // Jaw/Face Shape Approximation
    double faceRatio = face.boundingBox.width / face.boundingBox.height;
    if (faceRatio > 0.82) {
      probability -= 0.15; // Wider, more angular face -> lean male
    } else if (faceRatio < 0.75) {
      probability += 0.15; // Tapered, oval face -> lean female
    }

    final upperLip = face.contours[FaceContourType.upperLipTop];
    final lowerLip = face.contours[FaceContourType.lowerLipBottom];
    
    if (upperLip != null && lowerLip != null && upperLip.points.isNotEmpty && lowerLip.points.isNotEmpty) {
      // Estimate lip thickness
      double lipHeight = (upperLip.points.first.y - lowerLip.points.first.y).abs().toDouble();
      double faceHeight = face.boundingBox.height;
      
      if (faceHeight > 0) {
        double lipRatio = lipHeight / faceHeight;
        // Typical lip ratios. Fuller lips lean female.
        if (lipRatio > 0.12) {
          probability += 0.1; 
        } else if (lipRatio < 0.08) {
          probability -= 0.1;
        }
      }
    }
    
    // 3. Hair Volume Stabilizer
    // A sideways body breaks shoulder/hip ratios, but hair volume from the face bounding box is scale & rotation invariant.
    final noseLandmark = face.landmarks[FaceLandmarkType.noseBase];
    if (noseLandmark != null) {
       double noseY = noseLandmark.position.y.toDouble();
       double topY = face.boundingBox.top;
       double bottomY = face.boundingBox.bottom;
       
       double topDistance = (noseY - topY).abs();
       double bottomDistance = (bottomY - noseY).abs();
       
       if (bottomDistance > 0) {
         double hairRatio = topDistance / bottomDistance;
         if (hairRatio > 1.3) {
            probability += 0.35; // Strongly lean female due to hair volume
         } else if (hairRatio > 1.1) {
            probability += 0.15; // Moderately lean female
         }
       }
    }

    return probability.clamp(0.0, 1.0);
  }
}
