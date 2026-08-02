#!/usr/bin/env bash
# release-build.sh - verify runtime-only release branch creation
#
# Why this exists:
# - Protects the branch contract consumed by downstream repositories that pin
#   this kit as a `.devcontainer` submodule.
# - Exercises the real `scripts/release-build.sh` workflow from a bounded source
#   input set in a cleanup-trapped OS temporary Git repository, so ignored local
#   state is not copied and the current checkout is not changed.
#
# Related files:
# - ../scripts/release-build.sh
# - ../Taskfile.yaml

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

test_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codegeist-release-build-test.XXXXXX")"
release_repo="$test_tmp_dir/release-build-fixture"
release_branch="release"
expected_files="$test_tmp_dir/release-build-expected-files.txt"
actual_files="$test_tmp_dir/release-build-actual-files.txt"
dirty_worktree_log="$test_tmp_dir/release-build-dirty-worktree.log"
missing_verification_log="$test_tmp_dir/release-build-missing-verification.log"
clean_readme="$test_tmp_dir/README_release.md"
release_source_files=(
  ".gitignore"
  ".local.env.example"
  ".oc_local.gitignore.example"
  ".oc_local.opencode.json.example"
  "Dockerfile.base"
  "Dockerfile.example"
  "LICENSE"
  "README_release.md"
  "compose.local.yml.example"
  "devcontainer.json"
  "docker-compose.yml"
  "entrypoint.sh"
  "initialize.sh"
  "scripts/chrome.sh"
  "scripts/release-build.sh"
)

cleanup_release_test() {
  rm -rf "$test_tmp_dir"
}

trap cleanup_release_test EXIT

create_git_repo "$release_repo"
for source_file in "${release_source_files[@]}"; do
  mkdir -p "$release_repo/$(dirname "$source_file")"
  cp -p "$project_root/$source_file" "$release_repo/$source_file"
done
git -C "$release_repo" add .
git -C "$release_repo" commit -m "initial devcontainer kit" >/dev/null

main_commit="$(git -C "$release_repo" rev-parse main)"

[[ "$(git -C "$release_repo" config --local --get commit.gpgSign)" = "false" ]] \
  || fail "fixture repository did not disable inherited commit signing"
[[ "$(git -C "$release_repo" config --local --get core.hooksPath)" = "/dev/null" ]] \
  || fail "fixture repository did not disable inherited Git hooks"

cp -p "$release_repo/README_release.md" "$clean_readme"
printf '\nDirty worktree marker.\n' >>"$release_repo/README_release.md"
if (cd "$release_repo" && scripts/release-build.sh) >"$dirty_worktree_log" 2>&1; then
  fail "release-build accepted an uncommitted source change"
fi
grep -F "working tree must be clean" "$dirty_worktree_log" >/dev/null \
  || fail "release-build did not explain the clean-worktree requirement"
cp -p "$clean_readme" "$release_repo/README_release.md"

if (cd "$release_repo" && scripts/release-build.sh) >"$missing_verification_log" 2>&1; then
  fail "release-build accepted a commit without full-suite verification"
fi
grep -F "release verification is missing or stale" "$missing_verification_log" >/dev/null \
  || fail "release-build did not explain the mandatory verification gate"

mkdir -p "$release_repo/.test-tmp"
cat >"$release_repo/.test-tmp/release-verification" <<EOF
commit=$main_commit
browser-wayland-display0=passed
EOF

(cd "$release_repo" && scripts/release-build.sh) >/dev/null

[[ "$(git -C "$release_repo" rev-parse --abbrev-ref HEAD)" = "main" ]] \
  || fail "release-build did not return to main"
[[ "$(git -C "$release_repo" rev-parse main)" = "$main_commit" ]] \
  || fail "release-build changed main"
[[ -z "$(git -C "$release_repo" status --porcelain)" ]] \
  || fail "release-build left the fixture working tree dirty"

git -C "$release_repo" rev-parse --verify "refs/heads/$release_branch" >/dev/null \
  || fail "release-build did not create branch $release_branch"
[[ "$(git -C "$release_repo" rev-list --parents -n 1 "$release_branch" | wc -w)" = "1" ]] \
  || fail "first release branch commit is not orphaned"

cat >"$expected_files" <<'EOF'
.gitignore
.local.env.example
.oc_local.gitignore.example
.oc_local.opencode.json.example
Dockerfile
Dockerfile.example
LICENSE
README.md
compose.local.yml.example
devcontainer.json
docker-compose.yml
entrypoint.sh
initialize.sh
scripts/chrome.sh
EOF
sort -o "$expected_files" "$expected_files"

git -C "$release_repo" ls-tree -r --name-only "$release_branch" | sort >"$actual_files"
diff -u "$expected_files" "$actual_files" \
  || fail "release branch contains unexpected files"

diff -u "$release_repo/README_release.md" <(git -C "$release_repo" show "$release_branch:README.md") \
  || fail "release branch README.md does not match README_release.md"

diff -u "$release_repo/Dockerfile.base" <(git -C "$release_repo" show "$release_branch:Dockerfile") \
  || fail "release branch Dockerfile does not match Dockerfile.base"

diff -u "$release_repo/LICENSE" <(git -C "$release_repo" show "$release_branch:LICENSE") \
  || fail "release branch LICENSE does not match source LICENSE"

if git -C "$release_repo" show "$release_branch:Dockerfile.example" | grep -Eiq '^[[:space:]]*FROM([[:space:]]|$)'; then
  fail "release branch Dockerfile.example must not contain FROM"
fi

if git -C "$release_repo" show "$release_branch:initialize.sh" | grep -q 'rev-parse --git-path info/exclude\|ensure_git_exclude_pattern'; then
  fail "release branch initializer still writes .git/info/exclude"
fi

[[ "$(git -C "$release_repo" log -1 --format=%s "$release_branch")" = "chore(release): update devcontainer runtime branch" ]] \
  || fail "release branch commit subject is wrong"

pass "release-build rejects dirty source and creates the exact runtime-only branch"
