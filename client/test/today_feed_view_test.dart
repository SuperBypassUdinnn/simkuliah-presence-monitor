import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:simkuliah_client/models/meeting_model.dart';
import 'package:simkuliah_client/models/schedule_customization_model.dart';
import 'package:simkuliah_client/models/schedule_model.dart';
import 'package:simkuliah_client/services/backend_health_service.dart';
import 'package:simkuliah_client/services/presence_service.dart';
import 'package:simkuliah_client/views/today_feed_view.dart';

MeetingModel _meeting(int id, String course) {
  return MeetingModel(
    id: id,
    courseName: course,
    meetingNumber: id,
    simkuliahStatus: 'hadir',
    isPresenceOpen: false,
  );
}

class _FakePresenceService extends PresenceService {
  @override
  Future<List<MeetingModel>> fetchTodaysMeetings({
    required DateTime today,
  }) async {
    return [_meeting(1, 'KECERDASAN ARTIFISIAL')];
  }
}

/// The Jadwal tab hosts two lists in a lazily-built ListView; a tall test
/// viewport keeps below-the-fold children built for finder assertions.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

class _FailingPresenceService extends PresenceService {
  @override
  Future<List<MeetingModel>> fetchTodaysMeetings({
    required DateTime today,
  }) async {
    throw http.ClientException(
      'SocketException: Connection failed (OS Error: Network is unreachable,'
      ' errno = 101), address = example.supabase.co, port = 443',
    );
  }
}

class _FakeHealthService extends BackendHealthService {
  _FakeHealthService(this.result);

  final BackendHealthResult result;

  @override
  Future<BackendHealthResult> check() async => result;
}

void main() {
  testWidgets('gateway banner appears when Simkuliah sync is degraded', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayFeedView(
            presenceService: _FakePresenceService(),
            backendHealthService: _FakeHealthService(
              const BackendHealthResult(
                status: BackendHealthStatus.simkuliahDegraded,
                message:
                    'Sinkronisasi ke Simkuliah tertunda - status presensi mungkin '
                    'tidak terbaru. Data terakhir tetap ditampilkan.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Sinkronisasi ke Simkuliah tertunda'),
      findsOneWidget,
    );
    // The feed itself still renders its meetings below the banner.
    expect(find.text('KECERDASAN ARTIFISIAL'), findsOneWidget);
  });

  testWidgets('no banner when the backend and Simkuliah are healthy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayFeedView(
            presenceService: _FakePresenceService(),
            backendHealthService: _FakeHealthService(
              const BackendHealthResult(
                status: BackendHealthStatus.ok,
                message: '',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KECERDASAN ARTIFISIAL'), findsOneWidget);
    expect(
      find.textContaining('Sinkronisasi ke Simkuliah tertunda'),
      findsNothing,
    );
    expect(
      find.textContaining('Server pemantau tidak dapat dihubungi'),
      findsNothing,
    );
  });

  testWidgets('load failure shows the clean message, not the raw error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayFeedView(
            presenceService: _FailingPresenceService(),
            backendHealthService: _FakeHealthService(
              const BackendHealthResult(
                status: BackendHealthStatus.ok,
                message: '',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gagal memuat jadwal'), findsOneWidget);
    expect(
      find.text(
        'Tidak ada koneksi internet. Periksa jaringan Anda, lalu coba lagi.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('errno = 101'), findsNothing);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });

  testWidgets('syncedNow triggers a refresh without re-probing health', (
    tester,
  ) async {
    var fetchCount = 0;
    final countingPresence = _CountingPresenceService(() => ++fetchCount);
    final health = _CountingHealthService(
      const BackendHealthResult(
        status: BackendHealthStatus.ok,
        message: '',
        syncedNow: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayFeedView(
            presenceService: countingPresence,
            backendHealthService: health,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initial load (1) + post-sync refresh (2), while health check ran once.
    expect(fetchCount, 2);
    expect(health.checkCount, 1);
  });

  testWidgets('Masuk segment shows the weekly class timetable', (tester) async {
    _useTallViewport(tester);
    final today = DateTime.now();
    final todayDate =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    const dayNames = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];
    final expectedToday = dayNames[today.weekday - 1];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayFeedView(
            presenceService: _FakeWeeklyPresenceService(todayDate: todayDate),
            backendHealthService: _FakeHealthService(
              const BackendHealthResult(
                status: BackendHealthStatus.ok,
                message: '',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default lens is the presence feed.
    expect(find.text('KECERDASAN ARTIFISIAL'), findsOneWidget);
    expect(find.text('Hari ini'), findsNothing);

    // Switch to the weekly class-entry timetable.
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    // One section per class day, derived from meeting dates.
    expect(find.text('Senin'), findsOneWidget);
    expect(find.text(expectedToday), findsOneWidget);
    expect(find.text('Matematika Diskrit'), findsOneWidget);
    expect(find.text('Basis Data'), findsOneWidget);
    // Today's section carries the badge.
    expect(find.text('Hari ini'), findsOneWidget);
    // The effective window honors the +15m course offset.
    expect(find.textContaining('08:15 - 09:55 WIB'), findsOneWidget);
    expect(find.textContaining('(Portal: 08:00 - 09:40)'), findsOneWidget);

    // Switching back restores the presence feed.
    await tester.tap(find.text('Absen'));
    await tester.pumpAndSettle();
    expect(find.text('KECERDASAN ARTIFISIAL'), findsOneWidget);
    expect(find.text('Matematika Diskrit'), findsNothing);
  });
}

/// Fake service serving both the presence feed and the semester schedules
/// used by the weekly class timetable.
class _FakeWeeklyPresenceService extends PresenceService {
  _FakeWeeklyPresenceService({required this.todayDate});

  final String todayDate;

  @override
  Future<List<MeetingModel>> fetchTodaysMeetings({
    required DateTime today,
  }) async {
    return [_meeting(1, 'KECERDASAN ARTIFISIAL')];
  }

  @override
  Future<List<ScheduleModel>> fetchSemesterMatrix() async {
    return [
      ScheduleModel(
        id: 1,
        courseCode: 'SIF2001',
        courseName: 'Matematika Diskrit',
        classGroup: 'B',
        room: 'D.1.02',
        startTime: '08:00:00',
        endTime: '09:40:00',
        lecturerName: 'Dr. M',
        meetings: [
          MeetingModel(
            id: 101,
            courseName: 'Matematika Diskrit',
            meetingNumber: 1,
            meetingDate: todayDate,
            simkuliahStatus: 'pending',
            isPresenceOpen: false,
            customization: const ScheduleCustomizationModel(
              scheduleId: 1,
              timeOffsetMinutes: 15,
            ),
          ),
        ],
      ),
      ScheduleModel(
        id: 2,
        courseCode: 'SIF2002',
        courseName: 'Basis Data',
        classGroup: 'A',
        room: 'D.2.01',
        startTime: '10:00:00',
        endTime: '11:40:00',
        lecturerName: 'Dr. N',
        meetings: [
          MeetingModel(
            id: 201,
            courseName: 'Basis Data',
            meetingNumber: 1,
            meetingDate: '2026-01-05',
            simkuliahStatus: 'pending',
            isPresenceOpen: false,
          ),
        ],
      ),
    ];
  }
}

class _CountingPresenceService extends PresenceService {
  _CountingPresenceService(this.onFetch);

  final void Function() onFetch;

  @override
  Future<List<MeetingModel>> fetchTodaysMeetings({
    required DateTime today,
  }) async {
    onFetch();
    return [_meeting(1, 'KECERDASAN ARTIFISIAL')];
  }
}

class _CountingHealthService extends BackendHealthService {
  _CountingHealthService(this.result);

  final BackendHealthResult result;
  int checkCount = 0;

  @override
  Future<BackendHealthResult> check() async {
    checkCount++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return result;
  }
}
