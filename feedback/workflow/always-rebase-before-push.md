---
title: Always rebase before every push
status: active
scope: engineer / pm
added: 2026-05-12
last-confirmed: 2026-05-20
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

Before EVERY `git push`, run:

```bash
git fetch origin main && git rebase origin/main
```

(Replace `main` with the appropriate base branch if you're pushing a hotfix or release-promote.)

## Why

Multiple engineers + sub-PMs work concurrently. `main` moves between when you started your branch and when you push. Without rebase:
- Your PR opens with an out-of-date base → CI uses stale workflow files
- Merge-conflict drama at squash-merge time
- "Mergeable: BLOCKED" because GitHub thinks you need to update branch

With rebase, your branch always shows up at the tip of current `main` and CI runs against the actual current workflow / dep state.

## How to apply

Make it a reflex before every push:

```bash
# Before EVERY push to a feature branch:
git fetch origin main
git rebase origin/main
# (resolve conflicts if any — better here than at PR-merge time)
git push --force-with-lease origin <your-branch>
```

`--force-with-lease` (not `--force`) — protects against overwriting someone else's push to your branch.

## When rebasing isn't needed

- First push of a brand-new branch (you just branched off latest main)
- Push to your own draft branch that no one else has touched

But making it a reflex covers both cases safely — `git rebase origin/main` is a no-op when you're already up-to-date.

## SPECIFICALLY: rebase immediately before flipping DRAFT → ready-for-review

Beyond every push, **the flip-to-ready moment is a hard rebase checkpoint** — see [`../../seats/engineer/KICKOFF.md`](../../seats/engineer/KICKOFF.md) §5 "rebase immediately before flipping a PR to ready".

The flip-to-ready is logically a *new contract with the PM* ("this PR is the version I want you to merge"). At that moment the contract must be satisfiable. If `main` moved between opening the PR (DRAFT) and flipping to ready — because a parallel PR landed during your work — the PM will hit `mergeStateStatus: BEHIND` on first merge attempt and have to ask you to rebase, adding a round-trip.

Pattern:

```bash
# CI green on your DRAFT PR
git fetch origin
git rebase origin/main
git push --force-with-lease origin <your-branch>
# Wait for CI to re-run green
gh pr ready <pr-number>      # flip-to-ready AFTER the rebase
# Post your unit-landed report (per your seat file's report protocol)
```

If rebase is a no-op (already up-to-date), you've cost yourself 10 seconds. If `main` moved, you've saved the PM-asks-for-rebase round-trip that costs 5–15 min.

### Order matters — commit BEFORE rebase, not git-add BEFORE rebase

`git rebase` refuses to run with uncommitted changes in the working tree or staged in the index. The full sequence when you have unfinished work that needs to ship:

```bash
# ✅ CORRECT — commit-then-rebase
git add <files>
git commit -m "..."
git fetch origin
git rebase origin/main
git push --force-with-lease origin <branch>

# ❌ WRONG — git-add-then-rebase
git add <files>
git fetch origin
git rebase origin/main                  # errors:
                                        #   "cannot rebase: Your index contains uncommitted changes"
                                        #   "Please commit or stash them."
```

If you hit the error, the safe recovery is `git stash` → `rebase` → `git stash pop` → `commit` → `push`. But the cleaner habit is to commit first, then rebase, then push — one straight line, no stash dance.

**Cautionary tale (2026-05-20, INTAKEV2 WS-B PR-2 prep)** — engineer ran `git add` then `git rebase` directly, hit the "index contains uncommitted changes" error, didn't notice / didn't re-run after committing, and pushed. Branch happened to be up-to-date by luck (nothing landed on main between the failed rebase and the push). Next time the luck won't hold; encode the order as muscle memory.

## Cautionary tales

**2026-05-08** — two engineers active concurrently. Engineer A opened PR off `main@deadbeef`. Engineer B merged their PR (`main` advanced to `cafe1234`). Engineer A pushed without rebasing → mergeable=behind → CI ran against stale workflow → smoke gate had a fix on it that wasn't being applied. Whole chain rebased + re-CI'd, ~25 min wasted.

**2026-05-20 (INTAKEV2 EPIC kickoff)** — both engineers (Sebastiaan WS-0/WS-B, Jonathan WS-I/WS-D) ran in parallel. Every single one of their first-shot PRs hit `BEHIND` on first PM merge attempt because the other engineer landed in between. The PM had to post a rebase ask on each PR, the engineer's session was in finish-report-stop, the human had to paste the trigger, then the engineer rebased + force-pushed, CI re-ran, PM finally merged. That round-trip on every PR added ~5–10 min of avoidable cycle time per merge. **The rebase-before-flip-to-ready rule above eliminates the entire pattern.**

The rule prevents both. Cost: 10 seconds of `git rebase` per push, including the implicit push when flipping to ready.

## After rebase, force-push correctly

```bash
git push --force-with-lease origin <branch>     # GOOD — protects against race
git push --force origin <branch>                # BAD — can overwrite collaborator's push
```

If you don't have collaborators on a feature branch, both are equivalent — `--force-with-lease` is just the safer reflex.

## Enforcement (promoted from prose to gate, 2026-06-12)

The `.claude/hooks/bash-guard.mjs` PreToolUse hook **blocks** any `git push` from a Claude Code session while the branch is behind `origin/main` — the BEHIND-at-merge class that hit every first-shot PR on the INTAKEV2 kickoff day can no longer reach the PM. Exceptions: `hotfix/*` branches (release-line based) are skipped; sub-PRs targeting a long-lived EPIC branch rebase onto that branch and re-run with `<INSTANCE>_CEREMONY_OVERRIDE=1`.

## Related enforcement (FLOOR-4, #1069)

This convention is the rebase half of release-line hygiene; the
forward-port half is [`forward-port-release-hotfixes-same-day.md`](forward-port-release-hotfixes-same-day.md).
Together they are now **enforced** by the FLOOR-4 gate
(`infra/scripts/check-forward-port-convergence.ts`): a release commit
whose main equivalent isn't a same-day, patch-id-equivalent forward-port
fails CI. Rebasing before push is what keeps that convergence from
landing on a stale base — skip it and FLOOR-4 surfaces the divergence
instead of a human catching it by trial-merge.
