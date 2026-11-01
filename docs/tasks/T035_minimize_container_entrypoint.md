# Minimize Container Entrypoint

- ID: `T035`
- Type: `chore`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `7b1299f1-6eb5-47aa-bf2d-17d8c33120a4`

## Goal

Make `entrypoint.sh` a minimal, straight-line startup script executed exactly
once per container start, exclusively through Docker's `ENTRYPOINT`.

## Context

The user explicitly wants the absolute minimum rather than defensive handling
of duplicate starts. The former `postStartCommand` invoked the entrypoint a
second time, requiring startup serialization and service-reuse checks.

The [T034 entrypoint-only investigation](T034_log_opencode_http_requests.md#entrypoint-only-investigation)
proved that the image entrypoint alone starts the services on creation and
restart. Without the hook, `devcontainer up` returned roughly 1.3 seconds before
all service checks passed. Asynchronous readiness is part of this minimal design.

The system-DBus startup retained in the original T035 implementation is removed
by [T041](T041_remove_system_dbus_startup.md). The dated verification results
below preserve the original behavior; the current contract needs no system bus.

## Scope

- Remove `postStartCommand` from `devcontainer.json` without a replacement hook.
- Flatten `entrypoint.sh` into path/directory preparation, essential stale
  runtime-file cleanup, PATH and Chrome-link setup, background
  Docker and mitmdump startup with log redirection, and final `exec "$@"`.
- Remove `start.lock`, `flock`, descriptor 9, service-reuse branches, `ensure_*`
  wrappers, installed-tool checks, readiness polling, and process monitoring.
- Assume the image-provided tools and documented runtime environment exist.
  Keep only cleanup needed for a genuine new container start, such as removing
  a stale Docker PID file; do not add duplicate-start recovery.
- Update tests and documentation for one-shot, asynchronous startup. Readiness
  waits belong in tests or callers that explicitly need ready services.

Out of scope: replacement startup/health hooks, supervisor processes, automatic
service restarts, toolchain changes, networking changes, and release publication.

## Acceptance Criteria

- The normal Docker and Dev Containers paths execute the entrypoint once per
  container start. Reattaching to a running container does not invoke it again;
  restarting the container executes it once for the new start.
- The runtime script is a short, direct command sequence with no locking,
  duplicate-start assumptions, readiness loops, or service supervision.
- Docker, the Chrome launcher, and the shared proxy function after both
  fresh starts and restarts under the normal workspace user.
- The proxy retains its fixed `127.0.0.1:18080` listener, mitmproxy-managed CA,
  metadata logging, and private state/log permissions.
- Synchronous setup failures use normal shell error propagation. Background
  service failures remain visible in their logs; the script does not supervise
  them or promise that the foreground command starts only after they are ready.
- Tests no longer reinvoke the entrypoint to check idempotency or assume that
  asynchronous proxy failure prevents the foreground command from running.
  Replace those assertions with checks matching the new contract.
- Source and release guides explain the single start path and asynchronous
  readiness. Startup diagnostics distinguish launching services from readiness.

## Verification

- Test a fresh `devcontainer up`, repeated `up` on a running container, `up`
  after `docker stop`, and a direct `docker restart` with real dependencies.
- Verify one startup per actual boot and functional Docker, Chrome, and HTTPS
  through the proxy. T041 verifies the absence of the removed system bus.
- Keep bounded readiness waits in test code before exercising these services.
- Run `task check`, `task tests-run`, and `git --no-pager diff --check`.

## File Targets

- `entrypoint.sh`, `devcontainer.json`
- `tests/docker-run.sh`, `tests/docker-build.sh`, `tests/opencode-tmux-wrapper.sh`
- `tests/devcontainer-up.sh` and other integration tests with readiness assumptions
- `README.md`, `README_release.md`, this task, and affected T034 contract notes

## Dependencies

- [T034](T034_log_opencode_http_requests.md): existing shared HTTP proxy runtime
  and the completed entrypoint-only investigation.

## Implementation Notes

Aim for roughly 20–30 executable lines, excluding useful contract comments.
Prefer readable commands over dense one-liners or replacement helper layers.
Keep restart cleanup limited to kit-owned runtime files. Implement in the source
checkout; consuming `.devcontainer/` submodule changes belong to a later release.

The previous fail-fast assertion in `tests/docker-build.sh` was timing-sensitive:
mitmproxy could briefly open its port before exiting on an HTTP log-open error.
It is replaced with an explicit asynchronous failure test: the foreground command
runs and retains its exit status while the actual proxy error is recorded.

Restart cleanup includes both `/var/run/docker.pid` and Docker's managed
`/var/run/docker/containerd/containerd.pid`. A real restart exposed an old
containerd PID already assigned to another process in the new PID namespace;
removing only Docker's top-level PID file was insufficient. Cleanup removes only
these runtime PID files and the old Docker diagnostic log.

## Verification Results

Verified on 2026-10-31:

- `entrypoint.sh` reduced from 160 to 43 total lines, with 24 nonblank,
  non-comment lines. The remaining conditional only supplies the existing
  default `bash` command when no arguments are supplied.
- Removed `postStartCommand`, startup locking, daemon-reuse guards, and runtime
  polling. Added explicit startup and asynchronous handoff diagnostics.
- The single-start lifecycle regression failed against the old configuration
  before implementation, then passed fresh `up`, reconnect to the same running
  container/proxy, `up` after stop, and direct Docker restart. Three boots emitted
  exactly three entrypoint startup events.
- Docker, real DBus method calls, the Chrome launcher, proxy/CA readiness, and
  HTTPS through the proxy passed after restarts. The stale Docker/containerd PID
  and root-owned Docker log regression passed as the normal workspace user.
- An unwritable HTTP log produced its real error while the foreground command
  ran and preserved exit status 23. Invalid proxy-state directory preparation
  failed synchronously before the foreground command ran.
- Shell syntax checks for changed scripts, `task check`, and `git diff --check`
  passed. `task tests-run` passed completely in 102 seconds, including Chrome,
  Docker/Podman, KVM, OpenCode, worktree, and submodule integrations.
  Full log: `.tmp/t035-tests.log`.
- Real `task devcontainer:try` staged the current runtime, verified services via
  its caller-side readiness checks, and opened Bash successfully. The probe's
  own container and fixture were cleaned afterward. Log: `.tmp/t035-try.log`.
- The advisory image scan reported 535 HIGH and 25 CRITICAL findings under the
  existing policy. Report: `.tmp/image-cve-scan/report.json`; tested image:
  `sha256:7eec9e7c81aa88708bb7b3018c0481c9009494f468a352c4a19e732b803ab122`.

### System-DBus Dependency Probe

On 2026-11-01, a disposable consuming repository was staged from the current
runtime with only the two system-DBus setup/start commands removed from its
entrypoint. The normal Chrome launcher and existing CDP test driver were used
with Google Chrome `156.0.8078.79`.

- Headless rendering passed with no system bus and no observed session daemon.
- Non-headless rendering over authenticated loopback TCP X11 passed without a
  system bus. The normal visible launcher started its own `dbus-run-session`
  session daemon, which is separate from the entrypoint's system bus.
- A third non-headless run also passed without a session daemon. An explicit
  nonexistent `DBUS_SESSION_BUS_ADDRESS` suppressed the launcher's automatic
  session-bus startup; no `dbus-daemon` process was observed during that run.
- Each run verified the expected accessible page text and produced a valid PNG.
  The system socket was absent, and a real system-bus method call failed as
  expected. The container was restarted between modes; Docker and the HTTP
  proxy remained usable without system-DBus initialization.
- This demonstrates that the two entrypoint system-bus commands are unnecessary
  for these tested browser paths. DBus libraries remained installed; this was
  not an audit of every optional desktop integration or a physical SSH display.
- Logs and screenshots: `.tmp/no-dbus.5W0oBE/`. The test container, anonymous
  volume, network, consuming checkout, and temporary Xauthority files were
  removed. The runtime edit was confined to the disposable fixture.

## Cancellation Reason

Not cancelled.
