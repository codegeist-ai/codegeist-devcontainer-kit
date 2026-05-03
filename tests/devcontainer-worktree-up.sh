#!/usr/bin/env bash
# devcontainer-worktree-up.sh - verify a real Git worktree starts through Dev Containers CLI
#
# Why this exists:
# - proves the worktree flow works in an actual Git repository, not only a copied
#   folder fixture
# - verifies root .local.env is shared from the repository root into the
#   managed worktree
# - verifies devcontainer up starts from the repository root and selects the
#   worktree as /workspace without starting VS Code
#
# Related files:
# - ../initialize.sh
# - ../initialize.sh
# - ../devcontainer.json
# - ../docker-compose.yml
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

repo_dir="$suite_tmp_dir/worktree-devcontainer-repo"
branch_name="feature/test-worktree"
root_container_id=""
prepare_log_file="$suite_tmp_dir/devcontainer-worktree-prepare.log"
expected_hostname=""
expected_user="$(id -u):$(id -u)"
expected_user_name="$(expected_container_user)"

cleanup_devcontainer() {
  if [ -n "$root_container_id" ]; then
    docker rm -f "$root_container_id" >/dev/null 2>&1 || true
  fi

}
trap cleanup_devcontainer EXIT

create_git_fixture_repo "$repo_dir"

BRANCH="$branch_name" devcontainer_cli up --workspace-folder "$repo_dir" | tee "$prepare_log_file"
root_container_id="$(extract_container_id_from_log "$prepare_log_file" || true)"
[[ -n "$root_container_id" ]] || fail "could not extract preparation container id from devcontainer output"
[[ "$(extract_remote_workspace_folder_from_log "$prepare_log_file" || true)" = "/workspace" ]] || fail "worktree devcontainer did not report /workspace as remote workspace folder"

worktree_path="$repo_dir/.worktrees/$branch_name"

[[ -d "$worktree_path" ]] || fail "worktree path was not created: $worktree_path"
[[ -d "$worktree_path/.git" || -f "$worktree_path/.git" ]] || fail "worktree is not a Git checkout"
[[ -f "$worktree_path/.devcontainer/devcontainer.json" ]] || fail "worktree .devcontainer files are missing"
[[ -L "$worktree_path/.local.env" ]] || fail "worktree .local.env is not a symlink"
[[ -f "$repo_dir/.local.env" ]] || fail "root .local.env was not created"

[[ -f "$repo_dir/compose.local.yml" ]] || fail "initializeCommand did not create root compose.local.yml"
[[ -f "$repo_dir/.devcontainer/.gen.env" ]] || fail "initializeCommand did not create .devcontainer/.gen.env"
[[ -f "$repo_dir/.devcontainer/compose.local.gen.yml" ]] || fail "initializeCommand did not create .devcontainer/compose.local.gen.yml"
expected_hostname="$(expected_generated_hostname "$repo_dir" "$branch_name")"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose file does not set worktree hostname"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"CONTAINER_USER: $expected_user_name"* ]] || fail "generated compose file does not set worktree build user"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"user: \"$expected_user\""* ]] || fail "generated compose file does not set worktree user"
[[ -e "$worktree_path/.local.env" ]] || fail "worktree .local.env disappeared after devcontainer up"
[[ -L "$worktree_path/.local.env" ]] || fail "worktree .local.env stopped being a symlink"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if docker exec -w /workspace -u "$expected_user_name" "$root_container_id" bash -lc 'test "$(id -un)" = "'"$expected_user_name"'" && test "$(hostname)" = "'"$expected_hostname"'" && test "$DEVCONTAINER_HOSTNAME" = "'"$expected_hostname"'" && test "$DEVCONTAINER_USER" = "'"$expected_user_name"'" && test "$DEVCONTAINER_UID:$DEVCONTAINER_GID" = "'"$expected_user"'" && docker ps >/dev/null && git rev-parse --is-inside-work-tree >/dev/null && test "$(git rev-parse --abbrev-ref HEAD)" = "feature/test-worktree" && test -d "'"$repo_dir"'/.git"'; then
    pass "root Dev Containers CLI start selects real Git worktree as workspace with nested Docker"
    exit 0
  fi

  sleep 1
done

fail "devcontainer root start did not expose selected worktree, nested Docker, and Git workspace"
