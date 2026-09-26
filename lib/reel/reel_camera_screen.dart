import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../camera/camera_session.dart';
import '../camera/capture_aspect.dart';
import '../services/capture_feedback.dart';
import '../services/upload_manager.dart';
import '../services/video_processor.dart';
import '../theme/aura_theme.dart';
import '../widgets/aspect_ratio_picker.dart';
import 'reel_duration_picker.dart';
import 'reel_review_screen.dart';
import 'reel_session.dart';
import '../hands_free/hands_free_commands.dart';
import '../hands_free/hands_free_controls.dart';
import '../hands_free/hands_free_preferences.dart';
import '../hands_free/preview_sampler.dart';

class ReelCameraScreen extends StatefulWidget {
  const ReelCameraScreen({
    super.key,
    required this.cameras,
    this.cameraIndex = 0,
  });
  final List<CameraDescription> cameras;
  final int cameraIndex;
  @override
  State<ReelCameraScreen> createState() => _ReelCameraScreenState();
}

class _ReelCameraScreenState extends State<ReelCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  final _previewKey = GlobalKey();
  final _handsFreeKey = GlobalKey<HandsFreeControlsState>();
  late int _cameraIndex;
  late final ReelSession _session;
  CaptureAspect _aspect = CaptureAspect.full;
  int? _seconds; // null: press and hold; otherwise hands-free.
  bool _busy = true, _away = false, _leaving = false, _reviewing = false;
  bool _flash = false, _suspending = false;
  int _generation = 0;
  DateTime? _startedAt;
  String? _error;
  Future<void>? _cameraOperation;
  int? _heldPointer;
  double _zoom = 1, _baseZoom = 1, _minZoom = 1, _maxZoom = 1;
  bool get _locked => _busy || _away || _suspending || _session.active;
  bool get _ready => !_busy && !_away && _camera?.value.isInitialized == true;
  bool get _front =>
      widget.cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    _cameraIndex = widget.cameraIndex.clamp(0, widget.cameras.length - 1);
    _session = ReelSession(
      startCapture: _startCapture,
      finishCapture: _finishCapture,
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _cameraOperation = _open();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _open({bool clearError = true}) async {
    final generation = ++_generation;
    if (_away || _leaving || _reviewing) return;
    if (mounted) {
      setState(() {
        _busy = true;
        if (clearError) _error = null;
      });
    }
    try {
      final camera = await CameraSession.open(widget.cameras[_cameraIndex]);
      if (!mounted || _away || _leaving || generation != _generation) {
        await camera.dispose();
        return;
      }
      _camera = camera;
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      final range = await CameraSession.zoomRange(camera);
      _minZoom = range.$1;
      _maxZoom = range.$2;
      _zoom = 1.0.clamp(_minZoom, _maxZoom);
      _flash = _flash && await CameraSession.flash(camera, FlashMode.torch);
    } catch (e) {
      _error = 'Camera unavailable. Check camera access and try again.';
      await _close();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    await _handsFreeKey.currentState?.suspend();
    _generation++;
    final camera = _camera;
    _camera = null;
    if (mounted) setState(() {});
    await camera?.dispose();
  }

  Future<void> _startCapture() async {
    final camera = _camera;
    if (!_ready || camera == null) throw StateError('Camera unavailable');
    if (!camera.enableAudio && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone unavailable; recording without sound.'),
        ),
      );
    }
    _handsFreeKey.currentState?.cancelPending();
    await _handsFreeKey.currentState?.prepareForVideo();
    await camera.startVideoRecording();
    _startedAt = DateTime.now();
    CaptureFeedback.videoStart();
  }

  Future<({String path, double seconds})> _finishCapture() async {
    try {
      return await _finishCaptureOnce();
    } catch (_) {
      // A failed native stop may leave the controller marked as recording.
      // Reopen it so the next clip is possible without losing earlier clips.
      await _close();
      if (mounted && !_away && !_leaving) {
        _cameraOperation = _open(clearError: false);
        await _cameraOperation;
      }
      rethrow;
    }
  }

  Future<({String path, double seconds})> _finishCaptureOnce() async {
    final camera = _camera;
    if (camera == null) throw StateError('Camera unavailable');
    String? path;
    if ((_away || _suspending) && Platform.isAndroid) {
      // CameraX finalizes on disposal after its preview surface is destroyed.
      // Calling stop at that point can crash the native recorder.
      final since = _startedAt!;
      await _close();
      final dir = await getTemporaryDirectory();
      final candidates =
          dir
              .listSync()
              .whereType<File>()
              .where(
                (file) =>
                    file.uri.pathSegments.last.startsWith('REC') &&
                    file.path.endsWith('.mp4') &&
                    file.lastModifiedSync().isAfter(
                      since.subtract(const Duration(seconds: 1)),
                    ),
              )
              .toList()
            ..sort(
              (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
            );
      if (candidates.isNotEmpty) {
        path = candidates.first.path;
        for (int i = 0; i < 20; i++) {
          if (await VideoProcessor.isPlayable(path)) break;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    } else {
      path = (await camera.stopVideoRecording()).path;
    }
    _startedAt = null;
    CaptureFeedback.videoStop();
    if (path == null) throw StateError('No finalized clip');
    await UploadManager.instance.enqueue(path);
    final seconds = await VideoProcessor.duration(path);
    if (seconds <= 0) throw StateError('Empty recording');
    return (path: path, seconds: seconds);
  }

  void _start() {
    if (!_ready || _session.active) return;
    final ratio = _aspect.resolveRatio(MediaQuery.sizeOf(context));
    _session.start(ratio: ratio, mirror: _front, seconds: _seconds);
  }

  void _shutter() {
    _handsFreeKey.currentState?.cancelPending();
    if (_session.active) {
      _session.stop();
    } else {
      _start();
    }
  }

  Future<void> _flip() async {
    if (_locked || widget.cameras.length < 2) return;
    await _handsFreeKey.currentState?.suspend();
    setState(() => _busy = true);
    _cameraOperation = () async {
      await _close();
      _cameraIndex = (_cameraIndex + 1) % widget.cameras.length;
      await _open();
    }();
    await _cameraOperation;
  }

  Future<void> _pickAspect() async {
    if (_locked) return;
    _handsFreeKey.currentState?.cancelPending();
    final aspect = await showAspectRatioPicker(
      context,
      current: _aspect,
      screen: MediaQuery.sizeOf(context),
    );
    if (mounted && aspect != null) setState(() => _aspect = aspect);
  }

  Future<void> _customTimer() async {
    if (_locked) return;
    _handsFreeKey.currentState?.cancelPending();
    final seconds = await showReelDurationPicker(context, _seconds ?? 5);
    if (mounted && seconds != null) setState(() => _seconds = seconds);
  }

  Future<void> _review() async {
    if (_locked || _session.clips.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _reviewing = true;
    });
    try {
      await _close();
      final output = await VideoProcessor.reel([
        for (final clip in _session.clips)
          (
            path: clip.path,
            mirror: clip.mirror,
            ratio: clip.ratio,
            seconds: clip.seconds,
          ),
      ], ratio: _session.clips.first.ratio);
      if (output == null) throw StateError('Reel export failed');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => ReelReviewScreen(path: output)),
      );
    } catch (_) {
      _error = 'Could not combine the reel. Your clips are still here; tap Preview reel to retry.';
    } finally {
      _reviewing = false;
      if (mounted) {
        setState(() => _busy = false);
        if (!_away) {
          _cameraOperation = _open(clearError: false);
          await _cameraOperation;
        }
      }
    }
  }

  Future<void> _leave() async {
    if (_busy || _session.active || _leaving) return;
    if (_session.clips.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave this reel?'),
          content: const Text(
            'Clips in this session will be discarded. Any reel already saved to your gallery will stay there.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    _leaving = true;
    await _close();
    if (mounted) Navigator.pop(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_leaving) return;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _away = true;
      _suspend();
    } else if (state == AppLifecycleState.resumed) {
      _away = false;
      if (!_suspending && !_reviewing && _camera == null) {
        _cameraOperation = _open();
      }
    }
  }

  Future<void> _suspend() async {
    if (_suspending) return;
    _suspending = true;
    _heldPointer = null;
    try {
      await _cameraOperation;
      await _session.stop();
      await _close();
    } finally {
      _suspending = false;
      if (mounted && !_away && !_leaving && !_reviewing) {
        _cameraOperation = _open();
      }
    }
  }

  Widget _preview() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const SizedBox.expand();
    }
    final size = MediaQuery.sizeOf(context);
    final geometry = ViewfinderGeometry.compute(
      screen: size,
      padding: MediaQuery.paddingOf(context),
      frameAspect: 1 / camera.value.aspectRatio,
      cropRatio: _aspect.resolveRatio(size),
      fieldAspect: 9 / 16,
      fillScreen: _aspect.isFull,
      bottomControls: 330,
    );
    return Stack(
      children: [
        Positioned.fromRect(
          rect: geometry.frame,
          child: GestureDetector(
            onScaleStart: (_) => _baseZoom = _zoom,
            onScaleUpdate: (details) {
              _zoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
              camera.setZoomLevel(_zoom).catchError((Object _) {});
            },
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: camera.value.previewSize!.height,
                height: camera.value.previewSize!.width,
                child: RepaintBoundary(
                  key: _previewKey,
                  child: CameraPreview(camera),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: ViewfinderMaskPainter(geometry.crop)),
          ),
        ),
      ],
    );
  }

  Widget _captureButton() {
    final active = _session.active;
    final working =
        _session.phase == ReelPhase.starting ||
        _session.phase == ReelPhase.stopping;
    final button = Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
      ),
      padding: const EdgeInsets.all(6),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: active ? 30 : 58,
          height: active ? 30 : 58,
          decoration: BoxDecoration(
            color: AuraColors.error,
            borderRadius: BorderRadius.circular(active ? 8 : 40),
          ),
          child: working
              ? const Padding(
                  padding: EdgeInsets.all(5),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
      ),
    );
    return Semantics(
      button: true,
      label: active
          ? 'Pause reel recording'
          : (_seconds == null ? 'Hold to record reel' : 'Record reel clip'),
      enabled: _ready,
      onTap: _ready ? _shutter : null,
      child: ExcludeSemantics(
        child: _seconds == null
            ? Listener(
                key: const ValueKey('reel-shutter'),
                onPointerDown: (event) {
                  if (_heldPointer != null || !_ready) return;
                  if (active) {
                    _session.stop();
                    return;
                  }
                  _heldPointer = event.pointer;
                  _start();
                },
                onPointerUp: (event) {
                  if (_heldPointer == event.pointer) {
                    _heldPointer = null;
                    _session.stop();
                  }
                },
                onPointerCancel: (event) {
                  if (_heldPointer == event.pointer) {
                    _heldPointer = null;
                    _session.stop();
                  }
                },
                child: button,
              )
            : GestureDetector(
                key: const ValueKey('reel-shutter'),
                onTap: _ready ? _shutter : null,
                child: button,
              ),
      ),
    );
  }

  Widget _tools() {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final frame = ViewfinderGeometry.compute(
      screen: screen,
      padding: padding,
      frameAspect: 3 / 4,
      cropRatio: 3 / 4,
    ).crop;
    final bottom = (screen.height - padding.bottom - 310).clamp(
      frame.top + 48,
      frame.bottom,
    );
    return Positioned(
      right: 8,
      top: frame.top + 8,
      height: (bottom - frame.top - 16).clamp(48, 200),
      width: 64,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ColoredBox(
            color: AuraColors.scrim,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _locked ? null : _pickAspect,
                    child: Text(
                      _aspect.label,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Flash',
                    onPressed: _locked || _camera == null
                        ? null
                        : () async {
                            final enabled = !_flash;
                            final ok = await CameraSession.flash(
                              _camera!,
                              enabled ? FlashMode.torch : FlashMode.off,
                            );
                            if (mounted) setState(() => _flash = ok && enabled);
                          },
                    icon: Icon(_flash ? Icons.flash_on : Icons.flash_off),
                  ),
                  IconButton(
                    tooltip: 'Hands-free',
                    onPressed: () => _handsFreeKey.currentState?.openSettings(),
                    icon: ListenableBuilder(
                      listenable: HandsFreePreferences.instance,
                      builder: (_, _) => Icon(
                        Icons.front_hand_outlined,
                        color:
                            HandsFreePreferences.instance.gestures ||
                                HandsFreePreferences.instance.voice
                            ? AuraColors.yellow
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clips = _session.clips;
    final active = _session.active;
    final error = _error ?? _session.error;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _preview(),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 130,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 8,
              right: 16,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to camera',
                    onPressed: _locked ? null : _leave,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Text(
                    'Reel',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      '${clips.length} clips · ${_session.totalSeconds.toStringAsFixed(1)}s',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            _tools(),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 430,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xEE000000)],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HandsFreeControls(
                        key: _handsFreeKey,
                        showSettingsButton: false,
                        contextState: () => RemoteContext(
                          mode: RemoteMode.reel,
                          recording: _session.phase == ReelPhase.recording,
                          hasClips: _session.clips.isNotEmpty,
                          busy:
                              _busy ||
                              _session.phase == ReelPhase.starting ||
                              _session.phase == ReelPhase.stopping,
                        ),
                        ready: () => _ready && !_reviewing && !_leaving,
                        snapshot: () => sampleCameraPreview(_previewKey),
                        onAction: (action) async {
                          switch (action) {
                            case RemoteAction.start:
                              _start();
                            case RemoteAction.pause:
                              await _session.stop();
                            case RemoteAction.finish:
                              await _session.stop();
                              await _review();
                            case RemoteAction.cancel:
                              _handsFreeKey.currentState?.cancelPending();
                            case RemoteAction.photo:
                              break;
                          }
                        },
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AuraColors.yellow),
                          ),
                        ),
                      if (_camera == null && !_busy && !_reviewing)
                        TextButton(
                          onPressed: () => _cameraOperation = _open(),
                          child: const Text('Retry camera'),
                        ),
                      if (clips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: clips.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 6),
                            itemBuilder: (_, i) => Chip(
                              label: Text(
                                '${i + 1} · ${clips[i].seconds.toStringAsFixed(1)}s',
                              ),
                              avatar: Icon(
                                clips[i].mirror
                                    ? Icons.face
                                    : Icons.landscape_outlined,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: const Text('Hold'),
                                selected: _seconds == null,
                                onSelected: _locked
                                    ? null
                                    : (_) => setState(() => _seconds = null),
                              ),
                            ),
                            for (final seconds in ReelSession.presets)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(
                                    seconds == 60 ? '1 min' : '${seconds}s',
                                  ),
                                  selected: _seconds == seconds,
                                  onSelected: _locked
                                      ? null
                                      : (_) =>
                                            setState(() => _seconds = seconds),
                                ),
                              ),
                            ActionChip(
                              label: Text(
                                _seconds != null &&
                                        !ReelSession.presets.contains(_seconds)
                                    ? '${_seconds}s · Custom'
                                    : 'Custom',
                              ),
                              onPressed: _locked ? null : _customTimer,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        active
                            ? '${_session.elapsed.toStringAsFixed(1)}s${_seconds == null ? '' : ' / ${_seconds}s'} · ${_session.phase == ReelPhase.starting
                                  ? 'Starting…'
                                  : _session.phase == ReelPhase.stopping
                                  ? 'Saving clip…'
                                  : 'Recording'}'
                            : _seconds == null
                            ? 'Hold to record · release to pause'
                            : 'Tap to record · stops after ${_seconds}s',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            tooltip: 'Undo last clip',
                            onPressed: _locked || clips.isEmpty
                                ? null
                                : () {
                                    _session.undo();
                                  },
                            icon: const Icon(Icons.undo_rounded),
                          ),
                          _captureButton(),
                          IconButton(
                            tooltip: 'Switch camera',
                            onPressed: _locked || widget.cameras.length < 2
                                ? null
                                : _flip,
                            icon: const Icon(
                              Icons.flip_camera_ios_outlined,
                              size: 30,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _locked || clips.isEmpty ? null : _review,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            _busy && _reviewing ? 'Combining…' : 'Preview reel',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _leaving = true;
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    _camera?.dispose();
    super.dispose();
  }
}
