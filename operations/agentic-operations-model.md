# The Agentic Operations Model — the Run spine

The [Agentic SDLC spine](../agentic-operating-model.md) governs how agents **build**. This spine governs how agents **run** what was built: monitoring, incident response, cost stewardship, and support. On conflict within the Run loop, this file wins; on conflict *between* loops, the SDLC spine's invariants (produce ≠ adjudicate, no false-green, the thread is the bus) still hold — they are load-bearing here too.

## The thesis

Fully autonomous remediation of novel failures is hype; **bounded runbook execution with graduated autonomy is what works**. An ops agent's authority is not a property of the *agent* — it is a property of the *(agent, action)* pair, earned per runbook with evidence, and revocable.

## The three trust tiers

| Tier | Seats | Credentials | May | May never |
|---|---|---|---|---|
| **A — observe** | Watcher | read-only telemetry/billing; issue write | read anything, file `ops:signal` issues with evidence bundles | change any system state |
| **B — investigate** | Investigator | tier A + repo/PR/CI read | post RCA + proposed remediation + blast radius | execute a remediation; merge |
| **C — act (guarded)** | Operator | scoped write creds, released per action via protected environments | execute an **allowlisted runbook** at its granted tier | improvise an action not in the runbook library |

## The runbook action tiers

- **Tier 0 — auto.** Reversible + bounded: restart a service, scale within pre-set min/max, clear a cache, rerun a failed job, flip a pre-approved flag *off*. Logged, no approval. **Tier 0 status is earned per runbook** (see promotion rule), never default.
- **Tier 1 — human-gated.** Rollback, config change, dependency pin. The gate lives **outside the agent runtime**: a GitHub environment protection rule or a human-applied approval label — and the gate checks the **actor** (a bot-applied approval label does not count).
- **Tier 2 — human-only.** Data mutations, security actions, customer communications. The Operator drafts; a human executes.

**Promotion rule (SLO-gated autonomy):** a runbook moves Tier 1 → Tier 0 only after N consecutive weeks (default 4) where its proposed executions were graded correct and inside SLO by the weekly evaluation. One graded regression demotes it back. Autonomy is earned, not assumed — and the compounding-error math is the reason: 95% per-step accuracy over ten steps is 60% end-to-end.

## The invariants

1. **Observation mode first.** Every new seat (and every new runbook) starts propose-only: 30–60 days where proposals are graded, nothing executes. Trust is granted runbook-by-runbook, not seat-by-seat.
2. **Capability containment over prompt trust.** Deterministic limits — read-only tokens, per-seat egress allowlists, PreToolUse deny-hooks — not instructions. Approval prompts are weak controls; hooks and environment protections are strong ones.
3. **Hard budgets, everywhere.** Max tokens per run, max runs per hour, max Tier-0 executions per hour per seat. Unbounded consumption ("nothing said stop") is the most-reported agentic-ops failure mode. The Watcher monitors the other seats' spend; a human monitors the Watcher.
4. **Blast radius is computed against the agent's full privilege set**, never the triggering event's scope.
5. **Evidence bundles, not vibes.** A signal without a metrics snapshot, log excerpt, and links is noise. Alert precision is tuned ruthlessly — false positives are where operator trust dies.
6. **Investigation is hypothesis-driven, not summarization** (the [incident-rca skill](skills/incident-rca.md)): enumerate causes, test each against telemetry and *what changed* (git log + PR history — the highest-yield RCA signal), prune by evidence.
7. **MTTR splits in two.** Track *investigation time* and *remediation time* separately — agents compress the former; conflating them hides which half improved.
8. **The loopback is mandatory.** Every `sev:1`/`sev:2` post-mortem produces a framed item on the **Delivery** backlog. Run discovers work; Build fixes it; a post-mortem with no backlog item is unfinished ([scope honesty](../agentic-operating-model.md) applies).
9. **The agent toolchain is an attack surface.** Pin and verify the Actions, packages, and MCP servers ops seats consume; an Investigator reads arbitrary production text, so prompt injection via logs/telemetry is a live vector — which is exactly why approval gates live outside the runtime.

## Cadence — the honest amendment

The SDLC's operator-driven mode ([`../MODES.md`](../MODES.md) — "no cron, no self-loop") remains the default for Investigator and Operator: they act on `/ops-check` or on an explicit event dispatch, and stop at empty. **Watchers are the deliberate, owner-gated exception**: monitoring that only runs when a human remembers is not monitoring. A Watcher run is a *scheduled, bounded, headless* invocation (GitHub Actions `schedule:`, own App token, REST-only discovery, hard token/duration caps) — a different mechanism from the removed autonomous seat-loop: no idle pane, no self-wake, no shared-quota GraphQL. Escalation never widens authority: if no human acks a Tier 1 proposal, the Operator may apply Tier 0 mitigations only and keep paging.

## Metrics

Classic: MTTD · MTTA · MTTR (investigation/remediation split, over `type:incident` items — see [`../workflow/flow-metrics.md`](../workflow/flow-metrics.md)) · SLO burn · **alert precision per watcher**. Agentic: % incidents resolved zero-touch · escalation precision · RCA accuracy grade (graded against actual root cause, weekly) · % actions auto vs gated. FinOps: cost per incident investigated · token spend per seat per week · unit cost per outcome (the [finops-cost skill](skills/finops-cost.md)).

---
Squad: [`seats/SQUAD.md`](seats/SQUAD.md) · Flow: [`workflow/ops-state-machine.md`](workflow/ops-state-machine.md) · Runbooks: [`runbooks/README.md`](runbooks/README.md) · Assure loop: [`../assurance/README.md`](../assurance/README.md)
