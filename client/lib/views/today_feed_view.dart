import 'package:flutter/material.dart';

import '../models/meeting_model.dart';
import '../services/presence_service.dart';
import 'widgets/active_lecture_card.dart';
import 'widgets/gateway_alert_banner.dart';

/// Today's feed: renders the list of today's lecture meetings from
/// [`PresenceService`], each as an [`ActiveLectureCard`].
class TodayFeedView extends StatefulWidget {
  /// Optional injectable presence service (defaults to a new instance).
  final PresenceService? presenceService;

  const TodayFeedView({super.key, this.presenceService});

  @override
  State<TodayFeedView> createState() => _TodayFeedViewState();
}

class _TodayFeedViewState extends State<TodayFeedView> {
  late final PresenceService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kehadiran Hari Ini')),
      body: FutureBuilder<List<MeetingModel>>(
        future: _service.fetchTodaysMeetings(today: DateTime.now()),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Gagal memuat jadwal: ${snapshot.error}'),
            );
          }
          final meetings = snapshot.data ?? const <MeetingModel>[];
          if (meetings.isEmpty) {
            return const Center(
              child: Text('Tidak ada jadwal kuliah hari ini.'),
            );
          }
          return Column(
            children: [
              const GatewayAlertBanner(hasOutage: false),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: meetings.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ActiveLectureCard(meeting: meetings[index]),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
