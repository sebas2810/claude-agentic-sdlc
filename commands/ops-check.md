---
description: Drain THIS ops seat's queue (tier-aware) via the cheap ops:* label index — Watcher sweeps, Investigator triages/RCAs, Operator executes granted runbooks. REST discovery, dual-write, stop at empty.
---

You **drain your ops queue**, tier-aware, off the cheap `ops:*` **label index** — never a heavy board read. Take an eligible item, do it, report, take the next, until none remain for your role; then report `queue clear — idle` and **stop** (no self-loop, no idle-poll — the operator or an event dispatch re-engages you). The same two rails as `/check`: operator-initiated (or an explicit event dispatch) and bounded by the work that exists right now.

Resolve seat identity exactly as `/check` does (env first, else `./.env.local`): `SEAT_ROLE` must be `watcher`, `investigator`, or `operator` — a delivery role gets *"that's `/check`'s queue, not `/ops-check`'s"* and stop. **Targeted mode `/ops-check #<n>`** works like `/check #<n>`: act only if the item's `ops:*` state matches your role's gate below, else report why and stop.

**Dual-write, every transition** — the `ops:*` label (REST, the discovery mirror) **and** the Ops board Status field together, same non-negotiable rule as the Delivery board.

Find + act by **role**:

- **watcher** — your queue is your *sources*, not the board. One sweep per engagement:
  1. Read health endpoints, error rates, SLO burn, third-party status, cloud spend, and the fleet's own token spend (per seat/model), per your [FinOps Cost](../operations/skills/finops-cost.md) skill.
  2. Deviation beyond a baseline threshold → file **one** `ops:signal` issue per distinct anomaly (dedupe first: `gh issue list --search "is:open label:ops:signal" -L 30` — annotate an existing signal rather than duplicating) with the **evidence bundle**: metrics snapshot · log excerpt · links.
  3. Post/append the cost digest when due. Report what you filed/annotated (#s) and stop. You **never** remediate, never triage severity — that's the Investigator.

- **investigator** — triage first, then RCA:
  `gh issue list --search "is:open label:ops:signal sort:created-asc" -L 1 --json number,title,labels`
  → **TRIAGE**: noise/dup → close with reason (Watcher tuning feedback); real → `sev:1|2|3` + `type:incident`, dual-write → `ops:triage` (for `sev:1`: confirm a human is paged **now** — if not, that page is your first act). Then
  `gh issue list --search "is:open label:ops:triage sort:created-asc" -L 1 --json number,title,labels`
  → **RCA** per your [Incident RCA](../operations/skills/incident-rca.md) skill (claim: dual-write → `ops:investigating`): hypotheses → what-changed correlation (git log · merged PRs · deploys · config) → discriminating tests → prune. Post: **root cause · evidence · confidence · proposed runbook from `operations/runbooks/` · blast radius**; dual-write → `ops:mitigating`. No fitting runbook → say so + propose drafting one (Tier 2 this time). After resolution, `sev:1/2`: write the post-mortem **and file the loopback** on the Delivery board (`status:backlog`, parent `Epic: Operations & Incidents`, link the incident) before closing. You **never** execute.

- **operator** —
  `gh issue list --search "is:open label:ops:mitigating sort:created-asc" -L 1 --json number,title,labels`
  → read the RCA + the named runbook **in full**; re-verify its preconditions *now*. Then by the runbook's granted tier: **tier-0** → execute, log (runbook id+version · evidence before/after); **tier-1** → request the external approval gate and execute only after a **human** actor approves (a bot-applied approval is void); **tier-2** → draft exact commands + rollback into the issue for a human. **In observation mode** (your default until graduated): post the exact execution plan instead of executing, for grading. Verify by the runbook's **independent health signal** — healthy → dual-write `ops:resolved`; not → run the rollback, post state honestly, re-page. Respect hard budgets (max tier-0/hour, max tokens/run) — budget hit ⇒ stop and page.

**Drain, then idle.** Re-run your role's query; another eligible item → handle it; none → `queue clear — idle`, stop.
