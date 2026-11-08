import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/models/meeting_model.dart';

void main() {
  test('MeetingModel parses JSON and computes effective status correctly', () {
    final json = {
      'id': 1,
      'meeting_number': 7,
      'meeting_date': '2026-11-09',
      'simkuliah_status': 'pending',
      'local_override': {'override_type': 'izin'}
    };
    final meeting = MeetingModel.fromJson(json);
    expect(meeting.effectiveStatus, 'Izin');
    expect(meeting.isOverridden, isTrue);
  });
}
