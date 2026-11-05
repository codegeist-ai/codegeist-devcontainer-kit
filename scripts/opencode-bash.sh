#!/bin/bash
# opencode-bash.sh - log each shell start, then execute the real Bash.
#
# Inputs: DEVCONTAINER_WORKSPACE_TMP, optional OC_RUN_ID, unchanged shell arguments.
# Appends metadata and full shell arguments to the existing workspace .tmp directory;
# arguments may contain sensitive values. Logging failure
# aborts execution. Install as "bash" to preserve OpenCode's shell selection.
# Related files: cmds/oc, Dockerfile.base, README.md#opencode-in-tmux.

log_file="${DEVCONTAINER_WORKSPACE_TMP:?DEVCONTAINER_WORKSPACE_TMP must be set}/opencode-shell.log"

# Restrict new log files without changing the executed command's umask.
(
  umask 077
  # Serialize writers so long records from parallel runs cannot interleave.
  # The dashboard reads without taking this lock.
  exec 9>>"$log_file" || exit 1
  flock -x 9 || exit 1
  {
    printf \
      'time=%(%Y-%m-%dT%H:%M:%S%z)T event=shell_start pid=%s ppid=%s run_id=%q cwd=%q argv=' \
      -1 "$$" "$PPID" "${OC_RUN_ID:-unattributed}" "$PWD"
    printf ' %q' "$@"
    printf '\n'
  } >&9
) || exit 1

export SHELL=/bin/bash
exec /bin/bash "$@"
