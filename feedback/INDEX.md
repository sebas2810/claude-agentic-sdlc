# Feedback Index

Accumulated rules. Each is a short markdown file with a clear "why" and "how
to apply" so future sessions can apply them without re-deriving.

**The root every rule stands under** is the spine,
[`../agentic-operating-model.md`](../agentic-operating-model.md) (the ORBIS
Agentic SDLC). When a rule conflicts with the spine, the spine wins - raise a
`chore(playbook):` PR rather than diverging silently.

**To add a rule:** see [`../learning-loop/how-to-capture-a-rule.md`](../learning-loop/how-to-capture-a-rule.md).

**ORBIS-specific rules** (AgentCore-first, the AWS/Next.js gotchas, dev-environment practices, the Project-#4 status flip) live in the instance overlay: [`../instance/orbis/rules/`](../instance/orbis/rules/INDEX.md). This index lists the **portable framework** rules a fork keeps.

## Integrity / workflow rules (kept - load-bearing under the spine)

These are the rules the spine **keeps**. Confirmed and retained in the
2026-05-19 reconciliation; not rewritten unless noted.

| Rule | One-liner |
|---|---|
| [`workflow/always-pr-never-push.md`](workflow/always-pr-never-push.md) | All changes go through PRs; never push directly to `main` |
| [`workflow/no-claude-attribution.md`](workflow/no-claude-attribution.md) | Drop `Co-Authored-By: Claude` and "Generated with Claude Code" footers |
| [`workflow/branch-per-epic.md`](workflow/branch-per-epic.md) | One branch per EPIC; multi-phase work lands on one branch |
| [`workflow/deployed-env-smoke-before-ready.md`](workflow/deployed-env-smoke-before-ready.md) | Ready/landed report MUST include deployed-env smoke evidence |
| [`workflow/audit-pr-history-before-pickup.md`](workflow/audit-pr-history-before-pickup.md) | Check `gh pr list` before declaring an issue "unstarted" |
| [`workflow/always-rebase-before-push.md`](workflow/always-rebase-before-push.md) | `git fetch origin main && git rebase origin/main` before every push |
| [`workflow/forward-port-release-hotfixes-same-day.md`](workflow/forward-port-release-hotfixes-same-day.md) | Release-line hotfixes forward-port to main same-day - ENFORCED by the FLOOR-4 gate (#1069) |
| [`workflow/dont-block-on-irrelevant-ci.md`](workflow/dont-block-on-irrelevant-ci.md) | Don't artificially block on CI that doesn't affect the next step |
| [`workflow/repo-settings-via-pr.md`](workflow/repo-settings-via-pr.md) | Repo settings changes need explicit owner approval (owner-touchpoint) |
| [`workflow/milestone-shifts-user-facing.md`](workflow/milestone-shifts-user-facing.md) | Milestone shifts are owner-touchpoints (never autonomous) |
| [`workflow/run-oversight-gates-locally.md`](workflow/run-oversight-gates-locally.md) | Run local gates before push; never bypass |
| [`workflow/verify-wrap-up-scope.md`](workflow/verify-wrap-up-scope.md) | Verify wrap-up scope concretely; don't estimate "small" without checking each step |

## Workflow rules reconciled to the spine (2026-05-19)

Rewritten or pointer-updated to the de-gated, one-PM-seat model.

| Rule | One-liner | Reconciliation |
|---|---|---|
| [`workflow/finish-report-stop.md`](workflow/finish-report-stop.md) | Finish → one check → report → STOP and wait for the human (no loops, no polling); merge authority = 4-eye Engineer→PM (PM reviews + merges, no owner trigger; engineer never self-merges) | Light-confirm only on the no-loops part; merge-authority part refined 2026-06-15 to the 4-eye Engineer→PM model |
| [`workflow/engineer-ready-signal.md`](workflow/engineer-ready-signal.md) | After a unit lands, one report then continue the steered EPIC; no per-unit gate; no autonomous merge | Rewritten: per-unit "wait for next trigger" retired (steer-as-trigger) |
| [`workflow/pm-routes-via-github.md`](workflow/pm-routes-via-github.md) | The shared GitHub thread is the bus; the owner is never the relay | Rewritten to spine invariant 7; one PM seat |

## Superseded (archived 2026-06-12 → [`docs/archive/agentic-sdlc/`](../../archive/agentic-sdlc/))

| Rule | Superseded by |
|---|---|
| `engineer-no-unilateral-decisions` (archived) | Spine "steer-as-trigger" + [`../seats/engineer/KICKOFF.md`](../seats/engineer/KICKOFF.md). The per-unit "do X" trigger is retired; the engineer no longer waits between WPs on a steered EPIC |
| `engineer-seat-senior-architect` (archived) | The Principal skills ([`../skills/INDEX.md`](../skills/INDEX.md)) + the spine's Engineer-Principal role |
| _(removed 2026-05-19)_ | the autonomous seat-coordination-loop pattern was deleted - see `learning-loop/CHANGELOG.md` and `workflow/finish-report-stop.md` (named `standing-by-means-polling.md` until 2026-06-12) |

## Architecture rules (kept - hard constraints, confirmed not rewritten)

Violating these creates real bugs / outages. Each stands under the spine
(Principle 3: the augmented LLM is the atom; AgentCore-first).

| Rule | One-liner |
|---|---|
| [`architecture/no-silent-degradation-on-load-bearing-paths.md`](architecture/no-silent-degradation-on-load-bearing-paths.md) | Load-bearing swallow = defect: surface + health signal; schema-validate structured output pre-persist (FLOOR-2/3) |

ORBIS's stack-specific architecture rules (AgentCore-first, the `auth.ts` edge-runtime + Next.js slug gotchas) are in the instance overlay: [`../instance/orbis/rules/`](../instance/orbis/rules/INDEX.md).

## Operational rules

All operational rules are ORBIS-specific (DEV credentials, ECS scale-to-zero, the deploy circuit breaker) and live in the instance overlay: [`../instance/orbis/rules/`](../instance/orbis/rules/INDEX.md).

_(removed 2026-05-19: the autonomous seat-coordination-loop pattern — see `learning-loop/CHANGELOG.md` and `workflow/finish-report-stop.md`.)_
