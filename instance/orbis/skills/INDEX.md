# ORBIS Principal Skills

The 5 Principal-grade operating standards the ORBIS engineer seat embodies while delivering a Master-EPIC — the *bar* it holds itself to when the work touches a domain, not personas. What a Principal skill *is* (structure, how-to, eval discipline) is the framework's [`../../../skills/INDEX.md`](../../../skills/INDEX.md); this is ORBIS's concrete set.

| Skill | Embody when the EPIC touches… |
|---|---|
| [Principal AWS Cloud Architect](principal-aws-cloud-architect.md) | CDK stack topology, Bedrock/AgentCore IAM, serverless data flow, cost ceilings, eu-west-1 deploy pipeline |
| [Principal Agentic Engineer](principal-agentic-engineer.md) | Strands graphs, AgentCore Memory/sessions/A2A, `agents/shared/tools/`, the 5-layer envelope |
| [Principal GenAI & Agentic AI](principal-genai-agentic-ai.md) | Model routing, prompt caching, eval design, guardrails/Verifier, RAG→V2 promotion, provenance |
| [Principal Data Science](principal-data-science.md) | Deal-signal modelling, MEDDPICC scoring + calibration, training-data extraction, model evaluation |
| [Principal Data Analytics](principal-data-analytics.md) | Corpus/quality dashboards, delivery telemetry, win/loss attribution, ingestion-health surfacing |

Often more than one governs a surface (a Strands graph writing to Aurora is both Agentic Engineer and AWS Cloud Architect). Hold the matching `## Operating standard` + `## Hard rules & refusals` as the floor; run the `## Decision checklist` before any "ready" signal — a failed check is a blocker, not a note.

**Bundled evals — honest status:** ADR-0001 (A3) requires each skill to ship a bundled falsifiable eval; **these five do not yet carry one** (`status: TBD (follow-up)` in each). "Skill exists" ≠ "eval-backed" — exactly the false-green (#985) these standards exist to prevent.

## Adding a skill

This catalog is **AWS-first and extensible**. To add a domain (e.g. Testing, Data & Pipelines, Reporting) or — later — another cloud, copy the framework template [`SKILL.template.md`](../../../skills/SKILL.template.md), drop the filled-in skill here, and add a row to the table above. Add a skill **when the engineer actually builds in that domain**, not before. See [`../../../skills/INDEX.md`](../../../skills/INDEX.md) → "Add your own skill".
