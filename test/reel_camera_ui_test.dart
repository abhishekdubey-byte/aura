import 'dart:async';

import 'package:aura/main.dart' as app;
import 'package:aura/camera/capture_aspect.dart';
import 'package:aura/hands_free/hands_free_commands.dart';
import 'package:aura/hands_free/hands_free_controls.dart';
import 'package:aura/services/upload_manager.dart';
import 'package:aura/reel/reel_camera_screen.dart';
import 'package:aura/theme/aura_theme.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const cameras = [
  CameraDescription(
    name: 'back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  ),
  CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 90,
  ),
];

class FakeCamera extends CameraPlatform {
  int _id = 0, starts = 0, stops = 0;
  bool failStop = true;
  final opened = <String>[];
  final _errors = StreamController<CameraErrorEvent>.broadcast();
  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    opened.add(cameraDescription.name);
    return ++_id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}
  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}
  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;
  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 8;
  @override
  Widget buildPreview(int cameraId) =>
      const ColoredBox(color: Color(0xff223344));
  @override
  Future<void> dispose(int cameraId) async {}
  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    starts++;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stops++;
    if (!failStop) return XFile('/fake/clip-$stops.mp4');
    throw CameraException(
      'test_stop',
      'No real file is recorded in this widget test',
    );
  }
}

void main() {
  late FakeCamera fake;
  late CameraPlatform previous;
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.aura.aura/hands_free'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.aura.aura/hands_free_events'),
          (_) async => null,
        );
    UploadManager.instance.suspendForTesting = true;
    previous = CameraPlatform.instance;
    fake = FakeCamera();
    CameraPlatform.instance = fake;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.aura.aura/volume'),
          (_) async => null,
        );
  });
  tearDown(() {
    CameraPlatform.instance = previous;
    UploadManager.instance.suspendForTesting = false;
  });

  Widget host(Widget screen) => MaterialApp(
    theme: AuraTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.6)),
      child: child!,
    ),
    home: screen,
  );

  testWidgets(
    'reel capture and camera switching work; right-side tools stay within 3:4',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(const ReelCameraScreen(cameras: cameras)));
      await tester.pumpAndSettle();
      expect(find.text('Full'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Switch camera'));
      await tester.pumpAndSettle();
      expect(fake.opened, ['back', 'front']);
      expect(
        tester.getCenter(find.byKey(const ValueKey('reel-shutter'))).dy,
        greaterThan(320),
      );
      await tester.tap(find.text('3s'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reel-shutter')));
      await tester.pump();
      expect(fake.starts, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(fake.stops, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      fake.starts = 0;
      fake.stops = 0;
      fake.opened.clear();
      await tester.pumpWidget(host(const ReelCameraScreen(cameras: cameras)));
      await tester.pumpAndSettle();
      expect(fake.opened, ['back']);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('reel-shutter'))),
      );
      await tester.pump();
      expect(fake.starts, 1);
      await gesture.up();
      await tester.pump();
      expect(fake.stops, 1);
      await tester.pumpWidget(const SizedBox());
      app.cameras = cameras;
      await tester.pumpWidget(host(const app.CameraScreen()));
      await tester.pumpAndSettle();
      final tools = find.byKey(const ValueKey('camera-side-tools'));
      final frame = ViewfinderGeometry.compute(
        screen: const Size(320, 640),
        padding: EdgeInsets.zero,
        frameAspect: 9 / 16,
        cropRatio: 3 / 4,
      ).crop;
      expect(tester.getTopLeft(tools).dx, greaterThan(250));
      expect(tester.getTopLeft(tools).dy, greaterThanOrEqualTo(frame.top));
      expect(tester.getBottomRight(tools).dy, lessThanOrEqualTo(frame.bottom));
      final buttons = find.descendant(
        of: tools,
        matching: find.byType(IconButton),
      );
      expect(buttons, findsNWidgets(8));
      double previousY = -1;
      for (final button in buttons.evaluate()) {
        final center = tester.getCenter(find.byWidget(button.widget));
        expect(center.dx, closeTo(284, 1));
        expect(center.dy, greaterThan(previousY));
        previousY = center.dy;
      }
      expect(find.byKey(const ValueKey('reel-mode-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
      fake.failStop = false;
      fake.starts = 0;
      fake.stops = 0;
      final handsFree = tester.widget<HandsFreeControls>(
        find.byType(HandsFreeControls),
      );
      await handsFree.onAction(RemoteAction.start);
      await tester.pump();
      expect(handsFree.contextState().recording, true);
      await handsFree.onAction(RemoteAction.pause);
      await tester.pump();
      expect(handsFree.contextState().paused, true);
      expect(find.text('Video paused'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await handsFree.onAction(RemoteAction.start);
      await tester.pump();
      expect(handsFree.contextState().recording, true);
      expect(handsFree.contextState().paused, false);
      await handsFree.onAction(RemoteAction.pause);
      await tester.pump();
      expect(fake.starts, 2);
      expect(fake.stops, 2);
      expect(find.text('Finish'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
