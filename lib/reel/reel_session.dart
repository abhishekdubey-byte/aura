import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'domain/reel_project_controller.dart';

/// A finalized clip as capture and preview see it.
///
/// This is a read-only view of one entry in the project's primary sequence, kept
/// in seconds because that is what the existing preview and export path takes.
/// The authoritative document is [ReelSession.project]; this view is derived from
/// it and never stored twice.
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
  ReelSession({
    required this.startCapture,
    required this.finishCapture,
    ReelProjectController? project,
  }) : _ownsProject = project == null,
       project = project ?? ReelProjectController() {
    this.project.addListener(_emit);
  }

  final Future<void> Function() startCapture;
  final Future<({String path, double seconds})> Function() finishCapture;

  /// The editable document accepted captures are committed to. It outlives this
  /// session when one is supplied, so leaving the capture route does not discard
  /// the project.
  final ReelProjectController project;
  final bool _ownsProject;

  /// The primary sequence as capture and preview consume it, derived from the
  /// project rather than kept alongside it.
  List<ReelClip> get clips => [
    for (final clip in project.project.sequence)
      ReelClip(
        path: project.project.assetForClip(clip).path,
        seconds: clip.outputDuration.inMicroseconds / Duration.microsecondsPerSecond,
        ratio: clip.ratio,
        mirror: project.project.assetForClip(clip).mirrored,
      ),
  ];

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
  double get totalSeconds =>
      project.project.totalDuration.inMicroseconds /
      Duration.microsecondsPerSecond;
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
      // The hands-free limit bounds how much of the take the reel uses; the
      // asset keeps its full recorded length so a later trim can extend again.
      final source = _microseconds(result.seconds);
      final used = _microseconds(
        math.min(result.seconds, (_limit ?? maxSeconds).toDouble()),
      );
      if (source <= Duration.zero || used <= Duration.zero) {
        throw StateError('Empty recording');
      }
      project.appendCapturedClip(
        path: result.path,
        duration: source,
        usedDuration: used < source ? used : source,
        mirrored: _mirror,
        ratio: _ratio,
      );
    } catch (_) {
      error = 'This clip could not be finalized. Your earlier clips are still here. Try recording again.';
    } finally {
      phase = ReelPhase.idle;
      _emit();
    }
  }

  /// Capture's own "remove the last clip" action, kept distinct from the
  /// project-wide undo an editor will offer. It is committed as a project edit,
  /// so the clip and its asset can be restored.
  void undo() {
    if (active || project.project.sequence.isEmpty) return;
    project.removeLastClip();
    _emit();
  }

  static Duration _microseconds(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );

  @override
  void dispose() {
    _disposed = true;
    _deadline?.cancel();
    _ticker?.cancel();
    _clock.stop();
    project.removeListener(_emit);
    if (_ownsProject) project.dispose();
    super.dispose();
  }
}
