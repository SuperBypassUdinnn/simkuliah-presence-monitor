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

  test('MeetingModel prefers the meeting-level lecturer over the schedule', () {
    final meeting = MeetingModel.fromJson({
      'id': 20,
      'meeting_number': 12,
      'lecturer_name': 'Fathia Sabrina, S.T., M.Inf.Tech',
      'schedules': {
        'course_name': 'Penelusuran Informasi',
        'course_code': 'SINF6045',
        'lecturer_name': 'Prof. Dr. Taufik Fuadi Abidin, S.Si., M.Tech',
      },
    });
    expect(meeting.lecturerName, 'Fathia Sabrina, S.T., M.Inf.Tech');
  });

  test(
    'MeetingModel falls back to the schedule lecturer when meeting has none',
    () {
      final meeting = MeetingModel.fromJson({
        'id': 21,
        'meeting_number': 3,
        'schedules': {
          'course_name': 'Penelusuran Informasi',
          'lecturer_name': 'Prof. Dr. Taufik Fuadi Abidin, S.Si., M.Tech',
        },
      });
      expect(
        meeting.lecturerName,
        'Prof. Dr. Taufik Fuadi Abidin, S.Si., M.Tech',
      );
    },
  );

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
