---
title: ECS deployment circuit breaker is the auto-rollback safety net
status: active
scope: all-seats
added: 2026-05-13
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../../agentic-operating-model.md`](../../../agentic-operating-model.md)).

## Rule

Both `Orbis-{Stage}-FrontendStack` and `Orbis-{Stage}-ApiEcsStack` have `circuitBreaker: { enable: true, rollback: true }` configured on the FargateService. When a deploy fails, ECS auto-rolls back to the previous task definition. **STAGING stays healthy on the prior version while we diagnose the failure.**

## What this means in practice

- A broken container image doesn't bring down STAGING
- We get an explicit failure signal (ECS event) instead of "stuck waiting"
- Smoke test sees the broken state + reports it
- We diagnose with the OLD version still serving — no time pressure

## How to read a circuit-breaker event

In the deploy-staging run log:

```
Resource handler returned message: "Error occurred during operation 
'ECS Deployment Circuit Breaker was triggered'." 
```

Then look at the timeline:

```
06:12:27  FargateService rollout started
06:20:35  ⛔ Circuit breaker triggered (~8 min retries exhausted)
06:21:17  Rollback complete — service back on prior TaskDef
```

The 8-min window is the default ECS retry budget. Adjustable via `deploymentConfiguration.deploymentCircuitBreaker.maximumPercent` if needed.

## What this WON'T save you from

- **Migrations applied successfully** → can't be rolled back automatically. If a migration is destructive + the deploy fails, you'll need a manual rollback migration.
- **Cross-stack updates** → CFN rolls back THE FAILED STACK, not other stacks that succeeded earlier in `cdk deploy --all`.
- **Auth / IAM changes that broke something downstream** → those are usually CFN-rolled-back, but the downstream effects might persist briefly.

## How to diagnose post-rollback

1. ECS Console → service → Events tab — failure events explain why tasks couldn't start
2. ECS Console → Tasks tab → filter stopped → click any → Logs — actual stderr from the failed container
3. CloudWatch logs at `/ecs/orbis-{stage}-frontend` or `/aws/bedrock-agentcore/runtimes/<id>-DEFAULT`

Use these to figure out the actual root cause. Today (#820 / 2026-05-13) the cause was a Next.js slug conflict at server boot — runtime error not caught by `next build`.

## Pair this with the smoke gate

Smoke test in `scripts/smoke.sh` checks for steady state AFTER cdk-deploy returns. With the circuit breaker, smoke test sees a DEFINITIVE state (rolled-back) rather than waiting indefinitely. The new PR #819 pattern uses `aws ecs wait services-stable` to enforce this explicitly.

## Cautionary tale (the opposite — without circuit breaker)

Pre-#742 / pre-rule: a broken frontend deploy could roll forward, kill the running service, leave STAGING in a half-deployed state requiring manual intervention. Cost: hours of debugging in a stressed state, with stakeholders watching.

With circuit breaker: today's 2026-05-13 v1.1.1 first attempt failed gracefully. STAGING stayed on v1.1.0. We diagnosed, fixed, redeployed. No user impact.

## Don't disable it

Whatever you do — don't disable the circuit breaker to "see what happens" or "force the deploy through." The safety net is the whole point.
