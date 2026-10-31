#!/usr/bin/env bash
# entrypoint.sh - start container services, then run the requested command
#
# Why this exists:
# - The devcontainer needs Docker tooling available inside the workspace.
# - Visible Chrome expects a system DBus socket even when browser traffic and UI
#   rendering are otherwise handled directly inside the container.
# - The `chrome` command points at the mounted workspace launcher so changes to
#   `.devcontainer/scripts/chrome.sh` do not require an image rebuild.
# - The Dockerfile sets USER to the workspace user, so dockerd is started through
#   passwordless sudo configured during image build.
# - One mitmdump on 127.0.0.1:18080 serves every oc pane in this container.
#   CA state lives in workspace .tmp/opencode-http; only oc sets proxy variables.
#
# Inputs:
# - The requested container command from Docker, Compose, or Dev Containers CLI.
# - CONTAINER_GROUP controls the dockerd socket group.
# - DEVCONTAINER_WORKSPACE_FOLDER selects disposable proxy state and HTTP logs.
#
# Related files:
# - Dockerfile.base
# - Taskfile.yaml
# - devcontainer.json (postStartCommand also invokes this entrypoint)
# - cmds/oc, scripts/opencode-http-log.py, README.md#opencode-http-logging

set -euo pipefail

dockerd_log_file="/tmp/dockerd.log"
dockerd_pid_file="/var/run/docker.pid"
dbus_socket_file="/run/dbus/system_bus_socket"

ensure_chrome_launcher() {
  local launcher=""

  [ -n "${DEVCONTAINER_WORKSPACE_FOLDER:-}" ] || return 0
  launcher="$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/scripts/chrome.sh"
  [ -f "$launcher" ] || return 0

  chmod +x "$launcher"
  sudo -n ln -sf "$launcher" /usr/local/bin/chrome
}

prepend_workspace_scripts_path() {
  export PATH="$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/scripts:$PATH"
}

ensure_system_dbus() {
  if [ -S "$dbus_socket_file" ]; then
    return 0
  fi

  if ! command -v dbus-daemon >/dev/null 2>&1; then
    return 0
  fi

  sudo -n install -d -m 0755 /run/dbus
  sudo -n dbus-daemon --system --fork --nopidfile || true
}

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

  sudo -n rm -f "$dockerd_pid_file"
}

ensure_docker_daemon() {
  local attempt=""

  if docker ps >/dev/null 2>&1; then
    return 0
  fi

  clear_stale_docker_pid

  sudo -n rm -f "$dockerd_log_file"

  sudo -n env CONTAINER_GROUP="${CONTAINER_GROUP:-docker}" \
    DOCKERD_LOG_FILE="$dockerd_log_file" \
    bash -c '
      # Let Docker choose the storage driver so nested Docker can use overlay2
      # when available. Forcing vfs duplicates layers and exhausts disk quickly.
      nohup dockerd \
        --group "$CONTAINER_GROUP" \
        >"$DOCKERD_LOG_FILE" 2>&1 &
    '

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

# The image entrypoint and Dev Containers postStartCommand can overlap. Serialize
# just this startup and reuse a ready proxy; the daemon does not inherit the lock.
start_opencode_proxy() (
  umask 077
  proxy_dir="$DEVCONTAINER_WORKSPACE_FOLDER/.tmp/opencode-http"
  install -d -m 0700 "$proxy_dir"
  exec 9>"$proxy_dir/start.lock"
  flock 9
  if [ -s "$proxy_dir/mitmproxy-ca-cert.pem" ] && nc -z 127.0.0.1 18080; then
    printf 'level=info event=oc_http status=reused proxy=http://127.0.0.1:18080\n' >&2
    return 0
  fi
  printf 'level=info event=oc_http status=starting proxy=http://127.0.0.1:18080\n' >&2
  PYTHONDONTWRITEBYTECODE=1 mitmdump --quiet \
    --listen-host 127.0.0.1 --listen-port 18080 \
    --set "confdir=$proxy_dir" \
    --scripts /usr/local/lib/oc-http/opencode-http-log.py \
    </dev/null >"$proxy_dir/proxy.log" 2>&1 9>&- &
  proxy_pid="$!"
  for _ in {1..100}; do
    kill -0 "$proxy_pid" 2>/dev/null || break
    if [ -s "$proxy_dir/mitmproxy-ca-cert.pem" ] && nc -z 127.0.0.1 18080; then
      printf 'level=info event=oc_http status=ready proxy=http://127.0.0.1:18080\n' >&2
      return 0
    fi
    sleep 0.1
  done
  printf 'level=error event=oc_http status=failed log=%s/proxy.log\n' "$proxy_dir" >&2
  return 1
)

ensure_system_dbus
prepend_workspace_scripts_path
ensure_chrome_launcher
ensure_docker_daemon
start_opencode_proxy

if [ "$#" -eq 0 ]; then
  set -- bash
fi

exec "$@"
