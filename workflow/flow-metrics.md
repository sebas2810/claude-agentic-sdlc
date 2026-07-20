---
title: Flow & DORA metrics — reading the board's movement
status: active
scope: all-seats
---

# Flow & DORA Metrics

> **Measure flow, not utilisation.** The board's one job is to move work to
> `Released`; these metrics tell you whether it is. A busy board is not a flowing
> board — a seat at 100% utilisation with nothing reaching `Released` is the
> failure these numbers expose.

Every metric here is **derived from the board**, not entered by hand. Each
[`Status`](state-machine.md) transition stamps a timestamp on the item; the
metrics are functions of those stamps. No separate tracker, no story points — the
board is already the system of record, so it is also the measurement surface.

## Flow metrics

| Metric | Definition | Derived from |
|---|---|---|
| **Lead time** | wall-clock from `Backlog` to `Released` — total time a request is in the system | `Released` stamp − `Backlog` (created) stamp |
| **Cycle time** | `In Progress` to `Released` — time once work actually starts | `Released` stamp − first `In Progress` stamp |
| **Throughput** | items reaching `Released` per week — the delivery rate | count of `→ Released` transitions in the window |
| **WIP** | items currently in `In Progress`..`Tested` — work in flight | live count of items in those four states |
| **Flow efficiency** | active time ÷ lead time — share of lead time actually being worked | Σ(time in active states) ÷ lead time, per item |
| **Aging** | time-in-current-state for each in-flight item — staleness | now − last-transition stamp; flag past a per-state threshold |

Throughput and WIP bound cycle time (Little's Law: cycle time ≈ WIP ÷
throughput). Holding WIP at its [limits](state-machine.md) is therefore the most
direct lever on cycle time — the reason the limits are policy, not advice.

## DORA metrics

The four delivery-performance signals, read off the same `Merged`/`Released`
events plus revert/blocker history.

| Metric | Definition | Reads from |
|---|---|---|
| **Deployment frequency** | how often work reaches the target env | count of `→ Released` events per window |
| **Lead time for changes** | code-committed to running-in-prod | `Released` stamp − first-commit stamp on the item's branch |
| **Change-failure rate** | share of releases that need a fix-forward or revert | (reverts + hotfixes) ÷ deployments |
| **MTTR** | mean time to restore after a failed change | mean `Blocked → resolved` duration on incident-tagged items |

Deployment frequency + lead time read off the `Merged`/`Released` timeline;
change-failure rate counts reverts/hotfixes against deployments; MTTR is the mean
duration of `Blocked → (prior)` on items tagged as incidents.

## How the Flow seat / runner uses them

The Flow seat (the [runner](../seats/scrum-master/KICKOFF.md)) reads these each
tick and acts on three of them:

- **WIP-limit enforcement.** WIP over its limit → no seat pulls
  the next `Scoped` item; in-flight work is driven to `Released` first. *Stop
  starting, start finishing* — the limits in [`state-machine.md`](state-machine.md)
  are the trigger.
- **Aging alerts.** An item past its time-in-state threshold is surfaced like any
  other flow defect — a stale `Delivered` item means review fell behind build.
- **Weekly throughput for forecasting.** Forecasts use throughput over recent
  weeks, **not** story-point velocity. This is a Kanban / continuous-flow model;
  "velocity" here just *is* throughput (items/week). There are no points to burn.

A failed gate or a breached limit is a blocker the runner reports, not a number it
averages away. The metrics describe flow; the [gates](state-machine.md) decide
movement.

## Where they surface

- **Project Insights charts** carry the live view out of the box: throughput,
  burn-up, and status-over-time come straight from the board's history.
- **Cycle-time-per-state and the full DORA set** need a small metrics job layered
  on top of Insights (to diff per-state timestamps and join revert/incident
  history). This is named as a **deliberate follow-up**, not silent debt — Insights
  covers the flow basics today; per-state and DORA are a tracked build on top.

See also [`prioritization.md`](prioritization.md) for how WSJF orders within a
state, and [`project-boards.md`](project-boards.md) for which tier each chart
lives on.
