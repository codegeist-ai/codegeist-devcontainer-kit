#!/usr/bin/env bash
# compose-config.sh - verify compose config resolves through Dev Containers CLI
#
# Why this exists:
# - proves generated runtime user and KVM settings reach the real container
# - verifies a host Wayland socket is mounted at the generated container path
# - verifies Xauthority is read from reconnect-refreshable workspace state
#
# Related files:
# - ../docker-compose.yml
# - ../compose.local.yml.example
# - ../initialize.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

fixture_dir="$suite_tmp_dir/compose-config-repo"
container_id=""
log_file="$suite_tmp_dir/compose-config-devcontainer.log"
kvm_gid="$(stat -c %g /dev/kvm 2>/dev/null || printf '993')"
wayland_runtime_dir="$suite_tmp_dir/w"
wayland_display="w"
wayland_socket="$wayland_runtime_dir/$wayland_display"
wayland_pid=""
create_git_fixture_repo "$fixture_dir"
prepare_devcontainer_home "$fixture_dir"

cleanup_devcontainer() {
  if [ -n "$wayland_pid" ]; then
    kill "$wayland_pid" >/dev/null 2>&1 || true
    wait "$wayland_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$wayland_runtime_dir"
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

mkdir -m 700 "$wayland_runtime_dir"
socat "UNIX-LISTEN:$wayland_socket,fork" EXEC:/bin/true >/dev/null 2>&1 &
wayland_pid="$!"
for _ in $(seq 1 50); do
  [ ! -S "$wayland_socket" ] || break
  sleep 0.1
done
[[ -S "$wayland_socket" ]] || fail "test Wayland socket was not created"

DISPLAY=localhost:43.0 \
  WAYLAND_DISPLAY="$wayland_display" \
  XDG_RUNTIME_DIR="$wayland_runtime_dir" \
  HOME="$fixture_dir" \
  devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"

[[ ! -e "$fixture_dir/.codegeist/compose.local.yml" ]] || fail "initializeCommand created .codegeist/compose.local.yml without an on-demand override"
[[ -f "$fixture_dir/.devcontainer/compose.user.gen.yml" ]] || fail "initializeCommand did not create .devcontainer/compose.user.gen.yml"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_KVM_GID=$kvm_gid"* ]] || fail "initializeCommand did not write KVM GID"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_DISPLAY=localhost:43.0"* ]] || fail "initializeCommand did not write DISPLAY"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_XAUTHORITY=$fixture_dir/.devcontainer/.Xauthority.gen"* ]] || fail "initializeCommand did not write workspace Xauthority"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_WAYLAND_SOCKET_HOST=$wayland_socket"* ]] || fail "initializeCommand did not write Wayland socket"

container_config="$(docker inspect "$container_id")"
[[ "$container_config" == *'"PathOnHost": "/dev/kvm"'* ]] || fail "workspace container did not mount /dev/kvm"
[[ "$container_config" == *'"PathInContainer": "/dev/kvm"'* ]] || fail "workspace container did not expose /dev/kvm"
[[ "$container_config" == *'"GroupAdd": ['* ]] || fail "workspace container did not include supplemental groups"
[[ "$container_config" == *'"'"$kvm_gid"'"'* ]] || fail "workspace container did not add KVM group"
[[ "$container_config" == *'"DISPLAY=localhost:43.0"'* ]] || fail "workspace container did not use generated DISPLAY"
[[ "$container_config" == *'"XAUTHORITY='"$fixture_dir"'/.devcontainer/.Xauthority.gen"'* ]] || fail "workspace container did not use generated Xauthority"
[[ "$container_config" == *'"WAYLAND_DISPLAY='"$wayland_display"'"'* ]] || fail "workspace container did not use generated Wayland display"
[[ "$container_config" == *'"XDG_RUNTIME_DIR=/tmp/codegeist-wayland"'* ]] || fail "workspace container did not use generated Wayland runtime"
[[ "$container_config" == *'"Source": "'"$wayland_socket"'"'* ]] || fail "workspace container did not mount host Wayland socket"
[[ "$container_config" == *'"Destination": "/tmp/codegeist-wayland/'"$wayland_display"'"'* ]] || fail "workspace container did not expose Wayland socket at generated target"
docker exec "$container_id" test -S "/tmp/codegeist-wayland/$wayland_display" \
  || fail "workspace container Wayland target is not a Unix socket"

pass "compose config mounts generated Wayland and reconnect-safe Xauthority state"
