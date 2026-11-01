# Refresh SSH X11 Session State For Devcontainer GUI Launches

- ID: `T042`
- Type: `fix`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `297652ab-b17a-4fb1-ad96-5f4e7811ff8e`

## Goal

Supported GUI launch paths in reused devcontainers use the current workspace's
SSH X11 display and matching authentication after reconnects, even when the
container or parent process retains an older environment.

## Context

Related infrastructure task:
`codegeist-cloud-infra/docs/tasks/T054_refresh_devcontainer_x11_sessions.md`.

Read-only investigation on 2026-10-31 in the `product` workspace on `hetzner-dev`
reported:

- Container `main-product-workspace-1` inherited `DISPLAY=hetzner-dev:12.0`, while
  generated workspace state contained `DEVCONTAINER_DISPLAY=10.77.0.5:11.0`.
- SSH X11 listeners existed on ports 6010 and 6011, but not 6012.
- The short hostname resolved to multiple host addresses through Docker DNS and
  the host's synthetic systemd-resolved response, including Docker bridge addresses.
- A container connection to the bridge gateway on TCP 6012 was blocked. The
  deployed firewall permits this X11 traffic only to the WireGuard address.

These are observations, not defaults to hardcode. Neither stale environment
values nor the blocked connection identifies the calling process. No concrete
GUI command or launch action has been verified as the source. Do not assume
OpenCode, tmux, or Chrome caused it.

The installed Chrome launcher was reported to match `scripts/chrome.sh`, which
already refreshes DISPLAY and XAUTHORITY from the workspace's generated state.
The initializer already derives TCP destinations from the SSH server IPv4 and
refreshes checkout-local authority files. Existing launcher tests simulate
reconnects; the real authenticated-X11 browser smoke currently covers one session.

## Scope

In scope:

- First identify and reproduce the actual GUI launch action with an operator
  present, including its executable, invocation path, parent process, effective
  DISPLAY, Xauthority path, and connection destination.
- If that action bypasses the existing supported launcher, first determine
  whether using the supported launch path resolves the problem.
- Apply only the correction justified by that reproduction. Add a launch-time
  handoff to an affected supported entrypoint when required, reusing Chrome's
  refresh behavior and extracting shared logic only for an actual consumer.
- Obtain DISPLAY and XAUTHORITY from the selected checkout's generated state;
  verify that the existing host initialization workflow refreshes it from the
  current SSH session.
- Document the supported GUI invocation, targeted process restart, and verified
  consumer update procedure. Record live acceptance in infrastructure T054.

Out of scope:

- Host DNS, `/etc/hosts`, firewall, Docker networking, or SSH server policy changes.
- A new display proxy/service, address guessing, display-port scanning, or
  authentication fallback to another session.
- Global process restarts or retroactive mutation of running process environments.
- Concurrent sessions sharing one checkout's generated state; independent
  sessions use separate checkout/worktree directories.

## Acceptance Criteria

- The actual affected entrypoint has a recorded reproducible failing case and a
  passing regression. Stale environment inspection alone is not reproduction.
- After reconnect changes the display and authentication, a new GUI launch in
  the same existing container uses refreshed workspace state despite stale
  values in its still-running parent.
- Supported TCP derivation uses the SSH server IPv4, preserving the complete
  display/screen suffix without hardcoded infrastructure values or hostname
  discovery. The initializer's handling of local displays such as `:12` remains
  intact.
- Independent checkout/worktree sessions retain separate display and authority
  state; refreshing one does not change the other.
- Missing, expired, or unusable required state fails the affected GUI launch
  clearly, without guessing a destination or selecting another session's cookie.
- Existing Chrome visible/headless behavior remains intact. Diagnostics reveal
  no Xauthority cookies or unrelated environment values.
- Documentation explains that updating files neither changes running process
  environments nor reconnects an existing GUI. It identifies the supported
  launch path and the smallest targeted restart when necessary.
- The consumer handoff identifies the exact tested source and corresponding
  runtime kit revisions, plus any one-time container rebuild/recreation needed
  for deployment. Live pre/post-reconnect acceptance is recorded in T054,
  including investigation of any test-related firewall blocks.

## Verification

1. In an attended `product` session, capture the exact action and relevant
   sanitized arguments, resolved executable, parent-process chain, effective X11
   values, and actual destination. Distinguish a new GUI process from a request
   forwarded to an already-running application. Use process-scoped diagnostics
   without logging cookies, protocol payloads, or full environments.
2. Verify current SSH inputs at the actual host-side `initializeCommand`, then
   repeat the action after reconnect with the same container and stale parent.
   Compare the existing supported invocation before selecting a runtime change.
3. Use existing focused kit tests and disposable authenticated X11 fixtures to
   reproduce the identified failure before the correction and pass afterward.
   Exercise the real entrypoint, not only an environment-reading helper.
4. Extend the real fixture with sessions A and B: rotate display/authentication,
   refresh through initialization, and relaunch from the unchanged parent.
   Assert unchanged container ID/start time and authenticated use of B. Include
   cookie rotation at the same display, independent workspaces, absent state,
   wrong/expired authentication, unavailable listeners, and exact suffixes.
5. Run affected checks, including `tests/initialize.sh`,
   `tests/chrome-launcher.sh`, and `tests/browser-smoke.sh` as applicable, then
   `task check`, `task tests-run`, and `git diff --check` for runtime changes.
6. Hand off the verified revision for an attended `product` check of authenticated
   X11 before and after reconnect, the actual destination and current display,
   and any correlated firewall denials. Record results in T054 and summarize
   the outcome here; automated fixtures alone do not establish live acceptance.

## File Targets

- The actual GUI/terminal launcher or invocation identified during reproduction.
- `initialize.sh`: `container_display()` and generated session state.
- `docker-compose.yml`: creation-time DISPLAY and XAUTHORITY handoff.
- `scripts/chrome.sh`: existing refresh, authentication normalization, and probes.
- `tests/initialize.sh`, `tests/chrome-launcher.sh`, `tests/browser-smoke.sh`,
  `tests/browser-ui-cdp.mjs`, and the relevant lifecycle/entrypoint tests.
- `README.md` and `README_release.md`: browser support and consumer instructions.
- `scripts/stage-runtime-tree.sh` and `tests/release-build.sh` only if shipped
  runtime files change; `Dockerfile.base` only if image installation changes.

These are inspection targets, not a requirement to edit every file. The concrete
runtime diff depends on attended reproduction.

## Dependencies

- [T032](T032_support_ssh_x11_from_bridge_devcontainers.md): existing SSH-server
  IPv4 derivation and workspace X11 authentication handoff.
- An operator-attended SSH X11 session for initial identification and consumer
  acceptance, with access to the affected `product` workspace and T054 record.
- Existing bridge-to-host X11 access; infrastructure T040/T045 already provide
  the required networking on `hetzner-dev`.

## Blockers

Runtime-change selection is gated on identifying and reproducing the unknown GUI
launch action. The next implementation step is the attended investigation above.
The infrastructure T054 file was not available at the expected sibling checkout
during planning; locate its checkout before recording live acceptance.

## Implementation Notes

- Prefer a verified invocation correction and documentation when the existing
  supported launcher resolves the issue. Add shared-kit behavior only for a
  demonstrated supported-entrypoint gap.
- Read only the required generated keys at GUI launch; do not source the whole
  env file. Keep workspace selection explicit and authority normalization scoped
  to the requested destination/display.
- A launch request may reuse an existing GUI instance. Identify and restart only
  that workspace's affected process when needed; refreshing its parent once is
  not sufficient for future reconnects.
- Mounted-script updates can affect subsequent launches, whereas image-installed
  changes may require a one-time rebuild/recreation. After installation, prove
  reconnect recovery with the same container.
- Read-only planning is complete. Reproduction, implementation, runtime tests,
  verified-fix revision, and live acceptance are pending.

## Cancellation Reason

Not cancelled.
