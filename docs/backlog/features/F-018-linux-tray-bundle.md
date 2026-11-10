# Feature Log: F-018 Linux Tray + Background Operation & Installable Bundle

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: #31
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Two desktop-Linux deliverables from owner feedback:

1. **Background operation + system tray**: closing the window keeps the app
   running so the realtime alert service keeps polling; a StatusNotifierItem
   tray icon provides "Buka Simkuliah Monitor" and "Keluar".
2. **Installable Linux bundle**: package the `flutter build linux` release
   bundle with an install script, hicolor icons derived from the Jam-Centang
   logo, and a freedesktop `.desktop` entry so the app appears in the
   launcher with correct icon and window grouping.

## 2. Implementation Checklist

- [x] `window_manager 0.5.2` + `tray_manager 0.5.3` pinned to the classic
      API line. Rationale: 0.6.0 / 0.7.0+ rewrote both packages onto the
      `nativeapi` FFI stack, which requires Flutter's experimental
      multi-window feature (`isWindowingEnabled`) for window control and
      relegates the classic API to deprecated bridges. The classic API is
      the correct fit for this single-window runner-based app.
- [x] `main()`: `windowManager.ensureInitialized()` +
      `waitUntilReadyToShow(title: 'Simkuliah Monitor')` before `runApp`,
      desktop platforms only.
- [x] `_MainHomeScreenState` mixes in `WindowListener` + `TrayListener`;
      `setPreventClose(true)`; `onWindowClose` hides to tray; tray menu
      "Buka Simkuliah Monitor" / "Keluar" (`windowManager.destroy()`);
      left-click shows + focuses. Setup is guarded to Linux/Windows.
- [x] Tray icon resolves an absolute path next to the executable
      (`data/flutter_assets/assets/icons/tray_icon.png`, 128 px duotone
      Jam-Centang) because AppIndicator needs a file path.
- [x] Linux plugin capability guards: tray_manager 0.5.3's Linux plugin
      implements `setIcon`/`setTitle`/`setContextMenu` only — `setToolTip`
      and `popUpContextMenu` are Windows-only calls (AppIndicator pops the
      context menu natively on right-click). Guards verified against the
      plugin source and a runtime run (no `MissingPluginException`).
- [x] `client/linux/CMakeLists.txt`: scoped
      `-Wno-deprecated-declarations` on `tray_manager_plugin` only —
      libayatana-appindicator 0.6.x deprecates `app_indicator_new`, which
      the pinned plugin still calls; without this the plugin fails under
      the standard `-Werror` plugin settings.
- [x] `APPLICATION_ID` set to `com.superbypassudin.simkuliah_monitor`
      (mirrors the Android `applicationId`); `.desktop`
      `StartupWMClass` matches it for Wayland window grouping; runner sets
      `gtk_window_set_default_icon_name("simkuliah-monitor")` so an
      installed app shows the brand icon in taskbar/titlebar.
- [x] `client/packaging/linux/`: `simkuliah-monitor.desktop.in` template
      (`@APP_DIR@` substitution), `install-bundle.sh` (help + dynamic bash
      and fish completions per the script-authoring standard), hicolor
      icons 64/256/512.
- [x] `install-bundle.sh` copies the bundle to
      `~/.local/share/simkuliah-monitor`, installs hicolor icons, renders
      the `.desktop` to `~/.local/share/applications/`, refreshes caches;
      `--uninstall` removes everything.

## 2b. Follow-up Fixes (owner feedback, 2026-11-10)

- [x] **Tray state persistence**: the tray_manager 0.5.3 Dart wrapper
      hardcodes `'id': shortid.generate()` per process, so the
      StatusNotifierItem id changed on every restart and Plasma (which keys
      System Tray > Entries settings by that id — confirmed by the orphaned
      `P387syl5OK` shortid in `hiddenItems`) forgot the user's visibility
      choice. `setIcon` now bypasses the wrapper and invokes the plugin
      channel directly with the stable application id. Verified live: the
      item registers as
      `org/ayatana/NotificationItem/com_superbypassudin_simkuliah_monitor`
      with `Id = com.superbypassudin.simkuliah_monitor`.
- [x] **Tray entry name**: the plugin's `setTitle` maps to
      `app_indicator_set_label` (label, not the SNI `Title` property), so
      the human-readable name comes from the desktop-file association
      instead: item id == desktop id == WMClass, plus `kbuildsycoca6`
      cache refresh.
- [x] **Badge icon style**: new `badge` logo style (white disc behind
      ring + check) for tray/launcher contrast on dark and light panels;
      tray icon and hicolor 64/256/512 icons regenerated from it.

## 2c. Follow-up Fixes (owner feedback, 2026-11-10, round 2)

- [x] **Tray entry name**: measured live SNI properties of correct items
      (steam, rustdesk) proved Plasma displays the SNI `Title` property.
      The tray_manager Linux plugin's `setTitle` maps to
      `app_indicator_set_label` (never rendered), so the displayed name
      fell back to the id. `tray_manager` 0.5.3 is now vendored under
      `client/third_party/tray_manager` (via `dependency_overrides`) with
      one patched function: `set_title` calls `app_indicator_set_title`.
      Verified live: `Title = Simkuliah Monitor`. Upstream `example/` is
      dropped from the vendored copy.
- [x] **Single-instance launch**: the Flutter Linux runner used
      `G_APPLICATION_NON_UNIQUE`, so every launcher click spawned a new
      process (and a new tray item). The runner now uses the unique
      default (`G_APPLICATION_DEFAULT_FLAGS`; debug builds keep
      non-unique so `flutter run` is not hijacked by an installed
      instance) and `my_application_activate` re-presents the existing
      window when one is already created (tray-hidden included).
      Verified: `gtk-launch` while running leaves the instance count at 1.
- [x] **Tray item id** renamed to the human-readable `Simkuliah Monitor`
      (space-containing ids are valid — Kate registers as "Kate
      Sessions"); it stays stable across restarts.
- [x] **Pipeline**: `third_party` is excluded from the analyzer/formatter
      pubspec discovery (vendored upstream code is not gated by this
      project's linters) and `dart format` is scoped to `lib` and `test`.

## 2d. Follow-up: badge logo everywhere (#34)

- [x] Android launcher icons (`mipmap-*/ic_launcher.png`, 48/72/96/144/192
      px) regenerated from the badge style — the phone previously showed
      the default Flutter icon.
- [x] Windows runner `app_icon.ico` regenerated (256/128/64/48/32/16).
- [x] The in-app sidebar brand mark now uses the bundled badge logo asset
      instead of the `Icons.school` placeholder.
- Linux tray and hicolor launcher icons already used the badge style
  (sections 2b/2c).

## 3. Design Notes

- Hide-on-close is the only background mechanism: the Dart engine stays
  alive, so the realtime alert service keeps polling while hidden. Closing
  the window therefore never exits the process; real exit is the tray
  menu's "Keluar" (`windowManager.destroy()`).
- Package versions verified via the pub resolver at add time (0.5.2 /
  0.5.3) and plugin API surface verified against the published sources in
  the pub cache, not from memory.

## 4. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No issues |
| `flutter test` | PASS | 40 tests |
| `flutter build linux --dart-define-from-file=.env` | PASS | Bundle with both tray plugins |
| `shellcheck -x install-bundle.sh` | PASS | 0 findings |
| `script-conformance --script install-bundle.sh full` | PASS | Help + completions |
| `install-bundle.sh` (executed) | PASS | Bundle, 3 hicolor icons, `.desktop` installed |
| `desktop-file-validate` | PASS | Clean (single main category) |
| Runtime tray check | PASS | App PID appears as `org.kde.StatusNotifierItem-<pid>-1` in `RegisteredStatusNotifierItems`; 0 plugin exceptions in the app log |

## 5. Manual Follow-ups

- Close-to-tray, tray menu "Buka"/"Keluar", and left-click restore are
  interactive behaviors — verify once on the real desktop session.
