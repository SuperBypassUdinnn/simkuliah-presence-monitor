# Feature Log: F-034 Automation Settings Tab and Linux Runner Wake Fix

- **Parent Plan**: [`docs/superpowers/plans/2026-11-17-automation-settings-tab-and-linux-runner-fix-plan.md`](../../superpowers/plans/2026-11-17-automation-settings-tab-and-linux-runner-fix-plan.md)
- **Design Spec**: [`docs/superpowers/specs/2026-11-17-automation-settings-tab-and-linux-runner-fix-design.md`](../../superpowers/specs/2026-11-17-automation-settings-tab-and-linux-runner-fix-design.md)
- **Target Issue**: Owner report (chat, 2026-11-17)
- **Status**: Completed
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

F-033 introduced schedule offsets, class reminders, and auto-presence, but three defects prevented the feature from being usable in practice:

1. **Customization did not persist.** `schedule_customizations` carried a plain `UNIQUE(schedule_id, meeting_id)` constraint. PostgreSQL treats `NULL` values as distinct inside a multi-column unique constraint, so every course-level customization (`meeting_id IS NULL`) inserted a new duplicate row instead of updating the existing one. Reading the effective customization then surfaced an arbitrary stale row.
2. **No place to configure automation.** Settings were reachable only through a per-lecture popup dialog. There was no surface for a global reminder default or for reviewing every course's offset and auto-presence state in one place.
3. **Linux runner rendered a blank window when woken from `--hidden`.** The single-instance `activate` handler called `gtk_widget_show` on the top-level window only. The `FlView` child stayed unmapped, so an instance started with `--hidden` at autostart presented an empty frame on the first tray or launcher click.

This feature delivers:

1. **Deterministic persistence**: partial unique indexes on the nullable column pair plus id-resolving upserts on both the backend and the client.
2. **Dedicated "Pengaturan & Automasi" tab**: global reminder template, per-course auto-presence switch, offset chips, and reset-to-portal action.
3. **One-click auto-absen toggle** directly on the active lecture card, with optimistic update and rollback on failure.
4. **Linux runner wake fix**: recursive widget mapping on single-instance activation.

## 2. Implementation Checklist

- [x] **Supabase Migration (`supabase/migrations/20261117000000_fix_customization_null_index.sql`)**:
  - Drops `schedule_customizations_schedule_id_meeting_id_key`.
  - Creates `idx_schedule_customizations_course_unique` on `(schedule_id) WHERE meeting_id IS NULL`.
  - Creates `idx_schedule_customizations_meeting_unique` on `(schedule_id, meeting_id) WHERE meeting_id IS NOT NULL`.
- [x] **Backend Deterministic Upsert (`backend/app/core/database.py`)**:
  - `upsert_schedule_customization` resolves an existing row id before writing and targets `on_conflict: id` when one exists.
  - `resolve_effective_customization` ignores rows whose `schedule_id` does not match the requested schedule.
  - Covered by `backend/tests/test_database_customizations.py`.
- [x] **Client Model and Service (`client/lib/`)**:
  - `MeetingModel` gained a `customization` field and `copyWith`.
  - `PresenceService.fetchTodaysMeetings` attaches the resolved customization per meeting.
  - `PresenceService.saveCustomization` and `saveMeetingAutoPresence` perform deterministic id resolution before upsert.
- [x] **Quick Toggle on Lecture Card (`client/lib/views/widgets/active_lecture_card.dart`)**:
  - Inline "Auto-Absen Pertemuan Ini" switch replaces the popup-only entry point.
  - Optimistic state update with rollback and an error notification when the write fails.
  - `TodayFeedView` and `ActivePresenceView` pass `meeting.customization`.
- [x] **Settings Tab (`client/lib/views/settings_automation_view.dart`)**:
  - Global reminder card with 10m / 15m / 30m chips and a custom-minutes dialog.
  - Per-course cards with auto-presence switch, offset chips (-30 to +120), and reset action.
  - Registered as the fourth view and navigation destination in `client/lib/main.dart`.
- [x] **Linux Runner Wake Fix (`client/linux/runner/my_application.cc`)**:
  - `my_application_activate` calls `gtk_widget_show_all` so the unmapped `FlView` child is mapped before `gtk_window_present`.
- [x] **Version Bump**:
  - Client bumped to `1.1.1+7` in `client/pubspec.yaml`.

## 3. Verification

- `python3 scripts/verify_pipeline.py` passed:
  - `ruff check`: All passed
  - `ruff format`: All formatted
  - `pytest (backend)`: passed
  - `flutter analyze (client)`: 0 issues
  - `dart format (client)`: All formatted
- `python3 scripts/sync_backlog_status.py --check` passed.
- Targeted suites: `backend/tests/test_database_customizations.py`, `client/test/settings_automation_view_test.dart`, `client/test/active_lecture_card_customization_test.dart`, `client/test/models_test.dart`.
- `flutter build linux --dart-define-from-file=.env` produced a working bundle.

## 4. Follow-Up

- The migration file is committed but still has to be applied to the live Supabase project (`ftznonanlbshweysliar`) through the dashboard SQL editor or the Supabase CLI, because the `exec_sql` RPC is not exposed on that project.
- End-to-end auto-presence behavior against a live portal window remains to be observed in a real lecture session.
