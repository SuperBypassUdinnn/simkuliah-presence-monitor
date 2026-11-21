# F-038 — Settings Course Filter, Matrix Day Detail, and Dialog UX

- **Status**: In Progress
- **Date**: 2026-11-21
- **Parent Plan**: `.planning/01-architecture-mvp.md`
- **Issues**: owner-reported UX batch 2026-11-21 (no GitHub issue)

## Summary

Three owner-reported improvements to the client UX, plus a design discussion
item (jadwal masuk navigation) tracked separately:

1. **Settings course filter + search** (`settings_automation_view.dart`):
   a search field filtering by course name (case-insensitive) and
   Semua / Praktikum / Teori filter chips, where praktikum detection matches
   the course name the same way Simkuliah names its lab courses.

2. **Matrix detail day row** (`meeting_grid_tile.dart`): the meeting detail
   dialog gains a `Hari` row resolved from the meeting date (Simkuliah
   carries no explicit day-of-week field; unparseable dates render `-`).

3. **Dialog vertical centering + past-meeting validation**: both dialogs cap
   their content height at 65% of the viewport so short content renders as a
   compact vertically centered dialog and long content scrolls internally
   instead of stretching edge-to-edge. The auto-absen selection dialog locks
   meetings that have already happened (date before today, or today with the
   official lecture window ended): their switches are disabled with a
   "Sudah lewat" marker, and the Pilih Semua / Batalkan Semua shortcut only
   touches meetings that have not happened yet. Unparseable dates fail open
   and stay editable.

## Verification Matrix

| Target / Stack | Command Executed | Result |
| :--- | :--- | :--- |
| Settings widgets (filter, search, dialog lock) | `flutter test test/settings_automation_view_test.dart` | PASS (10 tests) |
| Matrix day row | `flutter test test/semester_matrix_widget_test.dart` | PASS |
| Full client suite | `flutter test` | PASS |
| Automated Pipeline Gate | `python3 scripts/verify_pipeline.py --fast` | PASS |
