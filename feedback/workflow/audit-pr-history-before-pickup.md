---
title: Audit PR history before posting pickup signals
status: active
scope: pm
added: 2026-05-12
last-confirmed: 2026-05-13
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

Before declaring an issue "ready for engineer pickup" (or any "start work on #X" signal), check whether there's already a PR for it — open OR merged.

## Why

Open ≠ unstarted. An issue can be open while:
- A merged PR already addressed most of it (`Closes #X` reference linked it but didn't auto-close it)
- An open PR is in flight against it
- An engineer started it in another session and left a draft branch

Telling engineer "start #X" when there's actually a half-finished PR creates duplicate work + scope drift.

## How to apply

Before posting a "do #X" trigger:

```bash
# Check open + merged PRs referencing the issue
gh pr list --state all --search "<n> in:body,title" --limit 10 --json number,state,headRefName,title

# Check issue's auto-linked PRs
gh issue view <n> --json closedByPullRequestsReferences

# Check if an active branch exists for it
git ls-remote origin "*<n>*"
```

If any of these turn up something — investigate before triggering new work.

## Common failure modes the rule catches

| Symptom | Likely cause |
|---|---|
| Issue open, merged PR with `Closes #X` reference | Auto-close didn't fire (often because PR was rebased on a different base) |
| Issue open, open PR with `head: feat/<n>-*` | Work in flight, paused |
| Issue open, draft branch on origin, no PR | Engineer started locally, didn't push to PR yet |
| Stale tag-not-closed | Issue should be closed; this is just data-hygiene drift |

## Cautionary tale

2026-05-12 — Sebastiaan asked PM-seat to direct engineer to start #X. PM-seat posted the routing comment. Engineer started a fresh branch. ~20 min in, engineer noticed an open PR from earlier in the day with substantial work on the same issue. ~20 min lost; messy rebase.

Cost of the check: 10 seconds. Cost of skipping it: 20+ min per occurrence.

## When the check is genuinely fine

If you've JUST closed the prior PR yourself (you know the history), you can skip. The rule is for issues where you don't have full session context — which is most of them most of the time.
