---
name: engineer-autonomous-runner
description: The engineer seat's operating procedure in autonomous mode (SDLC_MODE=autonomous) when staffed as a standing self-looping seat (a visible pane) rather than a PM-spawned subagent — a board-watching loop that pulls Scoped items in its domain, builds them, reports, and loops, without waiting to be nudged.
status: active
---

# Engineer skill: autonomous-runner (the standing self-looping seat)

> Autonomous mode has **two** ways to staff the producer (see [`MODES.md`](../../MODES.md)):
> the PM **spawns a headless subagent** per `Scoped` item, **or** a **standing seat**
> (a visible pane) runs *this* board-loop itself. Both are "autonomous" — neither
> needs a per-unit human nudge. This file is the standing-seat form.

This is the engineer twin of [`../pm/autonomous-runner.md`](../pm/autonomous-runner.md).
The authority, the build cycle, the ready-signal, the 3 consult-exceptions, and
"never self-merge" are **unchanged** from [`KICKOFF.md`](KICKOFF.md) — the only
difference from manual mode is **who triggers the next unit**: in manual mode a
human re-engages the seat; here the seat re-triggers itself off the board.

## When it runs

`SDLC_MODE=autonomous` **and** this producer is staffed as a standing seat (a pane
you can watch + interject), not as a PM-spawned subagent. The seat boots straight
into the loop — its [seat file](../../onboarding/seat.engineer.template.md) carries
this instruction, injected by the SessionStart hook, so **no one pastes or nudges**.

## The loop (a pure reduction over the board — the seat's, not the PM's)

Each pass — the seat holds **no private cursor**; it re-reads the board every time:

1. **Read** the Execution board: `gh project item-list <exec-board#> --owner <owner> --format json`.
2. **Filter to your Domain** (the seat file's `Domain:` line — e.g. `parent-app + agents`). `Scoped` items outside your domain are another seat's lane — skip them.
3. **If a `Scoped` item in your domain exists and you are not already mid-build:** take it — read the issue + its `## Steer` comment (the pre-committed AC) — and run the [KICKOFF build cycle](KICKOFF.md): branch off `origin/main`, build, gates + a real DEV round-trip, **one PR** with `## Closes #<n>`, post the `## Unit landed` ready-signal. **Never self-merge** — the PM adjudicates + merges.
4. **Report, then loop** back to step 1 for the next `Scoped` item in your domain — no pause between units.
5. **Nothing `Scoped` for you →** post `idle — watching the board` and re-check periodically.

## Stop / pause (same as the PM runner)

- **Drained** — nothing `Scoped` in your domain: idle-watch; do not invent work.
- **Consult-exception** — out-of-scope · materially better solution · external blocker → post `## Consult-exception: <kind>` on the issue and stop on that item; the PM resolves it on the thread.
- The seat **never** crosses the owner-gated class (PROD, branch-protection, destructive infra) and **never** self-merges — those are unchanged from every mode.

## Why this is safe (same invariants as the PM runner)

Produce ≠ adjudicate holds — the seat **produces**, the PM **adjudicates + merges**;
evals are the oracle at the `Delivered → Tested` gate (the Quality seat / the
deterministic evals, not the producer's opinion); the board is the only state
(re-read each pass — resumable, observable). The standing-seat form changes the
*ergonomics* (a visible, interjectable pane) without touching a single gate.

## Bundled eval

`status: TBD (follow-up)` — the eval that discriminates a good standing-seat run
(every unit gate-backed, no self-merge, paused correctly on a seeded
consult-exception, never picked up another domain's item) from a bad one.
