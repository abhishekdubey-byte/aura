import 'package:aura/hands_free/hands_free_commands.dart';
import 'package:flutter_test/flutter_test.dart';

ObservedHand openHand({
  String gesture = 'Open_Palm',
  double confidence = .99,
  Offset wrist = const Offset(.5, .8),
  Offset axis = const Offset(0, -.3),
}) {
  final points = List.generate(21, (_) => wrist);
  for (final tip in [8, 12, 16, 20]) {
    points[tip - 3] = wrist + axis * .45;
    points[tip - 2] = wrist + axis * .65;
    points[tip - 1] = wrist + axis * .8;
    points[tip] = wrist + axis;
  }
  return ObservedHand(gesture, confidence, points);
}

void main() {
  test('voice only accepts complete explicit commands, never substrings', () {
    expect(parseVoiceCommand('Aura, CAPTURE!'), RemoteSignal.click);
    expect(parseVoiceCommand('start recording'), RemoteSignal.start);
    expect(parseVoiceCommand('resume'), RemoteSignal.start);
    expect(parseVoiceCommand('cancel'), RemoteSignal.cancel);
    for (final phrase in [
      'do not capture',
      'restart',
      'please stop talking',
      'capture this memory for later',
      'clickbait',
    ]) {
      expect(parseVoiceCommand(phrase), isNull, reason: phrase);
    }
  });
  test(
    'commands honor mode, pause state, busy state and countdown cancellation',
    () {
      const photo = RemoteContext(mode: RemoteMode.photo);
      const recording = RemoteContext(mode: RemoteMode.photo, recording: true);
      const paused = RemoteContext(mode: RemoteMode.photo, paused: true);
      const reel = RemoteContext(mode: RemoteMode.reel, hasClips: true);
      expect(resolveRemoteAction(RemoteSignal.palm, photo), RemoteAction.photo);
      expect(resolveRemoteAction(RemoteSignal.click, reel), RemoteAction.start);
      expect(resolveRemoteAction(RemoteSignal.palm, reel), isNull);
      expect(resolveRemoteAction(RemoteSignal.thumbsUp, recording), isNull);
      expect(
        resolveRemoteAction(RemoteSignal.timeOut, recording),
        RemoteAction.pause,
      );
      expect(
        resolveRemoteAction(RemoteSignal.thumbsUp, paused),
        RemoteAction.start,
      );
      expect(
        resolveRemoteAction(RemoteSignal.fist, paused),
        RemoteAction.finish,
      );
      expect(resolveRemoteAction(RemoteSignal.fist, reel), RemoteAction.finish);
      expect(
        resolveRemoteAction(
          RemoteSignal.start,
          const RemoteContext(mode: RemoteMode.photo, videoAllowed: false),
        ),
        isNull,
      );
      expect(
        resolveRemoteAction(
          RemoteSignal.click,
          const RemoteContext(mode: RemoteMode.photo, busy: true),
        ),
        isNull,
      );
      expect(
        resolveRemoteAction(RemoteSignal.click, photo, countingDown: true),
        isNull,
      );
      expect(
        resolveRemoteAction(RemoteSignal.cancel, photo, countingDown: true),
        RemoteAction.cancel,
      );
    },
  );
  test('classifier rejects weak/conflicting hands and distinguishes the two-hand T', () {
    final palm = openHand();
    final thumb = openHand(gesture: 'Thumb_Up');
    expect(HandSignals.classify([palm]), RemoteSignal.palm);
    expect(HandSignals.classify([thumb]), RemoteSignal.thumbsUp);
    expect(HandSignals.classify([openHand(confidence: .6)]), isNull);
    expect(HandSignals.classify([palm, thumb]), isNull);
    final horizontal = openHand(
      wrist: const Offset(.35, .48),
      axis: const Offset(.3, 0),
    );
    expect(HandSignals.classify([palm, horizontal]), RemoteSignal.timeOut);
    expect(HandSignals.classify([horizontal, palm]), RemoteSignal.timeOut);
    final far = openHand(
      wrist: const Offset(.05, .1),
      axis: const Offset(.25, 0),
    );
    expect(HandSignals.classify([palm, far]), isNot(RemoteSignal.timeOut));
    final mirrored = [palm, horizontal]
        .map(
          (h) => ObservedHand(
            h.gesture,
            h.confidence,
            h.points.map((p) => Offset(1 - p.dx, p.dy)).toList(),
          ),
        )
        .toList();
    expect(HandSignals.classify(mirrored), RemoteSignal.timeOut);
  });
  test(
    'weaker palm labels require spread fingers and never promote unknown hands',
    () {
      final points = List<Offset>.filled(21, const Offset(.5, .7));
      points[0] = const Offset(.5, .9);
      points[4] = const Offset(.2, .6);
      for (var finger = 0; finger < 4; finger++) {
        final x = .4 + finger * .1;
        points[5 + finger * 4] = Offset(x, .65);
        points[8 + finger * 4] = Offset(x, .25);
      }
      ObservedHand hand(String label, double score) =>
          ObservedHand(label, score, points);
      expect(HandSignals.classify([hand('Open_Palm', .6)]), RemoteSignal.palm);
      expect(HandSignals.classify([hand('Open_Palm', .5)]), isNull);
      expect(HandSignals.classify([hand('None', .9)]), isNull);
      points[8] =
          points[5]; // Bent index finger cannot use the lower threshold.
      expect(HandSignals.classify([hand('Open_Palm', .6)]), isNull);
    },
  );
  test('stable gesture fires once, then requires neutral and cooldown before rearming', () {
    final gate = GestureGate();
    RemoteSignal? at(int ms, RemoteSignal? signal) =>
        gate.update(signal, Duration(milliseconds: ms));
    for (final ms in [0, 300, 600]) {
      expect(at(ms, RemoteSignal.palm), isNull);
    }
    expect(at(900, RemoteSignal.palm), RemoteSignal.palm);
    for (int ms = 1200; ms <= 6000; ms += 300) {
      expect(at(ms, RemoteSignal.palm), isNull);
    }
    for (final ms in [6300, 6600, 6900]) {
      at(ms, null);
    }
    for (final ms in [7200, 7500, 7800]) {
      expect(at(ms, RemoteSignal.palm), isNull);
    }
    expect(at(8100, RemoteSignal.palm), RemoteSignal.palm);
  });
  test('stale frames and alternating shapes cannot satisfy a hold', () {
    final gate = GestureGate();
    expect(gate.update(RemoteSignal.palm, Duration.zero), isNull);
    expect(gate.update(RemoteSignal.palm, const Duration(seconds: 2)), isNull);
    expect(
      gate.update(RemoteSignal.thumbsUp, const Duration(milliseconds: 2300)),
      isNull,
    );
    expect(
      gate.update(RemoteSignal.palm, const Duration(milliseconds: 2600)),
      isNull,
    );
    gate.disarm();
    for (int ms = 2900; ms <= 5000; ms += 300) {
      expect(
        gate.update(RemoteSignal.palm, Duration(milliseconds: ms)),
        isNull,
      );
    }
  });
}
