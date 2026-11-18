/// Purpose: Model representing schedule offset, custom timing, and auto-presence configurations.
/// Data & Logic Flow: Maps to the Supabase `schedule_customizations` table rows, supporting JSON serialization and immutability.
/// Key Components: ScheduleCustomizationModel

class ScheduleCustomizationModel {
  final int? id;
  final int scheduleId;
  final int? meetingId;
  final int timeOffsetMinutes;
  final int? customDayOfWeek;
  final String? customStartTime;
  final String? customEndTime;
  final bool autoPresenceEnabled;
  final int? reminderLeadMinutes;

  /// Per-course reminder override. NULL = inherit the global `reminderEnabled`
  /// setting from `user_preferences`. When explicitly set to true or false,
  /// it overrides the global flag for this course only.
  final bool? reminderEnabled;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ScheduleCustomizationModel({
    this.id,
    required this.scheduleId,
    this.meetingId,
    this.timeOffsetMinutes = 0,
    this.customDayOfWeek,
    this.customStartTime,
    this.customEndTime,
    this.autoPresenceEnabled = false,
    this.reminderLeadMinutes,
    this.reminderEnabled,
    this.createdAt,
    this.updatedAt,
  });

  factory ScheduleCustomizationModel.fromJson(Map<String, dynamic> json) {
    return ScheduleCustomizationModel(
      id: json['id'] as int?,
      scheduleId: json['schedule_id'] as int,
      meetingId: json['meeting_id'] as int?,
      timeOffsetMinutes: json['time_offset_minutes'] as int? ?? 0,
      customDayOfWeek: json['custom_day_of_week'] as int?,
      customStartTime: json['custom_start_time'] as String?,
      customEndTime: json['custom_end_time'] as String?,
      autoPresenceEnabled: json['auto_presence_enabled'] as bool? ?? false,
      reminderLeadMinutes: json['reminder_lead_minutes'] as int?,
      reminderEnabled: json['reminder_enabled'] as bool?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'schedule_id': scheduleId,
      'meeting_id': meetingId,
      'time_offset_minutes': timeOffsetMinutes,
      'custom_day_of_week': customDayOfWeek,
      'custom_start_time': customStartTime,
      'custom_end_time': customEndTime,
      'auto_presence_enabled': autoPresenceEnabled,
      'reminder_lead_minutes': reminderLeadMinutes,
      'reminder_enabled': reminderEnabled,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  ScheduleCustomizationModel copyWith({
    int? id,
    int? scheduleId,
    int? meetingId,
    int? timeOffsetMinutes,
    int? customDayOfWeek,
    String? customStartTime,
    String? customEndTime,
    bool? autoPresenceEnabled,
    int? reminderLeadMinutes,
    bool? reminderEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScheduleCustomizationModel(
      id: id ?? this.id,
      scheduleId: scheduleId ?? this.scheduleId,
      meetingId: meetingId ?? this.meetingId,
      timeOffsetMinutes: timeOffsetMinutes ?? this.timeOffsetMinutes,
      customDayOfWeek: customDayOfWeek ?? this.customDayOfWeek,
      customStartTime: customStartTime ?? this.customStartTime,
      customEndTime: customEndTime ?? this.customEndTime,
      autoPresenceEnabled: autoPresenceEnabled ?? this.autoPresenceEnabled,
      reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
