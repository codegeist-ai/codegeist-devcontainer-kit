#!/usr/bin/env bash
# release-build.sh - create a runtime-only devcontainer release tag
#
# Why this exists:
# - Consuming repositories can pin this kit as a `.devcontainer` submodule tag.
# - The tag commit contains only files needed by the Dev Containers runtime, not
#   this repository's tests, documentation, Taskfile, or OpenCode workspace.
#
# Inputs:
# - First positional argument: SemVer release tag, for example `v1.0.9`.
# - Optional `--push`: push the created tag to `origin` after local creation.
#
# Related files:
# - ../Taskfile.yaml
# - ../devcontainer.json
# - ../docker-compose.yml
# - ../Dockerfile

set -euo pipefail

tag_name=""
push_tag=0
tmp_branch=""
repo_root=""
tag_created=0

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
  printf 'Usage: task release-build -- v1.0.9 [--push]\n' >&2
}

cleanup() {
  if [ -n "$repo_root" ]; then
    git -C "$repo_root" switch main >/dev/null 2>&1 || true

    if [ -n "$tmp_branch" ]; then
      git -C "$repo_root" branch -D "$tmp_branch" >/dev/null 2>&1 || true
    fi

    if [ "$tag_created" -eq 1 ]; then
      git -C "$repo_root" tag -d "$tag_name" >/dev/null 2>&1 || true
    fi
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --push)
      push_tag=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail "unknown option: $1"
      ;;
    *)
      if [ -n "$tag_name" ]; then
        fail "unexpected extra argument: $1"
      fi

      tag_name="$1"
      ;;
  esac

  shift
done

[ -n "$tag_name" ] || {
  usage
  fail "missing release tag"
}

[[ "$tag_name" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
  || fail "tag must be a normal SemVer tag like v1.0.9: $tag_name"

repo_root="$(git rev-parse --show-toplevel)"
current_branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)"
tmp_branch="tmp-$tag_name"

[ "$current_branch" = "main" ] \
  || fail "release-build must run from main, current branch is $current_branch"

[ -z "$(git -C "$repo_root" status --porcelain)" ] \
  || fail "working tree must be clean"

git -C "$repo_root" rev-parse --verify --quiet "refs/tags/$tag_name" >/dev/null \
  && fail "tag already exists: $tag_name"

git -C "$repo_root" rev-parse --verify --quiet "refs/heads/$tmp_branch" >/dev/null \
  && fail "temporary branch already exists: $tmp_branch"

for runtime_file in "${runtime_files[@]}"; do
  [ -e "$repo_root/$runtime_file" ] || fail "runtime file is missing: $runtime_file"
done

trap cleanup EXIT

git -C "$repo_root" switch --quiet -c "$tmp_branch"
git -C "$repo_root" rm -r --quiet --ignore-unmatch -- .
rm -f "$repo_root/.gitmodules"
git -C "$repo_root" checkout HEAD -- "${runtime_files[@]}"
git -C "$repo_root" add -A -- "${runtime_files[@]}"

git -C "$repo_root" commit \
  -m "chore(release): prepare $tag_name devcontainer kit" \
  -m "Create a runtime-only devcontainer tree for consumption as a Git submodule tag."

git -C "$repo_root" tag -a "$tag_name" -m "$tag_name"
tag_created=1

git -C "$repo_root" switch --quiet main
git -C "$repo_root" branch -D "$tmp_branch" >/dev/null
tmp_branch=""

if [ "$push_tag" -eq 1 ]; then
  git -C "$repo_root" push origin "$tag_name"
fi

tag_created=0
trap - EXIT

printf 'Created release tag %s\n' "$tag_name"
