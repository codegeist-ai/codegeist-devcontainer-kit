# Support SSH X11 From Bridge Devcontainers

- ID: `T032`
- Type: `fix`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `42c8f3b8-bc3d-495a-adf8-297c78a2de0e`

## Goal

Derive an IPv4 container-facing SSH X11 display and reuse the existing Chrome
launcher and Xauthority handoff on the isolated Compose network.

## Context

The user verified that the current SSH server address is reachable from a bridge
container with its generated Xauthority, while the inherited hostname display
times out. The deployment already permits bridge-to-host X11 traffic. The kit
must select the active SSH server address, not a hardcoded address, DNS result,
or arbitrarily enumerated interface.

## Scope

- For `DISPLAY=hostname:N[.screen]` or an IPv4 TCP display, derive the destination
  from field three of host `SSH_CONNECTION` during `initializeCommand`.
- Preserve the display/screen suffix exactly and leave the host `DISPLAY` intact.
- With missing inputs or an unsupported server address, preserve the existing
  value. Local `:N` and `unix:N` are not converted. Only IPv4 is supported.
- Let `scripts/chrome.sh` accept hostname/IPv4 TCP displays, probe them with
  `xdpyinfo`, and normalize a matching cookie for the requested address only.
- Keep checkout-local generated state and Chrome profiles; use the existing
  unique, mode-0600 temporary authorization files for parallel launches.
- Update existing tests, the manual browser helper, help, source/release docs,
  and local display guidance.

Out of scope: host networking, IPv6 support, DNS/firewall/SSH-server changes,
new proxies or forwarding services, audio, authentication bypasses, and release
publication.

## Acceptance Criteria

- The actual VS Code initializer environment is confirmed to contain
  `SSH_CONNECTION`; inspection of an unrelated terminal is not sufficient.
- A hostname display derives from the SSH server IPv4 address, including a
  screenless display such as `hostname:12`; literal `:12` stays unchanged.
- Missing display/SSH values do not fail initialization. Unsupported server
  address forms do not produce malformed derived displays.
- Reconnects refresh display numbers, optional screens, and authority state;
  refreshing one checkout does not overwrite another checkout's state.
- The launcher retains its probe-before-launch behavior, generated-file reread,
  requested-display-number cookie filter, and protected temporary permissions.
- No cookies or credentials are emitted in logs. Headless and loopback checks
  continue to work.
- A live bridge-container `xdpyinfo` check and attended visible Chrome test pass
  using state refreshed through the normal initialization workflow.

## File Targets

- `initialize.sh`, `scripts/chrome.sh`
- `tests/initialize.sh`, `tests/chrome-launcher.sh`, `tests/compose-config.sh`
- `tests/browser-open-test.sh`; retain existing `tests/browser-smoke.sh` coverage
- `docker-compose.yml` comments; existing environment handoff already suffices
- `README.md`, `README_release.md`, `.oc_local/rules/devcontainer-kit.md`

## Verification

- Extend the existing fixtures for display derivation with/without a screen,
  missing inputs, preserved local displays, unsupported server addresses,
  parallel workspaces, and reconnect refresh.
- Check network-display acceptance, failed probes, and exact-address cookie
  normalization using the existing launcher test and real `xauth` fixture files.
- Run affected tests, `task check`, `task tests-run`, and `git diff --check`.
- Use initialization decision logs to verify SSH input availability in the real
  host lifecycle, then test `xdpyinfo` and visible Chrome with the user present.

## Dependencies

- A real forwarded SSH X11 listener reachable from the bridge network and its
  matching authority file; the user reports these are already available.

## Implementation Notes

- Keep the change to one small derivation helper and the existing launcher flow.
- SSH owns display allocation. Do not add counters, shared display state, or
  per-container address discovery.
- Xauthority entries are display-specific, not screen-specific; `xauth add`
  accepts the requested display and ignores its screen component.

## Cancellation Reason

Not cancelled.

## Implementation And Verification Results

Verified on 2026-10-30:

- Added one host-side display derivation helper; the existing generated env and
  Compose mapping carry its result. No server address is configured in runtime
  code. Missing/non-applicable inputs preserve DISPLAY with a concise diagnostic.
- Chrome accepts hostname/IPv4 TCP displays and normalizes the matching cookie
  for the requested destination with one `xauth add`, replacing loopback aliases.
- The initializer and launcher regressions failed against the previous source,
  then passed with the change. They cover host DISPLAY preservation, exact
  suffixes, independent checkouts, reconnects, failed probes, authority permissions,
  cookie filtering, and loopback/headless behavior.
- `task check`, helper help output, and `git diff --check`: passed.
- `task tests-run`: passed in 502 seconds, including the derived display reaching
  a real Compose workspace, existing real visible/headless browser regressions,
  and advisory CVE scanning. That Compose test supplies explicit SSH test inputs;
  it is not proof of the user's actual VS Code initialization environment.
- Live `xdpyinfo` from the current bridge workspace succeeded with the existing
  generated authority at the deployment address supplied by the user and the
  current display suffix (`10.77.0.5:11.0`). The source launcher also passed its
  probe and returned the Chrome version.
- An attended source-launcher test with a separate temporary profile displayed
  the local "T032 bridge X11 test" page. The user confirmed it was visible and
  interactive. This used a per-test DISPLAY override, not freshly derived host
  initialization state.

### Host Lifecycle Check — Passed

A runtime-only consumer fixture was prepared using the existing staging and test
storage helpers at `.test-tmp/suite.1ZresI/t032-ssh-x11`. An initial reopen had
selected the main checkout's old runtime instead; opening the fixture explicitly
from the laptop through Remote SSH exercised the intended normal workflow.

- The user ran Reopen in Container in that fixture, followed by `xdpyinfo` and
  visible Chrome without a manual DISPLAY override, and confirmed success.
- Inspection of the fixture's generated `.env` confirmed host initialization on
  `hetzner-dev`, the correct fixture workspace path, and the automatic
  `DEVCONTAINER_DISPLAY=10.77.0.5:11.0` handoff. This verifies the actual host
  lifecycle in addition to the synthetic SSH-input tests.
- The generated `.Xauthority.gen` exists with mode `0600` and the expected user
  ownership. Its contents were not printed or added to this task record.
- The fixture is disposable test state. Source changes are verified and the
  normal-workflow acceptance check is complete; no runtime release was published
  as part of this task.
