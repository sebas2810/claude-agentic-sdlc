---
title: On a board not linked to the issues' repo, read the Status back with a project-item node query — `projectItems` comes back empty
status: active
scope: all-seats
added: 2026-09-01
last-confirmed: 2026-09-01
---

## Rule

Every dual-write ends with a read-back — that invariant is unchanged. But `gh issue view <n> --json labels,projectItems` only reports projects **linked to the issue's repository**. If your board is a personal/unlinked project, `projectItems` returns `[]` **even when the board `Status` is correctly set**. Read that half back with a targeted **project-item node query** instead. An empty `projectItems` on such a board is *not* evidence the write failed.

## Why

- Observed 2026-09-01 while scoping #4941: a board owned by a different account and not linked to the repository holding the issues. `Status = Scoped` was set and confirmed, yet `projectItems` read `[]`.
- Positive control, which is what makes the above evidence rather than a null result ([rule](a-null-result-is-not-evidence.md)): issues on the repo-**linked** board (project #4) return `projectItems = 1`; the unlinked one returns `0`.
- Not permissions (the token carried the `project` scope throughout): `repository.projectsV2` lists **only** the linked project, and `projectItems` surfaced only that one.
- Cost of getting it wrong: the seat believes the board half no-oped and re-writes it, or reports a false failure — and the "verified at the point of write" guarantee silently degrades to label-only.

## How to apply

Keep the item id that `project item-add` / `item-edit` already returned — never reach for the 300-item list to find it:

```bash
gh api graphql -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2Item {
  content { ... on Issue { number } }
  fieldValues(first:30){ nodes { ... on ProjectV2ItemFieldSingleSelectValue {
    name field { ... on ProjectV2SingleSelectField { name } } } } } } } }' -F id="$ITEM_ID" \
  --jq '.data.node | "#\(.content.number)", (.fieldValues.nodes[] | select(.field.name=="Status") | "Status = \(.name)")'
```

Still read the **label** half with `gh issue view <n> --json labels,assignees`; only the board half changes. Report which form you used, so the next seat can tell a genuine half-write from this artifact. **Do not overclaim the cause:** the observed board is *both* unlinked *and* cross-owner; those two were never disentangled, because separating them means linking a board (project-structure mutation, owner-gated). Treat "unlinked **or** cross-owner board → use the node query" as the trigger, and don't assert which one is load-bearing.

## Cautionary tale

The PM seat dual-wrote #4941 to `Scoped`, read back `projectItems: []`, and was one step from re-writing a board field that was already correct. The node query showed `Status = Scoped` all along. Had the seat trusted the documented read-back and "fixed" it, the report would have carried a phantom half-write — the exact false signal the read-back exists to prevent.
