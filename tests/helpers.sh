#!/usr/bin/env bash
# helpers.sh - shared helpers for the generic devcontainer kit tests
#
# Why this exists:
# - keeps timing, TTY execution, and fixture setup consistent across tests
# - lets each test script focus on one observable contract
#
# Inputs:
# - WARN_*_SECONDS configure warning thresholds for long-running checks.
# - DEVCONTAINER_PROJECT_ROOT can override the project root under test.
#
# Related files:
# - ../Taskfile.yaml
# - ./run.sh

set -euo pipefail

helpers_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
project_root="${DEVCONTAINER_PROJECT_ROOT:-$(dirname "$helpers_dir")}" 
suite_tmp_dir="${suite_tmp_dir:-}"
suite_start_epoch="${suite_start_epoch:-}"

log() {
  printf '[%(%Y-%m-%dT%H:%M:%S%z)T] %s\n' -1 "$*"
}

pass() {
  log "PASS: $*"
}

warn() {
  log "WARN: $*" >&2
}

fail() {
  log "FAIL: $*" >&2
  exit 1
}

setup_suite() {
  suite_tmp_dir="$(mktemp -d)"
  suite_start_epoch="$(date +%s)"
  export suite_tmp_dir suite_start_epoch
}

cleanup_suite() {
  if [ -n "${suite_tmp_dir:-}" ] && [ -d "$suite_tmp_dir" ]; then
    rm -rf "$suite_tmp_dir"
  fi
}

elapsed_seconds() {
  local start_epoch="$1"
  local end_epoch=""

  end_epoch="$(date +%s)"
  printf '%s' "$((end_epoch - start_epoch))"
}

run_timed() {
  local label="$1"
  local warn_after_seconds="$2"
  shift 2

  local started_at=""
  local duration=""

  started_at="$(date +%s)"
  log "starting $label"
  "$@"
  duration="$(elapsed_seconds "$started_at")"
  log "finished $label in ${duration}s"

  if [ "$duration" -gt "$warn_after_seconds" ]; then
    warn "$label took ${duration}s, above warning threshold ${warn_after_seconds}s"
  fi
}

run_tty() {
  local command="$1"

  script -qec "$command" /dev/null
}

task_project() {
  task -t "$project_root/Taskfile.yaml" "$@"
}

devcontainer_cli() {
  local workspace_folder=""
  local container_workspace_folder=""
  local container_workspace_relative="."
  local container_workspace_suffix=""
  local previous_arg=""
  local arg=""

  for arg in "$@"; do
    if [ "$previous_arg" = "--workspace-folder" ]; then
      workspace_folder="$arg"
      break
    fi

    previous_arg="$arg"
  done

  if [ -n "$workspace_folder" ]; then
    container_workspace_folder="$(expected_workspace_folder "$workspace_folder" "${BRANCH:-}")"
    if [ -n "${BRANCH:-}" ]; then
      container_workspace_relative=".worktrees/$BRANCH"
      container_workspace_suffix="/.worktrees/$BRANCH"
    fi
    (cd "$workspace_folder" && DEVCONTAINER_WORKSPACE_FOLDER="${DEVCONTAINER_WORKSPACE_FOLDER:-$container_workspace_folder}" DEVCONTAINER_WORKSPACE_RELATIVE="${DEVCONTAINER_WORKSPACE_RELATIVE:-$container_workspace_relative}" DEVCONTAINER_WORKSPACE_SUFFIX="${DEVCONTAINER_WORKSPACE_SUFFIX:-$container_workspace_suffix}" npx --yes @devcontainers/cli "$@")
    return
  fi

  npx --yes @devcontainers/cli "$@"
}

run_project_tty() {
  local task_name="$1"
  shift

  run_tty "task -t '$project_root/Taskfile.yaml' '$task_name' $*"
}

extract_container_id_from_log() {
  local log_file="$1"

  tr -d '\r' <"$log_file" \
    | grep -Eo 'containerId[": ]+[a-f0-9]+' \
    | grep -Eo '[a-f0-9]{12,}' \
    | tail -n 1
}

extract_remote_workspace_folder_from_log() {
  local log_file="$1"

  tr -d '\r' <"$log_file" \
    | grep -Eo '"remoteWorkspaceFolder":"[^"]+"' \
    | tail -n 1 \
    | cut -d: -f2- \
    | tr -d '"'
}

extract_key_value() {
  local input="$1"
  local key="$2"
  local line=""

  while IFS= read -r line; do
    case "$line" in
      "$key="*)
        printf '%s\n' "${line#*=}"
        return 0
        ;;
    esac
  done <<<"$input"
}

slug_hostname_part() {
  local value="${1:-detached}"

  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-')"
  value="${value#-}"
  value="${value%-}"

  if [ -z "$value" ]; then
    value="detached"
  fi

  printf '%s\n' "$value"
}

fit_hostname() {
  local value="$1"

  value="${value:0:63}"
  value="${value%-}"

  if [ -z "$value" ]; then
    value="detached"
  fi

  printf '%s\n' "$value"
}

expected_generated_hostname() {
  local repo_dir="$1"
  local branch_name="$2"
  local host_part=""
  local repo_part=""
  local branch_part=""

  host_part="$(slug_hostname_part "$(hostname -s 2>/dev/null || hostname)")"
  repo_part="$(slug_hostname_part "$(basename "$repo_dir")")"

  if [ -z "$branch_name" ]; then
    branch_name="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  fi

  if [ -z "$branch_name" ] || [ "$branch_name" = "HEAD" ]; then
    branch_name="detached"
  fi

  branch_part="$(slug_hostname_part "$branch_name")"
  fit_hostname "$host_part-$repo_part-$branch_part"
}

expected_container_user() {
  printf '%s\n' "${USER:-$(id -un)}"
}

expected_workspace_folder() {
  local repo_dir="$1"
  local branch_name="${2:-}"

  if [ -n "$branch_name" ]; then
    printf '%s/.worktrees/%s\n' "$repo_dir" "$branch_name"
    return 0
  fi

  printf '%s\n' "$repo_dir"
}

copy_project_files() {
  local target_dir="$1"

  mkdir -p "$target_dir"

  # Fixtures need the devcontainer kit files, not this repository's own Git
  # database or development-only submodules.
  tar \
    --exclude='.git' \
    --exclude='.devcontainer' \
    --exclude='.opencode' \
    --exclude='.local.env' \
    --exclude='compose.local.yml' \
    -C "$project_root" \
    -cf - . \
    | tar -C "$target_dir" -xf -
}

create_fixture_repo() {
  local fixture_dir="$1"

  mkdir -p "$fixture_dir/.devcontainer"
  copy_project_files "$fixture_dir/.devcontainer"
  rm -rf "$fixture_dir/.devcontainer/tests"
  printf '# fixture\n' >"$fixture_dir/README.md"
}

create_git_fixture_repo() {
  local fixture_dir="$1"

  create_fixture_repo "$fixture_dir"
  git -C "$fixture_dir" init >/dev/null
  git -C "$fixture_dir" config user.name "Test User"
  git -C "$fixture_dir" config user.email "test@example.com"
  git -C "$fixture_dir" add .
  git -C "$fixture_dir" commit -m "initial fixture" >/dev/null
}

create_git_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -b main >/dev/null
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.com"
}

create_kit_submodule_repo() {
  local repo_dir="$1"

  create_git_repo "$repo_dir"
  copy_project_files "$repo_dir"
  rm -rf "$repo_dir/tests"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -m "initial devcontainer kit" >/dev/null
}
