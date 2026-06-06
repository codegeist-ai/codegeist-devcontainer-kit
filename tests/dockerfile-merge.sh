#!/usr/bin/env bash
# dockerfile-merge.sh - verify the root .codegeist Dockerfile extension
#
# Why this exists:
# - Consuming repositories keep the visible devcontainer extension at root
#   `.codegeist/Dockerfile`, next to `.codegeist/compose.local.yml`.
# - The generated Dockerfile must append that extension to the kit base image,
#   reject `FROM`, and stay ignored by the kit submodule.
#
# Related files:
# - ../initialize.sh
# - ../Dockerfile.base
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
merged_contents=""
compose_config=""
root_dockerfile=""
merge_error_file="$suite_tmp_dir/dockerfile-merge-error.log"

create_git_fixture_repo "$fixture_dir"
merged_dockerfile="$fixture_dir/.devcontainer/Dockerfile.merged.gen"
root_dockerfile="$fixture_dir/.codegeist/Dockerfile"

rm -f "$merged_dockerfile" "$root_dockerfile"
"$fixture_dir/.devcontainer/initialize.sh"

[[ -f "$root_dockerfile" ]] || fail "root .codegeist/Dockerfile was not created"
assert_not_ignored "$fixture_dir" ".codegeist/Dockerfile"
[[ -n "$(git -C "$fixture_dir" status --porcelain -- .codegeist/Dockerfile)" ]] || fail ".codegeist/Dockerfile is not visible to git status"
[[ -f "$merged_dockerfile" ]] || fail "merged Dockerfile was not generated"
[[ "$(<"$merged_dockerfile")" == *"FROM debian:bookworm-slim"* ]] || fail "merged Dockerfile does not include the kit Dockerfile"
[[ "$(<"$root_dockerfile")" != *"FROM"* ]] || fail "default .codegeist/Dockerfile extension contains FROM"
[[ "$(<"$merged_dockerfile")" == *"Local project Dockerfile extension from ../.codegeist/Dockerfile"* ]] || fail "merged Dockerfile does not include the default extension marker"
[[ -z "$(git -C "$fixture_dir" status --porcelain -- .devcontainer/Dockerfile.merged.gen)" ]] || fail "merged Dockerfile is not ignored"
compose_config="$(cd "$fixture_dir/.devcontainer" && docker compose -f docker-compose.yml -f compose.local.gen.yml -f ../.codegeist/compose.local.yml config)"
[[ "$compose_config" == *"Dockerfile.merged.gen"* ]] || fail "compose config does not build from the merged Dockerfile"

cp "$root_dockerfile" "$fixture_dir/Dockerfile"
"$fixture_dir/.devcontainer/initialize.sh"
[[ "$(<"$merged_dockerfile")" == *"Local project Dockerfile extension from ../.codegeist/Dockerfile"* ]] || fail "root Dockerfile was treated as the devcontainer extension"

cat >"$fixture_dir/.codegeist/Dockerfile" <<'EOF'
# Dockerfile - fixture devcontainer extension

ENV LOCAL_AGENT_PATTERN=enabled
RUN test "$LOCAL_AGENT_PATTERN" = enabled
EOF

"$fixture_dir/.devcontainer/initialize.sh"
merged_contents="$(<"$merged_dockerfile")"

[[ "$merged_contents" == *"Local project Dockerfile extension from ../.codegeist/Dockerfile"* ]] || fail "merged Dockerfile does not include the local extension marker"
[[ "$merged_contents" == *"ENV LOCAL_AGENT_PATTERN=enabled"* ]] || fail "merged Dockerfile does not include the local extension"
[[ "$merged_contents" == *"ENV LOCAL_AGENT_PATTERN=enabled"*'USER ${CONTAINER_USER}'* ]] || fail "merged Dockerfile does not restore the container user after the local extension"

cat >"$fixture_dir/.codegeist/Dockerfile" <<'EOF'
FROM alpine:3.20
RUN true
EOF

if "$fixture_dir/.devcontainer/initialize.sh" 2>"$merge_error_file"; then
  fail "initialize accepted a local Dockerfile extension with FROM"
fi

[[ "$(<"$merge_error_file")" == *"must not contain FROM"* ]] || fail "invalid local Dockerfile error did not explain the FROM restriction"

pass "initialize appends root .codegeist/Dockerfile extension without allowing FROM"
