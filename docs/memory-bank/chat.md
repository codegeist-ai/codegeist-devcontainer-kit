# Project Memory

## Current Goal

- This repository maintains the reusable `codegeist-devcontainer-kit` for
  consuming projects that want the normal VS Code Dev Containers workflow with
  the current Codegeist/planner-style toolchain.
- OpenCode work should continue from `/workspace`, this repository root.

## Current State

- Local default branch is `main`.
- `.devcontainer/` and `.opencode/` are checked-out shared submodules in this
  development repository. Do not edit them directly during normal project work
  unless the task is explicit submodule work.
- `.devcontainer` currently points at runtime `release` commit
  `26332d0e12b9e24c02a9353ae1c4389e7986a8b7`.
- `Dockerfile` installs `@mermaid-js/mermaid-cli` with the global npm tooling
  alongside `opencode-ai`, `repomix`, `@ast-grep/cli`, and
  `@devcontainers/cli`.
- `compose.local.yml` and `compose.local.yml.example` are intentionally minimal
  override files with `services: {}`. Shared defaults belong in
  `docker-compose.yml`; local or consuming-repo overrides can be added only when
  needed.
- The parent repository may still see this directory as an untracked nested Git
  repo; treat this repository as the source of truth for kit work.

## Kit Contract

- Consuming repositories install this kit at `.devcontainer/` as either a Git
  subtree or a Git submodule.
- `devcontainer.json` is the VS Code / Dev Containers entrypoint.
- `initialize.sh` is the host-side `initializeCommand`; it creates local config,
  generated runtime files, root `.oc_local/`, and optional branch worktrees.
- Normal flow starts from the consuming repository root with `code .`.
- Worktree flow also starts from the consuming repository root with
  `BRANCH=<branch> code .`; Compose mounts `.worktrees/<branch>` at
  `/workspace`.
- Generated runtime files such as `.local.env`, `.devcontainer/.env`,
  `.devcontainer/compose.local.gen.yml`, `.oc_local/`, `compose.local.yml`, and
  `.worktrees/` should stay untracked unless a consuming repository explicitly
  owns an overlay.

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

## Verification

- Latest full `task tests-run` passed after pruning Docker storage.
- Latest `tests/release-build.sh` and `task release-build -- release --push`
  passed, publishing runtime `release` commit
  `26332d0e12b9e24c02a9353ae1c4389e7986a8b7`.
- The suite covers initialization, Compose config resolution, branch worktree
  setup, local Docker image build, TTY `docker-run`, `devcontainer up`,
  `BRANCH` + `devcontainer up`, and the consuming-repo submodule workflow.

## Useful Commands

```bash
task tests-run
task code-open
task code-open -- develop0
task code-open-test
task code-open-test -- develop0
task release-build -- release --push
```
