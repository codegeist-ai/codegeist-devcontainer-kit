#!/usr/bin/env bash
# stage-runtime-tree.sh - copy the current source into the runtime release layout
#
# Inputs:
# - RUNTIME_TREE_OUTPUT_DIR: destination, relative paths resolve from repo root.
# - RUNTIME_TREE_REPLACE=true: replace an existing destination below `.tmp/`.
#
# Side effects:
# - Writes only the runtime allowlist and applies the release filename mappings.
# - Replacement is restricted to `.tmp/` so arbitrary directories are never
#   removed by the test-release workflow.
#
# Related files:
# - ../Taskfile.yaml
# - release-build.sh
# - ../tests/release-build.sh

set -euo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

repo_root="$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)"
requested_output="${RUNTIME_TREE_OUTPUT_DIR:-}"
replace_output="${RUNTIME_TREE_REPLACE:-false}"

[ -n "$requested_output" ] || fail "RUNTIME_TREE_OUTPUT_DIR is required"
case "$requested_output" in
  /*) output_dir="$(realpath -m "$requested_output")" ;;
  *) output_dir="$(realpath -m "$repo_root/$requested_output")" ;;
esac

if [ "$replace_output" = "true" ]; then
  [ -e "$repo_root/.tmp" ] || fail "replacement requires the workspace .tmp path"
  tmp_root="$(readlink -f "$repo_root/.tmp")"
  case "$output_dir" in
    "$tmp_root"/*) ;;
    *) fail "replacement destination must be below $repo_root/.tmp" ;;
  esac
  rm -rf -- "$output_dir"
fi

mkdir -p "$output_dir"
[ -z "$(ls -A "$output_dir")" ] || fail "runtime output directory is not empty: $output_dir"

runtime_files=(
  ".gitignore"
  ".local.env.example"
  ".oc_local.gitignore.example"
  ".oc_local.opencode.json.example"
  "cmds/oc"
  "cmds/oc-record"
  "LICENSE"
  "Dockerfile.example"
  "compose.local.yml.example"
  "devcontainer.json"
  "docker-compose.yml"
  "entrypoint.sh"
  "initialize.sh"
  "scripts/chrome.sh"
  "scripts/worktree.sh"
)

for runtime_file in "${runtime_files[@]}"; do
  [ -e "$repo_root/$runtime_file" ] || fail "runtime file is missing: $runtime_file"
  mkdir -p "$output_dir/$(dirname "$runtime_file")"
  cp -p "$repo_root/$runtime_file" "$output_dir/$runtime_file"
done

cp -p "$repo_root/Dockerfile.base" "$output_dir/Dockerfile"
cp -p "$repo_root/README_release.md" "$output_dir/README.md"
cp -p "$repo_root/Taskfile.runtime.yaml" "$output_dir/Taskfile.yaml"

printf 'level=info event=runtime_tree_stage status=completed output=%s\n' "$output_dir" >&2
