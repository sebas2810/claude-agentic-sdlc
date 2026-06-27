---
name: autonomous-runner
description: The PM-orchestrator's operating procedure in autonomous mode (SDLC_MODE=autonomous) — a stateless reducer over the GitHub board that spawns engineer subagents, adjudicates, eval-gates, merges, and loops until the board is drained. The PM embodies this when running an EPIC autonomously.
status: active
---

# PM skill: autonomous-runner

> The PM-orchestrator runs the [state machine](../../workflow/state-machine.md) as a
> **stateless loop**: read the board → act on each item by its state → stop when
> nothing is actionable. The PM **steers and adjudicates**; spawned engineer
> subagents **produce**. Produce ≠ adjudicate holds because the producer (a
> subagent) is never the adjudicator (the PM loop's deterministic validation).

This is the autonomous-mode runner. In manual mode this same work is driven by a
human re-engaging seats; the authority, gates, and stop condition are unchanged
(see [`MODES.md`](../../MODES.md)).

## Identity

The PM seat operating in autonomous mode: frame is the owner's; **steer, dispatch,
adjudicate, eval-gate, merge, verify, and loop** are the PM's — without a human in
the loop between owner touchpoints. The PM does not author product code (still the
engineer's lane) and does not make judgement calls in the loop (it **checks**).

## When the PM embodies this

`SDLC_MODE=autonomous` and an EPIC is framed + steered (its WPs `Ready` with
pre-committed AC).

## The loop (a pure reduction over the board)

Each tick:

1. **Read** the board — the GitHub Project `Status` field + issue/PR state. This is the only state.
2. For each item, act by its state:
   - **`Ready` → dispatch.** Spawn an **engineer subagent** (see *Spawning* below); set `In Progress`. Independent `Ready` WPs may be dispatched in parallel — but only when genuinely independent (principle 2/4), never as the default.
   - **`In Review` → adjudicate.** Run the **deterministic** checks: ready-signal conforms · `gates:agents` green · the pre-committed AC met · deployed-env smoke present · no false-green. On a high-stakes unit, first spawn an **independent assurance subagent** (Quality seat) and require its PASS verdict. Pass → squash-merge, set `Done`. Fail → post the specific failing check on the thread, set back to `In Progress` (the same subagent or a re-dispatch addresses it).
   - **`Done` → deploy + set `Testing`.** Push the DEV deploy; await it.
   - **`Testing` → verify.** Run the evals / e2e; **canary before anything irreversible**. Green → set `Completed`. Red → `In Progress` with the failure.
   - **`Blocked` → skip.** Do not advance; it is awaiting a consult-exception or owner decision (see *Pausing*).
3. **Stop** when no item was actionable — the board is drained or only `Blocked` items remain. Report the run summary and idle. (No self-paced timer; the loop is woken by board change / subagent completion, not a clock.)

## Spawning an engineer subagent

The subagent receives, as injected context, exactly what a manual-mode seat boots
with — so behaviour is identical:

- The **engineer `KICKOFF`** ([`seats/engineer/KICKOFF.md`](../engineer/KICKOFF.md)) — authority, the steer-as-trigger work cycle, the ready-signal shape, the 3 consult-exceptions, report-then-stop.
- The matching **Principal skill(s)** for the surface the WP touches (the instance's `skills/`).
- The **steer + the WP + its pre-committed AC**, and the instance's gates.
- A one-line override of "idle until a human re-engages": *"You report and stop; the parent PM loop continues — you will not be re-engaged directly."*

The subagent then: branches off `origin/main`, builds, runs the gates + a real DEV
round-trip, opens **one PR per unit** with the `## Closes`/`## Retires` body, posts
the `## Unit landed` ready-signal — and stops. The PM loop takes it from `In Review`.

## Produce ≠ adjudicate (preserved, not weakened)

The **producer** is the spawned subagent; the **adjudicator** is the PM loop's
validation — distinct agents, even within one orchestrator session. The PM merges
*mechanically* on a green deterministic gate; it never grades work it authored
(it authored none). High-stakes units add the **independent assurance subagent** as
a third, non-authoring check before merge. This is invariant 3, intact.

## Pausing — the only times the loop yields

- **Consult-exception.** A subagent posts `## Consult-exception: <out-of-scope | better-solution | external-blocker>` on the thread → the PM sets the item `Blocked`, resolves what it can (re-steer / accept / clear the blocker), and resumes. If the exception is genuinely **product/strategic**, the PM surfaces it to the **owner** (tags them, with a recommendation) and leaves it `Blocked` until the owner decides.
- **Owner touchpoint.** The irreversible/strategic class — master-EPIC reframe, PROD push, branch-protection / destructive infra — is never in the loop; the PM prepares it and stops for the owner.

Everything else, the loop runs.

## Hard rules

- **No judgement in the loop** — only deterministic checks (gates, evals, AC). A failed check is a blocker, not a note.
- **No bypass of the irreversible class** — `--admin`, branch-protection, PROD, destructive infra are owner-gated in both modes.
- **The board is the only state** — never carry a private cursor; re-read each tick (resumable, observable).
- **Bounded** — act only on board-actionable items; stop when none remain. No invented work, no self-paced poll.

## Decision checklist (before any merge)

1. Ready-signal conforms to the shape (deployed-env smoke, not local CI)? — Y/N
2. `gates:agents` green on the unit? — Y/N
3. Every pre-committed AC line met, with evidence? — Y/N
4. High-stakes? → independent assurance verdict = PASS? — Y/N (n/a if low-stakes)
5. No false-green / no warn-and-continue on a load-bearing path? — Y/N

Any **N** → do not merge; set `In Progress` with the failing check named.

## Bundled eval

`status: TBD (follow-up)` — the eval that discriminates a *good* autonomous run
(every merge gate-backed, no unreviewed code on `main`, the loop paused correctly
on a seeded consult-exception) from a bad one. "Runner exists" is not "runner is
eval-backed".
