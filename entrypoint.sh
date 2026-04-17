#!/usr/bin/env bash
# entrypoint.sh - start dockerd for the devcontainer, then run the requested command.
#
# Why this exists:
# - The devcontainer needs Docker tooling available inside the workspace.
# - This product subtree keeps the same no-tmux Docker startup behavior as the planner.
#
# Inputs:
# - The requested container command from docker-compose or the devcontainer tool.
# - CONTAINER_GROUP controls the dockerd socket group.
#
# Related files:
# - .devcontainer/Dockerfile
# - .devcontainer/docker-compose.yml
# - .devcontainer/devcontainer.json

set -euo pipefail

dockerd_log_file="/tmp/dockerd.log"
dockerd_pid_file="/var/run/docker.pid"

clear_stale_docker_pid() {
  local existing_pid=""
  local existing_command=""

  if [ ! -f "$dockerd_pid_file" ]; then
    return 0
  fi

  existing_pid="$(cat "$dockerd_pid_file" 2>/dev/null || true)"

  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    existing_command="$(ps -p "$existing_pid" -o comm= 2>/dev/null || true)"

    if [ "$existing_command" = "dockerd" ]; then
      return 0
    fi
  fi

  rm -f "$dockerd_pid_file"
}

ensure_docker_daemon() {
  local attempt=""

  if docker ps >/dev/null 2>&1; then
    return 0
  fi

  clear_stale_docker_pid

  nohup sudo -n dockerd \
    --group "${CONTAINER_GROUP:-docker}" \
    --storage-driver=vfs \
    >"$dockerd_log_file" 2>&1 &

  for attempt in $(seq 1 30); do
    if docker ps >/dev/null 2>&1; then
      return 0
    fi

    sleep 1
  done

  printf 'dockerd did not become ready\n' >&2

  if [ -f "$dockerd_log_file" ]; then
    tail -n 50 "$dockerd_log_file" >&2 || true
  fi

  return 1
}

ensure_docker_daemon

if [ "$#" -eq 0 ]; then
  set -- bash
fi

exec "$@"
