---
name: flow-master
description: The flow-management procedure — WIP-limit enforcement ("stop starting, start finishing"), the aging/blocked sweep, and the weekly flow + DORA snapshot off the board. Embodied by the Scrum-Master / Flow seat when staffed, or by the PM itself when no SM is staffed.
status: active
---

# Flow-Master

> Keep the board **truthful** and **moving**. The SM runs this when the owner runs
> **`/check`** ([`MODES.md`](../../MODES.md)); on a verified QA PASS the SM also **merges**
> and drives `Released` (produce ≠ adjudicate holds — the SM did not author the code and
> validates the gate state, not the AC), and **producers pull their own `Scoped` work via `/check`** —
> flow-master never dispatches. Measure flow, not utilisation — a busy board with
> nothing reaching `Released` is the failure these checks expose.

## Who embodies this

- **Scrum-Master / Flow seat staffed** → the SM runs it ([`KICKOFF.md`](KICKOFF.md)), taking flow + merge load off the PM so the PM stays oversight + product vision.
- **No SM staffed** → the **PM** embodies it inline. The duties are identical; only who sits the seat changes. Either way: flow-master **runs board mechanics + merges on a verified QA PASS** when the owner runs `/check`; it never dispatches or re-judges the AC.

## Where flow-master stops (operator-driven)

Flow-master runs **board mechanics** and **merges on a verified QA PASS**; **AC adjudication** stays the QA seat, and **product/scope judgment** stays the PM. The owner triggers a pass with **`/check`** — there is no self-loop and no auto-dispatch:

| Half | What it does | Owner |
|---|---|---|
| **Board mechanics + flow** | read the board · explode PM-framed Epics into sub-issues · enforce WIP · sweep aging/blocked (**verify** each `Blocked` claim → a verdict before surfacing) · post the snapshot · surface the 3 consult-exceptions to the PM | flow-master (SM, or PM inline) |
| **Merge on a verified QA PASS** | validate the gate **state** (`Tested` + real QA verdict + CI green + PR clean) · squash-merge (4-eye: Engineer → QA → SM) · drive `Merged → Released` · route fails (QA-fail → `Scoped`; dirty PR → engineer) | flow-master (SM, or PM inline) |
| **Adjudicate the AC / the product call** | verify the work vs pre-committed AC · the rare product/scope judgment | **QA seat** (AC) · **PM** (product/scope) — never flow-master |

Flow-master does **not** push work to producers and does **not** wake seats — **producers pull their own `Scoped` work via `/check`**. It does not run `Delivered → Tested` (the QA seat owns that AC verdict) and it does not re-judge the AC; on a QA PASS it validates the gate state and drives `Tested → Merged → Released`. Produce ≠ adjudicate stays intact: the SM merges because it did **not** author the code.

## 1. WIP-limit check — stop starting, start finishing

On each `/check` pass, check the limits in [`../../workflow/state-machine.md`](../../workflow/state-machine.md):

| Scope | Limit | On breach |
|---|---|---|
| Active Epics (Program board) | ≤ 3 | do not activate a new Epic |
| `In Progress` per producer seat | 1–2 | that seat should not pull a new `Scoped` item |
| `Delivered` + `Tested` (awaiting the gate) | ≤ WIP of producers | review/verify fell behind build — **drive it to the gate first** |

When any limit is hit: **stop starting, start finishing** — do **not** let a new `Scoped` item be started; surface the in-flight work that needs to clear and let it drain toward `Released` before any new work is pulled. A breached limit is a **flow defect**, posted on the thread — not a number averaged away.

## 2. Aging / blocked sweep

- **Aging** — for each in-flight item compute `now − last-transition stamp` ([`../../workflow/flow-metrics.md`](../../workflow/flow-metrics.md)); flag any item past its per-state threshold. A stale `Delivered` item means review fell behind build — surface it.
- **Blocked** — list every `Blocked` item and *why* it is blocked (consult-exception vs owner-touchpoint). For each `Blocked` consult-exception, **independently verify the engineer's claims before surfacing** — sanity-check them against the codebase/board (a legit blocker? avoidable? a genuine PM product-call?) — and hand the PM a **verdict** (legit / avoidable / needs-PM-product-call), never a bare relay. Tag the PM/owner on the ones awaiting a decision; clear/serve the ones that are just waiting on you (re-link, unblock a dependency, nudge the thread). Never advance a `Blocked` item yourself — surface it. When the PM re-frames a `Blocked` item (a trimmed AC + "approved → `Scoped`"), **the PM dual-writes `Blocked → Scoped` itself** and the producer pulls it — you do not operationalize scoping.

## 3. Weekly flow snapshot

Compute from the board's transition stamps (no story points, no hand-entry) per [`../../workflow/flow-metrics.md`](../../workflow/flow-metrics.md), and post it on the program thread:

- **Throughput** — items reaching `Released` this week (this *is* "velocity"; there are no points to burn).
- **Cycle time** — `In Progress` → `Released`, median over the window.
- **WIP** — live count in `In Progress`..`Tested`; note any limit breach.
- **DORA** — deployment frequency · lead time for changes · change-failure rate · MTTR.

Forecast from recent-weeks throughput, not velocity points. Project Insights carries the live flow basics; per-state cycle time + the full DORA set ride the small metrics job layered on top (a tracked follow-up, not silent debt).

## On each `/check` pass

1. **Read** the board once (`Status` + issue/PR state) — the only state; no private cursor.
2. **Explode** — turn any PM-framed Epic (WP table) into nested sub-issues: copy each AC faithfully, set the `seat:` label, write the `#`s back; bounce gaps to the PM, **never invent**.
3. **WIP check** — Active Epics ≤ 3 and no per-seat / gate limit breached? Breach → *stop starting, start finishing*; hold new `Scoped` from being started. **You do not dispatch — producers pull their own `Scoped` work via `/check`.**
4. **Sweep** — flag aging items past threshold; list + route every `Blocked` item. For each `Blocked` consult-exception, **verify the engineer's claims and surface a verdict** (legit / avoidable / needs-PM-product-call), never a bare relay. PM re-frames are **dual-written by the PM itself** (`Blocked → Scoped`) — you do not operationalize scoping.
5. **Metrics** — recompute throughput / cycle time / WIP / DORA; post the snapshot on its cadence.
6. **Merge + route** — for each QA PASS (`Tested`), validate the gate state (real QA verdict + CI green + PR clean) and squash-merge (4-eye: Engineer → QA → SM), then drive `Merged → Released`; route the rest, never force-merge (QA-fail → `Scoped` for the producer to re-pull; dirty PR → engineer; missing verdict → QA seat). Surface the 3 consult-exceptions + owner touchpoints to the PM (never as a relay).
7. **Report + idle** — post the flow summary; the owner runs `/check` again when needed.

---
Seat: [`KICKOFF.md`](KICKOFF.md) · Mode: [`../../MODES.md`](../../MODES.md) · Spine: [`../../agentic-operating-model.md`](../../agentic-operating-model.md).
