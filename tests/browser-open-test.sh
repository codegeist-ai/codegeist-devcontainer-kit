#!/usr/bin/env bash
# browser-open-test.sh - open interactive Chrome through Remote SSH X11
#
# Why this exists:
# - exercises the normal Dev Containers lifecycle and the real `chrome` command
# - verifies a genuine SSH-loopback display creates a detectable browser process
# - leaves the fixture and browser running for manual keyboard/pointer inspection
#
# Inputs:
# - Optional URL argument, defaulting to a local data URL.
# - DISPLAY must be a Remote SSH loopback X11 value and XAUTHORITY must identify
#   a readable authority file.
#
# Related files:
# - ../scripts/chrome.sh
# - ../initialize.sh
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
opens non-headless Chrome through the current Remote SSH X11 display. The
fixture and browser remain running for manual interaction.
EOF
}

case "$url" in
  -h|--help) usage; exit 0 ;;
esac

if [[ "${DISPLAY:-}" != localhost:[0-9]* ]] \
  && [[ "${DISPLAY:-}" != 127.0.0.1:[0-9]* ]]; then
  fail "DISPLAY must be a Remote SSH loopback X11 value such as localhost:10.0"
fi
source_authority="${XAUTHORITY:-${HOME:-}/.Xauthority}"
if [ -z "$source_authority" ] || [ ! -r "$source_authority" ]; then
  fail "XAUTHORITY must identify a readable Remote SSH X11 authority file"
fi

mkdir -p "$browser_tmp_root"
suite_tmp_dir="$(mktemp -d "$browser_tmp_root/browser-open.XXXXXX")"
suite_start_epoch="$(date +%s)"
export suite_tmp_dir suite_start_epoch

fixture_name="browser-open-fixture-${suite_tmp_dir##*.}"
fixture_dir="$suite_tmp_dir/$fixture_name"
log_file="$suite_tmp_dir/browser-open.log"
chrome_log_file="/tmp/browser-open-test.chrome.log"
chrome_exec_log_file="$suite_tmp_dir/browser-open.chrome-exec.log"

create_git_fixture_repo "$fixture_dir"
prepare_devcontainer_home "$fixture_dir"
HOME="$fixture_dir" XAUTHORITY="$source_authority" DISPLAY="$DISPLAY" \
  devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id"

docker exec -d -u "$expected_user_name" \
  -e BROWSER_OPEN_TEST_URL="$url" \
  -e CHROME_LOG_FILE="$chrome_log_file" \
  "$container_id" bash -lc '
    set -euo pipefail
    rm -f "$CHROME_LOG_FILE"
    exec chrome \
      --new-window \
      --window-position=40,40 \
      --window-size=1280,900 \
      "$BROWSER_OPEN_TEST_URL" \
      >"$CHROME_LOG_FILE" 2>&1
  ' >"$chrome_exec_log_file" 2>&1

chrome_profile_dir="$fixture_dir/.chrome"
chrome_started="false"
for _ in $(seq 1 60); do
  if docker exec -u "$expected_user_name" \
    -e CHROME_PROFILE_DIR="$chrome_profile_dir" \
    "$container_id" bash -lc '
      ps ww -u "$(id -u)" -o args= \
        | grep -F -- "--user-data-dir=$CHROME_PROFILE_DIR" \
        | grep -v grep >/dev/null
    '; then
    chrome_started="true"
    break
  fi
  sleep 1
done

if [ "$chrome_started" != "true" ]; then
  docker exec -u "$expected_user_name" "$container_id" \
    bash -lc 'printf "Chrome log:\n" >&2; cat /tmp/browser-open-test.chrome.log >&2 || true' || true
  cat >&2 <<EOF

Visible Chrome requires the active SSH X11 listener for DISPLAY=$DISPLAY and a
matching cookie copied to $fixture_dir/.devcontainer/.Xauthority.gen. Reconnect
the Remote SSH session if its display forwarding is stale.
EOF
  fail "visible Chrome did not start through Remote SSH X11"
fi

cat <<EOF
Visible interactive Chrome is running in the devcontainer fixture.

URL: $url
Temporary repo: $fixture_dir
Workspace profile: $chrome_profile_dir
Container id: $container_id
Devcontainer log: $log_file
Chrome log inside container: $chrome_log_file

Inspect the running container with:
  docker exec -it -u $expected_user_name $container_id bash

Stop it when done with:
  docker rm -f $container_id

Remove the temporary repo when done with:
  rm -rf $suite_tmp_dir
EOF
