# Add SSH Microphone Forwarding

- ID: `T010_01`
- Type: `docs`
- Status: `solved`
- Parent: `T010` (`docs/tasks/T010_add_ssh_forwarded_tmux_recording/task.md`)
- Public Tracking: `https://github.com/codegeist-ai/codegeist-devcontainer-kit/issues/15`
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
- Document how parallel VS Code SSH sessions reuse one fixed listener through
  OpenSSH connection multiplexing.
- Document how a Pulse-compatible client selects the forwarded server and how
  FFmpeg verifies the complete audio path without writing an output file.
- Record the security and ownership constraints for future kit changes.

Out of scope:

- Editing `~/.ssh/config`, `sshd_config`, or system PipeWire configuration.
- Adding scripts that create or monitor the SSH tunnel.
- Changing `initialize.sh`, `docker-compose.yml`, or the image.
- Adding the persistent recorder command or tmux shortcut owned by `T010_02` and
  `T010_03`.
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
- Documentation explains that independent connections conflict on fixed port
  `47130` and that multiplexed sessions reuse one control-master-owned forward.
- The listener can be checked from both the SSH host and container without
  exposing it on a non-loopback interface.
- A documented FFmpeg null-output command verifies Pulse protocol access and
  five seconds of audio without creating a recording file.
- Pulse-compatible clients can select the endpoint through
  `PULSE_SERVER=tcp:127.0.0.1:47130`.
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
- Verify the full Pulse and microphone path without writing a file with
  `PULSE_SERVER=tcp:127.0.0.1:47130 ffmpeg -hide_banner -loglevel info -f pulse
  -i default -t 5 -f null -`.
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

## Implementation Plan

1. Resolve public tracking before changing the target documentation:
   - Preview and obtain explicit approval for the exact GitHub Issue title and
     body required by the shared task workflow.
   - Create or reuse the validated Issue, verify its canonical task marker, and
     replace `pending issue creation` in `Public Tracking` with the full Issue
     URL.
   - Keep this task `blocked` until public tracking is valid. Do not treat a
     request to implement the task as approval to create the Issue.
2. Add an `SSH Microphone Forwarding` section immediately after `OpenCode In
   tmux` in `README.md` and `README_release.md`:
   - State that VS Code Remote SSH does not forward microphone audio and that
     this procedure applies only to a local Linux PipeWire client with the
     PulseAudio compatibility socket.
   - Show `id -u` and
     `test -S "/run/user/$(id -u)/pulse/native"` as local preflight commands.
   - Explain that `<uid>` in SSH configuration is replaced with the numeric
     output of `id -u`; OpenSSH configuration does not evaluate shell command
     substitutions.
3. Document the fixed client-side SSH configuration in both READMEs:

   ```sshconfig
   Host <remote-host>
     RemoteForward 127.0.0.1:47130 /run/user/<uid>/pulse/native
     ExitOnForwardFailure yes
   ```

   - Explain that the local SSH client opens the Unix socket as the local user.
   - Explain that `ExitOnForwardFailure yes` fails the SSH connection when the
     remote listener cannot be established, such as when port `47130` is in use
     or forwarding is rejected. It does not guarantee that later connections
     to the local Pulse socket will succeed.
   - Do not document fallback ports, wildcard listeners, TCP-exposed local Pulse
     servers, or alternate audio transports.
4. Document SSH server and lifecycle prerequisites in both READMEs:
   - State that the server must permit remote TCP forwarding through its
     effective `AllowTcpForwarding` and `DisableForwarding` policy, and that a
     restricted `PermitListen` policy must allow `127.0.0.1:47130`.
   - Tell users to ask the SSH host administrator for server-side changes; do
     not instruct repository automation to edit `sshd_config`.
   - Require a full VS Code Remote SSH reconnect after changing the local SSH
     configuration.
   - State that the listener exists only while its owning SSH connection is
     active and is recreated on a later connection.
5. Document reachability and bind-safety checks:

   ```bash
   nc -z 127.0.0.1 47130
   ss -ltn '( sport = :47130 )'
   ```

   - Run both commands on the SSH host and require the `ss` result to show only
     `127.0.0.1:47130`, never a wildcard or non-loopback bind.
   - Run `nc -z 127.0.0.1 47130` inside the devcontainer. Explain that this
     works because the workspace service uses host networking.
   - Warn that loopback prevents exposure to other network hosts but does not
     isolate the endpoint from processes that can access loopback on the SSH
     host. Such processes may reach the forwarded Pulse server with the local
     SSH user's access, so the procedure is appropriate only on a trusted host.
6. Keep startup behavior independent:
   - State that microphone forwarding is an optional, manually managed
     prerequisite for the future recorder.
   - State that a missing tunnel must not affect devcontainer initialization,
     ordinary OpenCode use, or tmux.
   - Do not change `initialize.sh`, `docker-compose.yml`, the image, local SSH
     files, server SSH files, or PipeWire configuration.
7. Add a `Microphone Forwarding` subsection to
   `.oc_local/rules/devcontainer-kit.md` that preserves the implementation
   boundaries:
   - Keep forwarding manual and Linux-client-owned.
   - Keep the transport fixed to `/run/user/<uid>/pulse/native` and
     `127.0.0.1:47130`.
   - Forbid wildcard binds, fallback ports, automatic tunnel management, and
     startup dependencies.
   - Require `README.md` and `README_release.md` to remain aligned on the
     endpoint, socket, reconnect behavior, server prerequisites, and security
     warning.
8. Verify the completed documentation:
   - Review both README sections side by side for the same commands and
     behavioral contract.
   - Run `git diff --check`.
   - On an explicitly configured Linux client and active SSH connection, run
     the local socket check and the host/container reachability checks from the
     `Verification` section. If that environment is unavailable, report those
     checks as unexecuted rather than claiming success.
9. Complete task tracking only after verification:
   - Close the validated linked GitHub Issue with reason `completed` and read it
     back to verify the closed state and canonical linkage.
   - Change this task's status to `solved` only after that remote confirmation.
   - Leave the parent task open until `T010_02` and `T010_03` complete their own
     scopes.

## Verification Results

The manual environment verification completed on a Linux PipeWire client and a
host-networked devcontainer:

- `id -u` returned the local UID used in the socket path, and
  `test -S /run/user/$(id -u)/pulse/native` succeeded.
- `ssh -G <remote-host>` confirmed `ControlMaster auto`, the intended shared
  `ControlPath`, `ControlPersist 60`, `ExitOnForwardFailure yes`, and the
  normalized remote forward `[127.0.0.1]:47130` to the local Pulse Unix socket.
- A verbose initial SSH connection reported `remote forward success` and created
  the multiplex master. A second session reported `found existing forwarding`,
  confirming reuse without a second remote bind attempt.
- `ssh -O check <remote-host>` reported the master running while the sessions
  were active.
- Inside the devcontainer, `ss -ltn '( sport = :47130 )'` showed exactly one
  `127.0.0.1:47130` listener, and `nc -vz -w 3 127.0.0.1 47130` succeeded.
- The FFmpeg null-output check connected to Pulse source `default`, identified
  48 kHz 16-bit stereo input, processed five seconds at real-time speed, and
  exited without connection, authentication, input, or encoding errors.
- The matching `README.md` and `README_release.md` sections were compared
  directly, `git diff --check` passed, and the repository's `task check` passed.
- GitHub Issue `#15` was closed with reason `completed`; its canonical task id,
  path, Tracking Key, and source-of-truth statement were read back successfully.

## Cancellation Reason

- `none`
