#!/usr/bin/env bash
# code-open.sh - create a temporary consuming repo and open it in VS Code
#
# Why this exists:
# - Exercises the real human entrypoint: opening the repository root with `code`.
# - Copies this kit into `.devcontainer/` in a temporary Git repository so VS
#   Code can discover `devcontainer.json` exactly as a consuming repo would.
# - Leaves the temporary repository on disk for manual inspection and for the VS
#   Code window that was just opened.
#
# Inputs:
# - BRANCH or the first positional argument selects a worktree branch. When set,
#   VS Code still opens the Git root and `initializeCommand` should select the
#   worktree as `/workspace` inside the container.
# - KEEP_CODE_FIXTURE_DIR can point at an existing or desired directory instead
#   of creating a new temporary directory.
#
# Related files:
# - ../devcontainer.json
# - ../initialize.sh
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
  log "starting VS Code from fixture root with BRANCH=$branch_name"
  BRANCH="$branch_name" code "$fixture_dir"
else
  log "starting VS Code from fixture root without BRANCH"
  code "$fixture_dir"
fi

pass "started VS Code for temporary devcontainer fixture: $fixture_dir"
