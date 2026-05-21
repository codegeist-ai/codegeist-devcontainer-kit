#!/usr/bin/env bash
# browser-smoke.sh - verify Chrome starts inside a Dev Containers CLI workspace
#
# Why this exists:
# - proves the shared kit can launch Chrome from inside the devcontainer runtime
# - verifies the browser can read container-local resources without host display
#   forwarding or project-specific browser configuration
# - drives a rendered browser UI check through Chrome DevTools Protocol
#
# Related files:
# - ../Dockerfile
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

devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"

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

pass "Chrome loads container-local content and passes CDP UI smoke checks"
