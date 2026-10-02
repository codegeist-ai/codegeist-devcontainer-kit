#!/usr/bin/env bash
# initialize.sh - prepare the checkout opened by Dev Containers
#
# Why this exists:
# - Seeds checkout-local machine configuration without overwriting user files.
# - Generates the Dockerfile, Compose overrides, runtime environment, and
#   reconnect-refreshable Xauthority state consumed by devcontainer.json.
# - Resolves Git's common directory so a directly opened linked worktree can use
#   normal Git commands without mounting or managing another checkout.
# - Bootstraps writable OpenCode state and runs the optional trusted
#   `.codegeist/extensions/custom_initialize.sh` hook from the opened checkout.
#
# Inputs and side effects:
# - The script location identifies the opened checkout; caller cwd and BRANCH are
#   intentionally ignored.
# - DISPLAY and XAUTHORITY are captured for visible Remote SSH X11 Chrome.
# - Generated files under `.devcontainer/` are replaced atomically. User-owned
#   inputs remain under `.codegeist/` and `.oc_local/`.
# - Git worktree creation, branch selection, and submodule initialization remain
#   explicit caller responsibilities.
#
# Related files:
# - devcontainer.json
# - docker-compose.yml
# - scripts/chrome.sh
# - .local.env.example
# - Dockerfile.example
# - compose.local.yml.example

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"
checkout_dir="$(dirname "$script_dir")"

log() {
  printf 'level=info event=devcontainer_initialize %s\n' "$*" >&2
}

copy_if_missing() {
  local source_file="$1"
  local target_file="$2"

  if [ -e "$target_file" ] || [ -L "$target_file" ]; then
    return 0
  fi
  cp "$source_file" "$target_file"
}

validate_local_dockerfile_fragment() {
  local local_dockerfile="$1"

  if grep -Eiq '^[[:space:]]*FROM([[:space:]]|$)' "$local_dockerfile"; then
    printf 'Refusing to merge %s because local devcontainer Dockerfile extensions must not contain FROM. Extend the kit image with RUN, COPY, ENV, or similar instructions instead.\n' "$local_dockerfile" >&2
    return 1
  fi
}

kit_dockerfile_path() {
  if [ -f "$script_dir/Dockerfile" ]; then
    printf '%s\n' "$script_dir/Dockerfile"
  elif [ -f "$script_dir/Dockerfile.base" ]; then
    printf '%s\n' "$script_dir/Dockerfile.base"
  else
    return 1
  fi
}

write_merged_dockerfile() {
  local root_dir="$1"
  local kit_dockerfile=""
  local local_dockerfile="$root_dir/.codegeist/Dockerfile"
  local target_file="$script_dir/Dockerfile.merged.gen"
  local temporary_file=""

  if ! kit_dockerfile="$(kit_dockerfile_path)"; then
    printf 'Kit Dockerfile is missing: %s or %s\n' "$script_dir/Dockerfile" "$script_dir/Dockerfile.base" >&2
    return 1
  fi
  temporary_file="$(mktemp "$target_file.XXXXXX")"
  cp "$kit_dockerfile" "$temporary_file"

  if [ -f "$local_dockerfile" ] \
    && [ "$(readlink -f "$local_dockerfile")" != "$(readlink -f "$kit_dockerfile")" ] \
    && ! cmp -s "$kit_dockerfile" "$local_dockerfile"; then
    validate_local_dockerfile_fragment "$local_dockerfile"
    {
      printf '\n# Local project Dockerfile extension from ../.codegeist/Dockerfile.\n'
      printf '# Appended by .devcontainer/initialize.sh; do not edit this generated file.\n\n'
      cat "$local_dockerfile"
      printf '\nUSER ${CONTAINER_USER}\n'
    } >>"$temporary_file"
  fi
  mv -f "$temporary_file" "$target_file"
}

repo_root() {
  git -C "$checkout_dir" rev-parse --show-toplevel
}

git_common_dir() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir
}

slugify_hostname_part() {
  local value="${1:-detached}"

  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-')"
  value="${value#-}"
  value="${value%-}"
  [ -n "$value" ] || value="detached"
  printf '%s\n' "$value"
}

fit_hostname() {
  local value="${1:0:63}"

  value="${value%-}"
  [ -n "$value" ] || value="detached"
  printf '%s\n' "$value"
}

current_branch_name() {
  local branch_name=""

  branch_name="$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "$branch_name" ] || [ "$branch_name" = "HEAD" ]; then
    branch_name="detached"
  fi
  printf '%s\n' "$branch_name"
}

# Use the repository that owns the shared Git directory for runtime identity.
# A linked worktree's basename can be arbitrary and is not a stable repo name.
repository_name() {
  local root_dir="$1"
  local common_dir=""
  local common_name=""

  common_dir="$(git_common_dir "$root_dir")"
  common_name="$(basename "$common_dir")"
  if [ "$common_name" = ".git" ]; then
    basename "$(dirname "$common_dir")"
  else
    common_name="${common_name%.git}"
    printf '%s\n' "${common_name:-$(basename "$root_dir")}"
  fi
}

generated_hostname() {
  local root_dir="$1"
  local host_part=""
  local repo_part=""
  local branch_part=""

  host_part="$(slugify_hostname_part "$(hostname -s 2>/dev/null || hostname)")"
  repo_part="$(slugify_hostname_part "$(repository_name "$root_dir")")"
  branch_part="$(slugify_hostname_part "$(current_branch_name "$root_dir")")"
  fit_hostname "$host_part-$repo_part-$branch_part"
}

generated_compose_project_name() {
  local root_dir="$1"
  local repo_part=""
  local branch_part=""

  repo_part="$(slugify_hostname_part "$(repository_name "$root_dir")")"
  branch_part="$(slugify_hostname_part "$(current_branch_name "$root_dir")")"
  printf '%s-%s\n' "$branch_part" "$repo_part"
}

write_generated_xauthority() {
  local target_file="$1"
  local source_file="${XAUTHORITY:-${HOME:-}/.Xauthority}"
  local temporary_file=""

  mkdir -p "$(dirname "$target_file")"
  temporary_file="$(mktemp "$target_file.XXXXXX")"
  if [ -n "$source_file" ] && [ -f "$source_file" ]; then
    cp "$source_file" "$temporary_file"
  else
    : >"$temporary_file"
  fi
  chmod 600 "$temporary_file"
  mv -f "$temporary_file" "$target_file"
}

write_generated_env() {
  local target_file="$1"
  local root_dir="$2"
  local common_dir="$3"
  local branch_name=""
  local temporary_file=""

  branch_name="$(current_branch_name "$root_dir")"
  temporary_file="$(mktemp "$target_file.XXXXXX")"
  cat >"$temporary_file" <<EOF
# .env - generated by .devcontainer/initialize.sh
#
# Do not edit manually. Local environment overrides belong in ../.codegeist/.local.env.
DEVCONTAINER_HOST_NAME=$(slugify_hostname_part "$(hostname -s 2>/dev/null || hostname)")
DEVCONTAINER_REPO_NAME=$(slugify_hostname_part "$(repository_name "$root_dir")")
DEVCONTAINER_REPO_ROOT=$root_dir
DEVCONTAINER_GIT_COMMON_DIR=$common_dir
DEVCONTAINER_BRANCH_NAME=$(slugify_hostname_part "$branch_name")
DEVCONTAINER_HOSTNAME=$(generated_hostname "$root_dir")
DEVCONTAINER_COMPOSE_PROJECT_NAME=$(generated_compose_project_name "$root_dir")
DEVCONTAINER_WORKSPACE_FOLDER=$root_dir
DEVCONTAINER_USER=${USER:-$(id -un)}
DEVCONTAINER_GROUP=$(id -gn)
DEVCONTAINER_UID=$(id -u)
DEVCONTAINER_GID=$(id -u)
DEVCONTAINER_KVM_GID=$(stat -c %g /dev/kvm 2>/dev/null || id -g)
DEVCONTAINER_DISPLAY=${DISPLAY:-}
DEVCONTAINER_XAUTHORITY=$root_dir/.devcontainer/.Xauthority.gen
EOF
  mv -f "$temporary_file" "$target_file"
}

write_generated_compose() {
  local target_file="$1"
  local root_dir="$2"
  local temporary_file=""
  local uid=""

  uid="$(id -u)"
  temporary_file="$(mktemp "$target_file.XXXXXX")"
  cat >"$temporary_file" <<EOF
# compose.local.gen.yml - generated by .devcontainer/initialize.sh
#
# Do not edit manually. Repository Compose overrides are loaded through compose.user.gen.yml.
name: $(generated_compose_project_name "$root_dir")

services:
  workspace:
    build:
      args:
        CONTAINER_USER: ${USER:-$(id -un)}
        CONTAINER_GROUP: $(id -gn)
        CONTAINER_UID: "$uid"
        CONTAINER_GID: "$uid"
    hostname: $(generated_hostname "$root_dir")
    extra_hosts:
      - "$(generated_hostname "$root_dir"):127.0.0.1"
    user: "$uid:$uid"
EOF
  mv -f "$temporary_file" "$target_file"
}

write_user_compose_bridge() {
  local root_dir="$1"
  local source_file="$root_dir/.codegeist/compose.local.yml"
  local target_file="$script_dir/compose.user.gen.yml"
  local temporary_file=""

  temporary_file="$(mktemp "$target_file.XXXXXX")"
  if [ -f "$source_file" ]; then
    cp "$source_file" "$temporary_file"
  else
    cat >"$temporary_file" <<'EOF'
# compose.user.gen.yml - generated by .devcontainer/initialize.sh
#
# Do not edit manually. Create ../.codegeist/compose.local.yml when repository
# Compose overrides are needed.
services: {}
EOF
  fi
  mv -f "$temporary_file" "$target_file"
}

ensure_workspace_tmp_link() {
  local root_dir="$1"

  mkdir -p /tmp/ws-data
  if [ ! -e "$root_dir/.tmp" ] && [ ! -L "$root_dir/.tmp" ]; then
    ln -s /tmp/ws-data "$root_dir/.tmp"
  fi
}

ensure_codegeist_state() {
  local root_dir="$1"

  mkdir -p "$root_dir/.codegeist/secrets"
  copy_if_missing "$script_dir/.local.env.example" "$root_dir/.codegeist/.local.env"
}

ensure_opencode_local_config_dir() {
  local root_dir="$1"
  local config_dir="$root_dir/.oc_local"

  mkdir -p "$config_dir"
  copy_if_missing "$script_dir/.oc_local.gitignore.example" "$config_dir/.gitignore"
}

has_tracked_opencode_local_overlay() {
  [ -n "$(git -C "$1" ls-files .oc_local 2>/dev/null || true)" ]
}

ensure_gitignore_pattern() {
  local root_dir="$1"
  local pattern="$2"
  local gitignore_file="$root_dir/.gitignore"
  local last_byte=""
  local line=""

  if [ -f "$gitignore_file" ]; then
    while IFS= read -r line; do
      [ "$line" != "$pattern" ] || return 0
    done <"$gitignore_file"
  fi
  if [ -s "$gitignore_file" ]; then
    last_byte="$(tail -c 1 "$gitignore_file" | od -An -t x1 | tr -d '[:space:]')"
    [ "$last_byte" = "0a" ] || printf '\n' >>"$gitignore_file"
  fi
  printf '%s\n' "$pattern" >>"$gitignore_file"
}

remove_gitignore_pattern() {
  local root_dir="$1"
  local pattern="$2"
  local gitignore_file="$root_dir/.gitignore"
  local temporary_file=""
  local line=""
  local removed=0

  [ -f "$gitignore_file" ] || return 0
  temporary_file="$(mktemp "$gitignore_file.XXXXXX")"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$pattern" ]; then
      removed=1
    else
      printf '%s\n' "$line" >>"$temporary_file"
    fi
  done <"$gitignore_file"
  if [ "$removed" -eq 1 ]; then
    # Write through symlinks and retain the existing inode's ownership and mode.
    command cat "$temporary_file" >"$gitignore_file"
  fi
  rm -f "$temporary_file"
}

main() {
  local root_dir=""
  local common_dir=""
  local custom_initialize=""

  if [ "$#" -ne 0 ]; then
    printf 'Usage: %s\n' "$0" >&2
    return 1
  fi

  root_dir="$(repo_root)"
  common_dir="$(git_common_dir "$root_dir")"
  log "status=started workspace=$root_dir git_common_dir=$common_dir"

  ensure_codegeist_state "$root_dir"
  ensure_workspace_tmp_link "$root_dir"
  ensure_opencode_local_config_dir "$root_dir"
  write_merged_dockerfile "$root_dir"

  if ! has_tracked_opencode_local_overlay "$root_dir"; then
    ensure_gitignore_pattern "$root_dir" "/.oc_local/"
    ensure_gitignore_pattern "$root_dir" "/.oc_local/.gitignore"
  fi
  ensure_gitignore_pattern "$root_dir" "/.worktrees/"
  ensure_gitignore_pattern "$root_dir" "/.codegeist/.local.env"
  ensure_gitignore_pattern "$root_dir" "/.codegeist/secrets/"
  ensure_gitignore_pattern "$root_dir" "/.chrome/"
  ensure_gitignore_pattern "$root_dir" "/.tmp"
  remove_gitignore_pattern "$root_dir" "/.local.env"
  remove_gitignore_pattern "$root_dir" "/compose.local.yml"
  remove_gitignore_pattern "$root_dir" "/.worktrees/**/.codegeist/.local.env"
  remove_gitignore_pattern "$root_dir" "/.worktrees/**/.local.env"

  write_generated_xauthority "$script_dir/.Xauthority.gen"
  write_generated_env "$script_dir/.env" "$root_dir" "$common_dir"
  write_generated_compose "$script_dir/compose.local.gen.yml" "$root_dir"
  write_user_compose_bridge "$root_dir"

  custom_initialize="$root_dir/.codegeist/extensions/custom_initialize.sh"
  if [ -f "$custom_initialize" ]; then
    log "status=hook_started path=$custom_initialize"
    (cd "$root_dir" && bash "$custom_initialize")
  fi

  log "status=completed workspace=$root_dir"
}

main "$@"
