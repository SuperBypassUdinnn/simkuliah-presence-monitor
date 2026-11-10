#!/usr/bin/env bash
# Purpose: Install the Flutter Linux release bundle as a user-local freedesktop application.
# Data & Logic Flow: Copies the release bundle into ~/.local/share/simkuliah-monitor, installs
#   hicolor PNG icons from packaging, renders the .desktop entry with the concrete install
#   path, and refreshes desktop caches. --uninstall removes everything it created.
# Key Components: install-bundle.sh, completions machinery
set -euo pipefail

APP_NAME="simkuliah-monitor"
BIN_NAME="simkuliah_client"
DESKTOP_ID="com.superbypassudin.simkuliah_monitor"
ICON_SIZES="64 256 512"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PACKAGING_DIR="$REPO_ROOT/client/packaging/linux"

usage() {
  cat <<'EOF'
install-bundle.sh - install the Simkuliah Monitor Linux bundle as a desktop app

Usage:
  install-bundle.sh [OPTIONS] [BUNDLE_DIR]
  install-bundle.sh completions bash|fish
  install-bundle.sh completions install [--fish|--bash|--uninstall]

Arguments:
  BUNDLE_DIR    path to the flutter linux bundle directory
                (default: client/build/linux/x64/release/bundle)

Options:
  --uninstall   remove the installed application files
  -h, --help    show this help

Subcommands:
  completions   emit or install shell completion
  help          show detailed help for a subcommand

Examples:
  install-bundle.sh
  install-bundle.sh ~/builds/simkuliah-bundle
  install-bundle.sh --uninstall
EOF
}

usage_completions() {
  cat <<'EOF'
Usage: install-bundle.sh completions bash|fish
       install-bundle.sh completions install [--fish|--bash|--uninstall]

Emit or install shell completion scripts. With no flag, install targets the
device's primary shell ($SHELL, falling back to the passwd login shell).
EOF
}

do_install() { # [BUNDLE_DIR]
  local bundle_dir="${1:-$REPO_ROOT/client/build/linux/x64/release/bundle}"
  local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
  local app_dir="$data_dir/$APP_NAME"
  local icons_src="$PACKAGING_DIR/icons"
  local desktop_src="$PACKAGING_DIR/$APP_NAME.desktop.in"
  local desktop_dst="$data_dir/applications/$DESKTOP_ID.desktop"

  if [ ! -d "$bundle_dir" ]; then
    printf 'install-bundle.sh: bundle dir not found: %s\n' "$bundle_dir" >&2
    exit 1
  fi
  if [ ! -x "$bundle_dir/$BIN_NAME" ]; then
    printf 'install-bundle.sh: bundle binary not found: %s/%s\n' \
      "$bundle_dir" "$BIN_NAME" >&2
    exit 1
  fi
  if [ ! -f "$desktop_src" ]; then
    printf 'install-bundle.sh: desktop template not found: %s\n' "$desktop_src" >&2
    exit 1
  fi

  mkdir -p "$app_dir"
  cp -a "$bundle_dir/." "$app_dir/"

  local size icon_dir
  for size in $ICON_SIZES; do
    icon_dir="$data_dir/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    cp "$icons_src/$APP_NAME-$size.png" "$icon_dir/$APP_NAME.png"
  done

  mkdir -p "$data_dir/applications"
  sed "s|@APP_DIR@|$app_dir|g" "$desktop_src" > "$desktop_dst"

  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f "$data_dir/icons/hicolor" 2>/dev/null || true
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$data_dir/applications" 2>/dev/null || true
  fi
  # Refresh KDE's service cache so the tray item id associates with the
  # desktop entry's Name (Plasma reads the human-readable tray entry name
  # from this association).
  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
  elif command -v kbuildsycoca >/dev/null 2>&1; then
    kbuildsycoca >/dev/null 2>&1 || true
  fi

  printf 'installed bundle   %s\n' "$app_dir"
  printf 'installed desktop  %s\n' "$desktop_dst"
  printf 'launch with: gtk-launch %s\n' "$DESKTOP_ID"
}

do_uninstall() {
  local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
  local size
  rm -rf "${data_dir:?}/$APP_NAME"
  rm -f "$data_dir/applications/$DESKTOP_ID.desktop"
  for size in $ICON_SIZES; do
    rm -f "$data_dir/icons/hicolor/${size}x${size}/apps/$APP_NAME.png"
  done
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$data_dir/applications" 2>/dev/null || true
  fi
  printf 'removed %s\n' "$APP_NAME"
}

emit_bash_completion() {
  cat <<'EOF'
# bash completion for install-bundle.sh (dynamic; regenerate with: install-bundle.sh completions bash)
__install_bundle_complete() {
    local cur cands c
    cur="${COMP_WORDS[COMP_CWORD]}"
    mapfile -t cands < <(install-bundle.sh __complete "${COMP_WORDS[@]:1:COMP_CWORD-1}" "$cur" 2>/dev/null)
    COMPREPLY=()
    for c in "${cands[@]}"; do
        c="${c%%$'\t'*}"
        [[ "$c" == "__FILE_COMPLETION__" ]] && COMPREPLY=() && _filedir -d && break
        [[ "$c" == "$cur"* ]] && COMPREPLY+=("$c")
    done
}
complete -F __install_bundle_complete -o nosort install-bundle.sh
EOF
}

emit_fish_completion() {
  cat <<'EOF'
# fish completion for install-bundle.sh (dynamic; regenerate with: install-bundle.sh completions fish)
function __install_bundle_complete
    set -l toks (commandline -opc)
    set -l partial (commandline -ct)
    set -l args
    if test (count $toks) -ge 2; and test -n "$partial"; and test "$toks[-1]" = "$partial"
        set args $toks[2..-2]
    else
        set args $toks[2..-1]
    end
    set -l out (install-bundle.sh __complete $args "$partial" 2>/dev/null)
    if test (count $out) -ge 1; and test "$out[1]" = "__FILE_COMPLETION__"
        __fish_complete_directories "$partial"
    else
        printf '%s\n' $out
    end
end
complete -c install-bundle.sh -f -a '(__install_bundle_complete)'
EOF
}

primary_shell() { # device's primary shell: $SHELL, else the passwd login shell
  local sh="${SHELL:-}"
  [ -n "$sh" ] || sh="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f7)"
  case "$sh" in
    */fish) printf 'fish\n' ;;
    *) printf 'bash\n' ;;
  esac
}

completions_install() { # [--fish|--bash] [--uninstall] ; no flag = the primary shell
  local filter="" remove=0 do_fish=1 do_bash=1
  local fish_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"
  local bash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --fish) filter=fish ;;
      --bash) filter=bash ;;
      --uninstall) remove=1 ;;
      -h|--help) usage_completions; return 0 ;;
      *)
        printf 'install-bundle.sh: completions install: unknown option: %s\n' "$1" >&2
        return 1
        ;;
    esac
    shift
  done
  if [ -z "$filter" ]; then filter="$(primary_shell)"; fi
  if [ "$filter" = fish ]; then do_bash=0; fi
  if [ "$filter" = bash ]; then do_fish=0; fi
  if [ "$remove" = 1 ]; then
    if [ "$do_fish" = 1 ]; then
      rm -f "$fish_dir/install-bundle.sh.fish"
      printf 'removed %s\n' "$fish_dir/install-bundle.sh.fish"
    fi
    if [ "$do_bash" = 1 ]; then
      rm -f "$bash_dir/install-bundle.sh"
      printf 'removed %s\n' "$bash_dir/install-bundle.sh"
    fi
    return 0
  fi
  if [ "$do_fish" = 1 ]; then
    mkdir -p "$fish_dir"
    emit_fish_completion > "$fish_dir/install-bundle.sh.fish"
    printf 'installed %s\n' "$fish_dir/install-bundle.sh.fish"
  fi
  if [ "$do_bash" = 1 ]; then
    mkdir -p "$bash_dir"
    emit_bash_completion > "$bash_dir/install-bundle.sh"
    printf 'installed %s\n' "$bash_dir/install-bundle.sh"
  fi
}

cmd_completions() {
  case "${1:-}" in
    bash) emit_bash_completion ;;
    fish) emit_fish_completion ;;
    install) shift; completions_install "$@" ;;
    -h|--help) usage_completions ;;
    "")
      usage_completions >&2
      return 1
      ;;
    *)
      printf 'install-bundle.sh: completions: unknown target: %s\n' "$1" >&2
      usage_completions >&2
      return 1
      ;;
  esac
}

cmd___complete() { # words... partial -> candidate<TAB>description lines for partial's position
  [ "$#" -eq 0 ] && return 0
  local partial="${*: -1}"
  local -a words=()
  if [ "$#" -gt 1 ]; then words=("${@:1:$#-1}"); fi
  local first="" prev="" w
  if [ "${#words[@]}" -gt 0 ]; then prev="${words[-1]}"; fi
  for w in "${words[@]}"; do
    case "$w" in -h|--help|--uninstall) ;; *)
      if [ -z "$first" ]; then first="$w"; fi
      ;;
    esac
  done

  # A path-like partial is always the BUNDLE_DIR argument.
  case "$partial" in
    /*|.*|~*) printf '__FILE_COMPLETION__\n'; return 0 ;;
  esac

  if [[ "$partial" == -* ]]; then
    case "$first" in
      "") printf -- '--uninstall\tremove the installed application files\n' ;;
      completions)
        if [ "$prev" = install ]; then
          printf -- '--fish\tinstall only the fish completion\n'
          printf -- '--bash\tinstall only the bash completion\n'
          printf -- '--uninstall\tremove installed completions\n'
        fi
        ;;
    esac
    return 0
  fi

  if [ -z "$first" ]; then
    printf 'completions\tinstall or print shell completions\n'
    printf 'help\tshow detailed help for a subcommand\n'
    printf -- '--uninstall\tremove the installed application files\n'
    return 0
  fi

  case "$first" in
    completions)
      if [ "$prev" = completions ]; then
        printf 'bash\temit the bash completion script\n'
        printf 'fish\temit the fish completion script\n'
        printf 'install\tinstall completions for the primary shell\n'
      fi
      ;;
    help)
      if [ "$prev" = help ]; then
        printf 'completions\tcompletion subcommand help\n'
      fi
      ;;
  esac
}

main() {
  if [ "${1:-}" = "__complete" ]; then
    shift
    cmd___complete "$@"
    return $?
  fi

  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    completions)
      shift
      cmd_completions "$@"
      ;;
    help)
      case "${2:-}" in
        completions) usage_completions ;;
        *) usage ;;
      esac
      ;;
    --uninstall)
      do_uninstall
      ;;
    *)
      do_install "$@"
      ;;
  esac
}

main "$@"
