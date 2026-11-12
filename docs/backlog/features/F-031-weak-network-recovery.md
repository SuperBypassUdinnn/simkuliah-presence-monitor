# Feature Log: F-031 Weak-Network Recovery and Hung-Request Resilience

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: Owner report (chat + screenshot, 2026-11-12) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Owner report (2026-11-12, screenshot `Screenshot_20261112_173508.png`): after
internet connectivity became unstable and stabilized ~2 hours later, the app
remained permanently stuck on the loading spinner (`CircularProgressIndicator`)
on `Presensi Aktif` (and failed to refresh), requiring a process kill and
restart to recover.

Root causes identified and reproduced via Toxiproxy simulation:

1. **Unbounded Supabase queries**: `PresenceService` methods (`fetchTodaysMeetings`,
   `fetchSemesterMatrix`, `fetchMeetingsForSchedule`, `submitOverride`,
   `clearOverride`) had no `.timeout(...)`, allowing half-open/zombie TCP sockets
   after a 2-hour outage to hang indefinitely.
2. **Rigid `_fetchInFlight` lockout**: `ActivePresenceView`, `TodayFeedView`,
   and `SemesterMatrixView` used a boolean `_fetchInFlight` flag that silently
   dropped every `RefreshBus` / focus / retry event while an earlier request was
   stalled, locking the UI on `CircularProgressIndicator` forever.
3. **No stream reconnect on `RealtimeAlertService`**: Supabase Realtime stream
   `onError` only called `debugPrint` and `onDone` was unhandled, so WebSocket
   drops left desktop alerts and automatic UI refreshes dead until restart.

## 2. Implementation Checklist

- [x] **`PresenceService` hard timeout + transient retry**:
      wrap Supabase read/override operations with `_runWithResilience` (10s
      configurable `requestTimeout` default, plus 1 fast retry after 300ms on
      reads for `TimeoutException`, `SocketException`, or `http.ClientException`;
      writes use the 10s deadline with `retry: false`).
- [x] **Epoch-isolated view loading (`LoadEpochGuard` across `ActivePresenceView`, `TodayFeedView`, `SemesterMatrixView`)**:
      extract `LoadEpochGuard` (`client/lib/core/load_epoch_guard.dart`) so
      `force: true` refreshes (tab switch, focus resume, pull-to-refresh,
      retry) or stale in-flight requests (`>= requestTimeout`) advance the epoch
      and discard late completions from abandoned sockets.
- [x] **Pull-to-refresh & outage recovery**:
      add `AlwaysScrollableScrollPhysics` to `ListView`/`SingleChildScrollView`
      inside `RefreshIndicator` across all views, and trigger `RefreshBus`
      automatically when `TodayFeedView` detects backend health recovery from
      `backendDown` to `ok`.
- [x] **`RealtimeAlertService` exponential backoff + jitter reconnect**:
      handle both `onError` and `onDone` with a single-timer guard, exponential
      backoff up to 60s + jitter, reset attempts only after a live snapshot
      arrives, and broadcast `RefreshBus.instance.requestRefresh()` on recovery.
- [x] **Weak-network test pyramid (`weaknet_recovery_test.dart` + `network_resilience_test.dart` + `presence_service_test.dart`)**:
      Toxiproxy live simulation (stalled 30s socket, full outage, slow jittery
      3G, mid-stream TCP timeout cut) plus deterministic unit/widget suites
      verifying hung `Completer` abandonment, single-timer stream reconnect, and
      loopback `HttpServer` timeout + retry.

## 3. Verification

- `python3 scripts/verify_pipeline.py` passes (ruff check, ruff format,
  backend pytest 151 tests, flutter analyze, dart format).
- `flutter test` passes 90 deterministic tests (+ 4 Toxiproxy tests skipped in
  bare CI without `WEAKNET_PROXY_URL`).
- Live Toxiproxy simulation (`ghcr.io/shopify/toxiproxy:latest`) passed all 4
  fault scenarios (`weaknet_recovery_test.dart`).
