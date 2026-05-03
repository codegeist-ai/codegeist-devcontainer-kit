# Project Memory

## Current Goal

- This repository is the standalone `codegeist-devcontainer-kit` candidate.
- It provides a reusable `.devcontainer/` kit for consuming repositories that
  want the normal VS Code Dev Containers workflow with a Codegeist/planner-style
  development toolchain.
- OpenCode work should continue from this repository root, not from the parent
  `m7` workspace.

## Repository State

- The repository was initialized locally at `/home/test/Projects/m7/_devcontainer_new`.
- The local default branch is `main` and there are no commits yet.
- `.opencode/` is a Git submodule pointing to
  `https://github.com/codegeist-ai/codegeist-agent-kit`.
- The intended first commit has not been created yet.
- Current tracked/staged state before the first commit:
  - `.gitmodules` and `.opencode` are staged by `git submodule add`.
  - all kit source files are still untracked until staged for the initial commit.
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
  generated runtime files, and optional branch worktrees.
- `Taskfile.yaml` provides repo-local maintenance commands:
  - `task docker-build`
  - `task docker-run`
  - `task tests-run`
  - `task code-open-test`
- `tests/` contains the Bash smoke suite that exercises the real Dev Containers
  lifecycle.
- `README.md` is the primary usage documentation for consuming repos and for
  developing this kit.

## Usage Contract

- Consuming repositories install this kit at `.devcontainer/` either as a Git
  subtree or a Git submodule.
- Normal user flow from a consuming repository root:

```bash
code .
```

- Worktree flow still starts from the consuming repository root:

```bash
BRANCH=develop0 code .
```

- Without `BRANCH`, `/workspace` is the consuming repository root.
- With `BRANCH`, `initialize.sh` creates or reuses `.worktrees/<branch>` and
  Compose mounts that worktree as `/workspace`.
- The consuming repository root is also bind-mounted at its host path inside the
  container so linked-worktree Git metadata resolves correctly.
- Changing `BRANCH` does not remount an already existing devcontainer. Rebuild or
  remove the existing container before starting with another branch.

## Generated Files

- Consuming repositories should ignore these root-local files:

```gitignore
/.local.env
/compose.local.yml
/.worktrees/
```

- `initialize.sh` creates root `.local.env` from
  `.devcontainer/.local.env.example` when missing.
- `initialize.sh` creates root `compose.local.yml` from
  `.devcontainer/compose.local.yml.example` when missing.
- `initialize.sh` rewrites kit-owned `.devcontainer/.gen.env` and
  `.devcontainer/compose.local.gen.yml` on each start.
- Users should not edit `.devcontainer/.gen.env` or
  `.devcontainer/compose.local.gen.yml`; manual overrides belong in root
  `.local.env` or `compose.local.yml`.

## Important Decisions

- No root-level launcher is required for normal VS Code usage.
- `initializeCommand` must stay idempotent, non-interactive, host-side only, and
  must not open VS Code or start/remove containers.
- Dev Containers CLI verification should use real lifecycle commands, primarily
  `npx --yes @devcontainers/cli up --workspace-folder <fixture-repo>`.
- Tests should not replace lifecycle checks with direct calls to `initialize.sh`
  when the behavior depends on Dev Containers integration.
- The devcontainer user follows host `${localEnv:USER}` through both
  `remoteUser` and `containerUser`.
- Runtime `user` intentionally uses the host UID for both numeric user and group.
  `docker-compose.yml` has a static fallback: `${UID:-1000}:${UID:-1000}`.
- `BRANCH` path selection uses the literal branch name under `.worktrees/`; only
  generated hostnames use slugged branch names.
- Docker-in-Docker is enabled by default because it is part of the tested smoke
  path.
- `.opencode/` is for this kit repository's AI workflow support and is not part
  of the consuming `.devcontainer/` runtime contract.

## Verification Already Done

- The full `_devcontainer_new` suite passed from the parent workspace after the
  UID fallback change:

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

## Known Local Artifacts

- Two manual VS Code reality-test containers were intentionally left by the
  previous workflow:
  - `c4d66d1a4a34`
  - `7a5a733031ea`
- They came from manual `code-open-test` runs and are not automatic-suite leaks.

## Next Steps

- Stage the initial repository contents, including `.gitmodules`, `.opencode`,
  source files, tests, README, and this memory file.
- Suggested initial commit message:

```text
feat: add initial devcontainer kit

Add the generic Dev Containers kit with worktree-aware startup,
Docker-in-Docker support, local override templates, tests, and the shared
OpenCode agent kit submodule.
```

- Before or after the initial commit, optionally run the repo-local verification
  from this repository root:

```bash
task tests-run
```

- If opening the real editor flow again, use:

```bash
task code-open-test
BRANCH=develop0 task code-open-test
```
