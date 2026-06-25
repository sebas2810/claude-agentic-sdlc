---
title: AgentCore-first design pattern
status: active
scope: engineer / pm
added: 2026-05-05
last-confirmed: 2026-05-30
---

> Stands under the ORBIS Agentic SDLC spine ([`../../../agentic-operating-model.md`](../../../agentic-operating-model.md)).

## Rule

**Anywhere we need learning curve, guardrails, or memory → use AWS Bedrock AgentCore.** Lambda-side Bedrock model invokes are reserved exclusively for genuinely stateless single-shot leaf transforms.

This is the durable design pattern for ORBIS. No per-PR debates about "should this be Lambda or AgentCore" — the rule answers it.

## When AgentCore is the right tier (ANY of these)

- Multi-pass / iterative reasoning (counter-extraction, multi-model ensemble, self-critique loops)
- Memory required (across passes, across sessions, across edits — feedback compounds quality)
- Tool access required (DB lookups, KB schema introspection, perceptual hash, web search, MCP tools)
- A2A composition (Composer → CompetitiveResponder → revised draft, etc.)
- Guardrails / Verifier checks against domain constraints
- Streaming progress events for live UI subscribers
- Confidence calibration that learns from steward feedback

## When Lambda Bedrock invoke is fine

- Per-page vision passes (high-throughput, latency-sensitive, truly stateless per page)
- Embedding generation (pure function — never agentic)
- Single-shot summary with no looping value
- High-throughput latency-sensitive batch transforms (~100s of invokes per ingest)

## When in doubt — default to AgentCore

The platform brings memory, A2A, MCP tools, sessions, native observability, identity-scoped IAM, code-interpreter, browser primitives — all features that compound. Lambda Bedrock invokes give us none of those.

## How this shapes new work

- New agent runtimes ship in `agents/` under the right project — never as a new Lambda Hono handler.
- New `@tool` definitions live in `agents/shared/tools/` (single canonical source) so both new + existing agents share interfaces (kb_search, knowledge_graph, document_upload, entity_dedup, find_similar_docs, compute_perceptual_hash, schema_introspect, kb_taxonomy).
- Lambda Bedrock calls that are about to grow loops / memory / tool-access → migrate to AgentCore BEFORE that growth (don't bolt state onto a stateless invoke).

## Reference architecture

The SummaryWriter migration (#751) is the reference. The MEDDPICC Foundation Agent (#805) extends the pattern. Look at:

- `agents/OpportunitySummary/` for the project shape
- `agents/OpportunityIntelligence/app/MeddpiccFoundation/` for the world-class shape (16 @tools, Memory binding, Strands graph + verifier loop)
- `agents/shared/tools/` for the shared tool surface

## Phased migration path

Issues #562 + #552 codified the migration in phases. Current state: most agents live on AgentCore; remaining Lambda Bedrock invokes are explicitly scoped to leaf transforms.

If you're proposing a new agent-shaped feature and considering Lambda — read this rule, then propose AgentCore. The Lambda path is the exception, not the default.

## Canonical worked examples

[ADR-0007](../../../../docs/decisions/adr/0007-lambda-leaves-vs-agentcore.md) (2026-05-30, WP-4 anchor) makes the rule mechanical: 9 yes/no questions, first YES wins. It walks through the two canonical worked examples:

- **Stays in Lambda:** `infra/lambda/api/lib/pdf-page-primitives.ts` — per-page vision pass, ~500 invocations per ingest, no state, no tool calls, no composition. Pure leaf.
- **Migrates to AgentCore:** `infra/lambda/api/lib/extract-entities.ts` — multi-pass extraction, memory-bearing, mid-flow tool calls (kb_taxonomy + find_similar_docs + schema_introspect), composes with VerifierAgent, streams to admin dashboard, carries confidence calibration. Trips all 6 AgentCore signals.

When a PR's placement is non-obvious, cite the ADR by number + paste the 9-question test results in the PR body. Reviewers adjudicate against the test, not first principles.
