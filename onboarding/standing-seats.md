---
title: Standing seats — runnable autonomous launchers
status: stable
scope: framework
---

# Standing seats — make the autonomous loop *runnable*

[`MODES.md`](../MODES.md) and the [autonomous runners](../seats/engineer/autonomous-runner.md) describe
the standing-seat loop in prose: in `SDLC_MODE=autonomous` a producer/verifier seat *self-loops the
board* instead of waiting for a per-unit nudge. This file is the **mechanism** that makes it real — a
double-clickable launcher per seat, and the Stop hook that drives the loop.

## The shape — types enforced, names free

A seat is **one variable bag**: a worktree + its `.env.local`. The `SEAT_ROLE` is the **enforced type**
(it selects the role template *and* the loop behaviour); the `SEAT_NAME` is **free** — call your engineers
`Dex`/`Sam` or `alice`/`bob`, run one or five. There is no central roster to maintain: the squad is just
the set of configured worktrees ([`SQUAD.md`](../seats/SQUAD.md) is the *suggested* shape, not a mandate).

```
worktree/.env.local   →  seat-launch.sh   →  <name>.command   →  <Name>.app
 SEAT_ROLE (type)         the runtime         double-click         Dock/Finder icon
 SEAT_NAME (free)         title · identity     (1-liner →           (open →
 SEAT_LABEL (routing)     hook · claude         seat-launch)         the .command)
```

## The pieces

| File | Role |
|---|---|
| [`.env.local.example`](.env.local.example) | the per-seat config — type, name, routing label, board, optional board-ops token |
| [`seat-launch.sh`](seat-launch.sh) | **the runtime** — titles the window, runs `setup-seat.sh` (identity + the SessionStart brief), wires the Stop hook, launches `claude` in accept-edits mode |
| [`seat-loop-hook.sh`](seat-loop-hook.sh) | **the loop** — a Claude Code *Stop* hook: while the board has a next item for this seat it returns `{"decision":"block"}` and hands it over; drained → clean stop |
| [`make-launcher.sh`](make-launcher.sh) | generate a `<name>.command` for a worktree (trivial 1-liner → the runtime) |
| [`build-apps.sh`](build-apps.sh) | wrap `.command`s into `.app` bundles (cosmetic; the `.command` stays the source of truth) |

## How the loop works (the back-edges are deterministic)

After every turn Claude Code runs the Stop hook. It reads the Execution board and, **by role**, finds this
seat's next item:

- **producer** (`engineer`, specialists) → first `Status=Scoped` item carrying its `SEAT_LABEL`; instruction: *claim (atomic flip Scoped→In Progress) → build → ONE PR → Delivered. Never self-merge.*
- **verifier** (`quality-engineer`) → first `Status=Delivered` item; instruction: *verify on deployed env → PASS sets Tested, FAIL sets In Progress.*

If an item exists it **blocks the stop** and re-engages the seat with it; if not, it **exits clean** (the seat
idles, watchable, in its pane). Safety: it honours `stop_hook_active` (and Claude Code force-overrides after 8
consecutive blocks), exits clean on any tooling error rather than looping forever, and tells the seat to set an
item `Blocked` + post a `## Consult-exception` on a 3rd repeat (the dead-letter).

> The PM/orchestrator does **not** use this hook — it runs its own [autonomous runner](../seats/pm/autonomous-runner.md)
> (steer · dispatch · adjudicate · merge), which is judgement, not a board-watch.

## Quick start

```bash
# 1. configure each seat's worktree
cp onboarding/.env.local.example  ~/Code/proj-dex/.env.local      # set SEAT_ROLE/SEAT_NAME/SEAT_LABEL/BOARD_*
# 2. generate launchers (+ optional board-ops token for unattended runs)
onboarding/make-launcher.sh --worktree ~/Code/proj-dex --out ~/Code/agents/proj \
  --token-cmd "bash ~/Code/agents/proj/gh-app-token.sh"
# 3. (optional) wrap them as apps
onboarding/build-apps.sh --dir ~/Code/agents/proj
# 4. double-click Dex.app (or `open ~/Code/agents/proj/dex.command`)
```

## Rate note — give board ops their own quota

The loop reads the board (`gh project`, GraphQL) every turn. On the seats' shared personal token that
exhausts GitHub's 5,000/hr GraphQL quota and the loop stalls. For unattended runs, point `BOARD_TOKEN_CMD`
(or `--token-cmd`) at a command that prints a **GitHub App installation token** — board reads/writes then
run on the App's own quota, isolated from the seats.
