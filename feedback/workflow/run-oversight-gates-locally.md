---
title: Run agent-oversight gates locally before pushing
status: active
scope: engineer
added: 2026-05-03
last-confirmed: 2026-05-13
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

On any PR touching your instance's gated paths, run your instance's **full** local gate suite before pushing — one command. The concrete command and the gated paths are your instance overlay's `engineering-standard.md`; e.g., the reference instance runs:

```bash
npm run gates:agents   # e.g. — the reference instance's gate suite; use YOUR instance's command
```

Run the full inventory, not a subset — running only a subset is not "running the gates" (three CI failures in one reference-instance session, #2161/#2162/#2172, came from following an older 2-gate version of this rule).

Fix any failures BEFORE the push. **Don't bypass gates** — fix the underlying issue.

## Why

- CI runs these same gates; a local pre-flight saves a CI cycle when you've broken them
- Drift gates catch docs lagging behind code (a frequent source of confused engineers)
- Type/coverage gates catch classes of bugs before CI ever sees them
- "It works locally, CI will catch the rest" is a poor habit — CI is for catching regressions, not for finding the bug you just wrote

## How to apply

After making changes, **commit first**, then before `git push`:

```bash
# In repo root — YOUR instance's gate command (see your overlay's engineering-standard.md)
<your gate command>

# If any gate FAILs, FIX the failure — don't push
# (e.g., in the reference instance: README drift → update the agent's README;
#  type coverage → add the missing annotations; skill-content drift → re-run the hash updater)

# Then push
git push
```

## What "fix the failure" means

- A drift gate → edit the doc to describe what the code currently does (don't just delete the doc's claim)
- A coverage gate → add the missing types/tests, not an exclusion
- If you genuinely think the gate is wrong, file an issue + DON'T bypass — discuss before adjusting

## NO --no-verify or skip-gate flags

You're not allowed to:
- `git commit --no-verify` to bypass pre-commit hooks
- `git push --no-verify` to bypass pre-push hooks
- Add a skip-gate marker to the PR

If the gate is wrong: fix the gate (separate PR). If your code is wrong: fix the code. There's no third option.

## Cautionary tale

Pre-rule: engineer-seat pushed a `feat/<n>` PR with a drift gate ignored (bypassed locally to "save time"). CI caught it. Engineer pushed a fix. CI caught a related type-coverage issue (cascade from the first). Engineer pushed a fix. ~25 min of CI cycles vs ~3 min of local runs upfront.

Rule cost: 90 seconds local pre-flight. Saves: 20+ min per occurrence + reviewer's attention.

## Enforcement (instance-specific, promoted from prose to gate)

An instance can promote this rule from prose to a machine gate — e.g., the reference instance wires a PreToolUse hook (`.claude/hooks/bash-guard.mjs`) that **blocks** any `git push` whose committed diff touches gated paths unless its gate suite has passed against that exact diff (a patch-id stamp in `.git/gates-pass`, so a clean rebase doesn't invalidate it — only changing the actual diff does). The framework ships only the generic git guard; wire your own gate-enforcement hook in your instance.
