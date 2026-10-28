#!/bin/bash
# opencode-bash.sh - log each shell start, then execute the real Bash.
#
# Inputs: DEVCONTAINER_WORKSPACE_FOLDER and unchanged shell arguments.
# Appends metadata and full shell arguments to the existing workspace .tmp directory;
# arguments may contain sensitive values. Logging failure
# aborts execution. Install as "bash" to preserve OpenCode's shell selection.
# Related files: cmds/oc, Dockerfile.base, README.md#opencode-in-tmux.

log_file="${DEVCONTAINER_WORKSPACE_FOLDER:?DEVCONTAINER_WORKSPACE_FOLDER must be set}/.tmp/opencode-shell.log"

# Restrict new log files without changing the executed command's umask.
(
  umask 077
  {
    printf \
      'time=%(%Y-%m-%dT%H:%M:%S%z)T event=shell_start pid=%s ppid=%s cwd=%q argv=' \
      -1 "$$" "$PPID" "$PWD"
    printf ' %q' "$@"
    printf '\n'
  } >>"$log_file"
) || exit 1

export SHELL=/bin/bash
exec /bin/bash "$@"
