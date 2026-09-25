import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:aura/camera/capture_aspect.dart';
import 'package:aura/services/media_library.dart';

import 'layout_draft.dart';
import 'layout_exporter.dart';
import 'layout_store.dart';
import 'layout_widgets.dart';

class LayoutReviewScreen extends StatefulWidget {
  const LayoutReviewScreen({
    super.key,
    required this.draft,
    required this.store,
  });
  final LayoutDraft draft;
  final LayoutStore store;
  @override
  State<LayoutReviewScreen> createState() => _LayoutReviewScreenState();
}

class _LayoutReviewScreenState extends State<LayoutReviewScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _player;
  String? _output;
  String? _error;
  bool _rendering = false, _saving = false;
  double _progress = 0;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _render();
  }

  Future<void> _render() async {
    if (_rendering || _saving) return;
    final generation = ++_generation;
    setState(() {
      _rendering = true;
      _error = null;
      _progress = 0;
      _output = null;
    });
    await _player?.dispose();
    _player = null;
    try {
      await widget.store.save(widget.draft);
      final prefs = await SharedPreferences.getInstance();
      final watermark = prefs.getBool('watermark_enabled') == true
          ? prefs.getString('custom_watermark') ??
                'Calculate your Aura: Download AURA App'
          : null;
      final output = await LayoutExporter.render(
        widget.draft,
        watermark: watermark,
        onProgress: (p) {
          if (mounted && generation == _generation) {
            setState(() => _progress = p);
          }
        },
      );
      if (!mounted || generation != _generation) return;
      if (widget.draft.isVideo) {
        final player = VideoPlayerController.file(File(output));
        _player = player;
        await player.initialize();
        if (!mounted || generation != _generation) return;
        await player.setLooping(true);
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          await player.play();
        }
      }
      if (mounted) setState(() => _output = output);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not prepare the layout. Your cells are safe.\n$e',
        );
      }
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _save() async {
    if (_output == null || _saving || _rendering) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _player?.pause();
      // Preserve the rendered preview so a gallery permission failure is retryable.
      if (widget.draft.isVideo) {
        await MediaLibrary.saveVideo(
          _output!,
          MediaAlbum.videos,
          keepSource: true,
        );
      } else {
        final album =
            CaptureAspect.byId(widget.draft.aspectId).category ==
                AspectCategory.desktop
            ? MediaAlbum.wallpapers
            : MediaAlbum.snaps;
        await MediaLibrary.saveImage(_output!, album, keepSource: true);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save to the gallery. Check gallery access and retry.\n$e',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player?.pause();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_rendering,
    child: Scaffold(
      appBar: AppBar(title: const Text('Review layout')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: _output == null
                      ? LayoutGrid(draft: widget.draft, showSelection: false)
                      : widget.draft.isVideo
                      ? AspectRatio(
                          aspectRatio: _player!.value.aspectRatio,
                          child: VideoPlayer(_player!),
                        )
                      : Image.file(File(_output!), fit: BoxFit.contain),
                ),
              ),
            ),
            if (_rendering)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preparing layout${_progress > 0 ? ' • ${(_progress * 100).round()}%' : '…'}',
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                  maxLines: 4,
                ),
              ),
            if (widget.draft.isVideo)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('Audio: '),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: widget.draft.audioCell ?? -1,
                        items: [
                          const DropdownMenuItem(
                            value: -1,
                            child: Text('Mute'),
                          ),
                          for (int i = 0; i < widget.draft.media.length; i++)
                            if (widget.draft.media[i]?.hasAudio == true)
                              DropdownMenuItem(
                                value: i,
                                child: Text('Cell ${i + 1}'),
                              ),
                        ],
                        onChanged: _rendering || _saving
                            ? null
                            : (i) {
                                widget.draft.audioCell = i == -1 ? null : i;
                                _render();
                              },
                      ),
                    ),
                    if (_player != null && !_rendering)
                      IconButton(
                        tooltip: 'Play / pause',
                        onPressed: () => setState(() {
                          _player!.value.isPlaying
                              ? _player!.pause()
                              : _player!.play();
                        }),
                        icon: Icon(
                          _player!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                  ],
                ),
              ),
            if (widget.draft.isVideo)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Clips start together. Shorter clips hold their last frame.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: _rendering || _saving
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('Edit cells'),
                  ),
                  if (_output == null && !_rendering)
                    FilledButton(onPressed: _render, child: const Text('Retry'))
                  else
                    FilledButton.icon(
                      onPressed: _output == null || _rendering || _saving
                          ? null
                          : _save,
                      icon: const Icon(Icons.save_alt),
                      label: Text(_saving ? 'Saving…' : 'Save layout'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
