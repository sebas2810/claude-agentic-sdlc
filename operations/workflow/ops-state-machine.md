# The Ops State Machine — incident flow

**The Operations board *is* the state.** Same discipline as the Delivery board: the board `Status` field is the canonical record, the `ops:*` **issue label** is its cheap discovery mirror, and every transition **dual-writes both**. Discovery is always `gh issue list --search "label:ops:<state>"` (REST budget) — never the 300-item board read.

## States

| State | Meaning | Entry gate |
|---|---|---|
| `ops:signal` | A watcher filed evidence of something anomalous | Evidence bundle attached (metrics snapshot · log excerpt · links) — a signal without evidence is closed as noise |
| `ops:triage` | Signal acknowledged, severity assigned | `sev:1/2/3` + `type:incident` applied; duplicates/noise closed with reason |
| `ops:investigating` | Investigator owns it, RCA in progress | — |
| `ops:mitigating` | RCA posted; remediation proposed or executing | RCA comment: root cause · evidence · confidence · proposed runbook · **blast radius** |
| `ops:resolved` | Service restored, verified from telemetry | Independent health signal green (not the remediation's own success log) |
| `ops:postmortem` | `sev:1/2` only: post-mortem being written | — |

Terminal: **close** — for `sev:1/2`, closing requires the post-mortem comment **and the loopback item** (below). `sev:3` may close at `ops:resolved`.

## Transitions

| From → To | Driver | Rule |
|---|---|---|
| (none) → `ops:signal` | Watcher | evidence bundle or it doesn't exist |
| `ops:signal` → `ops:triage` | Investigator | assign `sev:*`; noise/dup → close with reason (feeds alert-precision tuning) |
| `ops:triage` → `ops:investigating` | Investigator | claims it; hypothesis-driven RCA per the [incident-rca skill](../skills/incident-rca.md) |
| `ops:investigating` → `ops:mitigating` | Investigator | RCA comment posted (root cause · evidence · confidence · runbook · blast radius) |
| `ops:mitigating` → `ops:resolved` | Operator | executes the named runbook **at its granted tier** (Tier 1+ = external approval gate first); verification = independent health signal, never the action's own exit code |
| `ops:resolved` → `ops:postmortem` | Investigator | `sev:1/2` mandatory |
| `ops:postmortem` → closed | Investigator | post-mortem posted **+ loopback filed** |

**Severity:** `sev:1` = user-facing outage / data risk — a human is paged *in parallel* with the Investigator, always. `sev:2` = degradation with a deadline. `sev:3` = anomaly worth a look. P0 on the Delivery board and `sev:1` here are cousins: a `sev:1` whose fix needs code becomes a `priority:P0` delivery item immediately, not post-post-mortem.

## The loopback (mandatory for sev:1/2)

The post-mortem's "how do we prevent recurrence" items are filed on the **Delivery board**: `status:backlog`, parented under `Epic: Operations & Incidents`, linking the incident issue. The PM frames them like any backlog item. **Run discovers work; Build fixes it.** An ops issue closed without its loopback is the silent-debt failure the SDLC spine's scope-honesty rule exists to prevent.

## Support lane (when the instance has external users)

`ops:inbox → ops:answering → ops:escalated → ops:closed`. Hard escalation triggers, no judgment calls: confidence below threshold → escalate · explicit "human please" → escalate **immediately, no confirmation step** · two consecutive negative-sentiment turns → escalate. Every escalation carries full context. Target honest zero-touch resolution (40–60%), not brochure numbers.
