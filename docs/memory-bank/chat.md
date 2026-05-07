# Project Memory

## Current Goal

- This repository is the standalone `codegeist-devcontainer-kit` candidate.
- It provides a reusable `.devcontainer/` kit for consuming repositories that
  want the normal VS Code Dev Containers workflow with a Codegeist/planner-style
  development toolchain.
- OpenCode work should continue from this repository root, not from the parent
  `m7` workspace.

## Repository State

- Current workspace root is `/workspace`.
- The local default branch is `main`.
- `.devcontainer/` and `.opencode/` are checked-out shared submodules in this
  development repository. Do not edit them directly during normal project work.
- Project-specific OpenCode behavior belongs in `.oc_local/`; the local overlay
  now includes `.oc_local/rules/submodule-editing.md` to make that convention
  explicit, and `.oc_local/opencode.json` loads both `.oc_local/rules` and
  `README.md` as instruction sources.
- Latest work keeps generated `.env` files ignored without direct edits inside
  `.devcontainer/`: root `.gitignore` now covers the release-branch root `.env`,
  and release builds copy that `.gitignore` into the runtime-only branch.
- Release builds publish `README_release.md` as `README.md` in the runtime-only
  branch so consuming `.devcontainer` submodule checkouts expose the focused
  consumer guide as their primary README.
- The local `.devcontainer` submodule checkout is intentionally updated to the
  latest runtime `origin/release` commit when release work is ready for a parent
  gitlink commit.
- Latest pushed runtime release is `7b18c2adcba4cf7002aafc3a0490d489902a7c2d`;
  the parent `.devcontainer` gitlink should point at that commit.
- Latest source work adds `jq` to the image APT toolchain, removes the Compose
  `/var/lib/docker` tmpfs cap, and caps generated container hostnames at 63
  characters so Docker can start containers for long host/repo/branch names.
- The parent repository still sees this directory as an untracked nested Git repo;
  treat this repository as the source of truth for the kit work.

## What This Kit Contains

- `devcontainer.json` is the VS Code / Dev Containers entrypoint.
- `docker-compose.yml` defines the reusable workspace service, Docker-in-Docker
  runtime, bind mounts, generated env loading, and UID-based runtime user.
- `Dockerfile` is the full Codegeist/planner-style Debian image with Docker CE,
  Node 24, VS Code, GitHub CLI, Maven, GraalVM 25, Hugo, Nix, OpenCode tooling,
  Repomix, Task, and related CLI tools.
- `entrypoint.sh` starts nested Docker through passwordless `sudo` because the
  image runs as the configured workspace user.
- `initialize.sh` is the host-side `initializeCommand`; it creates local config,
  generated runtime files, root `.oc_local/`, and optional branch worktrees.
- `Taskfile.yaml` provides repo-local maintenance commands:
  - `task docker-build`
  - `task docker-run`
  - `task tests-run`
  - `task code-open`
  - `task code-open-test`
  - `task release-build -- release --push`
- `task code-open -- <branch>` opens the current Git root and writes
  `.devcontainer/.env` so VS Code/Compose keep the branch even when an existing
  VS Code process handles `code .`; `BRANCH=<branch> task code-open` remains
  supported.
- `task code-open-test -- <branch>` builds a temporary fixture and then invokes
  the real `task code-open` against it.
- `tests/` contains the Bash smoke suite that exercises the real Dev Containers
  lifecycle.
- `README.md` is the primary usage documentation for consuming repos and for
  developing this kit.
- `README_release.md` is the focused guide for projects that consume the
  runtime-only `release` branch as a `.devcontainer` Git submodule, including
  coding-agent rules for consumer repositories.

## Usage Contract

- Consuming repositories install this kit at `.devcontainer/` either as a Git
  subtree or a Git submodule.
- Normal user flow from a consuming repository root can use VS Code directly:

```bash
code .
```

- Worktree flow still starts from the consuming repository root:

```bash
BRANCH=develop0 code .
```

- VS Code opens the container workspace at `/workspace`.
- Without `BRANCH`, `/workspace` is also the consuming repository root.
- With `BRANCH`, `initialize.sh` creates or reuses `.worktrees/<branch>` and
  Compose mounts that worktree as `/workspace`.
- Repo-local helper flow from a consuming repository root:

```bash
task code-open
task code-open -- develop0
```

- `task code-open-test -- <branch>` creates a temporary fixture and then invokes
  the real `task code-open` path against it.
- Test fixtures copy only runtime kit files into the consuming repo's
  `.devcontainer/`; repo-development submodules such as this repository's own
  `.devcontainer/` and `.opencode/` are intentionally excluded to avoid nested
  devcontainer discovery in VS Code. Root-local runtime files such as
  `.local.env` and `compose.local.yml` are also excluded so they are generated
  only in the consuming repo root, not inside `.devcontainer/`.
- The consuming repository root is also bind-mounted at its host path inside the
  container so linked-worktree Git metadata resolves correctly.
- OpenCode config, share, and state directories are bind-mounted from
  `OPENCODE_DIR_CONFIG`, `OPENCODE_DIR_SHARE`, and `OPENCODE_DIR_STATE`, with
  host defaults under `/home/$USER/.config/opencode`,
  `/home/$USER/.local/share/opencode`, and
  `/home/$USER/.local/state/opencode`.
- `devcontainer.json` sets `OPENCODE_CONFIG_DIR=/workspace/.oc_local`. Fresh
  consuming checkouts therefore need root `.oc_local/` before OpenCode starts.
  `initialize.sh` creates it, copies `.oc_local.gitignore.example` to
  `.oc_local/.gitignore`, and adds `/.oc_local/` to local `.git/info/exclude`
  only when the repository has no tracked `.oc_local/` overlay.
- Changing `BRANCH` does not remount an already existing devcontainer. Rebuild or
  remove the existing container before starting with another branch.

## Generated Files

- Consuming repositories should ignore these root-local files:

```gitignore
/.local.env
/.devcontainer/.env
/.oc_local/
/.worktrees/
```

- Do not ignore `/.oc_local/` when the consuming repository intentionally tracks
  project-specific OpenCode overlay files there.

- `initialize.sh` creates root `.local.env` from
  `.devcontainer/.local.env.example` when missing.
- `compose.local.yml` is tracked in this repository as the default local
  override file that consuming checkouts can edit or replace.
- `initialize.sh` rewrites kit-owned `.devcontainer/.env` and
  `.devcontainer/compose.local.gen.yml` on each start.
- Users should not edit `.devcontainer/.env` or
  `.devcontainer/compose.local.gen.yml`; manual overrides belong in root
  `.local.env` or `compose.local.yml`.
- `task code-open -- <branch>` can seed `BRANCH` in `.devcontainer/.env` before
  `initialize.sh` rewrites the same file with generated runtime values and the
  persisted branch selection; it should stay untracked.
- `.oc_local/` may be generated for workspace-local OpenCode config; this kit
  repository tracks project-specific `.oc_local/` overlay files, so future work
  must not hide the directory globally here.

## Important Decisions

- No root-level launcher is required for normal VS Code usage.
- `initializeCommand` must stay idempotent, non-interactive, host-side only, and
  must not open VS Code or start/remove containers.
- Dev Containers CLI verification should use real lifecycle commands, primarily
  `npx --yes @devcontainers/cli up --workspace-folder <fixture-repo>`.
- Tests should not replace lifecycle checks with direct calls to `initialize.sh`
  when the behavior depends on Dev Containers integration.
- After code, script, or workflow changes, run the complete `task tests-run`
  suite before handoff. If the environment blocks the full suite, report that
  blocker and list the targeted checks that did pass.
- The devcontainer user follows host `${localEnv:USER}` through both
  `remoteUser` and `containerUser`.
- Runtime `user` intentionally uses the host UID for both numeric user and group.
  `docker-compose.yml` has a static fallback: `${UID:-1000}:${UID:-1000}`.
- Nested Docker no longer mounts `/var/lib/docker` as a size-limited tmpfs; the
  image still declares `VOLUME ["/var/lib/docker"]`, but Compose does not impose
  the previous 16G tmpfs cap.
- Generated Compose hostnames are capped at the Linux hostname limit of 63
  characters after slugging. This prevents `sethostname: invalid argument` when
  host, repository, and branch names are long.
- `BRANCH` path selection uses the literal branch name under `.worktrees/`; only
  generated hostnames use slugged branch names.
- Docker-in-Docker is enabled by default because it is part of the tested smoke
  path.
- `.opencode/` is for this kit repository's AI workflow support and is not part
  of the consuming `.devcontainer/` runtime contract.
- Never make normal project-specific edits directly in `.devcontainer/` or
  `.opencode/`. If a shared submodule truly must change, ask first and treat it
  as explicit submodule work with its own review, tests, commit, and parent
  gitlink update.
- Runtime releases are published from clean `main` with `task release-build`.
  The task copies runtime files into a temporary tree, copies
  `README_release.md` there as `README.md`, then writes that tree with a
  temporary index and `commit-tree` before updating the orphan `release` branch.
  Use `--push` only when the branch should be pushed immediately.
- Repo-local release automation lives in `.oc_local/`: `/release-build` first
  executes `@.opencode/commands/save.md`, then verifies the branch-only release
  contract, runs `tests/release-build.sh`, calls
  `task release-build -- release --push`, and updates the `.devcontainer`
  submodule checkout to the just-pushed `origin/release` commit so the parent
  gitlink is ready for a follow-up commit. Do not update `.opencode/` in this
  workflow; the release commit belongs to `.devcontainer/`. This repository's
  release workflow does not use SemVer or Git release tags.
- The release command must not start the branch build until the save workflow has
  synchronized the local and remote base branches, and it must not skip updating
  `.devcontainer/` to the just-pushed release commit after a successful push.
- Managed worktree `.local.env` files are ignored via
  `/.worktrees/**/.local.env`. Fresh worktrees get a symlink to the root
  `.local.env`; existing normal `.local.env` files in worktrees are preserved.

## Verification Already Done

- Latest full `task tests-run` passed after the `jq`, Docker tmpfs removal, and
  hostname-length fixes:

```text
PASS: all generic devcontainer kit tests passed
```

- Latest targeted verification for release README publication passed:

```bash
bash -n scripts/release-build.sh tests/release-build.sh
tests/release-build.sh
git diff --check
```

- Latest runtime release publish passed:

```bash
tests/release-build.sh
task release-build -- release --push
git ls-remote --heads origin refs/heads/release
git ls-tree -r --name-only release
diff -u README_release.md <(git show release:README.md)
```

- The pushed `release` branch and `.devcontainer` submodule checkout both point
  at `7b18c2adcba4cf7002aafc3a0490d489902a7c2d`.

- Latest full-suite attempt ran `task tests-run` and failed inside the Dev
  Containers image build while extracting `scc` with
  `tar: scc: Wrote only 2560 of 10240 bytes`. Treat this as the current
  environment/build-storage blocker, not a completed full-suite pass.

- Latest targeted verification for the release command save preflight passed:

```bash
git diff --check
```

- Latest full-suite attempts for the release command save preflight ran
  `task tests-run` twice. Both failed inside the Dev Containers image build:
  first with BuildKit `no space left on device`, then with a truncated `scc`
  extraction while building the same image. Treat this as an environment/storage
  blocker, not a completed full-suite pass.

- Earlier full-suite attempts for the `.env` rename ran `task tests-run` twice
  and hit Docker storage exhaustion while Compose still mounted
  `/var/lib/docker` as a 16G tmpfs. Targeted checks for the rename passed before
  that full-suite blocker.

- Latest targeted verification for the `.env` rename passed:

```bash
bash -n initialize.sh .devcontainer/initialize.sh tests/initialize.sh tests/devcontainer-up.sh tests/code-open-args.sh tests/devcontainer-worktree-up.sh tests/submodule-workflow.sh
```

- The full `_devcontainer_new` suite passed earlier from the parent workspace
  after the UID fallback change:

```bash
bash _devcontainer_new/tests/run.sh
```

- Result from the latest cached run:

```text
PASS: all generic devcontainer kit tests passed
test suite completed in 30s
```

- The suite covers:
  - initialization and generated files
  - Compose config resolution
  - branch worktree setup
  - local Docker image build
  - TTY `docker-run`
  - `devcontainer up`
  - `BRANCH` + `devcontainer up`
  - real consuming-repo submodule workflow with commit and fast-forward merge
- Latest targeted verification for the `code-open` workflow passed:

```bash
bash -n scripts/code-open.sh tests/code-open-test.sh tests/code-open-args.sh tests/helpers.sh tests/run.sh
tests/code-open-args.sh
task --dry code-open -- develop0
task --dry code-open-test -- develop0
```

- Latest targeted verification for the `release-build` workflow passed:

```bash
bash -n scripts/release-build.sh tests/release-build.sh tests/run.sh
tests/release-build.sh
task --dry release-build -- --push
git diff --check
```

- Latest targeted verification for the OpenCode mount and fixture cleanup work
  passed:

```bash
bash -n tests/helpers.sh tests/code-open-args.sh tests/initialize.sh tests/run.sh
bash -n tests/opencode-mounts.sh tests/run.sh
tests/code-open-args.sh
tests/initialize.sh
tests/opencode-mounts.sh
tests/release-build.sh
git diff --check
```

- Latest targeted verification for the `.oc_local` OpenCode bootstrap work
  passed:

```bash
bash -n initialize.sh .devcontainer/initialize.sh tests/initialize.sh tests/devcontainer-up.sh tests/opencode-startup.sh tests/run.sh
bash -n scripts/release-build.sh tests/release-build.sh
tests/initialize.sh
tests/opencode-startup.sh
tests/devcontainer-up.sh
tests/release-build.sh
```

- `tests/opencode-startup.sh` remains as a focused non-interactive regression
  test. The full suite uses the same OpenCode bootstrap assertion inside
  `tests/devcontainer-up.sh` to avoid an extra devcontainer startup and avoid
  hanging on the real TUI.

- A later full `task tests-run` attempt was blocked by Docker Hub unauthenticated
  pull rate limits while pulling `debian:bookworm-slim`, not by a test assertion.

- Latest targeted verification for the stale `dockerd` log fix:

```bash
bash -n entrypoint.sh tests/docker-run.sh
git diff --check
```

- A `task docker-run` attempt for the same fix was blocked before reaching the
  edited entrypoint layer when the local Docker builder failed extracting the
  external `scc` tarball with `tar: scc: Wrote only ... bytes`.

## Known Local Artifacts

- Two manual VS Code reality-test containers were intentionally left by the
  previous workflow:
  - `c4d66d1a4a34`
  - `7a5a733031ea`
- They came from manual `code-open-test` runs and are not automatic-suite leaks.

## Next Steps

- If opening the real editor flow again, use:

```bash
task code-open-test
task code-open-test -- develop0
task code-open
task code-open -- develop0
```
