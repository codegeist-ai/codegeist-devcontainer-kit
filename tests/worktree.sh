#!/usr/bin/env bash
# worktree.sh - verify managed worktree commit and merge flow
#
# Related files:
# - ../initialize.sh
# - ../.local.env.example

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

repo_dir="$suite_tmp_dir/worktree-repo"
branch_name="feature/test-worktree"
container_id=""
log_file="$suite_tmp_dir/worktree-devcontainer.log"
expected_user_name="$(expected_container_user)"
expected_workspace_folder=""

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

create_git_fixture_repo "$repo_dir"

BRANCH="$branch_name" "$repo_dir/.devcontainer/initialize.sh"

worktree_path="$repo_dir/.worktrees/$branch_name"
expected_workspace_folder="$(expected_workspace_folder "$repo_dir" "$branch_name")"

[[ -d "$worktree_path" ]] || fail "worktree path was not created: $worktree_path"
[[ -f "$worktree_path/.devcontainer/devcontainer.json" ]] || fail "worktree .devcontainer files are missing"
[[ -L "$worktree_path/.local.env" ]] || fail "worktree .local.env is not a symlink"
[[ -f "$repo_dir/.local.env" ]] || fail "root .local.env was not created"

devcontainer_cli up --remove-existing-container --workspace-folder "$worktree_path" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"

docker exec -w "$expected_workspace_folder" -u "$expected_user_name" "$container_id" bash -lc '
  test "$(git rev-parse --abbrev-ref HEAD)" = "feature/test-worktree"
  printf "worktree change\n" > worktree-change.txt
  git add worktree-change.txt
  git commit -m "add worktree change" >/dev/null
'

docker exec -w "$repo_dir" -u "$expected_user_name" "$container_id" git merge --ff-only "$branch_name" >/dev/null

[[ -f "$repo_dir/worktree-change.txt" ]] || fail "worktree commit was not merged into the main checkout"
[[ "$(<"$repo_dir/worktree-change.txt")" = "worktree change" ]] || fail "merged worktree file content is wrong"

pass "devcontainer lifecycle creates generic worktree, links local env, and supports commit merge flow"
