#!/usr/bin/env bash
# code-open-test.sh - prepare a fixture and execute the real code-open task
#
# Why this exists:
# - Keeps `task code-open-test` as a manual reality-test helper without
#   duplicating the production `task code-open` behavior.
# - Leaves the temporary repository on disk for manual inspection and for the VS
#   Code window that was just opened.
#
# Inputs:
# - First positional argument or BRANCH selects a worktree branch.
# - KEEP_CODE_FIXTURE_DIR can point at an existing or desired directory instead
#   of creating a new temporary directory.
# - CODE_BIN can replace `code` for non-interactive tests.
#
# Related files:
# - ../Taskfile.yaml
# - ../scripts/code-open.sh
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

branch_name="${1:-${BRANCH:-}}"
fixture_dir="${KEEP_CODE_FIXTURE_DIR:-$(mktemp -d -t devcontainer-code-open-XXXXXX)}"

if [ -e "$fixture_dir" ] && [ -n "$(ls -A "$fixture_dir" 2>/dev/null)" ]; then
  fail "fixture directory is not empty: $fixture_dir"
fi

create_git_fixture_repo "$fixture_dir"

log "created VS Code fixture at $fixture_dir"

if [ -n "$branch_name" ]; then
  log "starting real code-open task from fixture root with BRANCH=$branch_name"
  CODE_OPEN_WORKSPACE="$fixture_dir" task -t "$project_root/Taskfile.yaml" code-open -- "$branch_name"
else
  log "starting real code-open task from fixture root without BRANCH"
  CODE_OPEN_WORKSPACE="$fixture_dir" task -t "$project_root/Taskfile.yaml" code-open
fi

pass "started VS Code for temporary devcontainer fixture: $fixture_dir"
