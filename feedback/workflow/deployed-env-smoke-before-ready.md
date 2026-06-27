---
title: Ready signal MUST include deployed-env smoke evidence
status: active
scope: engineer / pm
added: 2026-05-11
last-confirmed: 2026-05-13
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

Before declaring "ready" (engineer post-merge ready signal OR sub-PM post-deploy ready signal), include **deployed-env smoke evidence** — local CI green is NOT sufficient.

## Why

Local `next build` and `tsc` and unit tests pass on broken code regularly:
- **#820 Next.js slug conflict** (2026-05-13) — `next build` passed, runtime crashed on container boot
- **#743 → #746 edge-runtime regression** — same pattern, different surface
- **CFN drift / IAM permission gaps** — pre-deploy CDK synth passes, deploy fails on actual resource update

The only way to know the code WORKS is to deploy it and verify.

## How to apply

In every ready signal, include:

| Type of work | Required evidence |
|---|---|
| Code merged to main → DEV auto-deploys | DEV deploy-dev run URL + all jobs green |
| Release-promote to STAGING | deploy-staging run URL + smoke passed + auto-tag landed |
| Hotfix to release/v1.x | deploy-staging run URL + smoke passed + tag landed |
| Agent change | + CloudWatch trace showing the agent invoked successfully |
| Frontend change | + screenshot of the surface working on the target env |
| Docs-only | `docs-only, no deploy/smoke applicable` is sufficient |

## What the smoke step actually verifies

`scripts/smoke.sh` checks:
- API Gateway → Lambda → DB chain is alive
- Frontend ALB serves 200/redirects from the EXPECTED git SHA (not a prior version)
- Middleware doesn't crash on the edge-runtime bundle
- Migrations applied successfully

If any of these fail post-deploy, the ready signal is premature.

## When you skip smoke explicitly

If the deploy didn't touch a checked surface (e.g., docs-only deploy with `FRONTEND_DEPLOYED=0`), the smoke step skips that check by design. Note in the ready signal:

```
Smoke step: skipped — FRONTEND_DEPLOYED=0 (docs-only deploy, no ECS rollout to verify)
```

Don't claim "smoke passed" when it actually didn't run on the surface in question.

## When the smoke step fails on something unrelated to your work

E.g., DEV's scale-to-zero frontend pattern causes the SHA wait to fail per [`../../instance/<your-instance>/rules/dev-ecs-scale-to-zero.md`](../../instance/<your-instance>/rules/dev-ecs-scale-to-zero.md). Don't pretend smoke passed — explicitly note:

```
Smoke step: DEV frontend SHA wait failed (scale-to-zero false-positive, known pattern). 
Lambda smoke + opportunities-401 + middleware-alive all passed. 
Re-run on STAGING expected to be clean (no scale-to-zero there).
```

## Sub-PM verifies before forwarding

Before sub-PM forwards engineer's ready signal as "ship-ready", sub-PM verifies the deploy URL + tag + smoke step independently. Don't just trust the engineer's word; click the link.
