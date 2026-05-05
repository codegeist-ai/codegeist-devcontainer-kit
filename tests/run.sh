#!/usr/bin/env bash
# run.sh - run the generic devcontainer kit test suite
#
# Why this exists:
# - provides one narrow entrypoint for validating the new kit behavior
# - reports total runtime while keeping slow checks as warnings, not failures
#
# Related files:
# - ./helpers.sh
# - ../Taskfile.yaml

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

WARN_BUILD_SECONDS="${WARN_BUILD_SECONDS:-180}"
WARN_DOCKER_SECONDS="${WARN_DOCKER_SECONDS:-60}"
WARN_DEVCONTAINER_SECONDS="${WARN_DEVCONTAINER_SECONDS:-240}"
WARN_FAST_SECONDS="${WARN_FAST_SECONDS:-10}"
WARN_SUITE_SECONDS="${WARN_SUITE_SECONDS:-600}"

setup_suite
trap cleanup_suite EXIT

run_timed "initialize bootstrap" "$WARN_FAST_SECONDS" "$script_dir/initialize.sh"
run_timed "code-open argument forwarding" "$WARN_FAST_SECONDS" "$script_dir/code-open-args.sh"
run_timed "release build branch" "$WARN_FAST_SECONDS" "$script_dir/release-build.sh"
run_timed "compose config" "$WARN_FAST_SECONDS" "$script_dir/compose-config.sh"
run_timed "worktree setup" "$WARN_FAST_SECONDS" "$script_dir/worktree.sh"
run_timed "opencode mounts" "$WARN_DOCKER_SECONDS" "$script_dir/opencode-mounts.sh"
run_timed "docker image build" "$WARN_BUILD_SECONDS" "$script_dir/docker-build.sh"
run_timed "docker-run task" "$WARN_DOCKER_SECONDS" "$script_dir/docker-run.sh"
run_timed "devcontainer up" "$WARN_DEVCONTAINER_SECONDS" "$script_dir/devcontainer-up.sh"
run_timed "devcontainer worktree up" "$WARN_DEVCONTAINER_SECONDS" "$script_dir/devcontainer-worktree-up.sh"
run_timed "submodule workflow" "$WARN_DEVCONTAINER_SECONDS" "$script_dir/submodule-workflow.sh"

suite_duration="$(elapsed_seconds "$suite_start_epoch")"
log "test suite completed in ${suite_duration}s"

if [ "$suite_duration" -gt "$WARN_SUITE_SECONDS" ]; then
  warn "test suite took ${suite_duration}s, above warning threshold ${WARN_SUITE_SECONDS}s"
fi

pass "all generic devcontainer kit tests passed"
