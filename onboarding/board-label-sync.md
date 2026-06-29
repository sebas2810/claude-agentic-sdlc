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

## One-time setup (per repo on the board)

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
      Released) L=status:released;; Blocked) L=status:blocked;; *) continue;;
    esac
    gh issue edit "$num" --add-label "$L" 2>/dev/null && echo "#$num -> $L"
  done
```

After the backfill, discovery is fully label-driven and the expensive read is off
the hot path for good.

## The default: dual-write (no extra infra)

On every transition a seat **dual-writes**: set the `status:*` label (REST — the
discovery mirror) **and** the board `Status` field (one cheap single-item
mutation — the canonical record + visual kanban). The field mutation is the cheap
targeted `updateProjectV2ItemFieldValue` (look up the item's project-item id with
a single-issue query, *never* the 300-item list) — a few points, not the ~30–90 of
the full read. This keeps the visual board live with **no new infrastructure**.

```bash
# label side of a flip (REST): e.g. claim Scoped -> In Progress
gh issue edit <n> --remove-label status:scoped --add-label status:in-progress --add-assignee @me
# field side: the cheap targeted board mutation (item-id lookup + updateProjectV2ItemFieldValue)
```

## Optional upgrade: pure label-driven (one small Action)

To drop even the cheap field mutation from the loop — **zero GraphQL in the seat
loop** — enable a GitHub Action that projects `status:*` label changes onto the
board `Status` field. (GitHub emits webhook events on **label** changes but not on
Projects-field changes, so the sync only works in this direction — which is why
labels are the writeable index and the field is the projection.)

Needs a **project-scoped token** as a repo secret (`PROJECTS_TOKEN`) — the default
`GITHUB_TOKEN` cannot write an **org-owned** project. One-time owner setup:
`gh secret set PROJECTS_TOKEN` with a fine-grained PAT scoped to the org's
Projects (read/write).

Template — `.github/workflows/sync-status-label.yml` in the **product** repo:

```yaml
name: Sync status label -> board
on:
  issues:
    types: [labeled, unlabeled]
permissions:
  issues: read
jobs:
  sync:
    if: startsWith(github.event.label.name, 'status:')
    runs-on: ubuntu-latest
    steps:
      - name: Project the status:* label onto the board Status field
        env:
          GH_TOKEN: ${{ secrets.PROJECTS_TOKEN }}   # fine-grained PAT, org Projects read/write
          BOARD_NUMBER: "1"                          # the org Project number
          BOARD_OWNER: "Nestor-Software"             # the org
          ISSUE_NODE: ${{ github.event.issue.node_id }}
          LABEL: ${{ github.event.label.name }}
        run: |
          # map status:<x> -> the Status single-select option, then
          # updateProjectV2ItemFieldValue on this issue's project item.
          # (see scripts/sync-status-label.sh — resolve project/field/option ids once, cache as repo vars)
          bash .github/scripts/sync-status-label.sh
```

When the Action is enabled, seats write **only** the label and the board follows;
disable the dual-write field mutation in that case (the `/check` flip step notes
this). Until it's enabled, the dual-write keeps the board correct — so the Action
is a pure optimisation, never a prerequisite for the rate-limit fix.
