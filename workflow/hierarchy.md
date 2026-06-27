---
title: The Work Hierarchy — Initiative → Epic → Story → Task
status: active
scope: all-seats, both modes
---

# The Work Hierarchy

> **Every Story is nested under an Epic, and every Epic under an Initiative.**
> An orphan Story has no steer to dispatch from — the Epic *is* the steer. No
> Epic, no acceptance-criteria context, no roadmap parent, nothing for
> [`state-machine.md`](state-machine.md) to pull. The runner cannot dispatch
> what it cannot trace.

Four levels, two boards. The coarse levels (Initiative, Epic) set direction and
live on the **Program board**; the execution levels (Story, Task) flow the
7 states and live on the **Execution board**
([`project-boards.md`](project-boards.md)). The connective tissue is the
parent link.

## The four levels

| Level | Is | Horizon / framing | Lives on | Lifecycle |
|---|---|---|---|---|
| **Initiative** | a strategic outcome | quarters; owner-framed | Program board | coarse Program lifecycle |
| **Epic** | a shippable capability; **branch-per-Epic**; the **unit of steering**; WIP-limited active set **≤ 3** | weeks; one branch | Program board | coarse (`Proposed → Active → Done`) |
| **Story** | one outcome; **fits a PR**; flows the 7 states | days; one PR | Execution board | the [7 states](state-machine.md) |
| **Task** | a sub-unit of a Story, when a Story needs decomposition | a Story-slice | Execution board | the [7 states](state-machine.md) |

The Epic is where steering happens: scope, pre-committed acceptance-criteria
context, and the branch all attach to it. A Story inherits that steer from its
Epic parent — which is why it cannot exist without one.

## The nesting rule

A **Story REQUIRES an Epic parent.** No exceptions to *needing a parent* — only
to *which* parent. Reactive and unplanned work still gets one:

| Work | Conventional type | Parent |
|---|---|---|
| a feature slice | `feat` | the feature Epic it belongs to |
| a bug | `fix` | the **feature Epic it broke** (preferred — traceability) *or* `Epic: Operations & Incidents` if cross-cutting |
| hygiene / pipeline | `chore` / `ci` | `Epic: Maintenance & Tech Debt` |
| investigation | `spike` | `Epic: Discovery & Spikes` (optional) *or* the Epic it informs |
| a P0 incident | `fix` (P0) | `Epic: Operations & Incidents` |

The reactive parents are a small fixed set of **standing epics**, always open so
nothing is ever orphaned:

- `Epic: Maintenance & Tech Debt` — `chore` / `ci` / `refactor` hygiene.
- `Epic: Operations & Incidents` — P0s and cross-cutting `fix` work.
- `Epic: Quality & Evals` — eval and assurance work that spans features.
- `Epic: Discovery & Spikes` *(optional)* — `spike` investigations.

> A bug attaches to the feature Epic it broke when that Epic is known — the
> traceable default. Only when the defect is genuinely cross-cutting does it go
> to Operations & Incidents.

## Why no orphans

- **Steer / AC context.** The Epic carries the steer; a Story without one has no
  committed acceptance criteria to be verified against ([`state-machine.md`](state-machine.md)).
- **Roadmap traceability.** Initiative → Epic → Story rolls up cleanly — every
  shipped Story traces to a strategic outcome.
- **WIP stays meaningful.** The **≤ 3 active Epics** limit only bounds
  context-switching if every Story sits under an Epic; orphans leak past it.
- **Reporting rolls up.** Progress and throughput aggregate by Epic, then by
  Initiative — orphans don't appear in any roll-up.

## How it maps to GitHub

- **Sub-issues give the real parent/child links** — Epic → Story → Task is a
  native sub-issue tree, not a label convention.
- **One issue, multiple projects.** An Epic sits on the **Program** board while
  its Stories sit on the **Execution** board ([`project-boards.md`](project-boards.md));
  the same issue can be a member of both.
- **Epic progress = children's `Released` count** — an Epic is `Done` when all
  its child Stories reach `Released`. No separate progress field to drift.

The title, label, and priority conventions that tag each level are
[`naming-conventions.md`](naming-conventions.md); ordering within a state is
[`prioritization.md`](prioritization.md).
