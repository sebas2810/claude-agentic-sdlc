---
description: Drain THIS seat's queue (role-aware) via the cheap status:* label index — take an item, report, take the next, until empty; then idle. REST discovery, no 300-item board read.
---

You **drain your queue**, role-aware, off the cheap `status:*` **label index** — never the heavy board read. Take an eligible item, do it, report, take the next — repeating (item → report → next) until none remain for your role, then report `queue clear — idle` and **stop**. Two rails: the drain is **operator-initiated** (this `/check`) and **bounded by the work that exists right now**, and every item still passes its normal gate (producers stay Engineer → QA → SM per unit — *not* autonomous EPIC-draining). **Stop at empty:** once your queue is clear you do **not** keep re-querying (no self-loop, no idle-poll) — the operator runs `/check` again when new work lands.

**Discovery is a cheap REST/Search query on the `status:*` label index — never `gh project item-list`.** The board's Status field is the canonical record + the visual kanban; the matching `status:*` **issue label** is its discovery mirror, so you find work server-filtered on the **REST budget** (the 300-item Projects-v2 GraphQL read is what exhausts the rate limit — it has no server-side Status filter, so it pulls everything to use one). Resolve once:
```
ROLE="${SEAT_ROLE:?run /check inside a seat pane}"; KEY="${SEAT_KEY:-$ROLE}"
# discovery runs against THIS worktree's repo (gh resolves it from cwd — no hardcode);
# BOARD_ID/BOARD_OWNER are only needed for the dual-write field flip below.
BOARD_ID="${BOARD_ID:-}"; BOARD_OWNER="${BOARD_OWNER:-}"
```

**Targeted mode — `/check #<n>`:** pass an issue number to skip the queue and focus that **one** item. Fetch it once (`gh issue view <n> --json number,title,labels,assignees,state`) and act on it **only if its `status:*` matches your role's gate** — producer→`scoped`, quality-engineer→`delivered`, scrum-master→`tested`, pm→`backlog`/`blocked`. If it's in a state your role doesn't own, **report why and stop** (e.g. *"#494 is `status:delivered` — that's the quality-engineer's gate, not the producer's"*) — don't force it. No number → drain the queue below.

Find + act by **role** — each discovery is one cheap `gh issue list --search` (re-run it to drain):

- **producer** (`engineer`; KEY = your `seat:<x>` suffix). **One cheap Search call, then order in memory** — do *not* run a query per priority tier (the labels + assignees in this one list decide everything; no extra round-trips):
  `gh issue list --search "is:open label:status:scoped label:seat:$KEY sort:created-asc" -L 30 --json number,title,labels,assignees`
  Pick the **first** item by this order:
  1. **`priority:P0`** — incident/interrupt; preempts everything (even rework).
  2. **Rework** — any item **with an assignee** (a `status:scoped` + `seat:$KEY` item that is *assigned* can only be a QA **FAIL** bounce-back — a claimed item is `status:in-progress`, not `scoped`; QA leaves it assigned precisely so it re-surfaces here). **Fix it FIRST:** read its per-criterion QA comments, fix the **existing branch/PR**, re-**deliver** (dual-write → `status:delivered`). **Never re-`deliver` a QA-failed item without a fix that addresses the failing criteria** — that's the loop QA caught.
  3. **Fresh, by priority:** `priority:P1` → `priority:P2` → `priority:P3` → no-priority (treat as P2); `created-asc` within each tier.
  → **CLAIM** the chosen item (dual-write: `status:scoped`→`status:in-progress` label + board Status→In Progress + assign yourself), read its issue + `## Steer` AC, build per your KICKOFF (branch off `origin/main`, gates + a real deployed round-trip), open ONE PR `## Closes #<n>`, **deliver** (dual-write → `status:delivered`), post your ready-signal. **Never self-merge.** **Block protocol:** a genuine consult-exception (AC unmeetable as written · a real product fork · out-of-scope creep) → do **not** build; post the **full consult-exception to the GitHub issue** (file-cited findings · the fork/options · your recommendation), dual-write → `status:blocked` + assign yourself, then **stop**. The issue comment IS the board item's context — the SM/PM read it from the board, not your pane.

- **quality-engineer**:
  `gh issue list --search "is:open label:status:delivered sort:created-asc" -L 1 --json number,title`
  → **VERIFY** against the pre-committed AC on the **deployed** env (perturb the happy path — gate reliability, not one lucky output). Post per-criterion PASS/FAIL; on PASS dual-write → `status:tested`; on **FAIL → `status:scoped`** with the per-criterion comments, and **leave it assigned to the engineer** — do **not** unassign; that assignment is exactly what the engineer's `/check` rework query (#1 above) re-pulls. **You never merge.**

- **scrum-master**:
  `gh issue list --search "is:open label:status:tested sort:created-asc" -L 1 --json number,title`
  → validate the merge preconditions (a **real QA PASS** verdict · **CI green** · PR **mergeable/clean**) → **MERGE (squash; 4-eye — you did not author it)**, dual-write → `status:merged`, then drive `→ status:released` (staging + canary; PROD owner-gated). Precondition fail → **route, never force-merge** (dirty PR → engineer rebase; no verdict → QA). Plus board hygiene — explode any newly-framed Epic into sub-issues (back-link the `#`s), enforce WIP, sweep aging. `Blocked` duty (find them with `label:status:blocked`): **verify before surfacing** — independently verify each consult-exception's cited claims against the codebase/board, then surface to the PM **with a verdict** — *legit blocker* / *avoidable* / *needs-PM-product-call* — never a bare relay. (Producers pull their own `status:scoped` via `/check`, so you don't push build work; and the **PM dual-writes its own `status:scoped`** for `Backlog → Scoped` + `Blocked → Scoped`, so you don't operationalize scoping either.)

- **pm**: **no routine merge; dual-write your own scoping transitions.**
  `gh issue list --search "is:open label:status:backlog sort:created-asc" -L 1 --json number,title`
  → frame the top `status:backlog` item with a **falsifiable** AC (the contract QA verifies against), then **dual-write it `→ status:scoped` yourself** (set the `status:scoped` label **and** the board Status field together — the v1.4 write-both rule applies to the PM too); the producer then pulls `status:scoped` directly via its own `/check`. Resolve any product/scope judgement the QA seat surfaced (an ambiguous / deploy-gated AC), or re-frame a `Blocked` consult-exception the SM surfaced (e.g. trim the AC + "approved → Scoped") and **dual-write it `status:blocked → status:scoped` yourself**. **You dual-write your own scoping transitions (`Backlog → Scoped` + `Blocked → Scoped`), but you still NEVER merge — the SM is the merge authority.** Otherwise oversight — roadmap + owner touchpoints.

**Dual-write, every transition — non-negotiable.** Whenever you change state, write **both**, together: set the `status:*` **label** (REST — the discovery mirror) **and** the board **Status field** (one cheap single-item mutation — get the item's project-item id with a targeted single-issue query, *never* the 300-item list — keeps the visual kanban + canonical record live). A hard invariant for **every** seat on **every** transition: no label-only mode, no projection Action, no separate reconcile/validate step — consistency is guaranteed at the point of write, by whoever writes.

**Drain, then idle.** Re-run your role's cheap discovery query: another eligible item → handle it (report with the issue/PR #); none → report `queue clear — idle` and **stop**. Re-querying is cheap REST, so no snapshot is needed — but the rails still hold: **(1)** operator-initiated + bounded by current work, per-unit gate intact (not autonomous EPIC-draining); **(2) stop at empty — no idle-poll:** once clear, do **not** keep re-querying (no self-loop, no `/loop`, no `ScheduleWakeup`) — the operator re-engages you when new work lands.
