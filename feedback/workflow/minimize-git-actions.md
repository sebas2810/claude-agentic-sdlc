---
title: Minimize git actions — the workflow is efficient; don't brute-force around its load-bearing pieces
status: active
scope: all-seats
added: 2026-07-02
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

**A unit of work should cost ~3 git actions (branch · PR · push), not ~15–20.**
When you catch yourself running many `gh pr merge` / `gh pr update-branch` /
poll-loops, you've bypassed one of the workflow's load-bearing pieces — **fix
the piece, don't brute-force around it.**

## The four sources of git-action bloat (and the fix for each)

| Source | Symptom | Fix |
|---|---|---|
| **1. Per-PR merges to `main` (no EPIC branch)** | every merge bumps `main` → all other open PRs go `BEHIND` → `update-branch` → full CI re-run → poll → repeat (the "chase-main storm") | **EPIC integration branch created BEFORE the first sub-PR** ([`branch-per-epic.md`](branch-per-epic.md)). Sub-PRs land INTO it; `main` never moves mid-batch; one merge to `main` at the end. |
| **2. Agent poll-loops for CI** | `for i in 1..5; do gh pr view; sleep; done` — 5–10 reads per PR while waiting for green | Don't poll in a loop. Check **once**, let CI run, re-check on the next engagement. Prefer **label-triggered auto-merge** (a CI workflow merges tested+green PRs — zero agent git actions). |
| **3. The PM running merges** | PM runs `gh pr merge` / `update-branch` / polls because the SM is blocked | The **PM never runs git merge loops.** If the SM is blocked, fix the block (or ship auto-merge) — don't relocate the merge to the PM. Merges are SM- or CI-owned. |
| **4. Closing-keyword churn** | a prerequisite PR uses `Closes #<story>` → auto-closes the story prematurely → reopen → repeat | **`Refs #<story>` on prerequisite/infra PRs; `Closes` only on the completion PR.** ⚠️ GitHub matches `close #<n>` even inside *"Doesn't close #<n>"* — never write that phrase; use `complete` or `Refs`. |

## The target state

On an EPIC branch **with auto-merge live**: engineer pushes → QA labels
`tested` → the workflow merges. Nobody runs `gh pr merge`, `update-branch`, or a
poll loop. Per unit: **~3 git actions**, not 15–20.

## How to apply, per seat

- **Engineer:** branch off the EPIC branch (not `main`); one PR per unit; push and signal Ready — never merge.
- **QA:** read-only verification (`gh pr checks` / `view`) + the status flip; never `update-branch`, never merge.
- **SM (or auto-merge):** the *only* seat that runs `gh pr merge` — once per PR, `--squash --delete-branch`. Don't poll: if CI isn't green, route back and move on.
- **PM:** zero repo git actions. Frame, adjudicate, own the roadmap. If you're typing `gh pr merge`, something upstream is broken — fix that instead.

## Cautionary tale

2026-07-02, ORBIS substrate EPIC: ~20 sub-PRs merged **per-PR to `main`** (no
EPIC branch) + the **PM doing the SM's blocked merges** + prerequisite PRs using
**`Closes`** → an entire session of chase-main churn (dozens of
`update-branch`+poll cycles, and 3× close/reopen on one story). Owner: *"it
feels like we're running way too many git actions than required."* All four
sources were live at once; each has a clean structural fix above — and none is a
workflow-design flaw, they're bypasses of it.

Related: [`branch-per-epic.md`](branch-per-epic.md) ·
[`always-rebase-before-push.md`](always-rebase-before-push.md) ·
[`dont-block-on-irrelevant-ci.md`](dont-block-on-irrelevant-ci.md).
