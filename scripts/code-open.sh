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

update_branch_env() {
  local env_file="$1"
  local branch="$2"
  local tmp_file=""

  mkdir -p "$(dirname "$env_file")"

  if [ -n "$branch" ]; then
    printf 'BRANCH=%s\n' "$branch" >"$env_file"
    return 0
  fi

  if [ ! -f "$env_file" ]; then
    return 0
  fi

  tmp_file="$(mktemp)"
  grep -v '^BRANCH=' "$env_file" >"$tmp_file" || true

  if [ -s "$tmp_file" ]; then
    mv "$tmp_file" "$env_file"
  else
    rm -f "$tmp_file" "$env_file"
  fi
}

workspace_dir="$(realpath "$workspace_dir")"

git -C "$workspace_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "workspace is not inside a Git repository: $workspace_dir"

git_root="$(git -C "$workspace_dir" rev-parse --show-toplevel)"
[ "$git_root" = "$workspace_dir" ] \
  || fail "run from the Git root or set CODE_OPEN_WORKSPACE=$git_root"

[ -f "$workspace_dir/.devcontainer/devcontainer.json" ] \
  || fail "workspace has no .devcontainer/devcontainer.json: $workspace_dir"

update_branch_env "$workspace_dir/.devcontainer/.env" "$branch_name"

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
  (cd "$code_workspace_dir" && BRANCH="$branch_name" DEVCONTAINER_WORKSPACE_FOLDER="$container_workspace_dir" DEVCONTAINER_WORKSPACE_RELATIVE="$container_workspace_relative" DEVCONTAINER_WORKSPACE_SUFFIX="$container_workspace_suffix" "$code_bin" .)
else
  log "opening VS Code from Git root without BRANCH: $workspace_dir"
  (cd "$code_workspace_dir" && DEVCONTAINER_WORKSPACE_FOLDER="$container_workspace_dir" DEVCONTAINER_WORKSPACE_RELATIVE="$container_workspace_relative" DEVCONTAINER_WORKSPACE_SUFFIX="$container_workspace_suffix" "$code_bin" .)
fi
