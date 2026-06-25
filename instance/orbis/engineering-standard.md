# ORBIS Engineering Standard — EPIC #1065 cluster bar

> Builds on the framework production-ready floor ([`../../engineering-standard.md`](../../engineering-standard.md)) and the firmwide tiered model **ADR-0006** (Tier-1 / Tier-2). This adds ORBIS's EPIC-#1065 cluster-specific "done means", wave plan, and hygiene contract.
>
> **The bar.** Every PR that touches EPIC #1065 (or its 4 cluster EPICs #1063 Observability, #1019 Uplift, #246 Security, #1132 Cost) ships against this document. Cite it in PR bodies as `Bar: agentic-sdlc/instance/orbis/engineering-standard.md`.

## Done means — per cluster

### Observability (EPIC #1063)

- `agentcore deploy <runtime>` makes a row appear in `AgentRuntimeRegistry` with the **live ARN** from the `AWS::BedrockAgentCore::Runtime` resource. The seeder that manually populated this table is **deleted** in the same PR family (`## Retires` block).
- **Every** registered runtime has observability enabled (X-Ray traces, CloudWatch metrics, `AgentGeneration` rows). The gate is "100% of registry rows have ≥1 generation row within 24h of deploy."
- **Injection defense:** any RFP / web-tool content treated as **untrusted data** — wrapped in `<untrusted-input>` and **schema-validated** before any tool call. Schema mismatch fails closed (deploy / invocation aborts; no silent fallback).

### Uplift (EPIC #1019)

- A `SKILL.md` file the **live runtime LOADS and TRIGGER-FIRES** — proven by a smoke that POSTs a trigger phrase and asserts the skill fired (CloudWatch log line + a structured event written by the skill).
- **Secret rotation in DEV** is picked up by the running agent with **no redeploy** — proven by rotating `orbis/dev/lambda-internal-secret`, waiting one rotation poll cycle, and seeing the next invocation use the new value (audit via X-Ray correlation id on the secret-fetch).
- **Extended-thinking + memory:** AgentCore-native primitives, never Strands-SDK shims. Linter gate fails on `from strands.tools import MemoryTool` etc.

### Security (EPIC #246)

- **One canonical lexicon** at `agents/shared/forbidden-lexicon.json`. CI grep gate proves the scattered copies are **deleted** — `grep -rln "forbidden_lexicon\|FORBIDDEN_WORDS" | grep -v shared/forbidden-lexicon.json` returns empty.
- **Guardrails enforced, not log-only.** Bedrock Guardrails wired with a blocking action; the trust-layer audit records the block, not the model output the block prevented.

### Cost (EPIC #1132)

- **Real ledger rows.** Every Bedrock / AgentCore invocation writes an `AgentGeneration` row with `costEur > 0`. CI gate fails if any agent path has zero-cost rows after a smoke invocation.
- **Over-ceiling halt.** A run that crosses `pitch.costCeilingEur` actually halts — the next agent invocation throws `CostBudgetExceededError`. **No post-breach rows** in `AgentGeneration`. CI smoke triggers this with a synthetic ceiling and asserts the row count is bounded.

## Hygiene contract

Every sub-PR under EPIC #1065:

1. **Per-issue PR**, not per-cluster. The items merge as ~7 waves of focused PRs into the long-lived branch.
2. **Status-flip discipline** — Project #4 status moves `Backlog/Ready → In Progress` on first commit, `→ In Review` on main-merge, `→ Done` on STAGING deploy success (PROD-less mode).
3. **Closure with rationale.** No issue closes without a comment recording the decision — `Closed by #NNNN — <one-line evidence>` for shipped items; `Closed: adopt / skip / defer per ADR-0001 §X` for Review issues; `Superseded by #NNNN` for re-scoped items. No silent drops.
4. **PR body cites the bar.** Every PR body opens with `Bar: agentic-sdlc/instance/orbis/engineering-standard.md` and a one-line tick against each "Done means" criterion it addresses (or a `n/a — does not touch <cluster>` line).
5. **`## Retires` block** when the change replaces existing functionality — names what gets deleted, deprecated, or migrated in the same PR family. Load-bearing here because Wave 2 (registry SoR) retires the hand-seed script and Wave 6 (dashboard) retires scattered surfaces.

## Wave plan

See [the wave plan that opens the EPIC](https://github.com/sebas2810/orbis-platform/issues/1065). Summary order, with each wave's primitive deliverable:

| # | Wave | Primitive |
|---|---|---|
| 0 | Hygiene + bar | This document, citeable in every sub-PR |
| 1 | Eval discipline + lexicon | Falsifiable-evidence + single-source lexicon |
| 2 | Registry SoR | Deploy-derived registry, hand-seed deleted |
| 3 | Injection defense + runtime secrets | Untrusted-content gate + rotation-without-redeploy |
| 4 | Cost rails | Re-meter intake_v5 + ceiling halt |
| 5 | SKILL.md runtime + memory + compaction | Skills are load-bearing code |
| 6 | Eval/doctor/drift + guardrail + dashboard | Single ops surface |
| 7 | Model bump + security CI + close-outs | EPIC tree pruned |

The cluster-agnostic rejection list + grep-able anti-patterns this builds on are the framework's [`../../engineering-standard.md`](../../engineering-standard.md).

---

**Adopted:** 2026-06-03 as part of EPIC #1065 Wave 0. **Lives at:** the ORBIS instance overlay (`agentic-sdlc/instance/orbis/`).
