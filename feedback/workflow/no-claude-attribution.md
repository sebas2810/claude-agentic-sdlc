---
title: No Claude attribution in commits or PRs
status: active
scope: all-seats
added: 2026-04-15
last-confirmed: 2026-05-13
---

> Stands under the ORBIS Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)).

## Rule

Drop these from all commits and PRs:

- `Co-Authored-By: Claude <noreply@anthropic.com>` (any variation)
- `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
- Any other "this was written by Claude" footer

Commits/PRs are attributed to the **human author** (the seat owner running Claude Code), not to Claude.

## Why

- ORBIS git history represents work the human team produced, with Claude as a tool — same as IDE autocomplete or copilot. Tools don't get authorship.
- Cleaner `git blame` / `git log` — the human is the actual decision-maker / reviewer-of-record
- External-readability — when Capgemini leadership reviews the changelog, Claude attribution adds noise

## How to apply

- Engineer: use plain `git commit -m "..."` with the message you want. Don't paste Anthropic's default footer.
- Top PM / Sub-PM: when running `gh pr create` or `gh issue comment`, write the body as you mean it — no automated footer.
- If Claude Code suggests adding the attribution: refuse. It's a default in the CLI's prompt; we override it for this repo.

## Why this rule is in the agentic-sdlc folder

Claude Code's default Bash tool guidance suggests adding the footer. Without this rule documented in the repo, every new team member would re-introduce it. The rule is the override.

## Enforcement (promoted from prose to gate, 2026-06-12)

The `.claude/hooks/bash-guard.mjs` PreToolUse hook **blocks** any `git commit` whose message contains `Co-Authored-By: … Claude` or `Generated with … Claude Code`. New team members can no longer re-introduce the footer by accident.
