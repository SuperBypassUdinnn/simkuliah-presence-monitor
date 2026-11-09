# Feature Log: F-010 Stacked Status Notifications

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: #13
- **Status**: In Progress
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope
Rapid status changes produced overlapping notification cards because every
message rendered at the same fixed position. Introduce a notification manager
that stacks newer messages below older ones and reflows on dismissal.

## 2. Implementation Checklist
- [x] Track active notifications in one manager and a single overlay entry.
- [x] Render a vertical stack with `AnimatedSize` reflow.
- [x] Keep per-card enter animation, auto-dismiss, progress bar, and close.
- [x] Cover stacked ordering and cleanup with widget tests.

## 3. Objective Verification Matrix
| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No warnings |
| `dart format --output=none --set-exit-if-changed .` | PASS | Formatted |
| `flutter test` | PASS | 10 tests incl. stacking order |
| `python3 scripts/verify_pipeline.py` | PASS | Full local gate |
