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
REVIEWER_VERDICT_FILE=""
TEST_CMDS_FILE=""
SDLC_CONFIG=""
STAMP_DIR="${TMPDIR:-/tmp}"

usage() {
  cat >&2 <<'EOF'
usage: delivery-check.sh --issue <n> [--pr <n>] [--base <ref>]
         [--issue-body-file <f>] [--pr-body-file <f>] [--pr-mergeable <v>]
         [--pr-base-ref <ref>] [--reviewer-verdict-file <f>]
         [--test-cmds-file <f>] [--sdlc-config <f>] [--stamp-dir <d>]

--base defaults to onboarding/lib/resolve-integration-base.sh's resolution
for HEAD (the registered integration branch, else origin/main).
--pr-base-ref defaults to the PR's actual baseRefName (via gh); compared
against --base — a PR opened against the wrong branch fails this check.
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

PR_BODY=""; PR_MERGEABLE="UNKNOWN"; PR_BASE_REF=""
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
fi

echo "== delivery-check: issue #$ISSUE${PR:+, pr #$PR}, base $BASE_REF =="

# ── AC1/AC4-shape: parse "- [ ]"/"- [x]" lines, and an immediately-following
#    indented "Proof: \`cmd\`" line as that AC's proof command. ────────────
AC_TMP="$(mktemp)"
printf '%s\n' "$ISSUE_BODY" | awk '
  /^[[:space:]]*-[[:space:]]\[[ xX]\]/ {
    desc = $0
    sub(/^[[:space:]]*-[[:space:]]\[[ xX]\][[:space:]]*/, "", desc)
    pending_desc = desc
    have_ac = 1
    next
  }
  have_ac && /^[[:space:]]+Proof:[[:space:]]*`/ {
    cmd = $0
    sub(/^[[:space:]]+Proof:[[:space:]]*`/, "", cmd)
    sub(/`[[:space:]]*$/, "", cmd)
    print cmd "\t" pending_desc
    have_ac = 0
    next
  }
  /^[^[:space:]]/ || /^[[:space:]]*-[[:space:]]\[/ { have_ac = 0 }
' > "$AC_TMP"

UNTICKED_COUNT="$(printf '%s\n' "$ISSUE_BODY" | grep -cE '^[[:space:]]*-[[:space:]]\[[[:space:]]\]' || true)"
TICKED_COUNT="$(printf '%s\n' "$ISSUE_BODY" | grep -cE '^[[:space:]]*-[[:space:]]\[[xX]\]' || true)"
TOTAL_CHECKBOX_COUNT="$((UNTICKED_COUNT + TICKED_COUNT))"
AC_COUNT="$(wc -l < "$AC_TMP" | tr -d ' ')"
note "found $AC_COUNT AC line(s) with a Proof: command, $UNTICKED_COUNT unticked / $TICKED_COUNT ticked checkbox line(s) total"

# #5239 QA re-delivery check 1: an issue body with ZERO recognized GFM
# task-list checkboxes (framework #73's own body is a numbered list, not
# checkboxes) must not silently read as "nothing to check, so PASS" — that
# is exactly the "no criterion was proven" gap QA found live. No recognized
# AC line means this script cannot verify anything, so it refuses, loudly,
# rather than reporting a clean PASS with zero content behind it.
if [ "$TOTAL_CHECKBOX_COUNT" -eq 0 ]; then
  bad "no acceptance-criteria checkboxes ('- [ ] ...') found in the issue body — cannot verify anything; rewrite the issue's Acceptance Criteria as GFM task-list items (see skills/delivery-check/SKILL.md)"
fi

# ── run each AC's proof command both ways ────────────────────────────────
if [ "$AC_COUNT" -gt 0 ]; then
  BASE_SHA="$(git merge-base HEAD "$BASE_REF" 2>/dev/null || true)"
  if [ -z "$BASE_SHA" ]; then
    bad "cannot resolve merge-base of HEAD and $BASE_REF — cannot prove any AC"
  else
    REVERT_WT="$(mktemp -d)"
    if git worktree add --detach --quiet "$REVERT_WT" "$BASE_SHA" >/dev/null 2>&1; then
      while IFS=$'\t' read -r cmd desc; do
        [ -n "$cmd" ] || continue
        # Printed before execution: this command came from the issue body,
        # not from whoever is running the check (see the SECURITY note at
        # the top of this file) — visible before it runs, not only after.
        note "running proof: \`$cmd\`"
        before_rc=0; ( cd "$REVERT_WT" && eval "$cmd" ) >/dev/null 2>&1 || before_rc=$?
        after_rc=0; ( eval "$cmd" ) >/dev/null 2>&1 || after_rc=$?
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
      if eval "$cmd" >/dev/null 2>&1; then
        ok "DELIVERY_TEST_CMDS[$glob]: $cmd"
      else
        bad "DELIVERY_TEST_CMDS[$glob] failed: $cmd"
      fi
    fi
  done < "$TEST_CMDS_FILE"
fi

# ── AC3: PR checks ────────────────────────────────────────────────────────
if [ -n "$PR_BODY" ]; then
  if printf '%s' "$PR_BODY" | grep -Eiq "(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[[:space:]]+#${ISSUE}([^0-9]|$)"; then
    if [ "$TOTAL_CHECKBOX_COUNT" -eq 0 ]; then
      bad "PR body closes #$ISSUE but no AC checkboxes were found to verify against — cannot confirm none are open"
    elif [ "$UNTICKED_COUNT" -gt 0 ]; then
      bad "PR body closes #$ISSUE with $UNTICKED_COUNT unticked AC line(s) still open"
    else
      ok "close keyword present, no unticked ACs remain"
    fi
  fi
fi

# #5239 QA re-delivery check 3: the check resolved a base to prove ACs
# against, but never confirmed the PR was actually OPENED against that same
# base — a PR opened against the wrong branch (e.g. main, for an item that
# belongs on an integration branch) passed silently. Compare the PR's real
# baseRefName (GitHub, unprefixed) against the resolved --base
# (origin/<branch> form) with the origin/ prefix stripped for the compare.
if [ -n "$PR" ] && [ -n "$PR_BASE_REF" ] && [ -n "$BASE_REF" ]; then
  RESOLVED_BASE_UNPREFIXED="${BASE_REF#origin/}"
  if [ "$PR_BASE_REF" = "$RESOLVED_BASE_UNPREFIXED" ]; then
    ok "PR is opened against the resolved base ($PR_BASE_REF)"
  else
    bad "PR is opened against '$PR_BASE_REF' but the resolved base is '$RESOLVED_BASE_UNPREFIXED' — wrong target branch"
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

case "$PR_MERGEABLE" in
  MERGEABLE) ok "PR is mergeable against the current base tip" ;;
  UNKNOWN) note "PR mergeable state unknown (no --pr / no gh / not yet computed) — not scored" ;;
  *) bad "PR is not mergeable against the current base tip (state: $PR_MERGEABLE)" ;;
esac

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
