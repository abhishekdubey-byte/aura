// Removed taxonomy_panel import
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

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
import 'package:aura/models/upload_record.dart';

List<CameraDescription> cameras = [];

Future<String> _processImageInBackground(Map<String, dynamic> args) async {
  String imagePath = args['imagePath'];
  final bool isFrontCamera = args['isFrontCamera'];
  final bool watermarkEnabled = args['watermarkEnabled'];
  final String watermarkText = args['watermarkText'];
  final String tempDir = args['tempDir'];

  if (isFrontCamera) {
    final bytes = await File(imagePath).readAsBytes();
    final img.Image? capturedImage = img.decodeImage(bytes);
    if (capturedImage != null) {
      final img.Image flippedImage = img.flipHorizontal(capturedImage);
      final flippedPath = '$tempDir/flipped_aura_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(flippedPath).writeAsBytes(img.encodePng(flippedImage));
      imagePath = flippedPath;
    }
  }

  if (watermarkEnabled && watermarkText.isNotEmpty) {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final img.Image? capturedImage = img.decodeImage(bytes);
      if (capturedImage != null) {
        img.drawString(
          capturedImage,
          watermarkText,
          font: img.arial24,
          x: 20,
          y: capturedImage.height - 40,
          color: img.ColorRgb8(255, 255, 255),
        );
        final gallerySavePath = '$tempDir/watermarked_aura_${DateTime.now().millisecondsSinceEpoch}.png';
        await File(gallerySavePath).writeAsBytes(img.encodePng(capturedImage));
        imagePath = gallerySavePath;
      }
    } catch (e) {
      print('Error adding watermark: $e');
    }
  }

  return imagePath;
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  try {
    await Supabase.initialize(
      url: 'https://stjogqzjlbiuuubjsosd.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN0am9ncXpqbGJpdXV1Ympzb3NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODg3NTIsImV4cCI6MjEwNDk2NDc1Mn0.Xkb2Bq90XQyVbEosexfhCbHarYsWDXrzyRr39FDw50g',
    );
  } catch (e) {
    debugPrint('Supabase initialization failed: $e');
  }

  // Initialize Periodic Reminders
  try {
    await ReminderService.init();
    await ReminderService.schedulePeriodicReminder();
  } catch (e) {
    debugPrint('Reminder service initialization failed: $e');
  }

  // Initialize Background Sync for Offline Queue
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

  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error initializing cameras: ${e.code}\n${e.description}');
  }
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
class VideoSegment {
  final String path;
  final bool isFrontCamera;
  VideoSegment(this.path, this.isFrontCamera);
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
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
  bool _isStitching = false;
  bool _isAuraMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera(_selectedCameraIndex);
    _volumeSubscription = _volumeChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is String) {
        _handleVolumeEvent(event);
      }
    });
  }


  Future<void> _initCamera(int cameraIndex) async {
    if (cameras.isEmpty) return;

    final CameraController previousController = _controller ?? CameraController(cameras[0], ResolutionPreset.max);
    if (_controller != null) {
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
      
      // Enable best quality ISP settings
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      _minZoomLevel = await controller.getMinZoomLevel();
      _maxZoomLevel = await controller.getMaxZoomLevel();
      _currentZoomLevel = 1.0;

      // Apply initial flash mode
      await controller.setFlashMode(_isFlashOn ? FlashMode.always : FlashMode.off);

      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
    } on CameraException catch (e) {
      debugPrint('Camera error: ${e.code}\n${e.description}');
    }
  }

  Future<void> _toggleCamera() async {
    if (cameras.length > 1) {
      bool wasRecording = _isRecordingVideo;
      if (wasRecording) {
        await _stopVideoRecording(isToggle: true);
      }

      setState(() {
        _isCameraInitialized = false;
        _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
        _currentZoomLevel = 1.0;
      });
      
      await _initCamera(_selectedCameraIndex);
      
      if (wasRecording) {
        // Slight delay to ensure the camera is fully ready before starting the new recording
        await Future.delayed(const Duration(milliseconds: 300));
        await _startVideoRecording(isToggle: true);
      }
    }
  }

  Future<void> _startVideoRecording({bool isToggle = false}) async {
    if (_isAuraMode) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video recording disabled in Aura Mode'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    if (_controller == null || !_controller!.value.isInitialized || _isRecordingVideo) {
      return;
    }
    try {
      if (!isToggle) {
        _videoSegments.clear();
      }
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.torch);
      }
      await _controller!.startVideoRecording();
      _baseZoomLevel = _currentZoomLevel;
      if (mounted) {
        setState(() {
          _isRecordingVideo = true;
        });
      }
    } on CameraException catch (e) {
      debugPrint('Error starting video recording: $e');
    }
  }

  Future<void> _stopVideoRecording({bool isToggle = false}) async {
    if (_controller == null || !_controller!.value.isRecordingVideo) {
      return;
    }
    try {
      final XFile file = await _controller!.stopVideoRecording();
      bool isFront = cameras.isNotEmpty && cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
      _videoSegments.add(VideoSegment(file.path, isFront));

      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
        });
      }
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.always);
      }
      
      if (!isToggle) {
        await _stitchAndSaveVideos();
      }

    } on CameraException catch (e) {
      debugPrint('Error stopping video recording: $e');
    }
  }

  Future<void> _stitchAndSaveVideos() async {
    if (_videoSegments.isEmpty) return;

    if (_videoSegments.length == 1) {
      if (_videoSegments.first.isFrontCamera) {
        // Just one segment, but it's front camera so we need to flip it
        setState(() {
          _isStitching = true;
        });
        try {
          final directory = await getTemporaryDirectory();
          final outputPath = '${directory.path}/flipped_output_${DateTime.now().millisecondsSinceEpoch}.mp4';
          final String command = "-y -i '${_videoSegments.first.path}' -vf hflip -c:a copy '$outputPath'";
          final session = await FFmpegKit.execute(command);
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            await _saveVideoToGallery(outputPath);
          } else {
            await _saveVideoToGallery(_videoSegments.first.path);
          }
        } catch (e) {
          debugPrint('Error flipping single video: $e');
          await _saveVideoToGallery(_videoSegments.first.path);
        } finally {
          if (mounted) {
            setState(() {
              _isStitching = false;
            });
          }
          _videoSegments.clear();
        }
        return;
      } else {
        await _saveVideoToGallery(_videoSegments.first.path);
        _videoSegments.clear();
        return;
      }
    }

    setState(() {
      _isStitching = true;
    });

    try {
      final directory = await getTemporaryDirectory();
      
      String inputs = "";
      String filterComplex = "";
      String concatInputs = "";
      
      for (int i = 0; i < _videoSegments.length; i++) {
        inputs += "-i '${_videoSegments[i].path}' ";
        
        String videoFilter = "[$i:v]";
        if (_videoSegments[i].isFrontCamera) {
          videoFilter += "hflip,";
        }
        // Normalize to a standard portrait resolution to ensure concat works smoothly
        videoFilter += "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1[v$i];";
        
        String audioFilter = "[$i:a]aresample=44100[a$i];";
        
        filterComplex += videoFilter + audioFilter;
        concatInputs += "[v$i][a$i]";
      }
      
      filterComplex += "${concatInputs}concat=n=${_videoSegments.length}:v=1:a=1[outv][outa]";

      final outputPath = '${directory.path}/stitched_output_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final String command = "-y $inputs -filter_complex \"$filterComplex\" -map \"[outv]\" -map \"[outa]\" -c:v libx264 -preset ultrafast -crf 28 -c:a aac '$outputPath'";

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        await _saveVideoToGallery(outputPath);
      } else {
        final failLog = await session.getFailStackTrace();
        debugPrint('FFmpeg failed: $failLog');
        await _saveVideoToGallery(_videoSegments.first.path);
      }
      
    } catch (e) {
      debugPrint('Error during stitching: $e');
      await _saveVideoToGallery(_videoSegments.first.path);
    } finally {
      if (mounted) {
        setState(() {
          _isStitching = false;
        });
      }
      _videoSegments.clear();
    }
  }

  Future<void> _saveVideoToGallery(String path) async {
    try {
      await Gal.putVideo(path);
      final streakData = await StreakService.incrementStreak();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(streakData.justIncreased ? '🔥 ${streakData.count} Day Streak! Video saved! ✨' : 'Video saved to gallery! ✨'),
            backgroundColor: streakData.justIncreased ? Colors.orangeAccent : Colors.black87,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving video: $e');
    }
  }

  void _handleZoomUpdate(double dy) {
    // dy is the change in Y. Negative dy is moving up.
    double zoomRange = _maxZoomLevel - _minZoomLevel;
    // Map -200 pixels to full zoom range for smooth sliding
    double zoomDelta = (-dy / 200.0) * zoomRange;
    double newZoom = (_baseZoomLevel + zoomDelta).clamp(_minZoomLevel, _maxZoomLevel);
    
    if ((newZoom - _currentZoomLevel).abs() > 0.05) {
      _controller!.setZoomLevel(newZoom);
      _currentZoomLevel = newZoom;
    }
  }
  
  void _handleDragZoomUpdate(double deltaY) {
    double zoomRange = _maxZoomLevel - _minZoomLevel;
    double zoomDelta = (-deltaY / 100.0) * zoomRange;
    double newZoom = (_currentZoomLevel + zoomDelta).clamp(_minZoomLevel, _maxZoomLevel);
    
    if ((newZoom - _currentZoomLevel).abs() > 0.05) {
      _controller!.setZoomLevel(newZoom);
      _currentZoomLevel = newZoom;
    }
  }

  Future<void> _captureAura() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile file = await _controller!.takePicture();
      final String originalImagePath = file.path;
      final bool isFrontCamera = cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
      
      if (!mounted) return;
      
      setState(() {
        _isCapturing = false;
      });

      StreakService.incrementStreak().then((streakData) {
        if (mounted && streakData.justIncreased) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🔥 ${streakData.count} Day Streak!'),
              backgroundColor: Colors.orangeAccent,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });

      if (_isAuraMode) {
        final directory = await getTemporaryDirectory();
        String finalPath = await compute(_processImageInBackground, {
          'imagePath': originalImagePath,
          'isFrontCamera': isFrontCamera,
          'watermarkEnabled': false,
          'watermarkText': '',
          'tempDir': directory.path,
        });

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
        final prefs = await SharedPreferences.getInstance();
        bool watermarkEnabled = prefs.getBool('watermark_enabled') ?? false;
        String watermarkText = prefs.getString('custom_watermark') ?? 'Calculate your Aura: Download AURA App';
        final directory = await getTemporaryDirectory();

        compute(_processImageInBackground, {
          'imagePath': originalImagePath,
          'isFrontCamera': isFrontCamera,
          'watermarkEnabled': watermarkEnabled,
          'watermarkText': watermarkText,
          'tempDir': directory.path,
        }).then((finalPath) async {
          UploadManager.instance.enqueue(finalPath);
          await Gal.putImage(finalPath);
        }).catchError((e) {
          debugPrint('Error saving photo: $e');
        });
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
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
    final CameraController? cameraController = _controller;
    
    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_selectedCameraIndex);
    }
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    _controller?.dispose();
    super.dispose();
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
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize?.height ?? 1,
                height: _controller!.value.previewSize?.width ?? 1,
                child: GestureDetector(
                  onScaleStart: (details) {
                    _baseZoomLevel = _currentZoomLevel;
                  },
                  onScaleUpdate: (details) {
                    double newZoom = (_baseZoomLevel * details.scale).clamp(_minZoomLevel, _maxZoomLevel);
                    if ((newZoom - _currentZoomLevel).abs() > 0.05) {
                      _controller!.setZoomLevel(newZoom);
                      _currentZoomLevel = newZoom;
                    }
                  },
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          ),
          

          // Top action buttons
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Empty Left Side to keep balance
                const SizedBox(width: 48),

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
                  // Mode Toggle
                  Container(
                    margin: const EdgeInsets.only(bottom: 20.0),
                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _isAuraMode = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: !_isAuraMode ? Colors.amber : Colors.transparent,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              'Normal',
                              style: TextStyle(
                                color: !_isAuraMode ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _isAuraMode = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: _isAuraMode ? Colors.purpleAccent : Colors.transparent,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              'Aura Calc',
                              style: TextStyle(
                                color: _isAuraMode ? Colors.white : Colors.white70,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 40.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                      IconButton(
                        icon: const Icon(Icons.photo_library, color: Colors.white, size: 32),
                        onPressed: () async {
                          if (!_isAuraMode) {
                            try {
                              await Gal.open();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not open gallery app')),
                                );
                              }
                            }
                            return;
                          }
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Could not open gallery')),
                              );
                            }
                          }
                        },
                      ),
                    
                    // Capture Button
                    _isStitching
                      ? const CircularProgressIndicator(color: Colors.white)
                      : AnimatedCaptureButton(
                          isRecording: _isRecordingVideo,
                          onTap: _captureAura,
                          onLongPressStart: () => _startVideoRecording(),
                          onLongPressEnd: () => _stopVideoRecording(),
                          onLongPressMoveUpdate: _handleZoomUpdate,
                          onDragUpdate: _handleDragZoomUpdate,
                        ),
                    
                    // Toggle Camera Button
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 32),
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

class AnimatedCaptureButton extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;
  final Function(double) onLongPressMoveUpdate;
  final Function(double) onDragUpdate;
  final bool isRecording;

  const AnimatedCaptureButton({
    super.key,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onLongPressMoveUpdate,
    required this.onDragUpdate,
    required this.isRecording,
  });

  @override
  State<AnimatedCaptureButton> createState() => _AnimatedCaptureButtonState();
}

class _AnimatedCaptureButtonState extends State<AnimatedCaptureButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
  }
  
  @override
  void didUpdateWidget(AnimatedCaptureButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _controller.forward();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: (_) => widget.onLongPressStart(),
      onLongPressMoveUpdate: (details) => widget.onLongPressMoveUpdate(details.localOffsetFromOrigin.dy),
      onLongPressEnd: (_) => widget.onLongPressEnd(),
      onVerticalDragUpdate: (details) => widget.onDragUpdate(details.primaryDelta ?? 0),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.isRecording ? Colors.redAccent.withOpacity(0.6) : Colors.deepPurpleAccent,
                  width: widget.isRecording ? 8 : 4,
                ),
                color: widget.isRecording ? Colors.redAccent.withOpacity(0.15) : Colors.transparent,
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  height: widget.isRecording ? 45 : 60,
                  width: widget.isRecording ? 45 : 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.isRecording ? 12 : 30),
                    color: widget.isRecording ? Colors.redAccent : Colors.white,
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
  final AuraCalculatorService _calculator = AuraCalculatorService();
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
    
    // Decode image size
    final imageFile = File(widget.imagePath);
    final bytes = await imageFile.readAsBytes();
    final decodedImage = await decodeImageFromList(bytes);
    final imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());

    // Process image using ML Kit
    AuraResult result = await _calculator.analyzeImage(widget.imagePath);
    
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _saveAura(showSnackBar: false);
      });
    });
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
        ? 'Check my aura score: ${_auraResult!.score}' 
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
        await Gal.putImage(widget.imagePath);
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
      
      await Gal.putImageBytes(bytes);
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
                    _buildDetailSection('Content Bonus', details.content),
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
                '${scoreObj.score > 0 ? '+' : ''}${scoreObj.score}',
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
                      Text('${comp.scoreImpact > 0 ? '+' : ''}${comp.scoreImpact}', style: TextStyle(color: comp.scoreImpact < 0 ? Colors.red[300] : Colors.green[300], fontSize: 14, fontWeight: FontWeight.w600)),
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
                '${score > 0 ? '+' : ''}$score',
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
                    // NO HUMAN DETECTED
                    return const SafeArea(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 60),
                            SizedBox(height: 20),
                            Text(
                              'NO HUMAN DETECTED',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 5,
                                color: Colors.orangeAccent,
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
                                          '${score > 0 ? '+' : ''}$score',
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
