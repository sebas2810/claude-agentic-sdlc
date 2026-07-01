---
title: Work preparation — the PM→SM prep pipeline
status: active
scope: workflow
---

# Work preparation — from Epic to Ready

How a strategic intent becomes dispatch-ready, nested issues. The PM **book-ends** the
pipeline (authors the Epic + approves Ready); the **SM does the middle** (explodes the
Epic into nested, detailed issues). The split exists so the PM stays on roadmap +
adjudication while the SM does the issue-shaping toil — without either touching the
other's authority: **the PM owns intent + AC; the SM owns readiness + flow.**

## The pipeline

| # | Step | Owner | Board move |
|---|---|---|---|
| 1 | **Frame the Epic** — outcome · why · scope · success, and a **WP table** (one row per Work Package: title · intent · **AC** · priority). | **PM** | Epic in the EPICS view |
| 2 | **Explode → nest** — read the WP table; for each WP create a **sub-issue** nested under the Epic, capture the Definition of Ready (routing/`seat:` label · dependencies · context + links · the AC copied faithfully from the WP) — then **write the Issue # back into the Epic's WP table**. | **SM** | sub-issues created in `Backlog` |
| 3 | **Review → approve → Ready** — check each issue against the Epic's intent + AC; approve, or bounce a gap back to step 2. | **PM** | `Backlog → Scoped` |
| 4 | **Dispatch** — assign each Scoped issue to the producer seat for its label. | **SM** | `Scoped → In Progress` |

The **Epic's WP table is the contract and the index**: the PM authors its rows; the SM fills
the `Issue #` column as it creates each sub-issue. One glance at the Epic shows every WP and
its issue, with live status.

## The Epic body — WP table format

```markdown
## Work Packages
| WP | Title | Intent (what / why) | Acceptance criteria | Priority | Seat | Issue |
|----|-------|---------------------|---------------------|----------|------|-------|
| 1  | …     | …                   | • AC1 • AC2 • AC3   | P1       | —    | —     |
| 2  | …     | …                   | • …                 | P2       | —    | —     |
```

- **PM authors** columns *WP · Title · Intent · Acceptance criteria · Priority* (and may suggest *Seat*).
- **SM fills** *Seat* (final routing) and *Issue* (the `#` of the sub-issue it creates), and nests each issue under the Epic.

## Who owns what — and why it's safe

- **AC is the PM's, always.** The PM adjudicates at merge against the AC it pre-committed
  ([state machine](state-machine.md), produce ≠ adjudicate). The SM **copies** the AC into the
  issue faithfully and may flag it as untestable — but never **authors or rewrites** it. A product
  or AC gap is **bounced to the PM**, not invented by the SM.
- **Readiness is the SM's.** Everything that makes an issue dispatchable but isn't product intent —
  routing, dependencies, sizing, context, links, the nesting — is the SM completing the
  [Definition of Ready](definition-of-ready-done.md).
- **The Ready gate (`Backlog → Scoped`) is the PM's.** The SM prepares; the PM approves. So no work
  becomes dispatchable without the PM's sign-off, and the PM is freed from authoring every issue by
  hand.

## Boundaries (the bounce rules)

- SM hits a missing/ambiguous AC, an unclear outcome, or a scope question → **bounce to the PM** (comment on the Epic; do not guess).
- PM wants a WP split/resized for flow → that's an SM proposal the PM approves; the SM never silently re-scopes product intent.
- Neither merges work they prepared the readiness of without the independent gates (produce ≠ adjudicate, 4-eye) — see [state machine](state-machine.md).

---
Hierarchy: [`hierarchy.md`](hierarchy.md) · Ready/Done: [`definition-of-ready-done.md`](definition-of-ready-done.md) · Priority: [`prioritization.md`](prioritization.md) · Roles: [`../seats/SQUAD.md`](../seats/SQUAD.md).
