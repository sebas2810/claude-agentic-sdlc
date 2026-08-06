---
description: One-shot live snapshot of the OPS board — counts per ops:* state + open incidents by severity — via the cheap label index. Read-only, no polling.
---

Give the operator a **single glance** at the live ops picture — read once, print, stop. Built on the cheap `ops:*` **label index** (REST/Search), same discipline as `/board`. Do not poll.

Resolve the repo (`gh` reads it from cwd):
```
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

**Counts per ops state** — one cheap exact count each (keep this list in sync with `operations/workflow/project-templates/labels.json`):
```
for s in signal triage investigating mitigating resolved postmortem inbox answering escalated; do
  n="$(gh api -X GET search/issues -f q="repo:$REPO is:open is:issue label:ops:$s" --jq '.total_count')"
  printf '%-14s %s\n' "$s" "$n"
done
```

**Open incidents by severity** (one line each — `#num  SEV  STATE  age  title`, truncate long titles):
```
gh issue list --search "is:open label:type:incident sort:created-asc" -L 30 --json number,title,labels,createdAt
```

Then **flag** what can advance and where: `signal` (Investigator can triage) · `triage`/`investigating` (Investigator) · `mitigating` (Operator) · any `sev:1` older than 15 minutes with no human comment → say so **loudly**. Close with the loopback check: any closed `sev:1/2` postmortem in the last 7 days without a linked Delivery-board item is named as missing (`gh issue list --search "label:ops:postmortem is:closed" -L 10`).

Keep it to a screen. A glance, not a report — then the operator runs `/ops-check` in whichever ops seat should advance.
