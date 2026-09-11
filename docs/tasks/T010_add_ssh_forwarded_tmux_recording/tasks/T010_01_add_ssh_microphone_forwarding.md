# Add SSH Microphone Forwarding

- ID: `T010_01`
- Type: `docs`
- Status: `blocked`
- Parent: `T010` (`docs/tasks/T010_add_ssh_forwarded_tmux_recording/task.md`)
- Public Tracking: `pending issue creation`
- Tracking Key: `179a280c-fd5a-4159-9a63-327c793c5ec1`

## Goal

Define a secure and repeatable manual SSH configuration that exposes a local
Linux PipeWire microphone to the Remote SSH host at `127.0.0.1:47130`.

## Context

The local PipeWire Pulse compatibility socket normally exists at
`/run/user/<uid>/pulse/native`. OpenSSH can forward a remote TCP listener to
that local Unix socket. The devcontainer uses host networking, so a loopback
listener on the SSH host is also reachable from the container.

`initialize.sh` runs on the SSH host and cannot manage the user's local audio
socket or SSH client configuration. Forwarding must remain an explicit local
prerequisite instead of hidden bootstrap behavior.

## Scope

In scope:

- Document how to find the local numeric UID and verify the PipeWire Pulse
  compatibility socket.
- Document a loopback-only SSH `RemoteForward` from remote TCP port `47130` to
  the local Pulse Unix socket.
- Document relevant SSH server forwarding prerequisites and reconnect behavior.
- Document checks from the SSH host and devcontainer that prove the listener is
  reachable.
- Record the security and ownership constraints for future kit changes.

Out of scope:

- Editing `~/.ssh/config`, `sshd_config`, or system PipeWire configuration.
- Adding scripts that create or monitor the SSH tunnel.
- Changing `initialize.sh`, `docker-compose.yml`, or the image.
- Proving audio capture before `T010_02` provides the recorder.
- Supporting macOS, Windows, TCP-exposed Pulse servers, or non-Pulse transports.

## Acceptance Criteria

- Consumer documentation includes local commands equivalent to `id -u` and
  `test -S /run/user/$(id -u)/pulse/native`.
- Consumer documentation includes this loopback-only SSH contract:

  ```sshconfig
  Host <remote-host>
    RemoteForward 127.0.0.1:47130 /run/user/<uid>/pulse/native
    ExitOnForwardFailure yes
  ```

- Documentation states that the SSH server must permit TCP forwarding and that
  users may need an administrator to enable it.
- Documentation requires a Remote SSH reconnect after configuration changes.
- The listener can be checked from both the SSH host and container without
  exposing it on a non-loopback interface.
- Normal devcontainer startup remains independent of microphone forwarding.
- No repository script or configuration attempts to modify the local or remote
  SSH setup.

## Verification

- Review both READMEs for the same endpoint, socket path, reconnect instruction,
  and loopback safety warning.
- On a configured Linux client, verify the local socket with
  `test -S /run/user/$(id -u)/pulse/native`.
- After reconnecting, verify the listener on the SSH host and in the container
  with `nc -z 127.0.0.1 47130`.
- Confirm the listener is not bound to a non-loopback address with
  `ss -ltn '( sport = :47130 )'`.
- Run `git diff --check`.

## File Targets

- `README.md`
- `README_release.md`
- `.oc_local/rules/devcontainer-kit.md`

## Dependencies

- Local Linux client running PipeWire with Pulse compatibility.
- SSH server permits TCP forwarding.
- `none` within the repository.

## Implementation Notes

1. Add a focused microphone-forwarding subsection near the existing Remote SSH
   and tmux documentation in both source and consumer READMEs.
2. Explain that the SSH client process accesses the local Unix socket as the
   local user and keeps the remote listener scoped to `127.0.0.1`.
3. Describe port conflicts and disabled forwarding as explicit SSH connection
   failures through `ExitOnForwardFailure yes`; do not add fallback ports.
4. Add a concise local rule that keeps microphone forwarding manual,
   loopback-only, and outside initialization and Compose behavior.

## Cancellation Reason

- `none`
