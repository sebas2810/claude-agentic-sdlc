---
title: Repo settings changes need explicit user approval
status: active
scope: pm
added: 2026-04-22
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

Mutations to repo settings need explicit Sebastiaan approval before firing. Even top-PM seat asks before:

- `gh api PATCH /repos/.../*` — any settings mutation
- `gh label create / delete` — label set changes (`gh label edit` for existing labels is fine)
- `gh project ...` — project board structure mutations (status field options, new fields, etc.)
- Branch protection rules
- New release branch creation (`release/vN.M`)
- Production deploys

## Why

- These actions affect ALL team members, not just one EPIC
- Most are hard to reverse cleanly (label deletion loses history, branch protection drift can let bad code merge)
- "Just one tiny tweak" → drift over time → settings nobody remembers configuring
- Sebastiaan owns the strategic shape of the repo; he should approve shape-changes

## How to apply

When you hit one of these:

```bash
# Don't run the mutation. Instead, propose:
echo "TOP PM CALL NEEDED: repo settings change

Action: <command>
Reason: <why>
Reversibility: <how to undo if wrong>

OK to fire?"
```

Wait for explicit "yes, fire it" before running.

## Exceptions (auto-approved by this rule's existence)

- Status flips on Project #4 (per [`../../instance/orbis/rules/flip-epic-status-when-starting.md`](../../instance/orbis/rules/flip-epic-status-when-starting.md)) — these are routine
- Existing-label-set assignment to issues/PRs — routine
- `gh label edit` of an existing label's description/color — routine (but ask before creating new ones)
- Issue body editing on EPICs you own — routine

## Cautionary tale

Pre-rule: PM-seat created several labels mid-session ("trying things out"), then deleted some. Each one drifted the label list. Sebastiaan noticed weeks later when he was looking for a label he remembered seeing. Lost data + drift.

Rule cost: 30 seconds for explicit approval per settings change. Benefit: settings drift = zero.
