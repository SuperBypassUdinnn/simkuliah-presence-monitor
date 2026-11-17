# Design Specification: Automation Settings Tab, Persistence Fix, and Linux Runner Repair

- **Date**: 2026-11-17
- **Target Release**: Version 1.1.1+7
- **Status**: Draft (Under Review)
- **Author**: AI Agent / Developer

---

## 1. Executive Summary

This specification addresses four critical findings in the Simkuliah Presence Monitor platform:

1. **Customization & Reminder Persistence Defect**: Fixes the regression where schedule offsets and pre-class reminders reverted to defaults due to un-joined data in daily feeds and a PostgreSQL unique index NULL trap on course-level customizations (`meeting_id IS NULL`).
2. **Auto-Presence Validation & Reliability**: Validates end-to-end autonomous presence execution in both background poller ticks and instant single-meeting triggers once persistence is resolved.
3. **Dedicated "Pengaturan & Automasi" Tab**: Replaces the overloaded card popup dialog with a dedicated 4th navigation tab providing clear, granular configuration for global reminders, course-level schedule offsets, and course-wide auto-presence. Adds an inline 1-click toggle for quick single-meeting auto-presence directly on lecture cards.
4. **Linux Desktop Background Activation Bug**: Fixes the native GTK runner bug where re-opening the application from an autostart background instance (`--hidden`) rendered a blank black window due to unmapped `FlView` children.

---

## 2. Problem Statement & Root Cause Analysis

### 2.1 Persistence & Data Flow Gaps
- `TodayFeedView` and `ActivePresenceView` invoked `fetchTodaysMeetings()` which only joined `schedules` and `local_overrides`, completely omitting `schedule_customizations`. Consequently, `ActiveLectureCard` always received `customization: null`.
- When users opened the customization dialog, `initialCustomization` was always null, presenting initial defaults every time.
- In PostgreSQL, standard `UNIQUE(schedule_id, meeting_id)` treats NULLs as distinct (`NULL != NULL`). Saving course-level customizations (`meeting_id = NULL`) caused PostgREST's `ON CONFLICT (schedule_id, meeting_id)` to fail to match existing rows, inserting duplicate records instead of updating.
- Global user preferences (`user_preferences` table) were never fetched or updated by the client UI.

### 2.2 Linux Desktop Window Blank Screen
- When launched with `--hidden`, the window is initialized but never shown, and `first-frame` signal intentionally suppresses `gtk_widget_show`.
- Upon second launch (e.g. from the desktop app launcher), GApplication forwards activation to the running instance in `my_application_activate`.
- The handler invoked `gtk_widget_show(GTK_WIDGET(self->first_window))`. In GTK 3, calling `gtk_widget_show` on a top-level window does not recursively map unmapped child widgets (`FlView`). As a result, the window displayed only the default black background (`#000000`) without rendering Flutter frames.

---

## 3. Database Schema Migration

### 3.1 Migration: `20261117000000_fix_customization_null_index.sql`
To enforce deterministic upserts regardless of whether `meeting_id` is null or set:

```sql
-- Drop the multi-column unique constraint that fails on NULLs
ALTER TABLE schedule_customizations DROP CONSTRAINT IF EXISTS schedule_customizations_schedule_id_meeting_id_key;

-- Create two partial unique indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_customizations_course_unique
    ON schedule_customizations (schedule_id)
    WHERE meeting_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_customizations_meeting_unique
    ON schedule_customizations (schedule_id, meeting_id)
    WHERE meeting_id IS NOT NULL;
```

---

## 4. Client Architecture & UI Design

### 4.1 Navigation Structure Update (`MainHomeScreen`)
A 4th tab is added to the navigation rail / bottom navigation bar:
- Index 0: `ActivePresenceView` (Presensi Aktif)
- Index 1: `TodayFeedView` (Jadwal Hari Ini)
- Index 2: `SemesterMatrixView` (Matriks Semester)
- Index 3: `SettingsAutomationView` (Pengaturan & Automasi) [NEW]

### 4.2 Dedicated Tab: `SettingsAutomationView`
Divided into two organized sections:

1. **Pengingat Masuk Kuliah (Global)**:
   - Header explaining default pre-class notification lead time.
   - Lead time chip templates: `10m`, `15m`, `30m`, or custom minute input field.
   - Persisted immediately to `user_preferences` for the user.

2. **Daftar Mata Kuliah & Penyesuaian Jadwal**:
   - Lists all courses registered in the current semester.
   - Each course card displays:
     - Course name, code, class group, and official portal schedule.
     - **Presensi Otomatis (Auto-Absen)** switch: enables autonomous presence confirmation for all meetings in this course.
     - **Penyesuaian Waktu**:
       - *Relatif*: Offset chips (-30m, -15m, 0m, +15m, +30m, +60m, +120m) or custom input.
       - *Pindah Jadwal (Absolut)*: Day of week selector + Start and End time pickers.
     - **Override Pengingat Kuliah (Opsional)**: Specific lead time for this course if differing from global default.
     - Reset button to restore official Simkuliah baseline.

### 4.3 Inline Quick Action on `ActiveLectureCard`
In `TodayFeedView` and `ActivePresenceView`:
- Remove the complex popup dialog trigger.
- Add a direct, 1-click **"Auto-Absen"** toggle switch on each card:
  - Toggling immediately creates or updates a meeting-level customization (`meeting_id`) with `auto_presence_enabled: true/false`.
  - Provides instant feedback without modal dialogs.
- Display effective adjusted time boldly with a subtle baseline tag: `10:00 - 11:40 WIB (Portal: 08:00)`.

### 4.4 Data Syncing in `PresenceService`
- `fetchTodaysMeetings()` and `fetchSemesterMatrix()` updated to load active customizations from `schedule_customizations` and merge them into each meeting model.
- `saveCourseCustomization` and `saveMeetingAutoPresence` provide focused, robust API methods.

---

## 5. Linux Desktop Native Runner Repair

In `client/linux/runner/my_application.cc`:
- In `my_application_activate`:
  ```cpp
  if (self->first_window != nullptr) {
    gtk_widget_show_all(GTK_WIDGET(self->first_window));
    gtk_window_present(self->first_window);
    return;
  }
  ```
- Use `gtk_widget_show_all` so `FlView` and header bars are recursively mapped to the Wayland/X11 compositor surface.
- Ensure focus is grabbed by `FlView` to immediately resume the frame rendering loop.

---

## 6. Verification Plan

1. **Database & Indexing**:
   - Verify upserting `meeting_id = NULL` updates existing rows instead of duplicating.
2. **Client State Machine & UI**:
   - Verify changes made in `SettingsAutomationView` persist across restarts and tab switches.
   - Verify 1-click meeting auto-absen toggle updates database and reflects state on the card.
3. **Poller Execution**:
   - Test that poller reads `auto_presence_enabled = true` from database and triggers `confirm_meeting_on_simkuliah`.
4. **Linux Background Activation**:
   - Launch binary with `--hidden`.
   - Execute second launch `simkuliah_client` and verify the window renders full Flutter UI instead of blank black screen.
5. **Quality Pipeline**:
   - Run `python3 scripts/verify_pipeline.py`.
   - Run `python3 scripts/sync_backlog_status.py --check`.
