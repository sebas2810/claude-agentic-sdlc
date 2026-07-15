#!/usr/bin/env bash
#
# guard-git.sh — the framework's non-negotiables, enforced at the tool level.
# Wired by bootstrap.sh as a Claude Code PreToolUse hook on the Bash tool
# (product-root .claude/settings.json). Blocks, before they happen:
#
#   1. any push to main / master / release/*        (always a PR — never direct)
#   2. AI attribution in commit messages            (no Co-Authored-By: Claude)
#   3. pushing a branch that is behind origin/main  (rebase first; best-effort —
#      checked against the locally-cached origin/main, never fetches)
#
# Contract (Claude Code hooks): the tool call arrives as JSON on stdin;
# exit 2 blocks the call and stderr is fed back to the seat; exit 0 allows.
# Fails OPEN on missing jq / unparseable input — a guard must never brick a seat.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
IN="$(cat 2>/dev/null || true)"
CMD="$(printf '%s' "$IN" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || exit 0
case "$CMD" in *git*) : ;; *) exit 0 ;; esac   # cheap prefilter: only git commands

block() { printf 'BLOCKED (agentic-sdlc guard): %s\n' "$1" >&2; exit 2; }

# ── 1 + 3: git push ───────────────────────────────────────────────────────────
if printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+push'; then
  # protected ref named anywhere in the push (covers `origin main`, `HEAD:main`,
  # `origin master`, `release/x`, --force variants)
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]:])(main|master|release/[^[:space:]]+)([[:space:]]|$)'; then
    block "never push to main/master/release/* — open a PR instead (feedback/workflow/always-pr-never-push.md)."
  fi
  CUR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$CUR" in
    main|master) block "you are on '$CUR' — create a feature branch, push that, open a PR." ;;
  esac
  # 3: behind the cached origin/main → rebase first (best-effort, no network)
  if git rev-parse --verify -q origin/main >/dev/null 2>&1; then
    BEHIND="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
    if [ "${BEHIND:-0}" -gt 0 ]; then
      block "this branch is $BEHIND commit(s) behind origin/main — 'git fetch origin main && git rebase origin/main', rerun gates, then push (feedback/workflow/always-rebase-before-push.md)."
    fi
  fi
fi

# ── 2: AI attribution in a commit ─────────────────────────────────────────────
if printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+commit'; then
  if printf '%s' "$CMD" | grep -Eqi 'co-authored-by:[[:space:]]*claude|generated with .{0,3}claude code'; then
    block "no AI attribution in commits — drop the Co-Authored-By / Generated-with footer and commit again (feedback/workflow/no-claude-attribution.md)."
  fi
fi

exit 0
