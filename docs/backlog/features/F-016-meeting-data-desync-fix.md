# Feature Log: F-016 Meeting Data Desync Fix

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: #26
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Real-device evidence (2026-11-09, SINF6045 Penelusuran Informasi, 16:35-18:15
WIB): the app showed "Dosen Belum Melakukan Presensi" while the Simkuliah
dashboard already showed the open attendance card (PERTEMUAN KE-12, "Anda
sudah absen", batas absen 17:45); the app displayed "Pertemuan ke-11" with the
first-half lecturer while Simkuliah's current meeting is #12 taught by the
second-half lecturer; and after a manual absen the app never reflected it
(production even had `hadir` on meeting #16 while today's #12 stayed
`pending`).

## 2. Root Causes

1. **Meeting numbering desync**: the poller synced meetings from the semester
   matrix page (`jadwal_kuliah/index`) whose columns are chronological, and
   mapped column position to meeting number. Simkuliah's official numbering
   follows the today page (`jadwal_kuliah_hari_ini`); the two diverge whenever
   a week is skipped (SINF6045 skipped 21-09), shifting every meeting_date by
   one week.
2. **Stale dashboard cache**: `_last_dashboard_html` was fetched once and
   cached forever, and only the first absensi card was parsed regardless of
   course, so open-presence state was attributed to the wrong course and
   froze at the first tick's snapshot.
3. **Broken status persistence**: `record_meeting_status` inserted a new
   meetings row keyed by `schedule_id` and was never invoked;
   `deadline_at`/`lecturer_opened_at` were never persisted, so the client's
   `isPresenceOpen` was always false.
4. **Schedule-level lecturer**: split-semester courses change lecturer per
   meeting; the app showed the one lecturer scraped for the schedule row.

## 3. Implementation Checklist

- [x] `parse_meeting_matrix`: parses the today-page matrix, mapping column
      position to the official meeting number; each cell yields its real
      date, per-meeting lecturer, and attendance color. Cells without a
      parsable date are skipped (never guessed as "today" — the original
      corruption vector).
- [x] `parse_attendance_cards`: parses every dashboard absensi card (several
      sessions can be open at once); `parse_attendance_status` becomes a
      backward-compatible wrapper over it.
- [x] Poller: `_sync_meetings_from_today` reuses the schedule HTML already
      fetched each tick (no extra HTTP) and upserts meetings on
      `(schedule_id, meeting_number)` with date, `lecturer_name`, and status.
- [x] Poller: dashboard re-fetched every tick; cards matched to schedule
      items by course code; card data persisted through a rewritten
      `record_meeting_status` (proper upsert: `last_polled_at`,
      `deadline_at` with the machine's timezone offset, `lecturer_opened_at`
      only when open, `simkuliah_status='hadir'` when already absen).
      Missing keys are omitted so a closed card never clears earlier state.
- [x] `resolve_schedule_id` fallback for cards without a konfirmasi button
      ("anda sudah absen" renders no button, hence no schedule id).
- [x] Migration `20261109120000_meetings_lecturer_name.sql` (additive,
      idempotent).
- [x] Client: `MeetingModel` prefers the meeting-level `lecturer_name`,
      falling back to the schedule-level value.
- [ ] Pending approval: apply the migration to production; one-off
      self-healing sync run.

## 4. Data Self-Healing

The corrected sync overwrites every meeting row it writes (all 16 meetings
per course, every tick), so the shifted dates, the misplaced `hadir` on
meeting #16, and the stale lecturers repair themselves on the first tick
after deploy.

## 5. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| `ruff check .` / `ruff format --check .` | PASS | Backend |
| `pytest -q` | PASS | 115 tests incl. matrix/card/db/poller |
| `flutter analyze --no-pub` | PASS | Client |
| `flutter test` | PASS | 37 tests incl. lecturer fallback |
| `verify_pipeline.py --fast` | PASS | Full local gate |
| `flutter build linux --dart-define-from-file=.env` | PASS | Desktop release |
| Live parser check vs fetched Simkuliah HTML | PASS | SINF6045 P12 = 2026-11-09, Fathia Sabrina, hadir |
