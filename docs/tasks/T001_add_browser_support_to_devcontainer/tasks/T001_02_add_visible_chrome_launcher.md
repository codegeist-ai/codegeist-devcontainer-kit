# Add Visible Chrome Launcher

- ID: `T001_02`
- Type: `feature`
- Status: `finalized`
- Parent: `T001`
- Source Reference: `docs/tasks/T001_add_browser_support_to_devcontainer/task.md`

## Goal

Add a supported visible Chrome launch path while keeping the same launcher usable
for headless tests and automation.

## Context

After `T001_01` solved the Chrome install, headless smoke test, and CDP rendered
UI assertion, the user clarified that the kit should also open a visible Chrome
browser. The same launcher must still work headlessly so tests can use the
shared path without requiring a human-visible display.

## Scope

In scope:

- Add a runtime `chrome` command installed in the devcontainer image.
- Default `chrome` to visible Chrome on the current container display.
- Support `chrome --headless` for deterministic smoke tests.
- Add a development `task browser-open-test` wrapper that starts a temporary Git
  repo through Dev Containers CLI and opens visible Chrome inside that container.
- Update browser smoke tests to invoke Chrome through `chrome --headless`.
- Include the launcher in the runtime-only release branch contract.
- Document visible and headless usage for source and release consumers.

Out of scope:

- Project-specific browser profiles, bookmarks, credentials, and service URLs.
- Replacing the normal VS Code Dev Containers lifecycle.
- Managing host X11 or Wayland setup inside this shared kit.

## Implementation Notes

- Added `scripts/chrome.sh`, exposed as `/usr/local/bin/chrome` at container
  startup through a symlink to the mounted workspace script.
- Visible mode starts Chrome directly on the container's current display and
  fails with a clear message when neither `DISPLAY` nor `WAYLAND_DISPLAY` is
  available.
- Headless mode runs the same launcher with `--headless`, using Chrome-safe
  container flags and forwarding the caller's Chrome arguments.
- Added the `Taskfile.yaml` `browser-open-test` task so maintainers can run a
  temporary Dev Containers CLI fixture and open visible Chrome there.
- Updated `tests/browser-smoke.sh` and `tests/browser-ui-cdp.mjs` to use
  `chrome --headless`.
- Updated `scripts/release-build.sh` and `tests/release-build.sh` so
  `scripts/chrome.sh` is part of the runtime release tree.

## Verification Plan

- `bash -n scripts/chrome.sh tests/browser-smoke.sh tests/run.sh tests/release-build.sh tests/browser-open-test.sh`
- `node --check tests/browser-ui-cdp.mjs`
- `git --no-pager diff --check`
- `tests/browser-smoke.sh`
- `task tests-run`

## Verification Results

- `bash -n scripts/chrome.sh tests/browser-smoke.sh tests/run.sh tests/release-build.sh scripts/release-build.sh tests/browser-open-test.sh` passed.
- `node --check tests/browser-ui-cdp.mjs` passed.
- `git --no-pager diff --check` passed.
- `tests/release-build.sh` passed and confirmed `scripts/chrome.sh` is part
  of the runtime release tree.
- `tests/browser-smoke.sh` passed through `chrome --headless`; it rebuilt the
  fixture image with the `chrome` command and verified both the headless DOM check
  and the CDP screenshot/accessibility check.
- `task browser-open-test -- --help` passed and confirmed the manual Dev
  Containers CLI fixture opener is available.
- `docker run --rm --entrypoint bash codegeist-devcontainer-kit:local -lc 'command -v chrome && ! command -v chrome-open'` passed and confirmed the image exposes `chrome` without a `chrome-open` alias.
- `task tests-run` passed.
- `DISPLAY=localhost:10.0 XAUTHORITY=/home/test/.Xauthority task
  browser-open-test` passed after the runtime Compose path used host networking
  for SSH X11 forwarding, mounted Xauthority, and the test detected the actual
  X11 Chrome window for the current temporary profile.

## Phase Status

- Direct solve: User requested a Taskfile/task entry that opens visible Chrome,
  then clarified that tests must still work headlessly. No `.oc_local/rules/`
  overlays were present. Implemented one shared launcher with visible default and
  headless test mode, wired tests through it, updated release packaging and docs,
  and kept the behavior generic for consuming repositories. Verification passed,
  including focused browser smoke and full `task tests-run`. Result: solved.
  Next recommended phase: `/finalize-task T001_02`.
- Direct correction: User rejected VNC/noVNC and clarified that typing `chrome`
  in the terminal should open visible Chrome, with browser state stored in the
  container. Removed VNC/noVNC behavior and extra virtual-display packages,
  exposed the launcher only as `/usr/local/bin/chrome`, and kept tests on
  `chrome --headless`. Result: solved correction. Next recommended phase:
  `/finalize-task T001_02`.
- `/finalize-task`: Reviewed parent task `T001`, sibling task `T001_01`, README
  and release documentation, memory-bank notes, release packaging, and test
  coverage. Direct visible verification now passes through the Dev Containers CLI
  fixture with SSH X11 forwarding, host networking, mounted Xauthority, system
  DBus startup from `entrypoint.sh`, and a robust X11 window check in
  `tests/browser-open-test.sh`. Remaining follow-up: none for this child task.
  Result: finalized.

## Cancellation Reason

- `none`
