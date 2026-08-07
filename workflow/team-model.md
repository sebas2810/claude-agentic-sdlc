---
title: The Team Model — operators, squads, and the fleet altitude
status: active
scope: all-seats
---

# The Team Model

> **Team is a layer, not a mode.** Every rule in this framework is written once
> and is unconditional; adding humans adds surfaces and information, never a
> second rulebook. A solo operator configures nothing and loses nothing; a team
> is a solo instance plus one URL.

This document is the model for running the SDLC with **more than one human**.
The mechanics (scripts, boards, config) live in
[`project-boards.md`](project-boards.md) and `onboarding/`; this is the *why*
and the boundaries. It also lands the deferred owner decision recorded in the
learning loop ("modelling the multi-squad-per-repo case itself") — see
[Topologies](#topologies).

## Why a team layer

The operating model was built for one human conducting many seats. The moment a
second human appears, four things need a home that solo use never asked for:
a shared surface (who is working on what), a unit of exchange between humans,
machine-verified state (humans now compare each other's boards), and a native
"which human is accountable" field.

The 2025–26 literature converged on the same conclusion from three independent
directions: Team Topologies' second edition extends *cognitive load* to AI as
**bounded agency** ("organizations already organized for bounded agency in
humans adopt AI effectively"); Appelo's org-design work states **AI agents do
not self-organize** — they need explicit orchestration structure; and
practitioner writing on agent fleets observes that **implicit boundaries fail
faster with AI agents**, because agents lack the contextual negotiation humans
use to paper over fuzzy interfaces. This framework's answer is to make every
boundary explicit and machine-checkable — which is what the rest of this
document does.

## The identity spine

Three identity layers, each carried by a different field, each answering a
different question. They exist today; the team layer names them and completes
the third:

| Layer | Carried by | Answers | Status |
|---|---|---|---|
| **Squad** (instance) | issue/PR `author` | which deployment owns this item | existing rule — [author is the ownership boundary](../feedback/workflow/author-is-the-ownership-boundary.md), unchanged |
| **Seat** (agent) | comment signature + per-worktree git identity | which agent acted | existing rule — actor gate, unchanged |
| **Operator** (human) | `assignee` — **at Epic/Initiative altitude only** | which human is accountable | completed by this model |

The operator layer is deliberately narrow. Below epic altitude the assignee
field is load-bearing execution machinery: an engineer self-assigns at claim,
and QA leaves it set on a FAIL so the rework query re-pulls it — a
`status:scoped` story with an assignee **means rework**, and a recorded 2026-08
incident (ten owner-assigned stories each read as QA bounce-backs) is why
visibility assignment on stories is stripped unconditionally. That rule
already carves out the correct home: *"owner/stakeholder visibility assignment
belongs on EPICs only."* The team layer standardizes it:

- **Every Epic and Initiative carries an assignee: the accountable human's
  GitHub login.** Set at framing, changed only by explicit human decision
  (assigning to a peer *is* the handoff — see below).
- Assignee is **accountability and visibility, never ownership and never
  routing** — ownership stays with `author`, routing stays with the
  `seat:*` lane. Nothing in any discovery query changes.
- Stories and Tasks: unchanged, exclusively claim/rework semantics.

## The altitude rule: Epics are the inter-human currency

**Humans exchange Epics. Squads exchange nothing below.** A squad's boundary is
an interface with exactly one endpoint — the Epic — consumed by other humans,
never reached through. (Team Topologies calls this a *Team API*; Amazon's API
mandate is the strongest precedent: teams communicate through interfaces, no
other form allowed.)

Concretely:

- Assigning an Epic to a peer operator on the fleet board is the handoff.
- The receiving human's **own PM frames the work in its own instance** — the
  Team PM or a peer never creates framed work inside a foreign squad. This
  reuses the Assure loop's proven cross-boundary write pattern (the Auditor
  files `status:backlog` items on a target's board; the local PM frames them
  like any work). It is also mechanically forced: a foreign-authored epic
  inside a product repo would be dropped by every seat's author-boundary
  filter — invisible to the very squad meant to build it.
- Stories and Tasks never cross humans. They are squad-internal execution
  detail, protected by the author boundary exactly as today.

## Topologies

Both team shapes are supported by the same three-layer spine; neither is a
mode:

- **Repo-per-developer** (the leading shape, matching `team-bootstrap.sh`):
  each human owns an instance in their own repo; the fleet board aggregates
  epics across repos. The `author` boundary is trivially satisfied.
- **Multi-squad-per-repo**: several humans' squads share one repo. The author
  boundary is the partition (`SQUAD_AUTHORS` in each seat's `.env.local`);
  the label namespace is shared and deliberately carries no ownership. This
  answers the deferred owner decision: **the author boundary is the model**,
  not a partitioned label namespace.

## The Initiative altitude and the Team PM seat

The hierarchy already defines the level above the Epic —
[`hierarchy.md`](hierarchy.md): *Initiative — a strategic outcome; quarters;
owner-framed; sub-issue roll-up* — but nothing operates at it. The team layer
staffs it.

**The Team PM is the PM role at fleet altitude — not a fourth authority tier,
and not a revival of the retired top-PM/sub-PM split.** Each instance still has
exactly one PM seat; the Team PM is the *team instance's* PM. The role model's
three tiers (Owner · PM-orchestrator · Engineer-Principal) are unchanged; like
the delivery squad staffing the Engineer role, the team repo staffs the PM role
once more at a different altitude.

| | Frames | Into | Never touches |
|---|---|---|---|
| Owner (team lead) | Initiatives | — | (owner-only, as today) |
| **Team PM** | — decomposes owner-framed Initiatives | Epic candidates, routed to operators | any squad's interior; framing Initiatives |
| Instance PM | Epics | Stories | tasks in flight, merging |
| Engineer | Stories | Tasks / code | the backlog above |

Boundaries, precisely:

- **Framing stays owner-only.** The owner (team lead) frames Initiatives; the
  Team PM decomposes and routes — the same owner/PM split every instance
  already runs, one level up.
- **It is a fleet seat**, the second of its kind. The framework now has two
  seat classes: *instance seats* (inside the repo they work on) and *fleet
  seats* (outside, operating against targets from their own checkout — the
  Auditor, the Team PM, and in time an ops fleet Watcher). The Team PM lives
  in the **team repo** — the small repo that also holds `team.config` and
  the fleet docs — with its own worktree and seat identity.
- **Cadence is unchanged.** The Team PM is conducted by the team lead, inert
  until `/check`, drains its queue (unframed-initiative decompositions,
  unrouted epic candidates, epics whose derived state turned `Blocked`,
  cross-squad dependency flags), stops at empty. No polling, no self-loop —
  the operator-driven invariant holds at every altitude.
- Orchestration is **in-band, on the board** — assignments, routings, and
  state are visible artifacts, never private channels. (Published safety
  result: hidden orchestrators measurably suppress protective behavior in
  multi-agent systems; visible-by-construction is the mitigation.)
- Initiatives live in the **team repo** (authored by the Team PM's account, so
  the author boundary holds at fleet altitude); Epics live in instance repos
  (authored by their squads); the Initiative→Epic link is a **cross-repo
  sub-issue** (GA; same-org verified; ≤100 children, 8 levels), so progress
  rolls up natively.

## Boards and states at fleet altitude

**The fleet board is Flight Level 2/3; squad boards are Flight Level 1.** One
org-level board, all Epics, nothing below ([provisioning](project-boards.md)).
The execution state machine — the 7 states, their gates, dual-write at the
point of write — is untouched at Flight Level 1. Epics and Initiatives still do
not run the 7 states. What changes is that their coarse lifecycle becomes
**derived, never hand-set**:

| Coarse state | Derivation |
|---|---|
| `Planned` | framed, no child in flight |
| `Active` | any child Story `In Progress`..`Tested` |
| `Done` | all children `Released` (the existing sub-issue roll-up) |
| `Blocked` | any child `Blocked`, or flagged by the owning PM |
| `Cancelled` | human decision — the one hand-set state |

This supersedes the fleet board's current hand-set `Status` ("set by PM or SM
per instance") — a manual mirror that its own document forbids two sections
earlier. Derived state cannot drift, which is the whole point of a board humans
trust *about each other*.

**How derivation is computed — and why it is not the removed projection
Action.** The hard invariant stands: at execution altitude there is *no
label-only mode, no projection Action, no deferred reconcile job* — every seat
dual-writes its own transitions at the point of write, verified by read-back.
Nothing here touches that. The fleet board is different in kind: it is *by
definition* a projection of squad boards, at an altitude where no seat performs
transitions at all. Its roll-up runs under the Run loop's one sanctioned
scheduled shape — the **Watcher fence**: a scheduled, bounded, headless GitHub
Action with its **own App token** (org `Projects` write + repo issues read —
`GITHUB_TOKEN` cannot write org projects), **REST-first discovery**, hard
run/duration caps. It writes **only fleet-board fields at Epic/Initiative
altitude**; on a squad's delivery board it repairs nothing and flags loudly —
no seat (and no Action) polices another's parity.

The same job closes the fleet board's real provisioning hole: Projects
**auto-add workflows still cannot be created via any API** (verified against
the live schema, 2026-08), so linking a repo never populates the board. The
fleet job adds `level:epic` items itself — the only fully scriptable path.

## The transition script

At execution altitude the team layer *strengthens* the existing invariant
rather than adding machinery: seats perform transitions through **one shipped
script** (label + board field + read-back + the altitude-scoped assignee
rules, atomically) instead of each seat hand-running the write sequence from
prose. Prompts drift; scripts don't. Same script solo and team — this is a
capability every instance gains, not a team feature.

## Flow analytics

[`flow-metrics.md`](flow-metrics.md) already names the metrics job as a
deliberate follow-up; the team layer builds it. Design rules:

- **The script counts, the seat interprets.** Metrics are *reperformable* (the
  Assure loop's evidence bar): derived by a deterministic collector from the
  issue-timeline **label events** — which are durable (explicitly excluded
  from the 30-day events retention) and efficiently queryable
  (`timelineItems(itemTypes: [LABELED_EVENT, UNLABELED_EVENT], since: …)`).
  The `status:*` dual-write is what makes this deterministic: **labels are the
  ledger; the board is a view.** (This is also why `type:*` labels remain the
  canonical work-type layer: issue types are org-only and emit no label
  events.)
- **What ships:** the DORA five in their 2025 definitions (change lead time ·
  deployment frequency · failed-deployment recovery time · change-fail rate ·
  rework rate), the Flow set already specified (throughput · cycle time · WIP
  · aging · flow efficiency; throughput *is* velocity here — no story
  points), and the **agentic-native set**: gate latency (opened → first human
  review — the 2025-26 consensus bottleneck), first-pass yield,
  unreviewed-merge rate, batch size, agent-attribution ratio, and
  **per-operator review-queue depth** — the fleet's headline number, because
  human review capacity, not agent throughput, is the constraint.
- **Segment everything by author class** (human / seat / bot); unsegmented
  numbers are meaningless in a mixed fleet.
- **Metrics measure flow, never people.** No per-human performance
  comparison, ever — the collector's skill file states this as a refusal, in
  line with "measure flow, not utilisation."
- **Honest gaps over fake numbers.** A convention doctor verifies each
  metric's preconditions per repo (label discipline, incident convention,
  deploy workflow named) and reports *not computable here* rather than
  emitting garbage. Survey-based dimensions (satisfaction, DXI) are named as
  out of scope, not proxied.
- Solo instances get the collector and its instance-level report with zero
  team config; the fleet run only aggregates.

## Table-stakes tracked from prior art

Commercial agent planes (GitHub Agent HQ, Devin, Cursor, Codex, Factory)
converge on capabilities the team layer should meet on its own terms — and
three things none of them have: initiative/epic roll-up across squads, states
derived from a deterministic ledger, and review-capacity as the sizing
constraint. Tracked as stories, not aspirations:

- **Commit → session provenance** — seat commits carry a session-log pointer
  in a commit trailer (as GitHub's coding agent stamps `Agent-Logs-Url`),
  making the git object itself the audit trail.
- **Budgets and concurrency as managed knobs** — per-seat/squad caps with
  alert-then-hard-stop semantics; WIP limits are the board half, spend/session
  caps are the runtime half.
- **Plan-approval gates** — the DoR/steer flow *is* the board-native plan
  gate; named as the equivalence so adopters recognize it.

## Adoption tiers

| Tier | Who | What exists |
|---|---|---|
| **0 — solo** | one human | today's two commands; nothing new to configure; transition script + collector improve every instance |
| **1 — team board** | 2–3 humans | `team-bootstrap.sh` + one URL; epics-only fleet board; the team lead conducts it by hand |
| **2 — fleet seats** | portfolio scale | the team repo; the Team PM seat; the fleet roll-up job; the fleet cadence report |

Each tier is an upgrade grown into, never a day-one decision — the same
graduated-trust arc the framework prescribes for its agents.

## What this changes (landed as stories, each a `chore(playbook)` PR)

1. Transition script (execution altitude, all instances).
2. Derived Epic/Initiative states + the fleet roll-up job (Watcher-fenced);
   rewrite of the fleet board's hand-set `Status` row.
3. Assignee-at-altitude rule (amendment to the seat-label-mirror rule; doctor
   check).
4. Fleet wiring completion: bootstrap wizard asks for `TEAM_BOARD_URL`
   (Enter = skip); fleet job auto-adds epics; `SQUAD_AUTHORS` added to
   `.env.local.example`.
5. Team repo + Team PM seat (KICKOFF, role-guard rows in `/check` ·
   `/workload` · `doctor.sh`, `seat.team-pm.template.md`).
6. Flow analytics: collector + `/fleet` command + cadence report + the
   flow-analytics skill + the `type:*` taxonomy check.
7. Provenance, budget, and concurrency knobs (table-stakes set).

Until a story lands, the current mechanics remain authoritative — this
document names target state versus built state deliberately; unfinished
reconciliation is tracked work, not silent debt.

## See also

- [`hierarchy.md`](hierarchy.md) — the four levels; the Initiative row this model staffs
- [`project-boards.md`](project-boards.md) — fleet board provisioning and views
- [`state-machine.md`](state-machine.md) — the 7 execution states (untouched by this model)
- [`flow-metrics.md`](flow-metrics.md) — the metric definitions the collector implements
- [`../feedback/workflow/author-is-the-ownership-boundary.md`](../feedback/workflow/author-is-the-ownership-boundary.md) — the squad boundary
- [`../assurance/agentic-assurance-model.md`](../assurance/agentic-assurance-model.md) — the first fleet seat and the cross-boundary write pattern
- `onboarding/team-bootstrap.sh` · `onboarding/team.config.example` — the mechanics
