# The Runbook Library — remediations as code

The Operator's **entire action surface**. A remediation exists only as a versioned, PR-reviewed runbook in this directory; anything else is improvisation, which the Operator refuses by KICKOFF. Runbooks are code: they enter through the normal Delivery flow (issue → PR → QA → merge), and their *authority* is separate from their *existence* — a merged runbook starts at Tier 1 or 2, never Tier 0.

## The action tiers

| Tier | Label | Execution | Examples |
|---|---|---|---|
| **0 — auto** | `runbook:tier-0` | Operator executes, logs, verifies. No approval. | restart service · scale within pre-set min/max · clear cache · rerun failed job · flip a pre-approved flag **off** |
| **1 — human-gated** | `runbook:tier-1` | External approval gate first (environment protection / human-applied label — the gate checks the **actor**) | deploy rollback · config change · dependency pin |
| **2 — human-only** | `runbook:tier-2` | Operator drafts exact commands + rollback; a human executes | data mutations · security actions · customer communications |

## The promotion rule (SLO-gated autonomy)

Tier 1 → Tier 0 requires **N consecutive weeks (default 4)** of graded-correct proposed executions inside SLO, granted by the owner, recorded in the runbook's `## Promotion history`. **One graded regression demotes it back** — a demotion is the system working. New runbooks and new seats start in observation mode (propose-only) regardless of tier.

## What makes a runbook valid

Every runbook follows [`TEMPLATE.md`](TEMPLATE.md) and must have: falsifiable **preconditions** (checked at execution time, not RCA time) · deterministic **steps** (commands, not intentions) · a **rollback** that is part of the action, not a follow-up · a stated **blast radius** against the Operator's full privilege set · an **independent verification signal** (never the action's own exit code) · named **credentials** (scoped, short-lived, released per execution — no standing broad tokens).

A runbook missing any of these is Tier 2 at best, whatever its label says — and the label gets fixed.
