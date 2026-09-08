#!/usr/bin/env bash
# opencode-tmux-wrapper.sh - control real tmux sessions started by the oc wrapper
#
# Why this exists:
# - The wrapper must preserve its working directory and argument boundaries.
# - An isolated tmux server proves sessions and windows can be controlled from
#   outside without touching the user's tmux state.
#
# Related files:
# - ../cmds/oc
# - ../Taskfile.yaml
# - ./helpers.sh

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0")")"

# shellcheck source=./helpers.sh
source "$script_dir/helpers.sh"

owns_suite=0
if [ -z "${suite_tmp_dir:-}" ]; then
  setup_suite
  owns_suite=1
fi

fixture_dir="$suite_tmp_dir/opencode-tmux-wrapper"
fake_bin="$fixture_dir/bin"
tmux_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/oc-tmux.XXXXXX")"
outside_capture="$fixture_dir/outside.capture"
inside_capture="$fixture_dir/inside.capture"
expected_file="$fixture_dir/opencode.expected"
launcher="$fixture_dir/launch-oc"
attached_pid=""

[ "$(command -v oc)" = "/usr/local/bin/oc" ] \
  || fail "oc is not installed globally at /usr/local/bin/oc"

mkdir -p "$fake_bin"
chmod 700 "$tmux_tmp_dir"

cat >"$fake_bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'PWD=%s\n' "$PWD"
  printf 'ARG=%s\n' "$@"
} >"$OPENCODE_CAPTURE"

exec sleep 30
EOF
chmod +x "$fake_bin/opencode"

cat >"$launcher" <<EOF
#!/usr/bin/env bash
exec oc --model provider/model "project path"
EOF
chmod +x "$launcher"

assert_capture() {
  local capture_file="$1"

  cat >"$expected_file" <<EOF
PWD=$fixture_dir
ARG=--auto
ARG=-c
ARG=--model
ARG=provider/model
ARG=project path
EOF

  diff -u "$expected_file" "$capture_file" \
    || fail "oc did not preserve its OpenCode invocation"
}

tmux_cmd() {
  TMUX="" TMUX_TMPDIR="$tmux_tmp_dir" tmux "$@"
}

wait_for_file() {
  local file="$1"

  for _ in {1..50}; do
    [ -s "$file" ] && return
    sleep 0.1
  done

  fail "timed out waiting for $file"
}

cleanup() {
  tmux_cmd kill-server >/dev/null 2>&1 || true
  rm -rf "$tmux_tmp_dir"

  if [ -n "$attached_pid" ]; then
    wait "$attached_pid" 2>/dev/null || true
  fi

  if [ "$owns_suite" -eq 1 ]; then
    cleanup_suite
  fi
}

trap cleanup EXIT

# Outside tmux, `oc` attaches to a new session. `script` supplies the PTY while
# this test controls the isolated server through separate tmux client commands.
(
  cd "$fixture_dir"
  env -u TMUX \
    PATH="$fake_bin:$PATH" \
    OPENCODE_CAPTURE="$outside_capture" \
    TERM=xterm-256color \
    TMUX_TMPDIR="$tmux_tmp_dir" \
    OC_TEST_LAUNCHER="$launcher" \
    script -qec 'exec "$OC_TEST_LAUNCHER"' /dev/null >/dev/null 2>&1
) &
attached_pid="$!"

wait_for_file "$outside_capture"
[ "$(tmux_cmd list-sessions -F '#{session_name}' | wc -l)" -eq 1 ] \
  || fail "oc did not create exactly one tmux session"
assert_capture "$outside_capture"

tmux_cmd kill-server
wait "$attached_pid" 2>/dev/null || true
attached_pid=""

# A process launched in an existing session receives TMUX from the server. The
# wrapper should add one OpenCode window while the original control window stays.
PATH="$fake_bin:$PATH"
OPENCODE_CAPTURE="$inside_capture"
export PATH OPENCODE_CAPTURE
tmux_cmd new-session -d -s wrapper-test -c "$fixture_dir" sleep 30
tmux_cmd new-window -d -t wrapper-test -c "$fixture_dir" \
  oc --model provider/model "project path"

wait_for_file "$inside_capture"
for _ in {1..50}; do
  [ "$(tmux_cmd list-windows -t wrapper-test -F '#{window_id}' | wc -l)" -eq 2 ] \
    && break
  sleep 0.1
done
[ "$(tmux_cmd list-windows -t wrapper-test -F '#{window_id}' | wc -l)" -eq 2 ] \
  || fail "oc did not add exactly one window to the existing tmux session"
assert_capture "$inside_capture"

pass "oc creates controllable tmux sessions and windows with preserved arguments"
