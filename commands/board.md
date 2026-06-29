---
description: One-shot live snapshot of the Execution board — counts per status + the in-flight items. No polling, no loop.
---

Give the operator a **single glance** at the live board — read once, print, stop. Do not poll.

```
BOARD_ID="${BOARD_ID:?BOARD_ID unset — run in a configured seat pane}"; BOARD_OWNER="${BOARD_OWNER:?BOARD_OWNER unset}"
gh project item-list "$BOARD_ID" --owner "$BOARD_OWNER" --format json --limit 200
```

From that one read, show concisely:
- **Counts per Status**: Backlog · Scoped · In Progress · Delivered · Tested · Merged · Released · Blocked.
- **The non-Backlog items**, one per line: `#num  STATUS  [seat:label]  title` (truncate long titles).
- **Flag** what's ready for a seat to pick up with `/check`: **Scoped** (a producer can build) · **Delivered** (QA can verify) · **Tested** (PM can merge) · **Blocked** (needs the owner).

Keep it to a screen. A glance, not a report — then the operator runs `/check` in whichever seat should advance.
