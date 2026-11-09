# Plan 04: Hybrid Push Notifications (FCM + In-App Realtime)

- **Target Issues**: #17, #18, #19, #20, #21
- **Status**: In Progress
- **Primary Stack**: Cross-stack

## 1. Context & Objectives
Replace external-app push (ntfy) with a hybrid model: Firebase Cloud Messaging
for Android and Supabase Realtime in-app banners for desktop, keeping ntfy
alive only during the transition window.

## 2. Architectural Decisions
- **Priority policy**: only `LECTURER_OPENED` (dosen buka presensi) and
  `URGENT_CLOSING` (10 minutes before the window closes) escalate to high
  priority; every other level stays normal.
- Signed action tokens (`create_action_token` / `verify_action_token`) are
  reused by both dispatchers; only the delivery transport changes.
- Android receives FCM; desktop never receives FCM (platform unsupported) and
  instead renders in-app banners fed by Supabase Realtime.
- ntfy stays enabled in parallel until FCM is validated, then is retired.

## 3. Implementation Steps
- [x] Phase 0 (#17): unified priority policy, ntfy action URL/JSON fixes.
- [x] Phase 1 (#18): `device_tokens` table, FCM dispatcher, dual dispatch.
- [x] Phase 2 (#19): Android client channels, local action buttons,
      full-screen intent opt-in (Firebase app values pending from the owner).
- [x] Phase 3 (#20): desktop realtime in-app notifications (sticky banners for
      lecturer-opened and urgent-closing, toasts otherwise).
- [ ] Phase 4 (#21): retire ntfy dispatch (blocked until FCM is validated on a
      real device).

## 4. Verification Gate
```bash
python3 scripts/verify_pipeline.py
python3 scripts/sync_backlog_status.py --check
```
