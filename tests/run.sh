#!/usr/bin/env bash
# run.sh - execute the devcontainer kit test suite
#
# Why this exists:
# - Keeps one stable entrypoint while the actual tests live under `tests/`.
# - Runs both the fast launcher regression checks and the heavier devcontainer
#   smoke test.
#
# Related files:
# - tests/start-compose-local.sh
# - tests/devcontainer-smoke.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

"$script_dir/start-compose-local.sh"
"$script_dir/devcontainer-smoke.sh"
