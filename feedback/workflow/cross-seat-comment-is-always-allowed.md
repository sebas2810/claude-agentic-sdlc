---
title: A finding-only comment on ANY issue is always allowed — commenting is not mutating
status: active
scope: all-seats
added: 2026-08-07
last-confirmed: 2026-08-08
---

> Stands under the Agentic SDLC spine ([`../../agentic-operating-model.md`](../../agentic-operating-model.md)), invariant 7: "the shared thread is the bus, the human is never the relay."

## Rule

`gh issue comment` / `gh pr comment` on an issue or PR your seat doesn't own is **always** permitted — read-and-speak is the coordination bus, not a scope violation. Only *mutation* of another seat's issue (labels, status, assignee, close) stays role-gated. Never let "stay in your lane" self-censor a finding-only comment.

## Why

- 2026-07-14 (surfaced by QA on a live instance): a seat found the exact root cause of a live P0 (`customer_locked` defaults `False` on a swallowed HTTP-read exception), tried to post it as a finding-only comment, and self-blocked believing cross-seat GitHub writes were restricted. The finding never reached the thread. The assigned engineer re-diagnosed from scratch, refuted the wrong hypothesis, and shipped a symptom fix. QA failed it. The P0 cost a full extra round-trip.
- **The real mechanism, found by QA reproducing it live against this exact issue** (an earlier version of this rule guessed "an unanswered client-side permission prompt" — wrong, and corrected here): `.claude/hooks/bash-guard.mjs`'s rebase-check matched `/\bgit\s+push\b/` against the **whole raw command string**, including text inside quotes and heredocs. It needs no `gh`-specific logic to block a `gh` command — any command whose *text* merely contains the phrase "git push" gets treated as a push. A QA finding that quotes this hook's own block message (which itself contains "git push") is unpostable by construction; two plain `echo` commands differing only in whether their text mentions the phrase reproduced it with no git involved at all.
- Conflating "I shouldn't decide/mutate this" with "I shouldn't even speak on this" breaks the one invariant the whole operating model rests on.

## How to apply

- Found something relevant to an issue you don't own (root cause, a blocker, a cross-cutting risk)? Post it: `gh issue comment <n> --body "..."`, signed with your seat name. That's it — no ownership check required for a comment.
- Still don't touch another seat's `status:*`/`priority:*` labels, assignee, or close state unless your role's gate explicitly covers it (QA verifying, SM merging, PM scoping — per the normal role matrix).
- If a comment genuinely can't land (auth/network failure, not a permission question), fall back to `docs/.handoff/YYYY-MM-DD-<title>.md` (gitignored, local) and say so explicitly in your session report — never silently drop the finding.
- `.claude/hooks/bash-guard.mjs` now masks quoted-string and heredoc content (position-preserving, so `&&`/`;`/`||` inside a quote no longer desyncs segment splitting either) before testing for `git push` — a comment whose body quotes any block message, PR text, or prose containing a semicolon is no longer indistinguishable from an actual push. Regression test: `.claude/hooks/bash-guard.test.mjs`. (A `permissions.allow` entry for `gh issue/pr comment` was the first-guessed fix — QA proved it would not have helped: an allowlist doesn't bypass a `PreToolUse` hook. Self-editing `.claude/hooks/*.mjs` is itself classifier-gated for an agent — apply hook changes as the human.)

## Cautionary tale

RJ had the right answer to a live P0 and no channel to say so. The tooling — or the seat's own over-cautious reading of "stay in your lane" — turned a one-comment handoff into a full re-diagnosis cycle. The fix isn't cleverness, it's permission: commenting was never actually restricted, and now it's explicit that it never should be.
