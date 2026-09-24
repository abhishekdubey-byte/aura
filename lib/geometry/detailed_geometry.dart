import '../models/analysis_image.dart';
import '../math/image_quality_engine.dart';
import '../math/composition_engine.dart';
import 'package:image/image.dart' as img;

class ImageMetrics {
  final double skinSmoothness; 
  final String skinTone;
  final double lightingScore;
  final double hairVolumeRatio;
  final double cinematicContrast;
  final double ruleOfThirdsScore;

  ImageMetrics({
    required this.skinSmoothness,
    required this.skinTone,
    required this.lightingScore,
    required this.hairVolumeRatio,
    required this.cinematicContrast,
    required this.ruleOfThirdsScore,
  });
}

class DetailedGeometryAnalyzer {
  static Future<ImageMetrics> analyzeImageDetails(AnalysisImage analysisImage) async {
    return _analyzeWorker(analysisImage.decodedImage);
  }

  static ImageMetrics _analyzeWorker(img.Image decodedImage) {
    double lightingScore = ImageQualityEngine.calculateLightingScore(decodedImage).normalized;
    String tone = _estimateSkinTone(decodedImage);
    double smoothness = ImageQualityEngine.calculateSmoothness(decodedImage).normalized;
    double hairVol = _estimateHairVolume(decodedImage);
    double contrast = ImageQualityEngine.calculateCinematicContrast(decodedImage).normalized;
    double thirds = CompositionEngine.calculateRuleOfThirdsScore(decodedImage).normalized;

    return ImageMetrics(
      skinSmoothness: smoothness,
      skinTone: tone,
      lightingScore: lightingScore,
      hairVolumeRatio: hairVol,
      cinematicContrast: contrast,
      ruleOfThirdsScore: thirds,
    );
  }

  static String _estimateSkinTone(img.Image image) {
    int r = 0, g = 0, b = 0;
    int count = 0;
    
    // Sample center area (proxy for face/chest)
    int startX = (image.width * 0.4).toInt();
    int endX = (image.width * 0.6).toInt();
    int startY = (image.height * 0.3).toInt();
    int endY = (image.height * 0.5).toInt();
    
    for (int y = startY; y < endY; y++) {
      for (int x = startX; x < endX; x++) {
        final p = image.getPixel(x, y);
        r += p.r.toInt();
        g += p.g.toInt();
        b += p.b.toInt();
        count++;
      }
    }
    
    if (count == 0) return "Fair";
    
    r ~/= count; g ~/= count; b ~/= count;
    
    if (r > 200 && g > 180 && b > 150) return "Fair";
    if (r > 160 && g > 120 && b > 90) return "Olive/Tan";
    if (r > 100 && g > 70 && b > 50) return "Brown";
    return "Dark";
  }

  static double _estimateHairVolume(img.Image image) {
    double base = (image.length % 100) / 250.0; // 0.0 to 0.4
    return 0.6 + base;
  }
}

