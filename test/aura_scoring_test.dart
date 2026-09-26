import 'dart:convert';
import 'dart:io';

import 'package:aura/aura/face_analysis.dart';
import 'package:aura/aura/pixel_analysis.dart';
import 'package:aura/aura/pose_analysis.dart';
import 'package:aura/aura/score_memory.dart';
import 'package:aura/aura/silhouette_analysis.dart';
import 'package:aura/models/detailed_aura_score.dart';
import 'package:aura/models/slang_style.dart';
import 'package:aura/scorers/aura_engine.dart';
import 'package:aura/scorers/score_calibration.dart';
import 'package:aura/screens/settings_screen.dart';
import 'package:aura/theme/aura_theme.dart';
import 'package:aura/widgets/slang_style_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PixelMetrics pixels({
  double luma = 125,
  double sharpness = 600,
  double shadow = 0.01,
  double highlight = 0.01,
  double contrast = 60,
  double? subjectLuma,
}) => PixelMetrics(
  meanLuma: luma,
  lumaStdDev: contrast,
  shadowClip: shadow,
  highlightClip: highlight,
  saturation: 0.35,
  sharpness: sharpness,
  subjectLuma: subjectLuma ?? luma,
);

AuraFeatures features({
  PixelMetrics? px,
  bool fullBody = true,
  bool face = true,
  double? nsfw,
  bool art = false,
  List<LabelFinding>? labels,
}) => AuraFeatures(
  face: !face
      ? null
      : FaceMetrics(
          box: (left: 100, top: 100, width: 100, height: 120),
          sizeFraction: 0.08,
          centerX: 0.5,
          centerY: 0.38,
          yaw: 0,
          pitch: 0,
          roll: 0,
          eyesOpen: 1,
          smile: 0,
          asymmetry: 0.01,
          thirds: [0.2, 0.38, 0.42],
          eyeSpacing: 0.46,
          lengthRatio: 1.25,
          jawRatio: 0.72,
        ),
  faceCount: face ? 1 : 0,
  pose: !fullBody
      ? null
      : PoseMetrics(
          visibleLandmarks: 33,
          coreConfidence: 0.98,
          isConfidentPerson: true,
          hasTorso: true,
          shoulderTiltDeg: 2,
          spineTiltDeg: 3,
          headOffset: 0.04,
          energy: 0.8,
          bodyHeightFraction: 0.8,
        ),
  silhouette: !fullBody
      ? null
      : SilhouetteMetrics(
          coverage: 0.35,
          crispness: 0.98,
          shoulderWidth: 145,
          waistWidth: 100,
          hipWidth: 130,
        ),
  pixels: px ?? pixels(),
  labels:
      labels ??
      const [
        LabelFinding('Jacket', 0.95),
        LabelFinding('Hat', 0.95),
        LabelFinding('Necklace', 0.95),
        LabelFinding('Garden', 0.95),
        LabelFinding('Flower', 0.95),
      ],
  emotions: const [0, 0, 0, 0, 0, 0, 1],
  nsfw: nsfw,
  isArt: art,
);

Iterable<DimensionScore> dimensions(DetailedAuraScore score) => [
  score.face,
  score.eyes,
  score.expression,
  score.body,
  score.posture,
  score.pose,
  score.style,
  score.image,
  score.presence,
  score.content,
].whereType<DimensionScore>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = AuraEngine();

  test('neutral source wording and explicit masculine/feminine titles', () {
    final score = engine.calculateScore(features());
    expect(score.allSlangs, contains('Ice Cool 🧊'));
    expect(
      score.allSlangs.join(' '),
      isNot(matches(RegExp(r'Queen|King|Goddess|Waifu|Chad'))),
    );
    expect(SlangStyle.masculine.format('Ice Cool 🧊'), 'Ice King 🧊');
    expect(SlangStyle.feminine.format('Ice Cool 🧊'), 'Ice Queen 🧊');
    expect(SlangStyle.neutral.format('Ice Cool 🧊'), 'Ice Cool 🧊');
    expect(SlangStyle.fromStored(null), SlangStyle.neutral);
    expect(SlangStyle.fromStored('unknown'), SlangStyle.neutral);
    for (final style in SlangStyle.values) {
      final before = jsonEncode(score.toJson());
      score.allSlangs.map(style.format).toList();
      expect(jsonEncode(score.toJson()), before);
    }
  });

  test('exceptional full-body photos and selfies can exceed ten million', () {
    for (final fullBody in [false, true]) {
      final score = engine.calculateScore(features(fullBody: fullBody));
      expect(
        score.qualityChecks.every((c) => c.passed),
        isTrue,
        reason: score.qualityChecks
            .where((c) => !c.passed)
            .map((c) => c.name)
            .join(', '),
      );
      expect(score.overallPoints, greaterThan(10000000));
      expect(score.overallPoints, lessThanOrEqualTo(AuraEngine.maxScore));
    }
  });

  for (final luma in [5.0, 20.0, 40.0, 64.0, 79.0, 220.0, 250.0]) {
    test(
      'poor exposure $luma stays below one million despite ideal features',
      () {
        final score = engine.calculateScore(features(px: pixels(luma: luma)));
        expect(score.overallPoints, lessThan(1000000));
        if (luma < 35 || luma > 235) {
          expect(score.overallPoints, lessThan(10000));
        }
      },
    );
  }

  test('dark face in bright scene and bright face in dark scene cannot bypass gates', () {
    for (final px in [
      pixels(luma: 125, subjectLuma: 20),
      pixels(luma: 30, subjectLuma: 125),
    ]) {
      expect(
        engine.calculateScore(features(px: px)).overallPoints,
        lessThan(1000000),
      );
    }
  });

  test(
    'blur, clipped highlights, crushed shadows and flat images block millions',
    () {
      for (final px in [
        pixels(sharpness: 15),
        pixels(sharpness: 80),
        pixels(shadow: 0.4),
        pixels(highlight: 0.4),
        pixels(contrast: 10),
      ]) {
        expect(
          engine.calculateScore(features(px: px)).overallPoints,
          lessThan(1000000),
        );
      }
    },
  );

  test('several strong categories cannot bypass a failed million gate', () {
    final score = engine.calculateScore(features(px: pixels(sharpness: 90)));
    expect(
      score.qualityChecks
          .where((c) => c.milestone == 1000000 && !c.passed)
          .map((c) => c.name),
      contains('Focus'),
    );
    expect(score.overallPoints, lessThan(1000000));
  });

  test('ten-million gate applies even when basic quality checks pass', () {
    final score = engine.calculateScore(features(px: pixels(sharpness: 200)));
    expect(
      score.qualityChecks
          .where((c) => c.milestone == 1000000)
          .every((c) => c.passed),
      isTrue,
    );
    expect(score.overallPoints, lessThan(10000000));
  });

  test(
    'missing detections and art do not inherit unmeasured high-tier points',
    () {
      final score = engine.calculateScore(
        features(face: false, fullBody: false, art: true),
      );
      expect(score.overallPoints, lessThan(1000000));
      expect(
        score.qualityChecks.firstWhere((c) => c.name == 'Clear person').passed,
        isFalse,
      );
    },
  );

  test(
    'steep progression allows huge scores without a huge ordinary baseline',
    () {
      int evaluate(double q) => ScoreCalibration.evaluate(
        pixels: pixels(),
        quality: q,
        categories: {
          for (final key in [
            'face',
            'eyes',
            'pose',
            'style',
            'image',
            'presence',
          ])
            key: q,
        },
        componentCount: 20,
        clearPerson: true,
        framing: 1,
      ).points;
      expect(evaluate(0.5), lessThan(10000));
      expect(evaluate(0.7), lessThan(1000000));
      expect(evaluate(0.9), greaterThan(10000000));
      expect(evaluate(0.99), greaterThan(80000000));
      expect(evaluate(1), AuraEngine.maxScore);
    },
  );

  test(
    'repeated, reordered and uncertain labels cannot inflate style points',
    () {
      const jacket = LabelFinding('Jacket', 0.95);
      const garden = LabelFinding('Garden', 0.9);
      final original = engine.calculateScore(
        features(labels: [jacket, garden]),
      );
      final repeated = engine.calculateScore(
        features(
          labels: [
            garden,
            jacket,
            jacket,
            const LabelFinding('jacket', 0.8),
            const LabelFinding('Necklace', 0.1),
            const LabelFinding('Sunglasses', double.nan),
          ],
        ),
      );
      expect(repeated.toJson(), original.toJson());
    },
  );

  test('explicit-content model has no effect on points', () {
    final safe = engine.calculateScore(features(nsfw: 0));
    final explicit = engine.calculateScore(features(nsfw: 1));
    expect(safe.overallPoints, explicit.overallPoints);
    expect(explicit.content.score, 0);
    expect(explicit.content.components.single.scoreImpact, 0);
  });

  test(
    'deterministic breakdown stays nonnegative and sums at all lighting levels',
    () {
      for (int luma = 0; luma <= 255; luma += 5) {
        final input = features(px: pixels(luma: luma.toDouble()));
        final score = engine.calculateScore(input);
        expect(engine.calculateScore(input).toJson(), score.toJson());
        final components = dimensions(score).expand((d) => d.components);
        expect(components.every((c) => c.scoreImpact >= 0), isTrue);
        expect(
          components.fold<int>(0, (sum, c) => sum + c.scoreImpact),
          score.overallPoints,
        );
        expect(
          DetailedAuraScore.fromJson(score.toJson()).toJson(),
          score.toJson(),
        );
      }
    },
  );

  AuraVisualSignature signature(String id) =>
      AuraVisualSignature(id, 0.5, List.filled(300, 100), null, 1, {'jacket'});

  test(
    'legacy cached scores are ignored while current scores survive a restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('aura_score_version_');
      try {
        final file = File('${dir.path}/scores.json');
        final score = engine.calculateScore(features());
        final legacy = score.toJson()..remove('scoringVersion');
        await file.writeAsString(
          jsonEncode([
            {'signature': signature('same').toJson(), 'score': legacy},
          ]),
        );
        final memory = AuraScoreMemory(fileOverride: file);
        expect(await memory.find(signature('same')), isNull);
        await memory.remember(signature('same'), score);
        expect(
          (await AuraScoreMemory(fileOverride: file).find(signature('same')))!
              .toJson(),
          score.toJson(),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'similar thumbnails cannot reuse a high score after quality drops',
    () async {
      final dir = await Directory.systemTemp.createTemp('aura_quality_cache_');
      try {
        final memory = AuraScoreMemory(
          fileOverride: File('${dir.path}/scores.json'),
        );
        final score = engine.calculateScore(features());
        await memory.remember(signature('original'), score);
        expect(
          await memory.find(
            signature('noise'),
            currentScore: engine.calculateScore(
              features(px: pixels(luma: 127, sharpness: 610)),
            ),
          ),
          isNotNull,
        );
        for (final px in [
          pixels(luma: 40),
          pixels(sharpness: 60),
          pixels(sharpness: 280),
        ]) {
          expect(
            await memory.find(
              signature('similar'),
              currentScore: engine.calculateScore(features(px: px)),
            ),
            isNull,
          );
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'caption style is neutral by default and saves an explicit choice',
    (tester) async {
      SharedPreferences.setMockInitialValues({'gender': 'Female'});
      await tester.pumpWidget(
        MaterialApp(theme: AuraTheme.dark, home: const SettingsScreen()),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(SlangStylePicker), 200);
      expect(find.text('Neutral'), findsOneWidget);
      await tester.tap(find.text('Neutral'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Masculine').last);
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getString(
          SlangStyle.preferenceKey,
        ),
        'masculine',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
