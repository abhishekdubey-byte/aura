import 'package:aura/hands_free/hands_free_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'hands-free choices survive a new instance and rapid global changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = HandsFreePreferences();
      await settings.load();
      expect(settings.voice, false);
      expect(settings.gestures, false);
      await settings.update(gestures: true, voice: true);
      final relaunched = HandsFreePreferences();
      await relaunched.load();
      expect(relaunched.gestures, true);
      expect(relaunched.voice, true);
      await Future.wait([
        settings.update(voice: false),
        settings.update(voice: true),
        settings.update(gestures: false),
      ]);
      final saved = HandsFreePreferences();
      await saved.load();
      expect(saved.voice, true);
      expect(saved.gestures, false);
      settings.dispose();
      relaunched.dispose();
      saved.dispose();
    },
  );
}
