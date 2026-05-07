#!/usr/bin/env bash
# initialize.sh - verify local devcontainer runtime files are bootstrapped
#
# Why this exists:
# - proves initializeCommand creates required local compose/env files
# - protects user-edited local files from being overwritten across devcontainer up
# - proves worktree setup is triggered by Dev Containers lifecycle, not by direct
#   script calls
#
# Related files:
# - ../initialize.sh
# - ../compose.local.yml.example
# - ../.local.env.example

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

fixture_dir="$suite_tmp_dir/initialize-fixture"
container_id=""
log_file="$suite_tmp_dir/initialize-devcontainer.log"
expected_hostname=""
expected_user="$(id -u):$(id -u)"
expected_user_name="$(expected_container_user)"
worktree_local_env=""
create_git_fixture_repo "$fixture_dir"

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

rm -f "$fixture_dir/compose.local.yml"
rm -f "$fixture_dir/.local.env"
rm -f "$fixture_dir/.devcontainer/.env"
rm -f "$fixture_dir/.devcontainer/compose.local.gen.yml"

BRANCH=feature/initialize-test devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"
expected_hostname="$(expected_generated_hostname "$fixture_dir" "feature/initialize-test")"

[[ -f "$fixture_dir/compose.local.yml" ]] || fail "compose.local.yml was not created in repository root"
[[ -f "$fixture_dir/.local.env" ]] || fail ".local.env was not created in repository root"
[[ ! -e "$fixture_dir/.devcontainer/compose.local.yml" ]] || fail "compose.local.yml was created in the kit directory"
[[ ! -e "$fixture_dir/.devcontainer/.local.env" ]] || fail ".local.env was created in the kit directory"
[[ -f "$fixture_dir/.devcontainer/compose.local.yml.example" ]] || fail "compose.local.yml.example is missing from the kit directory"
[[ -f "$fixture_dir/.devcontainer/.local.env.example" ]] || fail ".local.env.example is missing from the kit directory"
[[ -f "$fixture_dir/.devcontainer/.env" ]] || fail ".devcontainer/.env was not created"
[[ -f "$fixture_dir/.devcontainer/compose.local.gen.yml" ]] || fail ".devcontainer/compose.local.gen.yml was not created"
[[ -d "$fixture_dir/.oc_local" ]] || fail ".oc_local was not created in repository root"
[[ -f "$fixture_dir/.oc_local/.gitignore" ]] || fail ".oc_local/.gitignore was not created"
[[ "$(<"$fixture_dir/.oc_local/.gitignore")" == *"*"* ]] || fail ".oc_local/.gitignore does not ignore local OpenCode files"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_HOSTNAME=$expected_hostname"* ]] || fail ".env does not contain generated hostname"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_USER=$expected_user_name"* ]] || fail ".env does not contain generated user"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_UID=$(id -u)"* ]] || fail ".env does not contain generated UID"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_GID=$(id -u)"* ]] || fail ".env does not contain generated GID"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose file does not set generated hostname"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"CONTAINER_USER: $expected_user_name"* ]] || fail "generated compose file does not set generated build user"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"user: \"$expected_user\""* ]] || fail "generated compose file does not set generated user"
[[ -d "$fixture_dir/.worktrees/feature/initialize-test" ]] || fail "initializeCommand did not create the requested worktree"
worktree_local_env="$fixture_dir/.worktrees/feature/initialize-test/.local.env"
[[ -L "$worktree_local_env" ]] || fail "worktree .local.env is not a symlink"
rm -f "$worktree_local_env"
printf 'WORKTREE_LOCAL_ENV=1\n' >"$worktree_local_env"
BRANCH=feature/initialize-test "$fixture_dir/.devcontainer/initialize.sh"
[[ -f "$worktree_local_env" ]] || fail "existing worktree .local.env file was removed"
[[ ! -L "$worktree_local_env" ]] || fail "existing worktree .local.env file was replaced with a symlink"
[[ "$(<"$worktree_local_env")" = "WORKTREE_LOCAL_ENV=1" ]] || fail "existing worktree .local.env file was overwritten"
[[ -z "$(git -C "$fixture_dir" status --porcelain -- .worktrees/feature/initialize-test/.local.env)" ]] || fail "worktree .local.env is not ignored"
[[ "$(<"$fixture_dir/compose.local.yml")" != *"/workspace"* ]] || fail "compose.local.yml should not mount the workspace"
[[ "$(<"$fixture_dir/compose.local.yml")" != *".worktrees"* ]] || fail "compose.local.yml should not mount selected worktrees"
[[ -z "$(git -C "$fixture_dir" status --porcelain -- .oc_local)" ]] || fail ".oc_local is not ignored"

cp "$fixture_dir/compose.local.yml" "$fixture_dir/compose.local.yml.before"
cp "$fixture_dir/.local.env" "$fixture_dir/.local.env.before"
printf '\n# local compose marker\n' >>"$fixture_dir/compose.local.yml"
printf 'CUSTOM_ENV=1\n' >"$fixture_dir/.local.env"

BRANCH=feature/initialize-test devcontainer_cli up --workspace-folder "$fixture_dir" >/dev/null

[[ "$(<"$fixture_dir/compose.local.yml")" == *"# local compose marker"* ]] || fail "compose.local.yml was overwritten"
[[ "$(<"$fixture_dir/.local.env")" = "CUSTOM_ENV=1" ]] || fail ".local.env was overwritten"

devcontainer_cli up --workspace-folder "$fixture_dir" >/dev/null
expected_hostname="$(expected_generated_hostname "$fixture_dir" "")"

[[ "$(<"$fixture_dir/compose.local.yml")" == *"# local compose marker"* ]] || fail "compose.local.yml was overwritten when BRANCH was unset"
[[ "$(<"$fixture_dir/.local.env")" = "CUSTOM_ENV=1" ]] || fail ".local.env was overwritten when BRANCH was unset"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose hostname was not refreshed without BRANCH"

pass "initializeCommand creates local files and selected BRANCH worktrees without owning compose mounts"
