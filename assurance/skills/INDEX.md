# Audit Lenses — the assurance skill catalog

Same skill model as the [Principal skills](../../skills/INDEX.md), with one twist: an assurance skill is an **audit lens** — a published framework turned into falsifiable, reperformable checks the Auditor runs against a target. The framework's own question set is the point: findings cite the framework's item (pillar/risk ID), which is what makes them legible to external auditors and the industry.

| Skill | Lens | Audits |
|---|---|---|
| [`aws-well-architected.md`](aws-well-architected.md) | AWS Well-Architected Framework (6 pillars) | The **product** the loops build and run, where it runs on AWS |
| [`owasp-agentic-top10.md`](owasp-agentic-top10.md) | OWASP Top 10 for Agentic Applications | The **fleet itself** — seats, credentials, tools, MCP servers |

The two directions are deliberate: Well-Architected audits *what the agents made*; the Agentic Top 10 audits *the agents*. A full quarterly engagement runs both.

**Roadmap (add when an engagement first needs it, not before):** an ISO 27001 Annex A agent-scope lens (5.15–5.18 access · 5.3 SoD · 8.25–8.32 secure SDLC/change · 8.15–8.16 logging · 5.19–5.23 supplier) · a CSA AI Controls Matrix mapping · a mutation-testing lens for auditing AI-written tests (an assertion-free test still passes; the mutation score exposes it).

**Add a lens:** copy [`../../skills/SKILL.template.md`](../../skills/SKILL.template.md); the operating standard is the framework's own question set made falsifiable; every checklist item must name the evidence that would prove it and how to reperform the check. Honest-eval discipline applies.
