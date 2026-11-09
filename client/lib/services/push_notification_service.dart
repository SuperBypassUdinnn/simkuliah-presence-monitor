/// Purpose: FCM push lifecycle for the Android/iOS client.
/// Data & Logic Flow: Requests permissions, creates priority channels, registers the device token, renders foreground/background messages with signed action buttons, and posts webhook actions on tap.
/// Key Components: PushNotificationService, firebaseMessagingBackgroundHandler, handleNotificationActionTap, FcmActionEncoder
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/firebase_config.dart';
import 'device_service.dart';

/// Android notification channels, aligned with the backend priority policy:
/// high priority is reserved for lecturer-opened and urgent-closing states.
const AndroidNotificationChannel _urgentChannel = AndroidNotificationChannel(
  'presensi_urgent',
  'Presensi Urgent',
  description: 'Dosen buka presensi dan sisa waktu menipis',
  importance: Importance.max,
);

const AndroidNotificationChannel _generalChannel = AndroidNotificationChannel(
  'presensi_general',
  'Presensi',
  description: 'Informasi jadwal dan status presensi',
  importance: Importance.defaultImportance,
);

/// Fixed id for the ongoing urgent notification so it can be cancelled when
/// the presence window expires or the meeting state resolves.
const int _urgentNotificationId = 4201;

/// Opt-in full-screen delivery for urgent alerts (Android 14+ requires the
/// user to grant the special access).
const bool _fullScreenIntentEnabled = bool.fromEnvironment(
  'FCM_FULLSCREEN_INTENT',
  defaultValue: false,
);

/// Encodes and decodes the signed action buttons carried in FCM data.
class FcmActionEncoder {
  FcmActionEncoder._();

  /// Parse the `actions` JSON produced by the backend dispatcher.
  static List<({String label, String action, String token})> parse(
    String? actionsJson,
  ) {
    if (actionsJson == null || actionsJson.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(actionsJson) as List<dynamic>;
      return decoded
          .map(
            (entry) => (
              label: entry['label'] as String? ?? '',
              action: entry['action'] as String? ?? '',
              token: entry['token'] as String? ?? '',
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Build the Android action buttons for a notification.
  static List<AndroidNotificationAction> toAndroidActions(
    List<({String label, String action, String token})> actions,
  ) {
    return actions
        .where((entry) => entry.label.isNotEmpty && entry.token.isNotEmpty)
        .map(
          (entry) => AndroidNotificationAction(
            '${entry.action}|${entry.token}',
            entry.label,
          ),
        )
        .toList();
  }

  /// Split an action id (`action|token`) into its parts, or null.
  static ({String action, String token})? decodeActionId(String? actionId) {
    if (actionId == null || !actionId.contains('|')) {
      return null;
    }
    final separator = actionId.indexOf('|');
    final action = actionId.substring(0, separator);
    final token = actionId.substring(separator + 1);
    if (action.isEmpty || token.isEmpty) {
      return null;
    }
    return (action: action, token: token);
  }
}

/// Background isolate entry point. Hybrid payloads are displayed by the
/// system tray automatically while backgrounded; data-only payloads (no
/// notification block) are rendered here so action buttons keep working.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseConfig.initialize();
  await PushNotificationService.instance.handleBackgroundMessage(message);
}

/// Fires when a notification action button is tapped while the app is in the
/// background or terminated. Must be top-level and entry-point annotated.
@pragma('vm:entry-point')
Future<void> handleNotificationActionTap(NotificationResponse response) async {
  final decoded = FcmActionEncoder.decodeActionId(response.actionId);
  if (decoded == null) {
    return;
  }
  await DeviceService().submitActionToken(
    action: decoded.action,
    token: decoded.token,
  );
}

/// Sets up Firebase Cloud Messaging for the running platform.
///
/// Everything degrades to a safe no-op on desktop, web, tests, and builds
/// without Firebase configuration.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final DeviceService _deviceService = DeviceService();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || !FirebaseConfig.isSupportedPlatform) {
      return;
    }
    if (!FirebaseConfig.isConfigured || Firebase.apps.isEmpty) {
      debugPrint('Push notifications skipped: Firebase not configured');
      return;
    }

    await _initializePlugin();
    await _createChannels();
    await _requestPermissions();

    // Foreground messages are rendered manually below, so disable the
    // automatic presentation (which cannot use our priority channels).
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((_) {
      // Tapping a system-tray notification opens the app; refresh views via
      // the existing tab-focus mechanism.
    });

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _deviceService.registerDeviceToken(token, platform: _platformName);
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _deviceService.registerDeviceToken(token, platform: _platformName);
    });

    _initialized = true;
  }

  /// Render a background/terminated FCM message. With the hybrid payload the
  /// system tray already displayed it; data-only payloads are rendered here
  /// so the signed action buttons stay available.
  Future<void> handleBackgroundMessage(RemoteMessage message) async {
    if (message.notification != null) {
      return;
    }
    await _initializePlugin();
    await _showLocalNotification(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: message.data['title'] ?? 'Presensi',
      body: message.data['body'] ?? '',
      actionsJson: message.data['actions'],
      urgent: _isUrgentKind(message.data['action_kind']),
    );
  }

  String get _platformName => Platform.isIOS ? 'ios' : 'android';

  static bool _isUrgentKind(String? kind) =>
      kind == 'lecturer_opened' || kind == 'urgent_closing';

  Future<void> _initializePlugin() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) async {
        // Non-action taps open the app; action taps are handled by the
        // background entry point above so both paths behave identically.
        await handleNotificationActionTap(response);
      },
      onDidReceiveBackgroundNotificationResponse: handleNotificationActionTap,
    );
  }

  Future<void> _createChannels() async {
    if (!Platform.isAndroid) {
      return;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_urgentChannel);
    await android?.createNotificationChannel(_generalChannel);
  }

  Future<void> _requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.requestNotificationsPermission();
      }
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('FCM permission: ${settings.authorizationStatus}');
    } catch (error) {
      debugPrint('FCM permission request failed: $error');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final kind = message.data['action_kind'] ?? '';
    if (kind == 'window_expired') {
      // The presence window closed; drop any lingering urgent notification.
      _plugin.cancel(id: _urgentNotificationId);
    }
    final urgent = _isUrgentKind(kind);
    if (notification == null && !urgent) {
      // Data-only noise without a visible payload.
      return;
    }
    _showLocalNotification(
      id: urgent ? _urgentNotificationId : notification!.hashCode,
      title:
          notification?.title ??
          'Presensi ${message.data['course_code'] ?? ''}',
      body: notification?.body ?? '',
      actionsJson: message.data['actions'],
      urgent: urgent,
    );
  }

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    required String? actionsJson,
    required bool urgent,
  }) async {
    final channel = urgent ? _urgentChannel : _generalChannel;
    final actions = FcmActionEncoder.toAndroidActions(
      FcmActionEncoder.parse(actionsJson),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: urgent ? Importance.max : Importance.defaultImportance,
          priority: urgent ? Priority.max : Priority.defaultPriority,
          // Urgent alerts resist a casual swipe; they are cancelled when the
          // window expires or the presence state resolves.
          ongoing: urgent,
          autoCancel: !urgent,
          fullScreenIntent: urgent && _fullScreenIntentEnabled,
          actions: actions.isEmpty ? null : actions,
        ),
      ),
      payload: actionsJson,
    );
  }
}
