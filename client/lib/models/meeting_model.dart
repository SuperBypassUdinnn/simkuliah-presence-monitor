/// Purpose: Course meeting data model matching database schema.
/// Data & Logic Flow: Deserializes meeting records and computes presence status with overrides.
/// Key Components: MeetingModel
class MeetingModel {
  final int id;
  final String courseName;
  final int meetingNumber;
  final String meetingDate;
  final String simkuliahStatus;
  final Map<String, dynamic>? localOverride;
  final bool isPresenceOpen;
  final DateTime? deadlineAt;

  const MeetingModel({
    required this.id,
    this.courseName = 'Mata Kuliah',
    required this.meetingNumber,
    this.meetingDate = '',
    this.simkuliahStatus = 'Pending',
    this.localOverride,
    required this.isPresenceOpen,
    this.deadlineAt,
  });

  factory MeetingModel.fromJson(Map<String, dynamic> json) {
    return MeetingModel(
      id: json['id'] as int,
      courseName: json['course_name'] as String? ?? 'Mata Kuliah',
      meetingNumber: json['meeting_number'] as int,
      meetingDate: json['meeting_date'] as String? ?? '',
      simkuliahStatus: json['simkuliah_status'] as String? ?? 'Pending',
      localOverride: json['local_override'] as Map<String, dynamic>?,
      isPresenceOpen: json['is_presence_open'] as bool? ?? false,
      deadlineAt: json['deadline_at'] == null
          ? null
          : DateTime.tryParse(json['deadline_at'] as String),
    );
  }

  /// True when a local override is present for this meeting.
  bool get isOverridden => localOverride != null;

  /// Effective presence status for display.
  ///
  /// When a local override exists, returns the capitalized override type
  /// ('Izin', 'Sakit', 'Alpa'). Otherwise returns the capitalized
  /// `simkuliah_status` ('Hadir', 'Tidak Hadir', 'Pending').
  String get effectiveStatus {
    final overrideType = localOverride?['override_type'] as String?;
    if (overrideType != null && overrideType.isNotEmpty) {
      return _capitalize(overrideType);
    }
    return _capitalize(simkuliahStatus);
  }

  static String _capitalize(String value) {
    return value
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'course_name': courseName,
      'meeting_number': meetingNumber,
      'meeting_date': meetingDate,
      'simkuliah_status': simkuliahStatus,
      'local_override': localOverride,
      'is_presence_open': isPresenceOpen,
      'deadline_at': deadlineAt?.toIso8601String(),
    };
  }
}
