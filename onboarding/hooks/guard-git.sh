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
#   6. writing the `status:delivered` label without a passing delivery-check
#      stamp for the current HEAD (sebas2810/claude-agentic-sdlc#73)
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
#   AGENTIC_SDLC_SKIP_DELIVERY_CHECK=1 one-off exception to rule 6
#   AGENTIC_SDLC_DELIVERY_STAMP_DIR=<dir> where delivery-check.sh's stamps
#                                      live (default ${TMPDIR:-/tmp}, matching
#                                      the script's own default)
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
RESOLVE_BASE="$SCRIPT_DIR/../lib/resolve-integration-base.sh"
command -v jq >/dev/null 2>&1 || exit 0
IN="$(cat 2>/dev/null || true)"
CMD="$(printf '%s' "$IN" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || exit 0
# cheap prefilter — must catch every route the LABEL_ROUTE detection below
# does, including `-R`/`--repo` BEFORE the subcommand (`gh -R o/r issue
# edit`), or this exits 0 before that logic ever runs.
case "$CMD" in
  *git*|*gh\ pr*|*gh\ issue*|*gh\ api*|*gh\ -R*|*gh\ --repo*) : ;;
  *) exit 0 ;;
esac

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
  #
  # #4543 — REGISTRY SHAPE. One file per branch under agentic-sdlc/
  # integration-branches/, the file's path equal to the branch name (e.g.
  # agentic-sdlc/integration-branches/feat/4489-journey-rail). Branch names
  # are recovered by listing the directory tree (recursively, since a branch
  # name's own "/" becomes a real subdirectory) and stripping the registry
  # root prefix — never a second hand-maintained list. Replaces a single
  # JSON array (see agentic-sdlc/integration-branches/README.md for why).
  #
  # Resolved by onboarding/lib/resolve-integration-base.sh, the ONE place
  # this logic lives — delivery-check.sh (sebas2810/claude-agentic-sdlc#73)
  # shares it rather than re-deriving its own copy. Fails open to
  # origin/main if the shared script is missing (an old checkout) — a
  # guard must never brick a seat.
  if [ -x "$RESOLVE_BASE" ]; then
    BASE="$("$RESOLVE_BASE" "$TARGET_DIR" "$SRC" 2>/dev/null || echo origin/main)"
  else
    BASE="origin/main"
  fi

  if [ "${AGENTIC_SDLC_SKIP_REBASE_CHECK:-}" != "1" ] \
     && g rev-parse --verify -q "$BASE" >/dev/null 2>&1; then
    BEHIND="$(g rev-list --count "$SRC".."$BASE" 2>/dev/null || echo 0)"
    if [ "${BEHIND:-0}" -gt 0 ]; then
      REPO="$(g rev-parse --show-toplevel 2>/dev/null || echo "$TARGET_DIR")"
      block "'$SRC' is $BEHIND commit(s) behind $BASE in $REPO — 'git fetch origin && git rebase $BASE', rerun gates, then retry (feedback/workflow/always-rebase-before-push.md). If that is not the repository you meant, check the -C / cd target. If this targets an unregistered long-lived branch, register it: touch agentic-sdlc/integration-branches/<branch-name>."
    fi
  fi

  # 5: the configured pre-push quality gate, stamped against the current diff so
  # it runs once per change rather than once per push attempt.
  # The gate command: env first, else a conventional repo-committed script.
  # Env-only would mean the gate is inactive until every seat exports it — a
  # control that silently does not run on any seat that missed the setup step,
  # which is the failure class this guard exists to prevent. A committed
  # .claude/hooks/pre-push-gate.sh is active for every seat, on clone, with no
  # per-seat configuration.
  GATE="${AGENTIC_SDLC_GATE_CMD:-}"
  if [ -z "$GATE" ]; then
    GRR="$(g rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$GRR" ] && [ -x "$GRR/.claude/hooks/pre-push-gate.sh" ] \
      && GATE="$GRR/.claude/hooks/pre-push-gate.sh"
  fi
  if [ -n "$GATE" ]; then
    PID="$(g diff "$BASE"...  2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1)"
    [ -n "$PID" ] || PID="$(g rev-parse "$SRC" 2>/dev/null || echo none)"
    # Key the stamp by the DIFF *and* the gate definition. Patch-id alone meant
    # that once a diff passed, changing the gate to something stricter reused the
    # old pass and the new gate never ran — a stale green on a control that had
    # been deliberately tightened.
    GID="$(printf '%s' "$GATE" | cksum | cut -d' ' -f1)"
    STAMP="${TMPDIR:-/tmp}/agentic-sdlc-gate.${PID}.${GID}"
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

# ── 6: status:delivered label write without a passing delivery-check stamp ───
# FAIL-CLOSED (found in independent QA re-delivery review of #73): the first
# cut only matched an --add-label whose value CONTAINED the literal text
# "status:delivered" — every one of these bypassed it, each verified live:
#   gh pr edit 1 --add-label status:delivered            (wrong subcommand)
#   L=status:delivered; gh issue edit 1 --add-label "$L"  (opaque variable)
#   gh api -X POST .../labels --input -                   (opaque stdin JSON)
#   gh api graphql -f query='mutation{addLabelsToLabelable(...)}'
# The fix inverts the default: first detect the ROUTE (issue edit, PR edit,
# REST labels, GraphQL mutation) on MASKED (structural, verb-only) — any
# match means "this command can write a label" and is gated UNLESS a
# concrete, inspectable literal value is found that provably does NOT say
# status:delivered. No extractable literal (a variable, stdin, a GraphQL
# payload) is treated as UNSAFE, not safe — "refusing a label it cannot
# read counts as blocking" (QA's own framing). A routine label write with a
# literal value (`--add-label seat:seb`, `--add-label "status:in-progress"`)
# still needs no stamp; only status:delivered, and anything opaque, does.
LABEL_ROUTE=0
# #5239 QA re-delivery review round 2 — five more live routes found:
#   gh -R o/r issue edit 1 --add-label status:delivered   (repo flag BEFORE
#                                                           the subcommand)
#   gh api -X PATCH repos/o/r/issues/1 -f 'labels[]=status:delivered'
#                                                          (no /labels path
#                                                           suffix at all)
#   gh api -X POST "repos/o/r/issues/1/labels"            (quoted path —
#                                                           blank on MASKED)
#   gh api graphql -F query=@mutation.graphql             (mutation text is
#                                                           in a file this
#                                                           guard can't read)
#   gh api graphql -f query='mutation{updateIssue(input:{labelIds:[...]})}'
#                                                          (a second mutation
#                                                           shape — not just
#                                                           addLabelsToLabelable)
GH_REPO_OPT='([[:space:]]+(-R|--repo)([[:space:]]+[^[:space:]]+|=[^[:space:]]+))?'
if printf '%s' "$MASKED" | grep -Eq "(^|[;&|[:space:]])gh${GH_REPO_OPT}[[:space:]]+(issue|pr)[[:space:]]+edit[[:space:]]+.*--add-label"; then
  LABEL_ROUTE=1
fi
if printf '%s' "$MASKED" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+api'; then
  # The URL path is a real argument to `gh api`, not prose merely quoting
  # one — a quoted path is still the literal command actually being run,
  # so check the raw $CMD too: MASKED alone blanks a quoted path to spaces.
  printf '%s\n%s' "$MASKED" "$CMD" | grep -Eq '/labels([[:space:]"'"'"']|$)' && LABEL_ROUTE=1
  # `-f`/`-F labels[]=...` writes labels via a PATCH straight to
  # .../issues/{n} — no "/labels" path suffix, and the whole
  # "labels[]=value" token is normally one quoted argument (same
  # invisible-on-MASKED reason) — check raw $CMD.
  printf '%s' "$CMD" | grep -Eiq -- 'labels\[\][[:space:]]*=' && LABEL_ROUTE=1
  printf '%s' "$CMD" | grep -Eq 'addLabelsToLabelable|labelIds' && LABEL_ROUTE=1
  printf '%s' "$MASKED" | grep -Eq -- '-[fF][[:space:]]+query=@' && LABEL_ROUTE=1
fi

if [ "$LABEL_ROUTE" = 1 ]; then
  # A "safe" literal: --add-label (space or =) followed by a FULLY quoted
  # (single or double) token with NO `$` inside, or a genuinely bare token
  # containing none of space/$/quote (a `$` means a variable/substitution —
  # opaque, not a literal we can trust). The bare-token class EXCLUDES both
  # quote characters — without that exclusion, `--add-label "$L"` matches
  # the bare-token alternative against the lone opening `"` (stopping at the
  # `$` that immediately follows), capturing a one-character "literal" that
  # trivially doesn't contain status:delivered and is wrongly marked SAFE.
  # A quote character appearing outside a closed quote pair means the value
  # could not be read as a real literal — no alternative should match it,
  # and the `+`/`*` there are non-greedy-by-exclusion, not size, so a
  # zero-width match (e.g. `labels[]=$L`, nothing before the `$`) is also
  # excluded by requiring at least one real character. `--input` (stdin
  # JSON), any addLabelsToLabelable/updateIssue/updatePullRequest GraphQL
  # mutation, an out-of-line `-f/-F query=@file`, and any `labels[]=` form
  # are ALWAYS unsafe — their payload is never fully in $CMD to inspect (a
  # GraphQL variable is an opaque ID, not a label name, even when present).
  # `gh issue/pr edit` legitimately accepts a REPEATED --add-label flag —
  # `... --add-label seat:x --add-label status:delivered` bypassed a
  # `head -1`-on-first-match design (found in the SAME independent review
  # that reported this fix as ready), because only the FIRST occurrence's
  # literal was ever inspected. The fix counts: every `--add-label` MARKER
  # present (on MASKED — structural) must pair 1:1 with a
  # successfully-extracted safe LITERAL (on $CMD); any unpaired marker (an
  # occurrence whose value could not be read as a clean literal) makes the
  # whole command unsafe, same as zero extractable literals does.
  # Case-INsensitive substring match on "status:delivered", since GitHub's
  # own label matching is.
  SAFE=0
  if ! printf '%s' "$CMD" | grep -Eq 'addLabelsToLabelable|labelIds' \
     && ! printf '%s' "$CMD" | grep -Eiq -- 'labels\[\][[:space:]]*=' \
     && ! printf '%s' "$MASKED" | grep -Eq -- '(^|[[:space:]])--input([[:space:]]|=)' \
     && ! printf '%s' "$MASKED" | grep -Eq -- '-[fF][[:space:]]+query=@'; then
    MARKER_COUNT="$(printf '%s' "$MASKED" | grep -Eo -- '--add-label' | wc -l | tr -d ' ')"
    LITERALS="$(printf '%s' "$CMD" | grep -Eo -- '--add-label[[:space:]=]+"[^"$]*"|--add-label[[:space:]=]+'"'"'[^'"'"'$]*'"'"'|--add-label[[:space:]=]+[^[:space:]$"'"'"']+')"
    LITERAL_COUNT="$(printf '%s\n' "$LITERALS" | grep -c . || true)"
    if [ "$MARKER_COUNT" -gt 0 ] && [ "$MARKER_COUNT" = "$LITERAL_COUNT" ] \
       && ! printf '%s\n' "$LITERALS" | grep -qi 'status:delivered'; then
      SAFE=1
    fi
  fi

  if [ "$SAFE" != 1 ] && [ "${AGENTIC_SDLC_SKIP_DELIVERY_CHECK:-}" != "1" ]; then
    SHA="$(g rev-parse HEAD 2>/dev/null || echo none)"
    SDIR="${AGENTIC_SDLC_DELIVERY_STAMP_DIR:-${TMPDIR:-/tmp}}"
    STAMP="$SDIR/agentic-sdlc-delivery.$SHA"
    REPO="$(g rev-parse --show-toplevel 2>/dev/null || echo "$TARGET_DIR")"
    if [ ! -f "$STAMP" ]; then
      block "no passing delivery-check stamp for HEAD ($SHA) in $REPO, or this label write could not be verified safe (opaque value / route) — run onboarding/lib/delivery-check.sh first, it writes the stamp on PASS. A new commit invalidates the old stamp (re-run after any change). If that is not the repository you meant, check the -C / cd target. Owner exception: AGENTIC_SDLC_SKIP_DELIVERY_CHECK=1 (one-off, sebas2810/claude-agentic-sdlc#73)."
    fi
    # The stamp proves local HEAD passed; it says nothing about whether HEAD
    # was ever PUSHED — a stamp for content nobody can review on the actual
    # PR is not proof of anything reviewable.
    #
    # #5239 QA re-delivery review round 2: the local `@{u}` tracking ref is
    # a locally-cached pointer — it says what THIS checkout last saw as its
    # upstream, not what the PR actually shows on GitHub right now. Where
    # the command names an actual issue/PR number, ask GitHub directly for
    # that PR's real head commit and require HEAD to match IT — a stronger
    # check than trusting a local ref that could be stale or misconfigured.
    # Falls back to the `@{u}` comparison when no PR can be resolved (a
    # plain issue, no gh, or gh cannot reach the remote) rather than
    # skipping the pushed-content check altogether.
    # #5239 QA re-delivery round 3, check 4(b): deriving PRNUM from the
    # command text broke the `gh issue edit N --add-label status:delivered`
    # route entirely — the route labels actually use, since a board item
    # is an issue. It put issue N's number where a PR number belongs; `gh
    # pr view N` can never resolve it (issues and PRs share one number
    # space per repo), so REMOTE_HEAD stayed empty and this silently fell
    # back to the weaker local @{u} comparison every time — on exactly the
    # route this check exists to cover. The stamp is authoritative instead:
    # delivery-check.sh refuses to write one without --pr (its own "no
    # --pr given" AC3 check), so every valid stamp for this HEAD already
    # names the real PR it was verified against — read it from there,
    # independent of which gh subcommand is writing the label.
    PRNUM="$(sed -nE 's/^pr:[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$STAMP" 2>/dev/null | head -1)"
    REPO_ARG="$(printf '%s' "$MASKED" | sed -nE 's/.*(-R|--repo)[[:space:]=]+([^[:space:]]+).*/\2/p' | head -1)"
    REMOTE_HEAD=""
    if [ -n "$PRNUM" ] && command -v gh >/dev/null 2>&1; then
      if [ -n "$REPO_ARG" ]; then
        REMOTE_HEAD="$(gh pr view "$PRNUM" -R "$REPO_ARG" --json headRefOid -q .headRefOid 2>/dev/null || true)"
      else
        REMOTE_HEAD="$(cd "$TARGET_DIR" && gh pr view "$PRNUM" --json headRefOid -q .headRefOid 2>/dev/null || true)"
      fi
    fi
    if [ -n "$REMOTE_HEAD" ]; then
      if [ "$REMOTE_HEAD" != "$SHA" ]; then
        block "HEAD ($SHA) in $REPO does not match PR #$PRNUM's actual head on GitHub ($REMOTE_HEAD) — push first so the stamped commit is what the PR actually shows, then retry."
      fi
    else
      UPSTREAM="$(g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
      if [ -z "$UPSTREAM" ]; then
        block "HEAD ($SHA) in $REPO has no upstream tracking branch — push first so the stamped commit is verifiably what is on the remote/PR, then retry."
      else
        UPSTREAM_SHA="$(g rev-parse "$UPSTREAM" 2>/dev/null || true)"
        if [ "$UPSTREAM_SHA" != "$SHA" ]; then
          block "HEAD ($SHA) in $REPO has not been pushed to $UPSTREAM (which is at ${UPSTREAM_SHA:-unknown}) — a stamp for unpushed content proves nothing about the PR. Push, then retry."
        fi
      fi
    fi
  fi
fi

exit 0
