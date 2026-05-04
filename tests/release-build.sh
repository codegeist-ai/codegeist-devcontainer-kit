#!/usr/bin/env bash
# release-build.sh - verify runtime-only release tag creation
#
# Why this exists:
# - Protects the tag contract consumed by downstream repositories that pin this
#   kit as a `.devcontainer` submodule.
# - Exercises the real `scripts/release-build.sh` workflow in a temporary Git
#   repository so the current checkout is not tagged or branch-mutated.
#
# Related files:
# - ../scripts/release-build.sh
# - ../Taskfile.yaml

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

release_repo="$suite_tmp_dir/release-build-fixture"
tag_name="v1.2.3"
expected_files="$suite_tmp_dir/release-build-expected-files.txt"
actual_files="$suite_tmp_dir/release-build-actual-files.txt"

create_git_repo "$release_repo"
copy_project_files "$release_repo"
git -C "$release_repo" add .
git -C "$release_repo" commit -m "initial devcontainer kit" >/dev/null

main_commit="$(git -C "$release_repo" rev-parse main)"

(cd "$release_repo" && scripts/release-build.sh "$tag_name") >/dev/null

[[ "$(git -C "$release_repo" rev-parse --abbrev-ref HEAD)" = "main" ]] \
  || fail "release-build did not return to main"
[[ "$(git -C "$release_repo" rev-parse main)" = "$main_commit" ]] \
  || fail "release-build changed main"
[[ -z "$(git -C "$release_repo" branch --list "tmp-$tag_name")" ]] \
  || fail "release-build did not delete temporary branch"
[[ -z "$(git -C "$release_repo" status --porcelain)" ]] \
  || fail "release-build left the fixture working tree dirty"

git -C "$release_repo" rev-parse --verify "$tag_name" >/dev/null \
  || fail "release-build did not create tag $tag_name"
[[ "$(git -C "$release_repo" rev-parse "$tag_name^{}^")" = "$main_commit" ]] \
  || fail "release tag commit is not based on main"

cat >"$expected_files" <<'EOF'
.gitignore
.local.env.example
Dockerfile
compose.local.yml.example
devcontainer.json
docker-compose.yml
entrypoint.sh
initialize.sh
EOF
sort -o "$expected_files" "$expected_files"

git -C "$release_repo" ls-tree -r --name-only "$tag_name" | sort >"$actual_files"
diff -u "$expected_files" "$actual_files" \
  || fail "release tag contains unexpected files"

[[ "$(git -C "$release_repo" log -1 --format=%s "$tag_name^{commit}")" = "chore(release): prepare $tag_name devcontainer kit" ]] \
  || fail "release tag commit subject is wrong"

pass "release-build creates a runtime-only tag without changing main"
