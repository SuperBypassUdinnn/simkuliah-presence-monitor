/// Purpose: Unit tests for PresenceService backend confirmation path.
/// Data & Logic Flow: Verifies submitPresence posts to /api/v1/presence/confirm,
/// surfaces backend domain errors as UserFacingException, and refuses fake local writes.
/// Key Components: PresenceServiceTest
import 'dart:convert';

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
}
