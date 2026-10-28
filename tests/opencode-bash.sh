#!/usr/bin/env bash
# opencode-bash.sh - verify mandatory metadata logging and transparent Bash exec.
# Uses a cleanup-trapped OS fixture, not the user's workspace log. Tests arguments,
# PID handoff, output/status, umask preservation, and failure before command start.
# Related files: scripts/opencode-bash.sh, tests/docker-build.sh.

set -euo pipefail
project_root="$(dirname "$(dirname "$(readlink -f "$0")")")"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/oc-shell-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/.tmp"
wrapper="${OC_SHELL_BIN:-$project_root/scripts/opencode-bash.sh}"
export DEVCONTAINER_WORKSPACE_FOLDER="$fixture"

# exec preserves the launched PID; the real Bash must retain argument boundaries
# and the caller's umask while the log itself is created with mode 0600.
umask 022
"$wrapper" -c 'printf "%s\n" "$$" "$SHELL" "$1"; umask; printf "diagnostic\n" >&2; exit 7' \
  opencode 'argument with spaces' >"$fixture/output" 2>"$fixture/error" &
pid="$!"
status=0
wait "$pid" || status="$?"
[[ "$status" = 7 ]]
printf '%s\n' "$pid" /bin/bash 'argument with spaces' 0022 >"$fixture/expected"
diff -u "$fixture/expected" "$fixture/output"
[[ "$(<"$fixture/error")" = diagnostic ]]
[[ "$(stat -c %a "$fixture/.tmp/opencode-shell.log")" = 600 ]]
[[ "$(wc -l <"$fixture/.tmp/opencode-shell.log")" = 1 ]]
grep -F "event=shell_start pid=$pid ppid=$$ cwd=" "$fixture/.tmp/opencode-shell.log" >/dev/null
printf -v expected_args ' %q' -c 'printf "%s\n" "$$" "$SHELL" "$1"; umask; printf "diagnostic\n" >&2; exit 7' \
  opencode 'argument with spaces'
grep -F "argv=$expected_args" "$fixture/.tmp/opencode-shell.log" >/dev/null
"$wrapper" -c ':'
[[ "$(wc -l <"$fixture/.tmp/opencode-shell.log")" = 2 ]]
# Multiline commands must remain a single record without losing their content.
command=$'printf "first\\n"\nprintf "second\\n"'
"$wrapper" -c "$command" >/dev/null
printf -v expected_args ' %q' -c "$command"
grep -F "argv=$expected_args" "$fixture/.tmp/opencode-shell.log" >/dev/null
[[ "$(wc -l <"$fixture/.tmp/opencode-shell.log")" = 3 ]]

# A nonexistent workspace log directory must prevent command side effects.
if DEVCONTAINER_WORKSPACE_FOLDER="$fixture/missing" "$wrapper" \
  -c 'touch "$1"' opencode "$fixture/unexpected" 2>"$fixture/failure"; then
  exit 1
fi
[[ ! -e "$fixture/unexpected" ]]
printf 'PASS: mandatory shell logging preserves Bash execution and rejects log failure\n'
