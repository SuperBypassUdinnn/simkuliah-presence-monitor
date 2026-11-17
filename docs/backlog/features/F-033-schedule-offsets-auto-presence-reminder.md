# Feature Log: F-033 Schedule Offsets, Auto-Presence, Class Reminders, and Action Buttons

- **Parent Plan**: [`.planning/04-hybrid-push-notifications.md`](../../../.planning/04-hybrid-push-notifications.md)
- **Target Issue**: Owner report & feature expansion (chat, 2026-11-16)
- **Status**: Completed
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

In real-world university settings, class schedules frequently diverge from official portal timetables (e.g. negotiated start times, postponed or moved meetings). When lecturers open presence during portal hours while students are outside class or unaware, the 30-minute attendance window is often missed.

Furthermore, on Android, interactive notification action buttons ("Presensi Sekarang", "Izin", "Sakit") were not handling background taps due to a missing `ActionBroadcastReceiver` in `AndroidManifest.xml`.

This feature delivers:
1. **Advance Class Reminders**: Pre-class notifications with customizable lead times (10m, 15m, 30m, or custom).
2. **Flexible Schedule Offsets**: Relative shifts (+/- minutes/hours) or absolute rescheduling (day of week + time), scoped per meeting or across an entire course schedule.
3. **Autonomous Presence Confirmation (Auto-Presence)**: Background submission of the verified 7-field AJAX presence confirmation upon window opening, dispatching `AUTO_CONFIRMED` ("Presensi Otomatis Berhasil") or `AUTO_PRESENCE_FAILED` with an urgent alert.
4. **Interactive Action Buttons Fix**: Native broadcast receiver registered in `AndroidManifest.xml` and immediate visual confirmation upon action execution.

## 2. Implementation Checklist

- [x] **Supabase Migration (`20261116000000_schedule_customizations.sql`)**:
  - `user_preferences` table for global default reminder lead times.
  - `schedule_customizations` table for offsets, absolute timing, and auto-presence flags.
- [x] **Database Repository Methods (`backend/app/core/database.py`)**:
  - `get_user_preferences`, `upsert_user_preferences`.
  - `get_schedule_customizations`, `upsert_schedule_customization`, `delete_schedule_customization`.
  - `resolve_effective_customization` prioritizing meeting-level over course-level overrides.
- [x] **State Machine & Notification Content (`backend/app/services/`)**:
  - Added `CLASS_REMINDER`, `AUTO_CONFIRMED`, `AUTO_PRESENCE_FAILED` to `NotificationLevel`.
  - Configured delivery priorities and titles/texts in `notification_content.py`.
- [x] **Adaptive Poller Automation & Interval Clamping (`backend/app/services/poller.py`)**:
  - Resolves effective schedules and clamps poll intervals for upcoming advance reminders.
  - Autonomously invokes `confirm_meeting_on_simkuliah` when auto-presence is active.
- [x] **Android Manifest & Action Tap Handling (`client/`)**:
  - Registered `ActionBroadcastReceiver` in `AndroidManifest.xml`.
  - Implemented background token submission and transient success notification in `push_notification_service.dart`.
- [x] **Client Models & Presence Service (`client/`)**:
  - Added `ScheduleCustomizationModel` and `UserPreferencesModel`.
  - Added CRUD customization methods to `PresenceService`.
- [x] **Interactive Customization UI (`client/lib/views/widgets/`)**:
  - Built `ScheduleCustomizationDialog` for relative/absolute time adjustment, reminder chips, and auto-presence switch.
  - Updated `ActiveLectureCard` with effective time display, portal baseline badge, auto-absen indicator, and customization trigger.
  - Added "Sesuaikan Jadwal" action to `MeetingGridTile` details dialog.
- [x] **Version Bump**:
  - Client bumped to `1.1.0+6` in `client/pubspec.yaml`.

## 3. Verification

- `python3 scripts/verify_pipeline.py` passed:
  - `ruff check`: All passed
  - `ruff format`: All formatted
  - `pytest (backend)`: 172 passed
  - `flutter analyze (client)`: 0 issues
  - `dart format (client)`: All formatted
- `python3 scripts/sync_backlog_status.py --check` passed.
