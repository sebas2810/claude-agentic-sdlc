---
title: Operating Model — operator-driven (semi-automated)
status: active
scope: all-seats
---

# Operating Model — operator-driven

The framework is **operator-driven**: the **human is the orchestrator**. There is **no autonomous
self-loop, no board polling, no events, no inbox**. Each seat is an interactive, watchable pane that
stays **idle until the operator engages it**, then on **`/check`** (role-aware) **drains its queue** —
each discovery is one cheap `gh issue list --search` on the `status:*` **label index** (never the
expensive 300-item board read), re-run per item to drain: take an eligible item, handle it, report,
re-query for the next, until none remain for its role, then idle. The drain is bounded by the
work that exists now and every unit still passes its normal gate; re-querying per item is cheap REST
(no snapshot semantics), and once the queue is empty the seat does **not**
keep re-querying (no idle-poll, no self-loop). The operator conducts the cadence:
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
   - **producer** (`engineer`) → next `Scoped` for its `seat:` lane → claim → build → `Delivered`. **Block protocol:** on a genuine consult-exception (AC unmeetable as written · a real product fork · out-of-scope creep) it does **not** build — it posts the **full context to the GitHub issue** (file-cited findings · options · recommendation), sets `Blocked` (+ assigns itself), and stops; the issue comment is the board item's context.
   - **quality-engineer** → next `Delivered` → verify on the deployed env → PASS `Tested` / FAIL `Scoped` (+ comments — the engineer re-pulls it)
   - **scrum-master** → next `Tested` → validate (real QA verdict, CI green, PR clean) + merge (squash) → drive `Merged → Released`; plus board hygiene (explode Epics into sub-issues, WIP, sweep). On `Blocked`: for each `Blocked` consult-exception **verify the claims, then surface to the PM with a verdict** (legit / avoidable / needs-PM-call), never a bare relay.
   - **pm** → oversight + product: frame the next `Backlog` → `Scoped` with its pre-committed AC, re-frame a `Blocked` consult-exception the SM surfaced, own the roadmap + owner touchpoints, resolve the rare product/scope judgment the QA seat surfaces (not in the routine merge path). The PM **dual-writes its own scoping transitions** — `Backlog → Scoped` (framing) and `Blocked → Scoped` (re-framing): set the `status:*` label **and** the board `Status` field together; producers then pull `status:scoped` directly. The PM **still never merges** — the SM is the merge authority.
3. **Drain your queue per `/check`, then idle.** Don't stop after one item — after each item (report
   posted, status flipped) immediately **re-run your role's cheap discovery query** (one
   `gh issue list --search` on the `status:*` label index) and handle the next eligible item
   (item → report → next), until none remain for your role; then report `queue clear — idle` and
   **stop**. The drain is **operator-initiated** and **bounded by the work that exists now**, every
   unit still passes its normal gate (per-unit 4-eye intact — not autonomous EPIC-draining), and
   discovery never touches the expensive 300-item board read — re-querying per item is cheap REST,
   so no snapshot is needed and the rate-limit fix stays intact.
   Once empty, do **not** keep re-querying (no idle-poll, no self-loop); the operator
   re-engages you when new work lands.

## What is unchanged (the spine)

- The 7 principles, the phases, the invariants, the role model, the seats, the Principal skills, the
  [state machine](workflow/state-machine.md), the gates, the ready-signal, the PR/board contract.
- **Produce ≠ adjudicate · evals are the oracle · canary before irreversible · the fixed owner touchpoints.**

## Why operator-driven is safe (the safeguards still hold)

- **Produce ≠ adjudicate (#3)** — now a three-way separation: the producer (Engineer) builds; the
  independent Quality seat verifies at `Delivered → Tested` (FAIL sends it back `Delivered → Scoped`
  for the engineer to re-pull); the SM — who didn't author — validates and merges (squash) at
  `Tested → Merged` and drives `Merged → Released`. The PM frames + adjudicates product/scope but is
  out of the routine merge path. The operator triggering `/check` changes *when* a step runs, never *who* runs it.
- **Role boundary — the PM scopes its own work; the SM is the merge authority.** The **PM dual-writes its
  own scoping transitions** — for `Backlog → Scoped` (framing) and `Blocked → Scoped` (re-framing) it sets
  the `status:*` label **and** the board `Status` field together (the v1.4 write-both rule applies to every
  seat, including the PM); producers then pull `status:scoped` directly. (Every seat flips its *own*
  transitions — engineer claims `Scoped→In Progress`, QA sets `Tested`/`Scoped`, the PM scopes
  `Backlog`/`Blocked → Scoped`, the SM merges → `Merged`/`Released`.) The **PM still never merges** — that
  stays with the independent SM (produce ≠ adjudicate). Two supporting protocols: a producer that hits a
  consult-exception posts the **full context to the issue** and sets `Blocked` rather than building; and the
  **SM verifies each `Blocked` consult-exception's claims before surfacing** to the PM with a verdict
  (legit / avoidable / needs-PM-call), not a bare relay.
- **Evals are the oracle (#2)** — `Tested` is gated by falsifiable QA verification, not opinion; that
  QA verification is the gate the SM merges on.
- **Canary before irreversible (#4) + owner-only PROD/gated class (#1)** — `Merged → Released` to PROD,
  branch-protection, and destructive infra still stop for the owner.
- **No runaway cost** — GraphQL + tokens are spent only on an operator `/check`; idle costs nothing
  (the failure mode that killed the autonomous loop is gone by construction).

The owner is the orchestrator **and** holds the fixed touchpoints — master-EPIC framing, the 3
genuine consult-exception escalations, and PROD.
