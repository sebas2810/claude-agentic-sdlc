# Agentic Assurance — the Assure loop

**One spine, three loops.** [Build](../agentic-operating-model.md) delivers, [Run](../operations/README.md) operates, **Assure audits both** — the third line of the IIA Three Lines Model, staffed by an agent. Delivery agents earn trust through code review; ops agents through graduated autonomy; **the audit agent earns trust through reperformable evidence** — the gate moves from *merge* to *execute* to ***attest***.

> **Independence is structural here.** This directory is **excluded from product vendoring** (`vendor-framework.sh`) — the Auditor runs from its own checkout of this framework *against* target repos, not from inside them. The seat never builds, never merges, reports to the **owner** (not the PM), and a **human signs** every audit report.

## What's in this folder

| Path | What it is |
|---|---|
| [`agentic-assurance-model.md`](agentic-assurance-model.md) | **The Assure spine** — the three lines mapped to seats, independence rules, the evidence bar |
| [`workflow/audit-lifecycle.md`](workflow/audit-lifecycle.md) | Engagement types (release audit · quarterly systemic · monitor audit) and the finding flow back into delivery |
| [`seats/auditor/KICKOFF.md`](seats/auditor/KICKOFF.md) | The Auditor seat — authority, work cycle, refusals |
| [`skills/`](skills/INDEX.md) | Audit lenses: **AWS Well-Architected** (six pillars as falsifiable checks) · **OWASP Agentic Top 10** (auditing the fleet itself) |
| [`evidence/`](evidence/README.md) | The evidence-store contract — machine-checkable, reperformable, provenance-tracked |
| [`registry/`](registry/README.md) | **Know your agent** — one agent card per seat across all three loops (asset inventory · NHI register · auditor/insurer evidence pack in one) |
| [`../commands/audit.md`](../commands/audit.md) | The `/audit` engagement command |

## The three lines, staffed

| Line | Who | What |
|---|---|---|
| **1 — own the risk** | Producer seats, ops seats | Build and run, inside the gates |
| **2 — oversee** | Quality Engineer · Scrum-Master · CI gates · Watcher SLOs | Continuous monitoring, embedded in the flow |
| **3 — assure** | **Auditor seat → owner signs** | Independent, periodic, reperformable — and it audits the *monitors*, not just the work |

The load-bearing distinction (from the IIA's continuous-auditing guidance): lines 1–2 monitor **continuously**; line 3's job is then to **test the monitoring itself** — did QA verdicts hold post-release? Can the "green" gates actually fail? What is the Watcher's real alert precision?

## Quickstart

1. Create the Auditor's **own checkout** of this framework (not a vendored copy inside a product repo) with read access to the target repos + boards.
2. Fill one [agent card](registry/AGENT-CARD.template.md) per existing seat — the registry is audit prerequisite #1 ("know your agent").
3. Run the first engagement: `/audit release <epic-#>` on one released epic — end-to-end AC-to-verdict trace + a monitor test. Findings land on the target's Delivery board as `type:audit` issues; the owner signs the report.
