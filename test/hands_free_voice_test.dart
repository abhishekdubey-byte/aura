import 'dart:async';

import 'package:aura/hands_free/hands_free_commands.dart';
import 'package:aura/hands_free/hands_free_controls.dart';
import 'package:aura/hands_free/hands_free_preferences.dart';
import 'package:aura/theme/aura_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  testWidgets(
    'voice waits for opt-in, cancels countdown promptly and releases microphone before recording',
    (tester) async {
      const channel = 'com.aura.aura/hands_free';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      String? owner;
      var now = Duration.zero;
      bool recording = false;
      final actions = <RemoteAction>[];
      messenger.setMockMethodCallHandler(const MethodChannel(channel), (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'capabilities') {
          return {'gestures': false, 'voice': true, 'onDeviceVoice': true};
        }
        if (call.method == 'startVoice') {
          owner = call.arguments['owner'] as String;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('${channel}_events'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
          if (call.method == 'requestPermissions') return {7: 1};
          return 1;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.dark,
          home: Scaffold(
            body: HandsFreeControls(
              elapsed: () => now,
              ready: () => true,
              contextState: () =>
                  RemoteContext(mode: RemoteMode.reel, recording: recording),
              snapshot: () async => null,
              onAction: (action) async {
                expect(
                  calls.last,
                  'stopVoice',
                  reason: 'Microphone must be released before camera starts',
                );
                actions.add(action);
                recording = true;
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(calls, isNot(contains('startVoice')));
      await tester.tap(find.byKey(const ValueKey('hands-free-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile).last);
      await tester.tap(find.byType(SwitchListTile).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(owner, isNotNull);
      Future<void> words(String phrase, {String type = 'words'}) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          '${channel}_events',
          const StandardMethodCodec().encodeSuccessEnvelope({
            'owner': owner,
            'type': type,
            'text': phrase,
          }),
          (_) => done.complete(),
        );
        await done.future;
        await tester.pump();
      }

      final beforeRetry = calls.where((c) => c == 'startVoice').length;
      await words('Speech service unavailable', type: 'error');
      expect(HandsFreePreferences.instance.voice, true);
      now = const Duration(seconds: 31);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        calls.where((c) => c == 'startVoice').length,
        greaterThan(beforeRetry),
      );
      await words('', type: 'listening');
      expect(find.text('Speech service unavailable'), findsNothing);

      await words('do not start recording');
      expect(find.text('Record in 3'), findsNothing);
      await words('start');
      expect(find.text('Record in 3'), findsOneWidget);
      now += const Duration(milliseconds: 500);
      await words('cancel');
      expect(find.text('Record in 3'), findsNothing);
      now += const Duration(seconds: 3);
      await words('capture');
      expect(find.text('Record in 3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(actions, [RemoteAction.start]);
      final starts = calls.where((c) => c == 'startVoice').length;
      await tester.pump(const Duration(seconds: 3));
      expect(calls.where((c) => c == 'startVoice').length, starts);
      final screen = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final previousOwner = owner;
      await tester.pumpWidget(const SizedBox());
      recording = false;
      await tester.pumpWidget(screen);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(owner, isNot(previousOwner));
      expect(HandsFreePreferences.instance.voice, true);
      expect(
        (await SharedPreferences.getInstance()).getBool('hands_free_voice'),
        true,
      );
      expect(find.text('Hands-free on'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      for (final name in [
        channel,
        '${channel}_events',
        'flutter.baseflow.com/permissions/methods',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
    },
  );
}
