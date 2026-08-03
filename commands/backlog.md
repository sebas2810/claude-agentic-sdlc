---
description: List the unframed backlog (status:backlog) via the cheap label index — the PM's framing queue. Read-only.
---

Show the **backlog** — items awaiting PM framing — off the cheap `status:*` **label index** (REST/Search, no heavy board read). **Read-only**: this lists; `/check` (pm) frames the top one.

Resolve the repo (`gh` reads it from cwd) and the ownership boundary (a repo can host more than one squad; labels are shared namespace — the issue **author** is what encodes squad ownership, [the rule](../feedback/workflow/author-is-the-ownership-boundary.md)):
```
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
[ -z "${SQUAD_AUTHORS:-}" ] && [ -f .env.local ] && SQUAD_AUTHORS="$(sed -n 's/^SQUAD_AUTHORS=//p' .env.local | head -1)"
SQUAD_AUTHORS="${SQUAD_AUTHORS:-$(gh repo view --json owner -q .owner.login)}"
```

**The framing queue** — open issues labelled `status:backlog`, oldest-first, with a count and the epic each sits under:
```
gh issue list --search "is:open label:status:backlog sort:created-asc" -L 60 --json number,title,labels,author
```
**Count and list only squad-authored rows** (`author.login` ∈ `$SQUAD_AUTHORS`) — a foreign-authored `status:backlog` item is another squad's framing queue, not the PM's. Each line: `#num  title  [epic / seat label if set]` (truncate long titles). Head with the count, e.g. `7 in backlog:`.

**Hygiene flag** — a freshly-filed issue with **no `status:*` label** isn't on the index yet and won't surface to `/check`. Surface any **squad-authored** ones you spot so the SM labels it `status:backlog` (the PM then frames it → dual-writes `status:scoped` itself):
```
gh issue list --search "is:open is:issue -label:status:backlog -label:status:scoped -label:status:in-progress -label:status:delivered -label:status:tested -label:status:merged -label:status:released -label:status:blocked sort:created-asc" -L 30 --json number,title,author
```

Keep it to a screen. The PM frames the top item (posts AC) on its `/check` and **dual-writes it `status:backlog → status:scoped`** itself (label + board Status field).
