# The Ops Squad — seats by trust tier

Same seat-vs-skill rule as the [delivery squad](../../seats/SQUAD.md): a capability is a **seat** when it operates independently (own context, parallel, especially when it checks someone else's work); a **skill** when it's a lens the same seat applies. The ops squad's extra dimension is the **trust tier** — what credentials a seat may hold.

## Roster

| Tier | Seat | × | Role | Embodies (skills) | Model |
|---|---|---|---|---|---|
| **A — observe** | **Watcher** | 1 | Read-only sentry: health endpoints, SLO burn, error rates, third-party status, cloud spend **and the fleet's own token bill**. Files `ops:signal` issues with evidence bundles; daily cost digest. **Never remediates.** | [FinOps Cost](../skills/finops-cost.md) | haiku |
| **B — investigate** | **Investigator** | 1 | Hypothesis-driven RCA on incidents: enumerate causes, test against telemetry + *what changed* (git/PR history), prune by evidence; posts root cause · evidence · confidence · proposed runbook · blast radius. **Never executes.** | [Incident RCA](../skills/incident-rca.md) | opus |
| **C — act** | **Operator** | 1 | Guarded actuator: executes **allowlisted runbooks only**, at each runbook's granted tier (0 auto / 1 human-gated / 2 draft-only). Starts in observation mode — proposes, never executes, until graduated. | [Runbook library](../runbooks/README.md) | sonnet |
| **B — respond** | **Support** | 0–1 | Drains the support inbox lane from KB + code; hard escalation triggers with full-context handoff. Staff only when the instance has external users. | — | sonnet |

**Evaluation is a duty, not a seat (initially):** the delivery **Quality Engineer** extends its line-2 role with the weekly ops evaluation — grade RCAs against actual root causes, grade Operator proposals, maintain the agent SLOs that gate runbook promotion. Staff a dedicated Evaluator seat only when volume demands it.

**Humans:** one on-call human is the escalation target and Tier-1 approval authority; the owner is incident commander for `sev:1`. Always-on agents + a single human rota replaces follow-the-sun.

## Why the tiers are load-bearing

Credentials follow the tier, not the task: a Watcher that *could* restart a service will eventually be prompted into doing so — containment is deterministic (what the token allows), not behavioral (what the prompt says). Only the Operator holds write credentials, released per action through protected environments; the Investigator's independence from execution is what makes its blast-radius estimate honest.

## Add a seat

Same flow as the delivery squad: copy a KICKOFF as the shape, fill in authority + work cycle + **tier**, add a row here, wire identity via `onboarding/setup-seat.sh` (`SEAT_ROLE=watcher|investigator|operator`) — `bootstrap.sh` provisions ops roles from `sdlc.config` like any other seat.
