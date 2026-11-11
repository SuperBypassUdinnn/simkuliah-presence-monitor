# Feature Log: F-026 Matrix Fit, Refresh Button Removal, Phantom Class Group

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: Owner request (chat + screenshots, 2026-11-11) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Three owner-reported items on the desktop client:

1. The AppBar refresh button is redundant with the existing silent
   refresh mechanism.
2. The semester matrix overflows the default window: with the 250px
   sidebar, the row chrome (250 + 24 page padding + 240 name + 608
   meetings + 12 gap + 150 recap = 1284) exceeds the 1280px default
   Flutter desktop window, clipping the right edge of the recap column.
3. A second, empty "PRAKTIKUM KECERDASAN ARTIFISIAL" row
   (SINF3033 Kelas A) appears in the matrix next to the real one
   (SINF3033 Kelas C).

## 2. Root Cause Analysis (item 3)

`upsert_schedules` hardcoded `"class_group": "A"` in its payload, while
`parse_daily_schedule` stripped the row's "(Kelas : X)" paren without
capturing it. When SINF3033 (real group C) appeared in a today-page
parse, the upsert key `(SINF3033, A, 20261)` matched nothing and inserted
a phantom schedule row. Only one phantom existed because courses whose
real group is A merge into their own row; every non-A course seen on a
today page was at risk. The phantom row has no meetings, so the client
rendered 16 fabricated Pending tiles for it.

## 3. Implementation Checklist

- [x] **Refresh button removed** from all three AppBars (Presensi Aktif,
      Jadwal Hari Ini, Matriks Semester). Auto-refresh already covers the
      dominant paths: silent refetch on window-focus regain
      (`didChangeAppLifecycleState.resumed`) and on every tab switch
      (RefreshBus). Known accepted gap: a window left focused and
      untouched for a long stretch does not refetch until focus changes.
      The error screens' "Coba Lagi" button is unrelated and stays.
- [x] **Matrix compaction**: column layout moved into shared constants
      (`_nameColumnWidth` 240 -> 190, `_meetingColumnWidth` 38 -> 35,
      `_recapColumnWidth` 150 -> 130, `_recapGap` 12) used by both the
      header and every course row. New row footprint: 250 + 24 + 16 +
      190 + 560 + 12 + 130 = 1182 <= 1280, with ~100px slack. Widget test
      renders the matrix inside a 1280x720 viewport with a 250px sidebar
      and asserts the recap column ends inside the window (widget tests
      fail on any RenderFlex overflow).
- [x] **Class group parsed, not hardcoded**: `ParsedScheduleItem` gains a
      `class_group` field (default "A"), `parse_daily_schedule` extracts
      it from the row's "(Kelas : X)" paren, and `upsert_schedules` uses
      it — the upsert key now matches the course's real row instead of
      phantom-creating an "A" twin.
- [ ] **Phantom row cleanup** (live Supabase): schedule id 20 (SINF3033,
      Kelas A, zero meetings) — deletion prepared, pending owner approval;
      no meetings reference it so the delete is a single row with no
      cascade effects.

## 4. Design Notes

- The matrix tile itself stays 32px; the column shrinks to 35px (3px
  spacing) which keeps the tap target and the header numbers legible.
- The recap column's `Flexible` + ellipsis (F-022) absorbs the narrower
  130px column; "10/12 hadir" plus the percentage still fit.
- Courses whose real group is not A are now upsert-safe; the one live
  phantom is removed at the source so no client-side filtering is needed.

## 5. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| Backend `pytest tests/test_parser.py tests/test_database.py` | PASS | 2 new parser tests (paren captured, default A) |
| Flutter Static Analysis | `flutter analyze --no-pub` | PASS |
| Flutter Tests | `flutter test` | PASS (70 tests; new 1280x720 fit test) |
| `python3 scripts/verify_pipeline.py --fast` | PASS | Full gate green |
| Live data check | Supabase REST | Phantom SINF3033/A row confirmed (id 20, 0 meetings); deletion prepared, awaiting owner approval |
