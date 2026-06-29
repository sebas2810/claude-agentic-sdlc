---
title: Operating Model — operator-driven (semi-automated)
status: active
scope: all-seats
---

# Operating Model — operator-driven

The framework is **operator-driven**: the **human is the orchestrator**. There is **no autonomous
self-loop, no board polling, no events, no inbox**. Each seat is an interactive, watchable pane that
stays **idle until the operator engages it**, then on **`/check`** (role-aware) **drains its queue** —
it reads the board **once**, then handles every eligible item in that one snapshot (item → report →
next-from-the-same-snapshot) until none remain for its role, then idles. The drain is bounded by the
work that exists now and every unit still passes its normal gate; it costs **one** board read per
`/check` (only cheap single-item mutations after), and once the queue is empty the seat does **not**
keep re-reading the board (no idle-poll, no self-loop). The operator conducts the cadence:
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
   - **scrum-master** → next `Tested` → validate (real QA verdict, CI green, PR clean) + merge (squash) → drive `Merged → Released`; plus board hygiene (explode Epics into sub-issues, WIP, sweep). On `Blocked`: **operationalize PM re-frames** — flip `Blocked→Scoped` for any item the PM re-framed/approved — and for each `Blocked` consult-exception **verify the claims, then surface to the PM with a verdict** (legit / avoidable / needs-PM-call), never a bare relay.
   - **pm** → oversight + product: frame the next `Backlog` → `Scoped` with its pre-committed AC, re-frame a `Blocked` consult-exception the SM surfaced, own the roadmap + owner touchpoints, resolve the rare product/scope judgment the QA seat surfaces (not in the routine merge path). The PM **frames/decides by posting a comment — it never edits the board `Status` field**; the SM operationalizes the transition.
3. **Drain your queue per `/check`, then idle.** Don't stop after one item — read the board **once** at
   the start of the engagement, then after each item (report posted, status flipped) immediately pull
   your role's next eligible item **from that same snapshot** and handle it (item → report → next),
   until none remain for your role; then report `queue clear — idle` and **stop**. The drain is
   **operator-initiated** and **bounded by the work that exists now**, every unit still passes its
   normal gate (per-unit 4-eye intact — not autonomous EPIC-draining), and it costs **one** board read
   regardless of queue depth (only cheap per-item mutations after — the rate-limit fix stays intact).
   Once empty, do **not** keep re-reading the board (no idle-poll, no self-loop); the operator
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
- **Role boundary — PM decides, SM operationalizes the board.** The **PM never edits the board `Status`
  field**: it frames/decides (AC · product-scope judgment · re-frames) by **posting a comment/decision**.
  The **SM performs the status transition** — e.g. for a re-framed `Blocked` item the PM posts the trimmed
  AC + "approved → Scoped", and the SM flips `Blocked→Scoped` on its `/check`. (Other seats still flip
  their *own* transitions — engineer claims `Scoped→In Progress`, QA sets `Tested`/`Scoped`, SM merges →
  `Merged`/`Released`; only the PM is status-edit-free.) Two supporting protocols: a producer that hits a
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
