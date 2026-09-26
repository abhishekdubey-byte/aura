import 'dart:io';

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
    'reel joins mixed framing, front-camera mirroring and silent/audio clips at exact limits',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Synthetic reel export check')),
        ),
      );
      final dir = await Directory(
        '${(await getTemporaryDirectory()).path}/reel_export_checks',
      ).create();
      final outputs = <String>[];
      try {
        for (final audio in [false, true]) {
          final path = '${dir.path}/${audio ? 'audio' : 'silent'}.mp4';
          final result = await FFmpegKit.executeWithArguments([
            '-y',
            '-f',
            'lavfi',
            '-i',
            'testsrc=size=120x160:rate=30',
            if (audio) ...['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo'],
            '-t',
            '2',
            '-c:v',
            'libx264',
            '-preset',
            'ultrafast',
            '-pix_fmt',
            'yuv420p',
            if (audio) ...['-c:a', 'aac'] else '-an',
            path,
          ]);
          expect(ReturnCode.isSuccess(await result.getReturnCode()), isTrue);
        }
        for (final audio in [false, true]) {
          final output = await VideoProcessor.reel([
            (
              path: '${dir.path}/silent.mp4',
              mirror: false,
              ratio: 1.0,
              seconds: .7,
            ),
            (
              path: '${dir.path}/${audio ? 'audio' : 'silent'}.mp4',
              mirror: true,
              ratio: 16 / 9,
              seconds: 1.2,
            ),
          ], ratio: 9 / 16);
          expect(output, isNotNull);
          outputs.add(output!);
          final info = (await FFprobeKit.getMediaInformation(output))
              .getMediaInformation()!;
          expect(double.parse(info.getDuration()!), closeTo(1.9, .12));
          final video = info.getStreams().firstWhere(
            (s) => s.getType() == 'video',
          );
          expect(video.getWidth()! / video.getHeight()!, closeTo(9 / 16, .02));
          expect(info.getStreams().any((s) => s.getType() == 'audio'), audio);
        }
        final single = await VideoProcessor.reel([
          (
            path: '${dir.path}/audio.mp4',
            mirror: true,
            ratio: 1.0,
            seconds: 1.0,
          ),
        ], ratio: 1);
        expect(single, isNotNull);
        outputs.add(single!);
        expect(await VideoProcessor.duration(single), closeTo(1, .1));
      } finally {
        for (final path in outputs) {
          await File(path).delete();
        }
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
