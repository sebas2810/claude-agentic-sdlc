# Seat labels mirror the board Seat field — routing never reads the GitHub assignee

**Rule.** Every producer seat gets a `seat:<name>` **label** (e.g. `seat:finn`,
`seat:cas`) and a matching value in the board's **`Seat` field** (TEXT — the field the
shipped [execution-board template](../../workflow/project-templates/execution-board.json)
creates), and the scoping write keeps them in lockstep: `Backlog → Scoped` is a
**quintuple write** — `status:scoped` label +
board Status field + board Seat field + `seat:<name>` label + an **unconditional
assignee strip** (`gh issue edit <n> --remove-assignee <login>`). Producers discover work
with the documented cheap query (`label:status:scoped label:seat:<name>`); the GitHub
**assignee field is never used for seat routing**.

**Why.** Multiple agent seats typically share ONE GitHub account, so the assignee
field structurally cannot distinguish them. Instances that skip the seat labels leave
producers with no label mirror for the Seat field — they fall back to the assignee
and conclude "assigned to someone else / no unassigned work" on their own queue
(observed 2026-07-05: a producer idled on three freshly-scoped items). The board field
is the record; the label is the index — the same design as `status:*`.

**Assignee semantics (unchanged, now exclusive).** The assignee field carries exactly
two meanings: an engineer **self-assigns at claim** (`Scoped → In Progress`), and QA
**leaves it on a FAIL** so the rework query re-pulls it. Therefore a scoped item with
an assignee means REWORK — never "reserved". Owner/stakeholder visibility assignment
belongs on EPICs only, and the scoping write strips it **unconditionally** — not as a
courtesy: observed 2026-08-03, ten freshly-scoped stories carrying an owner-assignment
each presented to the producer's `/check` as a QA bounce-back, with no QA comments to
act on. "Freshly scoped" and "QA-rejected" must stay distinguishable, and the strip is
what keeps them so.

**Instance setup.** `bootstrap.sh` creates the `seat:<name>` labels alongside the
status labels for every seat configured in `sdlc.config`.
