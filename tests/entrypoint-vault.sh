#!/usr/bin/env bash
# entrypoint-vault.sh - verify optional workspace Vault Agent startup
#
# Why this exists:
# - A missing workspace `secrets.hcl` must leave entrypoint startup unchanged.
# - Malformed HCL must fail through the real local Vault CLI before the requested
#   command runs, without depending on a previously built test image.
#
# Related files:
# - ../entrypoint.sh
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

workspace_dir="$suite_tmp_dir/entrypoint-vault-workspace"
requested_command_marker="$workspace_dir/requested-command-ran"

mkdir -p "$workspace_dir"

DEVCONTAINER_WORKSPACE_FOLDER="$workspace_dir" "$project_root/entrypoint.sh" true

printf 'invalid = [\n' >"$workspace_dir/secrets.hcl"
if DEVCONTAINER_WORKSPACE_FOLDER="$workspace_dir" \
  "$project_root/entrypoint.sh" touch "$requested_command_marker"; then
  fail "entrypoint accepted malformed workspace Vault configuration"
fi

[[ ! -e "$requested_command_marker" ]] \
  || fail "entrypoint ran the requested command after Vault Agent failed"

pass "entrypoint ignores missing and rejects malformed workspace Vault configuration"
