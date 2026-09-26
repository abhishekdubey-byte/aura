import 'dart:math' as math;
import 'dart:ui';

enum RemoteSignal {
  palm,
  thumbsUp,
  timeOut,
  fist,
  click,
  start,
  pause,
  finish,
  cancel,
}

enum RemoteAction { photo, start, pause, finish, cancel }

enum RemoteMode { photo, boomerang, reel }

class RemoteContext {
  const RemoteContext({
    required this.mode,
    this.recording = false,
    this.paused = false,
    this.hasClips = false,
    this.busy = false,
    this.videoAllowed = true,
  });
  final RemoteMode mode;
  final bool recording, paused, hasClips, busy, videoAllowed;
}

RemoteSignal? parseVoiceCommand(String words) {
  var text = words.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), '').trim();
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  if (text.startsWith('aura ')) text = text.substring(5);
  return switch (text) {
    'click' ||
    'capture' ||
    'take photo' ||
    'take a photo' => RemoteSignal.click,
    'start' || 'record' || 'start recording' || 'resume' => RemoteSignal.start,
    'pause' => RemoteSignal.pause,
    'stop' || 'finish' || 'stop recording' => RemoteSignal.finish,
    'cancel' => RemoteSignal.cancel,
    _ => null,
  };
}

RemoteAction? resolveRemoteAction(
  RemoteSignal signal,
  RemoteContext state, {
  bool countingDown = false,
}) {
  if (signal == RemoteSignal.cancel ||
      (countingDown &&
          (signal == RemoteSignal.timeOut || signal == RemoteSignal.fist))) {
    return RemoteAction.cancel;
  }
  if (countingDown || state.busy) return null;
  switch (signal) {
    case RemoteSignal.palm:
      return state.mode == RemoteMode.photo && !state.recording && !state.paused
          ? RemoteAction.photo
          : null;
    case RemoteSignal.click:
      if (state.recording) return null;
      return state.mode == RemoteMode.photo && !state.paused
          ? RemoteAction.photo
          : RemoteAction.start;
    case RemoteSignal.start:
    case RemoteSignal.thumbsUp:
      return state.recording || !state.videoAllowed ? null : RemoteAction.start;
    case RemoteSignal.pause:
    case RemoteSignal.timeOut:
      return state.recording && state.mode != RemoteMode.boomerang
          ? RemoteAction.pause
          : null;
    case RemoteSignal.finish:
    case RemoteSignal.fist:
      return state.recording || state.paused || state.hasClips
          ? RemoteAction.finish
          : null;
    case RemoteSignal.cancel:
      return RemoteAction.cancel;
  }
}

class ObservedHand {
  const ObservedHand(this.gesture, this.confidence, this.points);
  final String gesture;
  final double confidence;
  final List<Offset> points;
  factory ObservedHand.fromMap(Map<dynamic, dynamic> map) => ObservedHand(
    map['gesture'] as String? ?? 'None',
    (map['score'] as num?)?.toDouble() ?? 0,
    (map['points'] as List? ?? [])
        .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList(),
  );
}

class HandSignals {
  static RemoteSignal? classify(List<ObservedHand> hands) {
    final visible = hands
        .where(
          (hand) =>
              hand.points.length == 21 &&
              hand.points.every((p) => p.dx.isFinite && p.dy.isFinite) &&
              (hand.points[0] - hand.points[9]).distance > .025,
        )
        .toList();
    if (visible.length == 2 &&
        (_timeOut(visible[0], visible[1]) ||
            _timeOut(visible[1], visible[0]))) {
      return RemoteSignal.timeOut;
    }
    final signals = <RemoteSignal>{};
    for (final hand in visible) {
      // The palm classifier can be less confident for a hand's back. Accept
      // that label at a lower score only when all four fingers are extended
      // and the thumb and fingertips visibly spread across the palm.
      final verifiedPalm =
          hand.gesture == 'Open_Palm' &&
          hand.confidence >= .55 &&
          _spreadPalm(hand);
      if (hand.confidence < .7 && !verifiedPalm) continue;
      final signal = switch (hand.gesture) {
        'Open_Palm' => RemoteSignal.palm,
        'Thumb_Up' => RemoteSignal.thumbsUp,
        'Closed_Fist' => RemoteSignal.fist,
        _ => null,
      };
      if (signal != null) signals.add(signal);
    }
    // Conflicting hands never choose an arbitrary action.
    return signals.length == 1 ? signals.single : null;
  }

  static bool _spreadPalm(ObservedHand hand) {
    final points = hand.points;
    final width = (points[5] - points[17]).distance;
    if (width < .015 ||
        (points[4] - points[5]).distance < width * .55 ||
        (points[8] - points[20]).distance < width * .85) {
      return false;
    }
    return [8, 12, 16, 20].every(
      (tip) =>
          (points[tip] - points[0]).distance >
          (points[tip - 3] - points[0]).distance * 1.35,
    );
  }

  static bool _extended(ObservedHand hand) {
    final wrist = hand.points[0];
    return [8, 12, 16, 20]
            .where(
              (tip) =>
                  (hand.points[tip] - wrist).distance >
                  (hand.points[tip - 3] - wrist).distance * 1.35,
            )
            .length >=
        3;
  }

  static bool _timeOut(ObservedHand vertical, ObservedHand horizontal) {
    if (!_extended(vertical) || !_extended(horizontal)) return false;
    final v = vertical.points[12] - vertical.points[0];
    final h = horizontal.points[12] - horizontal.points[0];
    if (v.dy >= 0 ||
        v.dy.abs() < v.dx.abs() * 1.6 ||
        h.dx.abs() < h.dy.abs() * 1.6) {
      return false;
    }
    final length = math.max(v.distance, h.distance);
    final tip = vertical.points[12];
    final base = horizontal.points[0];
    final dot = (tip.dx - base.dx) * h.dx + (tip.dy - base.dy) * h.dy;
    final fraction = dot / h.distanceSquared;
    if (fraction < .15 || fraction > .9) return false;
    final contact = base + h * fraction;
    return (tip - contact).distance < length * .28 &&
        vertical.points[0].dy > contact.dy + length * .45;
  }
}

/// Stable hold, cooldown and an explicit neutral gap prevent a held hand from
/// triggering repeatedly, including across a camera mode/state change.
class GestureGate {
  RemoteSignal? _candidate;
  Duration? _since, _lastFrame, _neutralSince;
  Duration _blockedUntil = Duration.zero;
  bool _armed = true;

  RemoteSignal? update(RemoteSignal? signal, Duration now) {
    if (_lastFrame != null &&
        now - _lastFrame! > const Duration(milliseconds: 900)) {
      _candidate = null;
      _since = null;
    }
    _lastFrame = now;
    if (signal == null) {
      _candidate = null;
      _since = null;
      _neutralSince ??= now;
      if (now - _neutralSince! >= const Duration(milliseconds: 600)) {
        _armed = true;
      }
      return null;
    }
    _neutralSince = null;
    if (!_armed || now < _blockedUntil) return null;
    if (_candidate != signal) {
      _candidate = signal;
      _since = now;
      return null;
    }
    final hold = signal == RemoteSignal.fist ? 1400 : 900;
    if (now - _since! < Duration(milliseconds: hold)) return null;
    _armed = false;
    _blockedUntil = now + const Duration(seconds: 2);
    _candidate = null;
    _since = null;
    return signal;
  }

  void disarm() {
    _armed = false;
    _candidate = null;
    _since = null;
    _neutralSince = null;
  }
}
