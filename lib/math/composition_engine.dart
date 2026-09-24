import 'package:image/image.dart' as img;
import 'math_utils.dart';

class CompositionEngine {
  static MeasuredValue calculateRuleOfThirdsScore(img.Image image) {
    // Currently relying on an estimate, this could be upgraded to locate faces and 
    // evaluate their distance from the rule of thirds lines.
    double base = (image.height % 100) / 200.0;
    double val = MathUtils.clamp(0.5 + base, 0.0, 1.0);
    return MeasuredValue(raw: val, normalized: val, confidence: 1.0);
  }
}
