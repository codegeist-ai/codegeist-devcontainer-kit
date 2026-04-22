#!/usr/bin/env bash
# launch.sh - open the workspace root or a repo-managed worktree in a VS Code devcontainer
#
# Why this exists:
# - Keeps the actual devcontainer launcher logic inside the checked-in
#   `.devcontainer/` toolkit instead of duplicating it across wrapper scripts.
# - Reuses the repository root's `.devcontainer/.local.env` from managed
#   worktrees via a symlink.
# - Reuses the tracked root `compose.local.yml` and `.env` files so all managed
#   worktrees share one checked-in overlay and one checked-in set of defaults.
# - Repairs the required `.opencode` and `.devcontainer` submodule checkouts for
#   the selected repository checkout so worktrees stay runnable.
# - Bootstraps the target devcontainer before handing off to host-side VS Code,
#   so the editor attaches to an already running workspace.
# - Waits for the opened VS Code window and removes the matching Compose
#   project plus only the project volumes created by that launcher session.
#
# Usage:
# - ./.devcontainer/launch.sh           Open the repository root in a new VS Code devcontainer window.
# - ./.devcontainer/launch.sh <branch>  Create or open `.worktrees/<branch>` in a new VS Code devcontainer window.
#
# Related files:
# - ../start.sh
# - ../.env
# - ../compose.local.yml
# - .local.env.example
# - docker-compose.yml

set -euo pipefail

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [branch]\n' "$0" >&2
  exit 1
fi

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
repo_root="$(readlink -f "$script_dir/..")"
branch="${1:-}"
target="$repo_root"
runtime_repo_root="$repo_root"
runtime_repo_worktree="$repo_root"
runtime_project_name="codegeist-ai-planer-root"
runtime_hostname="codegeist-ai-planer"
runtime_uid="$(id -u)"
runtime_gid="$(id -g)"
runtime_opencode_dir_config="${OPENCODE_DIR_CONFIG:-$HOME/.config/opencode}"
runtime_opencode_dir_share="${OPENCODE_DIR_SHARE:-$HOME/.local/share/opencode}"
runtime_opencode_dir_state="${OPENCODE_DIR_STATE:-$HOME/.local/state/opencode}"

slugify_branch() {
  local branch_name="${1:-detached}"

  branch_name="$(printf '%s' "$branch_name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-')"
  branch_name="${branch_name#-}"
  branch_name="${branch_name%-}"

  if [ -z "$branch_name" ]; then
    branch_name="detached"
  fi

  printf '%s\n' "$branch_name"
}

ensure_worktree() {
  local branch_name="$1"
  local worktree_path="$repo_root/.worktrees/$branch_name"

  git check-ref-format --branch "$branch_name" >/dev/null
  mkdir -p "$(dirname "$worktree_path")"

  if [ -e "$worktree_path" ]; then
    [ "$(git -C "$worktree_path" rev-parse --show-toplevel)" = "$worktree_path" ]
  elif git show-ref --verify --quiet "refs/heads/$branch_name"; then
    git worktree add "$worktree_path" "$branch_name" >&2
  else
    git worktree add -b "$branch_name" "$worktree_path" >&2
  fi

  printf '%s\n' "$worktree_path"
}

init_submodule() {
  local checkout="$1"
  local submodule_name="$2"

  git -C "$checkout" -c protocol.file.allow=always \
    submodule update --init --recursive "$submodule_name" >&2
}

prepare_submodule_path() {
  local checkout="$1"
  local submodule_name="$2"
  local submodule_path="$checkout/$submodule_name"
  local preserve_dir=""
  local entry=""
  local entry_name=""

  if [ ! -e "$submodule_path" ] || [ -e "$submodule_path/.git" ]; then
    return 0
  fi

  if [ "$submodule_name" != ".devcontainer" ]; then
    return 0
  fi

  preserve_dir="$(mktemp -d)"
  shopt -s dotglob nullglob

  for entry in "$submodule_path"/*; do
    entry_name="${entry##*/}"

    case "$entry_name" in
      .local.env)
        mv "$entry" "$preserve_dir/$entry_name"
        ;;
      *)
        shopt -u dotglob nullglob
        mv "$preserve_dir"/.local.env "$submodule_path/.local.env" 2>/dev/null || true
        rmdir "$preserve_dir" 2>/dev/null || true
        printf 'Cannot initialize %s submodule in %s\n' "$submodule_name" "$checkout" >&2
        printf 'The path %s contains unexpected local files.\n' "$submodule_path" >&2
        printf 'Keep only .local.env there, or move the other files away, then run %s again.\n' "$0" >&2
        return 1
        ;;
    esac
  done

  shopt -u dotglob nullglob
  rmdir "$submodule_path"
  init_submodule "$checkout" "$submodule_name"

  if [ -f "$preserve_dir/.local.env" ]; then
    mv "$preserve_dir/.local.env" "$submodule_path/.local.env"
  fi

  rmdir "$preserve_dir"
}

ensure_submodule() {
  local checkout="$1"
  local submodule_name="$2"
  local submodule_path="$checkout/$submodule_name"
  local submodule_status=""

  if [ ! -f "$checkout/.gitmodules" ]; then
    return 0
  fi

  if ! git -C "$checkout" config --file .gitmodules --get "submodule.${submodule_name}.path" >/dev/null 2>&1; then
    return 0
  fi

  if [ -e "$submodule_path/.git" ]; then
    if [ "$submodule_name" = ".devcontainer" ] && [ ! -f "$submodule_path/devcontainer.json" ]; then
      init_submodule "$checkout" "$submodule_name"
    fi

    return 0
  fi

  prepare_submodule_path "$checkout" "$submodule_name"

  if [ -e "$submodule_path/.git" ]; then
    return 0
  fi

  submodule_status="$(git -C "$checkout" submodule status -- "$submodule_name" 2>/dev/null || true)"

  if [ -n "$submodule_status" ] && [ "${submodule_status#-}" != "$submodule_status" ]; then
    printf 'Initializing %s submodule in %s\n' "$submodule_name" "$checkout" >&2
    init_submodule "$checkout" "$submodule_name"
    return 0
  fi

  if [ -e "$submodule_path" ]; then
    printf 'Cannot initialize %s submodule in %s\n' "$submodule_name" "$checkout" >&2
    printf 'The path %s already exists and is not an initialized Git submodule.\n' "$submodule_path" >&2
    printf 'Move or remove that directory, then run %s again.\n' "$0" >&2
    return 1
  fi

  printf 'Initializing %s submodule in %s\n' "$submodule_name" "$checkout" >&2
  init_submodule "$checkout" "$submodule_name"
}

devcontainer_folder_uri() {
  local checkout="$1"
  local workspace_hex=""

  workspace_hex="$(printf '%s' "$checkout" | od -An -tx1 -v | tr -d '[:space:]')"
  printf 'vscode-remote://dev-container+%s%s\n' "$workspace_hex" "$checkout"
}

has_open_workspace_window() {
  local checkout="$1"
  local folder_uri="$(devcontainer_folder_uri "$checkout")"
  local process_args=""

  while IFS= read -r process_args; do
    case "$process_args" in
      *" --folder-uri $folder_uri"|*" --folder-uri $folder_uri "*)
        return 0
        ;;
    esac
  done < <(ps -eo args=)

  return 1
}

remove_stopped_project_containers() {
  local container_id=""
  local container_status=""

  while IFS=' ' read -r container_id container_status; do
    if [ -n "$container_id" ] && [ "$container_status" != "running" ]; then
      docker rm -f "$container_id" >&2 || true
    fi
  done < <(
    docker ps -a \
      --filter "label=com.docker.compose.project=$runtime_project_name" \
      --format '{{.ID}} {{.State}}'
  )
}

open_remote_checkout() {
  local checkout="$1"
  local folder_uri="$(devcontainer_folder_uri "$checkout")"

  if [ -n "${VSCODE_IPC_HOOK_CLI:-}" ] && [ -S "${VSCODE_IPC_HOOK_CLI}" ]; then
    env \
      PWD="$runtime_repo_worktree" \
      CODEGEIST_REPO_ROOT="$runtime_repo_root" \
      CODEGEIST_REPO_WORKTREE="$runtime_repo_worktree" \
      COMPOSE_PROJECT_NAME="$runtime_project_name" \
      PROJECT_NAME="$runtime_project_name" \
      CODEGEIST_HOSTNAME="$runtime_hostname" \
      UID="$runtime_uid" \
      GID="$runtime_gid" \
      OPENCODE_DIR_CONFIG="$runtime_opencode_dir_config" \
      OPENCODE_DIR_SHARE="$runtime_opencode_dir_share" \
      OPENCODE_DIR_STATE="$runtime_opencode_dir_state" \
      code --new-window --folder-uri "$folder_uri"
    return 0
  fi

  if [ -x /usr/bin/code ]; then
    env \
      -u VSCODE_IPC_HOOK_CLI \
      -u REMOTE_CONTAINERS \
      -u REMOTE_CONTAINERS_IPC \
      -u TERM_PROGRAM \
      PWD="$runtime_repo_worktree" \
      CODEGEIST_REPO_ROOT="$runtime_repo_root" \
      CODEGEIST_REPO_WORKTREE="$runtime_repo_worktree" \
      COMPOSE_PROJECT_NAME="$runtime_project_name" \
      PROJECT_NAME="$runtime_project_name" \
      CODEGEIST_HOSTNAME="$runtime_hostname" \
      UID="$runtime_uid" \
      GID="$runtime_gid" \
      OPENCODE_DIR_CONFIG="$runtime_opencode_dir_config" \
      OPENCODE_DIR_SHARE="$runtime_opencode_dir_share" \
      OPENCODE_DIR_STATE="$runtime_opencode_dir_state" \
      /usr/bin/code --new-window --folder-uri "$folder_uri"
  else
    printf 'Open this folder URI in VS Code: %s\n' "$folder_uri" >&2
  fi
}

open_ipc_checkout() {
  local checkout="$1"
  local folder_uri="$(devcontainer_folder_uri "$checkout")"

  env \
    PWD="$runtime_repo_worktree" \
    CODEGEIST_REPO_ROOT="$runtime_repo_root" \
    CODEGEIST_REPO_WORKTREE="$runtime_repo_worktree" \
    COMPOSE_PROJECT_NAME="$runtime_project_name" \
    PROJECT_NAME="$runtime_project_name" \
    CODEGEIST_HOSTNAME="$runtime_hostname" \
    UID="$runtime_uid" \
    GID="$runtime_gid" \
    OPENCODE_DIR_CONFIG="$runtime_opencode_dir_config" \
    OPENCODE_DIR_SHARE="$runtime_opencode_dir_share" \
    OPENCODE_DIR_STATE="$runtime_opencode_dir_state" \
    code --new-window --folder-uri "$folder_uri"
}

open_checkout() {
  local checkout="$1"
  local folder_uri="$(devcontainer_folder_uri "$checkout")"

  if [ -n "${VSCODE_IPC_HOOK_CLI:-}" ] && [ -S "${VSCODE_IPC_HOOK_CLI}" ]; then
    open_ipc_checkout "$checkout"
    return 0
  fi

  if [ "${REMOTE_CONTAINERS:-false}" = "true" ]; then
    open_remote_checkout "$checkout"
    return 0
  fi

  env \
    PWD="$runtime_repo_worktree" \
    CODEGEIST_REPO_ROOT="$runtime_repo_root" \
    CODEGEIST_REPO_WORKTREE="$runtime_repo_worktree" \
    COMPOSE_PROJECT_NAME="$runtime_project_name" \
    PROJECT_NAME="$runtime_project_name" \
    CODEGEIST_HOSTNAME="$runtime_hostname" \
    UID="$runtime_uid" \
    GID="$runtime_gid" \
    OPENCODE_DIR_CONFIG="$runtime_opencode_dir_config" \
    OPENCODE_DIR_SHARE="$runtime_opencode_dir_share" \
    OPENCODE_DIR_STATE="$runtime_opencode_dir_state" \
    code --new-window --wait --folder-uri "$folder_uri"
}

cleanup_devcontainer_project() {
  local checkout="$1"

  env \
    PWD="$runtime_repo_worktree" \
    CODEGEIST_REPO_ROOT="$runtime_repo_root" \
    CODEGEIST_REPO_WORKTREE="$runtime_repo_worktree" \
    COMPOSE_PROJECT_NAME="$runtime_project_name" \
    PROJECT_NAME="$runtime_project_name" \
    CODEGEIST_HOSTNAME="$runtime_hostname" \
    UID="$runtime_uid" \
    GID="$runtime_gid" \
    OPENCODE_DIR_CONFIG="$runtime_opencode_dir_config" \
    OPENCODE_DIR_SHARE="$runtime_opencode_dir_share" \
    OPENCODE_DIR_STATE="$runtime_opencode_dir_state" \
    docker compose \
      --project-name "$runtime_project_name" \
      -f "$checkout/.devcontainer/docker-compose.yml" \
      -f "$checkout/compose.local.yml" \
      down --volumes --remove-orphans >&2
}

set_runtime_env() {
  local checkout="$1"
  local branch_name="$(git -C "$checkout" branch --show-current || true)"
  local branch_slug=""

  if [ -z "$branch_name" ]; then
    branch_name="detached"
  fi

  branch_slug="$(slugify_branch "$branch_name")"

  runtime_repo_root="$repo_root"
  runtime_repo_worktree="$checkout"
  runtime_project_name="codegeist-ai-planer-$branch_slug"
  runtime_hostname="codegeist-ai-planer-$branch_slug"
}

ensure_worktree_local_env_link() {
  local checkout="$1"
  local link_path="$checkout/.devcontainer/.local.env"
  local link_target="../../../.devcontainer/.local.env"

  if [ "$checkout" = "$repo_root" ]; then
    return 0
  fi

  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    return 0
  fi

  ln -s "$link_target" "$link_path"
}

ensure_root_local_env() {
  local root_local_env="$repo_root/.devcontainer/.local.env"
  local root_local_env_example="$repo_root/.devcontainer/.local.env.example"

  if [ -f "$root_local_env" ]; then
    return 0
  fi

  if [ -f "$root_local_env_example" ]; then
    cp "$root_local_env_example" "$root_local_env"
    printf 'Created %s from %s\n' "$root_local_env" "$root_local_env_example" >&2
    return 0
  fi

  return 1
}

if [ -n "$branch" ]; then
  target="$(ensure_worktree "$branch")"
fi

ensure_submodule "$target" .opencode
ensure_submodule "$target" .devcontainer

ensure_worktree_local_env_link "$target"
ensure_root_local_env || true

if [ ! -f "$target/.devcontainer/.local.env" ]; then
  printf 'Missing %s\n' "$target/.devcontainer/.local.env" >&2
  printf 'The launcher could not create it from .devcontainer/.local.env.example in the repository root.\n' >&2
fi

set_runtime_env "$target"

if [ "${W_NO_OPEN:-0}" = "1" ]; then
  printf 'CODEGEIST_REPO_ROOT=%s\n' "$runtime_repo_root"
  printf 'CODEGEIST_REPO_WORKTREE=%s\n' "$runtime_repo_worktree"
  printf 'COMPOSE_PROJECT_NAME=%s\n' "$runtime_project_name"
  printf 'PROJECT_NAME=%s\n' "$runtime_project_name"
  printf 'CODEGEIST_HOSTNAME=%s\n' "$runtime_hostname"
  printf 'UID=%s\n' "$runtime_uid"
  printf 'GID=%s\n' "$runtime_gid"
  printf 'OPENCODE_DIR_CONFIG=%s\n' "$runtime_opencode_dir_config"
  printf 'OPENCODE_DIR_SHARE=%s\n' "$runtime_opencode_dir_share"
  printf 'OPENCODE_DIR_STATE=%s\n' "$runtime_opencode_dir_state"
  exit 0
fi

open_checkout "$target"

if [ "${REMOTE_CONTAINERS:-false}" != "true" ]; then
  if has_open_workspace_window "$target"; then
    printf 'Skipping cleanup for %s because another VS Code window still targets it.\n' "$target" >&2
  else
    cleanup_devcontainer_project "$target"
  fi
fi
