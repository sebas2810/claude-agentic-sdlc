#!/usr/bin/env bash
# Rule tests for onboarding/hooks/guard-git.sh. Every block has a matching allow case, so a
# guard that blocks everything fails this suite as surely as one that blocks
# nothing.
#
# Usage: bash onboarding/tests/guard-rules.test.sh [path/to/guard-git.sh]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${1:-$HERE/../hooks/guard-git.sh}"
GUARD="$(cd "$(dirname "$GUARD")" && pwd)/$(basename "$GUARD")"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main

P="p""ush"  # split so this file never trips a guard scanning for the verb
ATTR="Co-Authored-By: Claude <noreply@anthropic.com>"

git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/repo" 2>/dev/null
R="$T/repo"
echo a > "$R/f"; git -C "$R" add f; git -C "$R" commit -qm base
git -C "$R" $P -q origin main 2>/dev/null
git -C "$R" checkout -qb work

run() { # $1 = command, $2.. = extra env; prints the exit code
  local cmd="$1"; shift
  jq -n --arg c "$cmd" '{tool_input:{command:$c}}' \
    | ( cd "$R" && env "$@" bash "$GUARD" >/dev/null 2>&1 ); echo $?
}
fail=0
chk() { # label expected got
  if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1 (expected $2, got $3)"; fail=1; fi
}

echo "protected refs"
chk "push to main blocks"                 2 "$(run "git $P origin main")"
chk "push HEAD:main blocks"               2 "$(run "git $P origin HEAD:main")"
chk "push a feature branch allows"        0 "$(run "git $P -u origin work")"
chk "push a branch named feat/main-x allows" 0 "$(run "git $P origin feat/main-x")"
chk "push to release/1.0 blocks"          2 "$(run "git $P origin release/1.0")"
chk "release push with ceremony env allows" 0 "$(run "git $P origin release/1.0" AGENTIC_SDLC_ALLOW_RELEASE_PUSH=1)"
chk "git -C <dir> push main blocks"       2 "$(run "git -C $R $P origin main")"
chk "prose quoting a push to main allows" 0 "$(run "gh issue create --title x --body 'never run git $P origin main'")"
git -C "$R" checkout -q main
chk "bare push while on main blocks"      2 "$(run "git $P")"
git -C "$R" checkout -q work

echo "attribution in commit commands"
chk "commit -m with a trailer blocks"     2 "$(run "git commit -m 'fix' -m '$ATTR'")"
chk "clean commit -m allows"              0 "$(run "git commit -m 'fix: a clean message'")"

echo "attribution in the commits being pushed"
printf 'feat: x\n\n%s\n' "$ATTR" > "$T/msg"
echo b >> "$R/f"; git -C "$R" commit -qaF "$T/msg"
chk "commit made with -F, then pushed, blocks" 2 "$(run "git $P origin work")"
git -C "$R" commit -q --amend -m "feat: x"
chk "same commit reworded, then pushed, allows" 0 "$(run "git $P origin work")"
git -C "$R" checkout -q main
printf 'old: y\n\n%s\n' "$ATTR" > "$T/msg"
echo c >> "$R/f"; git -C "$R" commit -qaF "$T/msg"
git -C "$R" $P -q origin main 2>/dev/null
git -C "$R" checkout -q -b later
echo d >> "$R/f"; git -C "$R" commit -qam "feat: later"
chk "attribution already on the remote does not block a new clean push" 0 "$(run "git $P origin later")"

echo "attribution in PR bodies"
chk "gh pr create with an inline footer blocks" 2 "$(run "gh pr create --title t --body 'x 🤖 Generated with [Claude Code](https://claude.com/claude-code)'")"
printf 'Summary\n\nGenerated with Claude Code\n' > "$T/body.md"
chk "gh pr create --body-file with a footer blocks" 2 "$(run "gh pr create --title t --body-file $T/body.md")"
printf 'Summary\n' > "$T/clean.md"
chk "gh pr create with a clean body file allows" 0 "$(run "gh pr create --title t --body-file $T/clean.md")"

echo "admin merge"
chk "--admin without approval blocks"     2 "$(run "gh pr merge 12 --squash --admin")"
chk "--admin approved for this PR allows" 0 "$(run "gh pr merge 12 --squash --admin" AGENTIC_SDLC_OWNER_ADMIN_MERGE=12)"
chk "--admin approved for another PR blocks" 2 "$(run "gh pr merge 12 --squash --admin" AGENTIC_SDLC_OWNER_ADMIN_MERGE=13)"
chk "plain squash merge allows"           0 "$(run "gh pr merge 12 --squash")"

echo "pre-push gate"
chk "failing gate blocks"                 2 "$(run "git $P origin later" AGENTIC_SDLC_GATE_CMD=false TMPDIR="$T")"
chk "passing gate allows"                 0 "$(run "git $P origin later" AGENTIC_SDLC_GATE_CMD=true TMPDIR="$T")"

echo "unrelated commands"
chk "ls allows"                           0 "$(run "ls -la")"
chk "git status allows"                   0 "$(run "git status")"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
