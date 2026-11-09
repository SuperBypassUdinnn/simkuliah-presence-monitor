import 'meeting_model.dart';

/// A course schedule row matching the database `schedules` table.
///
/// Columns: id, course_code, course_name, class_group, room, start_time,
/// end_time, lecturer_name.
class ScheduleModel {
  final int id;
  final String courseCode;
  final String courseName;
  final String classGroup;
  final String room;
  final String startTime;
  final String endTime;
  final String lecturerName;
  final List<MeetingModel> meetings;

  const ScheduleModel({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.classGroup,
    required this.room,
    required this.startTime,
    required this.endTime,
    required this.lecturerName,
    this.meetings = const [],
  });

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    final parentCourseName = json['course_name'] as String? ?? '';
    final parentCourseCode = json['course_code'] as String? ?? '';
    final parentClassGroup = json['class_group'] as String? ?? '';
    final parentLecturer = json['lecturer_name'] as String? ?? '';
    final parentRoom = json['room'] as String? ?? '';
    final parentStartTime = json['start_time'] as String? ?? '';
    final parentEndTime = json['end_time'] as String? ?? '';

    List<MeetingModel> parsedMeetings = [];
    if (json['meetings'] != null && json['meetings'] is List) {
      parsedMeetings = (json['meetings'] as List).map((m) {
        final mMap = Map<String, dynamic>.from(m as Map);
        mMap.putIfAbsent('course_name', () => parentCourseName);
        mMap.putIfAbsent('course_code', () => parentCourseCode);
        mMap.putIfAbsent('class_group', () => parentClassGroup);
        mMap.putIfAbsent('lecturer_name', () => parentLecturer);
        mMap.putIfAbsent('room', () => parentRoom);
        mMap.putIfAbsent('start_time', () => parentStartTime);
        mMap.putIfAbsent('end_time', () => parentEndTime);
        return MeetingModel.fromJson(mMap);
      }).toList();
      parsedMeetings.sort((a, b) => a.meetingNumber.compareTo(b.meetingNumber));
    }

    return ScheduleModel(
      id: json['id'] as int,
      courseCode: parentCourseCode,
      courseName: parentCourseName,
      classGroup: parentClassGroup,
      room: parentRoom,
      startTime: parentStartTime,
      endTime: parentEndTime,
      lecturerName: parentLecturer,
      meetings: parsedMeetings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'course_code': courseCode,
      'course_name': courseName,
      'class_group': classGroup,
      'room': room,
      'start_time': startTime,
      'end_time': endTime,
      'lecturer_name': lecturerName,
    };
  }
}
