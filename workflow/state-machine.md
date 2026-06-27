---
title: The SDLC State Machine — a stateless workflow over the GitHub board
status: active
scope: all-seats, both modes
---

# The SDLC State Machine

> **The board *is* the state. The runner is a pure function of the board.**
> No hidden state, no in-memory drift — interrupt the runner and it resumes from
> the board; the owner watches the *same* board the runner reads.

This is the foundation both operating modes (manual + autonomous, see
[`MODES.md`](../MODES.md)) run on. The states live on the **GitHub Project `Status`
field**; the transitions are the workflow. It makes invariant 7 ("the shared
thread is the bus") literal — the board is the bus, and no seat holds a private
copy of where the work is.

The state machine governs **Stories and Tasks** (the execution items). Epics and
Initiatives have their own coarser lifecycle on the **Program board**
([`project-boards.md`](project-boards.md)); the hierarchy that connects them is
[`hierarchy.md`](hierarchy.md).

## The 7 states (+ Blocked)

The canonical `Status` options, in board order. The entry gate of each is its
slice of the [Definition of Ready / Definition of Done](definition-of-ready-done.md) —
DoR gates the entry to `Scoped`, a per-state DoD gates every later transition.

| # | State | Means | Entry signal | Gate to enter (DoD of the prior step) |
|---|---|---|---|---|
| 1 | **Backlog** | exists, not yet steered (no committed AC) | issue created | — (DoR not yet met) |
| 2 | **Scoped** | PM-steered — scope + **pre-committed acceptance criteria**; **DoR met** | the steer comment is posted | **Definition of Ready** (scope, AC, sized, parented to an Epic) |
| 3 | **In Progress** | a seat/subagent is building it; a branch exists | dispatch | a free WIP slot (see *WIP limits*) |
| 4 | **Delivered** | a PR is open + the ready-signal posted; awaiting verification | `gh pr ready` + `## Unit landed` | local gates green + a real DEV round-trip |
| 5 | **Tested** | **independent** verification PASS against the pre-committed AC (Quality seat / evals) — the assurance gate | the verification report posts PASS | **evals are the oracle**, deployed-env, perturbed happy path |
| 6 | **Merged** | adjudicated + squash-merged to `main` | PR merged | **produce ≠ adjudicate**, once, by the non-author at the gate |
| 7 | **Released** | deployed to the target env + verified there (canary → promote); issue closed | deploy + post-deploy check green | **canary before irreversible**; PROD is owner-gated |
| — | **Blocked** | a consult-exception or owner-touchpoint is pending | `## Consult-exception` / owner-tag | the 3 consult-exceptions / the owner-gated class |

Two deliberate properties of this ordering:

- **`Tested` precedes `Merged`.** The independent check runs on the *delivered PR*
  (a real DEV round-trip on its branch), so a defect is caught **before** it
  reaches `main` — not after. This is the Quality Engineer seat's state
  ([`../seats/quality-engineer/KICKOFF.md`](../seats/quality-engineer/KICKOFF.md));
  where no Quality seat is staffed, the deterministic evals are the oracle and the
  PM confirms them at the gate.
- **`Released` is its own state, owner-gated at PROD.** Merging to `main` is the
  PM's routine authority; pushing the irreversible release is the owner's. Keeping
  them as two states keeps that boundary legible on the board.

## Definition of Ready / Done (the gates between states)

Every transition has a **gate** — a falsifiable exit condition (DoD) of the step
it leaves. The full checklists live in
[`definition-of-ready-done.md`](definition-of-ready-done.md); the load-bearing
ones are named in the table above. A transition with an unmet gate **does not
fire** — the item stays where it is (or goes `Blocked`), never advances on
optimism. "It produced output" is never a gate; a gate is an eval, a green check,
or a met AC line with evidence.

## WIP limits (flow, not utilisation)

Pull-based, not push-based: a seat pulls the next item only when it has a free
slot. The limits are policy, enforced by the Flow seat / runner
([`flow-metrics.md`](flow-metrics.md)):

| Scope | Default limit | Why |
|---|---|---|
| **Active Epics** (Program board) | **≤ 3** in `Active` | bounds context-switching at the program level (the "defined amount of active epics") |
| **`In Progress`** per producer seat | **1–2** | one unit of focus; a second only if the first is genuinely blocked on review |
| **`Delivered` + `Tested`** (awaiting the gate) | **≤ WIP of producers** | review/verify is not allowed to fall behind build — if it does, *stop starting, start finishing* |

When a limit is hit the rule is **stop starting, start finishing**: the runner
does not dispatch a new `Scoped` item; it drives the in-flight ones to `Released`
first. Breaching a WIP limit is a flow defect, surfaced like any other.

## Transitions (who drives each — mode-aware *only* on dispatch)

| From → To | Driver — **manual** | Driver — **autonomous** | Gate |
|---|---|---|---|
| Backlog → Scoped | PM steer | PM steer | **DoR**: scope + pre-committed AC + sized + parented to an Epic |
| Scoped → In Progress | human launches the engineer seat | runner **spawns the engineer subagent** | a free WIP slot |
| In Progress → Delivered | engineer (PR + ready-signal) | subagent (PR + ready-signal) | local gates green + a real DEV round-trip |
| Delivered → Tested | Quality seat verifies (or evals) | runner spawns the **assurance subagent** (or runs evals) | **evals (oracle) + AC, deployed-env, perturbed** |
| Tested → Merged | PM adjudicates + merges | runner **adjudicates + merges** | **produce ≠ adjudicate**, once, at the gate |
| Delivered/Tested → In Progress | PM/QE requests changes | runner posts the failure → re-dispatch | a failed gate is a blocker, not a note |
| Merged → Released | PM deploys; PROD = owner | runner deploys (staging); PROD = owner | **canary before irreversible**; PROD owner-gated |
| any → Blocked | engineer/QE surfaces | subagent surfaces (`## Consult-exception`) | the 3 consult-exceptions / owner-touchpoints |
| Blocked → (prior) | PM / owner resolves on the thread | same | — |

**Everything except `Scoped → In Progress` is identical across modes.** That
single difference is the whole of "manual vs autonomous" — so the two modes
cannot diverge on any safety gate.

## The stateless runner (the reducer over the board)

The runner holds **no state**. Each tick it reads the board and acts on what the
state dictates — a pure reduction:

```
loop:
  board = read(Project Status + issue/PR state)        # the ONLY source of truth
  if active_epics > 3 or wip_breached: finish_in_flight_first
  acted = false
  for item in board (most-advanced state first):       # drain, don't start
    case item.status:
      Scoped      -> if free_wip: dispatch(item); set In Progress   # spawn engineer subagent (autonomous)
      Delivered   -> v = verify(item)                  # independent: Quality seat / evals, deployed-env
                     v.pass ? set Tested : (comment; set In Progress)
      Tested      -> a = adjudicate(item)              # produce != adjudicate, once
                     a.pass ? (merge; set Merged) : (comment; set In Progress)
      Merged      -> deploy(item); canary; set Released # PROD is owner-gated, never in the loop
      Blocked     -> surface to PM/owner; skip          # do NOT advance
    acted |= item_changed
  if not acted: STOP        # explicit stop — the board is drained or only Blocked remains
```

Process most-advanced-state-first so the loop **finishes work before starting
new work** (WIP discipline falls out of the iteration order).

What statelessness buys:

- **Resumable.** Crash or interrupt mid-loop → the next read picks up exactly where the board is. There is nothing to "recover".
- **Observable.** The owner watches the same board the runner reads — no opaque internal cursor.
- **Idempotent.** Re-reading a board in a stable state produces no spurious action.
- **Mode-shared.** Only `dispatch` differs by mode; every other transition + gate is the same code path, so a safety gate can never apply in one mode and not the other.

## The stop condition (principle 7, both modes)

The loop's **explicit stop condition** is: *no actionable item remains* — the
board is drained, or every remaining item is `Blocked` (awaiting a
consult-exception or owner-touchpoint). This is the autonomous-mode form of
"finish, report, stop": the runner does not poll on a self-paced timer and does
not invent work — it acts only on what the board says is actionable, and stops
when nothing is. (Manual mode's stop condition is the same shape: report, stop,
idle until a human re-engages.)

## GitHub mapping (the concrete board)

- The states are the **`Status` single-select** options, in the order above.
- An item **carries its Epic parent** (sub-issue link / `Epic` field) — every
  Story is parented per [`hierarchy.md`](hierarchy.md); an orphan Story has no
  steer to dispatch from.
- `Priority` (P0–P3), `WSJF` (number), and `Area` fields drive ordering within a
  state — see [`prioritization.md`](prioritization.md).
- The board is provisioned from the **Execution-board template** by the
  scaffolder ([`../onboarding/create-instance.sh`](../onboarding/create-instance.sh));
  the two-tier Program ⇄ Execution layout is [`project-boards.md`](project-boards.md).

## Why stateless is the invariant

A workflow whose state lives anywhere but the board can drift from it — the
classic "the runner thinks it shipped but `main` says otherwise". By making the
board the single source of truth and the runner a pure function of it, the system
has **one** state, legible to human and machine alike. Resumability,
observability, and the audit trail are then free, not bolted on.
