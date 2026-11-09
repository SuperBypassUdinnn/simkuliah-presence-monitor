# Feature Log: F-015 Desktop Realtime Alerts

- **Parent Plan**: [`.planning/04-hybrid-push-notifications.md`](../../../.planning/04-hybrid-push-notifications.md)
- **Target Issue**: #20
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Desktop builds have no push path (ntfy was removed from the desktop story and
FCM targets Android). Users must keep the window in the foreground and watch
the meeting list. This phase adds in-app realtime alerts on desktop: the app
subscribes to Supabase Realtime changes on the `meetings` table and renders
overlay notifications, with sticky banners reserved for the two high-priority
states defined by the shared priority policy.

## 2. Implementation Checklist

- [x] `AppNotification` sticky variant: `duration: Duration.zero` disables the
      auto-dismiss timer, hides the countdown bar (static accent strip
      instead), and the close button becomes the only exit. `show` now returns
      the notification id and `dismiss(id)` removes a banner programmatically.
- [x] `RealtimeAlertEvaluator`: pure state evaluation over a meetings
      snapshot. Mirrors the backend state machine: presence open == pending
      meeting with a deadline; urgent phase starts 10 minutes before the
      deadline; attended/overridden meetings suppress alerts; expired windows
      resolve their meeting. Dedupes by `meetingId:kind` keys so poller-driven
      realtime events never repeat an alert.
- [x] `RealtimeAlertService`: Supabase Realtime stream on `meetings` filtered
      to today, plus a 30-second safety-net timer for time-driven transitions
      (urgent phase entry without a row change). Tracks sticky banner ids and
      dismisses them when their meeting resolves or expires; a new sticky
      banner supersedes earlier ones for the same meeting (urgent-closing
      replaces lecturer-opened).
- [x] `main.dart` wiring: desktop (non-Android, non-web) starts the service
      post-frame; urgent alerts render as sticky banners in `colorScheme.error`,
      normal ones as 4-second toasts in `colorScheme.primary`.
- [x] Supabase migration `20261109010000_enable_realtime.sql` (already merged)
      publishes `meetings` (and `schedules`, `local_overrides`) to
      `supabase_realtime`; no backend change required.

## 3. Design Notes

- Realtime streams cannot join `schedules`, so alert copy uses the meeting's
  own columns (course name defaults survive via `MeetingModel.fromJson`
  fallbacks); room-level detail remains in the meeting list view.
- Android intentionally skips this service: the FCM push stack covers the same
  states and also works while backgrounded.
- Dedupe state is in-memory per session: relaunching the app re-surfaces a
  sticky banner once, which is the desired recovery behavior.

## 4. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No issues |
| `flutter test` | PASS | 35 tests incl. evaluator dedupe + sticky banner widget tests |
| `python3 scripts/verify_pipeline.py --fast` | PASS | Fast local gate |
| `flutter build linux --dart-define-from-file=.env` | PASS | Desktop release build |

## 5. Follow-ups

- After FCM is validated on a real device (issue #19), retire the ntfy
  dispatcher (Phase 4, issue #21).
