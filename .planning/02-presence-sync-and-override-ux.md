# Plan 02: Presence Sync & Override UX

- **Target Issues**: #5, #6, #7
- **Status**: In Progress
- **Primary Stack**: Cross-stack

## 1. Context & Objectives
Close the gap between the local attendance view and the authoritative Simkuliah
semester matrix, while making every manual status visually unambiguous.

## 2. Architectural Boundaries & Decisions
- The backend poller owns reconciliation with Simkuliah; the client only reads
  Supabase and submits manual overrides.
- `hadir` from Simkuliah always supersedes a local override.
- Manual override keys stay lowercase snake_case in the database; presentation
  labels are resolved in one shared client palette.
- The semester matrix remains a read-only projection; overrides are written
  through the existing service boundary.

## 3. Implementation Steps
- [x] Add `lupa_absen` and `dosen_tidak_absen` to the backend enum and webhook validation.
- [x] Widen `local_overrides.override_type` through a Supabase migration.
- [x] Add a shared override palette (label, letter, color, icon) in the client.
- [x] Render distinct matrix indicators and override chips.
- [x] Reconcile the semester matrix from the poller every cycle.
- [x] Refresh the active client view on tab focus and window resume.
- [x] Normalize status labels and improve dialog contrast.
- [x] Polish override chip legibility in the today feed (F-008).
- [x] Replace bottom snackbars with top-right status notifications (F-009).

## 4. Verification Gate
```bash
python3 scripts/verify_pipeline.py
python3 scripts/sync_backlog_status.py --check
```
