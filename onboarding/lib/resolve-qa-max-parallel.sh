#!/usr/bin/env bash
#
# resolve-qa-max-parallel.sh: how many quality-workers the quality seat runs at
# once (workflow/fresh-context-workers.md).
#
# Order: QA_MAX_PARALLEL in the environment, else the last QA_MAX_PARALLEL= line
# of the env file (default ./.env.local, which bootstrap writes from
# sdlc.config), else 3. An empty value counts as unset.
#
# The cap is the number somebody wrote, or a refusal. Never another number:
#   - An env file line counts only in the strict form QA_MAX_PARALLEL=<value>,
#     at the start of the line. Any other line that mentions QA_MAX_PARALLEL
#     (`export QA_MAX_PARALLEL=5`, `QA_MAX_PARALLEL = 5`, an indented line) is
#     refused, because skipping it would put the default in place of a value
#     somebody set. A comment line is not a setting and is skipped.
#   - From the file, a trailing comment, whitespace and a CR at the ends, and
#     one pair of surrounding quotes are stripped. Nothing inside the value is:
#     `3 4` is refused, not read as 34.
#   - The value must be a whole number of at least 1 with at most 3 digits. A
#     longer one would wrap in shell arithmetic into a cap nobody chose.
# A refused value is not replaced by the default: a cap nobody chose, applied
# silently, is the weakened-default failure
# (feedback/architecture/weakening-a-default-must-signal.md). An env file that
# exists but cannot be read is an error too, never "unset".
#
# Usage:  resolve-qa-max-parallel.sh [env-file]
# Stdout: the cap.
# Exit 0: resolved. Exit 2: a refused value or line, or an unreadable env file (cause on stderr).
set -uo pipefail

ENV_FILE="${1:-.env.local}"
DEFAULT=3

refuse() { echo "resolve-qa-max-parallel: $1" >&2; exit 2; }

value="${QA_MAX_PARALLEL:-}"
origin="environment"

if [ -z "$value" ] && [ -e "$ENV_FILE" ]; then
  if [ ! -r "$ENV_FILE" ] || [ -d "$ENV_FILE" ]; then
    refuse "cannot read $ENV_FILE"
  fi
  # Exit 3 names the first loose line; exit 0 prints the last strict value.
  parsed="$(awk -v q="'" '
    /^[[:space:]]*#/ { next }
    index($0, "QA_MAX_PARALLEL") == 0 { next }
    /^QA_MAX_PARALLEL=/ { value = substr($0, length("QA_MAX_PARALLEL=") + 1); next }
    { print "line " NR ": " q $0 q; loose = 1; exit 3 }
    END { if (!loose) print value }
  ' "$ENV_FILE")"
  rc=$?
  case "$rc" in
    0) ;;
    3) refuse "$ENV_FILE $parsed mentions QA_MAX_PARALLEL but is not a QA_MAX_PARALLEL=<n> line at the start of the line" ;;
    *) refuse "cannot read $ENV_FILE" ;;
  esac
  value="${parsed%%#*}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  case "$value" in
    \"*\"|\'*\') value="${value:1:${#value}-2}" ;;
  esac
  origin="$ENV_FILE"
fi

if [ -z "$value" ]; then
  echo "$DEFAULT"
  exit 0
fi

case "$value" in
  *[!0-9]*) refuse "QA_MAX_PARALLEL='$value' (from $origin) is not a whole number of at least 1" ;;
esac
if [ "${#value}" -gt 3 ]; then
  refuse "QA_MAX_PARALLEL='$value' (from $origin) has more than 3 digits; a cap is a whole number from 1 to 999"
fi
cap=$((10#$value))
if [ "$cap" -lt 1 ]; then
  refuse "QA_MAX_PARALLEL='$value' (from $origin) is not a whole number of at least 1"
fi
echo "$cap"
