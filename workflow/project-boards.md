---
title: Project boards — the Program ⇄ Execution two-tier
status: active
scope: all-seats, both modes
---

# Project Boards

> **Two tiers, two granularities.** A **Program (Master) project** tracks the
> Epic/Initiative level; per-instance **Execution boards** track the Story level.
> They are separate projects with **different `Status` fields and different
> views** — strategy rolls up, execution rolls down, and neither is forced
> through the other's lifecycle.

The [state machine](state-machine.md) governs the Execution tier (Stories +
Tasks). Epics and Initiatives have their own coarser lifecycle on the Program
tier. The [hierarchy](hierarchy.md) — Initiative ▸ Epic ▸ Story ▸ Task — is what
binds the two.

## Program (Master) project

One org-level project; the owner + PM strategic surface. Items are **Epics and
Initiatives** only.

| View | Shows |
|---|---|
| **Program Roadmap** | epics on a timeline (target dates, dependencies) |
| **Epic Board** | the epic lifecycle `Proposed → Steered → Active → Done`; the `Active` set is WIP-limited **≤ 3** ([`state-machine.md`](state-machine.md)) |
| **Portfolio Table** | WSJF, target date, % complete per epic ([`prioritization.md`](prioritization.md)) |
| **Insights** | epic burn-up (child Stories `Released` ÷ total); program velocity = epics completed over time |

The Epic Board's four states are the program-level analogue of the execution
states — coarser, slower, owned by Frame + Steer.

## Execution (Team) board

One project **per instance**. Items are **Stories and Tasks**. This is the working
**7-state Kanban** — `Backlog → Scoped → In Progress → Delivered → Tested → Merged
→ Released` (+ `Blocked`) from [`state-machine.md`](state-machine.md).

| View | Shows |
|---|---|
| **Kanban** | the 7 states, in board order — the runner's primary surface |
| **Roadmap** | stories on a timeline within the active epics |
| **Table** | `Priority`, `WSJF`, `Area`, `Epic` parent for ordering |
| **Insights** | flow metrics — throughput, burn-up, status-over-time ([`flow-metrics.md`](flow-metrics.md)) |

The SM / runner, the engineer seats, and the Quality seat all operate **here**.
The Program tier is read-mostly for them; this board is where work moves.

## How the tiers link

GitHub **sub-issues** give the parent chain Initiative ▸ Epic ▸ Story ▸ Task. A
single issue can live in **multiple projects** at once: the **Epic** is an item on
the Program project *and* its child **Stories** are items on the Execution board.
Because "every Story under an Epic" is enforced by the [hierarchy](hierarchy.md),
the epic burn-up rolls up **automatically** — no manual status mirroring, the
child Stories' `Released` count *is* the epic's progress.

## Map to the SDLC phases

Frame (owner) and Steer (PM) happen on the **Program** tier; `Scoped → … →
Released` happens on the **Execution** tier. Epics roll up from the Stories
beneath them:

```
PROGRAM tier        Initiative
                       │
                    ┌──┴──┐
                  Epic   Epic     ← Frame (owner) · Steer (PM)
                    │              ← Active set WIP ≤ 3
        ════════════╪════════════  roll-up: Stories Released ÷ total
                    │
EXECUTION tier   Story Story Task ← Scoped → In Progress → Delivered →
                                     Tested → Merged → Released
```

A Story closing on the Execution board ticks its Epic's burn-up on the Program
board through the sub-issue link — one event, both tiers.

## Portfolio across instances

For 2–3 instances at once, add an **org-level Portfolio project** that aggregates
issues **across the instance repos** — the cross-project review lens. It sits
above even the Program tier: one place the owner sees every instance's epics and
their roll-up side by side, without opening each repo.

## Built by the scaffolder

Both projects are provisioned by
[`../onboarding/create-instance.sh`](../onboarding/create-instance.sh) →
[`setup-board.sh`](../onboarding/setup-board.sh) from the JSON
[templates](project-templates/) — not hand-built per instance. The script creates
each project, sets the canonical `Status` options + custom fields (`WSJF`,
`Priority`, `Level`, `Area`) the [state machine](state-machine.md) expects, and
**links the project to the product repo** (`gh project link`) so it appears in the
repo's Projects tab and issues/PRs can be added to it from the repo. The default
**Board + Table** views ship automatically.

> **Two GitHub realities to know.** (1) The Projects v2 API **cannot create
> views** — Roadmap + Insights are added once from a golden template via
> `copyProjectV2`, or in the UI. (2) Adding an Epic that **already has sub-issues**
> to a project **auto-adds its children** — so when seeding the Program project
> from an existing repo, **prune to epics-only** afterwards (the Program tier holds
> Epics + Initiatives, never Stories). Seeding fresh standing epics avoids this:
> they have no children yet.
