# Add Chrome Browser Support And UI Test

- ID: `T001_01`
- Type: `feature`
- Status: `finalized`
- Parent: `T001`
- Source Reference: `docs/tasks/T001_add_browser_support_to_devcontainer/task.md`

## Goal

Add a reusable Google Chrome browser capability to the devcontainer kit and prove
through the Dev Containers CLI that Chrome can start inside the container, load
content from a container-local `file://` URL, and expose a UI-level test path for
rendered browser content.

## Context

The parent task specifies browser support for the shared devcontainer kit. The
user provided a reference implementation that installs Google Chrome from the
official Linux `.deb`, disables Chrome hardware acceleration through a managed
policy, and sets Compose `shm_size: '1gb'` for GUI stability. The user also
requires an automated test that starts the devcontainer through the Dev
Containers CLI, opens a container-local file in the browser, and compares
expected versus actual content.

This plan originally selected a deterministic headless Chrome launch path for the
first implementation slice. The user later clarified that a UI test must also be
part of this same task instead of a separate child task. The headless browser
contract and the UI-level Chrome DevTools Protocol test are now implemented and
verified.

The UI test must exercise a rendered browser path, not just a DOM dump. It should
still be automated and deterministic: the test runner should start or access the
browser UI through the devcontainer runtime, load content that exists only inside
the container, capture the rendered result, and compare that rendered result with
the expected value.

## Concrete Solution Direction

Install Google Chrome in `Dockerfile`, configure Chrome to disable hardware
acceleration, give the workspace container enough shared memory for browser
startup, document headless Chrome usage, add a Dev Containers CLI smoke test
that loads a known `file://` URL from inside the container with Chrome headless,
and add a UI-level browser test that drives Chrome through the Chrome DevTools
Protocol from inside a Dev Containers CLI-started workspace.

The browser readback mechanism is Chrome's headless DOM dump mode, for example
`google-chrome --headless --disable-gpu --no-sandbox --dump-dom file:///tmp/...`.
The test should compare the dumped page content against the expected text and
fail with an explicit expected-versus-actual message when they differ.

The UI-level mechanism is a dependency-free Node script that launches the
installed Chrome with `--headless=new` and `--remote-debugging-port`, connects to
Chrome DevTools Protocol with Node's built-in WebSocket client, loads a
container-local HTML page, waits for render completion, captures a PNG
screenshot, reads the accessibility tree as rendered text, and compares that
captured UI text with the expected value. This keeps the test generic for the
shared kit without adding Playwright, Xvfb, VNC, or desktop packages.

## Scope

In scope:

- Install Google Chrome from the official architecture-specific Linux `.deb` in
  the Debian-based image.
- Remove the downloaded Chrome `.deb` after installation.
- Add a managed Chrome policy at
  `/etc/opt/chrome/policies/managed/disable-hardware-accel.json` with
  `HardwareAccelerationModeEnabled` set to `false`.
- Add `shm_size: '1gb'` to the `workspace` service in `docker-compose.yml`.
- Document the supported headless Chrome launch workflow and its constraints in
  both source and release consumer documentation.
- Add a focused browser smoke test that uses the Dev Containers CLI to start a
  fixture container, creates `/tmp/datei_innerhalb_des_containers.txt` inside
  that container, opens the file with Chrome headless, and compares expected and
  actual content.
- Wire the smoke test into the existing test suite entrypoint.
- Add a UI-level browser test that captures rendered browser content and compares
  expected versus actual content.
- Document the selected UI mechanism and any host, VS Code, display,
  port-forwarding, or browser bridge constraints.
- Keep the UI test generic for this shared kit and reusable by unrelated
  consuming repositories.

Out of scope:

- Adding browser profiles, credentials, bookmarks, extensions, service URLs, or
  project-specific configuration.
- Changing the normal VS Code Dev Containers lifecycle or adding a root launcher.
- Copying mkctl-specific mounts, environment files, or tooling from the
  reference implementation.
- Implementing Chromium fallback unless Chrome is unavailable during solve and a
  concrete blocker requires updating the plan.
- Adding broad desktop environment support beyond the smallest reliable mechanism
  needed for the UI test.
- Requiring a human to manually inspect the browser window as the only assertion.
- Treating the already-passing headless `--dump-dom` smoke test as sufficient UI
  coverage.

## UI Test Specification

The UI test must prove these user-visible facts:

- Chrome can be started through a devcontainer runtime path that uses container
  DNS, networking, and installed certificates.
- Browser-rendered content can be captured by automation without relying on a
  human manually reading a screen.
- The test page or file exists only inside the container runtime. A
  `file:///tmp/datei_innerhalb_des_containers.txt` URL is acceptable when the
  selected UI mechanism can render and capture it; serving an equivalent local
  HTML page from inside the container is also acceptable when the UI mechanism
  needs an HTTP URL.
- The captured UI result is compared against expected content with a clear
  expected-versus-actual failure.

The selected UI mechanism is Chrome DevTools Protocol capture from a small Node
script running inside the workspace container. The script should:

- Start `google-chrome` with `--headless=new`, `--disable-gpu`, `--no-sandbox`, a
  temporary user-data dir, and a fixed localhost DevTools port.
- Open a container-local HTML file such as
  `file:///tmp/datei_innerhalb_des_containers.html`.
- Wait for the page lifecycle event or `document.readyState === "complete"`.
- Capture a PNG screenshot into a temporary file inside the container so the test
  proves a rendered browser surface was produced.
- Read the Chrome accessibility tree and compare the visible text exposed by the
  rendered page with the expected content.
- Fail with explicit expected-versus-actual output when the rendered text does
  not match.

This is a UI-level automated test because it starts the real browser, exercises
the rendering pipeline, captures a rendered screenshot artifact, and checks the
browser-exposed accessibility representation instead of relying only on
`--dump-dom` or a manual screen inspection. It is still not an interactive GUI
forwarding feature; VNC, X11, Wayland, browser profiles, and remote desktop
support remain out of scope.

## Planned Files

- `Dockerfile` - add Google Chrome installation and managed Chrome policy.
- `docker-compose.yml` - add `shm_size: '1gb'` to `services.workspace`.
- `README.md` - document the browser capability, headless launch example, and
  limitations for kit development and subtree consumers.
- `README_release.md` - document the same consumer-facing browser contract for
  release-branch submodule consumers.
- `tests/browser-smoke.sh` - new focused Dev Containers CLI smoke test.
- `tests/run.sh` - run the browser smoke test after the image build and before or
  near the existing Dev Containers CLI smoke tests.
- `tests/browser-ui-cdp.mjs` - container-side Chrome DevTools Protocol driver
  that launches Chrome, captures a screenshot, and compares rendered text.
- `docs/memory-bank/chat.md` - update only if solve changes durable project
  state, verification status, or known blockers.

## Implementation Steps

1. Update `Dockerfile` after the existing APT/tool installation blocks to
   download `google-chrome-stable_current_$(dpkg --print-architecture).deb` to
   `/tmp/chrome.deb`, install it with `apt-get -y install /tmp/chrome.deb`, and
   remove the temporary file.
2. In the same Dockerfile area, create
   `/etc/opt/chrome/policies/managed/disable-hardware-accel.json` with the JSON
   policy disabling hardware acceleration.
3. Add `shm_size: '1gb'` to the `workspace` service in `docker-compose.yml` with
   a short comment explaining browser stability and `/dev/shm`.
4. Add `tests/browser-smoke.sh` using existing `tests/helpers.sh` patterns:
   create a git fixture repo, start it with `devcontainer_cli up`, extract the
   workspace container id, create a known `/tmp/datei_innerhalb_des_containers.txt`
   file inside the container, run Chrome headless against the `file://` URL, and
   compare expected versus actual output.
5. Make the browser smoke test deterministic and non-interactive. Use a temporary
   user-data directory inside `/tmp`, include flags needed for containerized
   headless execution such as `--headless`, `--disable-gpu`, `--no-sandbox`, and
   cleanly remove the fixture container through the test trap.
6. Add the browser smoke test to `tests/run.sh` with a suitable warning threshold
   near the existing Docker image build and Dev Containers CLI tests.
7. Update `README.md` and `README_release.md` with a concise browser section:
   what is installed, how to run a headless `google-chrome` command from inside
   the container, that requests use container networking/DNS/certificates, that
   `shm_size` is set for stability, and that interactive GUI forwarding is not
   part of this first shared contract.
8. Add `tests/browser-ui-cdp.mjs` as the container-side UI test driver. Use only
   Node built-ins: `node:child_process`, `node:fs/promises`, `node:http`,
   `node:os`, `node:path`, `node:timers/promises`, and Node's global
   `WebSocket` client.
9. In `tests/browser-smoke.sh`, copy or bind the Node driver into the fixture
   workspace container, create a container-local HTML page with known visible
   content, run the driver with expected text and screenshot path arguments, and
   check that the screenshot file exists and is non-empty.
10. Keep the existing `--dump-dom` headless check in `tests/browser-smoke.sh` so
    the previous smoke coverage remains intact.
11. Add concise browser documentation stating that the automated UI smoke test
    uses Chrome DevTools Protocol screenshot plus accessibility-tree assertions;
    it does not provide interactive desktop forwarding.
12. Run formatting/static checks and the narrow browser-related tests. If Docker
   Hub rate limits, Chrome package download, or host Docker constraints block the
   full test, record the blocker and the checks that passed.

## Acceptance Criteria

- `google-chrome` is available in the built devcontainer image.
- Chrome hardware acceleration is disabled by managed policy.
- The workspace service has `shm_size: '1gb'`.
- Documentation describes the supported headless Chrome workflow and explicitly
  states that interactive GUI browser forwarding is out of scope for this slice.
- The browser smoke test starts a fixture through the Dev Containers CLI, creates
  `/tmp/datei_innerhalb_des_containers.txt` inside the container, opens
  `file:///tmp/datei_innerhalb_des_containers.txt` with Chrome headless in the
  same container, and compares expected versus actual content.
- A UI-level browser test exists, runs through the devcontainer runtime, captures
  a rendered screenshot artifact, and compares expected versus actual rendered
  accessibility text.
- Documentation states the Chrome DevTools Protocol UI test mechanism and its
  environment limits.
- The UI test is automated and does not pass only because a human manually looked
  at the browser.
- The existing headless browser smoke test remains in place and passing.
- Existing initialization, worktree, OpenCode mount, nested Docker, and release
  branch contracts are not intentionally changed.

## Verification Plan

- `git --no-pager diff --check` proves documentation and script edits avoid
  whitespace errors.
- `bash -n tests/browser-smoke.sh tests/run.sh` proves shell syntax for the new
  and touched shell scripts.
- `node --check tests/browser-ui-cdp.mjs` proves syntax for the container-side UI
  test driver.
- `task tests-run` proves the full kit contract, including image build,
  Dev Containers CLI startup, browser smoke, UI browser coverage, worktree
  startup, and submodule workflow, when the environment allows it.
- If full `task tests-run` is blocked, run the narrowest available fallback after
  the image is buildable: `tests/browser-smoke.sh`, plus any prerequisite build
  or Dev Containers CLI command needed by the script. The focused script must
  execute both the existing headless DOM check and the new CDP UI check.

## Dependencies

- Docker must be available for image build and Dev Containers CLI smoke tests.
- The Google Chrome Linux `.deb` endpoint must serve the architecture used by the
  build environment.
- The Dev Containers CLI must be available through the existing `devcontainer_cli`
  helper path.
- Existing fixture helpers in `tests/helpers.sh` must remain compatible with a
  test that creates and removes its own started container.
- Node in the devcontainer image must expose the global WebSocket client used by
  the CDP driver. Node 24 is already part of this kit, so no extra package is
  planned.

## Open Questions

- None. The plan uses Chrome DevTools Protocol from a Node script, keeps the UI
  check in `tests/browser-smoke.sh` and therefore in `task tests-run`, and uses a
  container-local `file://` HTML page so no test HTTP server is needed.

## Risks And Tradeoffs

- Google Chrome download availability can make image builds network-dependent;
  this matches the current toolchain style, which already downloads several
  external tools at build time.
- `--no-sandbox` is acceptable for the smoke test because it runs inside a
  disposable development container test fixture; documentation should not present
  it as a security hardening measure.
- Headless Chrome validates browser startup and container-local resource access
  without requiring a GUI. It does not yet prove the requested UI-level path.
- Accessibility-tree text is more deterministic than pixel-level OCR and avoids
  adding heavyweight dependencies, but it is not a full visual regression system.
  The screenshot artifact proves a rendered surface was produced; the
  accessibility text provides the expected-versus-actual assertion.

## Implementation Notes

- Installed Google Chrome in the image from the official architecture-specific
  Linux `.deb`, removed the temporary package, and verified `google-chrome --version`
  during build.
- Added the managed Chrome policy at
  `/etc/opt/chrome/policies/managed/disable-hardware-accel.json` with hardware
  acceleration disabled.
- Added `shm_size: '1gb'` to the `workspace` service so browser processes do not
  rely on Docker's small default `/dev/shm`.
- Documented the supported headless browser contract in `README.md` and
  `README_release.md`; interactive GUI forwarding remains out of scope.
- Added `tests/browser-smoke.sh`, wired it into `tests/run.sh`, and made test
  fixture roots repo-local and ignored so Dev Containers CLI bind mounts are
  visible to the Docker daemon in this workspace.
- Updated test helpers to compute Dev Containers workspace environment values
  explicitly for each CLI call instead of inheriting stale outer devcontainer
  environment variables.
- Added `tests/browser-ui-cdp.mjs` to launch Chrome with DevTools Protocol,
  capture a PNG screenshot of container-local HTML, and compare rendered
  accessibility text against the expected value.
- Extended `tests/browser-smoke.sh` so the focused browser smoke test now covers
  both the original `--dump-dom` check and the CDP rendered UI check.
- Updated `README.md` and `README_release.md` to document the automated CDP UI
  smoke-test path and clarify that interactive GUI forwarding remains out of
  scope.
- Later child task `T001_02` added the shared `chrome` launcher. The headless DOM
  and CDP UI checks now run through `chrome --headless`, preserving this task's
  automated browser coverage while giving users a direct visible launch command.

## Verification Results

- `bash -n tests/browser-smoke.sh tests/run.sh tests/helpers.sh tests/code-open-args.sh` passed.
- `git --no-pager diff --check` passed.
- `tests/browser-smoke.sh` passed: it started a fixture through Dev Containers
  CLI, created `/tmp/datei_innerhalb_des_containers.txt` inside the workspace
  container, loaded it with Chrome headless, and matched expected versus actual
  content.
- `task tests-run` passed after moving suite fixtures to repo-local ignored temp
  roots and avoiding stale inherited workspace environment values.
- `bash -n tests/browser-smoke.sh tests/run.sh` passed after adding the CDP UI
  check.
- `node --check tests/browser-ui-cdp.mjs` passed.
- `git --no-pager diff --check` passed.
- `tests/browser-smoke.sh` passed: it started a fixture through Dev Containers
  CLI, verified the headless `--dump-dom` path, ran the CDP UI driver against a
  container-local HTML file, captured a non-empty screenshot, and matched
  expected versus actual rendered accessibility text.
- `task tests-run` passed after the CDP UI smoke test was added.
- Acceptance criteria are satisfied for the Chrome install, managed policy,
  shared memory setting, headless browser smoke test, automated rendered UI
  smoke test, documentation, and unchanged existing startup/worktree/submodule
  contracts.
- Current verification after `T001_02` passed: `tests/browser-smoke.sh` still
  exercises the headless DOM and CDP UI checks through the shared `chrome`
  command, and `task tests-run` passes.

## Plan Workflow Handoff

- Resolved source task: `docs/tasks/T001_add_browser_support_to_devcontainer/task.md`.
- Parent task considered: `T001` after migration to canonical task directory
  form.
- User context considered: `t001` plus previous user requirements for Chrome
  installation, managed policy, `shm_size`, and Dev Containers CLI browser
  startup test.
- Selected option: one narrow headless Chrome implementation and verification
  slice.
- Duplicate check result: no existing child, adjacent implementation task, or
  duplicate browser task under `docs/tasks/`.
- Discovered hints considered: no `.oc_local/rules/`, `docs/tasks/hints/`,
  parent hints, child hints, or dependency hints were present.
- Related context files read: `Dockerfile`, `docker-compose.yml`, `README.md`,
  `README_release.md`, `tests/run.sh`, `tests/devcontainer-up.sh`, and
  `tests/helpers.sh`.
- Recommended next phase: `/solve-task T001_01`.

## Phase Status

- `/plan-task`: User context was `t001`. Upstream phase dependency was
  `/specify-task` on `T001`, satisfied by the source task's `specified` status
  and phase records. Discovered hints considered: none found. Result: planned one
  concrete implementation task using headless Chrome as the deterministic browser
  launch and readback mechanism. Open decisions or blockers: none for this slice.
  Next recommended phase: `/solve-task T001_01`.
- `/solve-task`: User context was `T001_01`. Upstream phase dependency was
  `/plan-task`, satisfied by this task's planned status and implementation plan.
  Discovered hints considered: no `.oc_local/rules/`, `docs/tasks/hints/`, child
  tasks, or dependency hints were present. Implemented Google Chrome install,
  managed policy, workspace shared memory, headless browser documentation,
  browser smoke test, and test-fixture reliability updates. Verification passed:
  shell syntax check, `git --no-pager diff --check`, targeted browser smoke, and
  full `task tests-run`. Acceptance criteria are satisfied. Result: solved.
  Open decisions or blockers: none for this slice. Next recommended phase:
  `/finalize-task T001_01`.
- Task update: User clarified that the UI browser test must be part of `T001_01`
  and not a separate child task. The separate `T001_02` task was removed, the UI
  requirement was folded into this task, and status was reset from `solved` to
  `specified` because the UI mechanism and implementation plan are not yet
  complete. Next recommended phase: `/specify-task T001_01` for the UI test
  mechanism, then `/plan-task T001_01`.
- `/specify-task`: User context was `T001_01` after clarifying that the UI test
  belongs in this task. Parent `T001` was considered. No `.oc_local/rules/`,
  sibling child tasks, dependency tasks, or `docs/tasks/hints/` files were
  present. Specification clarified that the UI test must exercise a rendered
  browser path, capture rendered output automatically, compare expected versus
  actual content, avoid manual-only assertions, and preserve the existing
  headless smoke test. Upstream phase dependency: none, satisfied. Result:
  specified. Open decisions for planning: choose the UI automation/display
  mechanism, decide whether the UI test belongs in `task tests-run` by default,
  and decide whether `file://` or an in-container local HTTP page is the more
  reliable UI target. Next recommended phase: `/plan-task T001_01`.
- `/plan-task`: User context was `T001_01` after UI test re-specification.
  Upstream phase dependency was `/specify-task`, satisfied by this task's
  specified status and phase record. Selected Chrome DevTools Protocol as the UI
  test mechanism because it can launch the installed Chrome, capture a rendered
  screenshot, and read rendered accessibility text with only Node 24 built-ins.
  Planned files: `tests/browser-ui-cdp.mjs`, `tests/browser-smoke.sh`,
  `tests/run.sh`, `README.md`, and `README_release.md`. Result: planned. Open
  decisions or blockers: none. Next recommended phase: `/solve-task T001_01`.
- `/solve-task`: User context was `T001_01`. Upstream phase dependency was
  `/plan-task`, satisfied by this task's planned status and concrete CDP UI test
  plan. Discovered hints considered: no `.oc_local/rules/` overlays and no
  `docs/tasks/hints/` files were present; parent `T001`, task README, and
  adjacent task context were considered. Implemented the planned
  `tests/browser-ui-cdp.mjs` driver, extended `tests/browser-smoke.sh` to run it
  inside the Dev Containers CLI-started workspace, and updated `README.md`,
  `README_release.md`, and project memory. Verification passed: `bash -n
  tests/browser-smoke.sh tests/run.sh`, `node --check tests/browser-ui-cdp.mjs`,
  `git --no-pager diff --check`, `tests/browser-smoke.sh`, and `task tests-run`.
  Acceptance criteria are satisfied. Result: solved. Open decisions or blockers:
  none. Next recommended phase: `/finalize-task T001_01`.
- `/finalize-task`: Reviewed sibling task `T001_02`, parent task `T001`, source
  and release documentation, memory-bank notes, and current smoke-test wiring.
  `T001_02` superseded the raw `google-chrome` test invocation with the shared
  `chrome --headless` launcher, but did not weaken this task's headless DOM or
  CDP UI coverage. Documentation already describes the current visible/headless
  split. Remaining follow-up: keep the parent task as the umbrella record for the
  combined browser-support feature. Verification: `git --no-pager diff --check`
  passed. Result: finalized.

## Cancellation Reason

- `none`
