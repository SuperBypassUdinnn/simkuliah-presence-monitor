import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meeting_model.dart';
import '../models/schedule_model.dart';

/// Provides methods and streams for fetching today's meetings, the semester
/// schedule matrix, and submitting presence overrides.
///
/// The Supabase client is injectable through the constructor so the service
/// can be exercised offline with a mock client, mirroring the backend
/// `DatabaseRepository` client-injection pattern.
class PresenceService {
  PresenceService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _tableSchedules = 'schedules';
  static const String _tableMeetings = 'meetings';
  static const String _tableOverrides = 'overrides';

  /// Stream of today's meetings, updated in real time via Supabase Realtime.
  Stream<List<MeetingModel>> watchTodaysMeetings({required DateTime today}) {
    final start = DateTime(today.year, today.month, today.day);
    return _client
        .from(_tableMeetings)
        .stream(primaryKey: ['id'])
        .eq('meeting_date', start.toIso8601String())
        .map((rows) => rows.map(MeetingModel.fromJson).toList());
  }

  /// Fetch today's meetings as a one-off future.
  Future<List<MeetingModel>> fetchTodaysMeetings({required DateTime today}) async {
    final start = DateTime(today.year, today.month, today.day);
    final response = await _client
        .from(_tableMeetings)
        .select()
        .eq('meeting_date', start.toIso8601String())
        .order('meeting_number');
    return response.map(MeetingModel.fromJson).toList();
  }

  /// Fetch the full semester schedule matrix.
  Future<List<ScheduleModel>> fetchSemesterMatrix() async {
    final response = await _client
        .from(_tableSchedules)
        .select()
        .order('course_code');
    return response.map(ScheduleModel.fromJson).toList();
  }

  /// Submit a presence override (izin / sakit / alpa) for a meeting.
  Future<void> submitOverride({
    required int meetingId,
    required String overrideType,
    String note = '',
  }) async {
    await _client.from(_tableOverrides).upsert({
      'meeting_id': meetingId,
      'override_type': overrideType,
      'note': note,
      'is_active': true,
    });
  }

  /// Submit presence (open/closed) for a meeting.
  Future<void> submitPresence({
    required int meetingId,
    required bool isPresent,
  }) async {
    await _client
        .from(_tableMeetings)
        .update({'is_presence_open': isPresent})
        .eq('id', meetingId);
  }
}
