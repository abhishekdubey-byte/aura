import 'dart:io';
import 'dart:ui' as ui;

import 'package:aura/boomerang/boomerang_effect.dart';
import 'package:aura/boomerang/boomerang_player.dart';
import 'package:aura/boomerang/infinity_loader.dart';
import 'package:aura/services/video_processor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/aura_theme.dart';
import '../widgets/aura_controls.dart';

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
  final double? aspect;
  final void Function(BoomerangEffect effect, int frameCount) onSave;
  @override
  State<BoomerangScreen> createState() => _BoomerangScreenState();
}

class _BoomerangScreenState extends State<BoomerangScreen> {
  List<ui.Image>? _frames;
  Directory? _framesDir;
  String? _error;
  BoomerangEffect _effect = BoomerangEffect.classic;
  bool _sharing = false, _preparing = false, _saving = false;
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (_preparing) return;
    setState(() {
      _preparing = true;
      _error = null;
    });
    final frames = <ui.Image>[];
    Directory? dir;
    try {
      final paths = await VideoProcessor.extractFrames(
        widget.videoPath,
        seconds: widget.seconds,
        mirror: widget.mirror,
        aspect: widget.aspect,
        width: widget.seconds > 2.2 ? 400 : 432,
      );
      if (paths == null || paths.length < 4) throw StateError('Clip too short');
      dir = File(paths.first).parent;
      for (final path in paths) {
        if (!mounted) break;
        final codec = await ui.instantiateImageCodec(
          await File(path).readAsBytes(),
        );
        try {
          frames.add((await codec.getNextFrame()).image);
        } finally {
          codec.dispose();
        }
      }
      if (!mounted) return;
      _framesDir = dir;
      setState(() => _frames = frames);
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Boomerang preview: $e');
      if (mounted) {
        setState(
          () => _error = 'We couldn’t prepare this clip. Try again, or retake a slightly longer moment.',
        );
      }
    } finally {
      if (!mounted || _frames != frames) {
        for (final frame in frames) {
          frame.dispose();
        }
        if (dir != null) {
          await dir.delete(recursive: true).catchError((_) => dir!);
        }
      }
      if (mounted) setState(() => _preparing = false);
    }
  }

  void _save() {
    if (_frames == null || _sharing || _saving) return;
    setState(() => _saving = true);
    try {
      widget.onSave(_effect, _frames!.length);
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save the boomerang. Please try again.';
      });
    }
  }

  Future<void> _share() async {
    if (_frames == null || _sharing || _saving) return;
    final effect = _effect;
    setState(() => _sharing = true);
    try {
      final output = await VideoProcessor.boomerang(
        widget.videoPath,
        seconds: widget.seconds,
        mirror: widget.mirror,
        frameCount: _frames!.length,
        effect: effect,
        aspect: widget.aspect,
      );
      if (output == null) throw StateError('Render failed');
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(output)],
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      debugPrint('Boomerang share: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not share the boomerang. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sharing && !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Boomerang'),
        actions: [
          IconButton(
            tooltip: 'Retake',
            onPressed: _sharing || _saving
                ? null
                : () => Navigator.pop(context),
            icon: const Icon(Icons.replay_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Center(
                  child: _error != null && _frames == null
                      ? AuraEmptyState(
                          icon: Icons.movie_outlined,
                          title: 'Let’s try that again',
                          message: _error!,
                          action: 'Retry preview',
                          onAction: _prepare,
                        )
                      : AspectRatio(
                          aspectRatio: _frames == null
                              ? widget.aspect ?? 9 / 16
                              : _frames!.first.width / _frames!.first.height,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                const ColoredBox(color: AuraColors.surface),
                                if (_frames == null)
                                  const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InfinityLoader(size: 80),
                                        SizedBox(height: 16),
                                        Text('Preparing your loop…'),
                                      ],
                                    ),
                                  )
                                else
                                  BoomerangPlayer(
                                    frames: _frames!,
                                    effect: _effect,
                                  ),
                                if (_sharing)
                                  const ColoredBox(
                                    color: AuraColors.scrim,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final effect in BoomerangEffect.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(
                          effect.icon,
                          size: 18,
                          color: AuraColors.primary,
                        ),
                        label: Text(effect.label),
                        selected: _effect == effect,
                        onSelected: _frames == null || _sharing || _saving
                            ? null
                            : (_) {
                                HapticFeedback.selectionClick();
                                setState(() => _effect = effect);
                              },
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _frames == null || _sharing || _saving
                          ? null
                          : _share,
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Share'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AuraButton(
                      label: 'Save loop',
                      icon: Icons.download_rounded,
                      busy: _saving,
                      onPressed: _frames == null || _sharing ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    for (final frame in _frames ?? <ui.Image>[]) {
      frame.dispose();
    }
    _framesDir?.delete(recursive: true).ignore();
    super.dispose();
  }
}
