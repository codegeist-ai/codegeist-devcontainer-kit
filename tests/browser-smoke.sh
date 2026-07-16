#!/usr/bin/env bash
# browser-smoke.sh - verify Chrome starts inside a Dev Containers CLI workspace
#
# Why this exists:
# - proves the shared kit can launch Chrome from inside the devcontainer runtime
# - verifies the browser can read container-local resources without host display
#   forwarding or project-specific browser configuration
# - drives a rendered browser UI check through Chrome DevTools Protocol
# - reproduces the local VS Code failure shape with DISPLAY=:0, no X0 socket, and
#   a real Wayland compositor before a runtime release can pass the full suite
#
# Related files:
# - ../Dockerfile.base
# - ../docker-compose.yml
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

container_id=""
expected_user_name="$(expected_container_user)"
expected_content="browser smoke expected content from inside the container"
container_file="/tmp/datei_innerhalb_des_containers.txt"
ui_expected_content="browser UI smoke rendered content from inside the container"
ui_container_file="/tmp/datei_innerhalb_des_containers.html"
ui_driver_file="/tmp/browser-ui-cdp.mjs"
ui_screenshot_file="/tmp/browser-ui-smoke.png"
wayland_expected_content="visible Chrome rendered through a real Wayland socket"
wayland_container_file="/tmp/browser-wayland-visible.html"
wayland_screenshot_file="/tmp/browser-wayland-visible.png"
wayland_runtime_dir="/tmp/browser-wayland-runtime"
wayland_socket_name="vscode-wayland-regression.sock"
weston_log_file="/tmp/browser-wayland-weston.log"
browser_tmp_root="${BROWSER_SMOKE_TMP_ROOT:-$project_root/.browser-smoke-tmp}"

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}

mkdir -p "$browser_tmp_root"
suite_tmp_dir="$(mktemp -d "$browser_tmp_root/browser-smoke.XXXXXX")"
suite_start_epoch="$(date +%s)"
export suite_tmp_dir suite_start_epoch

cleanup_browser_smoke() {
  cleanup_devcontainer
  cleanup_suite
}
trap cleanup_browser_smoke EXIT

fixture_dir="$suite_tmp_dir/browser-fixture-repo"
log_file="$suite_tmp_dir/browser-smoke.log"

create_git_fixture_repo "$fixture_dir"

# Weston is installed only in this disposable fixture. It provides a real
# Wayland protocol endpoint without adding a compositor to the release image.
mkdir -p "$fixture_dir/.codegeist"
cat >"$fixture_dir/.codegeist/Dockerfile" <<'EOF'
# Test-only image extension for the visible Wayland browser regression.
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends weston \
 && rm -rf /var/lib/apt/lists/*
USER ${CONTAINER_USER}
EOF

prepare_devcontainer_home "$fixture_dir"
DISPLAY=:0 HOME="$fixture_dir" devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"
grep -Fx "DEVCONTAINER_DISPLAY=:0" "$fixture_dir/.devcontainer/.env" >/dev/null \
  || fail "browser fixture did not preserve the failing local DISPLAY=:0 shape"

log "checking real Chrome headless DOM output with DISPLAY=:0 present"
actual_content="$(docker exec -u "$expected_user_name" \
  -e EXPECTED_CONTENT="$expected_content" \
  -e CONTAINER_FILE="$container_file" \
  "$container_id" bash -lc '
    set -euo pipefail

    user_data_dir="$(mktemp -d)"
    trap '\''rm -rf "$user_data_dir"'\'' EXIT

    printf "%s\n" "$EXPECTED_CONTENT" > "$CONTAINER_FILE"
    chrome \
      --headless \
      --user-data-dir="$user_data_dir" \
      --dump-dom \
      "file://$CONTAINER_FILE" \
      | python3 -c '\''import re, sys; print(re.sub(r"<[^>]+>", "", sys.stdin.read()).strip())'\''
  ')"

if [ "$actual_content" != "$expected_content" ]; then
  printf 'Expected browser content: %s\n' "$expected_content" >&2
  printf 'Actual browser content:   %s\n' "$actual_content" >&2
  fail "Chrome did not load the container-local file content"
fi

docker cp "$script_dir/browser-ui-cdp.mjs" "$container_id:$ui_driver_file"

log "checking real Chrome headless CDP rendering"
docker exec -u "$expected_user_name" \
  -e UI_EXPECTED_CONTENT="$ui_expected_content" \
  -e UI_CONTAINER_FILE="$ui_container_file" \
  -e UI_DRIVER_FILE="$ui_driver_file" \
  -e UI_SCREENSHOT_FILE="$ui_screenshot_file" \
  "$container_id" bash -lc '
    set -euo pipefail

    cat >"$UI_CONTAINER_FILE" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Browser UI Smoke</title>
    <style>
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: sans-serif; }
      main { border: 4px solid #2155d9; padding: 2rem; }
    </style>
  </head>
  <body>
    <main aria-label="$UI_EXPECTED_CONTENT">$UI_EXPECTED_CONTENT</main>
  </body>
</html>
EOF

    rm -f "$UI_SCREENSHOT_FILE"
    node "$UI_DRIVER_FILE" \
      --url "file://$UI_CONTAINER_FILE" \
      --expected "$UI_EXPECTED_CONTENT" \
      --screenshot "$UI_SCREENSHOT_FILE"

    test -s "$UI_SCREENSHOT_FILE"
  '

log "checking real visible Chrome with invalid X11 and a real Wayland compositor"
docker exec -u "$expected_user_name" \
  -e UI_EXPECTED_CONTENT="$wayland_expected_content" \
  -e UI_CONTAINER_FILE="$wayland_container_file" \
  -e UI_DRIVER_FILE="$ui_driver_file" \
  -e UI_SCREENSHOT_FILE="$wayland_screenshot_file" \
  -e WAYLAND_RUNTIME_DIR="$wayland_runtime_dir" \
  -e WAYLAND_SOCKET_NAME="$wayland_socket_name" \
  -e WESTON_LOG_FILE="$weston_log_file" \
  "$container_id" bash -lc '
    set -euo pipefail

    weston_pid=""
    cleanup_wayland() {
      if [ -n "$weston_pid" ]; then
        kill "$weston_pid" >/dev/null 2>&1 || true
        wait "$weston_pid" >/dev/null 2>&1 || true
      fi
      rm -rf "$WAYLAND_RUNTIME_DIR"
    }
    trap cleanup_wayland EXIT

    [ "${DISPLAY:-}" = ":0" ] \
      || { printf "Expected container DISPLAY=:0, got %s\n" "${DISPLAY:-<unset>}" >&2; exit 1; }
    [ "${DEVCONTAINER_DISPLAY:-}" = ":0" ] \
      || { printf "Expected DEVCONTAINER_DISPLAY=:0, got %s\n" "${DEVCONTAINER_DISPLAY:-<unset>}" >&2; exit 1; }
    [ ! -S /tmp/.X11-unix/X0 ] \
      || { printf "Expected /tmp/.X11-unix/X0 to be absent\n" >&2; exit 1; }

    rm -rf "$WAYLAND_RUNTIME_DIR"
    mkdir -m 700 "$WAYLAND_RUNTIME_DIR"
    export XDG_RUNTIME_DIR="$WAYLAND_RUNTIME_DIR"
    export WAYLAND_DISPLAY="$WAYLAND_SOCKET_NAME"

    weston \
      --backend=headless-backend.so \
      --socket="$WAYLAND_SOCKET_NAME" \
      --idle-time=0 \
      --use-pixman \
      --no-config \
      --log="$WESTON_LOG_FILE" &
    weston_pid="$!"

    for _ in $(seq 1 100); do
      [ ! -S "$WAYLAND_RUNTIME_DIR/$WAYLAND_SOCKET_NAME" ] || break
      if ! kill -0 "$weston_pid" 2>/dev/null; then
        cat "$WESTON_LOG_FILE" >&2 || true
        exit 1
      fi
      sleep 0.1
    done
    [ -S "$WAYLAND_RUNTIME_DIR/$WAYLAND_SOCKET_NAME" ] \
      || { cat "$WESTON_LOG_FILE" >&2 || true; exit 1; }

    cat >"$UI_CONTAINER_FILE" <<EOF
<!doctype html>
<html lang="en">
  <head><meta charset="utf-8"><title>Visible Wayland Regression</title></head>
  <body><main aria-label="$UI_EXPECTED_CONTENT">$UI_EXPECTED_CONTENT</main></body>
</html>
EOF

    rm -f "$UI_SCREENSHOT_FILE"
    timeout 30s node "$UI_DRIVER_FILE" \
      --mode visible \
      --url "file://$UI_CONTAINER_FILE" \
      --expected "$UI_EXPECTED_CONTENT" \
      --expected-browser-arg=--ozone-platform=wayland \
      --screenshot "$UI_SCREENSHOT_FILE"

    test -s "$UI_SCREENSHOT_FILE"
  '

pass "Chrome passes headless UI checks and the real DISPLAY=:0 Wayland regression"
