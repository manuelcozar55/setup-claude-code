# Guide · The short route (English)

The full guide is in Spanish; this is the one-screen version. Figures were measured on a real setup in 2026 and anonymized.

**Why it matters.** Every turn resends everything loaded: ~45k fixed tokens per turn on a loaded setup (tool schemas 25k, skill list 5.6k, memory index 4.5k, instructions 3.2k). When the window fills, auto-compaction throws away ~88 % of the context and takes ~150 s. 84 % of what gets compacted is tool I/O, and 63 % of compactions happen inside a single autonomous turn. Only what is on disk survives, yet 75 % of compactions arrived with a state file untouched in the previous 20 turns.

| Day | Habit | Done when |
|---|---|---|
| 1 | Install ([`10-onboarding.md`](../10-onboarding.md)), then run `/context` in a fresh session | you have your fixed-cost baseline written down |
| 2 | Keep `.claude/estado/nucleo.md` in a fixed shape: original request, invariants, plan, current step, next action, open items, touched files, verification commands. Finished work moves out. | a new session can tell you the next action without you pasting it |
| 3 | Close each phase with `/handoff` ([`11-cockpit.md`](../11-cockpit.md)) or update the file and `/clear`. One task, one session. | the new session starts with `git log` and `git status`, as the startup hook asks |
| 4 | Learn which incident each hook prevents ([`05-security.md`](../05-security.md#hook--incidente-que-evita)) | you can justify every hook in your `settings.json` |
| 5 | Delegate any search longer than three queries to a subagent; cap shell output (`tail -n 40`, `grep -c`) | `/context` barely grows in the main thread |
| 6 | One short line per memory entry; look facts up with `recuerda <terms>` | your memory index fits in 60 short lines |
| 7 | Measure yourself ([`04-mide-tu-setup.md`](04-mide-tu-setup.md)) | three dated numbers: fixed cost, % manual compactions, % sessions with corrections |

**Anti-patterns that cost something real** ([`03-antipatrones.md`](03-antipatrones.md)): a session left open for 42 days with 66 compactions; a compression proxy that saved 0.2–0.6 % and was removed; `effortLevel: "max"` silently falls back to `high` (use `"xhigh"`); `--1m` breaks Haiku subagents (put `[1m]` in the model id instead); `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` measured as inert on the 1M path; a 78 KB diary-style `nucleo.md` injected in pieces (hook output caps at 10,000 characters); `Bash(node *)` in `allow` is arbitrary code execution; `/model` never sticks when `ANTHROPIC_MODEL` is set in `env`; in `Edit(/x)` one slash anchors to the settings directory, `//x` to the filesystem root.

See it working, with real hook outputs: [`02-sesion-real.md`](02-sesion-real.md). Trim the template to your case: [`06-adaptar.md`](06-adaptar.md).
