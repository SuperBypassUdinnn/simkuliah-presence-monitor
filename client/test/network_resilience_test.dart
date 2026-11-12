/// Purpose: Deterministic unit and widget tests for network outage recovery, hung-request epoch isolation, and RealtimeAlertService stream reconnect backoff.
/// Data & Logic Flow: Simulates hung Completer futures, out-of-order completion, stream error+done double-events, and verifies recovery without hanging spinners.
/// Key Components: network_resilience_test
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/core/refresh_bus.dart';
import 'package:simkuliah_client/models/meeting_model.dart';
import 'package:simkuliah_client/models/schedule_model.dart';
import 'package:simkuliah_client/services/backend_health_service.dart';
import 'package:simkuliah_client/services/presence_service.dart';
import 'package:simkuliah_client/services/realtime_alert_service.dart';
import 'package:simkuliah_client/views/active_presence_view.dart';
import 'package:simkuliah_client/views/semester_matrix_view.dart';
import 'package:simkuliah_client/views/today_feed_view.dart';

MeetingModel _meeting({int id = 1, String course = 'KECERDASAN ARTIFISIAL'}) {
  return MeetingModel(
    id: id,
    courseName: course,
    meetingNumber: 13,
    simkuliahStatus: 'pending',
    isPresenceOpen: false,
  );
}

class _HungThenLivePresenceService extends PresenceService {
  _HungThenLivePresenceService(this.firstCompleter);

  final Completer<List<MeetingModel>> firstCompleter;
  int calls = 0;

  @override
  Future<List<MeetingModel>> fetchTodaysMeetings({
    required DateTime today,
  }) async {
    calls++;
    if (calls == 1) {
      return firstCompleter.future;
    }
    return [_meeting(course: 'KECERDASAN ARTIFISIAL')];
  }

  @override
  Future<List<ScheduleModel>> fetchSemesterMatrix() async {
    calls++;
    if (calls == 1) {
      await firstCompleter.future;
      return const [];
    }
    return [
      ScheduleModel(
        id: 4,
        courseCode: 'SINF3031',
        courseName: 'KECERDASAN ARTIFISIAL',
        classGroup: 'C',
        room: 'E.03.05',
        startTime: '09:50:00',
        endTime: '11:30:00',
        lecturerName: 'Zulfan, S.Si., M.Sc.',
        meetings: [_meeting(course: 'KECERDASAN ARTIFISIAL')],
      ),
    ];
  }
}

class _OkHealthService extends BackendHealthService {
  @override
  Future<BackendHealthResult> check() async =>
      const BackendHealthResult(status: BackendHealthStatus.ok, message: '');
}

void main() {
  testWidgets(
    'ActivePresenceView abandons hung request on RefreshBus and ignores stale late error',
    (tester) async {
      final hung = Completer<List<MeetingModel>>();
      final service = _HungThenLivePresenceService(hung);

      await tester.pumpWidget(
        MaterialApp(home: ActivePresenceView(presenceService: service)),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Network stabilizes and user triggers refresh while first call is still stuck.
      RefreshBus.instance.requestRefresh();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(service.calls, 2);

      // Even if the abandoned socket errors late, UI must stay healthy.
      hung.completeError(TimeoutException('stale timeout'));
      await tester.pumpAndSettle();
      expect(find.text('Gagal memuat status presensi'), findsNothing);
    },
  );

  testWidgets(
    'TodayFeedView abandons hung request on RefreshBus and shows fresh course',
    (tester) async {
      final hung = Completer<List<MeetingModel>>();
      final service = _HungThenLivePresenceService(hung);

      await tester.pumpWidget(
        MaterialApp(
          home: TodayFeedView(
            presenceService: service,
            backendHealthService: _OkHealthService(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      RefreshBus.instance.requestRefresh();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('KECERDASAN ARTIFISIAL'), findsOneWidget);

      hung.completeError(TimeoutException('stale timeout'));
      await tester.pumpAndSettle();
      expect(find.text('KECERDASAN ARTIFISIAL'), findsOneWidget);
    },
  );

  testWidgets(
    'SemesterMatrixView abandons hung request on RefreshBus and renders matrix',
    (tester) async {
      final hung = Completer<List<MeetingModel>>();
      final service = _HungThenLivePresenceService(hung);

      await tester.pumpWidget(
        MaterialApp(home: SemesterMatrixView(presenceService: service)),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      RefreshBus.instance.requestRefresh();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('KECERDASAN ARTIFISIAL'), findsOneWidget);
    },
  );

  test('RealtimeAlertService schedules single reconnect on error+done and resets backoff after frame', () async {
    final controllers = <StreamController<List<Map<String, dynamic>>>>[];
    var streamCreations = 0;

    final fakePresence = _HungThenLivePresenceService(
      Completer<List<MeetingModel>>()..complete([_meeting()]),
    )..calls = 1; // skip firstCompleter so fetchTodaysMeetings returns immediately

    final service = RealtimeAlertService(
      presenceService: fakePresence,
      baseReconnectDelay: const Duration(milliseconds: 30),
      streamFactory: (_) {
        streamCreations++;
        final ctrl = StreamController<List<Map<String, dynamic>>>();
        controllers.add(ctrl);
        return ctrl.stream;
      },
    );

    var refreshCount = 0;
    final sub = RefreshBus.instance.stream.listen((_) => refreshCount++);

    service.start(onAlert: (_) => 1);
    expect(streamCreations, 1);

    // Emit error AND close the stream immediately (the double-schedule trap).
    controllers[0].addError(Exception('WebSocket drop'));
    await controllers[0].close();

    // Single-timer guard: only 1 reconnect attempt scheduled despite error+done.
    expect(service.reconnectAttempts, 1);

    // Wait for reconnect timer to open stream #2.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(streamCreations, 2);

    // Delivering a snapshot on the reconnected stream resets backoff and
    // broadcasts a RefreshBus refresh so views recover.
    controllers[1].add([
      {'id': 57, 'meeting_number': 13},
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.reconnectAttempts, 0);
    expect(refreshCount, greaterThanOrEqualTo(1));

    await sub.cancel();
    await service.stop();
    for (final c in controllers) {
      if (!c.isClosed) {
        await c.close();
      }
    }
  });
}
