---
title: Don't artificially block on irrelevant CI
status: active
scope: pm
added: 2026-05-09
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

Fire parallel work the moment one piece's output stabilises. Don't wait on CI that doesn't affect the next step.

## Why

Today's workflow has lots of cross-piece CI: deploy-dev fires on every main merge, deploy-staging on release/v* push, smoke-tests on both, scoring-quality regression, README drift, agent type coverage, etc. Some are inputs to the next step; most aren't.

If you're waiting on a smoke test that's testing a frontend the next PR doesn't touch — you're blocking yourself.

## How to apply

Before declaring "blocked on CI":

1. Identify what the next action actually depends on
2. Check whether the currently-running CI is on that path
3. If not, FIRE the next action

Examples:
- Docs-only PR open, CI running → next PR doesn't depend on docs PR → don't wait
- Frontend hotfix on `release/v1.1`, deploy-staging running → next step is forward-port to main → main's deploy-dev is independent → don't wait
- Smoke test on STAGING is hanging on DEV scale-to-zero false-positive → real signal is the agentcore stack deploys (all green) → don't wait

## The opposite anti-pattern: skipping CI that DOES matter

This rule is NOT "skip CI you find inconvenient." It's "don't burn cycles on CI whose output doesn't gate your next move."

If CI is testing the thing you just changed, wait for it. If CI is testing something orthogonal, fire next work.

## Examples from today (2026-05-13)

- v1.1.0 deploy succeeded on STAGING (#811 hotfix landed). PM-seat opened the version-bump PR #810 immediately (didn't wait for an "OK to bump?" loop) — correct application.
- The DEV-frontend smoke false-positive on the v1.1.1 first attempt — would have blocked the PR merge incorrectly if we'd treated it as a real failure. Top PM marked PR #818 as merge-anyway after confirming the failure was the scale-to-zero pattern, not a real regression — correct application.

## When in doubt — diagnose the failing check

If CI is failing and you're not sure whether it's relevant:
1. Read the failed step's output
2. If it's a known false-positive (in our memory: scale-to-zero pattern), note + carry on
3. If it's a real failure, treat as a blocker

Don't silently `--admin` bypass. Always document why CI is being overridden.
