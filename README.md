# Agentic SDLC — a forkable framework

> **Capgemini IP — evaluation / non-production license.** This framework is the
> intellectual property of **Capgemini**, provided under a **royalty-free license
> for evaluation and non-production use only**. Production use is not permitted
> without a separate written agreement with Capgemini — for production licensing,
> contact Sebastiaan van Wijngaarden <sebastiaan.van.wijngaarden@capgemini.com>. See [`LICENSE`](LICENSE).


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

## First thing every session does (read order)

1. `CLAUDE.md` (repo root, auto-loaded)
2. `agentic-sdlc/README.md` — this file
3. `agentic-sdlc/agentic-operating-model.md` — **the spine**; all seat authority derives from it
   - `MODES.md` — manual vs **autonomous** mode (`SDLC_MODE`) · `workflow/state-machine.md` — the **stateless board state machine** both modes run on · autonomous PM runner: `seats/pm/autonomous-runner.md`
4. Your seat file (authority + work cycle + report protocol in one):
   - **PM** → `seats/pm/KICKOFF.md`
   - **Engineer** → `seats/engineer/KICKOFF.md`
5. `feedback/INDEX.md` (skim) · `learning-loop/CHANGELOG.md` (last few entries)
6. Engineer also: `skills/INDEX.md` (the skill model) + `instance/<your-instance>/skills/` — embody the matching Principal skill

## The seats

- **PM-orchestrator** (terminal) — frames + steers EPICs, decomposes work,
  pre-commits acceptance criteria, reviews + merges at the gate, owns docs +
  the board. Does **not** write product code.
- **Engineer-Principal** (Claude Code panel) — architect-level design + build
  within an assigned EPIC; branch-per-EPIC; report-then-stop after each unit.
  Does **not** touch the backlog / PM lane.

The **Owner** frames master EPICs and owns PROD. The full role model, the
8 SDLC phases, and the 8 invariants live in the spine.

## Per-seat setup — multiple seats on one machine

Each seat runs in its **own git worktree** with its **own identity**, so commits
and AWS/GitHub calls attribute correctly and never collide.

```bash
# 1. a worktree per seat
git worktree add -b feat/<epic> ~/Code/<your-repo>-<seat> origin/main
cd ~/Code/<your-repo>-<seat>

# 2. configure the seat
cp agentic-sdlc/onboarding/.env.local.example .env.local
$EDITOR .env.local      # SEAT_ROLE/NAME · GIT_USER_NAME/EMAIL · AWS_PROFILE · GH_TOKEN
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
├── agentic-operating-model.md ← the spine: roles · 8 phases · 8 invariants
├── engineering-standard.md    ← the generic production-ready floor (instances add their tiered standard)
├── onboarding/                ← new-pair-setup + per-seat config (.env.local, setup-seat.sh)
├── seats/                     ← the agentic squad: SQUAD.md roster + SEAT.template.md + a KICKOFF per seat
├── skills/                    ← the Principal-skill MODEL (structure + how-to)
├── learning-loop/             ← how rules are captured + the CHANGELOG
├── feedback/                  ← the portable (framework) rules, by area
└── instance/<your-instance>/            ← the instance-specific overlay: concrete skills + rules (fork = swap this folder)
```

## Fork it

To run this SDLC for your own product:

1. **Take the framework** — everything outside `instance/`.
2. **Replace the overlay.** Delete `instance/<your-instance>/` and create `instance/<you>/` with your own:
   - `skills/` — your Principal-grade engineer skills (the *model* is [`skills/INDEX.md`](skills/INDEX.md));
   - `rules/` — your stack-specific feedback rules (the portable ones stay in [`feedback/`](feedback/INDEX.md));
   - `engineering-standard.md` — your concrete tiered bar on top of the [framework floor](engineering-standard.md);
   - `product-mapping.md` — how the 7 principles govern the agents *your* product ships.
3. **Configure a seat** — `cp onboarding/.env.local.example .env.local`, fill it in, then `source onboarding/setup-seat.sh`. It sets the per-worktree identity and scaffolds the seat-identity file + SessionStart injection (native start).
4. **Wire the gates** — the framework rules are enforced by hooks under `.claude/hooks/` (no-push-to-main, no-AI-attribution, rebase-before-push, run-gates). Repoint any instance-specific paths at your overlay.
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
