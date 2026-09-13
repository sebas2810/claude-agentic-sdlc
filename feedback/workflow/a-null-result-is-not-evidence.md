---
title: A null result is not evidence until its scope is proven
status: active
scope: all-seats
---

# A null result is not evidence until its scope is proven

"I searched and found nothing" supports a conclusion **only** after you have
proven the search would have found the thing if it were there. Until then a
null result means *the query returned nothing*, which is a fact about the
query, not about the system.

Before an absence becomes evidence, one of these must hold:

- a **positive control** — the same query, run where the thing is known to
  exist, returns it; or
- an **enumerated scope** — you can name every place the thing could appear and
  show the query covered all of them.

Absent both, report it as "not found in X" and say what X was. Never promote it
to "it does not happen".

## Why

Investigating a stalled queue (#4206, 2026-08-17), an engineer reported that
`oqs_contribution_drain_exhausted` and `_drain_failed` never fired across a
2h42m window — searched in the worker Lambda's log group. The PM took that
absence and elevated it into a steer:

> *"an event that must appear on either branch appearing on neither is not a
> counting problem — the code took a path that goes through neither. That is a
> stronger claim than `attempts=3` would support"*

Both events had fired **7 times each**, in a different log group — the ECS
service where the drain actually runs. The engineer had **already discovered
that exact scoping trap earlier in the same investigation**, finding that a
sibling event came from ECS rather than the Lambda, and had corrected for it on
that one event without re-running the other two. The PM, reading the report,
did not apply the lesson either.

The cost: a fix was built against the wrong mechanism and shipped as a no-op,
caught only at the QA gate. Worse, the PM had told the engineer to **drop the
database read** — closing the one independent path that would have caught it —
on the strength of the absence.

And the arithmetic was there all along: 7 rows × a retry bound of 5 = the 35
attempts observed. The bound had worked perfectly. "35 attempts against a bound
that never fired" was the same evidence read exactly backwards.

## How to apply

- **State the scope in the finding, always.** "No matches in
  `/aws/lambda/<fn>` over 18:00-22:30Z" is a fact. "It never fired" is a claim,
  and needs the control.
- **Run the positive control.** Query somewhere the event is known to occur. If
  you cannot make the query return anything, you have not tested the system —
  you have tested your filter.
- **Ask where the code actually runs**, not where you assume it runs. Shared
  library code emits from whichever runtime imported it; one function can log
  into several groups.
- **Reviewers and PMs: a null result arrives with the same confidence as a
  positive one and must not be given the same weight.** When a report's load
  bearing evidence is an absence, the first question is "what would have
  produced this line, and did we look there?" — before any conclusion is built
  on it.
- **Never close off an independent verification path because of an absence.**
  That converts a checkable mistake into an uncheckable one.

## Related

- [`unmeasured-numbers-must-not-size-work.md`](unmeasured-numbers-must-not-size-work.md)
  — the same failure in its number-shaped form.
- [`../architecture/no-silent-degradation-on-load-bearing-paths.md`](../architecture/no-silent-degradation-on-load-bearing-paths.md)
  — invariant 5 read forwards: produced output is never evidence output is
  correct. This rule is invariant 5 read backwards: a missing log line is never
  evidence the path did not run.
