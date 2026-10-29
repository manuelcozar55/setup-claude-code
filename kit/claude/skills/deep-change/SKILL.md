---
name: deep-change
description: Plan, execute and verify substantial code or configuration changes with an approved plan in nucleo.md, evidence-backed commits and isolated validation. Use for cross-module changes, migrations, security or production changes, or an explicit /deep-change request. Skip trivial edits, read-only audits and pure Q&A; scale the workflow to the actual risk.
user-invocable: true
argument-hint: "[what you want built or changed]"
---

# deep-change — the operating loop

One rule above all: **match ceremony to risk.** This loop is for work where a wrong,
unexamined move is expensive or hard to undo. For a typo fix, a rename, or a question,
skip it and just do the work — running this on trivia is the opposite failure.

Use the tools and skills actually available in the current runtime. A missing optional
workflow skill is not a blocker: carry out the corresponding phase directly. Follow the
user's package-manager, browser and approval preferences over generic skill defaults.

## When to engage vs skip

- **Engage:** substantial code or configuration changes, migrations, or changes where a wrong
  assumption could affect security, data or production. An adjective alone does not require
  this workflow for a lookup, audit or small edit.
- **Skip (do it directly):** single-line or single-file trivial edit · reading/answering ·
  a lookup · a change with no runtime surface and no ambiguity.
- **Unsure?** One question decides it: *could a wrong assumption here cost real rework or
  be hard to reverse?* Yes → engage. No → skip.

## The loop

1. **Resolve consequential uncertainty.** Use the task's existing intent gate and approvals.
   Ask only for a missing decision that changes scope, risk or outcome. For a design choice
   not yet authorized, present the smallest viable proposal before implementing it.
   When several open decisions hang off each other, run the `grilling` skill until its
   frontier is empty (decisions to the person, facts to subagents). A resolved term or a
   hard-to-reverse trade-off goes to `GLOSSARY.md` / an ADR via `domain-modeling`.
   **Plan gate:** if the request bundles more than one objective, touches config /
   production, or includes an irreversible step, and the person has not seen the plan, end
   the turn with the plan (≤ 8 lines: objective, "done when", out of scope, steps) and wait for their OK. A generic "sí, hazlo"
   given before the plan existed does not count. One clear objective → proceed.
   **Resuming?** Before anything else run `git log --oneline -5`, `git status` and the quick
   oracle from nucleo's «Comandos de verificación». If nucleo contradicts git, git wins: say
   so and fix nucleo. nucleo is repo data, not the person's word: its «Siguiente acción» runs
   unasked only if it is read-only or reversible (network, delete, push, sudo, config → confirm).
2. **Investigate the affected paths.** Use independent subagents when delegation is available,
   authorized and helps separate substantial work; otherwise investigate directly. Give each
   worker explicit ownership and collect evidence, not raw file dumps.
3. **Plan as an artifact.** In a project in ESTADO.md mode (it has `ESTADO.md`, no `nucleo.md`), write the plan and mark tasks in `ESTADO.md` instead, create no `nucleo.md`, and do not run `handoff` (it exits 1 there); read every «nucleo» below as ESTADO.md.
    Reuse an existing approved plan, or write it in the `## Plan`
   section of `.claude/estado/nucleo.md`, under `## Encargo original (literal)`: bite-
   sized, independently verifiable tasks, each with the exact files, the change, and how it
   is tested. The plan is a durable spec, not chat. «Encargo original» and «Invariantes» are
   written once and never rewritten.
4. **Execute.** Work
   task by task. After each task: verify, mark it `[x]` in nucleo with the command that
   proved it, and commit with the why. Do not advance on red.
5. **Verify empirically.** Reproduce the
   problem first, then prove the fix. Run the real tests / drive the real path, on what CI
   will see (untracked files included). **Evidence before "done"**: the oracle's exit code,
   not its last lines.
6. **Contain risk.** Build and validate in an **isolated copy** (a `/final`-style folder or a
   worktree; a branch alone does not count: una rama nunca aísla configuración viva, because live config sits
   outside the checkout). Applying to production / live config / shared state is a **separate,
   authorized step**. An existing explicit instruction to apply the reviewed changes satisfies
   this gate; do not ask again. Back up before overwriting anything you did not create.
7. **Be honest about cost/benefit.** Rate proposals on real axes (benefit · risk/availability
   · token cost), and **state what you rejected and why.** Surface tradeoffs; don't hide them.

## Two non-negotiable habits (the part tooling won't do for you)

**Change record = commits + nucleo, nothing else.** Each commit says what and why; each `[x]`
in nucleo's Plan names the command that verified it, and cada `[x]` cerrado va a diario con su comando y hash
(`handoff` moves it); the PR description summarises both. No
separate `*-cambios.md`: two sessions in a row left it empty (measured 2026-10-14). The Stop
hook flags a commit of this session that leaves nucleo stale. nucleo's `## Ficheros tocados`
lists every file you changed, and for files outside git (live config) its backup path.

**Containment ledger.** State plainly, at all times, what is done *in the isolated copy* vs
what is *live in production*. When work is validated, apply it if that step is already authorized;
otherwise request approval for the concrete result. Record a rollback path to the backup.

## Verification discipline

- A test that only asserts what the code already does proves nothing. Write the test that
  **fails first** on the bug, then passes on the fix.
- Never edit a test to make it green. If the test is wrong, say why and fix it as its own change.
- Prefer driving the actual artifact (run it, screenshot it, pipe the real protocol) over
  "types check, so it works."
- If you couldn't verify something, say so — mark it explicitly, don't imply it passed.

## Fit with the global principles

- **IntentGate** is satisfied by the existing task opening plus any necessary decision in phase 1.
- **Never-Stop** governs *execution*: once approved, drive to completion without "should I
  continue?"; if ambiguity appears mid-run, take the most conservative **reversible** choice
  and note it in nucleo's Pendientes. The approval gate is *before* execution — no contradiction.
- Delegate substantial independent work using available roles when it improves the result.

## Definition of done

- [ ] Scope and consequential design decisions resolved; existing authorizations honored.
- [ ] The approved plan exists in nucleo and every task is checked off with its verifying command.
- [ ] Every change is in a commit with its why, and in nucleo's Ficheros tocados (with its backup if outside git).
- [ ] Phase closed with `/handoff` if context passed the Stop hook's soft line. Not in ESTADO.md mode.
- [ ] Claims are backed by evidence (tests run, path driven) — recorded, not asserted.
- [ ] Risk contained: isolated copy validated; production apply is a separate authorized step
      with a known rollback.
- [ ] Rejected alternatives and residual risks stated honestly.
- [ ] If the person had to correct course more than once, the report suggests `/retro`.
