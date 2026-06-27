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
| Who drives the next unit | a human re-engages the seat | the **PM loop** (a stateless reducer over the board) |
| Merge | PM, on a human-triggered cycle | PM loop, **autonomously, eval-gated** |
| Human's role | owner touchpoints **+ operator (launches/relaunches sessions)** | owner touchpoints **only** |
| Principle 7 stop condition | "finish, report, stop; idle until a human re-engages" | "act only on board-actionable items; **stop when the board is drained or only `Blocked` remains**" |

That is the entire delta. The engineer seat *behaves identically* in both —
"steer-as-trigger, build, report-then-stop" is exactly what an autonomous
subagent does; the only change is who receives the report and drives the next
unit.

## Why the autonomous loop is safe (it *strengthens* principle 7, not loosens it)

Principle 7's blunt "no autonomous loop-driven merge" is replaced by the **finer
safeguards already in the spine** — the loop is safe *because* the other
invariants hold:

- **Evals are the oracle (#2).** Every `In Review → Done` merge is gated by deterministic, falsifiable evals — never the runner's opinion.
- **Produce ≠ adjudicate (#3).** The runner *spawned* the engineer but did not *author* the code; on a high-stakes unit it spawns an **independent assurance subagent** (the squad's Quality seat, [`seats/SQUAD.md`](seats/SQUAD.md)) whose verdict feeds the adjudication. Dispatching ≠ producing.
- **Canary before irreversible (#4) + owner-only PROD/gated class (#1).** The loop *cannot* perform the irreversible class — PROD, branch-protection, destructive infra still stop for the owner.
- **Bounded, stateless stop.** The loop acts only on `Ready`/`In Review`/`Done`/`Testing` items and **stops** when none remain or only `Blocked` does. No self-paced timer, no invented work.

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
