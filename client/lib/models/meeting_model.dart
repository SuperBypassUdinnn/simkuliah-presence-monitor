/// Purpose: Course meeting data model matching database schema.
/// Data & Logic Flow: Deserializes meeting records and computes presence status with overrides.
/// Key Components: MeetingModel
class MeetingModel {
  final int id;
  final int? scheduleId;
  final String courseName;
  final String courseCode;
  final String classGroup;
  final String lecturerName;
  final String room;
  final String startTime;
  final String endTime;
  final int meetingNumber;
  final String meetingDate;
  final String simkuliahStatus;
  final Map<String, dynamic>? localOverride;
  final bool isPresenceOpen;
  final DateTime? deadlineAt;

  const MeetingModel({
    required this.id,
    this.scheduleId,
    this.courseName = 'Mata Kuliah',
    this.courseCode = '',
    this.classGroup = '',
    this.lecturerName = '',
    this.room = '',
    this.startTime = '',
    this.endTime = '',
    required this.meetingNumber,
    this.meetingDate = '',
    this.simkuliahStatus = 'Pending',
    this.localOverride,
    required this.isPresenceOpen,
    this.deadlineAt,
  });

  factory MeetingModel.fromJson(Map<String, dynamic> json) {
    String resolvedCourseName = 'Mata Kuliah';
    String resolvedCourseCode = '';
    String resolvedClassGroup = '';
    String resolvedLecturer = '';
    String resolvedRoom = '';
    String resolvedStartTime = '';
    String resolvedEndTime = '';

    if (json['schedules'] != null && json['schedules'] is Map) {
      final s = json['schedules'] as Map<String, dynamic>;
      resolvedCourseName = s['course_name'] as String? ?? 'Mata Kuliah';
      resolvedCourseCode = s['course_code'] as String? ?? '';
      resolvedClassGroup = s['class_group'] as String? ?? '';
      resolvedLecturer = s['lecturer_name'] as String? ?? '';
      resolvedRoom = s['room'] as String? ?? '';
      resolvedStartTime = s['start_time'] as String? ?? '';
      resolvedEndTime = s['end_time'] as String? ?? '';
    } else {
      resolvedCourseName = json['course_name'] as String? ?? 'Mata Kuliah';
      resolvedCourseCode = json['course_code'] as String? ?? '';
      resolvedClassGroup = json['class_group'] as String? ?? '';
      resolvedLecturer = json['lecturer_name'] as String? ?? '';
      resolvedRoom = json['room'] as String? ?? '';
      resolvedStartTime = json['start_time'] as String? ?? '';
      resolvedEndTime = json['end_time'] as String? ?? '';
    }

    // Split-semester courses change lecturer per meeting; the meeting-level
    // value (synced from each Simkuliah matrix cell) wins when present.
    final meetingLecturer = json['lecturer_name'] as String?;
    if (meetingLecturer != null && meetingLecturer.isNotEmpty) {
      resolvedLecturer = meetingLecturer;
    }

    final status = (json['simkuliah_status'] as String? ?? 'Pending');
    final deadlineStr = json['deadline_at'] as String?;
    final deadline = deadlineStr != null
        ? DateTime.tryParse(deadlineStr)
        : null;

    final isPresenceOpen =
        json['is_presence_open'] as bool? ??
        (status.toLowerCase() == 'pending' &&
            deadline != null &&
            // A deadline in the past means the window already closed; the
            // stored deadline is never cleared, so bound it by time or the
            // card would claim "presensi sedang dibuka" forever.
            deadline.isAfter(DateTime.now()));

    Map<String, dynamic>? overrideData;
    if (json['local_override'] is Map<String, dynamic>) {
      overrideData = json['local_override'] as Map<String, dynamic>;
    } else if (json['local_overrides'] is Map<String, dynamic>) {
      overrideData = json['local_overrides'] as Map<String, dynamic>;
    } else if (json['local_overrides'] is List &&
        (json['local_overrides'] as List).isNotEmpty) {
      overrideData =
          (json['local_overrides'] as List).first as Map<String, dynamic>;
    }

    return MeetingModel(
      id: json['id'] as int,
      scheduleId: json['schedule_id'] as int?,
      courseName: resolvedCourseName,
      courseCode: resolvedCourseCode,
      classGroup: resolvedClassGroup,
      lecturerName: resolvedLecturer,
      room: resolvedRoom,
      startTime: resolvedStartTime,
      endTime: resolvedEndTime,
      meetingNumber: json['meeting_number'] as int,
      meetingDate: json['meeting_date'] as String? ?? '',
      simkuliahStatus: status,
      localOverride: overrideData,
      isPresenceOpen: isPresenceOpen,
      deadlineAt: deadline,
    );
  }

  /// `startTime` normalized for display: hours and minutes only (HH:mm).
  /// Falls back to the raw string when it carries no HH:MM segment.
  String get startTimeShort => _stripSeconds(startTime);

  /// `endTime` normalized for display: hours and minutes only (HH:mm).
  String get endTimeShort => _stripSeconds(endTime);

  /// Removes the seconds segment from a Simkuliah time-of-day string.
  static String _stripSeconds(String time) {
    final match = RegExp(r'(\d{2})[:.](\d{2})').firstMatch(time);
    if (match == null) return time;
    return '${match.group(1)}:${match.group(2)}';
  }

  /// True strictly when attendance is recorded as 'hadir' in Simkuliah.
  /// Presence status has absolute precedence over local overrides.
  bool get isAttended => simkuliahStatus.toLowerCase() == 'hadir';

  /// True when a local override is present AND meeting is not yet confirmed Hadir.
  bool get isOverridden => !isAttended && localOverride != null;

  /// Effective presence status for display.
  ///
  /// 'Hadir' always supersedes local overrides. When not Hadir and a local
  /// override exists, returns capitalized override type ('Izin', 'Sakit', 'Alpa').
  /// Otherwise returns capitalized `simkuliahStatus` ('Tidak Hadir', 'Pending').
  String get effectiveStatus {
    if (isAttended) {
      return 'Hadir';
    }
    final overrideType = localOverride?['override_type'] as String?;
    if (overrideType != null && overrideType.isNotEmpty) {
      return _capitalize(overrideType);
    }
    return _capitalize(simkuliahStatus);
  }

  /// Whether the current time is strictly within the scheduled lecture window.
  bool isWithinScheduleTime({DateTime? referenceTime}) {
    if (startTime.isEmpty || endTime.isEmpty) return false;
    final now = referenceTime ?? DateTime.now();
    final startMatch = RegExp(r'(\d{2})[:.](\d{2})').firstMatch(startTime);
    final endMatch = RegExp(r'(\d{2})[:.](\d{2})').firstMatch(endTime);
    if (startMatch == null || endMatch == null) return false;

    final sH = int.parse(startMatch.group(1)!);
    final sM = int.parse(startMatch.group(2)!);
    final eH = int.parse(endMatch.group(1)!);
    final eM = int.parse(endMatch.group(2)!);

    final start = DateTime(now.year, now.month, now.day, sH, sM);
    final end = DateTime(now.year, now.month, now.day, eH, eM);

    return (now.isAfter(start) || now.isAtSameMomentAs(start)) &&
        (now.isBefore(end) || now.isAtSameMomentAs(end));
  }

  /// Whether the scheduled lecture end time has passed today.
  bool isPastScheduleTime({DateTime? referenceTime}) {
    if (endTime.isEmpty) return false;
    final now = referenceTime ?? DateTime.now();
    final endMatch = RegExp(r'(\d{2})[:.](\d{2})').firstMatch(endTime);
    if (endMatch == null) return false;
    final eH = int.parse(endMatch.group(1)!);
    final eM = int.parse(endMatch.group(2)!);
    final end = DateTime(now.year, now.month, now.day, eH, eM);
    return now.isAfter(end);
  }

  /// Whether the scheduled lecture has not yet started today.
  bool isBeforeScheduleTime({DateTime? referenceTime}) {
    if (startTime.isEmpty) return false;
    final now = referenceTime ?? DateTime.now();
    final startMatch = RegExp(r'(\d{2})[:.](\d{2})').firstMatch(startTime);
    if (startMatch == null) return false;
    final sH = int.parse(startMatch.group(1)!);
    final sM = int.parse(startMatch.group(2)!);
    final start = DateTime(now.year, now.month, now.day, sH, sM);
    return now.isBefore(start);
  }

  static String _capitalize(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'schedule_id': scheduleId,
      'course_name': courseName,
      'course_code': courseCode,
      'class_group': classGroup,
      'lecturer_name': lecturerName,
      'room': room,
      'start_time': startTime,
      'end_time': endTime,
      'meeting_number': meetingNumber,
      'meeting_date': meetingDate,
      'simkuliah_status': simkuliahStatus,
      'is_presence_open': isPresenceOpen,
      'deadline_at': deadlineAt?.toIso8601String(),
    };
  }
}
