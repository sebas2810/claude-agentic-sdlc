# CLAUDE.md — project briefing

This product is delivered with the **Agentic SDLC** (vendored at
[`agentic-sdlc/`](agentic-sdlc/)). Every Claude session working in this repo
starts by reading, in order:

1. [`agentic-sdlc/README.md`](agentic-sdlc/README.md) — the SDLC index
2. [`agentic-sdlc/agentic-operating-model.md`](agentic-sdlc/agentic-operating-model.md) — **the spine**; all seat authority derives from it
3. Your seat file — `agentic-sdlc/seats/<role>/KICKOFF.md` (this worktree's `.<instance>-seat.md`, injected at session start, names your role)
4. [`agentic-sdlc/feedback/INDEX.md`](agentic-sdlc/feedback/INDEX.md) (skim) + [`agentic-sdlc/learning-loop/CHANGELOG.md`](agentic-sdlc/learning-loop/CHANGELOG.md) (last few entries)

## House rules (hook-enforced where possible)

- **Always a PR — never push to `main`/`master`/`release/*`.**
- **No AI attribution in commits or PRs** (no Co-Authored-By footers).
- **Rebase on `origin/main` before every push.**
- **The board is the state**: discover work via the `status:*` label index
  (`/check`), dual-write every transition (label + board Status field).
- The seat that produced work never adjudicates it; nobody merges their own PR.

A PreToolUse guard (`.claude/hooks/guard-git.sh`, wired by bootstrap) blocks the
first three at the tool level. If it blocks you, satisfy the rule it cites —
never work around it.

## Product context

<!-- Replace this section with your product's brief: what it is, how to run it
     locally, the tech stack, where things live. Keep it tight — long CLAUDE.md
     files get skimmed; short ones get read. -->
