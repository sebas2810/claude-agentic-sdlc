#!/usr/bin/env bash
#
# check-plugin-version-bump.sh — a change to what the plugin ships must raise its version (#77).
#
# An installed plugin cache refreshes only when .claude-plugin/plugin.json's "version" changes. One
# instance ran a 0.1.0 cache that never updated while the commands it carried moved on. This check
# compares HEAD with its merge-base on <base-ref>: when a shipped path changed, the version at HEAD
# must be higher than the version at the merge-base. Any higher version passes, so parallel PRs do
# not have to agree on one number.
#
# Shipped paths: commands/ · skills/ · agents/ · onboarding/hooks/ (except *.test.sh) · .claude-plugin/
#
# Usage: check-plugin-version-bump.sh [base-ref]     (default origin/main; run inside the repository)
# Exit:  0 no shipped change, or the version was raised
#        1 a shipped path changed and the version was not raised
#        2 could not determine: not a repository, base ref missing (a shallow clone?), no merge-base,
#          plugin.json unreadable, or a version that is not MAJOR.MINOR.PATCH
set -uo pipefail

BASE="${1:-origin/main}"
MANIFEST=".claude-plugin/plugin.json"
SHIPPED=(commands skills agents onboarding/hooks .claude-plugin)
die(){ printf 'check-plugin-version-bump: %s\n' "$1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq is required and not installed"
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$TOP" || die "cannot enter $TOP"
git rev-parse --verify -q "${BASE}^{commit}" >/dev/null \
  || die "base ref '$BASE' does not resolve (a shallow clone? fetch it with full history)"
MB="$(git merge-base "$BASE" HEAD 2>&1)" || die "no merge-base between '$BASE' and HEAD: $MB"

CHANGED="$(git diff --name-only "$MB" HEAD -- "${SHIPPED[@]}" 2>&1)" || die "git diff failed: $CHANGED"
CHANGED="$(printf '%s\n' "$CHANGED" | grep -v -e '^$' -e '\.test\.sh$' || true)"
SHORT="$(git rev-parse --short "$MB")"
if [ -z "$CHANGED" ]; then
  echo "check-plugin-version-bump: no shipped plugin content changed since $SHORT; no bump needed"
  exit 0
fi

version_at(){ # version_at <rev> <label>
  local json v
  json="$(git show "$1:$MANIFEST" 2>&1)" || die "cannot read $MANIFEST at $2: $json"
  v="$(printf '%s' "$json" | jq -er '.version' 2>/dev/null)" || die "$MANIFEST at $2 has no readable \"version\""
  printf '%s' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "$MANIFEST at $2 has version '$v'; expected MAJOR.MINOR.PATCH"
  printf '%s' "$v"
}
OLD="$(version_at "$MB" "the merge-base $SHORT")" || exit 2
NEW="$(version_at HEAD HEAD)" || exit 2

IFS=. read -r o1 o2 o3 <<<"$OLD"
IFS=. read -r n1 n2 n3 <<<"$NEW"
RAISED=0
if   [ "$n1" -ne "$o1" ]; then [ "$n1" -gt "$o1" ] && RAISED=1
elif [ "$n2" -ne "$o2" ]; then [ "$n2" -gt "$o2" ] && RAISED=1
elif [ "$n3" -gt "$o3" ]; then RAISED=1
fi

echo "check-plugin-version-bump: shipped plugin content changed since $SHORT:"
printf '%s\n' "$CHANGED" | sed 's/^/  /'
if [ "$RAISED" -eq 1 ]; then
  echo "  version $OLD -> $NEW: raised"
  exit 0
fi
echo "  version $OLD -> $NEW: NOT raised; set a higher \"version\" in $MANIFEST so installed plugin caches refresh"
exit 1
