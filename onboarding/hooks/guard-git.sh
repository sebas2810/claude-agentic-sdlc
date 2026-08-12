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
# Repo scoping: a seat legitimately runs git against OTHER repositories (a
# cloned upstream, a scratch worktree). The state checks below therefore run in
# the directory the COMMAND targets — honouring `git -C <dir>` and a leading
# `cd <dir> &&` — not the hook's own cwd. Measuring the project repo while the
# command targets somewhere else produced false "N commits behind" blocks with
# no way past them.
#
# Escape hatch: AGENTIC_SDLC_SKIP_REBASE_CHECK=1 must be exported in the SEAT's
# environment (e.g. .env.local). The hook runs in its own process, so an inline
# `VAR=1 git ...` prefix never reaches it — that is why the previously
# documented per-command form silently did nothing.
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

# Resolve the directory this command actually operates on, so the state checks
# are never evaluated against the wrong repository:
#   `git -C <dir> ...`      -> <dir>
#   `cd <dir> && git ...`   -> <dir>
#   otherwise               -> the hook's cwd
TARGET_DIR="$(printf '%s' "$CMD" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)"
[ -n "$TARGET_DIR" ] || TARGET_DIR="$(printf '%s' "$CMD" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]&;|]+).*/\1/p' | head -1)"
[ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ] || TARGET_DIR="."
g() { git -C "$TARGET_DIR" "$@"; }

# git may carry options BEFORE the subcommand — `git -C <dir> push`, `git
# --no-pager push`, `git -c k=v push` — so match flags between git and the verb
# (an adjacency-only regex was a full bypass for `git -C . push origin main`).
GIT_VERB='git([[:space:]]+-[A-Za-z]([[:space:]]+[^[:space:]]+)?|[[:space:]]+--[A-Za-z0-9-]+(=[^[:space:]]*)?)*[[:space:]]+'

# ── 1 + 3: git push ───────────────────────────────────────────────────────────
if printf '%s' "$CMD" | grep -Eq "(^|[;&|[:space:]])${GIT_VERB}push"; then
  # protected ref named anywhere in the push (covers `origin main`, `HEAD:main`,
  # `refs/heads/main`, `origin master`, `release/x`, --force variants)
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]:/])(main|master|release/[^[:space:]]+)([[:space:]]|$)'; then
    block "never push to main/master/release/* — open a PR instead (feedback/workflow/always-pr-never-push.md)."
  fi
  CUR="$(g rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$CUR" in
    main|master) block "you are on '$CUR' — create a feature branch, push that, open a PR." ;;
  esac
  # 3: behind the cached origin/main → rebase first (best-effort, no network)
  if [ "${AGENTIC_SDLC_SKIP_REBASE_CHECK:-}" != "1" ] \
     && g rev-parse --verify -q origin/main >/dev/null 2>&1; then
    BEHIND="$(g rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
    if [ "${BEHIND:-0}" -gt 0 ]; then
      REPO="$(g rev-parse --show-toplevel 2>/dev/null || echo "$TARGET_DIR")"
      block "this branch is $BEHIND commit(s) behind origin/main in $REPO — 'git fetch origin main && git rebase origin/main', rerun gates, then retry (feedback/workflow/always-rebase-before-push.md). If that is not the repository you meant, check the -C / cd target."
    fi
  fi
fi

# ── 2: AI attribution in a commit ─────────────────────────────────────────────
if printf '%s' "$CMD" | grep -Eq "(^|[;&|[:space:]])${GIT_VERB}commit"; then
  if printf '%s' "$CMD" | grep -Eqi 'co-authored-by:[[:space:]]*claude|generated with .{0,3}claude code'; then
    block "no AI attribution in commits — drop the Co-Authored-By / Generated-with footer and commit again (feedback/workflow/no-claude-attribution.md)."
  fi
fi

exit 0
