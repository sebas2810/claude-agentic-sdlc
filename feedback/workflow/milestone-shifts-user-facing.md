---
title: Milestone shifts on master EPICs are ALWAYS user-facing
status: active
scope: pm
added: 2026-05-05
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

Never autonomously move an issue between milestones, **especially master EPICs**. Always surface as a recommendation; wait for explicit Sebastiaan approval before applying.

## Why

- Milestone is the strategic timeline visible to Capgemini leadership
- Master EPIC milestone shifts implicitly reschedule the programme
- Even small shifts ("just from v1.1.0 to v1.2.0") signal scope-slip to anyone watching the board
- Sebastiaan needs to be IN the decision, not informed after

## How to apply

When you find yourself about to do:

```bash
gh issue edit <n> --milestone v1.2.0    # changing existing milestone
```

STOP. Instead:

```bash
gh issue comment <n> --body "TOP PM call needed: milestone shift recommendation

Current: <milestone>
Proposed: <new milestone>
Reason: <why — be concrete; "scope grew" isn't enough>
Impact: <what leadership-facing surface changes>

Recommend: <do/don't shift>. Waiting for approval."
gh issue edit <n> --add-label "needs:top-pm"
```

## Setting milestone on a NEW issue

Setting an initial milestone when an issue is CREATED is fine — it's not a SHIFT, it's an initial assignment. Use your judgment + the EPIC's master programme as a guide.

## When the user has explicitly approved the shift in chat

Then it's just applying their decision. Confirm understanding in the comment:

```bash
gh issue comment <n> --body "Per Sebastiaan's call in <conversation reference>: 
shifting #<n> from <milestone-a> to <milestone-b>. <why>."
gh issue edit <n> --milestone <milestone-b>
```

## What counts as "master EPIC"

Issues with the `master-epic` label. The whole point of that label is to mark the strategic timeline view. Don't mess with their milestones casually.

## Cautionary tale

Pre-rule: PM-seat moved an EPIC from v1.0.0 to v1.1.0 milestone because it "didn't fit v1.0.0 scope anymore." Sebastiaan saw the move on the board hours later, asked why. The reason was reasonable, but the move-then-tell-later pattern made him spend a cycle interrogating something that should have been a 30-second pre-approval ask.
