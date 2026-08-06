# The Agentic Assurance Model — the Assure spine

The [SDLC spine](../agentic-operating-model.md) governs building; the [Run spine](../operations/agentic-operations-model.md) governs operating. This spine governs **assurance**: independent, evidence-backed confirmation that both loops' gates actually hold — audit-grade, in the profession's sense of the word. On conflict within the Assure loop, this file wins.

## The thesis

The market's AI checkers (quality gates, AI reviewers, embedded scanners) are **line 2** — continuous monitoring inside the first line's workflow: same vendor, same loop, limited independence. Genuine **line 3** assurance is different in kind, not degree: independent context, deterministic reperformable evidence, reporting to the governing body, a human signature. An LLM's opinion — however good — is not audit evidence; what makes evidence audit-grade is the pipeline that produced it.

## The evidence bar (SAS 142 / GTAG, operationalized)

Evidence is admissible in a finding only if it is:

1. **Relevant** — it speaks to the control being tested, not adjacent to it.
2. **Reliable** — produced by a controlled pipeline: complete underlying data, with provenance (who/what produced it, when, from what inputs).
3. **Independent** — the producer of the evidence is not the subject of the finding. A seat's self-report is a *claim*; the board timeline, CI log, or metric that corroborates it is *evidence*.
4. **Reperformable** — a human (or external auditor) can re-run the cited check — the mutation score, the gate log query, the label-timeline query, the cost row — and get the same answer. LLM reasoning may *frame* a finding; a deterministic check must *ground* it.

Perception is not measurement: self-attestation by dev teams or their agents (velocity felt, quality believed) is never evidence — measured outcomes are.

## The independence rules (never relaxed)

| Rule | Concretely |
|---|---|
| **Independent context** | Own checkout of this framework (this directory is vendor-excluded from product repos), own worktree, own seat identity, opus tier. Never claims delivery or ops work. |
| **Reads everything, writes findings** | Read access to repos, boards, CI history, telemetry, the evidence store. Writes only: findings (`type:audit` issues on the target's board) and evidence packs. **No PRs to product code, ever.** |
| **Reports to the owner** | Not to the PM. Findings the PM disputes are adjudicated by the owner. |
| **Audits the monitors** | Lines 1–2 monitor continuously ⇒ line 3 tests the monitoring: sample released items and reperform their QA; verify "green" gates can actually fail; measure the Watcher's real alert precision. |
| **A human signs** | The seat drafts the report; the owner (or an external assessor) signs it. Agents do procedures; accountable humans conclude. |
| **Findings are work, not verdicts-in-place** | A finding becomes a framed item on the target's Delivery board; remediation flows through the normal Build loop and the Auditor **verifies closure** in the next engagement. |

## What the Auditor tests (the standing scope)

1. **Gate integrity** — produce ≠ adjudicate ≠ merge held on every sampled item; no self-approval; the merge trail traces to a real QA verdict by a different seat; any trusted-robot exception is documented.
2. **Verdict quality** — reperform a sample of QA PASSes on the deployed environment; a PASS that doesn't reproduce is a line-2 finding (the monitor, not just the item).
3. **Evidence infrastructure** — per-seat attribution present (who did what provable from the timeline); session/OTel logs retained per policy; the [agent registry](registry/README.md) current (card per seat, credentials match reality — a card that undersells a seat's actual permissions is a critical finding).
4. **Fleet security posture** — per the [OWASP Agentic Top 10 skill](skills/owasp-agentic-top10.md): credential scope vs card, MCP/tool supply-chain pinning, injection surfaces on seats that read untrusted text.
5. **Architecture & operations conformance** — per the [AWS Well-Architected skill](skills/aws-well-architected.md) where the instance runs on AWS: six pillars as falsifiable checks, including that cost ceilings and health signals *demonstrably fire*.
6. **Loop closure** — sev:1/2 post-mortems have loopback items and those items actually shipped; prior audit findings were remediated or explicitly accepted by the owner (an aging unremediated finding re-escalates).

## Cadence

- **Continuous** — evidence *collection* is infrastructure (CI artifacts, OTel export, board history streaming into the [evidence store](evidence/README.md)), not the seat's labor.
- **Per release** — an evidence pack assembled when an epic reaches `Released`: AC-to-verdict trace, gate evidence, deviations. Mechanical, cheap, mostly automated.
- **Quarterly** — the systemic engagement: sampled reperformance, monitor tests, SoD review, registry reconciliation, posture review — closed by a signed report.

## Framework anchoring (what "audit-solid" maps to)

The control shape targets **ISO 27001:2022 / SOC 2 with agents explicitly in scope** (non-human identities · SoD · secure SDLC & change management · logging/monitoring · the model vendor as supplier), with the **CISA agentic-adoption guidance + OWASP Agentic Top 10 + CSA AI Controls Matrix** as the technical checklists and **ISO/IEC 42001** practices layered on (impact assessment, supplier management, transparency) — certification when demand justifies it. The operator-driven mode is itself a control: **human-initiated, agent-executed** — every agent action downstream of a human `/check` is precisely the human-oversight evidence these frameworks ask for.

---
Auditor: [`seats/auditor/KICKOFF.md`](seats/auditor/KICKOFF.md) · Lifecycle: [`workflow/audit-lifecycle.md`](workflow/audit-lifecycle.md) · Evidence: [`evidence/README.md`](evidence/README.md) · Registry: [`registry/README.md`](registry/README.md)
