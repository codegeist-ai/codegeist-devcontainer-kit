#!/usr/bin/env bash
# initialize-vault.sh - verify optional host-side workspace Vault Agent startup
#
# Why this exists:
# - Missing HCL must not require Vault during normal initialization.
# - Malformed HCL must fail through the real host Vault CLI before custom hooks.
# - No container is needed to exercise this host-side lifecycle contract.
#
# Related files:
# - ../initialize.sh
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

if [ "$local_suite" -eq 1 ]; then
  trap cleanup_suite EXIT
fi

workspace_dir="$suite_tmp_dir/initialize-vault-workspace"
hook_marker="$workspace_dir/.codegeist/hook-ran"

create_git_fixture_repo "$workspace_dir"

"$workspace_dir/.devcontainer/initialize.sh"
assert_ignored_by_root_gitignore "$workspace_dir" ".codegeist/secrets.env"
assert_not_ignored "$workspace_dir" "secrets.hcl"
mkdir -p "$workspace_dir/.codegeist/extensions"
printf 'touch .codegeist/hook-ran\n' >"$workspace_dir/.codegeist/extensions/custom_initialize.sh"

printf 'invalid = [\n' >"$workspace_dir/secrets.hcl"
if "$workspace_dir/.devcontainer/initialize.sh"; then
  fail "initializer accepted malformed workspace Vault configuration"
fi

[[ ! -e "$hook_marker" ]] \
  || fail "initializer ran the custom hook after Vault Agent failed"

pass "host initializer ignores missing and rejects malformed Vault configuration before hooks"
