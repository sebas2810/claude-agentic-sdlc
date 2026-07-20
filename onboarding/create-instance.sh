#!/usr/bin/env bash
#
# create-instance.sh — the golden path. Stand up a new product instance on the
# agentic-SDLC framework in one run:
#   1. scaffold the instance overlay skeleton (instance/<name>/)
#   2. create the portable label taxonomy in the product repo
#   3. provision one Delivery project (carries both an EPICS view + a Board view)
#   4. seed the standing epics (so nothing is ever orphaned — workflow/hierarchy.md)
#
# Idempotent-ish: label/issue creation tolerate "already exists". Board creation
# always makes a NEW project (GitHub has no upsert) — run once per instance.
#
# Usage:
#   onboarding/create-instance.sh --instance sammy --owner sebas2810 --repo sebas2810/nestor-sammy
#   onboarding/create-instance.sh --instance sammy --owner sebas2810 --repo sebas2810/nestor-sammy --boards-only
#
# Requires: gh (with `project` scope) + node.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TPL="$ROOT/workflow/project-templates"

INSTANCE="" ; OWNER="" ; REPO="" ; BOARDS_ONLY=0 ; SKELETON_ONLY=0 ; GOLDEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) INSTANCE="$2"; shift 2 ;;
    --owner)    OWNER="$2"; shift 2 ;;
    --repo)     REPO="$2"; shift 2 ;;
    --golden)   GOLDEN="$2"; shift 2 ;;   # existing configured project to copyProjectV2 (views travel)
    --boards-only)   BOARDS_ONLY=1; shift ;;
    --skeleton-only) SKELETON_ONLY=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -n "$INSTANCE" ] || { echo "usage: create-instance.sh --instance <name> --owner <login> --repo <owner/repo>" >&2; exit 1; }

# ── 1. overlay skeleton ───────────────────────────────────────────────────────
if [ "$BOARDS_ONLY" -eq 0 ]; then
  DEST="$ROOT/instance/$INSTANCE"
  echo "→ scaffolding overlay: instance/$INSTANCE/"
  mkdir -p "$DEST/skills" "$DEST/rules"
  [ -f "$DEST/product-mapping.md" ] || cat > "$DEST/product-mapping.md" <<EOF
---
title: Product Mapping — $INSTANCE
status: draft
scope: instance-overlay
---

# $INSTANCE — product mapping

How the 7 principles (../../agentic-operating-model.md) govern the agents/product
**$INSTANCE** ships. Replace this scaffold with the real mapping.

| Principle | Product (how $INSTANCE applies it) |
|---|---|
| 1. Workflow-first | TODO |
| 2. Start simple | TODO |
| 3. Augmented atom | TODO |
| 4. Orchestrator-workers | TODO |
| 5. Verify ≠ produce | TODO |
| 6. ACI first-class | TODO |
| 7. Simplicity + human owns irreversible | TODO |
EOF
  [ -f "$DEST/engineering-standard.md" ] || cat > "$DEST/engineering-standard.md" <<EOF
---
title: Engineering Standard — $INSTANCE
status: draft
scope: instance-overlay
---

# $INSTANCE — engineering standard

The concrete, tiered bar on top of the framework floor
(../../engineering-standard.md). Replace this scaffold.
EOF
  [ -f "$DEST/skills/INDEX.md" ] || printf -- '# %s — Principal skills\n\nThe instance Principal skills (the model is ../../skills/INDEX.md). Add one file per skill.\n' "$INSTANCE" > "$DEST/skills/INDEX.md"
  [ -f "$DEST/rules/INDEX.md" ]  || printf -- '# %s — instance rules\n\nStack-specific feedback rules (portable ones stay in ../../feedback/). Add one file per rule.\n' "$INSTANCE" > "$DEST/rules/INDEX.md"
  echo "  overlay ready (fill in product-mapping.md + engineering-standard.md)."
  [ "$SKELETON_ONLY" -eq 1 ] && { echo "✓ skeleton-only: done."; exit 0; }
fi

[ -n "$OWNER" ] && [ -n "$REPO" ] || { echo "need --owner and --repo for labels/boards" >&2; exit 1; }

# ── 2. labels ─────────────────────────────────────────────────────────────────
echo "→ creating labels in $REPO"
node -e '
const fs=require("fs");const labels=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).labels;
for(const l of labels) console.log([l.name,l.color,l.description||""].join("\t"));
' "$TPL/labels.json" | while IFS=$'\t' read -r NAME COLOR DESC; do
  gh label create "$NAME" --repo "$REPO" --color "$COLOR" --description "$DESC" --force >/dev/null 2>&1 \
    && echo "  + $NAME" || echo "  · $NAME (exists)"
done

# ── 3. board ──────────────────────────────────────────────────────────────────
# ONE project per instance. Epics + stories + tasks all live here; the two audiences
# are served by two VIEWS on this single project, not two projects:
#   • Board view  — the 7-state Kanban (Status × Seat), the execution surface;
#                   filter: has:status -status:Backlog,Merged,Released,Cancelled (active flow only)
#   • EPICS view  — a Table filtered to label:level:epic, with Sub-issues progress (the
#                   owner+PM strategic roll-up that the old Program project used to be)
# The Projects API can't create/configure views, so the two views are applied from a
# golden template (copyProjectV2) or once in the UI — see workflow/project-boards.md.
TITLE_CASE="$(printf '%s' "$INSTANCE" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
BOARD_TITLE="$TITLE_CASE — Delivery"
# Reuse an existing board (GitHub has no project upsert — without this check a
# re-run would stand up a DUPLICATE Delivery project).
BOARD_NUM="$(gh project list --owner "$OWNER" --format json --limit 100 2>/dev/null \
  | BT="$BOARD_TITLE" node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const p=(JSON.parse(s).projects||[]).find(p=>p.title===process.env.BT);process.stdout.write(p?String(p.number):"")}catch(e){}})' || true)"
if [ -n "$BOARD_NUM" ]; then
  echo "→ Delivery board already exists — reusing project #$BOARD_NUM"
else
  echo "→ provisioning Delivery board (one project · EPICS view + Board view)"
  BOARD_LOG="$(mktemp)"
  if [ -n "$GOLDEN" ]; then
    bash "$HERE/setup-board.sh" --owner "$OWNER" --title "$BOARD_TITLE" --copy-from "$GOLDEN" --repo "$REPO" | tee "$BOARD_LOG"
  else
    bash "$HERE/setup-board.sh" --owner "$OWNER" --title "$BOARD_TITLE" --template "$TPL/execution-board.json" --repo "$REPO" | tee "$BOARD_LOG"
  fi
  # the board number, for putting the seeded epics ON the board (setup-board prints "project #N")
  BOARD_NUM="$(sed -n 's/.*project #\([0-9][0-9]*\).*/\1/p' "$BOARD_LOG" | tail -1)"
  rm -f "$BOARD_LOG"
fi

# ── 4. standing epics ─────────────────────────────────────────────────────────
echo "→ seeding standing epics in $REPO"
node -e '
const fs=require("fs");const eps=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).standing_epics;
for(const e of eps) console.log([e.title,(e.labels||[]).join(","),e.body||""].join("\t"));
' "$TPL/labels.json" | while IFS=$'\t' read -r TITLE LBLS BODY; do
  # `gh issue create` has no upsert — search by title first, or every re-run
  # would seed the standing epics again.
  EXISTS="$(gh issue list --repo "$REPO" --state all --search "in:title \"$TITLE\"" --json number --jq '.[0].number' 2>/dev/null || true)"
  if [ -n "$EXISTS" ]; then
    echo "  · $TITLE (exists — #$EXISTS)"
  elif URL="$(gh issue create --repo "$REPO" --title "$TITLE" --body "$BODY" --label "$LBLS" 2>/dev/null)"; then
    echo "  + $TITLE"
    # one project holds the whole hierarchy — the epic must live ON the board, not just in the repo
    [ -n "$BOARD_NUM" ] && gh project item-add "$BOARD_NUM" --owner "$OWNER" --url "$URL" >/dev/null 2>&1 \
      && echo "    ↳ on board #$BOARD_NUM" || true
  else
    echo "  ! $TITLE — creation FAILED (missing labels? run the labels step first)"
  fi
done

echo "✓ instance '$INSTANCE' provisioned."
# machine-readable hand-off — bootstrap.sh reads this line for .env.local
echo "BOARD_NUM=${BOARD_NUM:-}"
echo "  next: on the Delivery project, apply the two views — an EPICS view (Table · filter label:level:epic · Sub-issues progress) + a Board view (kanban · Status × Seat · filter has:status -status:Backlog,Merged,Released,Cancelled) — from the golden template or the UI (the Projects API can't create views); set it as the repo's default; then steer the first epic (workflow/state-machine.md)."
