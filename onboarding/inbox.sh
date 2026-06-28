#!/usr/bin/env bash
#
# inbox.sh — the per-seat local work inbox: the $0, API-free wake surface.
#
# The autonomous loop is event-driven (feedback/architecture/event-driven-orchestration.md):
# ONLY the Scrum-Master reads the GitHub Projects board (the single GraphQL consumer). Every other
# seat (producers, Quality, PM) is *woken* by an item appearing in its local inbox — a plain
# directory of JSON files on this machine. Reading it costs a filesystem stat, never a GitHub call,
# so N idle seats no longer cannibalise one shared rate budget (the 2026-06-28 exhaustion incident).
#
# The SM (and the /recheck · /dispatch slash-commands) PUSH items here; seat-loop-hook.sh PEEKs here
# instead of polling the board. Idempotent by filename → a duplicate webhook/dispatch is a no-op (O3).
#
# Layout:  $INBOX_ROOT/<key>/<item>-<action>.json     one file per (item, action)
#          $INBOX_ROOT/.paused                         kill-switch flag (honoured by the hook)
#   INBOX_ROOT defaults to ~/.agentic-sdlc/<INSTANCE>/inbox  (override with SAMMY_INBOX_ROOT).
#   <key> is the seat key: a producer's label suffix (seat:dex → "dex") or the role (pm, quality-engineer).
#
# Usage:
#   inbox.sh push  --key dex --item 101 --action claim+build [--ac "#101 ## Steer"] \
#                  [--epic 245] [--by sm|webhook] [--event <id>] [--title "..."] [--label seat:dex]
#   inbox.sh peek  --key dex            # print the oldest item's JSON (empty if none) — what the hook reads
#   inbox.sh list  --key dex            # print every queued item JSON (newline-delimited)
#   inbox.sh count --key dex            # number of queued items
#   inbox.sh pop   --key dex --item 101 # consume (remove) item 101's file(s) after handover/done
#   inbox.sh path  [--key dex]          # print the resolved inbox dir (or root)
#   inbox.sh pause | resume | paused    # manage / test the global .paused kill-switch
#
set -uo pipefail

INBOX_ROOT="${SAMMY_INBOX_ROOT:-$HOME/.agentic-sdlc/${INSTANCE:-seat}/inbox}"

cmd="${1:-}"; [ $# -gt 0 ] && shift
KEY="" ITEM="" ACTION="" AC="" EPIC="" BY="cli" EVENT="" TITLE="" LABEL=""
while [ $# -gt 0 ]; do case "$1" in
  --key)    KEY="$2"; shift 2 ;;
  --item)   ITEM="$2"; shift 2 ;;
  --action) ACTION="$2"; shift 2 ;;
  --ac)     AC="$2"; shift 2 ;;
  --epic)   EPIC="$2"; shift 2 ;;
  --by)     BY="$2"; shift 2 ;;
  --event)  EVENT="$2"; shift 2 ;;
  --title)  TITLE="$2"; shift 2 ;;
  --label)  LABEL="$2"; shift 2 ;;
  *) echo "inbox.sh: unknown arg: $1" >&2; exit 2 ;;
esac; done

# sanitise a value into a safe filename token (alnum + dash)
slug() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9' '-' | sed -E 's/-+/-/g; s/^-|-$//g'; }
dir_for() { printf '%s/%s' "$INBOX_ROOT" "$(slug "$1")"; }

case "$cmd" in
  push)
    [ -n "$KEY" ] && [ -n "$ITEM" ] && [ -n "$ACTION" ] || { echo "push needs --key --item --action" >&2; exit 2; }
    command -v jq >/dev/null 2>&1 || { echo "inbox.sh: jq required" >&2; exit 3; }
    d="$(dir_for "$KEY")"; mkdir -p "$d"
    f="$d/$(slug "$ITEM")-$(slug "$ACTION").json"   # idempotent: same (item,action) → same file
    jq -cn \
      --argjson item "$ITEM" --arg seat "$KEY" --arg action "$ACTION" --arg ac "$AC" \
      --arg epic "$EPIC" --arg by "$BY" --arg event "${EVENT:-$ITEM-$ACTION}" \
      --arg title "$TITLE" --arg label "$LABEL" \
      '{item:$item, seat:$seat, action:$action, ac_ref:$ac, epic:$epic,
        enqueued_by:$by, event_id:$event, title:$title, label:$label}' > "$f" \
      && echo "queued → $f"
    ;;
  peek)
    d="$(dir_for "$KEY")"
    [ -d "$d" ] || exit 0
    # oldest first (FIFO) — ls -tr orders by mtime ascending
    f="$(ls -1tr "$d"/*.json 2>/dev/null | head -1)"
    [ -n "$f" ] && cat "$f"
    ;;
  list)
    d="$(dir_for "$KEY")"
    [ -d "$d" ] || exit 0
    for f in $(ls -1tr "$d"/*.json 2>/dev/null); do cat "$f"; echo; done
    ;;
  count)
    d="$(dir_for "$KEY")"
    [ -d "$d" ] && ls -1 "$d"/*.json 2>/dev/null | wc -l | tr -d ' ' || echo 0
    ;;
  pop)
    [ -n "$KEY" ] && [ -n "$ITEM" ] || { echo "pop needs --key --item" >&2; exit 2; }
    d="$(dir_for "$KEY")"
    n=0
    for f in "$d/$(slug "$ITEM")"-*.json; do [ -e "$f" ] && { rm -f "$f"; n=$((n+1)); }; done
    echo "popped $n file(s) for item $ITEM from $KEY"
    ;;
  path)
    [ -n "$KEY" ] && dir_for "$KEY" || printf '%s\n' "$INBOX_ROOT"
    ;;
  pause)   mkdir -p "$INBOX_ROOT"; : > "$INBOX_ROOT/.paused"; echo "loop PAUSED ($INBOX_ROOT/.paused)" ;;
  resume)  rm -f "$INBOX_ROOT/.paused"; echo "loop RESUMED" ;;
  paused)  [ -f "$INBOX_ROOT/.paused" ] && { echo "paused"; exit 0; } || { echo "active"; exit 1; } ;;
  ""|help|-h|--help)
    sed -n '2,30p' "$0" ;;
  *) echo "inbox.sh: unknown command '$cmd' (push|peek|list|count|pop|path|pause|resume|paused)" >&2; exit 2 ;;
esac
