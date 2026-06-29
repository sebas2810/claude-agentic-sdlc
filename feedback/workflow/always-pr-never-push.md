---
title: Always open a PR — never push directly to main
status: active
scope: all-seats
added: 2026-04-15
last-confirmed: 2026-05-13
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

All changes to `main` go through a PR. **Never** push directly to `main`. Repo history is 100% PR-based.

## Why

- Audit trail: every change is reviewable, comment-able, and version-history-traceable
- CI gate: PRs run the full CI matrix; direct pushes can bypass gates
- Coordination: GitHub is the single source of truth for what's in flight (per [`pm-routes-via-github.md`](pm-routes-via-github.md))
- Reversibility: PRs are revertable cleanly via `gh pr revert`; direct pushes are messier to undo

## How to apply

- Engineer: always work on `feat/*`, `fix/*`, `chore/*`, `hotfix/*` branches; open PR before merge
- Sub-PM / Top-PM: review PRs, squash-merge once CI green; never `git push origin main` directly
- The repo permission system blocks direct push to `main` for safety — if you hit a permission error trying to push to `main`, you've made a mistake

## Exception

`release/v*` branches accept direct pushes for release ceremony work (creating the branch from main, version bumps via release-promote PR). Even then, content changes go through PRs into the release branch.

## Enforcement (promoted from prose to gate, 2026-06-12)

The `.claude/hooks/bash-guard.mjs` PreToolUse hook (wired in `.claude/settings.json`) **blocks** any `git push` targeting `main` or `release/*` from a Claude Code session. The release-ceremony exception is the `<INSTANCE>_CEREMONY_OVERRIDE=1` override — SM staging-promote ceremony only (the SM drives `Merged → Released`).
