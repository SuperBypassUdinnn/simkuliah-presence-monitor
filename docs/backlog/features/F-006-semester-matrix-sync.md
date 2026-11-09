# Feature Log: F-006 Simkuliah Semester Matrix Synchronization

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: #6
- **Status**: In Progress
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope
Local attendance could drift from the Simkuliah portal because the poller only
inspected today's schedule cards. Reconcile the full semester matrix on each
poll cycle and keep `hadir` authoritative.

## 2. Implementation Checklist
- [x] Parse `#simpletable` rows and map cell classes to attendance statuses.
- [x] Upsert meetings by `(schedule_id, meeting_number)`.
- [x] Add periodic `_sync_semester_matrix()` to `AdaptivePoller`.
- [x] Remove stale overrides when Simkuliah records attendance.
- [x] Preserve parent course metadata in nested meeting payloads.

## 3. Objective Verification Matrix
| Command | Result | Notes |
| :--- | :--- | :--- |
| `pytest -q` | PASS | Poller and parser suites green |
| `ruff check backend` | PASS | No import or style issues |
| `python3 scripts/verify_pipeline.py` | PASS | Full local gate |
