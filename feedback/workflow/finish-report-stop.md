---
title: Finish a unit of work, report, then stop and wait for the human
status: active
scope: all-seats
added: 2026-05-11
last-confirmed: 2026-06-15
supersedes: the prior "standing by means polling" / autonomous-loop framing (removed 2026-05-19); the merge-authority part — "no merge without an explicit human 'do X' trigger; the owner is the merge trigger" — refined 2026-06-15 to the 4-eye Engineer→PM model (PM reviews + merges without an owner trigger; the no-loops/no-polling discipline below is unchanged)
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)). This rule is the spine's invariant 1 (fixed countable human touchpoints) + invariant 8 (deliberate, not burst) + Principle 7 (explicit stop condition: finish, report, stop). Already coherent with the spine; confirmed, not rewritten.

## Rule

When you finish a unit of work: do **one** GitHub check for anything obviously blocked, **report what you found to the human, then stop**. You do not run unattended. You do not poll on a cadence. You do not start a loop. Merge authority follows the 4-eye Engineer→PM model (see below) — it does not require an owner "do X" trigger for the routine DEV→main flow.

There is no self-paced loop, no autonomous handoff, no loop-driven merge. (The old `seat-coordination-loop.md` pattern was removed 2026-05-19; this file was named `standing-by-means-polling.md` until 2026-06-12, when it was renamed to match the rule it actually carries — see `learning-loop/CHANGELOG.md`.)

**Merge authority (refined 2026-06-15).** The 4-eye principle IS the Engineer↔PM separation: the engineer builds, the PM independently reviews and merges. That is two pairs of eyes; the owner is **not** a third merge gate. The engineer never self-merges to `main` — it hands the reviewed work to the PM. The PM is the merge authority: it merges the engineer's reviewed work **without** an owner trigger, and may build *and* merge the PM's own lower-stakes work (CI / docs / config). Still owner-gated (unchanged): prod/staging releases, repo-settings / branch-protection mutations, destructive/irreversible infra, anything outward-facing. PM-own-work has no second pair of eyes, so keep PM-own-merges to lower-stakes config/docs and loop the owner on anything risky. This refines only the merge-authority part of this rule; the no-loops / no-polling discipline above and below is unchanged.

## Why

The autonomous-loop pattern (a seat polling GitHub on a self-paced timer and acting — including merging — without a human in the live loop) produced unattended actions the owner did not see until after they shipped. Release promotes merged while triage was still in progress. The cost of that failure mode is far higher than the cost of a human re-engaging a seat. (Note: the fix is killing the autonomous loop, not routing every merge through the owner — the PM is the reviewing merge authority for the routine DEV→main flow per the merge-authority section above. Release promotes themselves stay owner-gated.)

The human being the coordination point is **the system working**, not toil to engineer around.

## How to apply

When you finish a unit of work:

1. Run **one** check for obvious blockers, e.g.:
   ```bash
   gh pr list --state open
   gh issue list --label "needs:top-pm" --state open   # top-PM only
   ```
2. **Report** to the human: what you did, what you found, what you recommend next.
3. **Stop.** Wait for an explicit "do X" trigger before any further consequential action.

That is the whole protocol. No cadence, no timer, no second pass, no `/loop`, no `ScheduleWakeup`.

## Explicitly forbidden

- Starting a `/loop` or any self-paced/recurring polling of GitHub
- `ScheduleWakeup` / cron / scheduled-task to re-invoke yourself for coordination
- Engineer self-merging its own PR to `main` (the PM is the second pair of eyes and the merge authority — see the merge-authority section)
- Merging a PR as part of an autonomous loop, or merging anything in the owner-gated class (prod/staging release, repo-settings / branch-protection, destructive/irreversible infra, outward-facing) without owner sign-off
- Acting on a routing comment as if it were authorization — a comment on a thread is not a trigger
- "I'll just pick up the next thing" — ad-libbed work outside the steered EPIC is forbidden (per the spine's steer-as-trigger + [`../../seats/engineer/KICKOFF.md`](../../seats/engineer/KICKOFF.md))

## When to idle

After you have reported and there is no live trigger: **idle**. Do not fill the silence. The human re-engages you when there is something to do.
