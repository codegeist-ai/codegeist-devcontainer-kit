#!/usr/bin/env bash
# tests.sh - smoke-test the repo devcontainer with the devcontainer CLI
#
# Why this exists:
# - Verifies that the checked-in devcontainer configuration still resolves,
#   builds, and accepts commands after environment changes.
# - Lives inside `.devcontainer/` so that directory can later move into its own
#   repository without losing its self-test entrypoint.
# - Provides one repeatable check for Dockerfile, Compose, and devcontainer.json
#   regressions without going through VS Code.
#
# Inputs:
# - Optional first argument: workspace folder to test.
# - Otherwise defaults to the repository root that contains this `.devcontainer/`
#   directory.
#
# Related files:
# - .devcontainer/devcontainer.json
# - .devcontainer/docker-compose.yml
# - .devcontainer/Dockerfile
# - ../start.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
workspace_folder="${1:-$(dirname "$script_dir")}"
local_env_path="$workspace_folder/.devcontainer/.local.env"
temp_local_env=0
start_time="$(date +%s)"
compose_project_name=""
container_id=""

if command -v devcontainer >/dev/null 2>&1; then
  devcontainer_cmd=(devcontainer)
else
  devcontainer_cmd=(npx --yes @devcontainers/cli)
fi

run_devcontainer() {
  env UID="$(id -u)" GID="$(id -g)" "${devcontainer_cmd[@]}" "$@"
}

run_compose() {
  env \
    UID="$(id -u)" \
    GID="$(id -g)" \
    CODEGEIST_REPO_ROOT="$CODEGEIST_REPO_ROOT" \
    CODEGEIST_REPO_WORKTREE="$CODEGEIST_REPO_WORKTREE" \
    COMPOSE_PROJECT_NAME="$compose_project_name" \
    PROJECT_NAME="$PROJECT_NAME" \
    CODEGEIST_HOSTNAME="$CODEGEIST_HOSTNAME" \
    docker compose \
      --project-name "$compose_project_name" \
      -f "$workspace_folder/.devcontainer/docker-compose.yml" \
      "$@"
}

start_devcontainer() {
  local up_output=""
  local parsed_ids=""

  up_output="$(run_devcontainer up --workspace-folder "$workspace_folder" --log-level info 2>&1)"
  printf '%s\n' "$up_output"

  parsed_ids="$(printf '%s\n' "$up_output" | python3 -c 'import json, sys
container_id = ""
compose_name = ""
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        continue
    container_id = payload.get("containerId", container_id)
    compose_name = payload.get("composeProjectName", compose_name)
print(container_id)
print(compose_name)
')"

  container_id="$(printf '%s\n' "$parsed_ids" | python3 -c 'import sys; print(sys.stdin.read().splitlines()[0] if sys.stdin.readable() else "")')"
  compose_project_name="$(printf '%s\n' "$parsed_ids" | python3 -c 'import sys; lines = sys.stdin.read().splitlines(); print(lines[1] if len(lines) > 1 else "")')"

  if [ -z "$container_id" ]; then
    printf 'Could not determine containerId from devcontainer up output\n' >&2
    return 1
  fi
}

run_timed_step() {
  local label="$1"
  shift
  local step_start="$(date +%s)"

  printf '[start] %s\n' "$label"
  "$@"
  printf '[done] %s (%ss)\n' "$label" "$(( $(date +%s) - step_start ))"
}

if [ ! -e "$local_env_path" ]; then
  temp_local_env=1
  printf '%s\n' \
    'GIT_AUTHOR_NAME=devcontainer-smoke-test' \
    'GIT_AUTHOR_EMAIL=devcontainer-smoke-test@example.com' \
    'GIT_COMMITTER_NAME=${GIT_AUTHOR_NAME}' \
    'GIT_COMMITTER_EMAIL=${GIT_AUTHOR_EMAIL}' \
    > "$local_env_path"
fi

if [ -x "$workspace_folder/start.sh" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      CODEGEIST_REPO_ROOT|CODEGEIST_REPO_WORKTREE|COMPOSE_PROJECT_NAME|PROJECT_NAME|CODEGEIST_HOSTNAME)
        export "$key=$value"
        ;;
    esac
  done < <(W_NO_OPEN=1 "$workspace_folder/start.sh")
fi

compose_project_name="${COMPOSE_PROJECT_NAME:-$(basename "$workspace_folder") }"

cleanup() {
  run_compose down >/dev/null 2>&1 || true

  if [ "$temp_local_env" = "1" ]; then
    rm -f "$local_env_path"
  fi
}

trap cleanup EXIT

printf 'Testing devcontainer in %s\n' "$workspace_folder"

run_timed_step 'read configuration' \
  run_devcontainer read-configuration --workspace-folder "$workspace_folder" >/dev/null
run_timed_step 'start devcontainer' \
  start_devcontainer
run_timed_step 'exec smoke command' \
  docker exec "$container_id" bash -lc 'printf "devcontainer ok\n"'
run_timed_step 'check nix' \
  docker exec "$container_id" bash -lc 'nix --version'

printf 'Total: %ss\n' "$(( $(date +%s) - start_time ))"
