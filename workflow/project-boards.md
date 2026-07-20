---
title: Project board — one project, two views
status: active
scope: all-seats, both modes
---

# Project Board

> **One project per instance, two views.** A single GitHub Project holds the whole
> hierarchy — Initiative ▸ Epic ▸ Story ▸ Task. Two **views** on that one project
> serve the two audiences: a **Board view** (the 7-state execution Kanban) and an
> **EPICS view** (the epic roll-up the old Program project used to be). No second
> project, no mirrored status.

The [state machine](state-machine.md) governs execution (Stories + Tasks). Epics
don't run through the 7 states — they're tracked by **sub-issue progress** (child
Stories `Released` ÷ total), surfaced in the EPICS view. The
[hierarchy](hierarchy.md) — Initiative ▸ Epic ▸ Story ▸ Task — binds it all via
GitHub sub-issues.

## The one project

One project **per instance**, linked to the product repo. It holds **everything** —
epics, stories, tasks. Canonical `Status` (the 7-state Kanban + `Blocked` +
`Cancelled`) plus custom fields (`WSJF`, `Priority`, `Level`, `Seat`, `Target`, `Area`).

## The two views

### Board view — the execution surface
The **7-state Kanban** — `Backlog → Scoped → In Progress → Delivered → Tested →
Merged → Released` (+ `Blocked`) from [`state-machine.md`](state-machine.md),
grouped **Status × Seat** (a swim-lane per producer), filtered to live work with
the canonical Board filter:

```
has:status -status:Backlog,Merged,Released,Cancelled
```

— i.e. require a Status, and hide `Backlog` (not yet steered), `Merged`,
`Released` (done), and `Cancelled` (closed unshipped). What's left is the active
flow: `Scoped → In Progress → Delivered → Tested` (+ `Blocked`). The SM/runner, the engineer seats, and the
Quality seat operate here.

### EPICS view — the strategic roll-up
A **Table** filtered to **`label:level:epic`**, with the **Sub-issues progress**
column — every epic with a live % -done bar. This is the owner + PM surface the old
Program *project* used to be, now just a view on the same project. `Target` gives a
date column; `Priority` / `WSJF` order it.

## How the hierarchy rolls up

GitHub **sub-issues** give the parent chain Initiative ▸ Epic ▸ Story ▸ Task. Because
"every Story under an Epic" is enforced by the [hierarchy](hierarchy.md), the epic
burn-up rolls up **automatically** — the child Stories' `Released` count *is* the
epic's progress in the EPICS view. No manual status mirroring, no second project to
keep in sync.

## Map to the SDLC phases

Frame (owner) and Steer (PM) happen in the **EPICS view**; `Scoped → … → Released`
happens in the **Board view**. Same project, same items — only the lens changes.

```
        Initiative
           │
        ┌──┴──┐
      Epic   Epic        ← EPICS view  (label:level:epic · Sub-issues progress)
        │                   Frame (owner) · Steer (PM)
   ═════╪═════  roll-up: child Stories Released ÷ total
        │
   Story Story Task       ← Board view (Status × Seat)
                            Scoped → In Progress → Delivered → Tested → Merged → Released
```

## Portfolio across instances

For 2–3 instances at once, add an **org-level Portfolio project** that aggregates
issues across the instance repos — the cross-project review lens, above any single
instance's board.

## Built by the scaffolder

The project is provisioned by
[`create-instance.sh`](../onboarding/create-instance.sh) →
[`setup-board.sh`](../onboarding/setup-board.sh) from
[`execution-board.json`](project-templates/execution-board.json) — **one** project,
not two. The script sets the canonical `Status` + custom fields (`WSJF`, `Priority`,
`Level`, `Seat`, `Target`, `Area`) and **links the project to the product repo**
(`gh project link`) so it shows in the repo's Projects tab. The default **Board +
Table** views ship automatically.

> **Two GitHub realities.** (1) The Projects v2 API **cannot create or configure
> views** — so the two views (Board: group `Status × Seat`; EPICS: filter
> `label:level:epic` + Sub-issues-progress column) are applied once from a **golden
> template via `copyProjectV2`**, or set in the UI. (2) Adding an Epic that
> **already has sub-issues** to a project **auto-adds its children** — which is
> exactly what we want now (one project holds the whole tree); no epics-only pruning
> anymore.
