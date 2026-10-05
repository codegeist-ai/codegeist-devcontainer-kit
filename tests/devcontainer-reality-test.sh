#!/usr/bin/env bash
# devcontainer-reality-test.sh - verify a staged runtime release as a consumer
#
# Why this exists:
# - Tests the exact runtime tree produced from the current source worktree rather
#   than reopening this repository's already-pinned devcontainer.
# - Uses the Dev Containers CLI for deterministic build, startup, and in-container
#   checks without claiming that a nested `code` invocation changed runtimes.
# - Bridges the caller's connected VS Code remote CLI into the fixture container
#   when its IPC socket and server installation are available.
# - Opens Bash in the verified container and leaves the fixture available afterward.
#
# Inputs:
# - DEVCONTAINER_TEST_RELEASE_DIR must select a staged runtime release tree.
# - KEEP_REALITY_FIXTURE_DIR can select an empty fixture directory instead of a
#   newly allocated operating-system temporary directory.
#
# Outputs:
# - Reports the retained fixture and container ID, then opens Bash in that
#   container with the fixture selected as its workspace.
#
# Related files:
# - ../Taskfile.yaml
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

fixture_dir="${KEEP_REALITY_FIXTURE_DIR:-$(mktemp -d -t devcontainer-reality-XXXXXX)}"
requested_release_dir="${DEVCONTAINER_TEST_RELEASE_DIR:-}"
release_dir=""
remote_workspace_folder=""
expected_workspace_folder=""
expected_remote_workspace_folder=""
container_id=""

configure_vscode_cli_bridge() {
  local code_cli=""
  local server_root=""
  local ipc_socket="${VSCODE_IPC_HOOK_CLI:-}"

  [ -n "$ipc_socket" ] && [ -S "$ipc_socket" ] || return 0
  code_cli="$(readlink -f "$(command -v code 2>/dev/null || true)")"
  case "$code_cli" in
    /vscode/*/bin/remote-cli/code) ;;
    *) return 0 ;;
  esac
  server_root="$(dirname "$(dirname "$(dirname "$code_cli")")")"
  [ -x "$server_root/node" ] || return 0

  mkdir -p "$fixture_dir/.codegeist/bin"
  cat >"$fixture_dir/.codegeist/bin/code" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$REALITY_VSCODE_SERVER_ROOT/bin/remote-cli/code" "$@"
EOF
  chmod +x "$fixture_dir/.codegeist/bin/code"

  cat >"$fixture_dir/.codegeist/compose.local.yml" <<EOF
services:
  workspace:
    environment:
      REALITY_VSCODE_SERVER_ROOT: "$server_root"
      VSCODE_IPC_HOOK_CLI: "$ipc_socket"
      PATH: "$fixture_dir/.codegeist/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    volumes:
      - type: bind
        source: "$server_root"
        target: "$server_root"
        read_only: true
      - type: bind
        source: "$ipc_socket"
        target: "$ipc_socket"
EOF
  log "configured VS Code CLI bridge for reality fixture"
}

[ -n "$requested_release_dir" ] \
  || fail "pass the staged release directory after --"
case "$requested_release_dir" in
  /*) release_dir="$(realpath -m "$requested_release_dir")" ;;
  *) release_dir="$(realpath -m "$project_root/$requested_release_dir")" ;;
esac
[ -f "$release_dir/devcontainer.json" ] \
  || fail "staged release is missing devcontainer.json: $release_dir"
[ -f "$release_dir/Dockerfile" ] \
  || fail "staged release is missing Dockerfile: $release_dir"

if [ -e "$fixture_dir" ] && [ -n "$(ls -A "$fixture_dir" 2>/dev/null)" ]; then
  fail "fixture directory is not empty: $fixture_dir"
fi

mkdir -p "$fixture_dir/.devcontainer"
cp -a "$release_dir/." "$fixture_dir/.devcontainer/"
printf '# Devcontainer reality fixture\n' >"$fixture_dir/README.md"
configure_vscode_cli_bridge
create_git_repo "$fixture_dir"
git -C "$fixture_dir" add .
git -C "$fixture_dir" commit -m "initial release fixture" >/dev/null

log "created devcontainer fixture at $fixture_dir from $release_dir"
expected_workspace_folder="$(expected_workspace_folder "$fixture_dir")"
expected_remote_workspace_folder="$(expected_remote_workspace_folder "$expected_workspace_folder")"
remote_workspace_folder="$expected_remote_workspace_folder"

if [ "${DEVCONTAINER_REALITY_TEST_SKIP_UP:-false}" != "true" ]; then
  log "starting devcontainer CLI from fixture root"
  devcontainer_log="$fixture_dir/devcontainer-up.log"
  prepare_devcontainer_home "$fixture_dir"
  HOME="$fixture_dir" devcontainer_cli up --remove-existing-container --workspace-folder "$fixture_dir" | tee "$devcontainer_log"

  remote_workspace_folder="$(extract_remote_workspace_folder_from_log "$devcontainer_log")"
  [ -n "$remote_workspace_folder" ] || fail "devcontainer CLI did not report a remote workspace folder"
  [ "$remote_workspace_folder" = "$expected_remote_workspace_folder" ] \
    || fail "devcontainer CLI reported $remote_workspace_folder, expected $expected_remote_workspace_folder"
  container_id="$(extract_container_id_from_log "$devcontainer_log")"
  [ -n "$container_id" ] || fail "devcontainer CLI did not report a container ID"

  devcontainer_cli exec \
    --workspace-folder "$fixture_dir" \
    --container-id "$container_id" \
    bash -c '
    set -eu
    test "$(pwd -P)" = "'"$expected_workspace_folder"'"
    test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$expected_workspace_folder"'"
    test "$(command -v oc)" = "/usr/local/bin/oc"
    git rev-parse --is-inside-work-tree >/dev/null
  '
fi

pass "verified staged runtime release in temporary consuming devcontainer: $fixture_dir"
if [ -n "$container_id" ]; then
  log "container ID: $container_id"
  log "opening Bash in workspace: $fixture_dir"
  devcontainer_cli exec \
    --workspace-folder "$fixture_dir" \
    --container-id "$container_id" \
    bash
fi
