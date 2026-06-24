#!/usr/bin/env bash
# initialize.sh - verify local devcontainer runtime files are bootstrapped
#
# Why this exists:
# - proves initializeCommand creates required local env and generated Compose files
# - protects user-edited local files from being overwritten across devcontainer up
# - proves root-side worktree preparation and later Dev Containers lifecycle
#   initialization preserve user-owned local files
#
# Related files:
# - ../initialize.sh
# - ../compose.local.yml.example
# - ../.local.env.example

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

local_suite=0
if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  local_suite=1
fi

fixture_dir="$suite_tmp_dir/initialize-fixture"
container_id=""
log_file="$suite_tmp_dir/initialize-devcontainer.log"
expected_hostname=""
expected_project_name=""
expected_user="$(id -u):$(id -u)"
expected_user_name="$(expected_container_user)"
expected_kvm_gid="$(stat -c %g /dev/kvm 2>/dev/null || id -g)"
expected_chrome_cdp_profile_dir="$fixture_dir/.config/codegeist-chrome-cdp"
worktree_path=""
worktree_local_env=""
current_branch=""
current_branch_alias=""
create_git_fixture_repo "$fixture_dir"

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}

cleanup_test() {
  cleanup_devcontainer
  if [ "$local_suite" -eq 1 ]; then
    cleanup_suite
  fi
}
trap cleanup_test EXIT

rm -rf "$fixture_dir/.codegeist"
printf '# legacy compose marker\n' >"$fixture_dir/compose.local.yml"
printf 'LEGACY_ENV=1\n' >"$fixture_dir/.local.env"
rm -f "$fixture_dir/.devcontainer/.env"
rm -f "$fixture_dir/.devcontainer/compose.local.gen.yml"
rm -f "$fixture_dir/.devcontainer/compose.user.gen.yml"

env -u CODEGEIST_CHROME_CDP_PROFILE_DIR HOME="$fixture_dir" DISPLAY=localhost:42.0 BRANCH=feature/initialize-test "$fixture_dir/.devcontainer/initialize.sh"
expected_hostname="$(expected_generated_hostname "$fixture_dir" "feature/initialize-test")"
expected_project_name="$(expected_compose_project_name "$fixture_dir" "feature/initialize-test")"

[[ -f "$fixture_dir/.codegeist/compose.local.yml" ]] || fail ".codegeist/compose.local.yml was not created"
[[ ! -e "$fixture_dir/.codegeist/Dockerfile" ]] || fail ".codegeist/Dockerfile was created without an on-demand extension"
[[ -f "$fixture_dir/.codegeist/.local.env" ]] || fail ".codegeist/.local.env was not created"
[[ "$(<"$fixture_dir/.codegeist/compose.local.yml")" == *"# legacy compose marker"* ]] || fail "legacy compose.local.yml was not migrated"
[[ "$(<"$fixture_dir/.codegeist/.local.env")" = "LEGACY_ENV=1" ]] || fail "legacy .local.env was not migrated"
[[ ! -e "$fixture_dir/.devcontainer/compose.local.yml" ]] || fail "compose.local.yml was created in the kit directory"
[[ ! -e "$fixture_dir/.devcontainer/.local.env" ]] || fail ".local.env was created in the kit directory"
[[ -f "$fixture_dir/.devcontainer/compose.local.yml.example" ]] || fail "compose.local.yml.example is missing from the kit directory"
[[ -f "$fixture_dir/.devcontainer/.local.env.example" ]] || fail ".local.env.example is missing from the kit directory"
[[ -f "$fixture_dir/.devcontainer/.env" ]] || fail ".devcontainer/.env was not created"
[[ -f "$fixture_dir/.devcontainer/compose.local.gen.yml" ]] || fail ".devcontainer/compose.local.gen.yml was not created"
[[ -f "$fixture_dir/.devcontainer/compose.user.gen.yml" ]] || fail ".devcontainer/compose.user.gen.yml was not created"
[[ -d "$expected_chrome_cdp_profile_dir" ]] || fail "shared Chrome CDP profile directory was not created"
[[ "$(<"$fixture_dir/.devcontainer/compose.user.gen.yml")" == *"# legacy compose marker"* ]] || fail "user compose bridge did not copy legacy compose override"
[[ -f "$fixture_dir/.gitignore" ]] || fail ".gitignore was not created"
[[ -d "$fixture_dir/.oc_local" ]] || fail ".oc_local was not created in repository root"
[[ -f "$fixture_dir/.oc_local/.gitignore" ]] || fail ".oc_local/.gitignore was not created"
[[ "$(<"$fixture_dir/.oc_local/.gitignore")" == *"*"* ]] || fail ".oc_local/.gitignore does not ignore local OpenCode files"
assert_not_ignored "$fixture_dir" ".codegeist/compose.local.yml"
[[ -n "$(git -C "$fixture_dir" status --porcelain -- .codegeist/compose.local.yml)" ]] || fail ".codegeist/compose.local.yml is not visible to git status"
assert_not_ignored "$fixture_dir" ".codegeist/Dockerfile"
assert_ignored_by_root_gitignore "$fixture_dir" ".codegeist/.local.env"
assert_ignored_by_root_gitignore "$fixture_dir" ".oc_local/.gitignore"
assert_ignored_by_root_gitignore "$fixture_dir" ".worktrees/feature/initialize-test/.codegeist/.local.env"
assert_info_exclude_lacks_patterns \
  "$fixture_dir" \
  "/.oc_local/" \
  "/.oc_local/.gitignore" \
  "/.worktrees/" \
  "/.codegeist/.local.env" \
  "/.codegeist/Dockerfile" \
  "/.codegeist/compose.local.yml"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_HOSTNAME=$expected_hostname"* ]] || fail ".env does not contain generated hostname"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_COMPOSE_PROJECT_NAME=$expected_project_name"* ]] || fail ".env does not contain generated Compose project name"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_USER=$expected_user_name"* ]] || fail ".env does not contain generated user"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_UID=$(id -u)"* ]] || fail ".env does not contain generated UID"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_GID=$(id -u)"* ]] || fail ".env does not contain generated GID"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_KVM_GID=$expected_kvm_gid"* ]] || fail ".env does not contain generated KVM GID"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_DISPLAY=localhost:42.0"* ]] || fail ".env does not contain generated DISPLAY"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"CODEGEIST_CHROME_CDP_PROFILE_DIR=$expected_chrome_cdp_profile_dir"* ]] || fail ".env does not contain shared Chrome CDP profile path"
[[ "$(<"$fixture_dir/.devcontainer/.env")" != *"BRANCH="* ]] || fail ".env persisted BRANCH input"
! grep -q '^COMPOSE_PROJECT_NAME=' "$fixture_dir/.devcontainer/.env" || fail ".env persisted Docker Compose project override"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"name: $expected_project_name"* ]] || fail "generated compose file does not set generated project name"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose file does not set generated hostname"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"\"$expected_hostname:127.0.0.1\""* ]] || fail "generated compose file does not resolve generated hostname"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"CONTAINER_USER: $expected_user_name"* ]] || fail "generated compose file does not set generated build user"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"user: \"$expected_user\""* ]] || fail "generated compose file does not set generated user"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" != *"group_add:"* ]] || fail "generated compose file should not own KVM group_add"
[[ -z "$(git -C "$fixture_dir" status --porcelain -- .devcontainer/compose.user.gen.yml)" ]] || fail "user compose bridge is not ignored"
worktree_path="$fixture_dir/.worktrees/feature/initialize-test"
[[ -d "$worktree_path" ]] || fail "root initializer did not create the requested worktree"
worktree_local_env="$worktree_path/.codegeist/.local.env"
[[ -L "$worktree_local_env" ]] || fail "worktree .codegeist/.local.env is not a symlink"
rm -f "$worktree_local_env"
printf 'WORKTREE_LOCAL_ENV=1\n' >"$worktree_local_env"
env -u CODEGEIST_CHROME_CDP_PROFILE_DIR HOME="$fixture_dir" BRANCH=feature/initialize-test "$fixture_dir/.devcontainer/initialize.sh"
[[ -f "$worktree_local_env" ]] || fail "existing worktree .codegeist/.local.env file was removed"
[[ ! -L "$worktree_local_env" ]] || fail "existing worktree .codegeist/.local.env file was replaced with a symlink"
[[ "$(<"$worktree_local_env")" = "WORKTREE_LOCAL_ENV=1" ]] || fail "existing worktree .codegeist/.local.env file was overwritten"
assert_ignored_by_root_gitignore "$fixture_dir" ".worktrees/feature/initialize-test/.codegeist/.local.env"
[[ -z "$(git -C "$fixture_dir" status --porcelain -- .worktrees/feature/initialize-test/.codegeist/.local.env)" ]] || fail "worktree .codegeist/.local.env is not ignored"
[[ "$(<"$fixture_dir/.codegeist/compose.local.yml")" != *"/workspace"* ]] || fail ".codegeist/compose.local.yml should not mount the workspace"
[[ "$(<"$fixture_dir/.codegeist/compose.local.yml")" != *".worktrees"* ]] || fail ".codegeist/compose.local.yml should not mount selected worktrees"
assert_ignored_by_root_gitignore "$fixture_dir" ".oc_local/.gitignore"
[[ -z "$(git -C "$fixture_dir" status --porcelain -- .oc_local)" ]] || fail ".oc_local is not ignored"

cp "$fixture_dir/.codegeist/compose.local.yml" "$fixture_dir/.codegeist/compose.local.yml.before"
cp "$fixture_dir/.codegeist/.local.env" "$fixture_dir/.codegeist/.local.env.before"
printf '\n# local compose marker\n' >>"$fixture_dir/.codegeist/compose.local.yml"
printf 'CUSTOM_ENV=1\n' >"$fixture_dir/.codegeist/.local.env"

env -u CODEGEIST_CHROME_CDP_PROFILE_DIR HOME="$fixture_dir" BRANCH=feature/initialize-test "$fixture_dir/.devcontainer/initialize.sh"

[[ "$(<"$fixture_dir/.codegeist/compose.local.yml")" == *"# local compose marker"* ]] || fail ".codegeist/compose.local.yml was overwritten"
[[ "$(<"$fixture_dir/.devcontainer/compose.user.gen.yml")" == *"# local compose marker"* ]] || fail "user compose bridge did not refresh local compose marker"
[[ "$(<"$fixture_dir/.codegeist/.local.env")" = "CUSTOM_ENV=1" ]] || fail ".codegeist/.local.env was overwritten"

env -u BRANCH -u DISPLAY -u CODEGEIST_CHROME_CDP_PROFILE_DIR HOME="$fixture_dir" "$fixture_dir/.devcontainer/initialize.sh"
[[ "$(<"$fixture_dir/.devcontainer/.env")" != *"BRANCH="* ]] || fail "generated .env kept stale BRANCH after unset start"
[[ "$(<"$fixture_dir/.devcontainer/.env")" != *"DEVCONTAINER_BRANCH_NAME=feature-initialize-test"* ]] || fail "generated .env reused stale branch after unset start"
[[ "$(<"$fixture_dir/.devcontainer/.env")" != *"DEVCONTAINER_COMPOSE_PROJECT_NAME=$expected_project_name"* ]] || fail "generated .env reused stale Compose project after unset start"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_WORKSPACE_FOLDER=$fixture_dir"* ]] || fail "generated .env did not reset workspace when BRANCH was unset"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_DISPLAY="* ]] || fail "generated .env removed DISPLAY key after unset start"
[[ "$(<"$fixture_dir/.devcontainer/.env")" != *"DEVCONTAINER_DISPLAY=localhost:42.0"* ]] || fail "generated .env reused stale DISPLAY after unset start"

current_branch="$(git -C "$fixture_dir" rev-parse --abbrev-ref HEAD)"
current_branch_alias="$fixture_dir/.worktrees/$current_branch"
env -u CODEGEIST_CHROME_CDP_PROFILE_DIR HOME="$fixture_dir" BRANCH="$current_branch" "$fixture_dir/.devcontainer/initialize.sh"
[[ -L "$current_branch_alias" ]] || fail "current branch did not create a worktree alias"
[[ "$(readlink -f "$current_branch_alias")" = "$fixture_dir" ]] || fail "current branch alias does not resolve to repository root"
git -C "$fixture_dir" switch -c replacement-root >/dev/null
env -u CODEGEIST_CHROME_CDP_PROFILE_DIR HOME="$fixture_dir" BRANCH="$current_branch" "$fixture_dir/.devcontainer/initialize.sh"
[[ -d "$current_branch_alias" ]] || fail "stale current branch alias was not replaced with a worktree"
[[ ! -L "$current_branch_alias" ]] || fail "stale current branch alias is still a symlink"
[[ "$(git -C "$current_branch_alias" rev-parse --abbrev-ref HEAD)" = "$current_branch" ]] || fail "replaced current branch alias is not on the original branch"

prepare_devcontainer_home "$worktree_path"
HOME="$worktree_path" devcontainer_cli up --remove-existing-container --workspace-folder "$worktree_path" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"
expected_hostname="$(expected_generated_hostname "$worktree_path" "feature/initialize-test")"

[[ "$(<"$fixture_dir/.codegeist/compose.local.yml")" == *"# local compose marker"* ]] || fail ".codegeist/compose.local.yml was overwritten when BRANCH was unset"
[[ "$(<"$fixture_dir/.codegeist/.local.env")" = "CUSTOM_ENV=1" ]] || fail ".codegeist/.local.env was overwritten when BRANCH was unset"
[[ "$(<"$worktree_path/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose hostname was not refreshed for worktree start"
[[ "$(<"$worktree_path/.devcontainer/compose.local.gen.yml")" == *"\"$expected_hostname:127.0.0.1\""* ]] || fail "generated compose hostname resolution was not refreshed for worktree start"

pass "initialize creates .codegeist local files and selected BRANCH worktrees without owning compose mounts"
