# Way of Working — Changelog

Every rule add, edit (significant), or deprecation is logged here. Newest at top.

## 2026-06-29 — v1.3: rate-aware board access — the `status:*` label index + per-seat model tier (owner-directed)

The board read was the rate-limit hog: `gh project item-list … --limit 300` (Projects-v2 GraphQL) has **no server-side `Status` filter**, so every `/check` pulled ~N items to use one — and N seats on a shared 5,000-pt/hr GraphQL budget exhausted it in 2–3 epics. Fix: **discover off a cheap `status:*` issue-label index (REST/Search), never the board read.**

- **The `status:*` label index.** One label per `Status` option (`status:backlog|scoped|in-progress|delivered|tested|merged|released|blocked`). The board `Status` field stays the **canonical record + the visual kanban**; the label is its **read-replica / discovery index**. Seats find work with a server-filtered query (`gh issue list --search "label:status:scoped label:seat:dex no:assignee"`) on the **REST budget** — the expensive GraphQL read is off the hot path entirely.
- **`/check`, `/workload`, `/board`, `/backlog` all run off the index** (REST). `/check` drains by **re-running the cheap query** (no snapshot needed — re-querying is cheap, which also retires v1.2's "drain from one snapshot" workaround). New `/backlog` command lists the unframed queue + flags issues missing a `status:*` label.
- **Dual-write, every transition (default, zero new infra).** A flip sets the `status:*` label (REST) **and** the board `Status` field (one cheap single-item mutation — a few points, not the ~30–90 of the full read; the targeted flip Vera proved works under the limit). Keeps the visual kanban live with no extra infrastructure.
- **Optional pure-A upgrade.** A small GitHub Action (`onboarding/board-label-sync.md`) projects `status:*` label changes onto the board field — seats then write **only** the label (zero GraphQL in the loop). Needs a project-scoped `PROJECTS_TOKEN` secret (the default `GITHUB_TOKEN` can't write an org-owned project; GitHub emits events on label changes, not field changes — hence labels-are-writeable, field-is-projection). A pure optimisation, never a prerequisite — dual-write already fixes the rate limit.
- **Per-seat model tier (`SEAT_MODEL`).** `seat-launch.sh` now launches each seat on a capability tier: **pm + quality-engineer → opus** (judgment + the independent gate — where an error is expensive or hard to catch), **scrum-master + producers → sonnet** (mechanical / high-volume, backstopped by the gate). Override per seat via `SEAT_MODEL` in `.env.local` (e.g. `opus` for an agent-path/infra/data/ML engineer; `haiku` for a pure-mechanics SM; empty → account default). Spends capability where it changes outcomes; economises on gated, high-volume work.

One-time per repo: create the labels + **backfill** existing items from their current `Status` field (the one expensive board read, run once when the budget is healthy) — both scripted in `board-label-sync.md`.

### Files updated
- **new** `commands/backlog.md` · `onboarding/board-label-sync.md` · rewritten `commands/{check,workload,board}.md` · `workflow/state-machine.md` (the label-index section + reducer/stop-condition) · `onboarding/seat-launch.sh` (`SEAT_MODEL` tier) + `onboarding/.env.local.example` · seat KICKOFFs + templates + `MODES.md` + spine + `new-pair-setup.md` (discovery-via-label + dual-write propagation).

## 2026-06-29 — v1.2: engineer block-protocol · SM verifies/operationalizes Blocked · PM never edits the board · drain-the-queue (owner-directed)

Refines the operator-driven loop and hardens the PM↔SM boundary. Four changes:

- **Engineer block-protocol.** A genuine consult-exception (AC unmeetable as written · a real product fork · out-of-scope creep) is no longer a pane-local stop: the producer posts the **FULL consult-exception as a comment on the GitHub issue** (file-cited findings · the fork/options · a recommendation), sets `Status → Blocked`, **assigns itself**, and stops — does **not** build. The issue comment *is* the board item's context; the SM + PM read it **from the board, not the producer's pane**.
- **SM verifies a Blocked item before surfacing.** On the `Blocked` sweep the SM does not relay: it **independently verifies the cited claims** against the codebase/board and hands the PM a **verdict** (legit blocker / avoidable / needs-PM-product-call), never a bare relay.
- **PM decides, SM operationalizes the board.** The PM **frames/decides by posting a comment/AC and never edits the board `Status` field**. The SM performs every status transition — including flipping `Blocked → Scoped` after a PM re-frame (the trimmed AC + "approved → Scoped"). Producer ≠ verifier ≠ merger now extends to *decider ≠ board-operator*.
- **Drain-the-queue.** A seat no longer stops after one item per `/check`. On an operator-initiated `/check` it **drains its queue** — handles an item, reports, immediately pulls its role's next eligible item, repeats (item → report → next) until none remain, then reports `queue clear — idle` and stops. **Rails preserved:** the drain is operator-initiated and bounded by the work that exists *now*, every unit still passes the per-unit gate (Engineer → QA → SM) — so it is **not** autonomous EPIC-draining; and **stop-at-empty is absolute** — once the queue is clear the seat does not keep re-reading the board (no self-loop, no board poll, no `/loop`/`ScheduleWakeup`/Stop-hook). Rate-cost is unchanged: **one** board read per `/check` (drain from that single snapshot; only cheap per-item ops between).

Also a **merge-authority consistency sweep** caught + fixed pre-v1.1 remnants the earlier fan-outs missed: the `data-architect`/`data-scientist`/`cloud-architect` seats + their templates + `new-pair-setup.md` still said "the PM reviews + merges" / "4-eye = Producer → PM" / "PM staging ceremony" → now **Engineer → QA → SM** with the **SM** driving `Merged → Released` (the `<INSTANCE>_CEREMONY_OVERRIDE` note updated too).

Why: the block-back-and-forth lost context (it lived in a pane, not the board); the PM was occasionally doing the SM's board mechanics (an owner-flagged overstep); and stopping per-item forced the operator to re-trigger `/check` on an obvious queue (e.g. a QA seat with two more `Delivered` items waiting).

### Files updated
- spine (`agentic-operating-model.md`) · `MODES.md` · `workflow/state-machine.md` · `commands/{check,workload}.md` · `onboarding/seat-launch.sh` (4 boot prompts) · all seat KICKOFFs (engineer/pm/quality-engineer/scrum-master + data-architect/data-scientist/cloud-architect) + `scrum-master/flow-master.md` · all seat templates · `SEAT.template.md` · `SQUAD.md` · `feedback/INDEX.md` + `feedback/workflow/{finish-report-stop,engineer-ready-signal,always-pr-never-push}.md` · `onboarding/new-pair-setup.md`.

## 2026-06-29 — v1.1: merge authority PM → SM; QA-fail → Scoped (owner-directed)

The routine merge moves off the PM. New role model (still operator-driven, single mode):
- **The Scrum-Master is the merge authority.** On a QA PASS (`Delivered→Tested`), the SM validates the merge preconditions (a real QA verdict · CI green · PR mergeable/clean) and squash-merges, then drives `Merged→Released`. The SM did not author the code → produce≠adjudicate holds. On a precondition fail the SM **routes** (dirty PR → engineer rebase; no verdict → QA), never force-merges.
- **The PM is oversight + product vision** — frames Epics + the pre-committed, falsifiable AC (the contract QA verifies against) + the roadmap + owner touchpoints; resolves only the rare product/scope judgment the QA seat surfaces; **out of the routine merge path**.
- **4-eye is now Engineer builds → QA verifies → SM merges** (was Engineer→PM). produce≠adjudicate = producer ≠ verifier ≠ merger.
- **QA-fail back-edge is `Delivered → Scoped`** (was `In Progress`) — the QA seat leaves per-criterion comments; the engineer re-pulls it on its next `/check` and fixes on the existing branch/PR.

Why: the PM-merge + the consult-exception back-and-forth was redundant ceremony — the independent QA verification is the quality oracle, and the SM closes the circle. The PM is freed for product + oversight.

### Files updated
- spine (`agentic-operating-model.md` — invariants 1/3, phases 6/7) · `MODES.md` · `workflow/state-machine.md` · all seat KICKOFFs + templates · `SQUAD.md` · `commands/{check,workload}.md` · `onboarding/seat-launch.sh` (boot prompts) · `README.md` · `feedback/workflow/*` + `feedback/INDEX.md`.

## 2026-06-29 — Operator commands are framework-provided + auto-installed (drop-in across projects)

The operator slash-commands now live **in the framework** at `commands/` (`check.md` · `board.md` · `workload.md`) — instance-agnostic (board id/owner come from the seat's `.env.local` env, no hardcoded project), and `onboarding/seat-launch.sh` **auto-installs** them to `~/.claude/commands/` on launch. So the framework is genuinely **drop-in**: vendor it into any project, launch a seat, and the operator surface is there and **consistent across every project** — `/board` (overview) → `/workload` (this seat's queue) → `/check` (take the next item). Previously these were hand-made machine-global files (not version-controlled, not portable).

### Files updated
- **new** `commands/{check,board,workload}.md` · `onboarding/seat-launch.sh` (the auto-install step).

## 2026-06-29 — Autonomous approach REMOVED → operator-driven (`/check`), owner-directed

The autonomous self-loop (the 2026-06-28 hardening below) was itself the problem: a standing seat that self-drives needs a *wake* an idle interactive pane can't give itself, and any board-reading driver (even one SM) spends GraphQL in bursts — the loop stalled repeatedly with work piled across every state, and re-engaging it was constant manual `/recheck`. **Owner decision: remove the whole autonomous approach, keep the logic.**

**Removed:** `seat-loop-hook.sh` (the Stop-hook self-loop + board-read cache) · `inbox.sh` (the push bus) · `onboarding/github-app/` (the webhook App) · `feedback/architecture/event-driven-orchestration.md` + `onboarding/event-driven-dispatch.md` (the autonomous specs) · `SEAT_AUTONOMOUS` · the `/recheck`·`/dispatch`·`/wake`·`/pause`·`/resume` commands. **Kept:** the 7-state machine, the seat roles, AC / 4-eye / adjudication, board-as-record.

**New model — operator-driven (semi-automated):** the human is the orchestrator. Each seat is an interactive pane, idle until engaged; the operator runs **`/check`** in a seat → it **pulls** its next workload from the board (producer builds next `Scoped`, QA verifies next `Delivered`, PM merges next `Tested`, SM does board hygiene), one item, report, idle. **`/board`** is the overview. No polling, no events, no inbox — GraphQL/tokens spent only per `/check`. See `MODES.md`.

### Files updated
- `MODES.md` (operator-driven, single mode) · `onboarding/seat-launch.sh` (operator-driven boot; strips any legacy Stop-hook on relaunch) · seat templates engineer/quality/scrum-master (→ `/check`) · `onboarding/.env.local.example`. New machine-global command `/check`.

## 2026-06-28 — Autonomous loop hardened: event-driven dispatch, no N-way poll (owner-directed)

A GitHub GraphQL **rate-limit incident** stalled the autonomous loop: N standing seats (dex/sam/qa) each ran the `seat-loop-hook.sh` Stop hook, which does a full Projects-v2 board read on every turn-stop. All seats authenticate as one identity → one shared rate budget → exhaustion + idle seats burning tokens/CI on zero velocity. Root cause was a **contradiction in the framework**: `orchestrator-runner.md` already intended the SM to be the *single* poller, and the spine's `finish-report-stop.md` already forbids self-paced polling — but `MODES.md` + `seats/engineer/autonomous-runner.md` + `seat-loop-hook.sh` sanctioned a standing **self-looping** seat that polls. The poll was also **load-bearing** (the only dispatch path), so a bare disable would zero-out dispatch.

Owner direction: the loop is **event-driven, not polling**. A board transition is a GitHub event that wakes **exactly one standing pane** for one item; the **SM is the single board reader**; every other seat is **woken**, never polling. This **re-aligns autonomous mode to `finish-report-stop`** — the re-engager becomes a webhook event instead of a human. Also reaffirmed (owner, repeated): the SDLC seats are **standing, watchable, interjectable panes — NEVER headless subagents**; the "PM-spawned subagent" form is struck.

The mechanism (dispatcher + per-seat inbox + SM boot/periodic reconcile + `/recheck` + the GitHub App webhook foundation) is specified build-ready and tracked as the platform-infra WP; the policy/rule landed first (PR #277). Hardening is **not done** until the robustness evals (E1–E6) retire the runners' `Bundled eval: TBD`s.

### Added
- `feedback/architecture/event-driven-orchestration.md` — the golden rule (one-reader → push → cheap-probe; App is foundation-not-fix; rejected patterns).
- `onboarding/event-driven-dispatch.md` — the build-ready contract (lifecycle · 7 operational invariants O1–O7 · inbox · dispatcher · reconcile · `/recheck` · evals E1–E6 · #101 worked example · file map).
- `onboarding/github-app/app-manifest.json` + `SETUP.md` — the dispatcher App (events, least-privilege perms, owner setup; secrets out of the repo).

### Updated
- `MODES.md` — autonomous staffing collapses to **one** form (standing, event-woken pane); explicit ⛔ no-subagents.
- `seats/scrum-master/orchestrator-runner.md` — SM is the sole reader, event-woken, low-frequency reconcile backstop (not a tight timer).
- `seats/engineer/autonomous-runner.md` — rewritten to woken-per-item; never reads the board.

## 2026-06-23 — Engineer: `--admin` / branch-protection bypass is never an engineer tool (sharpening)

Reinforces the 2026-06-15 4-eye rule after a slip: an engineer seat (RJ, 2026-06-22) `--admin`-merged two of its own PRs, bypassing PM review + branch protection. The rule already forbade self-merge; this names the exact failure mode — `gh pr merge --admin` is never an engineer tool, doesn't count as "the PM merged it," and never bypasses branch protection without an explicit owner go. Self-flagged by the engineer (healthy signal — the point of capture is to make it stick across seats). Durable fix is **enforcement** (align branch protection so engineer seats can't `--admin`), tracked separately — a doc rule alone didn't prevent it.

### Files updated
- `seats/engineer/authority.md` — the "Self-merge to `main`" anti-pattern now explicitly includes `--admin` / branch-protection bypass.

## 2026-06-15 — Merge authority refined: 4-eye = Engineer→PM (owner-directed)

Merge authority refined — the 4-eye principle IS the Engineer→PM separation: the engineer builds, the PM independently reviews + merges (two pairs of eyes); the owner is NOT a third merge gate. The PM reviews + merges the engineer's routine DEV→main work **without an owner trigger**, and may build *and* merge the PM's own lower-stakes work (CI / docs / config). The engineer **never self-merges** to `main` — it builds + hands the PR to the PM. The owner gates only prod/staging releases, repo-settings / branch-protection mutations, and destructive/irreversible infra. **Supersedes** the prior owner-trigger / "no autonomous merge" framing ("no merge without an explicit human 'do X' trigger; the owner is the merge trigger").

Unchanged (explicitly preserved): the no-loops / no-polling / no-`/loop` / no-`ScheduleWakeup` / no-self-invoke-for-coordination discipline (only the merge-authority part moved); "always open a PR — never push directly to `main`" (the engineer still never pushes to main; only *who merges the PR* changed); repo-settings / branch-protection stay owner-gated.

Self-guardrail: PM-own-work has no second pair of eyes → keep PM-own-merges to lower-stakes config/docs and loop the owner on anything risky. Branch-protection enforcement will be aligned separately so routine PM merges don't need `--admin`.

### Files updated
- `feedback/workflow/finish-report-stop.md` — surgically changed only the merge sentences in Rule / Why / "Explicitly forbidden"; added a merge-authority section; `last-confirmed: 2026-06-15` + supersedes note. All no-loops/no-polling content kept intact.
- `CLAUDE.md` — finish-report-stop section, the user-pings line, the autonomy zones (PM = merge authority; engineer never self-merges), and the CI-must-pass-before-merge line.
- `agentic-operating-model.md` (spine) — Principle 7 row, invariant 1 (human touchpoints), Owner + PM-orchestrator role entries: routine-merge touchpoint = PM, owner for the gated class.
- `seats/pm/authority.md` — PM is the merge authority (reviews + merges engineer work without owner trigger; may build + merge own lower-stakes work).
- `seats/engineer/authority.md` — engineer never self-merges; builds + hands to PM for review + merge.
- `seats/pm/KICKOFF.md` + `seats/engineer/KICKOFF.md` — merge-step lines.
- `feedback/INDEX.md` — finish-report-stop one-liner.

## 2026-06-12 — SDLC hardening: prose rules promoted to Claude Code-native enforcement (#2208)

Pre-blog review found the operating model strong but the enforcement almost entirely prose — ~26 rules and 22 gate scripts, zero Claude Code-native machinery. This pass closes the convention-vs-gate gap the product side already closed with FLOOR-4.

### Promoted from prose to hard gate (`.claude/hooks/` + `.claude/settings.json`)

- `always-pr-never-push` — PreToolUse hook blocks `git push` to `main`/`release/*` (ceremony override: `<INSTANCE>_CEREMONY_OVERRIDE=1`, PM staging-promote only)
- `no-claude-attribution` — hook blocks commits carrying Claude attribution footers
- `always-rebase-before-push` — hook blocks pushes while behind `origin/main` (the BEHIND class that hit every INTAKEV2 first-shot PR); `hotfix/*` skipped, EPIC-branch sub-PRs use `<INSTANCE>_CEREMONY_OVERRIDE=1`
- `run-oversight-gates-locally` — hook blocks agent-path pushes unless `npm run gates:agents` (NEW single-command runner, `scripts/run-agent-gates.sh`, all 11 blocking + 2 report-only gates) passed against the exact committed diff (patch-id stamp). Supersedes the copy-paste gate loop; rule file updated from the stale 2-gate version.
- `db:generate after schema.prisma edit` — PostToolUse hook regenerates the Prisma client automatically
- SessionStart hook injects the seat-kickoff briefing + standing-state surfaces into every session

### Implemented (was documented-but-not-wired since 2026-05-13)

- `chore(playbook):` auto-merge — `.github/workflows/playbook-auto-merge.yml` verifies title prefix + docs-only diff, enables squash auto-merge. `how-to-capture-a-rule.md` updated to state the prior section described unimplemented behaviour (a no-false-green instance in our own docs).

### Added

- `plugins/<instance>-sdlc/` plugin + root `.claude-plugin/marketplace.json` — kickoff-pm, kickoff-engineer, ready-signal, promote-staging, capture-rule as installable skills. The WoW procedures become infrastructure new pairs install, not docs they remember to read. Docs remain the source of truth; skills point at them.
- `REVIEW.md` (repo root) — severity overrides for Claude Code Review: ADR-0006 Tier-1 / AgentCore-first / edge-runtime / `## Retires` follow-through escalate to Important; style stays Nit; playbook PRs skipped. Enabling the GitHub review service itself is an owner decision (billed, org-admin).

### Debt cleared (named in the 2026-05-19 reconciliation)

- Stale `scope:` frontmatter re-labelled on 6 workflow rules (`top-pm`/`sub-pm` → `pm`) + the template in `how-to-capture-a-rule.md`.

### Legacy archived + legacy names retired (same day, owner-directed)

- The 8 superseded stub files (6 retired seat files under `seats/top-pm/` + `seats/sub-pm/`, plus `feedback/workflow/engineer-no-unilateral-decisions.md` and `feedback/seat-specific/engineer-seat-senior-architect.md`) moved via `git mv` to [`docs/archive/agentic-sdlc/`](../../archive/agentic-sdlc/README.md), waiving the last 6 days of the 30-day grace (owner call, pre-blog corpus cleanup). All live inbound references repointed (engineer KICKOFF's stale senior-architect pointer now goes to the Principal skills).
- **Renamed:** `feedback/workflow/standing-by-means-polling.md` → `finish-report-stop.md` — the rule was inverted 2026-05-19 but kept its old name "so cross-refs resolve"; all 8 live cross-refs (incl. CLAUDE.md) now point at the new name, which finally matches the rule.
- **Renamed:** `escalation/needs-top-pm-label.md` → `escalation/owner-touchpoints.md` — named after the retired `needs:top-pm` queue; content was already current.
- Historical CHANGELOG entries below this one intentionally keep the old filenames — they are records of what happened, not live links.

### Still open (unchanged)

- Per-skill ADR-0001 bundled evals (`status: TBD` on the 5 Principal skills); deep ADR-0006/vision prose integration.

## 2026-05-20 — Sharpened: rebase immediately before flipping DRAFT → ready-for-review (+ commit-then-rebase order)

**Rule sharpened, not new.** The existing `feedback/workflow/always-rebase-before-push.md` covers rebase-before-every-push, but the INTAKEV2 EPIC kickoff (2026-05-20) surfaced two specific failure modes:

1. **The flip-to-ready gap** — every first-shot PR hit `BEHIND` at flip-to-ready because the engineer's session was in finish-report-stop between push and flip. Main moved during that gap.
2. **The git-add-then-rebase misorder** — engineer ran `git add` (staged but not committed) then `git rebase`, hit the "index contains uncommitted changes" error, didn't re-run after committing, and pushed. Got lucky (nothing landed on main between the failed rebase and the push) — next time the luck won't hold.

### What changed

- `feedback/workflow/always-rebase-before-push.md` — added a "SPECIFICALLY: rebase immediately before flipping DRAFT → ready-for-review" section + "Order matters — commit BEFORE rebase, not git-add BEFORE rebase" sub-section; bumped `last-confirmed`.
- `seats/engineer/ready-signals.md` — added "ALWAYS rebase immediately before flipping a PR to ready-for-review" as a hard step in the ready-signal ceremony, with the concrete cost of skipping (5–15 min round-trip per PR) and the exact pattern.

### Why the existing rule wasn't enough

`always-rebase-before-push.md` told engineers to rebase before every `git push`. But the *flip-to-ready* is logically a new contract with the PM ("this PR is the version I want you to merge"), not a push — and engineers (correctly following finish-report-stop) were stopping between their last push and the flip. By the time the human pasted the flip-to-ready trigger, main had moved. The rebase needed to happen as part of the flip-to-ready ceremony itself, not as a separate earlier step.

### Cost-of-pattern (INTAKEV2 EPIC kickoff data)

5 PRs landed on 2026-05-20. **Every single one** hit BEHIND on first PM merge attempt, requiring a rebase-ask round-trip:
- PR #1158 (WS-0 PR-1) → rebased once
- PR #1157 (WS-I PR-1) → rebased once
- PR #1159 (WS-I PR-2) → rebased once
- PR #1160 (PM fixture-seed) → rebased once (PM-authored, PM did the rebase)
- PR #1164 (WS-I PR-3) → rebased twice
- PR #1166 (WS-D PR-1) → rebased once

Estimated wasted cycle time: ~30–60 min across the kickoff day. The sharpened rule eliminates the pattern.

## 2026-05-19 - Reconciled agentic-sdlc → Agentic SDLC (deliberate pass)

The deliberate reconciliation pass named in the spine's `## Scope honesty`.
The spine ([`agentic-operating-model.md`](../agentic-operating-model.md)) and
[`seats/engineer/authority.md`](../seats/engineer/authority.md) were the
ratified root + reference shape; everything below derives from them, nothing
contradicts them. Staged on-branch only - **no commit, no push, no merge**.

### Rebrand (name only - directory path stable)
- `README.md` retitled to **"Agentic SDLC"** ("the operating model
  formerly called 'way of working'"), reframed as the index; spine named as
  the root. Seat overview rewritten to the 3-role spine model (Owner /
  PM-orchestrator / Engineer-Principal). Folder tree, the session-start
  checklist, and the "bounded autonomy / fixed owner-touchpoints" principle
  updated. The directory path `agentic-sdlc/` is unchanged.
- `CLAUDE.md`: textual references call it the "Agentic SDLC"; seat
  pointers now point at `seats/pm/KICKOFF.md` + the spine; all
  `agentic-sdlc/...` paths kept intact. Surgical - the workflow-split
  prose (Terminal/VS Code lanes) was left intact (not a name/seat-pointer
  contradiction; out of scope for a surgical name-only edit).

### PM seats collapsed to one `seats/pm/` (owner-decided)
- **Created** `seats/pm/KICKOFF.md` + `seats/pm/authority.md` - spine-rooted,
  de-gated, matching the `seats/engineer/authority.md` shape. PM = the
  orchestrator: sets the EPIC steer, handles the 3 consult-exceptions, does
  the ONE merge-time validation (produce != adjudicate), owns the
  staging-promote ceremony, keeps the SDLC coherent. Owner owns master-EPIC
  definition, product/strategic, PROD. The still-valid reserved-vs-autonomous
  matrix content from both old top-PM and sub-PM authority files was folded
  in and reconciled to the bounded-autonomy model; the old per-unit /
  mid-flight gating and the `needs:top-pm` queue were NOT carried over.
- **Superseded → stubs** (2-4 lines, link-stable, delete later):
  `seats/top-pm/KICKOFF.md`, `seats/top-pm/authority.md`,
  `seats/top-pm/escalation-handling.md`, `seats/sub-pm/KICKOFF.md`,
  `seats/sub-pm/authority.md`, `seats/sub-pm/escalation.md` - all point at
  `seats/pm/` + the spine.
- **Pointers updated** to `seats/pm/` (+ spine): `CLAUDE.md`, `README.md`,
  `onboarding/new-pair-setup.md`. The top-PM/sub-PM distinction is retired
  into one PM seat.

### 11 stale files reconciled to the spine + de-gated model
- **Superseded → stub:** `feedback/workflow/engineer-no-unilateral-decisions.md`
  → spine "steer-as-trigger" (the steer IS the trigger; the engineer does not
  wait per-unit between WPs on a steered EPIC).
- **Superseded → stub:** `feedback/seat-specific/engineer-seat-senior-architect.md`
  → the Principal skills (`skills/`) + the spine's Engineer-Principal role.
- **Rewritten:** `feedback/workflow/engineer-ready-signal.md` - per-unit
  "wait for the next do-X trigger" retired; after a unit, one report then
  continue the steered EPIC; no per-unit gating; no autonomous merge; the 3
  consult-exceptions are the only stops.
- **Rewritten:** `seats/engineer/ready-signals.md` - same de-gating; report
  is a handoff marker not a go-signal request; one PM merge validation, not
  per-WP; finish/report/stop preserved.
- **Rewritten:** `feedback/workflow/pm-routes-via-github.md` → spine
  invariant 7 ("the shared GitHub thread is the bus; the human is never the
  relay"); one PM seat.
- **Rewritten:** `escalation/needs-top-pm-label.md` → PM/Owner model: no
  top-PM seat, no `needs:top-pm` queue; PM handles the 3 consult-exceptions
  on-thread; owner only for the owner-touchpoints.
- **Rewritten:** `onboarding/new-pair-setup.md` → onboards a pair into the
  SDLC spine model (Owner/PM/Engineer-Principal, bounded autonomy, the
  Principal skills, steer-as-trigger), not the old per-unit-trigger model.
- **Rewritten:** `feedback/INDEX.md` → spine named as the root; kept
  integrity rules listed; reconciled rules + superseded stubs marked as such.
- **Light-confirm only (stated honestly, NOT rewritten):**
  `feedback/workflow/standing-by-means-polling.md` - already inverted +
  coherent with the spine (2026-05-19 earlier entry); added a one-line spine
  pointer only. Content unchanged below that line.
- **Contradiction-only fix (NOT a full rewrite):**
  `escalation/cross-team-coordination.md` - this file was not in the named
  11 but directly contradicted the spine (top-PM broker, `needs:top-pm` on
  both EPICs, sub-PM-to-sub-PM). Only the contradicting lines were fixed +
  a spine note added; the concurrency-hazard content (e.g. the
  same-file-two-sessions detection) was left intact.

### ~26 neutral integrity/architecture/operational rules - confirmed-and-kept (NOT rewritten)
- A single one-line spine note (`> Stands under the Agentic SDLC
  spine ...`) was added to: the 13 kept `feedback/workflow/*` integrity rules
  (always-pr-never-push, no-claude-attribution, branch-per-epic,
  deployed-env-smoke-before-ready, audit-pr-history-before-pickup,
  always-rebase-before-push, forward-port-release-hotfixes-same-day,
  dont-block-on-irrelevant-ci, flip-epic-status-when-starting,
  repo-settings-via-pr, milestone-shifts-user-facing,
  run-oversight-gates-locally, verify-wrap-up-scope), the 4
  `feedback/architecture/*` rules (agentcore-first,
  auth-ts-edge-runtime-constraint, nextjs-slug-runtime-check,
  no-silent-degradation-on-load-bearing-paths), the 3
  `feedback/operational/*` rules (dev-credentials, dev-ecs-scale-to-zero,
  circuit-breaker-as-safety-net), and `learning-loop/how-to-capture-a-rule.md`.
  **Body content of these was NOT rewritten** - only the one-line note added.
- **Honest note:** several of these still carry stale `scope:` frontmatter
  (`scope: top-pm / sub-pm`, `scope: sub-pm`). This is metadata, not a
  behavioural contradiction with the spine; per the pass's "do not rewrite
  the kept rules" constraint the `scope:` fields were left as-is. A
  follow-up metadata sweep (re-label `scope:` to `pm` / `engineer` /
  `all-seats`) is named here as deliberate debt, not done in this pass.
- `feedback/architecture/*`, `feedback/operational/*`,
  `learning-loop/how-to-capture-a-rule.md`, `escalation/cross-team-coordination.md`
  (post-fix), and the kept workflow rules were read and confirmed coherent
  with the spine other than the noted `scope:` metadata. "Confirmed-and-kept"
  here means: read, no behavioural contradiction found, one-line note added -
  NOT independently re-derived or rewritten.

### Merge is HELD (owner sequencing)
This reconciliation is staged on-branch only. Merge to `main` is **held by
owner sequencing** until both in-flight master EPICs complete and `main` is
clean: **#1096** (Agent-Augmented Pursuit Intake) and **#1107** (L1/Global KB
Ingestion). No commit, no push, no merge, no `main` mutation was performed in
this pass; code was untouched (edits confined to `agentic-sdlc/` +
textual seat/name pointers in `CLAUDE.md`).

### Not fully reconciled (honest scope statement)
- `standing-by-means-polling.md`: light-confirmed only (pointer added), as
  stated above - not rewritten.
- `escalation/cross-team-coordination.md`: contradiction-fixed only, not a
  full ground-up rewrite.
- Stale `scope:` frontmatter on the kept rules: deliberately not rewritten.
- The deep ADR-0006 / product-vision prose integration and the per-skill
  ADR-0001 bundled-eval builds remain tracked follow-ups (per the spine's
  `## Scope honesty`); this pass did not touch them.

## 2026-05-19

### Added (agentic operating model: the spine)
- `agentic-sdlc/agentic-operating-model.md`: the single authoritative spine. the instance is an agentic platform built by an agentic SDLC, both on one root (Anthropic "Building Effective Agents"). Carries the 7-principle dual mapping (product vs SDLC), the 8-phase Agentic SDLC, the 8 invariants, the 3-role touchpoint model, and the agent-scaling rules. Seat authority / Principal skills / kickoffs are now downstream of it.
- **De-gated `seats/engineer/authority.md`**: removed the heavy per-unit "do X" trigger protocol; installed the bounded-autonomy contract: EPIC-scoped full autonomy as Senior Cloud Architect / Agentic Engineer, only 3 consult-PM triggers (out-of-scope / better solution / external blocker), ONE PM validation at merge (produce != adjudicate, the only retained routine check), PM owns staging ceremony, owner only for PROD + product/strategic + master-EPIC. Integrity rules preserved verbatim (produce != adjudicate, no-false-green, no-silent-degradation, AgentCore-first, isolation, branch-per-EPIC).
- **Pointers (surgical, no rewrites):** `principal-agentic-engineer.md` gained a `## Building Effective Agents canon` section; `agentic-sdlc/README.md`, `seats/engineer/KICKOFF.md` (read-order), `skills/INDEX.md`, `CLAUDE.md` (standards area), and `docs/product-vision.md` each point at the spine.
- **Tracked deliberate follow-up (NOT done here, stated plainly in the spine's `## Scope honesty`):** full reconciliation of the ~30 agentic-sdlc files against the spine, deep ADR-0006/vision prose integration, and the per-skill ADR-0001 bundled-eval builds. "Spine exists" is not "agentic-sdlc reconciled".

### Added (Principal-grade engineer skills)
- `agentic-sdlc/skills/INDEX.md` + 5 Principal skill files (`principal-aws-cloud-architect`, `principal-agentic-engineer`, `principal-genai-agentic-ai`, `principal-data-science`, `principal-data-analytics`) — the Principal-grade operating standards the engineer seat embodies within Master-EPIC delivery. Each ties explicitly to the binding standards (AgentCore-first; ADR-0006 Tier-1: isolation, no-silent-degradation, no-false-green/produce≠adjudicate, convergence) and carries a falsifiable `## Decision checklist`. Wired into the engineer KICKOFF read-order. **Bundled evals are NOT shipped** — each skill names the eval it should carry, marked `status: TBD (follow-up)`; the eval build is a tracked ADR-0001 follow-up, stated honestly so "skill exists" is not mistaken for "eval-backed" (the #985 false-green class these standards exist to prevent).

### Removed (owner-directed — kill all autonomous loops/automation)
- **Deleted `feedback/operational/seat-coordination-loop.md`** — the self-paced GitHub poll-loop + autonomous-merge + ceremony-only-escalation pattern. Owner-directed removal after it shipped unattended actions (release promotes merged while triage was still in progress; the owner only saw them after the fact). No `/loop`, no `ScheduleWakeup`/cron self-re-invocation, no autonomous merge.
- **Inverted `feedback/workflow/standing-by-means-polling.md`** — filename kept so cross-refs resolve, but the rule is now the opposite: finish a unit of work → one GitHub check → report to the human → **STOP and wait** for an explicit live "do X" trigger. No cadence, no loop, no auto-merge.
- **`CLAUDE.md`** — replaced the "'Standing by' means polling, not idling" section (which instructed seats to "squash-merge ... without waiting for a chat ping") with "Finish, report, then stop — no loops, no autonomous merge."
- **`feedback/INDEX.md`** — seat-coordination-loop row removed; standing-by row text updated.
- Verified at removal time: zero hooks in any `settings.json`, zero crons (`CronList`), zero scheduled tasks — nothing was live-firing; this was documented pattern only.

### Added / promoted (convention → enforced gate)
- `feedback/workflow/forward-port-release-hotfixes-same-day.md` — migrated from personal memory into the shared store and **promoted from convention to an enforced gate** by WP3 / FLOOR-4 (#1069). The discipline broke 4× in one session; it is now CI-enforced by `infra/scripts/check-forward-port-convergence.ts` (real `git patch-id` same-day-equivalence on every `release/v*` push) + `test-forward-port-convergence.ts` (both-directions self-test so the gate can't silently regress to a no-op).
- `feedback/workflow/always-rebase-before-push.md` — added a "Related enforcement (FLOOR-4)" section: rebase is what keeps the now-enforced forward-port convergence from landing on a stale base.

## 2026-05-18

### Added
- `feedback/architecture/no-silent-degradation-on-load-bearing-paths.md` — load-bearing swallow = defect; surface + health signal; schema-validate structured output pre-persist. Codified by WP2 (FLOOR-2 #1067 + FLOOR-3 #1068, EPIC #1065); reference impl = the converged intake write-back (`_api_call(required=True)` → `WriteError` + write-health, `validate_finalize_payload` pre-POST gate).
- `feedback/operational/seat-coordination-loop.md` — GitHub-as-bus + per-seat self-paced poll loop + ceremony-only owner escalation. Operationalises the previously-principle-only `standing-by-means-polling` + `pm-routes-via-github` rules so routine WP handoffs flow seat-to-seat without the owner hand-carrying messages between terminals. Owner is a subscriber to one topic: ceremony gates.
- `feedback/operational/seat-coordination-loop.md` **amended (same day, first live run)**: 3 demonstrated hard-won rules — (a) a seat must not conclude its loop while a dispatch to it is unacknowledged; dispatcher confirms pickup; (b) shared `sebas2810` identity ⇒ watermark-dedupe + own-post/ack no-ops + don't poll human-gated waits; (c) AskUserQuestion answers are invisible to the auto-mode classifier — ceremony-grade actions need in-transcript auth or human execution.

## 2026-05-13

### Scaffolded
- `agentic-sdlc/` folder created as the single source of truth for team agentic-sdlc
- Per-seat KICKOFFs (`seats/top-pm/`, `seats/sub-pm/`, `seats/engineer/`) — every session starts here
- Authority matrices per seat
- Learning loop protocol — this file + `how-to-capture-a-rule.md`
- Onboarding flow (`onboarding/new-pair-setup.md`)

### Added (initial migration from `~/.claude/projects/.../memory/`)
- `feedback/workflow/always-pr-never-push.md` — all changes via PR
- `feedback/workflow/no-claude-attribution.md` — drop Co-Authored-By: Claude
- `feedback/workflow/branch-per-epic.md` — one branch per EPIC
- `feedback/workflow/engineer-no-unilateral-decisions.md` — engineer waits for explicit "do X" trigger
- `feedback/workflow/engineer-ready-signal.md` — engineer posts ready signals between units
- `feedback/workflow/pm-routes-via-github.md` — PMs route via GitHub, not chat-paste
- `feedback/workflow/deployed-env-smoke-before-ready.md` — smoke evidence required for ready signal
- `feedback/workflow/standing-by-means-polling.md` — "standing by" = actively polling GitHub
- `feedback/workflow/always-rebase-before-push.md` — rebase before every push
- `feedback/workflow/dont-block-on-irrelevant-ci.md` — fire parallel work when CI is orthogonal
- `feedback/workflow/audit-pr-history-before-pickup.md` — check PR history before "ready to start"
- `feedback/workflow/flip-epic-status-when-starting.md` — Project #4 status flip BEFORE first PR
- `feedback/workflow/repo-settings-via-pr.md` — repo settings need explicit approval
- `feedback/workflow/milestone-shifts-user-facing.md` — milestone shifts always user-facing
- `feedback/workflow/run-oversight-gates-locally.md` — local oversight gates before push; no bypass
- `feedback/workflow/verify-wrap-up-scope.md` — verify wrap-up steps concretely
- `feedback/architecture/agentcore-first.md` — AgentCore-first design pattern
- `feedback/architecture/auth-ts-edge-runtime-constraint.md` — auth.ts top-level imports edge-compat
- `feedback/architecture/nextjs-slug-runtime-check.md` — Next.js slug conflict at server-start (NEW today)
- `feedback/operational/dev-credentials.md` — dev creds = isolated blast radius
- `feedback/operational/dev-ecs-scale-to-zero.md` — DEV frontend ECS desiredCount=0 pattern
- `feedback/operational/circuit-breaker-as-safety-net.md` — ECS deployment circuit breaker auto-rollback (NEW today)
- `feedback/seat-specific/engineer-seat-senior-architect.md` — engineer-seat senior-architect framing

### Migrated to indices
- `feedback/INDEX.md` — navigable directory of all rules
- `reference/INDEX.md` — placeholder; reference pages will migrate over the week

## Backfill queue (not in scaffold; landing over the week)

- `reference/capgemini-landing-zone-sso.md`
- `reference/repo-map.md`
- `reference/virtual-team.md`
- `reference/release-strategy.md`
- `reference/gh-cli.md`

These can move to the new home as their existing content gets touched (any session editing the corresponding `~/.claude/projects/.../memory/` file should move it instead — adds the rule to the shared store).
