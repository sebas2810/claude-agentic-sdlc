---
description: List the unframed backlog (status:backlog) via the cheap label index — the PM's framing queue. Read-only.
---

Show the **backlog** — items awaiting PM framing — off the cheap `status:*` **label index** (REST/Search, no heavy board read). **Read-only**: this lists; `/check` (pm) frames the top one.

Resolve the repo (`gh` reads it from cwd):
```
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
```

**The framing queue** — open issues labelled `status:backlog`, oldest-first, with a count and the epic each sits under:
```
gh issue list --search "is:open label:status:backlog sort:created-asc" -L 60 --json number,title,labels
```
Each line: `#num  title  [epic / seat label if set]` (truncate long titles). Head with the count, e.g. `7 in backlog:`.

**Hygiene flag** — a freshly-filed issue with **no `status:*` label** isn't on the index yet and won't surface to `/check`. Surface any you spot so the SM labels it `status:backlog` (the PM frames → SM operationalizes → `status:scoped`):
```
gh issue list --search "is:open is:issue -label:status:backlog -label:status:scoped -label:status:in-progress -label:status:delivered -label:status:tested -label:status:merged -label:status:released -label:status:blocked sort:created-asc" -L 30 --json number,title
```

Keep it to a screen. The PM frames the top item (posts AC) on its `/check`; the SM then flips it `status:backlog → status:scoped`.
