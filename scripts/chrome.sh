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
# - Visible mode prefers a reachable Wayland socket, validates local X11 sockets,
#   and probes SSH-forwarded X11 before Google Chrome starts.
# - `DEVCONTAINER_WORKSPACE_FOLDER` points at the mounted workspace whose
#   `.devcontainer/.env` contains reconnect-refreshed display and Xauthority
#   state isolated from other workspace instances on the same host.
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
  A non-empty DISPLAY or WAYLAND_DISPLAY alone is not sufficient. Wayland needs
  a socket at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY, and local X11 displays such as
  :0 need the matching /tmp/.X11-unix/X0 socket inside the container.
  A reachable Wayland socket takes precedence over DISPLAY. SSH-loopback X11
  displays are verified with xdpyinfo and may normalize their matching
  Xauthority /unix:N cookie.
  DISPLAY and XAUTHORITY are refreshed from the current workspace's
  .devcontainer/.env on every launch, including after VS Code SSH reconnects.
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

refresh_display_from_workspace_env() {
  local generated_env=""
  local line=""
  local display_value=""
  local xauthority_value=""
  local wayland_display_value=""
  local wayland_runtime_value=""
  local has_display=0
  local has_xauthority=0
  local has_wayland_display=0
  local has_wayland_runtime=0

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
      DEVCONTAINER_WAYLAND_DISPLAY=*)
        wayland_display_value="${line#DEVCONTAINER_WAYLAND_DISPLAY=}"
        has_wayland_display=1
        ;;
      DEVCONTAINER_WAYLAND_RUNTIME_DIR=*)
        wayland_runtime_value="${line#DEVCONTAINER_WAYLAND_RUNTIME_DIR=}"
        has_wayland_runtime=1
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

  if [ "$has_xauthority" -eq 1 ] && [ -n "$xauthority_value" ]; then
    export XAUTHORITY="$xauthority_value"
  fi

  if [ "$has_wayland_display" -eq 1 ] && [ "$has_wayland_runtime" -eq 1 ]; then
    # Empty refreshed values clear create-time Compose state after a host logout
    # or reconnect. New sockets still require container recreation for mounting.
    if [ -n "$wayland_display_value" ] && [ -n "$wayland_runtime_value" ]; then
      export WAYLAND_DISPLAY="$wayland_display_value"
      export XDG_RUNTIME_DIR="$wayland_runtime_value"
    else
      unset WAYLAND_DISPLAY XDG_RUNTIME_DIR
    fi
  fi
}

probe_x11_display() {
  local display_value="$1"
  local authority_file="${2:-}"

  if [ -n "$authority_file" ]; then
    DISPLAY="$display_value" XAUTHORITY="$authority_file" \
      timeout 2s xdpyinfo >/dev/null 2>&1
    return
  fi

  DISPLAY="$display_value" timeout 2s xdpyinfo >/dev/null 2>&1
}

create_normalized_xauthority() {
  local display_number="$1"
  local cookie="$2"
  local source_file="${XAUTHORITY:-}"
  local xauth_dir="${XDG_RUNTIME_DIR:-/tmp}"
  local normalized_xauthority=""

  if [ ! -d "$xauth_dir" ] || [ ! -w "$xauth_dir" ]; then
    xauth_dir="/tmp"
  fi

  normalized_xauthority="$(mktemp "$xauth_dir/chrome-xauthority.XXXXXX")"
  if [ -n "$source_file" ] && [ -f "$source_file" ]; then
    cp "$source_file" "$normalized_xauthority"
  fi
  chmod 600 "$normalized_xauthority"

  # SSH commonly records hostname/unix:N while clients connect through a
  # loopback DISPLAY. Keep aliases unique to this launcher process.
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
  local display_number="$1"
  local cookie="$2"
  local candidate_display="localhost:${display_number}.0"
  local candidate_xauthority=""

  candidate_xauthority="$(create_normalized_xauthority "$display_number" "$cookie")" || return 1
  tested_ssh_displays+=("$candidate_display")
  if probe_x11_display "$candidate_display" "$candidate_xauthority"; then
    export DISPLAY="$candidate_display"
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

  # Only normalize the requested workspace display. Trying another reachable
  # cookie could attach Chrome to a different parallel VS Code SSH session.
  while read -r authority_entry authority_family authority_cookie _; do
    [[ "$authority_entry" =~ /unix:([0-9]+)(\.[0-9]+)?$ ]] || continue
    candidate_number="${BASH_REMATCH[1]}"
    [ "$candidate_number" = "$requested_number" ] || continue
    [ "$authority_family" = "MIT-MAGIC-COOKIE-1" ] || continue
    [[ "$authority_cookie" =~ ^[[:xdigit:]]+$ ]] || continue
    if try_normalized_ssh_display "$candidate_number" "$authority_cookie"; then
      return 0
    fi
  done < <(xauth -f "$authority_file" list 2>/dev/null)

  x11_error="Detected stale SSH DISPLAY=$requested_display; its Xauthority cookie did not pass xdpyinfo."
  return 1
}

resolve_visible_display() {
  local display_value="${DISPLAY:-}"
  local display_number=""
  local wayland_socket=""

  wayland_error=""
  x11_error=""

  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
      wayland_error="Detected WAYLAND_DISPLAY=$WAYLAND_DISPLAY, but XDG_RUNTIME_DIR is not set."
    else
      wayland_socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
      if [ -S "$wayland_socket" ]; then
        # Chrome defaults to X11 on Linux, so select Wayland explicitly and do
        # not let an unreachable inherited DISPLAY pull it back to X11.
        unset DISPLAY
        visible_args+=(--ozone-platform=wayland)
        return 0
      fi

      wayland_error="Detected WAYLAND_DISPLAY=$WAYLAND_DISPLAY, but no socket is available at $wayland_socket."
    fi
  else
    wayland_error="WAYLAND_DISPLAY is not set."
  fi

  if [[ "$display_value" =~ ^:([0-9]+)(\.[0-9]+)?$ ]]; then
    display_number="${BASH_REMATCH[1]}"
    if [ -S "/tmp/.X11-unix/X$display_number" ]; then
      return 0
    fi

    x11_error="Detected DISPLAY=$display_value, but /tmp/.X11-unix/X$display_number is not available inside the container."
    return 1
  fi

  if [[ "$display_value" =~ ^(localhost|127\.0\.0\.1):([0-9]+)(\.[0-9]+)?$ ]]; then
    display_number="${BASH_REMATCH[2]}"
    resolve_ssh_x11 "$display_value" "$display_number"
    return
  fi

  if [ -n "$display_value" ]; then
    # Explicit non-loopback remote X11 hosts remain caller-managed. Unlike SSH
    # loopback forwards, the kit cannot infer their authority or lifecycle.
    return 0
  fi

  x11_error="DISPLAY is not set."
  return 1
}

report_unusable_visible_display() {
  cat >&2 <<EOF
Chrome needs a usable visible display.

$x11_error
$wayland_error
SSH X11 candidates tested: ${tested_ssh_displays[*]:-none}

Use \`chrome --headless ...\` for automation, reopen the devcontainer with SSH
X11 forwarding, or recreate it to mount a newly available Wayland socket.
EOF
}

if [ "$mode" = "headless" ]; then
  exec google-chrome "${headless_args[@]}" "${chrome_args[@]}"
fi

refresh_display_from_workspace_env

wayland_error=""
x11_error=""
tested_ssh_displays=()
if ! resolve_visible_display; then
  report_unusable_visible_display
  exit 1
fi

if [ "$has_explicit_user_data_dir" -eq 0 ]; then
  if [ -n "${DEVCONTAINER_WORKSPACE_FOLDER:-}" ]; then
    workspace_profile_dir="$DEVCONTAINER_WORKSPACE_FOLDER/.chrome"
    mkdir -p "$workspace_profile_dir"
    visible_args+=(--user-data-dir="$workspace_profile_dir")
  fi
fi

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- google-chrome "${visible_args[@]}" "${chrome_args[@]}"
fi

exec google-chrome "${visible_args[@]}" "${chrome_args[@]}"
