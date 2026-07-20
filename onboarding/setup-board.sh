#!/usr/bin/env bash
#
# setup-board.sh — provision one GitHub Project (v2) from a board template.
#
# Creates a project, sets its Status single-select to the template's states, and
# adds the template's custom fields. Non-destructive: it creates a NEW project, so
# the full Status replace runs on an empty board (no items to unset). The default
# Board + Table views ship automatically; Roadmap + Insights views are added once
# from a golden template via `copyProjectV2` or in the UI (Projects API can't
# create views) — see workflow/project-boards.md.
#
# Usage:
#   onboarding/setup-board.sh --owner <login|org> --title "<full title>" \
#       --template workflow/project-templates/execution-board.json --repo <owner/repo>
#
# --repo is optional; when given, the new project is linked to that repository so it
# shows in the repo's Projects tab (issues/PRs can then be added to it from the repo).
#
# Requires: gh (with `project` scope) + node.
set -euo pipefail

OWNER="" ; TITLE="" ; TEMPLATE="" ; REPO="" ; COPY_FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --owner)     OWNER="$2"; shift 2 ;;
    --title)     TITLE="$2"; shift 2 ;;
    --template)  TEMPLATE="$2"; shift 2 ;;
    --repo)      REPO="$2"; shift 2 ;;
    --copy-from) COPY_FROM="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -n "$OWNER" ] && [ -n "$TITLE" ] || {
  echo "usage: setup-board.sh --owner <login> --title <title> (--template <path.json> | --copy-from <project-number>) [--repo <owner/repo>]" >&2; exit 1; }

if [ -n "$COPY_FROM" ]; then
  # ── golden-template path: copyProjectV2 — VIEWS + fields travel with the copy
  #    (the one thing the raw API cannot create), so a configured board begets
  #    configured boards and no UI step remains.
  echo "→ copying project #$COPY_FROM → '$TITLE'  (owner: $OWNER)"
  OWNER_ID=$(gh api graphql -f query='query($l:String!){repositoryOwner(login:$l){id}}' -f l="$OWNER" --jq .data.repositoryOwner.id)
  SRC_ID=$(gh project view "$COPY_FROM" --owner "$OWNER" --format json \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).id))')
  COPY=$(gh api graphql \
    -f query='mutation($p:ID!,$o:ID!,$t:String!){copyProjectV2(input:{projectId:$p,ownerId:$o,title:$t,includeDraftIssues:false}){projectV2{number url}}}' \
    -f p="$SRC_ID" -f o="$OWNER_ID" -f t="$TITLE" --jq .data.copyProjectV2.projectV2)
  NUM=$(printf '%s' "$COPY" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).number))')
  URL=$(printf '%s' "$COPY" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).url))')
  echo "  created project #$NUM — $URL  (views + fields copied from #$COPY_FROM)"
  if [ -n "$REPO" ]; then
    gh project link "$NUM" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 \
      && echo "  linked to $REPO" \
      || echo "  ! link to $REPO failed (check the repo + project scope)"
  fi
  echo "✓ done: project #$NUM"
  exit 0
fi

[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 1; }

echo "→ creating project: $TITLE  (owner: $OWNER)"
CREATE=$(gh project create --owner "$OWNER" --title "$TITLE" --format json)
NUM=$(printf '%s' "$CREATE" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).number))')
URL=$(printf '%s' "$CREATE" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).url))')
echo "  created project #$NUM — $URL"

# Configure Status options + custom fields from the template (logic in node; it shells back to gh).
NUM="$NUM" OWNER="$OWNER" TEMPLATE="$TEMPLATE" node <<'NODE'
const { execSync } = require("child_process");
const fs = require("fs");
const tpl = JSON.parse(fs.readFileSync(process.env.TEMPLATE, "utf8"));
const NUM = process.env.NUM, OWNER = process.env.OWNER;
const sh = (c) => execSync(c, { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });

// 1. Status options — find the field id, full-replace (empty board, safe).
const fields = JSON.parse(sh(`gh project field-list ${NUM} --owner ${OWNER} --format json`)).fields;
const status = fields.find((f) => f.name === (tpl.statusField?.name || "Status"));
if (tpl.statusField && status) {
  const lit = tpl.statusField.options
    .map((o) => `{name:"${o.name}",color:${o.color || "GRAY"},description:${JSON.stringify(o.description || "")}}`)
    .join(",");
  sh(`gh api graphql -f query='mutation{updateProjectV2Field(input:{fieldId:"${status.id}",singleSelectOptions:[${lit}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}'`);
  console.log(`  Status → ${tpl.statusField.options.map((o) => o.name).join(" · ")}`);
}

// 2. Custom fields.
for (const f of tpl.fields || []) {
  let cmd = `gh project field-create ${NUM} --owner ${OWNER} --name ${JSON.stringify(f.name)} --data-type ${f.dataType}`;
  if (f.dataType === "SINGLE_SELECT") cmd += ` --single-select-options ${JSON.stringify((f.options || []).join(","))}`;
  try { sh(cmd); console.log(`  + field: ${f.name} [${f.dataType}]`); }
  catch (e) { console.log(`  ! field ${f.name} skipped (${String(e.message).split("\n")[0]})`); }
}
console.log(`  board #${NUM} configured.`);
NODE

# Link to the repo so it appears in the repo's Projects tab.
if [ -n "$REPO" ]; then
  gh project link "$NUM" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 \
    && echo "  linked to $REPO" \
    || echo "  ! link to $REPO failed (check the repo + project scope)"
fi

echo "✓ done: project #$NUM"
