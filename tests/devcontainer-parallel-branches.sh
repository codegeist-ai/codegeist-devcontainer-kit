#!/usr/bin/env bash
# devcontainer-parallel-branches.sh - verify branch workspaces run side by side
#
# Why this exists:
# - VS Code Remote SSH opens the same repository root for different Host entries
#   while `SetEnv BRANCH=<branch>` selects the desired managed worktree.
# - Without a branch-specific Compose project name, Dev Containers can find the
#   existing `workspace` service from the other branch and attach both VS Code
#   windows to one container.
# - This test starts two branch-selected devcontainers plus one explicit empty
#   `BRANCH=` start from the same root without removing existing containers and
#   proves all containers remain isolated.
#
# Related files:
# - ../initialize.sh
# - ../devcontainer.json
# - ../docker-compose.yml
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

local_suite=0
if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  local_suite=1
fi

repo_dir="$suite_tmp_dir/parallel-branches-repo-$$"
branch_one="codegeist-cloud-server"
branch_two="install-scripts"
container_one_id=""
container_two_id=""
container_empty_id=""
log_one_file="$suite_tmp_dir/devcontainer-parallel-branch-one.log"
log_two_file="$suite_tmp_dir/devcontainer-parallel-branch-two.log"
log_empty_file="$suite_tmp_dir/devcontainer-parallel-empty-branch.log"
expected_project_one=""
expected_project_two=""
expected_project_empty=""
expected_workspace_one=""
expected_workspace_two=""
expected_workspace_empty=""
expected_user_name="$(expected_container_user)"

cleanup_devcontainers() {
  if [ -n "$container_one_id" ]; then
    docker rm -f "$container_one_id" >/dev/null 2>&1 || true
  fi

  if [ -n "$container_two_id" ]; then
    docker rm -f "$container_two_id" >/dev/null 2>&1 || true
  fi

  if [ -n "$container_empty_id" ]; then
    docker rm -f "$container_empty_id" >/dev/null 2>&1 || true
  fi
}

cleanup_test() {
  cleanup_devcontainers
  if [ "$local_suite" -eq 1 ]; then
    cleanup_suite
  fi
}
trap cleanup_test EXIT

compose_project_label() {
  docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$1"
}

container_name() {
  docker inspect --format '{{ .Name }}' "$1"
}

create_git_fixture_repo "$repo_dir"
prepare_devcontainer_home "$repo_dir"

expected_project_one="$(expected_compose_project_name "$repo_dir" "$branch_one")"
expected_project_two="$(expected_compose_project_name "$repo_dir" "$branch_two")"
expected_project_empty="$(expected_compose_project_name "$repo_dir")"
expected_workspace_one="$(expected_workspace_folder "$repo_dir" "$branch_one")"
expected_workspace_two="$(expected_workspace_folder "$repo_dir" "$branch_two")"
expected_workspace_empty="$(expected_workspace_folder "$repo_dir")"

BRANCH="$branch_one" HOME="$repo_dir" devcontainer_cli up --workspace-folder "$repo_dir" | tee "$log_one_file"
container_one_id="$(extract_container_id_from_log "$log_one_file" || true)"
[[ -n "$container_one_id" ]] || fail "could not extract first branch container id"

BRANCH="$branch_two" HOME="$repo_dir" devcontainer_cli up --workspace-folder "$repo_dir" | tee "$log_two_file"
container_two_id="$(extract_container_id_from_log "$log_two_file" || true)"
[[ -n "$container_two_id" ]] || fail "could not extract second branch container id"

BRANCH="" HOME="$repo_dir" devcontainer_cli up --workspace-folder "$repo_dir" | tee "$log_empty_file"
container_empty_id="$(extract_container_id_from_log "$log_empty_file" || true)"
[[ -n "$container_empty_id" ]] || fail "could not extract empty BRANCH container id"

[[ "$container_one_id" != "$container_two_id" ]] || fail "parallel branch starts reused one workspace container"
[[ "$container_one_id" != "$container_empty_id" ]] || fail "empty BRANCH start reused first branch workspace container"
[[ "$container_two_id" != "$container_empty_id" ]] || fail "empty BRANCH start reused second branch workspace container"
[[ "$(compose_project_label "$container_one_id")" = "$expected_project_one" ]] || fail "first branch container has wrong Compose project label"
[[ "$(compose_project_label "$container_two_id")" = "$expected_project_two" ]] || fail "second branch container has wrong Compose project label"
[[ "$(compose_project_label "$container_empty_id")" = "$expected_project_empty" ]] || fail "empty BRANCH container has wrong Compose project label"
[[ "$(container_name "$container_one_id")" == *"$expected_project_one"* ]] || fail "first branch container name does not include branch project name"
[[ "$(container_name "$container_two_id")" == *"$expected_project_two"* ]] || fail "second branch container name does not include branch project name"
[[ "$(container_name "$container_empty_id")" == *"$expected_project_empty"* ]] || fail "empty BRANCH container name does not include root project name"

[[ "$(<"$repo_dir/.devcontainer/.env")" == *"DEVCONTAINER_COMPOSE_PROJECT_NAME=$expected_project_empty"* ]] || fail "generated env does not record latest empty BRANCH Compose project"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"name: $expected_project_empty"* ]] || fail "generated compose file does not set latest empty BRANCH project name"

docker exec -w "$expected_workspace_one" -u "$expected_user_name" "$container_one_id" bash -lc '
  test "$(git rev-parse --abbrev-ref HEAD)" = "codegeist-cloud-server"
  test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_one"'"
' >/dev/null

docker exec -w "$expected_workspace_two" -u "$expected_user_name" "$container_two_id" bash -lc '
  test "$(git rev-parse --abbrev-ref HEAD)" = "install-scripts"
  test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_two"'"
' >/dev/null

docker exec -w "$expected_workspace_empty" -u "$expected_user_name" "$container_empty_id" bash -lc '
  test "$(git rev-parse --show-toplevel)" = "'"$expected_workspace_empty"'"
  test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_empty"'"
' >/dev/null

pass "parallel and empty BRANCH devcontainers use separate Compose projects and containers"
