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

`flow.py` reads the item's own issue comments and looks at each comment's
heading (its first non-empty line). A heading carries a verdict when it matches the
FAIL-verdict or the PASS-verdict pattern (default: a heading starting
`QA verification`, `QA verdict` or `QA re-verification` that says `FAIL` or `PASS`).

**Matching a verdict to a return.** Each return is matched to the verdict comment
**nearest in time** from 12 hours before the return to 10 minutes after it. The
10-minute grace finds a verdict posted just after the label change, which is the
order most seats write them in. A verdict serves **at most one return**: when two
returns of the same item could take it, the nearer one does, and the other return
takes its own nearest verdict or none. A stale verdict is never reused.

The first-pass class is the first row that fits:

| The return | First-pass class |
|---|---|
| has a matched verdict that is a FAIL, even when the item had reached `status:tested` or `status:merged` | `verification_failure` |
| has a matched verdict that is a PASS, or has no matched verdict but the item had `status:tested` or `status:merged` added after its last `status:delivered` and before the return | `after_pass` |
| has no matched verdict and no such label | `unclassified` |

A FAIL wins so that a failure found after a merge, such as a post-merge gate, counts
as a verification failure and is not hidden among the returns after a pass.

A heading that says both is decided by the word written first (`FAIL on AC3; AC1 and AC2 PASS` is a FAIL). With custom patterns that use neither word, a heading matching both counts as FAIL. Both patterns, the
window length (`--verdict-window-hours`) and the grace (`--verdict-grace-minutes`)
are flags on `flow.py`, so an instance whose verdicts use other wording or timing
sets them once rather than reading every return by hand.

That split is a **first pass**, and it decides less than it seems:

- **`after_pass` is not a slice return.** A return after a pass is a slice return
  (row 1) or a routing after a pass (row 2), such as a Scrum-Master sending back a
  PR that conflicts and was not merged, with no slice left to build. The labels and
  the verdict look the same for both, so `flow.py` does not guess.
- **It cannot see** a verdict posted on a linked PR, a verdict stated only below a
  comment's heading, a verdict outside the window and grace, or a return a PM made
  without a verdict.

A person decides **each `after_pass` return with rows 1 and 2** of the table below,
reading the comments between the pass and the return for the reason. If neither
row fits (a failure found after the pass with no FAIL verdict on the item, say),
work down the table from row 3. A person classifies **every `unclassified` return**
with the whole table, and sub-classifies a `verification_failure` into one of rows
7 to 11 when the reason matters.

## The table

Work down the rows in order and **stop at the first row whose rule fits.** The
order is the tie-break: an event where the proof was hollow *and* the branch was
wrong is a branch return, because nothing on a wrong branch could have been
verified. Write the category name exactly as it appears here.

| # | Category | Decide it when | Read |
|---|---|---|---|
| 1 | slice return | The verdict is PASS for the slice that was delivered, and the item went back to `Scoped` for its next slice. | The verdict comment; the AC list in the issue body, to confirm criteria remain open. |
| 2 | routing after a pass | The item passed verification and was sent back for a reason that is not about the change's quality: the PR conflicts or cannot merge, a required reference line is missing, or the item was routed for merge hygiene. | The comments between the pass and the return (the routing comment, usually the scrum-master's); the PR's mergeable state at the time. |
| 3 | auto-close keyword while ACs are open | The return was made because the PR body or title carries a closing keyword for an issue whose acceptance criteria are not all met. | The whole PR body and title (keywords match as substrings); the issue's AC list. |
| 4 | acceptance criterion not verifiable as written | The verifier could not test a criterion as worded: it names no one who can satisfy it, needs access no seat has, or has no observable pass condition. | The AC text in the issue body; the verdict line that says it cannot be tested. |
| 5 | PM reframe or ruling not written into the PR | A PM ruling or reframe exists in a comment, and the PR or issue body still states the old criterion the build was checked against. | The issue and PR threads for the ruling; the PR body; the verdict line citing the mismatch. |
| 6 | scope narrowed without a ruling | The build covers less than the criteria ask, and no PM ruling on the thread allows the narrower scope. | The PR diff and body against the AC list; the thread, to confirm no ruling exists. |
| 7 | verification failure: branch, base or commits wrong | The verified head is on the wrong base or branch, is missing commits the criteria need, carries unrelated commits, or is not the PR's current head. | The verdict's ref line (head SHA, base, mergeable); the PR's base, head SHA and commit list. |
| 8 | verification failure: tests or gates red | A required CI check or a named gate is red on the verified head SHA. | The CI run on that SHA; the gate output. |
| 9 | verification failure: regression | Gates are green, but something outside the criteria that worked on the base is broken on the head. | The verdict's reproduction, run on base and on head. |
| 10 | verification failure: behaviour not met | Gates are green and at least one criterion's behaviour was reproduced as not met. | The verdict's per-criterion FAIL line and the observation it records. |
| 11 | verification failure: proof missing or hollow | Behaviour was not shown to fail, but the evidence a criterion requires is absent or does not discriminate: the test suite stays green with the fix reverted, or the artifact the criterion names does not exist. | The verdict's per-criterion line; the named artifact path; the revert check. |
| 12 | unclassified | No row above fits from the verdict and the thread. | Record what was missing (no verdict, verdict on another item, no reason given), so the gap can be closed. |

## Notes for the person classifying

- **Decide from what was written, not what you infer.** If the thread does not
  say why the item returned, the event is `unclassified`, even when the cause
  seems obvious. An unrecorded reason is itself a finding.
- **One event, one category.** An item that returns twice has two events, each
  classified on its own verdict. `flow.py` lists the verdict it matched
  (`verdict`, `verdict_at`) and the label that showed a pass (`pass_label`) for each
  event; check them against the thread before relying on them.
- **Rows 3 to 6 do not need a FAIL verdict.** A PM or Scrum-Master comment can
  carry the reason. They still come before rows 7 to 11, because a framing
  defect makes the engineering check meaningless: no rework fixes a criterion
  that was wrong.
- **Rows 1 and 2 read as `after_pass` in the first pass, and rows 7 to 11 as
  `verification_failure`.** Their split needs the thread or the verdict text,
  which is why a person does it.
