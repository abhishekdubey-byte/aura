// Removed taxonomy_panel import
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';

import 'package:aura/aura_calculator.dart';
import 'package:aura/services/api_service.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura/screens/registration_screen.dart';

import 'package:aura/services/reminder_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:aura/models/detailed_aura_score.dart';
import 'package:aura/services/streak_service.dart';
import 'package:aura/screens/leaderboard_screen.dart';
import 'package:flutter/services.dart';
import 'package:aura/screens/splash_screen.dart';
import 'package:aura/screens/settings_screen.dart';
import 'package:path_provider/path_provider.dart';
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
import 'package:aura/models/upload_record.dart';

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
  final Future<void> camerasReady = availableCameras().then((list) => cameras = list).catchError((Object e) {
    debugPrint('Error initializing cameras: $e');
    return cameras;
  });
  try {
    await Supabase.initialize(
      url: 'https://stjogqzjlbiuuubjsosd.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN0am9ncXpqbGJpdXV1Ympzb3NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODg3NTIsImV4cCI6MjEwNDk2NDc1Mn0.Xkb2Bq90XQyVbEosexfhCbHarYsWDXrzyRr39FDw50g',
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
    ApiService.processOfflineQueue();
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi)) {
        ApiService.processOfflineQueue();
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
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  appReady = _bootstrap();
  runApp(const AuraApp());
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurpleAccent,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.pinkAccent,
        ),
      ),
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

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  // Camera released because the app went to the background
  bool _cameraReleased = false;
  bool _cameraTransition = false;
  // When the current video segment actually started recording (null if none)
  DateTime? _segmentStartedAt;
  bool _isCapturing = false;
  int _queuedShots = 0;
  static const int _maxQueuedShots = 10;
  bool _isRecordingVideo = false;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _currentZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  bool _isFlashOn = false;
  final FocusNode _focusNode = FocusNode();
  DateTime? _volumeKeyDownTime;
  bool _volumeLongPressActive = false;
  static const EventChannel _volumeChannel = EventChannel('com.aura.aura/volume');
  StreamSubscription? _volumeSubscription;
  List<VideoSegment> _videoSegments = [];
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
  final ValueNotifier<({double min, double max})> _zoomRange = ValueNotifier((min: 1.0, max: 1.0));
  Timer? _zoomLabelTimer;
  // Sliding the capture button this many pixels doubles (or halves) the zoom
  static const double _zoomDragPixelsPerDoubling = 150;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shutterAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _shutterOpacity = _shutterAnim.drive(TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.85), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 0.0), weight: 70),
    ]));
    _initCamera(_selectedCameraIndex);
    _loadBoomerangSeconds();
    _loadCapturePrefs();
    _volumeSubscription = _volumeChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is String) {
        _handleVolumeEvent(event);
      }
    });
  }


  Future<void> _initCamera(int cameraIndex) async {
    if (cameras.isEmpty) return;

    final CameraController? previousController = _controller;
    if (previousController != null) {
      await previousController.dispose();
    }

    final CameraController controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.max, // Highest possible quality like native apps
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg, // Best quality capture format
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted || _controller != controller) return;

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

      final zoomLimits = await Future.wait([controller.getMinZoomLevel(), controller.getMaxZoomLevel()]);
      _minZoomLevel = zoomLimits[0];
      _maxZoomLevel = zoomLimits[1];
      _zoomRange.value = (min: _minZoomLevel, max: _maxZoomLevel);
      await controller.setFlashMode(_isFlashOn ? FlashMode.always : FlashMode.off);
    } on CameraException catch (e) {
      debugPrint('Camera error: ${e.code}\n${e.description}');
    }
  }

  /// Grabs a small frame of the live preview to show (blurred) while the other
  /// lens opens, instead of a blank screen and spinner.
  Future<ui.Image?> _snapshotPreview() async {
    try {
      final boundary = _previewBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      return await boundary.toImage(pixelRatio: 0.25).timeout(const Duration(milliseconds: 150));
    } catch (e) {
      return null;
    }
  }

  Future<void> _toggleCamera() async {
    if (cameras.length < 2 || _isFlipping || _isStartingVideo || _isBoomerangCapturing) return;

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
    final bool ready = !_isFlipping && !_cameraReleased && controller != null && controller.value.isInitialized;
    final Size screen = MediaQuery.sizeOf(context);
    final bool fill = _isAuraMode || _aspect.isFull;
    final geometry = ViewfinderGeometry.compute(
      screen: screen,
      padding: MediaQuery.paddingOf(context),
      frameAspect: _previewFrameAspect,
      cropRatio: _isAuraMode ? screen.width / screen.height : _aspect.resolveRatio(screen),
      // Videos (and boomerangs) record the centre 9:16 band of the frame
      fieldAspect: !_isAuraMode && (_isBoomerangMode || _isRecordingVideo) ? _videoFieldAspect : null,
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12, tileMode: TileMode.clamp),
              child: RawImage(image: _switchFrame, fit: BoxFit.cover, color: Colors.black26, colorBlendMode: BlendMode.darken),
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
                          onScaleUpdate: (details) => _setZoom(_baseZoomLevel * details.scale),
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
    final CaptureAspect aspect = CaptureAspect.byId(prefs.getString('capture_aspect'));
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
    final double frameAspect = frame != null ? frame.width / frame.height : _previewFrameAspect;
    return (ratio - frameAspect).abs() / frameAspect < 0.01 ? null : ratio;
  }

  /// Crop (width / height) for a recorded video or boomerang, or null when the
  /// framing already matches the 9:16 recording.
  double? _videoCropRatio() {
    if (_isAuraMode) return null;
    final double ratio = _aspect.resolveRatio(MediaQuery.sizeOf(context));
    return (ratio - _videoFieldAspect).abs() / _videoFieldAspect < 0.01 ? null : ratio;
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
    final CaptureAspect? chosen = await showAspectRatioPicker(
      context,
      current: _aspect,
      screen: MediaQuery.sizeOf(context),
      photoFrame: _photoFrameSize,
    );
    if (chosen == null || chosen == _aspect || !mounted) return;
    setState(() => _aspect = chosen);
    SharedPreferences.getInstance().then((prefs) => prefs.setString('capture_aspect', chosen.id));
  }

  Future<void> _openLayouts() async {
    if (_mode != CaptureMode.normal || _isCapturing || _isRecordingVideo ||
        _isStartingVideo || _isFlipping || _cameraTransition ||
        _controller?.value.isInitialized != true) return;
    final screen = MediaQuery.sizeOf(context);
    _cameraTransition = true;
    try {
      await _volumeSubscription?.cancel();
      _volumeSubscription = null;
      setState(() => _cameraReleased = true);
      await _controller?.dispose();
      _controller = null;
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => LayoutCameraScreen(
        cameras: cameras, aspect: _aspect, screen: screen, cameraIndex: _selectedCameraIndex,
      )));
    } finally {
      _cameraTransition = false;
      if (mounted) {
        _volumeSubscription = _volumeChannel.receiveBroadcastStream().listen((dynamic event) {
          if (event is String) _handleVolumeEvent(event);
        });
        if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          await _initCamera(_selectedCameraIndex);
        }
      }
    }
  }

  Widget _buildAspectChip() {
    final bool locked = _isRecordingVideo || _isBoomerangCapturing;
    return Padding(
      padding: const EdgeInsets.only(top: 22, left: 14),
      child: AnimatedOpacity(
        opacity: locked ? 0.4 : 1,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: locked ? null : _pickAspect,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectIcon(ratio: _aspect.resolveRatio(MediaQuery.sizeOf(context)), size: 16),
                const SizedBox(width: 6),
                Text(_aspect.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startVideoRecording({bool isToggle = false}) async {
    if (_isBoomerangMode && !isToggle) return;
    if (_isAuraMode) {
      if (mounted) {
        _showToast('Video recording disabled in Aura Mode', duration: const Duration(seconds: 1));
      }
      return;
    }
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.isRecordingVideo ||
        _isStartingVideo ||
        (!isToggle && (_isRecordingVideo || _isFlipping))) {
      if (isToggle) _abortRecording();
      return;
    }

    _isStartingVideo = true;
    if (!isToggle) _stopRequested = false;
    _baseZoomLevel = _currentZoomLevel;

    if (!isToggle) {
      _videoSegments.clear();
      _recordingAspect = _videoCropRatio();
      // Update the UI immediately; CameraX needs up to a second to reconfigure
      // the session for video before recording actually starts.
      CaptureFeedback.videoStart();
      _recordStopwatch.reset();
      setState(() {
        _isRecordingVideo = true;
      });
    }

    try {
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.torch);
      }
      await _controller!.startVideoRecording();
      _segmentStartedAt = DateTime.now();
      if (!isToggle) {
        _startRecordTimer();
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

  Future<void> _stopVideoRecording({bool isToggle = false}) async {
    if (_isStartingVideo || _isSwitchingCamera) {
      _stopRequested = true;
      return;
    }
    if (_controller == null || !_controller!.value.isRecordingVideo) {
      return;
    }

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
      _segmentStartedAt = null;
      bool isFront = cameras.isNotEmpty && cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
      _videoSegments.add(VideoSegment(file.path, isFront));

      if (!isToggle) {
        CaptureFeedback.videoStopSound();
        _enqueueSegmentsSave();
      }

      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.always);
      }
    } on CameraException catch (e) {
      debugPrint('Error stopping video recording: $e');
      if (!isToggle) {
        _enqueueSegmentsSave();
      }
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
    if (_videoSegments.isEmpty) return;
    final segments = List<VideoSegment>.of(_videoSegments);
    _videoSegments.clear();
    final double? aspect = _recordingAspect;
    MediaSaveQueue.instance.add(() => _stitchAndSaveVideos(segments, aspect));
  }

  /// [aspect] (width / height) crops to the chosen framing; null keeps the
  /// full 9:16 recording.
  Future<void> _stitchAndSaveVideos(List<VideoSegment> segments, double? aspect) async {
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
        outputPath = await VideoProcessor.mirror(segments.first.path, aspect: aspect);
      }
    } else {
      outputPath = await VideoProcessor.stitch([
        for (final s in segments) (path: s.path, mirror: s.isFrontCamera),
      ], aspect: aspect);
    }

    await _saveVideoToGallery(outputPath ?? segments.first.path);
  }

  // ---------------------------------------------------------------------------
  // Boomerang (∞)

  Future<void> _loadBoomerangSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final int seconds = prefs.getInt('boomerang_seconds') ?? 1;
    if (mounted) setState(() => _boomerangSeconds = seconds.clamp(1, _maxBoomerangSeconds));
  }

  void _setBoomerangSeconds(int seconds) {
    if (_isBoomerangCapturing || seconds == _boomerangSeconds) return;
    HapticFeedback.selectionClick();
    setState(() => _boomerangSeconds = seconds);
    SharedPreferences.getInstance().then((prefs) => prefs.setInt('boomerang_seconds', seconds));
  }

  void _setMode(CaptureMode mode) {
    if (mode == _mode || _isRecordingVideo || _isBoomerangCapturing) return;
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
    final double seconds = min(_boomerangStopwatch.elapsedMilliseconds / 1000, _boomerangSeconds.toDouble());
    final bool mirror = cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
    CaptureFeedback.videoStop();

    final CameraController? controller = _controller;
    XFile? file;
    try {
      if (controller != null && controller.value.isRecordingVideo) {
        file = await controller.stopVideoRecording();
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
            onSave: (effect, frameCount) => _saveBoomerang(videoPath, seconds, mirror, effect, frameCount, aspect),
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
  void _saveBoomerang(String videoPath, double seconds, bool mirror, BoomerangEffect effect, int frameCount, double? aspect) {
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
      await _saveVideoToGallery(output, label: '∞ Boomerang', album: MediaAlbum.boomerang);
    });
  }

  Widget _buildModeSwitch() {
    Widget segment(CaptureMode mode, String label, {IconData? icon}) {
      final bool selected = _mode == mode;
      final Gradient? gradient = !selected
          ? null
          : switch (mode) {
              CaptureMode.boomerang => const LinearGradient(colors: kBoomerangGradient),
              CaptureMode.aura => const LinearGradient(colors: [Colors.purpleAccent, Colors.deepPurpleAccent]),
              CaptureMode.normal => const LinearGradient(colors: [Colors.amber, Color(0xFFFFC83D)]),
            };
      final Color fg = selected && mode == CaptureMode.normal ? Colors.black : (selected ? Colors.white : Colors.white70);
      return GestureDetector(
        onTap: () => _setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(30)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 5),
              ],
              Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(CaptureMode.normal, 'Normal'),
          segment(CaptureMode.boomerang, 'Boomerang', icon: Icons.all_inclusive),
          segment(CaptureMode.aura, 'Aura Calc'),
        ],
      ),
    );
  }

  /// 1s / 2s / 3s picker shown in Boomerang mode.
  Widget _buildBoomerangLengthPicker() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int s = 1; s <= _maxBoomerangSeconds; s++)
            GestureDetector(
              onTap: () => _setBoomerangSeconds(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: s == _boomerangSeconds ? Colors.white : Colors.transparent,
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

  Future<void> _saveVideoToGallery(String path, {String label = 'Video', MediaAlbum album = MediaAlbum.videos}) async {
    try {
      await MediaLibrary.saveVideo(path, album);
      final streakData = await StreakService.incrementStreak();

      if (mounted) {
        _showToast(
          streakData.justIncreased ? '🔥 ${streakData.count} Day Streak! $label saved! ✨' : '$label saved to gallery! ✨',
          highlight: streakData.justIncreased,
        );
      }
    } catch (e) {
      debugPrint('Error saving video: $e');
    }
  }

  /// Applies a zoom level from any gesture, keeping the capture-button label
  /// in sync. Snaps to 1x so returning to the normal view is easy.
  void _setZoom(double requested) {
    final CameraController? controller = _controller;
    if (_isFlipping || controller == null || !controller.value.isInitialized) return;

    double zoom = requested.clamp(_minZoomLevel, _maxZoomLevel);
    if ((zoom - 1.0).abs() < 0.08) {
      zoom = 1.0.clamp(_minZoomLevel, _maxZoomLevel);
    }

    _zoomGestureActive.value = true;
    _zoomLabelTimer?.cancel();
    _zoomLabelTimer = Timer(const Duration(milliseconds: 900), () => _zoomGestureActive.value = false);

    if ((zoom - _currentZoomLevel).abs() < 0.02) return;

    // Light tick at each whole step (1x, 2x, 3x...) like native camera apps
    if (zoom.floor() != _currentZoomLevel.floor() || (zoom == 1.0 && _currentZoomLevel != 1.0)) {
      HapticFeedback.selectionClick();
    }
    controller.setZoomLevel(zoom);
    _currentZoomLevel = zoom;
    _zoomNotifier.value = zoom;
  }

  /// Sliding up on the capture button zooms in, sliding down zooms out.
  /// [dy] is the total vertical offset since the slide began (negative = up).
  void _handleSlideZoom(double dy) {
    _setZoom(_baseZoomLevel * pow(2, -dy / _zoomDragPixelsPerDoubling).toDouble());
  }

  /// Shutter handler. Taps made while a capture is still in flight are queued
  /// and taken back-to-back, so no tap is lost during rapid shooting.
  Future<void> _captureAura() async {
    if (_isBoomerangMode) {
      await _onBoomerangPressed();
      return;
    }
    if (_isFlipping || _controller == null || !_controller!.value.isInitialized) {
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

    final bool isFrontCamera = cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;

    final XFile file;
    try {
      file = await controller.takePicture();
    } catch (e) {
      debugPrint('Error taking picture: $e');
      return;
    }

    if (!mounted) return;
    final String originalImagePath = file.path;

    StreakService.incrementStreak().then((streakData) {
      if (mounted && streakData.justIncreased) {
        _showToast('🔥 ${streakData.count} Day Streak!', highlight: true);
      }
    });

    try {
      if (isAuraMode) {
        final String finalPath = await PhotoProcessor.process(originalImagePath, mirror: isFrontCamera);

        UploadManager.instance.enqueue(finalPath);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResultScreen(imagePath: finalPath, isFrontCamera: isFrontCamera),
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
  Future<void> _saveNormalPhoto(String originalImagePath, bool isFrontCamera) async {
    final double? aspect = _photoCropRatio();
    // Laptop/desktop framings are wallpapers; everything else is a snap
    final MediaAlbum album = !_isAuraMode && _aspect.category == AspectCategory.desktop ? MediaAlbum.wallpapers : MediaAlbum.snaps;
    final photo = CapturedPhoto(originalPath: originalImagePath, mirrored: isFrontCamera, aspect: aspect);
    if (_photoFrameSize == null) _measurePhotoFrame(originalImagePath);
    _sessionPhotos.insert(0, photo);
    if (_sessionPhotos.length > _maxSessionPhotos) {
      _sessionPhotos.removeLast();
    }
    _lastCapture.value = photo;

    final prefs = await SharedPreferences.getInstance();
    final bool watermarkEnabled = prefs.getBool('watermark_enabled') ?? false;
    final String watermarkText = prefs.getString('custom_watermark') ?? 'Calculate your Aura: Download AURA App';

    MediaSaveQueue.instance.add(() async {
      final String finalPath = await PhotoProcessor.process(
        originalImagePath,
        mirror: isFrontCamera,
        watermark: watermarkEnabled ? watermarkText : null,
        aspect: aspect,
      );
      // The unprocessed camera file is still shown by the thumbnail, so copy it
      final String savedPath = await MediaLibrary.saveImage(finalPath, album, keepSource: finalPath == originalImagePath);
      photo.savedPath.value = savedPath;
      UploadManager.instance.enqueue(savedPath);
    });
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    try {
      final newMode = !_isFlashOn;
      await _controller!.setFlashMode(newMode ? FlashMode.always : FlashMode.off);
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
        if (_volumeKeyDownTime != null && mounted && !_isRecordingVideo) {
          debugPrint("AURA_DEBUG: Long press detected via volume button. Starting video.");
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
          debugPrint("AURA_DEBUG: Short press detected via volume button. Capturing photo.");
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
    if (_cameraTransition) return;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (!_cameraReleased) _releaseCamera();
    } else if (state == AppLifecycleState.resumed && _cameraReleased) {
      _reopenCamera();
    }
  }

  /// Frees the camera while the app is in the background. A video in progress
  /// is stopped and saved first so the clip isn't lost and the UI doesn't stay
  /// stuck in the recording state; an unfinished boomerang is discarded.
  Future<void> _releaseCamera() async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _cameraTransition = true;
    DateTime? interruptedSince;
    final bool isFront = cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
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
    if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
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
        if (modified.isBefore(since.subtract(const Duration(seconds: 1)))) continue;
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
      // The microphone keeps going after the camera stops; drop that tail
      final String path = await VideoProcessor.trimToVideo(clip.path) ?? clip.path;
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
  void _showToast(String message, {bool highlight = false, Duration duration = const Duration(seconds: 3)}) {
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
          style: TextStyle(color: highlight ? Colors.black : Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: highlight ? Colors.orangeAccent : const Color(0xE6222228),
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
      MaterialPageRoute(builder: (context) => CapturePreviewScreen(photos: List.of(_sessionPhotos))),
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
                    scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                    child: child,
                  ),
                  child: last == null
                      ? const Icon(Icons.photo_library, key: ValueKey('gallery_icon'), color: Colors.white, size: 32)
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent)),
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

          // Top action buttons
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Aspect ratio (not used for Aura analysis)
                _isAuraMode ? const SizedBox(width: 48) : _buildAspectChip(),

                // Title removed from here

                // Leaderboard and Settings (Top Right)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, right: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.leaderboard, color: Colors.amber, size: 32),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white70),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          color: _isFlashOn ? Colors.amber : Colors.white70,
                        ),
                        onPressed: _toggleFlash,
                      ),
                      if (_mode == CaptureMode.normal)
                        IconButton(
                          key: const ValueKey('normal-layout-button'),
                          tooltip: 'Layout',
                          icon: const Icon(Icons.grid_view_rounded, color: Colors.white70),
                          onPressed: _isRecordingVideo || _isCapturing || _isStartingVideo ? null : _openLayouts,
                        ),

                    ],
                  ),
                ),
              ],
            ),
          ),


          // Mode Switch and Camera Controls
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      padding: const EdgeInsets.only(bottom: 36.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            child: _isBoomerangMode ? _buildBoomerangLengthPicker() : const SizedBox(width: 0),
                          ),
                          _buildModeSwitch(),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 40.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                      _isAuraMode
                        ? IconButton(
                        icon: const Icon(Icons.photo_library, color: Colors.white, size: 32),
                        onPressed: () async {
                          try {
                            final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
                            if (file != null && mounted) {
                              // Upload in background via UploadManager (Non-blocking queue)
                              UploadManager.instance.enqueue(file.path);
                              
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ResultScreen(imagePath: file.path, isFrontCamera: false),
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
                      onTap: _isRecordingVideo ? () => _stopVideoRecording() : _captureAura,
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
                      onZoomStart: () => _baseZoomLevel = _currentZoomLevel,
                      onSlideZoom: _handleSlideZoom,
                    ),
                    
                    // Toggle Camera Button
                    IconButton(
                      icon: AnimatedRotation(
                        turns: _flipTurns,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        child: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 32),
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
        ],
      ),
    );
  }
}

void _showSettings(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return const SettingsSheet();
    },
  );
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  String _savePreference = 'Both'; // Default

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savePreference = prefs.getString('save_preference') ?? 'Both';
    });
  }

  Future<void> _savePref(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('save_preference', value);
    setState(() {
      _savePreference = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24.0, 
        right: 24.0, 
        top: 24.0, 
        bottom: MediaQuery.of(context).viewInsets.bottom + 24.0
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            // Model Selection Setting
            const Text('Model Selection:', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 10),
            ListTile(
              title: const Text('Gemini 3.1 Pro (High)', style: TextStyle(color: Colors.white)),
              leading: Radio<String>(
                value: 'Gemini 3.1 Pro (High)',
                groupValue: 'Gemini 3.1 Pro (High)', // Hardcoded default for now
                onChanged: (val) {},
                activeColor: Colors.deepPurpleAccent,
              ),
            ),
            const SizedBox(height: 10),

            // Save Preference Setting
            const Text('Save Snapshot Default:', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 10),
            ListTile(
              title: const Text('Original Photo Only', style: TextStyle(color: Colors.white)),
              leading: Radio<String>(
                value: 'Original',
                groupValue: _savePreference,
                onChanged: (val) => _savePref(val!),
                activeColor: Colors.deepPurpleAccent,
              ),
            ),
            ListTile(
              title: const Text('With Score (Screenshot)', style: TextStyle(color: Colors.white)),
              leading: Radio<String>(
                value: 'Screenshot',
                groupValue: _savePreference,
                onChanged: (val) => _savePref(val!),
                activeColor: Colors.deepPurpleAccent,
              ),
            ),
            ListTile(
              title: const Text('Both', style: TextStyle(color: Colors.white)),
              leading: Radio<String>(
                value: 'Both',
                groupValue: _savePreference,
                onChanged: (val) => _savePref(val!),
                activeColor: Colors.deepPurpleAccent,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class ResultScreen extends StatefulWidget {
  final String imagePath;
  final bool isFrontCamera;

  const ResultScreen({super.key, required this.imagePath, required this.isFrontCamera});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _isCalculating = true;
  AuraResult? _auraResult;
  Size? _imageSize;
  final GlobalKey _globalKey = GlobalKey();
  final AuraCalculatorService _calculator = AuraCalculatorService.instance;
  bool _watermarkEnabled = false;
  String _customWatermarkText = 'Calculate your Aura: Download AURA App';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _calculateRealAura();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _watermarkEnabled = prefs.getBool('watermark_enabled') ?? false;
        _customWatermarkText = prefs.getString('custom_watermark') ?? 'Calculate your Aura: Download AURA App';
      });
    }
  }

  Future<void> _calculateRealAura() async {
    _startHeartbeat();
    
    // Process image using ML Kit (the result carries the photo's size, so the
    // full-resolution image no longer has to be decoded here)
    AuraResult result = await _calculator.analyzeImage(widget.imagePath);
    final imageSize = Size(max(result.imageWidth, 1).toDouble(), max(result.imageHeight, 1).toDouble());

    if (!mounted) return;
    
    setState(() {
      _isCalculating = false;
      _auraResult = result;
      _imageSize = imageSize;
    });
    
    // Submit score to global leaderboard if it's a valid human
    if (result.hasHuman) {
      ApiService.submitScoreToLeaderboard(result.score);
    }

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 50, 100, 200]);
    }
    final player = AudioPlayer();
    await player.play(AssetSource('audio/reveal.wav'));

    // Only real results are kept in the gallery (not "no human" screens)
    if (result.hasHuman) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _saveAura(showSnackBar: false);
        });
      });
    }
  }

  void _startHeartbeat() async {
    while (mounted && _isCalculating) {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 50);
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  @override
  void dispose() {
    _calculator.dispose();
    super.dispose();
  }

  Future<void> _shareAura() async {
    try {
      // Show loading indicator or toast if needed, but this is usually fast enough
      RenderRepaintBoundary boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final imagePath = await File('${directory.path}/shared_aura.png').create();
      await imagePath.writeAsBytes(bytes);

      String text = _auraResult?.hasHuman == true 
        ? 'Check my aura score: ${_groupDigits(_auraResult!.score)}' 
        : 'Checking my aura score';
        
      await Share.shareXFiles([XFile(imagePath.path)], text: text);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
    }
  }

  Future<void> _saveAura({bool showSnackBar = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final pref = prefs.getString('save_preference') ?? 'Both';

    if (pref == 'Original' || pref == 'Both') {
      try {
        await MediaLibrary.saveImage(widget.imagePath, MediaAlbum.auraResults, keepSource: true);
      } catch (e) {
        if (mounted && showSnackBar) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        return;
      }
    }

    if (pref == 'Screenshot' || pref == 'Both') {
      await _saveScreenshot(showSnackBar: showSnackBar);
    }

    if (mounted && showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved according to preference ($pref)')),
      );
    }
  }

  Future<void> _saveScreenshot({bool showSnackBar = true}) async {
    try {
      RenderRepaintBoundary boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      
      await MediaLibrary.saveImageBytes(bytes, MediaAlbum.auraResults);
      if (mounted && showSnackBar) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aura Snapshot saved!')));
    } catch (e) {
      if (mounted && showSnackBar) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save screenshot: $e')));
    }
  }

  void _showDetailedBreakdown(BuildContext context, DetailedAuraScore details) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                    const Text('Aura Breakdown', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    if (details.face != null) _buildDetailSection('Face', details.face!),
                    if (details.eyes != null) _buildDetailSection('Eyes', details.eyes!),
                    if (details.expression != null) _buildDetailSection('Expression', details.expression!),
                    _buildDetailSection('Body & Shape', details.body),
                    _buildDetailSection('Posture', details.posture),
                    _buildDetailSection('Pose & Dynamism', details.pose),
                    _buildDetailSection('Style', details.style),
                    _buildDetailSection('Lighting & Composition', details.image),
                    _buildDetailSection('Aura Presence', details.presence),
                    _buildDetailSection('Content Check', details.content),
                    const Divider(color: Colors.grey),
                    _buildDetailRow('Total Aura Score', _auraResult!.score, [], isTotal: true),
                  ],
                ),
              ),
            );
          },
        );
      }
    );
  }

  Widget _buildDetailSection(String label, DimensionScore scoreObj) {
    if (scoreObj.score == 0 && scoreObj.components.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text(
                '${scoreObj.score > 0 ? '+' : ''}${_groupDigits(scoreObj.score)}',
                style: TextStyle(
                  color: scoreObj.score < 0 ? Colors.redAccent : Colors.greenAccent,
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
                scoreObj.primaryTraits.join(' • '),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                      Expanded(child: Text('${comp.attribute}: ${comp.measurement}', style: const TextStyle(color: Colors.white70, fontSize: 14))),
                      Text('${comp.scoreImpact > 0 ? '+' : ''}${_groupDigits(comp.scoreImpact)}', style: TextStyle(color: comp.scoreImpact < 0 ? Colors.red[300] : Colors.green[300], fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(comp.description, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, int score, List<String> traits, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: Colors.white70, fontSize: isTotal ? 20 : 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
              Text(
                '${score > 0 ? '+' : ''}${_groupDigits(score)}',
                style: TextStyle(
                  color: score < 0 ? Colors.redAccent : Colors.greenAccent,
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
                traits.join(' • '),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 30),
          onPressed: () => Navigator.pop(context),
        ),

      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: _globalKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: Colors.black, // Ensure pure black background
                  child: Image.file(
                    File(widget.imagePath),
                    key: ValueKey('${widget.imagePath}_${DateTime.now().millisecondsSinceEpoch}'), 
                    fit: BoxFit.contain, // Changed from cover to contain to prevent stretching/cropping
                    width: double.infinity, 
                    height: double.infinity
                  ),
                ),

                if (_watermarkEnabled && _customWatermarkText.isNotEmpty)
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _customWatermarkText,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

              if (_isCalculating)
                Container(
                  color: Colors.black.withValues(alpha: 0.7),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.pinkAccent),
                        SizedBox(height: 20),
                        Text(
                          'Calculating Proportions & Physics...',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                
              if (!_isCalculating && _auraResult != null && _imageSize != null)
                Builder(builder: (context) {
                  if (!_auraResult!.hasHuman) {
                    // NO HUMAN DETECTED (or the photo couldn't be read)
                    return SafeArea(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 60),
                            const SizedBox(height: 20),
                            Text(
                              _auraResult!.error != null ? 'COULDN\'T READ PHOTO' : 'NO HUMAN DETECTED',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 5,
                                color: Colors.orangeAccent,
                              ),
                            ),
                            if (_auraResult!.hint != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(32, 14, 32, 0),
                                child: Text(
                                  _auraResult!.hint!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Mapping coordinates for dynamic UI
                  Size screenSize = MediaQuery.of(context).size;
                  double scaleX = screenSize.width / _imageSize!.width;
                  double scaleY = screenSize.height / _imageSize!.height;
                  double scale = max(scaleX, scaleY);
                  
                  double displayedWidth = _imageSize!.width * scale;
                  double displayedHeight = _imageSize!.height * scale;
                  
                  double offsetX = (displayedWidth - screenSize.width) / 2;
                  double offsetY = (displayedHeight - screenSize.height) / 2;

                  // Remove unused variables

                  int score = _auraResult!.score;
                  
                  return Stack(
                    children: [
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16.0, left: 16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        if (_auraResult!.details != null) {
                                          _showDetailedBreakdown(context, _auraResult!.details!);
                                        }
                                      },
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${score > 0 ? '+' : ''}${_groupDigits(score)}',
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            color: score < 0 ? Colors.redAccent : Colors.white,
                                            shadows: [
                                              Shadow(blurRadius: 10, color: score < 0 ? Colors.red : Colors.pinkAccent),
                                              Shadow(blurRadius: 20, color: score < 0 ? Colors.red[900]! : Colors.deepPurpleAccent),
                                            ]
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.info_outline, color: Colors.white, size: 24),
                                      onPressed: () {
                                        if (_auraResult!.details != null) {
                                          _showDetailedBreakdown(context, _auraResult!.details!);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                Text(
                                  score < 0 ? 'NEGATIVE AURA' : 'AURA LEVEL',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                    color: score < 0 ? Colors.red[200] : Colors.white,
                                    shadows: const [Shadow(blurRadius: 5, color: Colors.black)],
                                  ),
                                ),
                                if (_auraResult!.hypeMessage != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.5)),
                                    ),
                                    child: Text(
                                      _auraResult!.hypeMessage!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white.withValues(alpha: 0.9),
                                          shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
                                        ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                

              ],
            ),
          ),
          
          // Action Buttons Outside RepaintBoundary
          if (!_isCalculating && _auraResult != null && _imageSize != null && _auraResult!.hasHuman)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.share, size: 28),
                        label: const Text('SHARE ON INSTA / SOCIALS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurpleAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 10,
                        ),
                        onPressed: _shareAura,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
          // End of body stack children
        ],
      ),
    );
  }
}
