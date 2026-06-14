#!/usr/bin/env bash
# opencode-mounts.sh - verify shared state mounts resolve and stay writable
#
# Why this exists:
# - docker-compose.yml bind-mounts host OpenCode directories and the shared
#   Chrome CDP profile into the devcontainer so tools can reuse local state.
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
container_group="$(id -gn)"
container_home="/home/$container_user"
host_uid="$(id -u)"
workspace_folder="$(expected_workspace_folder "$fixture_dir")"

config_dir="$suite_tmp_dir/opencode/config"
share_dir="$suite_tmp_dir/opencode/share"
state_dir="$suite_tmp_dir/opencode/state"
chrome_cdp_profile_dir="$suite_tmp_dir/chrome-cdp-profile"
compose_base_env=(
  HOME="$fixture_dir"
  UID="$host_uid"
  CONTAINER_USER="$container_user"
  CONTAINER_GROUP="$container_group"
  CONTAINER_UID="$host_uid"
  CONTAINER_GID="$host_uid"
  DEVCONTAINER_REPO_ROOT="$fixture_dir"
  DEVCONTAINER_WORKSPACE_FOLDER="$workspace_folder"
)

create_git_fixture_repo "$fixture_dir"
env -u CODEGEIST_CHROME_CDP_PROFILE_DIR HOME="$fixture_dir" "$fixture_dir/.devcontainer/initialize.sh"
prepare_devcontainer_home "$fixture_dir"
mkdir -p "$config_dir" "$share_dir" "$state_dir"
mkdir -p "$chrome_cdp_profile_dir"

printf 'host config write check\n' >"$config_dir/host-write-check.txt"
printf 'host share write check\n' >"$share_dir/host-write-check.txt"
printf 'host state write check\n' >"$state_dir/host-write-check.txt"
printf 'host chrome profile write check\n' >"$chrome_cdp_profile_dir/host-write-check.txt"

cleanup_compose() {
  if [ -d "$fixture_dir" ]; then
    (cd "$fixture_dir" && env "${compose_base_env[@]}" docker compose -p "$compose_project" -f ".devcontainer/docker-compose.yml" down -v --remove-orphans >/dev/null 2>&1) || true
  fi
}
trap cleanup_compose EXIT

default_config="$(cd "$fixture_dir" && env -u OPENCODE_DIR_CONFIG -u OPENCODE_DIR_SHARE -u OPENCODE_DIR_STATE "${compose_base_env[@]}" docker compose \
  -f ".devcontainer/docker-compose.yml" \
  config)"

[[ "$default_config" == *"source: /home/$container_user/.config/opencode"* ]] || fail "default OpenCode config source did not resolve to host home"
[[ "$default_config" == *"source: /home/$container_user/.local/share/opencode"* ]] || fail "default OpenCode share source did not resolve to host home"
[[ "$default_config" == *"source: /home/$container_user/.local/state/opencode"* ]] || fail "default OpenCode state source did not resolve to host home"
[[ "$default_config" == *"source: $fixture_dir/.config/codegeist-chrome-cdp"* ]] || fail "default Chrome CDP profile source did not resolve to host home"

compose_config="$(cd "$fixture_dir" && env "${compose_base_env[@]}" OPENCODE_DIR_CONFIG="$config_dir" OPENCODE_DIR_SHARE="$share_dir" OPENCODE_DIR_STATE="$state_dir" CODEGEIST_CHROME_CDP_PROFILE_DIR="$chrome_cdp_profile_dir" docker compose \
  -p "$compose_project" \
  -f ".devcontainer/docker-compose.yml" \
  config)"

[[ "$compose_config" == *"source: $config_dir"* ]] || fail "OpenCode config override did not resolve as source"
[[ "$compose_config" == *"source: $share_dir"* ]] || fail "OpenCode share override did not resolve as source"
[[ "$compose_config" == *"source: $state_dir"* ]] || fail "OpenCode state override did not resolve as source"
[[ "$compose_config" == *"source: $chrome_cdp_profile_dir"* ]] || fail "Chrome CDP profile override did not resolve as source"
[[ "$compose_config" == *"target: $container_home/.config/opencode"* ]] || fail "OpenCode config target changed unexpectedly"
[[ "$compose_config" == *"target: $container_home/.local/share/opencode"* ]] || fail "OpenCode share target changed unexpectedly"
[[ "$compose_config" == *"target: $container_home/.local/state/opencode"* ]] || fail "OpenCode state target changed unexpectedly"
[[ "$compose_config" == *"target: /mnt/codegeist/chrome-cdp-profile"* ]] || fail "Chrome CDP profile target changed unexpectedly"

(
  cd "$fixture_dir"
  env "${compose_base_env[@]}" \
    OPENCODE_DIR_CONFIG="$config_dir" \
    OPENCODE_DIR_SHARE="$share_dir" \
    OPENCODE_DIR_STATE="$state_dir" \
    CODEGEIST_CHROME_CDP_PROFILE_DIR="$chrome_cdp_profile_dir" \
    docker compose -p "$compose_project" -f ".devcontainer/docker-compose.yml" up -d workspace >/dev/null

  env "${compose_base_env[@]}" \
    OPENCODE_DIR_CONFIG="$config_dir" \
    OPENCODE_DIR_SHARE="$share_dir" \
    OPENCODE_DIR_STATE="$state_dir" \
    CODEGEIST_CHROME_CDP_PROFILE_DIR="$chrome_cdp_profile_dir" \
    docker compose -p "$compose_project" -f ".devcontainer/docker-compose.yml" exec -T workspace sh -lc "
      set -eu
      printf 'container config write check\n' >'$container_home/.config/opencode/container-write-check.txt'
      printf 'container share write check\n' >'$container_home/.local/share/opencode/container-write-check.txt'
      printf 'container state write check\n' >'$container_home/.local/state/opencode/container-write-check.txt'
      printf 'container chrome profile write check\n' >/mnt/codegeist/chrome-cdp-profile/container-write-check.txt
    "
)

[[ "$(<"$config_dir/container-write-check.txt")" = "container config write check" ]] || fail "container could not write OpenCode config mount"
[[ "$(<"$share_dir/container-write-check.txt")" = "container share write check" ]] || fail "container could not write OpenCode share mount"
[[ "$(<"$state_dir/container-write-check.txt")" = "container state write check" ]] || fail "container could not write OpenCode state mount"
[[ "$(<"$chrome_cdp_profile_dir/container-write-check.txt")" = "container chrome profile write check" ]] || fail "container could not write Chrome CDP profile mount"

pass "OpenCode and Chrome CDP host directories mount into the container and stay writable"
