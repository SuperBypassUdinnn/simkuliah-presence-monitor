# Feature Log: F-035 Reopen Blank Window and Lecture Card UX Fixes

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: Owner report (chat, 2026-11-17) — no GitHub issue
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Four owner-reported defects observed on Android (1.1.1+7) and Linux desktop
after the F-034 release:

1. **Bottom navigation labels wrapped to two lines.** "Jadwal Hari Ini" and
   "Matriks Semester" did not fit their `NavigationBar` destination on a
   phone-width screen, so the label block rose above the icon and the icon
   drifted upward instead of staying centered.
2. **Card controls stretched across the desktop window.** The inline
   "Auto-Absen Pertemuan Ini" row and the "Lakukan Presensi" button expanded
   to the full card width, producing screen-wide controls on desktop.
3. **The inactive auto-absen subtitle lied about the reason.** It always read
   "Nonaktif: lakukan presensi manual" even when the real reason was that
   attendance was already recorded or the presence window had closed.
4. **The Linux desktop window still came back black.** F-034 mapped the
   `FlView` children on single-instance activation, which fixed the first
   wake from `--hidden`, but a window hidden to the tray and re-presented at
   the same size rendered an empty black surface until the user happened to
   resize it.

## 2. Root Cause Analysis

### 2.1 Bottom navigation (cosmetic)

Material 3's `NavigationBar` centers its label under the icon; a label that
wraps grows upward, pushing the rendered icon up. The honest fix is shorter
single-word labels, not a font hack.

### 2.2 Stretched controls

Both controls were direct children of the card's `Column` (a `Row`-backed
`Container` and a `SizedBox(width: double.infinity)`), so they adopted the
full available width. No maximum width existed.

### 2.3 Dishonest subtitle

`_autoPresence` is only the saved preference; the subtitle derived its text
from that boolean alone and never looked at the meeting state.

### 2.4 Linux blank window on re-open (the real bug)

Reproduced on the live session with the 1.1.1+7 bundle
(`client/build/linux/x64/release/bundle/simkuliah_client`):

| Step | Result |
| :--- | :--- |
| Launch with `--hidden`, activate via second launch | Window renders correctly |
| Close the window (hides to tray via `windowManager.hide()`) | Window unmaps |
| Activate again via second launch | **Window appears black (mean brightness 2.9/255)** |
| Resize the black window via KWin | Content renders immediately |

The F-034 diagnosis (`FlView` children unmapped) was correct for the very
first wake but incomplete: `windowManager.hide()` hides only the toplevel, so
its children are already "shown" and `gtk_widget_show_all` on re-activation
is a no-op. The Flutter Linux embedder only tells the engine a frame target
when the view's geometry changes (`handle_geometry_changed` in
`fl_view.cc` reacts to `realize`, `configure-event`, and scale-factor
changes). A window re-mapped at exactly the same size produces no configure
event, the embedder never schedules a frame, and the GL area keeps
presenting its empty black buffer until a real resize arrives.

## 3. Implementation

- [x] **Short mobile navigation labels (`client/lib/main.dart`)**: the four
      `NavigationDestination` labels become `Presensi`, `Jadwal`, `Matriks`,
      and `Pengaturan`; the desktop sidebar and each view's `AppBar` keep the
      full titles.
- [x] **Bounded card controls (`client/lib/views/widgets/active_lecture_card.dart`)**:
      the auto-absen row and the presence button are wrapped in
      `Align(centerLeft)` + `ConstrainedBox(maxWidth: 420)`. Narrow phone
      layouts stay full-width because the constraint never widens them.
- [x] **Reason-aware auto-absen subtitle (same file)**: `_autoPresenceSubtitle`
      resolves the true state in precedence order — attendance recorded,
      presence window closed, lecture finished, switch on, presence open now,
      or the plain call to action. Dead-window reasons are checked before the
      switch value so a stale "on" flag cannot promise automation that can no
      longer fire.
- [x] **Re-map frame restart (`client/linux/runner/my_application.cc`)**:
      the runner connects the window's `map` signal (fired by every
      presentation path: tray click via `windowManager.show()`, launcher
      single-instance activation, notification tap). On every map after the
      first, it resizes the window by one pixel and restores the original
      size 16 ms later; the generated configure event makes the embedder
      schedule the missing frame. The first map is skipped because a fresh
      window is allocated from scratch and already produces a configure
      event. `my_application_activate` also deiconifies before presenting.
- [x] **Widget tests (`client/test/active_lecture_card_customization_test.dart`)**:
      control widths are asserted to stay within the 420 px bound, and all
      four subtitle reasons are asserted with the old misleading text
      asserted absent.

## 4. Verification

| Check | Command | Result |
| :--- | :--- | :--- |
| Lint/format (fast pipeline) | `python3 scripts/verify_pipeline.py --fast` | PASS |
| Full client suite | `flutter test` | 104 passed, 4 skipped |
| Analyze | `flutter analyze --no-pub` | 0 issues |
| Linux release build | `flutter build linux --dart-define-from-file=.env` | PASS |
| Re-open after tray hide (live) | hide via window close, second-launch activate, window screenshot | Content renders (was black on 1.1.1+7) |
| Mobile navigation labels (live) | window resized to 420x820, window screenshot | Single-line labels, icons centered |
| Backlog parity | `python3 scripts/sync_backlog_status.py --check` | PASS |

Live evidence captured under `/tmp/opencode/f035/`:
`new-step1.png` (first wake), `new-step2-reopen.png` (re-open after hide,
renders), `narrow-nav.png` (single-line labels), against the pre-fix
captures `step2-reopen-after-hide.png` (black) and
`step3-after-resize.png` (renders after manual resize).
