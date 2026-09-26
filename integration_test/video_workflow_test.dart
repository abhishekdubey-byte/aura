import 'dart:io';

import 'package:aura/boomerang/boomerang_effect.dart';
import 'package:aura/services/video_processor.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'silent and mixed-audio video segments preserve the whole recording; all loop effects export',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Video export checks'))),
      );
      final dir = await Directory(
        '${(await getTemporaryDirectory()).path}/video_workflow',
      ).create();
      final outputs = <String>[];
      try {
        for (final audio in [false, true]) {
          final path = '${dir.path}/${audio ? 'audio' : 'silent'}.mp4';
          final session = await FFmpegKit.executeWithArguments([
            '-y',
            '-f',
            'lavfi',
            '-i',
            'testsrc=size=120x160:rate=30',
            if (audio) ...['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo'],
            '-t',
            '1',
            '-c:v',
            'libx264',
            '-preset',
            'ultrafast',
            '-pix_fmt',
            'yuv420p',
            if (audio) ...['-c:a', 'aac'] else '-an',
            path,
          ]);
          expect(ReturnCode.isSuccess(await session.getReturnCode()), isTrue);
        }
        final silent = '${dir.path}/silent.mp4',
            audible = '${dir.path}/audio.mp4';
        for (final withAudio in [false, true]) {
          final stitched = await VideoProcessor.stitch([
            (path: silent, mirror: false),
            (path: withAudio ? audible : silent, mirror: true),
          ]);
          expect(stitched, isNotNull);
          outputs.add(stitched!);
          final info = (await FFprobeKit.getMediaInformation(stitched))
              .getMediaInformation()!;
          expect(double.parse(info.getDuration()!), closeTo(2, 0.15));
          expect(
            info.getStreams().any((s) => s.getType() == 'audio'),
            withAudio,
          );
        }
        final frames = await VideoProcessor.extractFrames(
          silent,
          seconds: 1,
          mirror: false,
          width: 120,
        );
        expect(frames!.length, greaterThanOrEqualTo(28));
        for (final effect in BoomerangEffect.values) {
          final loop = await VideoProcessor.boomerang(
            silent,
            seconds: 1,
            mirror: true,
            frameCount: frames.length,
            effect: effect,
          );
          expect(loop, isNotNull, reason: effect.label);
          outputs.add(loop!);
          final info = (await FFprobeKit.getMediaInformation(loop))
              .getMediaInformation()!;
          expect(double.parse(info.getDuration()!), greaterThan(2));
          expect(info.getStreams().any((s) => s.getType() == 'audio'), isFalse);
        }
        await File(frames.first).parent.delete(recursive: true);
      } finally {
        for (final output in outputs) {
          await File(output).delete();
        }
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
