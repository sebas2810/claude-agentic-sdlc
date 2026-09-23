#!/usr/bin/env bash
# sync-sdlc.sh removes a file canonical retired, and only that: never a file
# the instance authored, and never one the instance edited since it synced.
# Offline: a local fake canonical repo stands in for GitHub.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$HERE/../sync-sdlc.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --global user.email t@example.com; git config --global user.name t
git config --global init.defaultBranch main

C="$T/canonical"; mkdir -p "$C/workflow" "$C/agents"
echo keep > "$C/README.md"; echo w > "$C/workflow/fresh.md"; echo a > "$C/agents/worker.md"; echo e > "$C/workflow/edited.md"
git -C "$C" init -q && git -C "$C" add -A && git -C "$C" commit -qm v1
V1="$(git -C "$C" rev-parse HEAD)"

I="$T/instance"; mkdir -p "$I"; cp -R "$C/." "$I/"; rm -rf "$I/.git"
echo "$V1" > "$I/.sdlc-version"
echo mine > "$I/workflow/local-rule.md"          # instance-authored
echo "edited by the instance" > "$I/workflow/edited.md"  # edited after sync

git -C "$C" rm -q workflow/fresh.md agents/worker.md workflow/edited.md
echo keep2 > "$C/README.md"; git -C "$C" commit -qam v2

fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1 (expected $2, got $3)"; fail=1; fi; }
ex() { [ -e "$1" ] && echo yes || echo no; }
run() { CANONICAL_URL="$C" SDLC_ROOT="$I" bash "$SYNC" "$@"; }

R="$(run)"
chk "report lists the retired file"            yes "$(echo "$R" | grep -q '  - workflow/fresh.md' && echo yes || echo no)"
chk "report writes nothing"                    yes "$(ex "$I/workflow/fresh.md")"
echo apply | run --apply >/dev/null 2>&1
chk "retired, unchanged file removed"          no  "$(ex "$I/workflow/fresh.md")"
chk "retired file's empty folder removed"      no  "$(ex "$I/agents")"
chk "instance-authored file kept"              yes "$(ex "$I/workflow/local-rule.md")"
chk "retired but locally edited file kept"     yes "$(ex "$I/workflow/edited.md")"
chk "changed file updated"                     keep2 "$(cat "$I/README.md")"

# Without a recorded version nothing can be told apart, so nothing is removed.
I2="$T/instance2"; mkdir -p "$I2/workflow"; echo w > "$I2/workflow/fresh.md"; echo keep > "$I2/README.md"
echo apply | CANONICAL_URL="$C" SDLC_ROOT="$I2" bash "$SYNC" --apply >/dev/null 2>&1
chk "no .sdlc-version: nothing removed"        yes "$(ex "$I2/workflow/fresh.md")"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"; exit "$fail"
