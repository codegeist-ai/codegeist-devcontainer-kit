#!/usr/bin/env bash
# code-open.sh - open a Git root with this devcontainer kit in VS Code
#
# Why this exists:
# - `task code-open` is the real human entrypoint for opening the current
#   consuming repository with VS Code.
# - `task code-open-test` can point CODE_OPEN_WORKSPACE at a temporary fixture
#   and exercise this same production path without duplicating branch logic.
#
# Inputs:
# - First positional argument or BRANCH selects the managed worktree branch.
# - CODE_OPEN_WORKSPACE overrides the workspace root, defaulting to $PWD.
# - CODE_BIN can replace `code` for non-interactive tests.
#
# Related files:
# - ../Taskfile.yaml
# - ../initialize.sh
# - ../docker-compose.yml
# - ../tests/code-open-test.sh

set -euo pipefail

branch_name="${1:-${BRANCH:-}}"
workspace_dir="${CODE_OPEN_WORKSPACE:-$PWD}"
code_bin="${CODE_BIN:-code}"
container_workspace_dir=""
container_workspace_relative="."
container_workspace_suffix=""
code_workspace_dir=""

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[%(%Y-%m-%dT%H:%M:%S%z)T] %s\n' -1 "$*"
}

workspace_dir="$(realpath "$workspace_dir")"

git -C "$workspace_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "workspace is not inside a Git repository: $workspace_dir"

git_root="$(git -C "$workspace_dir" rev-parse --show-toplevel)"
[ "$git_root" = "$workspace_dir" ] \
  || fail "run from the Git root or set CODE_OPEN_WORKSPACE=$git_root"

[ -f "$workspace_dir/.devcontainer/devcontainer.json" ] \
  || fail "workspace has no .devcontainer/devcontainer.json: $workspace_dir"

container_workspace_dir="$workspace_dir"
code_workspace_dir="$workspace_dir"
if [ -n "$branch_name" ]; then
  BRANCH="$branch_name" "$workspace_dir/.devcontainer/initialize.sh"
  container_workspace_dir="$workspace_dir/.worktrees/$branch_name"
  container_workspace_relative=".worktrees/$branch_name"
  container_workspace_suffix="/.worktrees/$branch_name"
  code_workspace_dir="$container_workspace_dir"
fi

if [ -n "$branch_name" ]; then
  log "opening VS Code from Git root with BRANCH=$branch_name: $workspace_dir"
  (cd "$code_workspace_dir" && DEVCONTAINER_WORKSPACE_FOLDER="$container_workspace_dir" DEVCONTAINER_WORKSPACE_RELATIVE="$container_workspace_relative" DEVCONTAINER_WORKSPACE_SUFFIX="$container_workspace_suffix" "$code_bin" .)
else
  log "opening VS Code from Git root without BRANCH: $workspace_dir"
  (cd "$code_workspace_dir" && DEVCONTAINER_WORKSPACE_FOLDER="$container_workspace_dir" DEVCONTAINER_WORKSPACE_RELATIVE="$container_workspace_relative" DEVCONTAINER_WORKSPACE_SUFFIX="$container_workspace_suffix" "$code_bin" .)
fi
