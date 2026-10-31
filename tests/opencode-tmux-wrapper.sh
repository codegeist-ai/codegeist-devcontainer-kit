#!/usr/bin/env bash
# opencode-tmux-wrapper.sh - control real tmux sessions started by the oc wrapper
#
# Why this exists:
# - The wrapper must preserve its working directory and argument boundaries.
# - An isolated tmux server proves sessions and windows can be controlled from
#   outside without touching the user's tmux state.
# - OpenCode's OSC 52 copy path requires tmux to accept application-originated
#   clipboard updates instead of its default external-only behavior.
# - The same wrapper must register both microphone recorder shortcuts.
# - Both paths use the same container proxy, which survives pane closure.
#   OpenCode capture isolates argv/OSC 52 behavior; real
#   HTTP/TLS/streaming and OpenCode traffic are covered in opencode-http.py.
# - Repeated entrypoint calls (the Dev Containers postStart path) reuse it too.
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
expected_clipboard="oc clipboard test"
attached_pid=""

[ "$(command -v oc)" = "/usr/local/bin/oc" ] \
  || fail "oc is not installed globally at /usr/local/bin/oc"

proxy_pid="$(pgrep -x mitmdump)"
/usr/local/bin/devcontainer-entrypoint true
[ "$(pgrep -x mitmdump)" = "$proxy_pid" ] || fail "postStart replaced the shared proxy"

mkdir -p "$fake_bin"
chmod 700 "$tmux_tmp_dir"

cat >"$fake_bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import os
from pathlib import Path
names = ("HTTPS_PROXY", "HTTP_PROXY", "https_proxy", "http_proxy", "NO_PROXY", "no_proxy",
         "NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE", "CURL_CA_BUNDLE", "REQUESTS_CA_BUNDLE", "GIT_SSL_CAINFO")
Path(os.environ["OPENCODE_CAPTURE"] + ".proxy").write_text(
    json.dumps({name: os.environ[name] for name in names}))
PY

{
  printf 'PWD=%s\n' "$PWD"
  printf 'SHELL=%s\n' "$SHELL"
  printf 'ARG=%s\n' "$@"
} >"$OPENCODE_CAPTURE"

printf '\033]52;c;b2MgY2xpcGJvYXJkIHRlc3Q=\a'
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
SHELL=/usr/local/lib/oc-shell/bash
ARG=--auto
ARG=-c
ARG=--model
ARG=provider/model
ARG=project path
EOF

  diff -u "$expected_file" "$capture_file" \
    || fail "oc did not preserve its OpenCode invocation"
}

assert_clipboard() {
  [ "$(tmux_cmd show-options -s -v set-clipboard)" = "on" ] \
    || fail "oc did not enable application clipboard updates"
  [ "$(tmux_cmd show-buffer)" = "$expected_clipboard" ] \
    || fail "tmux did not accept OpenCode's OSC 52 clipboard update"
}

assert_recorder_bindings() {
  tmux_cmd list-keys -T prefix R \
    | grep -F 'oc-record \"#{pane_id}\"' >/dev/null \
    || fail "oc did not bind Prefix + R to the microphone recorder"
  tmux_cmd list-keys -T root M-r \
    | grep -F 'oc-record \"#{pane_id}\"' >/dev/null \
    || fail "oc did not bind Alt + R to the microphone recorder"
}

# Verify the actual pane environment, not just the launch command's text.
assert_proxy() {
  wait_for_file "$1.proxy"
  python3 - "$1.proxy" <<'PY'
import json
from pathlib import Path
import socket
import sys
from urllib.parse import urlsplit
state = json.loads(Path(sys.argv[1]).read_text())
endpoint = urlsplit(state["HTTPS_PROXY"])
assert state["HTTPS_PROXY"] == "http://127.0.0.1:18080", state
assert all(state[name] == state["HTTPS_PROXY"] for name in ("HTTP_PROXY", "https_proxy", "http_proxy"))
assert state["NO_PROXY"] == state["no_proxy"]
assert "localhost" in state["NO_PROXY"] and "127.0.0.1" in state["NO_PROXY"]
assert "existing-bypass.test" in state["NO_PROXY"], state
assert Path(state["NODE_EXTRA_CA_CERTS"]).is_file(), state
assert Path(state["NODE_EXTRA_CA_CERTS"]).name == "mitmproxy-ca-cert.pem", state
assert all(state[name] == state["NODE_EXTRA_CA_CERTS"] for name in
           ("SSL_CERT_FILE", "CURL_CA_BUNDLE", "REQUESTS_CA_BUNDLE", "GIT_SSL_CAINFO"))
with socket.create_connection((endpoint.hostname, endpoint.port), timeout=2):
    pass
PY
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
export NO_PROXY=existing-bypass.test

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
assert_clipboard
assert_recorder_bindings
assert_proxy "$outside_capture"

tmux_cmd kill-server
wait "$attached_pid" 2>/dev/null || true
attached_pid=""
assert_proxy "$outside_capture"

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
assert_clipboard
assert_recorder_bindings
assert_proxy "$inside_capture"
tmux_cmd kill-server
assert_proxy "$inside_capture"
cmp "$outside_capture.proxy" "$inside_capture.proxy" \
  || fail "oc panes did not share the container proxy and mitmproxy CA"

pass "oc preserves arguments, clipboard, and recording while sharing one container proxy"
