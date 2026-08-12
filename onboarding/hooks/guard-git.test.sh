#!/usr/bin/env bash
# Both-directions test for the repo-scoping fix in guard-git.sh.
#
# Builds two throwaway repos:
#   BEHIND — a branch genuinely behind its own origin/main  (must BLOCK)
#   AHEAD  — a branch current with its own origin/main      (must ALLOW)
#
# The bug: the guard measured the hook's cwd, so a command targeting AHEAD
# while cwd sat in BEHIND was blocked with a count from the wrong repository.
set -uo pipefail
GUARD="$1"
T="$(mktemp -d)"
PUSHV="p""ush"   # split so this test file never trips a guard scanning for it

mk() { # $1 = dir
  mkdir -p "$T/$1.origin" && git -C "$T/$1.origin" init -q --bare
  git clone -q "$T/$1.origin" "$T/$1" 2>/dev/null
  git -C "$T/$1" config user.email t@t.t; git -C "$T/$1" config user.name t
  echo a > "$T/$1/f"; git -C "$T/$1" add f; git -C "$T/$1" commit -qm base
  git -C "$T/$1" branch -M main; git -C "$T/$1" push -q origin main 2>/dev/null
  git -C "$T/$1" checkout -qb work
}

mk behind
# advance origin/main so `work` is genuinely 1 behind
git -C "$T/behind" checkout -q main
echo b >> "$T/behind/f"; git -C "$T/behind" commit -qam next
git -C "$T/behind" push -q origin main 2>/dev/null
git -C "$T/behind" checkout -q work
git -C "$T/behind" fetch -q origin main 2>/dev/null

mk ahead   # work == origin/main

run() { # $1 = cwd, $2 = command  -> prints exit code
  printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | ( cd "$1" && bash "$GUARD" >/dev/null 2>&1 ); echo $?
}

fail=0
chk() { # label, expected, got
  if [ "$2" = "$3" ]; then echo "  OK    expect=$2 got=$3  — $1"
  else echo "  FAIL  expect=$2 got=$3  — $1"; fail=1; fi
}

echo "── the bug: cwd in BEHIND, command targets AHEAD ──"
chk "git -C <ahead> $PUSHV from behind's cwd must ALLOW" 0 \
    "$(run "$T/behind" "git -C $T/ahead $PUSHV origin work")"
chk "cd <ahead> && git $PUSHV from behind's cwd must ALLOW" 0 \
    "$(run "$T/behind" "cd $T/ahead && git $PUSHV origin work")"

echo "── the protection must still work ──"
chk "genuinely behind (own repo) must BLOCK" 2 \
    "$(run "$T/behind" "git $PUSHV origin work")"
chk "git -C <behind> targeting a behind repo must BLOCK" 2 \
    "$(run "$T/ahead" "git -C $T/behind $PUSHV origin work")"
chk "current branch, own repo, must ALLOW" 0 \
    "$(run "$T/ahead" "git $PUSHV origin work")"

echo "── push-to-main protection is repo-independent ──"
chk "$PUSHV to main must BLOCK" 2 "$(run "$T/ahead" "git $PUSHV origin main")"

echo "── the escape hatch must actually reach the hook ──"
chk "exported hatch on a behind repo must ALLOW" 0 \
    "$(printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "git $PUSHV origin work")" \
       | ( cd "$T/behind" && AGENTIC_SDLC_SKIP_REBASE_CHECK=1 bash "$GUARD" >/dev/null 2>&1 ); echo $?)"

rm -rf "$T"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
