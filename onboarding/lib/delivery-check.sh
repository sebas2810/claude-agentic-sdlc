#!/usr/bin/env bash
#
# delivery-check.sh — the proof-before-Delivered gate (framework issue #73).
#
# A producer runs this before writing status:delivered. It proves, not
# asserts, that the work meets its acceptance criteria:
#
#   - each AC line in the issue body that carries a `Proof:` command is run
#     TWICE — once against a worktree of the fix reverted (must FAIL) and
#     once against the current HEAD (must PASS). A command that passes both
#     ways proves nothing and is reported HOLLOW, not PASS. Each command is
#     PRINTED before it runs (stdout is still captured/suppressed) — it is
#     sourced from the issue body, not written by the person running this,
#     so it is visible before execution rather than only in a failure log.
#   - the instance's own test commands run for whichever DELIVERY_TEST_CMDS
#     (in `sdlc.config`, auto-discovered by walking up from cwd, or pass
#     --sdlc-config / --test-cmds-file explicitly) path globs the diff
#     touches. No stack is hardcoded here.
#   - the PR is checked for an auto-close keyword against unticked ACs, for
#     commits outside this item's own history, and for being mergeable
#     against the current base tip. `--base` defaults to whatever
#     onboarding/lib/resolve-integration-base.sh resolves for HEAD (the
#     registered integration branch it descends from, else origin/main) —
#     the SAME resolution guard-git.sh's own rebase check already uses, not
#     a second copy; pass `--base` explicitly only to override.
#   - a passing read-only reviewer verdict (agents/delivery-reviewer.md,
#     run by the calling session — this script cannot invoke a subagent
#     itself) is required.
#
# SECURITY: Proof: commands are read from the issue body and executed with
# `eval`. On a public repo, an issue can be opened by anyone — do not run
# this against an issue you have not read, and never against one you did
# not write or a trusted PM/producer did not write. This is the same trust
# boundary a producer already crosses by reading an issue and writing code
# from it; the difference is that `eval` runs unread text unattended, so
# read the printed command before letting it run.
#
# On an overall PASS it writes a stamp keyed to the current HEAD sha;
# guard-git.sh refuses a `status:delivered` label write without one.
#
# AC line syntax this script understands, in an issue body:
#
#   - [ ] Some criterion, in prose.
#     Proof: `command that must fail without the fix, pass with it`
#
# A `Proof:` command runs regardless of `[ ]`/`[x]` — a ticked box is a
# manual assertion, not proof, and does not exempt an AC from the mechanical
# check (that gap is exactly #73's "suite stayed green with the fix
# reverted" failure mode). Only `[ ]` (still unticked) counts toward the
# AC3 close-keyword check.
#
# Every input can come from `gh` (the default, for real use) or from a file
# override (for hermetic testing — see onboarding/tests/delivery-check.test.sh,
# which never calls `gh`).
#
# Exit 0  — every AC with a proof command proved real, no hollow proof, test
#           commands green, PR checks clean, reviewer verdict PASS. Stamp
#           written.
# Exit 1  — a check failed; see stderr for which one. No stamp written.
# Exit 2  — usage / IO error (a missing `gh`, an unreadable file).
#
# Rule: sebas2810/claude-agentic-sdlc#73
set -uo pipefail

ISSUE=""; PR=""; BASE_REF=""
ISSUE_BODY_FILE=""; PR_BODY_FILE=""; PR_MERGEABLE_OVERRIDE=""; PR_BASE_REF_OVERRIDE=""
PR_HEAD_SHA_OVERRIDE=""
REVIEWER_VERDICT_FILE=""
TEST_CMDS_FILE=""
SDLC_CONFIG=""
STAMP_DIR="${TMPDIR:-/tmp}"

usage() {
  cat >&2 <<'EOF'
usage: delivery-check.sh --issue <n> [--pr <n>] [--base <ref>]
         [--issue-body-file <f>] [--pr-body-file <f>] [--pr-mergeable <v>]
         [--pr-base-ref <ref>] [--pr-head-sha <sha>]
         [--reviewer-verdict-file <f>]
         [--test-cmds-file <f>] [--sdlc-config <f>] [--stamp-dir <d>]

--base defaults to onboarding/lib/resolve-integration-base.sh's resolution
for HEAD (the registered integration branch, else origin/main).
--pr-base-ref defaults to the PR's actual baseRefName (via gh); compared
against --base — a PR opened against the wrong branch fails this check.
--pr-head-sha defaults to the PR's actual headRefOid (via gh); compared
against local HEAD — a stamp for content that is not what the PR shows on
GitHub fails this check (sebas2810/claude-agentic-sdlc#73, #5239 round 3).
--test-cmds-file defaults to DELIVERY_TEST_CMDS sourced from --sdlc-config
(which itself defaults to <repo-root>/sdlc.config, if present).
EOF
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --base) BASE_REF="${2:-}"; shift 2 ;;
    --issue-body-file) ISSUE_BODY_FILE="${2:-}"; shift 2 ;;
    --pr-body-file) PR_BODY_FILE="${2:-}"; shift 2 ;;
    --pr-mergeable) PR_MERGEABLE_OVERRIDE="${2:-}"; shift 2 ;;
    --pr-base-ref) PR_BASE_REF_OVERRIDE="${2:-}"; shift 2 ;;
    --pr-head-sha) PR_HEAD_SHA_OVERRIDE="${2:-}"; shift 2 ;;
    --reviewer-verdict-file) REVIEWER_VERDICT_FILE="${2:-}"; shift 2 ;;
    --test-cmds-file) TEST_CMDS_FILE="${2:-}"; shift 2 ;;
    --sdlc-config) SDLC_CONFIG="${2:-}"; shift 2 ;;
    --stamp-dir) STAMP_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done
[ -n "$ISSUE" ] || usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# ── --base: explicit override, else the same resolution guard-git.sh uses ──
if [ -z "$BASE_REF" ]; then
  RESOLVE_BASE="$SCRIPT_DIR/resolve-integration-base.sh"
  if [ -x "$RESOLVE_BASE" ]; then
    BASE_REF="$("$RESOLVE_BASE" "$(pwd)" HEAD 2>/dev/null || echo origin/main)"
  else
    BASE_REF="origin/main"
  fi
fi

# ── DELIVERY_TEST_CMDS: --test-cmds-file wins; else source it out of
#    --sdlc-config (default: the nearest sdlc.config walking up from cwd).
#    Sourced, not parsed — unlike the issue-body Proof: commands (untrusted,
#    public-repo input), sdlc.config is repo-committed content the producer
#    already trusts by having it checked out. ────────────────────────────
if [ -z "$TEST_CMDS_FILE" ]; then
  if [ -z "$SDLC_CONFIG" ]; then
    RR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$RR" ] && [ -f "$RR/sdlc.config" ] && SDLC_CONFIG="$RR/sdlc.config"
  fi
  if [ -n "$SDLC_CONFIG" ] && [ -f "$SDLC_CONFIG" ]; then
    DTC="$( (DELIVERY_TEST_CMDS=""; . "$SDLC_CONFIG"; printf '%s' "$DELIVERY_TEST_CMDS") 2>/dev/null || true)"
    if [ -n "$DTC" ]; then
      TEST_CMDS_FILE="$(mktemp)"
      TEST_CMDS_FILE_TMP=1
      printf '%s\n' "$DTC" > "$TEST_CMDS_FILE"
    fi
  fi
fi

# ── one cleanup path for every temp resource this script creates, so an
#    interrupted run (Ctrl-C, a killed CI job) never leaves a stray
#    worktree behind — REVERT_WT is set later, once the proof loop needs it.
AC_TMP=""; REVERT_WT=""; TEST_CMDS_FILE_TMP="${TEST_CMDS_FILE_TMP:-0}"
cleanup() {
  [ -n "$AC_TMP" ] && rm -f "$AC_TMP"
  [ "$TEST_CMDS_FILE_TMP" = 1 ] && [ -n "$TEST_CMDS_FILE" ] && rm -f "$TEST_CMDS_FILE"
  [ -n "$REVERT_WT" ] && git worktree remove --force "$REVERT_WT" >/dev/null 2>&1
  [ -n "$REVERT_WT" ] && rm -rf "$REVERT_WT" 2>/dev/null
  return 0
}
trap cleanup EXIT

fails=0
ok()   { printf '  PASS  %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1" >&2; fails=$((fails + 1)); }
note() { printf '  %s\n' "$1"; }

# ── gather inputs (gh by default; file overrides make this hermetic) ────────
if [ -n "$ISSUE_BODY_FILE" ]; then
  [ -f "$ISSUE_BODY_FILE" ] || { echo "no such file: $ISSUE_BODY_FILE" >&2; exit 2; }
  ISSUE_BODY="$(cat "$ISSUE_BODY_FILE")"
else
  command -v gh >/dev/null 2>&1 || { echo "gh not found and no --issue-body-file override" >&2; exit 2; }
  ISSUE_BODY="$(gh issue view "$ISSUE" --json body -q .body 2>/dev/null)" \
    || { echo "could not fetch issue #$ISSUE body" >&2; exit 2; }
fi

PR_BODY=""; PR_MERGEABLE="UNKNOWN"; PR_BASE_REF=""; PR_HEAD_SHA=""
if [ -n "$PR" ]; then
  if [ -n "$PR_BODY_FILE" ]; then
    [ -f "$PR_BODY_FILE" ] || { echo "no such file: $PR_BODY_FILE" >&2; exit 2; }
    PR_BODY="$(cat "$PR_BODY_FILE")"
  elif command -v gh >/dev/null 2>&1; then
    PR_BODY="$(gh pr view "$PR" --json body -q .body 2>/dev/null || true)"
  fi
  if [ -n "$PR_MERGEABLE_OVERRIDE" ]; then
    PR_MERGEABLE="$PR_MERGEABLE_OVERRIDE"
  elif command -v gh >/dev/null 2>&1; then
    PR_MERGEABLE="$(gh pr view "$PR" --json mergeable -q .mergeable 2>/dev/null || echo UNKNOWN)"
  fi
  if [ -n "$PR_BASE_REF_OVERRIDE" ]; then
    PR_BASE_REF="$PR_BASE_REF_OVERRIDE"
  elif command -v gh >/dev/null 2>&1; then
    PR_BASE_REF="$(gh pr view "$PR" --json baseRefName -q .baseRefName 2>/dev/null || true)"
  else
    PR_BASE_REF=""
  fi
  # #5239 QA re-delivery round 3, check 4(a): this script checked the PR
  # was MERGEABLE against the current base tip, but never confirmed the PR
  # actually shows the commit being proven — a stamp got written for local
  # HEAD while the PR's real head (on GitHub) pointed at something else
  # entirely. `grep -c headRefOid` on this file returned 0 before this fix.
  if [ -n "$PR_HEAD_SHA_OVERRIDE" ]; then
    PR_HEAD_SHA="$PR_HEAD_SHA_OVERRIDE"
  elif command -v gh >/dev/null 2>&1; then
    PR_HEAD_SHA="$(gh pr view "$PR" --json headRefOid -q .headRefOid 2>/dev/null || true)"
  fi
fi

echo "== delivery-check: issue #$ISSUE${PR:+, pr #$PR}, base $BASE_REF =="

# ── AC1/AC4-shape: parse "- [ ]"/"- [x]" lines, and an immediately-following
#    indented "Proof: \`cmd\`" line as that AC's proof command. ────────────
#
# #5239 QA re-delivery round 4, FAIL 3 (#73 AC1): GitHub renders FOUR
# task-list marker styles as checkboxes — `-`, `*`, `+`, and an ordered
# `1.` — but this parser (and the two grep counts below) only ever
# recognized `-`. An AC written with any other marker silently read as
# prose, not a checkbox: it counted toward neither AC_COUNT nor
# TOTAL_CHECKBOX_COUNT, so a body using `*`/`+`/`1.` markers could pass
# with zero of its criteria ever having been proven — the same "no
# criterion was proven" gap check 1 (below) exists to catch, just reached
# through a marker style instead of a missing Proof: line. MARKER covers
# all four; used everywhere a line used to hardcode `-`. Written with
# bracket expressions ([-*+], [.]) instead of backslash-escaped
# metacharacters (\*, \+, \.) on purpose: this string is later passed to
# awk via `-v` and to grep -E via shell interpolation, and awk's `-v`
# assignment applies string-literal escape processing to the incoming
# value — an escape it doesn't recognize (\*, \+, \.) gets its backslash
# silently DROPPED (confirmed empirically: awk -v MARKER='\*' arrives as
# a bare `*`, an illegal regex primary with nothing to quantify).
# Bracket expressions need no escaping and survive both paths intact.
#
# #5239 QA re-delivery round 5 (Tess), round 6: round 5's fix still only
# matched exactly ONE whitespace character between the marker and `[`, only
# a `.` ordered delimiter (never `)`), required the marker to sit directly
# at the start of the (optionally indented) line, and had no notion of a
# blockquote prefix or a nested list item. 15 forms GitHub itself renders as
# a checkbox — `1) [ ]`; 2-4 spaces after any marker; `> - [ ]` and deeper
# blockquote nesting; `- - [ ]` (a nested list item) — read as ordinary
# prose and skipped the Proof: requirement, the same "no criterion was
# proven" gap round 5 was meant to close, just reached through a different
# marker shape (Tess's round-5 FAIL, orbis-platform#5239). Her own re-check
# used GitHub's renderer (`gh api markdown ... | grep -c
# task-list-item-checkbox`) as the oracle, per-form, rather than trust this
# script's own regex approximation.
#
# MARKER itself only gains the `)` ordered delimiter here (added to the
# existing bracket expression, so the awk -v escaping constraint above still
# holds — no backslash enters this string). The one-whitespace-char
# assumption, the blockquote prefix, and nested-marker repetition are new
# wrapping built directly into the awk script body below (and mirrored in
# the plain bash grep patterns further down) — never through -v, so they
# are free to use ordinary ERE grouping (`(...)`, `+`) with no backslash-
# drop risk either.
#
# Two forms below still match though GitHub does not render them as a
# checkbox — a 10-digit ordered marker (CommonMark caps ordered markers at
# 9 digits) and a marker followed by 5+ spaces (GitHub reads the extra
# indent as the item's content, not a task-list space) — both err toward
# blocking (an extra Proof: requirement on a line nobody meant as an AC),
# which Tess's round-5 ruling leaves explicitly out of scope rather than
# asking for an exact CommonMark replica.
MARKER='([-*+]|[0-9]+[.)])'
#
# #5239 QA re-delivery round 3, check 1: AC_TMP's fields used to be
# tab-separated, read back with `IFS=$'\t' read -r cmd desc`. Tab is one of
# bash's three "IFS whitespace" characters (space/tab/newline) — even when
# IFS is set to JUST a tab, `read` still applies the whitespace-splitting
# rule for it: a LEADING delimiter is stripped, not treated as an empty
# first field. A no-Proof line ("\t$desc") therefore parsed as cmd="$desc",
# desc="" instead of cmd="", desc="$desc" — the checkbox's own prose landed
# in $cmd and was silently `eval`'d as its own proof command in the loop
# below, and the "checkbox has no Proof: command" bad() a few lines down
# never fired because $cmd read as non-empty. Any OTHER delimiter char does
# not get this treatment (confirmed empirically — comma and the ASCII Unit
# Separator both preserve a leading empty field), so US (0x1F, a control
# character that cannot appear in Markdown prose or a shell one-liner)
# replaces the tab everywhere this file's fields are produced or consumed.
US="$(printf '\x1f')"
AC_TMP="$(mktemp)"
printf '%s\n' "$ISSUE_BODY" | awk -v US="$US" -v MARKER="$MARKER" '
  BEGIN {
    # Wrapping lives here, not in MARKER (see the escaping note above): zero
    # or more blockquote levels (">" + optional run of whitespace, repeated
    # — covers "> - [ ]" through "> > - [ ]" at any depth), then one or more
    # marker+whitespace groups (covers a plain marker AND a nested list
    # item like "- - [ ]", at any depth), with the whitespace between a
    # marker and what follows UNBOUNDED ("+", not a single [[:space:]]) so
    # any run length holds, not just the specific counts a QA round found.
    bq = "(>[[:space:]]*)*"
    markseq = "((" MARKER ")[[:space:]]+)+"
    prefix = "^[[:space:]]*" bq markseq
    ac_start = prefix "\\[[ xX]\\]"
    ac_prefix = prefix "\\[[ xX]\\][[:space:]]*"
    ac_any = prefix "\\["
  }
  function flush() {
    if (have_ac) {
      # No Proof: line ever paired with this checkbox — emit it with an
      # EMPTY cmd field instead of dropping it. A dropped-silently checkbox
      # is exactly the #5239 QA re-delivery gap: a checkbox with no proof
      # counted toward neither AC_COUNT nor any failure, so it just PASSED
      # by never being looked at again.
      print US pending_desc
      have_ac = 0
    }
  }
  $0 ~ ac_start {
    flush()
    desc = $0
    sub(ac_prefix, "", desc)
    pending_desc = desc
    have_ac = 1
    next
  }
  have_ac && /^[[:space:]]+Proof:[[:space:]]*`/ {
    cmd = $0
    sub(/^[[:space:]]+Proof:[[:space:]]*`/, "", cmd)
    sub(/`[[:space:]]*$/, "", cmd)
    print cmd US pending_desc
    have_ac = 0
    next
  }
  /^[^[:space:]]/ || $0 ~ ac_any { flush() }
  END { flush() }
' > "$AC_TMP"

# Mirrors the awk BEGIN block's prefix exactly (blockquote levels, then one
# or more marker+whitespace groups) — built here directly in bash, not via
# awk -v, so the grouping/quantifier syntax needs no backslash-drop care.
CM_PREFIX="^[[:space:]]*(>[[:space:]]*)*((${MARKER})[[:space:]]+)+"
UNTICKED_COUNT="$(printf '%s\n' "$ISSUE_BODY" | grep -cE "${CM_PREFIX}\\[[[:space:]]\\]" || true)"
TICKED_COUNT="$(printf '%s\n' "$ISSUE_BODY" | grep -cE "${CM_PREFIX}\\[[xX]\\]" || true)"
TOTAL_CHECKBOX_COUNT="$((UNTICKED_COUNT + TICKED_COUNT))"
AC_COUNT="$(wc -l < "$AC_TMP" | tr -d ' ')"
WITH_PROOF_COUNT="$(awk -F"$US" '$1 != "" { c++ } END { print c+0 }' "$AC_TMP")"
note "found $AC_COUNT AC checkbox line(s), $WITH_PROOF_COUNT with a Proof: command, $UNTICKED_COUNT unticked / $TICKED_COUNT ticked checkbox line(s) total"

# #5239 QA re-delivery check 1: an issue body with ZERO recognized GFM
# task-list checkboxes (framework #73's own body is a numbered list, not
# checkboxes) must not silently read as "nothing to check, so PASS" — that
# is exactly the "no criterion was proven" gap QA found live. No recognized
# AC line means this script cannot verify anything, so it refuses, loudly,
# rather than reporting a clean PASS with zero content behind it.
if [ "$TOTAL_CHECKBOX_COUNT" -eq 0 ]; then
  bad "no acceptance-criteria checkboxes ('- [ ] ...') found in the issue body — cannot verify anything; rewrite the issue's Acceptance Criteria as GFM task-list items (see skills/delivery-check/SKILL.md)"
elif [ "$WITH_PROOF_COUNT" -ne "$TOTAL_CHECKBOX_COUNT" ]; then
  # A checkbox with no Proof: line is a manual assertion, not proof — the
  # same "no criterion was proven" gap as zero checkboxes, just partial.
  while IFS="$US" read -r cmd desc; do
    [ -n "$cmd" ] && continue
    short_desc="$(printf '%s' "$desc" | cut -c1-72)"
    bad "checkbox has no Proof: command: $short_desc"
  done < "$AC_TMP"
fi

# #5239 QA re-delivery round 6 (owner ruling, EPIC #5179, relayed by PM):
# "fix the class of problem, not the listed examples ... refuse any
# unrecognised format instead of adding formats to a list." Round 4 added
# three marker styles; round 5 broadened the whitespace/blockquote/nesting
# rules above — both rounds still amount to enumerating known-good shapes,
# and a marker style neither round anticipated would repeat the identical
# gap: read as prose, never proven, PASS by never being looked at. Rather
# than trust that CM_PREFIX above now covers every shape GitHub will ever
# render as a checkbox, this counts the literal `[ ]`/`[x]`/`[X]` token —
# the one thing every GFM checkbox renders down to, regardless of what
# precedes it — wherever it starts a "word" (preceded by whitespace or the
# start of the line) anywhere in the body (Proof: lines excluded; those
# are shell commands, not prose, and may legitimately contain a literal
# bracket pair of their own) and compares it to how many the marker-aware
# parser above actually accounted for. The whitespace-or-line-start
# requirement is deliberate, not incidental: prose that discusses the
# literal syntax in a code span — "...an empty array `[ ]`..." — has a
# backtick, not whitespace, immediately before the bracket, so it is not
# counted; write it that way (as most technical prose already does) to
# talk about the token itself without tripping this check. Any bracket
# left over after that means some prefix in this body reads enough like a
# checkbox to matter, and this script could not positively confirm it is
# one it understands — so it fails closed instead of assuming the gap is
# prose. A future marker style still needs CM_PREFIX taught to recognize
# it (so it gets Proof-enforced rather than refused forever), but it can
# no longer slip through unnoticed meanwhile.
NON_PROOF_BODY="$(printf '%s\n' "$ISSUE_BODY" | grep -Ev '^[[:space:]]*Proof:' || true)"
RAW_BRACKET_TOKEN_COUNT="$(printf '%s\n' "$NON_PROOF_BODY" | grep -oE '(^|[[:space:]])\[[ xX]\]' | wc -l | tr -d ' ')"
if [ "$RAW_BRACKET_TOKEN_COUNT" -gt "$TOTAL_CHECKBOX_COUNT" ]; then
  bad "found $RAW_BRACKET_TOKEN_COUNT '[ ]'/'[x]'/'[X]' token(s) in the issue body but only recognized $TOTAL_CHECKBOX_COUNT as a task-list checkbox line — an unrecognized marker form is in play; rewrite it as a plain bullet (-, *, +) or ordered (N. or N)) task-list item, optionally blockquoted or nested, so it can be verified"
fi

# ── run each AC's proof command both ways ────────────────────────────────
if [ "$AC_COUNT" -gt 0 ]; then
  BASE_SHA="$(git merge-base HEAD "$BASE_REF" 2>/dev/null || true)"
  if [ -z "$BASE_SHA" ]; then
    bad "cannot resolve merge-base of HEAD and $BASE_REF — cannot prove any AC"
  else
    REVERT_WT="$(mktemp -d)"
    if git worktree add --detach --quiet "$REVERT_WT" "$BASE_SHA" >/dev/null 2>&1; then
      while IFS="$US" read -r cmd desc; do
        [ -n "$cmd" ] || continue
        # Printed before execution: this command came from the issue body,
        # not from whoever is running the check (see the SECURITY note at
        # the top of this file) — visible before it runs, not only after.
        note "running proof: \`$cmd\`"
        # Closed stdin: this loop's own `read` is fed by AC_TMP via
        # redirection below — a proof command that reads stdin (or is
        # missing one entirely) would otherwise consume the REST of
        # AC_TMP's lines, silently skipping every later AC as if there
        # were nothing left to check (PM finding, same shape as the
        # DELIVERY_TEST_CMDS bug below).
        before_rc=0; ( cd "$REVERT_WT" && eval "$cmd" ) </dev/null >/dev/null 2>&1 || before_rc=$?
        after_rc=0; ( eval "$cmd" ) </dev/null >/dev/null 2>&1 || after_rc=$?
        short_desc="$(printf '%s' "$desc" | cut -c1-72)"
        if [ "$before_rc" -eq 0 ] && [ "$after_rc" -eq 0 ]; then
          bad "hollow proof (passes reverted AND fixed): $short_desc -- \`$cmd\`"
        elif [ "$after_rc" -ne 0 ]; then
          bad "proof fails against the fix: $short_desc -- \`$cmd\`"
        elif [ "$before_rc" -eq 0 ]; then
          bad "proof does not fail when reverted (inverted?): $short_desc -- \`$cmd\`"
        else
          ok "$short_desc"
        fi
      done < "$AC_TMP"
    else
      bad "could not create a worktree at $BASE_SHA to prove ACs against"
    fi
  fi
fi

# ── AC2: the instance's own test commands, path-glob-selected ───────────
# One `<glob>:<command>` per line — split on the FIRST colon only (`read`
# dumps every remaining field, colons included, into the last variable), so
# a command containing its own colon (`npm run test:unit`) survives intact.
if [ -n "$TEST_CMDS_FILE" ] && [ -f "$TEST_CMDS_FILE" ]; then
  CHANGED="$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null || true)"
  while IFS=':' read -r glob cmd; do
    [ -n "${glob:-}" ] || continue
    [ -n "${cmd:-}" ] || continue
    matched=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      # shellcheck disable=SC2254 # glob is intentionally unquoted here
      case "$f" in
        $glob) matched=1 ;;
      esac
    done <<EOF
$CHANGED
EOF
    if [ "$matched" -eq 1 ]; then
      # PM finding: this loop's own `read` is fed by TEST_CMDS_FILE via
      # redirection below. Run bare, `eval "$cmd"` shares this shell AND
      # its stdin — a `cd`-prefixed command (every ORBIS #5248 command
      # starts with one) leaks its directory change into every later
      # command in this loop AND the rest of the script, and a command
      # that reads stdin consumes the REST of TEST_CMDS_FILE's lines,
      # silently skipping later checks as a false PASS (nothing left to
      # fail). A subshell isolates the cd; a closed stdin stops it eating
      # sibling commands.
      if ( eval "$cmd" ) </dev/null >/dev/null 2>&1; then
        ok "DELIVERY_TEST_CMDS[$glob]: $cmd"
      else
        bad "DELIVERY_TEST_CMDS[$glob] failed: $cmd"
      fi
    fi
  done < "$TEST_CMDS_FILE"
fi

# ── AC3: PR checks ────────────────────────────────────────────────────────
# #5239 QA re-delivery review round 2 ("a check must be able to report its
# own failure"): with no --pr at all, every PR subcheck below used to run
# its `if -n ...` guard, find nothing, and skip — silently, no bad(), same
# outcome as a clean PASS. Delivered means "PR open, awaiting QA" by
# definition (the label lifecycle this check gates), so a run that cannot
# see a PR cannot report PASS; it must say so.
if [ -z "$PR" ]; then
  bad "no --pr given — cannot verify the close-keyword, base branch, or mergeable state; Delivered requires an open PR"
else
  if printf '%s' "$PR_BODY" | grep -Eiq "(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[[:space:]]+#${ISSUE}([^0-9]|$)"; then
    if [ "$TOTAL_CHECKBOX_COUNT" -eq 0 ]; then
      bad "PR body closes #$ISSUE but no AC checkboxes were found to verify against — cannot confirm none are open"
    elif [ "$UNTICKED_COUNT" -gt 0 ]; then
      bad "PR body closes #$ISSUE with $UNTICKED_COUNT unticked AC line(s) still open"
    else
      ok "close keyword present, no unticked ACs remain"
    fi
  fi

  # #5239 QA re-delivery check 3: the check resolved a base to prove ACs
  # against, but never confirmed the PR was actually OPENED against that
  # same base — a PR opened against the wrong branch (e.g. main, for an
  # item that belongs on an integration branch) passed silently. Compare
  # the PR's real baseRefName (GitHub, unprefixed) against the resolved
  # --base (origin/<branch> form) with the origin/ prefix stripped.
  # An unresolved PR_BASE_REF (no gh, gh lookup failed, no override) used
  # to skip this comparison entirely rather than report it could not be
  # made — now it fails instead.
  if [ -n "$BASE_REF" ]; then
    if [ -z "$PR_BASE_REF" ]; then
      bad "could not resolve the PR's base branch (no gh, gh lookup failed, and no --pr-base-ref override) — cannot confirm it targets $BASE_REF"
    else
      RESOLVED_BASE_UNPREFIXED="${BASE_REF#origin/}"
      if [ "$PR_BASE_REF" = "$RESOLVED_BASE_UNPREFIXED" ]; then
        ok "PR is opened against the resolved base ($PR_BASE_REF)"
      else
        bad "PR is opened against '$PR_BASE_REF' but the resolved base is '$RESOLVED_BASE_UNPREFIXED' — wrong target branch"
      fi
    fi
  fi
fi

if [ -n "$BASE_REF" ] && git rev-parse --verify -q "$BASE_REF" >/dev/null 2>&1; then
  BASE_SHA_FOR_LOG="$(git merge-base HEAD "$BASE_REF" 2>/dev/null || true)"
  if [ -n "$BASE_SHA_FOR_LOG" ]; then
    OTHER_ISSUE_COMMITS="$(git log "$BASE_SHA_FOR_LOG..HEAD" --format='%H %s' 2>/dev/null \
      | grep -Ev "#${ISSUE}([^0-9]|$)" \
      | grep -E '#[0-9]+' || true)"
    if [ -n "$OTHER_ISSUE_COMMITS" ]; then
      bad "commit(s) on this branch reference a different issue number: $(printf '%s' "$OTHER_ISSUE_COMMITS" | wc -l | tr -d ' ') commit(s)"
    else
      ok "git log $BASE_REF..HEAD holds only this item's commits"
    fi
  fi
fi

# #5239 QA re-delivery review round 2: UNKNOWN used to be a benign `note`
# — not scored either way. With --pr now mandatory (see AC3 above), an
# UNKNOWN mergeable state means the check could not confirm mergeability
# at all (no gh, gh lookup failed, GitHub has not computed it yet), which
# is a failure to verify, not a pass-by-default.
if [ -n "$PR" ]; then
  case "$PR_MERGEABLE" in
    MERGEABLE) ok "PR is mergeable against the current base tip" ;;
    UNKNOWN) bad "PR mergeable state is unknown (no gh, gh lookup failed, or GitHub has not computed it yet) — cannot confirm it is mergeable" ;;
    *) bad "PR is not mergeable against the current base tip (state: $PR_MERGEABLE)" ;;
  esac
fi

# #5239 QA re-delivery round 3, check 4(a): "mergeable" is a statement about
# the base tip, not about WHICH commit the PR shows — a stub answering PR
# #7's head as one sha while local HEAD sits at another still passed every
# check above and wrote a stamp for the wrong commit. Compare the PR's real
# head (headRefOid, from GitHub) against local HEAD directly; unresolved is
# a failure to verify, not a pass-by-default, same posture as PR_MERGEABLE.
if [ -n "$PR" ]; then
  LOCAL_HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
  if [ -z "$PR_HEAD_SHA" ]; then
    bad "could not resolve PR #$PR's actual head commit (no gh, gh lookup failed, and no --pr-head-sha override) — cannot confirm HEAD is what the PR shows on GitHub"
  elif [ -z "$LOCAL_HEAD_SHA" ]; then
    bad "cannot resolve local HEAD to compare against PR #$PR's head"
  elif [ "$PR_HEAD_SHA" != "$LOCAL_HEAD_SHA" ]; then
    bad "local HEAD ($LOCAL_HEAD_SHA) does not match PR #$PR's actual head on GitHub ($PR_HEAD_SHA) — push first so the commit being proven is what the PR actually shows"
  else
    ok "local HEAD matches PR #$PR's actual head on GitHub ($LOCAL_HEAD_SHA)"
  fi
fi

# ── AC4: the read-only reviewer verdict ──────────────────────────────────
if [ -n "$REVIEWER_VERDICT_FILE" ] && [ -f "$REVIEWER_VERDICT_FILE" ]; then
  if grep -Eq '^VERDICT:[[:space:]]*PASS[[:space:]]*$' "$REVIEWER_VERDICT_FILE"; then
    ok "delivery-reviewer subagent verdict: PASS"
  else
    bad "delivery-reviewer subagent verdict is not PASS (see $REVIEWER_VERDICT_FILE)"
  fi
else
  bad "no delivery-reviewer verdict — run the agents/delivery-reviewer.md subagent against this diff + the AC first (--reviewer-verdict-file)"
fi

# ── AC5: the stamp ────────────────────────────────────────────────────────
echo ""
if [ "$fails" -eq 0 ]; then
  HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo none)"
  mkdir -p "$STAMP_DIR"
  STAMP="$STAMP_DIR/agentic-sdlc-delivery.$HEAD_SHA"
  {
    echo "issue: $ISSUE"
    echo "pr: $PR"
    echo "sha: $HEAD_SHA"
    echo "at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$STAMP"
  echo "delivery-check: PASS — stamp written for $HEAD_SHA ($STAMP)"
else
  echo "delivery-check: $fails check(s) FAILED — no stamp written" >&2
fi
exit "$fails"
