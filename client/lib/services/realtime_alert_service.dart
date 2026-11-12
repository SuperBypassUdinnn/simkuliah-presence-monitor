/// Purpose: Desktop in-app realtime alerts driven by Supabase Realtime.
/// Data & Logic Flow: Streams today's meetings rows, evaluates presence states
/// against the shared priority policy, dedupes alerts per meeting, and reports
/// resolved/expired meetings so sticky banners can be dismissed.
/// Key Components: RealtimeAlertService, PresenceAlert, PresenceAlertKind,
/// RealtimeAlertEvaluator
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_notification.dart';
import '../core/refresh_bus.dart';
import '../models/meeting_model.dart';
import 'presence_service.dart';

/// Alert kinds surfaced in-app. Mirrors the backend state machine levels that
/// are meaningful on desktop; only the urgent two are high priority.
enum PresenceAlertKind {
  lecturerOpened,
  urgentClosing,
  classStarted,
  windowExpired,
}

/// One renderable in-app alert.
class PresenceAlert {
  final PresenceAlertKind kind;
  final int meetingId;
  final String courseName;
  final String room;

  /// Urgent alerts render as sticky banners (no auto-dismiss); everything
  /// else is a normal auto-dismissing toast. Mirrors the backend priority
  /// policy: high priority is reserved for lecturer-opened and urgent-closing.
  final bool urgent;
  final String title;
  final String message;

  const PresenceAlert({
    required this.kind,
    required this.meetingId,
    required this.courseName,
    required this.room,
    required this.urgent,
    required this.title,
    required this.message,
  });
}

/// Result of one evaluation pass over the current meetings snapshot.
@immutable
class AlertEvaluation {
  /// Alerts to show now (already deduped against [shownKeys]).
  final List<PresenceAlert> alerts;

  /// Meeting ids whose presence resolved (attended/overridden) or whose
  /// window expired: any sticky banner for them must be dismissed.
  final Set<int> resolvedMeetingIds;

  /// Updated dedupe key set after this pass.
  final Set<String> shownKeys;

  const AlertEvaluation({
    required this.alerts,
    required this.resolvedMeetingIds,
    required this.shownKeys,
  });
}

/// Pure evaluator: turns a meetings snapshot into deduped alerts.
///
/// State semantics match the backend (`backend/app/services/state_machine.py`):
/// presence open == pending meeting with a deadline; the urgent phase starts
/// 10 minutes before the deadline; attended/overridden meetings suppress
/// alerts.
class RealtimeAlertEvaluator {
  const RealtimeAlertEvaluator._();

  /// How close to the deadline the urgent-closing phase begins (mirrors
  /// `_URGENT_WINDOW_MINUTES` in the backend state machine).
  static const Duration urgentWindow = Duration(minutes: 10);

  static String _key(int meetingId, PresenceAlertKind kind) =>
      '$meetingId:${kind.name}';

  /// Evaluate `meetings` at `now`, never re-emitting a key already in
  /// [shownKeys]. Deadline-free meetings (no open window) only produce a
  /// class-started toast while inside their scheduled time.
  ///
  /// Windows whose deadline passed before [suppressExpiredBefore] are marked
  /// seen without toasting: they ended before the app started, so a
  /// "presensi ditutup" toast would be stale noise (Android never shows
  /// these because the alert service is desktop-only).
  static AlertEvaluation evaluate({
    required List<MeetingModel> meetings,
    required Set<String> shownKeys,
    required DateTime now,
    DateTime? suppressExpiredBefore,
  }) {
    final alerts = <PresenceAlert>[];
    final resolved = <int>{};
    final nextShown = Set<String>.of(shownKeys);

    for (final meeting in meetings) {
      final resolvedState = meeting.isAttended || meeting.isOverridden;
      final expired =
          meeting.deadlineAt != null && now.isAfter(meeting.deadlineAt!);

      if (resolvedState) {
        resolved.add(meeting.id);
        continue;
      }

      if (expired) {
        resolved.add(meeting.id);
        final key = _key(meeting.id, PresenceAlertKind.windowExpired);
        if (suppressExpiredBefore != null &&
            meeting.deadlineAt!.isBefore(suppressExpiredBefore)) {
          // Stale: the window closed before the app started.
          nextShown.add(key);
          continue;
        }
        if (nextShown.add(key)) {
          alerts.add(
            PresenceAlert(
              kind: PresenceAlertKind.windowExpired,
              meetingId: meeting.id,
              courseName: meeting.courseName,
              room: meeting.room,
              urgent: false,
              title: 'Presensi Ditutup',
              message:
                  'Waktu presensi ${meeting.courseName} telah berakhir. '
                  'Status: ${meeting.effectiveStatus}.',
            ),
          );
        }
        continue;
      }

      final open = meeting.isPresenceOpen && meeting.deadlineAt != null;
      if (!open) {
        // Class started but the lecturer has not opened presence yet.
        if (meeting.isWithinScheduleTime(referenceTime: now) &&
            nextShown.add(_key(meeting.id, PresenceAlertKind.classStarted))) {
          alerts.add(
            PresenceAlert(
              kind: PresenceAlertKind.classStarted,
              meetingId: meeting.id,
              courseName: meeting.courseName,
              room: meeting.room,
              urgent: false,
              title: 'Kelas Dimulai',
              message:
                  '${meeting.courseName} telah dimulai. Presensi belum '
                  'dibuka dosen.',
            ),
          );
        }
        continue;
      }

      final deadline = meeting.deadlineAt!;
      final untilDeadline = deadline.difference(now);
      if (untilDeadline <= urgentWindow) {
        final key = _key(meeting.id, PresenceAlertKind.urgentClosing);
        if (nextShown.add(key)) {
          // The lecturer-opened banner is superseded by this one.
          nextShown.add(_key(meeting.id, PresenceAlertKind.lecturerOpened));
          final minutesLeft = untilDeadline.inMinutes.clamp(0, 999);
          alerts.add(
            PresenceAlert(
              kind: PresenceAlertKind.urgentClosing,
              meetingId: meeting.id,
              courseName: meeting.courseName,
              room: meeting.room,
              urgent: true,
              title: 'Presensi Segera Ditutup',
              message:
                  '${meeting.courseName} tutup dalam $minutesLeft menit '
                  '(${meeting.deadlineAt!.toIso8601String().substring(11, 16)}). '
                  'Segera konfirmasi kehadiran!',
            ),
          );
        }
        continue;
      }

      // Presence is open with time to spare: the high-priority
      // lecturer-opened banner.
      final key = _key(meeting.id, PresenceAlertKind.lecturerOpened);
      if (nextShown.add(key)) {
        alerts.add(
          PresenceAlert(
            kind: PresenceAlertKind.lecturerOpened,
            meetingId: meeting.id,
            courseName: meeting.courseName,
            room: meeting.room,
            urgent: true,
            title: 'Dosen Membuka Presensi',
            message:
                'Presensi ${meeting.courseName} telah dibuka. Segera '
                'konfirmasi kehadiran Anda.',
          ),
        );
      }
    }

    return AlertEvaluation(
      alerts: alerts,
      resolvedMeetingIds: resolved,
      shownKeys: nextShown,
    );
  }
}

/// Subscribes to today's meetings over Supabase Realtime and emits deduped
/// [PresenceAlert]s. Desktop-focused: on Android the FCM push stack covers
/// the same states, so the app only starts this service on non-Android
/// platforms.
class RealtimeAlertService {
  RealtimeAlertService({
    SupabaseClient? client,
    PresenceService? presenceService,
    Stream<List<Map<String, dynamic>>> Function(String dateStr)? streamFactory,
    Duration baseReconnectDelay = const Duration(seconds: 2),
  }) : _customClient = client,
       _customPresenceService = presenceService,
       _customStreamFactory = streamFactory,
       _reconnectBaseDelay = baseReconnectDelay;

  final SupabaseClient? _customClient;
  final PresenceService? _customPresenceService;
  final Stream<List<Map<String, dynamic>>> Function(String dateStr)?
  _customStreamFactory;
  final Duration _reconnectBaseDelay;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Timer? _timer;
  Timer? _reconnectTimer;
  bool _running = false;
  int _reconnectAttempts = 0;
  final math.Random _rng = math.Random();

  static const Duration _maxReconnectDelay = Duration(seconds: 60);

  @visibleForTesting
  int get reconnectAttempts => _reconnectAttempts;

  /// Dedupe keys already surfaced this session.
  @visibleForTesting
  final Set<String> shownKeys = {};

  /// When the service started: windows that ended before this instant are
  /// never toasted (stale on startup).
  DateTime? _startedAt;

  /// Sticky banner ids per alert key, so resolved meetings can dismiss them.
  final Map<String, int> _bannerIds = {};

  /// Meetings snapshot from the last pass, reused by the periodic timer.
  List<MeetingModel> _lastMeetings = const [];

  SupabaseClient get _client {
    if (_customClient != null) return _customClient;
    return Supabase.instance.client;
  }

  /// Start streaming and evaluating. `onAlert` renders an alert and returns
  /// the notification id used to dismiss sticky banners later. Safe to call
  /// once; further calls are no-ops.
  void start({
    required int Function(PresenceAlert alert) onAlert,
    void Function(int meetingId, PresenceAlertKind kind)? onDismissAlert,
    DateTime Function()? clock,
  }) {
    if (_running) {
      return;
    }
    _running = true;
    _startedAt = DateTime.now();
    _reconnectAttempts = 0;

    _subscribeStream(
      onAlert: onAlert,
      onDismissAlert: onDismissAlert,
      clock: clock,
    );

    // Time-driven transitions (urgent phase entry) need re-evaluation even
    // when no row changes arrive; if the stream died without an active
    // reconnect timer, kick off a fresh subscription.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _evaluate(
        _lastMeetings,
        onAlert: onAlert,
        onDismissAlert: onDismissAlert,
        clock: clock,
      );
      if (_running &&
          _subscription == null &&
          !(_reconnectTimer?.isActive ?? false)) {
        _subscribeStream(
          onAlert: onAlert,
          onDismissAlert: onDismissAlert,
          clock: clock,
        );
      }
    });
  }

  void _subscribeStream({
    required int Function(PresenceAlert alert) onAlert,
    void Function(int meetingId, PresenceAlertKind kind)? onDismissAlert,
    DateTime Function()? clock,
  }) {
    if (!_running) {
      return;
    }
    unawaited(_subscription?.cancel());
    _subscription = null;

    final today = clock?.call() ?? DateTime.now();
    final dateStr =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    final stream = _customStreamFactory != null
        ? _customStreamFactory(dateStr)
        : _client
              .from('meetings')
              .stream(primaryKey: ['id'])
              .eq('meeting_date', dateStr);

    _subscription = stream.listen(
      (rows) => unawaited(
        _handleRows(
          rows,
          onAlert: onAlert,
          onDismissAlert: onDismissAlert,
          clock: clock,
        ),
      ),
      onError: (Object error) {
        debugPrint('Realtime alert stream error: $error');
        _subscription = null;
        _scheduleReconnect(
          onAlert: onAlert,
          onDismissAlert: onDismissAlert,
          clock: clock,
        );
      },
      onDone: () {
        debugPrint('Realtime alert stream closed; scheduling reconnect');
        _subscription = null;
        _scheduleReconnect(
          onAlert: onAlert,
          onDismissAlert: onDismissAlert,
          clock: clock,
        );
      },
    );
  }

  void _scheduleReconnect({
    required int Function(PresenceAlert alert) onAlert,
    void Function(int meetingId, PresenceAlertKind kind)? onDismissAlert,
    DateTime Function()? clock,
  }) {
    if (!_running) {
      return;
    }
    // Single-timer guard prevents error + done from scheduling two timers.
    if (_reconnectTimer?.isActive ?? false) {
      return;
    }
    final factor = 1 << math.min(_reconnectAttempts, 5);
    final rawMs = _reconnectBaseDelay.inMilliseconds * factor;
    final cappedMs = math.min(_maxReconnectDelay.inMilliseconds, rawMs);
    final jitterMs = _reconnectBaseDelay.inMilliseconds > 0
        ? _rng.nextInt(math.max(1, _reconnectBaseDelay.inMilliseconds ~/ 4))
        : 0;
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(milliseconds: cappedMs + jitterMs), () {
      _reconnectTimer = null;
      _subscribeStream(
        onAlert: onAlert,
        onDismissAlert: onDismissAlert,
        clock: clock,
      );
    });
  }

  Future<void> stop() async {
    _running = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
    _timer = null;
  }

  /// Test seam: run one evaluation pass over an injected snapshot.
  @visibleForTesting
  void processMeetings({
    required List<MeetingModel> meetings,
    required int Function(PresenceAlert alert) onAlert,
    void Function(int meetingId, PresenceAlertKind kind)? onDismissAlert,
    DateTime Function()? clock,
  }) {
    _evaluate(
      meetings,
      onAlert: onAlert,
      onDismissAlert: onDismissAlert,
      clock: clock,
    );
  }

  Future<void> _handleRows(
    List<Map<String, dynamic>> rows, {
    required int Function(PresenceAlert alert) onAlert,
    void Function(int meetingId, PresenceAlertKind kind)? onDismissAlert,
    DateTime Function()? clock,
  }) async {
    List<MeetingModel> meetings;
    try {
      final now = clock?.call() ?? DateTime.now();
      final service =
          _customPresenceService ?? PresenceService(client: _client);
      meetings = await service.fetchTodaysMeetings(today: now);
    } catch (_) {
      // Fall back to the raw stream payload if the join query fails offline.
      meetings = rows.map(MeetingModel.fromJson).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
    }
    if (!_running || _subscription == null) {
      return;
    }
    // Reset backoff only after a live snapshot is processed cleanly.
    _reconnectAttempts = 0;
    _evaluate(
      meetings,
      onAlert: onAlert,
      onDismissAlert: onDismissAlert,
      clock: clock,
    );
    // Notify mounted feed views to reload from Supabase so newly opened
    // presence windows or status transitions appear immediately on screen.
    RefreshBus.instance.requestRefresh();
  }

  void _evaluate(
    List<MeetingModel> meetings, {
    required int Function(PresenceAlert alert) onAlert,
    void Function(int meetingId, PresenceAlertKind kind)? onDismissAlert,
    DateTime Function()? clock,
  }) {
    _lastMeetings = meetings;
    final now = clock?.call() ?? DateTime.now();
    // Baseline on the first evaluation even when start() was never called
    // (e.g. the test seam), so stale-window suppression always has a bound.
    _startedAt ??= now;
    final result = RealtimeAlertEvaluator.evaluate(
      meetings: meetings,
      shownKeys: shownKeys,
      now: now,
      suppressExpiredBefore: _startedAt,
    );

    shownKeys
      ..clear()
      ..addAll(result.shownKeys);

    // Resolved or expired meetings: drop their sticky banners.
    for (final id in result.resolvedMeetingIds) {
      for (final kind in PresenceAlertKind.values) {
        final banner = _bannerIds.remove('$id:${kind.name}');
        if (banner != null) {
          AppNotification.dismiss(banner);
          onDismissAlert?.call(id, kind);
        }
      }
    }

    for (final alert in result.alerts) {
      if (alert.urgent) {
        // A new sticky banner supersedes earlier sticky banners for the same
        // meeting (e.g. urgent-closing replaces lecturer-opened).
        for (final kind in PresenceAlertKind.values) {
          if (kind == alert.kind) {
            continue;
          }
          final previous = _bannerIds.remove('${alert.meetingId}:${kind.name}');
          if (previous != null) {
            AppNotification.dismiss(previous);
            onDismissAlert?.call(alert.meetingId, kind);
          }
        }
      }
      final notificationId = onAlert(alert);
      if (alert.urgent) {
        _bannerIds['${alert.meetingId}:${alert.kind.name}'] = notificationId;
      }
    }
  }
}
