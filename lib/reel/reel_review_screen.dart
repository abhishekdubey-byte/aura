import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/media_library.dart';
import '../services/streak_service.dart';
import '../services/upload_manager.dart';

class ReelReviewScreen extends StatefulWidget {
  const ReelReviewScreen({super.key, required this.path});
  final String path;
  @override
  State<ReelReviewScreen> createState() => _ReelReviewScreenState();
}

class _ReelReviewScreenState extends State<ReelReviewScreen>
    with WidgetsBindingObserver {
  late final _player = VideoPlayerController.file(File(widget.path));
  bool _ready = false, _saving = false, _saved = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      await _player.initialize();
      await _player.setLooping(true);
      if (!mounted) return;
      setState(() => _ready = true);
      await _player.play();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Preview unavailable. You can still save the reel or go back to your clips.',
        );
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _saved) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UploadManager.instance.enqueue(widget.path);
      await MediaLibrary.saveVideo(
        widget.path,
        MediaAlbum.videos,
        keepSource: true,
      );
      if (mounted) setState(() => _saved = true);
      try {
        await StreakService.incrementStreak();
      } catch (_) {}
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save to gallery. Check gallery access and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _ready) _player.pause();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _ready
                    ? AspectRatio(
                        aspectRatio: _player.value.aspectRatio,
                        child: VideoPlayer(_player),
                      )
                    : _error != null
                    ? const Icon(Icons.videocam_off_outlined)
                    : const CircularProgressIndicator(),
              ),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Edit clips'),
                  ),
                  if (_ready)
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _player,
                      builder: (_, value, _) => IconButton(
                        tooltip: value.isPlaying ? 'Pause' : 'Play',
                        onPressed: () =>
                            value.isPlaying ? _player.pause() : _player.play(),
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _saving || _saved ? null : _save,
                    icon: Icon(_saved ? Icons.check : Icons.save_alt),
                    label: Text(
                      _saved
                          ? 'Saved to gallery'
                          : _saving
                          ? 'Saving…'
                          : 'Save reel',
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
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }
}
