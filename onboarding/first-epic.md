> **The guided first epic** — seeded by `bootstrap.sh` so a brand-new instance
> can run one full pass through the loop (Frame → Steer → Build → Verify →
> Adjudicate → Merge) in about 30 minutes, on a work item that exists in every
> repo. Delete this epic once the loop has run; it has done its job.

## Frame (owner)

Ship a one-page `PRODUCT.md` at the repo root that states what this product is,
who it is for, and what is being built now. The point of the epic is **not** the
file — it is that every seat runs its part of the loop once, end to end, before
real feature work starts.

## Suggested stories (the SM explodes these into sub-issues)

1. **Story: PRODUCT.md one-pager** — create `PRODUCT.md` at the repo root.
   Pre-committed acceptance criteria (falsifiable — QA verifies each line):
   - [ ] `PRODUCT.md` exists at the repo root on the PR branch
   - [ ] it contains exactly these three H2 sections: `## Vision`, `## Users`, `## Now / Next / Later`
   - [ ] every section has real content (no TODO / placeholder text)
   - [ ] the file is ≤ 120 lines
   - [ ] the PR body uses the template (`## What` / `## Closes` / `## Retires` / `## Test plan`) and `## Retires` reads "Nothing — additive"

2. **Story: README points at PRODUCT.md** — one line near the top of the README
   linking `PRODUCT.md`.
   - [ ] README links to `PRODUCT.md` within its first 25 lines
   - [ ] the link resolves on the PR branch

## How to run it (the whole point)

1. **PM seat** — `/check`: frame story 1 (`status:backlog → status:scoped`,
   dual-write label + board Status), posting the AC above as the steer.
2. **Engineer seat** — `/check`: claim it, branch off `origin/main`, build,
   open ONE PR, deliver (`status:delivered`), post the ready-signal.
3. **Quality seat** — `/check`: verify each AC line on the PR branch,
   post per-criterion PASS/FAIL → `status:tested` (or FAIL → `status:scoped`).
4. **Scrum-Master seat** — `/check`: validate (QA PASS · CI green · PR clean),
   squash-merge with `--delete-branch` → `status:merged`, then drive
   `→ status:released`. Also: explode story 2 as a sub-issue if not yet done.
5. Repeat for story 2 — the second pass is where the rhythm becomes natural.

When both stories are `Released`, close this epic and frame your first real one
(`workflow/state-machine.md`). If any step surprised you, capture it as a rule
(`learning-loop/how-to-capture-a-rule.md`) — that is the learning loop working
on day one.
