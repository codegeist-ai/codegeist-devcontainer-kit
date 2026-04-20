#!/usr/bin/env bash
# start-compose-local.sh - verify compose.local.yml bootstrap in a temporary git repo
#
# Why this exists:
# - Proves that `start.sh` creates the ignored `compose.local.yml` from the
#   tracked example before the devcontainer flow needs it.
# - Uses a real temporary Git repository so the launcher still exercises its
#   normal repo-root and branch detection behavior.
#
# Related files:
# - ../../start.sh
# - ../compose.local.yml.example

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
  chmod +x "$target_repo/start.sh"
  cp "$devcontainer_dir/compose.local.yml.example" "$target_repo/.devcontainer/compose.local.yml.example"
  cp "$devcontainer_dir/.local.env.example" "$target_repo/.devcontainer/.local.env"
}

run_launcher() {
  local target_repo="$1"

  W_NO_OPEN=1 "$target_repo/start.sh" >/dev/null
}

test_creates_missing_compose_local() {
  local repo_path="$temp_root/repo-create"

  mkdir -p "$repo_path"
  git init "$repo_path" >/dev/null
  copy_fixture_repo "$repo_path"

  if [ -e "$repo_path/.devcontainer/compose.local.yml" ]; then
    printf 'compose.local.yml unexpectedly exists before launcher run\n' >&2
    return 1
  fi

  run_launcher "$repo_path"

  test -f "$repo_path/.devcontainer/compose.local.yml"
  assert_file_equals \
    "$repo_path/.devcontainer/compose.local.yml.example" \
    "$repo_path/.devcontainer/compose.local.yml"
}

test_preserves_existing_compose_local() {
  local repo_path="$temp_root/repo-preserve"
  local sentinel=""

  mkdir -p "$repo_path"
  git init "$repo_path" >/dev/null
  copy_fixture_repo "$repo_path"
  sentinel="$(cat <<'EOF'
services:
  workspace:
    environment:
      KEEP_ME: "1"
EOF
)"
  printf '%s\n' "$sentinel" > "$repo_path/.devcontainer/compose.local.yml"

  run_launcher "$repo_path"

  if [ "$(<"$repo_path/.devcontainer/compose.local.yml")" != "$(printf '%s\n' "$sentinel")" ]; then
    printf 'compose.local.yml was overwritten\n' >&2
    return 1
  fi
}

printf '[start] launcher compose.local bootstrap\n'
test_creates_missing_compose_local
test_preserves_existing_compose_local
printf '[done] launcher compose.local bootstrap\n'
