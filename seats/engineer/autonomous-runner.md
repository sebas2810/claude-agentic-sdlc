---
name: engineer-autonomous-runner
description: The engineer seat's operating procedure in autonomous mode (SDLC_MODE=autonomous) when staffed as a standing, event-woken seat (a visible pane) rather than a PM-spawned subagent — it WAITS for a dispatch event (the SM or a board/PR webhook) carrying one Scoped item, builds it, reports, and returns to idle. It does NOT read the board itself and does NOT run a self-paced poll loop.
status: active
---

# Engineer skill: autonomous-runner (the standing, event-woken seat)

> Autonomous mode has **two** ways to staff the producer (see [`MODES.md`](../../MODES.md)):
> the PM **spawns a headless subagent** per `Scoped` item, **or** a **standing seat**
> (a visible pane) is **woken by an event** for one item. Both are "autonomous" — neither
> needs a per-unit human nudge. This file is the standing-seat form. It is **woken**, it
> does **not** poll the board — only the SM reads the board
> ([event-driven-orchestration](../../feedback/architecture/event-driven-orchestration.md)).

This is the engineer twin of [`../pm/autonomous-runner.md`](../pm/autonomous-runner.md).
The authority, the build cycle, the ready-signal, the 3 consult-exceptions, and
"never self-merge" are **unchanged** from [`KICKOFF.md`](KICKOFF.md). The only
difference from manual mode is **who triggers the next unit**: in manual mode a
human re-engages the seat; here the **SM dispatch event** does — *not* a human, and
*not* the seat polling the board for itself.

## When it runs

`SDLC_MODE=autonomous` **and** this producer is staffed as a standing seat (a pane
you can watch + interject), not as a PM-spawned subagent. The seat boots and then
**idles at ~zero cost** until woken — its [seat file](../../onboarding/seat.engineer.template.md)
carries this instruction, injected by the SessionStart hook, so **no one pastes or nudges**.

## The model (woken per item — no board read, no poll)

The seat holds **no board cursor and never queries the Projects board** (that is the
SM's single read). It is **woken** with the one item to build:

1. **Idle until woken.** Wait for a dispatch event — the **SM** (`SendMessage`) or a
   board/PR webhook — carrying **one** `Scoped` item in your domain: the issue `#`, its
   `## Steer` comment (the pre-committed AC), and the `seat:` route. No event → stay idle;
   **do not** read the board, **do not** set a timer to re-check.
2. **Build the one item.** Run the [KICKOFF build cycle](KICKOFF.md): branch off
   `origin/main`, build, gates + a real DEV round-trip, **one PR** with `## Closes #<n>`,
   post the `## Unit landed` ready-signal. **Never self-merge** — the PM adjudicates + merges.
3. **Report, then return to idle.** Post the ready-signal and go back to step 1. **Do not**
   loop back to read the board for the next unit — the SM reads the board and **wakes you
   again** when the next domain item is `Scoped`. One wake = one item.

> If a seat finds itself about to run `gh project item-list` to look for its own work,
> that is the **rejected N-way poll** — stop and wait to be woken instead.

## Stop / pause (same as the PM runner)

- **Idle** — no dispatch event: wait at ~zero cost; do not invent work, do not poll the board.
- **Consult-exception** — out-of-scope · materially better solution · external blocker → post
  `## Consult-exception: <kind>` on the issue and stop on that item; the PM resolves it on the
  thread (the SM surfaces it).
- The seat **never** crosses the owner-gated class (PROD, branch-protection, destructive infra)
  and **never** self-merges — those are unchanged from every mode.

## Why this is safe (same invariants as the PM runner)

Produce ≠ adjudicate holds — the seat **produces**, the PM **adjudicates + merges**;
evals are the oracle at the `Delivered → Tested` gate (the Quality seat / the
deterministic evals, not the producer's opinion); the board is the only state, read by
the **SM** and pushed to the seat (resumable, observable). The event-woken form changes
the *ergonomics* (a visible, interjectable pane) and removes the per-seat poll — without
touching a single gate.

## Bundled eval

`status: TBD (follow-up)` — the eval that discriminates a good standing-seat run
(every unit gate-backed, no self-merge, paused correctly on a seeded
consult-exception, never picked up another domain's item, **never polled the board
itself**) from a bad one.
