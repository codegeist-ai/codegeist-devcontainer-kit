#!/usr/bin/env bash
# compose-config.sh - verify generated Compose state in a real devcontainer
#
# Why this exists:
# - proves runtime user, KVM, workspace, and Git metadata mounts reach Docker
# - verifies derived SSH server IPv4 and reconnect-refreshable Xauthority handoff
# - protects checkout-local Bitwarden state and optional Compose behavior
# - checks Buildx filesystem entitlement defaults, overrides, and runtime delivery
#
# Related files:
# - ../docker-compose.yml
# - ../initialize.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

unset SSH_CONNECTION

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
expected_buildx_fs="${BUILDX_BAKE_ENTITLEMENTS_FS:-0}"

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
# Resolve the prepared colon-path fixture without inheriting the caller's
# checkout metadata. Optional arguments are forwarded to `docker compose config`.
resolve_colon_compose_config() (
  cd "$colon_fixture_dir/.devcontainer"
  env \
    -u DEVCONTAINER_HOST_NAME \
    -u DEVCONTAINER_REPO_NAME \
    -u DEVCONTAINER_REPO_ROOT \
    -u DEVCONTAINER_GIT_COMMON_DIR \
    -u DEVCONTAINER_BRANCH_NAME \
    -u DEVCONTAINER_HOSTNAME \
    -u DEVCONTAINER_WORKSPACE_FOLDER \
    -u DEVCONTAINER_USER \
    -u DEVCONTAINER_GROUP \
    -u DEVCONTAINER_UID \
    -u DEVCONTAINER_GID \
    -u DEVCONTAINER_KVM_GID \
    -u DEVCONTAINER_DISPLAY \
    -u DEVCONTAINER_XAUTHORITY \
    docker compose \
    -f docker-compose.yml \
    -f compose.local.gen.yml \
    -f compose.user.gen.yml \
    config "$@"
)

colon_compose_config="$(
  unset BUILDX_BAKE_ENTITLEMENTS_FS
  resolve_colon_compose_config
)"
if [[ "$colon_compose_config" == *"network_mode: host"* ]]; then
  fail "default Compose configuration must not select host networking"
fi
grep -F "source: $colon_fixture_dir" <<<"$colon_compose_config" >/dev/null \
  || fail "Compose did not preserve the checkout path containing a colon"
grep -F "source: $colon_common_dir" <<<"$colon_compose_config" >/dev/null \
  || fail "Compose did not preserve the Git common path containing a colon"

log "checking Buildx filesystem entitlement default and host override"
grep -F 'BUILDX_BAKE_ENTITLEMENTS_FS: "0"' <<<"$colon_compose_config" >/dev/null \
  || fail "Compose must default BUILDX_BAKE_ENTITLEMENTS_FS to 0 when unset"
for buildx_input in "" "1"; do
  resolved_buildx_fs="$(
    BUILDX_BAKE_ENTITLEMENTS_FS="$buildx_input" \
      resolve_colon_compose_config --format json \
      | jq -r '.services.workspace.environment.BUILDX_BAKE_ENTITLEMENTS_FS'
  )"
  [[ "$resolved_buildx_fs" = "${buildx_input:-0}" ]] \
    || fail "BUILDX_BAKE_ENTITLEMENTS_FS expected=${buildx_input:-0} actual=$resolved_buildx_fs"
done

DISPLAY=ssh-host:43.2 SSH_CONNECTION='192.0.2.10 50000 10.77.0.5 22' HOME="$fixture_dir" \
  devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"

[[ ! -e "$fixture_dir/.codegeist/compose.local.yml" ]] \
  || fail "initializeCommand created an optional Compose override"
grep -Fx "DEVCONTAINER_KVM_GID=$kvm_gid" "$fixture_dir/.devcontainer/.env" >/dev/null \
  || fail "initializeCommand did not write KVM GID"
grep -Fx "DEVCONTAINER_DISPLAY=10.77.0.5:43.2" "$fixture_dir/.devcontainer/.env" >/dev/null \
  || fail "initializeCommand did not derive DISPLAY from the SSH server address"
grep -Fx "DEVCONTAINER_GIT_COMMON_DIR=$expected_common_dir" "$fixture_dir/.devcontainer/.env" >/dev/null \
  || fail "initializeCommand did not write the Git common directory"
if grep -q 'WAYLAND' "$fixture_dir/.devcontainer/.env" "$fixture_dir/.devcontainer/compose.local.gen.yml"; then
  fail "generated runtime state retained Wayland configuration"
fi

container_config="$(docker inspect "$container_id")"
[[ "$container_config" == *'"PathOnHost": "/dev/kvm"'* ]] || fail "workspace container did not mount /dev/kvm"
[[ "$container_config" == *'"'"$kvm_gid"'"'* ]] || fail "workspace container did not add KVM group"
[[ "$container_config" == *'"DISPLAY=10.77.0.5:43.2"'* ]] || fail "workspace container did not use derived DISPLAY"
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

actual_buildx_fs="$(docker exec -u "$(expected_container_user)" "$container_id" \
  printenv BUILDX_BAKE_ENTITLEMENTS_FS)"
[[ "$actual_buildx_fs" = "$expected_buildx_fs" ]] \
  || fail "workspace BUILDX_BAKE_ENTITLEMENTS_FS expected=$expected_buildx_fs actual=$actual_buildx_fs"

pass "Compose exposes checkout, Git metadata, KVM, Remote SSH X11, and overridable Buildx state"
