/// Purpose: Pre-release stress tests exercising the client's hot paths under load.
/// Data & Logic Flow: Hammers the refresh-bus/epoch-guard loop, the matrix detail dialog open-close cycle and its async override flow, the auto-absen dialog toggle/bulk storm, the settings filter churn, and a 50x16 matrix build; every test asserts stability (no exceptions, consistent final state) rather than timing.
/// Key Components: stress suite
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/core/refresh_bus.dart';
import 'package:simkuliah_client/models/meeting_model.dart';
import 'package:simkuliah_client/models/schedule_customization_model.dart';
import 'package:simkuliah_client/models/schedule_model.dart';
import 'package:simkuliah_client/services/presence_service.dart';
import 'package:simkuliah_client/views/semester_matrix_view.dart';
import 'package:simkuliah_client/views/settings_automation_view.dart';

ScheduleModel _course(
  int id,
  String name, {
  int meetingCount = 16,
  bool dated = true,
}) {
  return ScheduleModel(
    id: id,
    courseCode: 'KODE$id',
    courseName: name,
    classGroup: 'A',
    room: 'R.$id',
    startTime: '08:00:00',
    endTime: '09:40:00',
    lecturerName: 'Dosen $id',
    meetings: [
      for (var n = 1; n <= meetingCount; n++)
        MeetingModel(
          id: id * 100 + n,
          courseName: name,
          startTime: '08:00:00',
          endTime: '09:40:00',
          meetingNumber: n,
          meetingDate: dated
              ? '2026-11-${(n % 28 + 1).toString().padLeft(2, '0')}'
              : '',
          simkuliahStatus: n.isEven ? 'hadir' : 'pending',
          isPresenceOpen: false,
        ),
    ],
  );
}

class _CountingMatrixService extends PresenceService {
  int matrixFetches = 0;

  final List<ScheduleModel> courses;

  _CountingMatrixService(this.courses);

  @override
  Future<List<ScheduleModel>> fetchSemesterMatrix() async {
    matrixFetches++;
    return courses;
  }

  @override
  Future<void> submitOverride({
    required int meetingId,
    required String overrideType,
    String note = '',
  }) async {}

  @override
  Future<void> clearOverride({required int meetingId}) async {}
}

class _RecordingAutoPresenceService extends PresenceService {
  final Map<int, bool> calls = {};
  int saveCount = 0;

  @override
  Future<ScheduleCustomizationModel> saveMeetingAutoPresence({
    required int scheduleId,
    required int meetingId,
    required bool enabled,
  }) async {
    saveCount++;
    calls[meetingId] = enabled;
    return ScheduleCustomizationModel(
      id: meetingId,
      scheduleId: scheduleId,
      meetingId: meetingId,
      autoPresenceEnabled: enabled,
    );
  }
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('RefreshBus storm (200 forced events) keeps the matrix stable', (
    tester,
  ) async {
    final service = _CountingMatrixService([
      _course(1, 'Matriks Storm A'),
      _course(2, 'Matriks Storm B', meetingCount: 12),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SemesterMatrixView(presenceService: service)),
      ),
    );
    await tester.pumpAndSettle();
    final fetchesAfterLoad = service.matrixFetches;

    // 200 synchronous forced refresh events: the epoch guard must keep the
    // view consistent and no late-settling future may corrupt state.
    for (var i = 0; i < 200; i++) {
      RefreshBus.instance.requestRefresh();
    }
    await tester.pumpAndSettle();

    expect(service.matrixFetches, greaterThan(fetchesAfterLoad));
    expect(find.text('Matriks Storm A'), findsOneWidget);
    expect(find.text('Matriks Storm B'), findsOneWidget);
    expect(find.text('8/16 hadir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid dialog open/close cycles stay correct', (tester) async {
    _useTallViewport(tester);
    final service = _CountingMatrixService([_course(1, 'Dialog Cycle')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SemesterMatrixView(presenceService: service)),
      ),
    );
    await tester.pumpAndSettle();

    for (var cycle = 0; cycle < 15; cycle++) {
      await tester.tap(find.byType(MeetingGridTile).first);
      await tester.pumpAndSettle();
      expect(find.text('Pertemuan 1'), findsOneWidget);
      expect(find.text('Hari'), findsOneWidget);

      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('Pertemuan 1'), findsNothing);
    }

    // One more open must still render complete, correct content: the course
    // name appears both in the matrix row and in the dialog.
    await tester.tap(find.byType(MeetingGridTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Dialog Cycle'), findsNWidgets(2));
    expect(find.textContaining('08:00 - 09:40 WIB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('override chip confirm cycles survive rapid repetition', (
    tester,
  ) async {
    _useTallViewport(tester);
    final service = _CountingMatrixService([_course(1, 'Override Storm')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SemesterMatrixView(presenceService: service)),
      ),
    );
    await tester.pumpAndSettle();

    for (var cycle = 0; cycle < 10; cycle++) {
      await tester.tap(find.byType(MeetingGridTile).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Izin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Konfirmasi'));
      await tester.pumpAndSettle();

      // The detail dialog auto-closes after a successful submit.
      expect(find.text('Keterangan Mandiri:'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('50-course x 16-meeting matrix builds and scrolls clean', (
    tester,
  ) async {
    _useTallViewport(tester);
    final courses = [
      for (var i = 1; i <= 50; i++) _course(i, 'Kursus Besar $i'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SemesterMatrixView(
            presenceService: _CountingMatrixService(courses),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kursus Besar 1'), findsOneWidget);
    expect(find.text('Kursus Besar 50'), findsOneWidget);
    // Every real meeting tile of the first course renders.
    expect(find.byType(MeetingGridTile), findsNWidgets(50 * 16));

    // Scroll to the last row; its title must be present.
    await tester.scrollUntilVisible(
      find.text('Kursus Besar 50'),
      800,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings filter/search churn stays consistent', (tester) async {
    _useTallViewport(tester);
    final schedules = [
      const ScheduleModel(
        id: 1,
        courseCode: 'T1',
        courseName: 'Kecerdasan Artifisial',
        classGroup: 'A',
        room: 'R1',
        startTime: '08:00:00',
        endTime: '09:40:00',
        lecturerName: 'Dosen',
      ),
      const ScheduleModel(
        id: 2,
        courseCode: 'P1',
        courseName: 'PRAKTIKUM JARINGAN',
        classGroup: 'B',
        room: 'R2',
        startTime: '10:00:00',
        endTime: '11:40:00',
        lecturerName: 'Dosen',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: SettingsAutomationView(initialSchedules: schedules)),
    );
    await tester.pumpAndSettle();

    // Rapid search churn.
    for (var i = 0; i < 15; i++) {
      await tester.enterText(find.byType(TextField), 'jaringan');
      await tester.enterText(find.byType(TextField), '');
    }
    await tester.pumpAndSettle();
    expect(find.text('Kecerdasan Artifisial'), findsOneWidget);
    expect(find.text('PRAKTIKUM JARINGAN'), findsOneWidget);

    // Rapid filter chip churn.
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('Praktikum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teori'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Semua'));
    await tester.pumpAndSettle();
    expect(find.text('Kecerdasan Artifisial'), findsOneWidget);
    expect(find.text('PRAKTIKUM JARINGAN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-absen dialog survives toggle and bulk storms', (
    tester,
  ) async {
    _useTallViewport(tester);
    final service = _RecordingAutoPresenceService();
    final schedule = ScheduleModel(
      id: 1,
      courseCode: 'P1',
      courseName: 'PRAKTIKUM STORM',
      classGroup: 'A',
      room: 'R',
      startTime: '08:00:00',
      endTime: '09:40:00',
      lecturerName: 'Dosen',
      meetings: [
        // 4 past (locked), 8 future (editable).
        for (var n = 1; n <= 4; n++)
          MeetingModel(
            id: n,
            courseName: 'PRAKTIKUM STORM',
            meetingNumber: n,
            meetingDate: '2026-01-0$n',
            simkuliahStatus: 'pending',
            isPresenceOpen: false,
          ),
        for (var n = 5; n <= 12; n++)
          MeetingModel(
            id: n,
            courseName: 'PRAKTIKUM STORM',
            meetingNumber: n,
            meetingDate: '2030-02-${(n - 4).toString().padLeft(2, '0')}',
            simkuliahStatus: 'pending',
            isPresenceOpen: false,
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsAutomationView(
          initialSchedules: [schedule],
          presenceService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pilih Pertemuan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 sudah lewat'), findsOneWidget);

    // Rapid individual toggles on the editable meetings (even count so the
    // bulk button label ends up back at "Pilih Semua").
    for (var round = 0; round < 4; round++) {
      for (var n = 5; n <= 12; n++) {
        await tester.tap(find.text('Pertemuan $n'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }
    // Every future meeting received toggles; past ones never did.
    for (var n = 1; n <= 4; n++) {
      expect(service.calls.containsKey(n), isFalse);
    }
    for (var n = 5; n <= 12; n++) {
      expect(service.calls.containsKey(n), isTrue);
    }

    // Bulk storms keep the lock invariant.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Pilih Semua'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batalkan Semua'));
      await tester.pumpAndSettle();
    }
    // Past meeting switches remain disabled throughout.
    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches.length, 12);
    for (var i = 0; i < 4; i++) {
      expect(switches[i].onChanged, isNull);
    }
    expect(tester.takeException(), isNull);
  });
}
