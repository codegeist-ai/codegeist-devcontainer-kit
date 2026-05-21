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
# - Dockerfile
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

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- google-chrome "${common_args[@]}" "${chrome_args[@]}"
fi

exec google-chrome "${common_args[@]}" "${chrome_args[@]}"
