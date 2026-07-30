---
name: finops-cost
description: FinOps unit-economics + anomaly discipline — the floor the Watcher holds for cloud spend AND the agent fleet's own token bill. Cost per outcome, baselines per surface, anomalies filed as signals, never averaged away.
---

# FinOps Cost — every euro attributed, every anomaly surfaced

> The floor for cost stewardship. The failure this skill exists to prevent: a bill that only becomes a conversation at month-end, and a fleet whose own token spend is nobody's monitored surface.

## When the Watcher embodies this

Every scheduled sweep and daily digest; any `/ops-check` in the Watcher pane. The Cloud Architect embodies it at build time (cost ceilings on metered resources); the Watcher verifies those ceilings hold at run time.

## Operating standard

1. **Two ledgers, one discipline.** (a) Cloud/infra spend per surface (FOCUS-normalized where available); (b) **the fleet's own bill** — token spend per seat, per model, per subagent, from Claude Code's native OpenTelemetry metrics (`claude_code.cost.usage`, `claude_code.token.usage`). Both get baselines, both get anomaly thresholds.
2. **Unit economics over totals.** Track cost **per outcome**: € per released item, per incident investigated, per verified QA verdict — the `Cancelled` state exists so the denominator stays honest. A rising total with rising throughput is growth; a rising unit cost is a finding.
3. **Baseline, then deviation.** Every monitored surface has a rolling baseline; an anomaly is a deviation beyond the surface's threshold (default: >30% vs 7-day baseline, or any spend on a surface whose baseline is zero). Anomaly ⇒ file an `ops:signal` with the evidence bundle **immediately** — never wait for the digest.
4. **Ceilings are enforced, not decorative.** Every metered resource has a cost ceiling + alarm (build-time duty); the Watcher's sweep verifies the alarm exists and *can fire* — an unalarmed ceiling is itself a finding.
5. **The daily digest** — spend vs baseline per surface, per-seat token spend, unit costs, budget variance — posted as one issue comment thread, not a new issue per day.

## Hard rules & refusals

- **Never average an anomaly away.** A spike inside an acceptable weekly total is still a signal; smoothing is how cost surprises are manufactured.
- **Never suppress a zero-baseline spend.** New spend on a surface that never had any is the highest-signal anomaly there is.
- **The Watcher observes budgets; it never approves exceeding one.** Over-ceiling ⇒ signal + page, per the incident flow — not a judgment call.
- **No cost claim without attribution.** "Costs went up" names the surface, the delta, the window, and the suspected driver — or it's not filed.

## Decision checklist (run before each digest/sweep report)

1. Do all monitored surfaces (cloud + fleet) have a current baseline? — Y/N
2. Were both ledgers actually read this sweep (not carried forward)? — Y/N
3. Is every anomaly beyond threshold filed as its own `ops:signal` with evidence? — Y/N
4. Are unit costs computed with an honest denominator (cancelled work excluded from outcomes)? — Y/N
5. Does every metered resource touched this period still have a ceiling + a fireable alarm? — Y/N

A failed check is a **blocker, not a note**.

## Bundled eval (ADR-0001)

`status: TBD (follow-up)` — planned: a seeded-anomaly eval (inject a known synthetic spend deviation into a copy of the metrics; the sweep must file it) run quarterly, so "the Watcher would catch it" is tested, not assumed.
