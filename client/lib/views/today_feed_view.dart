/// Purpose: Today's schedule feed view displaying all daily lectures.
/// Data & Logic Flow: Caches today's meetings and silently refetches on refresh-bus events so focus changes never flash a loading spinner.
/// Key Components: TodayFeedView
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/refresh_bus.dart';
import '../models/meeting_model.dart';
import '../services/backend_health_service.dart';
import '../services/presence_service.dart';
import 'widgets/active_lecture_card.dart';
import 'widgets/error_state_view.dart';
import 'widgets/gateway_alert_banner.dart';

/// Today's feed: renders all of today's lecture meetings sorted by schedule
/// start time. Strictly displays lecture details and allows local overrides
/// if not yet attended.
class TodayFeedView extends StatefulWidget {
  final PresenceService? presenceService;
  final BackendHealthService? backendHealthService;

  const TodayFeedView({
    super.key,
    this.presenceService,
    this.backendHealthService,
  });

  @override
  State<TodayFeedView> createState() => _TodayFeedViewState();
}

class _TodayFeedViewState extends State<TodayFeedView> {
  late final PresenceService _service;
  late final BackendHealthService _healthService;
  StreamSubscription<void>? _refreshSub;
  List<MeetingModel>? _meetings;
  bool _loading = true;
  Object? _error;
  bool _fetchInFlight = false;
  BackendHealthResult? _health;
  DateTime? _lastHealthCheckAt;

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    _healthService = widget.backendHealthService ?? BackendHealthService();
    unawaited(_load(silent: false));
    unawaited(_checkHealth());
    _refreshSub = RefreshBus.instance.stream.listen((_) {
      unawaited(_load(silent: true));
      unawaited(_checkHealth());
    });
  }

  @override
  void dispose() {
    unawaited(_refreshSub?.cancel());
    super.dispose();
  }

  /// Probe backend and Simkuliah health for the warning banner. Refresh-bus
  /// events can fire in bursts, so rechecks are throttled to one per minute;
  /// a probe never throws and failures just light the banner.
  Future<void> _checkHealth() async {
    final last = _lastHealthCheckAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _lastHealthCheckAt = DateTime.now();
    final result = await _healthService.check();
    if (!mounted) return;
    setState(() {
      _health = result;
    });
  }

  /// Fetch today's meetings. [silent] keeps any cached data on screen and
  /// swaps it in place when the fetch completes, so a focus-driven refresh
  /// never flashes a loading spinner.
  Future<void> _load({required bool silent}) async {
    if (_fetchInFlight) return;
    _fetchInFlight = true;
    if (!silent || _meetings == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final meetings = await _service.fetchTodaysMeetings(
        today: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _meetings = meetings;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      // A failed silent refresh keeps the stale view; only the very first
      // load surfaces the error screen.
      if (_meetings == null) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    } finally {
      _fetchInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jadwal Kuliah Hari Ini')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _meetings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _meetings == null) {
      return ErrorStateView(
        title: 'Gagal memuat jadwal',
        error: _error,
        onRetry: () => unawaited(_load(silent: false)),
      );
    }
    final meetings = _meetings ?? const <MeetingModel>[];
    if (meetings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.calendar_month_outlined, size: 56, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'Tidak ada jadwal kuliah hari ini.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                'Selamat beristirahat atau belajar mandiri!',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: meetings.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            final health = _health;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: health == null || health.status == BackendHealthStatus.ok
                  ? const SizedBox.shrink()
                  : GatewayAlertBanner(
                      hasOutage: true,
                      errorMessage: health.message,
                    ),
            );
          }
          final meeting = meetings[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ActiveLectureCard(
              meeting: meeting,
              presenceService: _service,
              onStatusChanged: () => unawaited(_load(silent: true)),
              allowPresenceConfirmation: false,
            ),
          );
        },
      ),
    );
  }
}
