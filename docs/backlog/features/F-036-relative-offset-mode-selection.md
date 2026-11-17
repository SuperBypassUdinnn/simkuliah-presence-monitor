# Feature Log: F-036 Relative Offset Mode Selection Fix

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: Owner report (chat, 2026-11-17) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

In the "Pengaturan & Automasi" tab, tapping "Relatif" under "Penyesuaian Waktu"
immediately reverted to "Asli" for any course starting at official schedule
timing. The relative offset chips were never shown, making the relative offset
feature completely unusable from the UI.

## 2. Root Cause Analysis

In `client/lib/views/settings_automation_view.dart`:

1. `_timingModeFor(cust)` derives `_TimingMode` strictly from `cust`:
   - `customStartTime != null && customEndTime != null` -> `_TimingMode.absolute`
   - `timeOffsetMinutes != 0` -> `_TimingMode.relative`
   - otherwise -> `_TimingMode.official` ("Asli")
2. When the user tapped the "Relatif" segment, `_selectTimingMode` called
   `_saveCourseCustomization(schedule, clearAbsolute: true)` without passing
   `timeOffsetMinutes`.
3. In `_saveCourseCustomization`, `timeOffsetMinutes` defaulted to
   `base.timeOffsetMinutes`, which was `0`.
4. The customization was persisted with `timeOffsetMinutes: 0`.
5. On the subsequent rebuild, `_timingModeFor(saved)` saw
   `timeOffsetMinutes == 0`, returning `_TimingMode.official`.
6. As a result, the SegmentedButton snapped back to "Asli" and the relative
   offset chips were hidden.

Furthermore, `0` was listed in the relative quick offset chips
(`[-30, -15, 0, 15, 30, 60, 120]`). Selecting `0m` inside relative mode
saved `timeOffsetMinutes: 0`, which also triggered the collapse back to "Asli".

## 3. Implementation

- [x] **Default non-zero offset on switching to Relatif (`client/lib/views/settings_automation_view.dart`)**:
      In `_selectTimingMode`, selecting `_TimingMode.relative` now passes
      `(cust != null && cust.timeOffsetMinutes != 0) ? cust.timeOffsetMinutes : 15`.
      If the course already had a non-zero offset, it is retained; otherwise,
      it defaults to `+15m`.
- [x] **Non-zero relative offset chips (same file)**:
      The quick chips under "Relatif" are `[-30, -15, 15, 30, 60, 120]`,
      plus an extra chip if the course carries a non-zero custom offset.
      Selecting `Asli` on the SegmentedButton or clicking "Reset Jadwal Asli"
      remains the explicit way to return to official portal time (0 offset).
- [x] **Widget test verification (`client/test/settings_automation_view_test.dart`)**:
      Added a test verifying that tapping "Relatif" on an official course
      saves `timeOffsetMinutes: 15`, reveals the relative chips with `+15m`
      selected, allows tapping `+30m` to update, and tapping "Asli" resets to 0
      and hides the chips.

## 4. Verification Matrix

| Check | Command | Result |
| :--- | :--- | :--- |
| Lint/format (fast pipeline) | `python3 scripts/verify_pipeline.py --fast` | PASS |
| Settings view test suite | `flutter test test/settings_automation_view_test.dart` | 5 passed |
| Full client test suite | `flutter test` | 105 passed, 4 skipped |
| Client analyze | `flutter analyze --no-pub` | 0 issues |
| Backlog parity check | `python3 scripts/sync_backlog_status.py --check` | PASS |
