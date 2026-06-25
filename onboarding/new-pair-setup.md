# New Pair Setup - onboarding into the ORBIS Agentic SDLC

> Root: the spine [`../agentic-operating-model.md`](../agentic-operating-model.md).
> Read it first - it is the model everything below operationalises.

A "pair" in ORBIS is **one PM seat + one engineer seat**, both Claude Code,
coordinating over GitHub. The human is the **owner**. This walks you through
getting productive in that model on day 1.

## The model in one paragraph

ORBIS is an agentic platform built by an agentic SDLC, both on one root
(Building Effective Agents). Delivery is a fixed-phase workflow: the **owner**
frames the master EPIC; the **PM-orchestrator** steers it (scope + WP
decomposition + pre-committed acceptance criteria); the **Engineer-Principal**
delivers the whole EPIC autonomously within that steer, embodying the
Principal skills; deterministic evals are the oracle for "done"; the PM does
**one** merge validation (produce != adjudicate); the PM runs the
staging-promote ceremony; the owner owns PROD. The steer is the trigger -
there is no per-unit "do X" gate. The engineer breaks autonomy only for the
**3 consult-exceptions** (out-of-scope, a better solution, an external
blocker), resolved on the GitHub thread.

## Prerequisites

| Tool | Version | How |
|---|---|---|
| Claude Code | latest | https://claude.com/claude-code |
| VS Code | latest | https://code.visualstudio.com/ |
| `gh` CLI | latest | `brew install gh` |
| `node` | 22.x | `nvm install 22` |
| `git` | 2.40+ | `brew install git` |
| AWS CLI | v2 | for ECS / CloudWatch diagnostics |

## Step 1: Clone

```bash
git clone git@github.com:sebas2810/orbis-platform.git ~/Code/capgemini-orbis
cd ~/Code/capgemini-orbis
npm install
```

## Step 2: Authenticate `gh`

```bash
gh auth login
# Your own GitHub identity. Scopes: repo, project, read:org, gist.
```

## Step 2.5: Configure the seat (git · AWS · gh isolation)

Each seat runs in its own worktree with its own identity, so commits and AWS/gh
calls don't collide across seats on one machine:

```bash
cp agentic-sdlc/onboarding/.env.local.example .env.local
$EDITOR .env.local      # SEAT_ROLE/NAME · GIT_USER_NAME/EMAIL · AWS_PROFILE · GH_TOKEN
source ./agentic-sdlc/onboarding/setup-seat.sh   # per-worktree git identity + AWS/gh env + verify
```

`setup-seat.sh` sets a per-worktree git identity (never shared), exports
`AWS_PROFILE` (`orbis-admin` today) + an optional `GH_TOKEN`, and verifies AWS resolves.
It then **starts the seat natively**: it scaffolds a per-worktree `.orbis-seat.md`
(your identity + a self-route block) from the role template
(`orbis-seat.${SEAT_ROLE}.template.md`) and wires a SessionStart hook into this
worktree's `.claude/settings.local.json`, so every Claude session here boots with
your seat identity injected — no manual re-brief. Set its **steer line** to your
EPIC when you pick one up. The file is gitignored (per-worktree, never shared).

## Step 3: Two Claude Code sessions

**Terminal (PM seat):**
```bash
cd ~/Code/capgemini-orbis
claude
# Auto-loads CLAUDE.md → read the spine, then seats/pm/KICKOFF.md
```

**VS Code (Engineer seat):**
```bash
code ~/Code/capgemini-orbis
# Open the Claude Code panel → read the spine, then seats/engineer/KICKOFF.md
```

The two sessions don't share memory - they coordinate via GitHub. The owner
is never the relay between them (spine invariant 7).

## Step 4: Read order (both seats, first session)

1. `CLAUDE.md` (auto-loaded)
2. `agentic-sdlc/README.md` - the SDLC index
3. **`agentic-sdlc/agentic-operating-model.md` - the spine. Read this
   before the seat files; everything derives from it.**
4. Your seat file (authority + work cycle + report protocol, all in one):
   - PM: `seats/pm/KICKOFF.md`
   - Engineer: `seats/engineer/KICKOFF.md`
5. `feedback/INDEX.md` - skim
6. Engineer also: `skills/INDEX.md` - embody the matching Principal skill for the surface

## Step 5: Get a framed EPIC

The owner frames a master EPIC (phase 1, owner-only). The PM then **steers**
it (phase 2): scope, WP decomposition, pre-committed acceptance criteria,
posted on the EPIC thread. **That steer is the engineer's trigger** - the
engineer does not wait for a per-unit go-signal after it.

```bash
gh issue view <epic-#> --json assignees,milestone,labels
# PM: flip Project #4 status to In Progress before the first PR
# (per instance/orbis/rules/flip-epic-status-when-starting.md)
```

## Step 6: The delivery loop (phases 3-8)

**Engineer (Plan → Build → Verify, autonomous within the steer):**
```bash
git fetch origin main
git checkout -B feat/<epic-#>-<slug> origin/main

# build the whole EPIC on one branch (branch-per-EPIC)
tsx infra/scripts/check-agent-readme-drift.ts
tsx infra/scripts/check-agent-type-coverage.ts

git fetch origin main && git rebase origin/main   # always rebase before push
git push -u origin feat/<epic-#>-<slug>
gh pr create --base main --title "feat(epic): #<epic-#> - <slug>" --body "<template below>"

# After a unit lands, post the report (not a request for a go-signal):
gh issue comment <epic-#> --body "Unit landed - <scope>. Smoke: <evidence>. Continuing on next WP."
```

PR body template:
```markdown
## What
<one-paragraph summary>

## Closes
- #<epic-#>

## Retires
<what gets removed; "Nothing - additive" if not>

## Test plan
- [ ] CI green
- [ ] Deployed-env smoke evidence (DEV)
```

**PM (Verify-as-oracle → Adjudicate → Release):**
```bash
gh pr view <pr-#> --comments
gh pr checks <pr-#> --watch

# Phase 5/6: evals are the oracle; the PM validates ONCE at merge against the
# pre-committed acceptance criteria. The PM did not author the code → it is
# the independent check (produce != adjudicate). NEVER merge a PR you wrote.
gh pr review <pr-#> --approve --body "Validated vs AC: <criteria checked>"
gh pr merge <pr-#> --squash --delete-branch

# Phase 7: staging-promote ceremony is the PM's. PROD is the owner's.
```

The engineer does **not** merge its own PR. The PM does the one validation.
There is no per-unit gating between WPs on a steered EPIC.

## Step 7: Consult-exceptions (the only stops)

The engineer breaks autonomy and posts on the thread only for:

1. **Out-of-EPIC-scope** - work drifted outside the steered EPIC
2. **A materially better / alternative solution** - surface before building it
3. **A genuine external blocker** - missing access, upstream defect, an
   undecided product question

The PM resolves these on the thread. If the resolution is itself an
owner-touchpoint (a product/strategic call), the PM surfaces it to the owner
with a recommendation - it does not become a relay through the owner.

## Step 8: Finish, report, stop

When a unit lands or an EPIC completes: one GitHub check, report to the
owner, **stop**. No polling loop, no `/loop`, no `ScheduleWakeup`, no
autonomous merge. The human re-engaging is the system working. See
[`../feedback/workflow/finish-report-stop.md`](../feedback/workflow/finish-report-stop.md).

## Step 9: Learning loop

End of session: a new pattern worth preserving → capture it per
[`../learning-loop/how-to-capture-a-rule.md`](../learning-loop/how-to-capture-a-rule.md)
as a `chore(playbook): add <rule>` PR. If a rule conflicts with the spine,
the spine wins - raise a `chore(playbook):` PR rather than diverging silently.

## Personal Claude Code memory (optional, per-machine)

Personal preferences live in `~/.claude/projects/<user>/memory/` (local-only).
Project rules go in the repo `agentic-sdlc/`, never personal memory.

## Troubleshooting

- **Claude Code didn't auto-load CLAUDE.md?** You're not at repo root / a recognized worktree.
- **PR CI failing on a check you didn't change?** [`../feedback/workflow/dont-block-on-irrelevant-ci.md`](../feedback/workflow/dont-block-on-irrelevant-ci.md)
- **Smoke failing on DEV but Lambda looks fine?** [`../instance/orbis/rules/dev-ecs-scale-to-zero.md`](../instance/orbis/rules/dev-ecs-scale-to-zero.md)
- **Don't know what's next?** If you're the engineer mid-EPIC, the steer already cleared it - continue. If you hit a consult-exception, post it on the thread (not chat). The PM responds there.

## First week

- Day 1: setup + first small PR within a steered scope
- Day 2-3: deliver a real sub-EPIC end-to-end within the steer
- Day 4-5: run the full phase loop (steer → build → verify → adjudicate → staging)
- End of week 1: capture at least one feedback rule from your own learnings

If anything here is friction - file a `chore` issue ("onboarding friction:
<thing>"). The SDLC enables velocity; it is not bureaucracy.
