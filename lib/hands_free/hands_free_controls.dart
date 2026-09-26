import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'hands_free_commands.dart';
import 'hands_free_preferences.dart';

class HandsFreeControls extends StatefulWidget {
  const HandsFreeControls({
    super.key,
    required this.contextState,
    required this.ready,
    required this.snapshot,
    required this.onAction,
    this.elapsed,
    this.showSettingsButton = true,
  });
  final bool showSettingsButton;
  @visibleForTesting
  final Duration Function()? elapsed;
  final RemoteContext Function() contextState;
  final bool Function() ready;
  final Future<Uint8List?> Function() snapshot;
  final Future<void> Function(RemoteAction) onAction;
  @override
  State<HandsFreeControls> createState() => HandsFreeControlsState();
}

class HandsFreeControlsState extends State<HandsFreeControls>
    with WidgetsBindingObserver {
  static const _native = MethodChannel('com.aura.aura/hands_free');
  static final _events = const EventChannel('com.aura.aura/hands_free_events')
      .receiveBroadcastStream()
      .asBroadcastStream();
  final _owner = UniqueKey().toString();
  final _clock = Stopwatch()..start();
  final _gate = GestureGate();
  final _preferences = HandsFreePreferences.instance;
  bool get _gestures => _preferences.gestures;
  bool get _voice => _preferences.voice;
  bool _voiceStarted = false, _listening = false;
  Duration _voiceRetryAt = Duration.zero, _gestureRetryAt = Duration.zero;
  bool _frameBusy = false,
      _configuring = false,
      _executing = false,
      _foreground = true;
  bool _speechBusy = false, _disposed = false;
  int _generation = 0, _frameFailures = 0;
  int? _countdown;
  RemoteAction? _pending;
  RemoteContext? _countdownContext;
  Duration _lastWords = const Duration(seconds: -10);
  String? _message;
  Timer? _poll, _countTimer;
  StreamSubscription<dynamic>? _subscription;
  Duration get _now => widget.elapsed?.call() ?? _clock.elapsed;
  bool get _on => _gestures || _voice;
  bool get _visible =>
      mounted && _foreground && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preferences.addListener(_preferencesChanged);
    _preferences.load();
    if ((!kIsWeb && defaultTargetPlatform == TargetPlatform.android)) {
      _subscription = _events.listen(
        _voiceEvent,
        onError: (Object _) {
          if (mounted && _voice) {
            setState(() {
              _voiceRetryAt = _now + const Duration(seconds: 30);
              _message = 'Voice service unavailable. Retrying automatically…';
              _voiceStarted = false;
            });
          }
        },
      );
      _poll = Timer.periodic(const Duration(milliseconds: 300), (_) => _tick());
    }
  }

  void _preferencesChanged() {
    if (!mounted) return;
    _generation++;
    cancelPending();
    setState(() {
      _voiceRetryAt = Duration.zero;
      _gestureRetryAt = Duration.zero;
      _message = null;
    });
    if (!_voice) prepareForVideo();
  }

  void cancelPending() {
    _countTimer?.cancel();
    _pending = null;
    _countdownContext = null;
    if (mounted && _countdown != null) setState(() => _countdown = null);
    _gate.disarm();
  }

  Future<void> suspend() async {
    _generation++;
    cancelPending();
    await prepareForVideo();
  }

  /// Release speech capture before the recorder acquires the microphone.
  Future<void> prepareForVideo() async {
    if (!_voiceStarted && !_listening && !_speechBusy) return;
    _voiceStarted = false;
    _listening = false;
    try {
      await _native.invokeMethod<void>('stopVoice', {'owner': _owner});
    } catch (_) {}
  }

  Future<void> _syncVoice() async {
    if (_speechBusy || _disposed) return;
    final state = widget.contextState();
    final wanted =
        _voice &&
        _now >= _voiceRetryAt &&
        _visible &&
        widget.ready() &&
        !state.recording &&
        !state.busy &&
        !_executing;
    if (wanted == _voiceStarted) return;
    _speechBusy = true;
    try {
      _voiceStarted = wanted;
      if (wanted) {
        await _native.invokeMethod<void>('startVoice', {'owner': _owner});
        if (!_visible ||
            !_voice ||
            widget.contextState().recording ||
            widget.contextState().busy ||
            !widget.ready() ||
            _executing) {
          await prepareForVideo();
        }
      } else {
        await prepareForVideo();
      }
    } catch (_) {
      _voiceStarted = false;
      if (mounted) {
        setState(() {
          _voiceRetryAt = _now + const Duration(seconds: 30);
          _message = 'Voice is enabled but unavailable. Check microphone access or your speech service. Retrying automatically…';
        });
      }
    } finally {
      _speechBusy = false;
    }
  }

  void _voiceEvent(dynamic event) {
    if (event is! Map || event['owner'] != _owner || !_voice || !_visible) {
      return;
    }
    switch (event['type']) {
      case 'listening':
        setState(() {
          _listening = true;
          _message = null;
        });
      case 'processing':
      case 'waiting':
        setState(() => _listening = false);
      case 'retrying':
        setState(() {
          _listening = false;
          _message = event['text'] as String?;
        });
      case 'error':
        setState(() {
          _voiceRetryAt = _now + const Duration(seconds: 30);
          _voiceStarted = false;
          _listening = false;
          _message = event['text'] as String?;
        });
      case 'words':
        final signal = parseVoiceCommand(event['text'] as String? ?? '');
        if (signal == null ||
            (signal != RemoteSignal.cancel &&
                _now - _lastWords < const Duration(seconds: 2))) {
          return;
        }
        _lastWords = _now;
        _accept(signal);
    }
  }

  Future<void> _tick() async {
    if (_disposed) return;
    if (!_visible || !widget.ready()) {
      if (_countdown != null) cancelPending();
      _gate.disarm();
      await _syncVoice();
      return;
    }
    final state = widget.contextState();
    final expected = _countdownContext;
    if (expected != null &&
        (state.mode != expected.mode ||
            state.recording != expected.recording ||
            state.paused != expected.paused ||
            state.busy)) {
      cancelPending();
    }
    await _syncVoice();
    if (!_gestures ||
        _now < _gestureRetryAt ||
        _frameBusy ||
        _executing ||
        state.busy) {
      return;
    }
    _frameBusy = true;
    final generation = _generation;
    try {
      final bytes = await widget.snapshot();
      if (bytes == null || !_visible || generation != _generation) return;
      final rows = await _native.invokeListMethod<dynamic>('analyze', {
        'image': bytes,
      });
      if (!_visible || !_gestures || generation != _generation) return;
      _frameFailures = 0;
      final signal = HandSignals.classify(
        (rows ?? []).whereType<Map>().map(ObservedHand.fromMap).toList(),
      );
      final accepted = _gate.update(signal, _now);
      if (accepted != null) _accept(accepted);
    } catch (_) {
      _frameFailures++;
      if (_frameFailures >= 4 && mounted) {
        setState(() {
          _gestureRetryAt = _now + const Duration(seconds: 10);
          _message = 'Hand detection interrupted. Retrying automatically…';
        });
        cancelPending();
      }
    } finally {
      _frameBusy = false;
    }
  }

  void _accept(RemoteSignal signal) {
    if (!_visible || !widget.ready() || _executing) return;
    final state = widget.contextState();
    final action = resolveRemoteAction(
      signal,
      state,
      countingDown: _countdown != null,
    );
    if (action == null) return;
    if (action == RemoteAction.cancel) {
      cancelPending();
      return;
    }
    if (action == RemoteAction.pause || action == RemoteAction.finish) {
      _execute(action);
      return;
    }
    _countTimer?.cancel();
    _pending = action;
    _countdownContext = state;
    setState(() {
      _countdown = 3;
      _message = null;
    });
    _countTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = widget.contextState();
      final expected = _countdownContext;
      if (!_visible ||
          !widget.ready() ||
          expected == null ||
          current.busy ||
          current.mode != expected.mode ||
          current.recording != expected.recording ||
          current.paused != expected.paused) {
        cancelPending();
        return;
      }
      if (_countdown! > 1) {
        setState(() => _countdown = _countdown! - 1);
        return;
      }
      final action = _pending!;
      cancelPending();
      _execute(action);
    });
  }

  Future<void> _execute(RemoteAction action) async {
    if (_executing || !_visible || !widget.ready()) return;
    _executing = true;
    try {
      await prepareForVideo();
      if (!_visible || !widget.ready()) return;
      await widget.onAction(action);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not complete that command. Try again.',
        );
      }
    } finally {
      _executing = false;
      _gate.disarm();
    }
  }

  Future<void> _toggleGestures(bool enabled) async {
    if (_configuring) return;
    _configuring = true;
    try {
      if (enabled) await _native.invokeMethod<void>('prepareGestures');
      if (mounted) {
        setState(() {
          _message = null;
          _frameFailures = 0;
        });
      }
      await _preferences.update(gestures: enabled);
      if (!enabled) {
        _generation++;
        cancelPending();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Hand recognition is unavailable on this device.',
        );
      }
    } finally {
      _configuring = false;
    }
  }

  Future<void> _toggleVoice(bool enabled) async {
    if (enabled && !await Permission.microphone.request().isGranted) {
      if (mounted) {
        setState(
          () => _message = 'Allow microphone access to use voice commands.',
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _message = null;
    });
    await _preferences.update(voice: enabled);
    if (!enabled) {
      cancelPending();
      await prepareForVideo();
    }
  }

  Future<void> openSettings() async {
    await suspend();
    if (!mounted) return;
    Map<dynamic, dynamic> capabilities = {};
    if ((!kIsWeb && defaultTargetPlatform == TargetPlatform.android)) {
      try {
        capabilities =
            await _native.invokeMapMethod<dynamic, dynamic>('capabilities') ??
            {};
      } catch (_) {}
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hands-free camera',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Saved for all camera and reel screens, including after reopening the app. Keep your hands visible and hold each gesture briefly.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hand gestures'),
                  subtitle: const Text(
                    'On-device detection · no preview frames are saved',
                  ),
                  value: _gestures,
                  onChanged: capabilities['gestures'] == true
                      ? (value) async {
                          await _toggleGestures(value);
                          if (context.mounted) update(() {});
                        }
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Voice commands'),
                  subtitle: Text(
                    'English commands · on-device when available, with Android speech service fallback; your provider may process audio online',
                  ),
                  value: _voice,
                  onChanged: capabilities['voice'] == true
                      ? (value) async {
                          await _toggleVoice(value);
                          if (context.mounted) update(() {});
                        }
                      : null,
                ),
                if (capabilities.isEmpty)
                  const Text(
                    'Hands-free controls are currently available on supported Android devices.',
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_message!),
                  ),
                const Divider(),
                const Text(
                  'PHOTO · Open palm, “click” or “capture”\nVIDEO · Thumbs-up or “start” to record/resume\nREEL · “capture” also starts the next clip\nPAUSE · Make a T with two open hands\nFINISH · Hold a closed fist to finish; reels open in preview',
                  style: TextStyle(height: 1.7),
                ),
                const SizedBox(height: 12),
                const Text(
                  'T gesture: point one open hand upward and hold your other hand sideways across its fingertips. Lower both hands before the next command.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'A 3-second countdown lets you pose. Tap Cancel or say “cancel” to abort. Voice listening pauses during video recording to keep microphone audio clear; gestures stay active.',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.showSettingsButton)
        TextButton.icon(
          key: const ValueKey('hands-free-settings'),
          onPressed: openSettings,
          icon: Icon(_on ? Icons.front_hand : Icons.front_hand_outlined),
          label: Text(_on ? 'Hands-free on' : 'Hands-free'),
        ),
      if (_on || _message != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _message ??
                (widget.contextState().recording && _voice
                    ? 'Voice paused for video audio${_gestures ? ' · gestures active' : ''}'
                    : '${_gestures ? 'Gestures ready' : ''}${_gestures && _voice ? ' · ' : ''}${_voice ? (_listening ? 'Listening' : 'Voice ready') : ''}'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      if (_countdown != null)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_pending == RemoteAction.photo ? 'Photo' : 'Record'} in $_countdown',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            TextButton(onPressed: cancelPending, child: const Text('Cancel')),
          ],
        ),
    ],
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      suspend();
    } else {
      _voiceRetryAt = Duration.zero;
      _gestureRetryAt = Duration.zero;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _preferences.removeListener(_preferencesChanged);
    _poll?.cancel();
    _countTimer?.cancel();
    _subscription?.cancel();
    prepareForVideo();
    _clock.stop();
    super.dispose();
  }
}
