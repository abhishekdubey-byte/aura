import 'package:aura/services/upload_manager.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:aura/theme/aura_theme.dart';

import 'package:aura/main.dart' as app;
import 'package:aura/aura/aura_photo_composer.dart';
import 'package:aura/aura_calculator.dart';
import 'package:aura/services/photo_processor.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  // Device camera/export tests must not upload real scene photos.
  UploadManager.instance.suspendForTesting = true;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('side mode order, person icon and return to Normal', (
    tester,
  ) async {
    app.cameras = await availableCameras();
    await tester.pumpWidget(
      MaterialApp(theme: AuraTheme.dark, home: const app.CameraScreen()),
    );
    final layout = find.byKey(const ValueKey('normal-layout-button'));
    for (int i = 0; i < 100 && layout.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(layout, findsOneWidget);
    final boomerang = find.byKey(const ValueKey('mode-boomerang'));
    final aura = find.byKey(const ValueKey('mode-aura'));
    expect(
      tester.getTopLeft(boomerang).dy,
      greaterThan(tester.getTopLeft(layout).dy),
    );
    expect(
      tester.getTopLeft(aura).dy,
      greaterThan(tester.getTopLeft(boomerang).dy),
    );
    expect(
      find.descendant(of: aura, matching: find.byIcon(Icons.person_rounded)),
      findsOneWidget,
    );
    await tester.tap(boomerang);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('BOOMERANG'), findsOneWidget);
    expect(tester.widget<IconButton>(layout).onPressed, isNull);
    await tester.tap(aura);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AURA'), findsOneWidget);
    expect(find.byTooltip('AURA — tap for Normal'), findsOneWidget);
    await tester.tap(aura);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('NORMAL'), findsOneWidget);
    expect(tester.widget<IconButton>(layout).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('native full-screen crop and original-resolution export', (
    tester,
  ) async {
    final dir = await Directory(
      '${(await getTemporaryDirectory()).path}/aura_workflow_test',
    ).create();
    try {
      final photo = img.Image(width: 1200, height: 1600);
      img.fill(photo, color: img.ColorRgb8(20, 50, 180));
      img.fillRect(
        photo,
        x1: 0,
        y1: 0,
        x2: 599,
        y2: 1599,
        color: img.ColorRgb8(200, 30, 20),
      );
      final source = File('${dir.path}/source.png');
      await source.writeAsBytes(img.encodePng(photo));
      final path = await PhotoProcessor.process(
        source.path,
        mirror: true,
        aspect: 0.5,
      );
      final cropped = img.decodeImage(await File(path).readAsBytes())!;
      expect(cropped.width, 800);
      expect(cropped.height, 1600);
      expect(cropped.getPixel(30, 800).b, greaterThan(150));
      expect(cropped.getPixel(770, 800).r, greaterThan(150));
      final output = await AuraPhotoComposer.compose(
        imagePath: path,
        score: 87654321,
        slang: 'Main-character energy 💫',
        subjectRegions: [const Rect.fromLTWH(0, 0, 800, 1600)],
      );
      final edited = img.decodeImage(await File(output).readAsBytes())!;
      expect(edited.width, 800);
      expect(edited.height, greaterThan(1600));
      // Compare to the platform decoder used by the compositor. JPEG chroma
      // interpolation at a sharp edge differs from the pure-Dart decoder.
      final codec = await ui.instantiateImageCodec(
        await File(path).readAsBytes(),
      );
      final frame = (await codec.getNextFrame()).image;
      final rgba = (await frame.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      final offset = (800 * frame.width + 400) * 4;
      final after = edited.getPixel(400, 800);
      expect(
        [after.r, after.g, after.b],
        [rgba[offset], rgba[offset + 1], rgba[offset + 2]],
      );
      frame.dispose();
      codec.dispose();
      await tester.pumpWidget(
        MaterialApp(home: Image.file(File(output), fit: BoxFit.contain)),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await File(path).delete();
      await File(output).delete();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  testWidgets(
    'real detectors reject a blank image and serialize concurrent requests',
    (tester) async {
      final file = File(
        '${(await getTemporaryDirectory()).path}/aura_blank_test.jpg',
      );
      await file.writeAsBytes(
        img.encodeJpg(img.Image(width: 600, height: 800)),
      );
      try {
        final results = await Future.wait([
          AuraCalculatorService.instance.calculateAura(file.path),
          AuraCalculatorService.instance.calculateAura(file.path),
        ]);
        for (final result in results) {
          expect(result.hasHuman, isFalse);
          expect(result.error, isNull);
          expect(result.score, 0);
          expect(result.imageWidth, 600);
          expect(result.imageHeight, 800);
        }
      } finally {
        await file.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
