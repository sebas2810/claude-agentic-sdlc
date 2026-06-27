---
title: After a unit of work, one report then stop - no per-unit gating, no autonomous merge
status: active
scope: engineer
added: 2026-05-10
last-confirmed: 2026-05-19
reconciled: 2026-05-19 (de-gated to the spine; steer-as-trigger + finish/report/stop)
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

After a unit of work lands (PR merged, phase shipped, branch in main), the
engineer posts **one report** on the merged PR/issue, then **stops**. The
report is a handoff marker, not a request for a per-unit go-signal: the EPIC
steer already cleared the rest of the EPIC, so there is no "wait for the next
trigger" between WPs on a steered EPIC.

```markdown
## Unit landed - <one-line scope of what's in main now>

Deployed-env smoke evidence:
- Run: <github-actions-url>
- Tag landed: <vX.Y.Z @ sha>
- Smoke step: passed (or "skipped - explicit reason")

Next in this EPIC: #<n> (continuing) - or "EPIC complete, standing by".
```

Smoke evidence is mandatory per [`deployed-env-smoke-before-ready.md`](deployed-env-smoke-before-ready.md);
local CI green is not smoke.

## What changed (reconciliation)

The old rule made every unit a gated handoff: post a "ready for next pickup"
signal and **wait for an explicit per-unit "do X" trigger** from the sub-PM.
That per-unit gate is retired. Under the spine the **steer is the trigger**:
once the EPIC is steered, the engineer continues to the next WP without
waiting. The report still exists - for visibility and clean handoff - but it
does not pause delivery inside a steered EPIC.

## How to apply

1. Unit lands. Post the report (above) on the relevant PR/issue.
2. If the EPIC has more steered WPs: continue to the next one. No wait.
3. If the EPIC is complete, or you hit a consult-exception: that is where you
   stop and surface. Then do **one** GitHub check, report to the human, and
   **stop** - per [`finish-report-stop.md`](finish-report-stop.md).

## Hard limits (unchanged by de-gating)

- **No autonomous merge.** The engineer never merges its own PR. The PM does
  the one merge validation (produce != adjudicate).
- **No polling loop, no `/loop`, no `ScheduleWakeup`.** Finish, report, stop.
- **The 3 consult-exceptions still stop you**: out-of-EPIC-scope, a materially
  better solution, a genuine external blocker. Surface on the thread; the PM
  resolves there.
- A clarification or "looks good" is not a new steer and is not needed - you
  are already cleared by the original steer.

## Why

Per-unit gating produced over-direction / under-direction guessing and
ad-libbed parallel branches in the silence. The steer-as-trigger model
removes the guessing without removing the visibility: the report is the
handoff marker, the consult-exceptions are the only stops, and the human
re-engages for owner-touchpoints. See the spine's invariants 1, 7, 8.
