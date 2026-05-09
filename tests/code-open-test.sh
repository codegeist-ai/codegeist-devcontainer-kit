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
remote_workspace_folder=""
expected_workspace_folder=""

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

if [ "${CODE_OPEN_TEST_SKIP_UP:-false}" != "true" ]; then
  log "starting devcontainer CLI from fixture root"
  devcontainer_log="$fixture_dir/devcontainer-up.log"
  expected_workspace_folder="$(expected_workspace_folder "$fixture_dir" "$branch_name")"
  if [ -n "$branch_name" ]; then
    devcontainer_cli up --remove-existing-container --workspace-folder "$expected_workspace_folder" | tee "$devcontainer_log"
  else
    devcontainer_cli up --remove-existing-container --workspace-folder "$fixture_dir" | tee "$devcontainer_log"
  fi

  remote_workspace_folder="$(extract_remote_workspace_folder_from_log "$devcontainer_log")"
  [ -n "$remote_workspace_folder" ] || fail "devcontainer CLI did not report a remote workspace folder"
  [ "$remote_workspace_folder" = "$expected_workspace_folder" ] \
    || fail "devcontainer CLI reported $remote_workspace_folder, expected $expected_workspace_folder"

  if [ -n "$branch_name" ]; then
    devcontainer_cli exec --workspace-folder "$expected_workspace_folder" bash -lc '
      set -eu
      test "$PWD" = "'"$expected_workspace_folder"'"
      test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_folder"'"
      git rev-parse --is-inside-work-tree >/dev/null
      test "$(git rev-parse --abbrev-ref HEAD)" = "'"$branch_name"'"
    '
  else
    devcontainer_cli exec --workspace-folder "$fixture_dir" bash -lc '
      set -eu
      test "$PWD" = "'"$expected_workspace_folder"'"
      test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_folder"'"
      git rev-parse --is-inside-work-tree >/dev/null
    '
  fi
fi

pass "started VS Code and devcontainer for temporary fixture: $fixture_dir"
