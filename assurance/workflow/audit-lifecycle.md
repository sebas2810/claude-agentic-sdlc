# The Audit Lifecycle — engagements and findings

Assurance work is organized as **engagements**, tracked as issues in the Auditor's own space (its framework checkout / a dedicated audit repo for multi-target setups), while **findings** land on the *target's* Delivery board — remediation is delivery work like any other.

## Engagement types

| Type | Trigger | Scope | Weight |
|---|---|---|---|
| **Release audit** | An epic reaches `Released` | That epic end-to-end: AC-to-verdict trace · gate evidence · deviations · touched surfaces through the [Well-Architected lens](../skills/aws-well-architected.md) | Light, mostly mechanical — the per-release evidence pack |
| **Quarterly systemic** | Calendar | Sampled reperformance of QA verdicts · monitor tests (can the gates fail?) · SoD review · [registry](../registry/README.md) reconciliation · [fleet posture](../skills/owasp-agentic-top10.md) · prior-findings closure | The full engagement, closed by a signed report |
| **Monitor audit** | A monitor's credibility is in question (e.g. a `Released` defect QA had passed) | The monitor itself: reperform its recent verdicts, test its failure mode | Targeted |
| **Fleet-change audit** | New seat · new tool/MCP server · credential change · autonomy grant | The delta, through the Agentic Top 10 lens | Targeted, fast — before the change beds in |

## Engagement states

`engagement:planned → engagement:fieldwork → engagement:reporting → engagement:signed`

Entry gates: **planned** requires scope + sample recorded up front (scope creep mid-engagement is recorded, not silent) · **reporting** requires every finding filed and evidence-linked · **signed** requires the owner's signature on the report — **unsigned = unissued**, and an engagement stuck unsigned >2 weeks is escalated, not forgotten.

## The finding flow (into delivery, back for closure)

1. Finding filed on the **target's** board: `type:audit` (+ `type:security` when applicable) · `status:backlog` · severity in the title (`[AUD-<engagement>-<n>][high] …`) · evidence-linked · citing the lens item (pillar / Top-10 risk / control).
2. The **PM frames it** like any backlog item (the Auditor set severity, not priority — WSJF is the PM's call, with `type:audit` + high severity as a strong CoD input).
3. Remediation flows Build-loop as normal — the Auditor **never** writes the fix.
4. **Closure is verified by the Auditor** in the next engagement (reperform the failed check), not assumed from the issue closing. Owner may instead **accept the risk in writing** — recorded on the finding, reviewed next quarter.
5. An unremediated, unaccepted finding aging past a quarter **re-escalates to the owner** — it never silently re-lists.

## Evidence packs

Every engagement produces a pack under [`../evidence/`](../evidence/README.md): the queries/commands run, their outputs, the sample, the report. Machine-checkable artifacts over prose — the pack is what an external auditor (or insurer) receives, and it is held to the same evidence bar the Auditor holds everyone else to.
