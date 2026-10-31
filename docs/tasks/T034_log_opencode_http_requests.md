# Log OpenCode HTTP Requests

- ID: `T034`
- Type: `feature`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `b911614d-5b6f-42d9-bd39-5ac27eaab4ef`

## Goal

Log HTTP and HTTPS metadata from `oc` through one simple shared container proxy.
The user explicitly selected a fixed loopback listener and environment variables
instead of a separate proxy, CA, or process supervisor for every pane.
Use mitmproxy's automatically generated CA directly, without kit-owned CA bundles.

## Scope

- Install mitmdump. Start it once in `entrypoint.sh` at `127.0.0.1:18080`.
- Set proxy and CA variables in `oc`, passing them explicitly into both tmux
  paths. Keep the usual OpenCode invocation, shell wrapper, and tmux bindings.
- Keep mitmproxy's generated CA and diagnostics in private `.tmp/opencode-http/`
  state. Point client CA variables directly at `mitmproxy-ca-cert.pem`; use
  mitmproxy's native settings for custom upstream trust. Keep TLS verification
  and local proxy bypasses enabled.
- Append request/response/error metadata to `.tmp/opencode-http.jsonl`, without
  queries, headers, cookies, or bodies. Stream bodies immediately.
- Update the runtime allowlist, documentation, and real integration tests.

Out of scope: network enforcement, routing/firewall changes, per-pane lifecycle
management, automatic proxy restarts, and release publication.

## Acceptance Criteria

- Every `oc` pane uses the same listener and mitmproxy CA; closing a pane leaves
  the proxy available to other clients. Docker owns the proxy's lifetime.
- HTTP/HTTPS requests have correlated IDs, method, host, path, status, and
  duration. New logs are owner-only, and sensitive payload fields are omitted.
- TLS validation and native upstream CA configuration work. Streaming clients
  receive the first chunk before the origin completes its response.
- Container startup waits briefly for the proxy and its CA and reports failure
  if startup fails. Normal container and Dev Containers workflows still pass.
- Documentation describes shared lifetime, environment-based coverage, and logs.

## Verification

- Real entrypoint startup, both tmux paths, shared proxy use after pane closure,
  and a separate container with an unwritable log.
- Local HTTP/HTTPS origins, parallel gated streams, CLI clients, metadata
  omissions, upstream certificate rejection, and a real OpenCode catalog refresh.
- `task check`, `task tests-run`, and `git diff --check`.

## File Targets

- `entrypoint.sh`, `cmds/oc`, `Dockerfile.base`, `scripts/opencode-http-log.py`
- `scripts/stage-runtime-tree.sh`, `tests/release-build.sh`
- `tests/opencode-http.py`, `tests/opencode-tmux-wrapper.sh`, `tests/docker-build.sh`
- `README.md`, `README_release.md`

## Implementation Notes

The startup-only lock serializes the current image-entrypoint and
`postStartCommand` calls, which can overlap; the daemon closes the lock
descriptor before it starts serving. The entrypoint-only alternative was
verified separately below. Mitmproxy owns all certificate generation. The kit
neither copies CA files nor assembles trust bundles.

A later full-suite run reproduced a readiness race: the port check can pass
before mitmproxy exits on a log-open error. The recorded successful runs below
do not establish a reliable fail-fast guarantee. This finding and the selected
minimal asynchronous-startup follow-up are tracked in
[T035](T035_minimize_container_entrypoint.md).

## Verification Results

Verified on 2026-10-30:

- Both tmux paths passed the generated `mitmproxy-ca-cert.pem` directly to their
  clients. The shared proxy survived pane closure and repeated entrypoint calls.
- Real HTTP/HTTPS POSTs, Python HTTPS, parallel streaming, local bypass, private
  state/log permissions, metadata omissions, and upstream certificate rejection
  passed. The local TLS origin uses mitmproxy's native `config.yaml` settings.
- Real OpenCode refreshed `https://models.opencode.ai/api.json` through the proxy
  with status 200, isolated user state, and no provider credentials.
- A separate container rejected an unwritable log before its command ran.
- `task check` and `git diff --check`: passed.
- `task tests-run`: passed in 101 seconds, including the image, Chrome, nested
  Docker, Podman, KVM, Dev Containers, worktrees, and submodule consumption.
  Log: `.tmp/t034-native-ca-tests.log`.
- Image CVE scan completed with 537 HIGH and 25 CRITICAL advisory findings under
  the existing policy. Report: `.tmp/image-cve-scan/report.json`.
  Tested image: `sha256:e5739ac1556b16dbf80d57c0889ee43b76e155cd3dbccc16cfd097367b34f63c`.

### Entrypoint-Only Investigation

Verified on 2026-10-31 with Dev Containers CLI 0.90.0 and Docker 29.9.2:

- Staged the current runtime allowlist into a disposable consuming repository
  and removed only its `postStartCommand`. Effective merged configuration also
  contained no post-start hook. The generated container wrapper still executed
  `/usr/local/bin/devcontainer-entrypoint sleep infinity`.
- Fresh `devcontainer up`, another `up` on the running container, `up` after
  `docker stop`, and a plain `docker restart` all passed. Reopening the running
  container retained the proxy PID; the three actual boots produced exactly
  three proxy starts.
- Verified nested Docker, DBus, the Chrome launcher, proxy listener, and CA.
  Real HTTPS through the proxy and headless Chrome rendering also passed via
  `devcontainer exec`.
- Readiness differs from the current hook-backed workflow: all service checks
  passed 1.285 seconds after fresh `up`, 1.347 seconds after stopped-container
  `up`, and 1.409 seconds after `docker restart`. The first immediate checks
  were not ready; the running-container `up` was immediately ready.
- Conclusion: the image entrypoint is sufficient to start the services. The
  duplicate startup hook is unnecessary for that purpose. Removing it also
  removes its readiness wait, so callers requiring services immediately after
  `devcontainer up` need an explicit readiness check rather than another start.
- Probe logs: `.tmp/entrypoint-only.Y1aWPc/`. The fixture container, anonymous
  volume, network, and consuming checkout were removed after verification.
