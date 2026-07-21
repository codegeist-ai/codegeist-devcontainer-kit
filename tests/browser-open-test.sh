#!/usr/bin/env bash
# browser-open-test.sh - open visible Chrome in a temporary devcontainer fixture
#
# Why this exists:
# - gives maintainers the same Dev Containers CLI fixture path as browser tests
# - leaves the temporary repo and container running for manual visible inspection
# - verifies the real `chrome` command instead of a local host browser
#
# Inputs:
# - Optional URL argument, defaulting to a local data URL.
#
# Related files:
# - ./helpers.sh
# - ../scripts/chrome.sh
# - ../Taskfile.yaml

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

url="${1:-data:text/html,Visible%20Chrome%20test}"
browser_tmp_root="${BROWSER_OPEN_TEST_TMP_ROOT:-$project_root/.browser-smoke-tmp}"
expected_user_name="$(expected_container_user)"

usage() {
  cat <<'EOF'
Usage: task browser-open-test -- [url]

Creates a temporary Git repository, starts it through Dev Containers CLI, and
opens visible Chrome inside the workspace container. Without an explicit URL, it
uses a local data URL so visible-window detection is not blocked by network or
certificate behavior. The fixture is intentionally left running for manual
inspection.

Visible Chrome requires DISPLAY or WAYLAND_DISPLAY to be available to this shell
and reachable from Docker. This script writes a fixture-local compose override
for the detected display settings; it does not use VNC or noVNC.
EOF
}

case "$url" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  fail "DISPLAY or WAYLAND_DISPLAY must be set to open visible Chrome"
fi

mkdir -p "$browser_tmp_root"
suite_tmp_dir="$(mktemp -d "$browser_tmp_root/browser-open.XXXXXX")"
suite_start_epoch="$(date +%s)"
export suite_tmp_dir suite_start_epoch

fixture_name="browser-open-fixture-${suite_tmp_dir##*.}"
fixture_dir="$suite_tmp_dir/$fixture_name"
log_file="$suite_tmp_dir/browser-open.log"

create_git_fixture_repo "$fixture_dir"

compose_override="$fixture_dir/compose.local.yml"
volume_lines=""

cat >"$compose_override" <<'EOF'
services:
  workspace:
EOF

if [ -n "${DISPLAY:-}" ]; then
  case "$DISPLAY" in
    localhost:[0-9]*|127.0.0.1:[0-9]*)
      printf '    network_mode: host\n' >>"$compose_override"
      ;;
  esac
fi

cat >>"$compose_override" <<'EOF'
    environment:
EOF

if [ -n "${DISPLAY:-}" ]; then
  cat >>"$compose_override" <<EOF
      DISPLAY: ${DISPLAY}
EOF

  [ ! -d /tmp/.X11-unix ] || volume_lines="${volume_lines}      - /tmp/.X11-unix:/tmp/.X11-unix
"
fi

if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  cat >>"$compose_override" <<EOF
      WAYLAND_DISPLAY: ${WAYLAND_DISPLAY}
      XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-/tmp}
EOF

  if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    volume_lines="${volume_lines}      - ${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}:${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}
"
  fi
fi

if [ -n "${XAUTHORITY:-}" ] && [ -f "$XAUTHORITY" ]; then
  cat >>"$compose_override" <<EOF
      XAUTHORITY: ${XAUTHORITY}
EOF
  volume_lines="${volume_lines}      - ${XAUTHORITY}:${XAUTHORITY}
"
fi

if [ -n "$volume_lines" ]; then
  printf '    volumes:\n%s' "$volume_lines" >>"$compose_override"
fi

prepare_devcontainer_home "$fixture_dir"
HOME="$fixture_dir" devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"

chrome_log_file="/tmp/browser-open-test.chrome.log"
chrome_profile_dir="/tmp/browser-open-test-profile.$$"
chrome_exec_log_file="$suite_tmp_dir/browser-open.chrome-exec.log"

docker exec -u root "$container_id" bash -lc '
  if ! command -v xwininfo >/dev/null 2>&1 || ! command -v xauth >/dev/null 2>&1; then
    apt-get update >/dev/null
    apt-get install -y --no-install-recommends x11-utils xauth >/dev/null
  fi
' >/dev/null

set +e
timeout 15s docker exec -u "$expected_user_name" \
  -e BROWSER_OPEN_TEST_URL="$url" \
  -e CHROME_LOG_FILE="$chrome_log_file" \
  -e CHROME_PROFILE_DIR="$chrome_profile_dir" \
  "$container_id" bash -lc '
    set -euo pipefail

    rm -f "$CHROME_LOG_FILE"
    exec chrome \
      --user-data-dir="$CHROME_PROFILE_DIR" \
      --new-window \
      --window-position=40,40 \
      --window-size=1280,900 \
      "$BROWSER_OPEN_TEST_URL" \
      >"$CHROME_LOG_FILE" 2>&1
  ' >"$chrome_exec_log_file" 2>&1
chrome_exec_status="$?"
set -e

chrome_started="false"

for _ in $(seq 1 300); do
  if docker exec -u "$expected_user_name" \
    -e CHROME_PROFILE_DIR="$chrome_profile_dir" \
    -e BROWSER_OPEN_TEST_URL="$url" \
    "$container_id" bash -lc '
      set -euo pipefail
      matched="false"

      if [ -n "${DISPLAY:-}" ] && command -v xwininfo >/dev/null 2>&1; then
        window_tree="$(DISPLAY="$DISPLAY" xwininfo -root -tree 2>/dev/null || true)"
        if grep -F -- "$CHROME_PROFILE_DIR" <<<"$window_tree" >/dev/null; then
          matched="true"
        fi
      fi

      process_args="$(ps ww -u "$(id -u)" -o args= || true)"

      case "$process_args" in
        *"--user-data-dir=$CHROME_PROFILE_DIR"*)
          matched="true"
          ;;
      esac

      [ "$matched" = "true" ]
    '; then
    chrome_started="true"
    break
  fi

  sleep 1
done

if [ "$chrome_started" != "true" ]; then
  docker exec -u "$expected_user_name" \
    -e CHROME_LOG_FILE="$chrome_log_file" \
    "$container_id" bash -lc '
      set -euo pipefail

      printf "Chrome log from %s:\n" "$CHROME_LOG_FILE" >&2
      sed "s/^/  /" "$CHROME_LOG_FILE" >&2 || true
    ' || true
  if [ -f "$chrome_exec_log_file" ]; then
    printf 'docker exec log from %s:\n' "$chrome_exec_log_file" >&2
    sed 's/^/  /' "$chrome_exec_log_file" >&2 || true
  fi
  cat >&2 <<'EOF'

Visible Chrome uses the container's X11 or Wayland display directly. This is
different from `code` in a VS Code devcontainer terminal, which may work through
VS Code's remote CLI instead of opening an X11/Wayland GUI process.

If Chrome reports that no display is reachable, verify that the SSH X11 listener
or generated Wayland socket is still active. Normal kit starts refresh a
workspace-local Xauthority copy and do not require broad `xhost` access.
EOF
  fail "visible Chrome did not create a detectable X11 window in the devcontainer fixture"
fi

cat <<EOF
Visible Chrome was started in the devcontainer fixture.

URL: $url
Temporary repo: $fixture_dir
Container id: $container_id
Devcontainer log: $log_file
Chrome log inside container: $chrome_log_file
Chrome docker exec log: $chrome_exec_log_file

Inspect the running container with:
  docker exec -it -u $expected_user_name $container_id bash

Stop it when done with:
  docker rm -f $container_id

Remove the temporary repo when done with:
  rm -rf $suite_tmp_dir
EOF
