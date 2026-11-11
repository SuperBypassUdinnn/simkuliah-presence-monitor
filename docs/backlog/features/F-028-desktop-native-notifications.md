# Feature Log: F-028 Desktop Native Notifications for Linux KDE Plasma

- **Parent Plan**: [`.planning/04-hybrid-push-notifications.md`](../../../.planning/04-hybrid-push-notifications.md)
- **Target Issue**: Owner report (chat, 2026-11-11) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Desktop notifications were previously constrained to an in-app overlay banner
(`AppNotification.show`). When the application was hidden in the system tray,
minimized, or behind other desktop windows, the user received no visible or
audible alert from the operating system.

The owner requested native desktop notifications on Linux (specifically KDE
Plasma), so alert events appear in the desktop environment's native
notification popup, play system sounds if configured, record in Plasma's
notification history, and restore/focus the app window when clicked.

## 2. Architecture & Design

1. **Native D-Bus Integration via `flutter_local_notifications_linux`**:
   `flutter_local_notifications_linux` provides a pure Dart D-Bus implementation
   communicating directly with `org.freedesktop.Notifications`.
2. **DesktopNotificationService**:
   - `initialize()` sets up `LinuxInitializationSettings` with the default
     action name (`Buka Simkuliah Monitor`) and application icon.
   - `showNotification()` maps `urgent` alerts (`lecturer_opened`,
     `urgent_closing`) to `LinuxNotificationUrgency.critical`,
     `LinuxNotificationTimeout.expiresNever()`, and sound
     (`ThemeLinuxSound('message-new-instant')`). Normal alerts use
     `LinuxNotificationUrgency.normal` and system-default timeout without sound.
   - `notificationId(meetingId, kindIndex)` provides deterministic ID mapping.
   - `onNotificationTap`: Restores and focuses the window via `windowManager.show()`
     and `windowManager.focus()` when the user interacts with the notification.
   - **Fallback**: Includes a graceful fallback executing `/usr/bin/notify-send`
     (with generic `notify-send` fallback) if plugin dispatch encounters
     D-Bus or environment issues.
3. **RealtimeAlertService Integration**:
   - Emits native notifications alongside the in-app overlay.
   - Dispatches `onDismissAlert` callbacks selectively when active sticky
     notifications resolve or expire, canceling stale sticky notifications
     from the desktop notification daemon without redundant cancellations.

## 3. Implementation Checklist

- [x] Create `DesktopNotificationService` with `DesktopNotificationClient`
      adapter for testability, Linux D-Bus settings, sound support, urgency
      mapping, deterministic ID generation, and graceful `notify-send` fallback.
- [x] Integrate `DesktopNotificationService` into `MainHomeScreenState` in
      `main.dart`, wiring window restoration on notification tap.
- [x] Wire `onDismissAlert` into `RealtimeAlertService` to selectively cancel
      resolved or superseded desktop notifications.
- [x] Add comprehensive unit test suite in `desktop_notification_service_test.dart`
      and extend `realtime_alert_service_test.dart`.

## 4. Verification

- `python3 scripts/verify_pipeline.py` passes (ruff check, ruff format,
  backend pytest 137 tests, flutter analyze, dart format).
- Client unit tests: 78 tests pass, including 7 new tests covering
  `DesktopNotificationService` (unsupported platform safety, Linux D-Bus setup,
  tap callback, urgency formatting, sound attachment, notify-send fallback,
  cancellation, deterministic ID) and `RealtimeAlertService.onDismissAlert`.
- Manual verification: `/usr/bin/notify-send` confirmed operational on KDE
  Plasma Wayland session.
