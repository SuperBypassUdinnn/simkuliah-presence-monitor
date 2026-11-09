# Feature Log: F-007 Tab Focus Refresh & Status Polish

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: #7
- **Status**: In Progress
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope
Switching tabs left stale data on screen, raw `tidak_hadir` text leaked into the
UI, and confirmation dialog buttons had weak contrast. Refresh on focus and
normalize the presentation layer.

## 2. Implementation Checklist
- [x] Add `WidgetsBindingObserver` refresh on window resume.
- [x] Rebuild the selected view through per-tab `ValueKey`s.
- [x] Format snake_case statuses as human-readable labels.
- [x] Force white bold text on confirmation buttons.
- [x] Propagate parent course metadata into nested meetings.

## 3. Objective Verification Matrix
| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter test` | PASS | Refresh and formatting tests green |
| `flutter analyze --no-pub` | PASS | No warnings |
| `dart format --set-exit-if-changed .` | PASS | Formatted |
| `python3 scripts/verify_pipeline.py` | PASS | Full local gate |
