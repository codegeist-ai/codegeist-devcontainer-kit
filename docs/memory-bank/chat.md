# Project Memory

## Current Goal

- This repository maintains the reusable `codegeist-devcontainer-kit` for
  consuming projects that want the normal VS Code Dev Containers workflow with
  the current Codegeist/planner-style toolchain.
- Browser support task `docs/tasks/T001_add_browser_support_to_devcontainer/task.md`
  is finalized. The kit installs Google Chrome from the official Linux `.deb`,
  disables hardware acceleration through a managed Chrome policy, sets Compose
  `shm_size: '1gb'`, and verifies headless/rendered browser behavior through Dev
  Containers CLI-started fixtures.
- The user clarified the UI-level browser test must stay inside `T001_01`, not a
  separate child task. The implemented UI mechanism is a dependency-free Chrome
  DevTools Protocol test driven by Node 24 inside the Dev Containers CLI-started
  workspace. It launches Chrome, captures a PNG screenshot, reads the rendered
  accessibility tree, and compares expected versus actual content without manual
  screen inspection.
- The user then clarified that Chrome must also be visible without VNC/noVNC.
  `T001_02` adds the shared `chrome` launcher: visible mode starts Chrome on the
  current container display and stores the normal Chrome profile in the container
  user's home; test mode uses `chrome --headless` so the browser smoke remains
  deterministic. There is intentionally no `chrome-open` runtime alias. In the
  current maintenance environment, direct visible verification passes with
  `DISPLAY=localhost:10.0 XAUTHORITY=/home/test/.Xauthority task
  browser-open-test`; the runtime Compose defaults use host networking so SSH X11
  forwarding reaches the host-side listener from inside the container. `code`
  working is not proof that GUI display forwarding works because VS Code can use
  its remote CLI path instead of opening an X11/Wayland GUI process.
- OpenCode work should continue from this repository root, currently
  `/workspace` in the maintenance container.

## Current State

- Local default branch is `main`.
- `.devcontainer/` and `.opencode/` are checked-out shared submodules in this
  development repository. Do not edit them directly during normal project work
  unless the task is explicit submodule work.
- `.devcontainer` currently points at runtime `release` commit
  `de44d108581224b67a4bbb30d5821d23eda37666` in the working tree.
- `Dockerfile` installs `tiktoken-cli`, Mike Farah `yq`, network diagnostics,
  QEMU/KVM virtualization tools, Kubernetes administration CLIs (`kubectl`,
  `helm`, `k9s`, `talosctl`), and infrastructure tools (`terraform`,
  `ansible`) in the default toolchain.
- `docker-compose.yml` maps `/dev/kvm` explicitly and adds the KVM device group
  through `DEVCONTAINER_KVM_GID`, falling back to `KVM_GID` or `993` for older
  generated env files on the current host.
- `.gitmodules` configures both `.devcontainer` and `.opencode` to track their
  `release` branches so the shared submodule update workflow can refresh them.
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
- Lightweight task handoff files now live under `docs/tasks/`; top-level tasks
  use `TNNN_<slug>.md` and the canonical open status is `open`.
- `initializeCommand` must stay idempotent, non-interactive, host-side only, and
  must not open VS Code or start/remove containers.
- Tests should exercise the real Dev Containers lifecycle when behavior depends
  on VS Code or the Dev Containers CLI integration.
- Test fixtures now use repo-local ignored temp roots (`.test-tmp/` and
  `.browser-smoke-tmp/`) because Docker bind mounts in this workspace cannot rely
  on arbitrary `/tmp` paths being visible to the daemon.
- Browser UI verification uses `tests/browser-ui-cdp.mjs`, a Node 24 Chrome
  DevTools Protocol driver invoked by `tests/browser-smoke.sh`; tests launch
  Chrome through `chrome --headless`, while users can run visible Chrome by
  typing `chrome` when the devcontainer has access to `DISPLAY` or
  `WAYLAND_DISPLAY`.
- After code, script, or workflow changes, run the complete `task tests-run`
  suite before handoff when the environment allows it. If the environment blocks
  the full suite, report the blocker and list targeted checks that passed.
- Runtime releases are published from clean `main` with `task release-build`;
  use `--push` only when the branch should be pushed immediately. This repository
  publishes runtime artifacts through the `release` branch only, not through
  SemVer selection or Git release tags.
- The local `release-build` command workflow now requires `save` to finish,
  then a clean-worktree check, then `task tests-run`, then
  `tests/release-build.sh`, before publishing with
  `task release-build -- release --push`.
- After pushing a release branch update, move the local `.devcontainer/`
  submodule checkout to the pushed `origin/release` commit and report the parent
  gitlink change. Do not update `.opencode/` or automatically commit the
  `.devcontainer` gitlink unless the user explicitly asks.
- In consuming repos, treat both `.devcontainer/` and `.opencode/` as submodules:
  do not customize one project by editing their checked-out contents directly.

## Verification

- Latest browser-support verification passed: `bash -n
  scripts/chrome.sh tests/browser-smoke.sh tests/run.sh
  tests/release-build.sh scripts/release-build.sh`, `node --check
  tests/browser-ui-cdp.mjs`, `git --no-pager diff --check`,
  `tests/release-build.sh`, `tests/browser-smoke.sh`, `task browser-open-test --
  --help`, `docker run --rm --entrypoint bash codegeist-devcontainer-kit:local
  -lc 'command -v chrome && ! command -v chrome-open'`, and `task tests-run`.
- Direct visible verification passed with `DISPLAY=localhost:10.0
  XAUTHORITY=/home/test/.Xauthority task browser-open-test`.
  `tests/browser-open-test.sh` now fails loudly and prints Chrome logs when Chrome
  exits before a real X11 Chrome window appears for the current temporary profile.
- The release workflow must rerun `task tests-run` after save and the
  clean-worktree check before publishing.
- `.devcontainer` is checked out at runtime release
  `de44d108581224b67a4bbb30d5821d23eda37666`.
- The suite covers initialization, Compose config resolution, branch worktree
  setup, local Docker image build, QEMU Alpine `3.20.3` ISO boot via KVM
  acceleration until `localhost login:`, TTY `docker-run`, browser smoke
  including CDP UI coverage, root `devcontainer up`, direct worktree
  `devcontainer up`, and the consuming-repo submodule workflow.

## Useful Commands

```bash
task tests-run
task qemu-alpine-smoke
task code-open
task code-open -- develop0
task code-open-test
task code-open-test -- develop0
task release-build -- release --push
```
