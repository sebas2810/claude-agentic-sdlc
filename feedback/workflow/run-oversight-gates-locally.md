---
title: Run agent-oversight gates locally before pushing
status: active
scope: engineer
added: 2026-05-03
last-confirmed: 2026-05-13
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

On any PR touching `agents/`, `infra/specialists/`, `infra/orchestrators/`, or agent READMEs, run the **full** local gate inventory before pushing — one command:

```bash
npm run gates:agents
```

This runs all 11 blocking local gates (+ 2 report-only) and, on all-pass, stamps the diff's patch-id so the push guard lets the push through. Running only a subset is not "running the gates" — three CI failures in one session (#2161/#2162/#2172) came from following an older 2-gate version of this rule.

Fix any failures BEFORE the push. **Don't bypass gates** — fix the underlying issue.

## Why

- CI runs these same gates; a local pre-flight saves a CI cycle when you've broken them
- The README drift gate catches docs lagging behind code (a frequent source of confused engineers)
- The type coverage gate ensures Strands tool definitions stay typed (caught a #-of-bugs in the original wire-up)
- "It works locally, CI will catch the rest" is a poor habit — CI is for catching regressions, not for finding the bug you just wrote

## How to apply

After making changes, **commit first**, then before `git push`:

```bash
# In repo root
npm run gates:agents

# If any gate FAILs, FIX the failure — don't push
# - README drift: update the agent's README to match what the code does
# - Type coverage: add missing type annotations to the affected @tool definition
# - Runtime secrets: add the `# runtime-secret-ignore` marker where legitimate
# - Skill content drift: re-run the skill-hash updater after SKILL.md edits

# Then push
git push
```

The pass-stamp is computed from the committed diff (`origin/main...HEAD`, patch-id based), so a clean rebase does not invalidate it — only changing your actual diff does.

## What "fix the failure" means

- README drift → edit the README to describe what code currently does (don't just delete the README's claim)
- Type coverage → add Pydantic models / type annotations to the @tool args + return shape
- If you genuinely think the gate is wrong, file an issue + DON'T bypass — discuss before adjusting

## NO --no-verify or skip-gate flags

You're not allowed to:
- `git commit --no-verify` to bypass pre-commit hooks
- `git push --no-verify` to bypass pre-push hooks
- Add `skip-agent-oversight` to the PR

If the gate is wrong: fix the gate (separate PR). If your code is wrong: fix the code. There's no third option.

## Cautionary tale

Pre-rule: engineer-seat pushed a `feat/<n>` PR with the README drift gate ignored (bypassed locally to "save time"). CI caught it. Engineer pushed a fix. CI caught a related type-coverage issue (cascade from the first). Engineer pushed a fix. ~25 min of CI cycles vs ~3 min of local runs upfront.

Rule cost: 90 seconds local pre-flight. Saves: 20+ min per occurrence + reviewer's attention.

## Enforcement (promoted from prose to gate, 2026-06-12)

The `.claude/hooks/bash-guard.mjs` PreToolUse hook **blocks** any `git push` whose committed diff touches `agents/**`, `docs/agents/**`, or agent-adjacent Lambda code unless `npm run gates:agents` has passed against that exact diff (patch-id stamp in `.git/gates-pass`). "I ran the gates" is now verified, not claimed.
