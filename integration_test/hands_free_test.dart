import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aura/camera/camera_session.dart';
import 'package:aura/hands_free/hands_free_commands.dart';
import 'package:aura/hands_free/preview_sampler.dart';
import 'package:aura/services/upload_manager.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/hands_free/reference_hands.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  UploadManager.instance.suspendForTesting = true;
  testWidgets(
    'native model recognizes hand fixtures sampled through Flutter preview boundary',
    (tester) async {
      const native = MethodChannel('com.aura.aura/hands_free');
      final key = GlobalKey();
      final capabilities = await native.invokeMapMethod('capabilities');
      expect(capabilities!['gestures'], true);
      await native.invokeMethod<void>('prepareGestures');
      final actual = <String, RemoteSignal?>{};
      final expected = {
        'thumb_up.jpg': RemoteSignal.thumbsUp,
        'fist.jpg': RemoteSignal.fist,
        'woman_hands.jpg': null, // Bent fingers: do not guess an open palm.
        'right_hands.jpg': RemoteSignal.palm,
        'pointing_up.jpg': null,
      };
      for (final entry in expected.entries) {
        final bytes = base64Decode(referenceHands[entry.key]!);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 320,
                    height: 400,
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final snapshot = await sampleCameraPreview(key);
        expect(snapshot, isNotNull);
        final timer = Stopwatch()..start();
        final rows = await native.invokeListMethod<dynamic>('analyze', {
          'image': snapshot,
        });
        debugPrint('HAND_INFERENCE ${timer.elapsedMilliseconds}ms');
        final hands = rows!.map((r) => ObservedHand.fromMap(r as Map)).toList();
        debugPrint(
          'HAND_FIXTURE ${entry.key}: ${hands.map((h) => '${h.gesture}:${h.confidence.toStringAsFixed(2)}').join(', ')}',
        );
        actual[entry.key] = HandSignals.classify(hands);
      }
      await tester.pumpWidget(const SizedBox());
      expect(actual, expected);
    },
  );

  testWidgets(
    'camera texture stays readable for gestures during video recording',
    (tester) async {
      final cameras = await availableCameras();
      expect(cameras, isNotEmpty);
      for (final lens in [
        CameraLensDirection.back,
        CameraLensDirection.front,
      ]) {
        final candidates = cameras.where((c) => c.lensDirection == lens);
        if (candidates.isEmpty) continue;
        final camera = await CameraSession.open(
          candidates.first,
          preferred: ResolutionPreset.high,
        );
        final key = GlobalKey();
        String? path;
        try {
          await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: SizedBox(
                      width: 300,
                      height: 400,
                      child: CameraPreview(camera),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          for (final recording in [false, true]) {
            if (recording) await camera.startVideoRecording();
            await tester.pump(const Duration(seconds: 1));
            final bytes = await sampleCameraPreview(key);
            expect(bytes, isNotNull);
            final codec = await ui.instantiateImageCodec(bytes!);
            final image = (await codec.getNextFrame()).image;
            final rgba = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final data = rgba!.buffer.asUint8List();
            expect(
              data.where((v) => v != 0 && v != 255).length,
              greaterThan(100),
              reason:
                  '$lens texture must contain real frame pixels, not a black surface',
            );
            image.dispose();
            codec.dispose();
          }
          path = (await camera.stopVideoRecording()).path;
          debugPrint('HAND_PREVIEW $lens readable during recording');
        } finally {
          if (camera.value.isRecordingVideo) {
            path = (await camera.stopVideoRecording()).path;
          }
          await tester.pumpWidget(const SizedBox());
          await camera.dispose();
          if (path != null && await File(path).exists()) {
            await File(path).delete();
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
