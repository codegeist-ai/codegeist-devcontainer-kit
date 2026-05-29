#!/usr/bin/env bash
# dockerfile-merge.sh - verify local Dockerfile fragments extend the kit image
#
# Why this exists:
# - consuming repositories may keep project-local coding-agent tools in a root
#   `Dockerfile` while the reusable kit lives in a `.devcontainer` submodule
# - the generated Dockerfile must stay ignored by the submodule and must reject
#   `FROM` so local fragments cannot accidentally replace the kit image stage
#
# Related files:
# - ../initialize.sh
# - ../Dockerfile
# - ../docker-compose.yml

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

local_suite=0
if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  local_suite=1
fi

if [ "$local_suite" -eq 1 ]; then
  trap cleanup_suite EXIT
fi

fixture_dir="$suite_tmp_dir/dockerfile-merge-fixture"
merged_dockerfile=""
merge_error_file="$suite_tmp_dir/dockerfile-merge-error.log"
merged_contents=""
compose_config=""

create_git_fixture_repo "$fixture_dir"
merged_dockerfile="$fixture_dir/.devcontainer/Dockerfile.merged.gen"

rm -f "$merged_dockerfile"
"$fixture_dir/.devcontainer/initialize.sh"

[[ -f "$merged_dockerfile" ]] || fail "merged Dockerfile was not generated"
[[ "$(<"$merged_dockerfile")" == *"FROM debian:bookworm-slim"* ]] || fail "merged Dockerfile does not include the kit Dockerfile"
[[ "$(<"$merged_dockerfile")" != *"Local project Dockerfile extension"* ]] || fail "merged Dockerfile added a local extension when no root Dockerfile exists"
[[ -z "$(git -C "$fixture_dir" status --porcelain -- .devcontainer/Dockerfile.merged.gen)" ]] || fail "merged Dockerfile is not ignored"
compose_config="$(cd "$fixture_dir/.devcontainer" && docker compose -f docker-compose.yml -f compose.local.gen.yml -f ../compose.local.yml config)"
[[ "$compose_config" == *"Dockerfile.merged.gen"* ]] || fail "compose config does not build from the merged Dockerfile"

cp "$fixture_dir/.devcontainer/Dockerfile" "$fixture_dir/Dockerfile"
"$fixture_dir/.devcontainer/initialize.sh"
[[ "$(<"$merged_dockerfile")" != *"Local project Dockerfile extension"* ]] || fail "source repo Dockerfile copy was treated as a local extension"

cat >"$fixture_dir/Dockerfile" <<'EOF'
# Dockerfile - local devcontainer extension for the fixture

ENV LOCAL_AGENT_PATTERN=enabled
RUN test "$LOCAL_AGENT_PATTERN" = enabled
EOF

"$fixture_dir/.devcontainer/initialize.sh"
merged_contents="$(<"$merged_dockerfile")"

[[ "$merged_contents" == *"Local project Dockerfile extension from ../Dockerfile"* ]] || fail "merged Dockerfile does not include the local extension marker"
[[ "$merged_contents" == *"ENV LOCAL_AGENT_PATTERN=enabled"* ]] || fail "merged Dockerfile does not include the local extension"
[[ "$merged_contents" == *"ENV LOCAL_AGENT_PATTERN=enabled"*'USER ${CONTAINER_USER}'* ]] || fail "merged Dockerfile does not restore the container user after the local extension"

cat >"$fixture_dir/Dockerfile" <<'EOF'
FROM alpine:3.20
RUN true
EOF

if "$fixture_dir/.devcontainer/initialize.sh" 2>"$merge_error_file"; then
  fail "initialize accepted a local Dockerfile fragment with FROM"
fi

[[ "$(<"$merge_error_file")" == *"must not contain FROM"* ]] || fail "invalid local Dockerfile error did not explain the FROM restriction"

pass "initialize generates a merged Dockerfile with root Dockerfile extension support"
