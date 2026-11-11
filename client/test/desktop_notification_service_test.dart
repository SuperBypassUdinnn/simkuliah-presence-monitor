/// Purpose: Unit tests for DesktopNotificationService and its D-Bus notification dispatch.
/// Data & Logic Flow: Verifies initialization, urgency mapping, sound attachment, notify-send fallback, and cancel delegation using an injected mock client.
/// Key Components: DesktopNotificationServiceTest, _FakeDesktopNotificationClient
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/services/desktop_notification_service.dart';

class _FakeDesktopNotificationClient implements DesktopNotificationClient {
  InitializationSettings? lastSettings;
  DidReceiveNotificationResponseCallback? onResponse;
  final List<
    ({
      int id,
      String? title,
      String? body,
      NotificationDetails? details,
      String? payload,
    })
  >
  showCalls = [];
  final List<int> cancelCalls = [];
  bool shouldThrowOnShow = false;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    lastSettings = settings;
    onResponse = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (shouldThrowOnShow) {
      throw Exception('D-Bus connection error');
    }
    showCalls.add((
      id: id,
      title: title,
      body: body,
      details: notificationDetails,
      payload: payload,
    ));
  }

  @override
  Future<void> cancel({required int id}) async {
    cancelCalls.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopNotificationService', () {
    late _FakeDesktopNotificationClient fakeClient;
    final executedCommands = <({String exe, List<String> args})>[];

    Future<ProcessResult> fakeRunCommand(String exe, List<String> args) async {
      executedCommands.add((exe: exe, args: args));
      return ProcessResult(1234, 0, '', '');
    }

    setUp(() {
      fakeClient = _FakeDesktopNotificationClient();
      executedCommands.clear();
    });

    test('safe no-op when platform is unsupported', () async {
      final service = DesktopNotificationService(
        client: fakeClient,
        isSupportedPlatform: false,
        runCommand: fakeRunCommand,
      );

      await service.initialize();
      expect(service.isInitialized, isFalse);
      expect(fakeClient.lastSettings, isNull);

      await service.showNotification(id: 1, title: 'Title', body: 'Body');
      expect(fakeClient.showCalls, isEmpty);
      expect(executedCommands, isEmpty);

      await service.cancel(1);
      expect(fakeClient.cancelCalls, isEmpty);
    });

    test(
      'initializes with Linux D-Bus settings and invokes tap callback',
      () async {
        var tapInvoked = false;
        final service = DesktopNotificationService(
          client: fakeClient,
          isSupportedPlatform: true,
          runCommand: fakeRunCommand,
        );

        await service.initialize(
          onNotificationTap: () {
            tapInvoked = true;
          },
        );

        expect(service.isInitialized, isTrue);
        expect(fakeClient.lastSettings?.linux, isNotNull);
        expect(
          fakeClient.lastSettings?.linux?.defaultActionName,
          'Buka Simkuliah Monitor',
        );

        // Simulate notification click response.
        fakeClient.onResponse?.call(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
          ),
        );
        expect(tapInvoked, isTrue);
      },
    );

    test(
      'showNotification formats normal urgency details without sound',
      () async {
        final service = DesktopNotificationService(
          client: fakeClient,
          isSupportedPlatform: true,
          runCommand: fakeRunCommand,
        );

        await service.showNotification(
          id: 42,
          title: 'Kelas Dimulai',
          body: 'Kewirausahaan telah dimulai',
          urgent: false,
        );

        expect(fakeClient.showCalls, hasLength(1));
        final call = fakeClient.showCalls.single;
        expect(call.id, 42);
        expect(call.title, 'Kelas Dimulai');
        expect(call.body, 'Kewirausahaan telah dimulai');
        expect(call.details?.linux?.urgency, LinuxNotificationUrgency.normal);
        expect(call.details?.linux?.sound, isNull);
        expect(
          call.details?.linux?.timeout,
          const LinuxNotificationTimeout.systemDefault(),
        );
        expect(executedCommands, isEmpty);
      },
    );

    test('showNotification formats critical urgency, expiresNever, and sound for urgent alerts', () async {
      final service = DesktopNotificationService(
        client: fakeClient,
        isSupportedPlatform: true,
        runCommand: fakeRunCommand,
      );

      await service.showNotification(
        id: 99,
        title: 'Dosen Membuka Presensi',
        body: 'Presensi SINF6047 telah dibuka',
        urgent: true,
      );

      expect(fakeClient.showCalls, hasLength(1));
      final call = fakeClient.showCalls.single;
      expect(call.id, 99);
      expect(call.details?.linux?.urgency, LinuxNotificationUrgency.critical);
      expect(
        call.details?.linux?.timeout,
        const LinuxNotificationTimeout.expiresNever(),
      );
      expect(call.details?.linux?.sound?.content, 'message-new-instant');
    });

    test(
      'falls back to notify-send on Linux when plugin show throws',
      () async {
        fakeClient.shouldThrowOnShow = true;
        final service = DesktopNotificationService(
          client: fakeClient,
          isSupportedPlatform: true,
          runCommand: fakeRunCommand,
        );

        await service.showNotification(
          id: 10,
          title: 'Presensi Segera Ditutup',
          body: 'Sisa waktu 5 menit',
          urgent: true,
        );

        expect(executedCommands, hasLength(1));
        final cmd = executedCommands.single;
        expect(cmd.exe, contains('notify-send'));
        expect(cmd.args, contains('-a'));
        expect(cmd.args, contains('Simkuliah Monitor'));
        expect(cmd.args, contains('-u'));
        expect(cmd.args, contains('critical'));
        expect(cmd.args, contains('Presensi Segera Ditutup'));
        expect(cmd.args, contains('Sisa waktu 5 menit'));
      },
    );

    test('cancel delegates to client plugin', () async {
      final service = DesktopNotificationService(
        client: fakeClient,
        isSupportedPlatform: true,
        runCommand: fakeRunCommand,
      );

      await service.cancel(777);
      expect(fakeClient.cancelCalls, [777]);
    });

    test('notificationId generates deterministic id', () {
      expect(DesktopNotificationService.notificationId(5, 2), 52);
    });
  });
}
