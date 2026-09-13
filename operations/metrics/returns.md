---
title: Classifying a return, so two people get the same answer
status: active
scope: pm-orchestrator, quality-engineer, scrum-master
---

# Classifying a return

A **return** is an item that had `status:delivered` added and later had
`status:scoped` added again. [`flow.py`](flow.py) counts every return in its
window and lists each one (item number and time) under `returns.events`. This
page says what kind of return each one was.

The categories exist to find the cause, not a culprit. Half of them are framing
or process defects that no amount of engineering rework would have prevented.

## The automatic split is a first pass

`flow.py` reads the item's own issue comments created in the 12 hours before
the return, looks at each comment's heading (its first non-empty line), and takes
the **latest** comment whose heading carries a verdict:

| That comment matches | First-pass class |
|---|---|
| the FAIL-verdict pattern (default: a heading starting `QA verification`, `QA verdict` or `QA re-verification` that says `FAIL`) | `verification_failure` |
| the PASS-verdict pattern (default: a heading starting `QA verification`, `QA verdict` or `QA re-verification` that says `PASS`) | `slice_return` |
| neither, or there is no comment in the window | `unclassified` |

A heading that says both is decided by the word written first (`FAIL on AC3; AC1 and AC2 PASS` is a FAIL). With custom patterns that use neither word, a heading matching both counts as FAIL. Both patterns and the
window length are flags on `flow.py`, so an instance whose verdicts use other
wording sets them once rather than reading every return by hand.

That split is a **first pass**. It cannot see a verdict posted on a linked PR, a verdict stated only below a comment's heading,
a verdict older than the window, or a return a PM made without a verdict. A
person classifies the `unclassified` rest with the table below, and sub-classifies
a `verification_failure` into one of its five rows when the reason matters.

## The table

Work down the rows in order and **stop at the first row whose rule fits.** The
order is the tie-break: an event where the proof was hollow *and* the branch was
wrong is a branch return, because nothing on a wrong branch could have been
verified. Write the category name exactly as it appears here.

| # | Category | Decide it when | Read |
|---|---|---|---|
| 1 | slice return | The verdict is PASS for the slice that was delivered, and the item went back to `Scoped` for its next slice. | The verdict comment; the AC list in the issue body, to confirm criteria remain open. |
| 2 | auto-close keyword while ACs are open | The return was made because the PR body or title carries a closing keyword for an issue whose acceptance criteria are not all met. | The whole PR body and title (keywords match as substrings); the issue's AC list. |
| 3 | acceptance criterion not verifiable as written | The verifier could not test a criterion as worded: it names no one who can satisfy it, needs access no seat has, or has no observable pass condition. | The AC text in the issue body; the verdict line that says it cannot be tested. |
| 4 | PM reframe or ruling not written into the PR | A PM ruling or reframe exists in a comment, and the PR or issue body still states the old criterion the build was checked against. | The issue and PR threads for the ruling; the PR body; the verdict line citing the mismatch. |
| 5 | scope narrowed without a ruling | The build covers less than the criteria ask, and no PM ruling on the thread allows the narrower scope. | The PR diff and body against the AC list; the thread, to confirm no ruling exists. |
| 6 | verification failure: branch, base or commits wrong | The verified head is on the wrong base or branch, is missing commits the criteria need, carries unrelated commits, or is not the PR's current head. | The verdict's ref line (head SHA, base, mergeable); the PR's base, head SHA and commit list. |
| 7 | verification failure: tests or gates red | A required CI check or a named gate is red on the verified head SHA. | The CI run on that SHA; the gate output. |
| 8 | verification failure: regression | Gates are green, but something outside the criteria that worked on the base is broken on the head. | The verdict's reproduction, run on base and on head. |
| 9 | verification failure: behaviour not met | Gates are green and at least one criterion's behaviour was reproduced as not met. | The verdict's per-criterion FAIL line and the observation it records. |
| 10 | verification failure: proof missing or hollow | Behaviour was not shown to fail, but the evidence a criterion requires is absent or does not discriminate: the test suite stays green with the fix reverted, or the artifact the criterion names does not exist. | The verdict's per-criterion line; the named artifact path; the revert check. |
| 11 | unclassified | No row above fits from the verdict and the thread. | Record what was missing (no verdict, verdict on another item, no reason given), so the gap can be closed. |

## Notes for the person classifying

- **Decide from what was written, not what you infer.** If the thread does not
  say why the item returned, the event is `unclassified`, even when the cause
  seems obvious. An unrecorded reason is itself a finding.
- **One event, one category.** An item that returns twice has two events, each
  classified on its own verdict.
- **Rows 2 to 5 do not need a FAIL verdict.** A PM or Scrum-Master comment can
  carry the reason. They still come before rows 6 to 10, because a framing
  defect makes the engineering check meaningless: no rework fixes a criterion
  that was wrong.
- **Rows 6 to 10 all read as `verification_failure` in the first pass.** Their
  split needs the verdict text, which is why a person does it.
