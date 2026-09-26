import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

class ReelClip {
  const ReelClip({
    required this.path,
    required this.seconds,
    required this.ratio,
    required this.mirror,
  });
  final String path;
  final double seconds, ratio;
  final bool mirror;
}

enum ReelPhase { idle, starting, recording, stopping }

/// Owns the recording deadline and serializes release/start/stop races. The
/// camera adapter supplies actual media duration, never time spent opening it.
class ReelSession extends ChangeNotifier {
  ReelSession({required this.startCapture, required this.finishCapture});
  final Future<void> Function() startCapture;
  final Future<({String path, double seconds})> Function() finishCapture;
  final List<ReelClip> _clips = [];
  List<ReelClip> get clips => List.unmodifiable(_clips);
  ReelPhase phase = ReelPhase.idle;
  String? error;
  final Stopwatch _clock = Stopwatch();
  Timer? _deadline, _ticker;
  Future<void>? _starting, _stopping;
  bool _disposed = false;
  double _ratio = 9 / 16;
  bool _mirror = false;
  int? _limit;
  bool get active => phase != ReelPhase.idle;
  double get elapsed => _clock.elapsedMilliseconds / 1000;
  double get totalSeconds => _clips.fold(0, (sum, clip) => sum + clip.seconds);
  static const presets = [3, 5, 7, 30, 60];
  static const maxSeconds = 300;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start({
    required double ratio,
    required bool mirror,
    int? seconds,
  }) {
    if (active || _disposed) return Future.value();
    if (!ratio.isFinite ||
        ratio <= 0 ||
        (seconds != null && (seconds < 1 || seconds > maxSeconds))) {
      throw ArgumentError('Invalid reel framing or duration');
    }
    _ratio = ratio;
    _mirror = mirror;
    _limit = seconds;
    error = null;
    _clock.reset();
    phase = ReelPhase.starting;
    _emit();
    return _starting = _start();
  }

  Future<void> _start() async {
    try {
      await startCapture();
      if (_disposed) return;
      _clock
        ..reset()
        ..start();
      phase = ReelPhase.recording;
      _deadline = Timer(Duration(seconds: _limit ?? maxSeconds), () => stop());
      _ticker = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _emit(),
      );
      _emit();
    } catch (_) {
      phase = ReelPhase.idle;
      error = 'Could not start recording. Check camera and microphone access, then try again.';
      _emit();
    }
  }

  Future<void> stop() =>
      _stopping ??= _stop().whenComplete(() => _stopping = null);

  Future<void> _stop() async {
    await _starting;
    if (phase != ReelPhase.recording || _disposed) return;
    phase = ReelPhase.stopping;
    _deadline?.cancel();
    _ticker?.cancel();
    _clock.stop();
    _emit();
    try {
      final result = await finishCapture();
      if (!result.seconds.isFinite || result.seconds <= 0) {
        throw StateError('Empty recording');
      }
      _clips.add(
        ReelClip(
          path: result.path,
          seconds: math.min(result.seconds, (_limit ?? maxSeconds).toDouble()),
          ratio: _ratio,
          mirror: _mirror,
        ),
      );
    } catch (_) {
      error = 'This clip could not be finalized. Your earlier clips are still here. Try recording again.';
    } finally {
      phase = ReelPhase.idle;
      _emit();
    }
  }

  void undo() {
    if (active || _clips.isEmpty) return;
    _clips.removeLast();
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _deadline?.cancel();
    _ticker?.cancel();
    _clock.stop();
    super.dispose();
  }
}
