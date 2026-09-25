import 'dart:ui' as ui;

import 'package:aura/boomerang/boomerang_effect.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Plays decoded frames as a live boomerang loop. Effects switch instantly
/// because timing is computed per frame rather than baked into a video.
class BoomerangPlayer extends StatefulWidget {
  const BoomerangPlayer({super.key, required this.frames, required this.effect});

  final List<ui.Image> frames;
  final BoomerangEffect effect;

  @override
  State<BoomerangPlayer> createState() => _BoomerangPlayerState();
}

class _BoomerangPlayerState extends State<BoomerangPlayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<Duration> _clock = ValueNotifier(Duration.zero);
  Duration _offset = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _clock.value = elapsed - _offset)..start();
  }

  @override
  void didUpdateWidget(BoomerangPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect != widget.effect) {
      // Restart the loop from the first frame so the new effect reads clearly
      _offset += _clock.value;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BoomerangPainter(
          frames: widget.frames,
          timing: BoomerangTiming(widget.effect, widget.frames.length),
          clock: _clock,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BoomerangPainter extends CustomPainter {
  _BoomerangPainter({required this.frames, required this.timing, required this.clock}) : super(repaint: clock);

  final List<ui.Image> frames;
  final BoomerangTiming timing;
  final ValueListenable<Duration> clock;

  // Trail opacities for the echo effect, newest ghost first
  static const List<double> _echoAlphas = [0.34, 0.22, 0.12];

  @override
  void paint(Canvas canvas, Size size) {
    final double t = clock.value.inMicroseconds / 1e6;
    final rect = Offset.zero & size;
    _draw(canvas, rect, timing.frameAt(t), 1);
    if (timing.effect.echo) {
      for (int i = 0; i < _echoAlphas.length; i++) {
        _draw(canvas, rect, timing.frameAt(t - (i + 1) * 2 / timing.fps), _echoAlphas[i]);
      }
    }
  }

  void _draw(Canvas canvas, Rect rect, int index, double opacity) {
    paintImage(
      canvas: canvas,
      rect: rect,
      image: frames[index],
      fit: BoxFit.cover,
      opacity: opacity,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_BoomerangPainter old) =>
      old.frames != frames || old.timing.effect != timing.effect || old.clock != clock;
}
