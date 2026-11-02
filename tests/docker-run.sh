#!/usr/bin/env bash
# docker-run.sh - verify the Taskfile docker-run path works through a TTY
#
# The foreground probe waits for services inside the actual nested container;
# shell operators in Task's COMMAND value would otherwise run on the caller.
# Also exercise stale Docker PID/root-owned log cleanup before a single start.
#
# Related files:
# - ../Taskfile.yaml
# - ../entrypoint.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

local_suite=0
if [ -z "$suite_tmp_dir" ]; then
  setup_suite
  local_suite=1
fi
if [ "$local_suite" = 1 ]; then
  trap cleanup_suite EXIT
fi

probe_file="$suite_tmp_dir/docker-run-probe.sh"
cat >"$probe_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DEVCONTAINER_WORKSPACE_FOLDER/tests/helpers.sh"
wait_for_check "Docker" docker info
printf 'runtime_user=%s\nruntime_workspace=%s\n' "$(id -un)" "$PWD"
printf 'runtime_workspace_tmp=%s\n' "$DEVCONTAINER_WORKSPACE_TMP"
EOF

expected_user="${CONTAINER_USER:-${USER:-$(id -un)}}"
test_output="$(COMMAND="bash \"$probe_file\"" run_project_tty docker-run)"

[[ "$test_output" == *"runtime_user=$expected_user"* ]] || fail "docker-run did not execute as the container user"
[[ "$test_output" == *"runtime_workspace=$project_root"* ]] || fail "docker-run did not preserve the workspace path"
[[ "$test_output" == *"runtime_workspace_tmp=$project_root/.tmp"* ]] || fail "docker-run did not supply the workspace temporary path"

docker run --rm --privileged --user root --entrypoint bash \
  -e "DEVCONTAINER_WORKSPACE_FOLDER=$project_root" \
  -e "DEVCONTAINER_WORKSPACE_TMP=$project_root/.tmp" \
  -e "STARTUP_PROBE=$probe_file" \
  --mount "type=bind,src=$project_root,dst=$project_root" \
  -w "$project_root" \
  codegeist-devcontainer-kit:local -lc '
  set -euo pipefail

  install -o root -g root -m 0600 /dev/null /tmp/dockerd.log
  install -d -m 0755 /var/run/docker/containerd
  printf "%s\n" "$$" >/var/run/docker.pid
  printf "%s\n" "$$" >/var/run/docker/containerd/containerd.pid
  exec sudo -Eu "$CONTAINER_USER" /usr/local/bin/devcontainer-entrypoint bash "$STARTUP_PROBE"
'

pass "docker-run starts real workspace services and clears stale Docker state as the container user"
