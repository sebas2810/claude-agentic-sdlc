---
title: GitHub App — sammy-sdlc-dispatcher — owner setup
status: owner-gated (repo/org settings + secrets)
---

# `sammy-sdlc-dispatcher` — owner setup

The event-driven loop ([`../event-driven-dispatch.md`](../event-driven-dispatch.md)) needs a
GitHub **App** as its push foundation: it receives board/PR webhooks and authenticates the
dispatcher + per-seat tokens. **The PM frames this; the owner creates/installs it** — it touches
org settings + secrets (owner-gated, standing rule: *no secrets in code*).

> ⚠️ The App is the **foundation, not the fix.** A token swap alone just moves the rate-limit
> wall (one installation = one shared bucket). The win is **webhook eligibility + per-seat scoped
> tokens**. Polling is killed by the dispatch design, not by the App.

## Why an App (vs the current shared user token)
- **Webhooks** — only Apps (or org webhooks) push `projects_v2_item` events; PATs can't.
- **Separate budget** — App traffic stops cannibalising the human's interactive `gh` budget.
- **Per-seat least privilege** — scoped installation tokens, not one all-powerful PAT.

## Steps (owner)
1. **Create the App** via the manifest flow: `POST` [`app-manifest.json`](app-manifest.json) to
   `https://github.com/organizations/Nestor-Software/settings/apps/new?state=<csrf>` (manifest
   flow), or create manually with the same name / events / permissions. Set the **Webhook URL**
   to the deployed dispatcher endpoint (replace `REPLACE_WITH_DISPATCHER_WEBHOOK_URL`).
2. **Permissions** (least privilege): `metadata:read` · `issues:write` · `pull_requests:write` ·
   `contents:read` · `organization_projects:admin` (Projects v2 board moves). No `administration`,
   no branch-protection scope — those stay owner-hands-only.
3. **Events:** `projects_v2_item`, `pull_request`, `issues`.
4. **Install on the org** `Nestor-Software` (project_v2 events are org-level), scoped to
   `nestor-sammy`.
5. **Secrets** — store **outside the repo**: the App **private key** + the **webhook secret** in
   the dispatcher's secret store (AWS Secrets Manager / SSM per the standing rule), and each seat's
   installation token in its `.env.local` (git-ignored), **never committed**.
6. **Verify webhook secret** on every delivery (HMAC) before the dispatcher acts — reject unsigned.

## What stays owner-gated even with the App
The App can move the board + open/merge via the PM seat, but **never** the irreversible class:
PROD release, branch-protection, destructive infra, `--admin`. Those are not in the App's grant.

## Local-pane note
Laptop seat panes can't receive webhooks directly. Until the dispatcher is reachable
(tunnel: smee.io / cloudflared, or the cloud path), the **SM standing pane** is the interim
dispatcher: single board read on the reconcile cadence → writes seat inboxes. Same contract,
no webhook yet. (See [`../event-driven-dispatch.md`](../event-driven-dispatch.md) §5.)
