#!/usr/bin/env bash
# start-compose-local.sh - verify the launcher relies on the tracked root overlay
#
# Why this exists:
# - Proves that `start.sh` no longer needs a per-worktree
#   `.devcontainer/compose.local.yml` bootstrap file.
# - Confirms the tracked root `compose.local.yml` remains untouched when the
#   launcher prepares a temporary repository checkout.
# - Uses a real temporary Git repository so the launcher still exercises its
#   normal repo-root and branch detection behavior.
#
# Related files:
# - ../../start.sh
# - ../../compose.local.yml

set -euo pipefail

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
devcontainer_dir="$(dirname "$script_dir")"
source_repo_root="$(dirname "$devcontainer_dir")"
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT

assert_file_equals() {
  local expected="$1"
  local actual="$2"

  cmp -s "$expected" "$actual"
}

copy_fixture_repo() {
  local target_repo="$1"

  mkdir -p "$target_repo/.devcontainer"
  cp "$source_repo_root/start.sh" "$target_repo/start.sh"
  cp "$devcontainer_dir/launch.sh" "$target_repo/.devcontainer/launch.sh"
  chmod +x "$target_repo/start.sh"
  chmod +x "$target_repo/.devcontainer/launch.sh"
  cp "$source_repo_root/compose.local.yml" "$target_repo/compose.local.yml"
  cp "$devcontainer_dir/.local.env.example" "$target_repo/.devcontainer/.local.env"
}

run_launcher() {
  local target_repo="$1"

  W_NO_OPEN=1 "$target_repo/start.sh" >/dev/null
}

test_preserves_tracked_root_compose_overlay() {
  local repo_path="$temp_root/repo-root-overlay"
  local expected_overlay=""

  mkdir -p "$repo_path"
  git init "$repo_path" >/dev/null
  copy_fixture_repo "$repo_path"
  expected_overlay="$(<"$repo_path/compose.local.yml")"

  run_launcher "$repo_path"

  if [ -e "$repo_path/.devcontainer/compose.local.yml" ]; then
    printf '.devcontainer/compose.local.yml should not be created anymore\n' >&2
    return 1
  fi

  if [ "$(<"$repo_path/compose.local.yml")" != "$expected_overlay" ]; then
    printf 'root compose.local.yml was modified\n' >&2
    return 1
  fi
}

printf '[start] launcher root compose overlay contract\n'
test_preserves_tracked_root_compose_overlay
printf '[done] launcher root compose overlay contract\n'
