#!/usr/bin/env bash
# opencode-mounts.sh - verify OpenCode state mounts resolve and stay writable
#
# Why this exists:
# - docker-compose.yml bind-mounts host OpenCode config, share, and state
#   directories into the devcontainer so OpenCode can reuse local state.
# - The test checks both Compose interpolation and real container writeability.
#
# Related files:
# - ../docker-compose.yml
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  trap cleanup_suite EXIT
fi

fixture_dir="$suite_tmp_dir/opencode-mounts-fixture"
compose_project="opencode-mounts-$$"
container_user="$(expected_container_user)"
container_home="/home/$container_user"
host_uid="$(id -u)"
workspace_folder="$(expected_workspace_folder "$fixture_dir")"

config_dir="$suite_tmp_dir/opencode/config"
share_dir="$suite_tmp_dir/opencode/share"
state_dir="$suite_tmp_dir/opencode/state"

create_fixture_repo "$fixture_dir"
mkdir -p "$config_dir" "$share_dir" "$state_dir"

printf 'host config write check\n' >"$config_dir/host-write-check.txt"
printf 'host share write check\n' >"$share_dir/host-write-check.txt"
printf 'host state write check\n' >"$state_dir/host-write-check.txt"

cleanup_compose() {
  if [ -d "$fixture_dir" ]; then
    (cd "$fixture_dir" && env UID="$host_uid" DEVCONTAINER_REPO_ROOT="$fixture_dir" DEVCONTAINER_WORKSPACE_FOLDER="$workspace_folder" docker compose -p "$compose_project" -f ".devcontainer/docker-compose.yml" down -v --remove-orphans >/dev/null 2>&1) || true
  fi
}
trap cleanup_compose EXIT

default_config="$(cd "$fixture_dir" && env -u OPENCODE_DIR_CONFIG -u OPENCODE_DIR_SHARE -u OPENCODE_DIR_STATE UID="$host_uid" DEVCONTAINER_REPO_ROOT="$fixture_dir" DEVCONTAINER_WORKSPACE_FOLDER="$workspace_folder" docker compose \
  -f ".devcontainer/docker-compose.yml" \
  config)"

[[ "$default_config" == *"source: /home/$container_user/.config/opencode"* ]] || fail "default OpenCode config source did not resolve to host home"
[[ "$default_config" == *"source: /home/$container_user/.local/share/opencode"* ]] || fail "default OpenCode share source did not resolve to host home"
[[ "$default_config" == *"source: /home/$container_user/.local/state/opencode"* ]] || fail "default OpenCode state source did not resolve to host home"

compose_config="$(cd "$fixture_dir" && OPENCODE_DIR_CONFIG="$config_dir" OPENCODE_DIR_SHARE="$share_dir" OPENCODE_DIR_STATE="$state_dir" env UID="$host_uid" DEVCONTAINER_REPO_ROOT="$fixture_dir" DEVCONTAINER_WORKSPACE_FOLDER="$workspace_folder" docker compose \
  -p "$compose_project" \
  -f ".devcontainer/docker-compose.yml" \
  config)"

[[ "$compose_config" == *"source: $config_dir"* ]] || fail "OpenCode config override did not resolve as source"
[[ "$compose_config" == *"source: $share_dir"* ]] || fail "OpenCode share override did not resolve as source"
[[ "$compose_config" == *"source: $state_dir"* ]] || fail "OpenCode state override did not resolve as source"
[[ "$compose_config" == *"target: $container_home/.config/opencode"* ]] || fail "OpenCode config target changed unexpectedly"
[[ "$compose_config" == *"target: $container_home/.local/share/opencode"* ]] || fail "OpenCode share target changed unexpectedly"
[[ "$compose_config" == *"target: $container_home/.local/state/opencode"* ]] || fail "OpenCode state target changed unexpectedly"

(
  cd "$fixture_dir"
  OPENCODE_DIR_CONFIG="$config_dir" \
    OPENCODE_DIR_SHARE="$share_dir" \
    OPENCODE_DIR_STATE="$state_dir" \
    env UID="$host_uid" \
      DEVCONTAINER_REPO_ROOT="$fixture_dir" \
      DEVCONTAINER_WORKSPACE_FOLDER="$workspace_folder" \
    docker compose -p "$compose_project" -f ".devcontainer/docker-compose.yml" up -d workspace >/dev/null

  OPENCODE_DIR_CONFIG="$config_dir" \
    OPENCODE_DIR_SHARE="$share_dir" \
    OPENCODE_DIR_STATE="$state_dir" \
    env UID="$host_uid" \
      DEVCONTAINER_REPO_ROOT="$fixture_dir" \
      DEVCONTAINER_WORKSPACE_FOLDER="$workspace_folder" \
    docker compose -p "$compose_project" -f ".devcontainer/docker-compose.yml" exec -T workspace sh -lc "
      set -eu
      printf 'container config write check\n' >'$container_home/.config/opencode/container-write-check.txt'
      printf 'container share write check\n' >'$container_home/.local/share/opencode/container-write-check.txt'
      printf 'container state write check\n' >'$container_home/.local/state/opencode/container-write-check.txt'
    "
)

[[ "$(<"$config_dir/container-write-check.txt")" = "container config write check" ]] || fail "container could not write OpenCode config mount"
[[ "$(<"$share_dir/container-write-check.txt")" = "container share write check" ]] || fail "container could not write OpenCode share mount"
[[ "$(<"$state_dir/container-write-check.txt")" = "container state write check" ]] || fail "container could not write OpenCode state mount"

pass "OpenCode host directories mount into the container and stay writable"
