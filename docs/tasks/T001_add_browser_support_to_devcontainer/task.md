# Add Browser Support To Devcontainer

- ID: `T001`
- Type: `feature`
- Status: `finalized`
- Parent: `none`

## Goal

Add browser support to the reusable devcontainer so a user can launch a Chrome
browser from inside the container and access resources with the container's
network, DNS resolver, and installed certificate trust.

## Context

The current devcontainer focuses on CLI and VS Code tooling. Some local services
or internal resources are only reachable from inside the container because the
container has the relevant DNS configuration, network routes, and certificates.
This feature should let users browse those resources without leaving that
runtime context.

The user provided a working reference implementation from another devcontainer.
The reusable-kit version should adapt only the generic parts:

- Download and install `google-chrome-stable_current_$(dpkg --print-architecture).deb`
  with `apt-get -y install /tmp/chrome.deb` during the image build.
- Remove the temporary Chrome `.deb` after installation.
- Create `/etc/opt/chrome/policies/managed/disable-hardware-accel.json` with
  `HardwareAccelerationModeEnabled` set to `false`.
- Set Compose `shm_size: '1gb'` for the workspace service because GUI browsers
  can crash with a small `/dev/shm`.

The reference setup does not define the full display or browser UI access path.
Implementation still needs to decide and document how a user starts or views the
browser from the devcontainer environment.

This task is about a shared devcontainer-kit capability. The result must remain
generic for unrelated consuming repositories and must not encode mkctl-specific
paths, environment files, service names, credentials, or URLs.

## Scope

In scope:

- Define and implement a supported way to launch Chrome or Chromium from within
  the devcontainer runtime.
- Install Google Chrome in the image using the generic `.deb` package flow from
  the reference implementation.
- Add a managed Chrome policy that disables hardware acceleration by default.
- Increase the workspace service shared memory size to `1gb` for browser
  stability.
- Ensure browser traffic uses the container environment, including container DNS
  and installed certificates.
- Document how users launch the browser and what host or VS Code support is
  required.
- Add focused verification that the image or runtime exposes the expected
  browser capability without breaking existing devcontainer startup behavior.
- Add an automated Dev Containers CLI smoke test that starts the browser inside
  the devcontainer and verifies it can read a file that exists only inside the
  container.

Out of scope:

- Replacing the normal VS Code Dev Containers lifecycle.
- Adding project-specific browser profiles, credentials, bookmarks, or service
  URLs.
- Solving unrelated remote desktop or GUI application support beyond what this
  browser feature requires.
- Copying project-specific mounts, environment files, or mkctl-only tooling from
  the reference implementation.

## Acceptance Criteria

- A consuming repository using this kit can start the devcontainer and launch a
  supported Chrome/Chromium browser from the container context.
- The documented browser workflow makes clear whether rendering happens through
  VS Code, a forwarded display, a remote browser UI, or another supported path.
- The browser uses container-side DNS and certificate trust for web requests.
- The image contains a working `google-chrome` or equivalent Chrome launcher.
- Chrome hardware acceleration is disabled through a managed policy file.
- The workspace service has enough `/dev/shm` for stable browser startup.
- Runtime documentation explains user-visible commands, required host support,
  and known limitations.
- Existing startup, worktree, and release contracts remain intact.
- A test starts the devcontainer through the Dev Containers CLI, creates a file
  such as `/tmp/datei_innerhalb_des_containers.txt` inside the workspace
  container, opens `file:///tmp/datei_innerhalb_des_containers.txt` through the
  browser running in that same container, and compares the browser-observed value
  against the expected file content.

## Deliverable

The deliverable is a reusable browser capability in the devcontainer kit that is
visible to consuming projects through the normal VS Code Dev Containers flow.
The delivered behavior must include browser installation, enough runtime shared
memory for stable startup, a documented launch/access workflow, and release-path
documentation for consumers that pin the runtime-only `release` branch.

## Assumptions

- Google Chrome is acceptable as the initial browser because the user-provided
  reference implementation uses the official Google Chrome Linux package.
- The browser should run inside the container so HTTP(S) requests observe
  container-side DNS, networking, and certificate trust.
- The feature may require host or VS Code support for rendering or proxying the
  browser UI, but that support must be documented instead of hidden in
  project-specific setup.
- Browser startup verification can use an automated/headless control path when
  that is the most reliable way to assert the browser actually loaded the
  container-local `file://` URL.

## Constraints

- Keep the normal VS Code Dev Containers lifecycle as the entrypoint; do not add
  a root launcher or have kit scripts open VS Code automatically.
- Keep generated and machine-local state out of the runtime release tree.
- Preserve this repository's linked-worktree and stable workspace path behavior.
- Keep project-specific browser profiles, credentials, bookmarks, service URLs,
  and project-local overrides outside the shared kit. The shared Chrome CDP
  profile mount is the only generic browser state owned by the kit.

## Open Questions

- Resolved: visible Chrome should use a direct `chrome` terminal command on the
  current container display, not VNC/noVNC. Tests use the same launcher with
  `chrome --headless`.
- Resolved: the first implementation requires Google Chrome because the shared
  kit image builds and verifies the official Google Chrome package directly.
- Resolved: non-GUI verification uses `chrome --headless` in a Dev Containers
  CLI-started workspace against container-local `file://` content.
- Resolved: rendered UI readback uses Chrome DevTools Protocol from
  `tests/browser-ui-cdp.mjs`, with screenshot capture and accessibility-tree text
  comparison.

## Verification

- Run the narrow checks added for the browser package or launch workflow.
- Add and run a Dev Containers CLI browser smoke test. The test must create a
  known text file inside the started workspace container, open it in the
  container browser with a `file://` URL, extract the browser-observed content,
  and fail when the expected and actual values differ.
- Run `task tests-run` when the environment allows the full devcontainer smoke
  suite.
- If full smoke verification is blocked by Docker Hub rate limits or host GUI
  constraints, record the blocker and the targeted checks that passed.

## File Targets

- `Dockerfile`
- `devcontainer.json`
- `docker-compose.yml`
- `entrypoint.sh`
- `README.md`
- `README_release.md`
- `tests/`
- Likely test integration points include `tests/devcontainer-up.sh`, a new
  focused script under `tests/`, and `tests/run.sh` if the browser smoke test is
  added as a separate suite entry.

## Dependencies

- Browser package and launch mechanism availability for the Debian-based image.
- Host or VS Code capability to display or proxy a browser session when a GUI is
  required.
- Google Chrome Linux `.deb` availability for the container architecture.

## Implementation Notes

- User-provided reference implementation installs Google Chrome by downloading
  `https://dl.google.com/linux/direct/google-chrome-stable_current_$(dpkg --print-architecture).deb`,
  installing it with `apt-get`, then deleting `/tmp/chrome.deb`.
- User-provided reference implementation writes a managed Chrome policy at
  `/etc/opt/chrome/policies/managed/disable-hardware-accel.json` to disable
  hardware acceleration.
- User-provided reference implementation sets Compose `shm_size: '1gb'`; adapt
  that to this repo's `workspace` service in `docker-compose.yml`.
- Specify the launch or display mechanism before implementation so the task does
  not mix a package install with an unsupported GUI/display assumption.
- User requires a browser startup test through the Dev Containers CLI: create a
  container-local file, open its `file://` URL in the container browser, and
  compare expected and actual values from the loaded page.

## Phase Status

- `/specify-task`: User context was the existing `T001` task plus the earlier
  Chrome installation reference. No `.oc_local/rules/` overlays, parent task,
  child tasks, dependency tasks, or `docs/tasks/hints/` files were present.
  Specification clarified the shared-kit scope, reusable deliverable,
  assumptions, constraints, non-goals, and planning-readiness questions. Upstream
  phase dependency: none, satisfied. Result: specified. Open blocker for
  planning: choose and document the supported browser launch or UI access path.
  Next recommended phase: `/plan-task T001` after that decision is made.
- `/specify-task`: User added a required verification constraint: the browser
  must be opened through a Dev Containers CLI-started container against a
  container-local `file://` URL, then expected and actual content must be
  compared. Existing Dev Containers CLI tests under `tests/` were considered;
  no `.oc_local/rules/` overlays or hint files were present. Upstream phase
  dependency: none, satisfied. Result: specified. Open planning question: choose
  the deterministic browser control/readback mechanism for this smoke test.
  Next recommended phase: `/plan-task T001`.
- `/plan-task`: User context was `t001`. The task was migrated from standalone
  file form to canonical parent directory form because it now owns child
  implementation task `T001_01`. Duplicate check found no existing child or
  adjacent implementation task. Selected option: one narrow implementation slice
  that installs Google Chrome, configures browser-safe runtime defaults,
  documents a headless/container-local browser launch contract, and adds a Dev
  Containers CLI browser smoke test. Upstream phase dependency: `/specify-task`,
  satisfied. Result: parent preserved as specified; child `T001_01` records the
  concrete planned implementation. Next recommended phase: `/solve-task T001_01`.
- Task update: User requested an additional UI browser test after `T001_01` was
  solved, then clarified that this must stay in `T001_01` instead of becoming a
  separate child task. Removed the separate UI-test child task and moved that
  follow-up scope into `T001_01`.
- Task update: User requested a task that opens visible Chrome and clarified that
  tests must still work headlessly. Added child task `T001_02` for the shared
  Chrome launcher with visible direct-display mode and headless test mode.
- Task update: `T001_02` is finalized. Automated tests use `chrome --headless`,
  no VNC/noVNC or `chrome-open` alias remains in scope, and direct visible
  verification passes with `DISPLAY=localhost:10.0
  XAUTHORITY=/home/test/.Xauthority task browser-open-test` through the Dev
  Containers CLI fixture and SSH X11 forwarding.
- Task update: `T001_01` is finalized. Its original headless and rendered UI
  smoke coverage remains active through the shared `chrome --headless` launcher.
- Parent finalization: Child tasks `T001_01` and `T001_02` are finalized and
  together satisfy the parent acceptance criteria. Documentation covers source and
  release consumers, visible and headless launch modes, display requirements,
  release packaging, and test coverage. Verification passed for browser smoke,
  release packaging, full `task tests-run`, alias absence, direct visible
  `DISPLAY=localhost:10.0 XAUTHORITY=/home/test/.Xauthority task
  browser-open-test`, and `git --no-pager diff --check`. Result: finalized.

## Cancellation Reason

- `none`
