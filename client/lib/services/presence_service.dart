/// Purpose: Client-side service coordinating Supabase real-time presence data.
/// Data & Logic Flow: Streams active lecture meetings, executes presence confirmations and overrides.
/// Key Components: PresenceService
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meeting_model.dart';
import '../models/schedule_model.dart';

/// Provides methods and streams for fetching today's meetings, the semester
/// schedule matrix, and submitting presence overrides.
class PresenceService {
  PresenceService({SupabaseClient? client}) : _customClient = client;

  final SupabaseClient? _customClient;

  SupabaseClient get _client {
    if (_customClient != null) return _customClient;
    return Supabase.instance.client;
  }

  static const String _tableSchedules = 'schedules';
  static const String _tableMeetings = 'meetings';
  static const String _tableOverrides = 'local_overrides';

  /// Stream of today's meetings, updated in real time via Supabase Realtime.
  Stream<List<MeetingModel>> watchTodaysMeetings({required DateTime today}) {
    final dateStr =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return _client
        .from(_tableMeetings)
        .stream(primaryKey: ['id'])
        .eq('meeting_date', dateStr)
        .map((rows) => rows.map(MeetingModel.fromJson).toList());
  }

  /// Fetch today's meetings as a one-off future, sorted by start_time.
  Future<List<MeetingModel>> fetchTodaysMeetings({
    required DateTime today,
  }) async {
    final dateStr =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final response = await _client
        .from(_tableMeetings)
        .select('*, schedules(*), local_overrides(*)')
        .eq('meeting_date', dateStr);

    final meetings = response.map(MeetingModel.fromJson).toList();
    meetings.sort((a, b) {
      final cmp = a.startTime.compareTo(b.startTime);
      if (cmp != 0) return cmp;
      return a.meetingNumber.compareTo(b.meetingNumber);
    });
    return meetings;
  }

  /// Fetch the full semester schedule matrix with all nested meetings.
  Future<List<ScheduleModel>> fetchSemesterMatrix() async {
    final response = await _client
        .from(_tableSchedules)
        .select('*, meetings(*, local_overrides(*))')
        .order('course_code');
    return response.map(ScheduleModel.fromJson).toList();
  }

  /// Fetch the meetings of one schedule, ordered by meeting number.
  Future<List<MeetingModel>> fetchMeetingsForSchedule({
    required int scheduleId,
  }) async {
    final response = await _client
        .from(_tableMeetings)
        .select('*, schedules(*), local_overrides(*)')
        .eq('schedule_id', scheduleId)
        .order('meeting_number');
    return response.map(MeetingModel.fromJson).toList();
  }

  /// Submit a presence override (izin / sakit / alpa) for a meeting.
  Future<void> submitOverride({
    required int meetingId,
    required String overrideType,
    String note = '',
  }) async {
    await _client.from(_tableOverrides).upsert({
      'meeting_id': meetingId,
      'override_type': overrideType.toLowerCase(),
      'note': note,
    }, onConflict: 'meeting_id');
  }

  /// Delete/clear local override for a meeting.
  Future<void> clearOverride({required int meetingId}) async {
    await _client.from(_tableOverrides).delete().eq('meeting_id', meetingId);
  }

  /// Submit presence confirmation (hadir) for a meeting.
  ///
  /// Clears any local overrides so 'hadir' maintains absolute authority.
  Future<void> submitPresence({
    required int meetingId,
    required bool isPresent,
  }) async {
    await _client
        .from(_tableMeetings)
        .update({
          'simkuliah_status': isPresent ? 'hadir' : 'tidak_hadir',
          'student_confirmed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', meetingId);

    if (isPresent) {
      // Overwrite and clear any conflicting local override
      await _client.from(_tableOverrides).delete().eq('meeting_id', meetingId);
    }
  }
}
