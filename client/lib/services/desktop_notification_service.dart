/// Purpose: Native desktop notification service targeting Linux (KDE Plasma / D-Bus).
/// Data & Logic Flow: Initializes the local notification plugin with Linux D-Bus desktop settings, dispatches urgent and normal notifications with appropriate urgency, expiration, sound, and application icons, and restores/focuses the window on notification tap. Includes a graceful notify-send fallback for Linux.
/// Key Components: DesktopNotificationService, DesktopNotificationClient
import 'dart:async';
import 'dart:io' show File, Platform, Process, ProcessResult;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Pluggable client adapter so [DesktopNotificationService] can be thoroughly
/// unit tested without requiring a live D-Bus session bus.
abstract class DesktopNotificationClient {
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  });

  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  });

  Future<void> cancel({required int id});
}

class _DefaultDesktopNotificationClient implements DesktopNotificationClient {
  _DefaultDesktopNotificationClient(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) {
    return _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) {
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }

  @override
  Future<void> cancel({required int id}) {
    return _plugin.cancel(id: id);
  }
}

/// Dispatches native desktop notifications to the Linux system notification
/// daemon (KDE Plasma / freedesktop notifications via D-Bus).
class DesktopNotificationService {
  DesktopNotificationService._internal()
    : _client = _DefaultDesktopNotificationClient(
        FlutterLocalNotificationsPlugin(),
      ),
      _runCommand = Process.run,
      _isSupportedPlatformOverride = null;

  @visibleForTesting
  DesktopNotificationService({
    DesktopNotificationClient? client,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runCommand,
    bool? isSupportedPlatform,
  }) : _client =
           client ??
           _DefaultDesktopNotificationClient(FlutterLocalNotificationsPlugin()),
       _runCommand = runCommand ?? Process.run,
       _isSupportedPlatformOverride = isSupportedPlatform;

  static const String _iconRelativePath = 'assets/icons/tray_icon.png';
  static const String _notifySendPath = '/usr/bin/notify-send';

  static final DesktopNotificationService instance =
      DesktopNotificationService._internal();

  final DesktopNotificationClient _client;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )
  _runCommand;
  final bool? _isSupportedPlatformOverride;

  bool _initialized = false;
  FutureOr<void> Function()? _onNotificationTap;

  bool get isSupportedPlatform =>
      _isSupportedPlatformOverride ?? (!kIsWeb && Platform.isLinux);

  bool get isInitialized => _initialized;

  /// Deterministic notification ID mapped from meeting and kind index.
  static int notificationId(int meetingId, int kindIndex) =>
      meetingId * 10 + kindIndex;

  /// Initialize the notification client for the running desktop host.
  Future<void> initialize({
    FutureOr<void> Function()? onNotificationTap,
  }) async {
    if (_initialized || !isSupportedPlatform) {
      return;
    }
    _onNotificationTap = onNotificationTap;
    try {
      final linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Buka Simkuliah Monitor',
        defaultIcon: _linuxIcon(),
      );
      final initSettings = InitializationSettings(linux: linuxSettings);
      await _client.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) async {
          await _onNotificationTap?.call();
        },
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Desktop notification initialize note: $e');
    }
  }

  /// Display a native desktop notification.
  ///
  /// Urgent notifications use critical urgency (persisting in the system
  /// notification shade until interacted with) and play an alert sound;
  /// normal notifications use standard urgency and system-default expiration.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    bool urgent = false,
    String? payload,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    if (!_initialized) {
      await initialize(onNotificationTap: _onNotificationTap);
    }

    final linuxDetails = LinuxNotificationDetails(
      urgency: urgent
          ? LinuxNotificationUrgency.critical
          : LinuxNotificationUrgency.normal,
      timeout: urgent
          ? const LinuxNotificationTimeout.expiresNever()
          : const LinuxNotificationTimeout.systemDefault(),
      icon: _linuxIcon(),
      sound: urgent ? ThemeLinuxSound('message-new-instant') : null,
    );

    final details = NotificationDetails(linux: linuxDetails);

    try {
      await _client.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint(
        'Desktop notification plugin show failed ($e), attempting notify-send fallback',
      );
      await _fallbackNotifySend(title: title, body: body, urgent: urgent);
    }
  }

  /// Cancel an active notification by id.
  Future<void> cancel(int id) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      await _client.cancel(id: id);
    } catch (e) {
      debugPrint('Desktop notification cancel note: $e');
    }
  }

  /// Graceful notify-send fallback on Linux environments if plugin dispatch
  /// encounters issues.
  Future<void> _fallbackNotifySend({
    required String title,
    required String body,
    required bool urgent,
  }) async {
    try {
      final exe = File(_notifySendPath).existsSync()
          ? _notifySendPath
          : 'notify-send';
      final args = <String>[
        '-a',
        'Simkuliah Monitor',
        '-u',
        urgent ? 'critical' : 'normal',
        title,
        body,
      ];
      final iconPath = _absoluteIconPath();
      if (iconPath != null) {
        args.insertAll(2, ['-i', iconPath]);
      }
      await _runCommand(exe, args);
    } catch (e) {
      debugPrint('notify-send fallback failed: $e');
    }
  }

  LinuxNotificationIcon? _linuxIcon() {
    return AssetsLinuxIcon(_iconRelativePath);
  }

  String? _absoluteIconPath() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundled = '$exeDir/data/flutter_assets/$_iconRelativePath';
      if (File(bundled).existsSync()) {
        return bundled;
      }
      if (File(_iconRelativePath).existsSync()) {
        return File(_iconRelativePath).absolute.path;
      }
    } catch (_) {
      // Fall through to un-iconed notification.
    }
    return null;
  }
}
