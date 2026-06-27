---
name: flow-master
description: The flow-management procedure — WIP-limit enforcement ("stop starting, start finishing"), the aging/blocked sweep, and the weekly flow + DORA snapshot off the board. Embodied by the Scrum-Master / Flow seat when staffed, or by the PM itself when no SM is staffed.
status: active
---

# Flow-Master

> Keep the board **truthful** and **moving**. This is the dispatch + flow half of
> the [stateless runner](../pm/autonomous-runner.md); the **adjudicate + merge**
> half stays the PM (produce ≠ adjudicate). Measure flow, not utilisation — a busy
> board with nothing reaching `Released` is the failure these checks expose.

## Who embodies this

- **Scrum-Master / Flow seat staffed** → the SM runs it ([`KICKOFF.md`](KICKOFF.md)), taking flow/relay load off the PM so the PM stays Product-Owner + adjudicator.
- **No SM staffed** → the **PM** embodies it inline. The duties are identical; only who sits the seat changes. Either way: flow-master **dispatches and facilitates**, it never adjudicates or merges.

## Relationship to the runner

The [autonomous-runner](../pm/autonomous-runner.md) is one loop with two halves:

| Half | What it does | Owner |
|---|---|---|
| **Dispatch + flow** (this skill) | read board · enforce WIP · spawn the engineer subagent for free-slot `Scoped` items · sweep aging/blocked · post the snapshot | flow-master (SM, or PM inline) |
| **Adjudicate + merge** | verify vs pre-committed AC · squash-merge · deploy/canary · set `Released` | **PM only** — never flow-master |

Flow-master runs the **dispatch** step and stops there. It does **not** touch `Delivered → Tested → Merged → Released`; those are the PM's adjudication path. This is invariant 3 kept intact even when a separate seat runs flow.

## 1. WIP-limit check — stop starting, start finishing

Before dispatching anything, check the limits in [`../../workflow/state-machine.md`](../../workflow/state-machine.md):

| Scope | Limit | On breach |
|---|---|---|
| Active Epics (Program board) | ≤ 3 | do not activate a new Epic |
| `In Progress` per producer seat | 1–2 | do not dispatch a new `Scoped` to that seat |
| `Delivered` + `Tested` (awaiting the gate) | ≤ WIP of producers | review/verify fell behind build — **drive it to the gate first** |

When any limit is hit: **stop starting, start finishing** — do **not** dispatch the next `Scoped` item; surface the in-flight work that needs to clear and let it drain toward `Released` before pulling anything new. A breached limit is a **flow defect**, posted on the thread — not a number averaged away.

## 2. Aging / blocked sweep

- **Aging** — for each in-flight item compute `now − last-transition stamp` ([`../../workflow/flow-metrics.md`](../../workflow/flow-metrics.md)); flag any item past its per-state threshold. A stale `Delivered` item means review fell behind build — surface it.
- **Blocked** — list every `Blocked` item and *why* it is blocked (consult-exception vs owner-touchpoint). Tag the PM/owner on the ones awaiting a decision; clear/serve the ones that are just waiting on you (re-link, unblock a dependency, nudge the thread). Never advance a `Blocked` item yourself — surface it.

## 3. Weekly flow snapshot

Compute from the board's transition stamps (no story points, no hand-entry) per [`../../workflow/flow-metrics.md`](../../workflow/flow-metrics.md), and post it on the program thread:

- **Throughput** — items reaching `Released` this week (this *is* "velocity"; there are no points to burn).
- **Cycle time** — `In Progress` → `Released`, median over the window.
- **WIP** — live count in `In Progress`..`Tested`; note any limit breach.
- **DORA** — deployment frequency · lead time for changes · change-failure rate · MTTR.

Forecast from recent-weeks throughput, not velocity points. Project Insights carries the live flow basics; per-state cycle time + the full DORA set ride the small metrics job layered on top (a tracked follow-up, not silent debt).

## Per-tick checklist

1. **Read** the board (`Status` + issue/PR state) — the only state; no private cursor.
2. **WIP check** — Active Epics ≤ 3 and no per-seat / gate limit breached? Breach → *stop starting, start finishing*; skip dispatch this tick.
3. **Dispatch** — for each free-slot `Scoped` item, spawn the engineer subagent ([`../pm/autonomous-runner.md`](../pm/autonomous-runner.md)); set `In Progress`. **Dispatch only — do not adjudicate or merge.**
4. **Sweep** — flag aging items past threshold; list + route every `Blocked` item.
5. **Metrics** — recompute throughput / cycle time / WIP / DORA; post the snapshot on its cadence.
6. **Report** — post the flow summary; tag the PM/owner on anything needing a decision (the 3 consult-exceptions, never as a relay).
7. **Stop** when the board is drained or only `Blocked` remains — no self-paced poll, no invented work.

---
Seat: [`KICKOFF.md`](KICKOFF.md) · Runner: [`../pm/autonomous-runner.md`](../pm/autonomous-runner.md) · Spine: [`../../agentic-operating-model.md`](../../agentic-operating-model.md).
