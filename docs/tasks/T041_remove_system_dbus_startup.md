# Remove Automatic System DBus Startup

- ID: `T041`
- Type: `chore`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `252531c8-a7c4-4ebd-9d66-0c3f3c759e0d`

## Goal

Remove the unnecessary system-DBus startup from the minimal container entrypoint
and verify the supported browser workflows without that background service.

## Context

The [T035 system-DBus probe](T035_minimize_container_entrypoint.md#system-dbus-dependency-probe)
tested Google Chrome `156.0.8078.79` in a real Dev Containers fixture with only
these entrypoint commands removed:

```bash
sudo -n install -d -m 0755 /run/dbus
sudo -n dbus-daemon --system --fork --nopidfile
```

Headless and non-headless rendering over authenticated TCP X11 passed, including
accessible-text checks and PNG screenshots. The system socket was absent and
system-bus calls failed as expected. The normal visible launcher started a
separate session bus; an additional run without a session daemon also rendered
successfully. Docker and the HTTP proxy remained usable across fixture restarts.
Evidence is recorded in T035; disposable reports are under `.tmp/no-dbus.5W0oBE/`.

## Scope

- Remove the two system-bus setup/start commands from `entrypoint.sh` and update
  its contract comments.
- Remove the system-DBus requirement and the blanket
  `wait_for_workspace_services` helper. Callers wait only for required services;
  `tests/devcontainer-up.sh` owns combined lifecycle readiness assertions.
- Adapt the existing browser/lifecycle tests to prove actual functionality
  without a system bus, rather than requiring the removed service to answer.
- Update source and release guides plus affected T035 contract notes to describe
  the smaller startup sequence and distinguish system and session buses.

Out of scope: removing DBus libraries or packages, changing the visible Chrome
launcher's optional `dbus-run-session` behavior, introducing a DBus toggle or
fallback starter, manipulating host/user-managed buses, and release publication.

## Acceptance Criteria

- Normal container startup no longer prepares `/run/dbus` or launches
  `dbus-daemon --system` through kit-owned startup code or a replacement hook.
- Fresh starts and restarts work without a system-bus process or system-bus
  socket created by the kit. An empty package-provided directory may still exist.
- The real headless and authenticated non-headless X11 browser checks pass
  without a system bus, verifying rendered content and screenshots.
- Browser tests explicitly distinguish an allowed per-browser session daemon
  from the removed system daemon; they must not reject every `dbus-daemon`
  process indiscriminately.
- Docker, the shared HTTP proxy, and the remaining single-start lifecycle
  contracts continue to pass. Readiness checks stay test/caller-side and no
  longer wait for a system bus.
- Documentation accurately describes the tested browser scope and does not
  imply that DBus packages were removed or every optional desktop feature was
  audited.

## Verification

- Reuse the real Chrome/CDP and authenticated X11 regression path, checking
  system-bus absence before and during the browser checks.
- Exercise fresh `devcontainer up`, reconnect, stopped-container startup, and
  Docker restart with the updated service-readiness checks.
- Run `task check`, `task tests-run`, and `git --no-pager diff --check`.

## File Targets

- `entrypoint.sh`, `tests/helpers.sh`
- `tests/browser-smoke.sh`, `tests/browser-open-test.sh`, `tests/browser-ui-cdp.mjs`
- `tests/devcontainer-up.sh` and other affected startup test callers
- `README.md`, `README_release.md`, affected runtime rules
- `docs/tasks/T035_minimize_container_entrypoint.md`

## Dependencies

- [T035](T035_minimize_container_entrypoint.md): minimal single-start entrypoint
  and the completed system-bus dependency probe.

## Blockers

None at specification time.

## Implementation Notes

Implemented alongside the test-suite simplification. The existing CDP driver
observes system-bus absence both before launch and while the real browser is
rendering. Lifecycle checks retain Docker/proxy readiness; other callers wait
only for their own dependencies.

Keep the change small: remove the automatic system service and its artificial
test prerequisite, while retaining functional browser coverage. Preserve the
historical verification results and record the new supported contract explicitly.
Implement in the source checkout, not the consumed `.devcontainer/` submodule.

## Verification Results

Verified on 2026-11-01:

- The new browser regression failed against the previous runtime with
  `system DBus must be absent ... phase=before_launch`. After removing the two
  startup commands, both headless and authenticated visible X11 rendering passed
  with absence checks at `before_launch` and `rendered`. The predicate allows
  the visible launcher's session daemon. Logs: `.tmp/t041-browser-before.log`
  and `.tmp/t041-browser-after.log`.
- Cold start, reconnect, startup after stop, and direct Docker restart passed;
  three actual boots emitted exactly three startup events. Docker, the shared
  proxy, HTTPS, and the login-shell workspace PATH passed without a system bus.
  Targeted log: `.tmp/t041-lifecycle.log`.
- `task check`, `node --check tests/browser-ui-cdp.mjs`, and `git diff --check`
  passed. The final complete `task tests-run` passed in 91 seconds, including
  Docker/Podman, KVM, browser, OpenCode, worktree, and submodule integrations.
  Logs: `.tmp/test-audit-check.log` and `.tmp/test-audit-suite.log`.
- Real `task devcontainer:try` staged the runtime, verified Docker/proxy readiness,
  and opened Bash with EOF as its input. System-bus absence was confirmed; that
  probe's fixture, container, anonymous volumes, and network were removed.
  Log: `.tmp/test-audit-try.log`.
- The accompanying audit fixed per-file Bash syntax checks, strict image-smoke
  failure propagation, and standalone mount-test cleanup on success and early
  setup failure. Disposable regressions confirmed rejection of a syntax error
  after the first script, an incorrect Bitwarden version, and a forbidden APT
  source. Log: `.tmp/test-audit-regressions.log`.
- Simple image tool/file checks now share one container instead of 13. Consumer
  fixtures and the image-build context use the existing runtime stager; the
  focused release test checks the fixture tree against its independent file list.
- The advisory image scan reported 535 HIGH and 25 CRITICAL findings in
  `.tmp/image-cve-scan/report.json`, for image
  `sha256:ad0228b47b4211f889ac47e9809e940458a287856a1c40fb9f1a3a81ae04ff8c`.

## Cancellation Reason

Not cancelled.
