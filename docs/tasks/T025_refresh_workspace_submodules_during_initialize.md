# Refresh Workspace Submodules During Initialization

- ID: `T025`
- Type: `feature`
- Status: `planned`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `0be09a57-10a4-4eca-93c2-6e66db3858e1`

## Goal

Make each host-side `initialize.sh` run attempt to update the registered
`.devcontainer` and `.opencode` submodules to the latest commits on their
configured remote branches. Update failures must produce warnings and must not
prevent the existing initialization workflow from continuing.

When `.devcontainer` moves to a new commit, run the updated `initialize.sh`
immediately and at most once so generated runtime state uses the refreshed
implementation wherever the Dev Containers lifecycle permits it.

## Context

Consuming repositories pin `.devcontainer` and may also pin `.opencode` as Git
submodules. Their `.gitmodules` entries normally select the generated `release`
branches, but a normal submodule checkout remains at the commit recorded by the
parent repository until an explicit remote update occurs.

The requested workflow prioritizes automatically consuming the latest shared
release over preserving the parent repository's recorded gitlinks unchanged.
Successful refreshes will therefore leave `.devcontainer`, `.opencode`, or both
reported as modified gitlinks in the parent worktree until a user deliberately
records or discards that state.

Submodule checkouts commonly use detached `HEAD`, so plain `git pull` is not an
appropriate implementation. Use the registered submodule path, URL, and branch
configuration through `git submodule update --init --remote --recursive` or an
equivalent Git-native operation.

`initialize.sh` is itself stored under `.devcontainer`. VS Code must read the
existing `.devcontainer/devcontainer.json` before it can invoke
`initializeCommand`, so updating and rerunning the script cannot guarantee that
all configuration changes affect the already-started lifecycle. The refreshed
script and generated files can take effect immediately, but changes to
`devcontainer.json`, Compose selection, or other configuration already resolved
by the client may require another reopen or rebuild.

Automatically following a remote release branch also means that opening a
workspace may download and execute newly published shared code. This behavior
must remain limited to submodules explicitly registered by the consuming
repository and to their configured remote branches.

## Product Decisions

- Refresh `.opencode` and `.devcontainer` during every normal initializer run.
- Follow each submodule's branch configured in `.gitmodules`; do not hard-code a
  branch name in `initialize.sh`.
- Attempt updates even when a submodule worktree contains local changes. Let Git
  preserve compatible changes or reject conflicting updates normally.
- Never reset, clean, stash, force-checkout, or otherwise discard local state to
  make an update succeed.
- Treat each submodule independently. Failure to update one must not prevent an
  attempt to update the other.
- Report missing registrations, fetch failures, checkout conflicts, and similar
  refresh failures as warnings, then continue with the available checkout.
- If `.devcontainer` changes commit, invoke its refreshed `initialize.sh`
  immediately with a one-run guard that prevents recursive refresh loops.
- A failure in the refresh operation is warning-only. A normal initialization
  failure from the refreshed script remains a real lifecycle failure.
- Do not commit, stage, push, or otherwise record the changed parent gitlinks.

## Scope

In scope:

- Add a documented best-effort submodule refresh phase to `initialize.sh`.
- Detect whether `.devcontainer` and `.opencode` are registered submodules before
  attempting their updates so subtree consumers remain supported.
- Emit stable, structured start, success, skip, warning, and rerun diagnostics
  without exposing credentials or remote URLs.
- Compare the `.devcontainer` commit before and after refresh and rerun the new
  initializer once when it changed.
- Keep the existing checkout bootstrap, generated-file, display, extension, and
  custom-hook behavior unchanged after the refresh phase.
- Add deterministic tests backed by local Git repositories rather than network
  remotes.
- Document automatic updates, dirty parent gitlinks, warning-only failures, and
  the possible need for another VS Code reopen or rebuild.

Out of scope:

- Updating arbitrary submodules other than `.devcontainer` and `.opencode`.
- Creating commits for updated gitlinks or pushing any repository.
- Automatically restarting VS Code, rebuilding a container, or recursively
  invoking the Dev Containers CLI.
- Replacing Git's conflict handling with resets, stashes, retries, or custom
  merge behavior.
- Guaranteeing that a `devcontainer.json` change discovered after
  `initializeCommand` started applies to the same lifecycle invocation.
- Adding background update services, scheduled jobs, or persistent daemons.

## Acceptance Criteria

- A clean registered `.devcontainer` submodule advances to the latest commit on
  its configured remote branch during initialization.
- A clean registered `.opencode` submodule advances independently to the latest
  commit on its configured remote branch during initialization.
- The implementation uses submodule configuration and does not assume that a
  detached submodule checkout can run plain `git pull`.
- Dirty submodules are still attempted without destructive preparation. A Git
  rejection is logged as a warning and existing local changes remain intact.
- Failure, absence, or non-registration of one target does not stop the other
  target's refresh or the existing initializer behavior.
- Refresh warnings use a stable event name and identify the affected path and
  concise failure result without printing credentials or complete remote URLs.
- When `.devcontainer` changes commit, the refreshed `initialize.sh` runs exactly
  once and the original script does not duplicate the normal initialization
  side effects afterward.
- A refresh-loop guard prevents the refreshed initializer from fetching or
  rerunning itself again in the same lifecycle invocation.
- If no `.devcontainer` update occurs, normal initialization executes once with
  no rerun.
- Errors from the submodule refresh phase are warning-only, while unrelated
  required initialization failures keep their existing nonzero behavior.
- Successful updates leave parent gitlink changes visible to `git status` and do
  not stage, commit, or push them.
- Documentation states that configuration already read by VS Code may require a
  subsequent reopen or rebuild before the new devcontainer release is fully in
  use.
- Subtree installations, repositories without `.opencode`, linked worktrees,
  and repeated initializer runs remain supported.

## Implementation Plan

1. Add a warning logger and a small refresh function to `initialize.sh` that
   recognizes only exact registered paths from the root `.gitmodules` file.
2. Before normal generated-state work, record the current `.devcontainer`
   commit and attempt independent remote recursive updates for `.opencode` and
   `.devcontainer`.
3. Capture each failed Git operation in a structured warning and continue
   without mutating or cleaning local changes manually.
4. Compare the resulting `.devcontainer` commit with the recorded commit. When
   it changed and the rerun guard is absent, invoke the refreshed script with the
   guard set and return its normal initialization result.
5. Skip the refresh phase when the guard is present so the refreshed script
   performs the existing initialization exactly once.
6. Add local-remote fixtures covering success, independent failure, dirty
   submodules, absent registration, unchanged commits, and one-time refreshed
   script execution.
7. Update source and release documentation plus the local devcontainer rule to
   describe the automatic update and dirty-gitlink contract.
8. Run focused initializer and submodule tests, `task check`, and the full
   integration suite.

## Verification

- A local Git fixture publishes newer commits to `release` branches for both
  target submodules and proves initialization advances both checkouts.
- A refreshed `.devcontainer/initialize.sh` fixture writes a marker proving that
  the new script runs exactly once.
- A fixture forces one target update to fail and proves a warning is emitted,
  the second target is still attempted, and normal generated files are written.
- Dirty non-conflicting and conflicting submodule fixtures prove that updates are
  attempted without loss of local changes.
- Subtree and missing-`.opencode` fixtures prove absent registrations remain
  non-fatal.
- `bash -n initialize.sh tests/*.sh`
- `task check`
- `task tests-run`

## File Targets

- `initialize.sh`
- `tests/initialize.sh`
- `tests/submodule-workflow.sh`
- `tests/run.sh` if a focused refresh test receives its own entrypoint
- `README.md`
- `README_release.md`
- `.oc_local/rules/devcontainer-kit.md`
- `docs/tasks/T025_refresh_workspace_submodules_during_initialize.md`

## Dependencies

- `.gitmodules` must continue to declare the intended remote branch for each
  shared submodule.
- The refreshed `.devcontainer` release must retain a compatible
  `.devcontainer/initialize.sh` entrypoint.
- Network access and remote availability are optional at runtime because refresh
  failures are warning-only.

## Implementation Notes

- User selected immediate one-time execution of the refreshed initializer rather
  than deferring all behavior to the next reopen.
- User selected attempting updates in dirty submodules rather than preemptively
  skipping them.
- Prefer an explicit environment guard scoped to the child initializer process;
  do not persist refresh state in the repository.
- Keep Git's own diagnostics available for troubleshooting, but add one stable
  summary warning per failed target.
- The task intentionally accepts dirty parent gitlinks as the cost of always
  following the configured shared release branches.

## Cancellation Reason

- `none`
