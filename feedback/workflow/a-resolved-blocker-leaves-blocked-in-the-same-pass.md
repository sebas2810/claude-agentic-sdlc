---
title: A resolved blocker leaves Blocked in the same pass
status: active
scope: pm, scrum-master
added: 2026-09-14
last-confirmed: 2026-09-14
---

> Stands under the Agentic SDLC spine (../../agentic-operating-model.md).

# A resolved blocker leaves Blocked in the same pass

When the owner and the PM rule on a `Blocked` item together, the item moves out
of `Blocked` in that same pass. A ruling that exists only as a comment, while the
card still reads `Blocked`, looks to the owner like nothing happened.

**Why**

The owner judges progress by the board, not by the thread. On 2026-09-10 an
instance's owner walked the `Blocked` column with the PM, got a ruling on each
item, and came back to find four of them still `Blocked`: the resulting moves
(`Blocked → Merged`) belonged to the Scrum-Master, and the PM had handed them off
without saying so. A ruling that does not change the state the next seat reads is
a message-hold, not an interlock: nothing downstream can see it.

**How to apply**

- **The move is the PM's** (`Blocked → Scoped`, a re-frame): make it in the same
  pass as the ruling. Edit the AC lines in the issue body, then dual-write the
  state ([the transitions](../../workflow/state-machine.md#transitions-who-drives-each--operator-driven)).
- **The move belongs to another seat** (for example `Blocked → Merged` is the
  Scrum-Master's): say so *before* the owner chooses, and offer the owner-authorised
  flip as the recommended option. Authority gates still hold; the owner's explicit
  per-change OK is what lets the PM make that write.
- **A consult-exception on a P0** is the PM's call. Decide it, unblock it, and
  report the choice in one line instead of routing it back to the owner.
- **Prevent the churn at framing.** Most `Blocked` items on EPIC-branch work came
  from criteria that need a live deployed run. Tag those `[POST-PROMOTION GATE]`
  when scoping so they gate `Released`, not the build.

**Related.** [`unblocking-is-not-a-pull.md`](unblocking-is-not-a-pull.md) (release
into free WIP slots) · [`finish-report-stop.md`](finish-report-stop.md).
