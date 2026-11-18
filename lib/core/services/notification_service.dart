import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android notification channel ID for NEXUS operational alerts.
const String kNexusNotificationChannelId = 'nexus_alerts';

/// Handles local notifications and FCM (Firebase Cloud Messaging) wiring.
///
/// During development (Phases 1–6) with local Firebase emulators, local
/// notifications work fully offline/locally while FCM listeners, permissions,
/// and tap-navigation hooks remain wired for Phase 7 live Firebase testing.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  void Function(String? route)? _onNotificationTap;

  /// Initializes local notification channels, requests permissions, and
  /// attaches FCM foreground/tap listeners.
  Future<void> initialize({
    void Function(String? route)? onNotificationTap,
  }) async {
    _onNotificationTap = onNotificationTap;
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: (details) {
        _onNotificationTap?.call(details.payload);
      },
    );

    const androidChannel = AndroidNotificationChannel(
      kNexusNotificationChannelId,
      'NEXUS Alerts',
      description: 'Low stock, sales, stock transfer, and sync failure alerts',
      importance: Importance.high,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);
    await androidPlugin?.requestNotificationsPermission();

    await _initializeFcmSafe();
    _initialized = true;
  }

  Future<void> _initializeFcmSafe() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title ?? 'NEXUS Alert';
        final body = message.notification?.body ?? '';
        final route = message.data['route'] as String?;
        showLocalNotification(title: title, body: body, payload: route);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final route = message.data['route'] as String?;
        _onNotificationTap?.call(route);
      });

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final route = initialMessage.data['route'] as String?;
        _onNotificationTap?.call(route);
      }
    } catch (e) {
      // Expected on local emulators or iOS simulator without APNs/google-services.
      debugPrint('FCM initialization skipped/unavailable: $e');
    }
  }

  /// Displays an immediate local notification (works offline & on emulators).
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      kNexusNotificationChannelId,
      'NEXUS Alerts',
      channelDescription:
          'Low stock, sales, stock transfer, and sync failure alerts',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
