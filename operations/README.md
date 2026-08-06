# Agentic Operations — the Run loop

**One spine, three loops.** The [Agentic SDLC](../agentic-operating-model.md) is the **Build** loop (delivery agents earn trust through code review). This directory is the **Run** loop: agents that watch, investigate, and remediate production — earning trust through **graduated autonomy**. The **Assure** loop lives in [`../assurance/`](../assurance/README.md) and audits both.

> Delivery agents earn trust through code review; operations agents earn trust through graduated autonomy. Same seats-and-labels machinery — **the gate moves from *merge* to *execute*.**

## What's in this folder

| Path | What it is |
|---|---|
| [`agentic-operations-model.md`](agentic-operations-model.md) | **The Run spine** — trust tiers, graduated autonomy, the ops invariants |
| [`workflow/ops-state-machine.md`](workflow/ops-state-machine.md) | Incident flow: `signal → triage → investigating → mitigating → resolved → postmortem` + the **loopback** to the delivery backlog |
| [`workflow/project-templates/labels.json`](workflow/project-templates/labels.json) | The `ops:*` routing index + `type:incident` + `sev:*` labels (seeded when the ops board is stood up) |
| [`seats/SQUAD.md`](seats/SQUAD.md) | The ops squad: **Watcher** (tier A, read-only) · **Investigator** (tier B, read-mostly) · **Operator** (tier C, guarded actuator) |
| [`skills/`](skills/INDEX.md) | Ops skills: hypothesis-driven **incident RCA** · **FinOps cost** (including the fleet's own token bill) |
| [`runbooks/`](runbooks/README.md) | The runbook library contract — remediations as PR-reviewed code, tiered 0/1/2, promoted by SLO evidence |
| [`../commands/ops-check.md`](../commands/ops-check.md) · [`../commands/ops-board.md`](../commands/ops-board.md) | The ops slash-commands (top-level `commands/` so the plugin ships them with the rest) |

## Quickstart

1. Stamp an **Operations board** for your instance (golden-template `copyProjectV2`, the same mechanism as the Delivery board — see [`../workflow/project-boards.md`](../workflow/project-boards.md)) and seed the labels from `workflow/project-templates/labels.json`.
2. Stand up the **Watcher** seat first — read-only, files `ops:signal` evidence bundles, watches cost (cloud + the fleet's own token spend). Nothing else until its signal precision is trusted.
3. Add the **Investigator** in **observation mode**: RCAs posted and graded against actual root causes; no remediation authority.
4. Only then the **Operator** — and only via the [runbook library](runbooks/README.md): Tier 0 (auto, reversible) is *earned per runbook* by SLO evidence, never granted.

Ops seats boot exactly like delivery seats: worktree + `.env.local` (`SEAT_ROLE=watcher|investigator|operator`) + `setup-seat.sh` — `bootstrap.sh` provisions them from `sdlc.config` like any other role.

## Relationship to the Build loop

The Run loop **composes with** delivery — same cheap label-index discovery, same dual-write rule, same operator-driven default (with one owner-gated amendment for scheduled Watcher runs, stated honestly in the spine). Post-mortems file remediation work onto the **Delivery** board (`status:backlog`, parented under `Epic: Operations & Incidents`) — Run discovers work, Build fixes it, Assure verifies the loop closes.
