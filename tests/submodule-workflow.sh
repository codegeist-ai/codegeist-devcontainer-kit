#!/usr/bin/env bash
# submodule-workflow.sh - verify consuming repo workflow with this kit as submodule
#
# Why this exists:
# - Exercises a consuming repository that does not vendor the kit directly but
#   adds it as `.devcontainer` through `git submodule add`.
# - Verifies the real Dev Containers CLI lifecycle from the consuming repo root
#   with `BRANCH=dev0`, including generated root files, selected worktree mount,
#   nested Docker, and a commit/merge workflow.
#
# Related files:
# - ../initialize.sh
# - ../devcontainer.json
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

kit_repo_dir="$suite_tmp_dir/devcontainer-kit-submodule-repo"
p1_dir="$suite_tmp_dir/p1"
branch_name="dev0"
container_id=""
log_file="$suite_tmp_dir/submodule-workflow.log"
expected_hostname=""
expected_user="$(id -u):$(id -u)"
expected_user_name="$(expected_container_user)"

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

create_kit_submodule_repo "$kit_repo_dir"
create_git_repo "$p1_dir"

printf '# p1\n' >"$p1_dir/README.md"
cat >"$p1_dir/.gitignore" <<'EOF'
/.local.env
/compose.local.yml
/.worktrees/
EOF

git -C "$p1_dir" add README.md .gitignore
git -C "$p1_dir" commit -m "initial p1" >/dev/null
git -C "$p1_dir" -c protocol.file.allow=always submodule add "$kit_repo_dir" .devcontainer >/dev/null
git -C "$p1_dir" commit -m "add devcontainer submodule" >/dev/null

BRANCH="$branch_name" devcontainer_cli up --workspace-folder "$p1_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"
[[ "$(extract_remote_workspace_folder_from_log "$log_file" || true)" = "/workspace" ]] || fail "submodule workflow did not report /workspace as remote workspace folder"

worktree_path="$p1_dir/.worktrees/$branch_name"

[[ -d "$worktree_path" ]] || fail "BRANCH did not create .worktrees/$branch_name"
[[ -f "$worktree_path/.git" ]] || fail "selected worktree does not have a Git file"
[[ -f "$p1_dir/.local.env" ]] || fail "root .local.env was not created"
[[ -f "$p1_dir/compose.local.yml" ]] || fail "root compose.local.yml was not created"
[[ -f "$p1_dir/.devcontainer/.env" ]] || fail ".devcontainer/.env was not created"
[[ -z "$(git -C "$p1_dir/.devcontainer" status --porcelain -- .env)" ]] || fail ".devcontainer/.env is not ignored by the submodule"
[[ -f "$p1_dir/.devcontainer/compose.local.gen.yml" ]] || fail ".devcontainer/compose.local.gen.yml was not created"
expected_hostname="$(expected_generated_hostname "$p1_dir" "$branch_name")"
[[ "$(<"$p1_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose file does not set submodule hostname"
[[ "$(<"$p1_dir/.devcontainer/compose.local.gen.yml")" == *"CONTAINER_USER: $expected_user_name"* ]] || fail "generated compose file does not set submodule build user"
[[ "$(<"$p1_dir/.devcontainer/compose.local.gen.yml")" == *"user: \"$expected_user\""* ]] || fail "generated compose file does not set submodule user"
[[ -L "$worktree_path/.local.env" ]] || fail "worktree .local.env is not a symlink"
[[ -f "$worktree_path/.devcontainer/devcontainer.json" ]] || fail "submodule devcontainer is missing in worktree"

docker exec -w /workspace -u "$expected_user_name" "$container_id" bash -lc '
  test "$(pwd)" = /workspace
  test "$(hostname)" = "'"$expected_hostname"'"
  test "$DEVCONTAINER_HOSTNAME" = "'"$expected_hostname"'"
  test "$DEVCONTAINER_USER" = "'"$expected_user_name"'"
  test "$DEVCONTAINER_UID:$DEVCONTAINER_GID" = "'"$expected_user"'"
  test "$(git rev-parse --show-toplevel)" = /workspace
  test "$(git rev-parse --abbrev-ref HEAD)" = dev0
  test -f .git
  grep -q "/.git/worktrees/dev0" .git
  docker ps >/dev/null
'

docker exec -w /workspace -u "$expected_user_name" "$container_id" bash -lc '
  printf "dev0 change\n" > dev0-change.txt
  git add dev0-change.txt
  git commit -m "add dev0 change" >/dev/null
'

docker exec -w "$p1_dir" -u "$expected_user_name" "$container_id" git merge --ff-only "$branch_name" >/dev/null

[[ -f "$p1_dir/dev0-change.txt" ]] || fail "dev0 commit was not merged into main checkout"
[[ "$(<"$p1_dir/dev0-change.txt")" = "dev0 change" ]] || fail "merged file content is wrong"
[[ "$(git -C "$p1_dir" rev-parse main)" = "$(git -C "$p1_dir" rev-parse "$branch_name")" ]] || fail "main does not point at dev0 after fast-forward merge"

pass "submodule consuming repo starts selected worktree and supports dev0 commit merge"
