import 'dart:typed_data';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class TrueProportions {
  final double waistToHipRatio;
  final double waistToShoulderRatio;
  final double hipToShoulderRatio;
  final double chestToWaistRatio;
  final double thighFullness;
  final String bodyShapeSlang;
  final Map<String, double> rawMetrics;

  TrueProportions({
    required this.waistToHipRatio,
    required this.waistToShoulderRatio,
    required this.hipToShoulderRatio,
    required this.chestToWaistRatio,
    required this.thighFullness,
    required this.bodyShapeSlang,
    required this.rawMetrics,
  });
}

class SilhouetteMath {
  /// Measures the physical width of the subject's flesh by scanning the confidence mask
  /// left and right from the center bone spine.
  static double _measureMaskWidth(Float32List mask, int maskWidth, int maskHeight, int y, int startX, int searchRadius) {
    if (y < 0 || y >= maskHeight) return 0.0;
    
    int leftEdge = startX;
    int rightEdge = startX;
    
    // Scan left
    for (int x = startX; x >= 0 && (startX - x) < searchRadius; x--) {
      if (mask[y * maskWidth + x] > 0.5) {
        leftEdge = x;
      } else {
        break; // Reached the edge of the flesh
      }
    }
    
    // Scan right
    for (int x = startX; x < maskWidth && (x - startX) < searchRadius; x++) {
      if (mask[y * maskWidth + x] > 0.5) {
        rightEdge = x;
      } else {
        break; // Reached the edge of the flesh
      }
    }
    
    return (rightEdge - leftEdge).toDouble();
  }

  /// OVERLAY ALGORITHM: Fuses 3D skeletal data with 2D silhouette mask
  static TrueProportions calculateTrueFemaleShape(Pose pose, Float32List mask, int maskWidth, int maskHeight) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];
    final lk = pose.landmarks[PoseLandmarkType.leftKnee];
    final rk = pose.landmarks[PoseLandmarkType.rightKnee];

    if (ls == null || rs == null || lh == null || rh == null) {
      return TrueProportions(
        waistToHipRatio: 1.0, waistToShoulderRatio: 1.0, hipToShoulderRatio: 1.0,
        chestToWaistRatio: 1.0, thighFullness: 0.0, bodyShapeSlang: "Unknown Shape",
        rawMetrics: {}
      );
    }

    int midX = ((ls.x + rs.x + lh.x + rh.x) / 4).round();
    int searchRadius = (maskWidth * 0.4).round(); // Max scan width

    int shoulderY = ((ls.y + rs.y) / 2).round();
    int hipY = ((lh.y + rh.y) / 2).round();
    int waistY = (shoulderY + (hipY - shoulderY) * 0.4).round(); // Waist is slightly above midpoint

    double shoulderFleshWidth = _measureMaskWidth(mask, maskWidth, maskHeight, shoulderY, midX, searchRadius);
    
    // Deep Analysis Algorithm: To accurately capture the bust/boobs regardless of pose 
    // (e.g. laying down in 005.jpg, gravity sag, extreme volume), we scan the entire 
    // vertical region between the shoulder and the waist and extract the MAXIMUM width.
    double bustFleshWidth = 0.0;
    int scanStart = shoulderY;
    int scanEnd = waistY;
    if (scanStart > scanEnd) {
       int temp = scanStart;
       scanStart = scanEnd;
       scanEnd = temp;
    }
    // Scan every few pixels to find the absolute widest point of the chest
    int step = (maskHeight * 0.01).round().clamp(1, 10);
    for (int y = scanStart; y < scanEnd; y += step) {
       double w = _measureMaskWidth(mask, maskWidth, maskHeight, y, midX, searchRadius);
       if (w > bustFleshWidth) bustFleshWidth = w;
    }
    
    // 1. Dynamic Waist Detection: Find the narrowest point between bust and hip
    double waistFleshWidth = double.infinity;
    int waistScanStart = waistY - (maskHeight * 0.05).round(); // Slight buffer above static waist
    int waistScanEnd = hipY;
    if (waistScanStart > waistScanEnd) {
       int temp = waistScanStart; waistScanStart = waistScanEnd; waistScanEnd = temp;
    }
    for (int y = waistScanStart; y < waistScanEnd; y += step) {
       double w = _measureMaskWidth(mask, maskWidth, maskHeight, y, midX, searchRadius);
       if (w > 0 && w < waistFleshWidth) waistFleshWidth = w;
    }
    if (waistFleshWidth == double.infinity) waistFleshWidth = _measureMaskWidth(mask, maskWidth, maskHeight, waistY, midX, searchRadius);

    // 2. Dynamic Hip Detection: Find the widest point around the pelvic region
    double hipFleshWidth = 0.0;
    int hipScanStart = waistY; 
    int hipScanEnd = hipY + (maskHeight * 0.1).round(); 
    if (hipScanStart > hipScanEnd) {
       int temp = hipScanStart; hipScanStart = hipScanEnd; hipScanEnd = temp;
    }
    for (int y = hipScanStart; y < hipScanEnd; y += step) {
       double w = _measureMaskWidth(mask, maskWidth, maskHeight, y, midX, searchRadius);
       if (w > hipFleshWidth) hipFleshWidth = w;
    }
    if (hipFleshWidth == 0.0) hipFleshWidth = _measureMaskWidth(mask, maskWidth, maskHeight, hipY, midX, searchRadius);
    
    double thighFleshWidth = 0.0;
    double calfFleshWidth = 0.0;
    if (lk != null && rk != null) {
      int kneeY = ((lk.y + rk.y) / 2).round();
      
      // 3. Dynamic Thigh Detection: Find the widest point on the upper leg
      int thighScanStart = hipY;
      int thighScanEnd = kneeY;
      if (thighScanStart > thighScanEnd) {
         int temp = thighScanStart; thighScanStart = thighScanEnd; thighScanEnd = temp;
      }
      for (int y = thighScanStart; y < thighScanEnd; y += step) {
         double leftThigh = _measureMaskWidth(mask, maskWidth, maskHeight, y, lh.x.round(), searchRadius ~/ 2);
         double rightThigh = _measureMaskWidth(mask, maskWidth, maskHeight, y, rh.x.round(), searchRadius ~/ 2);
         double combined = leftThigh + rightThigh;
         if (combined > thighFleshWidth) thighFleshWidth = combined;
      }
      if (thighFleshWidth == 0.0) {
         int staticThighY = (hipY + (kneeY - hipY) * 0.3).round();
         thighFleshWidth = _measureMaskWidth(mask, maskWidth, maskHeight, staticThighY, lh.x.round(), searchRadius ~/ 2) + 
                           _measureMaskWidth(mask, maskWidth, maskHeight, staticThighY, rh.x.round(), searchRadius ~/ 2);
      }
      
      final lAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
      final rAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
      if (lAnkle != null && rAnkle != null) {
         int ankleY = ((lAnkle.y + rAnkle.y) / 2).round();
         int calfY = (kneeY + (ankleY - kneeY) * 0.3).round();
         double leftCalf = _measureMaskWidth(mask, maskWidth, maskHeight, calfY, lk.x.round(), searchRadius ~/ 2);
         double rightCalf = _measureMaskWidth(mask, maskWidth, maskHeight, calfY, rk.x.round(), searchRadius ~/ 2);
         calfFleshWidth = leftCalf + rightCalf;
      }
    }
    
    // Neck width estimation (slightly above shoulders)
    int neckY = (shoulderY - (maskHeight * 0.03)).round();
    double neckFleshWidth = _measureMaskWidth(mask, maskWidth, maskHeight, neckY, midX, searchRadius ~/ 3);

    // Safety clamps
    shoulderFleshWidth = shoulderFleshWidth.clamp(1.0, double.infinity);
    waistFleshWidth = waistFleshWidth.clamp(1.0, double.infinity);
    hipFleshWidth = hipFleshWidth.clamp(1.0, double.infinity);
    
    // --- PHYSICS & ANATOMY RATIO CALCULATIONS ---
    // These metrics are calculated based on the maximum physical flesh width extracted 
    // from the 2D silhouette mask layered over the 3D skeletal geometry.
    // By using the absolute maximums (e.g., the Deep Analysis scan for the bust), 
    // we accurately measure extreme proportions, curves, and massive assets 
    // without losing data to gravity sag, camera angles, or laying down poses.
    
    // Waist-to-Hip Ratio: Measures the extreme hourglass curve (hips and butts vs tiny waist).
    double waistToHipRatio = waistFleshWidth / hipFleshWidth;
    
    // Waist-to-Shoulder Ratio: Measures the taper from the upper torso down to the core.
    double waistToShoulderRatio = waistFleshWidth / shoulderFleshWidth;
    
    // Hip-to-Shoulder Ratio: Compares bottom-heavy curves (hips/butts/thighs) to the frame.
    double hipToShoulderRatio = hipFleshWidth / shoulderFleshWidth;
    
    // Chest-to-Waist Ratio: The ultimate metric for measuring massive busts/boobs 
    // against a tight waist. High ratios here (>1.3) trigger the highest bonus multipliers.
    double chestToWaistRatio = bustFleshWidth / waistFleshWidth;

    String shape = "Unknown Shape";
    if (waistToHipRatio < 0.8 && hipToShoulderRatio > 0.95) {
      shape = "Hourglass goddess ⏳";
    } else if (hipToShoulderRatio > 1.1) {
      shape = "Pear-shaped Queen 🍐";
    } else if (waistToShoulderRatio > 0.9 && hipToShoulderRatio < 0.95) {
      shape = "Voluptuous Apple 🍎";
    } else if (waistToHipRatio > 0.85 && hipToShoulderRatio < 0.9) {
      shape = "Athletic Goddess 🏃‍♀️";
    } else {
      shape = "Petite Perfection ✨";
    }

    Map<String, double> metrics = {
      "Waist-to-Hip Ratio": double.parse(waistToHipRatio.toStringAsFixed(3)),
      "Waist-to-Shoulder Ratio": double.parse(waistToShoulderRatio.toStringAsFixed(3)),
      "Hip-to-Shoulder Ratio": double.parse(hipToShoulderRatio.toStringAsFixed(3)),
      "Bust-to-Waist Ratio": double.parse(chestToWaistRatio.toStringAsFixed(3)),
      "Thigh Fullness": double.parse((thighFleshWidth / shoulderFleshWidth).toStringAsFixed(3)),
    };
    
    if (neckFleshWidth > 0) {
      metrics["Neck-to-Shoulder Ratio"] = double.parse((neckFleshWidth / shoulderFleshWidth).toStringAsFixed(3));
    }
    if (calfFleshWidth > 0) {
      metrics["Calf-to-Thigh Ratio"] = double.parse((calfFleshWidth / thighFleshWidth).toStringAsFixed(3));
    }

    return TrueProportions(
      waistToHipRatio: waistToHipRatio,
      waistToShoulderRatio: waistToShoulderRatio,
      hipToShoulderRatio: hipToShoulderRatio,
      chestToWaistRatio: chestToWaistRatio,
      thighFullness: thighFleshWidth / shoulderFleshWidth,
      bodyShapeSlang: shape,
      rawMetrics: metrics
    );
  }

  /// Infers body shape category based on skeletal hip and shoulder widths
  /// (Fallback when subject segmentation mask is unavailable)
  static String calculateBodyShape(Pose pose) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];

    if (ls == null || rs == null || lh == null || rh == null) {
      return "Unknown Shape";
    }

    double shoulderWidth = (ls.x - rs.x).abs();
    double hipWidth = (lh.x - rh.x).abs();

    if (shoulderWidth == 0) return "Unknown Shape";

    double h2s = hipWidth / shoulderWidth;

    if (h2s > 1.15) {
       return "Pear-shaped Queen 🍐";
    } else if (h2s > 1.05) {
       return "Bottom Hourglass silhouette ⏳🍑";
    } else if (h2s < 0.85) {
       return "Athletic Goddess 🏃‍♀️";
    } else if (h2s < 0.95) {
       return "Top Hourglass silhouette ⏳✨";
    } else {
       return "Hourglass queen ⏳🔥";
    }
  }

  /// OVERLAY ALGORITHM: Calculates true physical proportions for males
  static TrueProportions calculateTrueMaleShape(Pose pose, Float32List mask, int maskWidth, int maskHeight) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];
    final lk = pose.landmarks[PoseLandmarkType.leftKnee];
    final rk = pose.landmarks[PoseLandmarkType.rightKnee];

    if (ls == null || rs == null || lh == null || rh == null) {
      return TrueProportions(
        waistToHipRatio: 1.0, waistToShoulderRatio: 1.0, hipToShoulderRatio: 1.0,
        chestToWaistRatio: 1.0, thighFullness: 0.0, bodyShapeSlang: "Unknown Shape",
        rawMetrics: {}
      );
    }

    int midX = ((ls.x + rs.x + lh.x + rh.x) / 4).round();
    int searchRadius = (maskWidth * 0.4).round(); // Max scan width

    int shoulderY = ((ls.y + rs.y) / 2).round();
    int hipY = ((lh.y + rh.y) / 2).round();
    int waistY = (shoulderY + (hipY - shoulderY) * 0.4).round(); 

    double shoulderFleshWidth = _measureMaskWidth(mask, maskWidth, maskHeight, shoulderY, midX, searchRadius);
    
    // Deep Analysis Algorithm: Scan the entire vertical region between shoulder and waist 
    // to extract the absolute MAXIMUM chest/pec width.
    double chestFleshWidth = 0.0;
    int scanStart = shoulderY;
    int scanEnd = waistY;
    if (scanStart > scanEnd) {
       int temp = scanStart;
       scanStart = scanEnd;
       scanEnd = temp;
    }
    int step = (maskHeight * 0.01).round().clamp(1, 10);
    for (int y = scanStart; y < scanEnd; y += step) {
       double w = _measureMaskWidth(mask, maskWidth, maskHeight, y, midX, searchRadius);
       if (w > chestFleshWidth) chestFleshWidth = w;
    }
    
    double waistFleshWidth = _measureMaskWidth(mask, maskWidth, maskHeight, waistY, midX, searchRadius);
    double hipFleshWidth = _measureMaskWidth(mask, maskWidth, maskHeight, hipY, midX, searchRadius);
    
    double thighFleshWidth = 0.0;
    double calfFleshWidth = 0.0;
    if (lk != null && rk != null) {
      int kneeY = ((lk.y + rk.y) / 2).round();
      int thighY = (hipY + (kneeY - hipY) * 0.3).round();
      double leftThigh = _measureMaskWidth(mask, maskWidth, maskHeight, thighY, lh.x.round(), searchRadius ~/ 2);
      double rightThigh = _measureMaskWidth(mask, maskWidth, maskHeight, thighY, rh.x.round(), searchRadius ~/ 2);
      thighFleshWidth = leftThigh + rightThigh; 
      
      final lAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
      final rAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
      if (lAnkle != null && rAnkle != null) {
         int ankleY = ((lAnkle.y + rAnkle.y) / 2).round();
         int calfY = (kneeY + (ankleY - kneeY) * 0.3).round();
         double leftCalf = _measureMaskWidth(mask, maskWidth, maskHeight, calfY, lk.x.round(), searchRadius ~/ 2);
         double rightCalf = _measureMaskWidth(mask, maskWidth, maskHeight, calfY, rk.x.round(), searchRadius ~/ 2);
         calfFleshWidth = leftCalf + rightCalf;
      }
    }
    
    // Neck width estimation (slightly above shoulders)
    int neckY = (shoulderY - (maskHeight * 0.03)).round();
    double neckFleshWidth = _measureMaskWidth(mask, maskWidth, maskHeight, neckY, midX, searchRadius ~/ 3);

    // Safety clamps
    shoulderFleshWidth = shoulderFleshWidth.clamp(1.0, double.infinity);
    waistFleshWidth = waistFleshWidth.clamp(1.0, double.infinity);
    hipFleshWidth = hipFleshWidth.clamp(1.0, double.infinity);
    
    double waistToHipRatio = waistFleshWidth / hipFleshWidth;
    double waistToShoulderRatio = waistFleshWidth / shoulderFleshWidth;
    double hipToShoulderRatio = hipFleshWidth / shoulderFleshWidth;
    double chestToWaistRatio = chestFleshWidth / waistFleshWidth;

    String shape = "Unknown Shape";
    double s2w = shoulderFleshWidth / waistFleshWidth;
    
    if (s2w > 1.6) {
      shape = "God-Tier V-Taper 🗡️";
    } else if (s2w > 1.4) {
      shape = "Athletic V-Taper 📐";
    } else if (s2w > 1.2) {
      shape = "Fit & Lean 🏃‍♂️";
    } else if (waistToShoulderRatio > 0.95) {
      shape = "Dad Bod 🍺";
    } else if (waistToShoulderRatio > 0.9) {
      shape = "Built like a Tank 🛡️";
    } else {
      shape = "Average Build 👤";
    }

    Map<String, double> metrics = {
      "Waist-to-Hip Ratio": double.parse(waistToHipRatio.toStringAsFixed(3)),
      "Waist-to-Shoulder Ratio": double.parse(waistToShoulderRatio.toStringAsFixed(3)),
      "Hip-to-Shoulder Ratio": double.parse(hipToShoulderRatio.toStringAsFixed(3)),
      "Chest-to-Waist Ratio": double.parse(chestToWaistRatio.toStringAsFixed(3)),
      "Thigh Fullness": double.parse((thighFleshWidth / shoulderFleshWidth).toStringAsFixed(3)),
    };
    
    if (neckFleshWidth > 0) {
      metrics["Neck-to-Shoulder Ratio"] = double.parse((neckFleshWidth / shoulderFleshWidth).toStringAsFixed(3));
    }
    if (calfFleshWidth > 0) {
      metrics["Calf-to-Thigh Ratio"] = double.parse((calfFleshWidth / thighFleshWidth).toStringAsFixed(3));
    }

    return TrueProportions(
      waistToHipRatio: waistToHipRatio,
      waistToShoulderRatio: waistToShoulderRatio,
      hipToShoulderRatio: hipToShoulderRatio,
      chestToWaistRatio: chestToWaistRatio,
      thighFullness: thighFleshWidth / shoulderFleshWidth,
      bodyShapeSlang: shape,
      rawMetrics: metrics
    );
  }

  /// Infers male body shape category based on skeletal hip and shoulder widths
  /// (Fallback when subject segmentation mask is unavailable)
  static String calculateMaleBodyShapeFallback(Pose pose) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];

    if (ls == null || rs == null || lh == null || rh == null) {
      return "Unknown Shape";
    }

    double shoulderWidth = (ls.x - rs.x).abs();
    double hipWidth = (lh.x - rh.x).abs();

    if (shoulderWidth == 0) return "Unknown Shape";

    double s2h = shoulderWidth / hipWidth;

    if (s2h > 1.5) {
       return "Broad Shoulders 📐";
    } else if (s2h > 1.3) {
       return "Athletic Frame 🏃‍♂️";
    } else if (s2h < 1.0) {
       return "Bottom-Heavy 🍐";
    } else {
       return "Rectangular Frame 🚪";
    }
  }
}
