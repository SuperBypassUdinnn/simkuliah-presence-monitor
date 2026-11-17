/// Purpose: Client-side service coordinating Supabase real-time presence data.
/// Data & Logic Flow: Streams active lecture meetings, executes presence confirmations and overrides.
/// Key Components: PresenceService
import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_message.dart';
import '../models/meeting_model.dart';
import '../models/schedule_customization_model.dart';
import '../models/schedule_model.dart';
import '../models/user_preferences_model.dart';

/// Provides methods and streams for fetching today's meetings, the semester
/// schedule matrix, and submitting presence overrides.
class PresenceService {
  PresenceService({
    SupabaseClient? client,
    http.Client? httpClient,
    String? apiBaseUrl,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _customClient = client,
       _customHttpClient = httpClient,
       _customApiBaseUrl = apiBaseUrl;

  final SupabaseClient? _customClient;
  final http.Client? _customHttpClient;
  final String? _customApiBaseUrl;
  final Duration requestTimeout;

  static const String _envApiBaseUrl = String.fromEnvironment(
    'SIMKULIAH_API_BASE_URL',
  );

  String get _apiBaseUrl => _customApiBaseUrl ?? _envApiBaseUrl;

  SupabaseClient get _client {
    if (_customClient != null) return _customClient;
    return Supabase.instance.client;
  }

  static const String _tableSchedules = 'schedules';
  static const String _tableMeetings = 'meetings';
  static const String _tableOverrides = 'local_overrides';
  static const String _tableScheduleCustomizations = 'schedule_customizations';
  static const String _tableUserPreferences = 'user_preferences';

  static const Duration _retryDelay = Duration(milliseconds: 300);

  /// Run [action] with a hard request deadline and optional single fast retry
  /// on transient network faults (half-open sockets after a long outage,
  /// brief timeouts, or connection resets).
  Future<T> _runWithResilience<T>(
    Future<T> Function() action, {
    bool retry = true,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await action().timeout(requestTimeout);
      } on TimeoutException {
        if (!retry || attempt >= 2) rethrow;
      } on SocketException {
        if (!retry || attempt >= 2) rethrow;
      } on http.ClientException {
        if (!retry || attempt >= 2) rethrow;
      }
      await Future<void>.delayed(_retryDelay);
    }
  }

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

  /// Fetch today's meetings as a one-off future, sorted by start_time, with active customizations attached.
  Future<List<MeetingModel>> fetchTodaysMeetings({
    required DateTime today,
  }) async {
    final dateStr =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final response = await _runWithResilience<List<Map<String, dynamic>>>(
      () async => await _client
          .from(_tableMeetings)
          .select('*, schedules(*), local_overrides(*)')
          .eq('meeting_date', dateStr),
    );

    final meetings = response.map(MeetingModel.fromJson).toList();
    final scheduleIds = meetings
        .map((m) => m.scheduleId)
        .whereType<int>()
        .toSet()
        .toList();

    List<ScheduleCustomizationModel> customizations = const [];
    if (scheduleIds.isNotEmpty) {
      try {
        customizations = await fetchCustomizations(scheduleIds);
      } catch (_) {
        // Non-fatal if offline / customizations unavailable
      }
    }

    final mappedMeetings = meetings.map((m) {
      final cust = _resolveEffectiveCustomization(
        customizations,
        m.scheduleId,
        m.id,
      );
      return m.copyWith(customization: cust);
    }).toList();

    mappedMeetings.sort((a, b) {
      final cmp = a.startTime.compareTo(b.startTime);
      if (cmp != 0) return cmp;
      return a.meetingNumber.compareTo(b.meetingNumber);
    });
    return mappedMeetings;
  }

  static ScheduleCustomizationModel? _resolveEffectiveCustomization(
    List<ScheduleCustomizationModel> customizations,
    int? scheduleId,
    int? meetingId,
  ) {
    if (scheduleId == null) return null;
    ScheduleCustomizationModel? courseLevel;
    for (final c in customizations) {
      if (c.scheduleId != scheduleId) continue;
      if (meetingId != null && c.meetingId == meetingId) {
        return c; // Meeting-level takes absolute precedence
      }
      if (c.meetingId == null && courseLevel == null) {
        courseLevel = c;
      }
    }
    return courseLevel;
  }

  /// Fetch the full semester schedule matrix with all nested meetings and
  /// their resolved customizations attached.
  Future<List<ScheduleModel>> fetchSemesterMatrix() async {
    final response = await _runWithResilience<List<Map<String, dynamic>>>(
      () async => await _client
          .from(_tableSchedules)
          .select('*, meetings(*, local_overrides(*))')
          .order('course_code'),
    );
    final schedules = response.map(ScheduleModel.fromJson).toList();
    final scheduleIds = schedules.map((s) => s.id).toList();

    List<ScheduleCustomizationModel> customizations = const [];
    if (scheduleIds.isNotEmpty) {
      try {
        customizations = await fetchCustomizations(scheduleIds);
      } catch (_) {
        // Non-fatal: the matrix still renders official portal times.
      }
    }

    return schedules.map((schedule) {
      final meetings = schedule.meetings
          .map(
            (m) => m.copyWith(
              customization: _resolveEffectiveCustomization(
                customizations,
                schedule.id,
                m.id,
              ),
            ),
          )
          .toList();
      return schedule.copyWith(meetings: meetings);
    }).toList();
  }

  /// Fetch the meetings of one schedule, ordered by meeting number.
  Future<List<MeetingModel>> fetchMeetingsForSchedule({
    required int scheduleId,
  }) async {
    final response = await _runWithResilience<List<Map<String, dynamic>>>(
      () async => await _client
          .from(_tableMeetings)
          .select('*, schedules(*), local_overrides(*)')
          .eq('schedule_id', scheduleId)
          .order('meeting_number'),
    );
    return response.map(MeetingModel.fromJson).toList();
  }

  /// Submit a presence override (izin / sakit / alpa) for a meeting.
  Future<void> submitOverride({
    required int meetingId,
    required String overrideType,
    String note = '',
  }) async {
    await _runWithResilience<void>(
      () => _client.from(_tableOverrides).upsert({
        'meeting_id': meetingId,
        'override_type': overrideType.toLowerCase(),
        'note': note,
      }, onConflict: 'meeting_id'),
      retry: false,
    );
  }

  /// Delete/clear local override for a meeting.
  Future<void> clearOverride({required int meetingId}) async {
    await _runWithResilience<void>(
      () => _client.from(_tableOverrides).delete().eq('meeting_id', meetingId),
      retry: false,
    );
  }

  /// Confirm presence on Simkuliah through the backend gateway.
  ///
  /// Never writes 'hadir' directly into Supabase from the client: the backend
  /// submits the 7-field AJAX confirmation to Simkuliah first and updates
  /// Supabase only once Simkuliah returns "success".
  Future<void> submitPresence({
    required int meetingId,
    required bool isPresent,
  }) async {
    if (!isPresent) {
      await _client
          .from(_tableMeetings)
          .update({
            'simkuliah_status': 'tidak_hadir',
            'student_confirmed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', meetingId);
      return;
    }

    if (_apiBaseUrl.isEmpty) {
      throw const UserFacingException(
        'Server pemantau belum dikonfigurasi. Lakukan presensi langsung melalui website Simkuliah.',
      );
    }

    final ownsClient = _customHttpClient == null;
    final httpClient = _customHttpClient ?? http.Client();
    try {
      final response = await httpClient
          .post(
            Uri.parse('$_apiBaseUrl/api/v1/presence/confirm'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'meeting_id': meetingId}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return;
      }

      String? serverDetail;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
          serverDetail = decoded['detail'] as String;
        }
      } catch (_) {
        // Non-JSON body falls back to generic status error below.
      }
      throw UserFacingException(
        serverDetail ??
            'Konfirmasi presensi ke Simkuliah gagal (HTTP ${response.statusCode}).',
      );
    } finally {
      if (ownsClient) {
        httpClient.close();
      }
    }
  }

  /// Fetch schedule customizations for the given schedule ids.
  Future<List<ScheduleCustomizationModel>> fetchCustomizations(
    List<int> scheduleIds,
  ) async {
    if (scheduleIds.isEmpty) return [];
    final response = await _runWithResilience<List<Map<String, dynamic>>>(
      () async => await _client
          .from(_tableScheduleCustomizations)
          .select('*')
          .inFilter('schedule_id', scheduleIds),
    );
    return response.map(ScheduleCustomizationModel.fromJson).toList();
  }

  /// Save or update a schedule customization row with deterministic id conflict resolution.
  Future<ScheduleCustomizationModel> saveCustomization(
    ScheduleCustomizationModel customization,
  ) async {
    final payload = customization.toJson();
    if (!payload.containsKey('id') || payload['id'] == null) {
      final schedId = customization.scheduleId;
      final meetId = customization.meetingId;
      var query = _client
          .from(_tableScheduleCustomizations)
          .select('id')
          .eq('schedule_id', schedId);
      if (meetId == null) {
        query = query.filter('meeting_id', 'is', 'null');
      } else {
        query = query.eq('meeting_id', meetId);
      }
      final existing = await _runWithResilience<List<Map<String, dynamic>>>(
        () async => await query.limit(1),
      );
      if (existing.isNotEmpty && existing.first['id'] != null) {
        payload['id'] = existing.first['id'];
      }
    }

    final resolvedId = payload['id'];
    final response = await _runWithResilience<Map<String, dynamic>>(
      () async => resolvedId != null
          // Update the resolved row by primary key: the partial unique indexes
          // cannot serve as an ON CONFLICT target.
          ? await _client
                .from(_tableScheduleCustomizations)
                .upsert(payload, onConflict: 'id')
                .select()
                .single()
          // Brand-new row: plain insert, the partial unique indexes still
          // reject a concurrent duplicate.
          : await _client
                .from(_tableScheduleCustomizations)
                .insert(payload)
                .select()
                .single(),
      retry: false,
    );
    return ScheduleCustomizationModel.fromJson(response);
  }

  /// Quick 1-click toggle for auto-presence on a single meeting.
  Future<ScheduleCustomizationModel> saveMeetingAutoPresence({
    required int scheduleId,
    required int meetingId,
    required bool enabled,
  }) async {
    final existing = await _runWithResilience<List<Map<String, dynamic>>>(
      () async => await _client
          .from(_tableScheduleCustomizations)
          .select('id')
          .eq('schedule_id', scheduleId)
          .eq('meeting_id', meetingId)
          .limit(1),
    );

    final payload = <String, dynamic>{
      'schedule_id': scheduleId,
      'meeting_id': meetingId,
      'auto_presence_enabled': enabled,
    };
    if (existing.isNotEmpty && existing.first['id'] != null) {
      payload['id'] = existing.first['id'];
    }

    final resolvedId = payload['id'];
    final response = await _runWithResilience<Map<String, dynamic>>(
      () async => resolvedId != null
          ? await _client
                .from(_tableScheduleCustomizations)
                .upsert(payload, onConflict: 'id')
                .select()
                .single()
          : await _client
                .from(_tableScheduleCustomizations)
                .insert(payload)
                .select()
                .single(),
      retry: false,
    );
    return ScheduleCustomizationModel.fromJson(response);
  }

  /// Delete a schedule customization by primary key id.
  Future<void> deleteCustomization(int id) async {
    await _runWithResilience<void>(
      () => _client.from(_tableScheduleCustomizations).delete().eq('id', id),
      retry: false,
    );
  }

  /// Fetch user preferences, falling back to default values if not configured yet.
  Future<UserPreferencesModel> fetchUserPreferences({
    String userId = 'default_user',
  }) async {
    final response = await _runWithResilience<List<Map<String, dynamic>>>(
      () async => await _client
          .from(_tableUserPreferences)
          .select('*')
          .eq('user_id', userId)
          .limit(1),
    );
    if (response.isEmpty) {
      return UserPreferencesModel(userId: userId);
    }
    return UserPreferencesModel.fromJson(response.first);
  }

  /// Save or update user preferences.
  Future<UserPreferencesModel> saveUserPreferences(
    UserPreferencesModel preferences,
  ) async {
    final payload = preferences.toJson();
    final response = await _runWithResilience<Map<String, dynamic>>(
      () async => await _client
          .from(_tableUserPreferences)
          .upsert(payload, onConflict: 'user_id')
          .select()
          .single(),
      retry: false,
    );
    return UserPreferencesModel.fromJson(response);
  }
}
