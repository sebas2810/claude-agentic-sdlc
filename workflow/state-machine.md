---
title: The SDLC State Machine — a stateless workflow over the GitHub board
status: active
scope: all-seats
---

# The SDLC State Machine

> **The board *is* the state. Each seat is a pure function of the board.**
> No hidden state, no in-memory drift — interrupt a seat and it resumes from
> the board; the operator watches the *same* board the seat reads.

This is the foundation the operator-driven model (see
[`MODES.md`](../MODES.md)) runs on. The states live on the **GitHub Project `Status`
field**; the transitions are the workflow. It makes invariant 7 ("the shared
thread is the bus") literal — the board is the bus, and no seat holds a private
copy of where the work is.

The state machine governs **Stories and Tasks** (the execution items). Epics and
Initiatives don't run the 7 states — they're tracked by **sub-issue progress** in
the **EPICS view** of the same project ([`project-boards.md`](project-boards.md));
the hierarchy that connects them is [`hierarchy.md`](hierarchy.md).

## The 7 states (+ Blocked · Cancelled)

The canonical `Status` options, in board order. The entry gate of each is its
slice of the [Definition of Ready / Definition of Done](definition-of-ready-done.md) —
DoR gates the entry to `Scoped`, a per-state DoD gates every later transition.

| # | State | Means | Entry signal | Gate to enter (DoD of the prior step) |
|---|---|---|---|---|
| 1 | **Backlog** | exists, not yet steered (no committed AC) | issue created | — (DoR not yet met) |
| 2 | **Scoped** | PM-steered — scope + **pre-committed acceptance criteria**; **DoR met** | the steer comment is posted | **Definition of Ready** (scope, AC, sized, parented to an Epic) |
| 3 | **In Progress** | a seat is building it; a branch exists | the producer pulls it via `/check` | a free WIP slot (see *WIP limits*) |
| 4 | **Delivered** | a PR is open + the ready-signal posted; awaiting verification | `gh pr ready` + `## Unit landed` | local gates green + a real DEV round-trip |
| 5 | **Tested** | **independent** verification PASS against the pre-committed AC (Quality seat / evals) — the assurance gate | the verification report posts PASS | **evals are the oracle**, deployed-env, perturbed happy path |
| 6 | **Merged** | adjudicated + squash-merged to `main` | PR merged | **produce ≠ adjudicate**, once, by the non-author at the gate |
| 7 | **Released** | deployed to the target env + verified there (canary → promote); issue closed | deploy + post-deploy check green | **canary before irreversible**; PROD is owner-gated |
| — | **Blocked** | a consult-exception or owner-touchpoint is pending | `## Consult-exception` / owner-tag | the 3 consult-exceptions / the owner-gated class |
| — | **Cancelled** | closed **without shipping** — duplicate · won't-do · obsolete · premise-invalid; the board mirror of GitHub's `NOT_PLANNED` close | `gh issue close --reason "not planned"` | the non-success terminal — never parked in `Released` ([rule](../feedback/workflow/cancelled-status-state.md)) |

Two deliberate properties of this ordering:

- **`Tested` precedes `Merged`.** The independent check runs on the *delivered PR*
  (a real DEV round-trip on its branch), so a defect is caught **before** it
  reaches `main` — not after. This is the Quality Engineer seat's state
  ([`../seats/quality-engineer/KICKOFF.md`](../seats/quality-engineer/KICKOFF.md));
  where no Quality seat is staffed, the deterministic evals are the oracle and the
  SM confirms them at the merge gate.
- **`Released` is its own state, owner-gated at PROD.** Merging to `main` is the
  SM's routine authority (it did not author the work, so produce ≠ adjudicate
  holds); pushing the irreversible release is the owner's. Keeping them as two
  states keeps that boundary legible on the board.

## Definition of Ready / Done (the gates between states)

Every transition has a **gate** — a falsifiable exit condition (DoD) of the step
it leaves. The full checklists live in
[`definition-of-ready-done.md`](definition-of-ready-done.md); the load-bearing
ones are named in the table above. A transition with an unmet gate **does not
fire** — the item stays where it is (or goes `Blocked`), never advances on
optimism. "It produced output" is never a gate; a gate is an eval, a green check,
or a met AC line with evidence.

## WIP limits (flow, not utilisation)

Pull-based, not push-based: a seat pulls its next item (via `/check`) only when it
has a free slot. The limits are policy, surfaced by the scrum-master's board
hygiene and the flow metrics ([`flow-metrics.md`](flow-metrics.md)):

| Scope | Default limit | Why |
|---|---|---|
| **Active Epics** (with in-flight work) | **≤ 3** | bounds context-switching at the program level (the "defined amount of active epics"); an epic is "active" when it has a branch / children in flight, read off the EPICS view |
| **`In Progress`** per producer seat | **1–2** | one unit of focus; a second only if the first is genuinely blocked on review |
| **`Delivered` + `Tested`** (awaiting the gate) | **≤ WIP of producers** | review/verify is not allowed to fall behind build — if it does, *stop starting, start finishing* |

When a limit is hit the rule is **stop starting, start finishing**: a producer
does not pull a new `Scoped` item via `/check`; the in-flight ones are driven to
`Released` first. Breaching a WIP limit is a flow defect, surfaced like any other.

## Transitions (who drives each — operator-driven)

The operator runs `/check` in the seat that should advance; that seat does the
**one** transition its role owns, then idles.

| From → To | Driver (operator runs `/check` in the seat) | Gate |
|---|---|---|
| Backlog → Scoped | PM steers | **DoR**: scope + pre-committed AC + sized + parented to an Epic |
| Scoped → In Progress | the producer pulls its next `Scoped` → claims + branches | a free WIP slot |
| In Progress → Delivered | producer (PR + ready-signal) | local gates green + a real DEV round-trip |
| Delivered → Tested | quality-engineer pulls its next `Delivered` → verifies on the deployed env (or runs evals) | **evals (oracle) + AC, deployed-env, perturbed** |
| Tested → Merged | SM pulls its next `Tested` → validates preconditions (real QA PASS + CI green + PR mergeable/clean) → squash-merges | **produce ≠ adjudicate**, once, by the non-author at the gate |
| Delivered → Scoped | quality-engineer verification FAIL → back to `Scoped` with per-criterion comments, **left assigned to the engineer** (QA does not unassign); the engineer's `/check` **rework query** (`status:scoped` + `assignee:@me`) re-pulls it **first** | a failed gate is a blocker, not a note — and must not be re-`delivered` without a fix |
| Tested → (routed) | SM finds a precondition unmet → routes, never force-merges: dirty/conflicting PR → engineer rebases; no QA verdict → back to QA | real QA PASS + CI green + PR clean |
| Merged → Released | SM deploys (staging); PROD = owner | **canary before irreversible**; PROD owner-gated |
| any → Blocked | the producer (on a **consult-exception**) — does not build; posts the **full context to the issue** (file-cited findings · the fork/options · its recommendation) + assigns itself; the SM then **verifies the claims before surfacing** to the PM with a verdict | the 3 consult-exceptions / owner-touchpoints |
| Blocked → Scoped | **PM re-frames + dual-writes it itself** — the PM posts the decision (trimmed AC + "approved → Scoped") and sets the `status:scoped` label + board `Status` field; the producer then re-pulls it | the PM's re-frame/approval posted + dual-written (the PM scopes its own items) |
| any → Cancelled | the adjudicator of the close (PM for product calls; SM at the `Blocked` sweep) — closes as `NOT_PLANNED` + dual-writes (`status:cancelled` label + board `Cancelled`) in the same write | duplicate · won't-do · obsolete · premise-invalid — **never** `Released`, which stays *shipped-only* ([the rule](../feedback/workflow/cancelled-status-state.md)) |
| Blocked → (other prior) | PM / owner resolves on the thread; the PM dual-writes the resulting `Status` flip | — |

**Every transition is operator-paced via `/check`, and every gate is the same
regardless of when the operator triggers it.** The operator's pacing changes
*when* a step runs, never *who* runs it or *whether* its gate holds — so a safety
gate can never be skipped.

## The board as the reducer (drain the queue per `/check`)

No seat holds **state between engagements**. Each `/check` discovers its role's
actionable items via a **cheap label-index query** and acts on what the state
dictates — a pure-reduction **drain**, operator-triggered: reduce one item,
re-query for the next, until none remain. There is no self-running loop and no
poll; once the queue is empty the operator re-runs `/check` to start the next
engagement. Discovery never touches the expensive 300-item Projects read — it's a
server-filtered query on the `status:*` labels (REST budget), so re-querying per
item is cheap (this is what the operator-driven rate-limit fix rests on).

```
on /check in <seat>:
  # discovery = a cheap REST/Search query on the status:* LABEL INDEX (never the 300-item Projects read)
  if active_epics > 3 or wip_breached: finish_in_flight_first
  while (item = next actionable item for <seat>'s role) is not EMPTY:   # one cheap label query per pull; most-advanced first
    case item.status:
      scoped     (producer) -> pick = order(scoped@seat): P0 > assigned(rework) > P1 > P2 > P3 > none  # ONE search, sort in memory
                             pick.assigned ? fix EXISTING branch/PR -> re-deliver : (if free_wip: claim; branch; build -> in-progress -> delivered)
      delivered  (quality)  -> v = verify(item)            # independent: Quality seat / evals, deployed-env
                               v.pass ? -> tested : (comment per-criterion; -> scoped, KEEP assignee)   # FAIL: engineer re-pulls rework first (assignee:@me)
      tested     (sm)       -> p = check_preconditions(item)   # real QA PASS + CI green + PR clean; SM did not author -> produce != adjudicate
                               p.ok ? (squash-merge; -> merged) : route(item)   # dirty PR -> engineer rebase; no verdict -> back to QA; never force-merge
      merged     (sm)       -> deploy(item); canary; -> released   # PROD is owner-gated, never automated
      blocked    (producer) -> post full consult-exception to the ISSUE (findings·options·recommendation); -> blocked; assign self; do NOT build
      blocked    (sm)       -> verify claims vs codebase/board; surface to PM with a verdict (legit/avoidable/needs-PM-call). The PM re-frames AND dual-writes (-> scoped) itself; the SM does not operationalize scoping
    # every transition DUAL-WRITES: set the status:* label (REST, the discovery mirror) + the board Status field
    #   (one cheap single-item mutation, the canonical record) — or label-only if the sync Action is enabled
  report "queue clear — idle"; idle   # queue drained — stop at empty; operator re-engages (no idle-poll; the expensive read is never run)
```

The drain is **operator-initiated** (this `/check`) and **bounded by the work that
exists now**; every item still passes its normal gate (producers stay
Engineer → QA → SM per unit — not autonomous EPIC-draining), and discovery is a
**cheap label-index query** throughout — the expensive 300-item Projects read is
never run, so re-querying per item is cheap. Each iteration takes the
most-advanced actionable item first, so the system **finishes work before
starting new work** (WIP discipline falls out of the ordering).

What treating the board as the only state buys:

- **Resumable.** Crash or interrupt mid-`/check` → the next `/check` picks up exactly where the board is. There is nothing to "recover".
- **Observable.** The operator watches the same board each `/check` reads — no opaque internal cursor.
- **Idempotent.** Re-reading a board in a stable state produces no spurious action.
- **Single mode.** There is no manual/autonomous duality — operator-driven is the one mode; every transition + gate is the same path no matter when the operator runs `/check`, so a safety gate can never be skipped.

## The stop condition (principle 7)

Each `/check` has an **explicit stop**: the seat **drains its role's eligible
queue** via the cheap label-index query — actionable item → report → re-query for
next — and then **idles**. It does not poll on a self-paced timer, does not run
the expensive board read, and does not invent work — it acts only on what the
label index says is actionable for its role, and once its queue is empty it does
**not** keep re-querying (no idle-poll). When no actionable item remains — the queue is drained, or every
remaining item is `Blocked` (awaiting a consult-exception or owner-touchpoint) —
`/check` reports `queue clear — idle` and idles. This is "finish, report, stop"
made literal at the **queue level**: within an operator-initiated `/check` the
seat drains its queue, and **nothing advances without an operator-initiated
`/check`**; the operator re-engages a seat with `/check` to take the next batch.

## GitHub mapping (the concrete board)

- The states are the **`Status` single-select** options, in the order above.
- **The `status:*` label index (cheap discovery).** Each `Status` is mirrored by a
  `status:<state>` **issue label** — the *discovery index*. Seats find work with a
  cheap server-filtered REST/Search query (`label:status:scoped label:seat:dex …`),
  **never** `gh project item-list` (Projects v2 has no server-side `Status` filter,
  so the board read pulls all ~N items to use one — the call that exhausts the
  GraphQL budget). The board `Status` field stays the **canonical record + the
  visual kanban**; the label is its read-replica. Every transition **dual-writes
  both** — set the `status:*` label (REST) **and** the board `Status` field (one
  cheap single-item mutation) — together, always. A hard invariant for every seat:
  no label-only mode, no projection Action, no reconcile/validate step; consistency
  is guaranteed at the point of write. `/check`, `/workload`, `/board`, `/backlog`
  all run discovery off the label index; the expensive read is never on the hot path.
- An item **carries its Epic parent** (sub-issue link / `Epic` field) — every
  Story is parented per [`hierarchy.md`](hierarchy.md); an orphan Story has no
  steer to build from.
- `Priority` (P0–P3), `WSJF` (number), and `Area` fields drive ordering within a
  state — see [`prioritization.md`](prioritization.md).
- The board is provisioned from the **Execution-board template** by the
  scaffolder ([`../onboarding/create-instance.sh`](../onboarding/create-instance.sh));
  the one-project / two-view (Board + EPICS) layout is [`project-boards.md`](project-boards.md).

## Why stateless is the invariant

A workflow whose state lives anywhere but the board can drift from it — the
classic "a seat thinks it shipped but `main` says otherwise". By making the
board the single source of truth and each seat a pure function of it at every
`/check`, the system has **one** state, legible to human and machine alike.
Resumability, observability, and the audit trail are then free, not bolted on.
