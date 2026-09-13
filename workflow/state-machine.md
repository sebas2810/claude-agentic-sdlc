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
the hierarchy that connects them is [`hierarchy.md`](hierarchy.md), and their
coarse fleet-altitude lifecycle is [`team-model.md`](team-model.md).

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
| Backlog → In Progress (split parent) | PM, at framing, when the item needs more than one PR: one sub-issue per PR, each framed `→ Scoped`; the parent gets no `seat:` lane and no assignee ([the slice path](#the-slice-path-work-planned-as-more-than-one-pr)) | every child meets **DoR**; together the children carry every parent AC |
| Scoped → In Progress | the producer pulls its next `Scoped` → claims + branches | a free WIP slot |
| In Progress → Delivered | producer (PR + ready-signal) | local gates green + a real DEV round-trip |
| Delivered → Tested | quality-engineer pulls its next `Delivered` → verifies on the deployed env (or runs evals) | **evals (oracle) + AC, deployed-env, perturbed** |
| Tested → Merged | SM pulls its next `Tested` → validates preconditions (real QA PASS + CI green + PR mergeable/clean) → squash-merges | **produce ≠ adjudicate**, once, by the non-author at the gate |
| Delivered → Scoped | quality-engineer verification FAIL → back to `Scoped` with per-criterion comments, **left assigned to the engineer** (QA does not unassign); the engineer's `/check` **rework query** (`status:scoped` + `assignee:@me`) re-pulls it **first** | **FAIL only: a PASS never returns an item to `Scoped`.** A failed gate is a blocker, not a note — and must not be re-`delivered` without a fix |
| Tested → (routed) | SM finds a precondition unmet → routes, never force-merges: dirty/conflicting PR → engineer rebases; no QA verdict → back to QA; a PR that covers only some of its issue's ACs, or says "Partial" → `Blocked` for the PM to split, **never `Merged` and never `Scoped`** | real QA PASS on every AC of the issue + CI green + PR clean |
| Merged → Released | SM deploys (staging); PROD = owner | **canary before irreversible**; PROD owner-gated |
| In Progress → Released (split parent) | SM, in the pass that releases the parent's last child; closes the parent | every child `Released`. The parent has no PR, so it never enters `Delivered`, `Tested` or `Merged` |
| any → Blocked | the producer (on a **consult-exception**) — does not build; posts the **full context to the issue** (file-cited findings · the fork/options · its recommendation) + assigns itself; the SM then **verifies the claims before surfacing** to the PM with a verdict. **Or the SM, for one case:** at the merge gate, a PR that covers only some of its issue's ACs, or says "Partial", goes `→ Blocked` for the PM to split ([the slice path](#the-slice-path-work-planned-as-more-than-one-pr)) | the 3 consult-exceptions / owner-touchpoints |
| Blocked → Scoped | **PM re-frames + dual-writes it itself** — the PM posts the decision (trimmed AC + "approved → Scoped") and sets the `status:scoped` label + board `Status` field; the producer then re-pulls it | the PM's re-frame/approval posted + dual-written (the PM scopes its own items) |
| Blocked → In Progress (split parent) | PM, answering a consult-exception that the item needs more than one PR (or a partial PR the SM routed): splits it as at framing; work already on a branch or PR moves to the child that carries it | as for the framing split. Not a push ([rule](../feedback/workflow/unblocking-is-not-a-pull.md)): no one can claim the parent, and the producer pulls the children |
| any → Cancelled | the adjudicator of the close (PM for product calls; SM at the `Blocked` sweep) — closes as `NOT_PLANNED` + dual-writes (`status:cancelled` label + board `Cancelled`) in the same write | duplicate · won't-do · obsolete · premise-invalid — **never** `Released`, which stays *shipped-only* ([the rule](../feedback/workflow/cancelled-status-state.md)) |
| Blocked → (other prior) | PM / owner resolves on the thread; the PM dual-writes the resulting `Status` flip | — |

**Every transition is operator-paced via `/check`, and every gate is the same
regardless of when the operator triggers it.** The operator's pacing changes
*when* a step runs, never *who* runs it or *whether* its gate holds — so a safety
gate can never be skipped.

## The slice path (work planned as more than one PR)

`Merged` means every AC of an item landed, not that a PR merged. So an item never
rides the states once per PR: work that needs more than one PR is split, and each
slice travels as its own item. The rule and the evidence behind it:
[`a-slice-landing-does-not-make-the-item-merged.md`](../feedback/workflow/a-slice-landing-does-not-make-the-item-merged.md).

- **Split at framing.** When the PM frames an item whose ACs cannot land in one PR
  (the DoR's *Sized* box fails), it creates one sub-issue per PR, one level down
  [the hierarchy](hierarchy.md): a Story's slices are Tasks. Each child carries the
  ACs its PR lands and meets the DoR on its own; together the children carry every
  parent AC. Each child is framed `→ Scoped` with its lane label and flows the states
  like any other item.
- **The parent stays `In Progress`.** The PM dual-writes the parent `→ In Progress`
  with no `seat:` lane label and no assignee, so no drain discovers it as work and it
  counts against no producer's WIP limit. The parent has no PR of its own, so it never
  enters `Delivered`, `Tested` or `Merged`. It goes `→ Released` and closes when every
  child is `Released`; the SM does that in the pass that releases the last child.
- **A split found mid-build.** A producer who finds that an item needs more than one
  PR stops and posts a consult-exception (`→ Blocked`), and the PM splits it as above
  (`Blocked → In Progress` for the parent). Work already on a branch or PR moves to
  the child that carries it. The producer never ships a PR marked "Partial" against
  the whole item.
- **No return to `Scoped` for a passed slice.** No transition leads from `Tested` or
  `Merged` back to `Scoped`, and `Delivered → Scoped` fires only on a verification
  FAIL. A PR that covers only some of its issue's ACs, or says "Partial", cannot move
  that issue to `Merged`: the SM routes it `→ Blocked` for the PM to split, and the
  child that carries exactly those ACs takes the PR.

Without this path a passed slice had two exits, and both were wrong: back to
`Scoped`, where it re-ran a full drain and read as rework, or forward to `Merged`,
where it dropped out of every queue with ACs still open. With it, a
`Delivered → Scoped` is a verification failure again. The flow report (#78) counts
slice returns separately from verification failures, so any that still happen show
as a framing defect, not as rework.

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
      backlog    (pm)       -> frame; needs >1 PR ? (one sub-issue per PR -> scoped; parent -> in-progress, no lane, no assignee) : -> scoped
      scoped     (producer) -> pick = order(scoped@seat): P0 > assigned(rework) > P1 > P2 > P3 > none  # ONE search, sort in memory
                             pick.assigned ? fix EXISTING branch/PR -> re-deliver : (if free_wip: claim; branch; build -> in-progress -> delivered)
      delivered  (quality)  -> v = verify(item)            # independent: Quality seat / evals, deployed-env
                               v.pass ? -> tested : (comment per-criterion; -> scoped, KEEP assignee)   # FAIL: engineer re-pulls rework first (assignee:@me)
                               # scoped is the FAIL route only: a PASS never goes -> scoped
      tested     (sm)       -> p = check_preconditions(item)   # real QA PASS + CI green + PR clean; SM did not author -> produce != adjudicate
                               p.ok ? (squash-merge; -> merged) : route(item)   # dirty PR -> engineer rebase; no verdict -> back to QA; never force-merge
                               # PR covers only some ACs, or says "Partial" -> not p.ok: -> blocked for the PM to split; never -> merged, never -> scoped
      merged     (sm)       -> deploy(item); canary; -> released   # PROD is owner-gated, never automated
                               # last child of a split parent released -> parent -> released + closed
      blocked    (producer) -> post full consult-exception to the ISSUE (findings·options·recommendation); -> blocked; assign self; do NOT build
                               # "needs more than one PR" is a consult-exception: never ship a Partial PR against the whole item
      blocked    (sm)       -> verify claims vs codebase/board; surface to PM with a verdict (legit/avoidable/needs-PM-call). The PM re-frames AND dual-writes (-> scoped) itself; the SM does not operationalize scoping
    # every transition DUAL-WRITES: set the status:* label (REST, the discovery mirror) + the board Status field
    #   (one cheap single-item mutation, the canonical record) — always both; no label-only mode, no projection Action
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
  cheap single-item mutation) — together, always, **and ends with a read-back**:
  one targeted `gh issue view <n> --json labels,projectItems` asserting both
  halves landed. A dual-write can silently no-op while exiting 0, and a half
  that didn't land leaves the item invisible to the next seat's discovery while
  the writer reports success — **the transition is complete when the read-back
  confirms it, not when the write returns.** A hard invariant for every seat:
  no label-only mode, no projection Action, no deferred reconcile job; consistency
  is guaranteed — and verified — at the point of write, by whoever writes.
  On a board **not linked to the issues' repo** (a personal/unlinked project)
  `projectItems` reads empty even when `Status` is set — read that half back with
  a project-item node query
  ([the rule](../feedback/workflow/read-back-unlinked-board-via-node-query.md)).
  `/check`, `/workload`, `/board`, `/backlog`
  all run discovery off the label index; the expensive read is never on the hot
  path. In a repo hosting more than one squad, discovery also carries the
  **ownership boundary** — the issue `author`; the shared label namespace does
  not encode squad ([the rule](../feedback/workflow/author-is-the-ownership-boundary.md)).
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
