/// Purpose: Keeps the Android process alive via a foreground service so system RAM cleaning and Doze do not end background monitoring.
/// Data & Logic Flow: Initializes the foreground-task plugin once, starts a silent persistent-notification service at app launch, restarts on boot (plugin boot receiver), and asks the user for a battery-optimization exemption when not yet granted.
/// Key Components: AndroidBackgroundService, _KeepAliveTaskHandler, _startKeepAliveCallback
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Foreground-service keep-alive for the Android build.
///
/// The service itself performs no polling: lecture-state alerting on Android
/// is FCM-driven and the Render poller is the single dispatcher. The service
/// exists to hold the process alive so the app stays warm, keeps its state,
/// and survives OEM RAM cleaners.
class AndroidBackgroundService {
  const AndroidBackgroundService._();

  static const String _channelId = 'simkuliah_monitor_keep_alive';
  static const String _channelName = 'Simkuliah Monitor Latar Belakang';
  static const String _channelDescription =
      'Menjaga aplikasi tetap berjalan di latar belakang untuk memantau '
      'presensi.';
  static const String _notificationTitle = 'Simkuliah Monitor aktif';
  static const String _notificationText =
      'Memantau jadwal dan presensi di latar belakang.';

  /// Initializes the plugin, starts the keep-alive foreground service, and
  /// prompts for a battery-optimization exemption when not yet granted.
  ///
  /// Safe to call on every app start: when the service is already running,
  /// [FlutterForegroundTask.startService] returns a failure result which is
  /// logged and ignored.
  static Future<void> start() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        allowWakeLock: false,
        allowAutoRestart: true,
      ),
    );

    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: _notificationTitle,
      notificationText: _notificationText,
      callback: _startKeepAliveCallback,
    );
    if (result is ServiceRequestFailure) {
      debugPrint('AndroidBackgroundService note: ${result.error}');
    }

    // The system dialog explains itself and is remembered by the OS, so
    // prompting on every cold start until granted is intentional.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }
}

/// Registers the keep-alive handler inside the service isolate. The plugin
/// calls this top-level function, so it must survive tree shaking.
@pragma('vm:entry-point')
Future<void> _startKeepAliveCallback() async {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

/// No-op task handler: the service only holds the process alive; alerting
/// stays FCM-driven and the Render poller remains the single dispatcher.
class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
