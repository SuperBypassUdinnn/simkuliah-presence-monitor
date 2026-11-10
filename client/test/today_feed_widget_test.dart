import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/views/widgets/active_lecture_card.dart';
import 'package:simkuliah_client/models/meeting_model.dart';
import 'package:simkuliah_client/services/presence_service.dart';

/// PresenceService test double that records calls instead of touching the
/// network; the Supabase client is never reached because every method that
/// the card exercises is overridden.
class _RecordingPresenceService extends PresenceService {
  final List<String> calls = [];

  @override
  Future<void> submitOverride({
    required int meetingId,
    required String overrideType,
    String note = '',
  }) async {
    calls.add('submit:$meetingId:$overrideType');
  }

  @override
  Future<void> clearOverride({required int meetingId}) async {
    calls.add('clear:$meetingId');
  }
}

void main() {
  testWidgets(
    'ActiveLectureCard displays Lakukan Presensi when open and allowed',
    (tester) async {
      final meeting = MeetingModel(
        id: 1,
        courseName: 'Grafika Komputer',
        meetingNumber: 7,
        isPresenceOpen: true,
        deadlineAt: DateTime.now().add(const Duration(minutes: 15)),
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

      expect(find.text('Lakukan Presensi'), findsOneWidget);
      expect(find.text('Izin'), findsOneWidget);
      expect(find.text('Sakit'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the selected override chip cancels it after confirmation',
    (tester) async {
      final service = _RecordingPresenceService();
      final meeting = MeetingModel(
        id: 5,
        courseName: 'Grafika Komputer',
        meetingNumber: 7,
        isPresenceOpen: false,
        localOverride: {'override_type': 'izin'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveLectureCard(meeting: meeting, presenceService: service),
          ),
        ),
      );

      // The active chip is Izin; tapping it once more asks for confirmation
      // and then clears the override.
      await tester.tap(find.text('Izin'));
      await tester.pumpAndSettle();
      expect(find.text('Batalkan Keterangan Mandiri?'), findsOneWidget);

      await tester.tap(find.text('Konfirmasi'));
      // Manual pumps: pumpAndSettle would fast-forward through the toast's
      // own countdown timer and dismiss the notification before the assert.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.calls, ['clear:5']);
      expect(find.text('Keterangan Dibatalkan'), findsOneWidget);
    },
  );
}
