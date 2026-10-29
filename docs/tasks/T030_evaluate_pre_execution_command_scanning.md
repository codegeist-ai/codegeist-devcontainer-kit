# Evaluate and Integrate Pre-execution Command Scanning

- ID: `T030`
- Type: `feature`
- Status: `specified`
- Parent: `none`
- Public Tracking: `not requested`
- Tracking Key: `fef8f0c6-045c-4b4f-bf4c-cf6e7f20744e`

## Goal

Evaluate an existing command analyzer for OpenCode and implement a small,
non-blocking pre-execution integration if it fits. Surface potentially dangerous
commands without limiting the agent's normal coding work on real Bash.

## Context

Prompt injection can cause an agent to generate harmful commands. T028 logs
shell starts and their arguments but does not assess commands. The user wants
additional visibility without restricting tools, privileges, Docker, sudo,
interpreters, or normal automation, and without frequent approval prompts.

Initial candidates are Destructive Command Guard (`dcg`) and CC Safety Net.
Evaluate dcg first; compare CC Safety Net if needed. Their stock integrations
can block commands, so installing a default guard is not equivalent to the
requested observation-only behavior. In particular, dcg's broad warning policy
does not necessarily relax critical rules. Confirm the selected version's actual
analysis-only interface and behavior rather than relying on a mode name.

## Scope

- Evaluate a pinned version's analysis API/CLI, license, installation,
  maintenance status, OpenCode compatibility, latency, and diagnostic quality.
- Use a small representative command corpus to assess useful detections and
  false positives in this repository's normal workflows.
- If suitable, install the analyzer through the kit's image setup and integrate
  it before OpenCode shell-tool execution, preferably at the original-command
  hook rather than parsing the generated Bash startup block.
- Record decisions with stable fields and show concise warnings for matches.
- Keep the original Bash command, arguments, working directory, output, exit
  status, and existing T028 shell log behavior intact.
- Update packaging, focused tests, and source/consumer documentation as needed.

Out of scope: automatic blocking, operator approval flows, sandboxing, privilege
or network restrictions, daemon control, host-wide monitoring, a custom detection
engine, and release publication.

## Evaluation And Decision

1. Test ordinary Git reads/writes, builds, package installation commands, Docker
   operations, temporary cleanup, and repository test/release entrypoints.
2. Include chained commands, quoting, multiline Bash, heredocs, `bash -c`,
   interpreter one-liners, and dangerous-looking text used only as data.
3. Submit harmful examples to the analyzer only; never execute them. Cover
   destructive filesystem/Git operations and representative download-and-execute
   or secret-transfer patterns, recording unsupported categories honestly.
4. Record representative verdicts, false positives, and measured overhead. Check
   whether analysis performs network requests or persists command content.
5. Select a candidate only if useful warnings, tolerable noise/latency, and a
   small reliable observation-only integration are demonstrated. Record the
   evidence and proceed with implementation in this task when it fits.
6. If neither fits, record the reasons and finish as an evaluation-only outcome;
   do not introduce blocking or a larger framework to force an implementation.

## Acceptance Criteria

- The task records the tested version, evaluation commands/corpus, observations,
  limitations, and explicit implement-or-reject decision.
- If integrated, each supported shell call is analyzed before execution using
  its command text and actual working directory.
- Matches produce a rule identifier and concise reason without changing whether
  the command executes. No-match is labeled `no_match`, never `safe`.
- Analyzer errors, missing binaries, and timeouts produce an explicit
  `scan_unavailable` diagnostic and allow the original command to proceed.
  External analyzer execution has a bounded timeout so scanning cannot hang work.
- Analysis never evaluates the submitted command. Ordinary commands and harmless
  suspicious-text fixtures continue to run unchanged under real Bash.
- Logs use stable events and distinguish `match`, `no_match`, and
  `scan_unavailable`; documented fields identify the command/tool call and cwd.
  Avoid duplicate raw-command logs where the existing T028 log is sufficient.
- Documentation explains coverage, sensitive command content, and the limits of
  static analysis: called scripts, runtime downloads, package hooks, other tools,
  and future child processes are not proven harmless by a no-match result.
- No automatic denial, permission narrowing, or interactive approval is added.
- Shared `.opencode/` is not edited directly; use the kit's supported runtime
  integration path or consuming-project `.oc_local/` overlay. Verify the actual
  OpenCode plugin contract and restart requirements for the tested version.

## File Targets

- `docs/tasks/T030_evaluate_pre_execution_command_scanning.md`
- `Dockerfile.base`, if an analyzer is selected
- `cmds/oc` and a small plugin/adapter only if justified by evaluation
- Runtime packaging and existing image/OpenCode tests where affected
- `README.md`, `README_release.md`

## Dependencies

- T028 provides the existing shell-start log; no dependency on T029.

## Verification

- Evaluate analyzer inputs without executing harmful examples, using disposable
  fixtures outside the repository or under its existing `.tmp/`.
- If implemented, test a normal command, a harmless command triggering a match,
  and an unavailable/timed-out analyzer. All commands must still execute with
  their original observable behavior, and diagnostics must distinguish outcomes.
- Verify one real OpenCode tool call reaches the integration; configuration or
  plugin-loader checks alone do not prove pre-execution coverage.
- Run `task check`, affected tests, and `git diff --check`; run `task tests-run`
  if image contents or runtime integration change.

## Implementation Notes

- Prefer one existing analyzer and one small adapter over multiple scanning
  layers. Keep the user-visible workflow unchanged.
- References for evaluation, not assumptions about a future pinned version:
  - https://github.com/Dicklesworthstone/destructive_command_guard
  - https://github.com/Dicklesworthstone/destructive_command_guard/blob/main/docs/opencode-integration.md
  - https://ccsafetynet.com/docs/reference/library-api
  - https://ccsafetynet.com/docs/guides/security-model

## Cancellation Reason

Not cancelled.
