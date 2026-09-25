---
title: A slice landing does not make the item merged, and a passed slice never returns to Scoped
status: active
scope: all-seats
---

# A slice landing does not make the item `Merged`

**Rule.** `Merged` is a statement about an item's acceptance criteria, not about a PR: an item
reaches `Merged` only when every one of its ACs has landed. Work that needs more than one PR is
split into sub-issues when it is framed, one PR each, so each slice is an item with its own ACs and
its own path to `Released`. A slice that passes verification moves forward. It never goes back to
`Scoped`.

**Why.** The flip to `merged` is driven by a PR merging, and nothing in that event reads the PR's
own scope declaration or the issue's remaining ACs. So an item worked in slices had two exits, and
both were wrong:

- **Flipped to `merged` on its first slice**, it disappears. `/check` treats `merged` as finished,
  producer discovery finds nothing, and the parent Epic stalls while every item on it reads `merged`.
- **Sent back to `Scoped` for its next slice**, it re-runs a full drain per slice and counts as
  rework, although nothing failed.

**Measured.** One instance classified every return from `Delivered` to `Scoped` over 14 days: 121
returns, 39 of them slices. In each, a partial PR passed verification and the scrum-master moved the
item back to `Scoped` for its next slice, because no state meant "this slice landed, the item
continues". Five of those 39 were corrections of an item labelled `merged` too early. Earlier, the
same instance flipped five items to `merged` in about 24 hours with ACs still open: on the first PR
of two, on the first of three with the production wiring still missing, and on a prep PR while the
deletion that was the item's whole point had not happened. One PR wrote "Partial" in its own close
section, and its issue still went to `merged`. The PR was honest; the label was not.

**How to apply.**

- **PM, at framing:** if the ACs cannot land in one PR, split before scoping. Each child is a
  sub-issue one level down the hierarchy (a Story's slices are Tasks) carrying the ACs its PR lands;
  together the children carry every parent AC. The parent goes `→ In Progress` with no lane label
  (it keeps its human assignee), and closes when every child is `Released`.
- **Producer, mid-build:** once an item turns out to need more than one PR, stop and post a
  consult-exception. Never ship a PR marked "Partial" against the whole item. The PM splits it, and
  work already on a branch moves to the child that carries it.
- **Scrum-master, at the merge gate:** read the issue's ACs, not the merge event. A PR that covers
  only some of them, or says "Partial" anywhere, does not move its issue to `merged`: route it
  `→ Blocked` for the PM to split. Never flip a passed item back to `Scoped`; after `Delivered`,
  `Scoped` means a FAIL.
- **Symptom to watch:** an Epic where every item reads `merged` but nothing is promotable is
  stalled, not nearly done. In the flow report (#78), slice returns should fall to zero once splits
  happen at framing; any that remain are framing defects, not rework.

**Related.** [`../../workflow/state-machine.md`](../../workflow/state-machine.md) (the slice path) ·
[`../../commands/check.md`](../../commands/check.md) (each drain's decision point) ·
[`../../workflow/hierarchy.md`](../../workflow/hierarchy.md) ·
[`ac-must-name-who-can-satisfy-it.md`](ac-must-name-who-can-satisfy-it.md) ·
[`unblocking-is-not-a-pull.md`](unblocking-is-not-a-pull.md) (why the split parent's
`Blocked → In Progress` is not a push: no one can claim the parent).
