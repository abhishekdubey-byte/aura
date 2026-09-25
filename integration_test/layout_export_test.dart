import 'dart:io';

import 'package:aura/camera/capture_aspect.dart';
import 'package:aura/layout/layout_draft.dart';
import 'package:aura/layout/layout_exporter.dart';
import 'package:aura/layout/layout_template.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native export: every layout, ratio, orientation and media mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('AURA layout export tests'))),
      ),
    );
    await tester.runAsync(() async {
      FFmpegKitConfig.enableLogCallback((_) {});
      final dir = await Directory(
        '${(await getTemporaryDirectory()).path}/layout_native_tests',
      ).create(recursive: true);
      final photos = <LayoutMedia>[];
      final videos = <LayoutMedia>[];
      final colors = [
        [240, 20, 20],
        [20, 230, 20],
        [20, 20, 240],
        [240, 230, 20],
        [230, 20, 230],
        [20, 230, 230],
        [150, 150, 150],
        [240, 120, 20],
        [120, 50, 230],
      ];
      Future<void> execute(List<String> args) async {
        final session = await FFmpegKit.executeWithArguments(args);
        expect(
          ReturnCode.isSuccess(await session.getReturnCode()),
          isTrue,
          reason: await session.getLogsAsString(),
        );
      }

      for (int i = 0; i < colors.length; i++) {
        final source = img.Image(width: 96, height: 128);
        img.fill(
          source,
          color: img.ColorRgb8(colors[i][0], colors[i][1], colors[i][2]),
        );
        final photo = '${dir.path}/photo $i.jpg';
        final video = '${dir.path}/video $i.mp4';
        await File(photo).writeAsBytes(img.encodeJpg(source, quality: 100));
        photos.add(LayoutMedia(path: photo, kind: CellKind.photo));
        await execute([
          '-y',
          '-loop',
          '1',
          '-i',
          photo,
          if (i.isEven) ...['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo'],
          '-t',
          (0.2 + i / 30).toStringAsFixed(6),
          '-c:v',
          'libx264',
          '-preset',
          'ultrafast',
          '-pix_fmt',
          'yuv420p',
          '-r',
          '30',
          if (i.isEven) ...['-c:a', 'aac'] else '-an',
          video,
        ]);
        videos.add(await LayoutExporter.inspectVideo(video));
      }
      int count = 0;
      Future<void> check(
        LayoutTemplate template,
        CaptureAspect aspect,
        bool rotated,
        LayoutMode mode, {
        bool fullSize = false,
      }) async {
        final original = aspect.resolveRatio(const Size(1080, 2400));
        final draft = LayoutDraft(
          template: template,
          aspectId: aspect.id,
          ratio: rotated ? 1 / original : original,
          mode: mode,
        );
        for (int i = 0; i < draft.media.length; i++) {
          draft.put(
            i,
            mode == LayoutMode.photos || mode == LayoutMode.hybrid && i.isOdd
                ? photos[i]
                : videos[i],
          );
        }
        if (draft.isVideo) draft.audioCell = 0;
        final edge = fullSize ? (draft.isVideo ? 1920 : 2160) : 192;
        final expected = layoutOutputSize(draft.ratio, longEdge: edge);
        String output;
        if (draft.isVideo && !fullSize) {
          output = '${dir.path}/matrix.mp4';
          await execute(
            LayoutExporter.videoArguments(draft, output, longEdge: edge),
          );
        } else {
          output = await LayoutExporter.render(draft, longEdge: edge);
        }
        final label =
            '${template.name}/${aspect.id}/$rotated/${mode.name}/$edge';
        String frame = output;
        if (draft.isVideo) {
          final info = (await FFprobeKit.getMediaInformation(output))
              .getMediaInformation()!;
          final stream = info.getStreams().firstWhere(
            (s) => s.getType() == 'video',
          );
          expect(stream.getWidth(), expected.width.toInt(), reason: label);
          expect(stream.getHeight(), expected.height.toInt(), reason: label);
          expect(
            double.parse(info.getDuration()!),
            closeTo(draft.duration, .08),
            reason: label,
          );
          expect(
            info.getStreams().any((s) => s.getType() == 'audio'),
            isTrue,
            reason: label,
          );
          frame = '${dir.path}/frame.jpg';
          await execute([
            '-y',
            '-sseof',
            '-0.06',
            '-i',
            output,
            '-frames:v',
            '1',
            '-q:v',
            '2',
            frame,
          ]);
        }
        final decoded = img.decodeJpg(await File(frame).readAsBytes())!;
        expect(decoded.width, expected.width, reason: label);
        expect(decoded.height, expected.height, reason: label);
        final rects = template.pixelRects(expected);
        for (int i = 0; i < rects.length; i++) {
          final p = decoded.getPixel(
            rects[i].center.dx.floor(),
            rects[i].center.dy.floor(),
          );
          expect(p.r, closeTo(colors[i][0], 20), reason: '$label cell $i red');
          expect(
            p.g,
            closeTo(colors[i][1], 20),
            reason: '$label cell $i green',
          );
          expect(p.b, closeTo(colors[i][2], 20), reason: '$label cell $i blue');
        }
        if (template.isDiamond) {
          final r = rects.first;
          final cut = decoded.getPixel(
            (r.left + r.width * .12).floor(),
            (r.top + r.height * .12).floor(),
          );
          expect(cut.r, lessThan(25), reason: '$label diamond corner red');
          expect(cut.g, lessThan(25), reason: '$label diamond corner green');
          expect(cut.b, lessThan(25), reason: '$label diamond corner blue');
          expect(
            decoded.getPixel(1, 1).luminance,
            lessThan(10),
            reason: '$label black margin',
          );
        }
        await File(output).delete();
        count++;
        if (count % 12 == 0) debugPrint('LAYOUT_NATIVE_PASS $count ($label)');
      }

      for (final t in [
        LayoutTemplate.diamondEight,
        LayoutTemplate.nineStrips,
        LayoutTemplate.sevenStrips,
        ...LayoutTemplate.values.take(6),
      ]) {
        for (final aspect in CaptureAspect.values) {
          for (final rotated in [false, true]) {
            for (final mode in LayoutMode.values) {
              await check(t, aspect, rotated, mode);
            }
          }
        }
      }
      // Also exercise production resolution and the hardware encoder fallback.
      for (final t in LayoutTemplate.values) {
        for (final rotated in [false, true]) {
          for (final mode in LayoutMode.values) {
            await check(
              t,
              CaptureAspect.standard,
              rotated,
              mode,
              fullSize: true,
            );
          }
        }
      }
      for (final t in [
        LayoutTemplate.diamondEight,
        LayoutTemplate.nineStrips,
        LayoutTemplate.sevenStrips,
      ]) {
        for (final aspect in [
          CaptureAspect.desktop16x10,
          CaptureAspect.desktop21x9,
          CaptureAspect.stories,
          CaptureAspect.instagramPost,
          CaptureAspect.square,
        ]) {
          for (final rotated in [false, true]) {
            for (final mode in LayoutMode.values) {
              await check(t, aspect, rotated, mode, fullSize: true);
            }
          }
        }
      }
      expect(count, 792);
      await dir.delete(recursive: true);
      debugPrint('LAYOUT_NATIVE_COMPLETE $count verified exports');
    });
  }, timeout: const Timeout(Duration(minutes: 30)));
}
