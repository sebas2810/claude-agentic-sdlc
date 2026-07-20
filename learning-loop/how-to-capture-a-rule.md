# How to Capture a Rule (the learning loop)

> Stands under the Agentic SDLC spine ([`../agentic-operating-model.md`](../agentic-operating-model.md)).

When you discover something worth preserving across sessions — capture it as a feedback rule. This is the SYSTEM that makes the team smarter over time.

## When to capture

| Signal | Example | Category |
|---|---|---|
| PR rolled back / required hotfix | #743 → #746 edge-runtime; #820 slug conflict | `feedback/architecture/` |
| Same correction twice in a session | "again, smoke evidence needs the deploy URL not just CI green" | `feedback/workflow/` |
| Cross-tool gotcha (stack-specific) | AWS Health AGW stage tags; ECR auth flake | instance overlay: `instance/<you>/rules/` |
| Workflow refinement that worked unexpectedly well | "branch-per-EPIC saved 5× CI cost" | `feedback/workflow/` |
| Authority calibration discovered | "PM may build + merge its own low-stakes docs/config" | `seats/<role>/KICKOFF.md` |
| Known false-positive that fooled someone (env-specific) | DEV scale-to-zero smoke probe | instance overlay: `instance/<you>/rules/` |

## The format

Every rule file follows this shape:

```markdown
---
title: <one-line rule statement>
status: active           # active | deprecated
scope: <which seat(s)>   # all-seats / pm / engineer
added: <YYYY-MM-DD>
last-confirmed: <YYYY-MM-DD>
---

## Rule
<1-3 sentences: what to do or not do>

## Why
<2-5 bullets: the reason, ideally including a past incident>

## How to apply
<concrete examples, commands, anti-patterns>

## Cautionary tale (optional but recommended)
<the past incident in 2-4 sentences>
```

Keep it ≤30 lines. Tight, action-oriented, scannable.

## The PR pattern

```bash
# 1. Branch off main
git checkout -B chore/playbook-<rule-name> origin/main

# 2. Write the rule under the right subfolder
$EDITOR agentic-sdlc/feedback/<category>/<rule-slug>.md

# 3. Add the index entry
$EDITOR agentic-sdlc/feedback/INDEX.md

# 4. Add the CHANGELOG entry
$EDITOR agentic-sdlc/learning-loop/CHANGELOG.md

# 5. Commit + push + PR
git add agentic-sdlc/
git commit -m "chore(playbook): add <rule-name>"
git push -u origin chore/playbook-<rule-name>
gh pr create --title "chore(playbook): add <rule-name>" --body "<short context>"
```

PR title MUST start with `chore(playbook):` so auto-merge logic can recognise it.

## Auto-merge for `chore(playbook):` PRs

PRs that:
- Have title prefix `chore(playbook):`
- Only touch `agentic-sdlc/`
- Have CI green

→ Auto-merge after CI passes. No PM review click needed (the lightweight "no bureaucracy" pattern the owner called for).

PRs touching anything outside `agentic-sdlc/` use normal review flow.

**Auto-merge is instance-wired, not framework-shipped.** The framework does not ship the workflow; an instance that wants it adds its own `.github/workflows/` job that verifies the title prefix + docs-only file list and enables squash auto-merge (which fires once required checks pass) — the reference instance wired one on 2026-06-12 as `playbook-auto-merge.yml`. Without it, `chore(playbook):` merges are manual (via the SM, as usual).

## Where the rule goes

| Type | Folder |
|---|---|
| Workflow rules (PR conventions, signal protocols, etc.) | `feedback/workflow/` |
| Hard architectural constraints (portable) | `feedback/architecture/` |
| Stack/env-specific practices (operational gotchas, deploy quirks) | instance overlay: `instance/<you>/rules/` |
| Rules that only apply to one seat | the matching `feedback/<area>/`, with `scope:` frontmatter naming the seat |
| Authority calibration (what a seat can/cannot do) | `seats/<role>/KICKOFF.md` (edit, not add) |
| Escalation protocol changes | `seats/<role>/KICKOFF.md` (edit, not add) |
| Onboarding flow refinements | `onboarding/` |

## When you're not sure if it's worth a rule

Ask: *"Will the next session repeat this mistake without this rule?"*

If yes → write the rule.  
If no → don't add noise to the playbook.

We're aiming for **<50 active rules at any time**. Beyond that, signal-to-noise tanks.

## Pruning stale rules

Quarterly review (or anytime a rule feels stale):

1. Mark frontmatter `status: deprecated` with `deprecated-reason: <why>`
2. Open `chore(playbook): deprecate <rule-name>`
3. After 30-day grace, delete + add CHANGELOG entry

## Confirming a rule still applies

When you USE a rule and it works as expected, update `last-confirmed: <today>` in the frontmatter. Helps tell live rules from forgotten ones.

This update doesn't need a PR — fold it into the next PR that touches related files.
