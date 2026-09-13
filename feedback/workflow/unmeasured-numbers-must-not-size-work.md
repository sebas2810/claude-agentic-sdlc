---
title: An unmeasured number must not size a work package
status: active
scope: pm-orchestrator, engineer-principal, quality-engineer
---

# An unmeasured number must not size a work package

A figure that has not been measured **on the current build** must not size a
work package, set an acceptance threshold, or justify a design. Measure first,
then scope. If the measurement is not available yet, the WP that produces it
comes first and everything downstream waits for it.

This applies to every number a WP leans on: a latency, a cost, a count, a rate,
a panel size, a retry bound. "The trace said", "the design doc says", "it's
obviously N" are all the same failure.

## Why

EPIC #4211 (2026-08-17) was a turnaround EPIC. Its dial set was sized against
two numbers, neither of which had been measured on a healthy build:

- **"A clean 7-contribution convene takes 20-24 minutes."** Taken from an
  analysis artifact produced while the drain was stalling. Measured on a
  working drain the same day: **4m41s**. There was never 20-24 minutes to cut —
  the figure was a symptom of the open defect, not the steady state.
- **"A 7-specialist panel runs `ceil(7/4)` = 2 sequential rounds."** The panel
  is **4**, by design and in every dispatch log line, and had been since the
  concurrency cap was raised 3→4 for a named four-specialist panel. So
  `ceil(4/4) = 1` round already, and the WP existed to remove a round that was
  not there.

Consequences, all in one day: one WP shipped a dial with no effect and a
tautological guard; one WP's headline AC was unreachable and had to be struck
at the QA gate; the EPIC's biggest dial was scoped to remove ~8 minutes from a
14-minute term that did not exist, built, eval'd, and rejected 0/5; and the
EPIC's exit gate was set to a target that turned out to be met before any dial
merged. Three of four dials were mis-sized. **The PM approved every one of
those sizings.**

The measurement that settled it took one engineer about ninety minutes and
existed as a WP the whole time — it was simply ordered *after* the work it was
supposed to size.

## How to apply

**PM, when framing:**

- Before writing an AC threshold, ask: *has anyone measured this on the build
  we are shipping against?* If not, the measuring WP is WP0 and it blocks the
  rest — not as a formality, as an ordering constraint.
- Quote the source in the WP body: `measured 2026-08-17 on <sha>, 3 runs` or
  `UNMEASURED — from <artifact>, must be confirmed by <WP>`. An unlabelled
  number reads as measured, and every reader downstream inherits it.
- Never restate a derived number as a premise. "20-24 min, of which 14 is
  integrate" is arithmetic on an unmeasured figure — it inherits the doubt and
  compounds it.

**Engineer, when a WP's premise is checkable:** check it before building. A
`dispatched=` log line or a queue attribute is minutes of work and is the
difference between building the right thing and building a no-op. Surface a
false premise as a consult-exception — it is not scope creep, it is the WP
being wrong.

**QA:** a WP whose premise is contradicted by the environment is **BLOCKED to
the PM**, not FAIL to the engineer. The build can be correct and the WP still
wrong; failing the engineer for that is both unjust and useless — there is no
rework instruction that fixes a bad premise.

**When the correction lands, restate the claim.** A mis-sized WP that still
merges (as headroom, say) must have its contribution recorded as zero where the
EPIC's exit gates can see it. Otherwise the EPIC inherits an acceleration
nobody delivered, and the reconciliation surfaces at the release gate — the
most expensive possible place.

## Related

- [`a-null-result-is-not-evidence.md`](a-null-result-is-not-evidence.md) — the
  same failure in its absence-shaped form.
- Spine invariant 2 (evals are the oracle) and invariant 5 (no false-green):
  both say the environment decides, not a document about the environment.
