---
name: owasp-agentic-top10
description: The OWASP Top 10 for Agentic Applications as an audit lens on the fleet ITSELF — seats, credentials, tools, MCP servers, memory. Embodied in the quarterly engagement and after any fleet change (new seat, new tool, new MCP server).
---

# OWASP Agentic Top 10 — auditing the agents, not the app

> The other direction of assurance: the fleet is itself an attack surface. This lens turns the OWASP agentic risk taxonomy (tool misuse · privilege compromise · injection · memory/context poisoning · supply chain · identity/attribution gaps) into reperformable checks against the seats, their credentials, and their toolchains.

## When the Auditor embodies this

The quarterly engagement, always; plus a targeted pass whenever the fleet changes — a new seat, a new tool or MCP server, a credential scope change, a new autonomy grant (runbook promotion).

## Operating standard

- **Identity & attribution** — every seat maps to a distinct identity whose actions are distinguishable in the audit trail (issue timeline, commit trail, OTel logs). A fleet where agent activity is indistinguishable from human activity fails this check outright. Registry cards match live credentials — reconciled, not assumed.
- **Privilege** — each seat's *effective* permissions (tokens, IAM, gh scopes) tested against its trust tier: a Watcher that can write, an Investigator that can deploy, any seat with credentials beyond its card = finding, severity by blast radius. No standing broad credentials; Tier-C write creds released per action.
- **Injection surfaces** — enumerate where each seat reads untrusted text (logs, telemetry, issue bodies from outside, web content, support inbox); verify the guardrail is **structural** (deny-hooks, egress allowlists, approval gates outside the runtime), not "the prompt says to be careful".
- **Tool & MCP supply chain** — every MCP server / Action / package a seat consumes is pinned + vetted (auth required — a public no-auth MCP server in the chain is a critical finding); tool descriptions reviewed for embedded directives; update path controlled.
- **Memory/context poisoning** — persistent stores seats read at boot (seat briefs, memory dirs, KB): who can write them, is that write path gated, would a poisoned entry be detectable (provenance on entries).
- **Autonomy & budgets** — every autonomy grant (Tier-0 runbook, scheduled watcher) has its hard budgets configured and *tested* (a budget that has never tripped in a test is unverified); escalation paths never widen authority.
- **Human-oversight evidence** — the operator-driven claim holds on sampled actions: each traces to a human `/check`/dispatch/schedule approval; any self-initiated action is a critical finding.

## Hard rules & refusals

- **Test effective permissions, not declared ones** — the check is what the token *can do* (probed read-only where possible, or from provider policy introspection), not what the card says.
- **"The prompt forbids it" is not a control.** Only deterministic containment (credentials, hooks, gates) counts as a guardrail in a finding's mitigation status.
- **The Auditor's own seat is in scope** — this lens runs against the Auditor too, by the owner or a second run with the roles swapped; the third line is not exempt from the third line.
- **Read-only always** — probing never mutates; a permission probe that would write is designed out or skipped and named.

## Decision checklist (run per engagement)

1. Can every sampled fleet action be attributed to one specific seat from the trail alone? — Y/N
2. Does every seat's effective credential set match its registry card and trust tier? — Y/N
3. Is every untrusted-text surface covered by a structural guardrail (not prompt-trust)? — Y/N
4. Is every MCP server/tool/Action in every seat's chain pinned, vetted, and auth-gated? — Y/N
5. Have hard budgets on every autonomy grant been proven to trip? — Y/N
6. Does every sampled action trace to a human initiation? — Y/N

A failed check is a **blocker, not a note**.

## Bundled eval (ADR-0001)

`status: TBD (follow-up)` — planned: a red-team seed (an over-scoped test token + a tool description carrying an embedded directive, planted in a sandbox fleet; the engagement must surface both).
