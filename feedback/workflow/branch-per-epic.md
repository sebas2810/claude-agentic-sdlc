---
title: Branch-per-EPIC — one feature branch per EPIC, main touched once
status: active
scope: engineer / pm / sm
added: 2026-05-08
last-confirmed: 2026-07-21
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

**One feature branch per EPIC. `main` is touched exactly once per EPIC — by a PM-opened PR, at the end.**

### 🚧 THE RED LINE

**A single issue / work-package NEVER gets a PR to `main`. Only a whole EPIC does, once — and the PM opens it, not the engineer.**

This is the failure this rule exists to kill: agents opening one PR to `main` per issue, firing the full CI/gate chain N times per EPIC and sending every other open PR `BEHIND` into a "chase-main storm."

### Two conformant shapes — both keep `main` untouched until EPIC acceptance

- **Sub-branch per issue (preferred for multi-WP EPICs).** `wp/<issue#>-<slug>` off the feature branch, closed back **into the feature branch** — never into `main`. Gives each work-package its own revertable, reviewable unit.
- **All phases directly on the one feature branch** (fine for a small / linear EPIC). Push progress signals at phase boundaries; open no new PRs.

Either way: **one PR per EPIC to `main`, not N PRs per N sub-issues**, and the **PM** opens that final PR.

## Why this is enforceable, not just aspirational

In almost every CI setup the **heavy gate chain — build, tests, evals, security/leak audits, whatever your pipeline runs — is triggered by pull requests whose base is `main`.** A push to a feature branch, or a PR whose base is a *feature* branch, typically triggers little or nothing. **Verify this against your own workflows' `on:` triggers** — then the cost model is:

| Action | Heavy chain fired? |
|---|---|
| push / merge a sub-branch **into a feature branch** | usually **none** (no trigger watches feature-branch pushes) |
| PR whose base is a **feature branch** | at most your lightweight build/lint — not the full eval/audit chain |
| PR whose base is **`main`** | **the full chain** |

So intermediate work-package closures into the feature branch cost ~**zero** heavy-gate runs; the full chain fires **once**, at the single EPIC→main PR. Merging 8 issues to `main` separately can be 40+ workflow runs; the EPIC-branch model makes it one.

> If your CI exempts long-lived integration branches from a "rebase-before-push" guard via a registry file, **register the feature branch there at kickoff** so it isn't forced to constantly rebase on `main`. Note the coupling: if that same registry also drives which branches run the heavy gates, registering may fire those gates on sub-PRs — in which case close work-packages by **CLI merge (no sub-PR)** so the registration stays dormant until the EPIC→main PR.

## The commands

**1. Feature branch — PM/SM opens it ONCE, at EPIC kickoff:**
```bash
git checkout main && git pull
git checkout -b feat/<epic#>-<slug>
git push -u origin feat/<epic#>-<slug>
```

**2. Each issue = a sub-branch OFF the feature branch (engineer):**
```bash
git checkout feat/<epic#>-<slug> && git pull
git checkout -b wp/<issue#>-<slug>        # NOT nested under the feature branch name — ref collision
# ...work... then:
git add -A && git commit -m "feat(<scope>): #<issue#> — <what landed>"
```

**3. WP done → close it INTO the feature branch — zero/near-zero CI (engineer):**
```bash
git checkout feat/<epic#>-<slug>
git merge --no-ff wp/<issue#>-<slug>      # keeps the WP as one revertable unit
git push origin feat/<epic#>-<slug>       # fires nothing in a main-scoped CI setup
git branch -d wp/<issue#>-<slug>
```
> Optional — for a per-WP review record instead of a silent CLI merge:
> `gh pr create --base feat/<epic#>-<slug> --head wp/<issue#>-<slug>` and merge THAT into the
> feature branch. A feature-branch-based PR fires only your lightweight checks, never the full chain.
> **Never retarget it to `main`.**

**4. EPIC done → ONE PR to `main` — the PM opens it:**
```bash
gh pr create --base main --head feat/<epic#>-<slug> \
  --title "feat: EPIC #<epic#> — <title>" --body "...## Closes ...## Retires ..."
```
On green CI + QA PASS it merges to `main`. `main` moves **exactly once per EPIC.**

## Cautionary tale — the chase-main storm

A substrate EPIC once shipped as ~20 sub-PRs merged **per-PR directly to `main`** with no integration branch. Every merge bumped `main`, sending the other open PRs `BEHIND`; each then needed `update-branch` + a fresh full CI run + a poll loop before it could merge — an entire session of churn for what should have been one merge. The diagnosis was simply: *"we should have worked on a feature branch, not merged to `main` directly."* See [`minimize-git-actions.md`](minimize-git-actions.md) for the full breakdown.

## ❌ Never
- `gh pr create --base main` for a single issue / WP
- merging a sub-branch (or a WP-level PR) into `main`
- `git checkout main && git merge wp/...` — WPs never touch `main` directly
- the engineer opening the EPIC→main PR — that's the PM's step

## Multi-phase signals (not multi-PR)

Within a long-lived EPIC branch, post progress signals as comments on the EPIC issue instead of opening PRs:

```
## Phase N §X-§Y pushed
<what's in this commit>
Continuing on Phase N+1.
```

The PM/SM uses these to gauge progress without anything merging mid-branch.
