#!/usr/bin/env bash
# submodule-workflow.sh - verify direct use of the kit as .devcontainer submodule
#
# Why this exists:
# - exercises a consuming checkout whose recorded gitlink supplies the runtime kit
# - proves initialization stays in that checkout and generated submodule files
#   remain ignored
# - verifies consuming-repository Git and nested Docker remain usable
#
# Related files:
# - ../initialize.sh
# - ../devcontainer.json
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

local_suite=0
if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  local_suite=1
fi

kit_repo_dir="$suite_tmp_dir/devcontainer-kit-submodule-repo"
consumer_dir="$suite_tmp_dir/submodule-consumer"
container_id=""
log_file="$suite_tmp_dir/submodule-workflow.log"

cleanup_test() {
  if [ -n "$container_id" ]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
  if [ "$local_suite" -eq 1 ]; then
    cleanup_suite
  fi
}
trap cleanup_test EXIT

create_kit_submodule_repo "$kit_repo_dir"
create_git_repo "$consumer_dir"
printf '# submodule consumer\n' >"$consumer_dir/README.md"
git -C "$consumer_dir" add README.md
git -C "$consumer_dir" commit -m "initial consumer" >/dev/null
git -C "$consumer_dir" -c protocol.file.allow=always submodule add "$kit_repo_dir" .devcontainer >/dev/null
git -C "$consumer_dir" commit -m "add devcontainer submodule" >/dev/null
recorded_gitlink="$(git -C "$consumer_dir" rev-parse HEAD:.devcontainer)"

prepare_devcontainer_home "$consumer_dir"
HOME="$consumer_dir" devcontainer_cli up \
  --remove-existing-container \
  --workspace-folder "$consumer_dir" | tee "$log_file"
container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract submodule-consumer container id"
[[ "$(extract_remote_workspace_folder_from_log "$log_file" || true)" = "$consumer_dir" ]] \
  || fail "submodule consumer did not open its current checkout"

[[ "$(git -C "$consumer_dir/.devcontainer" rev-parse HEAD)" = "$recorded_gitlink" ]] \
  || fail "runtime kit does not match the consuming repository gitlink"
[[ -f "$consumer_dir/.codegeist/.local.env" ]] || fail "consumer local environment was not created"
[[ ! -e "$consumer_dir/.codegeist/compose.local.yml" ]] || fail "optional Compose override was created"
[[ ! -e "$consumer_dir/.codegeist/Dockerfile" ]] || fail "optional Dockerfile extension was created"
[[ -d "$consumer_dir/.oc_local" ]] || fail "consumer OpenCode directory was not created"
for generated_file in .env .Xauthority.gen Dockerfile.merged.gen compose.local.gen.yml compose.user.gen.yml; do
  [[ -e "$consumer_dir/.devcontainer/$generated_file" ]] \
    || fail "submodule generated file is missing: $generated_file"
  [[ -z "$(git -C "$consumer_dir/.devcontainer" status --porcelain -- "$generated_file")" ]] \
    || fail "submodule generated file is visible to Git: $generated_file"
done
assert_not_ignored "$consumer_dir" ".codegeist/compose.local.yml"
assert_not_ignored "$consumer_dir" ".codegeist/Dockerfile"
assert_ignored_by_root_gitignore "$consumer_dir" ".codegeist/.local.env"
assert_ignored_by_root_gitignore "$consumer_dir" ".oc_local/.gitignore"

expected_hostname="$(expected_generated_hostname "$consumer_dir" "")"
expected_common_dir="$(expected_git_common_dir "$consumer_dir")"
expected_user_name="$(expected_container_user)"
for expected in \
  "DEVCONTAINER_REPO_ROOT=$consumer_dir" \
  "DEVCONTAINER_GIT_COMMON_DIR=$expected_common_dir" \
  "DEVCONTAINER_WORKSPACE_FOLDER=$consumer_dir"; do
  grep -Fx "$expected" "$consumer_dir/.devcontainer/.env" >/dev/null \
    || fail "submodule consumer environment is missing: $expected"
done

docker exec -w "$consumer_dir" -u "$expected_user_name" "$container_id" bash -lc '
  set -euo pipefail
  test "$PWD" = "'"$consumer_dir"'"
  test "$(hostname)" = "'"$expected_hostname"'"
  test "$(git rev-parse --show-toplevel)" = "'"$consumer_dir"'"
  test "$(git -C .devcontainer rev-parse HEAD)" = "'"$recorded_gitlink"'"
  test "$DEVCONTAINER_WORKSPACE_FOLDER" = "'"$consumer_dir"'"
  docker ps >/dev/null
'

pass "current checkout consumes the recorded devcontainer submodule directly"
