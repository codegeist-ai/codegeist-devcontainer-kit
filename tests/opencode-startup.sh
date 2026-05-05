#!/usr/bin/env bash
# opencode-startup.sh - verify OpenCode can bootstrap in the devcontainer
#
# Why this exists:
# - `devcontainer.json` points `OPENCODE_CONFIG_DIR` at `/workspace/.oc_local`.
# - A fresh checkout used to miss that directory, causing OpenCode to fail during
#   TUI startup with `FileSystem.writeFile (/workspace/.oc_local/.gitignore)`.
# - The check stays non-interactive so the full suite does not hang on an
#   intentionally long-running TUI process.
#
# Related files:
# - ../initialize.sh
# - ../devcontainer.json
# - ./initialize.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  trap cleanup_suite EXIT
fi

fixture_dir="$suite_tmp_dir/opencode-startup-fixture"
log_file="$suite_tmp_dir/opencode-startup-devcontainer.log"
container_id=""
container_user="$(expected_container_user)"

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

create_git_fixture_repo "$fixture_dir"
rm -rf "$fixture_dir/.oc_local"

devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"
[[ -d "$fixture_dir/.oc_local" ]] || fail "initializeCommand did not create .oc_local"

output_file="$suite_tmp_dir/opencode-startup-output.log"

docker exec -u "$container_user" "$container_id" bash -lc '
  set -euo pipefail

  test -d /workspace/.oc_local
  test -w /workspace/.oc_local
  test -f /workspace/.oc_local/.gitignore

  OPENCODE_CONFIG_DIR=/workspace/.oc_local opencode --print-logs --log-level DEBUG debug startup
' >"$output_file" 2>&1

case "$(<"$output_file")" in
  *UnknownError*|*"tui bootstrap failed"*|*"FileSystem.writeFile (/workspace/.oc_local/.gitignore)"*)
    printf '%s\n' "$(<"$output_file")" >&2
    fail "OpenCode failed during TUI bootstrap"
    ;;
esac

pass "OpenCode bootstraps with workspace-local config directory"
