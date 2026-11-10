import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:simkuliah_client/models/meeting_model.dart';
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
}
