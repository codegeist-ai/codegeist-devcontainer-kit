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
pass "docker image builds through Taskfile with pass available"
