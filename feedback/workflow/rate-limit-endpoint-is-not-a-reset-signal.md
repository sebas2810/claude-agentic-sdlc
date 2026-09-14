---
title: /rate_limit is not a reset signal
status: active
scope: all-seats
added: 2026-09-14
last-confirmed: 2026-09-14
---

> Stands under the Agentic SDLC spine (../../agentic-operating-model.md).

# `/rate_limit` is not a reset signal

When GraphQL calls fail with a rate-limit error, confirm that the budget is back
with one real minimal GraphQL call. Do not read the `/rate_limit` endpoint's
numbers as proof.

**Why**

On 2026-09-10, on one account, `gh api rate_limit` reported
`graphql 5000/5000 used=0, reset=now+1h`, and `core used=0` right after about 15
successful REST calls, so it was not counting. Every GraphQL call at that moment
still failed with `API rate limit already exceeded for user ID ...`. A PM seat
read the endpoint as "reset", told the owner so, and the retry failed. The
endpoint is a report about the budget, and here the report was wrong; the only
thing that proves a call will succeed is a call that succeeds.

**How to apply**

- To check recovery, run `gh api graphql -f query='{viewer{login}}'`. Success means
  GraphQL is back; the rate-limit error means it is not.
- Never tell the owner or another seat that the limit has reset on the strength of
  `/rate_limit` alone.
- While GraphQL is exhausted, REST still works for issue bodies, labels, comments
  and issue creation. Board field writes and `gh issue edit` need GraphQL, so hold
  those transitions, and keep them board-first
  ([`write-the-board-field-before-the-label.md`](write-the-board-field-before-the-label.md)).

**Related.** [`a-check-must-be-able-to-report-its-own-failure.md`](a-check-must-be-able-to-report-its-own-failure.md).
