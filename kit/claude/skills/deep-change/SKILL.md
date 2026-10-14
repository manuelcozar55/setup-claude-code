---
name: deep-change
description: Plan, execute and verify substantial code or configuration changes with a change report and isolated validation. Use for cross-module changes, migrations, security or production changes, or an explicit /deep-change request. Skip trivial edits, read-only audits and pure Q&A; scale the workflow to the actual risk.
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
2. **Investigate the affected paths.** Use independent subagents when delegation is available,
   authorized and helps separate substantial work; otherwise investigate directly. Give each
   worker explicit ownership and collect evidence, not raw file dumps.
3. **Plan as an artifact.** Reuse and update an existing approved plan, or create
   `<topic>-plan.md` when none exists: bite-
   sized, independently verifiable tasks, each with the exact files, the change, and how it
   is tested. The plan is a durable spec, not chat.
4. **Execute.** Work
   task by task. After each task: verify, then append to the change report (below). Do not
   advance on red.
5. **Verify empirically.** Reproduce the
   problem first, then prove the fix. Run the real tests / drive the real path. **Evidence
   before "done"** — never claim success from a plausible read.
6. **Contain risk.** Build and validate in an **isolated copy** (a `/final`-style folder, a
   branch, a worktree). Applying to production / live config / shared state is a **separate,
   authorized step**. An existing explicit instruction to apply the reviewed changes satisfies
   this gate; do not ask again. Back up before overwriting anything you did not create.
7. **Be honest about cost/benefit.** Rate proposals on real axes (benefit · risk/availability
   · token cost), and **state what you rejected and why.** Surface tradeoffs; don't hide them.

## Two non-negotiable habits (the part tooling won't do for you)

**Living change report — `<topic>-cambios.md`.** One entry per modification, written as you
go, each with: *what changed · why (justification) · how it was verified.* Start it before the
first edit; keep it current. It is the audit trail that lets a reviewer (or future-you) trust
the work without re-deriving it.

**Containment ledger.** State plainly, at all times, what is done *in the isolated copy* vs
what is *live in production*. When work is validated, apply it if that step is already authorized;
otherwise request approval for the concrete result. Record a rollback path to the backup.

## Verification discipline

- A test that only asserts what the code already does proves nothing. Write the test that
  **fails first** on the bug, then passes on the fix.
- Prefer driving the actual artifact (run it, screenshot it, pipe the real protocol) over
  "types check, so it works."
- If you couldn't verify something, say so — mark it explicitly, don't imply it passed.

## Fit with the global principles

- **IntentGate** is satisfied by the existing task opening plus any necessary decision in phase 1.
- **Never-Stop** governs *execution*: once approved, drive to completion without "should I
  continue?"; if ambiguity appears mid-run, take the most conservative **reversible** choice
  and note it in the change report. The approval gate is *before* execution — no contradiction.
- Delegate substantial independent work using available roles when it improves the result.

## Definition of done

- [ ] Scope and consequential design decisions resolved; existing authorizations honored.
- [ ] The approved plan exists and every task is checked off.
- [ ] Every change has a `<topic>-cambios.md` entry (what / why / verified).
- [ ] Claims are backed by evidence (tests run, path driven) — recorded, not asserted.
- [ ] Risk contained: isolated copy validated; production apply is a separate authorized step
      with a known rollback.
- [ ] Rejected alternatives and residual risks stated honestly.
- [ ] If the person had to correct course more than once, the report suggests `/retro`.
