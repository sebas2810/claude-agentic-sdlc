---
description: Pull the latest canonical framework into this instance's vendored agentic-sdlc/ — drift report first, owner-gated apply, parity check, then a chore(playbook) PR. Operator-initiated.
---

You **sync this instance's vendored `agentic-sdlc/` copy to the canonical framework** (`claude-agentic-sdlc@main`), using the shipped script — never by hand-copying files. The whole flow is **owner-gated by design**: the files it rewrites (operating model, seat KICKOFFs, feedback rules, the command set) are what every active seat's behaviour derives from.

**1. Report first — always, no exceptions:**
```
agentic-sdlc/onboarding/sync-sdlc.sh            # report-only; writes nothing
```
Show the owner the three lists as-is: **ADDED** (new upstream), **CHANGED** (upstream moved), **LOCAL-ONLY** (instance overlay + diverged files — never auto-touched). Then read the top entries of the canonical `learning-loop/CHANGELOG.md` in the report's tmp clone (or after apply, locally) and tell the owner **what changed behaviourally**, not just which files moved. Flag any LOCAL-ONLY file whose *topic* collides with an ADDED/CHANGED one — a local rule and a new canonical rule about the same thing must be reconciled by the PM, not left to fight.

**2. Apply only on the owner's explicit go — in this session:**
The script requires the operator to type `apply` (no `--yes` flag exists, by design). The owner saying "apply" / "go" in this session IS that confirmation — pipe it through:
```
echo apply | agentic-sdlc/onboarding/sync-sdlc.sh --apply
```
**Never self-confirm.** No owner go → stop after the report; that is a complete, successful `/update` run. Mid-wave applies are the "silent process rewrite" risk — if seats are actively draining, say so and let the owner pick the moment.

**3. Post-apply checks (both cheap):**
```
bash agentic-sdlc/onboarding/doctor.sh sdlc.config   # parity gate: labels vs the roster
```
plus confirm `agentic-sdlc/.sdlc-version` now records the canonical SHA the report named.

**4. Land it like any other change — a `chore(playbook):` PR:**
Branch off `origin/main`, commit **only** the `agentic-sdlc/` paths the sync wrote (plus `.sdlc-version`) — never sweep unrelated working-tree files — and open:
```
chore(playbook): sync agentic-sdlc to canonical@<short-sha>
```
That title prefix rides the auto-merge lane where the instance has wired it ([`../learning-loop/how-to-capture-a-rule.md`](../learning-loop/how-to-capture-a-rule.md)); otherwise the SM merges it as usual.

**5. Report + stop.** One report: canonical SHA, files written, the behavioural changelog summary, doctor verdict, PR link. Note that **running seats keep their old text until their next session start** — a mid-session seat has already read its KICKOFF. Then idle; no re-sync loop, no polling for new canonical commits — the operator runs `/update` when they want the next pull.
