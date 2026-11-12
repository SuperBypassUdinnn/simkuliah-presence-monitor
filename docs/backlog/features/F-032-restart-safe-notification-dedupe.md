# Feature Log: F-032 Restart-Safe Notification Dedupe

- **Parent Plan**: [`.planning/04-hybrid-push-notifications.md`](../../../.planning/04-hybrid-push-notifications.md)
- **Target Issue**: Owner report (chat + screenshot, 2026-11-12) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Owner report (2026-11-12, screenshot `Screenshot_20261112-194126.jpg`): the
Android notification shade showed the **same** "Presensi Ditutup -
PRAKTIKUM PROTOKOL JARINGAN MAJU (SINF6075)" notification **twice** at
different times (~19:01 and ~19:28 WIB, 27 minutes apart).

Root cause: the poller's monotonic notification guard (`_last_levels`) lives
only in process memory. Every Render redeploy (PR #52/#53/#54/#55 merged the
same day) or free-tier container restart wipes it, so the state machine
re-dispatches `WINDOW_EXPIRED` for any meeting already past its end time —
producing a duplicate push on each restart.

## 2. Implementation Checklist

- [x] **`DatabaseRepository.load_notified_levels(meeting_ids)`**: returns the
      highest dispatched `state_level` per meeting id from the (pre-existing,
      unused) `notification_logs` table.
- [x] **`DatabaseRepository.list_today_meeting_ids(now)`**: returns today's
      meeting ids used to preload the dedupe map.
- [x] **`DatabaseRepository.log_notification(meeting_id, state_level)`**:
      inserts one row per dispatched notification.
- [x] **`AdaptivePoller._notified_ranks` + `_load_notified_ranks(now)`**:
      refresh the map each tick; when an in-memory `_last_levels` entry is
      absent but `notification_logs` has a dispatch record, the guard is
      seeded from it so a restarted poller does not re-fire.
- [x] **Stricter monotonic guard**: skip re-dispatch when the previous level's
      rank is >= the candidate's (previously only equal levels were skipped).
- [x] **Restart-safe state seed**: live `notification_logs` rows for today's
      meetings were pre-seeded manually so the production restart after this
      deploy does not re-fire for SINF3031 (P13) and SINF6075 (P11) whose
      windows already expired.

## 3. Verification

- `python3 scripts/verify_pipeline.py` passes (ruff check, ruff format,
  backend pytest 153 tests, flutter analyze, dart format).
- New backend tests: a restarted poller seeded from `notification_logs`
  (state_level 4) does not re-dispatch `WINDOW_EXPIRED`; a new dispatch writes
  `log_notification(183, 4)` and populates `_notified_ranks`.
