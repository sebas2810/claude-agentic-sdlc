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
[`MODES.md`](../MODES.md)) run on. The states live on the **GitHub Project Status
field**; the transitions are the workflow. It makes invariant 7 ("the shared
thread is the bus") literal — the board is the bus, and no seat holds a private
copy of where the work is.

## States (the Project `Status` field)

| State | Means | Entry signal |
|---|---|---|
| **Backlog** | exists, not yet steered (no committed AC) | issue created |
| **Ready** | PM-steered — scope + **pre-committed acceptance criteria** | the steer comment is posted |
| **In Progress** | a seat/subagent is building it; a branch exists | dispatch |
| **In Review** | a PR is open + the ready-signal posted | `gh pr ready` + `## Unit landed` |
| **Done** | merged to `main` | PR merged |
| **Testing** | deployed + under eval / e2e verification | deploy complete |
| **Completed** | verified against AC; issue closed | evals green |
| **Blocked** | a consult-exception or owner-touchpoint is pending | `## Consult-exception` / owner-tag |

## Transitions (who drives each — mode-aware *only* on dispatch)

| From → To | Driver — **manual** | Driver — **autonomous** | Gate |
|---|---|---|---|
| Backlog → Ready | PM steer | PM steer | scope + AC pre-committed |
| Ready → In Progress | human launches the engineer seat | runner **spawns the engineer subagent** | — |
| In Progress → In Review | engineer (PR + ready-signal) | subagent (PR + ready-signal) | local gates green + a real DEV round-trip |
| In Review → Done | PM reviews + merges | runner **adjudicates + merges** | **evals (oracle) + AC + produce ≠ adjudicate** |
| In Review → In Progress | PM requests changes | runner posts the failure → re-dispatch | a failed gate is a blocker, not a note |
| Done → Testing | PM deploys | runner deploys | — |
| Testing → Completed | PM verifies | runner verifies (evals / e2e) | **canary before irreversible** |
| any → Blocked | engineer surfaces | subagent surfaces (`## Consult-exception`) | the 3 consult-exceptions / owner-touchpoints |
| Blocked → (prior) | PM / owner resolves on the thread | same | — |

**Everything except `Ready → In Progress` is identical across modes.** That single
difference is the whole of "manual vs autonomous" — so the two modes cannot
diverge on any safety gate.

## The stateless runner (the reducer over the board)

The runner holds **no state**. Each tick it reads the board and acts on what the
state dictates — a pure reduction:

```
loop:
  board = read(Project Status + issue/PR state)        # the ONLY source of truth
  acted = false
  for item in board:
    case item.status:
      Ready      -> dispatch(item); set In Progress         # spawn engineer subagent (autonomous)
      In Review  -> v = adjudicate(item)                    # evals + AC; produce != adjudicate
                    v.pass ? (merge; set Done) : (comment; set In Progress)
      Done       -> deploy(item); set Testing
      Testing    -> verify(item); set Completed             # evals/e2e; canary before irreversible
      Blocked    -> surface to PM/owner; skip               # do NOT advance
    acted |= item_changed
  if not acted: STOP        # explicit stop — the board is drained or only Blocked remains
```

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

## Why stateless is the invariant

A workflow whose state lives anywhere but the board can drift from it — the
classic "the runner thinks it shipped but `main` says otherwise". By making the
board the single source of truth and the runner a pure function of it, the system
has **one** state, legible to human and machine alike. Resumability,
observability, and the audit trail are then free, not bolted on.
