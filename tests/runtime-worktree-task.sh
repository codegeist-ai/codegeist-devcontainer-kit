#!/usr/bin/env bash
# runtime-worktree-task.sh - smoke-test the runtime worktree task
#
# Runs the real Taskfile in a disposable Git repository. A `code` stub prevents
# the smoke test from opening an actual VS Code window.
#
# Related files:
# - ../Taskfile.runtime.yaml
# - ../scripts/worktree.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

test_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codegeist-runtime-worktree-test.XXXXXX")"
repo_dir="$test_tmp_dir/consumer"
fake_bin="$test_tmp_dir/bin"
branch_name="feature/runtime-task"
worktree_path="$repo_dir/.worktrees/feature-runtime-task"

trap 'rm -rf "$test_tmp_dir"' EXIT

create_git_repo "$repo_dir"
printf '# Test repository\n' >"$repo_dir/README.md"
git -C "$repo_dir" add README.md
git -C "$repo_dir" commit -m "initial consumer" >/dev/null

mkdir -p "$fake_bin"
cat >"$fake_bin/code" <<'EOF'
#!/usr/bin/env bash
touch "$CODE_CALLED"
EOF
chmod +x "$fake_bin/code"

DEVCONTAINER_WORKSPACE_FOLDER="$repo_dir" \
VSCODE_IPC_HOOK_CLI="$test_tmp_dir/fake-vscode-ipc" \
CODE_CALLED="$test_tmp_dir/code-called" \
PATH="$fake_bin:$PATH" \
  task -t "$project_root/Taskfile.runtime.yaml" \
    code:start:worktree -- "$branch_name"

[[ -d "$worktree_path" ]] || fail "runtime task did not create the slugged worktree path"
[[ "$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD)" = "$branch_name" ]] \
  || fail "runtime task worktree has the wrong branch"
[[ -f "$test_tmp_dir/code-called" ]] || fail "runtime task did not open VS Code"

pass "runtime worktree task creates and opens a branch checkout"
