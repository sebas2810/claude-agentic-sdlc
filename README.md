# Agentic SDLC — a forkable framework

> **License: Apache-2.0.** Copyright © 2026 Capgemini. Open source — free to
> use, modify, distribute, and run in production under the terms of the
> [Apache License 2.0](LICENSE) (see also [`NOTICE`](NOTICE)). Contact:
> Sebastiaan van Wijngaarden <sebastiaan.van.wijngaarden@capgemini.com>.


An agentic software-delivery lifecycle: an **Owner**, a **PM-orchestrator**, and
**Engineer-Principal** seats — each a Claude Code session — ship a product
together under written rules and machine-enforced gates. The spine derives from
Anthropic's *Building Effective Agents*; the same principles govern the product
you build and the process you build it with.

**Two layers.** Everything at the top of this folder is the **generic framework**
(spine, seats, the skill model, learning-loop, onboarding + native-start, the
portable rules, the production-ready floor). [`instance/<your-instance>/`](instance/<your-instance>/)
is the **instance overlay** — the product-specific skills, rules, standard, and
product-mapping. **To fork: keep the framework, swap the overlay** (see *Fork it*
below). The reference instance lives under instance/<name>/.

> This folder is the single source for how the SDLC works. Everything here is
> live — no history, no old versions.

## Quickstart

Two commands from a clone of this repo to a running instance.

**1. Vendor the framework into your product repo** (creates + `git init`s it if
new, stamps a root `CLAUDE.md`; with `--repo` it also publishes the repo to
GitHub, which bootstrap needs — the labels, issues, and board live there):

```bash
bash onboarding/vendor-framework.sh --into ~/Code/my-product --repo <you>/my-product
```

**2. Stand up the whole instance** — labels (incl. the `status:*` routing index
+ `seat:*` lanes), one Delivery board, the standing epics, an optional guided
first epic, the enforcement hooks, a worktree + seat identity per **named seat**,
and double-clickable seat apps — with one command from the product repo:

```bash
cd ~/Code/my-product && bash agentic-sdlc/onboarding/bootstrap.sh
```

All bespoke choices live in **one committed file, `sdlc.config`** (instance ·
repo · seats as `role:Name` pairs · git identity · AWS profile — never secrets;
tokens stay in each worktree's gitignored `.env.local`). First run: a wizard
asks, **suggests seat names** (Pim · Finn · Cas · Noor · Vera · …), and writes
the file; each seat's checkout, branch, and `.app` are named after it
(`~/Code/my-product-finn`, `Finn.app`). Re-runs read the config and are
idempotent — edit `sdlc.config` + re-run to change anything, or run
`bootstrap.sh --yes` non-interactively (see
[`onboarding/sdlc.config.example`](onboarding/sdlc.config.example)).

It prompts for the repo, owner, seats, and git identity, then provisions
everything and prints how to start. Full walkthrough + the manual/by-hand steps:
[`onboarding/new-pair-setup.md`](onboarding/new-pair-setup.md).

### The seat tooling as a Claude Code plugin

This repo is also a **plugin marketplace**: the plugin ships the seat commands
(`/check` · `/board` · `/workload` · `/backlog`), the **git guard** (PreToolUse),
and **seat-brief injection** (SessionStart, reads the worktree's `.env.local`) —
versioned, on **every Claude Code surface**: terminal, the desktop app, web
(claude.ai/code), and IDE panels. Whoever prefers the Claude app over a terminal
just opens the seat's worktree there and has the full seat. Install once:

```
/plugin marketplace add sebas2810/claude-agentic-sdlc
/plugin install agentic-sdlc@agentic-sdlc
```

…or pin it per product repo so every seat gets prompted automatically —
`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "agentic-sdlc": { "source": { "source": "github", "repo": "sebas2810/claude-agentic-sdlc" } }
  },
  "enabledPlugins": { "agentic-sdlc@agentic-sdlc": true }
}
```

The legacy paths (commands copied to `~/.claude/commands`, the bootstrap-wired
guard hook) keep working and are superseded by the plugin where it is enabled;
updates flow by plugin version bump instead of re-vendoring. Provisioning
(`bootstrap.sh`) stays a shell script — the plugin is distribution, not setup.

## First thing every session does (read order)

1. `CLAUDE.md` (repo root, auto-loaded)
2. `agentic-sdlc/README.md` — this file
3. `agentic-sdlc/agentic-operating-model.md` — **the spine**; all seat authority derives from it
   - `MODES.md` — the **operator-driven** operating model (the single mode: the human orchestrates; seats pull work with `/check`) · `workflow/state-machine.md` — the **stateless board state machine** the seats run on
   - `workflow/` — the **process layer**: [state-machine](workflow/state-machine.md) (the 7 states) · [definition-of-ready-done](workflow/definition-of-ready-done.md) · [prioritization (WSJF)](workflow/prioritization.md) · [hierarchy](workflow/hierarchy.md) (Initiative→Epic→Story→Task) · [naming-conventions](workflow/naming-conventions.md) · [flow-metrics](workflow/flow-metrics.md) · [project-boards](workflow/project-boards.md) (Program ⇄ Execution)
4. Your seat file (authority + work cycle + report protocol in one):
   - **PM** → `seats/pm/KICKOFF.md`
   - **Engineer** → `seats/engineer/KICKOFF.md`
5. `feedback/INDEX.md` (skim) · `learning-loop/CHANGELOG.md` (last few entries)
6. Engineer also: `skills/INDEX.md` (the skill model) + `instance/<your-instance>/skills/` — embody the matching Principal skill

## The seats

- **PM-orchestrator** — oversight + product vision: frames + steers
  EPICs, decomposes work, pre-commits acceptance criteria, owns the roadmap +
  owner touchpoints + docs + the board, and resolves the rare product/scope
  judgment the QA seat surfaces. Does **not** write product code and is **not**
  the routine merge gate.
- **Engineer-Principal** — architect-level design + build
  within an assigned EPIC; branch-per-EPIC; report-then-stop after each unit.
  Does **not** touch the backlog / PM lane, and **never** self-merges.
- **Quality Engineer** — independent verification at the `Delivered → Tested` gate
  (produce ≠ adjudicate); reports a falsifiable verdict (PASS → `Tested`; FAIL →
  back to `Scoped` for the engineer to re-pull); never merges.
- **Scrum-Master / Flow** — the merge authority + board-mechanics seat: on a QA
  PASS it validates (real QA verdict, CI green, PR clean) and merges (squash) at
  `Tested`, then drives `Merged → Released`; it also explodes Epics into
  sub-issues, enforces WIP limits, sweeps, and surfaces to the PM. The SM didn't
  author the work, so merging holds produce ≠ adjudicate. Does **not**
  auto-dispatch or code (producers pull their own work via `/check`).

The **Owner** frames master EPICs and owns PROD. The full roster (+ specialist
build seats) is [`seats/SQUAD.md`](seats/SQUAD.md); the role model, the 8 SDLC
phases, and the 8 invariants live in the spine.

## Per-seat setup — multiple seats on one machine

Each seat runs in its **own git worktree** with its **own identity**, so commits
and AWS/GitHub calls attribute correctly and never collide. `bootstrap.sh` does
all of this for every seat in `sdlc.config`; the by-hand equivalent for one
extra seat (say **Finn**, an engineer):

```bash
# 1. a worktree per seat — named after the seat, on its own seat/<name> branch
#    (the epic branch comes later, at claim time — branch-per-EPIC off origin/main)
git worktree add -b seat/finn ~/Code/<your-repo>-finn main
cd ~/Code/<your-repo>-finn

# 2. configure the seat
cp agentic-sdlc/onboarding/.env.local.example .env.local
$EDITOR .env.local      # SEAT_ROLE=engineer · SEAT_NAME=Finn · GIT_* · AWS_PROFILE · GH_TOKEN
source ./agentic-sdlc/onboarding/setup-seat.sh   # per-worktree git identity + AWS/gh env + verify

# 3. launch
claude
```

`setup-seat.sh` sets a **per-worktree** git identity (via
`extensions.worktreeConfig` — never shared), exports `AWS_PROFILE` (which AWS
credential the seat uses — `<your-aws-profile>` today) and an optional `GH_TOKEN`, and
verifies AWS resolves. It then **starts the seat natively**: it scaffolds a
per-worktree `.<instance>-seat.md` (your identity + a self-route block) from the role
template and wires a SessionStart hook, so every Claude session in the worktree
boots with that identity injected — no manual re-brief. Full walkthrough:
[`onboarding/new-pair-setup.md`](onboarding/new-pair-setup.md).

## What's in this folder

```
agentic-sdlc/
├── README.md                  ← this guide
├── .claude-plugin/            ← plugin + marketplace manifests: the seat tooling as a versioned Claude Code plugin
├── agentic-operating-model.md ← the spine: roles · 8 phases · 8 invariants
├── MODES.md                   ← the operator-driven operating model (the single mode)
├── engineering-standard.md    ← the generic production-ready floor (instances add their tiered standard)
├── commands/                  ← the operator slash-commands: /check · /board · /workload · /backlog
├── workflow/                  ← the process layer: state machine · DoR/DoD · WSJF · hierarchy · naming · flow metrics · project boards (+ project-templates/)
├── onboarding/                ← bootstrap.sh (sdlc.config-driven) · vendor-framework.sh · create-instance.sh · setup-board.sh · seat-launch + launcher/app builders · hooks/ (git guard + session brief) · new-pair-setup.md
├── seats/                     ← the agentic squad: SQUAD.md roster + a KICKOFF per seat (PM · Engineer · Quality · optional Flow · specialists)
├── skills/                    ← the Principal-skill MODEL (structure + how-to)
├── learning-loop/             ← how rules are captured + the CHANGELOG
├── feedback/                  ← the portable (framework) rules, by area
└── instance/<your-instance>/  ← the instance-specific overlay: concrete skills + rules (fork = swap this folder)
```

## Fork it

To run this SDLC for your own product:

**Golden path** — `onboarding/vendor-framework.sh --into <your-repo>` then
`bash agentic-sdlc/onboarding/bootstrap.sh` inside it (the Quickstart above) —
bootstrap drives `create-instance.sh`, which scaffolds the overlay skeleton,
creates the [label taxonomy](workflow/project-templates/labels.json) +
the standing epics, and provisions the Delivery board from the
[templates](workflow/project-templates/). Then refine by hand:

1. **Take the framework** — `vendor-framework.sh` copies everything into
   `<your-repo>/agentic-sdlc/`.
2. **Replace the overlay.** Delete `instance/<your-instance>/` and create `instance/<you>/` with your own:
   - `skills/` — your Principal-grade engineer skills (the *model* is [`skills/INDEX.md`](skills/INDEX.md));
   - `rules/` — your stack-specific feedback rules (the portable ones stay in [`feedback/`](feedback/INDEX.md));
   - `engineering-standard.md` — your concrete tiered bar on top of the [framework floor](engineering-standard.md);
   - `product-mapping.md` — how the 7 principles govern the agents *your* product ships.
3. **Configure a seat** — `cp onboarding/.env.local.example .env.local`, fill it in, then `source onboarding/setup-seat.sh`. It sets the per-worktree identity and scaffolds the seat-identity file + SessionStart injection (native start).
4. **Wire the gates** — `bootstrap.sh` installs the shipped PreToolUse git guard
   ([`onboarding/hooks/guard-git.sh`](onboarding/hooks/guard-git.sh):
   no-push-to-main, no-AI-attribution, rebase-before-push) into your product
   root `.claude/` and stamps a root `CLAUDE.md` — commit both. Add your own
   instance-specific hooks (e.g. run-gates) alongside it.
5. **Grow it** — capture new lessons via the learning loop ([`learning-loop/how-to-capture-a-rule.md`](learning-loop/how-to-capture-a-rule.md)); on any conflict, the spine wins.

The framework is product-agnostic; only `instance/<you>/` is yours to write.

## The learning loop

When a session surfaces a durable lesson it's captured as a rule under
`feedback/` and logged in `learning-loop/CHANGELOG.md` (see
[`learning-loop/how-to-capture-a-rule.md`](learning-loop/how-to-capture-a-rule.md)).
Stale rules are pruned. The corpus is always the **current** truth, not an archive.

## Relationship to personal memory

This folder is **shared truth** (versioned, propagates on clone). Per-user
preferences live in `~/.claude/projects/<user>/memory/`. Read repo first,
personal second.
