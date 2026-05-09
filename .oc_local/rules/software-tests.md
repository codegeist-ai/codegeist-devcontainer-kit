# Project Test Verification

Use this rule when making code, script, or workflow changes in this repository.

## Full Suite Default

- Run the complete `task tests-run` suite before handing off changes.
- Targeted tests are still useful while iterating, but they do not replace the
  final full-suite attempt.
- Do not run `docker system prune`, `docker builder prune`, or other Docker
  cleanup commands automatically before tests. If Docker storage is too tight,
  stop and ask for approval before pruning cache, images, containers, or volumes.
- If `task tests-run` cannot complete because the environment is blocked, for
  example Docker tmpfs exhaustion or missing host tooling, report the blocker
  explicitly and include the targeted tests that did pass.
