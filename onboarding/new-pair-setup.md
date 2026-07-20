# New Pair Setup - onboarding into the Agentic SDLC

> Root: the spine [`../agentic-operating-model.md`](../agentic-operating-model.md).
> Read it first - it is the model everything below operationalises.

A "pair" in the instance is **one PM seat + one engineer seat**, both Claude Code,
coordinating over GitHub. The human is the **owner**. This walks you through
getting productive in that model on day 1.

## The model in one paragraph

the instance is an agentic platform built by an agentic SDLC, both on one root
(Building Effective Agents). Delivery is a fixed-phase workflow: the **owner**
frames the master EPIC; the **PM-orchestrator** steers it (scope + WP
decomposition + pre-committed acceptance criteria); the **Engineer-Principal**
delivers the EPIC within that steer, embodying the Principal skills;
deterministic evals are the oracle for "done"; the QA seat verifies each unit
against its pre-committed AC (produce != adjudicate); the **SM** merges on a QA
PASS and runs the staging-promote ceremony (Merged → Released);
the owner owns PROD. The framework is **operator-driven** (a single mode): the
human is the orchestrator. Each seat is an interactive pane, idle until the
operator runs `/check` in it; then it **drains its queue** — reads the board
once, then handles every item eligible for its role in that snapshot (item →
report → next) until none remain, then idles. The drain is operator-initiated
and bounded by the work that exists now (one board read per `/check`); once the
queue is empty the seat stops re-reading the board — no self-loop, no board
polling, no idle-poll. The
pre-committed steer is what clears the build, so there is no per-unit "do X"
micro-gate; the engineer stops to consult the PM only for the **3
consult-exceptions** (out-of-scope, a better solution, an external blocker),
resolved on the GitHub thread.

## Quickstart — two commands

**Starting a new product?** Vendor the framework into it first (from a clone of
the framework repo — creates + inits the product repo if needed, stamps a root
`CLAUDE.md` + `.gitignore`, and **publishes the repo to GitHub** — bootstrap
requires the repo to exist there, because the labels, issues, and board live on
it; without `--repo`, commit and publish by hand before bootstrapping):

```bash
bash onboarding/vendor-framework.sh --into ~/Code/<your-product> --repo <you>/<your-product>
```

Then stand up the **entire instance** in one interactive command — the label
taxonomy (incl. the `status:*` routing index + per-seat `seat:*` lanes), one
Delivery project (Board + EPICS views), the standing epics, an optional guided
**first epic**, the **enforcement hooks** (PreToolUse git guard: no-push-to-main
· no-AI-attribution · rebase-before-push), one isolated git **worktree + seat
identity per role**, and a double-clickable **seat app** per role:

```bash
cd ~/Code/<your-product> && bash agentic-sdlc/onboarding/bootstrap.sh
```

All bespoke configuration lives in **one committed file at the product root:
`sdlc.config`** — instance, repo, owner, the seats as `role:Name` pairs
(optionally `role:Name:model` to pin a seat's Claude tier — defaults: pm +
quality-engineer → opus, others → sonnet), git
identity, AWS profile (never secrets — tokens go in each worktree's gitignored
`.env.local`). On first run a wizard asks for each value, **suggests a name per
seat** (Pim · Finn · Cas · Noor · Vera · …), writes `sdlc.config`, prints a
summary, and on your `yes` provisions everything. Every seat is then named
end-to-end: checkout `~/Code/<your-product>-<name>` on branch `seat/<name>`,
launcher + `.app` called `<Name>`. Re-runs read `sdlc.config` and are
idempotent (the board is reused, not duplicated) — edit the file + re-run to
change seats or identity, or `bootstrap.sh --yes` for non-interactive runs.
When it finishes, open a seat (double-click its `.app`, or `cd` its worktree and
run `claude`) and type `/check` to pull the first work item from the board.

**Steps 1–9 below are exactly what `bootstrap.sh` automates** — read them to
customize, to do it by hand, or to understand what got set up.

## Prerequisites

| Tool | Version | How |
|---|---|---|
| Claude Code | latest | `curl -fsSL https://claude.ai/install.sh \| bash` (https://claude.com/claude-code) |
| `gh` CLI | latest | `brew install gh` |
| `node` | 22.x | `nvm install 22` (or `brew install node`) |
| `git` | 2.40+ | `brew install git` |
| `jq` | 1.6+ | `brew install jq` — setup-seat's hook wiring + the git guard need it |
| AWS CLI | v2 | optional — for cloud diagnostics / the Bedrock route |
| VS Code | latest | **optional** — every seat runs in a terminal; an IDE is for the human reading code, never required by a seat |

Windows: run everything in WSL (Ubuntu) — the framework's scripts are bash.

## Step 1: Clone (or vendor)

New product? The vendor step in the Quickstart above already created + published
the repo — skip to Step 2. Joining an existing instance from another machine:

```bash
git clone git@github.com:<you>/<your-product>.git ~/Code/<your-repo>
cd ~/Code/<your-repo>
# npm install — only if YOUR product has a package.json; the framework itself needs none
```

## Step 2: Authenticate `gh`

```bash
gh auth login
gh auth refresh -s project   # gh auth login does NOT grant the project scope;
                             # boards fail without it. Scopes: repo, project, read:org, gist.
```

## Step 2.5: Configure the seat (worktree · git · AWS · gh isolation)

Each seat runs in its own worktree **named after the seat** (from the `SEATS`
`role:Name` pairs in `sdlc.config`), with its own identity, so commits and
AWS/gh calls don't collide across seats on one machine. `bootstrap.sh` creates
all of this; by hand, for one seat (say **Finn**, an engineer):

```bash
git worktree add -b seat/finn ~/Code/<your-repo>-finn main
cd ~/Code/<your-repo>-finn
cp agentic-sdlc/onboarding/.env.local.example .env.local
$EDITOR .env.local      # SEAT_ROLE=engineer · SEAT_NAME=Finn · GIT_* · AWS_PROFILE · GH_TOKEN
source ./agentic-sdlc/onboarding/setup-seat.sh   # per-worktree git identity + AWS/gh env + verify
```

`setup-seat.sh` sets a per-worktree git identity (never shared), exports
`AWS_PROFILE` (`<your-aws-profile>` today) + an optional `GH_TOKEN`, and verifies AWS resolves.
It then **starts the seat natively**: it scaffolds a per-worktree `.<instance>-seat.md`
(your identity + a self-route block) from the role template
(`seat.${SEAT_ROLE}.template.md`) and wires a SessionStart hook into this
worktree's `.claude/settings.local.json` (with the `agentic-sdlc` **plugin**
enabled, its own SessionStart hook does the same injection on every surface —
the local wiring then just double-covers the terminal), so every Claude session here boots with
your seat identity injected — no manual re-brief. Set its **steer line** to your
EPIC when you pick one up. The file is gitignored (per-worktree, never shared).

## Step 3: Two Claude Code sessions

Every seat is a terminal pane — one `claude` per seat worktree. (Prefer an IDE?
The Claude Code panel in VS Code works identically; optional, never required.)

**Prefer the Claude desktop app (or claude.ai/code)?** Install the
**`agentic-sdlc` plugin** once — it carries `/check` · `/board` · `/workload` ·
`/backlog`, the git guard, and the seat-brief injection to every Claude Code
surface, so opening the seat's worktree in the app gives you the full seat with
no launcher and no copied files:

```
/plugin marketplace add sebas2810/claude-agentic-sdlc
/plugin install agentic-sdlc@agentic-sdlc
```

(Or pin it per product repo via `extraKnownMarketplaces`/`enabledPlugins` in
`.claude/settings.json` — see the README's plugin section. One difference in the
app: the `--model` flag is a `seat-launch.sh` mechanism, so pick the seat's
model tier in the UI — the injected seat brief names the tier this seat is
configured for in `sdlc.config`.)

**Terminal 1 (PM seat):**
```bash
cd ~/Code/<your-repo>-pm
claude
# Auto-loads CLAUDE.md → read the spine, then seats/pm/KICKOFF.md
```

**Terminal 2 (Engineer seat):**
```bash
cd ~/Code/<your-repo>-engineer
claude
# Auto-loads CLAUDE.md → read the spine, then seats/engineer/KICKOFF.md
```

Both sessions launch **interactive** and stay idle until you run `/check` in a
seat — operator-driven: the seat then **drains its queue** — pulls its next
workload from the board, does it, reports, pulls the next from the same snapshot,
repeating until none remain for its role, then idles (`/board` is your overview).
They don't share memory - they coordinate via GitHub. The owner is never the relay between them
(spine invariant 7).

### Optional: one-click seat apps (instead of a bare `claude` window)

Once a seat's worktree is configured (Step 2.5), you can generate a **double-clickable
launcher + macOS `.app`** for it — a titled window ("Engineer - Dex"), the right
worktree + git identity, the operator commands auto-installed, and an interactive
operator-driven `claude`. You generate your **own** (the launchers hardcode local
paths, so they're never shipped pre-built — but the generators below ship with the framework):

```bash
# one .command per seat (run once per configured seat worktree)
agentic-sdlc/onboarding/make-launcher.sh --worktree ~/Code/<your-repo>-dex --out ~/Code/agents/<instance>
# wrap every .command in that dir into a double-clickable .app (macOS)
agentic-sdlc/onboarding/build-apps.sh --dir ~/Code/agents/<instance>
```

Double-click the `.app` (or `open <seat>.command`) to launch that seat. All runtime
logic lives in `seat-launch.sh`, so the app **inherits every framework update for free**
— no rebuild when the framework changes. (Drop a `icons/<seat>.icns` next to the `.command`
and re-run `build-apps.sh` to brand it.)

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
# (per instance/<your-instance>/rules/flip-epic-status-when-starting.md)
```

## Step 6: The delivery loop (phases 3-8)

**Engineer (Plan → Build → Verify, within the steer):**
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

**QA verifies → SM merges → SM releases:**
```bash
gh pr view <pr-#> --comments
gh pr checks <pr-#> --watch

# Phase 5/6: the QA seat verifies the item against the pre-committed acceptance
# criteria on the deployed env (Delivered → Tested). The SM then validates the
# gate STATE — item Tested, CI green, PR clean — and merges; the SM did not author
# the code → the independent check holds (produce != adjudicate). On a QA FAIL the
# item goes back Delivered → Scoped. NEVER merge a PR you wrote.
gh pr merge <pr-#> --squash --delete-branch

# Phase 7: the SM drives Merged → Released (staging + canary). PROD is the owner's.
```

The engineer does **not** merge its own PR — QA verifies and the **SM** merges (4-eye = Engineer → QA → SM).
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

## Step 8: Drain your queue, then stop

When the operator runs `/check`, **drain your role's eligible queue** — handle
each item, report, pull the next from the same board snapshot, repeating until
none remain — then **stop and idle**. The drain is operator-initiated and
bounded by the work that exists now (each unit still passes its gate). Stop at
empty: no polling loop, no `/loop`, no `ScheduleWakeup`, no idle re-reading once
your queue is clear, no self-merge. The human re-engaging for new work is the
system working. See
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
- **Smoke failing on DEV but Lambda looks fine?** [`../instance/<your-instance>/rules/dev-ecs-scale-to-zero.md`](../instance/<your-instance>/rules/dev-ecs-scale-to-zero.md)
- **Don't know what's next?** If you're the engineer mid-EPIC, the steer already cleared it - continue. If you hit a consult-exception, post it on the thread (not chat). The PM responds there.

## First week

- Day 1: setup + first small PR within a steered scope
- Day 2-3: deliver a real sub-EPIC end-to-end within the steer
- Day 4-5: run the full phase loop (steer → build → verify → adjudicate → staging)
- End of week 1: capture at least one feedback rule from your own learnings

If anything here is friction - file a `chore` issue ("onboarding friction:
<thing>"). The SDLC enables velocity; it is not bureaucracy.
