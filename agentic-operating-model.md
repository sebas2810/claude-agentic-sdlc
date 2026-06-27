---
title: Agentic Operating Model
status: active
scope: all-seats
root-source: "Anthropic - Building Effective Agents"
last-updated: 2026-05-19
---

# Agentic Operating Model

This is the single authoritative spine the agentic-sdlc derives from. Seat
authority files, the Principal skills, and the kickoffs are downstream of this
document. When they conflict, this wins; raise the conflict as a `chore(playbook)`
PR rather than diverging silently.

This is the **generic framework** spine — product-agnostic. How its principles
map to the specific agent platform an instance ships is the instance's overlay
(the instance's is [`instance/<your-instance>/product-mapping.md`](instance/<your-instance>/product-mapping.md)).

## Thesis

An agentic platform built by an agentic SDLC. Both run on one spine:
Anthropic's "Building Effective Agents". The product (the agents the instance
ships) and the process (how the PM and engineer seats actually deliver EPICs)
are isomorphic, and that isomorphism is the asset, not a coincidence.

The practical consequence: one test answers two questions. "Would we accept
this in our own SDLC?" is the same question as "is this agent design
effective?" If a pattern is too unbounded, too opaque, or self-grading to be
trusted in how we build, it is too unbounded, opaque, or self-grading to ship
as product. We do not maintain two bars.

## The 7 principles → dual mapping

Each principle governs both the product an instance ships and the process it
ships with — that is the isomorphism. The column below is the **process** (how
we build); the **product** column (how these principles govern the agents your
instance ships) is the instance's mapping — the instance's is in
[`instance/<your-instance>/product-mapping.md`](instance/<your-instance>/product-mapping.md).

| Principle | Agentic SDLC (how we build) |
|---|---|
| **1. Workflow-first; agents only for genuinely open-ended work** | EPIC delivery is a fixed-phase workflow (Frame → Steer → Plan → Build → Verify → Adjudicate → Release → Learn), not "an engineer agent figures it out". The open-ended judgement sits inside Build, scaffolded by the phases around it. |
| **2. Start simple; complexity must demonstrably pay** | One branch per EPIC, smallest design that meets the AC. Worker subagents are added only when parallel WPs are genuinely independent; "more agents" is never the default. |
| **3. The augmented LLM (tools + memory + guardrails) is the atom; compose, don't framework** | The Principal skills are composable operating standards a seat embodies. A core PM + Engineer pair extends to a squad of specialist **producer** + independent **assurance** seats when independence is warranted (the #985 granularity rule + produce ≠ adjudicate) — see [`seats/SQUAD.md`](seats/SQUAD.md). Each seat is an augmented atom composing its skills; GitHub is the composition substrate — a principled squad, not a sprawl of agents for its own sake. |
| **4. Orchestrator-workers for unpredictable multi-step** | PM-orchestrator decomposes an EPIC into WPs; engineer-Principal executes; worker subagents only for genuinely-independent parallel WPs. The same in-runtime-default / cross-runtime-only-when-independent rule applies to how work is split. |
| **5. Verify against the environment; evaluator ≠ producer** | Deterministic evals are the oracle for "done". The seat that produced the work does not adjudicate it; PM validates once at merge against pre-committed criteria. No LLM-self-grade in either column. |
| **6. ACI / tool design is first-class (as much effort as prompts)** | The GitHub thread, PR templates, `## Retires`/`## Closes` conventions, ready-signal shape, and local gate scripts are the SDLC's ACI. Their design is load-bearing and maintained with the same care as agent tooling. |
| **7. Simplicity + transparency; human owns irreversible; explicit stop condition** | Fixed countable human touchpoints; the thread is transparent and auditable; PROD + product/strategic + master-EPIC are owner-owned; routine DEV→main merge is the PM (4-eye = Engineer→PM, not an owner gate). **The stop condition is mode-aware** ([`MODES.md`](MODES.md)): in **manual** mode, "finish, report, stop" — no loops, no autonomous loop-driven merge; in **autonomous** mode, the PM runs a bounded, eval-gated [stateless loop over the board](workflow/state-machine.md) that stops when the board is drained or only `Blocked` remains. Either way the loop is bounded and the irreversible class stays owner-owned. |

## The Agentic SDLC - 8 phases

| Phase | Actor | Autonomy class | Gate / principle |
|---|---|---|---|
| **1 Frame** | Human owner | Owner-only | Master-EPIC definition, product/strategic intent. Principle 7 (human owns the irreversible framing). |
| **2 Steer** | PM-orchestrator | PM-autonomous | EPIC scope + WP decomposition + acceptance criteria pre-committed. Principle 1 (workflow scaffold) + 4 (orchestrator). |
| **3 Plan** | Engineer-Principal | Engineer-autonomous within steer | Design proposed against the smallest sufficient shape. Principle 2 (start simple) + 3 (augmented atom). |
| **4 Build** | Engineer-Principal (+ worker subagents only for genuinely-independent parallel WPs) | Engineer-autonomous within steer + guardrails + skills | Branch-per-EPIC; the instance's augmented-atom platform floor (the instance: AgentCore-first + the 5-layer envelope). Principle 3 + 4. |
| **5 Verify** | Deterministic evals | Non-negotiable, automated | Falsifiable, both-directions, anti-tautology. Canary before any irreversible step. Never LLM-self-grade. Principle 5 + 7. |
| **6 Adjudicate + Integrate** | PM-orchestrator | PM-autonomous, exactly once | Produce ≠ adjudicate: the non-authoring seat validates vs pre-committed criteria, once, at merge. Principle 5. |
| **7 Release** | Staging = PM ceremony; PROD = human owner | PM-autonomous (staging) / owner-only (PROD) | Irreversible release is human-owned. Principle 7. |
| **8 Learn** | PM-orchestrator | PM-autonomous | Capture rule/eval/skill; feed the RAG→fine-tune signal (V1→V2). Principle 5 (eval capture) + product flywheel. |

## The 8 invariants

These hold across product and process. Breaking one is a defect, not a
judgement call.

1. **Fixed, countable human touchpoints.** The *owner* appears in a known finite
   set of places (frame, the 3 consult-exceptions, PROD + the owner-gated
   release/repo-settings/destructive class). Not "wherever a question arises".
   The routine within-team human touchpoint — review + merge of the engineer's
   DEV→main work — is the **PM**, not the owner: the 4-eye principle is the
   Engineer→PM separation (engineer builds, PM independently reviews + merges),
   not a third owner gate.
2. **Evals are the oracle.** "Done" is decided by deterministic, falsifiable,
   both-directions, anti-tautology evals against the environment, not by a
   model's opinion of its own work.
3. **Produce ≠ adjudicate, once at merge.** The seat that produced the work
   never grades it. Validation happens once, by the non-authoring seat,
   against criteria committed before the work started.
4. **Canary before irreversible.** Nothing irreversible (PROD, customer publish,
   destructive migration) ships without a reversible canary first.
5. **No false-green, no silent-degradation.** A failed load-bearing path
   raises and flips a health signal. "Produced output" is never evidence the
   output is correct; warn-and-continue on a load-bearing path is a defect.
6. **Context engineering is where quality comes from.** Quality moves come
   from the envelope (right context, memory, tools, guardrails), not from more
   agents or longer prompts. Spend effort there.
7. **The shared thread is the bus; the human is never the relay.** PM and
   engineer coordinate on GitHub (issues/PRs). The owner is not a message
   courier between seats.
8. **Deliberate, not burst, on high-stakes units.** On a high-stakes unit, the
   seat reasons it through before acting; speed never overrides the verify
   and adjudicate invariants.

## Role model

Three roles, each with an exact fixed touchpoint list. The list is the
contract: a role's surface is what is on its list and nothing else.

The Engineer-Principal role is **staffable as a squad** — one or more specialist
producer seats (full-stack, data, cloud, …) plus an independent assurance seat
(quality / testing). The authority tiers stay these three; the squad is *how the
Engineer-Principal role is staffed*, not a fourth tier. See [`seats/SQUAD.md`](seats/SQUAD.md).

### Owner

- Master-EPIC definition and reframing.
- Product and strategic decisions (Model A vs B, thresholds, audience policy,
  milestone shifts).
- PROD push.

That is the entire list. The owner does not relay messages between seats and
does not adjudicate or gate routine PRs — the PM reviews + merges the routine
DEV→main flow without an owner trigger (4-eye = Engineer→PM). The owner appears
only for the gated class above (PROD/release, repo-settings / branch-protection,
destructive infra).

### PM-orchestrator

- EPIC steer: scope, WP decomposition, pre-committed acceptance criteria.
- The 3 consult-exception responses (out-of-EPIC-scope, a better/alternative
  solution surfaced, a genuine external blocker).
- One merge validation per EPIC (produce ≠ adjudicate; the only retained
  routine check) **and the merge itself** — the PM is the merge authority for
  the engineer's reviewed DEV→main work, no owner trigger required. The PM may
  also build *and* merge its own lower-stakes work (CI / docs / config) —
  same-person build+merge is acceptable for the PM only; keep it low-stakes and
  loop the owner on anything risky (PM-own-work has no second pair of eyes).
- Staging-promote ceremony.
- Way-of-working coherence (this spine + downstream files stay consistent).

### Engineer-Principal

- Autonomous EPIC delivery within the steer + guardrails + Principal skills:
  plan, build, verify-locally, ship.
- Surfaces only the 3 consult-exceptions; otherwise does not block.
- Coordinates on the GitHub thread, never via the owner.

## Scaling the platform's agents

Growing the instance's agent fleet follows the same 7 principles — workflow
scaffold + bounded autonomy within a step, the augmented-atom as the unit,
evaluator ≠ producer at every tier, a single canonical tool surface, and a
falsifiable bundled eval per agent or it is not "done". The instance's concrete
agent-platform rules (its augmented-atom floor, the in-runtime-vs-cross-runtime
split, the tool surface) live in its overlay — the instance's are in
[`instance/<your-instance>/product-mapping.md`](instance/<your-instance>/product-mapping.md).

## Scope honesty

The spine is decided; that is not the same as the whole system reconciled.
Any unfinished reconciliation — files still describing a superseded protocol,
deep prose integration with the instance's ADRs and product vision, per-skill
bundled-eval builds still `status: TBD` — is **named work, tracked as a
deliberate follow-up, not silent debt**. An instance records its own
reconciliation status in its overlay; "the spine exists" must never be read as
"the agentic-sdlc is fully reconciled".
