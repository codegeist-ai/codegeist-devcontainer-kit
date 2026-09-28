# Remove Host Network Mode

- ID: `T022`
- Type: `refactor`
- Status: `planned`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `ecaa4718-8b65-4aac-85ed-0cfee6425e79`

## Goal

Remove host networking from the shared devcontainer runtime and direct runtime
helpers while preserving the supported SSH X11, Wayland, microphone, nested
Docker, and ordinary network behavior through narrower explicit transports.
Establish why host networking was introduced, which current contracts still
depend on it, and which replacement is safe and reusable before changing the
runtime default.

## Context

`docker-compose.yml` currently sets `network_mode: host` on the workspace
service. `Taskfile.yaml` also passes `--network host` in its direct
`docker-run` path, and `tests/browser-open-test.sh` adds host networking to its
fixture override for an SSH-loopback X11 display.

Git history shows that commit `d277370` introduced host networking so an SSH
X11 value such as `DISPLAY=localhost:10.0` continued to refer to the SSH host's
X11 proxy from inside the workspace container. The later SSH microphone
contract in `T010_01` relies on the same property: OpenSSH creates a remote
listener at `127.0.0.1:47130` on the SSH host, and `cmds/oc-record` connects to
that address from the container.

Without host networking, the host and workspace use different network
namespaces:

- `localhost` and `127.0.0.1` inside the workspace identify the workspace
  container.
- The workspace container's own bridge IP also identifies the workspace, not
  the container host.
- `host.docker.internal` or a bridge gateway address identifies the container
  host, but does not make a service bound only to host `127.0.0.1` accept
  connections on that gateway address.

Replacing `localhost` with the workspace IP is therefore incorrect. Replacing
it with `host.docker.internal` is useful only after the target service is made
reachable on that address through an intentionally scoped listener, proxy, or
socket transport. A wildcard listener is not an acceptable shortcut for the
existing loopback-only microphone or X11 security boundary.

Wayland already uses a generated bind mount for one detected host Unix socket
and should not require host networking. Headless Chrome also has no display
network dependency. The investigation must distinguish those paths from SSH
X11 and the forwarded microphone instead of treating every browser or audio
workflow as one networking requirement.

The workspace also starts rootful Docker-in-Docker. Removing host networking
must preserve nested Docker startup, outbound DNS and registry access, and a
usable path to ports published by nested project containers. A nested
`docker run -p` publishes into the workspace network namespace; after the
workspace moves to a bridge network, tests must prove how users and VS Code
reach that port rather than assuming host-level publication.

## Replacement Constraints

Evaluate replacements against the real Remote SSH and Dev Containers lifecycle,
not only synthetic connectivity checks:

- For microphone forwarding, prefer an SSH-created Unix-domain listener that
  can be mounted narrowly into the workspace and selected through
  `PULSE_SERVER=unix:...`, if OpenSSH, Docker bind mounts, Pulse clients,
  ownership, reconnects, and parallel sessions satisfy the current contract.
- For SSH X11, evaluate a narrowly scoped proxy or socket transport that
  preserves Xauthority validation without exposing the host X11 proxy on a
  wildcard interface. Standard SSH X11 forwarding normally exposes a
  host-loopback TCP proxy, so changing only `DISPLAY` is insufficient.
- A host-gateway TCP proxy is acceptable only if its lifecycle, bind address,
  access restriction, failure behavior, and parallel-workspace behavior are
  explicit and tested. `initialize.sh` must not leave unmanaged background host
  processes behind.
- Binding SSH X11, Pulse, or another sensitive service to `0.0.0.0`, `::`, or an
  externally reachable host interface is not an acceptable replacement.
- Binding directly to a Docker bridge address must not be assumed portable:
  bridge addresses and Compose networks vary by engine, project, and host.
- Do not retain host networking in a hidden sidecar or generated override and
  claim that the dependency was removed. Any intentionally retained host-mode
  component must remain visible as an unresolved boundary or explicitly narrow
  follow-up decision.

If no secure generic replacement preserves an accepted feature, do not silently
remove that feature or weaken its security. Record the tested blocker and keep
this task open or blocked until the product contract is explicitly revised.

## Scope

In scope:

- Trace and document every source, test, generated configuration, and user
  workflow that currently relies on host networking.
- Remove `network_mode: host` from the shared workspace service.
- Remove `--network host` from the direct `docker-run` development path.
- Remove dynamic host-network fixture overrides such as the SSH X11 branch in
  `tests/browser-open-test.sh`.
- Add a focused negative assertion against host network mode in resolved Compose
  and inspected container configuration.
- Replace the SSH-loopback X11 path with a narrower transport while preserving
  Xauthority validation and stale-display diagnostics.
- Replace the host-loopback microphone path with a narrower transport while
  preserving the manual SSH ownership model, real Pulse/FFmpeg recording, tmux
  behavior, and loopback-or-better exposure boundary.
- Confirm that generated Wayland socket mounting and visible Wayland Chrome do
  not regress.
- Verify nested Docker startup, outbound networking, DNS, image pulls, and
  documented project-port reachability on the workspace bridge network.
- Update source, release, contributor, task, and local agent documentation to
  describe the new network boundary and transports accurately.

Out of scope:

- Removing rootful Docker-in-Docker or `privileged: true`; that requires a
  separate container-engine architecture task.
- Replacing Docker with Podman, Kata Containers, a microVM runtime, or a remote
  container engine.
- Exposing SSH X11, Pulse, Docker, or another host service on a wildcard or
  externally reachable listener to make bridge networking convenient.
- Adding persistent host daemons or modifying system `sshd_config`, firewall,
  PipeWire, X11, or display-manager configuration without a separately accepted
  host contract.
- Weakening the real microphone, browser, Docker, or Dev Containers integration
  tests merely to make removal pass.
- Editing generated release content directly in the `.devcontainer/` submodule.
- Publishing a release or changing Git history.

## Acceptance Criteria

- `docker-compose.yml` contains no `network_mode: host` setting for the
  workspace service.
- `Taskfile.yaml` and normal repository test helpers do not pass
  `--network host` for the workspace runtime.
- No generated or fixture Compose override silently restores host networking for
  SSH X11, microphone forwarding, or another standard feature.
- The resolved workspace configuration uses a normal isolated Compose network,
  and inspected runtime state confirms its network mode is not `host`.
- Documentation records commit `d277370` as the original SSH X11 rationale and
  `T010_01` as the later microphone dependency, then explains their replacement.
- Source and documentation do not claim that a container IP reaches host
  services or that `host.docker.internal` can reach a host-loopback-only
  listener without an additional transport.
- A real Remote SSH X11 session can start visible Chrome from the workspace
  without host networking, while preserving Xauthority checks and avoiding
  wildcard host listeners.
- A real SSH-forwarded microphone session can record through FFmpeg and the
  existing `oc-record` flow without host networking or a wildcard TCP listener.
- A missing X11 or microphone transport fails only the corresponding optional
  feature with an actionable diagnostic; ordinary devcontainer startup remains
  available.
- Local Wayland visible Chrome, headless Chrome, and reconnect-refreshable
  display state continue to pass their existing tests.
- Nested `dockerd` becomes ready for the workspace user, resolves DNS, pulls an
  image, and runs a container on the isolated workspace network.
- A focused nested-container fixture publishes an HTTP port and proves the
  documented access path from the workspace and through the supported VS Code
  or Dev Containers workflow.
- Standard workspace egress remains functional without unintentionally exposing
  container services on every host interface.
- Source and release documentation no longer state that the devcontainer uses
  host networking.
- No accepted feature is removed or security boundary weakened solely to satisfy
  the host-network absence assertion.

## File Targets

- `docker-compose.yml`
- `Taskfile.yaml`
- `initialize.sh`
- `cmds/oc-record`
- `scripts/chrome.sh`
- `tests/helpers.sh`
- `tests/initialize.sh`
- `tests/compose-config.sh`
- `tests/devcontainer-up.sh`
- `tests/browser-open-test.sh`
- `tests/browser-smoke.sh`
- `tests/chrome-launcher.sh`
- `tests/oc-record.sh`
- A focused network or nested-port test if existing tests cannot express the
  observable contract clearly
- `README.md`
- `README_release.md`
- `CONTRIBUTING.md`
- `.oc_local/rules/devcontainer-kit.md`
- `.oc_local/rules/software-tests.md`
- `docs/tasks/T022_remove_host_network_mode.md`

The final changed-file set should remain limited to files justified by the
chosen replacement. A listed target does not require an edit when investigation
proves its current behavior is independent of host networking.

## Dependencies And Sequencing

- This task has no semantic dependency on `T020`, but implementation should
  follow or rebase after `T020` because both tasks modify Compose, runtime tests,
  and the same source and release documentation.
- Real SSH X11 verification requires a reachable forwarded display and valid
  Xauthority state.
- Real microphone verification requires the documented Linux PipeWire client
  and active SSH forwarding path.

## Implementation Plan

1. Establish the current dependency map before editing runtime behavior:
   - Inspect Git history around commit `d277370` and the finalized `T001_02`
     task for the SSH X11 reason.
   - Inspect `T010_01`, `cmds/oc-record`, and the real recorder test for the
     microphone reason.
   - Inspect resolved Compose and runtime networking, including generated and
     user override files.
   - Exercise a small nested Docker published-port fixture and record current
     host-mode reachability.
2. Reproduce bridge-network failures deliberately:
   - Remove host networking only in a disposable fixture.
   - Show that container `localhost` and the container IP do not identify the
     host listener.
   - Test `host.docker.internal` against a host-loopback-only listener and retain
     the expected failure as evidence that host-gateway naming alone is not the
     replacement.
3. Select and prove the narrow microphone transport:
   - Prefer an SSH remote Unix-domain listener mounted into the workspace.
   - Verify socket creation order, permissions, reconnect behavior, stale socket
     cleanup, connection multiplexing, parallel projects, and Pulse URI syntax.
   - If a TCP proxy is required instead, constrain it to the workspace access
     path and document why the Unix socket approach failed.
4. Select and prove the narrow SSH X11 transport:
   - Preserve standard Xauthority cookie handling and reconnect refresh.
   - Avoid wildcard X11 exposure and broad `xhost` access.
   - Keep explicit non-loopback display hosts caller-managed and preserve the
     independent Wayland socket path.
5. Remove host mode from source Compose, direct Taskfile execution, and browser
   fixtures only after both required replacement paths pass focused probes.
6. Add runtime assertions for isolated networking, ordinary egress, nested
   Docker, and nested published-port access. Keep failure messages explicit
   about expected and actual network modes or endpoints.
7. Update source, release, contributor, and local agent guidance with the new
   transport setup, security boundary, diagnostics, and any intentional manual
   prerequisites.
8. Run focused syntax and contract checks, real X11 and microphone checks, the
   full integration suite, release-copy verification, and whitespace validation.
9. Record concrete verification results and set this task to `solved` only after
   both real optional-device workflows and normal startup pass without host
   networking.

## Verification

- `bash -n initialize.sh cmds/oc-record scripts/chrome.sh tests/helpers.sh tests/initialize.sh tests/compose-config.sh tests/devcontainer-up.sh tests/browser-open-test.sh tests/browser-smoke.sh tests/chrome-launcher.sh tests/oc-record.sh`
- `task check`
- `tests/initialize.sh`
- `tests/compose-config.sh`
- Inspect resolved Compose output and container state to confirm the workspace
  network mode is not `host`.
- In a disposable bridge-network fixture, prove that the container IP identifies
  the container and that `host.docker.internal` cannot reach a service bound
  only to host `127.0.0.1` without the selected replacement transport.
- In a configured Remote SSH session, run `task browser-open-test` and verify
  visible Chrome through SSH X11 without a host-network override.
- Verify local Wayland visible Chrome and the headless browser smoke path.
- Run the real microphone null-output check and `oc-record` integration through
  the replacement transport; inspect host listeners to confirm no wildcard or
  externally reachable Pulse endpoint exists.
- Run a nested Docker image pull and published HTTP-port fixture and verify its
  documented workspace and VS Code access paths.
- `task tests-run`
- `tests/release-build.sh`
- `git diff --check`

## Verification Results

Not run; this task currently records the investigated rationale, constraints,
and agreed implementation plan only.

## Cancellation Reason

Not cancelled.
