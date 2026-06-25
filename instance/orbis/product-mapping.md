# ORBIS — product mapping

How the framework's 7 principles ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)) govern the **agents ORBIS ships** — the *product* half of the isomorphism. The framework spine carries the *process* (SDLC) column; this is ORBIS's product column. A fork writes its own `instance/<them>/product-mapping.md`.

## The 7 principles → ORBIS product

| Principle | ORBIS (the agents we ship) |
|---|---|
| **1. Workflow-first; agents only for genuinely open-ended work** | The 7-step MEDDPICC pursuit flow is a workflow with agent-staffed steps and a verifier, not an open agent loop. Open-ended autonomy is reserved for the steps that genuinely need it (research synthesis, narrative). |
| **2. Start simple; complexity must demonstrably pay** | AgentCore-first is the floor, not maximalism: a single augmented call ships until memory/tools/loops demonstrably improve the artefact. New agent tiers earn their place against an eval. |
| **3. The augmented LLM is the atom; compose, don't framework** | The ADR-0005 5-layer envelope (identity/skill, bound context, memory, tools, surface state) is the unit. We compose envelopes via Strands; we do not adopt an orchestration framework over them. |
| **4. Orchestrator-workers for unpredictable multi-step** | Research/solution flows fan out to specialist passes under an orchestrator; #985 granularity amendment keeps that fan-out in-runtime by default, cross-runtime only when an agent is independently scaled / multi-caller / own-lifecycle. |
| **5. Verify against the environment; evaluator ≠ producer** | The golden-judge runs deterministic, falsifiable, both-directions evals against artefacts; an agent never grades its own output (ADR-0006 no-false-green / produce≠adjudicate). |
| **6. ACI / tool design is first-class** | `agents/shared/tools/` is the single canonical tool surface; tool contracts get the same design rigour as prompts, never per-agent forks. |
| **7. Simplicity + transparency; human owns irreversible; explicit stop** | Every agent flow has a stated stop condition and surfaces its reasoning (streaming progress, provenance). Irreversible product moves (PROD, customer-facing publish) are human-owned. |

## Scaling ORBIS's own agents

Growing the platform's agent fleet follows the same 7 principles — rules, not aspirations:

- **AgentCore-first (augmented-LLM-as-atom).** Memory, guardrails, learning, or tool-access → AgentCore. Lambda Bedrock invoke is a stateless leaf only.
- **In-runtime multi-agent is the default; cross-runtime A2A only when an agent is independently scaled, multi-caller, or on its own lifecycle** (#985 granularity amendment). One reasoning flow is not split across network-isolated runtimes for organisational tidiness.
- **Workflow scaffold + bounded agent autonomy within a step**, not unbounded autonomy. An agent gets latitude inside a step whose entry and exit are defined; it does not own the whole flow.
- **Evaluator ≠ producer at every tier.** A self-critique loop inside one agent is not behavioural acceptance; the eval is run by something that did not author the output.
- **ACI via `agents/shared/tools/` as the single canonical surface.** No per-agent fork of a shared tool contract.
- **Every new agent ships a falsifiable bundled eval (ADR-0001) or it is not "done".** "Agent exists" is not "agent is eval-backed".
