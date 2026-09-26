import 'package:aura/hands_free/hands_free_commands.dart';
import 'package:aura/hands_free/hands_free_controls.dart';
import 'package:aura/theme/aura_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hands_free_commands_test.dart' show openHand;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  const native = MethodChannel('com.aura.aura/hands_free');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  testWidgets(
    'opt-in detection, countdown cancellation, no repeat and lifecycle suspension',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var now = Duration.zero;
      String? gesture;
      int snapshots = 0;
      final actions = <RemoteAction>[];
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'capabilities') {
          return {'gestures': true, 'voice': false};
        }
        if (call.method == 'analyze') {
          if (gesture == null) return [];
          final hand = openHand(gesture: gesture);
          return [
            {
              'gesture': hand.gesture,
              'score': hand.confidence,
              'points': hand.points.map((p) => [p.dx, p.dy, 0]).toList(),
            },
          ];
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.aura.aura/hands_free_events'),
        (_) async => null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(native, null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: HandsFreeControls(
                elapsed: () => now,
                ready: () => true,
                contextState: () => const RemoteContext(mode: RemoteMode.photo),
                snapshot: () async {
                  snapshots++;
                  return Uint8List(1);
                },
                onAction: (action) async {
                  actions.add(action);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(snapshots, 0);
      await tester.tap(find.byKey(const ValueKey('hands-free-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile).first);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      Future<void> frames(int count) async {
        for (int i = 0; i < count; i++) {
          now += const Duration(milliseconds: 300);
          await tester.pump(const Duration(milliseconds: 300));
        }
      }

      await frames(4);
      gesture = 'Open_Palm';
      await frames(5);
      expect(find.text('Photo in 3'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await frames(14);
      expect(actions, isEmpty);
      gesture = null;
      await frames(4);
      gesture = 'Open_Palm';
      await frames(5);
      await frames(11);
      expect(actions, [RemoteAction.photo]);
      await frames(12);
      expect(actions.length, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = snapshots;
      await frames(4);
      expect(snapshots, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
