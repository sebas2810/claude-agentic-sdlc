#!/usr/bin/env bash
#
# resolve-qa-max-parallel.sh: how many quality-workers the quality seat runs at
# once (workflow/fresh-context-workers.md).
#
# Order: QA_MAX_PARALLEL in the environment, else the last QA_MAX_PARALLEL= line
# of the env file (default ./.env.local, which bootstrap writes from
# sdlc.config), else 3. An empty value counts as unset.
#
# A value that is not a whole number of at least 1 is refused, not replaced by
# the default: a cap nobody chose, applied silently, is the weakened-default
# failure (feedback/architecture/weakening-a-default-must-signal.md). An env
# file that exists but cannot be read is an error too, never "unset".
#
# Usage:  resolve-qa-max-parallel.sh [env-file]
# Stdout: the cap.
# Exit 0: resolved. Exit 2: an invalid value or an unreadable env file (cause on stderr).
set -uo pipefail

ENV_FILE="${1:-.env.local}"
DEFAULT=3

value="${QA_MAX_PARALLEL:-}"
origin="environment"

if [ -z "$value" ] && [ -e "$ENV_FILE" ]; then
  if [ ! -r "$ENV_FILE" ] || [ -d "$ENV_FILE" ]; then
    echo "resolve-qa-max-parallel: cannot read $ENV_FILE" >&2
    exit 2
  fi
  if ! value="$(sed -n 's/^QA_MAX_PARALLEL=//p' "$ENV_FILE" | tail -1)"; then
    echo "resolve-qa-max-parallel: cannot read $ENV_FILE" >&2
    exit 2
  fi
  value="${value%%#*}"
  value="$(printf '%s' "$value" | tr -d '"'"'"' \t\r')"
  origin="$ENV_FILE"
fi

if [ -z "$value" ]; then
  echo "$DEFAULT"
  exit 0
fi

case "$value" in
  *[!0-9]*)
    echo "resolve-qa-max-parallel: QA_MAX_PARALLEL='$value' (from $origin) is not a whole number of at least 1" >&2
    exit 2 ;;
esac
cap=$((10#$value))
if [ "$cap" -lt 1 ]; then
  echo "resolve-qa-max-parallel: QA_MAX_PARALLEL='$value' (from $origin) is not a whole number of at least 1" >&2
  exit 2
fi
echo "$cap"
