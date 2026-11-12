/// Purpose: Today's schedule feed view displaying all daily lectures.
/// Data & Logic Flow: Caches today's meetings and silently refetches on refresh-bus events so focus changes never flash a loading spinner.
/// Key Components: TodayFeedView
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/load_epoch_guard.dart';
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
  final LoadEpochGuard _loadGuard = LoadEpochGuard();
  StreamSubscription<void>? _refreshSub;
  Timer? _keepAliveTimer;
  List<MeetingModel>? _meetings;
  bool _loading = true;
  Object? _error;
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
      unawaited(_load(silent: _meetings != null, force: true));
      unawaited(_checkHealth());
    });
    if (_healthService.isConfigured) {
      // Keep the free-tier Render container warm (15-min idle sleep) while
      // the desktop tray or app is running, and trigger view recovery if
      // connectivity just returned after an outage.
      _keepAliveTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(_runKeepAlive()),
      );
    }
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    unawaited(_refreshSub?.cancel());
    super.dispose();
  }

  Future<void> _runKeepAlive() async {
    final wasDown = _health?.status == BackendHealthStatus.backendDown;
    final result = await _healthService.keepAlive();
    if (!mounted) return;
    setState(() {
      _health = result;
    });
    if ((wasDown && result.status == BackendHealthStatus.ok) ||
        (_meetings == null && result.status == BackendHealthStatus.ok)) {
      RefreshBus.instance.requestRefresh();
    }
  }

  /// Probe backend and Simkuliah health for the warning banner and wake a
  /// stale poller on demand. Refresh-bus events can fire in bursts, so
  /// rechecks are throttled to once per 30 seconds; when the backend runs a
  /// fresh sync (`syncedNow`) or recovers from an outage, broadcast a refresh
  /// so every mounted view reads the newly written state.
  Future<void> _checkHealth() async {
    final last = _lastHealthCheckAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastHealthCheckAt = DateTime.now();
    final wasDown = _health?.status == BackendHealthStatus.backendDown;
    final result = await _healthService.check();
    if (!mounted) return;
    setState(() {
      _health = result;
    });
    if (result.syncedNow ||
        (wasDown && result.status == BackendHealthStatus.ok)) {
      RefreshBus.instance.requestRefresh();
    }
  }

  /// Fetch today's meetings. [silent] keeps any cached data on screen and
  /// swaps it in place when the fetch completes, so a focus-driven refresh
  /// never flashes a loading spinner.
  Future<void> _load({required bool silent, bool force = false}) async {
    final epoch = _loadGuard.tryBegin(
      timeout: _service.requestTimeout,
      force: force,
    );
    if (epoch == null) return;
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
      if (!mounted || !_loadGuard.isCurrent(epoch)) return;
      setState(() {
        _meetings = meetings;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || !_loadGuard.isCurrent(epoch)) return;
      // A failed silent refresh keeps the stale view; only when no cached
      // data exists do we surface the error screen.
      if (_meetings == null) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    } finally {
      _loadGuard.complete(epoch);
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
        onRetry: () => unawaited(_load(silent: false, force: true)),
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
      onRefresh: () => _load(silent: true, force: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
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
              onStatusChanged: () =>
                  unawaited(_load(silent: true, force: true)),
              allowPresenceConfirmation: false,
            ),
          );
        },
      ),
    );
  }
}
