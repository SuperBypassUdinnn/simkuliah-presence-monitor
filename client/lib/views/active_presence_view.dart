/// Purpose: Active presence view strictly displaying currently open lectures.
/// Data & Logic Flow: Caches today's meetings, filters for the active schedule window, and silently refetches on refresh-bus events.
/// Key Components: ActivePresenceView
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/refresh_bus.dart';
import '../models/meeting_model.dart';
import '../services/presence_service.dart';
import 'widgets/active_lecture_card.dart';
import 'widgets/error_state_view.dart';

/// Active presence view: strictly displays lectures whose schedule is
/// currently active today.
class ActivePresenceView extends StatefulWidget {
  final PresenceService? presenceService;

  const ActivePresenceView({super.key, this.presenceService});

  @override
  State<ActivePresenceView> createState() => _ActivePresenceViewState();
}

class _ActivePresenceViewState extends State<ActivePresenceView> {
  late final PresenceService _service;
  StreamSubscription<void>? _refreshSub;
  List<MeetingModel>? _meetings;
  bool _loading = true;
  Object? _error;
  bool _fetchInFlight = false;

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    unawaited(_load(silent: false));
    _refreshSub = RefreshBus.instance.stream.listen(
      (_) => unawaited(_load(silent: true)),
    );
  }

  @override
  void dispose() {
    unawaited(_refreshSub?.cancel());
    super.dispose();
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
      appBar: AppBar(title: const Text('Presensi Aktif')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _meetings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _meetings == null) {
      return ErrorStateView(
        title: 'Gagal memuat status presensi',
        error: _error,
        onRetry: () => unawaited(_load(silent: false)),
      );
    }

    final allMeetings = _meetings ?? const <MeetingModel>[];
    // Strictly filter to lectures whose schedule is currently active right now
    final activeMeetings = allMeetings
        .where((m) => m.isWithinScheduleTime())
        .toList();

    if (activeMeetings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.schedule_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Tidak Ada Kuliah Berlangsung Saat Ini',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tab ini khusus menampilkan mata kuliah yang sedang berlangsung dalam rentang jam saat ini. Silakan periksa tab "Jadwal Hari Ini" untuk melihat seluruh jadwal kuliah Anda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.4),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Periksa Ulang'),
                onPressed: () => unawaited(_load(silent: true)),
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
        itemCount: activeMeetings.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ActiveLectureCard(
              meeting: activeMeetings[index],
              presenceService: _service,
              onStatusChanged: () => unawaited(_load(silent: true)),
              allowPresenceConfirmation: true,
            ),
          );
        },
      ),
    );
  }
}
