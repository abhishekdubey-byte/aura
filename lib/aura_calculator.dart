import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:aura/geometry/silhouette_math.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'scorers/aura_engine.dart';
import 'utils/gender_predictor.dart';
import 'utils/advanced_inference_service.dart';
import 'models/analysis_image.dart';
import 'models/detailed_aura_score.dart';

class ImageDimensions {
  final int width;
  final int height;
  ImageDimensions(this.width, this.height);
}
class SnapshotState {
  final DetailedAuraScore details;
  final String? hypeMessage;
  final Point<double>? targetPoint;
  final DateTime timestamp;
  final Set<String> objectLabels;
  final double faceRatio;
  final double bodyRatio;
  final double genderProbability;
  
  // Expression tracking for intentionality check
  final double smileProb;
  final double yaw;
  final double tilt;

  SnapshotState({
    required this.details,
    this.hypeMessage,
    this.targetPoint,
    required this.timestamp,
    required this.objectLabels,
    required this.faceRatio,
    required this.bodyRatio,
    required this.genderProbability,
    required this.smileProb,
    required this.yaw,
    required this.tilt,
  });
}

class AuraResult {
  final int score;
  final bool hasHuman;
  final Point<double>? targetPoint;
  final String? hypeMessage;
  final DetailedAuraScore? details;

  AuraResult({
    required this.score,
    required this.hasHuman,
    this.targetPoint,
    this.hypeMessage,
    this.details,
  });
}

class AuraCalculatorService {
  final FaceDetector _faceDetector = FaceDetector(options: FaceDetectorOptions(enableLandmarks: true, enableClassification: true, enableTracking: true));
  final SubjectSegmenter _segmenter = SubjectSegmenter(options: SubjectSegmenterOptions(enableForegroundBitmap: false, enableForegroundConfidenceMask: true, enableMultipleSubjects: SubjectResultOptions(enableConfidenceMask: false, enableSubjectBitmap: false)));
  final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.single));
  final ImageLabeler _imageLabeler = ImageLabeler(options: ImageLabelerOptions());
  
  final AdvancedInferenceService _advancedInference = AdvancedInferenceService();
  final AuraEngine _auraEngine = AuraEngine();
  
  static SnapshotState? _lastSnapshot;

  void dispose() {
    _faceDetector.close();
    _segmenter.close();
    _poseDetector.close();
    _imageLabeler.close();
  }

  Future<AuraResult> analyzeImage(String imagePath) async {
    return calculateAura(imagePath);
  }

  Future<AuraResult> calculateAura(String imagePath) async {
    double genderProbability = 0.5;
    bool hasHuman = true;
    Point<double>? targetPoint;
    DetailedAuraScore? detailedScore;
    
    Set<String> currentObjects = {};
    double currentFaceRatio = 0.0;
    double currentBodyRatio = 0.0;
    
    double currentSmile = 0.0;
    double currentYaw = 0.0;
    double currentTilt = 0.0;

    try {
      final analysisImage = await AnalysisImage.create(imagePath);
      final inputImage = analysisImage.inputImage;

      // Run tasks sequentially to prevent OOM and native crashes during batch processing
      final faces = await _faceDetector.processImage(inputImage);
      
      // Only run segmenter if we found a human to save massive amounts of memory/time
      SubjectSegmentationResult? segmentResult;
      if (faces.isNotEmpty) {
          try {
             segmentResult = await _segmenter.processImage(inputImage);
          } catch (e) {
             debugPrint("Segmenter error: $e");
          }
      }
      
      final poses = await _poseDetector.processImage(inputImage);
      
      if (segmentResult == null && poses.isNotEmpty) {
          try {
             segmentResult = await _segmenter.processImage(inputImage);
          } catch (e) {
             debugPrint("Segmenter error: $e");
          }
      }
      
      final labels = await _imageLabeler.processImage(inputImage);
      
      // We pass the pre-decoded AnalysisImage to advanced inference to avoid redundant decoding
      final advancedFeatures = await _advancedInference.analyze(analysisImage);

      
      for (var label in labels) {
         final l = label.label.toLowerCase();
         if (['glasses', 'sunglasses', 'hat', 'cap', 'jacket', 'coat', 'shirt', 'dress', 'tie', 'scarf', 'necklace', 'phone', 'mobile phone', 'watch', 'bag'].contains(l)) {
            currentObjects.add(label.label);
         }
      }

      if (faces.isNotEmpty) {
         final face = faces.first;
         currentFaceRatio = face.boundingBox.width / max(face.boundingBox.height, 1.0);
         currentSmile = face.smilingProbability ?? 0.0;
         currentYaw = face.headEulerAngleY ?? 0.0;
         currentTilt = face.headEulerAngleZ ?? 0.0;
      }
      
      if (poses.isNotEmpty && faces.isNotEmpty) {
         final p = poses.first;
         final ls = p.landmarks[PoseLandmarkType.leftShoulder];
         final rs = p.landmarks[PoseLandmarkType.rightShoulder];
         if (ls != null && rs != null) {
            double shoulderWidth = (ls.x - rs.x).abs();
            currentBodyRatio = shoulderWidth / max(faces.first.boundingBox.width, 1.0);
         }
      }

      if (faces.isNotEmpty) {
        genderProbability = GenderPredictor.calculateGenderProbability(faces.first, poses.isNotEmpty ? poses.first : null);
      }

      bool is2DArt = false;
      if (faces.isEmpty && poses.isEmpty) {
        final humanLabels = ['person', 'human', 'woman', 'man', 'girl', 'boy', 'face', 'hair', 'leg', 'arm', 'chest', 'torso', 'skin', 'eye', 'lip', 'mouth', 'smile', 'anime', 'female', 'male', 'curve', 'hand', 'body'];
        bool foundHumanLabel = false;
        for (var label in labels) {
            final l = label.label.toLowerCase();
            if (humanLabels.any((hl) => l.contains(hl))) {
                foundHumanLabel = true;
                break;
            }
        }
        if (!foundHumanLabel) {
            hasHuman = false;
        } else {
            hasHuman = true;
            is2DArt = true;
        }
      } else {
        hasHuman = true;
      }

      if (hasHuman) {
          // Snapshot Caching Logic
          if (AuraCalculatorService._lastSnapshot != null) {
             final timeDiff = DateTime.now().difference(AuraCalculatorService._lastSnapshot!.timestamp).inSeconds;
             if (timeDiff < 180) { // 3 minutes window
                 
                 // 1. PIN GENDER ARCHETYPE: Reuse stable gender probability to avoid flipping scorers due to jitter
                 genderProbability = AuraCalculatorService._lastSnapshot!.genderProbability;
                 
                 // 2. CACHE BUSTING LOGIC: Only bust if intentional expression/pose changes
                 bool objectsChanged = currentObjects.difference(AuraCalculatorService._lastSnapshot!.objectLabels).isNotEmpty || 
                                       AuraCalculatorService._lastSnapshot!.objectLabels.difference(currentObjects).isNotEmpty;
                 
                 bool bodyRatioChanged = false;
                 if (AuraCalculatorService._lastSnapshot!.bodyRatio > 0 && currentBodyRatio > 0) {
                     double diff = (currentBodyRatio - AuraCalculatorService._lastSnapshot!.bodyRatio).abs() / AuraCalculatorService._lastSnapshot!.bodyRatio;
                     if (diff > 0.15) bodyRatioChanged = true; 
                 } else if (AuraCalculatorService._lastSnapshot!.bodyRatio > 0 || currentBodyRatio > 0) {
                     bodyRatioChanged = true; 
                 }
                 
                 bool faceRatioChanged = false;
                 if (AuraCalculatorService._lastSnapshot!.faceRatio > 0 && currentFaceRatio > 0) {
                     double diff = (currentFaceRatio - AuraCalculatorService._lastSnapshot!.faceRatio).abs() / AuraCalculatorService._lastSnapshot!.faceRatio;
                     if (diff > 0.15) faceRatioChanged = true; 
                 }
                 
                 bool expressionChanged = false;
                 if ((currentSmile - AuraCalculatorService._lastSnapshot!.smileProb).abs() > 0.15) {
                     expressionChanged = true;
                 }
                 if ((currentYaw - AuraCalculatorService._lastSnapshot!.yaw).abs() > 10.0) {
                     expressionChanged = true;
                 }
                 if ((currentTilt - AuraCalculatorService._lastSnapshot!.tilt).abs() > 10.0) {
                     expressionChanged = true;
                 }
                 
                 // If nothing significant changed, lock the score to prevent jitter!
                 if (!objectsChanged && !bodyRatioChanged && !faceRatioChanged && !expressionChanged) {
                     return AuraResult(
                       score: AuraCalculatorService._lastSnapshot!.details.overallPoints,
                       hasHuman: true,
                       targetPoint: AuraCalculatorService._lastSnapshot!.targetPoint,
                       hypeMessage: AuraCalculatorService._lastSnapshot!.hypeMessage,
                       details: AuraCalculatorService._lastSnapshot!.details,
                     );
                 }
             }
          }
        bool isLikelyFemale = genderProbability >= 0.5;
        
        TrueProportions? proportions;
        if (poses.isNotEmpty) {
           if (segmentResult != null && segmentResult.foregroundConfidenceMask != null) {
              final mask = segmentResult.foregroundConfidenceMask!;
              int w = analysisImage.width;
              int h = analysisImage.height;
              
              if (w > 0 && h > 0) {
                 // Convert List<double> to Float32List
                 final floatMask = Float32List.fromList(mask);
                 try {
                   if (isLikelyFemale) {
                     proportions = SilhouetteMath.calculateTrueFemaleShape(poses.first, floatMask, w, h);
                   } else {
                     proportions = SilhouetteMath.calculateTrueMaleShape(poses.first, floatMask, w, h);
                   }
                 } catch (e, stack) {
                   debugPrint('Error in SilhouetteMath: $e\n$stack');
                 }
              }
           }
        }
        
        detailedScore = _auraEngine.calculateScore(
          face: faces.isNotEmpty ? faces.first : null, 
          pose: poses.isNotEmpty ? poses.first : null, 
          advanced: advancedFeatures,
          proportions: proportions,
          isLikelyFemale: isLikelyFemale,
          labels: labels.map((l) => l.label).toList(),
        );
        
        // Calculate target point for UI
        if (poses.isNotEmpty) {
          final pose = poses.first;
          final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
          final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
          final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
          final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
          
          if (leftShoulder != null && rightShoulder != null && leftHip != null && rightHip != null) {
            if (isLikelyFemale) {
               targetPoint = Point<double>(
                 (leftHip.x + rightHip.x) / 2, 
                 (leftHip.y + rightHip.y) / 2
               );
            } else {
               double midX = (leftShoulder.x + rightShoulder.x) / 2;
               double midY = (leftShoulder.y + rightShoulder.y) / 2;
               double shoulderWidthRef = max((leftShoulder.x - rightShoulder.x).abs(), 1.0);
               targetPoint = Point<double>(midX, midY + (0.3 * shoulderWidthRef));
            }
          }
        }
        
        if (targetPoint == null && faces.isNotEmpty) {
           final face = faces.first;
           targetPoint = Point<double>(
              face.boundingBox.center.dx,
              face.boundingBox.top - (0.3 * max(face.boundingBox.height, 1.0))
           );
        }
      }

    } catch (e, stack) {
      debugPrint('Error in Aura Calculation: $e\\n$stack');
    }

    String? finalHype;
    if (hasHuman && detailedScore != null) {
      if (detailedScore.allSlangs.isNotEmpty) {
        finalHype = detailedScore.allSlangs[Random().nextInt(detailedScore.allSlangs.length)];
      } else {
        finalHype = "Looking good! ✨";
      }
    } else if (hasHuman) {
      finalHype = "Oof, tough crowd 😬";
    }

    // Use the fallback score only if completely failed to produce details
    int fallbackScore = detailedScore?.isBodyOnly == true ? 500 : -9999;
    
    final result = AuraResult(
      score: detailedScore?.overallPoints ?? fallbackScore,
      hasHuman: hasHuman,
      targetPoint: targetPoint,
      hypeMessage: finalHype,
      details: detailedScore,
    );
    
    if (hasHuman && detailedScore != null) {
      AuraCalculatorService._lastSnapshot = SnapshotState(
        details: detailedScore,
        hypeMessage: result.hypeMessage,
        targetPoint: result.targetPoint,
        timestamp: DateTime.now(),
        objectLabels: currentObjects,
        faceRatio: currentFaceRatio,
        bodyRatio: currentBodyRatio,
        genderProbability: genderProbability,
        smileProb: currentSmile,
        yaw: currentYaw,
        tilt: currentTilt,
      );
    }

    return result;
  }
}
