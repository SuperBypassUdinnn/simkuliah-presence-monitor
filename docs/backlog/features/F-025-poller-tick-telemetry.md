# Feature Log: F-025 Poller Tick Telemetry

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: Follow-up to F-024 verification (chat, 2026-11-11) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

While verifying F-024 in production, the health endpoint flipped
`simkuliah_status` from `degraded` to `ok` (the new session login worked
from Render), but the database showed **nothing was written**: the
`record_meeting_status` path's `last_polled_at` stayed frozen at
2026-11-09 04:48 UTC, the matrix-sync-owned `lecturer_name` column stayed
NULL on every row it owns, and the 2026-11-10/11 statuses remained
`pending`.

Root cause of the blindness: `_tick` sets `last_success_at` immediately
after the fetch succeeds — **before** parse and persistence. Any failure
in the parse/persist stage crashed the tick, APScheduler logged it where
nobody can see it (no Render log access), and the health endpoint kept
reporting the cycle as healthy. A "successful fetch that persists
nothing" is undetectable from the outside.

Scope: per-stage tick telemetry exposed through `/health`, and the
parse/persist stage recorded instead of silently crashing. No behavior
change for the happy path.

## 2. Implementation Checklist

- [x] **Tick telemetry** (`AdaptivePoller.last_tick`): recorded per stage —
      `at`, `html_bytes`, `page_title` (identifies which page a
      "successful" fetch actually returned: login page, dashboard, or
      schedule matrix), `items` (parsed schedule rows),
      `matrix_courses` / `meetings_synced` (matrix sync), and per-stage
      `error` / `matrix_error`.
- [x] **Parse/persist guard**: a failure in `parse_daily_schedule`,
      `upsert_schedules`, or the matrix sync is now recorded and stops the
      tick cleanly instead of crashing into APScheduler's invisible log.
- [x] **`/health` exposure**: `last_tick` is included when the registered
      poller is a real `AdaptivePoller` (mock builds omit it).
- [x] **Tests**: telemetry on a successful tick; parse/persist failure
      recorded without crashing (dispatcher untouched); matrix-sync error
      recorded as `matrix_error`; `/health` includes `last_tick`.

## 3. Design Notes

- Telemetry lives in the poller process only; no schema or API-contract
  changes beyond an additive `/health` field.
- The page title is truncated to 120 chars and contains no personal data;
  it exists to distinguish "login page returned" from "schedule matrix
  returned" at a glance.
- The next diagnostic step after deploy is reading `/health last_tick` on
  the live service: it will show whether the fetched page is the expected
  matrix (and whether the failure is parse, schedule upsert, or matrix
  upsert), turning the remaining unknown into a one-request diagnosis.

## 4. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| Backend `pytest tests` | PASS | Full suite, 4 new tests |
| `python3 scripts/verify_pipeline.py --fast` | PASS | Full gate green |
