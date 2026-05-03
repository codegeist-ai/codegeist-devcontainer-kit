#!/usr/bin/env bash
# docker-run.sh - verify the Taskfile docker-run path works through a TTY
#
# Related files:
# - ../Taskfile.yaml
# - ../entrypoint.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

expected_user="${CONTAINER_USER:-${USER:-$(id -un)}}"
test_output="$(run_project_tty docker-run "COMMAND='id -un && docker ps >/dev/null && pwd'")"

[[ "$test_output" == *"$expected_user"* ]] || fail "docker-run did not execute as the container user"
[[ "$test_output" == *"$project_root"* ]] || fail "docker-run did not preserve the workspace path"

pass "docker-run starts nested Docker and runs as the container user"
