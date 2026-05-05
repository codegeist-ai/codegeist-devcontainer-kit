#!/usr/bin/env bash
# release-build.sh - update the runtime-only devcontainer release branch
#
# Why this exists:
# - Consuming repositories can pin this kit as a `.devcontainer` submodule branch.
# - The release branch contains only files needed by the Dev Containers runtime,
#   not this repository's tests, documentation, Taskfile, or OpenCode workspace.
# - The branch is created as an orphan branch the first time so runtime history
#   stays separate from the development branch.
#
# Inputs:
# - Optional positional argument: release branch name, default `release`.
# - Optional `--push`: push the release branch to `origin` after updating it.
#
# Related files:
# - ../Taskfile.yaml
# - ../devcontainer.json
# - ../docker-compose.yml
# - ../Dockerfile

set -euo pipefail

release_branch="release"
push_branch=0
repo_root=""
tmp_index=""

runtime_files=(
  ".gitignore"
  ".local.env.example"
  "Dockerfile"
  "compose.local.yml.example"
  "devcontainer.json"
  "docker-compose.yml"
  "entrypoint.sh"
  "initialize.sh"
)

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: task release-build -- [release-branch] [--push]\n' >&2
}

cleanup() {
  if [ -n "$tmp_index" ]; then
    rm -f "$tmp_index"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --push)
      push_branch=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail "unknown option: $1"
      ;;
    *)
      if [ "$release_branch" != "release" ]; then
        fail "unexpected extra argument: $1"
      fi

      release_branch="$1"
      ;;
  esac

  shift
done

repo_root="$(git rev-parse --show-toplevel)"
current_branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)"

git -C "$repo_root" check-ref-format --branch "$release_branch" >/dev/null \
  || fail "invalid release branch name: $release_branch"

[ "$current_branch" = "main" ] \
  || fail "release-build must run from main, current branch is $current_branch"

[ -z "$(git -C "$repo_root" status --porcelain)" ] \
  || fail "working tree must be clean"

for runtime_file in "${runtime_files[@]}"; do
  [ -e "$repo_root/$runtime_file" ] || fail "runtime file is missing: $runtime_file"
done

trap cleanup EXIT

tmp_index="$(mktemp)"
GIT_INDEX_FILE="$tmp_index" git -C "$repo_root" read-tree --empty
GIT_INDEX_FILE="$tmp_index" git -C "$repo_root" add -- "${runtime_files[@]}"
runtime_tree="$(GIT_INDEX_FILE="$tmp_index" git -C "$repo_root" write-tree)"

parent_args=()
if git -C "$repo_root" rev-parse --verify --quiet "refs/heads/$release_branch" >/dev/null; then
  parent_args=(-p "refs/heads/$release_branch")
fi

release_commit="$(git -C "$repo_root" commit-tree "$runtime_tree" \
  "${parent_args[@]}" \
  -m "chore(release): update devcontainer runtime branch" \
  -m "Create a runtime-only devcontainer tree for consumption as a Git submodule branch.")"

git -C "$repo_root" update-ref "refs/heads/$release_branch" "$release_commit"

if [ "$push_branch" -eq 1 ]; then
  git -C "$repo_root" push origin "refs/heads/$release_branch"
fi

trap - EXIT

printf 'Updated release branch %s at %s\n' "$release_branch" "$release_commit"
