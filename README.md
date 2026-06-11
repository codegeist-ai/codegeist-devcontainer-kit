# Devcontainer Kit

Reusable `.devcontainer/` toolkit for projects that want the normal VS Code Dev
Containers workflow with the current Codegeist/planner development toolchain.

## Purpose

This repository is a reusable devcontainer kit that can be added to other
repositories at `.devcontainer/`, either as a Git subtree or as a Git submodule.
The source `Dockerfile.base` intentionally carries the full
Codegeist/planner-style toolchain, including Docker CE, Node 24, VS Code,
GitHub CLI, Maven, GraalVM, Hugo, Nix, OpenCode tooling, Repomix, Kubernetes and
infrastructure CLIs, QEMU/KVM virtualization tools, `espeak-ng`, network
diagnostics, password-store tooling through `pass`, and related CLI tools. The
release build publishes this file as `.devcontainer/Dockerfile` for consuming
repositories.

The consuming project should use the standard VS Code flow:

1. Clone the consuming repository.
2. Open the repository folder in VS Code.
3. Run `Dev Containers: Reopen in Container`.

The kit should not require a root-level launcher such as `start.sh` for normal
VS Code usage. It should also not open VS Code from its own scripts. VS Code and
the Dev Containers extension own the container lifecycle.

The devcontainer user follows the host `$USER`: `remoteUser` and
`containerUser` both use `${localEnv:USER}`. `initialize.sh` writes matching
generated Docker build arguments and numeric runtime user values so the user
exists in the image and bind-mounted files use the host UID for both the
numeric user and group.

The same configuration can be smoke-tested without opening VS Code by running
the Dev Containers CLI against the repository root:

```bash
npx --yes @devcontainers/cli up --workspace-folder <repo-root>
```

VS Code opens the container workspace at an absolute host-matching path. Without
`BRANCH`, that path resolves back to the repository root. With `BRANCH`,
`initializeCommand` creates or reuses the matching Git worktree and
`devcontainer.json` opens `.worktrees/<branch>` as the remote workspace while
`docker-compose.yml` still mounts the repository root at its host path for
linked-worktree Git metadata. Keeping stable per-checkout paths prevents
OpenCode sessions from being mixed across projects or branches.

## Quick Start For Consuming Repos

Use one of the two installation modes below to place this kit at
`.devcontainer/` in a consuming repository. After installing it, add these local
files to the consuming repository's `.gitignore`:

```gitignore
/.codegeist/.local.env
/.oc_local/
/.worktrees/
```

Ignore `/.oc_local/` only when the consuming repository does not intentionally
track project-specific OpenCode overlay files there. Do not ignore
`.codegeist/compose.local.yml` or `.codegeist/Dockerfile` if the repository
creates them for intentional Compose or image overrides; they should stay
visible to Git.

If these patterns are missing, `initialize.sh` adds them to the repository root
`.gitignore`. It never writes generated-file ignores to `.git/info/exclude`, so
review and commit intentional `.gitignore` changes like normal repository state.

Open the consuming repository root in VS Code and run
`Dev Containers: Reopen in Container`:

```bash
code .
```

To select a managed Git worktree from VS Code Remote SSH, set `BRANCH` in the
SSH environment and reopen the repository root in the container. The Dev
Containers lifecycle creates `.worktrees/<branch>` and opens that checkout as
the remote workspace. If `BRANCH` names the already checked-out branch, such as
`BRANCH=main` on `main`, `.worktrees/<branch>` is a symlink alias back to the
repository root:

```sshconfig
Host project-dev0
  SetEnv BRANCH=develop0
```

The same path can be smoke-tested with the Dev Containers CLI:

```bash
BRANCH=develop0 npx --yes @devcontainers/cli up --workspace-folder <repo-root>
```

For a plain local VS Code command where an existing VS Code process may not
inherit new environment variables, prepare the worktree from the consuming
repository root and then open that checkout:

```bash
BRANCH=develop0 .devcontainer/initialize.sh
code .worktrees/develop0
```

The first start creates local and generated files when missing:

- `.codegeist/.local.env`
- `.devcontainer/.env`
- `.devcontainer/Dockerfile.merged.gen`
- `.devcontainer/compose.local.gen.yml`
- `.devcontainer/compose.user.gen.yml`, an ignored bridge to optional
  `.codegeist/compose.local.yml` overrides
- root `.oc_local/` with a local `.gitignore` for workspace-specific OpenCode
  config, when missing
- root `.worktrees/`; `.worktrees/<branch>` as a worktree or current-branch
  symlink alias when `BRANCH` is set

The kit also ships `.oc_local.opencode.json.example` as an inactive template for
`.oc_local/opencode.json`. When consumed as `.devcontainer/`, copy
`.devcontainer/.oc_local.opencode.json.example` to `.oc_local/opencode.json`
only when the consuming project wants a tracked local OpenCode overlay. The
template loads `README.md` first, then local rule files with the `rules/**/*.md`
instruction pattern; in the runtime release, that `README.md` is generated from
`README_release.md`.

The initializer creates writable `.oc_local/` and `.oc_local/.gitignore`, but it
never copies the template or overwrites `.oc_local/opencode.json`. If a consuming
repository tracks `.oc_local/`, remove or narrow generated ignores and keep
secrets out of tracked local overlay files.

When upgrading an older checkout, `initialize.sh` copies legacy root `.local.env`
or `compose.local.yml` into the matching `.codegeist/` path only when the new
file does not exist. It does not delete the legacy files and does not migrate a
root `Dockerfile`; move devcontainer image extensions to `.codegeist/Dockerfile`
manually if needed.

Do not edit `.devcontainer/.env`, `.devcontainer/Dockerfile.merged.gen`, or
`.devcontainer/compose.local.gen.yml` or `.devcontainer/compose.user.gen.yml`;
they are regenerated by `initialize.sh`. Put manual runtime overrides in
`.codegeist/.local.env`, local Compose overrides in `.codegeist/compose.local.yml`,
and devcontainer image extensions in `.codegeist/Dockerfile` instead. Create the
Compose and Dockerfile override files only when the repository needs them.

## Local Dockerfile Extensions

Consuming repositories can extend the devcontainer image without editing the
`.devcontainer/` submodule by adding `.codegeist/Dockerfile` only when a local
image extension is needed. During `initializeCommand`, `initialize.sh` writes
`.devcontainer/Dockerfile.merged.gen` from the release kit base at
`.devcontainer/Dockerfile` and appends root `.codegeist/Dockerfile` as a
project-local fragment when that file exists.

Create the extension from the template on demand:

```bash
mkdir -p .codegeist
cp .devcontainer/Dockerfile.example .codegeist/Dockerfile
```

A root `Dockerfile` remains available for application images and is not treated
as a devcontainer extension. Treat `.codegeist/Dockerfile` only as an extension
fragment:

```Dockerfile
# .codegeist/Dockerfile - project-local devcontainer extension

USER root
RUN npm install -g some-coding-agent-tool
USER ${CONTAINER_USER}
```

Do not put `FROM` in the `.codegeist/Dockerfile` fragment. A `FROM` instruction
would start a new stage and can replace the prepared kit image, so
`initialize.sh` rejects it with a clear error. `COPY` and `ADD` paths are still
resolved from the consuming repository root because the Docker build context
remains the project root.

`docker-compose.yml` builds `.devcontainer/Dockerfile.merged.gen`; do not edit or
commit that generated file.

## Local Compose Overrides

Consuming repositories can override Compose settings without editing the
`.devcontainer/` submodule by creating `.codegeist/compose.local.yml` from the
template only when an override is needed:

```bash
mkdir -p .codegeist
cp .devcontainer/compose.local.yml.example .codegeist/compose.local.yml
```

`initialize.sh` writes `.devcontainer/compose.user.gen.yml` on every start. The
generated bridge is an empty `services: {}` file by default, or a copy of
`.codegeist/compose.local.yml` when that on-demand override exists.

## Browser Support

The devcontainer image includes Google Chrome for browser checks and visible
browser sessions that must run from inside the container's network, DNS, and
certificate trust context. The shared kit installs a `chrome` launcher for direct
visible browser startup when the devcontainer has access to a host display, and
the same launcher supports deterministic headless automation for tests. It does
not add VNC, noVNC, browser profiles, bookmarks, credentials, or
project-specific service URLs.

Run visible Chrome from a terminal inside the devcontainer when you need to load
a URL with container-side DNS and certificates:

```bash
chrome https://example.test
```

The visible command does not start VNC or noVNC. It expects `DISPLAY` or
`WAYLAND_DISPLAY` to be available inside the container through the user's
devcontainer/host display setup. `initialize.sh` writes the host-side `DISPLAY`
visible to `initializeCommand` into `.devcontainer/.env` as
`DEVCONTAINER_DISPLAY`, and Compose passes that generated value into the
container. This keeps each VS Code or Dev Containers CLI start tied to the X11
forwarding endpoint it was opened with instead of inheriting a stale display from
a later long-lived process. If SSH X11 forwarding moves from one display number
to another, reopen or rebuild the devcontainer so `initializeCommand` refreshes
the generated value. For SSH X11 forwarding, the launcher copies the current
Xauthority file to a temporary file and adds localhost aliases when the cookie is
stored under the forwarded `/unix:<display>` name. Chrome stores its normal
profile data in the container user's home directory by default, so cookies and
browser state stay in the devcontainer rather than in a host browser profile. In
this repository, the same command can be exercised from the kit image:

```bash
task browser-open-test
```

Pass a URL after `--` when you want the visible test fixture to open a specific
page instead of its local data URL default.

For non-interactive tests and automation, use the same launcher in headless mode:

```bash
chrome --headless --dump-dom https://example.test
```

The workspace service sets `shm_size: '1gb'` because Chrome and other browser
processes can fail with Docker's small default `/dev/shm`. Chrome hardware
acceleration is disabled by a managed policy at
`/etc/opt/chrome/policies/managed/disable-hardware-accel.json`.

The repository test suite also includes a Chrome DevTools Protocol UI smoke test
in `tests/browser-smoke.sh`. It starts a Dev Containers CLI fixture, launches
Chrome through `chrome --headless` inside the workspace container, captures
a PNG screenshot of a container-local HTML file, and compares rendered
accessibility text against the expected value. This keeps the test path aligned
with the visible launcher while staying deterministic in CI-like environments.

## QEMU Support

The devcontainer image includes QEMU/KVM tooling for local VM and ISO workflows:
`qemu-system-x86_64`, `qemu-img`, `qemu-kvm`, `cloud-localds`, bridge/network
utilities, and small automation helpers such as `expect`, `sshpass`, and
`pwgen`. The Compose runtime is privileged, maps `/dev/kvm` explicitly, and adds
the numeric KVM device group so QEMU can use host virtualization devices when the
host exposes them. `initialize.sh` writes `DEVCONTAINER_KVM_GID` from
`stat -c %g /dev/kvm`; existing generated env files can use `KVM_GID` in
`.codegeist/.local.env` as a manual override when needed.

The smoke path requires `/dev/kvm` to be available and writable inside the
container. It downloads pinned Alpine Linux `3.20.3` into
`.test-tmp/qemu-cache/` and boots the ISO with QEMU KVM acceleration until the
fixed `localhost login:` prompt appears:

```bash
task qemu-alpine-smoke
```

The test fails when `/dev/kvm` is missing or not writable. Hosts that run the
devcontainer inside another VM must enable nested virtualization before this
suite can pass.

## Develop This Kit

Clone this repository with submodules initialized because `.devcontainer/` and
`.opencode/` are shared workspace submodules:

```bash
git clone --recurse-submodules <this-repo-url>
cd <repo>
```

If the repository was already cloned without submodules, initialize them later:

```bash
git submodule update --init --recursive
```

Run the local test suite from this repository root:

```bash
task tests-run
```

Open the current Git root with the real VS Code entrypoint:

```bash
task code-open
task code-open -- develop0
```

`BRANCH=develop0 task code-open` is still accepted for shell-driven runs. When a
branch is selected, the command prepares `.worktrees/<branch>` and opens VS Code
from that worktree without forwarding `BRANCH` into the opened VS Code process.

Run the fixture-backed reality test when you need to exercise the same command
against a temporary consuming repository:

```bash
task code-open-test
task code-open-test -- develop0
```

The reality test intentionally leaves its temporary fixture and VS Code-started
container in place because VS Code is opened against that fixture.

Update the runtime-only `release` branch when consuming repositories should pin
the kit as a stable `.devcontainer` submodule branch:

```bash
task release-build
```

The release task must run from a clean `main` checkout. The first run creates an
orphan `release` branch and commits only the files required by the Dev
Containers runtime. Later runs update the same runtime-only branch. Add `--push`
to push the branch after it is updated locally:

```bash
task release-build -- --push
```

The release branch tree contains only:

```text
.gitignore
.local.env.example
.oc_local.gitignore.example
.oc_local.opencode.json.example
Dockerfile
Dockerfile.example
README.md
compose.local.yml.example
devcontainer.json
docker-compose.yml
entrypoint.sh
initialize.sh
scripts/chrome.sh
```

`scripts/release-build.sh` copies source `Dockerfile.base` into the release tree
as `Dockerfile` and ships `Dockerfile.example` as the on-demand template for root
`.codegeist/Dockerfile`; do not add a tracked root `Dockerfile` to the source
checkout for the kit base image.

## OpenCode Workspace

This repository includes `.opencode/` as a Git submodule pointing to
`https://github.com/codegeist-ai/codegeist-agent-kit`. It provides shared
OpenCode commands, rules, and skills used while maintaining this kit.

Keep it initialized for development work:

```bash
git submodule update --init --recursive .devcontainer .opencode
```

The submodule is not part of the consuming `.devcontainer/` runtime contract;
it is repository-local AI workflow support for this kit. Project-specific
OpenCode commands, rules, and skills belong in `.oc_local/`, not in the checked
out `.opencode/` submodule.

## Git Subtree Setup

Use a Git subtree when a project should vendor this kit into `.devcontainer/`
without making consumers initialize a submodule. The consuming repository stores
the kit files directly in its history, while still allowing updates from the
upstream kit repository.

Add the kit to a consuming repository:

```bash
git remote add devcontainer-kit <kit-repo-url>
git fetch devcontainer-kit
git subtree add --prefix=.devcontainer devcontainer-kit <branch> --squash
```

Replace `<kit-repo-url>` with this repository URL and `<branch>` with the kit
branch to consume, for example `main`.

Update the vendored kit later:

```bash
git fetch devcontainer-kit
git subtree pull --prefix=.devcontainer devcontainer-kit <branch> --squash
```

Commit the subtree add or pull like any other source change in the consuming
repository.

If the consuming repository already has a `.devcontainer/` directory, move or
remove that directory first. `git subtree add` expects the target prefix to be
absent or empty.

The consuming repository should ignore local files generated next to the subtree:

```gitignore
/.codegeist/.local.env
/.oc_local/
/.worktrees/
```

Do not ignore `/.oc_local/` if the consuming repository deliberately tracks a
project-local OpenCode overlay there. Do not ignore `.codegeist/compose.local.yml`
or `.codegeist/Dockerfile`; they should remain visible to Git.

The kit also writes generated runtime files inside `.devcontainer/`:
`.env`, `Dockerfile.merged.gen`, `compose.local.gen.yml`, and
`compose.user.gen.yml`. They are ignored by the kit's own `.gitignore` and
should not be edited manually.

`initializeCommand` is not a bootstrap mechanism for downloading the kit. If
`.devcontainer/devcontainer.json` is not present in the checkout, VS Code cannot
discover or run the devcontainer configuration at all.

## Git Submodule Setup

Use a Git submodule when the consuming repository should keep the kit as a
separate repository mounted at `.devcontainer/`.

Add the kit to a consuming repository:

```bash
git submodule add <kit-repo-url> .devcontainer
git commit -m "chore(devcontainer): add shared kit submodule"
```

Pin the release branch when the consuming project should use a stable
runtime-only tree:

```bash
git -C .devcontainer fetch origin release
git -C .devcontainer checkout origin/release
git add .devcontainer
git commit -m "chore(devcontainer): pin shared release kit"
```

Clone or update consuming repositories with submodules initialized:

```bash
git submodule update --init --recursive
```

The same generated root files must still be ignored by the consuming repository:

```gitignore
/.codegeist/.local.env
/.oc_local/
/.worktrees/
```

The `.devcontainer/.env`, `.devcontainer/Dockerfile.merged.gen`,
`.devcontainer/compose.local.gen.yml`, and `.devcontainer/compose.user.gen.yml`
files are generated by the kit inside the submodule checkout and intentionally
ignored there.

The kit also creates root `.oc_local/` for `OPENCODE_CONFIG_DIR` so OpenCode can
bootstrap in fresh devcontainers. When the consuming repository does not track a
`.oc_local/` overlay, `initialize.sh` adds the missing local-file patterns to
that repository's root `.gitignore`; it never writes them to `.git/info/exclude`.

The test suite includes a real submodule-consuming fixture that starts
`BRANCH=dev0` through `devcontainer up`, verifies the selected workspace path,
nested Docker, and a commit/fast-forward merge flow from inside the container.

## Normal VS Code Workflow

The primary entrypoint is `devcontainer.json`.

The intended flow is:

```text
VS Code opens repository
Dev Containers extension reads .devcontainer/devcontainer.json
initializeCommand creates local compose/env files when missing
Docker Compose builds and starts the workspace service
VS Code attaches to the workspace service
```

This means the kit should avoid old launcher-style behavior in the normal VS
Code path:

- no `code --new-window` from repository scripts
- no recursive reopen-in-container behavior
- no root `start.sh` dependency
- no project-specific assumptions such as `CODEGEIST_*`

## initializeCommand Contract

`initializeCommand` is the only standard devcontainer lifecycle hook that runs
on the host before the container exists. It is useful for preparing local files
that Docker Compose or the container runtime will consume.

Recommended shape:

```json
{
  "initializeCommand": ".devcontainer/initialize.sh"
}
```

The initializer must be:

- idempotent
- non-interactive
- fast enough for repeated starts
- safe when run multiple times in one VS Code session
- limited to host-side preparation

It must not:

- open VS Code
- start long-running foreground processes
- start or remove the devcontainer project
- delete user data or running containers
- assume it runs only once
- rely on exporting variables back into VS Code

It may:

- create `.codegeist/.local.env` from `.devcontainer/.local.env.example`, or
  copy legacy root `.local.env` there when it already exists and the new file is
  missing
- create `.codegeist/compose.local.yml` from
  `.devcontainer/compose.local.yml.example`, or copy legacy root
  `compose.local.yml` there when it already exists and the new file is missing;
  this file is not ignored automatically
- create root `.oc_local/` for workspace-local OpenCode config
- write `.devcontainer/.env`, `.devcontainer/Dockerfile.merged.gen`, and
  `.devcontainer/compose.local.gen.yml` generated runtime values such as the
  container hostname, hostname loopback resolution, and numeric runtime user
- update generated local env values when their content changed
- compute host UID
- compute a stable project name
- compute the host short name
- create local cache/config directories
- validate required host tools and print clear errors

## Environment Model

`initializeCommand` cannot export environment variables back into the already
running VS Code process. Values produced by `initialize.sh` should therefore be
written to files, not expected to appear as `${localEnv:...}` values.

Preferred pattern:

1. `initialize.sh` writes `.codegeist/.local.env`.
2. `initialize.sh` migrates a legacy root `compose.local.yml` into
   `.codegeist/compose.local.yml` only when that legacy file exists.
3. `initialize.sh` writes `.devcontainer/.env`, including the host-side
   `DISPLAY` value as `DEVCONTAINER_DISPLAY` when one is present.
4. `initialize.sh` writes `.devcontainer/Dockerfile.merged.gen`.
5. `initialize.sh` writes `.devcontainer/compose.local.gen.yml`.
6. `initialize.sh` writes `.devcontainer/compose.user.gen.yml`, either empty or
   copied from `.codegeist/compose.local.yml`.
7. `.devcontainer/docker-compose.yml` reads `.env` and
   `../.codegeist/.local.env` with `env_file`.
8. `devcontainer.json` includes `compose.local.gen.yml` and
   `compose.user.gen.yml`.
9. `.devcontainer/docker-compose.yml` owns the workspace and parent Git mounts.
10. `devcontainer.json` uses `${localEnv:USER}` for `remoteUser` and
   `containerUser`.
11. `docker-compose.yml` passes `DEVCONTAINER_DISPLAY` into the container as
    `DISPLAY` so SSH X11 forwarding follows the initialize-time environment.
12. Container-side tools read normal environment variables from Compose.

Example Compose shape:

```yaml
services:
  workspace:
    env_file:
      - path: .env
        required: false
      - path: ../.codegeist/.local.env
        required: false
```

Avoid generating values for `devcontainer.json` to read through
`${localEnv:...}`. The Dev Containers extension may have captured host
environment variables before `initializeCommand` writes anything, and clients may
need a restart to pick up changed host environment.

## Lifecycle Constraints

Official Dev Container lifecycle behavior relevant to this kit:

- `initializeCommand` runs on the host machine.
- It can run during container creation and on later starts.
- It may run more than once in a session.
- String commands run through `/bin/sh`.
- Array commands execute directly without a shell.
- If a lifecycle command fails, later lifecycle commands are skipped.

Implementation consequence: `initialize.sh` must fail only for real blockers and
must produce clear diagnostics. Best-effort setup should not make the whole
container unusable unless the missing state is required.

## CLI And IDE Differences

VS Code and the `devcontainer` CLI do not behave identically in every path.
Known problem areas from upstream discussions include:

- `devcontainer build` may not run `initializeCommand` like VS Code does.
- CLI rebuild ordering around existing containers can differ from VS Code.
- `initializeCommand` has been observed to run on reopen, not only first create.

Tests should therefore cover the behavior the kit relies on directly. A build
test alone is not enough to prove host initialization behavior.

## Test Strategy

The kit should be tested as close to the real workflow as possible with the
Dev Containers CLI. Prefer `devcontainer up` over only validating files or
running `docker compose` directly, because `devcontainer up` exercises the same
configuration model that VS Code uses.

Primary smoke command:

```bash
npx --yes @devcontainers/cli up --workspace-folder <fixture-repo>
```

If the CLI is installed globally, the shorter form is equivalent:

```bash
devcontainer up --workspace-folder <fixture-repo>
```

The smoke fixture should look like a real consuming repository:

- repository root contains project files
- `.devcontainer/` contains this kit
- VS Code/devcontainer configuration is read from `.devcontainer/devcontainer.json`
- `initializeCommand` runs through the devcontainer lifecycle, not by calling the
  initializer directly as the only assertion

Recommended test layers:

- fast contract tests for generated files and static configuration
- `devcontainer read-configuration` for schema/config resolution
- `devcontainer up` for the real lifecycle, including `initializeCommand`
- `devcontainer exec` or `docker exec` for observable checks inside the running
  workspace service
- QEMU image-level smoke tests with KVM acceleration when virtualization tooling
  changes, so the suite proves `/dev/kvm` works inside the container

The tests should verify at least:

- `.codegeist/.local.env` is created or preserved by `initializeCommand`
- root `.oc_local/` is created for OpenCode and ignored unless the repository
  tracks a project overlay there
- `.devcontainer/.env`, `.devcontainer/Dockerfile.merged.gen`,
  `.devcontainer/compose.local.gen.yml`, and
  `.devcontainer/compose.user.gen.yml` are regenerated by `initializeCommand`
- the generated container hostname matches host, repo, and branch context
- the generated runtime user and group match the host UID
- repeated `devcontainer up` runs stay safe and idempotent
- no VS Code window is opened by kit scripts
- no project-specific names such as `CODEGEIST_*` are required
- the workspace service starts and accepts a basic command
- QEMU can download and boot a small pinned Alpine Linux ISO to its login prompt
- generated local files are not accidentally tracked
- On-demand `.codegeist/compose.local.yml` and `.codegeist/Dockerfile` files
  remain visible to Git so repository overrides are not hidden accidentally

Use direct `docker compose` tests only for focused Compose behavior that the CLI
does not expose clearly. Do not treat a plain Compose test as a substitute for a
full devcontainer smoke test.

## File Layout

Expected target layout when consumed as a subtree at `.devcontainer/`:

```text
.codegeist/
  .local.env            # generated, ignored by the consuming repo
  compose.local.yml     # optional on-demand Compose override, visible to Git
  Dockerfile            # optional on-demand image extension fragment, visible to Git
.oc_local/              # generated or project-owned OpenCode local overlay
.devcontainer/
  .env                  # generated, ignored by the kit
  Dockerfile.merged.gen # generated, ignored by the kit
  compose.local.gen.yml # generated, ignored by the kit
  compose.user.gen.yml  # generated bridge to optional .codegeist/compose.local.yml
  devcontainer.json
  docker-compose.yml
  Dockerfile            # kit base image file in the release branch
  Dockerfile.example    # template for root .codegeist/Dockerfile
  entrypoint.sh
  initialize.sh
  scripts/
    chrome.sh
  .local.env.example
  compose.local.yml.example
  tests/
```

Roles:

- `devcontainer.json` is the VS Code entrypoint.
- `initialize.sh` performs host-side setup for `initializeCommand`.
- `docker-compose.yml` defines the workspace runtime and the root/worktree bind
  mounts.
- `.devcontainer/Dockerfile` is the release kit base image file; source checkouts
  keep the same content as `Dockerfile.base`. Root `.codegeist/Dockerfile` can
  extend it through the generated `Dockerfile.merged.gen` file.
- `entrypoint.sh` runs inside the container.
- `scripts/chrome.sh` is installed as `/usr/local/bin/chrome`; it starts visible
  Chrome on the current container display or headless Chrome for automation.
- `.local.env.example` documents `.codegeist/.local.env` values.
- `.oc_local.gitignore.example` seeds root `.oc_local/.gitignore` when the
  consuming repository has no tracked `.oc_local/` overlay.
- `.oc_local.opencode.json.example` is an inactive template for a tracked
  `.oc_local/opencode.json` that loads `README.md` and project-local
  `rules/**/*.md` guidance. Consuming repositories copy it from
  `.devcontainer/.oc_local.opencode.json.example` only when they intentionally
  track a local OpenCode overlay.
- `compose.local.yml.example` is the on-demand template for
  `.codegeist/compose.local.yml`; the result is visible to Git.
- `Dockerfile.example` is the on-demand template for `.codegeist/Dockerfile`;
  the result is visible to Git and must not contain `FROM`.
- `.env` exposes generated runtime values to Compose and the container.
- `Dockerfile.merged.gen` is the generated Docker build input used by Compose.
- `compose.local.gen.yml` sets generated Compose-only values such as hostname,
  hostname loopback resolution for tools like `sudo`, build args, and runtime
  user.
- `compose.user.gen.yml` is generated as an empty Compose override by default, or
  as a copy of `.codegeist/compose.local.yml` when that on-demand override exists.
- `tests/` verifies host initialization and container configuration contracts.

The root `.codegeist` files intentionally live one directory above
`.devcontainer/`. This keeps consuming-repository env, Compose, and optional
image-extension state out of the vendored subtree while keeping
devcontainer-specific files grouped together. `.codegeist/.local.env` is still
machine-local and ignored; optional `.codegeist/compose.local.yml` and
`.codegeist/Dockerfile` remain visible to Git.

The generated `.env`, `Dockerfile.merged.gen`, `compose.local.gen.yml`, and
`compose.user.gen.yml` files intentionally live in `.devcontainer/` because they
are kit-owned dynamic runtime state. They are rewritten by `initialize.sh`; users
should put manual overrides in `.codegeist/.local.env`, `.codegeist/Dockerfile`,
and `.codegeist/compose.local.yml` instead.

`launch.sh` is not part of the required normal VS Code workflow. If a launcher
is kept for compatibility or manual convenience, it should be documented as
optional and must not be required by `devcontainer.json`.

## Git Worktrees

The kit supports managed Git worktrees under `.worktrees/<branch>`. When
`BRANCH` is present in the VS Code Remote SSH or Dev Containers CLI environment,
the repository root can be opened directly and the devcontainer opens the
matching worktree as the remote workspace. If `BRANCH` matches the branch already
checked out at the repository root, `initialize.sh` creates
`.worktrees/<branch>` as a symlink alias back to that root instead of asking Git
for a second checkout of the same branch. The helper flow below is still useful
for local `code` invocations where an already running VS Code process may not
inherit a newly exported `BRANCH` value.

From this repository, use the helper task:

```bash
task code-open -- develop0
```

For a consuming repository that only has the runtime kit at `.devcontainer/`, a
Remote SSH host alias can select the worktree while the user opens the repository
root:

```sshconfig
Host project-dev0
  SetEnv BRANCH=develop0
```

The same branch selection can be tested without VS Code:

```bash
BRANCH=develop0 npx --yes @devcontainers/cli up --workspace-folder <repo-root>
```

For local `code` commands, prepare the worktree from the root and then open the
worktree path:

```bash
BRANCH=develop0 .devcontainer/initialize.sh
code .worktrees/develop0
```

During root preparation, `initialize.sh` creates `.worktrees/`, creates or
reuses `.worktrees/<branch>` when `BRANCH` is set, or creates a current-branch
symlink alias when the selected branch is already checked out. It initializes any
consuming-repository submodules when the repository defines them, creates root
`.codegeist/.local.env` from `.devcontainer/.local.env.example` when missing,
migrates a legacy root `.local.env` into `.codegeist/.local.env` when needed,
and links the worktree `.codegeist/.local.env` back to the main root file. When
the devcontainer starts from an already selected checkout, `initializeCommand`
writes that checkout's
`.devcontainer/.env`, `.devcontainer/Dockerfile.merged.gen`,
`.devcontainer/compose.local.gen.yml`, and `.devcontainer/compose.user.gen.yml`
without nesting another worktree for the same branch.

`BRANCH` is a startup input only. `initialize.sh` uses it to compute generated
workspace values and prepare worktrees, but does not persist `BRANCH=` into
`.devcontainer/.env`; later starts without `BRANCH` should resolve back to the
current checkout instead of reusing an older branch selection.

`docker-compose.yml` mounts the selected workspace at the same absolute path
inside the container. For linked worktrees it also mounts the parent repository
root at its same absolute path so Git metadata resolves.
`.codegeist/compose.local.yml` remains available for local overrides, but it does
not own the workspace or parent Git mounts.

Changing branches after a container already exists does not automatically remount
the running container. Rebuild or remove the existing devcontainer first, then
open the desired checkout again.

## VS Code Reality Test

Use `code-open` as the real editor entrypoint from a repository root. It refuses
to run outside Git, from a Git subdirectory, or without
`.devcontainer/devcontainer.json`.

```bash
task code-open
task code-open -- develop0
```

Use the manual reality test when you want to verify that same entrypoint through
a temporary consuming repository. It creates a temporary Git repository, copies
this kit into `.devcontainer/`, and then invokes the real `code-open` task
against that fixture.

```bash
task code-open-test
```

To verify branch selection through the normal helper flow:

```bash
task code-open-test -- develop0
```

`BRANCH=develop0 task code-open-test` is still accepted when an environment
variable is more convenient. The helper prepares the worktree before invoking
`code .` from that checkout, which stays stable even when an existing VS Code
process handles the `code` request.

The temporary fixture is intentionally left on disk because VS Code is opened
against it.

## Local Generated Files

Generated or machine-local files should not be committed.

Typical examples:

- `.codegeist/.local.env`
- `.devcontainer/.env`
- `.devcontainer/Dockerfile.merged.gen`
- `.devcontainer/compose.local.gen.yml`
- `.devcontainer/compose.user.gen.yml`
- `.oc_local/` when it is only generated OpenCode local state
- generated runtime metadata
- editor state
- tool caches

If a value must affect the runtime, write it to a local env file or another
documented generated file that Compose reads explicitly. Compose overrides in
`.codegeist/compose.local.yml` are visible to Git; commit only intentional
repository-wide overrides.

## Design Rules

The kit should remain reusable across repositories, while currently preserving
the copied Codegeist/planner image contents.

Avoid:

- product-specific names
- repository-specific paths
- assumptions about root `start.sh`
- hard-coded nested dependency names outside `.devcontainer` itself
- committed root `.env` or `.codegeist/.local.env`
- direct project-specific edits inside shared `.devcontainer/` or `.opencode/`
  submodule checkouts
- automatic VS Code window management

Prefer:

- stable Dev Container spec properties
- static `devcontainer.json` where possible
- local generated env files for host-dependent values
- explicit optional extension points for consuming repositories
- project-specific OpenCode overlays under `.oc_local/`
- tests that exercise the exact documented contract

## Roadmap Notes

- Docker-in-Docker is enabled by default because it is part of the current tested
  smoke path. A future variant may make it opt-in if consuming projects need a
  lighter image.
- SSH helper behavior is intentionally left to consuming repositories for now.
- The base image currently keeps the copied Codegeist/planner toolchain intact;
  future work can split generic tools from project-specific features when there
  is a concrete consumer need.
