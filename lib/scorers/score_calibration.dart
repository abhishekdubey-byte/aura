import 'dart:math';

import '../aura/pixel_analysis.dart';
import '../models/detailed_aura_score.dart';

/// Product thresholds, not a statistical claim about a person's attractiveness.
/// A steep curve makes exceptional results possible without awarding millions
/// for simply detecting a person. Missing models cannot unlock high tiers.
class ScoreCalibration {
  const ScoreCalibration(this.points, this.ceiling, this.checks);
  final int points;
  final int ceiling;
  final List<AuraScoreCheck> checks;

  static ScoreCalibration evaluate({
    required PixelMetrics pixels,
    required double quality,
    required Map<String, double> categories,
    required int componentCount,
    required bool clearPerson,
    required double framing,
  }) {
    final p = pixels;
    bool between(double v, double lo, double hi) =>
        v.isFinite && v >= lo && v <= hi;
    final clip = p.shadowClip + p.highlightClip;
    final subjectLight = p.subjectLuma ?? p.meanLuma;
    final strong = categories.values.where((q) => q >= 0.72).length;
    final exceptional = categories.values.where((q) => q >= 0.85).length;
    final style = categories['style'] ?? 0;
    final checks = <AuraScoreCheck>[
      AuraScoreCheck(
        'Lighting',
        between(p.meanLuma, 80, 205) && between(subjectLight, 45, 225),
        'Use enough light to show the person and the scene clearly.',
        1000000,
      ),
      AuraScoreCheck(
        'Focus',
        p.sharpness.isFinite && p.sharpness >= 100,
        'Keep the subject in focus and hold the camera steady.',
        1000000,
      ),
      AuraScoreCheck(
        'Shadow & highlight detail',
        between(clip, 0, 0.18),
        'Keep detail in both dark and bright areas.',
        1000000,
      ),
      AuraScoreCheck(
        'Tonal detail',
        between(p.lumaStdDev, 20, 95),
        'Avoid flat lighting and harsh, crushed contrast.',
        1000000,
      ),
      AuraScoreCheck(
        'Clear person',
        clearPerson,
        'Show a clearly detected person at a useful size.',
        1000000,
      ),
      AuraScoreCheck(
        'Framing',
        framing >= 0.6,
        'Give the subject a clear place in the composition.',
        1000000,
      ),
      AuraScoreCheck(
        'Style & setting',
        style >= 0.55,
        'Bring together the outfit, colours and background.',
        1000000,
      ),
      AuraScoreCheck(
        'Multiple strengths',
        strong >= 4 && componentCount >= 12,
        'Build at least four strong categories with enough visible detail.',
        1000000,
      ),
      AuraScoreCheck(
        'Exceptional lighting',
        between(p.meanLuma, 90, 175) &&
            between(subjectLight, 55, 210) &&
            between(clip, 0, 0.06),
        'Balance the light with very little lost shadow or highlight detail.',
        10000000,
      ),
      AuraScoreCheck(
        'Exceptional detail',
        p.sharpness.isFinite &&
            p.sharpness >= 260 &&
            between(p.lumaStdDev, 35, 80),
        'Capture crisp subject detail with balanced contrast.',
        10000000,
      ),
      AuraScoreCheck(
        'Standout styling',
        style >= 0.72 && framing >= 0.8,
        'Combine strong styling with deliberate framing.',
        10000000,
      ),
      AuraScoreCheck(
        'Exceptional consistency',
        exceptional >= 5 && componentCount >= 16,
        'Reach five exceptional categories with enough measured detail.',
        10000000,
      ),
    ];
    final millionReady = checks
        .where((c) => c.milestone == 1000000)
        .every((c) => c.passed);
    final exceptionalReady = millionReady && checks.every((c) => c.passed);
    final severe =
        !between(p.meanLuma, 35, 235) ||
        !between(subjectLight, 25, 240) ||
        p.sharpness < 20 ||
        clip > 0.55;
    final dim =
        !between(p.meanLuma, 80, 205) ||
        !between(subjectLight, 45, 225) ||
        p.sharpness < 60 ||
        clip > 0.3;
    final ceiling = severe
        ? 9999
        : dim
        ? 99999
        : !millionReady
        ? 999999
        : !exceptionalReady
        ? 9999999
        : 99999999;
    final q = quality.isFinite ? quality.clamp(0.0, 1.0) : 0.0;
    // Even a technically perfect single category cannot carry a whole photo.
    final curved = 101 + (99999999 - 101) * pow(q, 16);
    // Scale within a locked tier, rather than giving every failed shot its cap.
    final tierLimit = exceptionalReady
        ? ceiling.toDouble()
        : 101 + (ceiling - 101) * pow(q, 4);
    final points = min(curved, tierLimit).round().clamp(101, ceiling);
    return ScoreCalibration(points, ceiling, checks);
  }
}
