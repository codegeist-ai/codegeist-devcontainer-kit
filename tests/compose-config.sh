#!/usr/bin/env bash
# compose-config.sh - verify generated Compose state in a real devcontainer
#
# Why this exists:
# - proves runtime user, KVM, workspace, and Git metadata mounts reach Docker
# - verifies Remote SSH X11 state uses the reconnect-refreshable workspace copy
# - protects checkout-local Bitwarden state and optional Compose behavior
#
# Related files:
# - ../docker-compose.yml
# - ../initialize.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

local_suite=0
if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  local_suite=1
fi

fixture_dir="$suite_tmp_dir/compose-config-repo"
colon_fixture_dir="$suite_tmp_dir/compose:path-repo"
container_id=""
log_file="$suite_tmp_dir/compose-config-devcontainer.log"
kvm_gid="$(stat -c %g /dev/kvm 2>/dev/null || printf '993')"
expected_bitwarden_appdata="$fixture_dir/.codegeist/secrets/bitwarden-cli"
expected_common_dir=""

cleanup_devcontainer() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
  if [ "$local_suite" -eq 1 ]; then
    cleanup_suite
  fi
}
trap cleanup_devcontainer EXIT

create_git_fixture_repo "$fixture_dir"
prepare_devcontainer_home "$fixture_dir"
expected_common_dir="$(expected_git_common_dir "$fixture_dir")"

log "checking long-form checkout mounts with a colon in the host path"
create_git_fixture_repo "$colon_fixture_dir"
HOME="$colon_fixture_dir" "$colon_fixture_dir/.devcontainer/initialize.sh"
colon_common_dir="$(expected_git_common_dir "$colon_fixture_dir")"
colon_compose_config="$(
  cd "$colon_fixture_dir/.devcontainer"
  docker compose \
    -f docker-compose.yml \
    -f compose.local.gen.yml \
    -f compose.user.gen.yml \
    config
)"
grep -F "source: $colon_fixture_dir" <<<"$colon_compose_config" >/dev/null \
  || fail "Compose did not preserve the checkout path containing a colon"
grep -F "source: $colon_common_dir" <<<"$colon_compose_config" >/dev/null \
  || fail "Compose did not preserve the Git common path containing a colon"

DISPLAY=localhost:43.0 HOME="$fixture_dir" \
  devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"

[[ ! -e "$fixture_dir/.codegeist/compose.local.yml" ]] \
  || fail "initializeCommand created an optional Compose override"
grep -Fx "DEVCONTAINER_KVM_GID=$kvm_gid" "$fixture_dir/.devcontainer/.env" >/dev/null \
  || fail "initializeCommand did not write KVM GID"
grep -Fx "DEVCONTAINER_DISPLAY=localhost:43.0" "$fixture_dir/.devcontainer/.env" >/dev/null \
  || fail "initializeCommand did not write DISPLAY"
grep -Fx "DEVCONTAINER_GIT_COMMON_DIR=$expected_common_dir" "$fixture_dir/.devcontainer/.env" >/dev/null \
  || fail "initializeCommand did not write the Git common directory"
if grep -q 'WAYLAND' "$fixture_dir/.devcontainer/.env" "$fixture_dir/.devcontainer/compose.local.gen.yml"; then
  fail "generated runtime state retained Wayland configuration"
fi

container_config="$(docker inspect "$container_id")"
[[ "$container_config" == *'"PathOnHost": "/dev/kvm"'* ]] || fail "workspace container did not mount /dev/kvm"
[[ "$container_config" == *'"'"$kvm_gid"'"'* ]] || fail "workspace container did not add KVM group"
[[ "$container_config" == *'"DISPLAY=localhost:43.0"'* ]] || fail "workspace container did not use generated DISPLAY"
[[ "$container_config" == *'"BITWARDENCLI_APPDATA_DIR='"$expected_bitwarden_appdata"'"'* ]] \
  || fail "workspace container did not use checkout-local Bitwarden state"
[[ "$container_config" == *'"XAUTHORITY='"$fixture_dir"'/.devcontainer/.Xauthority.gen"'* ]] \
  || fail "workspace container did not use generated Xauthority"
[[ "$container_config" == *'"Source": "'"$fixture_dir"'"'* ]] \
  || fail "workspace checkout was not mounted at its host path"
[[ "$container_config" == *'"Source": "'"$expected_common_dir"'"'* ]] \
  || fail "Git common metadata was not mounted at its host path"

docker exec -u "$(expected_container_user)" -w "$fixture_dir" "$container_id" \
  git status --short >/dev/null \
  || fail "Git metadata is not usable from the workspace container"

pass "Compose exposes checkout, Git metadata, KVM, and Remote SSH X11 state"
