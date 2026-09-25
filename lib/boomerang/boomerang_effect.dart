import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand gradient for everything Boomerang (∞).
const List<Color> kBoomerangGradient = [Color(0xFF7C4DFF), Color(0xFFE040FB), Color(0xFFFF4D8D), Color(0xFFFFA24D)];

/// How a clip is played back and forth.
///
/// Every effect is a ping-pong loop (A→D→A→D…) with a speed ramp: motion is
/// fastest mid-way and eases into each reversal. Slowing at the turn draws the
/// eye to the moment the motion "snaps back", the small prediction violation
/// that makes boomerangs so watchable, while the fast middle keeps it punchy.
class BoomerangEffect {
  const BoomerangEffect._({
    required this.id,
    required this.label,
    required this.icon,
    required this.forwardSpeed,
    required this.reverseSpeed,
    required this.ease,
    this.echo = false,
  });

  final String id;
  final String label;
  final IconData icon;
  /// Playback speed of the forward pass (1 = real time).
  final double forwardSpeed;
  /// Playback speed of the backward pass.
  final double reverseSpeed;
  /// Speed-ramp strength, 0 (constant speed) to <1 (near-pause at each turn).
  final double ease;
  /// Motion trails (ghosting of the previous frames).
  final bool echo;

  /// Snappy back-and-forth, the one everybody knows.
  static const classic = BoomerangEffect._(
    id: 'classic', label: 'Classic', icon: Icons.all_inclusive,
    forwardSpeed: 1.5, reverseSpeed: 1.5, ease: 0.55,
  );

  /// Dreamy half-speed loop.
  static const slowMo = BoomerangEffect._(
    id: 'slowmo', label: 'Slow-mo', icon: Icons.slow_motion_video,
    forwardSpeed: 0.6, reverseSpeed: 0.6, ease: 0.35,
  );

  /// Motion leaves a fading trail.
  static const echoTrail = BoomerangEffect._(
    id: 'echo', label: 'Echo', icon: Icons.blur_on,
    forwardSpeed: 1.2, reverseSpeed: 1.2, ease: 0.5, echo: true,
  );

  /// Whips forward, drifts back: an exaggerated rewind.
  static const duo = BoomerangEffect._(
    id: 'duo', label: 'Duo', icon: Icons.fast_rewind,
    forwardSpeed: 2.2, reverseSpeed: 0.8, ease: 0.6,
  );

  static const List<BoomerangEffect> values = [classic, slowMo, echoTrail, duo];
}

/// Maps playback time to source frames for one effect, and produces the
/// matching FFmpeg expressions, so the live preview and the saved video loop
/// identically.
///
/// A cycle plays frames 0…N-1 forward, then N-2…1 backward (the turn-around
/// frames are not repeated, so there is no stutter at either end).
class BoomerangTiming {
  BoomerangTiming(this.effect, this.frameCount, {this.fps = 30}) : assert(frameCount >= 4);

  final BoomerangEffect effect;
  final int frameCount;
  final int fps;

  double get forwardIn => frameCount / fps;
  double get reverseIn => (frameCount - 2) / fps;
  double get forwardOut => forwardIn / effect.forwardSpeed;
  double get reverseOut => reverseIn / effect.reverseSpeed;
  double get cycleSeconds => forwardOut + reverseOut;

  /// Source frame index to show [seconds] into playback (loops forever).
  ///
  /// Sampled one output frame ahead to line up with how FFmpeg's `fps` filter
  /// resamples the ramped timestamps, so the preview and the saved video
  /// agree to within a frame.
  int frameAt(double seconds) {
    final double t = (seconds + 1 / fps) % cycleSeconds;
    if (t < forwardOut) {
      final double u = _invertRamp(t / forwardOut, effect.ease);
      return (u * frameCount).floor().clamp(0, frameCount - 1);
    }
    final double u = _invertRamp((t - forwardOut) / reverseOut, effect.ease);
    final int j = (u * (frameCount - 2)).floor().clamp(0, frameCount - 3);
    return frameCount - 2 - j;
  }

  /// FFmpeg `setpts` expression for the forward or backward pass. Output time
  /// is out(T) = (T − a·H/2π · sin(2πT/H)) / speed, whose slope is lowest at
  /// both ends of the pass: the speed ramp.
  String setptsExpression({required bool forward}) {
    final double h = forward ? forwardIn : reverseIn;
    final double k = 1 / (forward ? effect.forwardSpeed : effect.reverseSpeed);
    final double a = effect.ease * h / (2 * math.pi);
    String f(double v) => v.toStringAsFixed(6);
    return '${f(k)}*(T-${f(a)}*sin(2*PI*T/${f(h)}))/TB';
  }

  /// Solves u − a/2π·sin(2πu) = p for u in [0, 1] (monotonic for a < 1).
  static double _invertRamp(double p, double a) {
    if (a <= 0) return p;
    double lo = 0, hi = 1;
    for (int i = 0; i < 24; i++) {
      final double mid = (lo + hi) / 2;
      final double v = mid - a / (2 * math.pi) * math.sin(2 * math.pi * mid);
      if (v < p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }
}
