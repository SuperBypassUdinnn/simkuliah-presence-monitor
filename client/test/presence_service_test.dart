/// Purpose: Unit tests for PresenceService backend confirmation path.
/// Data & Logic Flow: Verifies submitPresence posts to /api/v1/presence/confirm,
/// surfaces backend domain errors as UserFacingException, and refuses fake local writes.
/// Key Components: PresenceServiceTest
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simkuliah_client/core/error_message.dart';
import 'package:simkuliah_client/services/presence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final dummySupabase = SupabaseClient('https://example.supabase.co', 'anon');

  test(
    'submitPresence posts to /api/v1/presence/confirm on isPresent=true',
    () async {
      Uri? seenUri;
      Map<String, dynamic>? seenBody;

      final service = PresenceService(
        client: dummySupabase,
        apiBaseUrl: 'https://backend.example',
        httpClient: MockClient((request) async {
          seenUri = request.url;
          seenBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }),
      );

      await service.submitPresence(meetingId: 57, isPresent: true);

      expect(
        seenUri.toString(),
        'https://backend.example/api/v1/presence/confirm',
      );
      expect(seenBody, {'meeting_id': 57});
    },
  );

  test(
    'submitPresence throws UserFacingException with backend detail on 409',
    () async {
      final service = PresenceService(
        client: dummySupabase,
        apiBaseUrl: 'https://backend.example',
        httpClient: MockClient((request) async {
          return http.Response(
            '{"detail":"Dosen belum membuka presensi atau batas waktu presensi sudah tutup di Simkuliah."}',
            409,
          );
        }),
      );

      await expectLater(
        service.submitPresence(meetingId: 57, isPresent: true),
        throwsA(
          isA<UserFacingException>().having(
            (e) => friendlyErrorMessage(e),
            'friendlyErrorMessage',
            'Dosen belum membuka presensi atau batas waktu presensi sudah tutup di Simkuliah.',
          ),
        ),
      );
    },
  );

  test(
    'submitPresence fails clearly when backend URL is not configured',
    () async {
      final service = PresenceService(client: dummySupabase, apiBaseUrl: '');

      await expectLater(
        service.submitPresence(meetingId: 57, isPresent: true),
        throwsA(isA<UserFacingException>()),
      );
    },
  );

  test('fetchTodaysMeetings retries once after timeout and recovers on second attempt', () async {
    HttpOverrides.global = null;
    var hits = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    server.listen((req) async {
      hits++;
      if (hits == 1) {
        // Stall attempt 1 past requestTimeout to simulate a dead socket.
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          await req.response.close();
        } catch (_) {}
        return;
      }
      final body = jsonEncode([
        {
          'id': 57,
          'meeting_number': 13,
          'simkuliah_status': 'pending',
          'schedules': {'course_name': 'KECERDASAN ARTIFISIAL'},
        },
      ]);
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write(body);
      await req.response.close();
    });

    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'dummy-anon',
    );
    final service = PresenceService(
      client: client,
      requestTimeout: const Duration(milliseconds: 250),
    );

    final meetings = await service.fetchTodaysMeetings(
      today: DateTime(2026, 11, 12),
    );
    expect(hits, 2);
    expect(meetings, hasLength(1));
    expect(meetings.single.courseName, 'KECERDASAN ARTIFISIAL');
  });

  test('fetchTodaysMeetings throws TimeoutException promptly when all retries hang', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    server.listen((req) async {
      await Future<void>.delayed(const Duration(seconds: 5));
      try {
        await req.response.close();
      } catch (_) {}
    });

    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'dummy-anon',
    );
    final service = PresenceService(
      client: client,
      requestTimeout: const Duration(milliseconds: 200),
    );

    await expectLater(
      service.fetchTodaysMeetings(today: DateTime(2026, 11, 12)),
      throwsA(isA<TimeoutException>()),
    );
  });
}
