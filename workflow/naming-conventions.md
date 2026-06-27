---
title: Naming Conventions — titles, labels, branches
status: active
scope: all-seats, both modes
---

# Naming Conventions

> **Titles are Conventional-Commits-anchored; level / priority / area are
> LABELS; state lives in the Project `Status` field — never in the title.**
> A title says *what the change is*, a label says *what kind / how urgent /
> where*, and the board says *where it is*. Mixing them is how a board drifts.

## Title format

```
<type>(<area>): <imperative summary>
```

The title is the future commit subject — same prefix, same imperative mood (see
[Conventional Commits](https://www.conventionalcommits.org/)). Examples:

- `feat(parent-app): suggested-action chips`
- `fix(api): tenant scope on calendar effect`

The `<type>` and when each applies:

| Type | Applies to |
|---|---|
| `feat` | a user-facing capability slice |
| `fix` | a defect repair |
| `chore` | hygiene with no behaviour change |
| `ci` | pipeline / workflow changes |
| `docs` | documentation only |
| `refactor` | internal restructure, behaviour preserved |
| `test` | tests / fixtures only |
| `spike` | a time-boxed investigation |
| `perf` | a performance change |

The coarse levels prefix differently:

- **Epic** → `Epic: <capability>` (e.g. `Epic: Calendar sync`)
- **Initiative** → `Initiative: <outcome>` (e.g. `Initiative: Self-serve onboarding`)

## Label taxonomy

Labels are **flat strings** — `level:epic`, `priority:P0`, `area:api` — not
nested categories.

| Label family | Values | Means |
|---|---|---|
| `level:` | `initiative` / `epic` / `story` / `task` | where it sits in [`hierarchy.md`](hierarchy.md) |
| `type:` | `feat` / `fix` / `chore` / `ci` / `docs` / `refactor` / `test` / `spike` / `perf` | mirrors the commit/title type |
| `priority:` | `P0` / `P1` / `P2` / `P3` | urgency — **`P0` = incident / interrupt**, drop-everything |
| `area:` | the codebase domain (e.g. `api`, `parent-app`, `infra`) | where in the code it lands |

`priority:` and the WSJF field drive ordering within a state — see
[`prioritization.md`](prioritization.md).

## What goes where

| Carrier | Holds |
|---|---|
| **Title** | `type` + `area` + imperative summary |
| **Labels** | `level` + `priority` + `area` + `type` |
| **`Status` field** | the [7 states](state-machine.md) (+ Blocked) |
| **Sub-issue link** | the Epic parent ([`hierarchy.md`](hierarchy.md)) |
| **WSJF field** | the priority score for in-state ordering |

| | DO | DON'T |
|---|---|---|
| State | set the `Status` field | put `[In Progress]` in the title |
| Priority | add `priority:P0` | put `P0` in the title |
| Parent | link the sub-issue | name the Epic in the title |
| Type | prefix the title *and* add `type:` | invent a non-Conventional type |

## Branch naming

One branch per Epic ([`hierarchy.md`](hierarchy.md)):

```
feat/<epic#>-<slug>
```

e.g. `feat/142-calendar-sync`. The branch is created when the Epic goes
`Active`; its Stories flow the [7 states](state-machine.md) on that one branch,
each landing as a PR against it.

## Worked examples

| Title | Labels |
|---|---|
| `Epic: Calendar sync` | `level:epic`, `type:feat`, `priority:P1`, `area:api` |
| `feat(api): tenant-scoped calendar read` | `level:story`, `type:feat`, `priority:P1`, `area:api` |
| `fix(parent-app): chip overflow on small screens` | `level:story`, `type:fix`, `priority:P2`, `area:parent-app` |
| `chore(ci): pin pnpm version in workflow` | `level:task`, `type:chore`, `priority:P3`, `area:ci` |
| `fix(api): null tenant bypasses scope (P0)` | `level:story`, `type:fix`, `priority:P0`, `area:api` |

The first is an Epic on the Program board; the rest are Stories/Tasks on the
Execution board, each parented per [`hierarchy.md`](hierarchy.md).
