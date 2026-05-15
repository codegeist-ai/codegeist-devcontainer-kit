# Project Memory

## Current Goal

- This repository maintains the reusable `codegeist-devcontainer-kit` for
  consuming projects that want the normal VS Code Dev Containers workflow with
  the current Codegeist/planner-style toolchain.
- OpenCode work should continue from this repository root, currently
  `/workspace` in the maintenance container.

## Current State

- Local default branch is `main`.
- `.devcontainer/` and `.opencode/` are checked-out shared submodules in this
  development repository. Do not edit them directly during normal project work
  unless the task is explicit submodule work.
- `.devcontainer` currently points at runtime `release` commit
  `35f46d91d952f483887aa0a94cb9f660a9291ab5`.
- `Dockerfile` installs `tiktoken-cli`, Mike Farah `yq`, network diagnostics,
  Kubernetes administration CLIs (`kubectl`, `helm`, `k9s`, `talosctl`), and
  infrastructure tools (`terraform`, `ansible`) in the default toolchain.
- `entrypoint.sh` starts nested `dockerd` without forcing a storage driver so
  Docker can use `overlay2` when available. Do not reintroduce `vfs` by default;
  it duplicates layers and can exhaust disk during full image builds.
- `compose.local.yml` and `compose.local.yml.example` are intentionally minimal
  override files with `services: {}`. Shared defaults belong in
  `docker-compose.yml`; local or consuming-repo overrides can be added only when
  needed.
- The parent repository may still see this directory as an untracked nested Git
  repo; treat this repository as the source of truth for kit work.

## Kit Contract

- Consuming repositories install this kit at `.devcontainer/` as either a Git
  subtree or a Git submodule.
- `README_release.md` documents the runtime-release consumer path: pin
  `.devcontainer` to the kit's runtime-only `release` branch, not `main`.
- `devcontainer.json` is the VS Code / Dev Containers entrypoint.
- `devcontainer.json` includes default VS Code extensions for Docker, YAML,
  Nushell, Excalidraw, Mermaid, PlantUML, Spring Boot, Java, and Helm editing.
- `initialize.sh` is the host-side `initializeCommand`; it creates local config,
  generated runtime files, root `.oc_local/`, and optional branch worktrees.
- Normal flow starts from the consuming repository root with `code .`.
- Worktree flow prepares from the consuming repository root with
  `BRANCH=<branch> .devcontainer/initialize.sh`, then opens
  `.worktrees/<branch>` directly. The container workspace path matches that
  checkout's absolute host path so OpenCode sessions do not collapse across
  projects or branches that would otherwise all appear as `/workspace`.
- In this repository, `task code-open -- <branch>` performs that prepare-then-open
  flow and invokes `code .` from the selected worktree.
- `task code-open-test -- <branch>` now runs the real `code-open` path and then
  starts the fixture through Dev Containers CLI, so terminal cwd failures after
  container startup are caught by the test.
- Generated runtime files such as `.local.env`, `.devcontainer/.env`,
  `.devcontainer/compose.local.gen.yml`, `.oc_local/`, `compose.local.yml`, and
  `.worktrees/` should stay untracked unless a consuming repository explicitly
  owns an overlay.
- Generated `.oc_local/.gitignore` now ignores everything in the local OpenCode
  overlay and the initializer excludes both `/.oc_local/` and
  `/.oc_local/.gitignore` when no tracked project overlay exists.
- The runtime kit creates writable `.oc_local/` when no tracked overlay exists,
  but does not ship this repository's development-only `.opencode/` checkout.
- Consuming repositories that want shared OpenCode commands, rules, and skills
  should add `https://github.com/codegeist-ai/codegeist-agent-kit` as a separate
  `.opencode` submodule.
- Project-specific OpenCode behavior belongs in `.oc_local/`; only update the
  `.opencode/` submodule itself when changing the shared agent kit for every
  consumer.

## Workflow Decisions

- No root-level launcher is required for normal VS Code usage.
- `initializeCommand` must stay idempotent, non-interactive, host-side only, and
  must not open VS Code or start/remove containers.
- Tests should exercise the real Dev Containers lifecycle when behavior depends
  on VS Code or the Dev Containers CLI integration.
- After code, script, or workflow changes, run the complete `task tests-run`
  suite before handoff when the environment allows it. If the environment blocks
  the full suite, report the blocker and list targeted checks that passed.
- Runtime releases are published from clean `main` with `task release-build`;
  use `--push` only when the branch should be pushed immediately.
- The local `release-build` command workflow now requires `save` to finish,
  then a clean-worktree check, then `task tests-run`, then
  `tests/release-build.sh`, before publishing with
  `task release-build -- release --push`.
- In consuming repos, treat both `.devcontainer/` and `.opencode/` as submodules:
  do not customize one project by editing their checked-out contents directly.

## Verification

- Latest `task tests-run` is blocked by Docker Hub's unauthenticated pull rate
  limit for `debian:bookworm-slim` after the initialize test reaches a worktree
  Dev Containers config with absolute worktree and repo-root mounts.
- Passing checks from the current workspace-path update:
  `bash -n initialize.sh tests/initialize.sh tests/devcontainer-worktree-up.sh tests/submodule-workflow.sh tests/worktree.sh`,
  `git --no-pager diff --check`, `bash tests/code-open-args.sh` with a temp
  suite dir, and `CODE_OPEN_TEST_SKIP_UP=true task code-open-test -- dev1`.
- The release workflow must rerun `task tests-run` after save and the
  clean-worktree check before publishing.
- `.devcontainer` is already checked out at runtime release
  `35f46d91d952f483887aa0a94cb9f660a9291ab5`.
- The suite covers initialization, Compose config resolution, branch worktree
  setup, local Docker image build, TTY `docker-run`, root `devcontainer up`,
  direct worktree `devcontainer up`, and the consuming-repo submodule workflow.

## Useful Commands

```bash
task tests-run
task code-open
task code-open -- develop0
task code-open-test
task code-open-test -- develop0
task release-build -- release --push
```
