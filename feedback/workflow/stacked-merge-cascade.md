---
title: Squash-merging a stack parent poisons every dependent — cascade immediately, or don't merge
status: active
scope: scrum-master (merge authority) + any seat authoring a stacked PR
added: 2026-08-13
last-confirmed: 2026-08-13
---

> Stands under the spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)),
> principle 6 (the merge mechanics are the SDLC's ACI) and invariant 5 (no
> silent-degradation — a stale-duplicate diff is a corrupted artifact that still
> looks mergeable).

## Rule

**Merge authority:** before squash-merging any PR that has open dependents based
on its branch, you own the **whole cascade as one atomic operation**:

1. Record the parent PR's `headRefOid` (GitHub keeps it) — this is the exact
   commit boundary.
2. Squash-merge the parent (`--squash --delete-branch`).
3. **Immediately** — before merging or touching anything else — for each
   dependent, in stack order:
   `git rebase --onto <new-parent-tip> <parent-headRefOid> <dependent-branch>`
   so each branch keeps **only** its own commits; then `push --force-with-lease`
   and retarget its PR base.
4. A dependent branch checked out in its owner's live worktree is **never**
   force-pushed by anyone else — post the exact rebase one-liner on the PR
   instead and stop the cascade there.

**Authoring seats:** a legitimate stack is **declared** — every stacked PR's body
says `Stack N/M — parent #X`. An undeclared dependent discovered at merge time is
a defect in the PR, not bad luck. Non-sequential work stays on sibling branches
off the integration-branch tip.

## Why

Squash-merge **rewrites** the parent's commits into one new SHA. Any dependent
still carrying the original commits now double-counts them against the new base —
the stale-duplicate diff. Retargeting the PR base **does not** fix it; only the
boundary-exact `--onto` rebase does.

The failure is quiet in the worst way: the dependent PR still opens, still shows
a diff, and still reports mergeable. What it shows is wrong.

**Why not "use merge commits inside integration branches instead":** that would
preserve ancestry, but the final integration→`main` merge then drags the
unsquashed noise into `main`'s history. Slice-level squash plus cascade
discipline keeps `main` clean and puts the cascade cost where it belongs — at
merge time, owned by the merge authority.

## Cautionary tale

Observed three times on a live instance before the rule existed — two separate
pairs on 2026-07-04 and a three-deep chain on 2026-07-06. Each time the parent
merged cleanly and the dependents were left carrying duplicated commits, which
surfaced later as a diff nobody could explain.

## Provenance

Written on a live instance and carried there as a local-only rule until
2026-08-13. Nothing in it is instance-specific — it describes `git` and GitHub
squash semantics, which every fork inherits.
