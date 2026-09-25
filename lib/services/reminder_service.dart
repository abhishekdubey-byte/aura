import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/foundation.dart';

class ReminderService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // Initialize time zones for scheduling
    tz.initializeTimeZones();

    // Android Initialization
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS Initialization
    // Permission is asked later (after registration), not at app start
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

  }

  /// Asks for notification permission (Android 13+ / iOS). Called once the
  /// user has registered, so the prompt has context instead of greeting a
  /// brand-new user on top of onboarding.
  static Future<void> requestPermission() async {
    if (kIsWeb) return;
    try {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // We could navigate to a specific screen here if needed.
  }

  static Future<void> schedulePeriodicReminder() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'aura_reminder_channel', // id
      'AURA Reminders', // title
      channelDescription: 'Periodic reminders to check your AURA',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.periodicallyShow(
      id: 0,
      title: 'Time to Capture Your AURA 💫',
      body: 'Your Energy is waiting! Let\'s check your AURA today.',
      repeatInterval: RepeatInterval.daily,
      notificationDetails: platformChannelSpecifics,
      // A daily nudge doesn't need to be exact; exact alarms need a special
      // permission and failed with "exact_alarms_not_permitted"
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    debugPrint("Periodic reminder scheduled.");
  }
}
