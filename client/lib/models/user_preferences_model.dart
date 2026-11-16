/// Purpose: Model representing global user preferences for notification lead times and defaults.
/// Data & Logic Flow: Maps to the Supabase `user_preferences` table rows, supporting JSON serialization and immutability.
/// Key Components: UserPreferencesModel

class UserPreferencesModel {
  final int? id;
  final String userId;
  final int defaultReminderMinutes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserPreferencesModel({
    this.id,
    this.userId = 'default_user',
    this.defaultReminderMinutes = 15,
    this.createdAt,
    this.updatedAt,
  });

  factory UserPreferencesModel.fromJson(Map<String, dynamic> json) {
    return UserPreferencesModel(
      id: json['id'] as int?,
      userId: json['user_id'] as String? ?? 'default_user',
      defaultReminderMinutes: json['default_reminder_minutes'] as int? ?? 15,
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
      'user_id': userId,
      'default_reminder_minutes': defaultReminderMinutes,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  UserPreferencesModel copyWith({
    int? id,
    String? userId,
    int? defaultReminderMinutes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserPreferencesModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      defaultReminderMinutes:
          defaultReminderMinutes ?? this.defaultReminderMinutes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
