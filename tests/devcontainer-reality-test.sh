#!/usr/bin/env bash
# devcontainer-reality-test.sh - verify the current kit as a real consumer
#
# Why this exists:
# - Tests the current source worktree as a temporary consuming repository rather
#   than reopening this source repository's already-pinned devcontainer.
# - Uses the Dev Containers CLI for deterministic build, startup, and in-container
#   checks without claiming that a nested `code` invocation changed runtimes.
# - Leaves the temporary repository and container available for manual inspection.
#
# Inputs:
# - First positional argument or BRANCH selects a worktree branch.
# - KEEP_REALITY_FIXTURE_DIR can select an empty fixture directory instead of a
#   newly allocated operating-system temporary directory.
#
# Outputs:
# - Reports the retained fixture, container ID, and an exact `devcontainer exec`
#   command for opening that fixture workspace. The explicit workspace argument
#   is required because container-ID execution otherwise starts in the user's
#   home directory. Unsetting TMUX prevents `oc` from reusing the caller's outer
#   tmux server when this test is launched from an existing `oc` session.
#
# Related files:
# - ../Taskfile.yaml
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

branch_name="${1:-${BRANCH:-}}"
fixture_dir="${KEEP_REALITY_FIXTURE_DIR:-$(mktemp -d -t devcontainer-reality-XXXXXX)}"
remote_workspace_folder=""
expected_workspace_folder=""
expected_remote_workspace_folder=""
container_id=""

if [ -e "$fixture_dir" ] && [ -n "$(ls -A "$fixture_dir" 2>/dev/null)" ]; then
  fail "fixture directory is not empty: $fixture_dir"
fi

create_git_fixture_repo "$fixture_dir"

log "created devcontainer fixture at $fixture_dir"
expected_workspace_folder="$(expected_workspace_folder "$fixture_dir" "$branch_name")"
expected_remote_workspace_folder="$(expected_remote_workspace_folder "$expected_workspace_folder")"
remote_workspace_folder="$expected_remote_workspace_folder"

if [ -n "$branch_name" ]; then
  log "preparing fixture worktree with BRANCH=$branch_name"
  BRANCH="$branch_name" "$fixture_dir/.devcontainer/initialize.sh"
fi

if [ "${DEVCONTAINER_REALITY_TEST_SKIP_UP:-false}" != "true" ]; then
  log "starting devcontainer CLI from fixture root"
  devcontainer_log="$fixture_dir/devcontainer-up.log"
  if [ -n "$branch_name" ]; then
    prepare_devcontainer_home "$expected_workspace_folder"
    HOME="$expected_workspace_folder" devcontainer_cli up --remove-existing-container --workspace-folder "$expected_workspace_folder" | tee "$devcontainer_log"
  else
    prepare_devcontainer_home "$fixture_dir"
    HOME="$fixture_dir" devcontainer_cli up --remove-existing-container --workspace-folder "$fixture_dir" | tee "$devcontainer_log"
  fi

  remote_workspace_folder="$(extract_remote_workspace_folder_from_log "$devcontainer_log")"
  [ -n "$remote_workspace_folder" ] || fail "devcontainer CLI did not report a remote workspace folder"
  [ "$remote_workspace_folder" = "$expected_remote_workspace_folder" ] \
    || fail "devcontainer CLI reported $remote_workspace_folder, expected $expected_remote_workspace_folder"
  container_id="$(extract_container_id_from_log "$devcontainer_log")"
  [ -n "$container_id" ] || fail "devcontainer CLI did not report a container ID"

  if [ -n "$branch_name" ]; then
    devcontainer_cli exec --container-id "$container_id" bash -c '
      set -eu
      cd "$DEVCONTAINER_WORKSPACE_FOLDER"
      test "$(pwd -P)" = "'"$expected_workspace_folder"'"
      test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_folder"'"
      test "$(command -v oc)" = "/usr/local/bin/oc"
      git rev-parse --is-inside-work-tree >/dev/null
      test "$(git rev-parse --abbrev-ref HEAD)" = "'"$branch_name"'"
    '
  else
    devcontainer_cli exec --container-id "$container_id" bash -c '
      set -eu
      cd "$DEVCONTAINER_WORKSPACE_FOLDER"
      test "$(pwd -P)" = "'"$expected_workspace_folder"'"
      test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_folder"'"
      test "$(command -v oc)" = "/usr/local/bin/oc"
      git rev-parse --is-inside-work-tree >/dev/null
    '
  fi
fi

pass "verified current kit in temporary consuming devcontainer: $fixture_dir"
if [ -n "$container_id" ]; then
  log "container ID: $container_id"
  log "manual OpenCode command: devcontainer exec --container-id $container_id env -u TMUX oc $(printf '%q' "$expected_workspace_folder")"
fi
