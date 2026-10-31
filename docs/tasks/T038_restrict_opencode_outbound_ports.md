# Restrict OpenCode Outbound Ports

- ID: `T038`
- Type: `feature`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `3b5c1cfa-27d5-4655-b334-f31c4cbaa541`

## Goal

Enforce an outbound destination-port allowlist for OpenCode and its child
processes while retaining normal workspace access, development tools, and
ordinary `sudo` operations.

## Context

The requested configuration name and example are:

```dotenv
OPENCODE_ALLOWD_PORTS=22,443,80
```

Proxy environment variables alone cannot enforce this policy. The user wants
kernel-level control of connection attempts by the process tree, including
ordinary elevated child processes, without moving OpenCode into a separate
restricted filesystem or removing normal administrative workflows.

Docker delegates work to an existing daemon outside that process tree. Closing
that additional bypass belongs to follow-up
[T039](T039_harden_docker_access_for_opencode.md). Until it is complete, document
Docker-mediated networking as a known gap rather than claiming complete isolation.

## Scope

- Use `OPENCODE_ALLOWD_PORTS` consistently as the comma-separated destination-port
  policy. Validate ports before managed startup; malformed, empty, or missing
  required policy must not silently launch an unrestricted process.
- Assign OpenCode to the managed enforcement scope before it creates sockets.
  Cover child processes across fork/exec and normal `sudo` transitions.
- Enforce the policy in the kernel, including direct connections that ignore
  or unset HTTP proxy variables. A cgroup v2 with targeted network filtering is
  the preferred candidate; verify actual kernel/controller support first.
- Cover IPv4 and IPv6 and explicitly handle TCP, UDP, and required network-control
  traffic. Define narrow DNS and local-service exceptions; do not leave an
  unfiltered protocol or address-family fallback.
- Put the shared mitmproxy under the same effective outbound policy so local
  proxy access cannot relay requests to otherwise forbidden destination ports.
- Protect policy administration and group membership against modification from
  the managed process tree. Preserve normal file/package administration through
  `sudo`; identify administrative actions incompatible with maintaining the rule.
- Integrate with `oc`, startup configuration, diagnostics, documentation, and
  real allow/deny tests.

Out of scope: general filesystem sandboxing, domain/content filtering, a new
isolated agent container, and the Docker delegation controls specified in T039.

## Acceptance Criteria

- Managed OpenCode processes and their children can connect to allowed ports
  and cannot directly connect to forbidden ports, including after `sudo` and
  removal of proxy environment variables.
- The logging proxy obeys the same port policy. Allowed local OpenCode/MCP
  traffic and DNS work through explicitly documented exceptions.
- Normal workspace file access, installed tools, and ordinary `sudo` operations
  remain usable. Other applications are not unintentionally enrolled in the
  OpenCode-specific policy.
- Changing the environment in a child, migrating to another group, or modifying
  the filter cannot silently relax the active policy. Unsupported enforcement
  or an unresolved privilege conflict is reported as a blocker rather than
  described as a successfully enforced restriction.
- Startup through both tmux paths and concurrent OpenCode sessions uses the
  intended policy without leaving an unrestricted startup window.
- Documentation clearly states protocol coverage, local exceptions, how policy
  changes take effect, and the remaining daemon-mediated gap addressed by T039.

## Verification

- Use real routed test endpoints on allowed and forbidden ports over IPv4/IPv6;
  distinguish rejection by policy from an unavailable destination service.
- Exercise direct clients, shell children, `sudo` clients, and proxied requests.
- Test DNS/local communication, invalid policy, policy modification/group escape
  attempts, and enforcement setup failure. Do not use live host-wide firewall
  changes as an exploratory test fixture.
- Run `task check`, `task tests-run`, and `git --no-pager diff --check`.

## File Targets

- `cmds/oc`, `entrypoint.sh`, `.local.env.example`, `docker-compose.yml`
- `Dockerfile.base` and a focused network-policy helper if required
- OpenCode, container, and network integration tests
- `README.md`, `README_release.md`, relevant runtime rules

## Dependencies

- [T034](T034_log_opencode_http_requests.md): shared proxy integration.

## Blockers

None at specification time. Enforcement feasibility and the precise protected
administrative boundary must be demonstrated during implementation.

## Implementation Notes

A parent cannot predict all future network use when it starts a command; apply
the policy at the kernel network boundary. Cgroups provide grouping without
requiring a separate filesystem or network namespace. Check the actual socket
and packet coverage of the selected mechanism rather than assuming inheritance
alone covers all traffic.

Place enrollment immediately before OpenCode execution inside the tmux pane;
wrapping only the tmux client does not enroll commands spawned by an existing
tmux server. Assess other local brokers that could execute work outside the
scope. Do not equate retaining `sudo` with granting authority to disable the
network policy. Coordinate startup edits with
[T035](T035_minimize_container_entrypoint.md) and retain its minimal-startup goal.

## Cancellation Reason

Not cancelled.
