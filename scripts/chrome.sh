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
#   and preserves SSH-forwarded or explicitly configured remote X11 displays.
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
  A non-empty DISPLAY or WAYLAND_DISPLAY alone is not sufficient. Wayland needs
  a socket at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY, and local X11 displays such as
  :0 need the matching /tmp/.X11-unix/X0 socket inside the container.
  A reachable Wayland socket takes precedence over DISPLAY.
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

  if [ -n "$display_value" ]; then
    # SSH-forwarded localhost displays and caller-managed remote X11 displays
    # cannot be proven usable from the socket filesystem. Preserve them.
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

Use \`chrome --headless ...\` for automation, reopen the devcontainer with SSH
X11 forwarding, or configure a container-visible Wayland or local X11 socket.
EOF
}

if [ "$mode" = "headless" ]; then
  exec google-chrome "${headless_args[@]}" "${chrome_args[@]}"
fi

refresh_display_from_workspace_env

wayland_error=""
x11_error=""
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

normalize_ssh_xauthority

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- google-chrome "${visible_args[@]}" "${chrome_args[@]}"
fi

exec google-chrome "${visible_args[@]}" "${chrome_args[@]}"
