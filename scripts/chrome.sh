#!/usr/bin/env bash
# chrome.sh - start Chrome through Remote SSH X11 or in headless mode
#
# Why this exists:
# - Plain `chrome` opens an interactive browser through a verified Remote SSH
#   loopback X11 display and uses a workspace-local profile by default.
# - The launcher rereads generated display state on every visible start so an
#   existing container recovers after VS Code reconnects with a new display.
# - `chrome --headless` remains display-independent for deterministic automation.
#
# Inputs:
# - Visible mode accepts `DISPLAY=localhost:N[.screen]` or
#   `DISPLAY=127.0.0.1:N[.screen]` plus a matching generated Xauthority file.
# - `DEVCONTAINER_WORKSPACE_FOLDER` identifies reconnect-refreshed `.env` state
#   and the default `.chrome` profile.
#
# Related files:
# - ../initialize.sh
# - ../docker-compose.yml
# - ../tests/chrome-launcher.sh
# - ../tests/browser-smoke.sh

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
  default      Start visible Chrome through Remote SSH loopback X11.
  --headless   Start headless Chrome for tests and automation.

Visible mode requires DISPLAY=localhost:N[.screen] or 127.0.0.1:N[.screen].
The launcher probes the display with xdpyinfo and, when required, normalizes
only its matching /unix:N Xauthority cookie into a private temporary file.
DISPLAY and XAUTHORITY are refreshed from the current workspace's
.devcontainer/.env on every launch, including after VS Code SSH reconnects.
Plain `chrome` uses $DEVCONTAINER_WORKSPACE_FOLDER/.chrome unless the caller
passes an explicit --user-data-dir.
EOF
      exit 0
      ;;
    *)
      case "$1" in
        --user-data-dir|--user-data-dir=*) has_explicit_user_data_dir=1 ;;
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

refresh_display_from_workspace_env() {
  local generated_env=""
  local line=""
  local display_value=""
  local xauthority_value=""
  local has_display=0
  local has_xauthority=0

  [ -n "${DEVCONTAINER_WORKSPACE_FOLDER:-}" ] || return 0
  generated_env="$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/.env"
  [ -f "$generated_env" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      DEVCONTAINER_DISPLAY=*)
        display_value="${line#DEVCONTAINER_DISPLAY=}"
        has_display=1
        ;;
      DEVCONTAINER_XAUTHORITY=*)
        xauthority_value="${line#DEVCONTAINER_XAUTHORITY=}"
        has_xauthority=1
        ;;
    esac
  done <"$generated_env"

  if [ "$has_display" -eq 1 ]; then
    if [ -n "$display_value" ]; then
      export DISPLAY="$display_value"
    else
      unset DISPLAY
    fi
  fi
  if [ "$has_xauthority" -eq 1 ]; then
    if [ -n "$xauthority_value" ]; then
      export XAUTHORITY="$xauthority_value"
    else
      unset XAUTHORITY
    fi
  fi
}

probe_x11_display() {
  local display_value="$1"
  local authority_file="${2:-}"

  if [ -n "$authority_file" ]; then
    DISPLAY="$display_value" XAUTHORITY="$authority_file" timeout 2s xdpyinfo >/dev/null 2>&1
  else
    DISPLAY="$display_value" timeout 2s xdpyinfo >/dev/null 2>&1
  fi
}

create_normalized_xauthority() {
  local display_number="$1"
  local cookie="$2"
  local normalized_xauthority=""

  normalized_xauthority="$(mktemp /tmp/chrome-xauthority.XXXXXX)"
  chmod 600 "$normalized_xauthority"

  # Keep only aliases for the requested display. Copying the source file could
  # expose cookies belonging to another parallel SSH or VS Code session.
  if ! xauth -f "$normalized_xauthority" add "localhost:${display_number}" MIT-MAGIC-COOKIE-1 "$cookie" >/dev/null 2>&1 \
    || ! xauth -f "$normalized_xauthority" add "localhost:${display_number}.0" MIT-MAGIC-COOKIE-1 "$cookie" >/dev/null 2>&1 \
    || ! xauth -f "$normalized_xauthority" add "127.0.0.1:${display_number}" MIT-MAGIC-COOKIE-1 "$cookie" >/dev/null 2>&1 \
    || ! xauth -f "$normalized_xauthority" add "127.0.0.1:${display_number}.0" MIT-MAGIC-COOKIE-1 "$cookie" >/dev/null 2>&1; then
    rm -f "$normalized_xauthority"
    return 1
  fi
  printf '%s\n' "$normalized_xauthority"
}

try_normalized_ssh_display() {
  local requested_display="$1"
  local display_number="$2"
  local cookie="$3"
  local candidate_xauthority=""

  candidate_xauthority="$(create_normalized_xauthority "$display_number" "$cookie")" || return 1
  tested_ssh_displays+=("$requested_display")
  if probe_x11_display "$requested_display" "$candidate_xauthority"; then
    export DISPLAY="$requested_display"
    export XAUTHORITY="$candidate_xauthority"
    return 0
  fi
  rm -f "$candidate_xauthority"
  return 1
}

resolve_ssh_x11() {
  local requested_display="$1"
  local requested_number="$2"
  local authority_file="${XAUTHORITY:-}"
  local authority_entry=""
  local authority_family=""
  local authority_cookie=""
  local candidate_number=""

  if ! command -v xdpyinfo >/dev/null 2>&1; then
    x11_error="Detected SSH DISPLAY=$requested_display, but xdpyinfo is unavailable for the required reachability check."
    return 1
  fi
  tested_ssh_displays+=("$requested_display")
  if probe_x11_display "$requested_display" "$authority_file"; then
    return 0
  fi

  if ! command -v xauth >/dev/null 2>&1; then
    x11_error="Detected stale SSH DISPLAY=$requested_display, and xauth is unavailable for candidate recovery."
    return 1
  fi
  if [ -z "$authority_file" ] || [ ! -f "$authority_file" ]; then
    x11_error="Detected stale SSH DISPLAY=$requested_display, but XAUTHORITY does not identify a readable file."
    return 1
  fi

  while read -r authority_entry authority_family authority_cookie _; do
    [[ "$authority_entry" =~ /unix:([0-9]+)(\.[0-9]+)?$ ]] || continue
    candidate_number="${BASH_REMATCH[1]}"
    [ "$candidate_number" = "$requested_number" ] || continue
    [ "$authority_family" = "MIT-MAGIC-COOKIE-1" ] || continue
    [[ "$authority_cookie" =~ ^[[:xdigit:]]+$ ]] || continue
    if try_normalized_ssh_display "$requested_display" "$candidate_number" "$authority_cookie"; then
      return 0
    fi
  done < <(xauth -f "$authority_file" list 2>/dev/null)

  x11_error="Detected stale SSH DISPLAY=$requested_display; its Xauthority cookie did not pass xdpyinfo."
  return 1
}

resolve_visible_display() {
  local display_value="${DISPLAY:-}"

  x11_error=""
  if [[ "$display_value" =~ ^(localhost|127\.0\.0\.1):([0-9]+)(\.[0-9]+)?$ ]]; then
    resolve_ssh_x11 "$display_value" "${BASH_REMATCH[2]}"
    return
  fi

  if [ -z "$display_value" ]; then
    x11_error="DISPLAY is not set."
  else
    x11_error="DISPLAY=$display_value is not a supported Remote SSH loopback X11 value."
  fi
  return 1
}

report_unusable_visible_display() {
  cat >&2 <<EOF
Chrome needs usable Remote SSH loopback X11.

$x11_error
SSH X11 candidates tested: ${tested_ssh_displays[*]:-none}

Reconnect with SSH X11 forwarding and rerun plain \`chrome\`. Use
\`chrome --headless ...\` only for automation.
EOF
}

if [ "$mode" = "headless" ]; then
  exec google-chrome "${headless_args[@]}" "${chrome_args[@]}"
fi

refresh_display_from_workspace_env
x11_error=""
tested_ssh_displays=()
if ! resolve_visible_display; then
  report_unusable_visible_display
  exit 1
fi

if [ "$has_explicit_user_data_dir" -eq 0 ] && [ -n "${DEVCONTAINER_WORKSPACE_FOLDER:-}" ]; then
  workspace_profile_dir="$DEVCONTAINER_WORKSPACE_FOLDER/.chrome"
  mkdir -p "$workspace_profile_dir"
  visible_args+=(--user-data-dir="$workspace_profile_dir")
fi

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- google-chrome "${visible_args[@]}" "${chrome_args[@]}"
fi
exec google-chrome "${visible_args[@]}" "${chrome_args[@]}"
