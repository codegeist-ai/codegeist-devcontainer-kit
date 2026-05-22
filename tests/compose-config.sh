#!/usr/bin/env bash
# compose-config.sh - verify compose config resolves through Dev Containers CLI
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
create_git_fixture_repo "$fixture_dir"
prepare_devcontainer_home "$fixture_dir"

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

HOME="$fixture_dir" devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"

[[ -f "$fixture_dir/compose.local.yml" ]] || fail "initializeCommand did not create root compose.local.yml"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_KVM_GID=$kvm_gid"* ]] || fail "initializeCommand did not write KVM GID"

container_config="$(docker inspect "$container_id")"
[[ "$container_config" == *'"PathOnHost": "/dev/kvm"'* ]] || fail "workspace container did not mount /dev/kvm"
[[ "$container_config" == *'"PathInContainer": "/dev/kvm"'* ]] || fail "workspace container did not expose /dev/kvm"
[[ "$container_config" == *'"GroupAdd": ['* ]] || fail "workspace container did not include supplemental groups"
[[ "$container_config" == *'"'"$kvm_gid"'"'* ]] || fail "workspace container did not add KVM group"

pass "compose config resolves through Dev Containers CLI with generated local overlay"
