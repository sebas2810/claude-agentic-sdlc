---
title: Operating Model — operator-driven (semi-automated)
status: active
scope: all-seats
---

# Operating Model — operator-driven

The framework is **operator-driven**: the **human is the orchestrator**. There is **no autonomous
self-loop, no board polling, no events, no inbox**. Each seat is an interactive, watchable pane that
stays **idle until the operator engages it**, then **pulls its next workload from the board** with
**`/check`** (role-aware), does that one item, reports, and idles. The operator conducts the cadence:
watch **`/board`** → run **`/check`** in the seat that should advance.

> **History — what was removed and why.** An earlier "autonomous mode" had standing seats self-loop
> the board (a Stop-hook re-engager, an SM that read the board every tick, an inbox push-bus, and a
> planned GitHub-App webhook). With several seats each hitting the Projects-v2 **GraphQL** board it
> **exhausted the shared rate budget**, and once a pane went idle it **could not self-wake** — so the
> loop stalled. That entire autonomous approach (self-loop · inbox · wake-daemon · GitHub App) is
> **removed**. The *logic* it carried is **kept** — the 7-state machine, the seat roles, AC / 4-eye /
> adjudication, the board as system-of-record — now **operator-pulled** instead of autonomously pushed.

## The loop (operator-driven)

1. **`/board`** — the operator's one-shot overview (counts + in-flight items per state).
2. **`/check`** in a seat pane → that seat pulls + does its **next workload**:
   - **producer** (`engineer`) → next `Scoped` for its `seat:` lane → claim → build → `Delivered`
   - **quality-engineer** → next `Delivered` → verify on the deployed env → `Tested` / `In Progress`
   - **pm** → next `Tested` → adjudicate + merge (4-eye); else frame the next `Backlog` → `Scoped`
   - **scrum-master** → board hygiene (explode Epics into sub-issues, WIP, sweep, surface to PM)
3. **One item per `/check`**, report, idle. The operator runs `/check` again for the next.

## What is unchanged (the spine)

- The 7 principles, the phases, the invariants, the role model, the seats, the Principal skills, the
  [state machine](workflow/state-machine.md), the gates, the ready-signal, the PR/board contract.
- **Produce ≠ adjudicate · evals are the oracle · canary before irreversible · the fixed owner touchpoints.**

## Why operator-driven is safe (the safeguards still hold)

- **Produce ≠ adjudicate (#3)** — the producer builds; the independent Quality seat verifies at
  `Delivered → Tested`; the PM adjudicates at `Tested → Merged`. The operator triggering `/check`
  changes *when* a step runs, never *who* runs it.
- **Evals are the oracle (#2)** — `Tested` is gated by falsifiable verification, not opinion.
- **Canary before irreversible (#4) + owner-only PROD/gated class (#1)** — `Merged → Released` to PROD,
  branch-protection, and destructive infra still stop for the owner.
- **No runaway cost** — GraphQL + tokens are spent only on an operator `/check`; idle costs nothing
  (the failure mode that killed the autonomous loop is gone by construction).

The owner is the orchestrator **and** holds the fixed touchpoints — master-EPIC framing, the 3
genuine consult-exception escalations, and PROD.
