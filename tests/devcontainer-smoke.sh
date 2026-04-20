#!/usr/bin/env bash
# devcontainer-smoke.sh - smoke-test the repo devcontainer with the devcontainer CLI
#
# Why this exists:
# - Verifies that the checked-in devcontainer configuration still resolves,
#   builds, and accepts commands after environment changes.
# - Lives under `tests/` so launcher checks and container smoke tests can stay
#   separated while sharing one suite directory.
# - Provides one repeatable check for Dockerfile, Compose, and devcontainer.json
#   regressions without going through VS Code.
#
# Inputs:
# - Optional first argument: workspace folder to test.
# - Otherwise defaults to the repository root that contains this `.devcontainer/`
#   directory.
#
# Related files:
# - ../devcontainer.json
# - ../docker-compose.yml
# - ../Dockerfile
# - ../../start.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
devcontainer_dir="$(dirname "$script_dir")"
workspace_folder="${1:-$(dirname "$devcontainer_dir")}"
local_env_path="$workspace_folder/.devcontainer/.local.env"
temp_local_env=0
start_time="$(date +%s)"
compose_project_name=""
container_id=""
devcontainer_log_level="${DEVCONTAINER_LOG_LEVEL:-info}"
heartbeat_interval="${SMOKE_HEARTBEAT_SECONDS:-30}"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

start_heartbeat() {
  local label="$1"
  local step_start="$2"

  while true; do
    sleep "$heartbeat_interval"
    log "$label still running (${heartbeat_interval}s heartbeat, elapsed $(( $(date +%s) - step_start ))s)"
  done
}

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
      -f "$workspace_folder/.devcontainer/compose.local.yml" \
      "$@"
}

start_devcontainer() {
  local up_log
  local parsed_ids=""
  local heartbeat_pid=""
  local up_status=0

  up_log="$(mktemp)"

  log "Running devcontainer up with log level '$devcontainer_log_level'"
  log "Workspace: $workspace_folder"
  log "Compose project: ${compose_project_name:-pending-from-start-sh}"

  start_heartbeat 'devcontainer up' "$start_time" &
  heartbeat_pid="$!"

  set +e
  run_devcontainer up --workspace-folder "$workspace_folder" --log-level "$devcontainer_log_level" 2>&1 | tee "$up_log"
  up_status="${PIPESTATUS[0]}"
  set -e

  kill "$heartbeat_pid" >/dev/null 2>&1 || true
  wait "$heartbeat_pid" 2>/dev/null || true

  if [ "$up_status" -ne 0 ]; then
    log "devcontainer up failed with exit code $up_status"
    rm -f "$up_log"
    return "$up_status"
  fi

  parsed_ids="$(python3 -c 'import json, sys
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
' < "$up_log")"

  container_id="$(printf '%s\n' "$parsed_ids" | python3 -c 'import sys; print(sys.stdin.read().splitlines()[0] if sys.stdin.readable() else "")')"
  compose_project_name="$(printf '%s\n' "$parsed_ids" | python3 -c 'import sys; lines = sys.stdin.read().splitlines(); print(lines[1] if len(lines) > 1 else "")')"
  rm -f "$up_log"

  if [ -z "$container_id" ]; then
    printf 'Could not determine containerId from devcontainer up output\n' >&2
    return 1
  fi

  log "devcontainer up completed with container $container_id"
  log "Compose project resolved to $compose_project_name"
}

run_timed_step() {
  local label="$1"
  shift
  local step_start="$(date +%s)"

  log "[start] $label"
  "$@"
  log "[done] $label ($(( $(date +%s) - step_start ))s)"
}

if [ ! -e "$local_env_path" ]; then
  temp_local_env=1
  log "Creating temporary $local_env_path for smoke test"
  printf '%s\n' \
    'GIT_AUTHOR_NAME=devcontainer-smoke-test' \
    'GIT_AUTHOR_EMAIL=devcontainer-smoke-test@example.com' \
    'GIT_COMMITTER_NAME=${GIT_AUTHOR_NAME}' \
    'GIT_COMMITTER_EMAIL=${GIT_AUTHOR_EMAIL}' \
    > "$local_env_path"
fi

if [ -x "$workspace_folder/start.sh" ]; then
  log "Loading runtime variables from $workspace_folder/start.sh"
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
  log "Cleaning up compose project ${compose_project_name:-unknown}"
  run_compose down >/dev/null 2>&1 || true

  if [ "$temp_local_env" = "1" ]; then
    log "Removing temporary $local_env_path"
    rm -f "$local_env_path"
  fi
}

trap cleanup EXIT

log "Testing devcontainer in $workspace_folder"
log "Using devcontainer log level $devcontainer_log_level"

run_timed_step 'read configuration' \
  run_devcontainer read-configuration --workspace-folder "$workspace_folder" >/dev/null
run_timed_step 'start devcontainer' \
  start_devcontainer
run_timed_step 'exec smoke command' \
  docker exec "$container_id" bash -lc 'printf "devcontainer ok\n"'
run_timed_step 'check nix' \
  docker exec "$container_id" bash -lc 'nix --version'
run_timed_step 'check hugo' \
  docker exec "$container_id" bash -lc 'hugo version'
run_timed_step 'check lftp' \
  docker exec "$container_id" bash -lc 'lftp --version >/dev/null'
run_timed_step 'check graphify' \
  docker exec "$container_id" bash -lc 'python3 -c "import graphify"'

printf 'Total: %ss\n' "$(( $(date +%s) - start_time ))"
