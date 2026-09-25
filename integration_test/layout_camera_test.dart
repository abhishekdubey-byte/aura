import 'dart:io';

import 'package:aura/main.dart' as app;
import 'package:aura/camera/capture_aspect.dart';
import 'package:aura/layout/layout_camera_screen.dart';
import 'package:aura/layout/layout_draft.dart';
import 'package:aura/layout/layout_store.dart';
import 'package:aura/layout/layout_template.dart';
import 'package:aura/layout/layout_exporter.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Normal-only entry, photo/video/hybrid capture, retake and restore',
    (tester) async {
      Future<void> until(bool Function() condition, String message) async {
        for (int i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (condition()) return;
        }
        fail(message);
      }

      app.cameras = await availableCameras();
      expect(app.cameras, isNotEmpty);
      await tester.pumpWidget(
        MaterialApp(theme: ThemeData.dark(), home: const app.CameraScreen()),
      );
      await until(
        () => find
            .byKey(const ValueKey('normal-layout-button'))
            .evaluate()
            .isNotEmpty,
        'Normal camera did not open',
      );
      final flash = tester.getTopLeft(find.byIcon(Icons.flash_off));
      final layout = tester.getTopLeft(
        find.byKey(const ValueKey('normal-layout-button')),
      );
      expect(layout.dy, greaterThan(flash.dy));
      await tester.tap(find.text('Boomerang'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('normal-layout-button')), findsNothing);
      await tester.tap(find.text('Aura Calc'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('normal-layout-button')), findsNothing);
      await tester.tap(find.text('Normal'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('normal-layout-button')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));

      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/layout_camera_tests',
      );
      final store = LayoutStore(dir);
      await store.discard();
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: LayoutCameraScreen(
              cameras: app.cameras,
              aspect: CaptureAspect.standard,
              screen: const Size(1080, 2400),
              store: store,
            ),
          ),
        );
        await until(() {
          final shutter = find.byKey(const ValueKey('layout-shutter'));
          return shutter.evaluate().isNotEmpty &&
              tester.widget<IconButton>(shutter).onPressed != null;
        }, 'Layout camera did not initialize');
      }

      Future<void> idle() => until(
        () =>
            tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('layout-shutter')),
                )
                .onPressed !=
            null,
        'Capture did not finish',
      );
      Future<void> photo() async {
        await tester.tap(find.byKey(const ValueKey('layout-shutter')));
        await tester.pump(const Duration(milliseconds: 200));
        await idle();
      }

      await open();
      await photo();
      expect((await store.load())!.filled, 1);
      final original = (await store.load())!.media[0]!.path;
      await tester.tap(find.byKey(const ValueKey('layout-cell-0')));
      await tester.pump(const Duration(milliseconds: 200));
      await idle();
      await tester.tap(find.text('Retake'));
      await tester.pump();
      await photo();
      expect((await store.load())!.media[0]!.path, isNot(original));
      if (app.cameras.length > 1) {
        await tester.tap(find.byTooltip('Switch camera'));
        await tester.pump(const Duration(milliseconds: 200));
        await idle();
        await photo();
        expect(
          (await store.load())!.media[1]!.mirror,
          app.cameras[1].lensDirection == CameraLensDirection.front,
        );
      }

      await tester.tap(find.byKey(const ValueKey('layout-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hybrid'));
      await tester.tap(find.byKey(const ValueKey('template-rows')));
      await tester.tap(find.text('Use layout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await photo();
      await tester.tap(find.text('Video'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('layout-shutter')));
      await tester.pump(const Duration(seconds: 2));
      await idle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.stop), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('layout-shutter')));
      await tester.pump(const Duration(milliseconds: 200));
      await idle();
      final captured = (await store.load())!;
      expect(captured.complete, isTrue);
      expect(captured.media[0]!.kind, CellKind.photo);
      expect(captured.media[1]!.kind, CellKind.video);
      expect(captured.media[1]!.seconds, greaterThan(0));
      expect(captured.media[1]!.thumbnail, isNotNull);

      await tester.tap(find.byTooltip('Rotate composition'));
      await tester.pumpAndSettle();
      expect((await store.load())!.ratio, closeTo(4 / 3, .000001));
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
      ]);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect((await store.load())!.ratio, closeTo(4 / 3, .000001));
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await tester.pump(const Duration(seconds: 1));

      // Review actually decodes and plays the composed MP4. Return without writing
      // synthetic test captures to the user's gallery.
      await tester.tap(find.byKey(const ValueKey('layout-review')));
      await until(
        () =>
            find.text('Save layout').evaluate().isNotEmpty &&
            tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Save layout'),
                    )
                    .onPressed !=
                null,
        'Video review did not render',
      );
      await tester.tap(find.text('Edit cells'));
      await tester.pump(const Duration(seconds: 1));
      await idle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await open();
      expect((await store.load())!.complete, isTrue);
      await tester.tap(find.byTooltip('Clear cell'));
      await tester.pumpAndSettle();
      expect((await store.load())!.complete, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await store.discard();
      await SystemChrome.setPreferredOrientations([]);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
  testWidgets(
    'new desktop layouts capture hybrid cells, select final cell and review',
    (tester) async {
      final cameras = await availableCameras();
      Future<void> until(bool Function() ready, String message) async {
        for (int i = 0; i < 300; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (ready()) return;
        }
        fail(message);
      }

      Future<void> idle() => until(() {
        final shutter = find.byKey(const ValueKey('layout-shutter'));
        return shutter.evaluate().isNotEmpty &&
            tester.widget<IconButton>(shutter).onPressed != null;
      }, 'Layout capture did not finish');
      for (final template in [
        LayoutTemplate.diamondEight,
        LayoutTemplate.nineStrips,
        LayoutTemplate.sevenStrips,
      ]) {
        final store = LayoutStore(
          Directory(
            '${(await getTemporaryDirectory()).path}/layout_shape_test_${template.name}',
          ),
        );
        await store.discard();
        await store.save(
          LayoutDraft(
            template: template,
            mode: LayoutMode.hybrid,
            aspectId: CaptureAspect.desktop16x10.id,
            ratio: 1.6,
          ),
        );
        Future<void> open() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(),
              home: LayoutCameraScreen(
                cameras: cameras,
                aspect: CaptureAspect.desktop16x10,
                screen: const Size(1080, 2400),
                store: store,
              ),
            ),
          );
          await idle();
        }

        await open();
        final last = template.cells.length - 1;
        expect(find.byKey(ValueKey('layout-cell-$last')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('layout-shutter')));
        await tester.pump(const Duration(milliseconds: 200));
        await idle();
        final selector = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('layout-select-$last')),
          180,
          scrollable: selector,
        );
        await tester.tap(find.byKey(ValueKey('layout-select-$last')));
        await tester.pump(const Duration(milliseconds: 200));
        await idle();
        expect((await store.load())!.selected, last);
        await tester.tap(find.text('Video'));
        await tester.pumpAndSettle();
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
        ]);
        await tester.pump(const Duration(seconds: 1));
        await tester.ensureVisible(
          find.byKey(const ValueKey('layout-shutter')),
        );
        await tester.tap(find.byKey(const ValueKey('layout-shutter')));
        await tester.pump(const Duration(seconds: 2));
        await idle();
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byKey(const ValueKey('layout-shutter')));
        await tester.pump(const Duration(milliseconds: 200));
        await idle();
        var draft = (await store.load())!;
        expect(draft.media[0]!.kind, CellKind.photo);
        expect(draft.media[last]!.kind, CellKind.video);
        expect(draft.ratio, 1.6);
        // The export matrix verifies distinct media in every slot. Here we reuse
        // the two real captures to check full-resolution camera-to-review wiring.
        for (int i = 1; i < last; i++) {
          draft.put(i, i.isEven ? draft.media[0]! : draft.media[last]!);
        }
        await store.save(draft);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await open();
        await tester.ensureVisible(find.byKey(const ValueKey('layout-review')));
        await tester.tap(find.byKey(const ValueKey('layout-review')));
        await until(
          () =>
              find.text('Save layout').evaluate().isNotEmpty &&
              tester
                      .widget<FilledButton>(
                        find.widgetWithText(FilledButton, 'Save layout'),
                      )
                      .onPressed !=
                  null,
          'Review failed for ${template.name}',
        );
        debugPrint(
          'LAYOUT_CAMERA_PASS ${template.name} ${template.cells.length} cells, hybrid, landscape',
        );
        await tester.tap(find.text('Edit cells'));
        await tester.pump(const Duration(seconds: 1));
        await idle();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await store.discard();
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        await tester.pump(const Duration(seconds: 1));
      }
      await SystemChrome.setPreferredOrientations([]);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
  testWidgets('new video masks preserve motion and hold the last frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Layout motion verification')),
      ),
    );
    await tester.runAsync(() async {
      final dir = await Directory(
        '${(await getTemporaryDirectory()).path}/layout_motion_test',
      ).create(recursive: true);
      Future<void> execute(List<String> args) async {
        final session = await FFmpegKit.executeWithArguments(args);
        expect(
          ReturnCode.isSuccess(await session.getReturnCode()),
          isTrue,
          reason: await session.getLogsAsString(),
        );
      }

      final changing = '${dir.path}/changing.mp4';
      final long = '${dir.path}/long.mp4';
      final photo = '${dir.path}/photo.jpg';
      await execute([
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=red:s=96x128:r=30:d=0.2',
        '-f',
        'lavfi',
        '-i',
        'color=blue:s=96x128:r=30:d=0.2',
        '-filter_complex',
        '[0:v][1:v]concat=n=2:v=1:a=0[out]',
        '-map',
        '[out]',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        changing,
      ]);
      await execute([
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=gray:s=96x128:r=30:d=0.8',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        long,
      ]);
      await execute(['-y', '-i', long, '-frames:v', '1', photo]);
      final motion = await LayoutExporter.inspectVideo(changing);
      final longer = await LayoutExporter.inspectVideo(long);
      for (final template in [
        LayoutTemplate.diamondEight,
        LayoutTemplate.nineStrips,
        LayoutTemplate.sevenStrips,
      ]) {
        for (final mode in [LayoutMode.videos, LayoutMode.hybrid]) {
          final draft = LayoutDraft(template: template, mode: mode, ratio: 1.6);
          for (int i = 0; i < draft.media.length; i++) {
            draft.put(
              i,
              i == 0
                  ? motion
                  : i == 1 || mode == LayoutMode.videos
                  ? longer
                  : LayoutMedia(path: photo, kind: CellKind.photo),
            );
          }
          final output = await LayoutExporter.render(draft, longEdge: 480);
          for (final atEnd in [false, true]) {
            final frame = '${dir.path}/frame.jpg';
            await execute([
              '-y',
              '-ss',
              atEnd ? '0.65' : '0.05',
              '-i',
              output,
              '-frames:v',
              '1',
              '-q:v',
              '2',
              frame,
            ]);
            final decoded = img.decodeJpg(await File(frame).readAsBytes())!;
            final r = template
                .pixelRects(
                  Size(decoded.width.toDouble(), decoded.height.toDouble()),
                )
                .first;
            final pixel = decoded.getPixel(
              r.center.dx.floor(),
              r.center.dy.floor(),
            );
            expect(
              atEnd ? pixel.b : pixel.r,
              greaterThan(200),
              reason: '${template.name}/${mode.name}/$atEnd',
            );
            expect(
              atEnd ? pixel.r : pixel.b,
              lessThan(40),
              reason: '${template.name}/${mode.name}/$atEnd',
            );
          }
          await File(output).delete();
        }
      }
      await dir.delete(recursive: true);
      debugPrint(
        'LAYOUT_MOTION_PASS 6 exports retain motion and hold blue final frame',
      );
    });
  }, timeout: const Timeout(Duration(minutes: 4)));
}
