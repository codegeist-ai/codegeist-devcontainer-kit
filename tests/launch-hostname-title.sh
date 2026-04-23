#!/usr/bin/env bash
# launch-hostname-title.sh - verify launcher hostname is kept separate from container HOSTNAME
#
# Why this exists:
# - The devcontainer title should show the short hostname of the machine that
#   invoked `start.sh`, even when `CODEGEIST_HOSTNAME` is used for the container.
# - We must not override `HOSTNAME` in the container environment; Docker should
#   own that value.
#
# Related files:
# - ../devcontainer.json
# - ../launch.sh
# - ../tests/start-compose-local.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
devcontainer_dir="$(dirname "$script_dir")"
source_repo_root="$(dirname "$devcontainer_dir")"
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT

fail() {
  printf '%s\n' "$*" >&2
  return 1
}

copy_fixture_repo() {
  local target_repo="$1"

  mkdir -p "$target_repo/.devcontainer"
  cp "$devcontainer_dir/launch.sh" "$target_repo/.devcontainer/launch.sh"
  chmod +x "$target_repo/.devcontainer/launch.sh"
  cp "$source_repo_root/compose.local.yml" "$target_repo/compose.local.yml"
  cp "$devcontainer_dir/.local.env.example" "$target_repo/.devcontainer/.local.env"
}

write_fake_hostname() {
  local bin_dir="$1"

  cat >"$bin_dir/hostname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "-s" ]; then
  printf 'fixture-host\n'
  exit 0
fi

printf 'fixture-host.example.invalid\n'
EOF
  chmod +x "$bin_dir/hostname"
}

test_devcontainer_title_uses_launch_hostname_var() {
  if ! grep -q '${localEnv:CODEGEIST_LAUNCH_HOSTNAME}/${localEnv:PROJECT_NAME}' "$devcontainer_dir/devcontainer.json"; then
    fail "devcontainer.json name must include CODEGEIST_LAUNCH_HOSTNAME/PROJECT_NAME"
  fi
}

test_launcher_exports_short_hostname() {
  local repo_path="$temp_root/repo-launch-hostname"
  local bin_dir="$repo_path/bin"
  local output=""

  mkdir -p "$repo_path"
  git init "$repo_path" >/dev/null
  copy_fixture_repo "$repo_path"
  mkdir -p "$bin_dir"
  write_fake_hostname "$bin_dir"

  output="$(
    PATH="$bin_dir:$PATH" \
      W_NO_OPEN=1 "$repo_path/.devcontainer/launch.sh"
  )"

  if ! printf '%s\n' "$output" | grep -q '^CODEGEIST_LAUNCH_HOSTNAME=fixture-host$'; then
    fail "Expected CODEGEIST_LAUNCH_HOSTNAME=fixture-host in launcher output"
  fi

  if ! printf '%s\n' "$output" | grep -q '^CODEGEIST_HOSTNAME=codegeist-ai-planer-'; then
    fail "Expected CODEGEIST_HOSTNAME to remain the branch-based container hostname"
  fi
}

test_launcher_does_not_override_container_hostname_var() {
  if grep -Eq '(^|[[:space:]])HOSTNAME=' "$devcontainer_dir/launch.sh"; then
    fail "launch.sh must not pass HOSTNAME=... to VS Code"
  fi
}

printf '[start] launcher launch-hostname contract\n'
test_devcontainer_title_uses_launch_hostname_var
test_launcher_exports_short_hostname
test_launcher_does_not_override_container_hostname_var
printf '[done] launcher launch-hostname contract\n'
