# Feature Log: F-014 Android FCM Client

- **Parent Plan**: [`.planning/04-hybrid-push-notifications.md`](../../../.planning/04-hybrid-push-notifications.md)
- **Target Issue**: #19
- **Status**: In Progress
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope
The Flutter client could not receive push at all. Add the FCM receiving stack:
Firebase init from dart-define values, permission flow, priority channels,
token registration, foreground/background rendering with signed action
buttons, and the backend fixes those buttons depend on.

## 2. Implementation Checklist
- [x] `FirebaseConfig` initialization from `--dart-define` (graceful no-op on
      desktop/tests/unconfigured builds).
- [x] Android channels: `presensi_urgent` (max importance) and
      `presensi_general` (default).
- [x] Runtime notification permission request (Android 13+).
- [x] Device token registration + rotation to `POST /api/v1/devices/register`.
- [x] Foreground messages rendered through priority-mapped local notifications;
      urgent ones are ongoing and (opt-in) full-screen.
- [x] Action buttons from signed FCM data; taps call the webhook with
      `X-Action-Token` (foreground + background isolates).
- [x] Backend: overrides now persist to `local_overrides` (the previous
      `overrides` table never existed in production) and action buttons can
      resolve `meeting_id` from `(schedule_id, meeting_no)`.
- [x] Poller override lookup now uses the real meeting id instead of the
      schedule id.
- [x] `compileSdk = 37` + core library desugaring for
      flutter_local_notifications 23.
- [x] Firebase Android app values wired via `client/.env` dart-defines
      (owner-supplied `google-services.json`, project
      `aesthetic-forge-472216-g1`); `applicationId` aligned to the registered
      package `com.superbypassudin.simkuliah_monitor` (FCM requires an exact
      match; installs require uninstalling any previous
      `com.example.simkuliah_client` build).
- [ ] Real-device validation: install the release APK, confirm the token
      reaches `device_tokens` via the Render backend, and receive a live
      push. Backend prerequisites: upload the Firebase service-account JSON
      as a Render Secret File and set `FIREBASE_CREDENTIALS_PATH` in the
      `.env` secret. Full-screen intent remains opt-in via
      `FCM_FULLSCREEN_INTENT`.

## 3. Objective Verification Matrix
| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No issues |
| `flutter test` | PASS | 21 tests incl. action encoder + device service |
| `python3 scripts/verify_pipeline.py` | PASS | Full local gate |
| `flutter build linux --dart-define-from-file=.env` | PASS | Desktop unaffected |
| `flutter build apk --release --dart-define-from-file=.env` | PASS | 51.6 MB APK |
