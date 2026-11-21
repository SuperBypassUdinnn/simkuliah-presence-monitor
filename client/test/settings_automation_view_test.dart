// client/test/settings_automation_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/models/meeting_model.dart';
import 'package:simkuliah_client/models/schedule_customization_model.dart';
import 'package:simkuliah_client/models/schedule_model.dart';
import 'package:simkuliah_client/models/user_preferences_model.dart';
import 'package:simkuliah_client/services/presence_service.dart';
import 'package:simkuliah_client/views/settings_automation_view.dart';

const _schedule = ScheduleModel(
  id: 1,
  courseCode: 'INF201',
  courseName: 'Grafika Komputer',
  classGroup: 'A',
  room: 'Lab 1',
  startTime: '08:00:00',
  endTime: '09:40:00',
  lecturerName: 'Dr. X',
);

const _teoriCourse = ScheduleModel(
  id: 2,
  courseCode: 'SINF3031',
  courseName: 'Kecerdasan Artifisial',
  classGroup: 'C',
  room: 'D.3.02',
  startTime: '10:00:00',
  endTime: '11:40:00',
  lecturerName: 'Dr. Y',
);

const _praktikumCourse = ScheduleModel(
  id: 3,
  courseCode: 'SIF5001',
  courseName: 'PRAKTIKUM KEAMANAN SIBER',
  classGroup: 'A',
  room: 'L.1.01',
  startTime: '08:00:00',
  endTime: '09:40:00',
  lecturerName: 'Dr. Z',
);

MeetingModel _meetingWithDate(int id, int number, String date) {
  return MeetingModel(
    id: id,
    courseName: 'PRAKTIKUM KEAMANAN SIBER',
    meetingNumber: number,
    meetingDate: date,
    simkuliahStatus: 'pending',
    isPresenceOpen: false,
  );
}

Widget _buildView({
  List<ScheduleModel> schedules = const [_schedule],
  List<ScheduleCustomizationModel> customizations = const [],
  PresenceService? presenceService,
}) {
  return MaterialApp(
    home: SettingsAutomationView(
      presenceService: presenceService,
      initialSchedules: schedules,
      initialCustomizations: customizations,
      initialPreferences: const UserPreferencesModel(
        defaultReminderMinutes: 15,
      ),
    ),
  );
}

class _FakePresenceService extends PresenceService {
  ScheduleCustomizationModel? saved;

  @override
  Future<ScheduleCustomizationModel> saveCustomization(
    ScheduleCustomizationModel customization,
  ) async {
    saved = customization;
    return customization.copyWith(id: customization.id ?? 10);
  }
}

class _FakeAutoPresenceService extends PresenceService {
  final Map<int, bool> autoPresenceCalls = {};

  @override
  Future<ScheduleCustomizationModel> saveMeetingAutoPresence({
    required int scheduleId,
    required int meetingId,
    required bool enabled,
  }) async {
    autoPresenceCalls[meetingId] = enabled;
    return ScheduleCustomizationModel(
      id: meetingId,
      scheduleId: scheduleId,
      meetingId: meetingId,
      autoPresenceEnabled: enabled,
    );
  }
}

/// The course list lives in a lazily-built ListView; on the default 800x600
/// test viewport the cards below the fold are never built, so finder-based
/// assertions miss them. Tests that exercise the list or controls pushed
/// down by the search field use a tall viewport instead.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('renders global reminder and the course card', (tester) async {
    await tester.pumpWidget(_buildView());
    await tester.pumpAndSettle();

    expect(find.text('Pengaturan & Automasi'), findsOneWidget);
    expect(find.text('Pengingat Masuk Kuliah (Global)'), findsOneWidget);
    expect(find.text('Grafika Komputer'), findsOneWidget);
    // Per-meeting auto-presence button is shown instead of the old global switch.
    expect(find.text('Pilih Pertemuan'), findsOneWidget);
    // Schedule has no meeting rows loaded, so the status text reflects that.
    expect(find.text('Belum ada data pertemuan'), findsOneWidget);
    // Official portal window is trimmed to HH:mm.
    expect(find.textContaining('08:00 - 09:40 WIB'), findsOneWidget);
    // Per-course reminder override defaults to global — lead-time chips visible.
    expect(find.text('Ikuti Global'), findsOneWidget);
  });

  testWidgets('relative offset customization shows offset chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildView(
        customizations: const [
          ScheduleCustomizationModel(
            id: 1,
            scheduleId: 1,
            autoPresenceEnabled: true,
            timeOffsetMinutes: 15,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Penyesuaian Waktu'), findsOneWidget);
    expect(find.text('+15m'), findsOneWidget);
    expect(find.text('+120m'), findsOneWidget);
    // Absolute controls stay hidden while relative mode is active.
    expect(find.textContaining('Mulai '), findsNothing);
  });

  testWidgets('absolute customization shows day and time controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildView(
        customizations: const [
          ScheduleCustomizationModel(
            id: 2,
            scheduleId: 1,
            customDayOfWeek: 3,
            customStartTime: '10:00:00',
            customEndTime: '11:40:00',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rabu'), findsOneWidget);
    expect(find.text('Mulai 10:00'), findsOneWidget);
    expect(find.text('Selesai 11:40'), findsOneWidget);
  });

  testWidgets('per-course reminder override chip reflects the stored value', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildView(
        customizations: const [
          ScheduleCustomizationModel(
            id: 3,
            scheduleId: 1,
            reminderLeadMinutes: 30,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected)
        .toList();
    expect(chips, isNotEmpty);
    expect(
      chips.any((chip) => (chip.label as Text).data == '30m'),
      isTrue,
      reason: 'the 30m override chip must be selected',
    );
  });

  testWidgets(
    'switching to Relatif from official sets default +15m and shows chips',
    (tester) async {
      _useTallViewport(tester);
      final fakeService = _FakePresenceService();
      await tester.pumpWidget(
        _buildView(presenceService: fakeService, customizations: const []),
      );
      await tester.pumpAndSettle();

      // Initially in official mode: relative chips are hidden.
      expect(find.text('+15m'), findsNothing);

      // Tap "Relatif" segment.
      await tester.tap(find.text('Relatif'));
      await tester.pumpAndSettle();

      // Customization should have been saved with timeOffsetMinutes: 15.
      expect(fakeService.saved?.timeOffsetMinutes, 15);
      // Relative chips should now be visible and +15m selected.
      expect(find.text('+15m'), findsOneWidget);
      expect(find.text('+30m'), findsOneWidget);
      final selectedChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '+15m'),
      );
      expect(selectedChip.selected, isTrue);

      // Tapping another chip (e.g. +30m) updates offset to 30.
      await tester.tap(find.text('+30m'));
      await tester.pumpAndSettle();
      expect(fakeService.saved?.timeOffsetMinutes, 30);

      // Tapping "Asli" resets offset to 0 and hides relative chips.
      await tester.tap(find.text('Asli'));
      await tester.pumpAndSettle();
      expect(fakeService.saved?.timeOffsetMinutes, 0);
      expect(find.text('+15m'), findsNothing);
    },
  );

  testWidgets('praktikum/teori filter narrows the course list', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      _buildView(schedules: const [_teoriCourse, _praktikumCourse]),
    );
    await tester.pumpAndSettle();

    // Both courses are visible with the default "Semua" filter.
    expect(find.text('Kecerdasan Artifisial'), findsOneWidget);
    expect(find.text('PRAKTIKUM KEAMANAN SIBER'), findsOneWidget);

    await tester.tap(find.text('Praktikum'));
    await tester.pumpAndSettle();
    expect(find.text('PRAKTIKUM KEAMANAN SIBER'), findsOneWidget);
    expect(find.text('Kecerdasan Artifisial'), findsNothing);

    await tester.tap(find.text('Teori'));
    await tester.pumpAndSettle();
    expect(find.text('Kecerdasan Artifisial'), findsOneWidget);
    expect(find.text('PRAKTIKUM KEAMANAN SIBER'), findsNothing);

    await tester.tap(find.text('Semua'));
    await tester.pumpAndSettle();
    expect(find.text('Kecerdasan Artifisial'), findsOneWidget);
    expect(find.text('PRAKTIKUM KEAMANAN SIBER'), findsOneWidget);
  });

  testWidgets('course search narrows the list and can be cleared', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      _buildView(schedules: const [_teoriCourse, _praktikumCourse]),
    );
    await tester.pumpAndSettle();

    // Case-insensitive name search.
    await tester.enterText(find.byType(TextField), 'keamanan');
    await tester.pumpAndSettle();
    expect(find.text('PRAKTIKUM KEAMANAN SIBER'), findsOneWidget);
    expect(find.text('Kecerdasan Artifisial'), findsNothing);

    // The suffix clear button restores the full list.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Kecerdasan Artifisial'), findsOneWidget);
    expect(find.text('PRAKTIKUM KEAMANAN SIBER'), findsOneWidget);
  });

  testWidgets(
    'auto-absen dialog locks past meetings and bulk-selects future only',
    (tester) async {
      _useTallViewport(tester);
      final fakeService = _FakeAutoPresenceService();
      final datedSchedule = ScheduleModel(
        id: 9,
        courseCode: 'SIF5001',
        courseName: 'PRAKTIKUM KEAMANAN SIBER',
        classGroup: 'A',
        room: 'L.1.01',
        startTime: '08:00:00',
        endTime: '09:40:00',
        lecturerName: 'Dr. Z',
        meetings: [
          _meetingWithDate(901, 1, '2026-01-05'),
          _meetingWithDate(902, 2, '2030-01-01'),
        ],
      );
      await tester.pumpWidget(
        _buildView(schedules: [datedSchedule], presenceService: fakeService),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pilih Pertemuan'));
      await tester.pumpAndSettle();

      // The past meeting carries the lock marker and a disabled switch.
      expect(find.textContaining('Sudah lewat'), findsOneWidget);
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches.length, 2);
      expect(switches[0].onChanged, isNull, reason: 'past meeting is locked');
      expect(
        switches[1].onChanged,
        isNotNull,
        reason: 'future meeting stays editable',
      );

      // "Pilih Semua" only enables the meeting that has not happened yet.
      await tester.tap(find.text('Pilih Semua'));
      await tester.pumpAndSettle();
      expect(fakeService.autoPresenceCalls, {902: true});
    },
  );
}
