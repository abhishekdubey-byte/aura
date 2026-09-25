import 'dart:io';
import 'dart:ui' as ui;

import 'package:aura/boomerang/boomerang_effect.dart';
import 'package:aura/boomerang/boomerang_player.dart';
import 'package:aura/boomerang/infinity_loader.dart';
import 'package:aura/services/video_processor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Review screen for a freshly captured boomerang: a live looping preview with
/// instantly switchable effects, then Save (rendered in the background at full
/// quality) or Share.
class BoomerangScreen extends StatefulWidget {
  const BoomerangScreen({
    super.key,
    required this.videoPath,
    required this.seconds,
    required this.mirror,
    this.aspect,
    required this.onSave,
  });

  final String videoPath;
  final double seconds;
  final bool mirror;
  /// Framing (width / height) to crop to, or null for the full recording.
  final double? aspect;
  /// Called when the user saves; the caller renders and stores the video.
  final void Function(BoomerangEffect effect, int frameCount) onSave;

  @override
  State<BoomerangScreen> createState() => _BoomerangScreenState();
}

class _BoomerangScreenState extends State<BoomerangScreen> {
  List<ui.Image>? _frames;
  Directory? _framesDir;
  String? _error;
  BoomerangEffect _effect = BoomerangEffect.classic;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final paths = await VideoProcessor.extractFrames(
      widget.videoPath,
      seconds: widget.seconds,
      mirror: widget.mirror,
      aspect: widget.aspect,
      // Keep preview memory bounded for the longest clips
      width: widget.seconds > 2.2 ? 400 : 432,
    );
    if (paths == null || paths.length < 4) {
      if (mounted) setState(() => _error = 'That was too quick. Try holding still a moment longer.');
      return;
    }
    _framesDir = File(paths.first).parent;

    final frames = <ui.Image>[];
    for (final path in paths) {
      final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
      frames.add((await codec.getNextFrame()).image);
      codec.dispose();
      if (!mounted) {
        for (final f in frames) {
          f.dispose();
        }
        return;
      }
    }
    HapticFeedback.lightImpact();
    setState(() => _frames = frames);
  }

  @override
  void dispose() {
    for (final f in _frames ?? const <ui.Image>[]) {
      f.dispose();
    }
    _framesDir?.delete(recursive: true).ignore();
    super.dispose();
  }

  void _selectEffect(BoomerangEffect effect) {
    if (effect == _effect) return;
    HapticFeedback.selectionClick();
    setState(() => _effect = effect);
  }

  void _save() {
    final frames = _frames;
    if (frames == null) return;
    HapticFeedback.mediumImpact();
    widget.onSave(_effect, frames.length);
    Navigator.pop(context);
  }

  Future<void> _share() async {
    final frames = _frames;
    if (frames == null || _sharing) return;
    setState(() => _sharing = true);
    final output = await VideoProcessor.boomerang(
      widget.videoPath,
      seconds: widget.seconds,
      mirror: widget.mirror,
      frameCount: frames.length,
      effect: _effect,
      aspect: widget.aspect,
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    if (output == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create the boomerang')));
      return;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(output)]));
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    // While preparing, the card already takes the chosen framing's shape
    final double aspect = frames == null ? (widget.aspect ?? 9 / 16) : frames.first.width / frames.first.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: _buildPreviewCard(frames),
                  ),
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: frames == null ? 0.3 : 1,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: frames == null,
                child: Column(
                  children: [
                    _buildEffectPicker(),
                    const SizedBox(height: 14),
                    _buildActions(),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Discard',
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: kBoomerangGradient).createShader(r),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.all_inclusive, color: Colors.white, size: 22),
                SizedBox(width: 6),
                Text('Boomerang', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(List<ui.Image>? frames) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: kBoomerangGradient[1].withValues(alpha: 0.25), blurRadius: 40, spreadRadius: 2),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF121212)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: frames == null
                  ? Center(
                      key: const ValueKey('loading'),
                      child: _error != null
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 15),
                              ),
                            )
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InfinityLoader(size: 110),
                                SizedBox(height: 18),
                                Text('Creating your boomerang…', style: TextStyle(color: Colors.white70)),
                              ],
                            ),
                    )
                  : BoomerangPlayer(key: const ValueKey('player'), frames: frames, effect: _effect),
            ),
            if (_sharing)
              const ColoredBox(
                color: Colors.black54,
                child: Center(child: InfinityLoader(size: 90)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectPicker() {
    return SizedBox(
      height: 86,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final effect in BoomerangEffect.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: _EffectChip(
                effect: effect,
                selected: effect == _effect,
                onTap: () => _selectEffect(effect),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _RoundAction(
            icon: Icons.replay,
            tooltip: 'Retake',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: _save,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(colors: kBoomerangGradient),
                  boxShadow: [
                    BoxShadow(color: kBoomerangGradient[2].withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6)),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.download_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Save', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          _RoundAction(
            icon: Icons.ios_share_rounded,
            tooltip: 'Share',
            onTap: _share,
          ),
        ],
      ),
    );
  }
}

class _EffectChip extends StatelessWidget {
  const _EffectChip({required this.effect, required this.selected, required this.onTap});

  final BoomerangEffect effect;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: selected ? 1.08 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Container(
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selected ? const SweepGradient(colors: [...kBoomerangGradient, Color(0xFF7C4DFF)]) : null,
                color: selected ? null : Colors.white12,
              ),
              child: Container(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1C1C1E)),
                child: Icon(effect.icon, color: selected ? Colors.white : Colors.white70, size: 26),
              ),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
            child: Text(effect.label),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.1),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
