---
title: The SDLC State Machine — a stateless workflow over the GitHub board
status: active
scope: all-seats
---

# The SDLC State Machine

> **The board *is* the state. Each seat is a pure function of the board.**
> No hidden state, no in-memory drift — interrupt a seat and it resumes from
> the board; the operator watches the *same* board the seat reads.

This is the foundation the operator-driven model (see
[`MODES.md`](../MODES.md)) runs on. The states live on the **GitHub Project `Status`
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
| 3 | **In Progress** | a seat is building it; a branch exists | the producer pulls it via `/check` | a free WIP slot (see *WIP limits*) |
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

Pull-based, not push-based: a seat pulls its next item (via `/check`) only when it
has a free slot. The limits are policy, surfaced by the scrum-master's board
hygiene and the flow metrics ([`flow-metrics.md`](flow-metrics.md)):

| Scope | Default limit | Why |
|---|---|---|
| **Active Epics** (Program board) | **≤ 3** in `Active` | bounds context-switching at the program level (the "defined amount of active epics") |
| **`In Progress`** per producer seat | **1–2** | one unit of focus; a second only if the first is genuinely blocked on review |
| **`Delivered` + `Tested`** (awaiting the gate) | **≤ WIP of producers** | review/verify is not allowed to fall behind build — if it does, *stop starting, start finishing* |

When a limit is hit the rule is **stop starting, start finishing**: a producer
does not pull a new `Scoped` item via `/check`; the in-flight ones are driven to
`Released` first. Breaching a WIP limit is a flow defect, surfaced like any other.

## Transitions (who drives each — operator-driven)

The operator runs `/check` in the seat that should advance; that seat does the
**one** transition its role owns, then idles.

| From → To | Driver (operator runs `/check` in the seat) | Gate |
|---|---|---|
| Backlog → Scoped | PM steers | **DoR**: scope + pre-committed AC + sized + parented to an Epic |
| Scoped → In Progress | the producer pulls its next `Scoped` → claims + branches | a free WIP slot |
| In Progress → Delivered | producer (PR + ready-signal) | local gates green + a real DEV round-trip |
| Delivered → Tested | quality-engineer pulls its next `Delivered` → verifies on the deployed env (or runs evals) | **evals (oracle) + AC, deployed-env, perturbed** |
| Tested → Merged | PM pulls its next `Tested` → adjudicates + merges | **produce ≠ adjudicate**, once, at the gate |
| Delivered/Tested → In Progress | PM/QE requests changes (verification FAIL → back to `In Progress`) | a failed gate is a blocker, not a note |
| Merged → Released | PM deploys (staging); PROD = owner | **canary before irreversible**; PROD owner-gated |
| any → Blocked | the seat surfaces (`## Consult-exception`) | the 3 consult-exceptions / owner-touchpoints |
| Blocked → (prior) | PM / owner resolves on the thread | — |

**Every transition is operator-paced via `/check`, and every gate is the same
regardless of when the operator triggers it.** The operator's pacing changes
*when* a step runs, never *who* runs it or *whether* its gate holds — so a safety
gate can never be skipped.

## The board as the reducer (one tick per `/check`)

No seat holds **state between ticks**. Each `/check` reads the board and acts on
what the state dictates — **one** pure-reduction tick, operator-triggered. There
is no self-running loop and no poll; the operator re-runs `/check` to take the
next tick.

```
on /check in <seat>:
  board = read(Project Status + issue/PR state)        # the ONLY source of truth
  if active_epics > 3 or wip_breached: finish_in_flight_first
  item = next actionable item for <seat>'s role         # most-advanced state first
  case item.status:
    Scoped     (producer) -> if free_wip: claim(item); branch; build; set In Progress -> Delivered
    Delivered  (quality)  -> v = verify(item)            # independent: Quality seat / evals, deployed-env
                             v.pass ? set Tested : (comment; set In Progress)
    Tested     (pm)       -> a = adjudicate(item)        # produce != adjudicate, once
                             a.pass ? (merge; set Merged) : (comment; set In Progress)
    Merged     (pm)       -> deploy(item); canary; set Released   # PROD is owner-gated, never automated
    Blocked               -> surface to PM/owner          # do NOT advance
  report; idle        # one item per /check — the operator re-runs /check for the next
```

Each `/check` takes the most-advanced actionable item first, so the system
**finishes work before starting new work** (WIP discipline falls out of the
ordering).

What treating the board as the only state buys:

- **Resumable.** Crash or interrupt mid-`/check` → the next `/check` picks up exactly where the board is. There is nothing to "recover".
- **Observable.** The operator watches the same board each `/check` reads — no opaque internal cursor.
- **Idempotent.** Re-reading a board in a stable state produces no spurious action.
- **Single mode.** There is no manual/autonomous duality — operator-driven is the one mode; every transition + gate is the same path no matter when the operator runs `/check`, so a safety gate can never be skipped.

## The stop condition (principle 7)

Each `/check` has an **explicit stop**: the seat does **one** actionable item,
reports, and **idles**. It does not poll on a self-paced timer, does not loop the
board, and does not invent work — it acts only on what the board says is
actionable for its role. When no actionable item remains — the board is drained,
or every remaining item is `Blocked` (awaiting a consult-exception or
owner-touchpoint) — `/check` reports "nothing to do" and idles. This is "finish,
report, stop" made literal: nothing advances on its own; the operator re-engages
a seat with `/check` to take the next step.

## GitHub mapping (the concrete board)

- The states are the **`Status` single-select** options, in the order above.
- An item **carries its Epic parent** (sub-issue link / `Epic` field) — every
  Story is parented per [`hierarchy.md`](hierarchy.md); an orphan Story has no
  steer to build from.
- `Priority` (P0–P3), `WSJF` (number), and `Area` fields drive ordering within a
  state — see [`prioritization.md`](prioritization.md).
- The board is provisioned from the **Execution-board template** by the
  scaffolder ([`../onboarding/create-instance.sh`](../onboarding/create-instance.sh));
  the two-tier Program ⇄ Execution layout is [`project-boards.md`](project-boards.md).

## Why stateless is the invariant

A workflow whose state lives anywhere but the board can drift from it — the
classic "a seat thinks it shipped but `main` says otherwise". By making the
board the single source of truth and each seat a pure function of it at every
`/check`, the system has **one** state, legible to human and machine alike.
Resumability, observability, and the audit trail are then free, not bolted on.
