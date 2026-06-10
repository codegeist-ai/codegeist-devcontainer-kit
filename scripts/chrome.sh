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
# - `CHROME_OPEN_USER_DATA_DIR` optionally selects a custom profile directory.
#
# Related files:
# - Dockerfile.base
# - Taskfile.yaml
# - tests/browser-smoke.sh

set -euo pipefail

mode="visible"
chrome_args=()

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
  CHROME_OPEN_USER_DATA_DIR optionally overrides Chrome's profile directory.
EOF
      exit 0
      ;;
    *)
      chrome_args+=("$1")
      ;;
  esac
  shift
done

common_args=(--disable-gpu --no-first-run --no-default-browser-check)
headless_args=(--no-sandbox)

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

if [ "$mode" = "headless" ]; then
  exec google-chrome --headless=new "${common_args[@]}" "${headless_args[@]}" "${chrome_args[@]}"
fi

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  cat >&2 <<'EOF'
Chrome needs a container-visible display for non-headless mode.
Start the devcontainer with your host display forwarded, then run `chrome` again.
Use `chrome --headless ...` for tests and automation.
EOF
  exit 1
fi

if [ -n "${CHROME_OPEN_USER_DATA_DIR:-}" ]; then
  mkdir -p "$CHROME_OPEN_USER_DATA_DIR"
  common_args+=(--user-data-dir="$CHROME_OPEN_USER_DATA_DIR")
fi

normalize_ssh_xauthority

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- google-chrome "${common_args[@]}" "${chrome_args[@]}"
fi

exec google-chrome "${common_args[@]}" "${chrome_args[@]}"
