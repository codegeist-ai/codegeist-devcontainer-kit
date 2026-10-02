#!/usr/bin/env bash
# browser-smoke.sh - verify real headless and visible X11 Chrome
#
# Why this exists:
# - proves the shared launcher renders container-local content through CDP
# - verifies stale Remote SSH X11 state rejects launch before Chrome starts
# - exercises real non-headless Chrome through authenticated loopback X11 without
#   substituting a Wayland compositor for the supported display transport
#
# Related files:
# - ../scripts/chrome.sh
# - ../docker-compose.yml
# - ./browser-ui-cdp.mjs

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

container_id=""
expected_user_name="$(expected_container_user)"
ui_driver_file="/tmp/browser-ui-cdp.mjs"
browser_tmp_root="${BROWSER_SMOKE_TMP_ROOT:-$project_root/.browser-smoke-tmp}"

mkdir -p "$browser_tmp_root"
suite_tmp_dir="$(mktemp -d "$browser_tmp_root/browser-smoke.XXXXXX")"
suite_start_epoch="$(date +%s)"
export suite_tmp_dir suite_start_epoch

cleanup_browser_smoke() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
  cleanup_suite
}
trap cleanup_browser_smoke EXIT

fixture_dir="$suite_tmp_dir/browser-fixture-repo"
log_file="$suite_tmp_dir/browser-smoke.log"
create_git_fixture_repo "$fixture_dir"
prepare_devcontainer_home "$fixture_dir"
(unset DISPLAY; HOME="$fixture_dir" devcontainer_cli up \
  --workspace-folder "$fixture_dir") | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract browser workspace container id"
docker cp "$script_dir/browser-ui-cdp.mjs" "$container_id:$ui_driver_file"

log "checking stale SSH X11 is rejected before Google Chrome starts"
docker exec -u "$expected_user_name" "$container_id" bash -lc '
  set -euo pipefail
  workspace=/tmp/browser-stale-ssh-workspace
  fake_bin="$workspace/fake-bin"
  authority_file="$workspace/.devcontainer/.Xauthority.gen"
  error_file=/tmp/browser-stale-ssh-error.log
  marker=/tmp/browser-stale-ssh-google-chrome-started
  rm -rf "$workspace"
  mkdir -p "$workspace/.devcontainer" "$fake_bin"
  : >"$authority_file"
  cat >"$workspace/.devcontainer/.env" <<EOF
DEVCONTAINER_DISPLAY=localhost:39999.0
DEVCONTAINER_XAUTHORITY=$authority_file
EOF
  cat >"$fake_bin/google-chrome" <<EOF
#!/usr/bin/env bash
touch "$marker"
EOF
  chmod +x "$fake_bin/google-chrome"
  rm -f "$error_file" "$marker"
  if PATH="$fake_bin:$PATH" DEVCONTAINER_WORKSPACE_FOLDER="$workspace" chrome about:blank 2>"$error_file"; then
    exit 1
  fi
  test ! -e "$marker"
  grep -F "Detected stale SSH DISPLAY=localhost:39999.0" "$error_file" >/dev/null
'

log "checking real Chrome headless CDP rendering"
docker exec -u "$expected_user_name" \
  -e UI_DRIVER_FILE="$ui_driver_file" \
  "$container_id" bash -lc '
    set -euo pipefail
    expected="headless Chrome rendered content from inside the container"
    html=/tmp/browser-headless.html
    screenshot=/tmp/browser-headless.png
    cat >"$html" <<EOF
<!doctype html><html lang="en"><body><main aria-label="$expected">$expected</main></body></html>
EOF
    rm -f "$screenshot"
    node "$UI_DRIVER_FILE" \
      --url "file://$html" \
      --expected "$expected" \
      --screenshot "$screenshot"
    test -s "$screenshot"
  '

log "checking real non-headless Chrome through authenticated loopback X11"
docker exec -u "$expected_user_name" \
  -e UI_DRIVER_FILE="$ui_driver_file" \
  "$container_id" bash -lc '
    set -euo pipefail
    xvfb_pid=""
    proxy_pid=""
    display_number=""
    server_authority=/tmp/browser-x11-server.Xauthority
    source_authority="$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/.Xauthority.gen"
    screenshot=/tmp/browser-visible-x11.png
    html=/tmp/browser-visible-x11.html
    expected="visible Chrome rendered through authenticated loopback X11"
    cookie=0123456789abcdef0123456789abcdef

    cleanup_x11() {
      if [ -n "$proxy_pid" ]; then kill "$proxy_pid" >/dev/null 2>&1 || true; fi
      if [ -n "$xvfb_pid" ]; then kill "$xvfb_pid" >/dev/null 2>&1 || true; fi
      if [ -n "$proxy_pid" ]; then wait "$proxy_pid" >/dev/null 2>&1 || true; fi
      if [ -n "$xvfb_pid" ]; then wait "$xvfb_pid" >/dev/null 2>&1 || true; fi
      rm -f "$server_authority" "$screenshot" "$html"
    }
    trap cleanup_x11 EXIT

    for candidate in $(seq 200 299); do
      port=$((6000 + candidate))
      if [ ! -e "/tmp/.X11-unix/X$candidate" ] && ! nc -z -w 1 127.0.0.1 "$port" >/dev/null 2>&1; then
        display_number="$candidate"
        break
      fi
    done
    test -n "$display_number"
    port=$((6000 + display_number))

    rm -f "$server_authority" "$source_authority"
    touch "$server_authority" "$source_authority"
    xauth -f "$server_authority" add "$(hostname)/unix:$display_number" MIT-MAGIC-COOKIE-1 "$cookie"
    xauth -f "$source_authority" add "fixture/unix:$display_number" MIT-MAGIC-COOKIE-1 "$cookie"
    chmod 600 "$server_authority" "$source_authority"

    Xvfb ":$display_number" -screen 0 1280x900x24 -nolisten tcp -auth "$server_authority" >/tmp/browser-xvfb.log 2>&1 &
    xvfb_pid="$!"
    for _ in $(seq 1 100); do
      [ ! -S "/tmp/.X11-unix/X$display_number" ] || break
      kill -0 "$xvfb_pid"
      sleep 0.1
    done
    test -S "/tmp/.X11-unix/X$display_number"

    socat "TCP4-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" "UNIX-CONNECT:/tmp/.X11-unix/X$display_number" >/tmp/browser-x11-proxy.log 2>&1 &
    proxy_pid="$!"
    for _ in $(seq 1 100); do
      nc -z -w 1 127.0.0.1 "$port" >/dev/null 2>&1 && break
      kill -0 "$proxy_pid"
      sleep 0.1
    done
    nc -z -w 1 127.0.0.1 "$port" >/dev/null 2>&1

    cat >"$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/.env" <<EOF
DEVCONTAINER_DISPLAY=localhost:$display_number.0
DEVCONTAINER_XAUTHORITY=$source_authority
EOF
    cat >"$html" <<EOF
<!doctype html><html lang="en"><body><main aria-label="$expected">$expected</main></body></html>
EOF
    rm -f "$screenshot"
    BROWSER_UI_PROFILE_ROOT="$DEVCONTAINER_WORKSPACE_FOLDER" \
      timeout 30s node "$UI_DRIVER_FILE" \
        --mode visible \
        --url "file://$html" \
        --expected "$expected" \
        --screenshot "$screenshot"
    test -s "$screenshot"
    test -z "$(find "$DEVCONTAINER_WORKSPACE_FOLDER" -maxdepth 1 -name ".chrome-ui-cdp.*" -print -quit)"
  '

pass "Chrome passes stale-X11, headless CDP, and real visible loopback-X11 regressions"
