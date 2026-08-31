#!/usr/bin/env bash
# docker-build.sh - verify the kit image builds through its Taskfile
#
# Related files:
# - ../Taskfile.yaml
# - ../Dockerfile.base

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

task_project docker-build

trivy_fixture_dir="$suite_tmp_dir/trivy-config"
mkdir -p "$trivy_fixture_dir"
printf '%s\n' \
  'FROM scratch' \
  'USER root' \
  >"$trivy_fixture_dir/Dockerfile"

set +e
trivy_config_output="$(docker run --rm \
  --entrypoint trivy \
  --mount "type=bind,src=$trivy_fixture_dir,dst=/scan,readonly" \
  codegeist-devcontainer-kit:local \
  config \
  --cache-dir /tmp/trivy-cache \
  --skip-check-update \
  --skip-version-check \
  --severity HIGH \
  --exit-code 1 \
  --format json \
  --quiet \
  /scan)"
trivy_config_status="$?"
set -e

[ "$trivy_config_status" -eq 1 ] \
  || fail "Trivy config scan returned $trivy_config_status instead of the expected finding exit 1"
printf '%s' "$trivy_config_output" \
  | jq -e '
      [
        .Results[]?.Misconfigurations[]?
        | select(
            .ID == "DS-0002"
            and .Severity == "HIGH"
            and (.Message | contains("Last USER command in Dockerfile should not be"))
          )
      ]
      | length == 1
    ' >/dev/null \
  || fail "Trivy config scan did not report the expected DS-0002 root-user finding"

docker run --rm --entrypoint pass codegeist-devcontainer-kit:local --version >/dev/null
docker run --rm --entrypoint codegeist -w /tmp codegeist-devcontainer-kit:local --version >/dev/null
docker run --rm --entrypoint jbang codegeist-devcontainer-kit:local --version >/dev/null
docker run --rm --entrypoint tea codegeist-devcontainer-kit:local --version >/dev/null
docker run --rm --entrypoint gitleaks codegeist-devcontainer-kit:local version >/dev/null
docker run --rm --entrypoint sh codegeist-devcontainer-kit:local -lc \
  'ffmpeg -version >/dev/null && vhs --version >/dev/null && ttyd --version >/dev/null'
docker run --rm --entrypoint sh codegeist-devcontainer-kit:local -lc '
  set -e
  nvim --headless "+quit"
  gum --version >/dev/null
  rg --version >/dev/null
  bat --version >/dev/null
  btop --version >/dev/null
  eza --version >/dev/null
  dust --version >/dev/null
  fzf --version >/dev/null
  test ! -L /usr/local/bin/bat
  ! dpkg-query -W ripgrep >/dev/null 2>&1
'
docker run --rm --entrypoint sh codegeist-devcontainer-kit:local -lc \
  '
    set -e

    test ! -e /tmp/opencode
    test -d /tmp/ws-data
    test ! -e /usr/local/bin/chrome
    dpkg-query -W bash-completion >/dev/null
    test -s /usr/share/bash-completion/completions/task
    grep -F "function _task()" /usr/share/bash-completion/completions/task >/dev/null
    grep -F "complete -F _task \"\$TASK_CMD\"" /usr/share/bash-completion/completions/task >/dev/null
    grep -F "ln -sf \"\$launcher\" /usr/local/bin/chrome" /usr/local/bin/devcontainer-entrypoint >/dev/null
    grep -F "PATH=\"\$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/scripts:\$PATH\"" /etc/profile.d/codegeist-workspace-scripts.sh >/dev/null
  '
docker run --rm --entrypoint bash codegeist-devcontainer-kit:local -ic \
  '_completion_loader task >/dev/null 2>&1; status="$?"; { [ "$status" -eq 0 ] || [ "$status" -eq 124 ]; } && complete -p task | grep -F "complete -F _task task" >/dev/null'
pass "docker image builds with terminal tools, Trivy scanning, shared commands, and Task completion available"
