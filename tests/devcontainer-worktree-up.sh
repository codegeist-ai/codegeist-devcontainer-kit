#!/usr/bin/env bash
# devcontainer-worktree-up.sh - verify BRANCH starts the selected Git worktree
#
# Why this exists:
# - proves the worktree flow works in an actual Git repository, not only a copied
#   folder fixture
# - verifies `.codegeist/.local.env` is shared from the repository root into the
#   managed worktree
# - verifies Remote SSH-style `BRANCH=<name>` starts from the repository root but
#   opens the selected worktree as the remote workspace folder
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

repo_dir="$suite_tmp_dir/worktree-devcontainer-repo"
branch_name="feature/test-worktree"
root_container_id=""
log_file="$suite_tmp_dir/devcontainer-worktree-up.log"
expected_hostname=""
expected_workspace_folder=""
expected_user="$(id -u):$(id -u)"
expected_user_name="$(expected_container_user)"

cleanup_devcontainer() {
  if [ -n "$root_container_id" ]; then
    docker rm -f "$root_container_id" >/dev/null 2>&1 || true
  fi

}
trap cleanup_devcontainer EXIT

create_git_fixture_repo "$repo_dir"

worktree_path="$repo_dir/.worktrees/$branch_name"
expected_workspace_folder="$(expected_workspace_folder "$repo_dir" "$branch_name")"

prepare_devcontainer_home "$repo_dir"
BRANCH="$branch_name" HOME="$repo_dir" devcontainer_cli up --remove-existing-container --workspace-folder "$repo_dir" | tee "$log_file"
root_container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$root_container_id" ]] || fail "could not extract worktree container id from devcontainer output"
[[ "$(extract_remote_workspace_folder_from_log "$log_file" || true)" = "$expected_workspace_folder" ]] || fail "worktree devcontainer did not report expected remote workspace folder"

[[ -d "$worktree_path" ]] || fail "worktree path was not created: $worktree_path"
[[ -d "$worktree_path/.git" || -f "$worktree_path/.git" ]] || fail "worktree is not a Git checkout"
[[ -f "$worktree_path/.devcontainer/devcontainer.json" ]] || fail "worktree .devcontainer files are missing"
[[ -L "$worktree_path/.codegeist/.local.env" ]] || fail "worktree .codegeist/.local.env is not a symlink"
[[ -f "$repo_dir/.codegeist/.local.env" ]] || fail ".codegeist/.local.env was not created"

[[ -f "$repo_dir/.codegeist/compose.local.yml" ]] || fail "initializeCommand did not create .codegeist/compose.local.yml"
[[ -f "$repo_dir/.devcontainer/.env" ]] || fail "initializeCommand did not create .devcontainer/.env"
[[ -f "$repo_dir/.devcontainer/compose.local.gen.yml" ]] || fail "initializeCommand did not create .devcontainer/compose.local.gen.yml"
[[ "$(<"$repo_dir/.devcontainer/.env")" == *"DEVCONTAINER_WORKSPACE_FOLDER=$expected_workspace_folder"* ]] || fail "generated env does not set worktree workspace folder"
[[ -e "$worktree_path/.codegeist/.local.env" ]] || fail "worktree .codegeist/.local.env disappeared after devcontainer up"
[[ -L "$worktree_path/.codegeist/.local.env" ]] || fail "worktree .codegeist/.local.env stopped being a symlink"

expected_hostname="$(expected_generated_hostname "$repo_dir" "$branch_name")"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose file does not set worktree hostname"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"CONTAINER_USER: $expected_user_name"* ]] || fail "generated compose file does not set worktree build user"
[[ "$(<"$repo_dir/.devcontainer/compose.local.gen.yml")" == *"user: \"$expected_user\""* ]] || fail "generated compose file does not set worktree user"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if docker exec -w "$expected_workspace_folder" -u "$expected_user_name" "$root_container_id" bash -lc 'test "$(id -un)" = "'"$expected_user_name"'" && test "$(hostname)" = "'"$expected_hostname"'" && test "$DEVCONTAINER_HOSTNAME" = "'"$expected_hostname"'" && test "$DEVCONTAINER_USER" = "'"$expected_user_name"'" && test "$DEVCONTAINER_UID:$DEVCONTAINER_GID" = "'"$expected_user"'" && test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_folder"'" && test "$PWD" = "'"$expected_workspace_folder"'" && docker ps >/dev/null && git rev-parse --is-inside-work-tree >/dev/null && test "$(git rev-parse --abbrev-ref HEAD)" = "feature/test-worktree" && test -d "'"$repo_dir"'/.git"'; then
    pass "Dev Containers CLI starts Remote SSH BRANCH worktree as workspace"
    exit 0
  fi

  sleep 1
done

fail "Remote SSH BRANCH start did not expose selected worktree, nested Docker, and Git workspace"
