/// Purpose: Today's schedule feed view displaying all daily lectures.
/// Data & Logic Flow: Loads meetings for today sorted by schedule time without presence action buttons.
/// Key Components: TodayFeedView
import 'package:flutter/material.dart';

import '../models/meeting_model.dart';
import '../services/presence_service.dart';
import 'widgets/active_lecture_card.dart';
import 'widgets/gateway_alert_banner.dart';

/// Today's feed: renders all of today's lecture meetings sorted by schedule start time.
/// Strictly displays lecture details and allows local overrides if not yet attended.
class TodayFeedView extends StatefulWidget {
  final PresenceService? presenceService;

  const TodayFeedView({super.key, this.presenceService});

  @override
  State<TodayFeedView> createState() => _TodayFeedViewState();
}

class _TodayFeedViewState extends State<TodayFeedView> {
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
        title: const Text('Jadwal Kuliah Hari Ini'),
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
                      'Gagal memuat jadwal:\n${snapshot.error}',
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
          final meetings = snapshot.data ?? const <MeetingModel>[];
          if (meetings.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.calendar_month_outlined,
                      size: 56,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Tidak ada jadwal kuliah hari ini.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
            onRefresh: () async => _loadMeetings(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: meetings.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: GatewayAlertBanner(hasOutage: false),
                  );
                }
                final meeting = meetings[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ActiveLectureCard(
                    meeting: meeting,
                    presenceService: _service,
                    onStatusChanged: _loadMeetings,
                    allowPresenceConfirmation: false,
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
