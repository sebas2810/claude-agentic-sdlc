---
description: Show THIS seat's outstanding workload from the board (role-aware list). Read-only — /check takes the next one.
---

Show — don't take — every outstanding item **this seat** owns, by role. One board read, list, stop. This is **read-only**: do NOT claim, build, verify, merge, or change any status — that's what `/check` is for.

Resolve once:
```
BOARD_ID="${BOARD_ID:?BOARD_ID unset — run /workload in a configured seat pane}"; BOARD_OWNER="${BOARD_OWNER:?BOARD_OWNER unset}"
ROLE="${SEAT_ROLE:?run /workload inside a seat pane}"; KEY="${SEAT_KEY:-$ROLE}"
```
Read the board **once**: `gh project item-list "$BOARD_ID" --owner "$BOARD_OWNER" --format json --limit 300`.

Then list, by **role** — each line `#num  title  [seat:label]` (truncate long titles), most-recent/priority first, with a **count** header:

- **engineer** (KEY = `dex`/`sam`/…):
  - **`Scoped` · `seat:$KEY`** — your outstanding build queue (what `/check` would pull next; a re-`Scoped` item carries QA comments to address). *This is the "items scoped on your name" list.*
  - **`In Progress` · `seat:$KEY`** — what you already have in flight.
- **quality-engineer**: all **`Delivered`** items — your verify queue.
- **scrum-master**: all **`Tested`** items — your **merge queue** (validate preconditions → squash-merge → drive `Merged→Released`); plus a flow view — count per state (`Scoped`/`In Progress`/`Delivered`/`Tested`/`Merged`) + any **aging** or **`Blocked`** items to surface.
- **pm**: the **`Backlog`** awaiting framing — your steer queue; plus any product/scope judgement the QA seat has flagged for you to resolve. *(Not a merge queue — the SM merges.)*

Head each list with its count, e.g. `3 Scoped for dex:` then the lines. If a list is empty say `none`. End with a one-line nudge: "run `/check` to take the next one." Keep it to a screen.
