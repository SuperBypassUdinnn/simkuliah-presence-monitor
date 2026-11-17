// client/test/settings_automation_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/models/schedule_customization_model.dart';
import 'package:simkuliah_client/models/schedule_model.dart';
import 'package:simkuliah_client/models/user_preferences_model.dart';
import 'package:simkuliah_client/views/settings_automation_view.dart';

void main() {
  testWidgets(
    'SettingsAutomationView renders global reminder and course schedule section',
    (tester) async {
      const schedule = ScheduleModel(
        id: 1,
        courseCode: 'INF201',
        courseName: 'Grafika Komputer',
        classGroup: 'A',
        room: 'Lab 1',
        startTime: '08:00:00',
        endTime: '09:40:00',
        lecturerName: 'Dr. X',
      );
      const customization = ScheduleCustomizationModel(
        id: 1,
        scheduleId: 1,
        autoPresenceEnabled: true,
        timeOffsetMinutes: 15,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsAutomationView(
            initialSchedules: [schedule],
            initialCustomizations: [customization],
            initialPreferences: UserPreferencesModel(
              defaultReminderMinutes: 15,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pengaturan & Automasi'), findsOneWidget);
      expect(find.text('Pengingat Masuk Kuliah (Global)'), findsOneWidget);
      expect(find.text('15m'), findsOneWidget);
      expect(find.text('Grafika Komputer'), findsOneWidget);
      expect(find.text('Presensi Otomatis (Semua Pertemuan)'), findsOneWidget);
    },
  );
}
