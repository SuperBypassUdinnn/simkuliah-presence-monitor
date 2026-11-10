# Feature Log: F-020 Client Follow-ups

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issues**: #36, #37
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Three follow-ups from owner feedback (2026-11-10):

1. Schedule times render with seconds — show hours and minutes only (xx:xx).
2. No way to un-do a self-reported status — cancel it by tapping the
   selected chip again, with a confirmation popup, in all three places.
3. The Android app dies when the device's RAM cleaner runs — keep it alive
   in the background until manually killed.

## 2. Implementation Checklist

- [x] **HH:mm times**: `MeetingModel.startTimeShort` / `endTimeShort`
      strip the seconds segment (regex-shared with the model's time
      parsing; unmatched strings pass through unchanged). Applied to the
      lecture card time row, the "Belum Dimulai" banner, and the matrix
      meeting-detail popup.
- [x] **Cancel self-reported status**: tapping the already-selected
      override chip opens a "Batalkan Keterangan Mandiri?" confirmation and
      then calls `PresenceService.clearOverride`, in
      - `ActiveLectureCard` (Presensi Aktif + Jadwal Hari Ini tabs), and
      - the `MeetingGridTile` meeting-detail popup (Matriks Semester).
      Both flows then refresh via the existing silent loaders. Dialogs and
      notifications mirror the submit flow's wording and colors.
- [x] **Android background keep-alive**: `flutter_foreground_task` 11.0.3
      (version from the pub resolver). `AndroidBackgroundService.start()`
      runs once per app launch:
      - silent persistent notification (LOW importance channel),
      - `ForegroundServiceTypes.specialUse` — `dataSync` is capped at
        6 hours/day on Android 15, wrong for an all-day monitor,
      - no-op task handler: the service only holds the process alive;
        alerting stays FCM-driven and the Render poller is the single
        dispatcher,
      - `autoRunOnBoot: true` + the plugin's merged boot receiver restarts
        the service after reboot,
      - battery-optimization exemption prompt on every cold start until
        granted (the system dialog explains itself and is remembered).
      Manifest: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`,
      `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permissions, the service with
      `foregroundServiceType="specialUse"` and the
      `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` property (verified in the merged
      APK manifest via `aapt2 dump xmltree`).
      The service-start callback is a top-level function annotated
      `@pragma('vm:entry-point')` per the v11 API (it runs in the service
      isolate).

## 3. Design Notes

- Honest limit: a manual force stop sets Android's stopped-state flag — no
  app can silently restart from that state until the user opens it again.
  That is the only kill that fully ends the app; the boundary is enforced
  by the OS, not the app.
- OEM task killers (MIUI, ColorOS, and friends) may still kill apps despite
  the exemption; the battery dialog covers stock Android and most OEM
  cleaners, but some vendors need the app whitelisted in their own
  autostart settings. The FGS notification makes the exemption effective
  in the large majority of cases.

## 4. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No issues |
| `flutter test` | PASS | 43 tests (3 new: HH:mm x2, cancel flow) |
| `flutter build apk --release --dart-define-from-file=.env` | PASS | Keep-alive + badge icons |
| Merged APK manifest | PASS | FGS permissions, service, and specialUse property present (aapt2) |
| Cancel flow widget test | PASS | Fake `PresenceService` records `clear:<id>` after confirm |
