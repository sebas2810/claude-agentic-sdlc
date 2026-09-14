---
title: Write the board field before the label
status: active
scope: all-seats
added: 2026-09-14
last-confirmed: 2026-09-14
---

> Stands under the Agentic SDLC spine (../../agentic-operating-model.md).

# Write the board field before the label

A dual-write has two halves on two APIs: the board `Status` field (Projects v2,
GraphQL) and the `status:*` label (REST). Write the board field first, and write
the label only after the board write succeeded.

**Why**

The two halves fail independently. GraphQL has its own rate budget, and a seat
that exhausts it can still write labels over REST. When the label goes first and
the board write then fails, the item is moved in the discovery index but not on
the board: the next seat's `/check` pulls it, while the owner's kanban still shows
the old state. That split is invisible until someone reconciles the two by hand.

Written board-first, an exhausted budget leaves the item unmoved on **both**
halves, which is a failed transition you can see and retry, not a silent split.
A label-only half-move also gains nothing: every seat's next transition on that
item needs the board write too.

**How to apply**

- Order every transition: board `Status` field, check the mutation returned an
  item id, then the `status:*` label.
- If the board write fails, do not write the label. Report the transition as not
  made, with the error.
- Read back both halves before reporting, as [`commands/check.md`](../../commands/check.md)
  requires. On an unlinked board, read the board half with a project-item node query
  ([`read-back-unlinked-board-via-node-query.md`](read-back-unlinked-board-via-node-query.md)).
- If GraphQL is exhausted, see [`rate-limit-endpoint-is-not-a-reset-signal.md`](rate-limit-endpoint-is-not-a-reset-signal.md)
  before retrying.

**Related.** [`seat-label-mirror.md`](seat-label-mirror.md).
