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
    // Auto-presence toggle should be visible
    expect(find.text('Auto-Absen Pertemuan Ini'), findsOneWidget);
  });

  testWidgets('renders auto-absen toggle and reflects state', (tester) async {
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

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ActiveLectureCard(meeting: meeting)),
      ),
    );

    expect(find.text('Auto-Absen Pertemuan Ini'), findsOneWidget);
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    final switchWidget = tester.widget<Switch>(switchFinder);
    expect(switchWidget.value, isFalse);
  });

  testWidgets('bounds the inline controls instead of stretching them', (
    tester,
  ) async {
    // The default test surface is wider than the control bound, so a missing
    // constraint would show up as a full-width control here.
    final meeting = MeetingModel(
      id: 11,
      scheduleId: 1,
      courseName: 'Grafika Komputer',
      startTime: '08:00:00',
      endTime: '23:59:00',
      meetingNumber: 1,
      isPresenceOpen: true,
      deadlineAt: DateTime.now().add(const Duration(minutes: 20)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveLectureCard(
            meeting: meeting,
            allowPresenceConfirmation: true,
          ),
        ),
      ),
    );

    final autoPresenceRow = tester.getSize(
      find
          .ancestor(
            of: find.text('Auto-Absen Pertemuan Ini'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(autoPresenceRow.width, lessThanOrEqualTo(420));

    final presenceButton = tester.getSize(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(presenceButton.width, lessThanOrEqualTo(420));
  });

  testWidgets('names the real reason when auto-absen is inactive', (
    tester,
  ) async {
    // Attendance already recorded in Simkuliah.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ActiveLectureCard(
            meeting: MeetingModel(
              id: 12,
              scheduleId: 1,
              courseName: 'Grafika Komputer',
              startTime: '00:00:00',
              endTime: '00:00:00',
              meetingNumber: 3,
              simkuliahStatus: 'hadir',
              isPresenceOpen: false,
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Tidak diperlukan: presensi sudah tercatat di Simkuliah'),
      findsOneWidget,
    );
    expect(find.textContaining('lakukan presensi manual'), findsNothing);

    // Presence window already closed.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveLectureCard(
            meeting: MeetingModel(
              id: 13,
              scheduleId: 1,
              courseName: 'Grafika Komputer',
              startTime: '00:00:00',
              endTime: '23:59:00',
              meetingNumber: 4,
              isPresenceOpen: false,
              deadlineAt: DateTime.now().subtract(const Duration(minutes: 5)),
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Tidak berlaku: jendela presensi sudah ditutup'),
      findsOneWidget,
    );

    // Lecture finished without ever opening presence.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ActiveLectureCard(
            meeting: MeetingModel(
              id: 14,
              scheduleId: 1,
              courseName: 'Grafika Komputer',
              startTime: '00:00:00',
              endTime: '00:00:00',
              meetingNumber: 5,
              isPresenceOpen: false,
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Tidak berlaku: jadwal kuliah sudah berakhir'),
      findsOneWidget,
    );

    // Upcoming lecture: the honest call to action remains.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ActiveLectureCard(
            meeting: MeetingModel(
              id: 15,
              scheduleId: 1,
              courseName: 'Grafika Komputer',
              startTime: '23:58:00',
              endTime: '23:59:00',
              meetingNumber: 6,
              isPresenceOpen: false,
            ),
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Nonaktif: aktifkan agar presensi otomatis saat dosen membuka absensi',
      ),
      findsOneWidget,
    );
  });
}
