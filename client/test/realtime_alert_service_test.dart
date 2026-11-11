import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/core/app_notification.dart';
import 'package:simkuliah_client/models/meeting_model.dart';
import 'package:simkuliah_client/services/realtime_alert_service.dart';

MeetingModel _meeting({
  required int id,
  DateTime? deadline,
  String status = 'pending',
  Map<String, dynamic>? override,
  String startTime = '08:00',
  String endTime = '10:00',
}) {
  return MeetingModel(
    id: id,
    courseName: 'Kewirausahaan',
    courseCode: 'EKU401',
    room: 'R-301',
    startTime: startTime,
    endTime: endTime,
    meetingNumber: 3,
    simkuliahStatus: status,
    isPresenceOpen: deadline != null && status == 'pending',
    deadlineAt: deadline,
    localOverride: override,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = DateTime(2026, 11, 9, 8, 30);

  group('RealtimeAlertEvaluator', () {
    test('lecturer-opened presence produces one urgent alert', () {
      final deadline = base.add(const Duration(minutes: 45));
      final result = RealtimeAlertEvaluator.evaluate(
        meetings: [_meeting(id: 1, deadline: deadline)],
        shownKeys: {},
        now: base,
      );

      expect(result.alerts, hasLength(1));
      final alert = result.alerts.single;
      expect(alert.kind, PresenceAlertKind.lecturerOpened);
      expect(alert.urgent, isTrue);
      expect(alert.meetingId, 1);
      expect(alert.courseName, 'Kewirausahaan');
      expect(result.resolvedMeetingIds, isEmpty);
    });

    test('deadline within ten minutes escalates to urgent closing', () {
      final deadline = base.add(const Duration(minutes: 5));
      final result = RealtimeAlertEvaluator.evaluate(
        meetings: [_meeting(id: 1, deadline: deadline)],
        shownKeys: {},
        now: base,
      );

      expect(result.alerts.single.kind, PresenceAlertKind.urgentClosing);
      expect(result.alerts.single.urgent, isTrue);
      expect(result.alerts.single.message, contains('tutup dalam 5 menit'));
    });

    test('exactly at the urgent boundary counts as urgent closing', () {
      final deadline = base.add(RealtimeAlertEvaluator.urgentWindow);
      final result = RealtimeAlertEvaluator.evaluate(
        meetings: [_meeting(id: 1, deadline: deadline)],
        shownKeys: {},
        now: base,
      );

      expect(result.alerts.single.kind, PresenceAlertKind.urgentClosing);
    });

    test('attended and overridden meetings are resolved, never alerted', () {
      final deadline = base.add(const Duration(minutes: 30));
      final result = RealtimeAlertEvaluator.evaluate(
        meetings: [
          _meeting(id: 1, deadline: deadline, status: 'hadir'),
          _meeting(
            id: 2,
            deadline: deadline,
            override: {'override_type': 'izin'},
          ),
        ],
        shownKeys: {},
        now: base,
      );

      expect(result.alerts, isEmpty);
      expect(result.resolvedMeetingIds, {1, 2});
    });

    test('expired window resolves the meeting and toasts once', () {
      final deadline = base.subtract(const Duration(minutes: 1));
      final first = RealtimeAlertEvaluator.evaluate(
        meetings: [_meeting(id: 1, deadline: deadline)],
        shownKeys: {},
        now: base,
      );

      expect(first.resolvedMeetingIds, {1});
      expect(first.alerts.single.kind, PresenceAlertKind.windowExpired);
      expect(first.alerts.single.urgent, isFalse);

      final second = RealtimeAlertEvaluator.evaluate(
        meetings: [_meeting(id: 1, deadline: deadline)],
        shownKeys: first.shownKeys,
        now: base,
      );
      expect(second.alerts, isEmpty);
    });

    test('class without an open window toasts class-started once', () {
      final result = RealtimeAlertEvaluator.evaluate(
        meetings: [_meeting(id: 1)],
        shownKeys: {},
        now: base,
      );

      expect(result.alerts.single.kind, PresenceAlertKind.classStarted);
      expect(result.alerts.single.urgent, isFalse);
    });

    test('alerts never repeat across passes (dedupe by key)', () {
      final deadline = base.add(const Duration(minutes: 45));
      final meetings = [_meeting(id: 1, deadline: deadline)];

      final first = RealtimeAlertEvaluator.evaluate(
        meetings: meetings,
        shownKeys: {},
        now: base,
      );
      expect(first.alerts, hasLength(1));

      final second = RealtimeAlertEvaluator.evaluate(
        meetings: meetings,
        shownKeys: first.shownKeys,
        now: base.add(const Duration(minutes: 1)),
      );
      expect(second.alerts, isEmpty);
    });

    test('lecturer-opened key is superseded when urgent phase begins', () {
      final deadline = base.add(const Duration(minutes: 45));
      final meetings = [_meeting(id: 1, deadline: deadline)];

      final first = RealtimeAlertEvaluator.evaluate(
        meetings: meetings,
        shownKeys: {},
        now: base,
      );
      expect(first.alerts.single.kind, PresenceAlertKind.lecturerOpened);

      final second = RealtimeAlertEvaluator.evaluate(
        meetings: meetings,
        shownKeys: first.shownKeys,
        now: base.add(const Duration(minutes: 36)),
      );

      expect(second.alerts.single.kind, PresenceAlertKind.urgentClosing);
      // The superseded lecturer key is consumed so it can never re-fire.
      expect(second.shownKeys.contains('1:lecturerOpened'), isTrue);
    });

    test(
      'windows that expired before the startup instant are never toasted',
      () {
        final startedAt = base;
        final deadline = base.subtract(const Duration(hours: 2));
        final result = RealtimeAlertEvaluator.evaluate(
          meetings: [_meeting(id: 1, deadline: deadline)],
          shownKeys: {},
          now: base.add(const Duration(minutes: 5)),
          suppressExpiredBefore: startedAt,
        );

        expect(result.alerts, isEmpty);
        expect(result.resolvedMeetingIds, {1});
        // The key is consumed so a later pass can never emit it either.
        expect(result.shownKeys.contains('1:windowExpired'), isTrue);
      },
    );

    test('a window that expires while running still toasts', () {
      final startedAt = base;
      final deadline = base.add(const Duration(minutes: 1));
      final result = RealtimeAlertEvaluator.evaluate(
        meetings: [_meeting(id: 1, deadline: deadline)],
        shownKeys: {},
        now: base.add(const Duration(minutes: 2)),
        suppressExpiredBefore: startedAt,
      );

      expect(result.alerts.single.kind, PresenceAlertKind.windowExpired);
    });
  });

  group('RealtimeAlertService', () {
    late RealtimeAlertService service;
    var currentMeetings = <MeetingModel>[];
    var now = base;
    DateTime clock() => now;

    setUp(() {
      AppNotification.reset();
      service = RealtimeAlertService();
      currentMeetings = [];
      now = base;
    });

    Future<void> pumpHarness(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => service.processMeetings(
                  meetings: currentMeetings,
                  onAlert: (alert) => AppNotification.show(
                    context,
                    title: alert.title,
                    message: alert.message,
                    color: alert.urgent ? Colors.red : Colors.blue,
                    duration: alert.urgent
                        ? Duration.zero
                        : const Duration(seconds: 4),
                  ),
                  clock: clock,
                ),
                child: const Text('tick'),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> tick(WidgetTester tester) async {
      await tester.tap(find.text('tick'));
      await tester.pumpAndSettle();
    }

    testWidgets('sticky banner persists without auto-dismiss', (tester) async {
      await pumpHarness(tester);
      currentMeetings = [
        _meeting(id: 7, deadline: base.add(const Duration(minutes: 45))),
      ];
      await tick(tester);

      expect(find.text('Dosen Membuka Presensi'), findsOneWidget);

      // Sticky: no auto-dismiss timer runs for urgent banners.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Dosen Membuka Presensi'), findsOneWidget);

      // Close button only.
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('Dosen Membuka Presensi'), findsNothing);
    });

    testWidgets('resolving the meeting dismisses its sticky banner', (
      tester,
    ) async {
      await pumpHarness(tester);
      currentMeetings = [
        _meeting(id: 7, deadline: base.add(const Duration(minutes: 45))),
      ];
      await tick(tester);
      expect(find.text('Dosen Membuka Presensi'), findsOneWidget);

      currentMeetings = [
        _meeting(
          id: 7,
          deadline: base.add(const Duration(minutes: 45)),
          status: 'hadir',
        ),
      ];
      await tick(tester);

      expect(find.text('Dosen Membuka Presensi'), findsNothing);
    });

    testWidgets('urgent closing replaces the lecturer-opened banner', (
      tester,
    ) async {
      await pumpHarness(tester);
      currentMeetings = [
        _meeting(id: 9, deadline: base.add(const Duration(minutes: 45))),
      ];
      await tick(tester);
      expect(find.text('Dosen Membuka Presensi'), findsOneWidget);

      // Time advances into the urgent phase for the same meeting.
      now = base.add(const Duration(minutes: 40));
      currentMeetings = [
        _meeting(id: 9, deadline: base.add(const Duration(minutes: 45))),
      ];
      await tick(tester);

      expect(find.text('Dosen Membuka Presensi'), findsNothing);
      expect(find.text('Presensi Segera Ditutup'), findsOneWidget);
    });

    testWidgets('normal alerts auto-dismiss after their duration', (
      tester,
    ) async {
      await pumpHarness(tester);
      // A class started (no deadline yet): a normal, non-sticky toast whose
      // window is still open relative to the startup baseline.
      currentMeetings = [_meeting(id: 11)];
      // Manual pumps: pumpAndSettle would fast-forward through the toast's
      // own countdown animation and trigger the auto-dismiss early.
      await tester.tap(find.text('tick'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Kelas Dimulai'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Kelas Dimulai'), findsNothing);
    });

    testWidgets('windows expired before the service started stay silent', (
      tester,
    ) async {
      await pumpHarness(tester);
      // The service started when the harness was pumped (now == base); the
      // meeting's window ended two hours earlier.
      currentMeetings = [
        _meeting(id: 12, deadline: base.subtract(const Duration(hours: 2))),
      ];
      await tick(tester);

      expect(find.text('Presensi Ditutup'), findsNothing);
    });

    test('processMeetings invokes onDismissAlert when meeting resolves', () {
      final dismissed = <({int meetingId, PresenceAlertKind kind})>[];
      service.processMeetings(
        meetings: [
          _meeting(id: 7, deadline: base.add(const Duration(minutes: 45))),
        ],
        onAlert: (_) => 1,
        onDismissAlert: (id, kind) =>
            dismissed.add((meetingId: id, kind: kind)),
        clock: clock,
      );

      service.processMeetings(
        meetings: [
          _meeting(
            id: 7,
            deadline: base.add(const Duration(minutes: 45)),
            status: 'hadir',
          ),
        ],
        onAlert: (_) => 2,
        onDismissAlert: (id, kind) =>
            dismissed.add((meetingId: id, kind: kind)),
        clock: clock,
      );

      expect(dismissed.any((d) => d.meetingId == 7), isTrue);
    });
  });
}
