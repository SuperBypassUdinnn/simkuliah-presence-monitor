# Feature Log: F-030 End-to-End Simkuliah Presence Confirmation

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: Owner report (chat + screenshots, 2026-11-12) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Two owner-reported issues from 2026-11-12:

1. **Tapping "Lakukan Presensi" in the app did not mark attendance in Simkuliah**:
   the monitor temporarily showed "Sudah Hadir (Tercatat di Simkuliah)" and then
   reverted when the next Simkuliah sync arrived.
2. **Root causes found**:
   - `PresenceService.submitPresence` in Flutter only executed a direct
     `UPDATE` on Supabase `meetings.simkuliah_status = 'hadir'` without ever
     calling the backend gateway or Simkuliah.
   - On Simkuliah's dashboard, clicking `#konfirmasi-kehadiran-<id>` opens a
     SweetAlert confirmation popup whose confirm callback sends a 7-field AJAX
     POST (`kelas`, `kd_mt_kul8`, `jadwal_mulai`, `jadwal_berakhir`,
     `pertemuan`, `sks_mengajar`, `id`) to
     `/index.php/absensi/konfirmasi_kehadiran`, which replies literal
     `"success"`.
   - `webhooks.py` (`confirm_presence`) used an unauthenticated `SimkuliahClient`
     and sent only the 3-field legacy payload, while
     `SimkuliahClient.confirm_presence` erroneously treated any HTTP 200 (such
     as a login redirect HTML page) as success.

## 2. Implementation Checklist

- [x] **Parse 7-field AJAX payload from dashboard scripts (`simkuliah_parser.py`)**:
      extract `class_group`, `jadwal_mulai`, `jadwal_berakhir`, `sks_mengajar`
      from the `#konfirmasi-kehadiran-<id>` click handler alongside
      `schedule_id`, `course_code`, and `meeting_number`.
- [x] **Strict AJAX headers & response check (`simkuliah_client.py`)**:
      send `X-Requested-With: XMLHttpRequest` + `Referer`, and reject HTTP 200
      HTML pages or non-`"success"` responses.
- [x] **Shared orchestrator (`backend/app/services/presence_confirmer.py`)**:
      resolves the meeting from Supabase, reuses the authenticated poller
      session (or logs in / refreshes on stale cookie), fetches the live
      dashboard card, verifies the window is open, posts the 7-field AJAX
      payload to Simkuliah, and only calls `mark_meeting_present` once
      Simkuliah accepts.
- [x] **New endpoint `POST /api/v1/presence/confirm` (`presence.py` + `router.py`)**
      and unified `webhooks.py` `confirm_presence` handling through the same
      orchestrator.
- [x] **Client calls backend instead of faking Supabase state**:
      `PresenceService.submitPresence(isPresent: true)` calls
      `POST /api/v1/presence/confirm`, throws `UserFacingException` with the
      server `detail` message on `409`/`502` failures, and never writes
      `'hadir'` directly to Supabase.
- [ ] **Bump client version to `1.0.5+4`** (deferred to release PR alongside APK/Linux bundle rebuilds).

## 3. Verification

- `python3 scripts/verify_pipeline.py` passes (ruff check, ruff format,
  backend pytest 151 tests, flutter analyze, dart format).
- Client unit/widget test suite: 84 tests pass, covering `PresenceService`
  `/api/v1/presence/confirm` requests, 409/unconfigured error propagation via
  `UserFacingException`, 7-field HTML script parsing, strict HTTP 200 HTML
  rejection, closed-card 409 guard, Simkuliah-failure 502 guard (never marking
  `hadir`), and idempotent already-present handling.
