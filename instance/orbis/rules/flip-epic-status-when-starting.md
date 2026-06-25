---
title: Flip EPIC Project status to In Progress BEFORE the first PR
status: active
scope: pm
added: 2026-04-29
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../../agentic-operating-model.md`](../../../agentic-operating-model.md)).

## Rule

When an EPIC's first PR is about to open, **move its row in Project #4 from `Ready` → `In Progress` BEFORE opening the PR.**

## Why

- Stakeholder visibility — the project board is the strategic view; lagging-status flips defeat the purpose
- Avoids "is this in flight?" coordination questions
- Trivial to do; easy to forget

## How to apply

```bash
# Get Project #4 ID + field IDs
PROJECT_ID=$(gh api graphql -f query='{ user(login:"sebas2810"){ projectV2(number:4){ id } } }' --jq '.data.user.projectV2.id')

# Find the item ID for your EPIC issue
ITEM_ID=$(gh api graphql -f query="{ user(login:\"sebas2810\"){ projectV2(number:4){ items(first:200){ nodes{ id content { ... on Issue { number } } } } } } }" \
  --jq ".data.user.projectV2.items.nodes[] | select(.content.number==<EPIC_ISSUE_#>) | .id")

# Set status to In Progress
STATUS_FIELD=PVTSSF_lAHOANloic4BVy2gzgrqJJk      # Project #4's Status field
IN_PROGRESS_OPT=47fc9ee4                          # the In Progress option

gh api graphql -f query="mutation { updateProjectV2ItemFieldValue(input: { 
  projectId: \"$PROJECT_ID\", 
  itemId: \"$ITEM_ID\", 
  fieldId: \"$STATUS_FIELD\", 
  value: { singleSelectOptionId: \"$IN_PROGRESS_OPT\" } 
}) { projectV2Item { id } } }"
```

(IDs are stable per project; once you've grabbed them once, they don't change.)

## Then open the PR

Your engineer can now open the PR knowing the project board shows the EPIC as active.

## When you forget

If the PR already opened and the status is still `Ready`, flip it ASAP. The rule is "before first PR" because that's the easiest checkpoint to remember.

## Closing the loop

When the EPIC closes (master + all sub-issues done), top PM moves the row to `Done`. Sub-PM can also do this for their own EPICs.
