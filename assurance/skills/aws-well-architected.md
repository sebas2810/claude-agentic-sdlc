---
name: aws-well-architected
description: The AWS Well-Architected Framework as an audit lens — six pillars turned into falsifiable, reperformable checks the Auditor runs against any AWS-hosted target. Embodied during release and quarterly engagements; findings cite the pillar.
---

# AWS Well-Architected — six pillars as falsifiable audit checks

> The flagship audit lens for AWS-hosted targets. The Well-Architected Framework is already question-shaped — this skill's job is to keep the Auditor honest about *evidence*: every answer is grounded in a reperformable check (a CLI query, a config read, a fired alarm), never in what the architecture diagram or the building seat *says*. Where the instance uses the AWS Well-Architected Tool, the workload review lives there and this skill supplies the evidence discipline; where it doesn't, the checklist below is the review.

## When the Auditor embodies this

Release engagements (the released epic's touched surfaces) and the quarterly systemic engagement (the whole workload). Build-time counterpart: the Cloud Architect seat holds the *build* floor (its Principal skill); the Auditor independently verifies it held — same pillars, different line.

## Operating standard

Audit each pillar with evidence, not narrative. A check that cannot be reperformed from the finding is not done. Sample where exhaustive is impractical — but record the sample.

- **Operational Excellence** — everything load-bearing is code (IaC, runbooks); telemetry exists for each critical path; the ops loop's post-mortems trace to shipped loopback items.
- **Security** — least-privilege verified from *live* IAM policy (not intent); no long-lived broad credentials (seat tokens included — cross-check the [agent registry](../registry/README.md)); untrusted input schema-gated, failing closed; secrets in a manager, never in env files or code.
- **Reliability** — a failure injected in a sampled critical path *demonstrably* triggers the health signal and recovery path (the circuit-breaker/rollback actually fired in a test, ever); backups restorable (a restore has been performed, not assumed); quotas/limits known and alarmed.
- **Performance Efficiency** — the sampled path's latency/throughput measured against its stated target; right-sizing reviewed against actual utilization, not instinct.
- **Cost Optimization** — **every metered resource has a ceiling + an alarm that has been proven to fire**; unit cost per outcome computed with an honest denominator; scale-to-zero (or equivalent) on non-prod verified live; the fleet's own token spend attributed per seat.
- **Sustainability** — utilization targets set; idle/oversized capacity from the utilization data named as a finding, not a shrug.

## Hard rules & refusals

- **No diagram-audits.** Evidence comes from the live account and the pipelines (`aws` CLI reads, config exports, alarm history) — never solely from documentation or the building seat's description.
- **An alarm that has never fired in a test is unverified** — "configured" ≠ "working"; the check is the alarm's fire, not its existence.
- **Never accept compensating narrative for a failed check** — a failed check is a finding; the owner may accept the risk *in writing*, which the finding records.
- **Read-only always.** The lens audits; it never fixes, tunes, or "quickly enables" anything in the account.

## Decision checklist (run per engagement before the report drafts)

1. Does every pillar conclusion cite ≥1 reperformable check (command/query + result), with the sample recorded? — Y/N
2. Security: does live IAM match least-privilege claims, and does every seat credential match its registry card? — Y/N
3. Reliability: has the sampled recovery path *actually fired* (test or real) within the review window? — Y/N
4. Cost: does every metered resource touched by the audited work have a ceiling + a proven-fireable alarm? — Y/N
5. Are all failed checks filed as `type:audit` findings citing their pillar (none narrated away)? — Y/N

A failed check is a **blocker, not a note**.

## Bundled eval (ADR-0001)

`status: TBD (follow-up)` — planned: a seeded-defect eval (introduce a known Well-Architected violation — e.g. an unalarmed metered resource — into a sandbox stack; an engagement run against it must surface exactly that finding).
