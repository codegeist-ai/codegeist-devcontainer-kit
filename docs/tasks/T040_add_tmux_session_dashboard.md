# Add tmux Session Dashboard

- ID: `T040`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `907d0ae1-e60b-445c-b306-22ebd06731be`

## Goal

Focus an adjacent Gum dashboard pane with Prefix + g and its originating OpenCode
pane with Prefix + o. Open each selected shared log directly in Ubuntu's lnav for
live following, scrolling, searching, and readable HTTP metadata.

## Context

On 2026-11-03 the user requested simple raw log display with `tail`, a Gum log
chooser in a normal pane, and separate g/o shortcuts. The chooser must have no
Return to OpenCode entry. The shared workspace logs include other runs and
unattributed entries; existing per-invocation run IDs remain in the producers.
Follow-up requests add bat/jq presentation and scrolling of HTTP JSON while
retaining simple live logs. On 2026-11-04 the user selected lnav from Ubuntu's
official repositories to replace those reader/pager pipelines. Viewer state must
remain under workspace temporary storage, never the user's home directory.

## Scope

- Prefix + g opens/focuses a reusable right-hand dashboard pane in the same window;
  Prefix + o focuses its exact OpenCode origin. Preserve custom bindings, replacing
  only tmux's standard o next-pane binding, and keep the process/draft intact.
- The Gum chooser contains only Shell log and HTTP log. Open the selected
  `.tmp/opencode-shell.log` or `.tmp/opencode-http.jsonl` directly in lnav.
  Load the complete file, reset saved filters, and start at the live end with
  wrapping. Scrolling pauses following; G resumes. q from the main view or
  Ctrl+C returns to the chooser.
- Install Ubuntu's lnav package and the HTTP format in `scripts/lnav-formats.json`.
  Keep lnav configuration, history, and work files under private `.tmp/oc-dashboard/`
  state, including when the user's home already has `.lnav` or XDG configuration.
- Use Bash and tmux for registration and navigation. Keep navigation state and
  the first-open lock in tmux, without dashboard metadata files.
- Preserve shell execution, private log permissions, HTTP streaming, and
  metadata-only logging. Retain the per-run proxy marker and shell `run_id`.
- Update runtime packaging, source/consumer documentation, and actual PTY tests.

Out of scope: a Return to OpenCode menu entry, application-specific record analysis,
counts, automatic run filtering, request aggregation, custom pagers, log replay,
and changes to log collection coverage. Native interactive lnav tools remain available.

## Acceptance Criteria

- The shortcuts work for `oc` started outside tmux and inside an existing session.
  Repeated g/o navigation reuses the same two panes without creating a new window.
- Both log choices preserve all recorded fields, including entries from multiple
  runs and unattributed entries. Shell logs retain their Bash quoting; HTTP
  start/end events appear separately with colored summaries and indented metadata.
- Newly appended shell and HTTP records appear without a refresh action.
- Both logs can be scrolled backward/forward with arrows and PageUp/PageDown and
  searched with /. G resumes live following, including records received while
  scrolled back. q returns from the main view to Gum and stops lnav promptly,
  even when the log is idle. Closing the pane also cleans up its viewer processes.
- Shell Ctrl+C returns to the two-choice Gum menu in the same pane.
  Closing the dashboard does not close OpenCode; a later Prefix + g recreates
  it. Closing the origin leaves the dashboard readable and Prefix + o reports that
  state instead of selecting an unrelated pane.
- Missing files use lnav's file-panel diagnostic and appear automatically when
  created by a producer. Replacements are followed by name. Opening the viewer
  does not create, truncate, rewrite, or change permissions on logs.
- Viewer configuration/history/work files remain under `.tmp/oc-dashboard/`,
  whose mode is `0700`; existing user-home/XDG lnav state remains untouched.
- Navigation is not logged as agent shell activity. Producer-side Bash/JSON
  quoting remains intact; the viewer never evaluates command text.
- Run IDs stay stable across conversations within one invocation and distinct
  across invocations. HTTP markers are consumed before forwarding to origins.
- Source and consumer docs describe the shared-log scope, shortcut, live follow,
  scrollback, closure/reopen, and existing logging limitations.

## Verification

- `tests/opencode-dashboard.py` drives real OpenCode and tmux through an attached
  PTY. Generate actual shell records and local proxy requests; verify colored shell
  output and indented HTTP metadata, automatic updates, scroll/search/resume/quit,
  idle-viewer cleanup, missing/replaced file handling, workspace-only viewer state,
  Gum selection, g/o key conflicts, pane reuse/reopen,
  absence of a new window or Return to OpenCode menu item, origin closure, and
  preservation of input, process identity, clipboard, log content, and permissions.
- `tests/opencode-bash.sh`, `tests/opencode-tmux-wrapper.sh`, and
  `tests/opencode-http.py` retain producer and parallel run-attribution coverage.
- Run `task check`, `task tests-run`, and `git --no-pager diff --check`.

### Prior Pipeline Results — 2026-11-03

- The installed-command PTY fixture passed with real OpenCode, Gum, tmux, tail,
  bat, jq, and less: colored shell output, colored/indented HTTP JSON, live follow,
  pause/search/PageUp/PageDown/resume, q back to Gum, and complete reader cleanup
  after quit or pane closure while the log is idle. Separate g/o focus, pane
  reuse/reopen, custom bindings, the draft/process/clipboard, log content and
  permissions, and closed-origin handling also passed.
- `task check`, changed Python test syntax, matching source/consumer log-view
  documentation, and `git --no-pager diff --check` passed.
- The first full-suite run encountered an unmatched HTTP record at its immediate
  log snapshot. The HTTP fixture now waits up to ten seconds for every observed
  start/terminal pair, retaining all records and reporting unmatched metadata on
  timeout.
- `task tests-run` passed the complete suite in 109 seconds, including installed
  OpenCode 2.2.5/Gum/bat/jq/less navigation, parallel shell/HTTP run attribution,
  Docker and Dev Containers lifecycle, browser/X11, QEMU KVM, and submodule consumers.
- The advisory image scan at that stage reported 309 HIGH and 16 CRITICAL findings;
  248 findings list a dependency fix. Details remain in
  `.tmp/image-cve-scan/report.json`; these counts do not establish availability
  of compatible upstream tool releases containing those fixes.
- Changes remain uncommitted.

### lnav Follow-up — 2026-11-04

- Ubuntu 26.04 installs lnav 0.13.2 from `universe`.
- Targeted real PTY verification passed: both formatted live logs, search and
  PageUp/PageDown/G navigation, q/Ctrl+C, idle/pane-close cleanup, missing and
  rotated files, preserved origin input/process/clipboard, and private workspace
  state despite an existing user `.lnav` and XDG directory.
- `tests/docker-build.sh` passed with the installed image. Its preceding real
  shell/proxy tests also passed. Pane closure is covered with a non-reaping PID 1:
  the controller waits asynchronously and reaps lnav before exiting.
- `task check` passed, including shell syntax and the source-to-release contract
  with the new lnav format. Python/JSON syntax, matching source/consumer log-view
  documentation, and `git --no-pager diff --check` also passed.
- `task tests-run` passed the complete suite in 128 seconds, including installed
  OpenCode/Gum/lnav navigation, shell/HTTP logging, clipboard passthrough,
  Docker/Dev Containers lifecycle, browser/X11, QEMU KVM, and submodule consumers.
- The advisory image scan completed with 309 HIGH and 16 CRITICAL findings;
  248 findings list a dependency fix. The report is
  `.tmp/image-cve-scan/report.json`; those counts do not establish availability
  of compatible upstream tool releases containing the fixes.
- At this verification point, changes were uncommitted and unpublished, and the
  existing Git index was preserved. The consumed `.devcontainer` release did not
  yet contain the lnav integration.

### Wrapper Test Simplification — 2026-11-05

- Simplified `tests/opencode-tmux-wrapper.sh` from 293 to 254 lines with shared
  inside/outside assertions, the suite's bounded readiness helper, and common
  tmux/PTY cleanup. Its proxy captures still feed the real HTTP integration test.
- `task check`, `git --no-pager diff --check`, and the complete `task tests-run`
  suite passed; the full suite took 130 seconds and included real OpenCode TUI,
  clipboard passthrough, proxy attribution, and Gum/lnav dashboard checks.

## File Targets

- `cmds/oc`, `cmds/oc-dashboard`
- `scripts/opencode-bash.sh`, `scripts/opencode-http-log.py`, `scripts/lnav-formats.json`
- `Dockerfile.base`, `scripts/stage-runtime-tree.sh`, `tests/release-build.sh`
- `tests/opencode-tmux-wrapper.sh`, `tests/opencode-bash.sh`, `tests/opencode-http.py`,
  `tests/opencode-dashboard.py`, `tests/docker-build.sh`
- `README.md`, `README_release.md`, `.oc_local/rules/devcontainer-kit.md`

## Dependencies

- [T006](T006_add_terminal_productivity_tools.md): installed Gum toolkit.
- [T009](T009_add_tmux_opencode_wrapper.md): `oc`/tmux launch behavior.
- [T028](T028_log_opencode_shell_starts.md): shell-start log.
- [T034](T034_log_opencode_http_requests.md): shared HTTP metadata log.
- [T036](T036_expose_workspace_tmp_variable.md): workspace temporary path.

## Blockers

None; targeted, source-to-release, and full integration verification passed.

## Implementation Notes

- `cmds/oc-dashboard start` records the origin pane and log directory in tmux
  pane options, installs g/o when available, and directly execs OpenCode.
- `show` uses a tmux `wait-for` lock to serialize the first split; `origin` selects
  the exact original pane. Shell-quoted tmux formats preserve session IDs such as `$0`.
  Diagnostics use the tmux status line to preserve the origin's screen and input.
- `view` uses `gum choose` for two log choices and runs lnav directly on an exact
  filename glob, so missing/replaced logs are watched without opening other logs.
  Shell text uses native logfmt highlighting. The installed HTTP format prevents
  lnav's built-in PCAP detector from misidentifying JSONL and hiding its fields;
  the path and extra metadata occupy their own indented lines for narrow panes.
- The controller scopes HOME, XDG_CONFIG_HOME, and TMPDIR to `.tmp/oc-dashboard/`
  with private permissions. HOME is required because lnav 0.13 prefers an existing
  `.lnav` over XDG. Startup resets saved filters and restores the live position and
  wrapping. lnav 0.13 restores view state after startup commands, so the controller
  saves and reloads those settings before its late restore.
- Bash waits for lnav asynchronously with explicit TTY input, so pane-close
  signals can stop and reap the viewer even under a non-reaping container PID 1.
  Quitting normally also reaps it before returning to Gum.
- `cmds/oc` assigns one UUID per invocation. The proxy consumes its non-secret
  `oc-run-<UUID>:observe` marker from `Proxy-Authorization`, attributing HTTPS by
  client CONNECT connection rather than pooled upstream connections. Shell
  writers use `flock` to prevent interleaved records; readers do not lock writers.

## Cancellation Reason

Not cancelled.
