// client/test/settings_automation_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/models/schedule_customization_model.dart';
import 'package:simkuliah_client/models/schedule_model.dart';
import 'package:simkuliah_client/models/user_preferences_model.dart';
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

Widget _buildView({
  List<ScheduleCustomizationModel> customizations = const [],
}) {
  return MaterialApp(
    home: SettingsAutomationView(
      initialSchedules: const [_schedule],
      initialCustomizations: customizations,
      initialPreferences: const UserPreferencesModel(
        defaultReminderMinutes: 15,
      ),
    ),
  );
}

void main() {
  testWidgets('renders global reminder and the course card', (tester) async {
    await tester.pumpWidget(_buildView());
    await tester.pumpAndSettle();

    expect(find.text('Pengaturan & Automasi'), findsOneWidget);
    expect(find.text('Pengingat Masuk Kuliah (Global)'), findsOneWidget);
    expect(find.text('Grafika Komputer'), findsOneWidget);
    expect(find.text('Presensi Otomatis (Semua Pertemuan)'), findsOneWidget);
    // Official portal window is trimmed to HH:mm.
    expect(find.textContaining('08:00 - 09:40 WIB'), findsOneWidget);
    // Per-course reminder override defaults to the global value.
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
}
