---
title: BEHIND is not DIRTY — at the merge gate, merge-ready PRs are never rebased because main moved
status: active
scope: scrum-master (and any seat holding a merge gate)
added: 2026-08-03
last-confirmed: 2026-08-14
---

## Rule
At the merge gate, a PR that is `MERGEABLE` but `BEHIND` merges **as-is** —
GitHub merges it server-side against the current tip, and a real conflict
would read `CONFLICTING`, not `BEHIND`. When a drain holds several ready
items, merge them **back-to-back, oldest-first, with zero rebases in
between**. The gate-holder's verbs are validate · merge · route — **rebasing
is authoring work and never yours**.

## Why
- Every rebase-for-BEHIND re-fires the **entire heavy gate chain** for zero
  information: the code didn't change, only its base pointer did. K ready PRs
  rebased-after-each-merge ≈ **K(K−1)/2 wasted full CI runs** — 3 PRs → 3,
  5 → 10, 8 → 28. That is the Actions bill, in one habit.
- Rebasing the *whole* remaining queue after each merge is the quadratic
  version: every in-flight CI run on a PR that isn't next is already garbage
  the moment its predecessor merges and flips it `BEHIND` again.
- `mergeable: MERGEABLE` is GitHub's own trial-merge verdict against the
  current tip — a second opinion via rebase adds nothing.

## How to apply
```bash
gh pr view <n> --json mergeable,mergeStateStatus
# MERGEABLE + CLEAN             → merge now (squash); no rebase, no waiting
# MERGEABLE + BEHIND            → merge now, UNLESS the base enforces a
#                                 strict required-status-checks policy (see
#                                 below) — under strict, BEHIND is a BLOCKING
#                                 state, not a mergeable one
# CONFLICTING / DIRTY           → route to the engineer (a real conflict)
# MERGEABLE + BLOCKED on a      → branch protection's strict up-to-date is
#   green, conflict-free PR        forcing the update: advance ONE PR at a
#                                  time (update only the next in line, never
#                                  the whole queue — linear, not quadratic),
#                                  and surface the CONFIG as a flow defect:
#                                  merge queue (one batched CI run per group)
#                                  · branch-per-EPIC (a drain should rarely
#                                  hold >1 main-targeting PR) · drop strict
```
### Check for a strict policy BEFORE trusting BEHIND

`BEHIND` merges as-is only when the base does **not** require up-to-date
branches. When `strict_required_status_checks_policy` is on, GitHub still
reports `BEHIND` (not `BLOCKED`) and the merge is simply refused — "add the
`--auto` flag" with every check green and no conflict is the tell.

**A 404 from the branch-protection API is not proof the branch is
unprotected.** Repository *rulesets* enforce the same constraints and are
invisible to that endpoint. Check both:

```bash
gh api repos/<o>/<r>/branches/main/protection --jq .required_status_checks.strict
#   404 "Branch not protected"  →  NOT conclusive, check rulesets:
gh api repos/<o>/<r>/rules/branches/main \
  --jq '.[]|select(.type=="required_status_checks")|.parameters.strict_required_status_checks_policy'
#   true  →  BEHIND is blocking; advance ONE PR at a time (as for BLOCKED)
```

Under a strict policy the anti-quadratic guidance is unchanged and matters
more, not less: update **only the PR being merged next**, never the whole
queue, and surface the config as the flow defect it is.

Decide on those two fields — never on GitHub's "update branch" button, and
never by reflex-applying [`always-rebase-before-push.md`](always-rebase-before-push.md),
which binds seats **pushing authored work**, not the gate.

## Cautionary tale
2026-08-03: an SM drained three independent main-targeting PRs serially —
merged the first, then rebased **both** remaining PRs (two full CI runs).
The moment the second merged, the third flipped `BEHIND` again: second
rebase, third full run — its first re-run bought nothing. One merge cost 3+
heavy CI re-runs; none of the three PRs ever conflicted with another.
