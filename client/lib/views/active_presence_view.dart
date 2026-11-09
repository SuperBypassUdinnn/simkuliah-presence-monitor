/// Purpose: Active presence view strictly displaying currently open lectures.
/// Data & Logic Flow: Streams meetings, filters for active schedule window, enables presence confirmation.
/// Key Components: ActivePresenceView
import 'package:flutter/material.dart';

import '../models/meeting_model.dart';
import '../services/presence_service.dart';
import 'widgets/active_lecture_card.dart';

/// Active presence view: strictly displays lectures whose schedule is currently active today.
class ActivePresenceView extends StatefulWidget {
  final PresenceService? presenceService;

  const ActivePresenceView({super.key, this.presenceService});

  @override
  State<ActivePresenceView> createState() => _ActivePresenceViewState();
}

class _ActivePresenceViewState extends State<ActivePresenceView> {
  late final PresenceService _service;
  late Future<List<MeetingModel>> _meetingsFuture;

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    _loadMeetings();
  }

  void _loadMeetings() {
    setState(() {
      _meetingsFuture = _service.fetchTodaysMeetings(today: DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presensi Aktif'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan',
            onPressed: _loadMeetings,
          ),
        ],
      ),
      body: FutureBuilder<List<MeetingModel>>(
        future: _meetingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Gagal memuat status presensi:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi'),
                      onPressed: _loadMeetings,
                    ),
                  ],
                ),
              ),
            );
          }

          final allMeetings = snapshot.data ?? const <MeetingModel>[];
          // Strictly filter to lectures whose schedule is currently active right now
          final activeMeetings = allMeetings.where((m) {
            return m.isWithinScheduleTime();
          }).toList();

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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
                      onPressed: _loadMeetings,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _loadMeetings(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: activeMeetings.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ActiveLectureCard(
                    meeting: activeMeetings[index],
                    presenceService: _service,
                    onStatusChanged: _loadMeetings,
                    allowPresenceConfirmation: true,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
