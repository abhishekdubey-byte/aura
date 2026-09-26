import 'dart:async';

import 'package:aura/reel/reel_duration_picker.dart';
import 'package:aura/reel/reel_session.dart';
import 'package:aura/theme/aura_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'release during startup finalizes exactly once and preserves earlier clips',
    () async {
      final started = Completer<void>();
      int starts = 0, stops = 0;
      final session = ReelSession(
        startCapture: () async {
          if (++starts == 2) await started.future;
        },
        finishCapture: () async => (path: 'clip${++stops}', seconds: 2.0),
      );
      addTearDown(session.dispose);
      await session.start(ratio: 1, mirror: false);
      await session.stop();
      final start = session.start(ratio: 9 / 16, mirror: true);
      final stop = session.stop();
      final duplicate = session.stop();
      expect(stops, 1);
      started.complete();
      await Future.wait([start, stop, duplicate]);
      expect(stops, 2);
      expect(session.clips.map((clip) => clip.path), ['clip1', 'clip2']);
      expect(session.clips.first.ratio, 1);
      expect(session.clips.last.mirror, isTrue);
      expect(session.phase, ReelPhase.idle);
    },
  );

  testWidgets(
    'deadline starts after camera readiness and limits each clip independently',
    (tester) async {
      final ready = Completer<void>();
      int stops = 0;
      final session = ReelSession(
        startCapture: () => ready.future,
        finishCapture: () async => (path: 'clip${++stops}', seconds: 5.2),
      );
      addTearDown(session.dispose);
      unawaited(session.start(ratio: .5, mirror: false, seconds: 5));
      await tester.pump(const Duration(seconds: 10));
      expect(stops, 0);
      ready.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(stops, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(stops, 1);
      expect(session.clips.single.seconds, 5);
      await session.start(ratio: 1, mirror: true, seconds: 3);
      await tester.pump(const Duration(seconds: 3));
      expect(stops, 2);
      expect(session.totalSeconds, 8);
      expect(session.clips.last.ratio, 1);
    },
  );

  test(
    'failed capture leaves previous clips available and permits retry',
    () async {
      bool fail = false;
      final session = ReelSession(
        startCapture: () async {},
        finishCapture: () async {
          if (fail) throw StateError('camera failed');
          return (path: 'clip', seconds: 1.5);
        },
      );
      addTearDown(session.dispose);
      await session.start(ratio: 1, mirror: false);
      await session.stop();
      fail = true;
      await session.start(ratio: 1, mirror: false);
      await session.stop();
      expect(session.clips.length, 1);
      expect(session.error, isNotNull);
      fail = false;
      await session.start(ratio: 1, mirror: false);
      await session.stop();
      expect(session.clips.length, 2);
      expect(session.error, isNull);
      session.undo();
      expect(session.totalSeconds, 1.5);
    },
  );

  test('invalid duration is rejected before starting camera', () {
    int starts = 0;
    final session = ReelSession(
      startCapture: () async {
        starts++;
      },
      finishCapture: () async => (path: 'clip', seconds: 1.0),
    );
    addTearDown(session.dispose);
    for (final seconds in [0, -1, 301]) {
      expect(
        () => session.start(ratio: 1, mirror: false, seconds: seconds),
        throwsArgumentError,
      );
    }
    expect(starts, 0);
  });

  testWidgets(
    'custom timer validates bounds and fits a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? chosen;
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await showReelDurationPicker(context, 5);
                },
                child: const Text('Timer'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Timer'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('reel-custom-duration'));
      await tester.enterText(field, '0');
      await tester.ensureVisible(find.text('Set timer'));
      await tester.tap(find.text('Set timer'));
      await tester.pumpAndSettle();
      expect(find.text('Enter 1–300 seconds'), findsOneWidget);
      await tester.enterText(field, '47');
      await tester.ensureVisible(find.text('Set timer'));
      await tester.tap(find.text('Set timer'));
      await tester.pumpAndSettle();
      expect(chosen, 47);
      expect(tester.takeException(), isNull);
    },
  );
}
