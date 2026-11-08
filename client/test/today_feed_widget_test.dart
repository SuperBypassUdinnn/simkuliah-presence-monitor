import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/views/widgets/active_lecture_card.dart';
import 'package:simkuliah_client/models/meeting_model.dart';

void main() {
  testWidgets('ActiveLectureCard displays Konfirmasi Presensi when open', (
    tester,
  ) async {
    final meeting = MeetingModel(
      id: 1,
      courseName: 'Grafika Komputer',
      meetingNumber: 7,
      isPresenceOpen: true,
      deadlineAt: DateTime.now().add(const Duration(minutes: 15)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ActiveLectureCard(meeting: meeting)),
      ),
    );

    expect(find.text('Konfirmasi Presensi'), findsOneWidget);
    expect(find.text('Izin'), findsOneWidget);
    expect(find.text('Sakit'), findsOneWidget);
  });
}
