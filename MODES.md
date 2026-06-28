---
title: Operating Modes — manual and autonomous
status: active
scope: all-seats
---

# Operating Modes

The framework runs in one of two modes, chosen per run by `SDLC_MODE` in
`.env.local` (`manual` | `autonomous`; default `manual`). **Both modes run on the
same spine** — the 7 principles, 8 phases, 8 invariants, the role model, the
seats, the skills, the instance overlay, and the [state machine](workflow/state-machine.md).
They differ in exactly **one** transition and **one** principle.

## What is identical (mode-agnostic)

- The spine ([`agentic-operating-model.md`](agentic-operating-model.md)) — phases, roles, **invariants 1–6 and 8**.
- **Invariant 7** ("the shared thread is the bus; the human is never the relay") — *more* true in autonomous mode, never less.
- The seat definitions (PM + Engineer `KICKOFF`s), the Principal skills, the [state machine](workflow/state-machine.md), the gates, the ready-signal, the PR/board ACI.
- Produce ≠ adjudicate · evals are the oracle · canary before irreversible · fixed owner touchpoints. **These bind both modes.**

## What differs (only this)

| | **Manual** (default) | **Autonomous** |
|---|---|---|
| Seat instantiation | a human launches a Claude session per seat (worktree + the SessionStart hook injects the seat) | the **PM-orchestrator spawns the engineer as a subagent** per `Ready` work-item, the *same* KICKOFF + skills + AC injected as its context |
| Who drives the next unit | a human re-engages the seat | the **SM orchestrator** (the board's heartbeat — dispatch/flow/release); the PM frames + adjudicates |
| Merge | PM, on a human-triggered cycle | the **PM**, autonomously, eval-gated — the SM surfaces `Tested`-ready, the PM adjudicates |
| Human's role | owner touchpoints **+ operator (launches/relaunches sessions)** | owner touchpoints **only** |
| Principle 7 stop condition | "finish, report, stop; idle until a human re-engages" | "act only on board-actionable items; **stop when the board is drained or only `Blocked` remains**" |

That is the entire delta. The engineer seat *behaves identically* in both —
"steer-as-trigger, build, report-then-stop" is exactly what an autonomous
subagent does; the only change is who receives the report and drives the next
unit.

### Two ways to staff the producer in autonomous mode

"Autonomous" constrains the *trigger* (no per-unit human nudge), not the
*instantiation*. The producer can be staffed either way — both are equally
autonomous and run the **same** gates:

| Producer form | Is | Trade |
|---|---|---|
| **PM-spawned subagent** (default) | the PM-orchestrator spawns a **headless** engineer subagent per `Scoped` item; it builds, reports, terminates | zero panes to operate; you can't watch or interject mid-build |
| **Standing self-looping seat** | a **visible pane** the human launched that runs its **own** board-loop ([`seats/engineer/autonomous-runner.md`](seats/engineer/autonomous-runner.md)) — pulls `Scoped` items in its domain, builds, reports, loops | watchable + interjectable, but it burns tokens polling and must be launched once per seat |

The distinction is **ergonomic, not architectural** — same board-as-bus, same
produce ≠ adjudicate, same owner-gated class. The standing-seat form exists so a
human can *watch and interject* without reintroducing the manual per-unit nudge:
the seat self-triggers off the board, it is not re-engaged by a human. It is
enabled by `SDLC_MODE=autonomous` in the seat's `.env.local` (the
[seat template](onboarding/seat.engineer.template.md) then injects the board-loop
at boot via the SessionStart hook — nothing to paste).

## Why the autonomous loop is safe (it *strengthens* principle 7, not loosens it)

Principle 7's blunt "no autonomous loop-driven merge" is replaced by the **finer
safeguards already in the spine** — the loop is safe *because* the other
invariants hold:

- **Evals are the oracle (#2).** Every `Tested → Merged` merge is gated by deterministic, falsifiable evals — never the runner's opinion. The independent verification that produces `Tested` is its own state, *before* merge.
- **Produce ≠ adjudicate (#3).** The runner *spawned* the engineer but did not *author* the code; the **independent assurance subagent** (the squad's Quality seat, [`seats/SQUAD.md`](seats/SQUAD.md)) verifies at the `Delivered → Tested` gate and the PM adjudicates at `Tested → Merged`. Dispatching ≠ producing ≠ adjudicating.
- **Canary before irreversible (#4) + owner-only PROD/gated class (#1).** The loop *cannot* perform the irreversible class — `Merged → Released` to PROD, branch-protection, destructive infra still stop for the owner.
- **Bounded, stateless stop.** The loop acts only on `Scoped`/`Delivered`/`Tested`/`Merged` items and **stops** when none remain or only `Blocked` does. No self-paced timer, no invented work.

The runner never makes a judgement call — it **checks** (gates, evals, the AC
checklist). A failed check is a blocker that pauses the loop; a passed check is
safe to advance. All validation is rule- and eval-based, never LLM self-opinion.

## When to use which

- **Manual** — novel, high-stakes, or learning work; anything where the deliberate, per-unit human cadence is the point.
- **Autonomous** — a well-scoped, **`Ready`-stocked** backlog where throughput matters and the AC + evals are crisp enough to gate without a human in the live loop.

The owner is still required at the *fixed, countable* touchpoints — master-EPIC
framing, the 3 consult-exception escalations that are genuinely product/strategic,
and PROD. Autonomous mode automates the loop **between** those triggers; it never
claims to own the irreversible boundary.
