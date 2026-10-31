# Minimize Container Entrypoint

- ID: `T035`
- Type: `chore`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `7b1299f1-6eb5-47aa-bf2d-17d8c33120a4`

## Goal

Make `entrypoint.sh` a minimal, straight-line startup script executed exactly
once per container start, exclusively through Docker's `ENTRYPOINT`.

## Context

The user explicitly wants the absolute minimum rather than defensive handling
of duplicate starts. The current `postStartCommand` invokes the entrypoint a
second time, requiring startup serialization and service-reuse checks.

The [T034 entrypoint-only investigation](T034_log_opencode_http_requests.md#entrypoint-only-investigation)
proved that the image entrypoint alone starts the services on creation and
restart. Without the hook, `devcontainer up` returned roughly 1.3 seconds before
all service checks passed. Asynchronous readiness is part of this minimal design.

## Scope

- Remove `postStartCommand` from `devcontainer.json` without a replacement hook.
- Flatten `entrypoint.sh` into path/directory preparation, essential stale
  runtime-file cleanup, PATH and Chrome-link setup, DBus startup, background
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
- Docker, DBus, the Chrome launcher, and the shared proxy function after both
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
- Verify one startup per actual boot and functional Docker, DBus, Chrome, and
  HTTPS through the proxy. Check DBus responsiveness, not just its socket file.
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

The existing fail-fast assertion in `tests/docker-build.sh` is timing-sensitive:
mitmproxy can briefly open its port before exiting on an HTTP log-open error.
On 2026-10-31, the full suite and a separate image-based probe reproduced a
foreground command starting despite that error. Replace this assertion according
to the asynchronous contract above; a successful port probe is not proof of
successful addon initialization. Diagnostics: `.tmp/task-names-tests.log` and
`.tmp/task-names-proxy-error.log`.

## Cancellation Reason

Not cancelled.
