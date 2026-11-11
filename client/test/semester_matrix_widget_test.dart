import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/models/meeting_model.dart';
import 'package:simkuliah_client/models/schedule_model.dart';
import 'package:simkuliah_client/services/presence_service.dart';
import 'package:simkuliah_client/views/semester_matrix_view.dart';

MeetingModel _meeting(int scheduleId, int number, {String status = 'pending'}) {
  return MeetingModel(
    id: scheduleId * 100 + number,
    scheduleId: scheduleId,
    courseName: 'Kursus',
    meetingNumber: number,
    simkuliahStatus: status,
    isPresenceOpen: false,
  );
}

ScheduleModel _praktikumCourse() {
  // Praktikum-style course: Simkuliah publishes only 12 meetings.
  return ScheduleModel(
    id: 2,
    courseCode: 'SINF6091',
    courseName: 'PRAKTIKUM KOMPUTASI AWAN',
    classGroup: 'A',
    room: 'L.1.01',
    startTime: '08:00',
    endTime: '09:40',
    lecturerName: 'Dosen A',
    meetings: [
      for (var n = 1; n <= 12; n++)
        _meeting(2, n, status: n <= 10 ? 'hadir' : 'tidak_hadir'),
    ],
  );
}

ScheduleModel _teoriCourse() {
  // Theory course: full 16-meeting matrix, unchanged behaviour.
  return ScheduleModel(
    id: 4,
    courseCode: 'SINF3031',
    courseName: 'KECERDASAN ARTIFISIAL',
    classGroup: 'C',
    room: 'D.3.02',
    startTime: '10:00',
    endTime: '11:40',
    lecturerName: 'Dosen B',
    meetings: [
      for (var n = 1; n <= 16; n++)
        _meeting(4, n, status: n <= 8 ? 'hadir' : 'pending'),
    ],
  );
}

/// In-memory presence service returning a fixed semester fixture.
class _FakePresenceService extends PresenceService {
  _FakePresenceService(this.courses);

  final List<ScheduleModel> courses;

  @override
  Future<List<ScheduleModel>> fetchSemesterMatrix() async => courses;
}

void main() {
  testWidgets('SemesterMatrixView renders 16 meeting indicator tiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SemesterMatrixView(testMode: true)),
      ),
    );

    expect(find.byType(MeetingGridTile), findsNWidgets(16));
  });

  testWidgets('shorter course renders 12 tiles, empty slots, and /12 recap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SemesterMatrixView(
            presenceService: _FakePresenceService([
              _praktikumCourse(),
              _teoriCourse(),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 12 + 16 real tiles; columns 13-16 of the short course render as
    // neutral empty slots so both rows span the same 16-column grid.
    expect(find.byType(MeetingGridTile), findsNWidgets(28));
    expect(find.text('–'), findsNWidgets(4));

    // Recap divides by the course's real semester length, not the grid size.
    expect(find.text('10/12 hadir'), findsOneWidget);
    expect(find.text('83%'), findsOneWidget);
    expect(find.text('8/16 hadir'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('16-column grid fits the default 1280x720 window width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              // The app's fixed-width navigation sidebar.
              const SizedBox(width: 250),
              Expanded(
                child: SemesterMatrixView(
                  presenceService: _FakePresenceService([
                    _teoriCourse(),
                    // A long course name that wraps to two lines.
                    _praktikumCourse(),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No RenderFlex overflow was thrown (widget tests fail on one), and the
    // recap column ends inside the viewport instead of being clipped.
    final recap = tester.getRect(find.text('8/16 hadir'));
    expect(recap.right, lessThanOrEqualTo(1280));
    final progress = tester.getRect(find.byType(LinearProgressIndicator).first);
    expect(progress.right, lessThanOrEqualTo(1280));
  });
}
