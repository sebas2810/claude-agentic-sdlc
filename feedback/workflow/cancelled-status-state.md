# `Cancelled` — the terminal state for closed-but-not-shipped work

**Rule.** The board has a terminal `Cancelled` status, **distinct from `Released`**, for
work that closes **without shipping** — duplicates, won't-dos, obsoleted scope, or
premise-invalidated issues. It is the board mirror of GitHub's `NOT_PLANNED` close
reason. `Released` means *actually shipped*; `Cancelled` means *closed, nothing
shipped*. **Never park cancelled/duplicate work in `Released`.**

**The two terminals:**
- `Released` — merged **and** deployed. The success terminal.
- `Cancelled` — closed as `NOT_PLANNED` (duplicate · won't-do · obsolete ·
  premise-invalidated). The non-success terminal.

**Transition.** Any state → `Cancelled` when an issue is closed as `NOT_PLANNED`. The
close and the board flip are one write: `gh issue close --reason "not planned"` + board
Status → `Cancelled` + a `status:cancelled` label to mirror (same index-vs-record design
as every other `status:*` — the board field is the record, the label is the index).

**Why.** Without it, closed-but-not-shipped work gets shoved into `Released` (observed
in the reference instance, 2026-07-12: a duplicate created off a stale read landed in
`Released` because there was nowhere else). That corrupts every metric keyed on
`Released` — throughput, cycle-time, and any release / cost-per-outcome analytics built
on them: if cancelled work counts as "released," the "cost per successful outcome"
denominator is wrong at the source. A clean `Cancelled` bucket keeps `Released` meaning
*shipped*.

**How to apply.**
- Closing a duplicate / won't-do / obsolete / premise-invalid issue → `Cancelled`, not
  `Released` and not left in `Blocked`.
- SM `Blocked`-sweep: a `Blocked` item whose consult-exception resolves to *"this
  shouldn't be built"* (duplicate, false premise) → `Cancelled`. (Contrast a QA **FAIL**,
  which is actionable rework → `Scoped`, not a terminal.)
- Metrics exclude `Cancelled` from throughput and cost-per-outcome — it is a deliberate
  drop, not a delivered outcome and not a failure to action.
- The Board view hides it (the canonical filter excludes `Cancelled` along with
  `Backlog`, `Merged`, `Released`) — see
  [`../../workflow/project-boards.md`](../../workflow/project-boards.md).
