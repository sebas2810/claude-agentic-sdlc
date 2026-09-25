# Seat labels mirror the board Seat field — the Seat is the agent, the Assignee is the human

**Rule.** Every producer seat gets a `seat:<name>` **label** (e.g. `seat:finn`,
`seat:cas`) and a matching value in the board's **`Seat` field** (TEXT — the field the
shipped [execution-board template](../../workflow/project-templates/execution-board.json)
creates), and the scoping write keeps them in lockstep: `Backlog → Scoped` is a
**quadruple write** — `status:scoped` label + board Status field + board Seat field +
`seat:<name>` label. The scoping write **never touches the assignee**. Producers discover work
with the documented cheap query (`label:status:scoped label:seat:<name>`); the GitHub
**assignee field is never used for seat routing**.

**Why.** Multiple agent seats typically share ONE GitHub account, so the assignee
field structurally cannot distinguish them. Instances that skip the seat labels leave
producers with no label mirror for the Seat field — they fall back to the assignee
and conclude "assigned to someone else / no unassigned work" on their own queue
(observed 2026-07-05: a producer idled on three freshly-scoped items). The board field
is the record; the label is the index — the same design as `status:*`.

**Assignee semantics: the human owner, at every altitude.** The assignee field
names the accountable human (the owner, or the engineer who leads the agents on that
item) on Initiatives, Epics, Stories and Tasks alike. It is set when the issue is
created and changed only by a human decision (reassigning *is* the handoff). No seat
writes it on claim, block, scoping or verification, and no discovery query reads it:
the agent is the **Seat** (field + `seat:*` label), the human is the **Assignee**.

**Rework is its own label.** A QA FAIL sends the item `→ status:scoped` and adds the
`rework` label in the same write; the producer's rework query is
`status:scoped` + `seat:<name>` + `rework`, and the re-deliver removes the label. This
replaces the old "scoped + assigned = rework" signal, which forced an unconditional
assignee strip at scoping (observed 2026-08-03: ten owner-assigned stories read as QA
bounce-backs). With rework carried by a label, "freshly scoped" and "QA-rejected" stay
distinguishable while the assignee keeps meaning the owner (decided 2026-09-25).

**Instance setup.** `bootstrap.sh` creates the `seat:<name>` labels alongside the
status labels for every seat configured in `sdlc.config`; the `rework` label ships in
`workflow/project-templates/labels.json`.
