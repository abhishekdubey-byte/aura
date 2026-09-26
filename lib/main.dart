// Removed taxonomy_panel import
import 'dart:async';

import 'theme/aura_theme.dart';
import 'widgets/aura_controls.dart';
import 'config/server_config.dart';
import 'camera/camera_session.dart';
import 'widgets/slang_style_picker.dart';
import 'models/slang_style.dart';

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import 'package:aura/aura_calculator.dart';
import 'package:aura/aura/aura_photo_composer.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura/services/reminder_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:aura/models/detailed_aura_score.dart';
import 'package:aura/services/streak_service.dart';
import 'package:flutter/services.dart';
import 'package:aura/screens/splash_screen.dart';
import 'package:aura/screens/settings_screen.dart';
import 'package:aura/services/upload_manager.dart';
import 'package:aura/services/capture_feedback.dart';
import 'package:aura/services/media_save_queue.dart';
import 'package:aura/services/media_library.dart';
import 'package:aura/services/photo_processor.dart';
import 'package:aura/services/video_processor.dart';
import 'package:aura/models/captured_photo.dart';
import 'package:aura/screens/capture_preview_screen.dart';
import 'package:aura/widgets/capture_button.dart';
import 'package:aura/boomerang/boomerang_effect.dart';
import 'package:aura/screens/boomerang_screen.dart';
import 'package:aura/camera/capture_aspect.dart';
import 'package:aura/widgets/aspect_ratio_picker.dart';
import 'package:aura/layout/layout_camera_screen.dart';

import 'reel/reel_camera_screen.dart';
import 'hands_free/hands_free_commands.dart';
import 'hands_free/hands_free_controls.dart';
import 'hands_free/hands_free_preferences.dart';
import 'hands_free/preview_sampler.dart';

List<CameraDescription> cameras = [];

/// 82978586 -> "82,978,586"
String _groupDigits(int value) {
  final String digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Completes when the services the app needs are ready. Started before the
/// first frame and awaited by the splash screen, so the animated splash shows
/// instantly instead of a blank screen while these run.
late final Future<void> appReady;

/// 0..1 progress of [appReady], for the splash progress bar.
final ValueNotifier<double> appReadyProgress = ValueNotifier(0);

Future<void> _bootstrap() async {
  // Cameras and Supabase are independent: start both together
  final Future<void> camerasReady = availableCameras()
      .then<void>((list) {
        cameras = list;
      })
      .catchError((Object e) {
        debugPrint('Error initializing cameras: $e');
      });
  try {
    await Supabase.initialize(
      url: ServerConfig.url,
      publishableKey: ServerConfig.publicKey,
    );
  } catch (e) {
    debugPrint('Supabase initialization failed: $e');
  }
  appReadyProgress.value = 0.5;

  await camerasReady;
  appReadyProgress.value = 0.8;

  // Reminders and background sync don't block the UI
  () async {
    try {
      await ReminderService.init();
      await ReminderService.schedulePeriodicReminder();
    } catch (e) {
      debugPrint('Reminder service initialization failed: $e');
    }
  }();
  try {
    UploadManager.instance.resume();
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        UploadManager.instance.resume();
      }
    });
  } catch (e) {
    debugPrint('Error initializing background sync: $e');
  }
  appReadyProgress.value = 1;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge dark UI from the very first frame
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  appReady = _bootstrap();
  runApp(const AuraApp());
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA',
      debugShowCheckedModeBanner: false,
      theme: AuraTheme.dark,
      home: const SplashScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

enum CaptureMode { normal, boomerang, aura }

class VideoSegment {
  final String path;
  final bool isFrontCamera;
  VideoSegment(this.path, this.isFrontCamera);
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  String? _cameraError;
  // Camera released because the app went to the background
  bool _cameraReleased = false;
  bool _cameraTransition = false;
  // When the current video segment actually started recording (null if none)
  DateTime? _segmentStartedAt;
  bool _isCapturing = false;
  int _queuedShots = 0;
  static const int _maxQueuedShots = 10;
  bool _isRecordingVideo = false;
  bool _videoPaused = false;
  bool _isStoppingVideo = false;
  final _handsFreeKey = GlobalKey<HandsFreeControlsState>();
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _currentZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  bool _isFlashOn = false;
  final FocusNode _focusNode = FocusNode();
  DateTime? _volumeKeyDownTime;
  bool _volumeLongPressActive = false;
  static const EventChannel _volumeChannel = EventChannel(
    'com.aura.aura/volume',
  );
  StreamSubscription? _volumeSubscription;
  final List<VideoSegment> _videoSegments = [];
  CaptureMode _mode = CaptureMode.normal;
  bool get _isAuraMode => _mode == CaptureMode.aura;
  bool get _isBoomerangMode => _mode == CaptureMode.boomerang;

  // Boomerang capture: a short clip (1–3s) that stops on its own
  static const int _maxBoomerangSeconds = 3;
  int _boomerangSeconds = 1;
  bool _isBoomerangCapturing = false;
  bool _boomerangStarting = false;
  bool _isStoppingBoomerang = false;
  Timer? _boomerangTimer;
  final Stopwatch _boomerangStopwatch = Stopwatch();
  final ValueNotifier<double> _boomerangProgress = ValueNotifier(0);
  double? _boomerangAspect;

  // Framing for photos and videos (each is a centred crop of the frame)
  CaptureAspect _aspect = CaptureAspect.initial;
  // Upright photo size from the sensor, measured from the first photo
  Size? _photoFrameSize;
  // Crop fixed when a recording starts (applies across camera flips)
  double? _recordingAspect;
  static const double _videoFieldAspect = 9 / 16;
  bool _isStartingVideo = false;
  bool _isSwitchingCamera = false;

  // Lens switching: frozen, blurred last frame shown while the other camera opens
  bool _isFlipping = false;
  double _flipTurns = 0;
  ui.Image? _switchFrame;
  final GlobalKey _previewBoundaryKey = GlobalKey();
  bool _stopRequested = false;

  // Shutter blink shown over the preview on every photo capture
  late final AnimationController _shutterAnim;
  late final Animation<double> _shutterOpacity;

  // Photos taken this session (newest first) for the instant in-app preview;
  // the latest one is shown as the gallery button thumbnail
  final List<CapturedPhoto> _sessionPhotos = [];
  static const int _maxSessionPhotos = 50;
  final ValueNotifier<CapturedPhoto?> _lastCapture = ValueNotifier(null);

  // Recording timer (updates only the timer pill, not the whole screen)
  final Stopwatch _recordStopwatch = Stopwatch();

  // Zoom level shown inside the capture button; the label lingers briefly
  // after a zoom gesture even when back at 1x
  final ValueNotifier<double> _zoomNotifier = ValueNotifier(1.0);
  final ValueNotifier<bool> _zoomGestureActive = ValueNotifier(false);
  final ValueNotifier<({double min, double max})> _zoomRange = ValueNotifier((
    min: 1.0,
    max: 1.0,
  ));
  Timer? _zoomLabelTimer;
  // Sliding the capture button this many pixels doubles (or halves) the zoom
  static const double _zoomDragPixelsPerDoubling = 150;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shutterAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _shutterOpacity = _shutterAnim.drive(
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.85), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 0.85, end: 0.0), weight: 70),
      ]),
    );
    _initCamera(_selectedCameraIndex);
    _loadBoomerangSeconds();
    _loadCapturePrefs();
    _volumeSubscription = _volumeChannel.receiveBroadcastStream().listen((
      dynamic event,
    ) {
      if (event is String) {
        _handleVolumeEvent(event);
      }
    });
  }

  int _cameraGeneration = 0;

  Future<void> _initCamera(int cameraIndex) async {
    final generation = ++_cameraGeneration;
    if (mounted) setState(() => _cameraError = null);
    if (cameras.isEmpty) {
      try {
        cameras = await availableCameras();
      } catch (_) {}
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(
          () => _cameraError = 'No camera is available. Check camera access in your phone settings and try again.',
        );
        return;
      }
    }
    cameraIndex = cameraIndex.clamp(0, cameras.length - 1);

    final CameraController? previousController = _controller;
    _controller = null;
    _isCameraInitialized = false;
    if (previousController != null) {
      await previousController.dispose();
    }

    CameraController? controller;
    try {
      controller = await CameraSession.open(cameras[cameraIndex]);
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      _controller = controller;

      // Show the preview as soon as the camera is streaming. Focus and exposure
      // are already continuous-auto by default, so only zoom limits and flash
      // need setting, and they can finish after the preview is visible.
      _currentZoomLevel = 1.0;
      _zoomNotifier.value = 1.0;
      setState(() {
        _isCameraInitialized = true;
        _isFlipping = false;
        _cameraReleased = false;
      });

      final zoomLimits = await CameraSession.zoomRange(controller);
      if (!mounted || _controller != controller) return;
      _minZoomLevel = zoomLimits.$1;
      _maxZoomLevel = zoomLimits.$2;
      _zoomRange.value = (min: _minZoomLevel, max: _maxZoomLevel);
      if (!await CameraSession.flash(
        controller,
        _isFlashOn ? FlashMode.always : FlashMode.off,
      )) {
        _isFlashOn = false;
      }
    } catch (e) {
      debugPrint('Camera initialization: $e');
      if (mounted && generation == _cameraGeneration) {
        setState(
          () => _cameraError = 'Camera unavailable. Check camera access in your phone settings, then try again.',
        );
      }
    }
  }

  /// Grabs a small frame of the live preview to show (blurred) while the other
  /// lens opens, instead of a blank screen and spinner.
  Future<ui.Image?> _snapshotPreview() async {
    try {
      final boundary =
          _previewBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      return await boundary
          .toImage(pixelRatio: 0.25)
          .timeout(const Duration(milliseconds: 150));
    } catch (e) {
      return null;
    }
  }

  Future<void> _toggleCamera() async {
    await _handsFreeKey.currentState?.suspend();
    if (cameras.length < 2 ||
        _isFlipping ||
        _isStartingVideo ||
        _isStoppingVideo ||
        _isBoomerangCapturing) {
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _flipTurns += 0.5;
    });

    final ui.Image? frame = await _snapshotPreview();
    if (!mounted) {
      frame?.dispose();
      return;
    }
    setState(() {
      _isFlipping = true;
      _switchFrame?.dispose();
      _switchFrame = frame;
    });

    final bool wasRecording = _isRecordingVideo;
    if (wasRecording) {
      await _stopVideoRecording(isToggle: true);
      // A stop pressed while the camera switches is applied once recording resumes
      _isSwitchingCamera = true;
    }

    _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
    await _initCamera(_selectedCameraIndex);

    if (mounted) {
      setState(() {
        _isFlipping = false;
      });
    }

    if (wasRecording) {
      // Slight delay to ensure the camera is fully ready before starting the new recording
      await Future.delayed(const Duration(milliseconds: 300));
      _isSwitchingCamera = false;
      await _startVideoRecording(isToggle: true);
    }
  }

  /// Preview frame aspect (width / height) as shown upright.
  double get _previewFrameAspect {
    final Size? s = _controller?.value.previewSize;
    return s == null ? 0.75 : s.height / s.width;
  }

  /// Live preview framed to the chosen aspect ratio (with a mask over what
  /// won't be saved), or the blurred last frame while switching lenses. The
  /// new preview fades in over the frozen frame once the camera is streaming.
  Widget _buildPreviewLayer() {
    final CameraController? controller = _controller;
    final bool ready =
        !_isFlipping &&
        !_cameraReleased &&
        controller != null &&
        controller.value.isInitialized;
    final Size screen = MediaQuery.sizeOf(context);
    final bool fill = _isAuraMode || _aspect.isFull;
    final geometry = ViewfinderGeometry.compute(
      screen: screen,
      padding: MediaQuery.paddingOf(context),
      frameAspect: _previewFrameAspect,
      cropRatio: _isAuraMode
          ? screen.width / screen.height
          : _aspect.resolveRatio(screen),
      // Videos (and boomerangs) record the centre 9:16 band of the frame
      fieldAspect: !_isAuraMode && (_isBoomerangMode || _isRecordingVideo)
          ? _videoFieldAspect
          : null,
      fillScreen: fill,
      bottomControls: 200 + (_isBoomerangMode ? 46 : 0),
    );
    const Duration morph = Duration(milliseconds: 280);
    const Curve curve = Curves.easeOutCubic;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_switchFrame != null)
          AnimatedPositioned.fromRect(
            rect: geometry.frame,
            duration: morph,
            curve: curve,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 12,
                sigmaY: 12,
                tileMode: TileMode.clamp,
              ),
              child: RawImage(
                image: _switchFrame,
                fit: BoxFit.cover,
                color: Colors.black26,
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
        AnimatedPositioned.fromRect(
          rect: geometry.frame,
          duration: morph,
          curve: curve,
          child: AnimatedOpacity(
            opacity: ready ? 1 : 0,
            // Hide instantly when switching starts, fade in when the new lens is live
            duration: ready ? const Duration(milliseconds: 250) : Duration.zero,
            curve: Curves.easeOut,
            onEnd: () {
              if (ready && _switchFrame != null && mounted) {
                setState(() {
                  _switchFrame!.dispose();
                  _switchFrame = null;
                });
              }
            },
            child: !ready
                ? const SizedBox.expand()
                : RepaintBoundary(
                    key: _previewBoundaryKey,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.previewSize?.height ?? 1,
                        height: controller.value.previewSize?.width ?? 1,
                        child: GestureDetector(
                          onScaleStart: (details) {
                            _baseZoomLevel = _currentZoomLevel;
                          },
                          onScaleUpdate: (details) =>
                              _setZoom(_baseZoomLevel * details.scale),
                          child: CameraPreview(controller),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        // Bars over everything outside the saved area, like native camera apps
        IgnorePointer(
          child: TweenAnimationBuilder<Rect?>(
            tween: RectTween(end: geometry.crop),
            duration: morph,
            curve: curve,
            builder: (context, rect, _) => CustomPaint(
              size: Size.infinite,
              painter: ViewfinderMaskPainter(rect ?? geometry.crop),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Aspect ratio

  Future<void> _loadCapturePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final CaptureAspect aspect = CaptureAspect.byId(
      prefs.getString('capture_aspect'),
    );
    final double? w = prefs.getDouble('photo_frame_w');
    final double? h = prefs.getDouble('photo_frame_h');
    if (!mounted) return;
    setState(() {
      _aspect = aspect;
      if (w != null && h != null) _photoFrameSize = Size(w, h);
    });
  }

  /// Crop (width / height) for a saved photo, or null to keep the whole
  /// sensor frame (e.g. 3:4) or in Aura mode.
  double? _photoCropRatio() {
    if (_isAuraMode) return null;
    final double ratio = _aspect.resolveRatio(MediaQuery.sizeOf(context));
    final Size? frame = _photoFrameSize;
    final double frameAspect = frame != null
        ? frame.width / frame.height
        : _previewFrameAspect;
    return (ratio - frameAspect).abs() / frameAspect < 0.01 ? null : ratio;
  }

  /// Crop (width / height) for a recorded video or boomerang, or null when the
  /// framing already matches the 9:16 recording.
  double? _videoCropRatio() {
    if (_isAuraMode) return null;
    final double ratio = _aspect.resolveRatio(MediaQuery.sizeOf(context));
    return (ratio - _videoFieldAspect).abs() / _videoFieldAspect < 0.01
        ? null
        : ratio;
  }

  /// Records the sensor's photo size once, so the picker can show the real
  /// output resolution of every framing.
  Future<void> _measurePhotoFrame(String path) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(path);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      double w = descriptor.width.toDouble(), h = descriptor.height.toDouble();
      descriptor.dispose();
      buffer.dispose();
      if (w > h) {
        final t = w;
        w = h;
        h = t;
      }
      _photoFrameSize = Size(w, h);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('photo_frame_w', w);
      await prefs.setDouble('photo_frame_h', h);
    } catch (e) {
      debugPrint('Could not read photo size: $e');
    }
  }

  Future<void> _pickAspect() async {
    _handsFreeKey.currentState?.cancelPending();
    final CaptureAspect? chosen = await showAspectRatioPicker(
      context,
      current: _aspect,
      screen: MediaQuery.sizeOf(context),
      photoFrame: _photoFrameSize,
    );
    if (chosen == null || chosen == _aspect || !mounted) return;
    setState(() => _aspect = chosen);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString('capture_aspect', chosen.id),
    );
  }

  Future<void> _openLayouts() => _openCaptureTool();

  Future<void> _openReels() => _openCaptureTool(reel: true);

  Future<void> _openCaptureTool({bool reel = false}) async {
    if ((!reel && _mode != CaptureMode.normal) ||
        _isBoomerangCapturing ||
        _isCapturing ||
        _isRecordingVideo ||
        _videoPaused ||
        _isStoppingVideo ||
        _isStartingVideo ||
        _isFlipping ||
        _cameraTransition ||
        _controller?.value.isInitialized != true) {
      return;
    }
    final screen = MediaQuery.sizeOf(context);
    _cameraTransition = true;
    await _handsFreeKey.currentState?.suspend();
    try {
      await _volumeSubscription?.cancel();
      _volumeSubscription = null;
      setState(() => _cameraReleased = true);
      await _controller?.dispose();
      _controller = null;
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => reel
              ? ReelCameraScreen(
                  cameras: cameras,
                  cameraIndex: _selectedCameraIndex,
                )
              : LayoutCameraScreen(
                  cameras: cameras,
                  aspect: _aspect,
                  screen: screen,
                  cameraIndex: _selectedCameraIndex,
                ),
        ),
      );
    } finally {
      _cameraTransition = false;
      if (mounted) {
        _volumeSubscription = _volumeChannel.receiveBroadcastStream().listen((
          dynamic event,
        ) {
          if (event is String) _handleVolumeEvent(event);
        });
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          await _initCamera(_selectedCameraIndex);
        }
      }
    }
  }

  Widget _buildAspectChip() => IconButton(
    tooltip: 'Aspect ratio · ${_aspect.label}',
    onPressed:
        _isRecordingVideo ||
            _videoPaused ||
            _isStartingVideo ||
            _isBoomerangCapturing
        ? null
        : _pickAspect,
    icon: AspectIcon(ratio: _aspect.resolveRatio(MediaQuery.sizeOf(context))),
  );

  Future<void> _startVideoRecording({bool isToggle = false}) async {
    if (_isBoomerangMode && !isToggle) return;
    if (_isAuraMode) {
      if (mounted) {
        _showToast(
          'Video recording disabled in Aura Mode',
          duration: const Duration(seconds: 1),
        );
      }
      return;
    }
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.isRecordingVideo ||
        _isStartingVideo ||
        _isStoppingVideo ||
        (!isToggle && (_isRecordingVideo || _isFlipping))) {
      if (isToggle) _abortRecording();
      return;
    }

    _isStartingVideo = true;
    if (!isToggle) _stopRequested = false;
    final resuming = _videoPaused;
    _handsFreeKey.currentState?.cancelPending();
    await _handsFreeKey.currentState?.prepareForVideo();
    if (!mounted ||
        _cameraReleased ||
        _controller?.value.isInitialized != true) {
      _isStartingVideo = false;
      return;
    }
    _baseZoomLevel = _currentZoomLevel;

    if (!isToggle) {
      if (!resuming) {
        _videoSegments.clear();
        _recordingAspect = _videoCropRatio();
      }
      // Update the UI immediately; CameraX needs up to a second to reconfigure
      // the session for video before recording actually starts.
      CaptureFeedback.videoStart();
      if (!resuming) _recordStopwatch.reset();
      setState(() {
        _videoPaused = false;
        _isRecordingVideo = true;
      });
    }

    try {
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.torch);
      }
      if (!_controller!.enableAudio && mounted) {
        _showToast('Microphone unavailable; recording without sound.');
      }
      await _controller!.startVideoRecording();
      _segmentStartedAt = DateTime.now();
      if (!isToggle) {
        if (resuming) {
          _recordStopwatch.start();
        } else {
          _startRecordTimer();
        }
      }
    } on CameraException catch (e) {
      debugPrint('Error starting video recording: $e');
      _abortRecording();
    } finally {
      _isStartingVideo = false;
    }

    // The user released before recording had fully started
    if (_stopRequested) {
      _stopRequested = false;
      await _stopVideoRecording();
    }
  }

  Future<void> _stopVideoRecording({
    bool isToggle = false,
    bool pauseOnly = false,
  }) async {
    _handsFreeKey.currentState?.cancelPending();
    if (_isStoppingVideo) return;
    if (_videoPaused && !isToggle && !pauseOnly) {
      setState(_enqueueSegmentsSave);
      return;
    }
    if (_isStartingVideo || _isSwitchingCamera) {
      _stopRequested = true;
      return;
    }
    if (_controller == null || !_controller!.value.isRecordingVideo) {
      return;
    }

    _isStoppingVideo = true;
    if (!isToggle) {
      // Reset the UI immediately; finalizing and saving happen in the background
      _stopRecordTimer();
      CaptureFeedback.videoStop();
      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
        });
      }
    }

    try {
      final XFile file = await _controller!.stopVideoRecording();
      await UploadManager.instance.enqueue(file.path);
      _segmentStartedAt = null;
      bool isFront =
          cameras.isNotEmpty &&
          cameras[_selectedCameraIndex].lensDirection ==
              CameraLensDirection.front;
      _videoSegments.add(VideoSegment(file.path, isFront));

      if (!isToggle) {
        CaptureFeedback.videoStopSound();
        if (pauseOnly) {
          if (mounted) setState(() => _videoPaused = true);
        } else {
          _enqueueSegmentsSave();
        }
      }

      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.always);
      }
    } on CameraException catch (e) {
      debugPrint('Error stopping video recording: $e');
      if (!isToggle) {
        _enqueueSegmentsSave();
      }
    } finally {
      if (mounted) setState(() => _isStoppingVideo = false);
    }
  }

  /// Resets the recording UI after a failed start and keeps any segments
  /// already recorded (e.g. before a camera flip).
  void _abortRecording() {
    _stopRecordTimer();
    _stopRequested = false;
    if (mounted) {
      setState(() {
        _isRecordingVideo = false;
      });
    }
    _enqueueSegmentsSave();
  }

  void _startRecordTimer() {
    _recordStopwatch
      ..reset()
      ..start();
  }

  void _stopRecordTimer() {
    _recordStopwatch.stop();
  }

  /// Hands the recorded segments to the background save queue so the camera
  /// is immediately ready for the next capture.
  void _enqueueSegmentsSave() {
    _videoPaused = false;
    if (_videoSegments.isEmpty) return;
    final segments = List<VideoSegment>.of(_videoSegments);
    _videoSegments.clear();
    final double? aspect = _recordingAspect;
    MediaSaveQueue.instance.add(() => _stitchAndSaveVideos(segments, aspect));
  }

  /// [aspect] (width / height) crops to the chosen framing; null keeps the
  /// full 9:16 recording.
  Future<void> _stitchAndSaveVideos(
    List<VideoSegment> segments,
    double? aspect,
  ) async {
    if (segments.isEmpty) return;

    String? outputPath;
    if (segments.length == 1) {
      // Back-camera clips in the native framing are saved untouched;
      // front-camera clips are mirrored to match the preview.
      if (!segments.first.isFrontCamera) {
        if (aspect == null) {
          await _saveVideoToGallery(segments.first.path);
          return;
        }
        outputPath = await VideoProcessor.crop(segments.first.path, aspect);
      } else {
        outputPath = await VideoProcessor.mirror(
          segments.first.path,
          aspect: aspect,
        );
      }
    } else {
      outputPath = await VideoProcessor.stitch([
        for (final s in segments) (path: s.path, mirror: s.isFrontCamera),
      ], aspect: aspect);
    }

    if (outputPath == null && segments.length > 1) {
      for (final segment in segments) {
        await _saveVideoToGallery(segment.path, label: 'Video part');
      }
      if (mounted) {
        _showToast('Could not combine clips. Saved each original video.');
      }
      return;
    }
    await _saveVideoToGallery(outputPath ?? segments.first.path);
  }

  // ---------------------------------------------------------------------------
  // Boomerang (∞)

  Future<void> _loadBoomerangSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final int seconds = prefs.getInt('boomerang_seconds') ?? 1;
    if (mounted) {
      setState(
        () => _boomerangSeconds = seconds.clamp(1, _maxBoomerangSeconds),
      );
    }
  }

  void _setBoomerangSeconds(int seconds) {
    if (_isBoomerangCapturing || seconds == _boomerangSeconds) return;
    HapticFeedback.selectionClick();
    setState(() => _boomerangSeconds = seconds);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setInt('boomerang_seconds', seconds),
    );
  }

  void _setMode(CaptureMode mode) {
    _handsFreeKey.currentState?.cancelPending();
    if (mode == _mode ||
        _isRecordingVideo ||
        _videoPaused ||
        _isStoppingVideo ||
        _isBoomerangCapturing ||
        _isCapturing ||
        _isStartingVideo ||
        _isFlipping ||
        _cameraTransition) {
      return;
    }
    HapticFeedback.selectionClick();
    // Load the Aura models while the user frames the shot
    if (mode == CaptureMode.aura) AuraCalculatorService.instance.warmUp();
    setState(() => _mode = mode);
  }

  /// Tap in Boomerang mode: starts a clip that stops by itself after the
  /// chosen 1–3 seconds; a second tap ends it early.
  Future<void> _onBoomerangPressed() async {
    if (_isBoomerangCapturing) {
      _stopBoomerang(early: true);
      return;
    }
    final CameraController? controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isRecordingVideo ||
        _isFlipping ||
        _isRecordingVideo) {
      return;
    }

    CaptureFeedback.videoStart();
    _boomerangAspect = _videoCropRatio();
    _boomerangProgress.value = 0;
    _boomerangStopwatch.reset();
    setState(() => _isBoomerangCapturing = true);

    _boomerangStarting = true;
    _handsFreeKey.currentState?.cancelPending();
    await _handsFreeKey.currentState?.prepareForVideo();
    try {
      if (_isFlashOn) {
        await controller.setFlashMode(FlashMode.torch);
      }
      await controller.startVideoRecording();
    } catch (e) {
      debugPrint('Error starting boomerang: $e');
      _boomerangStarting = false;
      _resetBoomerangCapture();
      return;
    }
    _boomerangStarting = false;
    if (!mounted) return;

    // Count from the moment the camera is actually recording
    _boomerangStopwatch.start();
    final int totalMs = _boomerangSeconds * 1000;
    int lastSecond = 0;
    _boomerangTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final int ms = _boomerangStopwatch.elapsedMilliseconds;
      _boomerangProgress.value = (ms / totalMs).clamp(0.0, 1.0);
      final int second = ms ~/ 1000;
      if (second > lastSecond && ms < totalMs) {
        lastSecond = second;
        HapticFeedback.selectionClick();
      }
      if (ms >= totalMs) _stopBoomerang();
    });
  }

  Future<void> _stopBoomerang({bool early = false}) async {
    // Ignore a stray second tap while the camera is still starting, and clips
    // too short to loop nicely
    if (_boomerangStarting || _isStoppingBoomerang) return;
    if (early && _boomerangStopwatch.elapsedMilliseconds < 500) return;
    _isStoppingBoomerang = true;

    _boomerangTimer?.cancel();
    _boomerangTimer = null;
    _boomerangStopwatch.stop();
    final double seconds = min(
      _boomerangStopwatch.elapsedMilliseconds / 1000,
      _boomerangSeconds.toDouble(),
    );
    final bool mirror =
        cameras[_selectedCameraIndex].lensDirection ==
        CameraLensDirection.front;
    CaptureFeedback.videoStop();

    final CameraController? controller = _controller;
    XFile? file;
    try {
      if (controller != null && controller.value.isRecordingVideo) {
        file = await controller.stopVideoRecording();
        await UploadManager.instance.enqueue(file.path);
      }
      if (_isFlashOn && controller != null) {
        await controller.setFlashMode(FlashMode.always);
      }
    } catch (e) {
      debugPrint('Error stopping boomerang: $e');
    }
    _isStoppingBoomerang = false;
    _resetBoomerangCapture();
    if (file == null || !mounted) return;
    CaptureFeedback.videoStopSound();

    final String videoPath = file.path;
    final double? aspect = _boomerangAspect;
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, _) => FadeTransition(
          opacity: animation,
          child: BoomerangScreen(
            videoPath: videoPath,
            seconds: seconds,
            mirror: mirror,
            aspect: aspect,
            onSave: (effect, frameCount) => _saveBoomerang(
              videoPath,
              seconds,
              mirror,
              effect,
              frameCount,
              aspect,
            ),
          ),
        ),
      ),
    );
  }

  void _resetBoomerangCapture() {
    _boomerangTimer?.cancel();
    _boomerangTimer = null;
    _boomerangStopwatch.stop();
    _boomerangProgress.value = 0;
    if (mounted && _isBoomerangCapturing) {
      setState(() => _isBoomerangCapturing = false);
    }
  }

  /// Renders the full-quality boomerang in the background and saves it.
  void _saveBoomerang(
    String videoPath,
    double seconds,
    bool mirror,
    BoomerangEffect effect,
    int frameCount,
    double? aspect,
  ) {
    MediaSaveQueue.instance.add(() async {
      final String? output = await VideoProcessor.boomerang(
        videoPath,
        seconds: seconds,
        mirror: mirror,
        frameCount: frameCount,
        effect: effect,
        aspect: aspect,
      );
      if (output == null) {
        if (mounted) {
          _showToast('Could not save the boomerang');
        }
        return;
      }
      await _saveVideoToGallery(
        output,
        label: '∞ Boomerang',
        album: MediaAlbum.boomerang,
      );
    });
  }

  Future<void> _remoteCapture(RemoteAction action) async {
    switch (action) {
      case RemoteAction.photo:
        await _captureAura();
      case RemoteAction.start:
        if (_isBoomerangMode) {
          await _onBoomerangPressed();
        } else {
          await _startVideoRecording();
        }
      case RemoteAction.pause:
        await _stopVideoRecording(pauseOnly: true);
      case RemoteAction.finish:
        if (_isBoomerangCapturing) {
          await _stopBoomerang(early: true);
        } else {
          await _stopVideoRecording();
        }
      case RemoteAction.cancel:
        _handsFreeKey.currentState?.cancelPending();
    }
  }

  Widget _buildSideTools() {
    final locked =
        _isRecordingVideo ||
        _videoPaused ||
        _isStoppingVideo ||
        _isStartingVideo ||
        _isCapturing ||
        _isBoomerangCapturing ||
        _isFlipping ||
        _cameraTransition;
    final screen = MediaQuery.sizeOf(context);
    // Keep every feature above the lower 3:4 framing line, even in Full mode.
    final frame = ViewfinderGeometry.compute(
      screen: screen,
      padding: MediaQuery.paddingOf(context),
      frameAspect: _previewFrameAspect,
      cropRatio: 3 / 4,
      bottomControls: 200 + (_isBoomerangMode ? 46 : 0),
    ).crop;
    return Positioned(
      right: screen.width - frame.right + 8,
      top: frame.top + 8,
      bottom: screen.height - frame.bottom + 8,
      width: 56,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: ColoredBox(
            color: AuraColors.scrim,
            child: SingleChildScrollView(
              key: const ValueKey('camera-side-tools'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    [
                          if (!_isAuraMode) _buildAspectChip(),
                          IconButton(
                            tooltip: 'Settings',
                            onPressed: locked
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const SettingsScreen(),
                                    ),
                                  ),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                          IconButton(
                            tooltip: 'Flash',
                            onPressed: locked ? null : _toggleFlash,
                            icon: Icon(
                              _isFlashOn ? Icons.flash_on : Icons.flash_off,
                              color: _isFlashOn
                                  ? AuraColors.yellow
                                  : AuraColors.text,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('normal-layout-button'),
                            tooltip: 'Layout',
                            onPressed: locked || _mode != CaptureMode.normal
                                ? null
                                : _openLayouts,
                            icon: const Icon(Icons.grid_view_rounded),
                          ),
                          IconButton(
                            key: const ValueKey('reel-mode-button'),
                            tooltip: 'Reel',
                            onPressed: locked ? null : _openReels,
                            icon: const Icon(Icons.video_collection_outlined),
                          ),
                          _buildSideModeButton(
                            CaptureMode.boomerang,
                            'Boomerang',
                            Icons.all_inclusive,
                          ),
                          _buildSideModeButton(
                            CaptureMode.aura,
                            'AURA',
                            Icons.person_rounded,
                          ),
                          IconButton(
                            key: const ValueKey('hands-free-settings'),
                            tooltip: 'Hands-free',
                            onPressed: () =>
                                _handsFreeKey.currentState?.openSettings(),
                            icon: ListenableBuilder(
                              listenable: HandsFreePreferences.instance,
                              builder: (_, _) => Icon(
                                HandsFreePreferences.instance.gestures ||
                                        HandsFreePreferences.instance.voice
                                    ? Icons.front_hand
                                    : Icons.front_hand_outlined,
                                color:
                                    HandsFreePreferences.instance.gestures ||
                                        HandsFreePreferences.instance.voice
                                    ? AuraColors.yellow
                                    : null,
                              ),
                            ),
                          ),
                        ]
                        .map(
                          (button) =>
                              SizedBox(width: 48, height: 48, child: button),
                        )
                        .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideModeButton(CaptureMode mode, String label, IconData icon) {
    final selected = _mode == mode;
    final locked =
        _isRecordingVideo ||
        _videoPaused ||
        _isStoppingVideo ||
        _isBoomerangCapturing ||
        _isCapturing ||
        _isStartingVideo;
    return Semantics(
      selected: selected,
      child: IconButton(
        key: ValueKey('mode-${mode.name}'),
        tooltip: selected ? '$label — tap for Normal' : label,
        style: IconButton.styleFrom(
          backgroundColor: selected ? AuraColors.primary : AuraColors.scrim,
        ),
        icon: Icon(
          icon,
          color: selected ? AuraColors.background : AuraColors.text,
        ),
        onPressed: locked
            ? null
            : () => _setMode(selected ? CaptureMode.normal : mode),
      ),
    );
  }

  /// 1s / 2s / 3s picker shown in Boomerang mode.
  Widget _buildBoomerangLengthPicker() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int s = 1; s <= _maxBoomerangSeconds; s++)
            GestureDetector(
              onTap: () => _setBoomerangSeconds(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: s == _boomerangSeconds
                      ? Colors.white
                      : Colors.transparent,
                ),
                child: Text(
                  '${s}s',
                  style: TextStyle(
                    color: s == _boomerangSeconds ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveVideoToGallery(
    String path, {
    String label = 'Video',
    MediaAlbum album = MediaAlbum.videos,
  }) async {
    try {
      await UploadManager.instance.enqueue(path);
      await MediaLibrary.saveVideo(path, album, keepSource: true);
      final streakData = await StreakService.incrementStreak();

      if (mounted) {
        _showToast(
          streakData.justIncreased
              ? '🔥 ${streakData.count} Day Streak! $label saved! ✨'
              : '$label saved to gallery! ✨',
          highlight: streakData.justIncreased,
        );
      }
    } catch (e) {
      debugPrint('Error saving video: $e');
      if (mounted) {
        _showToast('Could not save the video. Check gallery access.');
      }
    }
  }

  /// Applies a zoom level from any gesture, keeping the capture-button label
  /// in sync. Snaps to 1x so returning to the normal view is easy.
  void _setZoom(double requested) {
    final CameraController? controller = _controller;
    if (_isFlipping || controller == null || !controller.value.isInitialized) {
      return;
    }

    double zoom = requested.clamp(_minZoomLevel, _maxZoomLevel);
    if ((zoom - 1.0).abs() < 0.08) {
      zoom = 1.0.clamp(_minZoomLevel, _maxZoomLevel);
    }

    _zoomGestureActive.value = true;
    _zoomLabelTimer?.cancel();
    _zoomLabelTimer = Timer(
      const Duration(milliseconds: 900),
      () => _zoomGestureActive.value = false,
    );

    if ((zoom - _currentZoomLevel).abs() < 0.02) return;

    // Light tick at each whole step (1x, 2x, 3x...) like native camera apps
    if (zoom.floor() != _currentZoomLevel.floor() ||
        (zoom == 1.0 && _currentZoomLevel != 1.0)) {
      HapticFeedback.selectionClick();
    }
    controller.setZoomLevel(zoom).catchError((Object e) {
      debugPrint('Zoom unavailable: $e');
    });
    _currentZoomLevel = zoom;
    _zoomNotifier.value = zoom;
  }

  /// Sliding up on the capture button zooms in, sliding down zooms out.
  /// [dy] is the total vertical offset since the slide began (negative = up).
  void _handleSlideZoom(double dy) {
    _setZoom(
      _baseZoomLevel * pow(2, -dy / _zoomDragPixelsPerDoubling).toDouble(),
    );
  }

  /// Shutter handler. Taps made while a capture is still in flight are queued
  /// and taken back-to-back, so no tap is lost during rapid shooting.
  Future<void> _captureAura() async {
    _handsFreeKey.currentState?.cancelPending();
    if (_videoPaused) {
      await _startVideoRecording();
      return;
    }
    if (_isBoomerangMode) {
      await _onBoomerangPressed();
      return;
    }
    if (_isFlipping ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }

    if (_isCapturing) {
      // Aura mode opens a result screen per shot, so extra taps are ignored there
      if (_isAuraMode || _queuedShots >= _maxQueuedShots) return;
      _queuedShots++;
      _giveShutterFeedback();
      return;
    }

    // Plain guard flag: no setState, so the preview is not rebuilt on capture
    _isCapturing = true;
    _giveShutterFeedback();
    final bool isAuraMode = _isAuraMode;

    try {
      while (mounted) {
        await _takePhoto(isAuraMode: isAuraMode);
        if (_queuedShots == 0) break;
        _queuedShots--;
      }
    } finally {
      _isCapturing = false;
      _queuedShots = 0;
    }
  }

  void _giveShutterFeedback() {
    CaptureFeedback.shutter();
    _shutterAnim.forward(from: 0);
  }

  Future<void> _takePhoto({required bool isAuraMode}) async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final bool isFrontCamera =
        cameras[_selectedCameraIndex].lensDirection ==
        CameraLensDirection.front;

    final auraAspect = isAuraMode
        ? MediaQuery.sizeOf(context).aspectRatio
        : null;
    final XFile file;
    try {
      file = await controller.takePicture();
    } catch (e) {
      debugPrint('Error taking picture: $e');
      return;
    }

    final String originalImagePath = file.path;
    // Retain and queue the raw capture before processing or gallery permissions.
    await UploadManager.instance.enqueue(originalImagePath);
    if (!mounted) return;

    StreakService.incrementStreak().then((streakData) {
      if (mounted && streakData.justIncreased) {
        _showToast('🔥 ${streakData.count} Day Streak!', highlight: true);
      }
    });

    try {
      if (isAuraMode) {
        final String finalPath = await PhotoProcessor.process(
          originalImagePath,
          mirror: isFrontCamera,
          aspect: auraAspect,
        );

        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResultScreen(
                imagePath: finalPath,
                isFrontCamera: isFrontCamera,
              ),
            ),
          );
        }
      } else {
        await _saveNormalPhoto(originalImagePath, isFrontCamera);
      }
    } catch (e) {
      debugPrint('Error saving photo: $e');
    }
  }

  /// Shows the photo on the thumbnail and in the in-app preview right away,
  /// then mirrors/watermarks it and saves it to the gallery in the background.
  Future<void> _saveNormalPhoto(
    String originalImagePath,
    bool isFrontCamera,
  ) async {
    final double? aspect = _photoCropRatio();
    // Laptop/desktop framings are wallpapers; everything else is a snap
    final MediaAlbum album =
        !_isAuraMode && _aspect.category == AspectCategory.desktop
        ? MediaAlbum.wallpapers
        : MediaAlbum.snaps;
    final photo = CapturedPhoto(
      originalPath: originalImagePath,
      mirrored: isFrontCamera,
      aspect: aspect,
    );
    if (_photoFrameSize == null) _measurePhotoFrame(originalImagePath);
    _sessionPhotos.insert(0, photo);
    if (_sessionPhotos.length > _maxSessionPhotos) {
      _sessionPhotos.removeLast();
    }
    _lastCapture.value = photo;

    final prefs = await SharedPreferences.getInstance();
    final bool watermarkEnabled = prefs.getBool('watermark_enabled') ?? false;
    final String watermarkText =
        prefs.getString('custom_watermark') ??
        'Calculate your Aura: Download AURA App';

    void queueSave() {
      photo.saveError.value = null;
      MediaSaveQueue.instance.add(() async {
        try {
          final finalPath = await PhotoProcessor.process(
            originalImagePath,
            mirror: isFrontCamera,
            watermark: watermarkEnabled ? watermarkText : null,
            aspect: aspect,
          );
          final savedPath = await MediaLibrary.saveImage(
            finalPath,
            album,
            keepSource: finalPath == originalImagePath,
          );
          photo.savedPath.value = savedPath;
          photo.retrySave = null;
        } catch (e) {
          photo.saveError.value = 'This photo hasn’t been saved. Check gallery access and try again.';
          if (mounted && ModalRoute.of(context)?.isCurrent == true) {
            _showToast('Photo not saved. Open the preview to retry.');
          }
          debugPrint('Photo save: $e');
        }
      });
    }

    photo.retrySave = queueSave;
    queueSave();
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    try {
      final newMode = !_isFlashOn;
      await _controller!.setFlashMode(
        newMode ? FlashMode.always : FlashMode.off,
      );
      if (mounted) {
        setState(() {
          _isFlashOn = newMode;
        });
      }
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  void _handleVolumeEvent(String action) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      _volumeKeyDownTime = null;
      _volumeLongPressActive = false;
      return;
    }
    debugPrint("AURA_DEBUG: _handleVolumeEvent received: $action");
    if (action == "down") {
      // If we are currently recording, ANY down press stops the recording.
      if (_isRecordingVideo) {
        debugPrint("AURA_DEBUG: Stopping video recording via volume button.");
        _stopVideoRecording();
        _volumeKeyDownTime = null;
        _volumeLongPressActive = false;
        return;
      }

      // We are not recording. Start tracking the key press.
      _volumeKeyDownTime = DateTime.now();
      _volumeLongPressActive = false;

      Future.delayed(const Duration(milliseconds: 400), () {
        // If the key is still held down after 400ms, it's a long press -> record video
        if (_volumeKeyDownTime != null &&
            mounted &&
            ModalRoute.of(context)?.isCurrent == true &&
            !_isRecordingVideo) {
          debugPrint(
            "AURA_DEBUG: Long press detected via volume button. Starting video.",
          );
          _volumeLongPressActive = true;
          _startVideoRecording();
        }
      });
    } else if (action == "up") {
      if (_volumeKeyDownTime != null) {
        final pressDuration = DateTime.now().difference(_volumeKeyDownTime!);
        _volumeKeyDownTime = null;

        // If we didn't trigger a long press and released under 400ms, it's a short press -> capture photo
        if (!_volumeLongPressActive && pressDuration.inMilliseconds < 400) {
          debugPrint(
            "AURA_DEBUG: Short press detected via volume button. Capturing photo.",
          );
          _captureAura();
        }
        _volumeLongPressActive = false;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // "inactive" is only a focus loss (notification shade, call banner, system
    // overlay): keep the camera and any recording running, like native camera
    // apps. Release the camera only once the app is actually out of view.
    if (state == AppLifecycleState.resumed) {
      unawaited(UploadManager.instance.resume());
    }
    if (_cameraTransition) return;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (!_cameraReleased) _releaseCamera();
    } else if (state == AppLifecycleState.resumed && _cameraReleased) {
      _reopenCamera();
    }
  }

  /// Frees the camera while the app is in the background. A video in progress
  /// is stopped and saved first so the clip isn't lost and the UI doesn't stay
  /// stuck in the recording state; an unfinished boomerang is discarded.
  Future<void> _releaseCamera() async {
    await _handsFreeKey.currentState?.suspend();
    _cameraGeneration++;
    final CameraController? controller = _controller;
    if (controller == null) {
      _cameraReleased = true;
      return;
    }
    if (!controller.value.isInitialized) return;
    _cameraTransition = true;
    DateTime? interruptedSince;
    final bool isFront =
        cameras[_selectedCameraIndex].lensDirection ==
        CameraLensDirection.front;
    try {
      if (_isBoomerangCapturing) {
        _resetBoomerangCapture();
      } else if (_isRecordingVideo || controller.value.isRecordingVideo) {
        // Don't call stop() here: stopping while Android tears down the preview
        // surface (as the app leaves the screen) can crash CameraX's Recorder.
        // Releasing the camera finalizes the clip natively instead; it is
        // picked up from the cache once written.
        interruptedSince = _segmentStartedAt;
        _segmentStartedAt = null;
        _stopRecordTimer();
        if (mounted) setState(() => _isRecordingVideo = false);
      }
      // Stop showing the preview before the controller goes away
      if (mounted) {
        setState(() => _cameraReleased = true);
      } else {
        _cameraReleased = true;
      }
      await controller.dispose();
    } finally {
      _cameraTransition = false;
    }
    if (interruptedSince != null) {
      _recoverInterruptedClip(interruptedSince, isFront);
    }
    // The app may have come back while the camera was being released
    if (mounted &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _reopenCamera();
    }
  }

  /// Saves a clip CameraX finalized on its own when the camera was released
  /// mid-recording (joined with any earlier segments from camera flips).
  Future<void> _recoverInterruptedClip(DateTime since, bool isFront) async {
    try {
      final Directory dir = await getTemporaryDirectory();
      File? clip;
      DateTime? newest;
      for (final f in dir.listSync().whereType<File>()) {
        final String name = f.uri.pathSegments.last;
        if (!name.startsWith('REC') || !name.endsWith('.mp4')) continue;
        final DateTime modified = f.lastModifiedSync();
        if (modified.isBefore(since.subtract(const Duration(seconds: 1)))) {
          continue;
        }
        if (newest == null || modified.isAfter(newest)) {
          newest = modified;
          clip = f;
        }
      }
      if (clip == null) return;
      // Wait until the file stops growing (CameraX is still finalizing it)
      int lastLength = -1;
      for (int i = 0; i < 20; i++) {
        final int length = await clip.length();
        if (length > 0 && length == lastLength) break;
        lastLength = length;
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (!await VideoProcessor.isPlayable(clip.path)) return;
      await UploadManager.instance.enqueue(clip.path);
      // The microphone keeps going after the camera stops; drop that tail
      final String path =
          await VideoProcessor.trimToVideo(clip.path) ?? clip.path;
      _videoSegments.add(VideoSegment(path, isFront));
      _enqueueSegmentsSave();
    } catch (e) {
      debugPrint('Could not recover interrupted clip: $e');
    }
  }

  Future<void> _reopenCamera() async {
    _cameraTransition = true;
    try {
      await _initCamera(_selectedCameraIndex);
    } finally {
      _cameraTransition = false;
    }
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    _controller?.dispose();
    _shutterAnim.dispose();
    _zoomLabelTimer?.cancel();
    _zoomNotifier.dispose();
    _zoomGestureActive.dispose();
    _zoomRange.dispose();
    _boomerangTimer?.cancel();
    _boomerangProgress.dispose();
    _lastCapture.dispose();
    _switchFrame?.dispose();
    super.dispose();
  }

  Future<void> _openGalleryApp() async {
    try {
      await Gal.open();
    } catch (e) {
      if (mounted) {
        _showToast('Could not open gallery app');
      }
    }
  }

  /// Camera-screen message: readable on any scene and floating just above the
  /// shutter controls instead of covering them.
  void _showToast(
    String message, {
    bool highlight = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    // Height of the bottom controls: shutter row (80 + 40) and mode switch
    // (44 + 36), plus the length picker in Boomerang mode
    final double controlsHeight = 200 + (_isBoomerangMode ? 46 : 0);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: highlight ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: highlight ? AuraColors.yellow : AuraColors.raised,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.fromLTRB(32, 0, 32, controlsHeight + 12),
        elevation: 0,
        duration: duration,
      ),
    );
  }

  /// Opens this session's photos instantly, even before they reach the gallery.
  void _openCapturePreview() {
    if (_sessionPhotos.isEmpty) {
      _openGalleryApp();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CapturePreviewScreen(photos: List.of(_sessionPhotos)),
      ),
    );
  }

  /// Normal-mode gallery button: shows the last capture with a "pop" on each
  /// new shot, and a progress ring while photos/videos are still being saved.
  Widget _buildLastCaptureButton() {
    return GestureDetector(
      onTap: _openCapturePreview,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ValueListenableBuilder<CapturedPhoto?>(
              valueListenable: _lastCapture,
              builder: (context, last, _) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                    child: child,
                  ),
                  child: last == null
                      ? const Icon(
                          Icons.photo_library,
                          key: ValueKey('gallery_icon'),
                          color: Colors.white,
                          size: 32,
                        )
                      : Container(
                          key: ValueKey(last.originalPath),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: ClipOval(
                            child: Transform.flip(
                              flipX: last.mirrored,
                              child: Image.file(
                                File(last.originalPath),
                                cacheWidth: 144,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ),
                );
              },
            ),
            ValueListenableBuilder<int>(
              valueListenable: MediaSaveQueue.instance.pending,
              builder: (context, pending, _) {
                if (pending == 0) return const SizedBox.shrink();
                return const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Camera'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: _cameraError == null
            ? const Center(child: CircularProgressIndicator())
            : AuraEmptyState(
                icon: Icons.camera_alt_outlined,
                title: 'Let’s get your camera ready',
                message: _cameraError!,
                action: 'Try again',
                onAction: () => _initCamera(_selectedCameraIndex),
              ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPreviewLayer(),

          // Soft scrims so the top icons and bottom controls stay readable on
          // bright scenes (a white wall made them nearly invisible)
          const IgnorePointer(
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 170,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x66000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 300,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0x80000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Shutter blink (only this layer repaints on capture)
          IgnorePointer(
            child: FadeTransition(
              opacity: _shutterOpacity,
              child: const ColoredBox(color: Colors.black),
            ),
          ),

          _buildSideTools(),

          // Mode Switch and Camera Controls
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HandsFreeControls(
                      key: _handsFreeKey,
                      showSettingsButton: false,
                      contextState: () => RemoteContext(
                        mode: _isBoomerangMode
                            ? RemoteMode.boomerang
                            : RemoteMode.photo,
                        recording: _isRecordingVideo || _isBoomerangCapturing,
                        paused: _videoPaused,
                        videoAllowed: !_isAuraMode,
                        busy:
                            _isCapturing ||
                            _isStartingVideo ||
                            _isStoppingVideo ||
                            _boomerangStarting ||
                            _isStoppingBoomerang,
                      ),
                      ready: () =>
                          _controller?.value.isInitialized == true &&
                          !_isFlipping &&
                          !_cameraReleased &&
                          !_cameraTransition,
                      snapshot: () => sampleCameraPreview(_previewBoundaryKey),
                      onAction: _remoteCapture,
                    ),
                    if (_videoPaused)
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Video paused'),
                          TextButton(
                            onPressed: () => _startVideoRecording(),
                            child: const Text('Resume'),
                          ),
                          TextButton(
                            onPressed: () => _stopVideoRecording(),
                            child: const Text('Finish'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    // Mode Toggle (fades out while the zoom dial is showing)
                    ValueListenableBuilder<bool>(
                      valueListenable: _zoomGestureActive,
                      builder: (context, zooming, child) => IgnorePointer(
                        ignoring: zooming,
                        child: AnimatedOpacity(
                          opacity: zooming ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: child,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              child: _isBoomerangMode
                                  ? _buildBoomerangLengthPicker()
                                  : const SizedBox(width: 0),
                            ),
                            Text(
                              _isAuraMode
                                  ? 'AURA'
                                  : (_isBoomerangMode ? 'BOOMERANG' : 'NORMAL'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _isAuraMode
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.photo_library,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                  onPressed: () async {
                                    try {
                                      final XFile? file = await ImagePicker()
                                          .pickImage(
                                            source: ImageSource.gallery,
                                          );
                                      if (file != null && context.mounted) {
                                        // Upload in background via UploadManager (Non-blocking queue)
                                        await UploadManager.instance.enqueue(
                                          file.path,
                                        );
                                        if (!context.mounted) return;

                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ResultScreen(
                                              imagePath: file.path,
                                              isFrontCamera: false,
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        _showToast('Could not open gallery');
                                      }
                                    }
                                  },
                                )
                              : _buildLastCaptureButton(),

                          // Capture Button
                          AnimatedCaptureButton(
                            isRecording: _isRecordingVideo,
                            recordStopwatch: _recordStopwatch,
                            zoomLevel: _zoomNotifier,
                            zoomRange: _zoomRange,
                            zoomActive: _zoomGestureActive,
                            // While recording (e.g. started with the volume key) a tap stops it
                            onTap: _isRecordingVideo
                                ? () => _stopVideoRecording()
                                : _captureAura,
                            onLongPressStart: () {
                              if (!_isBoomerangMode) _startVideoRecording();
                            },
                            onLongPressEnd: () {
                              if (!_isBoomerangMode) _stopVideoRecording();
                            },
                            boomerangMode: _isBoomerangMode,
                            isBoomerangCapturing: _isBoomerangCapturing,
                            boomerangProgress: _boomerangProgress,
                            boomerangSeconds: _boomerangSeconds,
                            onZoomStart: () =>
                                _baseZoomLevel = _currentZoomLevel,
                            onSlideZoom: _handleSlideZoom,
                          ),

                          // Toggle Camera Button
                          IconButton(
                            icon: AnimatedRotation(
                              turns: _flipTurns,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              child: const Icon(
                                Icons.flip_camera_ios,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            onPressed: _toggleCamera,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ResultScreen extends StatefulWidget {
  final String imagePath;
  final bool isFrontCamera;

  const ResultScreen({
    super.key,
    required this.imagePath,
    required this.isFrontCamera,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  SlangStyle _slangStyle = SlangStyle.neutral;
  bool _isCalculating = true;
  AuraResult? _auraResult;
  String? _editedPath;
  String? _exportError;
  Future<String>? _exportFuture;
  bool _originalSaved = false;
  bool _editedSaved = false;
  bool _savingPhoto = false;
  bool _sharingPhoto = false;
  String? _saveError;
  late final Future<void> _settingsReady;
  final AudioPlayer _revealPlayer = AudioPlayer();
  final AuraCalculatorService _calculator = AuraCalculatorService.instance;
  bool _watermarkEnabled = false;
  String _customWatermarkText = 'Calculate your Aura: Download AURA App';

  @override
  void initState() {
    super.initState();
    _settingsReady = _loadSettings();
    _calculateRealAura();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _watermarkEnabled = prefs.getBool('watermark_enabled') ?? false;
        _slangStyle = SlangStyle.fromStored(
          prefs.getString(SlangStyle.preferenceKey),
        );
        _customWatermarkText =
            prefs.getString('custom_watermark') ??
            'Calculate your Aura: Download AURA App';
      });
    }
  }

  Future<void> _calculateRealAura() async {
    _startHeartbeat();
    final result = await _calculator.analyzeImage(widget.imagePath);
    if (!mounted) return;
    _auraResult = result;
    if (result.hasHuman) {
      try {
        _editedPath = await _exportPhoto();
      } catch (e) {
        _exportError = 'Could not prepare the edited photo. Tap Retry.';
        debugPrint('Aura export failed: $e');
      }
    }
    if (!mounted) return;
    setState(() => _isCalculating = false);
    if (result.hasHuman) {
      // Saving must not depend on audio/haptics succeeding on this device.
      _saveAura(showSnackBar: false);
      _playReveal();
    }
  }

  Future<String> _exportPhoto() => _exportFuture ??= _composePhoto();

  Future<String> _composePhoto() async {
    await _settingsReady;
    final result = _auraResult!;
    try {
      return await AuraPhotoComposer.compose(
        imagePath: widget.imagePath,
        score: result.score,
        slang: _slangStyle.format(
          result.hypeMessage ?? 'Main-character energy 💫',
        ),
        subjectRegions: result.subjectRegions,
        watermark: _watermarkEnabled ? _customWatermarkText : null,
      );
    } catch (_) {
      _exportFuture = null;
      rethrow;
    }
  }

  Future<void> _playReveal() async {
    try {
      if (await Vibration.hasVibrator() && mounted) {
        Vibration.vibrate(pattern: [0, 50, 100, 200]);
      }
      if (mounted) await _revealPlayer.play(AssetSource('audio/reveal.wav'));
    } catch (e) {
      debugPrint('Aura reveal feedback unavailable: $e');
    }
  }

  void _startHeartbeat() async {
    try {
      while (mounted && _isCalculating) {
        if (await Vibration.hasVibrator() && mounted && _isCalculating) {
          Vibration.vibrate(duration: 50);
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }
    } catch (e) {
      debugPrint('Aura heartbeat unavailable: $e');
    }
  }

  @override
  void dispose() {
    _revealPlayer.dispose();
    super.dispose();
  }

  Future<void> _shareAura() async {
    if (_sharingPhoto || _savingPhoto) return;
    setState(() => _sharingPhoto = true);
    try {
      final path = await _exportPhoto();
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: 'Check my aura score: ${_groupDigits(_auraResult!.score)}',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not share this photo. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingPhoto = false);
    }
  }

  Future<void> _saveAura({bool showSnackBar = true}) async {
    if (_savingPhoto) return;
    if (mounted) {
      setState(() {
        _savingPhoto = true;
        _saveError = null;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final pref = prefs.getString('save_preference') ?? 'Both';
      if (!_originalSaved && (pref == 'Original' || pref == 'Both')) {
        await MediaLibrary.saveImage(
          widget.imagePath,
          MediaAlbum.auraResults,
          keepSource: true,
        );
        _originalSaved = true;
      }
      // Keep the old stored preference value compatible with installed apps.
      if (!_editedSaved &&
          (pref == 'Screenshot' || pref == 'Both' || pref == 'Edited')) {
        if (_editedPath == null) {
          throw StateError('The edited photo is not ready');
        }
        await MediaLibrary.saveImage(
          _editedPath!,
          MediaAlbum.auraResults,
          keepSource: true,
        );
        _editedSaved = true;
      }
      if (mounted && showSnackBar) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Aura photo saved')));
      }
    } catch (e) {
      debugPrint('Aura save: $e');
      if (mounted) {
        setState(
          () => _saveError = 'Could not save to the gallery. Check photo access, then tap Save to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _retryExport({bool save = true}) async {
    setState(() {
      _isCalculating = true;
      _exportError = null;
    });
    try {
      final path = await _exportPhoto();
      if (!mounted) return;
      setState(() => _editedPath = path);
      if (save) await _saveAura();
    } catch (_) {
      if (mounted) {
        setState(
          () => _exportError = 'Could not prepare the edited photo. Tap Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _isCalculating = false);
    }
  }

  Future<void> _chooseSlangStyle() async {
    final selected = await showModalBottomSheet<SlangStyle>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Caption wording',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose a style for the person in this photo. This changes the wording, never the score.',
            ),
            const SizedBox(height: 20),
            SlangStylePicker(
              value: _slangStyle,
              onChanged: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null || selected == _slangStyle) return;
    setState(() {
      _slangStyle = selected;
      _editedPath = null;
      _exportFuture = null;
      _editedSaved = false;
      _saveError = null;
    });
    // Recompose the original at full resolution without re-running models or
    // adding duplicate gallery photos. The user can save/share this revision.
    await _retryExport(save: false);
  }

  void _showDetailedBreakdown(BuildContext context, DetailedAuraScore details) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AuraColors.surface,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20.0,
                right: 20.0,
                top: 20.0,
                bottom: MediaQuery.of(context).padding.bottom + 20,
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Aura breakdown',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (details.qualityChecks.isNotEmpty) ...[
                      const Text(
                        'High-score checks',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Passing the checks unlocks a score range. The final score still depends on the whole photo.',
                      ),
                      for (final milestone in [1000000, 10000000]) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Text(
                            milestone == 1000000
                                ? 'For 1 million+'
                                : 'Extra checks for 10 million+',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AuraColors.primary,
                            ),
                          ),
                        ),
                        for (final check in details.qualityChecks.where(
                          (c) => c.milestone == milestone,
                        ))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              check.passed
                                  ? Icons.check_circle_outline
                                  : Icons.lightbulb_outline,
                              color: check.passed
                                  ? AuraColors.green
                                  : AuraColors.yellow,
                            ),
                            title: Text(check.name),
                            subtitle: check.passed ? null : Text(check.tip),
                          ),
                      ],
                      const Divider(),
                    ],
                    if (details.face != null)
                      _buildDetailSection('Face', details.face!),
                    if (details.eyes != null)
                      _buildDetailSection('Eyes', details.eyes!),
                    if (details.expression != null)
                      _buildDetailSection('Expression', details.expression!),
                    _buildDetailSection('Body & Shape', details.body),
                    _buildDetailSection('Posture', details.posture),
                    _buildDetailSection('Pose & Dynamism', details.pose),
                    _buildDetailSection('Style', details.style),
                    _buildDetailSection(
                      'Lighting & Composition',
                      details.image,
                    ),
                    _buildDetailSection('Aura Presence', details.presence),
                    _buildDetailSection('Content Check', details.content),
                    const Divider(color: Colors.grey),
                    _buildDetailRow(
                      'Total Aura Score',
                      _auraResult!.score,
                      [],
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailSection(String label, DimensionScore scoreObj) {
    if (scoreObj.score == 0 && scoreObj.components.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AuraColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${scoreObj.score > 0 ? '+' : ''}${_groupDigits(scoreObj.score)}',
                style: TextStyle(
                  color: scoreObj.score < 0
                      ? AuraColors.error
                      : AuraColors.green,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (scoreObj.primaryTraits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
              child: Text(
                scoreObj.primaryTraits.map(_slangStyle.format).join(' • '),
                style: const TextStyle(color: AuraColors.muted, fontSize: 12),
              ),
            ),
          ...scoreObj.components.map((comp) {
            return Container(
              margin: const EdgeInsets.only(top: 6.0, left: 8.0),
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${comp.attribute}: ${comp.measurement}',
                          style: const TextStyle(
                            color: AuraColors.muted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        '${comp.scoreImpact > 0 ? '+' : ''}${_groupDigits(comp.scoreImpact)}',
                        style: TextStyle(
                          color: comp.scoreImpact < 0
                              ? Colors.red[300]
                              : Colors.green[300],
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    comp.description,
                    style: const TextStyle(
                      color: AuraColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    int score,
    List<String> traits, {
    bool isTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AuraColors.muted,
                    fontSize: isTotal ? 18 : 16,
                    fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${score > 0 ? '+' : ''}${_groupDigits(score)}',
                style: TextStyle(
                  color: score < 0 ? AuraColors.error : AuraColors.green,
                  fontSize: isTotal ? 20 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (traits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                traits.map(_slangStyle.format).join(' • '),
                style: const TextStyle(color: AuraColors.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _auraResult;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Aura'),
        actions: [
          if (!_isCalculating && result?.hasHuman == true)
            IconButton(
              tooltip: 'Slang style: ${_slangStyle.label}',
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              onPressed: _savingPhoto || _sharingPhoto
                  ? null
                  : _chooseSlangStyle,
            ),
          if (!_isCalculating && result?.details != null)
            IconButton(
              tooltip: 'Score breakdown',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () =>
                  _showDetailedBreakdown(context, result!.details!),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: AuraColors.surface),
                      Image.file(
                        File(_editedPath ?? widget.imagePath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const AuraEmptyState(
                          icon: Icons.broken_image_outlined,
                          title: 'Photo unavailable',
                          message:
                              'Return to the camera and choose another photo.',
                        ),
                      ),
                      if (_isCalculating)
                        const ColoredBox(
                          color: AuraColors.scrim,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 20),
                                Text(
                                  'Finding your photo’s energy…',
                                  style: TextStyle(color: AuraColors.text),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!_isCalculating && result != null && !result.hasHuman)
                        ColoredBox(
                          color: AuraColors.scrim,
                          child: AuraEmptyState(
                            icon: Icons.person_search_outlined,
                            title: result.error == null
                                ? 'Step into the frame'
                                : 'Let’s try another photo',
                            message:
                                result.hint ??
                                'Choose a clear photo with a person in view.',
                            action: 'Back to camera',
                            onAction: () => Navigator.pop(context),
                          ),
                        ),
                      if (!_isCalculating && _exportError != null)
                        ColoredBox(
                          color: AuraColors.scrim,
                          child: AuraEmptyState(
                            icon: Icons.image_outlined,
                            title: 'Your score is ready',
                            message: _exportError!,
                            action: 'Retry photo',
                            onAction: _retryExport,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (!_isCalculating && _editedPath != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_saveError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AuraNotice(_saveError!, error: true),
                      ),
                    Text(
                      result!.reusedScore
                          ? 'Same look. Same energy.'
                          : 'Your moment, with a little extra Aura.',
                      style: const TextStyle(
                        color: AuraColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _savingPhoto || _sharingPhoto
                          ? null
                          : _chooseSlangStyle,
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                      label: Text('Slang: ${_slangStyle.label}'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _savingPhoto || _sharingPhoto
                                ? null
                                : () => _saveAura(),
                            icon: Icon(
                              _editedSaved || _originalSaved
                                  ? Icons.check_rounded
                                  : Icons.download_rounded,
                              color: AuraColors.green,
                            ),
                            label: Text(_savingPhoto ? 'Saving…' : 'Save'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AuraButton(
                            label: 'Share photo',
                            icon: Icons.ios_share_rounded,
                            busy: _sharingPhoto,
                            onPressed: _savingPhoto ? null : _shareAura,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_isCalculating || _editedPath == null)
              const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
