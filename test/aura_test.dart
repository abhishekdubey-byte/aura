import 'dart:io';

import 'package:aura/aura/aura_photo_composer.dart';
import 'package:aura/aura/pixel_analysis.dart';
import 'package:aura/aura/score_memory.dart';
import 'package:aura/aura/silhouette_analysis.dart';
import 'package:aura/aura/subject_regions.dart';
import 'package:aura/models/detailed_aura_score.dart';
import 'package:aura/scorers/aura_engine.dart';
import 'package:aura/services/photo_processor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

DetailedAuraScore score() => AuraEngine().calculateScore(
  AuraFeatures(
    face: null,
    faceCount: 0,
    pose: null,
    silhouette: null,
    pixels: PixelMetrics(
      meanLuma: 125,
      lumaStdDev: 60,
      shadowClip: 0,
      highlightClip: 0,
      saturation: 0.35,
      sharpness: 150,
    ),
    labels: [const LabelFinding('jacket', 0.9)],
    emotions: null,
    nsfw: null,
    isArt: true,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('aura_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await temp.delete(recursive: true);
  });

  test('caption fits above the head without intersecting the subject', () {
    const body = Rect.fromLTWH(200, 500, 600, 1500);
    final layout = AuraCaptionLayout.place(const Size(1000, 2000), [
      body,
    ], const Size(400, 200));
    expect(layout.outputSize, const Size(1000, 2000));
    expect(layout.rect.bottom, lessThan(body.top));
    expect(layout.rect.overlaps(body), isFalse);
  });

  test('caption fits beside a tall subject and avoids every person', () {
    const subject = Rect.fromLTWH(700, 0, 300, 1800);
    final layout = AuraCaptionLayout.place(const Size(1200, 1800), [
      subject,
    ], const Size(450, 200));
    expect(layout.outputSize, const Size(1200, 1800));
    expect(layout.rect.right, lessThan(subject.left));
    final group = AuraCaptionLayout.place(const Size(1200, 1800), [
      subject,
      const Rect.fromLTWH(0, 0, 700, 1800),
    ], const Size(450, 200));
    expect(group.rect.top, greaterThanOrEqualTo(1800));
  });

  test('crowded image uses a footer and retains all original pixels', () {
    final layout = AuraCaptionLayout.place(const Size(400, 800), [
      const Rect.fromLTWH(0, 0, 400, 800),
    ], const Size(180, 100));
    expect(layout.rect.top, greaterThanOrEqualTo(800));
    expect(layout.outputSize.width, 400);
    expect(layout.outputSize.height, greaterThan(800));
    expect(layout.rect.right, lessThan(layout.outputSize.width));
  });

  test(
    'segmentation uses independent x/y source scale and rejects bad masks',
    () {
      final mask = List<double>.filled(100, 0)
        ..[22] = 1
        ..[77] = 1;
      final regions = SubjectRegions.detect(
        faces: [],
        poses: [],
        width: 10,
        height: 10,
        sourceWidth: 100,
        sourceHeight: 200,
        mask: mask,
      );
      expect(regions.single.contains(const Offset(25, 50)), isTrue);
      expect(regions.single.contains(const Offset(75, 150)), isTrue);
      final unknown = SubjectRegions.detect(
        faces: [],
        poses: [],
        width: 10,
        height: 10,
        sourceWidth: 100,
        sourceHeight: 200,
        mask: [1],
      );
      expect(unknown.single, const Rect.fromLTWH(0, 0, 100, 200));
    },
  );

  test('odd-sized segmentation masks cannot exceed full coverage', () {
    final result = SilhouetteMetrics.fromMask(List.filled(9, 1), 3, 3, null);
    expect(result.coverage, 1);
    expect(result.crispness, 1);
  });

  AuraVisualSignature signature(
    String digest, {
    int color = 100,
    Set<String> labels = const {'jacket'},
    List<int>? colors,
    List<int>? face,
  }) => AuraVisualSignature(
    digest,
    0.5,
    colors ?? List.filled(300, color),
    face,
    1,
    labels,
  );

  test(
    'small capture noise matches; changed outfit, object or face does not',
    () {
      final original = signature('a');
      expect(original.matches(signature('b', color: 104)), isTrue);
      expect(original.matches(signature('c', color: 150)), isFalse);
      expect(
        original.matches(signature('d', labels: {'jacket', 'sunglasses'})),
        isFalse,
      );
      final localChange = List<int>.filled(300, 100);
      for (int i = 0; i < 12; i++) {
        localChange[i] = 200;
      }
      expect(original.matches(signature('e', colors: localChange)), isFalse);
      expect(
        signature(
          'f',
          face: List.filled(300, 100),
        ).matches(signature('g', face: List.filled(300, 160))),
        isFalse,
      );
    },
  );

  test(
    'exact photo wins despite label jitter and score memory survives restart',
    () async {
      final file = File('${temp.path}/memory.json');
      final first = AuraScoreMemory(fileOverride: file);
      final original = score();
      await first.remember(signature('exact'), original);
      final restored = await AuraScoreMemory(fileOverride: file)
          .find(signature('exact', labels: {}));
      expect(restored!.toJson(), original.toJson());
      final nearby = await AuraScoreMemory(fileOverride: file)
          .find(signature('nearby', color: 103));
      expect(nearby!.overallPoints, original.overallPoints);
      expect(await first.find(signature('new', labels: {'hat'})), isNull);
    },
  );

  test('stored breakdown remains deterministic and adds up to the total', () {
    final original = score();
    expect(score().overallPoints, original.overallPoints);
    final restored = DetailedAuraScore.fromJson(original.toJson());
    final dims = [
      restored.face,
      restored.eyes,
      restored.expression,
      restored.body,
      restored.pose,
      restored.posture,
      restored.style,
      restored.image,
      restored.presence,
      restored.content,
    ].whereType<DimensionScore>();
    expect(
      dims.fold<int>(
        0,
        (sum, d) =>
            sum + d.components.fold<int>(0, (s, c) => s + c.scoreImpact),
      ),
      restored.overallPoints,
    );
  });

  test(
    'full-screen capture crop matches requested ratio and mirrors only once',
    () async {
      final source = img.Image(width: 600, height: 800);
      img.fill(source, color: img.ColorRgb8(20, 30, 200));
      img.fillRect(
        source,
        x1: 0,
        y1: 0,
        x2: 299,
        y2: 799,
        color: img.ColorRgb8(220, 30, 20),
      );
      final input = File('${temp.path}/source.png');
      await input.writeAsBytes(img.encodePng(source));
      final output = await PhotoProcessor.process(
        input.path,
        mirror: true,
        aspect: 0.5,
      );
      final decoded = img.decodeImage(await File(output).readAsBytes())!;
      expect(decoded.width, 400);
      expect(decoded.height, 800);
      expect(decoded.getPixel(20, 400).b, greaterThan(150));
      expect(decoded.getPixel(380, 400).r, greaterThan(150));
    },
  );

  test(
    'export edits original resolution and preserves protected subject pixels',
    () async {
      final source = img.Image(width: 800, height: 1200);
      img.fill(source, color: img.ColorRgb8(40, 90, 130));
      final input = File('${temp.path}/source.png');
      await input.writeAsBytes(img.encodePng(source));
      final output = await AuraPhotoComposer.compose(
        imagePath: input.path,
        score: 12345678,
        slang: 'Main-character energy',
        subjectRegions: [const Rect.fromLTWH(0, 0, 800, 1200)],
      );
      final decoded = img.decodeImage(await File(output).readAsBytes())!;
      expect(decoded.width, 800);
      expect(decoded.height, greaterThan(1200));
      for (final point in [
        const Offset(0, 0),
        const Offset(400, 600),
        const Offset(799, 1199),
      ]) {
        final pixel = decoded.getPixel(point.dx.toInt(), point.dy.toInt());
        expect([pixel.r, pixel.g, pixel.b], [40, 90, 130]);
      }
      expect(await input.readAsBytes(), img.encodePng(source));
    },
  );
  test('export respects EXIF orientation before placing the score', () async {
    final source = img.Image(width: 120, height: 80);
    img.fill(source, color: img.ColorRgb8(210, 40, 25));
    source.exif.imageIfd.orientation = 6;
    final input = File('${temp.path}/rotated.jpg');
    await input.writeAsBytes(img.encodeJpg(source));
    final output = await AuraPhotoComposer.compose(
      imagePath: input.path,
      score: 12345678,
      slang: 'Looking good',
      subjectRegions: [const Rect.fromLTWH(0, 0, 80, 120)],
    );
    final decoded = img.decodeImage(await File(output).readAsBytes())!;
    expect(decoded.width, 80);
    expect(decoded.height, greaterThan(120));
    expect(decoded.getPixel(40, 60).r, greaterThan(180));
    int brightCaptionPixels = 0;
    for (int y = 120; y < decoded.height; y++) {
      for (int x = 0; x < decoded.width; x++) {
        if (decoded.getPixel(x, y).r > 220) brightCaptionPixels++;
      }
    }
    expect(brightCaptionPixels, greaterThan(0));
  });
}
