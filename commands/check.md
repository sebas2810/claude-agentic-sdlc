---
description: Find and take THIS seat's next workload from the board (role-aware). One item, report, stop — the operator re-runs /check for the next.
---

You are doing **one pull**: find your next piece of work based on this seat's role, take it, report, and **stop**. No loop, no repeated polling — the operator runs `/check` again when they want the next one.

Resolve once:
```
BOARD_ID="${BOARD_ID:?BOARD_ID unset — run /check in a configured seat pane (set BOARD_ID/BOARD_OWNER in .env.local)}"
BOARD_OWNER="${BOARD_OWNER:?BOARD_OWNER unset}"
ROLE="${SEAT_ROLE:?run /check inside a seat pane}"; KEY="${SEAT_KEY:-$ROLE}"
```
Read the board **once**: `gh project item-list "$BOARD_ID" --owner "$BOARD_OWNER" --format json --limit 300` (a deliberate, operator-paced read — not a poll; do it once and act).

Then act by **role**:

- **producer** (`engineer`; KEY = your `seat:<x>` suffix): the next item with `Status=Scoped`, label `seat:$KEY`, **no assignee**. → CLAIM it (flip `Scoped→In Progress` + assign yourself), read its issue + its `## Steer` AC, build per your KICKOFF (branch off `origin/main`, gates + a real deployed round-trip), open ONE PR with `## Closes #<n>`, set `Status→Delivered`, post your ready-signal. **Never self-merge.**

- **quality-engineer**: the next item with `Status=Delivered`. → VERIFY it against its pre-committed AC on the **deployed** env (perturb the happy path — gate reliability, not one lucky output). Post per-criterion PASS/FAIL; on PASS set `Status→Tested`, on FAIL `Status→In Progress`. **You never merge.**

- **pm**: the next `Status=Tested` item. → Adjudicate its PR against the pre-committed AC + evidence; merge it (4-eye — never one you authored). If **nothing** is `Tested`, frame the top `Backlog` item → `Scoped` with falsifiable AC.

- **scrum-master**: a flow pass — explode any newly-framed Epic into sub-issues (back-link the `#`s), enforce WIP, sweep aging/`Blocked`, surface `Tested`-ready + the 3 consult-exceptions to the PM. (Producers pull their own `Scoped` via `/check`, so you don't push work.)

If there's nothing for your role: report `no <status> work for <seat> — idle` and stop.

Take **one** item, report what you did (with the issue/PR #), then **stop**. Do not loop.
