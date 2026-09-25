import 'dart:math' as math;

import 'package:aura/boomerang/boomerang_effect.dart';
import 'package:flutter/material.dart';

/// An ∞ traced by a glowing comet, used while a boomerang is being prepared.
class InfinityLoader extends StatefulWidget {
  const InfinityLoader({super.key, this.size = 96, this.strokeWidth = 5});

  final double size;
  final double strokeWidth;

  @override
  State<InfinityLoader> createState() => _InfinityLoaderState();
}

class _InfinityLoaderState extends State<InfinityLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(widget.size, widget.size / 2),
        painter: _InfinityPainter(_controller, widget.strokeWidth),
      ),
    );
  }
}

class _InfinityPainter extends CustomPainter {
  _InfinityPainter(this.progress, this.strokeWidth) : super(repaint: progress);

  final Animation<double> progress;
  final double strokeWidth;

  // Lemniscate of Bernoulli, scaled to the box
  Offset _point(double t, Size size) {
    final double a = size.width / 2 - strokeWidth;
    final double s = math.sin(t), c = math.cos(t);
    final double d = 1 + s * s;
    return Offset(size.width / 2 + a * c / d, size.height / 2 + a * s * c / d);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const int samples = 120;
    final track = Path();
    for (int i = 0; i <= samples; i++) {
      final p = _point(2 * math.pi * i / samples, size);
      i == 0 ? track.moveTo(p.dx, p.dy) : track.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    // Comet: a tail of short segments fading into the head
    const int tail = 42;
    final double head = progress.value * 2 * math.pi;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < tail; i++) {
      final double f = i / tail;
      final double t0 = head - (1 - f) * math.pi * 0.9;
      final double t1 = head - (1 - (i + 1) / tail) * math.pi * 0.9;
      final Color color = _gradientAt(f).withValues(alpha: f);
      paint
        ..strokeWidth = strokeWidth * (0.4 + 0.6 * f)
        ..color = color;
      canvas.drawLine(_point(t0, size), _point(t1, size), paint);
    }
    final Offset tip = _point(head, size);
    canvas.drawCircle(
      tip,
      strokeWidth * 1.6,
      Paint()
        ..color = kBoomerangGradient.last.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(tip, strokeWidth * 0.7, Paint()..color = Colors.white);
  }

  static Color _gradientAt(double f) {
    final double scaled = f * (kBoomerangGradient.length - 1);
    final int i = scaled.floor().clamp(0, kBoomerangGradient.length - 2);
    return Color.lerp(kBoomerangGradient[i], kBoomerangGradient[i + 1], scaled - i)!;
  }

  @override
  bool shouldRepaint(_InfinityPainter old) => old.progress != progress || old.strokeWidth != strokeWidth;
}
