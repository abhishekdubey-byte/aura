import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User intent is shared and durable; camera/service availability is temporary.
class HandsFreePreferences extends ChangeNotifier {
  static final instance = HandsFreePreferences();
  bool gestures = false;
  bool voice = false;
  Future<void>? _loading;
  Future<void> _writes = Future.value();

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    gestures = prefs.getBool('hands_free_gestures') ?? false;
    voice = prefs.getBool('hands_free_voice') ?? false;
    notifyListeners();
  }

  Future<void> update({bool? gestures, bool? voice}) async {
    await load();
    if (gestures != null) this.gestures = gestures;
    if (voice != null) this.voice = voice;
    final savedGestures = this.gestures;
    final savedVoice = this.voice;
    notifyListeners();
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hands_free_gestures', savedGestures);
      await prefs.setBool('hands_free_voice', savedVoice);
    });
    await _writes;
  }
}
