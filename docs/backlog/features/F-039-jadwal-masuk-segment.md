# F-039 — Jadwal Masuk Weekly Timetable (Segmented Jadwal Tab)

- **Status**: In Progress
- **Date**: 2026-11-21
- **Parent Plan**: `.planning/01-architecture-mvp.md`
- **Issues**: owner-requested navigation design 2026-11-21 (no GitHub issue)

## Summary

Adds a "Jadwal Masuk" (weekly class-entry timetable) without growing the
Android bottom navigation bar to five destinations. Decision taken with the
owner among three options (dedicated fifth tab, settings-to-appbar-gear,
segment inside Jadwal): the **segmented control inside the Jadwal tab** was
chosen — both lenses cover the same schedule domain and the bottom bar stays
at four destinations on mobile while the desktop sidebar is unchanged.

## Changes

- `lib/views/widgets/weekly_timetable.dart` (new): fetches the semester
  schedules, derives each course's class day from its meeting dates
  (majority weekday; Simkuliah has no explicit day field), groups courses
  into Senin..Minggu sections (unknown-day bucket rendered last), sorts each
  day by effective start time, marks today's section with a `Hari ini`
  badge, and shows the effective lecture window (absolute override or
  offset) with the portal window as a secondary hint.
- `lib/views/today_feed_view.dart`: segmented button (`Absen | Masuk`) at
  the top of the Jadwal tab; the app bar title follows the active lens
  (`Jadwal Kuliah Hari Ini` / `Jadwal Masuk Mingguan`); the presence feed
  and its health banner remain untouched under the `Absen` segment.

## Verification Matrix

| Target / Stack | Command Executed | Result |
| :--- | :--- | :--- |
| Jadwal tab segment switch + weekly sections | `flutter test test/today_feed_view_test.dart` | PASS (5 tests, 1 new) |
| Automated Pipeline Gate | `python3 scripts/verify_pipeline.py --fast` | PASS |
| Backlog parity | `python3 scripts/sync_backlog_status.py --check` | PASS |
