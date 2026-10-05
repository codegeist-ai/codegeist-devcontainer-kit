#!/usr/bin/env bash
# worktree.sh - create and open branch worktrees from the runtime Taskfile
#
# Why this exists:
# - Taskfile.runtime.yaml composes the public tasks while this script keeps Git
#   validation and path handling out of shell-interpolated Task commands.
#
# Inputs:
# - action: branch-create, worktree-create, or code-start
# - DEVCONTAINER_WORKTREE_BRANCH: one branch name forwarded from Task CLI_ARGS
# - DEVCONTAINER_WORKSPACE_FOLDER: opened checkout, otherwise the current path
#
# Side effects and failure behavior:
# - branch-create creates the branch at the opened checkout's current HEAD.
# - worktree-create writes `.worktrees/<branch-with-slashes-as-dashes>` and
#   initializes its submodules. A later failure leaves created Git state intact.
# - code-start invokes the connected `code` CLI with `--new-window`.
#
# Related files:
# - ../Taskfile.runtime.yaml
# - ../README_release.md

set -euo pipefail

fail() {
  printf 'level=error event=worktree_task status=failed message=%s\n' "$*" >&2
  exit 1
}

log() {
  printf 'level=info event=%s status=%s %s\n' "$1" "$2" "$3" >&2
}

require_branch() {
  branch="${DEVCONTAINER_WORKTREE_BRANCH:-}"

  [ -n "$branch" ] || fail "pass one branch name after --"
  case "$branch" in
    *[[:space:]]*) fail "branch name must not contain whitespace: $branch" ;;
  esac

  git -C "$repo_root" check-ref-format --branch "$branch" >/dev/null 2>&1 \
    || fail "invalid branch name: $branch"

  slug="${branch//\//-}"
  worktree_path="$repo_root/.worktrees/$slug"
}

workspace="${DEVCONTAINER_WORKSPACE_FOLDER:-$PWD}"
repo_root="$(git -C "$workspace" rev-parse --show-toplevel 2>/dev/null)" \
  || fail "workspace is not inside a Git checkout: $workspace"

action="${1:-}"
require_branch

case "$action" in
  branch-create)
    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
      fail "branch already exists: $branch"
    fi

    base_commit="$(git -C "$repo_root" rev-parse HEAD)"
    log "branch_create" "started" "branch=$branch base=$base_commit"
    git -C "$repo_root" branch "$branch" "$base_commit"
    log "branch_create" "completed" "branch=$branch base=$base_commit"
    ;;

  worktree-create)
    git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" \
      || fail "branch does not exist: $branch"
    [ ! -e "$worktree_path" ] \
      || fail "worktree path already exists: $worktree_path"

    log "worktree_create" "started" "branch=$branch path=$worktree_path"
    mkdir -p "$(dirname "$worktree_path")"
    git -C "$repo_root" worktree add "$worktree_path" "$branch"
    git -C "$worktree_path" submodule update --init --recursive
    log "worktree_create" "completed" "branch=$branch path=$worktree_path"
    ;;

  code-start)
    [ -d "$worktree_path" ] || fail "worktree path does not exist: $worktree_path"
    command -v code >/dev/null 2>&1 || fail "code command is not available"
    [ -n "${VSCODE_IPC_HOOK_CLI:-}" ] \
      || fail "code command is not connected to a VS Code session"

    log "code_start" "started" "branch=$branch path=$worktree_path"
    code --new-window "$worktree_path"
    log "code_start" "completed" "branch=$branch path=$worktree_path"
    ;;

  *)
    fail "unknown action: ${action:-<empty>}"
    ;;
esac
