#!/usr/bin/env bash
#
# guard-git.sh — the framework's non-negotiables, enforced at the tool level.
# Wired by bootstrap.sh as a Claude Code PreToolUse hook on the Bash tool
# (product-root .claude/settings.json). Blocks, before they happen:
#
#   1. any push to main / master / release/*        (always a PR — never direct)
#   2. AI attribution in commit messages            (no Co-Authored-By: Claude)
#   3. pushing a branch that is behind its base     (rebase first; best-effort —
#      checked against the locally-cached ref, never fetches)
#   4. `gh pr merge --admin`                        (branch-protection bypass)
#   5. a configured pre-push gate that has not passed for the current diff
#
# THIS IS THE ONLY PUSH-INTERCEPTING HOOK AN INSTANCE SHOULD RUN. A second,
# forked implementation drifts silently: it keeps blocking the obvious cases
# while quietly losing a rule the other copy learned, and every signal stays
# green. That is not hypothetical — a forked copy lost the pre-verb bypass fix
# below and left "never push to a protected ref" fully bypassable via
# `git -C <dir> push origin main` until someone happened to read the file.
# See feedback/architecture/one-control-one-implementation.md.
#
# Instance configuration — all optional, all read from the SEAT's environment:
#   AGENTIC_SDLC_SKIP_REBASE_CHECK=1   one-off exception to rule 3
#   AGENTIC_SDLC_ALLOW_RELEASE_PUSH=1  release ceremony only — permits release/*
#   AGENTIC_SDLC_OWNER_ADMIN_MERGE=<n> authorises `--admin` for PR <n> only
#   AGENTIC_SDLC_GATE_CMD=<command>    pre-push gate; must exit 0 for the
#                                      current patch-id before a push is allowed
#   AGENTIC_SDLC_INTEGRATION_BRANCHES=<path to json>
#                                      {"branches":["feat/123-x"]} — a branch
#                                      descending from a registered integration
#                                      branch is measured against IT, not main
#
# These MUST be exported in the seat's environment (e.g. .env.local). The hook
# runs in its own process, so an inline `VAR=1 git ...` prefix never reaches it
# — that is why a per-command form silently does nothing.
#
# Repo scoping: a seat legitimately runs git against OTHER repositories (a
# cloned upstream, a scratch worktree). State checks run in the directory the
# COMMAND targets — honouring `git -C <dir>` and a leading `cd <dir> &&` — not
# the hook's own cwd.
#
# Contract (Claude Code hooks): the tool call arrives as JSON on stdin;
# exit 2 blocks the call and stderr is fed back to the seat; exit 0 allows.
# Fails OPEN on missing jq / unparseable input — a guard must never brick a seat.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
IN="$(cat 2>/dev/null || true)"
CMD="$(printf '%s' "$IN" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || exit 0
case "$CMD" in *git*|*gh\ pr*) : ;; *) exit 0 ;; esac   # cheap prefilter

block() { printf 'BLOCKED (agentic-sdlc guard): %s\n' "$1" >&2; exit 2; }

# ── Mask quoted strings and heredoc bodies ────────────────────────────────────
# The verb scan must see the COMMAND, never prose that merely quotes one. A
# commit message, issue body, or PR body documenting `git push origin main` is
# not a push — but an unmasked scan reads it as one and blocks the seat from
# reporting the very defect it is describing. Observed repeatedly; it makes the
# guard's failure mode obstruct reporting the guard's failure mode.
#
# Regions are blanked to spaces so offsets and word boundaries survive.
MASKED="$(printf '%s' "$CMD" | awk '
  BEGIN { hd = "" }
  {
    line = $0
    if (hd != "") {                              # inside a heredoc body
      t = line; sub(/^[ \t]+/, "", t)
      if (t == hd) { hd = "" }                   # closing delimiter
      gsub(/[^ \t]/, " ", line); print line; next
    }
    if (match(line, /<<-?[ \t]*'"'"'?"?[A-Za-z_][A-Za-z0-9_]*'"'"'?"?/)) {
      d = substr(line, RSTART, RLENGTH)
      gsub(/^<<-?[ \t]*/, "", d); gsub(/['"'"'"]/, "", d)
      hd = d
    }
    out = ""; i = 1; n = length(line); q = ""
    while (i <= n) {
      c = substr(line, i, 1)
      if (q == "") {
        if (c == "'"'"'" || c == "\"") { q = c; out = out " " }
        else { out = out c }
      } else {
        if (c == q) { q = ""; out = out " " }
        else { out = out (c ~ /[ \t]/ ? c : " ") }
      }
      i++
    }
    print out
  }
')"
[ -n "$MASKED" ] || MASKED="$CMD"

# Resolve the directory this command actually operates on.
TARGET_DIR="$(printf '%s' "$MASKED" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)"
[ -n "$TARGET_DIR" ] || TARGET_DIR="$(printf '%s' "$MASKED" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]&;|]+).*/\1/p' | head -1)"
[ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ] || TARGET_DIR="."
g() { git -C "$TARGET_DIR" "$@"; }

# git may carry options BEFORE the subcommand — `git -C <dir> push`, `git
# --no-pager push`, `git -c k=v push` — so match flags between git and the verb
# (an adjacency-only regex was a full bypass for `git -C . push origin main`).
GIT_VERB='git([[:space:]]+-[A-Za-z]([[:space:]]+[^[:space:]]+)?|[[:space:]]+--[A-Za-z0-9-]+(=[^[:space:]]*)?)*[[:space:]]+'

# ── 4: gh pr merge --admin ────────────────────────────────────────────────────
# Bypasses branch protection entirely, so it is owner-authorised per PR. The
# authorisation names ONE pr number and never carries to another.
if printf '%s' "$MASKED" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge' \
   && printf '%s' "$MASKED" | grep -Eq '(^|[[:space:]])--admin([[:space:]]|$)'; then
  PRNUM="$(printf '%s' "$MASKED" | sed -nE 's/.*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+([0-9]+).*/\1/p' | head -1)"
  AUTH="${AGENTIC_SDLC_OWNER_ADMIN_MERGE:-}"
  if [ -z "$PRNUM" ] || [ -z "$AUTH" ] || ! printf '%s' " $AUTH " | grep -q "[ ,]${PRNUM}[ ,]"; then
    block "\`gh pr merge --admin\` bypasses branch protection and is owner-gated. If the owner has authorised THIS pr, export AGENTIC_SDLC_OWNER_ADMIN_MERGE=${PRNUM:-<pr>} in the seat environment. Authorisation is per-pr and never carries to another."
  fi
fi

# ── 1 + 3 + 5: git push ───────────────────────────────────────────────────────
if printf '%s' "$MASKED" | grep -Eq "(^|[;&|[:space:]])${GIT_VERB}push"; then
  if printf '%s' "$MASKED" | grep -Eq '(^|[[:space:]:/])(main|master)([[:space:]]|$)'; then
    block "never push to main/master — open a PR instead (feedback/workflow/always-pr-never-push.md)."
  fi
  if printf '%s' "$MASKED" | grep -Eq '(^|[[:space:]:/])release/[^[:space:]]+([[:space:]]|$)'; then
    [ "${AGENTIC_SDLC_ALLOW_RELEASE_PUSH:-}" = "1" ] || \
      block "never push directly to a release line — hotfixes route via a PR into the active release branch. The release ceremony may export AGENTIC_SDLC_ALLOW_RELEASE_PUSH=1, for the ceremony only."
  fi

  CUR="$(g rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$CUR" in
    main|master) block "you are on '$CUR' — create a feature branch, push that, open a PR." ;;
  esac

  # The branch being PUSHED, not the hook's HEAD. A seat pushes from a worktree
  # while the project checkout sits on something else entirely; measuring HEAD
  # there judged the wrong branch and blocked correctly-rebased work with a
  # count taken from somewhere it never touched.
  SRC="$(printf '%s' "$MASKED" \
    | sed -nE "s/.*${GIT_VERB}push[[:space:]]+(-[^[:space:]]+[[:space:]]+)*[^[:space:]-]+[[:space:]]+([^[:space:]:]+)(:[^[:space:]]+)?.*/\2/p" \
    | head -1)"
  case "$SRC" in ''|-*|HEAD) SRC="HEAD" ;; esac
  g rev-parse --verify -q "$SRC" >/dev/null 2>&1 || SRC="HEAD"

  # Base to measure against: a registered long-lived integration branch that
  # SRC descends from, else origin/main. Sub-PRs targeting an epic branch are
  # legitimately "behind" main and must not be blocked for it.
  BASE="origin/main"
  REG="${AGENTIC_SDLC_INTEGRATION_BRANCHES:-}"
  if [ -z "$REG" ]; then
    RR="$(g rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$RR" ] && [ -f "$RR/agentic-sdlc/integration-branches.json" ] \
      && REG="$RR/agentic-sdlc/integration-branches.json"
  fi
  if [ -n "$REG" ] && [ -f "$REG" ]; then
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      if g rev-parse --verify -q "origin/$b" >/dev/null 2>&1 \
         && g merge-base --is-ancestor "origin/$b" "$SRC" 2>/dev/null; then
        BASE="origin/$b"; break
      fi
    done <<EOF
$(jq -r '.branches[]? // empty' "$REG" 2>/dev/null)
EOF
  fi

  if [ "${AGENTIC_SDLC_SKIP_REBASE_CHECK:-}" != "1" ] \
     && g rev-parse --verify -q "$BASE" >/dev/null 2>&1; then
    BEHIND="$(g rev-list --count "$SRC".."$BASE" 2>/dev/null || echo 0)"
    if [ "${BEHIND:-0}" -gt 0 ]; then
      REPO="$(g rev-parse --show-toplevel 2>/dev/null || echo "$TARGET_DIR")"
      block "'$SRC' is $BEHIND commit(s) behind $BASE in $REPO — 'git fetch origin && git rebase $BASE', rerun gates, then retry (feedback/workflow/always-rebase-before-push.md). If that is not the repository you meant, check the -C / cd target. If this targets an unregistered long-lived branch, add it to integration-branches.json."
    fi
  fi

  # 5: the configured pre-push quality gate, stamped against the current diff so
  # it runs once per change rather than once per push attempt.
  GATE="${AGENTIC_SDLC_GATE_CMD:-}"
  if [ -n "$GATE" ]; then
    PID="$(g diff "$BASE"...  2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1)"
    [ -n "$PID" ] || PID="$(g rev-parse "$SRC" 2>/dev/null || echo none)"
    STAMP="${TMPDIR:-/tmp}/agentic-sdlc-gate.${PID}"
    if [ ! -f "$STAMP" ]; then
      if ( cd "$TARGET_DIR" && eval "$GATE" ) >/dev/null 2>&1; then
        : > "$STAMP"
      else
        block "the pre-push gate failed for this diff: \`$GATE\`. Fix it and retry — the result is cached per patch-id, so an unchanged diff will not re-run it. (AGENTIC_SDLC_GATE_CMD)"
      fi
    fi
  fi
fi

# ── 2: AI attribution in a commit ─────────────────────────────────────────────
if printf '%s' "$MASKED" | grep -Eq "(^|[;&|[:space:]])${GIT_VERB}commit"; then
  if printf '%s' "$CMD" | grep -Eqi 'co-authored-by:[[:space:]]*claude|generated with .{0,3}claude code'; then
    block "no AI attribution in commits — drop the Co-Authored-By / Generated-with footer and commit again (feedback/workflow/no-claude-attribution.md)."
  fi
fi

exit 0
