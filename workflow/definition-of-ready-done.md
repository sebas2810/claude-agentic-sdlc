---
title: Definition of Ready / Definition of Done — the gates between states
status: active
scope: all-seats, both modes
---

# Definition of Ready / Definition of Done

> **A gate is a falsifiable exit condition, not a vibe.** A transition whose gate
> is unmet **does not fire** — the item stays where it is (or goes `Blocked`). No
> advancing on optimism; "it produced output" is never a gate.

These are the per-edge gates of the [SDLC state machine](state-machine.md). The
**Definition of Ready** gates the single entry edge `Backlog → Scoped`; a
**Definition of Done** gates every later transition. Each gate is a concrete,
checkable condition — an eval, a green check, a deployed round-trip, or a met AC
line with evidence — so the runner (and a human) can decide *fire / don't fire*
without judgement.

## Definition of Ready — the gate `Backlog → Scoped`

An item is **Ready** when the steer has made it dispatchable. Every box is
falsifiable; a single unchecked box keeps it in `Backlog`.

- [ ] **One clear outcome.** Scope is a single user-visible result, stated in one
  sentence. Two outcomes ⇒ two items.
- [ ] **Acceptance criteria pre-committed and falsifiable.** Written *before* any
  build, each criterion checkable **both directions** (a pass that could fail, a
  fail that could pass). No tautologies, no "looks right".
- [ ] **Sized.** Fits one branch / one PR. If it doesn't, split it (relative
  sizing — see [`prioritization.md`](prioritization.md), the "sized" check).
- [ ] **Parented to an Epic.** Carries its Epic link per
  [`hierarchy.md`](hierarchy.md). An orphan Story has no steer to dispatch from.
- [ ] **Dependencies known.** Upstream items / data / access are named and
  available, or the item is explicitly `Blocked`, not `Ready`.
- [ ] **No open product/strategic question.** If a decision is owner-class, it is
  resolved at the owner-gate first — a Ready item has no pending fork.

Naming and the steer-comment shape follow
[`naming-conventions.md`](naming-conventions.md).

## Definition of Done — per state

Each later transition has its own DoD. The producer satisfies it; the
**non-author** confirms it once at merge (produce ≠ adjudicate, invariant #3).

| Transition | Exit gate (DoD) | Invariant |
|---|---|---|
| **In Progress → Delivered** | Local gates green (typecheck · test · lint · format) **and** a real DEV round-trip exercised the change on its branch — not a mock, not "compiles". PR open + ready-signal posted. | #5 no false-green |
| **Delivered → Tested** | **Independent** verification returns PASS against the pre-committed AC, run on the **deployed env**, with the **happy path perturbed** (reliability, not one lucky output). The verifier is not the author. | #2 evals are the oracle |
| **Tested → Merged** | Adjudicated **once** by the non-authoring seat at the gate; **every AC line met with evidence** (the command / run-URL / trace that proves it). Squash-merge, Conventional Commit subject. | #3 produce ≠ adjudicate |
| **Merged → Released** | Canary green in the target env (reversible step before any irreversible one); post-deploy check passes. **PROD is owner-gated** — the runner never pushes PROD. | #4 canary before irreversible |

A failed gate on any edge is a **blocker, not a note**: the item routes back to
`In Progress` with the failure recorded, or to `Blocked` — it never slips forward.
The independent-verification edge is the [Quality Engineer
seat](../seats/quality-engineer/KICKOFF.md)'s state; where no Quality seat is
staffed, the deterministic evals are the oracle and the PM confirms them at the
gate.

## Why pre-commit the acceptance criteria

The AC are written at steer time, **before** the work starts, for one reason:
**evals are the oracle** (invariant #2), and an oracle authored after the fact is
the producer grading itself. Pre-committed, both-directions criteria make "done"
a property of the environment, not an opinion — the verifier checks the work
against a contract it could not have bent to fit. Criteria that turn out
untestable are a **consult-exception**, never a quietly relaxed waiver.

## See also

- [`state-machine.md`](state-machine.md) — the 7 states these gates sit between.
- [`prioritization.md`](prioritization.md) — WSJF ordering of the Ready queue; the "sized" check.
- [`hierarchy.md`](hierarchy.md) — Initiative → Epic → Story → Task; the Epic parent.
- [`naming-conventions.md`](naming-conventions.md) — issue / branch / commit shapes.
- [`../seats/quality-engineer/KICKOFF.md`](../seats/quality-engineer/KICKOFF.md) — the independent verifier behind `Delivered → Tested`.
