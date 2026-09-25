import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aura/camera/capture_aspect.dart';
import 'package:aura/services/capture_feedback.dart';
import 'package:aura/services/video_processor.dart';
import 'package:aura/widgets/aspect_ratio_picker.dart';

import 'layout_draft.dart';
import 'layout_exporter.dart';
import 'layout_review_screen.dart';
import 'layout_store.dart';
import 'layout_widgets.dart';

/// A Normal-mode capture session. The parent releases its camera before pushing
/// this route; only one camera controller is ever live at a time.
class LayoutCameraScreen extends StatefulWidget {
  const LayoutCameraScreen({
    super.key,
    required this.cameras,
    required this.aspect,
    required this.screen,
    this.cameraIndex = 0,
    this.store,
  });
  final List<CameraDescription> cameras;
  final CaptureAspect aspect;
  final Size screen;
  final int cameraIndex;
  final LayoutStore? store;
  @override
  State<LayoutCameraScreen> createState() => _LayoutCameraScreenState();
}

class _LayoutCameraScreenState extends State<LayoutCameraScreen>
    with WidgetsBindingObserver {
  late LayoutDraft _draft;
  LayoutStore? _store;
  CameraController? _camera;
  late int _cameraIndex;
  bool _loaded = false,
      _busy = false,
      _recording = false,
      _flash = false,
      _retaking = false;
  bool _leaving = false, _away = false, _suspending = false;
  Completer<void>? _operation;
  String? _error;
  DateTime? _recordStarted;
  int? _recordCell;
  bool _recordMirror = false;
  Timer? _ticker;
  StreamSubscription<dynamic>? _volume;
  double _zoom = 1, _baseZoom = 1, _minZoom = 1, _maxZoom = 1;

  bool get _front =>
      widget.cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
  String get _aspectLabel {
    final aspect = CaptureAspect.byId(_draft.aspectId);
    if (aspect.isFull) return 'Full';
    return (_draft.ratio - aspect.ratio!).abs() < .000001
        ? aspect.label
        : aspect.label.split(':').reversed.join(':');
  }

  bool get _canCapture =>
      _loaded &&
      !_busy &&
      !_away &&
      _camera?.value.isInitialized == true &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _cameraIndex = widget.cameraIndex;
    _draft = LayoutDraft(
      aspectId: widget.aspect.id,
      ratio: widget.aspect.resolveRatio(widget.screen),
    );
    WidgetsBinding.instance.addObserver(this);
    _volume = const EventChannel('com.aura.aura/volume')
        .receiveBroadcastStream()
        .listen((event) {
          if (event == 'down' && _canCapture) _shutter();
        }, onError: (Object _) {});
    _load();
  }

  Future<void> _load() async {
    await _run(() async {
      _store = widget.store ?? await LayoutStore.open();
      final saved = await _store!.load();
      if (saved != null) _draft = saved;
      _loaded = true;
      await _openCamera();
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    _operation = Completer<void>();
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _busy = false;
      _operation?.complete();
      _operation = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _persist() async {
    await _store?.save(_draft);
    await _store?.prune(_draft);
  }

  Future<void> _openCamera() async {
    if (!mounted || _away || _leaving || widget.cameras.isEmpty) return;
    final camera = CameraController(
      widget.cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _camera = camera;
    try {
      await camera.initialize();
      if (!mounted || _away || _camera != camera) {
        await camera.dispose();
        if (_camera == camera) _camera = null;
        return;
      }
      _minZoom = await camera.getMinZoomLevel();
      _maxZoom = await camera.getMaxZoomLevel();
      _zoom = 1.0.clamp(_minZoom, _maxZoom);
      await camera.setZoomLevel(_zoom);
      await camera.setFlashMode(_flash ? FlashMode.always : FlashMode.off);
    } catch (_) {
      if (_camera == camera) _camera = null;
      await camera.dispose();
      rethrow;
    }
  }

  Future<void> _closeCamera() async {
    final camera = _camera;
    _camera = null;
    if (mounted) setState(() {});
    await camera?.dispose();
  }

  Future<void> _addMedia(
    String path,
    CellKind kind,
    int index, {
    bool mirror = false,
  }) async {
    final retained = await _store!.retain(path);
    final media = kind == CellKind.video
        ? await LayoutExporter.inspectVideo(retained, mirror: mirror)
        : LayoutMedia(path: retained, kind: kind, mirror: mirror);
    // Decode once before accepting gallery images so corrupt inputs remain retryable.
    if (kind == CellKind.photo) {
      final bytes = await File(retained).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
    }
    _draft.put(index, media);
    _retaking = false;
    await _persist();
  }

  Future<void> _shutter() async {
    if (!_canCapture) return;
    if (!_recording && _draft.media[_draft.selected] != null && !_retaking) {
      setState(() => _retaking = true);
      return;
    }
    await _run(() async {
      final camera = _camera!;
      if (_recording) {
        await _finishRecording();
      } else if (_draft.selectedKind == CellKind.video) {
        _recordCell = _draft.selected;
        _recordMirror = _front;
        await camera.lockCaptureOrientation(camera.value.deviceOrientation);
        if (_flash) await camera.setFlashMode(FlashMode.torch);
        try {
          await camera.startVideoRecording();
          _recordStarted = DateTime.now();
          _recording = true;
          CaptureFeedback.videoStart();
          _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (mounted) setState(() {});
          });
        } catch (_) {
          await camera.unlockCaptureOrientation();
          rethrow;
        }
      } else {
        final cell = _draft.selected;
        final mirror = _front;
        await camera.lockCaptureOrientation(camera.value.deviceOrientation);
        try {
          CaptureFeedback.shutter();
          final file = await camera.takePicture();
          await _addMedia(file.path, CellKind.photo, cell, mirror: mirror);
        } finally {
          await camera.unlockCaptureOrientation();
        }
      }
    });
  }

  Future<void> _finishRecording() async {
    final camera = _camera;
    if (camera == null || !camera.value.isRecordingVideo) return;
    try {
      final file = await camera.stopVideoRecording();
      CaptureFeedback.videoStop();
      await _addMedia(
        file.path,
        CellKind.video,
        _recordCell!,
        mirror: _recordMirror,
      );
    } finally {
      _ticker?.cancel();
      _recording = false;
      _recordStarted = null;
      await camera.unlockCaptureOrientation();
      await camera.setFlashMode(_flash ? FlashMode.always : FlashMode.off);
    }
  }

  Future<void> _import() async {
    if (_busy || _recording) return;
    final cell = _draft.selected;
    final kind = _draft.selectedKind;
    await _run(() async {
      _away = true;
      await _closeCamera();
      try {
        final picker = ImagePicker();
        final file = kind == CellKind.photo
            ? await picker.pickImage(source: ImageSource.gallery)
            : await picker.pickVideo(source: ImageSource.gallery);
        if (file != null) await _addMedia(file.path, kind, cell);
      } finally {
        _away = false;
        if (mounted &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          await _openCamera();
        }
      }
    });
  }

  Future<void> _chooseLayout() async {
    if (_busy || _recording) return;
    final choice = await showLayoutPicker(context, _draft);
    if (choice == null ||
        !mounted ||
        choice.template == _draft.template && choice.mode == _draft.mode) {
      return;
    }
    if (_draft.hasMedia &&
        !await _confirm(
          'Start a new layout?',
          'Changing the grid or media mode clears the current cells.',
        )) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      _draft = LayoutDraft(
        template: choice.template,
        mode: choice.mode,
        aspectId: _draft.aspectId,
        ratio: _draft.ratio,
      );
      _retaking = false;
      await _persist();
    });
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _aspect() async {
    if (_busy || _recording) return;
    final aspect = await showAspectRatioPicker(
      context,
      current: CaptureAspect.byId(_draft.aspectId),
      screen: widget.screen,
      showOutputResolution: false,
    );
    if (aspect == null || !mounted) return;
    await _run(() async {
      _draft.aspectId = aspect.id;
      _draft.ratio = aspect.resolveRatio(widget.screen);
      await _persist();
    });
  }

  Future<void> _review() async {
    if (!_draft.complete || _busy || _recording) return;
    await _run(() async {
      _away = true;
      await _persist();
      await _closeCamera();
      try {
        if (!mounted) return;
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => LayoutReviewScreen(draft: _draft, store: _store!),
          ),
        );
        if (saved == true) {
          await _store!.discard();
          _draft = LayoutDraft(
            template: _draft.template,
            mode: _draft.mode,
            aspectId: _draft.aspectId,
            ratio: _draft.ratio,
          );
          await _persist();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Layout saved to gallery')),
            );
          }
        }
      } finally {
        _away = false;
        if (mounted &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          await _openCamera();
        }
      }
    });
  }

  Future<void> _leave() async {
    if (_busy || _recording || _leaving) return;
    if (_draft.hasMedia) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep this layout?'),
          content: const Text(
            'Your draft can be resumed from Layout in Normal mode.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep draft'),
            ),
          ],
        ),
      );
      if (discard == null || !mounted) return;
      await _run(() async {
        if (discard) {
          await _store?.discard();
        } else {
          await _persist();
        }
      });
      if (_error != null) return;
    }
    _leaving = true;
    await _closeCamera();
    if (mounted) {
      setState(() {});
      Navigator.pop(context);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_away || _leaving) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _suspend();
    } else if (state == AppLifecycleState.resumed &&
        !_suspending &&
        _camera == null) {
      _run(_openCamera);
    }
  }

  Future<void> _suspend() async {
    if (_suspending) return;
    _suspending = true;
    await _operation?.future;
    if (_away || _leaving) {
      _suspending = false;
      return;
    }
    await _run(() async {
      final since = Platform.isAndroid ? _recordStarted : null;
      final cell = _recordCell;
      final mirror = _recordMirror;
      if (!Platform.isAndroid && _recording) {
        try {
          await _finishRecording();
        } finally {
          await _closeCamera();
        }
      }
      _ticker?.cancel();
      _recording = false;
      _recordStarted = null;
      // CameraX finalizes on dispose. Stopping after its surface is destroyed
      // can crash its Recorder, so recover the finalized cache file instead.
      await _closeCamera();
      if (since != null && cell != null) {
        final dir = await getTemporaryDirectory();
        File? clip;
        for (final file in dir.listSync().whereType<File>()) {
          if (file.uri.pathSegments.last.startsWith('REC') &&
              file.path.endsWith('.mp4') &&
              file.lastModifiedSync().isAfter(
                since.subtract(const Duration(seconds: 2)),
              )) {
            if (clip == null ||
                file.lastModifiedSync().isAfter(clip.lastModifiedSync())) {
              clip = file;
            }
          }
        }
        if (clip != null) {
          for (int i = 0; i < 20; i++) {
            if (await VideoProcessor.isPlayable(clip.path)) break;
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          final path = await VideoProcessor.trimToVideo(clip.path) ?? clip.path;
          await _addMedia(path, CellKind.video, cell, mirror: mirror);
        }
      }
      await _persist();
    });
    _suspending = false;
    if (mounted &&
        !_away &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await _run(_openCamera);
    }
  }

  Widget _preview() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(
        child: Icon(Icons.camera_alt_outlined, color: Colors.white38),
      );
    }
    return ValueListenableBuilder<CameraValue>(
      valueListenable: camera,
      builder: (context, value, _) {
        final orientation = value.isRecordingVideo
            ? value.recordingOrientation
            : value.lockedCaptureOrientation ?? value.deviceOrientation;
        final landscape =
            orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;
        final sourceAspect = landscape
            ? value.aspectRatio
            : 1 / value.aspectRatio;
        // Photos use the full sensor preview; video uses its central 16:9 field.
        final field = _draft.selectedKind == CellKind.video
            ? (landscape ? 16 / 9 : 9 / 16)
            : sourceAspect;
        return GestureDetector(
          onScaleStart: (_) => _baseZoom = _zoom,
          onScaleUpdate: (details) {
            _zoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
            camera.setZoomLevel(_zoom).catchError((Object _) {});
          },
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: field * 1000,
              height: 1000,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: sourceAspect * 1000,
                    height: 1000,
                    child: CameraPreview(camera),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _controls() {
    final selected = _draft.media[_draft.selected];
    final seconds = _recordStarted == null
        ? 0
        : DateTime.now().difference(_recordStarted!).inSeconds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _recording
              ? 'Recording cell ${_draft.selected + 1} • ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
              : '${_draft.filled}/${_draft.media.length} filled • Cell ${_draft.selected + 1} • ${_draft.mode.name}',
          style: TextStyle(
            color: _recording ? Colors.redAccent : Colors.white70,
            fontSize: 12,
          ),
        ),
        if (_draft.media.length > 6)
          LayoutCellSelector(
            draft: _draft,
            onSelect: _busy || _recording
                ? null
                : (i) => _run(() async {
                    _draft.selected = i;
                    _retaking = false;
                    await _persist();
                  }),
          ),
        if (_draft.mode == LayoutMode.hybrid)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<CellKind>(
              segments: const [
                ButtonSegment(
                  value: CellKind.photo,
                  label: Text('Photo'),
                  icon: Icon(Icons.photo_camera, size: 16),
                ),
                ButtonSegment(
                  value: CellKind.video,
                  label: Text('Video'),
                  icon: Icon(Icons.videocam, size: 16),
                ),
              ],
              selected: {_draft.selectedKind},
              onSelectionChanged: _busy || _recording
                  ? null
                  : (s) => _run(() async {
                      _draft.kinds[_draft.selected] = s.first;
                      _retaking = selected != null;
                      await _persist();
                    }),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Import ${_draft.selectedKind.name}',
              onPressed: _busy || _recording ? null : _import,
              icon: const Icon(Icons.photo_library_outlined),
            ),
            TextButton(
              onPressed: selected == null || _busy || _recording
                  ? null
                  : () => setState(() => _retaking = true),
              child: const Text('Retake'),
            ),
            IconButton(
              tooltip: 'Clear cell',
              onPressed: selected == null || _busy || _recording
                  ? null
                  : () => _run(() async {
                      _draft.clear(_draft.selected);
                      _retaking = false;
                      await _persist();
                    }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: 'Switch camera',
              onPressed: _busy || _recording || widget.cameras.length < 2
                  ? null
                  : () => _run(() async {
                      await _closeCamera();
                      _cameraIndex = (_cameraIndex + 1) % widget.cameras.length;
                      await _openCamera();
                    }),
              icon: const Icon(Icons.flip_camera_ios_outlined),
            ),
            Semantics(
              label: _recording
                  ? 'Stop recording cell'
                  : _draft.selectedKind == CellKind.video
                  ? 'Record cell'
                  : 'Photograph cell',
              button: true,
              child: IconButton.filled(
                key: const ValueKey('layout-shutter'),
                onPressed: _canCapture ? _shutter : null,
                style: IconButton.styleFrom(
                  backgroundColor: _recording ? Colors.red : Colors.white,
                  foregroundColor: _recording ? Colors.white : Colors.black,
                  fixedSize: const Size(66, 66),
                ),
                iconSize: 32,
                icon: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _recording
                            ? Icons.stop
                            : _draft.selectedKind == CellKind.video
                            ? Icons.videocam
                            : Icons.camera_alt,
                      ),
              ),
            ),
            IconButton(
              tooltip: 'Rotate composition',
              onPressed: _busy || _recording
                  ? null
                  : () => _run(() async {
                      _draft.ratio = 1 / _draft.ratio;
                      await _persist();
                    }),
              icon: const Icon(Icons.crop_rotate),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('layout-review'),
          onPressed: _draft.complete && !_busy && !_recording ? _review : null,
          icon: const Icon(Icons.check),
          label: const Text('Review layout'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _busy || _recording ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Normal · Layout', style: TextStyle(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: _busy || _recording ? null : _aspect,
            child: Row(
              children: [
                AspectIcon(ratio: _draft.ratio),
                const SizedBox(width: 6),
                Text(_aspectLabel),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: !_loaded
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
              )
            : LayoutBuilder(
                builder: (context, bounds) {
                  final landscape = bounds.maxWidth > bounds.maxHeight;
                  final canvas = Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 54, 4),
                    child: Center(
                      child: LayoutGrid(
                        draft: _draft,
                        livePreview: _preview(),
                        retaking: _retaking,
                        onSelect: _busy || _recording
                            ? null
                            : (i) => _run(() async {
                                _draft.selected = i;
                                _retaking = false;
                                await _persist();
                              }),
                      ),
                    ),
                  );
                  final actions = SingleChildScrollView(
                    child: Column(
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              _error!,
                              maxLines: 3,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (_camera == null && !_busy && !_away)
                          TextButton(
                            onPressed: () => _run(_openCamera),
                            child: const Text('Retry camera'),
                          ),
                        _controls(),
                      ],
                    ),
                  );
                  final field = Stack(
                    children: [
                      Positioned.fill(child: canvas),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Column(
                          children: [
                            IconButton(
                              tooltip: 'Flash',
                              onPressed: _busy || _recording
                                  ? null
                                  : () => _run(() async {
                                      final next = !_flash;
                                      await _camera?.setFlashMode(
                                        next ? FlashMode.always : FlashMode.off,
                                      );
                                      _flash = next;
                                    }),
                              icon: Icon(
                                _flash ? Icons.flash_on : Icons.flash_off,
                                color: _flash ? Colors.amber : Colors.white,
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('layout-picker'),
                              tooltip: 'Change layout',
                              onPressed: _busy || _recording
                                  ? null
                                  : _chooseLayout,
                              icon: LayoutIcon(
                                template: _draft.template,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  return landscape
                      ? Row(
                          children: [
                            Expanded(child: field),
                            SizedBox(
                              width: math.min(260, bounds.maxWidth * .4),
                              child: actions,
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: field),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: bounds.maxHeight * .55,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: actions,
                              ),
                            ),
                          ],
                        );
                },
              ),
      ),
    ),
  );

  @override
  void dispose() {
    _leaving = true;
    _volume?.cancel();
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }
}
