---
title: Authority is the recorded event actor, never a prose signature
status: active
scope: scrum-master / quality-engineer / pm
added: 2026-08-03
last-confirmed: 2026-08-03
---

## Rule
A signature line in a comment ("— Nikita (scrum-master)") is self-asserted
text; nothing validates it. What **is** machine-checkable is the **event
actor**: the GitHub account that performed a label flip, a close, or a merge,
recorded in the issue timeline and PR metadata. A gate (QA verdict,
tested-flip, merge) counts only when its actor is a squad account; a
transition performed by a foreign account is a **violation to surface**, not a
state to build on.

## Why
- Prose signatures let any commenter claim any seat — invisible to every
  field, label, and roster query.
- With all seats sharing one account, the actor cannot distinguish seats
  *within* the squad (accepted trade-off) — but it fully catches the
  cross-squad case, which is the one that happened.
- No-code work-packages, where the verdict IS the deliverable, have no diff to
  fall back on; the adjudication trail is the entire artifact.

## How to apply
- SM merge preconditions include: the `status:tested` flip's actor is a squad
  account —
  `gh api repos/{owner}/{repo}/issues/{n}/timeline --jq '[.[] | select(.event=="labeled" and .label.name=="status:tested")] | last | .actor.login'`
- Foreign actor → do **not** merge; post the finding on the thread and surface
  to the PM.

## Cautionary tale
2026-08-03: three no-code work-packages were flipped `tested → merged` by
another squad's scrum-master on another squad's QA verdicts. The gating seat
appeared in no field, label, or roster — only in comment prose — and the
crossing surfaced only when the owner corrected the record.
