---
title: Branch-per-EPIC — one branch per EPIC, multi-phase work lands on one branch
status: active
scope: engineer / pm
added: 2026-05-08
last-confirmed: 2026-05-13
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

**One branch per EPIC.** All phases / sub-issues / §-blocks of an EPIC land on the same branch. One PR per EPIC, not N PRs per N sub-issues.

## Why

- Repo branch protection re-runs full CI on every merge — small PRs cost ~5× CI overhead
- Squash-merges cluster the EPIC's work into a single, reviewable commit on main
- The PR body's `## Closes` and `## Retires` sections are clean (one EPIC ⇒ one tree of changes)
- Reviewers can see the WHOLE thing in one place, not chase 4-5 PRs

## How to apply

- Engineer: when starting an EPIC, branch `feat/<epic-#>-<slug>` from `main`. Work all phases on that branch. Push progress signals at each phase boundary (not new PRs).
- Sub-PM: when reviewing, expect to see N phases on one branch. Squash-merge once the EPIC is complete (or at logical milestones if the EPIC genuinely needs multi-PR delivery — but that's the exception, not the default).
- Multi-PR is OK only for genuinely parallel work that can land independently (e.g., a P2 follow-up after the main EPIC ships).

## Cautionary tale

EPIC #683 (Discovery work) shipped as 4 separate PRs back-to-back. Each one fired a full CI cycle. Each one had its own merge-conflict drama. The squash-merges produced 4 commits on main that *should* have been one. The lesson: branch-per-EPIC is faster overall, even when "one PR per sub-issue feels more atomic."

## Multi-phase signals (not multi-PR)

Within a long-lived EPIC branch, post progress signals as comments on the EPIC issue:

```
## Phase N §X-§Y pushed
<what's in this commit>
Continuing on Phase N+1.
```

Pattern from PR #805 / #821. Sub-PM uses these to gauge progress without merging mid-branch.
