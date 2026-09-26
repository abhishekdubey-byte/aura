import 'dart:math';

import '../aura/face_analysis.dart';
import '../aura/model_runner.dart';
import '../aura/pixel_analysis.dart';
import '../aura/pose_analysis.dart';
import '../aura/silhouette_analysis.dart';
import '../models/detailed_aura_score.dart';
import 'score_calibration.dart';

class LabelFinding {
  const LabelFinding(this.label, this.confidence);
  final String label;
  final double confidence;
}

/// Everything the models found in one photo.
class AuraFeatures {
  AuraFeatures({
    required this.face,
    required this.faceCount,
    required this.pose,
    required this.silhouette,
    required this.pixels,
    required this.labels,
    required this.emotions,
    required this.nsfw,
    required this.isArt,
  });

  final FaceMetrics? face;
  final int faceCount;
  final PoseMetrics? pose;
  final SilhouetteMetrics? silhouette;
  final PixelMetrics pixels;
  final List<LabelFinding> labels;
  final List<double>? emotions;
  final double? nsfw;
  final bool isArt;
}

/// Turns measurements into an Aura score.
///
/// Quality is mapped onto a steep progression curve and explicit quality gates.
/// Wording is neutral here; the UI applies a user-selected caption style.
/// Deterministic: the same photo always gets the same score.
class AuraEngine {
  static const int scoringVersion = 2;
  static const int maxScore = 99999999;
  static const int minScore = 101;

  DetailedAuraScore calculateScore(AuraFeatures f) {
    final s = _Sheet();
    final slangs = <String>[];
    final metrics = <String, double>{};

    // ---- Face geometry (ML Kit face contours & landmarks) -----------------
    final face = f.face;
    if (face != null) {
      final double facing = (1 - face.turn * 1.4).clamp(0.2, 1.0);
      if (face.asymmetry != null) {
        final q = _shrink(_gauss(face.asymmetry!, 0.0, 0.16), facing);
        s.add(
          'face',
          'Facial Symmetry',
          '${(q * 100).toStringAsFixed(1)}%',
          6000000,
          q,
          'Left/right balance of eyes, mouth, cheeks and jaw mirrored across your face midline.',
        );
        metrics['Face Asymmetry'] = face.asymmetry!;
        if (q > 0.85) slangs.add('Symmetry Icon 📐');
      }
      if (face.thirds != null) {
        final t = face.thirds!;
        // ML Kit's face outline starts mid-forehead, so balanced faces measure
        // about 20 / 38 / 42 rather than the textbook equal thirds
        const ideal = [0.20, 0.38, 0.42];
        final double dev = sqrt(
          List.generate(
                3,
                (i) => pow(t[i] - ideal[i], 2),
              ).reduce((a, b) => a + b) /
              3,
        );
        final q = _shrink(_gauss(dev, 0, 0.05), facing);
        s.add(
          'face',
          'Facial Thirds',
          t.map((v) => (v * 100).round()).join(' / '),
          3000000,
          q,
          'Forehead, nose and lower-face heights compared with balanced proportions.',
        );
        metrics['Facial Thirds Deviation'] = dev;
        if (q > 0.85) slangs.add('Divine Proportions ✨');
      }
      if (face.eyeSpacing != null) {
        final q = _shrink(_gauss(face.eyeSpacing!, 0.46, 0.07), facing);
        s.add(
          'face',
          'Eye Spacing',
          face.eyeSpacing!.toStringAsFixed(2),
          2000000,
          q,
          'Distance between the eyes relative to face width (ideal about 0.46).',
        );
        metrics['Eye Spacing Ratio'] = face.eyeSpacing!;
      }
      if (face.lengthRatio != null) {
        final q = _shrink(_gauss(face.lengthRatio!, 1.25, 0.18), facing);
        s.add(
          'face',
          'Face Shape',
          face.lengthRatio!.toStringAsFixed(2),
          2000000,
          q,
          'Face length to width; balanced oval proportions score highest.',
        );
        metrics['Face Length Ratio'] = face.lengthRatio!;
      }
      if (face.jawRatio != null) {
        final q = _shrink(_gauss(face.jawRatio!, 0.72, 0.09), facing);
        s.add(
          'face',
          'Jawline Definition',
          face.jawRatio!.toStringAsFixed(2),
          2000000,
          q,
          'Jaw width relative to the widest part of the face.',
        );
        metrics['Jaw Ratio'] = face.jawRatio!;
        if (q > 0.85) slangs.add('Defined Jawline 🗿');
      }
      final double sharpQ = 1 - exp(-f.pixels.sharpness / 150);
      final double lumaQ = f.pixels.subjectLuma == null
          ? 0.6
          : _gauss(f.pixels.subjectLuma!, 135, 50);
      final double clarity = 0.6 * sharpQ + 0.4 * lumaQ;
      s.add(
        'face',
        'Face Clarity',
        '${(clarity * 100).toStringAsFixed(0)}%',
        3000000,
        clarity,
        'Focus and exposure on your face.',
      );

      // ---- Eyes & gaze --------------------------------------------------
      if (face.eyesOpen != null) {
        s.add(
          'eyes',
          'Eyes Open',
          '${(face.eyesOpen! * 100).toStringAsFixed(0)}%',
          4000000,
          face.eyesOpen!,
          'Open, engaged eyes carry presence.',
        );
      }
      final double frontal =
          _gauss(face.yaw, 0, 14) * _gauss(face.pitch, 0, 14);
      final double gazeQ = 0.35 + 0.65 * frontal;
      s.add(
        'eyes',
        'Camera Gaze',
        'yaw ${face.yaw.toStringAsFixed(0)}°, pitch ${face.pitch.toStringAsFixed(0)}°',
        6000000,
        gazeQ,
        'How directly you face the lens.',
      );
      if (face.yaw.abs() < 6 && face.pitch.abs() < 8) {
        slangs.add('Focused Gaze 👁️');
      }
      if (face.yaw.abs() > 25) slangs.add('Mysterious 🌒');

      // ---- Expression ----------------------------------------------------
      if (face.smile != null) {
        final double sm = face.smile!;
        final double q = 0.4 + 0.6 * (2 * sm - 1).abs();
        s.add(
          'expression',
          'Smile / Composure',
          '${(sm * 100).toStringAsFixed(0)}% smile',
          5000000,
          q,
          'A clear smile or a clear, composed look both read as confident.',
        );
        if (sm > 0.7) slangs.add('Glowing Energy ☀️');
        if (sm < 0.15) slangs.add('Ice Cool 🧊');
      }
      final raw = f.emotions;
      if (raw != null && raw.length == 7) {
        // The small 48x48 emotion model is noisy on phone selfies; ML Kit's
        // smile classifier is far more reliable, so a clear smile overrides it
        final emo = List<double>.of(raw);
        final double smile = face.smile ?? 0;
        if (smile > emo[3]) {
          final double rest = emo.fold(0.0, (a, v) => a + v) - emo[3];
          final double scale = rest > 0 ? (1 - smile) / rest : 0;
          for (int i = 0; i < 7; i++) {
            emo[i] = i == 3 ? smile : emo[i] * scale;
          }
        }
        final int top = List.generate(
          7,
          (i) => i,
        ).reduce((a, b) => emo[a] >= emo[b] ? a : b);
        final double happy = emo[3],
            neutral = emo[6],
            surprise = emo[5],
            angry = emo[0];
        final double negative = emo[1] + emo[2] + emo[4];
        final double q =
            (0.35 +
                    0.65 *
                        [
                          happy,
                          0.85 * neutral,
                          0.7 * surprise,
                          0.6 * angry,
                        ].reduce(max) -
                    0.35 * negative)
                .clamp(0.0, 1.0);
        final String label = ModelRunner.emotionLabels[top];
        s.add(
          'expression',
          'Emotion (AI)',
          '${label[0].toUpperCase()}${label.substring(1)} ${(emo[top] * 100).toStringAsFixed(0)}%',
          7000000,
          q,
          'Facial emotion from the on-device emotion model, cross-checked with smile detection.',
        );
        metrics['Emotion ${label[0].toUpperCase()}${label.substring(1)}'] =
            emo[top];
        if (label == 'happy' && emo[top] > 0.6) slangs.add('Radiant ☀️');
        if (label == 'angry' && emo[top] > 0.5) slangs.add('Menacing Aura 👹');
        if (label == 'surprise' && emo[top] > 0.5) slangs.add('Plot Twist 😲');
      }
    }

    // ---- Posture & pose (ML Kit pose) ----------------------------------
    final pose = f.pose;
    if (pose != null && pose.isConfidentPerson) {
      if (pose.shoulderTiltDeg != null) {
        final q = _gauss(pose.shoulderTiltDeg!, 0, 7);
        s.add(
          'posture',
          'Shoulder Line',
          '${pose.shoulderTiltDeg!.toStringAsFixed(1)}° tilt',
          4000000,
          q,
          'Level, open shoulders.',
        );
        metrics['Shoulder Tilt'] = pose.shoulderTiltDeg!;
      }
      if (pose.spineTiltDeg != null) {
        final q = _gauss(pose.spineTiltDeg!, 0, 12);
        s.add(
          'posture',
          'Spine Alignment',
          '${pose.spineTiltDeg!.toStringAsFixed(1)}° lean',
          5000000,
          q,
          'Upright torso from shoulders to hips.',
        );
        metrics['Spine Tilt'] = pose.spineTiltDeg!;
      }
      if (pose.headOffset != null) {
        final q = _gauss(pose.headOffset!, 0, 0.25);
        s.add(
          'posture',
          'Head Alignment',
          pose.headOffset!.toStringAsFixed(2),
          3000000,
          q,
          'Head centred over the shoulders.',
        );
      }
      final double postureQ = s.quality('posture');
      if (postureQ > 0.85) slangs.add('Dominant Posture 🕴️');
      if (postureQ < 0.45 && s.has('posture')) slangs.add('Gamer Posture 🦐');

      s.add(
        'pose',
        'Pose Energy',
        '${(pose.energy * 100).toStringAsFixed(0)}%',
        5000000,
        0.35 + 0.65 * pose.energy,
        'Raised arms, bent limbs, stance and lean make a pose dynamic.',
      );
      s.add(
        'pose',
        'Body Visibility',
        '${pose.visibleLandmarks}/33 points',
        3000000,
        min(1.0, pose.visibility * 1.3),
        'How much of your body the pose model can see.',
      );
      if (pose.energy >= 0.5) slangs.add('Dynamic ⚡');
    }

    // ---- Body & shape (ML Kit subject segmentation) -----------------------
    String bodyShape = 'Portrait Mode 📸';
    final sil = f.silhouette;
    if (sil != null && sil.coverage > 0.01) {
      final s2w = sil.shoulderToWaist, h2w = sil.hipToWaist;
      if (s2w != null && h2w != null) {
        final double definition = max(s2w, h2w);
        final q = 1 / (1 + exp(-(definition - 1.2) * 9));
        s.add(
          'body',
          'Shape Definition',
          '${definition.toStringAsFixed(2)}x',
          5000000,
          q,
          'Taper from shoulders or hips to the waist, measured on your silhouette.',
        );
        metrics['Shoulder-to-Waist'] = s2w;
        metrics['Hip-to-Waist'] = h2w;
        bodyShape = _shapeName(sil);
        slangs.add(bodyShape);
      }
      s.add(
        'body',
        'Subject Separation',
        '${(sil.crispness * 100).toStringAsFixed(0)}%',
        3000000,
        sil.crispness,
        'How cleanly you stand out from the background.',
      );
      s.add(
        'body',
        'Frame Coverage',
        '${(sil.coverage * 100).toStringAsFixed(0)}%',
        2000000,
        _gauss(sil.coverage, 0.35, 0.2),
        'How much of the frame you fill.',
      );
    }

    // ---- Style (ML Kit image labels + colour) ----------------------------
    double fashion = 0, scene = 0;
    final seen = <String>[], scenes = <String>[];
    final uniqueLabels = <String, double>{};
    for (final l in f.labels) {
      if (!l.confidence.isFinite || l.confidence < 0.55) continue;
      final name = l.label.trim().toLowerCase();
      uniqueLabels[name] = max(
        uniqueLabels[name] ?? 0,
        l.confidence.clamp(0.0, 1.0),
      );
    }
    final orderedLabels = uniqueLabels.keys.toList()..sort();
    for (final name in orderedLabels) {
      if (_fashionLabels.contains(name)) {
        fashion += uniqueLabels[name]!;
        seen.add(name);
      } else if (_sceneLabels.contains(name)) {
        scene += uniqueLabels[name]!;
        scenes.add(name);
      }
      if (name == 'sunglasses') slangs.add('Shades On 😎');
      if (name == 'sunset' || name == 'sky') slangs.add('Golden Hour ✨');
      if (name == 'beard') slangs.add('Majestic Beard 🧔');
    }
    s.add(
      'style',
      'Fashion & Accessories',
      seen.isEmpty ? 'None spotted' : seen.take(3).join(', '),
      4000000,
      0.25 + 0.75 * (1 - exp(-fashion / 1.2)),
      'Outfit and accessories recognised by the image labeling model.',
    );
    s.add(
      'style',
      'Scene & Vibe',
      scenes.isEmpty ? 'Plain' : scenes.take(3).join(', '),
      2000000,
      0.3 + 0.7 * (1 - exp(-scene)),
      'Backdrop and setting recognised in the photo.',
    );
    s.add(
      'style',
      'Colour Vibrance',
      '${(f.pixels.saturation * 100).toStringAsFixed(0)}%',
      2000000,
      _gauss(f.pixels.saturation, 0.35, 0.18),
      'Balanced, lively colour.',
    );
    if (s.quality('style') >= 0.72) slangs.add('Style Icon ✨');
    if (f.isArt) {
      s.add(
        'style',
        '2D Aesthetic',
        'Illustration',
        4000000,
        0.8,
        'Recognised as illustrated art.',
      );
      slangs.add('Anime Aesthetic ✨');
      slangs.add('Digital Masterpiece 🎨');
      bodyShape = 'Artistic Form 🎨';
    }

    // ---- Lighting & composition (pixels) ----------------------------------
    final px = f.pixels;
    final double clip = (px.shadowClip + px.highlightClip).clamp(0.0, 1.0);
    final double exposureQ =
        _gauss(px.meanLuma, 125, 45) * (1 - min(1.0, clip * 2));
    s.add(
      'image',
      'Exposure',
      'luma ${px.meanLuma.toStringAsFixed(0)}',
      5000000,
      exposureQ,
      'Brightness without crushed shadows or blown highlights.',
    );
    s.add(
      'image',
      'Contrast',
      px.lumaStdDev.toStringAsFixed(0),
      3000000,
      _gauss(px.lumaStdDev, 60, 25),
      'Tonal depth between lights and darks.',
    );
    final double sharpQ = 1 - exp(-px.sharpness / 150);
    s.add(
      'image',
      'Sharpness',
      px.sharpness.toStringAsFixed(0),
      4000000,
      sharpQ,
      'Focus on the subject.',
    );
    final (double cx, double cy)? subject = face != null
        ? (face.centerX, face.centerY)
        : null;
    if (subject != null) {
      final (x, y) = subject;
      final double horizontal = max(
        _gauss(x, 0.5, 0.12),
        _gauss((x - 0.5).abs(), 1 / 6, 0.07),
      );
      final q = horizontal * _gauss(y, 0.38, 0.16);
      s.add(
        'image',
        'Framing',
        'x ${(x * 100).round()}%, y ${(y * 100).round()}%',
        4000000,
        q,
        'Face placed on the centre line or rule-of-thirds with good headroom.',
      );
    }
    if (exposureQ > 0.85 && sharpQ > 0.8) slangs.add('Studio Lighting 💡');
    if (sharpQ > 0.9) slangs.add('Crisp 🎥');

    // ---- Presence ----------------------------------------------------------
    if (face != null) {
      s.add(
        'presence',
        'Subject Prominence',
        '${(face.sizeFraction * 100).toStringAsFixed(1)}% of frame',
        3000000,
        min(1.0, sqrt(face.sizeFraction / 0.06)),
        'How strongly you command the frame.',
      );
    } else if (pose?.bodyHeightFraction != null) {
      s.add(
        'presence',
        'Subject Prominence',
        '${(pose!.bodyHeightFraction! * 100).toStringAsFixed(0)}% of height',
        3000000,
        min(1.0, pose.bodyHeightFraction! / 0.6),
        'How strongly you command the frame.',
      );
    }
    final double detection = face != null
        ? (1 - face.turn * 0.5)
        : (pose?.coreConfidence ?? 0.5);
    s.add(
      'presence',
      'Detection Confidence',
      '${(detection * 100).toStringAsFixed(0)}%',
      3000000,
      detection,
      'How unmistakably the models see a person.',
    );
    if (f.faceCount > 1) slangs.add('Squad Aura 👥');

    // ---- Content (measured for reference, no points) ----------------------
    final contentComponents = <ScoreComponent>[];
    if (f.nsfw != null) {
      final String verdict = f.nsfw! >= 0.85
          ? 'Explicit'
          : (f.nsfw! >= 0.6 ? 'Suggestive' : 'Safe');
      contentComponents.add(
        ScoreComponent(
          'Content Check (AI)',
          verdict,
          0,
          'Checked by the on-device content model for reference; it does not change the score.',
        ),
      );
      metrics['Explicit Content'] = f.nsfw!;
    }

    // ---- Totals -----------------------------------------------------------
    final framing = face == null
        ? (pose?.isConfidentPerson == true
              ? min(1.0, (pose!.bodyHeightFraction ?? 0) / 0.65)
              : 0.0)
        : max(
                _gauss(face.centerX, 0.5, 0.12),
                _gauss((face.centerX - 0.5).abs(), 1 / 6, 0.07),
              ) *
              _gauss(face.centerY, 0.38, 0.16);
    final calibration = ScoreCalibration.evaluate(
      pixels: px,
      quality: s.overallQuality,
      categories: {for (final key in s.keys) key: s.quality(key)},
      componentCount: s.componentCount,
      clearPerson:
          !f.isArt &&
          (face != null
              ? face.sizeFraction >= 0.015
              : pose?.isConfidentPerson == true &&
                    (pose?.coreConfidence ?? 0) >= 0.8),
      framing: framing,
    );
    final total = s.finish(calibration.points);
    metrics.addAll({
      'Score Ceiling': calibration.ceiling.toDouble(),
      'Overall Quality': s.overallQuality,
      'Frame Luma': px.meanLuma,
      'Subject Luma': px.subjectLuma ?? px.meanLuma,
      'Sharpness': px.sharpness,
      'Clipped Pixels': clip,
    });
    if (slangs.isEmpty) slangs.add('Main-character energy 💫');

    return DetailedAuraScore(
      overallPoints: total,
      scoringVersion: scoringVersion,
      qualityChecks: calibration.checks,
      isBodyOnly: face == null,
      face: s.dimension('face', ['Symmetrical Features 📐']),
      eyes: s.dimension('eyes', ['Piercing Gaze 🦅']),
      expression: s.dimension('expression', [
        if (face?.smile != null && face!.smile! > 0.6)
          'Charming Smile ✨'
        else
          'Composed 🧊',
      ]),
      body: s.dimension('body', [bodyShape]) ?? DimensionScore(0, 0, []),
      posture:
          s.dimension('posture', ['Strong posture 👑']) ??
          DimensionScore(0, 0, []),
      pose: s.dimension('pose', ['Dynamic ⚡']) ?? DimensionScore(0, 0, []),
      style:
          s.dimension('style', ['Serving looks 💅']) ??
          DimensionScore(0, 0, []),
      image:
          s.dimension('image', [
            s.quality('image') >= 0.8 ? 'Crisp capture 📸' : 'Room to shine 📸',
          ]) ??
          DimensionScore(0, 0, []),
      presence:
          s.dimension('presence', ['Main-character energy 💫']) ??
          DimensionScore(0, 0, []),
      content: DimensionScore(
        0,
        f.nsfw ?? 0,
        const [],
        components: contentComponents,
      ),
      bodyShape: bodyShape,
      bodyShapeConfidence: sil?.crispness ?? 0,
      allSlangs: slangs.toSet().toList(),
      rawMetrics: metrics.map(
        (k, v) => MapEntry(k, double.parse(v.toStringAsFixed(3))),
      ),
    );
  }

  static String _shapeName(SilhouetteMetrics sil) {
    final ratio = sil.shoulderToWaist ?? 1;
    if (ratio >= 1.35) return 'Athletic Energy ⚡';
    return 'Standout Silhouette ✨';
  }

  static double _gauss(double x, double mu, double sigma) =>
      exp(-0.5 * pow((x - mu) / sigma, 2));

  /// Pulls a quality towards neutral (0.5) when the measurement is unreliable.
  static double _shrink(double q, double confidence) =>
      0.5 + (q - 0.5) * confidence;

  static const Set<String> _fashionLabels = {
    'sunglasses',
    'glasses',
    'hat',
    'cap',
    'jacket',
    'coat',
    'suit',
    'tie',
    'dress',
    'scarf',
    'jewellery',
    'jewelry',
    'necklace',
    'earring',
    'bracelet',
    'watch',
    'bag',
    'handbag',
    'denim',
    'jeans',
    'leather',
    'fashion',
    'shoe',
    'sneakers',
    'boot',
    'lipstick',
    'eyelash',
    'tattoo',
    'beard',
    'moustache',
    'hairstyle',
  };

  static const Set<String> _sceneLabels = {
    'sky',
    'sunset',
    'beach',
    'sea',
    'lake',
    'mountain',
    'flower',
    'garden',
    'nature',
    'forest',
    'city',
    'skyscraper',
    'architecture',
    'night',
    'neon',
    'stage',
    'concert',
    'party',
    'car',
    'motorcycle',
    'building',
    'bridge',
    'snow',
    'desert',
    'waterfall',
    'cool',
    'fun',
    'event',
  };
}

/// Collects scored components per category and turns them into points.
class _Sheet {
  final Map<String, List<_Item>> _items = {};
  final Map<String, DimensionScore> _dims = {};

  void add(
    String dim,
    String name,
    String measurement,
    double budget,
    double quality,
    String description,
  ) {
    (_items[dim] ??= []).add(
      _Item(
        name,
        measurement,
        budget,
        quality.isFinite ? quality.clamp(0.0, 1.0) : 0,
        description,
      ),
    );
  }

  bool has(String dim) => _items[dim]?.isNotEmpty ?? false;

  double quality(String dim) {
    final items = _items[dim];
    if (items == null || items.isEmpty) return 0;
    double q = 0, b = 0;
    for (final i in items) {
      q += i.quality * i.budget;
      b += i.budget;
    }
    return q / b;
  }

  Iterable<String> get keys => _items.keys;
  int get componentCount => _items.values.expand((v) => v).length;
  double get overallQuality {
    final items = _items.values.expand((v) => v);
    final budget = items.fold(0.0, (sum, i) => sum + i.budget);
    return budget == 0
        ? 0
        : items.fold(0.0, (sum, i) => sum + i.budget * i.quality) / budget;
  }

  /// Allocate calibrated points using largest remainders. Every component is
  /// nonnegative and the full breakdown adds up exactly, even at low scores.
  int finish(int total) {
    final items = _items.values.expand((v) => v).toList();
    final weight = items.fold(0.0, (sum, i) => sum + i.budget * i.quality);
    final shares = [
      for (final i in items)
        weight == 0
            ? total / items.length
            : total * i.budget * i.quality / weight,
    ];
    final points = shares.map((v) => v.floor()).toList();
    final remainder = total - points.fold(0, (sum, v) => sum + v);
    final order = List.generate(items.length, (i) => i)
      ..sort((a, b) {
        final delta = (shares[b] - points[b]).compareTo(shares[a] - points[a]);
        return delta == 0 ? a.compareTo(b) : delta;
      });
    for (int i = 0; i < remainder; i++) {
      points[order[i % order.length]]++;
    }
    int index = 0;
    for (final entry in _items.entries) {
      final comps = <ScoreComponent>[];
      for (final item in entry.value) {
        comps.add(
          ScoreComponent(
            item.name,
            item.measurement,
            points[index++],
            item.description,
          ),
        );
      }
      _dims[entry.key] = DimensionScore(
        comps.fold(0, (sum, c) => sum + c.scoreImpact),
        quality(entry.key),
        const [],
        components: comps,
      );
    }
    return total;
  }

  DimensionScore? dimension(String dim, List<String> traits) {
    final d = _dims[dim];
    if (d == null) return null;
    return DimensionScore(
      d.score,
      d.confidence,
      traits,
      components: d.components,
    );
  }
}

class _Item {
  _Item(
    this.name,
    this.measurement,
    this.budget,
    this.quality,
    this.description,
  );
  final String name;
  final String measurement;
  final double budget;
  final double quality;
  final String description;
}
