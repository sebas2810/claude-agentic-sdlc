---
title: DEV frontend ECS is scaled-to-zero — smoke SHA probe false-positive
status: active
scope: engineer / pm
added: 2026-05-04
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../../agentic-operating-model.md`](../../../agentic-operating-model.md)).

## Rule

DEV's frontend ECS service runs at `desiredCount=0` for cost control. The smoke test's `EXPECTED_GIT_SHA` frontend probe **fails on every infra-only deploy**. This is **not a regression** — verify Lambda env directly instead.

## Why

- DEV serves only the engineering team; no need for always-on
- $0 cost when idle vs $X/day for keep-warm
- First-request triggers ECS scale-up via the wake mechanism

## The false-positive

When the smoke test polls `/api/orbis-version` and gets `gitSha: "unknown"`, that's the DEV scale-to-zero pattern — there's no ECS task to query. The smoke gate has a `FRONTEND_HAS_WARM_TASK` check that skips the SHA probe in this case (per #779 follow-up).

But on a DEPLOY that includes frontend changes (`FRONTEND_DEPLOYED=1`), the smoke test DOES wait for the task to come up — and if it doesn't (because nobody wakes the service), it eventually fails after the retry window.

This is a KNOWN PATTERN. Don't treat it as a regression.

## How to interpret a failed smoke on DEV

If smoke fails on DEV with "frontend SHA still does not match" and:
- The deploy ITSELF succeeded (CDK green)
- The Lambda SHA matches expected
- The frontend image was rebuilt + pushed to ECR successfully

→ This is the scale-to-zero false-positive. Verify Lambda is healthy via:

```bash
curl https://<api-gw>/api/health
# Should return 200 with version + gitSha matching expected
```

If Lambda is healthy → DEV is in good shape. The frontend just hasn't been woken.

## Wake DEV manually if needed

```bash
# Bump desiredCount to 1 (warms the service)
aws ecs update-service --cluster orbis-dev-frontend --service orbis-dev-frontend \
  --desired-count 1 --region eu-west-1

# Wait for steady state
aws ecs wait services-stable --cluster orbis-dev-frontend \
  --services orbis-dev-frontend --region eu-west-1

# Now /api/orbis-version returns the real SHA
```

## STAGING does NOT have this pattern

STAGING runs at `desiredCount >= 1` always (it's the soak environment). Smoke SHA probe failures on STAGING are REAL regressions, not the scale-to-zero pattern.

## When to actually fix this

Long-term, the SHA probe could be smarter — check ECS service state first, only probe `/api/orbis-version` if a task is running. The current `FRONTEND_HAS_WARM_TASK` skip is the partial fix. A full solution would be the [`aws ecs wait services-stable` pattern](../../../../scripts/smoke.sh) (PR #819) — pending sweep.

## Cautionary tale

Pre-rule: engineer-seat saw DEV smoke fail, panicked, started diagnosing a non-existent deploy regression. ~30 min wasted before someone said "oh, that's the scale-to-zero pattern, ignore." The rule prevents this.
