# Schedule Offsets, Auto-Presence, Class Reminders, and Action Buttons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver version 1.1.0+6 adding class entry push reminders, flexible schedule offsets/rescheduling (relative/absolute, per-meeting or whole-course), autonomous presence confirmation with success/failure push alerts, and fixing Android notification interactive action buttons ("Presensi Sekarang", "Izin", "Sakit").

**Architecture:** Custom schedule offsets, auto-presence switches, and reminder configurations are stored in Supabase `schedule_customizations` and `user_preferences` tables to keep multi-device state in sync without mutating scraped portal baseline data. The backend `AdaptivePoller` dynamically evaluates effective schedule hierarchies (meeting override > schedule override > portal baseline), fires `CLASS_REMINDER` notifications before class start, clamps sleep intervals accordingly, and autonomously triggers the verified 7-field AJAX presence confirmation (`confirm_meeting_on_simkuliah`) as soon as the attendance window opens. The Android client registers `ActionBroadcastReceiver` in `AndroidManifest.xml` so background notification action button taps dispatch to `/api/v1/webhook/action` and provide instant visual success feedback.

**Tech Stack:** Python 3.11 / FastAPI / Supabase (PostgreSQL) / APScheduler / Firebase Cloud Messaging (FCM) / Flutter 3.x (Dart 3) / `flutter_local_notifications`.

**Spec:** `docs/superpowers/specs/2026-11-16-schedule-offsets-auto-presence-reminder-design.md`

## Global Constraints

- Python code must conform to `ruff check .` and `ruff format .` without warnings or suppressions.
- Flutter/Dart code must conform to `flutter analyze --no-pub` and `dart format --set-exit-if-changed .` without issues.
- Client version in `client/pubspec.yaml` must increment to `1.1.0+6`.
- Supabase migrations must use timestamped SQL files under `supabase/migrations/` and include idempotent RLS policies.
- Notification copy and titles must adhere to formal Indonesian student-facing messages defined in the spec.
- No Markdown formatting, emojis, or decorative icons in Git commit messages or technical artifacts.

## Review Focus

1. **Auto-presence failure while app is backgrounded**: Poller must not crash if Simkuliah times out; it must dispatch an urgent high-priority `AUTO_PRESENCE_FAILED` notification carrying a functional "Presensi Sekarang" action button.
2. **Midnight-crossing relative offset (+120m on late class)**: Effective start/end calculation must handle day boundary transitions safely without raising `ValueError` on time arithmetic.
3. **Double confirmation race condition**: If auto-presence is running concurrently with manual presence submission, subsequent attempts must treat already-present state as a benign success rather than throwing an unhandled exception.
4. **Offline / half-open socket when tapping notification action button**: Android `handleNotificationActionTap` must time out cleanly and log a warning without crashing the background isolate if the network is dead.
5. **Pre-class reminder interval clamping**: `calculate_next_poll_interval` must clamp to the earliest upcoming reminder lead time so the poller does not oversleep and miss firing `CLASS_REMINDER`.

---

### Task 1: Supabase Database Migration & Repository Customization Methods

**Files:**
- Create: `supabase/migrations/20261116000000_schedule_customizations.sql`
- Modify: `backend/app/core/database.py`
- Test: `backend/tests/test_database_customizations.py`

**Interfaces:**
- Consumes: `DatabaseRepository.client`, `DatabaseRepository._with_retry`
- Produces:
  - `DatabaseRepository.get_user_preferences(user_id: str = "default_user") -> dict[str, Any]`
  - `DatabaseRepository.upsert_user_preferences(preferences: dict[str, Any]) -> dict[str, Any]`
  - `DatabaseRepository.get_schedule_customizations(schedule_ids: list[int] | None = None) -> list[dict[str, Any]]`
  - `DatabaseRepository.upsert_schedule_customization(customization: dict[str, Any]) -> dict[str, Any]`
  - `DatabaseRepository.delete_schedule_customization(customization_id: int) -> bool`
  - `DatabaseRepository.resolve_effective_customization(schedule_id: int, meeting_id: int | None = None) -> dict[str, Any] | None`

- [ ] **Step 1: Write the failing tests for database customization methods**

```python
# backend/tests/test_database_customizations.py
import pytest
from unittest.mock import MagicMock
from app.core.database import DatabaseRepository

@pytest.mark.asyncio
async def test_resolve_effective_customization_prefers_meeting_over_schedule():
    repo = DatabaseRepository(supabase_url="http://mock", supabase_key="key")
    repo.client = MagicMock()
    # Mock return rows: one schedule-level and one meeting-level
    mock_data = [
        {"id": 1, "schedule_id": 10, "meeting_id": None, "time_offset_minutes": 15, "auto_presence_enabled": False},
        {"id": 2, "schedule_id": 10, "meeting_id": 50, "time_offset_minutes": 30, "auto_presence_enabled": True},
    ]
    repo.get_schedule_customizations = MagicMock(return_value=mock_data)

    eff = await repo.resolve_effective_customization(schedule_id=10, meeting_id=50)
    assert eff["time_offset_minutes"] == 30
    assert eff["auto_presence_enabled"] is True

    eff_sched = await repo.resolve_effective_customization(schedule_id=10, meeting_id=99)
    assert eff_sched["time_offset_minutes"] == 15
```

- [ ] **Step 2: Run test to verify it fails**

Run: `backend/.venv/bin/python -m pytest backend/tests/test_database_customizations.py -v`
Expected: FAIL with `AttributeError: 'DatabaseRepository' object has no attribute 'resolve_effective_customization'`

- [ ] **Step 3: Create migration `supabase/migrations/20261116000000_schedule_customizations.sql`**

Write table definitions for `user_preferences` and `schedule_customizations` with foreign keys, unique constraints, and permissive RLS policies matching Section 3.1 of the spec.

- [ ] **Step 4: Implement repository methods in `backend/app/core/database.py`**

Implement `get_user_preferences`, `upsert_user_preferences`, `get_schedule_customizations`, `upsert_schedule_customization`, `delete_schedule_customization`, and `resolve_effective_customization` using `_with_retry`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `backend/.venv/bin/python -m pytest backend/tests/test_database_customizations.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20261116000000_schedule_customizations.sql backend/app/core/database.py backend/tests/test_database_customizations.py
git commit -m "feat(backend): add schedule customizations and user preferences repository"
```

### Task 2: State Machine Extension (`CLASS_REMINDER`, `AUTO_CONFIRMED`, `AUTO_PRESENCE_FAILED`) & Content Strings

**Files:**
- Modify: `backend/app/services/state_machine.py`
- Modify: `backend/app/services/notification_content.py`
- Test: `backend/tests/test_state_machine_customizations.py`

**Interfaces:**
- Consumes: `NotificationLevel`, `evaluate_notification_state`
- Produces:
  - `NotificationLevel.CLASS_REMINDER = "class_reminder"`
  - `NotificationLevel.AUTO_CONFIRMED = "auto_confirmed"`
  - `NotificationLevel.AUTO_PRESENCE_FAILED = "auto_presence_failed"`
  - Updated `evaluate_notification_state(..., reminder_lead_minutes: int | None = None)`
  - Updated `STATE_TITLES`, `ACTIONABLE_STATES`, and `notification_text` in `notification_content.py`

- [ ] **Step 1: Write the failing tests for state machine reminder and auto-presence tiers**

```python
# backend/tests/test_state_machine_customizations.py
from datetime import datetime, time
import pytest
from app.services.state_machine import (
    NotificationLevel,
    Priority,
    evaluate_notification_state,
    priority_for_state,
    rank_for_level,
)
from app.services.notification_content import notification_title, notification_text, ACTIONABLE_STATES

def test_class_reminder_triggers_within_lead_window():
    now = datetime(2026, 11, 16, 7, 46) # 14 mins before 8:00
    state = evaluate_notification_state(
        now=now,
        start_time=time(8, 0),
        end_time=time(9, 40),
        is_dosen_open=False,
        is_student_present=False,
        has_override=False,
        last_notified_level=None,
        reminder_lead_minutes=15,
    )
    assert state == NotificationLevel.CLASS_REMINDER
    assert priority_for_state(state) == Priority.NORMAL

def test_auto_presence_failed_is_high_priority_and_actionable():
    assert priority_for_state(NotificationLevel.AUTO_PRESENCE_FAILED) == Priority.HIGH
    assert NotificationLevel.AUTO_PRESENCE_FAILED in ACTIONABLE_STATES
```

- [ ] **Step 2: Run test to verify it fails**

Run: `backend/.venv/bin/python -m pytest backend/tests/test_state_machine_customizations.py -v`
Expected: FAIL with `AttributeError: type object 'NotificationLevel' has no attribute 'CLASS_REMINDER'`

- [ ] **Step 3: Update `backend/app/services/state_machine.py`**

- Add `CLASS_REMINDER`, `AUTO_CONFIRMED`, `AUTO_PRESENCE_FAILED` to `NotificationLevel`.
- Update `_LEVEL_RANK` mapping:
  - `CLASS_REMINDER: 0`
  - `CLASS_STARTED: 1`
  - `LECTURER_OPENED: 2`
  - `AUTO_CONFIRMED: 2`
  - `AUTO_PRESENCE_FAILED: 2`
  - `PENDING_REMINDER: 3`
  - `URGENT_CLOSING: 4`
  - `WINDOW_EXPIRED: 5`
- Add `AUTO_PRESENCE_FAILED` to `_HIGH_PRIORITY_LEVELS`.
- In `evaluate_notification_state`, add parameter `reminder_lead_minutes: int | None = None`. Before `CLASS_STARTED` check, if `reminder_lead_minutes` is set and `now >= start_dt - timedelta(minutes=reminder_lead_minutes)` and `now < start_dt`, return `NotificationLevel.CLASS_REMINDER`.

- [ ] **Step 4: Update `backend/app/services/notification_content.py`**

- Add titles:
  - `NotificationLevel.CLASS_REMINDER: "Pengingat Kuliah"`
  - `NotificationLevel.AUTO_CONFIRMED: "Presensi Otomatis Berhasil"`
  - `NotificationLevel.AUTO_PRESENCE_FAILED: "Presensi Otomatis Gagal"`
- Add `NotificationLevel.AUTO_PRESENCE_FAILED` to `ACTIONABLE_STATES`.
- Add body strings in `notification_text` matching the spec copy.

- [ ] **Step 5: Run tests to verify they pass**

Run: `backend/.venv/bin/python -m pytest backend/tests/test_state_machine_customizations.py backend/tests/test_state_machine.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/app/services/state_machine.py backend/app/services/notification_content.py backend/tests/test_state_machine_customizations.py
git commit -m "feat(backend): add class reminder and auto presence state tiers"
```

---

### Task 3: Backend Poller Customization Resolution, Auto-Presence Trigger, & Sleep Clamping

**Files:**
- Modify: `backend/app/services/poller.py`
- Test: `backend/tests/test_poller_customizations.py`

**Interfaces:**
- Consumes:
  - `DatabaseRepository.get_schedule_customizations`, `DatabaseRepository.get_user_preferences`
  - `confirm_meeting_on_simkuliah` from `app.services.presence_confirmer`
  - `evaluate_notification_state` from `app.services.state_machine`
- Produces:
  - Autonomous presence confirmation in `AdaptivePoller._tick`
  - Clamp in `calculate_next_poll_interval` for upcoming reminders
  - Effective schedule time evaluation (+/- offsets and absolute overrides)

- [ ] **Step 1: Write the failing tests for poller auto-presence and sleep interval clamping**

```python
# backend/tests/test_poller_customizations.py
from datetime import datetime, time
from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from app.services.poller import AdaptivePoller, calculate_next_poll_interval
from app.services.simkuliah_parser import ParsedMeetingStatus, ParsedScheduleItem
from app.services.state_machine import NotificationLevel

@pytest.mark.asyncio
async def test_poller_triggers_auto_presence_when_open(poller_deps):
    deps = poller_deps
    deps["repo"].resolve_schedule_id = AsyncMock(return_value=10)
    deps["repo"].resolve_meeting_id = AsyncMock(return_value=50)
    deps["repo"].resolve_effective_customization = AsyncMock(return_value={
        "auto_presence_enabled": True,
        "time_offset_minutes": 0,
    })
    poller = AdaptivePoller(client=deps["client"], repo=deps["repo"], dispatcher=deps["dispatcher"], scheduler=deps["scheduler"])
    
    with (
        patch("app.services.poller.confirm_meeting_on_simkuliah", new_callable=AsyncMock) as mock_confirm,
        patch.object(poller, "_fetch_meeting_status", return_value=ParsedMeetingStatus(
            schedule_id=123, meeting_number=1, is_open=True, is_student_present=False
        ))
    ):
        mock_confirm.return_value = {"status": "success"}
        await poller._process_single_item(ParsedScheduleItem(
            course_code="IF101", course_name="Test", room="Lab", start_time="08:00", end_time="09:40", lecturer="Dr. X", class_group="A"
        ), now=datetime(2026, 11, 16, 8, 5))
        mock_confirm.assert_awaited_once()
        deps["dispatcher"].dispatch.assert_called_once()
        assert deps["dispatcher"].dispatch.call_args[0][0] == NotificationLevel.AUTO_CONFIRMED
```

- [ ] **Step 2: Run test to verify it fails**

Run: `backend/.venv/bin/python -m pytest backend/tests/test_poller_customizations.py -v`
Expected: FAIL with missing method or unexpected dispatch call.

- [ ] **Step 3: Update `backend/app/services/poller.py`**

- In `AdaptivePoller._tick`:
  - Fetch user preferences and schedule customizations map for today's courses.
  - Calculate effective start and end times for each item based on customizations.
  - If `is_dosen_open` and not `is_student_present` and `auto_presence_enabled`:
    - Call `confirm_meeting_on_simkuliah(...)`.
    - If successful: dispatch `NotificationLevel.AUTO_CONFIRMED` and record monotonic rank.
    - If exception raised: log error, dispatch `NotificationLevel.AUTO_PRESENCE_FAILED` with priority `HIGH` and action button.
- In `calculate_next_poll_interval`:
  - Accept optional list of upcoming reminder times and clamp sleep interval to `min(interval, reminder_dt - now)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `backend/.venv/bin/python -m pytest backend/tests/test_poller_customizations.py backend/tests/test_poller.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/poller.py backend/tests/test_poller_customizations.py
git commit -m "feat(backend): add auto-presence execution and reminder clamping in poller"
```

### Task 4: Android Notification Action Button Native Execution Fix

**Files:**
- Modify: `client/android/app/src/main/AndroidManifest.xml`
- Modify: `client/lib/services/push_notification_service.dart`
- Test: `client/test/push_notification_action_test.dart`

**Interfaces:**
- Consumes: `DeviceService.submitActionToken`, `FlutterLocalNotificationsPlugin`
- Produces:
  - Working native broadcast reception on Android for notification action buttons
  - Background execution in `handleNotificationActionTap` with transient visual success feedback

- [ ] **Step 1: Write the failing test for action tap handler and manifest presence**

```dart
// client/test/push_notification_action_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_presence_monitor/services/push_notification_service.dart';

void main() {
  test('AndroidManifest.xml contains ActionBroadcastReceiver registration', () {
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    expect(manifestFile.existsSync(), isTrue);
    final content = manifestFile.readAsStringSync();
    expect(
      content.contains('com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver'),
      isTrue,
      reason: 'ActionBroadcastReceiver must be registered in AndroidManifest.xml',
    );
  });

  test('FcmActionEncoder decodes action token payload correctly', () {
    final encoded = FcmActionEncoder.encodeActionId(
      action: 'confirm_presence',
      token: 'test_token_123',
    );
    final decoded = FcmActionEncoder.decodeActionId(encoded);
    expect(decoded?.action, 'confirm_presence');
    expect(decoded?.token, 'test_token_123');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/push_notification_action_test.dart`
Expected: FAIL on `AndroidManifest.xml contains ActionBroadcastReceiver registration`

- [ ] **Step 3: Register `ActionBroadcastReceiver` in `client/android/app/src/main/AndroidManifest.xml`**

Inside `<application>` tag, add:
```xml
        <!-- Action broadcast receiver for notification interactive action buttons -->
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"
            android:exported="false" />
```

- [ ] **Step 4: Update `handleNotificationActionTap` in `client/lib/services/push_notification_service.dart`**

Enhance `handleNotificationActionTap` to:
- Await `DeviceService().submitActionToken(...)`.
- On success, if notification id is present, show a transient success notification ("Presensi Berhasil", "Aksi presensi telah berhasil dikonfirmasi"), wait 3 seconds, and auto-cancel.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/push_notification_action_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/android/app/src/main/AndroidManifest.xml client/lib/services/push_notification_service.dart client/test/push_notification_action_test.dart
git commit -m "fix(client): register action broadcast receiver and provide success feedback"
```

---

### Task 5: Client Data Models & PresenceService Customization API

**Files:**
- Create: `client/lib/models/schedule_customization_model.dart`
- Create: `client/lib/models/user_preferences_model.dart`
- Modify: `client/lib/services/presence_service.dart`
- Test: `client/test/schedule_customization_model_test.dart`
- Test: `client/test/presence_service_customization_test.dart`

**Interfaces:**
- Consumes: Supabase tables `schedule_customizations` and `user_preferences`
- Produces:
  - `ScheduleCustomizationModel` with `toJson()`, `fromJson(...)`
  - `UserPreferencesModel` with `toJson()`, `fromJson(...)`
  - `PresenceService.fetchCustomizations(List<int> scheduleIds)`
  - `PresenceService.saveCustomization(ScheduleCustomizationModel customization)`
  - `PresenceService.deleteCustomization(int id)`
  - `PresenceService.fetchUserPreferences()`
  - `PresenceService.saveUserPreferences(UserPreferencesModel preferences)`

- [ ] **Step 1: Write the failing tests for serialization and PresenceService methods**

```dart
// client/test/schedule_customization_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_presence_monitor/models/schedule_customization_model.dart';

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
    expect(parsed.scheduleId, 10);
    expect(parsed.meetingId, 5);
    expect(parsed.timeOffsetMinutes, 15);
    expect(parsed.autoPresenceEnabled, true);
    expect(parsed.reminderLeadMinutes, 20);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/schedule_customization_model_test.dart`
Expected: FAIL with compilation error (model file does not exist).

- [ ] **Step 3: Create models in `client/lib/models/`**

Create `schedule_customization_model.dart` and `user_preferences_model.dart` with complete JSON mapping and copyWith methods.

- [ ] **Step 4: Add customization and preferences CRUD to `client/lib/services/presence_service.dart`**

Implement:
- `fetchCustomizations(...)` querying `_tableScheduleCustomizations = 'schedule_customizations'`
- `saveCustomization(...)` using Supabase upsert wrapped with `_runWithResilience`
- `deleteCustomization(...)`
- `fetchUserPreferences()` and `saveUserPreferences(...)`

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/schedule_customization_model_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/schedule_customization_model.dart client/lib/models/user_preferences_model.dart client/lib/services/presence_service.dart client/test/schedule_customization_model_test.dart
git commit -m "feat(client): add customization models and presence service api"
```

### Task 6: Client Customization Dialog & ActiveLectureCard Indicators

**Files:**
- Create: `client/lib/views/widgets/schedule_customization_dialog.dart`
- Modify: `client/lib/views/widgets/active_lecture_card.dart`
- Modify: `client/lib/views/widgets/matrix_meeting_detail_dialog.dart` (or `semester_matrix_view.dart`)
- Test: `client/test/schedule_customization_dialog_test.dart`
- Test: `client/test/active_lecture_card_customization_test.dart`

**Interfaces:**
- Consumes: `ScheduleCustomizationModel`, `PresenceService`
- Produces:
  - Interactive `ScheduleCustomizationDialog`
  - Action button "Sesuaikan Jadwal & Automasi" in lecture cards/detail dialogs
  - Primary effective time formatting with muted baseline Simkuliah badge: `10:00 - 11:40 (Portal: 08:00)`
  - Visual auto-presence badge/icon when enabled

- [ ] **Step 1: Write the failing widget tests for ScheduleCustomizationDialog**

```dart
// client/test/schedule_customization_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_presence_monitor/models/schedule_customization_model.dart';
import 'package:simkuliah_presence_monitor/views/widgets/schedule_customization_dialog.dart';

void main() {
  testWidgets('renders relative offset and auto-presence controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleCustomizationDialog(
            courseName: 'Grafika Komputer',
            courseCode: 'INF201',
            scheduleId: 1,
            meetingNumber: 1,
          ),
        ),
      ),
    );
    expect(find.text('Sesuaikan Jadwal & Automasi'), findsOneWidget);
    expect(find.text('Presensi Otomatis (Auto-Absen)'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/schedule_customization_dialog_test.dart`
Expected: FAIL (dialog file does not exist).

- [ ] **Step 3: Implement `ScheduleCustomizationDialog` in `client/lib/views/widgets/schedule_customization_dialog.dart`**

Implement Material 3 dialog with:
- Tabs for *Relatif* (+/- chips: 15m, 30m, 60m, 120m, or text field) vs *Pindah Jadwal (Absolut)* (Day dropdown + Time pickers).
- Scope radio selector: "Hanya Pertemuan Ini" vs "Seluruh Pertemuan Mata Kuliah Ini".
- Switch for "Presensi Otomatis (Auto-Absen)" with explanatory subtitle.
- Reminder lead time chip selector: `10m`, `15m`, `30m`, `Custom`.
- Save button calling `PresenceService.saveCustomization(...)`.

- [ ] **Step 4: Update `ActiveLectureCard` in `client/lib/views/widgets/active_lecture_card.dart`**

- Render effective schedule time boldly as primary text.
- If customized, render baseline portal time in a subtle muted badge: `(Portal: 08:00)`.
- If auto-presence is active, display a small robot/lightning badge.
- Add an action icon/button to open `ScheduleCustomizationDialog`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/schedule_customization_dialog_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/views/widgets/schedule_customization_dialog.dart client/lib/views/widgets/active_lecture_card.dart client/test/schedule_customization_dialog_test.dart
git commit -m "feat(client): add schedule customization dialog and card indicators"
```

---

### Task 7: Version Bump (1.1.0+6), Feature Execution Log, & End-to-End Pipeline Verification

**Files:**
- Modify: `client/pubspec.yaml` (bump version to `1.1.0+6`)
- Create: `docs/backlog/features/F-033-schedule-offsets-auto-presence-reminder.md`
- Test: Full pipeline verification scripts

**Interfaces:**
- Consumes: All completed backend and client modules from Tasks 1-6
- Produces: Clean pre-release gate passing all checks

- [ ] **Step 1: Bump version in `client/pubspec.yaml`**

Change `version: 1.0.6+5` to `version: 1.1.0+6`.

- [ ] **Step 2: Create feature execution log `docs/backlog/features/F-033-schedule-offsets-auto-presence-reminder.md`**

Author complete log with problem statement, implementation checklist, and verification outcomes linked to `.planning/04-hybrid-push-notifications.md`.

- [ ] **Step 3: Run full automated verification pipeline**

Run: `python3 scripts/verify_pipeline.py`
Expected:
```
[PASS] ruff check
[PASS] ruff format
[PASS] pytest (backend)
[PASS] flutter analyze (client)
[PASS] dart format (client)
All verification checks PASSED successfully.
```

- [ ] **Step 4: Run backlog status parity gate**

Run: `python3 scripts/sync_backlog_status.py --check`
Expected: `[PASS] Planning and backlog status parity verified.`

- [ ] **Step 5: Commit**

```bash
git add client/pubspec.yaml docs/backlog/features/F-033-schedule-offsets-auto-presence-reminder.md
git commit -m "chore(release): bump client version to 1.1.0+6 and record F-033 log"
```

