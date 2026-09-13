---
title: PR-shaped work must be discoverable — `gh issue list` omits pull requests
status: active
scope: all-seats
area: workflow
last-updated: 2026-09-03
---

# Discovery must use `gh search issues --include-prs`, never `gh issue list`

**`gh issue list` does not return pull requests.** A PR carrying a `status:*`
label is therefore invisible to every seat's `/check` drain, no matter how
correctly it was labelled and dual-written.

## The rule

Every seat's discovery query uses:

```bash
gh search issues --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
  --label "status:<state>" --state open --include-prs \
  -L <n> --json number,title,author,isPullRequest
```

Keep the squad/author filter. Without it the query returns other squads' rows,
which `gh issue list` was incidentally protecting you from only because it was
also hiding half your own work.

## Why — the incident

PR #4968 was a `P0`: a one-line config revert that unblocked a week-stalled
intake incident. It was labelled `status:delivered`, QA-verified, and moved to
`status:tested` — fully cleared to merge.

It appeared in **no** seat's `/check`:

- the SM's drain (`label:status:tested`) returned empty while the cleared P0 sat;
- the QA seat only reviewed it because the PM messaged directly;
- the SM only learned it was cleared because QA messaged directly.

It sat roughly a day. **Every hop that moved it was a direct message or a human
relay** — exactly the coordination the operating model exists to eliminate
(spine invariant 7: the shared thread is the bus, the human is never the relay).

The failure was silent in the worst way: the board and labels were *correct*,
the dual-write had landed, and the read-back confirmed it. Nothing was broken
except that the query could not see it.

## The second, unfixed half

**PRs have no board item.** Confirmed with a positive control: merged PR #4957
has none either, so this is structural, not a missed step. A `status:*` label on
a PR is therefore **label-only by construction** — the dual-write rule cannot be
satisfied for it, and board-derived WIP and flow metrics silently exclude
PR-shaped work.

That is accepted deliberately rather than papered over: PRs are short-lived
transit, so excluding them from WIP is defensible. What is *not* acceptable is
leaving it undocumented, so a seat reads a label-only PR write as an invariant
breach.

## How to apply

- Discovery: `gh search issues --include-prs`. If you are typing `gh issue list`
  for anything that decides what to work on, you are writing a query that lies.
- Labelling a PR is required for discovery and is expected to be label-only.
  Do not hunt for a board item that does not exist, and do not "fix" its absence.
- When a work item seems stalled with nobody owning it, check whether it is a PR
  before concluding it is a routing or authority problem. On #4968 three seats
  independently reasoned about merge authority when the actual defect was that
  nobody could see it.

Related: [[actor-not-signature]] · [[behind-is-not-dirty]].
