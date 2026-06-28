---
name: event-driven-orchestration
type: architecture
---

# The board PUSHES — event-driven, never N seats polling

**Rule (owner mandate, 2026-06-28):** the autonomous loop is **event-driven**.
A board transition is a GitHub **event** that wakes **exactly one** seat — the one
that owns the next edge — for **that one item**; the seat acts once and stops.
**No seat runs a self-paced board poll.** The Scrum-Master is the **single** board
reader; every other seat (PM, Quality, producers) is **woken**, never polling.

> Prior versions permitted a "standing self-looping seat" that ran **its own**
> board-loop ([`MODES.md`](../../MODES.md)). With 4–5 seats each polling the
> Projects v2 board, that loophole **exhausted the shared GitHub rate budget and
> stalled the loop** (the 2026-06-28 GraphQL rate-limit incident). **Removed.**
> A standing seat may be a *visible, interjectable pane*, but it is **woken by an
> event/the SM — it does not poll.**

**Why polling is the wrong model (not just "too aggressive"):**

- **One shared budget.** Every seat acts as the **same** GitHub identity, so all
  of them draw from **one** per-user rate budget. N pollers × one budget = guaranteed
  exhaustion; "poll less often" cannot fix a structurally-wrong model.
- **The heaviest possible probe.** The Projects v2 board read is **GraphQL-only**,
  paginated, hundreds of points a call — the single most expensive thing to poll.
- **Cost *and* fragility.** Polling burns tokens + API budget while idle **and**
  stalls whenever a tick doesn't fire or nothing is watching a transition.

**The model — cheapest-first:**

1. **One reader, not N.** Only the **SM** reads the board. PM · Quality · producers
   do **zero** board polling — they are **woken** (the SM via `SendMessage`, or a
   board/PR event), as **standing panes** (never subagents — owner mandate), and act
   once. This alone takes load from N×heavy to 1×heavy and is
   the **immediate** mitigation (effective on the next seat relaunch).
2. **Push, don't poll (target).** A GitHub **App** + webhook / Action on
   `pull_request` · `issues` · `project_v2_item` pushes to a dispatcher that wakes the
   one owning seat. Polling frequency → ~0; the board is read only in response to a
   real change.
3. **Cheap probe, heavy read only on change.** Never use the Projects GraphQL query
   as a "did anything happen?" probe. Trigger on a **cheap REST** signal (PR state ·
   label · comment) — REST supports **conditional requests (ETag → `304`, which does
   not count against the limit)**, so an idle probe is *free*. Reserve the expensive
   board read for the one targeted moment after a probe says "something moved."
4. **Floor, only if polling at all:** backoff + jitter + a shared-budget guard, and
   **per-seat installation scoping** so seats stop cannibalising one budget.

**On the GitHub App (necessary, not sufficient):** the App **unlocks** the fix but
does **not** by itself resolve polling. As a *token swap* it only **moves the wall**
— one installation is **one shared bucket**, and an App's GraphQL budget is the same
order (~5k pts/hr) as a user's; N pollers still exhaust it. The App's real value here
is **webhook eligibility + dispatcher identity + least-privilege scoping** — i.e. it
is the **foundation for #2**, not a substitute for killing the N-way poll.

Edge → trigger → seat (who is woken):

| Transition | Event | Wakes |
|---|---|---|
| `→ Scoped` (PM-approved) | `project_v2_item` edited | **SM** — dispatch |
| `→ Delivered` | `pull_request` opened/ready | **Quality** — verify |
| `→ Tested` | `project_v2_item` edited | **PM** — adjudicate + merge |
| `pull_request` merged | `pull_request` closed-merged | **SM** — deploy → canary → Released |

**Rejected patterns (any of these = block at review):**
- A producer / Quality / PM seat running its **own** board poll loop (`/loop`,
  `ScheduleWakeup`, cron) to pull work — they are **woken**, not self-polling.
- More than **one** GraphQL board reader in steady state.
- Using the Projects v2 board read as a polling **probe** (use a cheap REST/ETag
  signal; reserve the board read for after a real change).
- Treating "switch every seat to a GitHub App token" as the fix while keeping the
  N-way poll (moves the wall, doesn't remove it).

**On-spine:** this **re-aligns autonomous mode to [`../workflow/finish-report-stop.md`](../workflow/finish-report-stop.md)** —
the spine already forbids self-paced polling / `/loop` / `ScheduleWakeup`; the autonomous
standing-seat poll violated it. Event-driven restores the discipline: a seat finishes, reports,
idles, and is re-engaged — by a **webhook event** instead of a human. Not a new rule; the existing
one, made operational.

See also: the build-ready contract [`../../onboarding/event-driven-dispatch.md`](../../onboarding/event-driven-dispatch.md) ·
the App foundation [`../../onboarding/github-app/SETUP.md`](../../onboarding/github-app/SETUP.md) ·
[`MODES.md`](../../MODES.md) (standing panes, never subagents) ·
[`../../seats/scrum-master/orchestrator-runner.md`](../../seats/scrum-master/orchestrator-runner.md)
(the single-reader SM) · [`../../seats/pm/autonomous-runner.md`](../../seats/pm/autonomous-runner.md)
(the PM never polls).
