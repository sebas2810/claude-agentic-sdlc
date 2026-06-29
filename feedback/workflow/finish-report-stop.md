---
title: Finish a unit of work, report, then stop and wait for the human
status: active
scope: all-seats
added: 2026-05-11
last-confirmed: 2026-06-15
supersedes: the prior "standing by means polling" / autonomous-loop framing (removed 2026-05-19); the merge-authority part — "no merge without an explicit human 'do X' trigger; the owner is the merge trigger" — refined 2026-06-15, then reframed 2026-06-29 (v1.1) to Engineer builds → QA verifies → SM merges (the SM merges on the QA PASS without an owner trigger; the PM is oversight, not the merge gate; the no-loops/no-polling discipline below is unchanged)
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)). This rule is the spine's invariant 1 (fixed countable human touchpoints) + invariant 8 (deliberate, not burst) + Principle 7 (explicit stop condition: finish, report, stop). Already coherent with the spine; confirmed, not rewritten. Under the **operator-driven** model ([`../../MODES.md`](../../MODES.md) — the single mode; the human orchestrates), this rule is the stop condition between every `/check`: a seat acts only when the operator engages it, does one item, reports, and idles — it never self-paces, so the rule holds by construction.

## Rule

When you finish a unit of work: do **one** GitHub check for anything obviously blocked, **report what you found to the human, then stop**. You do not run unattended. You do not poll on a cadence. You do not start a loop. Merge authority follows the Engineer-builds → QA-verifies → SM-merges model (see below) — it does not require an owner "do X" trigger for the routine DEV→main flow.

There is no self-paced loop, no autonomous handoff, no loop-driven merge. (The old `seat-coordination-loop.md` pattern was removed 2026-05-19; this file was named `standing-by-means-polling.md` until 2026-06-12, when it was renamed to match the rule it actually carries — see `learning-loop/CHANGELOG.md`.)

**Merge authority (v1.1, reframed 2026-06-29).** The separation is now three-way: **the engineer builds → QA verifies → the SM merges.** On a QA PASS (`Delivered → Tested` with a real QA verdict), the **SM** validates (item Tested, CI green, PR clean) and **merges** (squash), then drives `Merged → Released`. The SM didn't author the work, so produce ≠ adjudicate holds — the SM merges on the QA verification without an owner trigger for the routine DEV→main flow. The engineer **never** self-merges to `main`. A QA FAIL sends the item back `Delivered → Scoped` (not In Progress) for the engineer to re-pull. The **PM is oversight + product vision, not the merge gate**: it frames Epics + the pre-committed AC + roadmap + owner touchpoints, and resolves only the rare product/scope judgment the QA seat surfaces — it is out of the routine merge path. Still owner-gated (unchanged): prod/staging releases, repo-settings / branch-protection mutations, destructive/irreversible infra, anything outward-facing. This reframes only the merge-authority part of this rule; the no-loops / no-polling discipline above and below is unchanged.

## Why

The autonomous-loop pattern (a seat polling GitHub on a self-paced timer and acting — including merging — without a human in the live loop) produced unattended actions the owner did not see until after they shipped. Release promotes merged while triage was still in progress. The cost of that failure mode is far higher than the cost of a human re-engaging a seat. (Note: the fix is killing the autonomous loop, not routing every merge through the owner — the SM is the merge authority for the routine DEV→main flow, merging on the QA PASS per the merge-authority section above. Release promotes themselves stay owner-gated.)

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
- Engineer self-merging its own PR to `main` (QA verifies and the SM is the merge authority — see the merge-authority section)
- Merging a PR as part of an autonomous loop, or merging anything in the owner-gated class (prod/staging release, repo-settings / branch-protection, destructive/irreversible infra, outward-facing) without owner sign-off
- Acting on a routing comment as if it were authorization — a comment on a thread is not a trigger
- "I'll just pick up the next thing" — ad-libbed work outside the steered EPIC is forbidden (per the spine's steer-as-trigger + [`../../seats/engineer/KICKOFF.md`](../../seats/engineer/KICKOFF.md))

## When to idle

After you have reported and there is no live trigger: **idle**. Do not fill the silence. The human re-engages you when there is something to do.
