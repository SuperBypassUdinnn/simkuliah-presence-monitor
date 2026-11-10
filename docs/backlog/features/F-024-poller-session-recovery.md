# Feature Log: F-024 Poller Session Recovery

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: Owner report (chat, 2026-11-11) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Minutes after F-023 shipped the gateway banner, the owner's desktop app
showed "Simkuliah sedang bermasalah" while Simkuliah itself worked fine in
the owner's browser. Diagnosis against live data:

- The backend poller had not successfully synced since 2026-11-09
  04:48 UTC (~25 hours): every meeting row dated 2026-11-10/11 was still
  `pending` although those classes had happened.
- Root cause: `SimkuliahClient` keeps `ci_session` only in an in-memory
  cookie jar, and **no production code path ever calls `login()`** (the
  `SimkuliahAuth` wrapper was built in 9067dfc but never wired in). After
  any deploy/restart (cookie jar lost) or server-side session expiry, every
  schedule fetch gets a sessionless `HTTP 307` redirect with an empty
  body, which the tick counts as a failure — forever. The poller could
  never self-recover.
- The F-023 banner was correct (data really was stale) but its wording
  blamed Simkuliah.

Scope: session bootstrap and recovery in the poller, plus honest banner
wording. No schema changes.

## 2. Implementation Checklist

- [x] **`SimkuliahClient.is_authenticated`**: public property reporting
      whether the in-memory jar holds `ci_session` (False on every fresh
      process until `login()` succeeds).
- [x] **Session bootstrap** (`AdaptivePoller._ensure_session`): each tick
      logs in first when the jar has no session; login failure counts a
      failure and backs off without fetching. Mock clients (offline test
      builds) default to authenticated so tests stay offline.
- [x] **Mid-cycle recovery**: an empty fetch body is either a genuine
      500/502/504 or a sessionless 307 (empty body). The tick now forces a
      re-login (unconditionally — a stale cookie can still sit in the jar
      after server-side expiry) and retries the fetch once before counting
      a failure; a real outage fails again and backs off as before.
- [x] **Banner wording**: the degraded message no longer claims Simkuliah
      is broken; it now reads "Sinkronisasi ke Simkuliah tertunda - status
      presensi mungkin tidak terbaru. Data terakhir tetap ditampilkan."
- [x] **Tests**: poller logs in when sessionless; recovers after a stale
      cookie mid-cycle (fetch, empty, forced login, retry, success, no
      backoff); backs off when login fails (no fetch); never logs in when
      authenticated; `is_authenticated` reflects the real cookie jar.

## 3. Design Notes

- Forcing a login on every empty-body failure costs up to 3 CAPTCHA
  attempts per failure cycle, bounded by the existing exponential backoff;
  a sessionless 307 and a server-side expired cookie share the same
  signature, so a login attempt is the only reliable discriminator.
- After deploy, the first successful tick re-syncs the full matrix, which
  self-heals the missed 2026-11-10/11 statuses from Simkuliah's records.
- A sessionless 307 response with `follow_redirects=False` carries an
  empty body, which is why "empty body" plus re-login covers the case; a
  200 login page cannot appear on this path.

## 4. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| `pytest tests/test_poller.py tests/test_simkuliah_auth.py` | PASS | 35 tests, 5 new |
| Backend `pytest tests` | PASS | Full suite green |
| `python3 scripts/verify_pipeline.py --fast` | PASS | Full gate green |
| Live `/health` before fix | observed | `simkuliah_status: degraded` for ~25h of failed syncs |
| Two-axis code review (Standards + Spec) | PASS | See PR description |
