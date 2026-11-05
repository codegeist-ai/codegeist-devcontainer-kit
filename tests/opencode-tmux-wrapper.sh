#!/usr/bin/env bash
# opencode-tmux-wrapper.sh - control real tmux sessions started by the oc wrapper
#
# Why this exists:
# - The wrapper must preserve its working directory and argument boundaries.
# - An isolated tmux server proves sessions and windows can be controlled from
#   outside without touching the user's tmux state.
# - OpenCode's OSC 52 copy path requires tmux to accept application-originated
#   clipboard updates and forward OpenTUI's tmux DCS-wrapped clipboard writes.
#   Capture the attached client's PTY output: passthrough bypasses tmux buffers.
# - The same wrapper must register both microphone recorder shortcuts.
# - Both paths use the same container proxy, which survives pane closure.
#   Their *.capture.proxy files feed opencode-http.py in docker-build.sh.
#   OpenCode capture isolates argv/OSC 52 behavior; real
#   HTTP/TLS/streaming and OpenCode traffic are covered in opencode-http.py.
# - Real OpenCode 2 TUI launches use isolated user state and an OS-temp cwd so
#   ancestor configuration discovery cannot load the mounted source checkout.
#
# Related files:
# - ../cmds/oc
# - ../Taskfile.yaml
# - ./docker-build.sh
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
expected_file="$fixture_dir/opencode.expected"
expected_clipboard="oc clipboard test"
expected_passthrough=$'\033]52;c;b2MgcGFzc3Rocm91Z2ggdGVzdA==\033\\'
attached_pid=""
native_dir=""
original_path="$PATH"

[ "$(command -v oc)" = "/usr/local/bin/oc" ] \
  || fail "oc is not installed globally at /usr/local/bin/oc"

wait_for_check "OpenCode proxy" bash -ec '
  test -s "$DEVCONTAINER_WORKSPACE_TMP/opencode-http/mitmproxy-ca-cert.pem"
  nc -z -w 1 127.0.0.1 18080
'

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
         "NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE", "CURL_CA_BUNDLE", "REQUESTS_CA_BUNDLE", "GIT_SSL_CAINFO", "OC_RUN_ID")
Path(os.environ["OPENCODE_CAPTURE"] + ".proxy").write_text(
    json.dumps({name: os.environ[name] for name in names}))
PY

{
  printf 'PWD=%s\n' "$PWD"
  printf 'SHELL=%s\n' "$SHELL"
  printf 'WORKSPACE_TMP=%s\n' "$DEVCONTAINER_WORKSPACE_TMP"
  printf 'ARG=%s\n' "$@"
} >"$OPENCODE_CAPTURE"

printf '\033]52;c;b2MgY2xpcGJvYXJkIHRlc3Q=\a'
# OpenTUI 0.8.0 wraps OSC 52 in DCS tmux passthrough with doubled escapes.
# Use a distinct payload so the ordinary OSC 52 above cannot satisfy this check.
printf '\033Ptmux;\033\033]52;c;b2MgcGFzc3Rocm91Z2ggdGVzdA==\033\033\\\033\\'
exec sleep 30
EOF
chmod +x "$fake_bin/opencode"

cat >"$expected_file" <<EOF
PWD=$fixture_dir
SHELL=/usr/local/lib/oc-shell/bash
WORKSPACE_TMP=$DEVCONTAINER_WORKSPACE_TMP
ARG=--standalone
ARG=--auto
ARG=-c
ARG=--prompt
ARG=review this change
ARG=project path
EOF

assert_clipboard() {
  [ "$(tmux_cmd show-options -s -v set-clipboard)" = "on" ] \
    || fail "oc did not enable application clipboard updates"
  [ "$(tmux_cmd show-buffer)" = "$expected_clipboard" ] \
    || fail "tmux did not accept OpenCode's OSC 52 clipboard update"
  wait_for_check "tmux OSC 52 passthrough to the outer terminal" \
    grep -Fq -- "$expected_passthrough" "$1.terminal"
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
  wait_for_check "OpenCode proxy environment" test -s "$1.proxy"
  python3 - "$1.proxy" <<'PY'
import json
from pathlib import Path
import socket
import sys
import uuid
from urllib.parse import urlsplit
state = json.loads(Path(sys.argv[1]).read_text())
endpoint = urlsplit(state["HTTPS_PROXY"])
assert (endpoint.scheme, endpoint.hostname, endpoint.port) == ("http", "127.0.0.1", 18080), state
assert str(uuid.UUID(state["OC_RUN_ID"])) == state["OC_RUN_ID"]
assert endpoint.username == "oc-run-" + state["OC_RUN_ID"] and endpoint.password == "observe", state
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

# Reap the attached PTY client before reusing the isolated server's socket.
stop_tmux() {
  tmux_cmd kill-server
  if [ -n "$attached_pid" ]; then
    wait "$attached_pid" 2>/dev/null || true
    attached_pid=""
  fi
}

cleanup() {
  stop_tmux >/dev/null 2>&1 || true
  rm -rf "$tmux_tmp_dir"
  [ -z "$native_dir" ] || rm -rf "$native_dir"

  if [ "$owns_suite" -eq 1 ]; then
    cleanup_suite
  fi
}

trap cleanup EXIT
export NO_PROXY=existing-bypass.test
export PATH="$fake_bin:$original_path"

# Both launch paths must produce the same invocation and environment. Only the
# startup differs: outside creates a session, inside adds to a control window.
for context in outside inside; do
  log "checking oc invocation $context tmux"
  export OPENCODE_CAPTURE="$fixture_dir/$context.capture"
  if [ "$context" = outside ]; then
    (
      cd "$fixture_dir"
      env -u TMUX TERM=xterm-256color TMUX_TMPDIR="$tmux_tmp_dir" \
        script -qec 'exec oc --prompt "review this change" "project path"' /dev/null \
        >"$OPENCODE_CAPTURE.terminal" 2>&1
    ) &
    attached_pid="$!"
    expected_windows=1
  else
    tmux_cmd new-session -d -s wrapper-test -c "$fixture_dir" sleep 30
    # Passthrough requires a visible pane, so attach before launching oc.
    env -u TMUX TMUX_TMPDIR="$tmux_tmp_dir" TERM=xterm-256color \
      script -qec 'exec tmux attach-session -t wrapper-test' /dev/null \
      >"$OPENCODE_CAPTURE.terminal" 2>&1 &
    attached_pid="$!"
    wait_for_check "attached tmux client" env -u TMUX TMUX_TMPDIR="$tmux_tmp_dir" \
      bash -ec 'test -n "$(tmux list-clients -t wrapper-test)"'
    tmux_cmd new-window -d -t wrapper-test -c "$fixture_dir" \
      oc --prompt "review this change" "project path"
    expected_windows=2
  fi

  wait_for_check "OpenCode invocation ($context tmux)" \
    diff -u "$expected_file" "$OPENCODE_CAPTURE"
  [ "$(tmux_cmd list-sessions -F '#{session_name}' | wc -l)" -eq 1 ] \
    || fail "oc did not preserve exactly one tmux session ($context)"
  TMUX="" TMUX_TMPDIR="$tmux_tmp_dir" wait_for_check "tmux windows ($context)" bash -ec '
    count="$(tmux list-windows -F "#{window_id}" | wc -l)"
    [ "$count" -eq "$1" ] || { printf "expected=%s actual=%s\n" "$1" "$count"; exit 1; }
  ' _ "$expected_windows"
  assert_clipboard "$OPENCODE_CAPTURE"
  assert_recorder_bindings
  assert_proxy "$OPENCODE_CAPTURE"
  stop_tmux
  nc -z -w 2 127.0.0.1 18080 || fail "closing $context tmux stopped the shared proxy"
done
jq -e -s '.[0].OC_RUN_ID != .[1].OC_RUN_ID' \
  "$fixture_dir"/{outside,inside}.capture.proxy >/dev/null \
  || fail "independent oc invocations reused a run identity"

# Exercise the public launcher with the actual binary, not the argument capture.
# No prompt is submitted and no account credentials enter these two TUI sessions.
# tmux also forwards its client's PATH when creating the nested window.
PATH="$original_path"
native_dir="$(mktemp -d /tmp/oc-native-tui.XXXXXX)"
native_env=(env -i
  "PATH=$original_path" "HOME=$native_dir/home" TERM=xterm-256color
  "TMUX_TMPDIR=$tmux_tmp_dir"
  "OPENCODE_CONFIG_DIR=$native_dir/.oc_local"
  "DEVCONTAINER_WORKSPACE_FOLDER=$native_dir"
  "DEVCONTAINER_WORKSPACE_TMP=$DEVCONTAINER_WORKSPACE_TMP"
)
mkdir -p "$native_dir/.oc_local"
cp "$project_root/.oc_local.opencode.json.example" "$native_dir/.oc_local/opencode.json"
for context in outside inside; do
  if [ "$context" = outside ]; then
    (
      cd "$native_dir"
      "${native_env[@]}" script -qec 'stty cols 120 rows 35 && exec oc' /dev/null >/dev/null 2>&1
    ) &
    attached_pid="$!"
  else
    "${native_env[@]}" tmux new-session -d -s native-test -x 120 -y 35 -c "$native_dir" sleep 60
    tmux_cmd new-window -d -t native-test -c "$native_dir" oc
  fi

  # docker-build.sh checks the version; this waits for an interactive TUI.
  TMUX="" TMUX_TMPDIR="$tmux_tmp_dir" wait_for_check "OpenCode 2 TUI ($context tmux)" bash -ec '
    screen="$(tmux capture-pane -p)"
    [[ "$screen" == *"Ask anything"* && "$screen" == *"Build auto"* ]] \
      || { tmux list-panes -a -F "#{session_name}:#{window_index} #{pane_id} #{pane_current_command}"; printf "%s\n" "$screen"; exit 1; }
  '
  stop_tmux
done

pass "oc starts real OpenCode 2 inside/outside tmux and preserves arguments, clipboard, recording, and proxy settings"
