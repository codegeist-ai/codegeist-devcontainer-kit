#!/usr/bin/env bash
# compose-config.sh - verify compose config resolves through Dev Containers CLI
#
# Related files:
# - ../docker-compose.yml
# - ../compose.local.yml.example
# - ../initialize.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

fixture_dir="$suite_tmp_dir/compose-config-repo"
container_id=""
log_file="$suite_tmp_dir/compose-config-devcontainer.log"
create_git_fixture_repo "$fixture_dir"

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"

[[ -f "$fixture_dir/compose.local.yml" ]] || fail "initializeCommand did not create root compose.local.yml"

pass "compose config resolves through Dev Containers CLI with generated local overlay"
