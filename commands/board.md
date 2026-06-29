---
description: One-shot live snapshot of the board — counts per status + in-flight items — via the cheap status:* label index. No 300-item GraphQL read, no polling.
---

Give the operator a **single glance** at the live board — read once, print, stop. Built on the cheap `status:*` **label index** (REST/Search) so even the dashboard avoids the heavy 300-item Projects-v2 read. Do not poll.

Resolve the repo (`gh` reads it from cwd):
```
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

**Counts per status** — one cheap exact count each (Search API `total_count`, REST budget):
```
for s in backlog scoped in-progress delivered tested merged released blocked; do
  n="$(gh api -X GET search/issues -f q="repo:$REPO is:open is:issue label:status:$s" --jq '.total_count')"
  printf '%-12s %s\n' "$s" "$n"
done
```

**The in-flight items** (everything not backlog/released), one per line — `#num  STATUS  [seat:label]  title` (truncate long titles):
```
gh issue list --search "is:open label:status:scoped,status:in-progress,status:delivered,status:tested,status:blocked sort:updated-desc" -L 60 --json number,title,labels
```
*(comma in a single `label:` term = OR; derive each item's STATUS + seat from its labels.)*

Then **flag** what a seat can pick up with `/check`: **scoped** (a producer can build) · **delivered** (QA can verify) · **tested** (SM can merge) · **blocked** (SM verifies → PM). The `status:*` labels mirror the board's Status field (kept in lockstep by the dual-write on every `/check` flip), so this glance is current without touching the expensive read.

Keep it to a screen. A glance, not a report — then the operator runs `/check` in whichever seat should advance. For just the unframed queue, use `/backlog`.
