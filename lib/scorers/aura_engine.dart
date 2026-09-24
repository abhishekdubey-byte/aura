import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/detailed_aura_score.dart';
import '../utils/advanced_inference_service.dart';
import '../math/geometry_engine.dart';
import '../math/face_feature_engine.dart';
import '../math/pose_feature_engine.dart';
import '../math/math_utils.dart';
import '../geometry/silhouette_math.dart';

class AuraEngine {
  final MathLogger logger = MathLogger();

  DetailedAuraScore calculateScore({
    required Face? face,
    required Pose? pose,
    required AdvancedInferenceResult? advanced,
    required TrueProportions? proportions,
    required bool isLikelyFemale,
    List<String> labels = const [],
  }) {
    List<String> allSlangs = [];
    bool isBodyOnly = face == null;
    
    // --- 1. FEATURE ACCUMULATION (Max ~10,000) ---
    int totalScore = 0;
    Map<String, double> engineMetrics = {};
    
    DimensionScore? faceScore;
    DimensionScore? eyesScore;
    DimensionScore? expressionScore;
    
    List<ScoreComponent> faceComponents = [];
    List<ScoreComponent> expressionComponents = [];
    
    if (face != null) {
      MeasuredValue fSym = GeometryEngine.calculateFaceSymmetry(face);
      double fScore = fSym.normalized;
      int fPoints = (fScore * 2000).round(); // up to 2000 points
      
      logger.logMeasuredValue("Face Symmetry", fSym);
      engineMetrics["Face Symmetry Raw"] = double.parse(fSym.raw.toStringAsFixed(3));
      engineMetrics["Face Symmetry"] = double.parse(fScore.toStringAsFixed(3));
      faceComponents.add(ScoreComponent('Facial Symmetry', '${(fScore * 100).toStringAsFixed(1)}%', fPoints, 'Calculated based on the structural balance of your facial landmarks. Higher is more symmetrical.'));
      
      // Face Angles & Presence
      double rotY = face.headEulerAngleY ?? 0;
      if (rotY.abs() < 5) {
        allSlangs.add(isLikelyFemale ? "Intense Stare 👁️" : "Sigma Stare 🗿");
        totalScore += 1500;
        faceComponents.add(ScoreComponent('Head Yaw Angle', '${rotY.toStringAsFixed(1)}°', 1500, 'Direct eye contact detected. Boosts aura presence significantly.'));
      } else if (rotY.abs() > 20) {
        allSlangs.add(isLikelyFemale ? "Mysterious 🌒" : "Looking Away 🌒");
        totalScore += 800;
        faceComponents.add(ScoreComponent('Head Yaw Angle', '${rotY.toStringAsFixed(1)}°', 800, 'Looking away adds an element of mystery to the portrait.'));
      }

      // Check smile
      if (face.smilingProbability != null) {
         engineMetrics["Smile Probability"] = double.parse(face.smilingProbability!.toStringAsFixed(3));
         if (face.smilingProbability! > 0.6) {
           int sPoints = 1500;
           expressionComponents.add(ScoreComponent('Smile Probability', '${(face.smilingProbability! * 100).toStringAsFixed(1)}%', sPoints, 'A glowing, confident smile was detected.'));
           expressionScore = DimensionScore(sPoints, face.smilingProbability!, ["Charming Smile ✨"], components: expressionComponents);
           allSlangs.add(isLikelyFemale ? "Glowing Energy ☀️" : "Golden Retriever Energy 🐶");
           totalScore += sPoints;
         } else if (face.smilingProbability! < 0.2) {
           int sPoints = 1000;
           expressionComponents.add(ScoreComponent('Smile Probability', '${(face.smilingProbability! * 100).toStringAsFixed(1)}%', sPoints, 'Stoic, relaxed facial expression detected.'));
           expressionScore = DimensionScore(sPoints, 1.0 - face.smilingProbability!, ["Stoic 🧊"], components: expressionComponents);
           allSlangs.add(isLikelyFemale ? "Ice Queen 🧊" : "Absolute Chad 🗿");
           totalScore += sPoints;
         }
      }
      
      // Jawline Angularity
      if (!isLikelyFemale) {
         MeasuredValue jaw = FaceFeatureEngine.calculateJawlineAngularity(face);
         logger.logMeasuredValue("Jawline Angularity", jaw);
         engineMetrics["Jawline Angularity"] = double.parse(jaw.raw.toStringAsFixed(3));
         if (jaw.normalized > 0.85) {
           fPoints += 2500;
           faceComponents.add(ScoreComponent('Jawline Angularity', jaw.raw.toStringAsFixed(2), 2500, 'Exceptionally sharp and defined jawline structure.'));
           allSlangs.add("Glass-cutting Jawline 🪒");
           allSlangs.add("Gigachad Energy 🗿");
         } else if (jaw.normalized > 0.80) {
           fPoints += 1200;
           faceComponents.add(ScoreComponent('Jawline Angularity', jaw.raw.toStringAsFixed(2), 1200, 'Strong and defined jawline structure.'));
           allSlangs.add("Defined Jawline 🗿");
         }
      }

      // Golden Ratio
      MeasuredValue golden = FaceFeatureEngine.calculateGoldenRatio(face);
      logger.logMeasuredValue("Golden Ratio", golden);
      engineMetrics["Golden Ratio Offset"] = double.parse(golden.raw.toStringAsFixed(3));
      int goldenPoints = (golden.normalized * 1500).round();
      fPoints += goldenPoints;
      if (golden.normalized > 0.8) {
         faceComponents.add(ScoreComponent('Golden Ratio (Phi)', '${(golden.normalized * 100).toStringAsFixed(1)}%', goldenPoints, 'Facial proportions closely align with the divine proportion (1.618).'));
         allSlangs.add("Divine Proportions ✨");
      }

      totalScore += fPoints;
      faceScore = DimensionScore(fPoints, 0.9, ["Symmetrical Features 📐"], components: faceComponents);
      eyesScore = DimensionScore(1000, 0.7, ["Piercing Gaze 🦅"]);
      
      expressionScore ??= DimensionScore(800, 0.8, ["Neutral 😐"], components: expressionComponents);

      allSlangs.addAll(faceScore.primaryTraits);
      allSlangs.addAll(eyesScore.primaryTraits);
      allSlangs.addAll(expressionScore!.primaryTraits);
    }
    
    // Body & Posture
    double postureScoreRaw = 0.5;
    String bodyShapeDesc = "Portrait Mode 📸";
    
    DimensionScore bodyScore = DimensionScore(0, 0.0, []);
    DimensionScore postureScore = DimensionScore(0, 0.0, []);
    List<ScoreComponent> bodyComponents = [];
    List<ScoreComponent> postureComponents = [];
    
    if (pose != null) {
      MeasuredValue pScore = GeometryEngine.calculatePostureScore(pose);
      postureScoreRaw = pScore.normalized;
      logger.logMeasuredValue("Posture", pScore);
      
      if (proportions != null) {
         bodyShapeDesc = proportions.bodyShapeSlang;
      } else {
         bodyShapeDesc = isLikelyFemale ? SilhouetteMath.calculateBodyShape(pose) : SilhouetteMath.calculateMaleBodyShapeFallback(pose);
      }
      allSlangs.add(bodyShapeDesc); // Directly add the shape slang
      
      // Posture Score
      engineMetrics["Posture Score"] = double.parse(pScore.normalized.toStringAsFixed(3));
      int posturePoints = (pScore.normalized * 2000).round();
      
      // Spine Angle
      MeasuredValue spine = PoseFeatureEngine.calculateSpineAngle(pose);
      logger.logMeasuredValue("Spine Angle", spine);
      engineMetrics["Spine Angle"] = double.parse(spine.raw.toStringAsFixed(1));
      int spinePoints = (spine.normalized * 1000).round();
      
      posturePoints += spinePoints;
      totalScore += posturePoints;
      
      if (pScore.normalized > 0.85 && spine.normalized > 0.85) {
        postureComponents.add(ScoreComponent('Alpha Posture', '${(pScore.normalized * 100).toStringAsFixed(1)}%', posturePoints, 'Impeccable upright alignment with straight spine.'));
        allSlangs.add("Dominant Posture 🕴️");
      } else if (pScore.normalized < 0.5 || spine.normalized < 0.5) {
        postureComponents.add(ScoreComponent('Slouch Detected', '${(pScore.normalized * 100).toStringAsFixed(1)}%', posturePoints, 'Hunched shoulders or bent spine severely damage your aura.'));
        allSlangs.add("Gamer Posture 🦐");
      } else {
        postureComponents.add(ScoreComponent('Posture Alignment', '${(pScore.normalized * 100).toStringAsFixed(1)}%', posturePoints, 'Standard, balanced posture.'));
      }
      postureScore = DimensionScore(posturePoints, 0.9, ["Strong posture 👑"], components: postureComponents);
      
      // Body shape / proportion points (up to 2000)
      int bPoints = 500; // base body
      bodyComponents.add(ScoreComponent('Base Frame', 'Detected', 500, 'Subject body frame identified in image.'));
      
      if (proportions != null) {
         if (!isLikelyFemale) {
            double s2w = proportions.waistToShoulderRatio > 0 ? (1.0 / proportions.waistToShoulderRatio) : 1.0;
            if (s2w > 1.45) {
               bPoints += 3000; // Massive V-taper reward
               bodyComponents.add(ScoreComponent('V-Taper Ratio', s2w.toStringAsFixed(2), 3000, 'Elite shoulder-to-waist ratio indicating an athletic V-taper.'));
               allSlangs.add("Greek God Physique 🏛️");
               allSlangs.add("Insane V-Taper 🔻");
            } else if (s2w > 1.3) {
               bPoints += 1500;
               bodyComponents.add(ScoreComponent('V-Taper Ratio', s2w.toStringAsFixed(2), 1500, 'Athletic shoulder-to-waist ratio.'));
               allSlangs.add("Athletic Build 🏃‍♂️");
            } else if (s2w > 1.15) {
               bPoints += 500;
               bodyComponents.add(ScoreComponent('V-Taper Ratio', s2w.toStringAsFixed(2), 500, 'Good shoulder-to-waist proportions.'));
            }
         } else {
            // Female curve rewards
            if (proportions.waistToHipRatio < 0.70) {
               bPoints += 6000;
               bodyComponents.add(ScoreComponent('Waist-to-Hip Ratio', proportions.waistToHipRatio.toStringAsFixed(2), 6000, 'Exceptional hourglass proportions.'));
               allSlangs.add("Dump Truck 🍑");
               allSlangs.add("God-Tier Proportions 🧬");
            } else if (proportions.waistToHipRatio < 0.8) {
               bPoints += 2000;
               bodyComponents.add(ScoreComponent('Waist-to-Hip Ratio', proportions.waistToHipRatio.toStringAsFixed(2), 2000, 'Highly attractive waist-to-hip ratio.'));
               allSlangs.add("Curvy Goddess ⏳");
            }
            
            if (proportions.hipToShoulderRatio > 1.15) {
               bPoints += 4000;
               bodyComponents.add(ScoreComponent('Hip-to-Shoulder Ratio', proportions.hipToShoulderRatio.toStringAsFixed(2), 4000, 'Prominent lower body proportions.'));
               allSlangs.add("Wide Hips 🌊");
            } else if (proportions.hipToShoulderRatio > 1.0) {
               bPoints += 1000;
               bodyComponents.add(ScoreComponent('Hip-to-Shoulder Ratio', proportions.hipToShoulderRatio.toStringAsFixed(2), 1000, 'Balanced lower body width.'));
            }

            if (proportions.chestToWaistRatio > 1.3) {
               bPoints += 6000;
               bodyComponents.add(ScoreComponent('Chest-to-Waist Ratio', proportions.chestToWaistRatio.toStringAsFixed(2), 6000, 'Exceptional upper body proportions.'));
               allSlangs.add("Massive Assets 🍈🍈");
               allSlangs.add("Top-Heavy Queen 👑");
            } else if (proportions.chestToWaistRatio > 1.1) {
               bPoints += 3000;
               bodyComponents.add(ScoreComponent('Chest-to-Waist Ratio', proportions.chestToWaistRatio.toStringAsFixed(2), 3000, 'Attractive upper body proportions.'));
               allSlangs.add("Blessed 🍒");
            }

            if (proportions.thighFullness > 1.0) {
               bPoints += 4000;
               bodyComponents.add(ScoreComponent('Thigh Fullness', proportions.thighFullness.toStringAsFixed(2), 4000, 'High muscular/curvy thigh volume.'));
               allSlangs.add("Thick Thighs Save Lives 🍗");
            } else if (proportions.thighFullness > 0.8) {
               bPoints += 2000;
               bodyComponents.add(ScoreComponent('Thigh Fullness', proportions.thighFullness.toStringAsFixed(2), 2000, 'Good leg proportions and fullness.'));
               allSlangs.add("Juicy Thighs 🔥");
            }
         }
      } 
      
      // SHAPE DIVERSITY BONUSES (Applies even if proportions were estimated via fallback)
      if (isLikelyFemale) {
         String slang = bodyShapeDesc.toLowerCase();
         if (slang.contains("pear")) {
            bPoints += 5000;
            bodyComponents.add(ScoreComponent('Shape Bonus', 'Pear', 5000, 'Exceptional lower-body dominant curves.'));
            if (!allSlangs.contains("Pear Perfection 🍐")) allSlangs.add("Pear Perfection 🍐");
         } else if (slang.contains("athletic") || slang.contains("triangle")) {
            bPoints += 5000;
            bodyComponents.add(ScoreComponent('Shape Bonus', 'Athletic', 5000, 'Strong, lean, and highly athletic frame.'));
            if (!allSlangs.contains("Athletic Build 🏃‍♀️")) allSlangs.add("Athletic Build 🏃‍♀️");
         } else if (slang.contains("apple")) {
            bPoints += 4000;
            bodyComponents.add(ScoreComponent('Shape Bonus', 'Apple', 4000, 'Beautifully voluptuous upper and core curves.'));
            if (!allSlangs.contains("Curvy Core 🍎")) allSlangs.add("Curvy Core 🍎");
         } else if (slang.contains("petite")) {
            bPoints += 4000;
            bodyComponents.add(ScoreComponent('Shape Bonus', 'Petite', 4000, 'Perfectly balanced, slender proportions.'));
            if (!allSlangs.contains("Slender Aesthetic ✨")) allSlangs.add("Slender Aesthetic ✨");
         }
      }

      totalScore += bPoints;
      bodyScore = DimensionScore(bPoints, 0.85, ["Confident form ✨"], components: bodyComponents);
      
      allSlangs.addAll(bodyScore.primaryTraits);
      allSlangs.addAll(postureScore.primaryTraits);
    } else {
      // 2D Art or Abstract Case (No pose detected)
      int bPoints = 500;
      if (advanced != null) {
        // Fallback to advanced stats for body approximation
        double w2s = advanced.waistToShoulderRatio;
        double h2s = advanced.hipToShoulderRatio;
        if (w2s < 0.75) {
          bPoints += 1500; 
          bodyComponents.add(ScoreComponent('Waist-to-Shoulder (Fallback)', w2s.toStringAsFixed(2), 1500, 'Calculated via bounding box estimates.'));
        }
        if (h2s > 1.0) {
          bPoints += 1500;  
          bodyComponents.add(ScoreComponent('Hip-to-Shoulder (Fallback)', h2s.toStringAsFixed(2), 1500, 'Calculated via bounding box estimates.'));
        }
        int racyBonus = (advanced.racyScore * 1000).round();
        if (racyBonus > 0) {
          bPoints += racyBonus;
          bodyComponents.add(ScoreComponent('Aesthetic Confidence', '${(advanced.racyScore * 100).toStringAsFixed(0)}%', racyBonus, 'Boldness in physical expression.'));
        }
        
        bool isAnime = labels.any((l) => ['anime', 'illustration', 'art', 'drawing', 'cartoon'].contains(l.toLowerCase()));
        if (isAnime) {
           allSlangs.add(isLikelyFemale ? "2D Waifu 🌸" : "Anime Aesthetic ✨");
           allSlangs.add("Digital Masterpiece 🎨");
           bPoints += 2000;
           bodyComponents.add(ScoreComponent('2D Aesthetic', 'Active', 2000, 'Recognized as high-quality illustrated art.'));
        } else {
           allSlangs.add("Abstract Form 👤");
        }
      }
      totalScore += bPoints;
      bodyScore = DimensionScore(bPoints, 0.85, ["Aesthetic Figure 💎"], components: bodyComponents);
      allSlangs.addAll(bodyScore.primaryTraits);
      bodyShapeDesc = "Artistic Form 🎨";
    }
    
    // Process Labels for Male-Specific Traits (Beard, Muscle)
    List<ScoreComponent> styleComponents = [];
    if (!isLikelyFemale) {
       for (var l in labels) {
         String label = l.toLowerCase();
         if (label.contains('beard') || label.contains('facial hair') || label.contains('moustache')) {
            if (!allSlangs.contains("Majestic Beard 🧔")) {
               allSlangs.add("Majestic Beard 🧔");
               totalScore += 800;
               styleComponents.add(ScoreComponent('Facial Hair Detection', 'Present', 800, 'Beard/Moustache detected via ML categorisation.'));
            }
         }
         if (label.contains('muscle') || label.contains('chest') || label.contains('barechested') || label.contains('six pack') || label.contains('abs') || label.contains('biceps')) {
            if (!allSlangs.contains("Shredded 🔱")) {
                allSlangs.add("Shredded 🔱");
                allSlangs.add("Absolute Unit 💪");
                totalScore += 2000;
                styleComponents.add(ScoreComponent('Muscular Definition', 'High', 2000, 'Muscle tone or barechested aesthetics detected.'));
            }
         }
       }
    }
    
    // Style, Emotion & Advanced Attributes
    int sPoints = 0;
    if (advanced != null) {
       // Styling score (up to 1500)
       int stlPts = (advanced.stylingScore * 1000).round();
       sPoints += stlPts;
       styleComponents.add(ScoreComponent('Styling Score', '${(advanced.stylingScore * 100).toStringAsFixed(0)}%', stlPts, 'Overall fashion and composition aesthetic.'));
       
       if (advanced.hasGlamorousMakeup) {
         sPoints += 300;
         styleComponents.add(ScoreComponent('Glamorous Makeup', 'Yes', 300, 'Makeup application detected.'));
       }
       
       int apparelPts = (advanced.detectedApparel.length * 100);
       sPoints += apparelPts;
       if (apparelPts > 0) {
         styleComponents.add(ScoreComponent('Apparel Complexity', '${advanced.detectedApparel.length} items', apparelPts, 'Bonus for complex outfits and accessories.'));
       }
       
       // Emotion variety
       if (advanced.dominantEmotion != 'neutral') {
         sPoints += 200;
         styleComponents.add(ScoreComponent('Dominant Emotion', advanced.dominantEmotion, 200, 'Non-neutral engaging emotion detected.'));
       }
    }
    totalScore += sPoints;
    DimensionScore styleScore = DimensionScore(sPoints, 0.8, ["Serving looks 💅", "Immaculate style 🪞"], components: styleComponents);
    allSlangs.addAll(styleScore.primaryTraits);
    
    // Image Quality / Lighting (replacing simulated with real pixel data)
    int iPoints = 500; 
    List<ScoreComponent> imageComponents = [];
    imageComponents.add(ScoreComponent('Base Quality', 'Standard', 500, 'Baseline image processing score.'));
    
    if (advanced != null) {
      int lightingPts = (advanced.lightingScore * 1000).round();
      iPoints += lightingPts; // up to 1000 for perfect luma
      imageComponents.add(ScoreComponent('Lighting Quality', '${(advanced.lightingScore * 100).toStringAsFixed(0)}%', lightingPts, 'Evaluation of image exposure and illumination.'));
      
      int skinPts = (advanced.skinSmoothness * 500).round();
      iPoints += skinPts; // up to 500 for skin quality
      imageComponents.add(ScoreComponent('Skin Smoothness', '${(advanced.skinSmoothness * 100).toStringAsFixed(0)}%', skinPts, 'Skin texture clarity and smoothness.'));
      
      int hairPts = (advanced.hairVolumeRatio * 500).round();
      iPoints += hairPts; // up to 500 for hair volume
      imageComponents.add(ScoreComponent('Hair Volume', '${(advanced.hairVolumeRatio * 100).toStringAsFixed(0)}%', hairPts, 'Proportion of hair volume relative to face size.'));
    }
    DimensionScore imageScore = DimensionScore(iPoints, 0.9, ["High Quality 📸", "Crisp 🎥"], components: imageComponents); 
    allSlangs.addAll(imageScore.primaryTraits);
    totalScore += iPoints;
    
    // Dynamic Pose bonus (up to 500 points)
    int posePoints = 200 + (postureScoreRaw * 300).round();
    List<ScoreComponent> poseComponents = [ScoreComponent('Dynamism', '${(postureScoreRaw * 100).toStringAsFixed(0)}%', posePoints, 'Pose energy and non-static presentation.')];
    DimensionScore poseS = DimensionScore(posePoints, 0.7, ["Dynamic ⚡"], components: poseComponents); 
    allSlangs.addAll(poseS.primaryTraits);
    totalScore += posePoints;
    
    // Presence (Aggregated confidence)
    double presenceMultiplier = isLikelyFemale ? 0.25 : 0.10;
    int multiplierBonus = (totalScore * presenceMultiplier).round();
    int prPoints = multiplierBonus;
    List<ScoreComponent> presenceComponents = [ScoreComponent('Overall Multiplier', '${(presenceMultiplier * 100).toInt()}%', multiplierBonus, 'Aura presence scales directly with all accumulated points.')];
    
    if (isLikelyFemale) {
       int divineBonus = 5000;
       prPoints += divineBonus;
       presenceComponents.add(ScoreComponent('Divine Feminine Bonus', 'Active', divineBonus, 'Inherent aura boost for female presence.'));
    }
    
    totalScore += prPoints;
    DimensionScore presenceScore = DimensionScore(prPoints, 0.85, ["Main-character energy 💫"], components: presenceComponents); 
    allSlangs.addAll(presenceScore.primaryTraits);
    
    // Content Score (NSFW/Racy logic) with Explicit Curve Multipliers
    int cScore = 0;
    List<ScoreComponent> contentComponents = [];
    if (advanced != null) {
      cScore = (advanced.nudityScore * 100).round();
      
      // Strict threshold: Only explicitly revealing images get massive boosts
      if (advanced.racyScore > 0.85 || advanced.nudityScore > 0.85) {
        int bonus = (advanced.racyScore * 15000).round() + (advanced.nudityScore * 25000).round();
        contentComponents.add(ScoreComponent('Provocative Bonus', 'Explicit', bonus, 'Massive aura amplification for bold explicit content.'));
        totalScore += bonus;
        
        // Massive curve bonuses ONLY when explicitly revealing
        if (proportions != null && isLikelyFemale) {
            double explicitMultiplier = max(advanced.racyScore, advanced.nudityScore);
            int curveBonus = 0;
            
            if (proportions.chestToWaistRatio > 1.2) {
                int cb = (30000 * explicitMultiplier).round();
                curveBonus += cb;
                contentComponents.add(ScoreComponent('Explicit Curves (Chest)', proportions.chestToWaistRatio.toStringAsFixed(2), cb, 'Unrestricted exposure bonus for proportions.'));
                if (!allSlangs.contains("Busty Perfection 🍒")) allSlangs.add("Busty Perfection 🍒");
            }
            if (proportions.waistToHipRatio < 0.75) {
                int cb = (22500 * explicitMultiplier).round();
                curveBonus += cb;
                contentComponents.add(ScoreComponent('Explicit Curves (Waist)', proportions.waistToHipRatio.toStringAsFixed(2), cb, 'Unrestricted exposure bonus for proportions.'));
                if (!allSlangs.contains("Snatched Waist ⏳")) allSlangs.add("Snatched Waist ⏳");
            }
            if (proportions.thighFullness > 0.9) {
                int cb = (22500 * explicitMultiplier).round();
                curveBonus += cb;
                contentComponents.add(ScoreComponent('Explicit Curves (Thighs)', proportions.thighFullness.toStringAsFixed(2), cb, 'Unrestricted exposure bonus for proportions.'));
                if (!allSlangs.contains("Incredible Thighs 🍗")) allSlangs.add("Incredible Thighs 🍗");
            }
            if (proportions.hipToShoulderRatio > 1.1) {
                int cb = (15000 * explicitMultiplier).round();
                curveBonus += cb;
                contentComponents.add(ScoreComponent('Explicit Curves (Hips)', proportions.hipToShoulderRatio.toStringAsFixed(2), cb, 'Unrestricted exposure bonus for proportions.'));
            }
            totalScore += curveBonus;
        }
      } else {
        // Minor curve bonuses for normal images
        if (proportions != null && isLikelyFemale) {
            int minorCurveBonus = 0;
            if (proportions.chestToWaistRatio > 1.2) {
               minorCurveBonus += 800;
               contentComponents.add(ScoreComponent('Implied Curves (Chest)', proportions.chestToWaistRatio.toStringAsFixed(2), 800, 'Subtle bonus for aesthetic proportions.'));
            }
            if (proportions.waistToHipRatio < 0.75) {
               minorCurveBonus += 800;
               contentComponents.add(ScoreComponent('Implied Curves (Waist)', proportions.waistToHipRatio.toStringAsFixed(2), 800, 'Subtle bonus for aesthetic proportions.'));
            }
            if (proportions.thighFullness > 0.9) {
               minorCurveBonus += 600;
               contentComponents.add(ScoreComponent('Implied Curves (Thighs)', proportions.thighFullness.toStringAsFixed(2), 600, 'Subtle bonus for aesthetic proportions.'));
            }
            if (proportions.hipToShoulderRatio > 1.1) {
               minorCurveBonus += 400;
               contentComponents.add(ScoreComponent('Implied Curves (Hips)', proportions.hipToShoulderRatio.toStringAsFixed(2), 400, 'Subtle bonus for aesthetic proportions.'));
            }
            totalScore += minorCurveBonus;
        }
      }
        
        if (advanced.nudityScore > 0.8) {
           allSlangs.add("Absolute Nudity 🔥🔥");
           allSlangs.add("Too Hot For Instagram 🚫");
           allSlangs.add("OnlyFans Top 0.1% 💸");
        } else if (advanced.racyScore > 0.8) {
           allSlangs.add("Racy Perfection 😈");
           allSlangs.add("God-Tier Assets 🍒💦");
        }
        
        if (!allSlangs.contains("Baddie 🥵")) allSlangs.add(isLikelyFemale ? "Baddie 🥵" : "Bold 🌶️");
        if (!allSlangs.contains("Breaking the Internet 🌐")) allSlangs.add("Breaking the Internet 🌐");
    }
    DimensionScore contentScore = DimensionScore(cScore, 0.95, [], components: contentComponents); 

    // If completely unable to detect anything good, give arbitrary small negative.
    if (totalScore < 500) {
      totalScore = -Random().nextInt(100);
    } else if (totalScore > 8500) {
      // ONLY boost the score if the image performs absolutely outstanding across all metrics
      totalScore = (totalScore * 1.3).round(); 
    }

    if (proportions != null && proportions.rawMetrics.isNotEmpty) {
      engineMetrics.addAll(proportions.rawMetrics);
    }
    
    logger.export().forEach((k, v) => engineMetrics[k] = (v as num).toDouble());

    return DetailedAuraScore(
      overallPoints: totalScore,
      isBodyOnly: isBodyOnly,
      face: faceScore,
      eyes: eyesScore,
      expression: expressionScore,
      body: bodyScore,
      posture: postureScore,
      pose: poseS,
      style: styleScore,
      image: imageScore,
      presence: presenceScore,
      content: contentScore,
      bodyShape: bodyShapeDesc,
      bodyShapeConfidence: 0.8,
      allSlangs: allSlangs.toSet().toList(),
      rawMetrics: engineMetrics,
    );
  }
}
