#!/usr/bin/env bash
# devcontainer-up.sh - verify the kit works through Dev Containers CLI
#
# Why this exists:
# - devcontainer up is the closest CLI smoke path for the VS Code workflow
# - assertions that need inner Docker run inside the workspace container
#
# Related files:
# - ../devcontainer.json
# - ../Dockerfile
# - ../entrypoint.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

fixture_dir="$suite_tmp_dir/fixture-repo"
log_file="$suite_tmp_dir/devcontainer-up.log"
container_id=""
expected_hostname=""
expected_user="$(id -u):$(id -u)"
expected_user_name="$(expected_container_user)"
workspace_ready=""
opencode_output_file="$suite_tmp_dir/devcontainer-up-opencode.log"

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

create_git_fixture_repo "$fixture_dir"
rm -f "$fixture_dir/compose.local.yml"
rm -f "$fixture_dir/.local.env"

devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"

[[ -f "$fixture_dir/compose.local.yml" ]] || fail "initializeCommand did not create root compose.local.yml"
[[ -f "$fixture_dir/.local.env" ]] || fail "initializeCommand did not create root .local.env"
[[ -f "$fixture_dir/.devcontainer/.gen.env" ]] || fail "initializeCommand did not create .devcontainer/.gen.env"
[[ -f "$fixture_dir/.devcontainer/compose.local.gen.yml" ]] || fail "initializeCommand did not create .devcontainer/compose.local.gen.yml"
expected_hostname="$(expected_generated_hostname "$fixture_dir" "")"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose file does not set expected hostname"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"CONTAINER_USER: $expected_user_name"* ]] || fail "generated compose file does not set expected build user"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"user: \"$expected_user\""* ]] || fail "generated compose file does not set expected user"

container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"
[[ "$(extract_remote_workspace_folder_from_log "$log_file" || true)" = "/workspace" ]] || fail "devcontainer up did not report /workspace as remote workspace folder"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if docker exec -u "$expected_user_name" "$container_id" bash -lc 'test "$(id -un)" = "'"$expected_user_name"'" && test "$(hostname)" = "'"$expected_hostname"'" && test "$DEVCONTAINER_HOSTNAME" = "'"$expected_hostname"'" && test "$DEVCONTAINER_USER" = "'"$expected_user_name"'" && test "$DEVCONTAINER_UID:$DEVCONTAINER_GID" = "'"$expected_user"'" && docker ps >/dev/null'; then
    workspace_ready=1
    break
  fi

  sleep 1
done

[[ -n "$workspace_ready" ]] || fail "devcontainer workspace did not expose nested Docker to the remote user"

docker exec -u "$expected_user_name" "$container_id" bash -lc '
  set -euo pipefail

  test -d /workspace/.oc_local
  test -w /workspace/.oc_local
  test -f /workspace/.oc_local/.gitignore

  OPENCODE_CONFIG_DIR=/workspace/.oc_local opencode --print-logs --log-level DEBUG debug startup
' >"$opencode_output_file" 2>&1

case "$(<"$opencode_output_file")" in
  *UnknownError*|*"tui bootstrap failed"*|*"FileSystem.writeFile (/workspace/.oc_local/.gitignore)"*)
    printf '%s\n' "$(<"$opencode_output_file")" >&2
    fail "OpenCode failed during devcontainer bootstrap"
    ;;
esac

pass "devcontainer up starts a workspace with nested Docker and OpenCode available"
