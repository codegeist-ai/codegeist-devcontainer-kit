# Add tmux Session Dashboard

- ID: `T040`
- Type: `feature`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `907d0ae1-e60b-445c-b306-22ebd06731be`

## Goal

Toggle from an OpenCode pane to a read-only tmux dashboard showing that run's
shell commands and HTTP activity, preferably using the installed Gum TUI tools.

## Context

The user explicitly selected an **OpenCode run per pane** as the session scope:
activity since that `oc` invocation started, including any conversations opened
or switched within it. It is not a conversation-specific view or an aggregate
of every OpenCode pane in the tmux session.

Existing `.tmp/opencode-shell.log` and `.tmp/opencode-http.jsonl` are workspace-wide.
Shell records contain startup metadata and arguments; HTTP records correlate
request starts and completions with `request_id`. Neither currently identifies
the originating OpenCode run. Reliable per-run attribution is part of this task.
Gum and tmux are already installed in the shared image.

## Scope

- Add a documented shortcut that toggles between the originating OpenCode pane
  and its dashboard window in the same tmux session. Proposed default:
  `Prefix + g` (`Ctrl+B`, then `g` with the default prefix).
- Create the dashboard window on first use and reuse it on subsequent toggles.
  Return to the exact originating pane; preserve OpenCode's input and process.
  Respect existing kit bindings and handle user binding conflicts explicitly.
- Provide a compact Gum-based interface with a run summary, command list, and
  HTTP/site list. Support navigation, filtering, record details, and refresh
  without restarting OpenCode or creating additional dashboard windows.
- Assign a stable run identifier once per `oc` invocation and propagate it to
  the relevant log producers. Attribute proxied traffic despite the shared
  proxy, concurrent runs, and connection reuse; do not infer ownership from a
  time window alone.
- Reuse the existing log streams and preserve their execution and privacy
  contracts. Keep legacy or unattributed records explicitly labeled and outside
  the default current-run view.
- Ship the dashboard command and helpers through the runtime allowlist and image,
  and update tests and source/consumer documentation.

Out of scope: conversation-level tracking, a web dashboard, new monitoring
daemons, full operating-system process auditing, command replay/execution,
permission enforcement, and collecting HTTP bodies, headers, or query strings.

## Dashboard Content

- **Run summary:** run identifier, originating tmux session/window/pane, workspace
  path, start time, last refresh, and clearly labeled activity counts.
- **Commands:** timestamp, working directory, and recorded command/arguments,
  with a readable detail view for long or multiline entries. These are recorded
  shell starts, not proof of successful completion or a list of every child
  executable. Do not invent exit codes, output, or durations absent from the log.
- **HTTP/sites:** timestamp, method, host, path, status/error, and duration.
  Merge start and terminal events into one row per `request_id`, show pending
  requests honestly, and count requests rather than JSONL lines. All attributed
  traffic remains discoverable, including model calls and package downloads.

## Acceptance Criteria

- The shortcut works for `oc` started outside tmux and inside an existing session.
  Repeated toggles reuse one dashboard for the run and restore its original pane.
- Two simultaneous OpenCode runs in the same workspace have distinct identities
  and correctly separated command/HTTP views. Restarting an invocation creates a
  new run; switching conversations within that invocation keeps its run identity.
- New commands and HTTP completions appear after refresh. Filtering and details
  remain usable with long records and a bounded initial view of large logs.
- Missing/empty logs, partially appended final records, unavailable attribution,
  and a closed origin pane produce understandable states without affecting the
  OpenCode process or jumping to an unrelated pane.
- The viewer treats log contents as inert data: no `eval`, command replay, or
  execution of terminal control sequences from recorded text. Dashboard refresh
  operations are not misrepresented as agent activity.
- Command logging retains argument boundaries, cwd, exit-status behavior, and
  its existing logging-failure contract. HTTP logging retains streaming and
  metadata-only collection. Any internal correlation marker is not forwarded
  to external servers or treated as an authorization credential.
- UI state remains disposable and project-local under the established workspace
  temporary path. Existing logs are not deleted or silently rewritten by opening
  the dashboard; existing private file permissions are preserved.
- Documentation explains the shortcut, per-run scope, refresh/navigation,
  sensitive command arguments, and limitations of shell/proxy log coverage.

## Verification

- Use real tmux and Gum in isolated PTY-backed fixtures to test first opening,
  toggling back, reuse, origin closure, and preservation of existing bindings.
- Generate actual shell-log entries and HTTP/proxy requests from two independent
  run contexts; prove attribution, isolation, one-row-per-request counting, and
  pending/error updates. Verify an actual OpenCode invocation receives its context.
- Verify legacy/unattributed and incomplete records, quoted/multiline commands,
  and control-character text are displayed safely without executing their content.
- Check runtime packaging, run `task check`, affected integration tests,
  `task tests-run`, and `git --no-pager diff --check`.

## File Targets

- `cmds/oc` and a focused dashboard command under `cmds/`
- `scripts/opencode-bash.sh`, `scripts/opencode-http-log.py`
- `Dockerfile.base`, `scripts/stage-runtime-tree.sh`, `tests/release-build.sh`
- `tests/opencode-tmux-wrapper.sh`, `tests/opencode-bash.sh`, `tests/opencode-http.py`
- `README.md`, `README_release.md`

## Dependencies

- [T006](T006_add_terminal_productivity_tools.md): installed Gum toolkit.
- [T009](T009_add_tmux_opencode_wrapper.md): `oc`/tmux launch behavior.
- [T028](T028_log_opencode_shell_starts.md): shell-start log.
- [T034](T034_log_opencode_http_requests.md): shared HTTP metadata log.

## Blockers

None at specification time. Reliable per-run HTTP attribution must be verified
as part of implementation; a workspace-wide log view is not an equivalent result.

## Implementation Notes

Prefer Gum's existing table, filter, chooser, style, and pager primitives with
a small parser/controller over a custom TUI framework. Keep refresh bounded and
responsive; avoid rescanning unbounded logs continuously or blocking log writers.
Run identity is an observability mechanism, not an access-control boundary.

Use the temporary-path contract from [T036](T036_expose_workspace_tmp_variable.md)
when available. Coordinate shared `oc`, tmux, and proxy changes with
[T038](T038_restrict_opencode_outbound_ports.md), preserving its enforcement scope
without turning this dashboard into a security-policy implementation.

## Cancellation Reason

Not cancelled.
