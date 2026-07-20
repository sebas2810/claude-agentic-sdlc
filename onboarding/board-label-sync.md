# The `status:*` label index — cheap board discovery (+ optional board sync)

Seats discover work with a **cheap REST/Search query on `status:*` issue labels**,
never the 300-item Projects-v2 board read (which has no server-side `Status`
filter and is what exhausts the GraphQL rate budget). This is the rate-limit fix
the operator-driven model rests on — see
[`../workflow/state-machine.md`](../workflow/state-machine.md) ("The `status:*`
label index") and [`../commands/check.md`](../commands/check.md).

The board `Status` field stays the **canonical record + the visual kanban**; each
`status:*` label is its **read-replica / discovery index**.

## The taxonomy

One label per `Status` option (board order), prefix `status:`:

| Label | Mirrors Status |
|---|---|
| `status:backlog` | Backlog (awaiting PM framing) |
| `status:scoped` | Scoped (framed + AC, claimable) |
| `status:in-progress` | In Progress (claimed, building) |
| `status:delivered` | Delivered (PR open, awaiting QA) |
| `status:tested` | Tested (QA PASS, awaiting SM merge) |
| `status:merged` | Merged to main |
| `status:released` | Released (staging/canary) |
| `status:blocked` | Blocked (consult-exception) |
| `status:cancelled` | Cancelled (terminal — closed without shipping; the board mirror of a `NOT_PLANNED` close, never parked in `Released`) |

## One-time setup (per repo on the board)

> Since v1.11 the `status:*` set ships in
> [`labels.json`](../workflow/project-templates/labels.json), so
> `create-instance.sh` / `bootstrap.sh` create it automatically — the snippet
> below is for repos provisioned before that (or created by hand).

Create the label set (idempotent — `--force` updates if present):

```bash
create() { gh label create "$1" --color "$2" --description "$3" --force; }
create "status:backlog"     "CCCCCC" "Routing index: awaiting PM framing"
create "status:scoped"      "FBCA04" "Routing index: framed + AC, claimable"
create "status:in-progress" "1D76DB" "Routing index: claimed, building"
create "status:delivered"   "0E8A16" "Routing index: PR open, awaiting QA"
create "status:tested"      "5319E7" "Routing index: QA PASS, awaiting SM merge"
create "status:merged"      "6F42C1" "Routing index: merged to main"
create "status:released"    "0052CC" "Routing index: released"
create "status:blocked"     "B60205" "Routing index: blocked consult-exception"
create "status:cancelled"   "6A737D" "Routing index: cancelled — closed without shipping (NOT_PLANNED)"
```

**Backfill existing items** (one-time, costs the *one* expensive board read — run it
once, deliberately, when the GraphQL budget is healthy). For each item on the
board, set the `status:*` label matching its current `Status` field:

```bash
# BOARD_ID / BOARD_OWNER from the seat env. One read; then cheap per-issue label writes.
gh project item-list "$BOARD_ID" --owner "$BOARD_OWNER" --format json --limit 300 \
| jq -r '.items[] | select(.content.number) | "\(.content.number)\t\(.status // "")"' \
| while IFS=$'\t' read -r num status; do
    case "$status" in
      Backlog) L=status:backlog;; Scoped) L=status:scoped;; "In Progress") L=status:in-progress;;
      Delivered) L=status:delivered;; Tested) L=status:tested;; Merged) L=status:merged;;
      Released) L=status:released;; Blocked) L=status:blocked;; Cancelled) L=status:cancelled;; *) continue;;
    esac
    gh issue edit "$num" --add-label "$L" 2>/dev/null && echo "#$num -> $L"
  done
```

After the backfill, discovery is fully label-driven and the expensive read is off
the hot path for good.

## The rule: dual-write — always, both, every transition

This is the **sole** sync mechanism, and it is non-negotiable. On every transition
**every** seat **dual-writes both**: set the `status:*` label (REST — the
discovery mirror) **and** the board `Status` field (one cheap single-item
mutation — the canonical record + visual kanban). The field mutation is the cheap
targeted `updateProjectV2ItemFieldValue` (look up the item's project-item id with
a single-issue query, *never* the 300-item list) — a few points, not the ~30–90 of
the full read. Consistency is guaranteed at the point of write, by whoever writes —
there is no projection Action, and no seat polices another's parity.

```bash
# label side of a flip (REST): e.g. claim Scoped -> In Progress
gh issue edit <n> --remove-label status:scoped --add-label status:in-progress --add-assignee @me
# field side: the cheap targeted board mutation (item-id lookup + updateProjectV2ItemFieldValue)
```

> **No projection Action.** An earlier draft offered an optional GitHub Action
> (`sync-status-label.yml` + a `PROJECTS_TOKEN` PAT) to project labels onto the
> board field. It was removed in v1.4: the write-both rule above is the single,
> mandatory mechanism, so a second sync path (and the owner-gated org-Projects PAT)
> is unnecessary.
