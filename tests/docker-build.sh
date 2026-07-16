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
docker run --rm --entrypoint pass codegeist-devcontainer-kit:local --version >/dev/null
docker run --rm --entrypoint codegeist -w /tmp codegeist-devcontainer-kit:local --version >/dev/null
docker run --rm --entrypoint jbang codegeist-devcontainer-kit:local --version >/dev/null
docker run --rm --entrypoint sh codegeist-devcontainer-kit:local -lc \
  'ffmpeg -version >/dev/null && vhs --version >/dev/null && ttyd --version >/dev/null'
docker run --rm --entrypoint sh codegeist-devcontainer-kit:local -lc \
  '
    set -e

    test ! -e /tmp/opencode
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
pass "docker image builds through Taskfile with shared toolchain commands and Task completion available"
