// client/test/schedule_customization_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/models/schedule_customization_model.dart';
import 'package:simkuliah_client/models/user_preferences_model.dart';

void main() {
  test('ScheduleCustomizationModel round-trip json serialization', () {
    final model = ScheduleCustomizationModel(
      id: 1,
      scheduleId: 10,
      meetingId: 5,
      timeOffsetMinutes: 15,
      customDayOfWeek: 3,
      customStartTime: '10:00:00',
      customEndTime: '11:40:00',
      autoPresenceEnabled: true,
      reminderLeadMinutes: 20,
    );
    final json = model.toJson();
    final parsed = ScheduleCustomizationModel.fromJson(json);

    expect(parsed.id, 1);
    expect(parsed.scheduleId, 10);
    expect(parsed.meetingId, 5);
    expect(parsed.timeOffsetMinutes, 15);
    expect(parsed.customDayOfWeek, 3);
    expect(parsed.customStartTime, '10:00:00');
    expect(parsed.customEndTime, '11:40:00');
    expect(parsed.autoPresenceEnabled, true);
    expect(parsed.reminderLeadMinutes, 20);
  });

  test('UserPreferencesModel round-trip json serialization', () {
    final prefs = UserPreferencesModel(
      id: 2,
      userId: 'default_user',
      defaultReminderMinutes: 30,
    );
    final json = prefs.toJson();
    final parsed = UserPreferencesModel.fromJson(json);

    expect(parsed.id, 2);
    expect(parsed.userId, 'default_user');
    expect(parsed.defaultReminderMinutes, 30);
  });
}
