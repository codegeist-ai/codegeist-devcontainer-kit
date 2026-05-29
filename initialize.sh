#!/usr/bin/env bash
# initialize.sh - create local devcontainer files and prepare worktrees
#
# Why this exists:
# - `devcontainer.json` includes `../.codegeist/compose.local.yml`, so a fresh
#   consuming checkout needs that local file before the Compose project can be
#   resolved.
# - `../.codegeist/.local.env` carries machine-local runtime values and should be
#   created from the template only once.
# - Git worktrees are prepared through BRANCH before VS Code or the Dev
#   Containers CLI opens the selected workspace path.
# - BRANCH lets root-side helpers create or reuse a managed worktree; when the
#   branch is already checked out, `.worktrees/<branch>` is a symlink alias back
#   to the current checkout so `workspaceFolder` still resolves.
# - `.env` and `compose.local.gen.yml` are generated kit-owned files under
#   `.devcontainer/`; users should edit `.codegeist/.local.env` and
#   `.codegeist/compose.local.yml` instead.
# - `Dockerfile.merged.gen` is generated from the kit Dockerfile and an optional
#   `.codegeist/Dockerfile` fragment so consuming projects can add local
#   coding-agent tools without editing the `.devcontainer` submodule.
# - OpenCode keys session state by directory path, so the container workspace
#   path must match the selected root/worktree path instead of a shared
#   `/workspace` mount.
# - The script runs as a Dev Containers `initializeCommand` on the host and must
#   stay idempotent, non-interactive, and safe for repeated starts.
#
# Related files:
# - devcontainer.json
# - docker-compose.yml
# - Dockerfile
# - Dockerfile.merged.gen
# - compose.local.gen.yml
# - compose.local.yml.example
# - .codegeist/compose.local.yml
# - .codegeist/.local.env
# - .env
# - .local.env.example

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"
checkout_dir="$(dirname "$script_dir")"

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
    printf 'Refusing to merge %s because local devcontainer Dockerfile fragments must not contain FROM. Extend the kit image with RUN, COPY, ENV, or similar instructions instead.\n' "$local_dockerfile" >&2
    return 1
  fi
}

write_merged_dockerfile() {
  local root_dir="$1"
  local kit_dockerfile="$script_dir/Dockerfile"
  local local_dockerfile="$root_dir/.codegeist/Dockerfile"
  local target_file="$script_dir/Dockerfile.merged.gen"
  local kit_dockerfile_real=""
  local local_dockerfile_real=""

  [ -f "$kit_dockerfile" ] || {
    printf 'Kit Dockerfile is missing: %s\n' "$kit_dockerfile" >&2
    return 1
  }

  cp "$kit_dockerfile" "$target_file"

  if [ ! -f "$local_dockerfile" ]; then
    return 0
  fi

  kit_dockerfile_real="$(readlink -f "$kit_dockerfile")"
  local_dockerfile_real="$(readlink -f "$local_dockerfile")"
  if [ "$local_dockerfile_real" = "$kit_dockerfile_real" ]; then
    return 0
  fi

  if cmp -s "$kit_dockerfile" "$local_dockerfile"; then
    return 0
  fi

  validate_local_dockerfile_fragment "$local_dockerfile"

  {
    printf '\n'
    printf '# Local project Dockerfile extension from ../.codegeist/Dockerfile.\n'
    printf '# Appended by .devcontainer/initialize.sh; do not edit this generated file.\n'
    printf '\n'
    cat "$local_dockerfile"
    printf '\n'
    printf 'USER ${CONTAINER_USER}\n'
  } >>"$target_file"
}

repo_root() {
  git -C "$checkout_dir" rev-parse --show-toplevel
}

repo_storage_root() {
  local root_dir="$1"
  local common_dir=""

  common_dir="$(git -C "$root_dir" rev-parse --path-format=absolute --git-common-dir)"
  if [ "$(basename "$common_dir")" = ".git" ]; then
    dirname "$common_dir"
    return 0
  fi

  printf '%s\n' "$root_dir"
}

slugify_hostname_part() {
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

current_branch_name() {
  local root_dir="$1"
  local branch_name=""

  branch_name="$(git -C "$root_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  if [ -z "$branch_name" ] || [ "$branch_name" = "HEAD" ]; then
    branch_name="detached"
  fi

  printf '%s\n' "$branch_name"
}

branch_selects_current_checkout() {
  local root_dir="$1"
  local branch_name="$2"

  [ -n "$branch_name" ] && [ "$(current_branch_name "$root_dir")" = "$branch_name" ]
}

generated_hostname() {
  local root_dir="$1"
  local branch_name="$2"
  local host_part=""
  local repo_part=""
  local branch_part=""

  host_part="$(slugify_hostname_part "$(hostname -s 2>/dev/null || hostname)")"
  repo_part="$(slugify_hostname_part "$(basename "$root_dir")")"
  branch_part="$(slugify_hostname_part "${branch_name:-$(current_branch_name "$root_dir")}")"

  fit_hostname "$host_part-$repo_part-$branch_part"
}

write_generated_env() {
  local target_file="$1"
  local root_dir="$2"
  local branch_name="$3"
  local host_name=""
  local repo_name=""
  local repo_storage_dir=""
  local selected_branch=""
  local container_hostname=""
  local workspace_folder=""
  local workspace_relative="."
  local workspace_suffix=""
  local user_name=""
  local group_name=""
  local uid=""
  local kvm_gid=""

  host_name="$(slugify_hostname_part "$(hostname -s 2>/dev/null || hostname)")"
  repo_name="$(slugify_hostname_part "$(basename "$root_dir")")"
  repo_storage_dir="$(repo_storage_root "$root_dir")"
  selected_branch="${branch_name:-$(current_branch_name "$root_dir")}"
  container_hostname="$(generated_hostname "$root_dir" "$selected_branch")"
  workspace_folder="$root_dir"
  if [ -n "$branch_name" ] && ! branch_selects_current_checkout "$root_dir" "$branch_name"; then
    workspace_folder="$root_dir/.worktrees/$branch_name"
    workspace_relative=".worktrees/$branch_name"
    workspace_suffix="/.worktrees/$branch_name"
  fi
  user_name="${USER:-$(id -un)}"
  group_name="$(id -gn)"
  uid="$(id -u)"
  kvm_gid="$(stat -c %g /dev/kvm 2>/dev/null || id -g)"

  cat >"$target_file" <<EOF
# .env - generated by .devcontainer/initialize.sh
#
# Do not edit manually. Local environment overrides belong in ../.codegeist/.local.env.
DEVCONTAINER_HOST_NAME=$host_name
DEVCONTAINER_REPO_NAME=$repo_name
DEVCONTAINER_REPO_ROOT=$repo_storage_dir
DEVCONTAINER_BRANCH_NAME=$(slugify_hostname_part "$selected_branch")
DEVCONTAINER_HOSTNAME=$container_hostname
DEVCONTAINER_WORKSPACE_FOLDER=$workspace_folder
DEVCONTAINER_WORKSPACE_RELATIVE=$workspace_relative
DEVCONTAINER_WORKSPACE_SUFFIX=$workspace_suffix
DEVCONTAINER_USER=$user_name
DEVCONTAINER_GROUP=$group_name
DEVCONTAINER_UID=$uid
DEVCONTAINER_GID=$uid
DEVCONTAINER_KVM_GID=$kvm_gid
EOF

}

write_generated_compose() {
  local target_file="$1"
  local container_hostname="$2"
  local user_name=""
  local group_name=""
  local uid=""

  user_name="${USER:-$(id -un)}"
  group_name="$(id -gn)"
  uid="$(id -u)"

  cat >"$target_file" <<EOF
# compose.local.gen.yml - generated by .devcontainer/initialize.sh
#
# Do not edit manually. Local Compose overrides belong in ../.codegeist/compose.local.yml.
services:
  workspace:
    build:
      args:
        CONTAINER_USER: $user_name
        CONTAINER_GROUP: $group_name
        CONTAINER_UID: "$uid"
        CONTAINER_GID: "$uid"
    hostname: $container_hostname
    user: "$uid:$uid"
EOF
}

ensure_codegeist_dir() {
  local root_dir="$1"

  mkdir -p "$root_dir/.codegeist"
}

copy_local_or_example_if_missing() {
  local legacy_file="$1"
  local example_file="$2"
  local target_file="$3"

  if [ -e "$target_file" ] || [ -L "$target_file" ]; then
    return 0
  fi

  if [ -e "$legacy_file" ] || [ -L "$legacy_file" ]; then
    cp "$legacy_file" "$target_file"
    return 0
  fi

  cp "$example_file" "$target_file"
}

ensure_codegeist_compose_local() {
  local root_dir="$1"

  copy_local_or_example_if_missing \
    "$root_dir/compose.local.yml" \
    "$root_dir/.devcontainer/compose.local.yml.example" \
    "$root_dir/.codegeist/compose.local.yml"
}

ensure_codegeist_local_env() {
  local root_dir="$1"

  copy_local_or_example_if_missing \
    "$root_dir/.local.env" \
    "$root_dir/.devcontainer/.local.env.example" \
    "$root_dir/.codegeist/.local.env"
}

ensure_opencode_local_config_dir() {
  local root_dir="$1"
  local config_dir="$root_dir/.oc_local"

  mkdir -p "$config_dir"
  copy_if_missing "$root_dir/.devcontainer/.oc_local.gitignore.example" "$config_dir/.gitignore"
}

ensure_worktrees_dir() {
  local root_dir="$1"

  mkdir -p "$root_dir/.worktrees"
}

ensure_current_checkout_alias() {
  local root_dir="$1"
  local branch_name="$2"
  local alias_path="$root_dir/.worktrees/$branch_name"
  local alias_target=""
  local resolved_alias=""

  mkdir -p "$(dirname "$alias_path")"

  if [ -L "$alias_path" ]; then
    resolved_alias="$(readlink -f "$alias_path" 2>/dev/null || true)"
    if [ "$resolved_alias" = "$root_dir" ]; then
      return 0
    fi

    printf 'Refusing to reuse %s because it does not resolve to %s\n' "$alias_path" "$root_dir" >&2
    return 1
  fi

  if [ -e "$alias_path" ]; then
    printf 'Refusing to replace existing non-symlink path: %s\n' "$alias_path" >&2
    return 1
  fi

  alias_target="$(realpath --relative-to="$(dirname "$alias_path")" "$root_dir")"
  ln -s "$alias_target" "$alias_path"
}

has_tracked_opencode_local_overlay() {
  local root_dir="$1"

  [ -n "$(git -C "$root_dir" ls-files .oc_local 2>/dev/null || true)" ]
}

ensure_git_exclude_pattern() {
  local root_dir="$1"
  local pattern="$2"
  local exclude_file=""
  local line=""

  exclude_file="$(git -C "$root_dir" rev-parse --git-path info/exclude 2>/dev/null || true)"
  if [ -z "$exclude_file" ]; then
    return 0
  fi

  if [ -f "$exclude_file" ]; then
    while IFS= read -r line; do
      if [ "$line" = "$pattern" ]; then
        return 0
      fi
    done <"$exclude_file"
  fi

  mkdir -p "$(dirname "$exclude_file")"
  printf '%s\n' "$pattern" >>"$exclude_file"
}

ensure_worktree() {
  local root_dir="$1"
  local branch="$2"
  local slug="$3"
  local worktree_path="$root_dir/.worktrees/$slug"
  local resolved_worktree=""

  git check-ref-format --branch "$branch" >/dev/null
  mkdir -p "$(dirname "$worktree_path")"

  if [ -L "$worktree_path" ]; then
    resolved_worktree="$(readlink -f "$worktree_path" 2>/dev/null || true)"
    if [ "$resolved_worktree" != "$root_dir" ]; then
      printf 'Refusing to replace existing symlink path: %s\n' "$worktree_path" >&2
      return 1
    fi

    rm "$worktree_path"
  fi

  if [ -e "$worktree_path" ]; then
    [ "$(git -C "$worktree_path" rev-parse --show-toplevel)" = "$worktree_path" ]
  elif git -C "$root_dir" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$root_dir" worktree add "$worktree_path" "$branch" >&2
  else
    git -C "$root_dir" worktree add -b "$branch" "$worktree_path" >&2
  fi

  if [ -f "$worktree_path/.gitmodules" ]; then
    git -C "$worktree_path" -c protocol.file.allow=always submodule update --init --recursive >&2
  fi

  printf '%s\n' "$worktree_path"
}

ensure_worktree_local_env_link() {
  local root_dir="$1"
  local worktree_path="$2"
  local link_path="$worktree_path/.codegeist/.local.env"
  local link_target=""

  mkdir -p "$(dirname "$link_path")"

  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    return 0
  fi

  link_target="$(realpath --relative-to="$(dirname "$link_path")" "$root_dir/.codegeist/.local.env")"
  ln -s "$link_target" "$link_path"
}

prepare_selected_worktree() {
  local root_dir="$1"
  local branch_name="$2"
  local worktree_path=""

  if branch_selects_current_checkout "$root_dir" "$branch_name"; then
    ensure_current_checkout_alias "$root_dir" "$branch_name"
    return 0
  fi

  worktree_path="$(ensure_worktree "$root_dir" "$branch_name" "$branch_name")"

  ensure_worktree_local_env_link "$root_dir" "$worktree_path"
}

main() {
  local root_dir=""
  local branch_name=""

  case "${1:-}" in
    "")
      root_dir="$(repo_root)"
      branch_name="${BRANCH:-}"

      ensure_codegeist_dir "$root_dir"
      ensure_codegeist_compose_local "$root_dir"
      ensure_codegeist_local_env "$root_dir"
      write_merged_dockerfile "$root_dir"
      ensure_opencode_local_config_dir "$root_dir"
      ensure_worktrees_dir "$root_dir"
      if ! has_tracked_opencode_local_overlay "$root_dir"; then
        ensure_git_exclude_pattern "$root_dir" "/.oc_local/"
        ensure_git_exclude_pattern "$root_dir" "/.oc_local/.gitignore"
      fi
      ensure_git_exclude_pattern "$root_dir" "/.worktrees/"
      ensure_git_exclude_pattern "$root_dir" "/.codegeist/.local.env"
      ensure_git_exclude_pattern "$root_dir" "/.codegeist/compose.local.yml"
      write_generated_env "$script_dir/.env" "$root_dir" "$branch_name"
      write_generated_compose "$script_dir/compose.local.gen.yml" "$(generated_hostname "$root_dir" "$branch_name")"

      if [ -n "$branch_name" ]; then
        prepare_selected_worktree "$root_dir" "$branch_name"
      fi
      ;;
    *)
      printf 'Usage: %s\n' "$0" >&2
      exit 1
      ;;
  esac
}

main "$@"
