# Seat labels mirror the board Agent field — routing never reads the GitHub assignee

**Rule.** Every seat on the board's Agent (seat) single-select field gets a matching
`seat:<key>` **label** (e.g. `seat:rj`, `seat:seb`), and the scoping write keeps them
in lockstep: `Backlog → Scoped` is a **quadruple write** — `status:scoped` label +
board Status field + board Agent field + `seat:<key>` label. Producers discover work
with the documented cheap query (`label:status:scoped label:seat:<key>`); the GitHub
**assignee field is never used for seat routing**.

**Why.** Multiple agent seats typically share ONE GitHub account, so the assignee
field structurally cannot distinguish them. Instances that skip the seat labels leave
producers with no label mirror for the Agent field — they fall back to the assignee
and conclude "assigned to someone else / no unassigned work" on their own queue
(observed 2026-07-05: a producer idled on three freshly-scoped items). The board field
is the record; the label is the index — the same design as `status:*`.

**Assignee semantics (unchanged, now exclusive).** The assignee field carries exactly
two meanings: an engineer **self-assigns at claim** (`Scoped → In Progress`), and QA
**leaves it on a FAIL** so the rework query re-pulls it. Therefore a scoped item with
an assignee means REWORK — never "reserved". Owner/stakeholder visibility assignment
belongs on EPICs only, and is stripped when a story is scoped.

**Instance setup.** `create-instance.sh` scaffolds must create the `seat:<key>` labels
alongside the status labels for every configured seat.
