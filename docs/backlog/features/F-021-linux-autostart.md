# Feature Log: F-021 Linux Autostart

- **Parent Plan**: [`.planning/01-architecture-mvp.md`](../../../.planning/01-architecture-mvp.md)
- **Target Issue**: #39
- **Status**: In Review
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope

Owner request: Simkuliah Monitor should start automatically at Linux desktop
login, silently monitoring from the tray.

## 2. Implementation Checklist

- [x] **`--hidden` launch flag**: `main(List<String> args)` reads the flag
      and skips `windowManager.show()`; the Linux runner gates
      `first_frame_cb`'s `gtk_widget_show` behind the same flag
      (`my_application_has_arg`), so the window stays hidden while the
      engine runs and the tray icon registers. A later launcher click
      presents the hidden window through the existing single-instance
      activation path (`gtk_widget_show` + `gtk_window_present` in
      `my_application_activate`).
- [x] **Autostart desktop entry**:
      `client/packaging/linux/simkuliah-monitor-autostart.desktop.in`
      rendered by `install-bundle.sh autostart install` with the concrete
      bundle path into `~/.config/autostart/`;
      `autostart uninstall` removes it; installing requires the bundle.
- [x] **Wayland session guard**: when `~/.scripts/autostart-env` exists,
      the rendered `Exec` is wrapped with it so the app only starts after
      the compositor socket exists (Plasma can reach autostart before
      `wayland-N` appears, which crashes GUI apps started in that window);
      machines without the helper fall back to a plain `Exec`.
- [x] Verified end-to-end on the live session: `--hidden` launch leaves the
      window absent while the tray item registers; `gtk-launch` then
      presents the window from the same process.

## 3. Design Notes

- The autostart entry is opt-in (`autostart install`), not part of the
  default bundle install.
- `--hidden` only suppresses the initial window; closing the window at any
  time still hides to tray, and the tray menu's "Keluar" remains the real
  exit.
- The rendered `Exec` quotes every component (wrapper and binary), and the
  template placeholder is resolved by splitting the file around it rather
  than by `sed` or bash pattern replacement: both engines treat `&` in the
  replacement text as the matched pattern, which would corrupt a home or
  bundle path containing reserved characters.

## 4. Objective Verification Matrix

| Command | Result | Notes |
| :--- | :--- | :--- |
| `shellcheck -x install-bundle.sh` | PASS | 0 findings |
| `script-conformance --script install-bundle.sh full` | PASS | Help + completions incl. new subcommand |
| `desktop-file-validate` (app + autostart entries) | PASS | Both clean |
| `flutter analyze --no-pub` / `flutter test` | PASS | No issues / 43 tests |
| `flutter build linux --dart-define-from-file=.env` | PASS | `--hidden` flag support |
| Runtime hidden launch | PASS | Window absent, tray item registered, 0 plugin exceptions |
| Single-instance activation | PASS | `gtk-launch` presents the window from the same process |
| `Exec` quoting robustness | PASS | Entries rendered with a space and with `&` in the path validate and stay literal |
| Live launch from the rendered entry | PASS | `gio launch` runs the wrapper (resolves `wayland-1`) and activates the same instance |
