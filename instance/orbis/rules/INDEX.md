# ORBIS-specific rules

The accumulated rules that apply to **ORBIS's stack + practices** — what a fork *replaces*. The portable framework rules (PR-not-push, rebase, no-AI-attribution, finish-report-stop, no-silent-degradation, deployed-env-smoke, branch-per-EPIC, …) stay in the framework at [`../../../feedback/`](../../../feedback/INDEX.md).

## Architecture (ORBIS stack)
| Rule | One-liner |
|---|---|
| [agentcore-first.md](agentcore-first.md) | Memory / tools / guardrails → AgentCore; Lambda Bedrock = stateless leaves only |
| [auth-ts-edge-runtime-constraint.md](auth-ts-edge-runtime-constraint.md) | `auth.ts` top-level imports must be edge-runtime compatible |
| [nextjs-slug-runtime-check.md](nextjs-slug-runtime-check.md) | Next.js slug-name conflicts fire at server start, not `next build` |

## Operational (ORBIS DEV / AWS)
| Rule | One-liner |
|---|---|
| [dev-credentials.md](dev-credentials.md) | DEV credentials are isolated blast radius — flag once, then drop |
| [dev-ecs-scale-to-zero.md](dev-ecs-scale-to-zero.md) | DEV frontend ECS at desiredCount=0 for cost; the smoke SHA probe false-positives |
| [circuit-breaker-as-safety-net.md](circuit-breaker-as-safety-net.md) | ECS deploy circuit breaker auto-rollback protects STAGING — don't disable |

## Workflow (ORBIS tooling)
| Rule | One-liner |
|---|---|
| [flip-epic-status-when-starting.md](flip-epic-status-when-starting.md) | Move Project #4 row to `In Progress` BEFORE the first PR |

> `run-oversight-gates-locally.md` is ORBIS-flavoured too but stays in the framework `feedback/workflow/` because the enforcement hooks reference its path — it generalises when the hook paths are batched (a later stage).
