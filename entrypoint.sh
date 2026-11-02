#!/usr/bin/env bash
# entrypoint.sh - launch workspace services once per container start.
#
# Docker's ENTRYPOINT is the sole caller; Compose supplies `sleep infinity`.
# Inputs: command argv, DEVCONTAINER_WORKSPACE_FOLDER, DEVCONTAINER_WORKSPACE_TMP,
# and CONTAINER_GROUP.
# Prepares the Chrome link, then launches Docker and the shared HTTP
# proxy asynchronously. The foreground command owns the container lifetime;
# service errors remain in their logs and do not trigger supervision or retries.
# Related: Dockerfile.base, devcontainer.json, cmds/oc,
# scripts/opencode-http-log.py, README.md#container-startup.

set -euo pipefail

printf 'level=info event=entrypoint status=starting\n' >&2
export PATH="$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/scripts:$PATH"
launcher="$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/scripts/chrome.sh"
proxy_dir="$DEVCONTAINER_WORKSPACE_TMP/opencode-http"

# Clear PID files from the previous boot, including Docker's managed containerd:
# a stale PID can already belong to another process in the new PID namespace.
sudo -n rm -f /var/run/docker.pid /var/run/docker/containerd/containerd.pid /tmp/dockerd.log
sudo -n ln -sf "$launcher" /usr/local/bin/chrome
sudo -n dockerd --group "$CONTAINER_GROUP" </dev/null >/tmp/dockerd.log 2>&1 &

install -d -m 0700 "$proxy_dir"
# Restrict proxy files without changing the foreground command's umask.
(
  umask 077
  exec env PYTHONDONTWRITEBYTECODE=1 mitmdump --quiet \
    --listen-host 127.0.0.1 --listen-port 18080 \
    --set "confdir=$proxy_dir" \
    --scripts /usr/local/lib/oc-http/opencode-http-log.py \
    </dev/null >"$proxy_dir/proxy.log" 2>&1
) &

if [ "$#" -eq 0 ]; then
  set -- bash
fi

printf 'level=info event=entrypoint status=handoff services=starting\n' >&2
exec "$@"
