#!/usr/bin/env bash
# devcontainer-worktree-up.sh - verify a directly opened Git worktree
#
# Why this exists:
# - proves Git, not initialize.sh, creates and selects the linked worktree
# - verifies an arbitrary worktree path opens as the host-identical workspace
# - proves the exact common Git directory supports index, object, ref, and commit
#   writes without broadly mounting the main checkout
#
# Related files:
# - ../initialize.sh
# - ../devcontainer.json
# - ../docker-compose.yml

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

local_suite=0
if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  local_suite=1
fi

repo_dir="$suite_tmp_dir/worktree-main-repo"
worktree_path="$suite_tmp_dir/arbitrary-linked-checkout"
branch_name="feature/direct-worktree"
container_id=""
log_file="$suite_tmp_dir/devcontainer-worktree-up.log"

cleanup_test() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
  if [ -d "$worktree_path" ]; then
    git -C "$repo_dir" worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
  fi
  if [ "$local_suite" -eq 1 ]; then
    cleanup_suite
  fi
}
trap cleanup_test EXIT

create_git_fixture_repo "$repo_dir"
git -C "$repo_dir" worktree add -b "$branch_name" "$worktree_path" >/dev/null
prepare_devcontainer_home "$worktree_path"

expected_hostname="$(expected_generated_hostname "$worktree_path" "$branch_name")"
expected_project_name="$(expected_compose_project_name "$worktree_path" "$branch_name")"
expected_common_dir="$(expected_git_common_dir "$worktree_path")"
expected_user_name="$(expected_container_user)"
main_head_before="$(git -C "$repo_dir" rev-parse HEAD)"

HOME="$worktree_path" devcontainer_cli up \
  --remove-existing-container \
  --workspace-folder "$worktree_path" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract linked-worktree container id"
[[ "$(extract_remote_workspace_folder_from_log "$log_file" || true)" = "$worktree_path" ]] \
  || fail "Dev Containers did not open the linked worktree directly"

for expected in \
  "DEVCONTAINER_REPO_ROOT=$worktree_path" \
  "DEVCONTAINER_GIT_COMMON_DIR=$expected_common_dir" \
  "DEVCONTAINER_WORKSPACE_FOLDER=$worktree_path" \
  "DEVCONTAINER_BRANCH_NAME=feature-direct-worktree" \
  "DEVCONTAINER_HOSTNAME=$expected_hostname" \
  "DEVCONTAINER_COMPOSE_PROJECT_NAME=$expected_project_name"; do
  grep -Fx "$expected" "$worktree_path/.devcontainer/.env" >/dev/null \
    || fail "linked-worktree environment is missing: $expected"
done
[[ -f "$worktree_path/.codegeist/.local.env" && ! -L "$worktree_path/.codegeist/.local.env" ]] \
  || fail "linked worktree does not own an independent local environment"
[[ ! -e "$repo_dir/.codegeist" ]] \
  || fail "linked-worktree initialization changed the main checkout local state"
[[ "$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$container_id")" = "$expected_project_name" ]] \
  || fail "linked-worktree container has the wrong Compose project"

mount_sources="$(docker inspect --format '{{range .Mounts}}{{println .Source}}{{end}}' "$container_id")"
grep -Fx "$worktree_path" <<<"$mount_sources" >/dev/null \
  || fail "linked worktree is not mounted at its host path"
grep -Fx "$expected_common_dir" <<<"$mount_sources" >/dev/null \
  || fail "exact Git common directory is not mounted"
if grep -Fx "$repo_dir" <<<"$mount_sources" >/dev/null; then
  fail "main checkout was broadly mounted for linked-worktree Git metadata"
fi

docker exec -w "$worktree_path" -u "$expected_user_name" "$container_id" bash -lc '
  set -euo pipefail
  test "$PWD" = "'"$worktree_path"'"
  test "$(git rev-parse --show-toplevel)" = "'"$worktree_path"'"
  test "$(git rev-parse --path-format=absolute --git-common-dir)" = "'"$expected_common_dir"'"
  test "$(git rev-parse --abbrev-ref HEAD)" = "'"$branch_name"'"
  test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$worktree_path"'"
  test "$(hostname)" = "'"$expected_hostname"'"
  docker ps >/dev/null
  printf "direct worktree commit\n" > direct-worktree.txt
  git add direct-worktree.txt
  git commit -m "test direct worktree commit" >/dev/null
'

[[ "$(git -C "$repo_dir" rev-parse HEAD)" = "$main_head_before" ]] \
  || fail "linked-worktree commit moved the main branch"
[[ "$(git -C "$worktree_path" log -1 --format=%s)" = "test direct worktree commit" ]] \
  || fail "container commit was not recorded on the linked-worktree branch"

pass "directly opened linked worktree has isolated state and writable Git metadata"
