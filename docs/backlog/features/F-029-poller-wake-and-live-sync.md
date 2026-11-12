# Feature Log: F-029 Poller Pre-Class Wake, On-Demand Sync, and Local Deadline Conversion

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: Owner report (chat, 2026-11-12) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Real-device / desktop report (2026-11-12, 10:06 WIB, SINF3031 Kecerdasan
Artifisial): the lecturer had already opened presence on Simkuliah (Pertemuan
ke-13, deadline 10:31 WIB), yet the desktop monitor still displayed "Dosen
Belum Melakukan Presensi" even after refreshing and restarting the app several
times.

Live inspection revealed four compounding failures:

1. **Installed desktop bundle was stale (`1.0.3+2`, built 2026-11-11 05:19)**:
   the running executable at `~/.local/share/simkuliah-monitor/` lacked the
   F-027 closed-window banner/time fixes and F-028 native desktop notifications.
2. **Poller overslept past the lecture start**: the last Render tick ran at
   01:43 UTC (08:43 WIB) when no class was active (SINF3031 starts 09:50 WIB),
   and `calculate_next_poll_interval` returned the full 7200-second (2-hour)
   idle interval, sleeping straight past 09:50, lecturer opening, and 10:31
   deadline. Moreover, `render.yaml` uses the free tier (`plan: free`), which
   spins down after 15 minutes with no HTTP traffic.
3. **App startup/refresh did not wake or wait for a backend sync**: the client
   only probed `GET /api/v1/health` passively while loading Supabase in parallel,
   so waking or restarting the app never triggered a Simkuliah sync and never
   refetched once a wake-up sync wrote new data.
4. **Client UTC deadline & unhydrated realtime stream**: `MeetingModel.fromJson`
   parsed `deadline_at` (`+00:00` from PostgREST) without `.toLocal()`,
   leaving `.hour`/`.minute` in UTC, and `RealtimeAlertService` parsed raw
   stream rows from `meetings` without joining `schedules` or `local_overrides`,
   causing missing course names and missing schedule windows.

## 2. Implementation Checklist

- [x] **Pre-class wake in `calculate_next_poll_interval`**: when idle before an
      upcoming lecture today, cap the sleep interval at the seconds remaining
      until `start_time - 10m` (pre-class observation entry), rather than
      sleeping 2 hours past the lecture start.
- [x] **On-demand poller wake (`trigger_if_stale` + `?sync=true`)**:
      `AdaptivePoller` serializes ticks via `_tick_lock` and updates
      `last_success_at` after live-state persistence completes.
      `GET /api/v1/health?sync=true` calls `trigger_if_stale(max_age_seconds=30)`
      and returns `"synced_now": true` when a fresh sync ran, while plain
      `GET /api/v1/health` remains instant for Render's liveness probe.
- [x] **Client auto-refresh on sync & Render keep-alive**:
      `BackendHealthService.check()` calls `/api/v1/health?sync=true` with a
      20s timeout; `TodayFeedView` triggers `RefreshBus.instance.requestRefresh()`
      when `syncedNow` is true and runs a lightweight `keepAlive()` probe every
      5 minutes when configured so the free-tier backend stays awake while the
      client runs.
- [x] **Local deadline & realtime stream hydration**:
      `MeetingModel.fromJson` converts `deadline_at` via `.toLocal()`;
      `RealtimeAlertService._handleRows` hydrates full rows via
      `PresenceService.fetchTodaysMeetings` and requests a UI refresh via
      `RefreshBus`.
- [x] **Rebuild & reinstall the local Linux desktop bundle** to
      `~/.local/share/simkuliah-monitor/` and restart the running client so the
      installed app runs the latest code (F-027, F-028, F-029).

## 3. Verification

- `python3 scripts/verify_pipeline.py` passes (ruff check, ruff format,
  backend pytest 142 tests, flutter analyze, dart format).
- Client test suite: 81 tests pass, covering pre-class interval clamping,
  `trigger_if_stale`, `/api/v1/health?sync=true`, UTC-to-local deadline parsing,
  `syncedNow` refresh trigger without loops, and `keepAlive()`.
- Live backend verification: manually ran sync and verified Supabase row `id=57`
  (`SINF3031` P13) persisted `lecturer_opened_at` and `deadline_at` (`03:31 UTC`
  = `10:31 WIB`).
