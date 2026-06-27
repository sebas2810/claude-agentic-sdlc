---
title: Forward-port release-line hotfixes to main same-day
status: active
scope: engineer / pm
added: 2026-05-19
last-confirmed: 2026-05-19
enforced-by: FLOOR-4 gate (#1069) — infra/scripts/check-forward-port-convergence.ts
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

A hotfix merged directly to the active release line (`release/v*`, the
STAGING line) **must be forward-ported to `main` the same day** — not
"later." A release-only fix that never reaches main is a divergence that
explodes into a multi-file merge conflict the next time main promotes
into that release line (worse when a later main-side change rewrites the
same area).

- Hotfix → `release/v*` merge ⇒ open the forward-port-to-main PR the
  **same session**. Do not defer.
- Never "re-home" a release-only artefact on main by re-creating it with
  an identical Prisma migration name — converge it **at the source** (one
  migration / model / tool / route across both branches).
- A "designed clean" promote claim is **not** acceptance. Verify with a
  real trial merge (`git checkout -B _trial origin/release/v* && git
  merge origin/main --no-commit --no-ff`) before pushing any promote.
- Divergent same-feature carriage ⇒ a **source-level convergence PR**,
  not per-promote symptom patching.

Pairs with [`always-rebase-before-push.md`](always-rebase-before-push.md)
— rebase keeps the forward-port honest (no stale-base convergence).

## Why this is now an ENFORCED gate, not a convention

The discipline **broke 4× in one session** as a convention (EPIC #985
v1.9.0 promote blocked twice by the same un-forward-ported #961;
identical-migration-name re-home collision). Conventions that cost that
much get promoted to gates. **FLOOR-4 (#1069)** is that gate:
`check-forward-port-convergence.ts` runs on every `release/v*` push and
fails (red, actionable) unless every release commit has a **same-day
`git patch-id`-equivalent** on main — a real equivalence check, never a
label. Its both-directions self-test (`test-forward-port-convergence.ts`,
CI-runnable, no live release line) keeps the gate itself from silently
regressing to a no-op.

**Cautionary tale:** EPIC #985 v1.9.0 — two consecutive promotes blocked
by the same forward-port lapse from v1.6.x firefighting. The convention
held only because PM caught it by hand via trial-merge; FLOOR-4 removes
the reliance on catching it by hand.
