import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/aura_theme.dart';
import 'aura_controls.dart';

/// AURA brand colours (purple → magenta → pink → orange).
const List<Color> kAuraGradient = AuraColors.gradient;

/// Slowly drifting, blurred colour blobs on black: the backdrop for the
/// first-run screens.
class AuraBackdrop extends StatefulWidget {
  const AuraBackdrop({super.key, this.child, this.intensity = 1.0});

  final Widget? child;

  /// 0..1, how bright the blobs are.
  final double intensity;

  @override
  State<AuraBackdrop> createState() => _AuraBackdropState();
}

class _AuraBackdropState extends State<AuraBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AuraColors.background),
        RepaintBoundary(
          child: CustomPaint(painter: _BlobPainter(_drift, widget.intensity)),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.t, this.intensity) : super(repaint: t);

  final Animation<double> t;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final double a = t.value * 2 * math.pi;
    final blobs = [
      (
        Offset(0.2 + 0.12 * math.sin(a), 0.22 + 0.08 * math.cos(a * 0.8)),
        0.55,
        kAuraGradient[0],
      ),
      (
        Offset(0.85 + 0.1 * math.cos(a * 0.7), 0.45 + 0.1 * math.sin(a)),
        0.5,
        kAuraGradient[1],
      ),
      (
        Offset(0.3 + 0.15 * math.cos(a * 1.1), 0.85 + 0.06 * math.sin(a * 0.9)),
        0.6,
        AuraColors.blue,
      ),
    ];
    for (final (center, radius, color) in blobs) {
      final c = Offset(center.dx * size.width, center.dy * size.height);
      final double r = radius * size.width;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [
            color.withValues(alpha: 0.13 * intensity),
            color.withValues(alpha: 0),
          ]),
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.intensity != intensity;
}

/// The AURA mark: a glowing orb with a rotating gradient ring.
class AuraOrb extends StatefulWidget {
  const AuraOrb({super.key, this.size = 120});

  final double size;

  @override
  State<AuraOrb> createState() => _AuraOrbState();
}

class _AuraOrbState extends State<AuraOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) {
          final double pulse = 0.5 + 0.5 * math.sin(_spin.value * 4 * math.pi);
          return SizedBox.square(
            dimension: widget.size,
            child: CustomPaint(
              painter: _OrbPainter(_spin.value, pulse),
              child: Center(
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Colors.white, Color(0xFFFFD6F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(r),
                  child: Icon(
                    Icons.auto_awesome,
                    size: widget.size * 0.36,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.spin, this.pulse);

  final double spin;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final double r = size.width / 2;

    // Outer glow
    canvas.drawCircle(
      c,
      r * (0.95 + 0.05 * pulse),
      Paint()
        ..color = kAuraGradient[1].withValues(alpha: 0.35 + 0.15 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35),
    );
    // Core
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..shader = ui.Gradient.radial(
          c.translate(-r * 0.15, -r * 0.2),
          r * 0.8,
          [const Color(0xFF3A1D6E), const Color(0xFF12071F)],
        ),
    );
    // Rotating gradient ring
    final rect = Rect.fromCircle(center: c, radius: r * 0.72);
    canvas.drawCircle(
      c,
      r * 0.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..shader = SweepGradient(
          colors: const [...kAuraGradient, AuraColors.violet],
          transform: GradientRotation(spin * 2 * math.pi),
        ).createShader(rect),
    );
    // Orbiting spark
    final double a = spin * 2 * math.pi * 2;
    final spark = c + Offset(math.cos(a), math.sin(a)) * r * 0.72;
    canvas.drawCircle(
      spark,
      r * 0.08,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
    );
    canvas.drawCircle(spark, r * 0.035, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.spin != spin || old.pulse != pulse;
}

/// Text with a light sweep moving across it.
class ShimmerText extends StatefulWidget {
  const ShimmerText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) {
          final double x = -1.5 + 3 * _c.value;
          return LinearGradient(
            begin: Alignment(x - 0.6, 0),
            end: Alignment(x + 0.6, 0),
            colors: const [Colors.white, Color(0xFFFFC6F0), Colors.white],
            stops: const [0.2, 0.5, 0.8],
          ).createShader(r);
        },
        child: child,
      ),
      child: Text(widget.text, style: widget.style),
    );
  }
}

/// Primary call-to-action: brand gradient, press bounce, haptic, and an
/// optional busy state.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) =>
      AuraButton(label: label, onPressed: onPressed, icon: icon, busy: busy);
}

/// Fades and slides a child up after [delay] (for staggered entrances).
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 24,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Shared panel styling for forms.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) =>
      AuraPanel(padding: padding, child: child);
}

/// Standard platform navigation for branded screens.
class AuraRoute<T> extends MaterialPageRoute<T> {
  AuraRoute(Widget page) : super(builder: (_) => page);
}
