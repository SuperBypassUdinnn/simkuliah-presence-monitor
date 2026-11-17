// client/test/active_lecture_card_customization_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/models/meeting_model.dart';
import 'package:simkuliah_client/models/schedule_customization_model.dart';
import 'package:simkuliah_client/views/widgets/active_lecture_card.dart';

void main() {
  testWidgets('renders effective time and portal badge when customized', (
    tester,
  ) async {
    const meeting = MeetingModel(
      id: 10,
      scheduleId: 1,
      courseName: 'Grafika Komputer',
      courseCode: 'INF201',
      startTime: '08:00:00',
      endTime: '09:40:00',
      meetingNumber: 1,
      isPresenceOpen: false,
    );

    const customization = ScheduleCustomizationModel(
      id: 1,
      scheduleId: 1,
      timeOffsetMinutes: 60,
      autoPresenceEnabled: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ActiveLectureCard(
            meeting: meeting,
            customization: customization,
          ),
        ),
      ),
    );

    // Baseline portal badge should be visible
    expect(find.textContaining('Portal: 08:00'), findsOneWidget);
    // Effective time should reflect +60m = 09:00 - 10:40
    expect(find.textContaining('09:00 - 10:40'), findsOneWidget);
    // Auto-presence badge should be visible
    expect(find.text('Auto-Absen'), findsOneWidget);
  });
}
