#!/usr/bin/env bash
#
# Parity suite: every rule a forked instance guard carried must have a canonical
# equivalent here, demonstrated case-by-case, BEFORE any instance deletes its
# copy. "The canonical guard covers it" is an assertion; this file is the proof.
#
# Rule: feedback/architecture/one-control-one-implementation.md
#
# Usage: guard-git.parity.test.sh <path-to-guard-git.sh>
set -uo pipefail

GUARD="${1:-}"
[ -n "$GUARD" ] || { echo "usage: $0 <path-to-guard-git.sh>" >&2; exit 1; }
case "$GUARD" in /*) ;; *) GUARD="$(cd "$(dirname "$GUARD")" && pwd)/$(basename "$GUARD")" ;; esac
[ -x "$GUARD" ] || { echo "guard not executable: $GUARD" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
V="p""ush"   # split so this file never trips a guard scanning for the verb

# run <expected> <label> <command> — runs the guard with the given command.
run() {
  local exp="$1" label="$2" cmd="$3" got
  printf '{"tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | jq -Rs .)" | ( cd "$T/repo" 2>/dev/null || cd "$T" || exit 1; bash "$GUARD" ) >/dev/null 2>&1
  got=$?
  if [ "$got" = "$exp" ]; then printf '  OK    expect=%s got=%s  — %s\n' "$exp" "$got" "$label"
  else printf '  FAIL  expect=%s got=%s  — %s\n' "$exp" "$got" "$label"; fails=$((fails+1)); fi
}

# A clean repo, current with its own origin/main.
mkdir -p "$T/origin" && git -C "$T/origin" init -q --bare
git clone -q "$T/origin" "$T/repo" 2>/dev/null
git -C "$T/repo" config user.email t@t.t; git -C "$T/repo" config user.name t
echo a > "$T/repo/f"; git -C "$T/repo" add f; git -C "$T/repo" commit -qm base
git -C "$T/repo" branch -M main; git -C "$T/repo" $V -q origin main 2>/dev/null
git -C "$T/repo" checkout -qb work

echo "── fork rule: protected refs, including the pre-verb forms ──"
run 2 "plain push to main"                "git $V origin main"
run 2 "pre-verb -C"                       "git -C . $V origin main"
run 2 "pre-verb --no-pager"               "git --no-pager $V origin main"
run 2 "pre-verb -c k=v"                   "git -c k=v $V origin main"

echo "── fork rule: release lines are protected, ceremony may override ──"
run 2 "push to a release line blocks"     "git $V origin release/v1.3.0"
AGENTIC_SDLC_ALLOW_RELEASE_PUSH=1 run 0 "ceremony override permits it" "git $V origin release/v1.3.0"

echo "── fork rule: --admin merge is owner-gated, per PR ──"
run 2 "admin merge with no authorisation" "gh pr merge 4063 --squash --admin"
run 2 "admin merge, flags reordered"      "gh pr merge 4063 --admin --squash"
AGENTIC_SDLC_OWNER_ADMIN_MERGE=4063 run 0 "authorised for this exact pr"   "gh pr merge 4063 --squash --admin"
AGENTIC_SDLC_OWNER_ADMIN_MERGE=4063 run 2 "authorisation does NOT carry"   "gh pr merge 4099 --squash --admin"
run 0 "a normal merge is untouched"       "gh pr merge 4063 --squash"

echo "── fork rule: quoted text and heredocs are not commands ──"
run 0 "prose quoting the command"         "gh issue create --body \"do not git $V origin main\""
run 0 "the verb inside a single-quoted arg" "echo 'git $V origin main'"
run 2 "a REAL push after a quoted decoy"  "echo 'nothing here' && git $V origin main"

echo "── canonical rule: AI attribution ──"
run 2 "Co-Authored-By: Claude in a commit" "git commit -m 'x' -m 'Co-Authored-By: Claude <n@a.com>'"
run 0 "an ordinary commit"                 "git commit -m 'ordinary message'"

echo "── #3325 Bug 1: the branch PUSHED is measured, not the hook's HEAD ──"
# `work` is current; make main-tracking stale so HEAD-based measurement would differ.
git -C "$T/repo" checkout -q -b stale main 2>/dev/null
echo b > "$T/repo/g"; git -C "$T/repo" add g; git -C "$T/repo" commit -qm advance
git -C "$T/repo" $V -q origin stale:main 2>/dev/null
git -C "$T/repo" fetch -q origin 2>/dev/null
git -C "$T/repo" checkout -q work
run 2 "a genuinely behind branch still blocks" "git $V origin work"

echo "── the gate command (rule 5) ──"
AGENTIC_SDLC_SKIP_REBASE_CHECK=1 AGENTIC_SDLC_GATE_CMD='false' \
  run 2 "a failing pre-push gate blocks"    "git $V origin work"
AGENTIC_SDLC_SKIP_REBASE_CHECK=1 AGENTIC_SDLC_GATE_CMD='true' \
  run 0 "a passing pre-push gate allows"    "git $V origin work"
AGENTIC_SDLC_SKIP_REBASE_CHECK=1 \
  run 0 "no gate configured = unchanged"    "git $V origin work"

echo "── unrelated commands are never touched ──"
run 0 "git status"                        "git status"
run 0 "a non-git command"                 "ls -la"

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ($fails)"; fi
exit $((fails > 0))
