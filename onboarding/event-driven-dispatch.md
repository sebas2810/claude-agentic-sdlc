---
title: Event-driven dispatch — the build-ready contract (hardening the autonomous loop)
status: spec (build-ready) — implements feedback/architecture/event-driven-orchestration.md
scope: autonomous mode · all standing seats
owner-gated: the GitHub App create/install + webhook secret (see github-app/SETUP.md)
---

# Event-driven dispatch — build-ready contract

> **What this locks.** The autonomous loop is **event-driven**: a board/PR transition
> is a GitHub event that **wakes** exactly one **standing pane** for one item; the seat
> acts once and idles. The **SM is the single board reader**; producers/Quality/PM never
> poll. This **re-aligns autonomous mode to the spine's [`finish-report-stop`](../feedback/workflow/finish-report-stop.md)**
> (no self-paced polling) — the re-engager is a **webhook event** instead of a human.
> Standing **panes only — never subagents** ([`MODES.md`](../MODES.md)).

This is the implementation contract for the **platform-infra WP** (engineer seat builds;
the PM adjudicates). The governing rule is [`event-driven-orchestration.md`](../feedback/architecture/event-driven-orchestration.md).

## 1. Seat lifecycle (the standing pane)

```
IDLE ──(event wakes me / I just finished a unit)──▶ DRAIN-CHECK (read MY inbox, $0)
   ▲                                                      │
   │  inbox empty                              item present│
   └──────────────────────────────────────────┐          ▼
                                               │   CLAIM (atomic: Scoped→In Progress + assign me)
                                               │          ▼
                                               └──── BUILD → REPORT → DRAIN-CHECK again
```

The after-work check reads the seat's **inbox**, never the board. A seat that runs
`gh project item-list` to find its own work is the **rejected N-way poll**.

## 2. Operational invariants (falsifiable — these are what "hardened" means)

| # | Invariant | Mechanism |
|---|---|---|
| O1 | **One GraphQL board reader, ever** (steady state) | only the SM reads the board; seats read inboxes |
| O2 | **No item ever orphaned** | at-least-once events **+** SM reconcile backstop |
| O3 | **At most one builder per item** | atomic claim: `Scoped→In Progress` + self-assign before build |
| O4 | **Bounded retries → parked** | 3rd repeat of one item → `Blocked` + consult-exception (dead-letter) |
| O5 | **Recover from board-as-truth** | boot reconcile resumes `In Progress`+no-PR; no private cursor |
| O6 | **Backpressure** | SM enforces WIP; a flood of events cannot overload a seat |
| O7 | **Rate-budget headroom** | per-seat App tokens (separate buckets) + single-reader |

## 3. The inbox (the cheap, local wake surface)

- **Location:** per-seat, machine-local (e.g. `~/.sammy-seat/<seat>/inbox/` or a named pipe) — **not** GitHub. Read cost = filesystem, $0 API.
- **Item shape (one file/line per item):**
  ```json
  { "item": 101, "seat": "dex", "action": "claim+build", "ac_ref": "#101 ## Steer",
    "epic": 245, "enqueued_by": "sm|webhook", "event_id": "<dedupe key>" }
  ```
- **Hook change:** `seat-loop-hook.sh` for `SEAT_ROLE ∈ {producer, quality-engineer, pm}` reads the **inbox** (not `gh project item-list`); item present → `block` + hand it over; empty → `exit 0` (clean idle). `SEAT_ROLE=scrum-master` keeps the board read (it is the one reader + dispatcher).

## 4. The dispatcher (event → inbox)

- **Source:** GitHub App webhook on `project_v2_item` · `pull_request` · `issues` (see [`github-app/`](github-app/)).
- **Map** the transition to the owning seat and write its inbox:

  | Transition | → inbox of |
  |---|---|
  | `→ Scoped` (PM-approved) | **SM** (dispatch) → then producer for its `seat:` label |
  | `→ Delivered` | **Quality** |
  | `→ Tested` | **PM** |
  | `pull_request` merged | **SM** (deploy→canary→Released) |

- **Idempotent:** dedupe by `(item, target_state)` / `event_id`; a duplicate webhook is a no-op (O2/O3).

## 5. Reconcile (the startup + periodic safety net — the SM owns it)

On **SM boot** and on a **slow, cache-aware tick** (~20–30 min, *not* a tight poll), the SM reads the board **once** and accounts for every in-flight item:

| Board state | Verdict | Action |
|---|---|---|
| `Scoped`, unassigned (e.g. **#101**) | Ready, never dispatched | push to seat inbox → wake |
| `In Progress` + open PR | being worked | leave |
| `In Progress`, no PR, stale | crashed/dropped | re-push → resume |
| `Delivered` | awaiting verify | ensure QA inbox has it |
| `Tested` | awaiting merge | surface to PM |
| 3rd repeat / wedged | dead-letter | `Blocked` + consult-exception |

**Seat boot is lightweight:** confirm seat → `git fetch origin main` → **drain inbox** (resume or idle). No board scan.

## 6. `/recheck` — the manual kick (bounded, not a loop)

- **`/recheck`** (any pane) → **one** reconcile pass (§5): read the board once, re-push stuck/new items to seat inboxes, report what was dispatched + what is legitimately idle. The manual equivalent of one reconcile tick.
- **`/recheck --me`** → this seat drains its own inbox once.

**Shipped** (machine-global skills in `~/.claude/commands/`, board #1/Nestor-Software):
`/recheck` (+`--me`) · `/board` (one-shot live snapshot, no poll) · `/dispatch <n>` (force-push one item to its owning seat's inbox) · `/wake <seat>` (fill a seat's inbox + print its relaunch command) · `/pause` + `/resume` (the `.paused` kill-switch the hook honours). Each is **one pass, report, stop** — never a loop.

## 7. Robustness evals (retire the `Bundled eval: TBD`s — these are first-class AC)

The runner docs currently end with `Bundled eval: status TBD`. The WP is **not done** until these exist and pass on a seeded board:

- **E1 (O1):** under an active-board cycle, exactly **one** process issues a Projects GraphQL read. *Fail:* any producer/QA/PM board read.
- **E2 (O2):** drop the `→ Scoped` webhook for an item → the reconcile still dispatches it within one tick. *Fail:* item stuck past a tick.
- **E3 (O3):** deliver the same `→ Scoped` event twice → exactly one claim/build. *Fail:* double-build.
- **E4 (O4):** force a unit to fail 3× → it lands `Blocked` + consult-exception, loop continues. *Fail:* infinite spin.
- **E5 (O5):** kill a seat mid-build (`In Progress`, no PR) → on relaunch it resumes that item, no duplicate. *Fail:* orphaned/duplicated.
- **E6 (rate):** a representative cycle completes with GraphQL budget margin > threshold, no 429.

## 8. Worked example — #101 (the acceptance trace)

`#101` is `Scoped · seat:dex · unassigned · no PR`. Under this contract: the `→ Scoped`
event (or the SM reconcile) writes `{item:101, seat:dex, claim+build}` to dex's inbox →
dex wakes, claims, builds → `Delivered` → QA → `Tested` → PM merge — **with dex never
reading the board.** If the built system can't unlock #101 untouched, it fails E1+E2.

## 9. What the WP changes (file map)

- `onboarding/seat-loop-hook.sh` — non-SM seats read the **inbox**, not the board.
- `onboarding/seat.engineer.template.md` · `seat.quality-engineer.template.md` · `seat.pm.template.md` — boot = confirm → fetch → **drain inbox** (no board-loop prose).
- `onboarding/seat-launch.sh` — wire the inbox + the wake-handler; boot prompt = reconcile/drain, not "run your board-loop".
- **new:** the dispatcher (webhook receiver) + the per-seat inbox + the `/recheck` skill.
- **new:** [`github-app/`](github-app/) — the App manifest + owner setup.

## 10. Owner-gated

Creating/installing the **GitHub App** + storing its **webhook secret** and per-seat
tokens — repo-settings/secrets. The PM frames; the owner ratifies + installs. See
[`github-app/SETUP.md`](github-app/SETUP.md).
