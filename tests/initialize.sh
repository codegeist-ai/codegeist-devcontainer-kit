#!/usr/bin/env bash
# initialize.sh - verify current-checkout devcontainer bootstrap behavior
#
# Why this exists:
# - proves initialization owns only the checkout containing the invoked script
# - rejects legacy root configuration imports and managed BRANCH worktrees
# - verifies direct linked worktrees retain independent generated and local state
# - protects atomic X11/Xauthority refresh and the custom initialization hook
#
# Related files:
# - ../initialize.sh
# - ../devcontainer.json
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

fixture_dir="$suite_tmp_dir/initialize-fixture"
worktree_path="$suite_tmp_dir/direct-linked-worktree"
bare_repo_dir="$suite_tmp_dir/shared-repository.git"
bare_worktree_path="$suite_tmp_dir/arbitrary-bare-worktree"
host_xauthority="$suite_tmp_dir/host.Xauthority"

cleanup_test() {
  if [ -d "$worktree_path" ]; then
    git -C "$fixture_dir" worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
  fi
  if [ -d "$bare_worktree_path" ]; then
    git --git-dir="$bare_repo_dir" worktree remove --force "$bare_worktree_path" >/dev/null 2>&1 || true
  fi
  if [ "$local_suite" -eq 1 ]; then
    cleanup_suite
  fi
}
trap cleanup_test EXIT

create_git_fixture_repo "$fixture_dir"
rm -rf "$fixture_dir/.codegeist" "$fixture_dir/.oc_local" "$fixture_dir/.tmp" "$fixture_dir/.worktrees"
rm -f "$fixture_dir/.devcontainer/.env" \
  "$fixture_dir/.devcontainer/.Xauthority.gen" \
  "$fixture_dir/.devcontainer/compose.local.gen.yml" \
  "$fixture_dir/.devcontainer/compose.user.gen.yml"
printf 'LEGACY_ENV=must-not-import\n' >"$fixture_dir/.local.env"
printf 'services:\n  workspace:\n    environment:\n      LEGACY_COMPOSE: must-not-import\n' >"$fixture_dir/compose.local.yml"
printf 'first-authority\n' >"$host_xauthority"
cat >"$fixture_dir/.gitignore" <<'EOF'
# Preserve this entry and the file metadata while removing obsolete patterns.
/kept-local-path/
/.local.env
/compose.local.yml
/.worktrees/**/.codegeist/.local.env
/.worktrees/**/.local.env
EOF
chmod 664 "$fixture_dir/.gitignore"

log "checking current-checkout bootstrap without legacy imports or BRANCH selection"
HOME="$fixture_dir" XAUTHORITY="$host_xauthority" DISPLAY=localhost:42.0 \
  BRANCH=ignored/managed-branch "$fixture_dir/.devcontainer/initialize.sh"

expected_branch="$(git -C "$fixture_dir" rev-parse --abbrev-ref HEAD)"
expected_hostname="$(expected_generated_hostname "$fixture_dir" "$expected_branch")"
expected_project_name="$(expected_compose_project_name "$fixture_dir" "$expected_branch")"
expected_common_dir="$(expected_git_common_dir "$fixture_dir")"
generated_env="$(<"$fixture_dir/.devcontainer/.env")"

[[ -f "$fixture_dir/.codegeist/.local.env" ]] || fail ".codegeist/.local.env was not created"
grep -F 'GITEA_SERVER_URL=' "$fixture_dir/.codegeist/.local.env" >/dev/null \
  || fail ".codegeist/.local.env was not seeded from the current template"
[[ "$generated_env" != *"must-not-import"* ]] || fail "legacy root environment was imported"
[[ ! -e "$fixture_dir/.codegeist/compose.local.yml" ]] || fail "legacy root Compose override was migrated"
[[ "$(<"$fixture_dir/.devcontainer/compose.user.gen.yml")" != *"LEGACY_COMPOSE"* ]] \
  || fail "legacy root Compose override reached the generated bridge"
[[ ! -e "$fixture_dir/.worktrees" ]] || fail "initializer created a managed .worktrees directory"
[[ -d "$fixture_dir/.codegeist/secrets" ]] || fail ".codegeist/secrets was not created"
[[ -L "$fixture_dir/.tmp" && "$(readlink "$fixture_dir/.tmp")" = "/tmp/ws-data" ]] \
  || fail ".tmp does not link to /tmp/ws-data"
[[ -d "$fixture_dir/.oc_local" && -f "$fixture_dir/.oc_local/.gitignore" ]] \
  || fail "OpenCode bootstrap directory was not created"
[[ -f "$fixture_dir/.devcontainer/Dockerfile.merged.gen" ]] || fail "merged Dockerfile was not generated"
[[ -f "$fixture_dir/.devcontainer/compose.local.gen.yml" ]] || fail "generated Compose file is missing"
[[ -f "$fixture_dir/.devcontainer/compose.user.gen.yml" ]] || fail "user Compose bridge is missing"
[[ "$(<"$fixture_dir/.devcontainer/.Xauthority.gen")" = "first-authority" ]] \
  || fail "host Xauthority was not copied"
[[ "$(stat -c %a "$fixture_dir/.devcontainer/.Xauthority.gen")" = "600" ]] \
  || fail "generated Xauthority mode is not 0600"
[[ "$(stat -c %a "$fixture_dir/.gitignore")" = "664" ]] \
  || fail "initializer changed the existing .gitignore mode"

for expected in \
  "DEVCONTAINER_REPO_ROOT=$fixture_dir" \
  "DEVCONTAINER_GIT_COMMON_DIR=$expected_common_dir" \
  "DEVCONTAINER_WORKSPACE_FOLDER=$fixture_dir" \
  "DEVCONTAINER_BRANCH_NAME=$(slug_hostname_part "$expected_branch")" \
  "DEVCONTAINER_HOSTNAME=$expected_hostname" \
  "DEVCONTAINER_COMPOSE_PROJECT_NAME=$expected_project_name" \
  "DEVCONTAINER_DISPLAY=localhost:42.0" \
  "DEVCONTAINER_XAUTHORITY=$fixture_dir/.devcontainer/.Xauthority.gen"; do
  grep -Fx "$expected" "$fixture_dir/.devcontainer/.env" >/dev/null \
    || fail "generated environment is missing: $expected"
done
if grep -Eq '^(BRANCH|DEVCONTAINER_WORKSPACE_(RELATIVE|SUFFIX)|DEVCONTAINER_WAYLAND_)=' \
  "$fixture_dir/.devcontainer/.env"; then
  fail "generated environment retained a removed managed-worktree or Wayland key"
fi

assert_not_ignored "$fixture_dir" ".local.env"
assert_not_ignored "$fixture_dir" "compose.local.yml"
assert_not_ignored "$fixture_dir" ".codegeist/compose.local.yml"
assert_not_ignored "$fixture_dir" ".codegeist/Dockerfile"
assert_ignored_by_root_gitignore "$fixture_dir" ".codegeist/.local.env"
assert_ignored_by_root_gitignore "$fixture_dir" ".codegeist/secrets/example"
assert_ignored_by_root_gitignore "$fixture_dir" ".tmp"
assert_ignored_by_root_gitignore "$fixture_dir" ".chrome/profile-file"

log "checking idempotence, current overrides, X11 refresh, and hooks"
mv "$fixture_dir/.gitignore" "$fixture_dir/.gitignore.target"
ln -s .gitignore.target "$fixture_dir/.gitignore"
printf '/.local.env\n/compose.local.yml\n' >>"$fixture_dir/.gitignore.target"
mkdir -p "$fixture_dir/.codegeist/extensions"
cat >"$fixture_dir/.codegeist/compose.local.yml" <<'EOF'
services:
  workspace:
    environment:
      CURRENT_OVERRIDE: preserved
EOF
printf 'CURRENT_ENV=preserved\n' >"$fixture_dir/.codegeist/.local.env"
cat >"$fixture_dir/.codegeist/extensions/custom_initialize.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$PWD" >.codegeist/custom-initialize.result
EOF
printf 'second-authority\n' >"$host_xauthority"
HOME="$fixture_dir" XAUTHORITY="$host_xauthority" DISPLAY=127.0.0.1:43.0 \
  "$fixture_dir/.devcontainer/initialize.sh"

[[ "$(<"$fixture_dir/.codegeist/.local.env")" = "CURRENT_ENV=preserved" ]] \
  || fail "current local environment was overwritten"
grep -F 'CURRENT_OVERRIDE: preserved' "$fixture_dir/.devcontainer/compose.user.gen.yml" >/dev/null \
  || fail "current Compose override did not refresh the generated bridge"
[[ "$(<"$fixture_dir/.devcontainer/.Xauthority.gen")" = "second-authority" ]] \
  || fail "generated Xauthority was not refreshed"
[[ "$(<"$fixture_dir/.codegeist/custom-initialize.result")" = "$fixture_dir" ]] \
  || fail "custom initialization hook did not run in the opened checkout"
[[ -L "$fixture_dir/.gitignore" ]] || fail "initializer replaced a symlinked .gitignore"
[[ "$(stat -Lc %a "$fixture_dir/.gitignore")" = "664" ]] \
  || fail "initializer changed the symlinked .gitignore target mode"
if grep -Fx -e '/.local.env' -e '/compose.local.yml' "$fixture_dir/.gitignore.target" >/dev/null; then
  fail "initializer did not remove obsolete patterns through a symlinked .gitignore"
fi

log "checking an externally created linked worktree owns independent state"
git -C "$fixture_dir" worktree add -b feature/direct-worktree "$worktree_path" >/dev/null
rm -rf "$worktree_path/.codegeist" "$worktree_path/.oc_local" "$worktree_path/.tmp"
printf 'worktree-authority\n' >"$host_xauthority"
HOME="$worktree_path" XAUTHORITY="$host_xauthority" DISPLAY=localhost:44.0 \
  BRANCH=ignored/again "$worktree_path/.devcontainer/initialize.sh"

worktree_common_dir="$(expected_git_common_dir "$worktree_path")"
for expected in \
  "DEVCONTAINER_REPO_ROOT=$worktree_path" \
  "DEVCONTAINER_GIT_COMMON_DIR=$worktree_common_dir" \
  "DEVCONTAINER_WORKSPACE_FOLDER=$worktree_path" \
  "DEVCONTAINER_BRANCH_NAME=feature-direct-worktree" \
  "DEVCONTAINER_DISPLAY=localhost:44.0"; do
  grep -Fx "$expected" "$worktree_path/.devcontainer/.env" >/dev/null \
    || fail "linked worktree environment is missing: $expected"
done
[[ "$(<"$fixture_dir/.devcontainer/.Xauthority.gen")" = "second-authority" ]] \
  || fail "linked worktree initialization changed main-checkout authority state"
[[ "$(<"$worktree_path/.devcontainer/.Xauthority.gen")" = "worktree-authority" ]] \
  || fail "linked worktree did not receive independent authority state"
[[ -f "$worktree_path/.codegeist/.local.env" && ! -L "$worktree_path/.codegeist/.local.env" ]] \
  || fail "linked worktree did not receive its own local environment file"

log "checking repository identity for a worktree backed by a bare common directory"
git clone --bare "$fixture_dir" "$bare_repo_dir" >/dev/null
git --git-dir="$bare_repo_dir" worktree add -b feature/bare-worktree \
  "$bare_worktree_path" main >/dev/null
HOME="$bare_worktree_path" "$bare_worktree_path/.devcontainer/initialize.sh"
grep -Fx 'DEVCONTAINER_REPO_NAME=shared-repository' \
  "$bare_worktree_path/.devcontainer/.env" >/dev/null \
  || fail "bare worktree did not derive repository identity from its common directory"
grep -Fx 'DEVCONTAINER_COMPOSE_PROJECT_NAME=feature-bare-worktree-shared-repository' \
  "$bare_worktree_path/.devcontainer/.env" >/dev/null \
  || fail "bare worktree Compose identity depends on its arbitrary checkout basename"

mkdir -p "$worktree_path/.codegeist/extensions"
cat >"$worktree_path/.codegeist/extensions/custom_initialize.sh" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
if HOME="$worktree_path" "$worktree_path/.devcontainer/initialize.sh"; then
  fail "failing custom initialization hook did not fail initialization"
fi

pass "initializer prepares only the opened checkout and direct Git worktrees"
