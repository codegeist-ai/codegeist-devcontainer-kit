#!/usr/bin/env bash
# devcontainer-up.sh - verify the kit works through Dev Containers CLI
#
# Why this exists:
# - devcontainer up is the closest CLI smoke path for the VS Code workflow
# - assertions that need inner Docker run inside the workspace container
# - the image entrypoint alone starts services once per actual boot; reconnects
#   must not rerun it, and restarts must recover Docker and proxy without a system bus
#
# Related files:
# - ../devcontainer.json
# - ../Dockerfile.base
# - ../entrypoint.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

fixture_dir="$suite_tmp_dir/fixture-repo"
log_file="$suite_tmp_dir/devcontainer-up.log"
container_id=""
expected_hostname=""
expected_user="$(id -u):$(id -u)"
expected_user_name="$(expected_container_user)"
expected_workspace_folder=""
expected_remote_workspace_folder=""
opencode_output_file="$suite_tmp_dir/devcontainer-up-opencode.log"

cleanup_devcontainer() {
  local status="$?"
  if [ -n "$container_id" ]; then
    if [ "$status" -ne 0 ]; then
      docker logs "$container_id" >&2 || true
      docker exec "$container_id" cat /tmp/dockerd.log >&2 || true
    fi
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup_devcontainer EXIT

create_git_fixture_repo "$fixture_dir"
jq -e 'has("postStartCommand") | not' "$fixture_dir/.devcontainer/devcontainer.json" >/dev/null \
  || fail "runtime must use only the image entrypoint for service startup"
rm -rf "$fixture_dir/.codegeist" "$fixture_dir/.oc_local"

prepare_devcontainer_home "$fixture_dir"
HOME="$fixture_dir" devcontainer_cli up --workspace-folder "$fixture_dir" | tee "$log_file"

[[ ! -e "$fixture_dir/.codegeist/compose.local.yml" ]] || fail "initializeCommand created .codegeist/compose.local.yml without an on-demand override"
[[ ! -e "$fixture_dir/.codegeist/Dockerfile" ]] || fail "initializeCommand created .codegeist/Dockerfile without an on-demand extension"
[[ -f "$fixture_dir/.codegeist/.local.env" ]] || fail "initializeCommand did not create .codegeist/.local.env"
[[ -f "$fixture_dir/.devcontainer/.env" ]] || fail "initializeCommand did not create .devcontainer/.env"
[[ -f "$fixture_dir/.devcontainer/compose.local.gen.yml" ]] || fail "initializeCommand did not create .devcontainer/compose.local.gen.yml"
[[ -f "$fixture_dir/.devcontainer/compose.user.gen.yml" ]] || fail "initializeCommand did not create .devcontainer/compose.user.gen.yml"
expected_hostname="$(expected_generated_hostname "$fixture_dir" "")"
expected_workspace_folder="$(expected_workspace_folder "$fixture_dir")"
expected_remote_workspace_folder="$(expected_remote_workspace_folder "$fixture_dir")"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"hostname: $expected_hostname"* ]] || fail "generated compose file does not set expected hostname"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"\"$expected_hostname:127.0.0.1\""* ]] || fail "generated compose file does not resolve expected hostname"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"CONTAINER_USER: $expected_user_name"* ]] || fail "generated compose file does not set expected build user"
[[ "$(<"$fixture_dir/.devcontainer/compose.local.gen.yml")" == *"user: \"$expected_user\""* ]] || fail "generated compose file does not set expected user"
[[ "$(<"$fixture_dir/.devcontainer/.env")" == *"DEVCONTAINER_WORKSPACE_FOLDER=$expected_workspace_folder"* ]] || fail "generated env does not set expected workspace folder"
grep -Fx "DEVCONTAINER_WORKSPACE_TMP=$expected_workspace_folder/.tmp" "$fixture_dir/.devcontainer/.env" >/dev/null \
  || fail "generated env does not set expected workspace temporary path"

container_id="$(extract_container_id_from_log "$log_file" || true)"
[[ -n "$container_id" ]] || fail "could not extract workspace container id from devcontainer output"
[[ "$(extract_remote_workspace_folder_from_log "$log_file" || true)" = "$expected_remote_workspace_folder" ]] || fail "devcontainer up did not report expected remote workspace folder"

# This lifecycle test owns the combined service/singleton contract. Other tests
# wait only for the service they exercise, so an unrelated daemon cannot block them.
wait_for_services() {
  wait_for_check "Docker and proxy" docker exec -u "$expected_user_name" "$container_id" bash -ec '
    docker info >/dev/null
    test -s "$DEVCONTAINER_WORKSPACE_TMP/opencode-http/mitmproxy-ca-cert.pem"
    test "$(pgrep -cx mitmdump)" = 1
    nc -z -w 1 127.0.0.1 18080
  '
}
wait_for_services
docker exec -u "$expected_user_name" "$container_id" bash -lc '
  set -eu
  test "$(id -un)" = "'"$expected_user_name"'"
  test "$(hostname)" = "'"$expected_hostname"'"
  getent hosts "$(hostname)" >/dev/null
  test "$DEVCONTAINER_HOSTNAME" = "'"$expected_hostname"'"
  test "$DEVCONTAINER_USER" = "'"$expected_user_name"'"
  test "$DEVCONTAINER_UID:$DEVCONTAINER_GID" = "'"$expected_user"'"
  test "$DEVCONTAINER_WORKSPACE_TMP" = "'"$expected_workspace_folder"'/.tmp"
  case ":$PATH:" in
    *":$DEVCONTAINER_WORKSPACE_FOLDER/.devcontainer/scripts:"*) ;;
    *) exit 1 ;;
  esac
'

# Dev Containers exec must receive the same literal value as Docker exec.
actual_workspace_tmp="$(HOME="$fixture_dir" devcontainer_cli exec \
  --workspace-folder "$fixture_dir" --container-id "$container_id" \
  printenv DEVCONTAINER_WORKSPACE_TMP)"
[[ "$actual_workspace_tmp" = "$expected_workspace_folder/.tmp" ]] \
  || fail "devcontainer exec temporary path expected=$expected_workspace_folder/.tmp actual=$actual_workspace_tmp"

# The structured startup event survives exec and is counted across Docker
# restarts. Also reject the removed system service while allowing session buses.
assert_boot() {
  local expected="$1" actual=""
  actual="$(docker logs "$container_id" 2>&1 | grep -c '^level=info event=entrypoint status=starting$' || true)"
  [ "$actual" = "$expected" ] || fail "entrypoint starts expected=$expected actual=$actual"
  docker exec -u "$expected_user_name" "$container_id" bash -ec '
    test ! -S /run/dbus/system_bus_socket
    status=0
    pgrep -f "[d]bus-daemon .*--system([[:space:]]|$)" >/dev/null || status=$?
    test "$status" = 1
  ' || fail "workspace boot must not start system DBus"
}
assert_boot 1
first_started_at="$(docker inspect --format '{{.State.StartedAt}}' "$container_id")"
first_proxy_pid="$(docker exec "$container_id" pgrep -x mitmdump)"

docker exec -u "$expected_user_name" "$container_id" \
  podman run --rm docker.io/library/hello-world >/dev/null \
  || fail "workspace user could not run a hello-world container with Podman"

docker exec -u "$expected_user_name" "$container_id" bash -c '
  set -euo pipefail

  test -d "'"$expected_workspace_folder"'/.oc_local"
  test -w "'"$expected_workspace_folder"'/.oc_local"
  test -f "'"$expected_workspace_folder"'/.oc_local/.gitignore"
  test "$(command -v oc)" = "/usr/local/bin/oc"

  OPENCODE_CONFIG_DIR="'"$expected_workspace_folder"'/.oc_local" opencode --print-logs --log-level DEBUG debug startup
' >"$opencode_output_file" 2>&1

case "$(<"$opencode_output_file")" in
  *UnknownError*|*"tui bootstrap failed"*|*"FileSystem.writeFile ($expected_workspace_folder/.oc_local/.gitignore)"*)
    printf '%s\n' "$(<"$opencode_output_file")" >&2
    fail "OpenCode failed during devcontainer bootstrap"
    ;;
esac

HOME="$fixture_dir" devcontainer_cli up --workspace-folder "$fixture_dir" \
  >"$suite_tmp_dir/devcontainer-reconnect.log" 2>&1
[ "$(extract_container_id_from_log "$suite_tmp_dir/devcontainer-reconnect.log")" = "$container_id" ] \
  || fail "reconnect replaced the container"
[ "$(docker inspect --format '{{.State.StartedAt}}' "$container_id")" = "$first_started_at" ] \
  || fail "reconnect restarted the container"
[ "$(docker exec "$container_id" pgrep -x mitmdump)" = "$first_proxy_pid" ] \
  || fail "reconnect replaced the proxy"
assert_boot 1

docker stop --timeout 10 "$container_id" >/dev/null
HOME="$fixture_dir" devcontainer_cli up --workspace-folder "$fixture_dir" \
  >"$suite_tmp_dir/devcontainer-restart.log" 2>&1
[ "$(extract_container_id_from_log "$suite_tmp_dir/devcontainer-restart.log")" = "$container_id" ] \
  || fail "starting the stopped workspace replaced the container"
wait_for_services
assert_boot 2
restarted_at="$(docker inspect --format '{{.State.StartedAt}}' "$container_id")"
[ "$restarted_at" != "$first_started_at" ] || fail "stopped workspace was not restarted"

docker restart --timeout 10 "$container_id" >/dev/null
wait_for_services
assert_boot 3
[ "$(docker inspect --format '{{.State.StartedAt}}' "$container_id")" != "$restarted_at" ] \
  || fail "Docker restart did not start a new boot"
docker exec -u "$expected_user_name" "$container_id" curl --fail --silent --show-error --max-time 20 \
  --proxy http://127.0.0.1:18080 --noproxy '' \
  --cacert "$expected_workspace_folder/.tmp/opencode-http/mitmproxy-ca-cert.pem" \
  --output /dev/null https://example.com

pass "entrypoint starts once per boot, preserves running sessions, and restores services on restart"
