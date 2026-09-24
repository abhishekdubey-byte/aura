import 'package:shared_preferences/shared_preferences.dart';

class StreakService {
  static const String _lastOpenedKey = 'last_opened_date';
  static const String _streakCountKey = 'streak_count';

  static Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    int streak = prefs.getInt(_streakCountKey) ?? 0;
    String? lastOpenedStr = prefs.getString(_lastOpenedKey);
    
    if (lastOpenedStr != null) {
      DateTime lastOpened = DateTime.parse(lastOpenedStr);
      DateTime now = DateTime.now();
      
      // Calculate difference in calendar days
      DateTime date1 = DateTime(lastOpened.year, lastOpened.month, lastOpened.day);
      DateTime date2 = DateTime(now.year, now.month, now.day);
      int diffInDays = date2.difference(date1).inDays;

      if (diffInDays > 1) {
        // Streak broken
        streak = 0;
      }
    }
    return streak;
  }

  static Future<({int count, bool justIncreased})> incrementStreak() async {
    final prefs = await SharedPreferences.getInstance();
    int streak = prefs.getInt(_streakCountKey) ?? 0;
    String? lastOpenedStr = prefs.getString(_lastOpenedKey);
    
    DateTime now = DateTime.now();
    bool shouldIncrement = false;

    if (lastOpenedStr == null) {
      shouldIncrement = true;
      streak = 1;
    } else {
      DateTime lastOpened = DateTime.parse(lastOpenedStr);
      
      DateTime date1 = DateTime(lastOpened.year, lastOpened.month, lastOpened.day);
      DateTime date2 = DateTime(now.year, now.month, now.day);
      int diffInDays = date2.difference(date1).inDays;

      if (diffInDays == 1) {
        // Next day!
        streak++;
        shouldIncrement = true;
      } else if (diffInDays > 1) {
        // Missed a day!
        streak = 1;
        shouldIncrement = true;
      }
      // If diffInDays == 0, they already opened it today, streak stays the same, we update the timestamp.
      if (diffInDays == 0) {
        await prefs.setString(_lastOpenedKey, now.toIso8601String());
      }
    }

    if (shouldIncrement) {
      await prefs.setInt(_streakCountKey, streak);
      await prefs.setString(_lastOpenedKey, now.toIso8601String());
    }

    return (count: streak, justIncreased: shouldIncrement && streak > 0);
  }
}
