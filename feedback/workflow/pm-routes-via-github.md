---
title: The shared GitHub thread is the bus; the human is never the relay
status: active
scope: pm / engineer
added: 2026-05-10
last-confirmed: 2026-05-19
reconciled: 2026-05-19 (to spine invariant 7; one PM seat)
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)) - this is the spine's **invariant 7** verbatim, applied.

## Rule

All inter-seat coordination flows through the **shared GitHub thread** (PR
comments, issue threads, labels). The **owner is never a message courier
between the PM and engineer seats**. Never hand the owner a chat message
saying "paste this to your engineer" - post it directly on the relevant
PR/issue. The owner appears only at the fixed owner-touchpoints
(master-EPIC framing, product/strategic, PROD), not as a relay.

## Why

- Searchable, auditable, async - replayable any time
- The other seat reads the thread when the operator runs `/check` in it (per
  [`finish-report-stop.md`](finish-report-stop.md) - no
  self-paced polling)
- The owner's cycles go to owner-touchpoints, not routine routing
- Future you, reviewing the EPIC, sees the FULL conversation in one timeline

## How to apply

**PM steering / directing the engineer:** `gh pr comment <n>` or
`gh issue comment <n>`. The EPIC steer itself is posted on the EPIC thread -
it is the engineer's trigger; there is no per-unit chat-paste.

**Engineer hitting a consult-exception:** comment on the same PR/issue (the
3 exceptions: out-of-scope, a better solution, an external blocker).

**Engineer's post-unit report:** comment on the issue/PR.

**PM hitting an owner-touchpoint:** post the one-line ask + recommendation on
the issue; the owner decides there. Not a chat-paste, not a relay request.

## What NOT to do

```
# BAD: handing the owner a paste-message / using the owner as a relay
"Here's what to tell the engineer:
'Continue Phase 3 §P-§S on feat/805-...'"
```

```
# GOOD: posting it directly on the thread
gh pr comment 821 --body "Steer: Phase 3 §P-§S in scope. Continuing."
```

## Cautionary tale

Pre-rule: every routing comment went through the owner's chat, who
copy-pasted between seats. Each routing → 3 sessions in the loop. The thread
is the bus: PM posts, the engineer reads it on GitHub. The owner is out of
the routine loop entirely.
