# Feature Log: F-017 Client UX Polish

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: #29
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Six UX changes from owner feedback after a full day of real usage
(2026-11-09): inconsistent confirmation button labels, missing per-meeting
lecturers for praktikum courses, a stale "Presensi Ditutup" toast on every
desktop app start, the placeholder app name, inconsistent override chip
layouts, and a focus-refresh mechanism that visibly remounts views.

## 2. Implementation Checklist

- [x] Confirmation dialogs for override statuses say **Konfirmasi** in both
      places (semester-matrix meeting dialog and today-feed card). The
      separate presence confirmation keeps its action-specific label
      ('Lakukan Presensi').
- [x] Per-meeting lecturer in the matrix meeting popup: already flowing via
      F-016 (meeting-level `lecturer_name` preferred over the schedule
      value); the running desktop build was simply older. Additionally the
      meaningless 'Dosen' placeholder is now hidden when no real lecturer
      exists (unsynced courses).
- [x] Startup toast suppression: `RealtimeAlertEvaluator` accepts
      `suppressExpiredBefore`; windows whose deadline passed before the
      service's first evaluation are marked seen without toasting, while a
      window that expires while the app runs still toasts. Android is
      unaffected (the alert service is desktop-only by design).
- [x] App renamed to **Simkuliah Monitor**: Android `android:label`, Linux
      GTK header/window title, Windows runner title, `MaterialApp.title`,
      pubspec description. The Dart package name (`simkuliah_client`)
      intentionally stays — renaming it would break every import.
- [x] Matrix popup override chips match the today-feed layout: leading icon
      avatar removed, `showCheckmark: false`.
- [x] Silent focus refresh: new `RefreshBus` (broadcast stream). The shell
      requests a refresh on app resume and tab switches instead of
      incrementing `ValueKey`s (which remounted views through the
      IndexedStack and reset Futures). Views cache their data and refetch in
      the background: no spinner on refresh, UI swaps only when data
      changes, scroll position preserved, stale data stays on screen if a
      silent refetch fails. The in-flight guard coalesces bursts.

## 3. Design Notes

- Focus-refresh frequency is unchanged — only its presentation. The
  disturbance was the remount + spinner, not the fetch itself. Urgent
  realtime states remain covered by the desktop alert service and (on
  Android) FCM push, so silent refresh plus realtime alerts gives effective
  continuous monitoring without visual noise.
- View tests keep working: `testMode` (matrix) and injected
  `presenceService` are preserved.

## 4. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No issues |
| `flutter test` | PASS | 40 tests incl. startup-suppression cases |
| `python3 scripts/verify_pipeline.py --fast` | PASS | Full local gate |
| `flutter build linux --dart-define-from-file=.env` | PASS | Window title "Simkuliah Monitor" |
| `flutter build apk --release --dart-define-from-file=.env` | PASS | `application-label:'Simkuliah Monitor'` (aapt2-verified) |
