# Simplify Initializer And Browser Display Contract

- ID: `T024`
- Type: `refactor`
- Status: `open`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `d705c30e-dcd7-41a8-b690-c59f6dcbdc0e`

## Goal

Reduce `initialize.sh` and its test surface to the devcontainer lifecycle that
the project actively supports. The initializer must prepare only the checkout
that VS Code or the Dev Containers CLI opened; it must no longer create, select,
repair, or synchronize Git worktrees from a `BRANCH` environment variable.

Keep ordinary Git worktrees supported through the standard Git workflow: a user
or repository tool creates the worktree, initializes any required submodules,
and opens that checkout directly. The devcontainer must then mount the checkout
and the shared Git metadata needed for normal Git commands inside the container.

Make visible, interactive Google Chrome through Remote SSH X11 the sole
supported visible browser transport. Preserve `chrome --headless` for automation,
but do not treat headless execution as a substitute for the visible-browser
contract. Remove Wayland-specific initialization, runtime, test, and
documentation behavior.

Remove legacy root-file migrations for `.local.env` and `compose.local.yml`.
Current consumers must use `.codegeist/.local.env` and
`.codegeist/compose.local.yml` directly.

## Context

`initialize.sh` currently combines several independent responsibilities:

- Current-checkout bootstrap and generated Compose state.
- Legacy migration from root `.local.env` and `compose.local.yml` files.
- Managed `.worktrees/<branch>` creation selected through `BRANCH`.
- Current-branch symlink aliases and stale worktree-path repair.
- Worktree submodule initialization and local-env linking.
- Host Wayland socket discovery and generated bind mounts.
- SSH X11 display and Xauthority capture.
- Dockerfile and Compose extension generation.
- OpenCode bootstrap and the custom initialization hook.

The managed worktree behavior is not required by the normal Dev Containers
workflow. It also owns a disproportionate amount of initialization logic and
integration coverage, including implicit branch creation, current-branch
aliases, nested path assumptions, generated-state synchronization, and several
overlapping end-to-end tests. It has correctness gaps around remote-only
branches, stale paths, branch-slug collisions, and simultaneous first starts.

Git already owns worktree creation and branch semantics. A directly opened
worktree has an unambiguous checkout root and independent generated files. Its
`.git` file points to metadata under the main repository's common Git directory,
so generic support requires mounting that metadata in the container; it does
not require `initialize.sh` to manage the worktree itself.

The browser implementation currently supports headless Chrome, host Wayland,
local X11, Remote SSH loopback X11, and caller-managed non-loopback X11. The
accepted interactive workflow is Remote SSH X11. Keeping every display backend
adds generated socket mounts, runtime-directory ownership behavior, launcher
branches, Weston fixtures, release attestation state, and documentation that do
not contribute to that workflow.

The legacy migration branches are documented and tested compatibility paths,
but no current repository workflow consumes them. The browser fixture is the
only in-repository user of legacy root `compose.local.yml` and can use the
current `.codegeist/compose.local.yml` path instead.

The refactor must preserve active extension and bootstrap contracts:

- `.codegeist/.local.env`
- `.codegeist/Dockerfile`
- `.codegeist/compose.local.yml`
- `.oc_local/`
- `.codegeist/extensions/custom_initialize.sh`
- generated `.devcontainer/.env`
- generated `.devcontainer/.Xauthority.gen`
- generated `.devcontainer/Dockerfile.merged.gen`
- generated `.devcontainer/compose.local.gen.yml`
- generated `.devcontainer/compose.user.gen.yml`

## Product Decisions

- `BRANCH` is no longer a devcontainer startup input.
- `initialize.sh` never invokes `git worktree add`, creates a worktree branch,
  creates a current-branch symlink alias, repairs a worktree path, or initializes
  worktree submodules.
- A worktree is supported only after Git or another explicit repository workflow
  creates it and the user opens that checkout directly.
- A worktree may live under `.worktrees/` or elsewhere; runtime path resolution
  must not depend on that directory name.
- The conventional `/.worktrees/` ignore may remain useful for manually created
  repository-local worktrees, but the initializer must not create the directory.
- Each directly opened checkout owns its generated `.devcontainer` state,
  `.codegeist` local state, `.oc_local` bootstrap, and `.chrome` profile.
- Visible Chrome supports Remote SSH loopback X11 with Xauthority validation and
  reconnect refresh.
- Wayland is not a supported browser transport after this task.
- Local `DISPLAY=:N` and arbitrary non-loopback X11 hosts are not part of the
  supported visible-browser contract. The implementation need not preserve
  special handling for them.
- Headless Chrome remains available for deterministic automation and CDP tests.
- Existing root `.local.env` and `compose.local.yml` files are not migrated,
  copied, read, or silently ignored as current configuration.
- Host networking is unchanged by this refactor. Replacing it for Remote SSH X11
  and microphone forwarding remains the responsibility of `T022`.
- The `.devcontainer` submodule gitlink is not an implementation target and must
  not be updated accidentally.

## Supported Worktree Workflow

A user creates and opens a worktree explicitly:

```bash
git worktree add .worktrees/feature-x feature-x
git -C .worktrees/feature-x submodule update --init --recursive
code .worktrees/feature-x
```

For a new branch:

```bash
git worktree add -b feature-x .worktrees/feature-x origin/main
git -C .worktrees/feature-x submodule update --init --recursive
code .worktrees/feature-x
```

When VS Code invokes the initializer from that checkout, path resolution should
use Git rather than a managed-directory convention:

```bash
git rev-parse --show-toplevel
git rev-parse --path-format=absolute --git-common-dir
```

The generated Compose configuration must mount the opened checkout at its
host-identical absolute path. For a linked worktree, it must also expose the
required common Git metadata at the path referenced by the worktree's `.git`
file. A command such as `git status` must therefore work inside the container
without mounting an unrelated guessed `.worktrees/..` path.

The implementation may mount the common Git directory itself or the narrowest
stable parent path required by Git. It must avoid broadening the mount merely to
recreate the old managed-worktree model.

## Scope

In scope:

- Refactor `initialize.sh` around one current-checkout execution path.
- Remove all `BRANCH` parsing and managed-worktree creation, aliasing, repair,
  submodule initialization, and local-env linking.
- Resolve the active checkout and Git common metadata without assuming a
  `.worktrees/<branch>` layout.
- Keep branch-aware Compose project and hostname generation based on the branch
  actually checked out in the opened workspace.
- Preserve direct root-checkout operation and direct linked-worktree operation.
- Remove root `.local.env` and `compose.local.yml` migration code.
- Stop documenting legacy root files as accepted configuration inputs.
- Preserve current `.codegeist` environment, Dockerfile, and Compose extension
  behavior without creating optional extension files automatically.
- Preserve OpenCode bootstrap and tracked-overlay safety.
- Preserve the custom initialization hook in the opened checkout, including its
  failure propagation.
- Preserve atomic `.env` and Xauthority refresh required by SSH reconnects.
- Keep visible Chrome defaulting to Remote SSH X11 and retain Xauthority cookie
  normalization for the requested loopback display only.
- Remove Wayland detection, generated environment values, socket mounts,
  launcher selection, entrypoint runtime-directory setup, tests, and current
  documentation.
- Remove special supported behavior for local and non-loopback X11 displays.
- Consolidate tests around observable contracts instead of generated comments,
  exact formatting, or repeated absence assertions.
- Keep one real non-headless X11 browser regression and one headless automation
  regression.
- Update release-copy tests and commit-bound verification so they no longer
  require the Wayland-specific marker.
- Reconcile active task documentation whose planned contract conflicts with the
  accepted removal of managed worktrees or Wayland.

Out of scope:

- Creating, deleting, pruning, repairing, or selecting Git worktrees.
- Creating branches or deciding their upstream or base commit.
- Automatically initializing consuming-repository submodules.
- Sharing `.codegeist/.local.env` between independent worktrees.
- Supporting multiple VS Code windows that open the same checkout and overwrite
  the same generated files.
- Adding VNC, noVNC, RDP, a browser proxy, or another remote desktop layer.
- Replacing Remote SSH X11 with Wayland or a hidden virtual display for the
  interactive user workflow.
- Removing `chrome --headless` or Playwright/CDP automation support.
- Removing host networking or redesigning the SSH X11 and microphone transport;
  those changes belong to `T022`.
- Changing Docker-in-Docker, Podman, QEMU, microphone recording, Vault Agent, or
  unrelated image tools.
- Removing the current Dockerfile, Compose, OpenCode, or custom-hook extension
  points.
- Editing generated runtime files or the `.devcontainer` release submodule
  directly.
- Publishing a release, changing Git history, or committing the implementation.

## Acceptance Criteria

### Initializer Contract

- `initialize.sh` contains no managed `BRANCH` workflow and does not create
  `.worktrees/` or invoke `git worktree`.
- Running the initializer from a normal checkout prepares that checkout and does
  not redirect the workspace to another path.
- Running it from an externally created linked worktree prepares that worktree
  without changing the main checkout or another worktree.
- Generated workspace paths are absolute, host-identical, and derived from the
  opened checkout.
- The generated Compose configuration exposes the Git common metadata required
  by linked worktrees, and normal Git read and write operations work inside the
  resulting container.
- Branch-aware project and hostname values use the actual checked-out branch and
  remain deterministic for normal branch names.
- Repeated initialization is idempotent and does not overwrite current
  user-owned `.codegeist` extension files.
- Required generated files are written atomically where reconnects or concurrent
  readers could otherwise observe partial content.
- The initializer remains non-interactive and fails with an actionable message
  only for a real required-input or generation failure.

### Legacy Removal

- Root `.local.env` is never copied into `.codegeist/.local.env`.
- Root `compose.local.yml` is never copied into
  `.codegeist/compose.local.yml` or generated Compose state.
- A missing `.codegeist/.local.env` is still seeded from
  `.devcontainer/.local.env.example`.
- Existing `.codegeist/.local.env`, `.codegeist/compose.local.yml`, and
  `.codegeist/Dockerfile` files remain untouched except where the documented
  generated bridge or merge output consumes them.
- Legacy root paths are removed from current source and release documentation.
- Legacy root files are not kept invisible through obsolete generated ignore
  behavior; accidental use should be visible to the repository owner.

### Browser And Display Contract

- Plain `chrome <url>` launches a non-headless Google Chrome process when a
  reachable Remote SSH loopback X11 display and matching authority cookie are
  available.
- The launcher rereads the opened workspace's generated display state on every
  visible launch so an SSH reconnect can replace stale container environment.
- `localhost:N.0` and `127.0.0.1:N.0` displays are probed before Chrome starts.
- Only the requested display's matching Xauthority cookie is normalized into a
  private temporary authority file when normalization is necessary.
- Missing, stale, unreachable, or unauthorized SSH X11 state prevents Google
  Chrome from starting and reports the relevant display and generated-state
  paths without exposing credentials.
- Parallel directly opened worktrees keep independent generated display state,
  Xauthority files, Chrome profiles, and Compose projects.
- `chrome --headless` remains independent of visible-display availability.
- No current runtime file contains Wayland socket discovery,
  `DEVCONTAINER_WAYLAND_*`, `WAYLAND_DISPLAY` selection, generated Wayland
  mounts, or `--ozone-platform=wayland` behavior.
- `entrypoint.sh` no longer prepares a Wayland runtime directory solely for the
  removed Chrome path.
- The release verification no longer depends on a
  `browser-wayland-display0=passed` marker.
- The commit-bound release verification records the visible-browser regression
  with the marker `browser-visible-x11=passed`.

### Preserved Extension Contracts

- `.codegeist/Dockerfile` remains optional, is appended to the kit image, and is
  rejected when it contains an active `FROM` instruction.
- `.codegeist/compose.local.yml` remains optional, visible to Git, and reaches
  resolved Compose behavior through `compose.user.gen.yml`.
- `.oc_local/` is created when absent, remains writable, and a tracked local
  overlay is not overwritten or hidden.
- `.codegeist/extensions/custom_initialize.sh` runs through Bash from the opened
  checkout even without its executable bit, and a hook failure fails
  initialization.
- The initializer does not create optional `.codegeist/Dockerfile` or
  `.codegeist/compose.local.yml` files.

### Test And Documentation Quality

- Tests assert observable paths, exit status, runtime configuration, process
  behavior, and side effects rather than generated comments or exact YAML
  formatting when those details are not contractual.
- Repeated checks for the same default absence or ignore pattern are reduced to
  one focused owner test.
- Source and release docs describe direct checkout and direct Git-worktree usage
  without `BRANCH`, managed aliases, or initializer-owned branch creation.
- Browser documentation presents Remote SSH X11 as the supported visible path
  and headless Chrome as automation-only.
- Historical solved task records remain historical; active task records are
  reconciled so they do not prescribe removed behavior.
- `task check`, the focused lifecycle tests, the real visible-X11 check, the full
  integration suite, and release-copy verification pass.

## Test Plan

### Fast Initializer Tests

Keep or add focused cases that prove:

1. A fresh normal checkout creates the required directories and generated files.
2. Missing `.codegeist/.local.env` is seeded from the current template.
3. Existing current-path environment, Dockerfile, and Compose overrides are
   preserved.
4. Root legacy `.local.env` and `compose.local.yml` files are not imported.
5. A second initializer run produces equivalent output and preserves user files.
6. The checked-out branch determines project and hostname inputs without
   `BRANCH`.
7. An externally created linked worktree resolves its own workspace root and the
   repository's absolute common Git directory.
8. X11 display and authority state are refreshed atomically.
9. A missing optional custom hook is ignored, a non-executable hook runs through
   Bash, and a failing hook propagates its status.
10. Tracked `.oc_local` content is preserved while an absent bootstrap directory
    is created.

### Compose And Extension Tests

Keep one focused owner for each contract:

1. Resolved Compose mounts the current checkout at the same absolute path.
2. A linked-worktree fixture exposes enough common Git metadata for `git status`
   and a disposable commit inside the container.
3. No user Compose override yields valid generated Compose without creating the
   optional source file.
4. A non-empty `.codegeist/compose.local.yml` changes an observable resolved or
   runtime setting.
5. No Dockerfile extension yields the base image, while a valid extension adds
   an observable package or file.
6. An active `FROM` in `.codegeist/Dockerfile` fails with an actionable error.

Do not retain assertions whose only purpose is to compare generated comments,
literal `services: {}` formatting, or the exact base-image line in a merge test
that does not own base-image selection.

### Devcontainer Integration Tests

Retain a compact real-lifecycle matrix:

1. Start a normal consuming checkout through `devcontainer up` and verify the
   remote workspace, runtime user, generated files, nested Docker baseline, and
   a basic command.
2. Create a linked worktree explicitly with `git worktree add`, initialize its
   submodules explicitly when required, open that path directly through
   `devcontainer up`, and verify Git plus workspace isolation inside the
   container.
3. Consume the release kit as a `.devcontainer` submodule in the current
   checkout and verify the normal lifecycle without adding a managed branch or
   testing an unrelated fast-forward merge workflow.
4. Start OpenCode once through the canonical devcontainer integration test; do
   not duplicate the same full startup in a second fixture unless it protects a
   distinct failure mode.

### Browser Tests

Keep the browser paths distinct:

1. Launcher contract test with fake `xdpyinfo` and fake Chrome:
   - generated state replaces stale inherited `DISPLAY`;
   - loopback display aliases are handled;
   - only the requested Xauthority cookie is normalized;
   - unreachable or unauthorized state rejects launch;
   - separate worktree state remains isolated.
2. Real non-headless X11 regression:
   - start a disposable X server with TCP loopback and Xauthority state shaped
     like SSH X11 forwarding;
   - launch real Google Chrome without `--headless`;
   - verify the live process and rendered page through CDP or an X11 window
     assertion;
   - verify the selected profile remains inside the opened workspace.
3. Manual Remote SSH check:
   - run `task browser-open-test` from a configured Remote SSH session;
   - confirm that the Chrome window is visible and interactive on the user's
     display;
   - inspect the reported fixture if needed, then stop its container and remove
     the retained temporary repository with the reported cleanup commands.
4. Headless automation regression:
   - retain one CDP screenshot or accessibility-content assertion through
     `chrome --headless`;
   - remove a weaker duplicate DOM-only smoke if it proves no additional
     contract.

Do not use a hidden Wayland compositor as proof of the visible Remote SSH X11
contract.

### Tests To Remove Or Rewrite

- Remove `tests/worktree.sh` managed-worktree creation and merge coverage.
- Remove `tests/remote-ssh-branch.sh`; `SetEnv BRANCH` is no longer supported.
- Remove `tests/devcontainer-current-branch-up.sh`; the symlink alias no longer
  exists.
- Replace `tests/devcontainer-worktree-up.sh` with one externally created,
  directly opened worktree lifecycle test.
- Remove `tests/devcontainer-parallel-branches.sh`; direct worktree isolation is
  covered by the worktree and launcher tests.
- Remove the optional branch argument and `BRANCH` environment behavior from
  `tests/devcontainer-reality-test.sh`.
- Rewrite `tests/submodule-workflow.sh` around direct current-checkout submodule
  consumption and remove its managed worktree plus commit/merge tail.
- Remove legacy migration cases from `tests/initialize.sh` and replace them with
  negative non-import assertions.
- Rewrite `tests/browser-open-test.sh` to use
  `.codegeist/compose.local.yml` rather than legacy root `compose.local.yml`.
- Remove Wayland branches from `tests/chrome-launcher.sh`.
- Replace the Weston/Wayland half of `tests/browser-smoke.sh` with the real
  non-headless loopback-X11 regression.
- Remove duplicate OpenCode startup coverage after selecting one canonical
  end-to-end owner.
- Update `tests/run.sh`, `Taskfile.yaml`, helper functions, and release
  verification for the reduced test set.

## File Targets

Primary runtime and configuration files:

- `initialize.sh`
- `devcontainer.json`
- `docker-compose.yml`
- `entrypoint.sh`
- `scripts/chrome.sh`
- `.gitignore`
- `.local.env.example`

Focused tests and orchestration:

- `Taskfile.yaml`
- `tests/run.sh`
- `tests/helpers.sh`
- `tests/initialize.sh`
- `tests/compose-config.sh`
- `tests/dockerfile-merge.sh`
- `tests/chrome-launcher.sh`
- `tests/browser-smoke.sh`
- `tests/browser-open-test.sh`
- `tests/devcontainer-up.sh`
- `tests/devcontainer-reality-test.sh`
- `tests/devcontainer-worktree-up.sh`
- `tests/devcontainer-current-branch-up.sh`
- `tests/devcontainer-parallel-branches.sh`
- `tests/worktree.sh`
- `tests/remote-ssh-branch.sh`
- `tests/submodule-workflow.sh`
- `tests/opencode-startup.sh`
- `tests/release-build.sh`
- `scripts/release-build.sh` only if release verification inputs change

Current-behavior documentation and task state:

- `README.md`
- `README_release.md`
- `CONTRIBUTING.md` if contributor commands or prerequisites change
- `.oc_local/rules/devcontainer-kit.md`
- `docs/tasks/T001_add_browser_support_to_devcontainer/tasks/T001_03_support_parallel_worktree_display_state.md`
- `docs/tasks/T022_remove_host_network_mode.md`
- `docs/tasks/T024_simplify_initializer_and_browser_display_contract.md`

The listed files are inspection targets, not a requirement to edit every file.
The final diff should contain only changes needed by the accepted contract.
Generated files and files inside the `.devcontainer` submodule are not direct
edit targets.

## Dependencies And Sequencing

- `T001_02` established visible Chrome and remains the historical source for the
  visible-default launcher contract.
- `T001_03` is cancelled as superseded by this task. Its completed reconnect
  work remains historical context, while its remaining managed
  parallel-`BRANCH` scope is no longer an active product requirement.
- `T017` is a solved historical Wayland fix. Do not rewrite its historical
  verification, but remove Wayland from current runtime documentation and code.
- `T022` remains `planned` and is sequenced after this task. Its reconciled plan
  preserves Remote SSH X11 without restoring Wayland while redesigning the
  narrower transport needed after host networking is removed.
- Implement `T024` before a future `T022` host-network removal so the transport
  redesign works against the smaller accepted display contract.
- Real manual browser verification requires an active Remote SSH X11 forwarding
  session and valid authority state.

## Implementation Plan

1. Update focused tests first to express the reduced contract:
   - add negative legacy non-import cases;
   - replace managed-worktree setup with explicit `git worktree add` fixtures;
   - define direct-worktree Git metadata assertions;
   - replace Wayland browser coverage with non-headless loopback X11 coverage.
2. Simplify `devcontainer.json` so `workspaceFolder` resolves to the directory
   opened by VS Code rather than `${localEnv:BRANCH}` and `.worktrees/`.
3. Refactor `initialize.sh` to one current-checkout path:
   - resolve the current checkout and common Git directory;
   - remove `BRANCH`, branch creation, aliases, repair, submodule setup, and
     root-to-worktree synchronization;
   - preserve current-path local setup, generation, OpenCode bootstrap, and hook.
4. Remove legacy root-file migration and update generated ignore behavior so
   obsolete configuration is no longer silently accepted.
5. Generate the narrow mount state required by a directly opened linked
   worktree and prove Git works inside the container.
6. Remove Wayland state from the initializer, Compose generation, entrypoint,
   and Chrome launcher. Keep Remote SSH X11 refresh, probing, cookie
   normalization, visible launch, and diagnostics.
7. Consolidate test helpers and delete obsolete test entrypoints after their
   unique accepted coverage has been replaced.
8. Update source and release documentation, examples, task relationships, and
   local project guidance to describe the current contract only.
9. Run syntax checks and targeted tests. Fix regressions without restoring
   removed compatibility branches.
10. Run the full integration suite, the manual visible Remote SSH browser check,
    release-copy verification, and whitespace validation.
11. Record concrete verification results and set this task to `solved` only when
    both normal checkout and direct linked-worktree workflows pass and the user
    has confirmed a visible interactive Chrome window over Remote SSH X11.

## Implementation Notes

- Keep the initializer centered on the checkout from which it is invoked; use
  Git's top-level and absolute common-directory queries for linked-worktree
  metadata rather than retaining a reduced `BRANCH` compatibility path.
- Keep the release attestation commit-bound, but replace the removed Wayland
  result with exactly `browser-visible-x11=passed` after the real non-headless
  loopback-X11 regression succeeds.
- Do not change this task to `solved` until the runtime, focused tests, full
  suite, release-copy check, and manual Remote SSH X11 verification have all
  completed.
- Implemented the current-checkout initializer, exact Git-common-directory
  mount, direct-worktree and submodule lifecycle coverage, X11-only Chrome
  launcher, reduced test orchestration, release marker, and current-behavior
  documentation described above.

## Verification

Planned automated checks:

- `bash -n initialize.sh entrypoint.sh scripts/chrome.sh tests/*.sh`
- `task check`
- `tests/initialize.sh`
- `tests/compose-config.sh`
- `tests/dockerfile-merge.sh`
- `tests/chrome-launcher.sh`
- The rewritten direct-worktree Dev Containers lifecycle test
- The rewritten current-checkout submodule-consumer test
- The real non-headless loopback-X11 browser regression
- The retained headless CDP browser regression
- `task tests-run`
- `tests/release-build.sh`
- `git diff --check`

Planned manual checks:

- From a configured Remote SSH session with a reachable forwarded X11 display,
  run `task browser-open-test`.
- Confirm that Google Chrome opens visibly, accepts keyboard and pointer input,
  loads the requested page, and uses the fixture's workspace-local profile.
- Reconnect SSH so the display number changes, rerun visible Chrome, and confirm
  the launcher uses refreshed generated display and Xauthority state rather than
  stale container environment.
- Create a Git worktree explicitly, initialize its submodules when present, open
  that checkout directly, and confirm `git status` and a disposable commit work
  inside its devcontainer without changing the main checkout.

## Verification Results

Completed on 2026-10-02:

- `task check` passed, including shell syntax and release-copy verification.
- `task tests-run` passed all generic kit tests in 96 seconds. This included
  initializer, Compose, direct linked-worktree, submodule-consumer, nested
  Docker, QEMU, microphone, headless Chrome, and real non-headless authenticated
  loopback-X11 coverage.
- The direct linked-worktree lifecycle test created a disposable commit inside
  the container through the exact shared Git metadata mount without changing the
  main checkout.
- `task browser-open-test` started Google Chrome through the active Remote SSH
  `DISPLAY=localhost:11.0` session. Direct process inspection confirmed the
  workspace-local profile and `--ozone-platform=x11`; the generated fixture and
  container were removed after inspection.
- After an SSH reconnect, the user confirmed that the second Chrome window was
  visibly rendered and accepted keyboard and pointer input. The reconnect
  retained `DISPLAY=localhost:11.0`, so it did not exercise the
  changed-display-number branch.
- `git diff --check` passed before and after the documentation updates.

Still required before `solved`:

- A manual SSH reconnect that changes the display number, followed by another
  visible launch confirming refreshed display and Xauthority state. The focused
  launcher regression already covers this refresh behavior synthetically, but
  does not replace the accepted manual check.

## Cancellation Reason

Not cancelled.
