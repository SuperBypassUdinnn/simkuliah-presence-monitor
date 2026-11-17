// client/test/schedule_customization_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/views/widgets/schedule_customization_dialog.dart';

void main() {
  testWidgets('renders relative offset and auto-presence controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScheduleCustomizationDialog(
            courseName: 'Grafika Komputer',
            courseCode: 'INF201',
            scheduleId: 1,
            meetingNumber: 1,
          ),
        ),
      ),
    );

    expect(find.text('Sesuaikan Jadwal & Automasi'), findsOneWidget);
    expect(find.text('Presensi Otomatis (Auto-Absen)'), findsOneWidget);
    expect(find.text('Relatif'), findsOneWidget);
    expect(find.text('Pindah Jadwal'), findsOneWidget);
  });
}
