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

  const ScheduleModel({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.classGroup,
    required this.room,
    required this.startTime,
    required this.endTime,
    required this.lecturerName,
  });

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    return ScheduleModel(
      id: json['id'] as int,
      courseCode: json['course_code'] as String,
      courseName: json['course_name'] as String,
      classGroup: json['class_group'] as String,
      room: json['room'] as String,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      lecturerName: json['lecturer_name'] as String,
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
