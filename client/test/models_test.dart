import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/models/meeting_model.dart';

void main() {
  test('MeetingModel parses JSON and computes effective status correctly', () {
    final json = {
      'id': 1,
      'meeting_number': 7,
      'meeting_date': '2026-11-09',
      'simkuliah_status': 'pending',
      'local_override': {'override_type': 'izin'},
    };
    final meeting = MeetingModel.fromJson(json);
    expect(meeting.effectiveStatus, 'Izin');
    expect(meeting.isOverridden, isTrue);
  });

  test('MeetingModel ensures Hadir supersedes local override', () {
    final json = {
      'id': 2,
      'meeting_number': 8,
      'meeting_date': '2026-11-09',
      'simkuliah_status': 'hadir',
      'local_override': {'override_type': 'alpa'},
    };
    final meeting = MeetingModel.fromJson(json);
    expect(meeting.isAttended, isTrue);
    expect(meeting.effectiveStatus, 'Hadir');
    expect(meeting.isOverridden, isFalse);
  });

  test(
    'MeetingModel formats tidak_hadir as Tidak Hadir without underscore',
    () {
      final json = {
        'id': 3,
        'meeting_number': 9,
        'meeting_date': '2026-11-09',
        'simkuliah_status': 'tidak_hadir',
      };
      final meeting = MeetingModel.fromJson(json);
      expect(meeting.effectiveStatus, 'Tidak Hadir');
    },
  );

  test('MeetingModel formats new override types without underscore', () {
    final lupaAbsen = MeetingModel.fromJson({
      'id': 4,
      'meeting_number': 10,
      'meeting_date': '2026-11-09',
      'simkuliah_status': 'pending',
      'local_override': {'override_type': 'lupa_absen'},
    });
    final dosenTidakAbsen = MeetingModel.fromJson({
      'id': 5,
      'meeting_number': 11,
      'meeting_date': '2026-11-09',
      'simkuliah_status': 'pending',
      'local_override': {'override_type': 'dosen_tidak_absen'},
    });

    expect(lupaAbsen.effectiveStatus, 'Lupa Absen');
    expect(dosenTidakAbsen.effectiveStatus, 'Dosen Tidak Absen');
  });
}
