# Add Custom Initialize Hook

- ID: `T018`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `e0ae90af-a756-471f-bf91-dc612b777051`

## Goal

Allow a consuming repository to extend the host-side Dev Containers
`initializeCommand` with one optional Bash script at
`.codegeist/extensions/custom_initialize.sh` without editing the shared
`.devcontainer` kit.

## Context

The kit already supports repository-owned image and Compose extensions through
`.codegeist/Dockerfile` and `.codegeist/compose.local.yml`, but it has no small
extension point for repository-specific host preparation. Adding another
lifecycle framework or a generic dispatcher would be unnecessary for this use
case. The required behavior is one direct optional call from `initialize.sh`.

`initialize.sh` can run repeatedly and can select a managed worktree through
`BRANCH`. The custom hook must therefore come from the workspace that will
actually be opened, not unconditionally from the repository root. Because the
hook runs on the host outside container isolation, consuming repositories must
treat it as trusted repository code and keep it non-interactive and safe for
repeated execution.

## Scope

In scope:

- Recognize `.codegeist/extensions/custom_initialize.sh` in the selected
  workspace.
- Run the hook with Bash on the host after the normal kit initialization has
  completed.
- Run the hook with the selected workspace as its current working directory.
- Use the `BRANCH`-selected worktree copy when managed worktree selection is
  active.
- Ignore a missing hook without creating `.codegeist/extensions/` or a template.
- Propagate a present hook's non-zero exit status so `initializeCommand` fails.
- Document the execution location, timing, repetition, trust boundary, and
  failure behavior in source and release documentation.
- Add only focused regression coverage for observable behavior not already
  exercised by the existing initializer tests.

Out of scope:

- Hooks for `onCreateCommand`, `updateContentCommand`, `postCreateCommand`,
  `postStartCommand`, or `postAttachCommand`.
- A generic lifecycle dispatcher, plugin framework, hook registry, or multiple
  scripts per lifecycle phase.
- Support for interpreters other than Bash.
- Requiring or checking an executable bit or shebang.
- Configurable ordering, best-effort failure handling, retries, timeouts, or
  background execution.
- Creating, copying, migrating, ignoring, or deleting consumer hook files.
- Backward-compatibility aliases or migration from another hook location.
- Persisting environment changes made by the hook into later processes.
- Editing generated release content directly under `.devcontainer/`.

## Behavior Contract

- The hook path is exactly
  `<selected-workspace>/.codegeist/extensions/custom_initialize.sh`.
- The hook runs only when that path is a regular file.
- The kit invokes the file as `bash "$custom_initialize"`; executable permission
  is not required.
- The hook's current working directory is the selected workspace.
- With no `BRANCH`, the selected workspace is the current checkout.
- With `BRANCH`, the selected workspace is the prepared managed worktree or the
  current-checkout alias resolved by `initialize.sh`.
- The hook runs after generated environment, Xauthority, Compose, and local
  workspace preparation is complete, immediately before `initialize.sh`
  returns.
- The hook inherits the host environment of `initializeCommand`. It must not
  assume that exports survive after the process exits.
- A missing hook is a no-op. A failing hook fails `initialize.sh` through its
  existing `set -euo pipefail` behavior.
- Since `initializeCommand` may run more than once, the consumer hook is
  responsible for being idempotent, non-interactive, and bounded.

## Acceptance Criteria

- A consuming repository can add
  `.codegeist/extensions/custom_initialize.sh` without changing
  `.devcontainer/devcontainer.json` or kit-owned files.
- `initialize.sh` executes a present hook with Bash after its normal setup.
- The hook executes from the selected workspace directory.
- A `BRANCH` start executes the hook stored in that selected worktree rather
  than a same-named root-checkout hook.
- The hook does not need executable permission.
- Existing initialization remains successful when the hook is absent.
- A non-zero hook result makes `initialize.sh` return non-zero.
- The kit does not create or ignore `.codegeist/extensions/`; consumer hook code
  remains normal repository-visible state.
- No other Dev Containers lifecycle command or extension mechanism changes.
- Source and release documentation describe the current contract concisely.

## Implementation Plan

1. Update the contract header in `initialize.sh` to name the optional custom
   initialize hook and its host-side trust and repetition constraints.
2. Add one local `custom_initialize` variable to `main()`.
3. After `write_user_compose_bridge "$root_dir"`, derive the hook path from the
   already resolved `workspace_folder`.
4. If the path is a regular file, enter a subshell, change to
   `workspace_folder`, and invoke the absolute hook path with Bash.
5. Do not add fallback paths, compatibility names, directory creation, custom
   logging infrastructure, or error suppression.
6. Extend the existing initializer regression with one non-executable hook in
   the prepared managed worktree. Have it write its current directory to a
   fixture-local result file, rerun initialization for that branch, and assert
   that the recorded directory is the selected worktree.
7. Reuse the existing repeated initializer runs without a hook as coverage for
   the missing-hook no-op; do not add a duplicate test for that branch.
8. Replace the fixture hook with a script that exits non-zero and assert that
   `initialize.sh` fails. Exact exit-code preservation is not part of the
   contract, so only the non-zero result needs an assertion.
9. Add a short `Custom Initialize Hook` section to `README.md` and
   `README_release.md`, and add a concise consumer-visible changelog entry to
   the release README.
10. Run only the focused initializer and normal fast repository checks required
    to prove this host lifecycle change.

## Intended Implementation Shape

The runtime change in `initialize.sh` should stay equivalent to:

```bash
custom_initialize="$workspace_folder/.codegeist/extensions/custom_initialize.sh"
if [ -f "$custom_initialize" ]; then
  (
    cd "$workspace_folder"
    bash "$custom_initialize"
  )
fi
```

The successful regression hook should stay minimal and should not require an
executable bit:

```bash
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$PWD" >.codegeist/custom-initialize.result
```

## Verification

- `bash -n initialize.sh tests/initialize.sh`
- `tests/initialize.sh`
- `task check`
- `git diff --check`

The focused initializer test already exercises a real managed worktree and a
Dev Containers CLI startup. The complete image, browser, QEMU, and recording
suite is not required because this task does not change the image or container
runtime behavior.

## File Targets

- `initialize.sh`
- `tests/initialize.sh`
- `README.md`
- `README_release.md`
- `docs/tasks/T018_add_custom_initialize_hook.md`

## Implementation Notes

- Keep the hook call at the end of successful kit initialization so consumer
  code cannot be overwritten by later kit setup and receives a fully prepared
  selected workspace.
- Use the selected workspace path already computed by `selected_workspace_folder`;
  do not independently reconstruct the `BRANCH` worktree path.
- Use a subshell for `cd` so the parent initializer's working directory remains
  unchanged.
- Do not add `|| true`, warnings-only behavior, or a recovery branch. A hook that
  exists is part of the consuming repository's required initialization.
- Do not add `.codegeist/extensions/` to generated `.gitignore` entries. Unlike
  `.codegeist/.local.env` and `.codegeist/secrets/`, this hook is intentional
  reviewable repository code.
- `initialize.sh` is already included in the release allowlist, so no release
  file-list change is needed.

## Verification Results

- On 2026-09-22, `bash -n initialize.sh tests/initialize.sh` passed.
- The focused `tests/initialize.sh` regression passed with a non-executable hook
  from the selected managed worktree, confirmed that the hook ran from that
  worktree, and confirmed that a failing hook failed `initializeCommand`.
- `task check` passed, including the exact release-copy contract test.
- `git diff --check` passed.
- The complete image, browser, QEMU, and recording suite was not run because the
  implementation changes only host-side initialization and the focused test
  exercises that lifecycle through a real Dev Containers CLI startup.

## Cancellation Reason

- `none`
