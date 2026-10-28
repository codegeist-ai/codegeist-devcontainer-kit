# Remove Host Network Mode

- ID: `T022`
- Type: `refactor`
- Status: `solved`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `ecaa4718-8b65-4aac-85ed-0cfee6425e79`

## Goal

Remove host networking from the shared runtime. Use the normal isolated Compose
network and VS Code port forwarding for project access.

## Context

Source `docker-compose.yml` and the direct Docker start in `Taskfile.yaml`
previously selected host networking. Host networking originally supported
SSH-loopback X11 and later microphone forwarding. Those features no longer need
to work after this change. On the isolated network, container `localhost` refers
to the container, not the SSH host.

The basic workflow has already passed a manual test in the recreated development
devcontainer without a release build; see Verification Results.

## Scope

In scope:

- Remove host networking from source Compose, direct Docker execution, and
  affected test fixtures.
- Remove required X11/microphone test execution and corresponding release
  requirements so these features no longer block verification.
- Update affected comments and current documentation, including container
  recreation and VS Code port forwarding instructions.

Out of scope:

- Chrome investigation, microphone implementation removal (owned by `T027`),
  replacement transports, host-network opt-ins, and new network-test frameworks.
- Changing Docker-in-Docker architecture, publishing releases, or editing the
  consumed `.devcontainer/` runtime as the permanent source fix.

## Acceptance Criteria

- Source Compose, direct Docker execution, and standard fixtures no longer select
  host networking.
- An existing Compose test checks that the default configuration does not select
  host mode; no new runtime-inspection framework or automated VS Code test is
  required.
- X11/microphone availability no longer blocks the main suite or release
  verification. Independent existing coverage is retained.
- Current documentation describes the isolated network and VS Code port
  forwarding without promising host-loopback access.
- Existing successful manual network checks remain recorded; repeat or extend
  them only if subsequent changes or failures justify it.

## File Targets

- `docker-compose.yml`
- `Taskfile.yaml`
- Existing Compose test and affected fixtures/test entrypoints
- Release verification logic where it requires X11 or microphone checks
- Affected comments, `README.md`, `README_release.md`, and other current guidance
  only where it describes the changed behavior

## Dependencies

- No prerequisite implementation of `T020` or `T024`.
- Microphone removal remains separate in `T027`.

## Implementation Plan

1. Remove host-network settings and add one assertion to the existing Compose test.
2. Adjust affected test execution and release requirements.
3. Correct affected documentation and comments.
4. Run focused checks and the main suite; record results before marking solved.

## Verification

- Run `task check`, affected tests, and `git diff --check`.
- Run the updated `task tests-run` once for final integration verification.
- Run `tests/release-build.sh` if release verification logic changes; do not
  publish or create an actual release for this task.
- Use the manual smoke results below for basic networking and port forwarding;
  no additional DNS matrix, nested HTTP fixture, or automated VS Code test is
  required.

## Verification Results

Manual smoke test after removing host mode from the development checkout's
`.devcontainer/docker-compose.yml` and recreating the devcontainer:

- HTTPS request to `https://example.com` returned HTTP `200`.
- `docker run --rm docker.io/library/hello-world` pulled and ran successfully.
- A temporary `nginx:alpine` container published workspace port `18080`; a request
  inside the devcontainer returned HTTP `200`.
- The user confirmed laptop access after forwarding port `18080` through VS Code.
- The HTTP test container was stopped and automatically removed afterward.

No release build was needed for the manual smoke test.

Implementation verification on 2026-10-27:

- Removed source Compose and direct Docker host mode, including image-test
  invocations. Added the default-network assertion to `tests/compose-config.sh`.
- Removed mandatory real forwarded-audio recording; retained missing-transport
  coverage. The existing container-local X11 regression is independent of host
  networking and remains unchanged.
- Release verification now requires `suite-isolated-network=passed` for the
  exact source commit; fixtures and workflow guidance use the same marker.
- `task check` passed, including syntax, release-layout, and runtime-worktree tests.
- The first `task tests-run` attempt hit the execution timeout during image build.
  Retried with a longer timeout: all tests passed in 257 seconds, including
  Compose, nested Docker, QEMU, browser, worktree, and submodule integrations.
- `git diff --check` passed. No release was published or source commit created.

## Cancellation Reason

Not cancelled.
