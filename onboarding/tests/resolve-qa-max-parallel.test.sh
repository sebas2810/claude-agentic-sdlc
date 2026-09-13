#!/usr/bin/env bash
#
# Both-directions test for resolve-qa-max-parallel.sh (#76, criterion 2).
#
# The defect it guards: a parallel cap that is silently wrong. A typo in
# QA_MAX_PARALLEL that falls back to the default runs a number of parallel
# verifiers nobody chose, and an unreadable .env.local read as "unset" does the
# same while looking configured. Both must fail loudly; valid values, in the
# documented order, must resolve exactly.
#
# Usage: resolve-qa-max-parallel.test.sh <path-to-resolve-qa-max-parallel.sh>
set -uo pipefail

S="${1:-}"
[ -n "$S" ] || { echo "usage: $0 <path-to-resolve-qa-max-parallel.sh>" >&2; exit 1; }
case "$S" in /*) ;; *) S="$(cd "$(dirname "$S")" && pwd)/$(basename "$S")" ;; esac
[ -f "$S" ] || { echo "no such script: $S" >&2; exit 1; }

T="$(mktemp -d)"
trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
ok()   { printf '  OK    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
skip() { printf '  SKIP  %s\n' "$1"; }

# value <description> <expected stdout> <command...>: exit 0 and exactly that value
value() {
  local desc="$1" want="$2" out rc; shift 2
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then ok "$desc"; else bad "$desc (exit $rc, got '$out', want '$want')"; fi
}
# refused <description> <text stderr must contain> <command...>: exit 2 and a named cause
refused() {
  local desc="$1" needle="$2" out rc; shift 2
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF -- "$needle"; then ok "$desc"; else bad "$desc (exit $rc, output '$out')"; fi
}

NONE="$T/absent.env"
printf 'SEAT_ROLE=quality-engineer\nQA_MAX_PARALLEL=2\n' > "$T/two.env"
printf 'QA_MAX_PARALLEL="6"    # six at once\n' > "$T/quoted.env"
printf 'QA_MAX_PARALLEL=\n' > "$T/empty.env"
printf 'QA_MAX_PARALLEL=0\n' > "$T/zero.env"
printf 'QA_MAX_PARALLEL=1\nQA_MAX_PARALLEL=4\n' > "$T/twice.env"
mkdir -p "$T/seat" && printf 'QA_MAX_PARALLEL=7\n' > "$T/seat/.env.local"
printf 'QA_MAX_PARALLEL=4 \r\n' > "$T/crlf.env"
printf 'QA_MAX_PARALLEL=999\n' > "$T/three-digits.env"
printf '# QA_MAX_PARALLEL=5\n  # QA_MAX_PARALLEL=6\n' > "$T/commented.env"
printf 'QA_MAX_PARALLEL=3 4\n' > "$T/inner-space.env"
printf 'QA_MAX_PARALLEL="3 4"\n' > "$T/quoted-inner-space.env"
printf 'QA_MAX_PARALLEL=99999999999999999999\n' > "$T/huge.env"
printf 'export QA_MAX_PARALLEL=5\n' > "$T/export.env"
printf 'QA_MAX_PARALLEL = 5\n' > "$T/spaced.env"
printf '  QA_MAX_PARALLEL=0\n' > "$T/indented.env"
printf 'QA_MAX_PARALLEL=2\nexport QA_MAX_PARALLEL=5\n' > "$T/strict-then-loose.env"
EXAMPLE="$(cd "$(dirname "$S")/.." && pwd)/.env.local.example"

value "unset everywhere resolves to the default 3" 3 env -u QA_MAX_PARALLEL bash "$S" "$NONE"
value "the environment value is used" 5 env QA_MAX_PARALLEL=5 bash "$S" "$NONE"
value "the env file value is used when the environment has none" 2 env -u QA_MAX_PARALLEL bash "$S" "$T/two.env"
value "the environment wins over the env file" 4 env QA_MAX_PARALLEL=4 bash "$S" "$T/two.env"
value "quotes and a trailing comment are stripped" 6 env -u QA_MAX_PARALLEL bash "$S" "$T/quoted.env"
value "the last assignment in the env file wins" 4 env -u QA_MAX_PARALLEL bash "$S" "$T/twice.env"
value "an empty value counts as unset" 3 env -u QA_MAX_PARALLEL bash "$S" "$T/empty.env"
value "the default env file is ./.env.local" 7 sh -c "cd '$T/seat' && env -u QA_MAX_PARALLEL bash '$S'"
value "whitespace and a CR at the ends of the value are stripped" 4 env -u QA_MAX_PARALLEL bash "$S" "$T/crlf.env"
value "three digits is the most a cap has" 999 env -u QA_MAX_PARALLEL bash "$S" "$T/three-digits.env"
value "a commented-out line is not a setting" 3 env -u QA_MAX_PARALLEL bash "$S" "$T/commented.env"
value "the shipped .env.local.example resolves" 3 env -u QA_MAX_PARALLEL bash "$S" "$EXAMPLE"

refused "a non-number is refused, naming the value and where it came from" \
  "QA_MAX_PARALLEL='abc' (from environment)" env QA_MAX_PARALLEL=abc bash "$S" "$NONE"
refused "zero is refused, naming the file it came from" \
  "(from $T/zero.env)" env -u QA_MAX_PARALLEL bash "$S" "$T/zero.env"
refused "a negative number is refused" \
  "QA_MAX_PARALLEL='-1'" env QA_MAX_PARALLEL=-1 bash "$S" "$NONE"

# The cap must be the number somebody wrote. Each case below once resolved to a
# different number, or to the default, with exit 0.
refused "a space inside the value is refused, not squeezed out ('3 4' is not 34)" \
  "QA_MAX_PARALLEL='3 4'" env -u QA_MAX_PARALLEL bash "$S" "$T/inner-space.env"
refused "a space inside a quoted value is refused" \
  "QA_MAX_PARALLEL='3 4'" env -u QA_MAX_PARALLEL bash "$S" "$T/quoted-inner-space.env"
refused "more than 3 digits from the environment is refused, not wrapped" \
  "has more than 3 digits" env QA_MAX_PARALLEL=99999999999999999999 bash "$S" "$NONE"
refused "more than 3 digits from the env file is refused, not wrapped" \
  "has more than 3 digits" env -u QA_MAX_PARALLEL bash "$S" "$T/huge.env"
refused "four digits is refused" \
  "QA_MAX_PARALLEL='1000'" env QA_MAX_PARALLEL=1000 bash "$S" "$NONE"
refused "an export line is refused, not skipped for the default" \
  "'export QA_MAX_PARALLEL=5'" env -u QA_MAX_PARALLEL bash "$S" "$T/export.env"
refused "spaces around = are refused, not skipped for the default" \
  "'QA_MAX_PARALLEL = 5'" env -u QA_MAX_PARALLEL bash "$S" "$T/spaced.env"
refused "an indented line is refused, not skipped for the default" \
  "'  QA_MAX_PARALLEL=0'" env -u QA_MAX_PARALLEL bash "$S" "$T/indented.env"
refused "a loose line is refused even next to a strict one" \
  "'export QA_MAX_PARALLEL=5'" env -u QA_MAX_PARALLEL bash "$S" "$T/strict-then-loose.env"

if [ "$(id -u)" -eq 0 ]; then
  skip "unreadable env file (root reads a mode-000 file)"
else
  printf 'QA_MAX_PARALLEL=9\n' > "$T/locked.env" && chmod 000 "$T/locked.env"
  refused "an unreadable env file is an error, not 'unset'" \
    "cannot read $T/locked.env" env -u QA_MAX_PARALLEL bash "$S" "$T/locked.env"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "resolve-qa-max-parallel: all checks passed"
else
  echo "resolve-qa-max-parallel: $fails check(s) FAILED" >&2
fi
exit "$fails"
