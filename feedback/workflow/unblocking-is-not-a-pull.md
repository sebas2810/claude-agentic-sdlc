# Unblocking is not a pull — resolve in a batch, release one at a time

**Rule.** When several `Blocked` items belonging to the *same producer seat*
become resolvable at once, the PM may rule on all of them in one pass, but must
release only enough to fill the seat's free WIP slots. The rest return to
`Scoped`, and the seat pulls them itself as slots free.

**Why.** A PM-written `Blocked → In Progress` is a **push**. The whole state
machine is pull-based: a producer claims its next item via `/check` *only when
it has a free slot* ([`../../workflow/state-machine.md`](../../workflow/state-machine.md)
WIP limits — 1–2 `In Progress` per producer seat). Batch-unblocking bypasses
that, because the seat never gets to decide whether to accept three units of
work simultaneously. The WIP limit is not advisory; breaching it is a flow
defect, and a PM-authored breach is worse than a seat-authored one because the
seat cannot refuse it.

**Measured, 2026-08-07.** A producer raised consult-exceptions on two items;
both went `Blocked` while a third stayed `In Progress`. The PM ruled all three
in one pass and flipped every one back to `In Progress` within twenty minutes —
3 against a limit of 2. Both blockers were genuinely resolved and the rulings
were correct; the *release pattern* was the defect.

**How to apply.**

- Rule on every resolvable `Blocked` item in the pass — that part is right, and
  leaving a seat's exceptions unanswered is worse.
- Then count the seat's current `In Progress`. Release only up to the limit;
  send the remainder to `Scoped` with the ruling attached, so the producer pulls
  them on its own `/check`.
- **Exception — finished work.** If a blocked item is already built and its
  blocker was the *gate* or the *push*, draining it forward to `Delivered` is
  correct even above the limit: it is leaving the seat's queue, not entering it.
  Demoting finished work to `Scoped` discards it.
- Say which item the seat should hold as its single active unit, and why.
  "Stop starting, start finishing" is only actionable if the seat knows which
  one to finish.

**Related.** [`../../workflow/state-machine.md`](../../workflow/state-machine.md)
(WIP limits · transitions) · [`finish-report-stop.md`](finish-report-stop.md).
