---
name: verification-before-completion
description: "Use before saying work is done, fixed or passing, and before committing or opening a PR: run the command that proves the claim and read its real exit code and output first."
---

<!-- Adaptado de https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/verification-before-completion/SKILL.md (MIT). Cambios: tono rebajado, comandos y oráculo del kit, sin referencias a skills ajenas. -->

# Verification Before Completion

A claim such as "tests pass" or "bug fixed" is only as good as the evidence behind it. Memory of an earlier run, a plausible diff or a confident feeling do not count: the state of the code may have changed since, and a wrong "done" costs the reader more than a minute of re-running.

The rule: before stating a status, run the command that proves it in this same turn, read the whole output and its exit code, and report what it actually shows.

## The gate

1. Identify the command that proves the claim.
2. Run it in full, fresh (not a subset, not a cached result).
3. Read the output and the exit code; count the failures.
4. If the output contradicts the claim, report the real status with the evidence. If it confirms it, report the claim together with the evidence.
5. Only then say it is done.

## Commands in this kit

- Project oracle: `oraculo -- <cmd>` when the project has it; it reports the command's real exit code.
- Otherwise `make test`, or the command listed under "Comandos de verificación" in `.claude/estado/nucleo.md` when that file exists. Prefer that list over guessing.
- When piping, the pipe hides the exit code of the first command: use `set -o pipefail`, or read `${PIPESTATUS[0]}`. `cmd | tail` returning 0 proves nothing about `cmd`.
- Quote the command and its rc in the report, for example `make test -> rc=0, 49 suites`.

## What counts as evidence

| Claim | Requires | Not enough |
|---|---|---|
| Tests pass | Test command output with 0 failures and rc=0 | A previous run, "should pass" |
| Linter clean | Linter output with 0 errors | A partial check, extrapolation |
| Build succeeds | Build command with rc=0 | The linter passing, clean-looking logs |
| Bug fixed | The original symptom reproduced before and absent after | Code changed, assumed fixed |
| Regression test works | Red-green cycle done (below) | The test passing once |
| Delegated agent finished | `git diff` / `git status` show the expected changes | The agent's report says "success" |
| Requirements met | Line-by-line checklist against the spec or plan | Tests passing |

## Regression tests: red then green

A test that never failed has not shown it can catch the bug.

1. Write the test and run it: it passes with the fix.
2. Revert the fix (or comment out the guarded line) and run it: it must fail.
3. Restore the fix and run it: it passes again.

## Wording that signals missing evidence

Stop and verify when you are about to write "should work", "probably", "seems to", or to express satisfaction ("Done!", "Perfect!") before any command ran. The same goes for committing or opening a PR without a fresh run, trusting a sub-agent's success report, or relying on a partial check because the full one is slow. Being tired or sure of the change does not replace the run.

## When to apply

- Before any statement that work is complete, fixed or passing, in any wording.
- Before committing, opening a PR, or moving to the next task.
- After delegating: check the diff yourself before reporting the delegate's result as yours.
- For requirements: re-read the plan, build a checklist, verify each item, and report the gaps or the completion.
