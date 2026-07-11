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
  'test ! -e /tmp/opencode && test ! -e /usr/local/bin/chrome && grep -F "ln -sf \"\$launcher\" /usr/local/bin/chrome" /usr/local/bin/devcontainer-entrypoint >/dev/null && grep -F "PATH=\"\$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/scripts:\$PATH\"" /etc/profile.d/codegeist-workspace-scripts.sh >/dev/null'
pass "docker image builds through Taskfile with shared toolchain commands available"
