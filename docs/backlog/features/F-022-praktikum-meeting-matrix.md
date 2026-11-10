# Feature Log: F-022 Praktikum Meeting Matrix Cap

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: Owner request (chat, 2026-11-10) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Praktikum courses only have 12 meetings in Simkuliah, but the semester
matrix rendered up to 16 meeting tiles for them. Investigation against the
live Supabase data showed the meetings table is already correct: every
`PRAKTIKUM*` course has exactly 12 meeting rows and theory courses have 16.
The 13-16 cells were client-fabricated `Pending` placeholders from
`List.generate(16)` in `_buildCourseRow`, not database rows. Side effect:
the recap divided praktikum attendance by 16 (e.g. 10 attended showed as
"10/16 hadir", 63%) instead of by the course's real length (83%).

Scope: client matrix rendering only. No data deletion is needed; the
backend parser and database already mirror Simkuliah's per-course column
counts.

## 2. Implementation Checklist

- [x] **Per-course semester length, data-driven**: `_buildCourseRow`
      derives the length from the highest synced `meetingNumber`
      (praktikum -> 12, theory -> 16), falling back to 16 when a course
      has no meetings yet. No course-name matching.
- [x] **Symmetric grid**: the grid stays 16 columns wide (header numbers
      1-16 unchanged). Columns beyond a course's semester length render as
      a neutral, non-clickable faint dash placeholder in the same 38px
      column, so praktikum rows span exactly the same width as theory rows.
- [x] **Recap correctness**: attendance percentage and the "x/y hadir"
      label divide by the course's real semester length instead of the
      fixed 16, and the progress bar reflects the corrected ratio.
- [x] **Recap overflow hardening**: the recap count is wrapped in
      `Flexible` with ellipsis so a long label or an enlarged system text
      scale truncates instead of overflowing the 150px recap column
      (surfaced by the new widget test's font metrics).
- [x] **Widget test**: a `PresenceService` fake feeds a 12-meeting
      praktikum-style course and a 16-meeting theory course; asserts 12+16
      tiles, exactly 4 dash placeholders, and the corrected recaps
      ("10/12 hadir" / 83% vs "8/16 hadir" / 50%).

## 3. Design Notes

- Within `1..semesterLength`, meeting numbers lacking a database row still
  pad as `Pending` placeholders (holes from skipped weeks), unchanged.
- The dash placeholder can never render for a meeting number at or below
  the semester length; `number > semesterLength` is the only null path.
- Theory courses render byte-identically to before: `syncedMax = 16`
  produces the same 16 tiles and a `/16` recap.
- If Simkuliah ever publishes more than 16 meetings for a course, the
  pre-existing clipping at 16 applies unchanged (out of scope).

## 4. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No issues |
| `dart format --output=none --set-exit-if-changed .` | PASS | 0 changed |
| `flutter test` | PASS | 44 tests (43 existing + 1 new) |
| Supabase data audit | PASS | All 7 `PRAKTIKUM*` schedules have exactly 12 meeting rows; theory have 16 |
| `python3 scripts/verify_pipeline.py --fast` | PASS | Full gate green |
| `python3 scripts/sync_backlog_status.py --check` | PASS | Parity verified |
| Two-axis code review (Standards + Spec) | PASS | No blocking findings |
