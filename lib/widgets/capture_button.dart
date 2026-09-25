import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aura/boomerang/boomerang_effect.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shutter button with a rotating zoom dial above it and a recording state
/// that shows a circle-in-circle stopwatch: the outer ring fills once a minute
/// and the pulsing red core carries the timer. In Boomerang mode it shows ∞
/// and, while capturing, a gradient ring that fills over the clip length.
class AnimatedCaptureButton extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  /// Called when a zoom slide (long-press drag or vertical drag) begins.
  final VoidCallback onZoomStart;

  /// Total vertical offset since the slide began (negative = up = zoom in).
  final ValueChanged<double> onSlideZoom;
  final bool isRecording;

  /// Running only while the camera is actually recording.
  final Stopwatch recordStopwatch;
  final ValueListenable<double> zoomLevel;
  final ValueListenable<({double min, double max})> zoomRange;

  /// True while a zoom gesture is in progress (and briefly after).
  final ValueListenable<bool> zoomActive;

  /// Boomerang (∞) mode, whether a boomerang is being captured, its 0..1
  /// progress and its length in seconds (for the per-second ticks).
  final bool boomerangMode;
  final bool isBoomerangCapturing;
  final ValueListenable<double> boomerangProgress;
  final int boomerangSeconds;

  const AnimatedCaptureButton({
    super.key,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onZoomStart,
    required this.onSlideZoom,
    required this.isRecording,
    required this.recordStopwatch,
    required this.zoomLevel,
    required this.zoomRange,
    required this.zoomActive,
    required this.boomerangMode,
    required this.isBoomerangCapturing,
    required this.boomerangProgress,
    required this.boomerangSeconds,
  });

  @override
  State<AnimatedCaptureButton> createState() => _AnimatedCaptureButtonState();
}

class _AnimatedCaptureButtonState extends State<AnimatedCaptureButton> with TickerProviderStateMixin {
  static const double _size = 80;
  static const _tabular = [ui.FontFeature.tabularFigures()];

  // 0 = photo, 1 = recording
  late final AnimationController _recordAnim;
  // Drives the pulse, blinking dot and the smooth progress ring while recording
  late final AnimationController _pulse;
  // Zoom dial visibility
  late final AnimationController _dialAnim;

  bool _pressed = false;
  double _dragStartY = 0;

  @override
  void initState() {
    super.initState();
    _recordAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _dialAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    widget.zoomActive.addListener(_onZoomActiveChanged);
    if (widget.isRecording) {
      _recordAnim.value = 1;
      _pulse.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedCaptureButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomActive != widget.zoomActive) {
      oldWidget.zoomActive.removeListener(_onZoomActiveChanged);
      widget.zoomActive.addListener(_onZoomActiveChanged);
    }
    if (widget.isRecording && !oldWidget.isRecording) {
      _recordAnim.forward();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _recordAnim.reverse();
    }
    final bool animating = widget.isRecording || widget.isBoomerangCapturing;
    if (animating && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!animating && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  void _onZoomActiveChanged() {
    if (widget.zoomActive.value) {
      _dialAnim.forward();
    } else {
      _dialAnim.reverse();
    }
  }

  @override
  void dispose() {
    widget.zoomActive.removeListener(_onZoomActiveChanged);
    _recordAnim.dispose();
    _pulse.dispose();
    _dialAnim.dispose();
    super.dispose();
  }

  static String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildButton() {
    return AnimatedBuilder(
      animation: Listenable.merge([_recordAnim, _pulse]),
      builder: (context, _) {
        final double t = _recordAnim.value;
        final double grow = Curves.easeOutBack.transform(t);
        // 0..1..0 once per pulse period
        final double pulse = 0.5 - 0.5 * math.cos(_pulse.value * 2 * math.pi);
        final Duration elapsed = widget.recordStopwatch.elapsed;
        final double progress = (elapsed.inMilliseconds % 60000) / 60000;

        final double coreSize = ui.lerpDouble(60, 56, t)! * (1 + 0.03 * pulse * t);
        final Color coreColor = Color.lerp(Colors.white, const Color(0xFFFF3B30), t)!;

        return Transform.scale(
          scale: 1 + 0.22 * grow,
          child: CustomPaint(
            size: const Size.square(_size),
            painter: _RingPainter(recording: t, progress: progress, pulse: pulse),
            child: SizedBox.square(
              dimension: _size,
              // Plain Container: this subtree rebuilds every frame while
              // recording, and an implicit animation would restart each frame
              // and never reach its target (the core would stay unpainted).
              child: Center(
                child: AnimatedScale(
                  scale: _pressed ? 0.86 : 1.0,
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeOut,
                  child: Container(
                    width: coreSize,
                    height: coreSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: t > 0 ? RadialGradient(colors: [Color.lerp(Colors.white, const Color(0xFFFF5A4F), t)!, Color.lerp(Colors.white, const Color(0xFFD70015), t)!]) : null,
                      color: t > 0 ? null : coreColor,
                      boxShadow: [
                        if (t > 0)
                          BoxShadow(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.35 + 0.35 * pulse * t),
                            blurRadius: 8 + 12 * pulse,
                            spreadRadius: 1 + 2 * pulse,
                          )
                        else
                          const BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: t < 0.4
                        ? null
                        : Opacity(
                            opacity: ((t - 0.4) / 0.6).clamp(0.0, 1.0),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Blinking "on air" dot
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(alpha: 0.35 + 0.65 * pulse),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _formatElapsed(elapsed),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        fontFeatures: _tabular,
                                        shadows: [Shadow(color: Colors.black38, blurRadius: 3)],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBoomerangButton() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, widget.boomerangProgress]),
      builder: (context, _) {
        final bool capturing = widget.isBoomerangCapturing;
        final double spin = _pulse.value;

        return AnimatedScale(
          scale: capturing ? 1.16 : 1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: CustomPaint(
            size: const Size.square(_size),
            painter: _BoomerangRingPainter(progress: capturing ? widget.boomerangProgress.value : null, seconds: widget.boomerangSeconds),
            child: SizedBox.square(
              dimension: _size,
              child: Center(
                // Size changes animate via AnimatedScale (its target only
                // changes on press/capture), the per-frame spin via a plain
                // Container.
                child: AnimatedScale(
                  scale: (capturing ? 0.9 : 1.0) * (_pressed ? 0.86 : 1.0),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: capturing ? null : Colors.white,
                      gradient: capturing ? SweepGradient(colors: const [...kBoomerangGradient, Color(0xFF7C4DFF)], transform: GradientRotation(spin * 2 * math.pi)) : null,
                      boxShadow: [
                        BoxShadow(
                          color: capturing ? kBoomerangGradient[2].withValues(alpha: 0.55) : Colors.black26,
                          blurRadius: capturing ? 16 : 6,
                          offset: capturing ? Offset.zero : const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: capturing
                        ? const Icon(Icons.all_inclusive, color: Colors.white, size: 30)
                        : ShaderMask(
                            shaderCallback: (r) => const LinearGradient(colors: kBoomerangGradient).createShader(r),
                            child: const Icon(Icons.all_inclusive, color: Colors.white, size: 34),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPressStart: (_) {
        setState(() => _pressed = false);
        widget.onZoomStart();
        widget.onLongPressStart();
      },
      onLongPressMoveUpdate: (details) => widget.onSlideZoom(details.localOffsetFromOrigin.dy),
      onLongPressEnd: (_) => widget.onLongPressEnd(),
      onVerticalDragStart: (details) {
        _dragStartY = details.localPosition.dy;
        widget.onZoomStart();
      },
      onVerticalDragUpdate: (details) => widget.onSlideZoom(details.localPosition.dy - _dragStartY),
      child: SizedBox.square(
        dimension: _size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Zoom dial, centred on the button and drawn above it
            IgnorePointer(
              child: OverflowBox(
                maxWidth: _ZoomDialPainter.boxSize.width,
                maxHeight: _ZoomDialPainter.boxSize.height,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: _ZoomDialPainter.boxSize,
                    painter: _ZoomDialPainter(
                      zoom: widget.zoomLevel,
                      range: widget.zoomRange,
                      visibility: _dialAnim,
                      recording: _recordAnim,
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    ),
                  ),
                ),
              ),
            ),
            widget.boomerangMode ? _buildBoomerangButton() : _buildButton(),
          ],
        ),
      ),
    );
  }
}

/// Outer ring: brand-coloured when idle; while recording a faint track with a
/// red sweep that fills clockwise once per minute, tipped with a glowing dot.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.recording, required this.progress, required this.pulse});

  final double recording;
  final double progress;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const double radius = 37;

    if (recording < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.deepPurpleAccent.withValues(alpha: 1 - recording),
      );
    }
    if (recording <= 0) return;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.white.withValues(alpha: 0.28 * recording),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    final double sweep = 2 * math.pi * progress;
    if (sweep > 0.01) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: 2 * math.pi,
            transform: const GradientRotation(-math.pi / 2),
            colors: [
              const Color(0xFFFF8A80).withValues(alpha: recording),
              const Color(0xFFFF3B30).withValues(alpha: recording),
            ],
          ).createShader(rect),
      );
    }

    // Glowing head of the sweep
    final double headAngle = -math.pi / 2 + sweep;
    final head = center + Offset(math.cos(headAngle), math.sin(headAngle)) * radius;
    canvas.drawCircle(
      head,
      5 + 2 * pulse,
      Paint()
        ..color = const Color(0xFFFF3B30).withValues(alpha: 0.35 * recording)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(head, 2.8, Paint()..color = Colors.white.withValues(alpha: recording));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.recording != recording || old.progress != progress || old.pulse != pulse;
}

/// Boomerang ring: a full gradient ring when ready; while capturing, a faint
/// track that fills clockwise with the gradient, with a tick at each second.
class _BoomerangRingPainter extends CustomPainter {
  _BoomerangRingPainter({required this.progress, required this.seconds});

  /// Null when not capturing.
  final double? progress;
  final int seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const double radius = 37;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const gradient = SweepGradient(colors: [...kBoomerangGradient, Color(0xFF7C4DFF)], transform: GradientRotation(-math.pi / 2));

    final double? p = progress;
    if (p == null) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..shader = gradient.createShader(rect),
      );
      return;
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white24,
    );
    if (p > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * p,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..shader = gradient.createShader(rect),
      );
    }
    // Second markers
    final tick = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white70;
    for (int i = 1; i < seconds; i++) {
      final double a = -math.pi / 2 + 2 * math.pi * i / seconds;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (radius - 4), center + dir * (radius + 4), tick);
    }
  }

  @override
  bool shouldRepaint(_BoomerangRingPainter old) => old.progress != progress || old.seconds != seconds;
}

/// Half-circle zoom dial around the top of the shutter. Values are spaced on
/// a log scale; zooming in turns the dial anticlockwise, zooming out turns it
/// clockwise, with the current level under a fixed pointer at 12 o'clock.
/// When the dial is hidden but the camera is zoomed, a small pill shows the level.
class _ZoomDialPainter extends CustomPainter {
  _ZoomDialPainter({required this.zoom, required this.range, required this.visibility, required this.recording, required this.fontFamily})
    : super(repaint: Listenable.merge([zoom, range, visibility, recording]));

  final ValueListenable<double> zoom;
  final ValueListenable<({double min, double max})> range;
  final Animation<double> visibility;

  /// Recording transition (the button grows), so the level pill stays clear of it.
  final Animation<double> recording;
  final String? fontFamily;

  static const double radius = 112;
  static const Size boxSize = Size(2 * (radius + 36), 2 * (radius + 52));
  // Degrees the dial turns per doubling of zoom
  static const double degreesPerDoubling = 60;
  static const double visibleHalfAngle = 78;

  static const Color _accent = Color(0xFFFFC83D);

  final Map<String, TextPainter> _textCache = {};

  static double _log2(double v) => math.log(v) / math.ln2;

  static String format(double z) {
    final text = z.toStringAsFixed(1);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}x';
  }

  TextPainter _text(String text, double size, Color color, {FontWeight weight = FontWeight.w700}) {
    final key = '$text|$size|${color.toARGB32()}|${weight.value}';
    return _textCache.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: fontFamily,
            color: color,
            fontSize: size,
            fontWeight: weight,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
            shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  /// Labelled stops: the widest zoom-out, whole steps, then coarser steps.
  static List<double> _labelValues(double min, double max) {
    final values = <double>[];
    if (min < 0.95) values.add((min * 10).ceil() / 10);
    for (final v in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 15.0, 20.0, 30.0, 50.0, 100.0]) {
      if (v >= min - 0.001 && v <= max + 0.001) values.add(v);
    }
    return values;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double current = zoom.value;
    final double show = Curves.easeOut.transform(visibility.value);
    final center = size.center(Offset.zero);
    final ({double min, double max}) r = range.value;

    // Compact level pill while zoomed and the dial is hidden
    final bool zoomed = (current - 1.0).abs() >= 0.05;
    if (zoomed && show < 1) {
      _drawPill(canvas, center - Offset(0, 56 + 10 * recording.value), format(current), 1 - show, small: true);
    }
    if (show <= 0 || r.max <= r.min) return;

    canvas.save();
    // Slight grow as it appears
    final double scale = 0.92 + 0.08 * show;
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    const double halfRad = visibleHalfAngle * math.pi / 180;

    // Soft dark band behind ticks and labels, fading out at both ends
    final bandRect = Rect.fromCircle(center: Offset.zero, radius: radius - 16);
    canvas.drawArc(
      bandRect,
      -math.pi / 2 - halfRad,
      2 * halfRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 50
        ..shader = SweepGradient(
          startAngle: -math.pi / 2 - halfRad,
          endAngle: -math.pi / 2 + halfRad,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.42 * show),
            Colors.black.withValues(alpha: 0.42 * show),
            Colors.black.withValues(alpha: 0),
          ],
          stops: const [0, 0.25, 0.75, 1],
        ).createShader(bandRect),
    );

    final double currentLog = _log2(current);
    double angleOf(double logValue) => (logValue - currentLog) * degreesPerDoubling;
    double fadeFor(double deg) {
      final double f = 1 - math.pow(deg.abs() / visibleHalfAngle, 3).toDouble();
      return f.clamp(0.0, 1.0) * show;
    }

    // Minor ticks, evenly spaced in log space (8 per doubling)
    final double minLog = _log2(r.min), maxLog = _log2(r.max);
    const double step = 1 / 8;
    final tickPaint = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (double l = (minLog / step).ceil() * step; l <= maxLog + 1e-6; l += step) {
      final double deg = angleOf(l);
      if (deg.abs() > visibleHalfAngle) continue;
      final double fade = fadeFor(deg);
      canvas.save();
      canvas.rotate(deg * math.pi / 180);
      tickPaint.color = Colors.white.withValues(alpha: 0.55 * fade);
      canvas.drawLine(const Offset(0, -radius), const Offset(0, -radius + 6), tickPaint);
      canvas.restore();
    }

    // Labelled stops with long ticks; the one nearest the pointer lights up
    final majorPaint = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (final v in _labelValues(r.min, r.max)) {
      final double deg = angleOf(_log2(v));
      if (deg.abs() > visibleHalfAngle) continue;
      final double fade = fadeFor(deg);
      final bool near = deg.abs() < 4;
      canvas.save();
      canvas.rotate(deg * math.pi / 180);
      majorPaint.color = (near ? _accent : Colors.white).withValues(alpha: fade);
      canvas.drawLine(const Offset(0, -radius), const Offset(0, -radius + 12), majorPaint);
      final tp = _text(format(v), near ? 14 : 12.5, near ? _accent : Colors.white);
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: fade));
      tp.paint(canvas, Offset(-tp.width / 2, -radius + 16));
      canvas.restore();
      canvas.restore();
    }

    // Fixed pointer at 12 o'clock
    final pointer = Path()
      ..moveTo(0, -radius + 2)
      ..lineTo(-6, -radius - 7)
      ..lineTo(6, -radius - 7)
      ..close();
    canvas.drawPath(pointer, Paint()..color = _accent.withValues(alpha: show));
    canvas.restore();

    // Current level pill above the pointer
    _drawPill(canvas, center - Offset(0, (radius + 22) * scale), format(current), show);
  }

  void _drawPill(Canvas canvas, Offset at, String label, double opacity, {bool small = false}) {
    if (opacity <= 0) return;
    final tp = _text(label, small ? 11 : 15, Colors.black, weight: FontWeight.w800);
    final double padH = small ? 7 : 11, padV = small ? 2 : 5;
    final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: at, width: tp.width + padH * 2, height: tp.height + padV * 2), const Radius.circular(20));
    canvas.saveLayer(rect.outerRect.inflate(8), Paint()..color = Colors.white.withValues(alpha: opacity));
    canvas.drawRRect(
      rect.shift(const Offset(0, 1.5)),
      Paint()
        ..color = Colors.black38
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(rect, Paint()..color = _accent);
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ZoomDialPainter old) => old.zoom != zoom || old.range != range || old.visibility != visibility || old.recording != recording || old.fontFamily != fontFamily;
}
