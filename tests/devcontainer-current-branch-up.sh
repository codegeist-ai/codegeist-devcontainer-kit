#!/usr/bin/env bash
# devcontainer-current-branch-up.sh - verify BRANCH can select the current checkout
#
# Why this exists:
# - `devcontainer.json` always maps BRANCH to `.worktrees/<branch>` so VS Code
#   Remote SSH can open the repository root while selecting a branch workspace.
# - When BRANCH names the already checked-out branch, Git cannot create a second
#   worktree for that branch; initialize.sh must create a safe symlink alias
#   instead so the requested workspaceFolder exists.
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

repo_dir="$suite_tmp_dir/current-branch-devcontainer-repo"
branch_name="main"
container_id=""
log_file="$suite_tmp_dir/devcontainer-current-branch-up.log"
alias_path=""
expected_hostname=""
expected_remote_workspace_folder=""
expected_workspace_folder=""
expected_user="$(id -u):$(id -u)"
expected_user_name="$(expected_container_user)"
generated_env=""

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

create_git_fixture_repo "$repo_dir"
git -C "$repo_dir" branch -M "$branch_name"

alias_path="$repo_dir/.worktrees/$branch_name"
expected_workspace_folder="$repo_dir"
expected_remote_workspace_folder="$(expected_remote_workspace_folder "$repo_dir" "$branch_name")"

prepare_devcontainer_home "$repo_dir"
BRANCH="$branch_name" HOME="$repo_dir" devcontainer_cli up --remove-existing-container --workspace-folder "$repo_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract current-branch container id from devcontainer output"
[[ "$(extract_remote_workspace_folder_from_log "$log_file" || true)" = "$expected_remote_workspace_folder" ]] || fail "current-branch devcontainer did not report expected remote workspace folder"

[[ -L "$alias_path" ]] || fail "current branch alias is not a symlink: $alias_path"
[[ "$(readlink -f "$alias_path")" = "$repo_dir" ]] || fail "current branch alias does not resolve to repository root"
[[ -z "$(git -C "$repo_dir" status --porcelain -- .worktrees/main)" ]] || fail "current branch alias is not ignored"
[[ -f "$repo_dir/.devcontainer/.env" ]] || fail "initializeCommand did not create .devcontainer/.env"
generated_env="$(<"$repo_dir/.devcontainer/.env")"
[[ "$generated_env" == *"DEVCONTAINER_WORKSPACE_FOLDER=$expected_workspace_folder"* ]] || fail "generated env does not keep current branch workspace at repository root"
[[ "$generated_env" != *"BRANCH="* ]] || fail "generated env persisted explicit current branch"

expected_hostname="$(expected_generated_hostname "$repo_dir" "$branch_name")"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose file does not set current branch hostname"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"CONTAINER_USER: $expected_user_name"* ]] || fail "generated compose file does not set current branch build user"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"user: \"$expected_user\""* ]] || fail "generated compose file does not set current branch user"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if docker exec -w "$expected_remote_workspace_folder" -u "$expected_user_name" "$container_id" bash -lc 'test "$(pwd -P)" = "'"$expected_workspace_folder"'" && test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_folder"'" && test "$(git rev-parse --show-toplevel)" = "'"$expected_workspace_folder"'" && test "$(git rev-parse --abbrev-ref HEAD)" = "main" && test "$(readlink -f "'"$expected_remote_workspace_folder"'")" = "'"$expected_workspace_folder"'" && docker ps >/dev/null'; then
    pass "Dev Containers CLI starts explicit current-branch workspace through alias"
    exit 0
  fi

  sleep 1
done

fail "current-branch start did not expose repository root through .worktrees/main alias"
