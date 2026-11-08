import 'package:flutter/material.dart';

import '../models/meeting_model.dart';
import '../services/presence_service.dart';
import 'widgets/active_lecture_card.dart';

/// Today's feed: renders the list of today's lecture meetings from
/// [`PresenceService`], each as an [`ActiveLectureCard`].
class TodayFeedView extends StatelessWidget {
  const TodayFeedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kehadiran Hari Ini'),
      ),
      body: FutureBuilder<List<MeetingModel>>(
        future: PresenceService().fetchTodaysMeetings(today: DateTime.now()),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat jadwal: ${snapshot.error}'));
          }
          final meetings = snapshot.data ?? const <MeetingModel>[];
          if (meetings.isEmpty) {
            return const Center(child: Text('Tidak ada jadwal kuliah hari ini.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: meetings.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ActiveLectureCard(meeting: meetings[index]),
              );
            },
          );
        },
      ),
    );
  }
}
