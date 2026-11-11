# Feature Log: F-027 Live Presence State Persistence and Notification Clarity

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: Owner report (chat, 2026-11-11) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Two owner-reported defects, fixed in this order:

1. **Lecturer-opened presence never reached the app.** SINF6047 Praktikum
   Penelusuran Informasi Pertemuan 11 had an open attendance card on the
   Simkuliah dashboard (Batas Absen 08:31), yet the client kept rendering
   "Dosen Belum Melakukan Presensi". Every meeting row still carried
   `last_polled_at = 2026-11-09T04:48`, proving no live-state write had
   succeeded since Nov 9.
2. **Simultaneous notifications were indistinguishable.** The title was
   `Presensi <course_code>`, so two classes alerted at the same moment looked
   identical, and the same payload carried presensi/override action buttons
   for states where the student cannot act (`CLASS_STARTED`,
   `WINDOW_EXPIRED`).

## 2. Root Causes

1. **Foreign-key id confusion.** `parse_attendance_cards` reads the id from the
   `konfirmasi-kehadiran-<id>` button, which is Simkuliah's own jadwal id
   (e.g. 6220432). The poller wrote that value into `meetings.schedule_id`,
   which references `schedules.id` (1-19). Every upsert violated the foreign
   key and the failure was swallowed by the tick's defensive `except`, so the
   live state never persisted while the poller appeared healthy.
2. **`is_open` inferred from the button.** A card renders the konfirmasi
   button even when "Batas Absen" reads "Dosen belum absen", so the parser
   reported `is_open=True` for a closed session and dispatched a false
   "Presensi Dibuka" push with action buttons.
3. **Client had no closed-window state.** `MeetingModel.isPresenceOpen`
   accepted any non-null deadline regardless of time, and the card had no
   branch for a deadline in the past, falling through to "Dosen Belum
   Melakukan Presensi".
4. **Partial upsert violated a NOT NULL column.** Once the id was correct,
   `record_meeting_status` still failed: its payload carries only live-state
   fields, and `meetings.meeting_date` is NOT NULL. Postgres validates NOT
   NULL before `ON CONFLICT` resolution, so every upsert attempted an insert
   and raised `23502` (confirmed against the live database: three retries per
   card, new ids 1155-1157). The write must be an UPDATE on
   `(schedule_id, meeting_number)`; the matrix sync owns row creation.

## 3. Implementation Checklist

- [x] `parse_attendance_cards`: `is_open` is true only when the "Batas
      Absen" cell parses as a wall-clock time (`_CLOCK_RE`); "Dosen belum
      absen" leaves `deadline_time` empty and the session closed. The button
      id is still captured because `confirm_presence` needs it.
- [x] `record_meeting_status` takes explicit `schedule_id` /
      `meeting_number` overrides so callers can supply the Supabase ids while
      the card keeps Simkuliah's id, and updates the existing row instead of
      upserting a partial payload.
- [x] Poller keeps two ids per meeting: `schedule_id` (Supabase, for meetings
      rows and override lookups) and `simkuliah_schedule_id` (for the
      `confirm_presence` action token). The dispatch context carries both as
      `schedule_id` and `db_schedule_id`.
- [x] Override webhook resolves the meeting from `db_schedule_id` first, so a
      signed button no longer looks up a nonexistent schedule.
- [x] `MeetingModel.isPresenceOpen` requires a deadline in the future.
- [x] `ActiveLectureCard` renders "Presensi Ditutup (Batas HH:MM WIB)" when
      the deadline has passed instead of claiming the lecturer never opened
      presence.
- [x] FCM and ntfy titles are `"<State> - <Course Name> (<Code>)"`, and
      action buttons are emitted only for `LECTURER_OPENED`,
      `PENDING_REMINDER`, and `URGENT_CLOSING`.
- [x] Shared copy and state policy live in
      `backend/app/services/notification_content.py`, so the two dispatchers
      cannot drift apart.
- [x] The confirm button is omitted when the payload has no Simkuliah jadwal
      id; the Supabase id is never substituted, because `confirm_presence`
      would reject it. Override buttons stay available and resolve the
      meeting through `db_schedule_id`.

## 4. Verification

- `python3 scripts/verify_pipeline.py` passes (ruff check, ruff format,
  backend pytest, flutter analyze, dart format).
- Backend 137 tests and client 70 tests pass, including new coverage for the
  closed-card marker, the dual-id token, button gating, and the
  update-on-live-state write path.
- Live dashboard evidence: SINF6047 P11 parsed open with deadline 08:31,
  SINF6069 P13 parsed closed ("Dosen belum absen") while still exposing
  `konfirmasi-kehadiran-6243661`.
- Live write evidence after the fix: one sync run wrote SINF6047 P11
  (`hadir`, deadline 08:31 WIB) and SINF6069 P13 (`hadir`, deadline 09:09 WIB)
  with fresh `last_polled_at`, the first successful live-state writes since
  2026-11-09.
