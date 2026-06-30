---
description: Show THIS seat's outstanding workload (role-aware list) via the cheap status:* label index. Read-only — /check takes the next one.
---

Show — don't take — every outstanding item **this seat** owns, by role, off the cheap `status:*` **label index** (REST/Search — never the 300-item board read). **Read-only**: do NOT claim, build, verify, merge, or change any status — that's `/check`.

Resolve once:
```
ROLE="${SEAT_ROLE:?run /workload inside a seat pane}"; KEY="${SEAT_KEY:-$ROLE}"
```
Discovery runs against THIS worktree's repo (`gh` resolves it from cwd). Each list is one cheap `gh issue list --search "...status:* label..."` — list, don't act.

List, by **role** — each line `#num  title  [labels]` (truncate long titles), oldest-first, with a **count** header:

- **engineer** (KEY = `dex`/`sam`/…):
  - **`status:scoped` · `seat:$KEY`** — your build queue, in the exact order `/check` pulls. **One** call, ordered in memory: **`priority:P0` → assigned (rework: QA-failed bounce-backs) → `priority:P1` → `P2` → `P3` → unlabelled**.
    `gh issue list --search "is:open label:status:scoped label:seat:$KEY sort:created-asc" -L 30 --json number,title,labels,assignees`
    *(An assigned `scoped` item = a QA **FAIL** re-pulled for rework, since a claimed item is `in-progress`. `/check` fixes those before fresh same-or-lower-priority work.)*
  - **`status:in-progress` · `seat:$KEY`** — what you already have in flight.
- **quality-engineer**: all **`status:delivered`** — your verify queue. `gh issue list --search "is:open label:status:delivered sort:created-asc" -L 30`
- **scrum-master**: all **`status:tested`** — your **merge queue** (validate preconditions → squash-merge → drive `→ status:released`); plus a flow view — a count per `status:*` label; and any **`status:blocked`** items needing action — consult-exceptions to **verify + surface to the PM with a verdict** (the PM then re-frames + dual-writes `status:blocked → status:scoped` itself).
- **pm**: the **`status:backlog`** awaiting framing — your steer queue; plus any product/scope judgement the QA seat flagged, or `status:blocked` consult-exception the SM surfaced, for you to resolve. *(Not a merge queue — the SM merges. The PM dual-writes its own scoping transitions — `Backlog`/`Blocked → Scoped`; producers then pull `status:scoped`.)*

Head each list with its count, e.g. `3 status:scoped for dex:` then the lines. If a list is empty say `none`. End with: "run `/check` to take the next one." Keep it to a screen.
