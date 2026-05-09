#!/usr/bin/env bash
# code-open-args.sh - verify Task forwards branch arguments to code-open.sh
#
# Why this exists:
# - `task code-open-test -- <branch>` is the manual VS Code reality-test entrypoint.
# - The test replaces `code` with a tiny recorder so the flow stays
#   non-interactive and does not open a real editor window.
#
# Related files:
# - ../Taskfile.yaml
# - ../scripts/code-open.sh
# - ./code-open-test.sh
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  trap cleanup_suite EXIT
fi

fixture_dir="$suite_tmp_dir/code-open-args-fixture"
capture_file="$suite_tmp_dir/code-open-args.capture"
fake_code="$suite_tmp_dir/fake-code"
branch_name="develop0"

cat >"$fake_code" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'PWD=%s\n' "$PWD"
  printf 'BRANCH=%s\n' "${BRANCH:-}"
  printf 'DEVCONTAINER_WORKSPACE_RELATIVE=%s\n' "${DEVCONTAINER_WORKSPACE_RELATIVE:-}"
  printf 'DEVCONTAINER_WORKSPACE_SUFFIX=%s\n' "${DEVCONTAINER_WORKSPACE_SUFFIX:-}"
  printf 'ARGS=%s\n' "$*"
} >"$CODE_OPEN_CAPTURE"
EOF
chmod +x "$fake_code"

CODE_BIN="$fake_code" \
  CODE_OPEN_CAPTURE="$capture_file" \
  CODE_OPEN_TEST_SKIP_UP=true \
  KEEP_CODE_FIXTURE_DIR="$fixture_dir" \
  task -t "$project_root/Taskfile.yaml" code-open-test -- "$branch_name" >/dev/null

[[ -f "$capture_file" ]] || fail "fake code command was not invoked"
expected_workspace_folder="$(expected_workspace_folder "$fixture_dir" "$branch_name")"
[[ "$(extract_key_value "$(<"$capture_file")" PWD)" = "$expected_workspace_folder" ]] || fail "code-open-test did not start code from the selected worktree"
[[ "$(extract_key_value "$(<"$capture_file")" BRANCH)" = "$branch_name" ]] || fail "code-open-test did not forward CLI branch as BRANCH"
[[ "$(extract_key_value "$(<"$capture_file")" DEVCONTAINER_WORKSPACE_RELATIVE)" = ".worktrees/$branch_name" ]] || fail "code-open-test did not pass relative workspace path"
[[ "$(extract_key_value "$(<"$capture_file")" DEVCONTAINER_WORKSPACE_SUFFIX)" = "/.worktrees/$branch_name" ]] || fail "code-open-test did not pass workspace suffix"
[[ "$(extract_key_value "$(<"$capture_file")" ARGS)" = "." ]] || fail "code-open-test did not open the fixture root with code ."
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"BRANCH=$branch_name"* ]] || fail "code-open-test did not persist branch for Compose startup"
[[ ! -e "$fixture_dir/.devcontainer/.devcontainer" ]] || fail "code-open-test copied a nested .devcontainer into the fixture"
[[ ! -e "$fixture_dir/.devcontainer/.local.env" ]] || fail "code-open-test copied root .local.env into the kit directory"
[[ ! -e "$fixture_dir/.devcontainer/compose.local.yml" ]] || fail "code-open-test copied root compose.local.yml into the kit directory"
[[ -f "$fixture_dir/.devcontainer/.local.env.example" ]] || fail "code-open-test did not keep .local.env.example in the kit directory"
[[ -f "$fixture_dir/.devcontainer/compose.local.yml.example" ]] || fail "code-open-test did not keep compose.local.yml.example in the kit directory"

env -u BRANCH "$fixture_dir/.devcontainer/initialize.sh"
[[ -d "$fixture_dir/.worktrees/$branch_name" ]] || fail "initializeCommand did not read branch from fixture .env"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_BRANCH_NAME=$branch_name"* ]] || fail "generated env does not use persisted branch"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"BRANCH=$branch_name"* ]] || fail "generated env does not keep persisted branch"

compose_config="$(cd "$fixture_dir" && env -u BRANCH docker compose \
  -f ".devcontainer/docker-compose.yml" \
  -f ".devcontainer/compose.local.gen.yml" \
  -f "compose.local.yml" \
  --profile '*' \
  config)"
[[ "$compose_config" == *"source: $fixture_dir/.worktrees/$branch_name"* ]] || fail "Compose did not select persisted branch worktree"
[[ "$compose_config" == *"target: $expected_workspace_folder"* ]] || fail "Compose did not mount selected worktree at the stable workspace path"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_WORKSPACE_FOLDER=$expected_workspace_folder"* ]] || fail "generated env does not persist selected workspace folder"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_WORKSPACE_RELATIVE=.worktrees/$branch_name"* ]] || fail "generated env does not persist relative workspace folder"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_WORKSPACE_SUFFIX=/.worktrees/$branch_name"* ]] || fail "generated env does not persist workspace suffix"
[[ "$(<"$fixture_dir/.devcontainer/devcontainer.json")" == *'"workspaceFolder": "${localWorkspaceFolder}"'* ]] || fail "devcontainer workspaceFolder does not use the opened workspace folder"

pass "code-open-test forwards task CLI branch arguments to VS Code and Compose startup"
