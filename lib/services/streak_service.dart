import 'package:shared_preferences/shared_preferences.dart';

class StreakService {
  static const _lastOpenedKey = 'last_opened_date';
  static const _streakCountKey = 'streak_count';
  static Future<void> _queue = Future.value();

  /// Compare calendar dates in UTC to avoid DST's 23/25-hour local days.
  static int calendarDays(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_lastOpenedKey) ?? '');
    if (last == null || calendarDays(last, DateTime.now()) > 1) return 0;
    return (prefs.getInt(_streakCountKey) ?? 0).clamp(0, 1000000);
  }

  static Future<({int count, bool justIncreased})> incrementStreak() {
    final result = _queue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final last = DateTime.tryParse(prefs.getString(_lastOpenedKey) ?? '');
      final count = (prefs.getInt(_streakCountKey) ?? 0).clamp(0, 1000000);
      final days = last == null ? 2 : calendarDays(last, now);
      final increased = last == null || days > 0 || count == 0;
      final next = !increased
          ? count
          : days == 1
          ? count + 1
          : 1;
      // Clock rollback must not move the anchor backward and double-count a day.
      if (increased) {
        await prefs.setInt(_streakCountKey, next);
        await prefs.setString(_lastOpenedKey, now.toIso8601String());
      }
      return (count: next, justIncreased: increased);
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}
