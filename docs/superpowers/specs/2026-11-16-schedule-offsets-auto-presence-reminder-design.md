# Design Specification: Schedule Offsets, Auto-Presence, Class Reminders, and Notification Action Fix

- **Date**: 2026-11-16
- **Target Release**: Version 1.1.0+6
- **Status**: Draft (Under Review)
- **Author**: AI Agent / Developer

---

## 1. Executive Summary

This specification introduces three major functional enhancements and resolves one critical operational defect in the Simkuliah Presence Monitor platform:

1. **Class Entry Reminders**: Advance push alerts dispatched before effective class start times with preset templates (10, 15, 30 minutes) and customizable lead times, configurable globally with per-course overrides.
2. **Schedule Offsets & Date/Time Customization**: Support for both relative time shifts (+/- minutes/hours) and absolute re-scheduling (day of week and wall-clock times), scoped flexibly per individual meeting or across all meetings in a course schedule.
3. **Automated Presence Confirmation (Auto-Presence)**: Background autonomous execution of the verified 7-field AJAX presence confirmation upon detection of an open attendance window, suppressing standard "Presensi Dibuka" alerts in favor of dedicated "Presensi Otomatis Berhasil" confirmations, with fallback urgent alerts on failure.
4. **Android Action Button Execution Fix**: Declarative registration of `ActionBroadcastReceiver` in `AndroidManifest.xml` restoring native background tap handling for interactive push notification action buttons ("Presensi Sekarang", "Izin", "Sakit").

## 2. Problem Statement & User Experience Objectives

### 2.1 The Classroom Reality vs. Official Portal Discrepancy
In academic environments, course timetables registered on the official university portal frequently diverge from real-world agreements negotiated between lecturers and student cohorts. Classes registered for Monday 08:00 WIB may regularly meet on Wednesdays at 10:00 WIB, or begin 60 minutes later than cataloged.

Currently, the monitor evaluates and displays schedules strictly based on official Simkuliah records. This divergence leads to:
- Mismatched active-lecture feeds and misplaced status markers.
- Misleading timing expectations.
- Missed attendance windows: when lecturers open attendance on Simkuliah during the official hour while students are not yet in class, the strict 30-minute confirmation window is frequently forgotten.

### 2.2 Broken Android Interactive Notification Actions
While notification payloads carry signed HMAC action tokens for "Presensi Sekarang", "Izin", and "Sakit", tapping these buttons in Android's notification drawer produced no network request and no state change. The taps failed silently because the underlying Android plugin's broadcast receiver was omitted from the application manifest.

---

## 3. Database Schema & Data Modeling

To decouple official scraped portal records from student customizations without corrupting periodic syncs, all custom schedules, offsets, and automation flags reside in dedicated Supabase tables.

### 3.1 Migration: `20261116000000_schedule_customizations.sql`

```sql
-- 1. User Global Preferences
CREATE TABLE IF NOT EXISTS user_preferences (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL DEFAULT 'default_user',
    default_reminder_minutes INT NOT NULL DEFAULT 15,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- 2. Schedule Customizations & Auto-Presence
CREATE TABLE IF NOT EXISTS schedule_customizations (
    id SERIAL PRIMARY KEY,
    schedule_id INT NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
    meeting_id INT REFERENCES meetings(id) ON DELETE CASCADE,
    -- Relative time shift applied to start and end times
    time_offset_minutes INT NOT NULL DEFAULT 0,
    -- Absolute rescheduling overrides (optional)
    custom_day_of_week INT, -- 1 = Monday, 7 = Sunday
    custom_start_time TIME,
    custom_end_time TIME,
    -- Automation flags
    auto_presence_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    -- Notification lead-time override (null inherits user_preferences)
    reminder_lead_minutes INT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    -- Either schedule-wide (meeting_id IS NULL) or single-meeting specific
    UNIQUE(schedule_id, meeting_id)
);

-- RLS Policies
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_customizations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access on user_preferences"
    ON user_preferences FOR SELECT USING (true);
CREATE POLICY "Allow public write access on user_preferences"
    ON user_preferences FOR ALL USING (true);

CREATE POLICY "Allow public read access on schedule_customizations"
    ON schedule_customizations FOR SELECT USING (true);
CREATE POLICY "Allow public write access on schedule_customizations"
    ON schedule_customizations FOR ALL USING (true);
```

### 3.2 Effective Schedule Resolution Hierarchy
For any given meeting on a given date:
1. **Meeting-level Customization** (`schedule_customizations` where `meeting_id = meeting.id`): Takes highest precedence.
2. **Schedule-level Customization** (`schedule_customizations` where `schedule_id = meeting.schedule_id AND meeting_id IS NULL`): Takes second precedence.
3. **Official Simkuliah Base Schedule** (`schedules` row): Fallback default.

Effective time calculation logic:
- If absolute `custom_start_time` is specified, `effective_start_time = custom_start_time`, `effective_end_time = custom_end_time`.
- Otherwise, `effective_start_time = base_start_time + time_offset_minutes`, `effective_end_time = base_end_time + time_offset_minutes`.
- `effective_day_of_week` follows `custom_day_of_week` if set, else base `day_of_week`.

## 4. State Machine & Notification Lifecycle

### 4.1 State Machine Extension (`CLASS_REMINDER`)

A new notification tier is added before `CLASS_STARTED`:

```
CLASS_REMINDER (-Xm) -> CLASS_STARTED (0m) -> LECTURER_OPENED / AUTO_CONFIRMED -> PENDING_REMINDER -> URGENT_CLOSING -> WINDOW_EXPIRED
```

- **`NotificationLevel.CLASS_REMINDER`**:
  - Triggers when `now >= effective_start_time - reminder_lead_minutes` and `now < effective_start_time`.
  - Suppressed if already attended, overridden, or if a reminder level was already dispatched.
  - Priority: `Priority.NORMAL`.
  - Notification copy:
    - Title: `"Pengingat Kuliah - <Course Name> (<Code>)"`
    - Body: `"Kuliah dimulai dalam X menit (pukul HH:mm WIB) di Ruang <Room>."`

### 4.2 Auto-Presence Execution in `AdaptivePoller`

During each polling tick, when `meeting_status.is_open` is `True` and `meeting_status.is_student_present` is `False`:
1. Query `schedule_customizations` for active `auto_presence_enabled` on `(schedule_id, meeting_id)`.
2. If `auto_presence_enabled` is `True`:
   - Immediately invoke `confirm_meeting_on_simkuliah(client, repo, meeting_id=meeting_id, ...)`.
   - **On Success**:
     - Dispatch push notification with level `AUTO_CONFIRMED`.
     - Title: `"Presensi Otomatis Berhasil - <Course Name> (<Code>)"`
     - Body: `"Presensi pertemuan ke-X telah otomatis dikonfirmasi hadir di Simkuliah."`
     - Record monotonic rank to avoid duplicate alerts.
     - Skip dispatch of standard `LECTURER_OPENED`.
   - **On Failure / Error**:
     - Dispatch urgent alert with level `AUTO_PRESENCE_FAILED` (Priority: `Priority.HIGH`).
     - Title: `"Presensi Otomatis Gagal - <Course Name> (<Code>)"`
     - Body: `"Presensi otomatis ke Simkuliah gagal. Segera lakukan presensi manual sebelum batas waktu!"`
     - Include native action button: `"Presensi Sekarang"`.
3. If `auto_presence_enabled` is `False`:
   - Proceed with normal `LECTURER_OPENED` alert flow.

### 4.3 Poller Sleep Interval Clamping with Effective Schedules
`calculate_next_poll_interval` evaluates effective start times:
- If an upcoming class reminder falls at `reminder_dt`, the sleep interval clamps to `reminder_dt - now` (minimum 60s).
- Pre-class wake (`effective_start_time - 10m`) remains enforced.

---

## 5. Android Native Action Buttons Fix

### 5.1 Root Cause & Solution
In `client/android/app/src/main/AndroidManifest.xml`, the plugin requires explicit registration of its broadcast receiver:

```xml
<receiver
    android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"
    android:exported="false" />
```

### 5.2 Background Action Dispatch Flow
1. User taps "Presensi Sekarang", "Izin", or "Sakit" on the Android notification.
2. Android OS routes the broadcast to `ActionBroadcastReceiver`.
3. The plugin spawns/wakes the background Dart isolate and calls `@pragma('vm:entry-point') handleNotificationActionTap`.
4. `handleNotificationActionTap` decodes `action|token` and calls `DeviceService().submitActionToken()`.
5. Upon successful HTTP 200 response from `/api/v1/webhook/action`, the local notification is updated with a transient success confirmation ("Presensi Berhasil", auto-dismissing after 3 seconds).

## 6. Client Architecture & User Interface Design

### 6.1 Customization Models & Service
- New model `ScheduleCustomizationModel`:
  - `timeOffsetMinutes`, `customDayOfWeek`, `customStartTime`, `customEndTime`, `autoPresenceEnabled`, `reminderLeadMinutes`.
- `PresenceService` extensions:
  - `fetchCustomizations()`: queries `schedule_customizations`.
  - `saveCustomization(...)`: upserts customization records.
  - `deleteCustomization(...)`: clears overrides.
  - `fetchPreferences()` and `savePreferences(...)`: manages global reminder defaults.

### 6.2 Schedule Customization Dialog
Triggered via an "Atur Jadwal & Automasi" button on `ActiveLectureCard` and within the meeting detail modal on `SemesterMatrixView`:
- **Mode Tab**:
  - *Relatif*: Slider or quick chips for `+/- 15, 30, 60, 120` minutes.
  - *Pindah Jadwal (Absolut)*: Day-of-week dropdown (Senin–Minggu) + start/end time pickers.
- **Scope Selector**:
  - Radio options: "Hanya Pertemuan Ini (Pertemuan ke-X)" vs "Seluruh Pertemuan Mata Kuliah Ini".
- **Auto-Presence Toggle**:
  - Switch: "Aktifkan Presensi Otomatis (Auto-Absen)".
  - Information tooltip explaining that the backend will automatically confirm presence when the lecturer opens the session.
- **Reminder Lead Time**:
  - Chip selector: `10m`, `15m`, `30m`, `Custom`, or `Ikuti Default Global`.

### 6.3 Card & Tile Visual Indicators
- Effective time displayed as the primary bold text.
- Original Simkuliah time displayed in a subtle muted badge: `10:00 - 11:40 (Portal: 08:00)`.
- Auto-presence status indicated by an automation badge or icon when active.

---

## 7. Versioning & Delivery

- **Client Version**: Bump `client/pubspec.yaml` to `1.1.0+6`.
- **Target Artifacts**:
  - Linux desktop release bundle (`~/.local/share/simkuliah-monitor/`).
  - Android release APK (`client/build/app/outputs/flutter-apk/app-release.apk`).
  - Backend deployment to Render.

---

## 8. Verification & Testing Matrix

### 8.1 Backend Unit & Integration Tests (`pytest`)
- Migration testing: verify `schedule_customizations` table creation and RLS policies.
- State machine testing: verify `CLASS_REMINDER` triggers at `effective_start - reminder_lead` and progresses monotonically.
- Poller testing:
  - Verify effective schedule resolution hierarchy (meeting > schedule > portal base).
  - Verify auto-presence execution: when open, auto-confirm succeeds, updates Supabase to `hadir`, dispatches `AUTO_CONFIRMED`, and suppresses `LECTURER_OPENED`.
  - Verify auto-presence failure fallback: dispatches `AUTO_PRESENCE_FAILED` with high priority and action button.
  - Verify `calculate_next_poll_interval` clamps to reminder lead time.

### 8.2 Client Unit & Widget Tests (`flutter test`)
- `LoadEpochGuard` and `PresenceService` customizations CRUD tests.
- Dialog widget tests: verify relative offset and absolute schedule input validation.
- Card rendering tests: verify effective time formatting, badge display, and auto-presence indicator.
- Action button tests: verify `ActionBroadcastReceiver` in manifest and action payload encoding.

