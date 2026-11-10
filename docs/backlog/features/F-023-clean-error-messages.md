# Feature Log: F-023 Clean Error Messages and Health Detection

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: Owner request (chat, 2026-11-10, screenshot from the field) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

The Android client showed the raw exception blob on the "Presensi Aktif"
screen when the device was offline:

> Gagal memuat status presensi: ClientException with SocketException:
> Connection failed (OS Error: Network is unreachable, errno = 101),
> address = ftznonanlbshweysliar.supabase.co, port = 443, uri=...

Owner request: replace it with a clean message, and sweep the other error
paths (Simkuliah gateway/timeout, backend/database unreachable, and other
possible failures) with clean messages too.

Audit of the client found six error surfaces printing `error.toString()`:
three full-screen error bodies (`ActivePresenceView`, `TodayFeedView`,
`SemesterMatrixView`) and three snackbars in `ActiveLectureCard`. Two
further gaps: the override dialog in `MeetingGridTile` had no error
handling at all (network failures vanished silently), and the
`GatewayAlertBanner` was dead scaffolding, hardcoded to `hasOutage: false`.

## 2. Implementation Checklist

- [x] **Central exception mapper** (`client/lib/core/error_message.dart`):
      classifies errors into seven buckets and returns a clean Indonesian
      message: no internet (errno 101/113, DNS lookup), server unreachable
      (refused/reset/closed), timeout (errno 110, `TimeoutException`),
      server error (`PostgrestException`, 5xx text), auth rejected
      (`AuthException`), invalid data (`FormatException`), and unexpected.
      `errorDetail(error)` keeps the raw text for diagnosis.
- [x] **Shared `ErrorStateView`**: deduplicates the three identical
      icon-plus-raw-error bodies. Renders the title, the friendly message,
      the retry button, and an opt-in expandable "Detail teknis" section
      (selectable raw error, collapsed by default).
- [x] **Snackbar messages** (`ActiveLectureCard`): presence confirmation,
      override save, and override cancel now show
      `friendlyErrorMessage(error)` instead of the raw blob.
- [x] **Override dialog guard** (`MeetingGridTile`): submit/cancel wrapped
      in try/catch; on failure the dialog closes and a notification shows
      the friendly message (previously the error was swallowed).
- [x] **Backend health reporting** (`/api/v1/health` now returns
      `simkuliah_status`): the poller tracks `last_success_at`; the health
      router reads the registered poller via the new
      `app/core/runtime.py` holder (avoids the main-router circular
      import) and reports `ok` / `degraded` (fetches failing) / `pending`
      (no tick since startup) / `unknown` (mock builds).
- [x] **Client health probe** (`client/lib/services/backend_health_service.dart`):
      GET `/health` with an 8s timeout and one retry (Render cold start),
      classified into ok / Simkuliah degraded / backend down with a
      ready-to-display banner message; unconfigured base URLs (desktop
      without backend) short-circuit to ok.
- [x] **Gateway banner wired** (`TodayFeedView`): the banner slot now uses
      the real health probe, checked on load and on refresh-bus events
      (throttled to one probe per minute); a degraded or unreachable
      backend shows the warning banner while the cached feed stays visible.

## 3. Design Notes

- The raw error is never the primary message anywhere; it stays one tap
  away ("Detail teknis") for diagnosis and bug reports.
- Upstream Simkuliah failures (gateway 502/504, CAPTCHA loops) are
  invisible to the client by design: the poller swallows them into log
  warnings and the data goes stale. The new `simkuliah_status` field makes
  that state observable; the incidents table exists but has no writers
  yet (candidate future work: record incidents on poller failure).
- Health probes are fire-and-forget: they never block the feed render,
  never throw, and throttle to one per minute.

## 4. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No issues |
| `dart format --output=none --set-exit-if-changed .` | PASS | 0 changed |
| `flutter test` | PASS | 69 tests (9 new: mapper 11, health service 8, ErrorStateView 3, feed banner 3) |
| Backend `pytest tests/test_webhooks.py` | PASS | Health tests: ok/pending, degraded, ok-after-sync |
| `python3 scripts/verify_pipeline.py --fast` | PASS | Full gate green |
| `python3 scripts/sync_backlog_status.py --check` | PASS | Parity verified |
