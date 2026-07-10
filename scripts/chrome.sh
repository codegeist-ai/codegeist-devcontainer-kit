#!/usr/bin/env bash
# chrome.sh - start Chrome in visible or headless devcontainer mode
#
# Why this exists:
# - provides one supported Chrome launcher for users and smoke tests
# - defaults to a visible browser on the current container display
# - keeps tests deterministic through the same command with `--headless`
#
# Inputs:
# - `--headless` starts Chrome without a display and forwards remaining args.
# - Visible Chrome defaults to `$DEVCONTAINER_WORKSPACE_FOLDER/.chrome` unless
#   the caller passes `--user-data-dir`, and disables container-expensive
#   browser services that are not needed for normal interactive checks.
# - `DEVCONTAINER_WORKSPACE_FOLDER` points at the mounted workspace whose
#   `.devcontainer/.env` may contain a refreshed `DEVCONTAINER_DISPLAY` after a
#   VS Code reopen.
#
# Related files:
# - Dockerfile.base
# - Taskfile.yaml
# - tests/browser-smoke.sh

set -euo pipefail

mode="visible"
chrome_args=()
has_explicit_user_data_dir=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --headless)
      mode="headless"
      ;;
    --help|-h)
      cat <<'EOF'
Usage: chrome [--headless] [chrome-args...]

Starts Google Chrome with devcontainer-safe defaults.

Modes:
  default      Start visible Chrome on the current container display.
  --headless   Start headless Chrome for tests and automation.

Visible mode environment:
  DISPLAY or WAYLAND_DISPLAY must be available for visible Chrome.
  DISPLAY is refreshed from .devcontainer/.env when the workspace provides a
  generated DEVCONTAINER_DISPLAY value.
  Plain `chrome` uses $DEVCONTAINER_WORKSPACE_FOLDER/.chrome unless the caller
  passes an explicit --user-data-dir.

Account sign-in:
  Use plain visible `chrome` directly from a terminal. Its default profile is
  workspace-local and ignored by Git.
EOF
      exit 0
      ;;
    *)
      case "$1" in
        --user-data-dir|--user-data-dir=*)
          has_explicit_user_data_dir=1
          ;;
      esac
      chrome_args+=("$1")
      ;;
  esac
  shift
done

visible_args=(
  --no-first-run
  --no-default-browser-check
  --disable-background-networking
  --disable-breakpad
  --disable-component-update
  --disable-default-apps
  --disable-extensions
  --disable-gpu
  --disable-notifications
  --disable-search-engine-choice-screen
  --disable-sync
  --disable-translate
  --metrics-recording-only
  --mute-audio
  --password-store=basic
)
headless_args=(
  --headless=new
  --disable-gpu
  --no-first-run
  --no-default-browser-check
  --no-sandbox
)

normalize_ssh_xauthority() {
  local display_number=""
  local xauth_dir=""
  local normalized_xauthority=""
  local cookie=""

  case "${DISPLAY:-}" in
    localhost:[0-9]*|127.0.0.1:[0-9]*) ;;
    *) return 0 ;;
  esac

  [ -n "${XAUTHORITY:-}" ] || return 0
  [ -f "$XAUTHORITY" ] || return 0
  command -v xauth >/dev/null 2>&1 || return 0

  display_number="${DISPLAY#*:}"
  display_number="${display_number%%.*}"
  [ -n "$display_number" ] || return 0

  cookie="$(xauth list 2>/dev/null \
    | awk -v suffix="/unix:${display_number}" '$1 ~ suffix"$" { print $NF; exit }')"
  [ -n "$cookie" ] || return 0

  xauth_dir="${XDG_RUNTIME_DIR:-/tmp}"
  if [ ! -d "$xauth_dir" ] || [ ! -w "$xauth_dir" ]; then
    xauth_dir="/tmp"
  fi

  normalized_xauthority="$(mktemp "$xauth_dir/chrome-xauthority.XXXXXX")"
  cp "$XAUTHORITY" "$normalized_xauthority"
  chmod 600 "$normalized_xauthority"
  export XAUTHORITY="$normalized_xauthority"

  # SSH X11 forwarding often stores only a /unix cookie while DISPLAY uses
  # localhost. Add host aliases to a temporary authority file for GUI clients.
  xauth add "localhost:${display_number}" MIT-MAGIC-COOKIE-1 "$cookie" >/dev/null 2>&1 || true
  xauth add "localhost:${display_number}.0" MIT-MAGIC-COOKIE-1 "$cookie" >/dev/null 2>&1 || true
  xauth add "127.0.0.1:${display_number}" MIT-MAGIC-COOKIE-1 "$cookie" >/dev/null 2>&1 || true
  xauth add "127.0.0.1:${display_number}.0" MIT-MAGIC-COOKIE-1 "$cookie" >/dev/null 2>&1 || true
}

refresh_display_from_workspace_env() {
  local generated_env=""
  local line=""
  local display_value=""

  [ -n "${DEVCONTAINER_WORKSPACE_FOLDER:-}" ] || return 0
  generated_env="$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/.env"
  [ -f "$generated_env" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      DEVCONTAINER_DISPLAY=*)
        display_value="${line#DEVCONTAINER_DISPLAY=}"
        ;;
    esac
  done <"$generated_env"

  [ -n "$display_value" ] || return 0
  export DISPLAY="$display_value"
}

if [ "$mode" = "headless" ]; then
  exec google-chrome "${headless_args[@]}" "${chrome_args[@]}"
fi

refresh_display_from_workspace_env

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  cat >&2 <<'EOF'
Chrome needs a container-visible display for non-headless mode.
Start the devcontainer with your host display forwarded, then run `chrome` again.
Use `chrome --headless ...` for tests and automation.
EOF
  exit 1
fi

if [ "$has_explicit_user_data_dir" -eq 0 ]; then
  if [ -n "${DEVCONTAINER_WORKSPACE_FOLDER:-}" ]; then
    workspace_profile_dir="$DEVCONTAINER_WORKSPACE_FOLDER/.chrome"
    mkdir -p "$workspace_profile_dir"
    visible_args+=(--user-data-dir="$workspace_profile_dir")
  fi
fi

normalize_ssh_xauthority

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- google-chrome "${visible_args[@]}" "${chrome_args[@]}"
fi

exec google-chrome "${visible_args[@]}" "${chrome_args[@]}"
