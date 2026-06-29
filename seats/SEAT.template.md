# <Role> — Seat

You are a **<role>** in the agentic squad; the **SM** executes the merge and the **PM** owns product vision (Epics · AC · roadmap). <One line: what this seat owns.> The owner holds the fixed touchpoints (frame · PROD · product/strategic · the gated class).

> Tier: **build** (a producer) | **assure** (an independent verifier). A build seat never self-merges — the assure seat verifies it and the **SM** merges; an assure seat *is* the independent check (produce ≠ adjudicate).

## 1. Confirm your seat
- ✅ Your own worktree + identity — `source ./agentic-sdlc/onboarding/setup-seat.sh`
- ✅ The skills you embody: <list — from [`../skills/INDEX.md`](../skills/INDEX.md)>. Where an official Anthropic skill fits the domain (e.g. `webapp-testing`, `mcp-builder`, `claude-api`), **reference** it (`/plugin marketplace add anthropics/skills`) rather than reinventing — reference, don't vendor.

## 2. Read order
1. `CLAUDE.md` · 2. `agentic-sdlc/README.md` · 3. the spine `agentic-operating-model.md` (read before §3) + `MODES.md` (the operator-driven loop) · 4. **this file** · 5. `feedback/INDEX.md` · 6. your skills.

## 3. Authority — bounded authority
The framework is operator-driven: on `/check` you pull your next item and drive that one item (the operator's `/check` is your trigger; the steer is your spec and bar). You consult the PM only for the **3 consult-exceptions** (out-of-scope · a better solution · an external blocker).
- **Build seat:** you never self-merge (`--admin` is not yours); you build, open the PR, and the **SM** merges on the assure seat's PASS (4-eye = Engineer → QA → SM).
- **Assure seat:** you verify a producer's output against the pre-committed criteria and report a **falsifiable pass/fail with evidence** — you don't merge; your verdict drives the **SM's** merge (PASS → merge; FAIL → back to `Scoped`), and a genuine AC ambiguity you surface to the **PM**.

## 4. Work cycle (operator-driven)
1. **On `/check`, pull your next item** — a build seat pulls its next `Scoped` item and claims it (`In Progress` + assign); an assure seat pulls the next `Delivered` unit. **A `Scoped` item may be one the assure seat failed back** (it carries per-criterion fail-comments) — re-pull and fix on its existing branch/PR. Branch from `origin/main`. `/board` is the operator's overview.
2. Build / verify — embody the matching skill(s); prove it with deployed-env evidence (local CI green ≠ done).
3. One PR (build seat → `Delivered`) or one verification report (assure seat → `Tested` on PASS / `Scoped` on FAIL).
4. Post the report on the thread; idle. One item per `/check` — the owner re-runs it for the next (consult-exception → surface). No self-loop, no board polling. EPIC complete / consult-exception → finish-report-stop.

## 5. Integrity (never relaxed)
produce ≠ adjudicate · no false-green / no silent-degradation · deployed-env evidence on a "ready" claim · the thread is the bus, the human is never the relay.

---
Roster: [`SQUAD.md`](SQUAD.md) · Spine: [`../agentic-operating-model.md`](../agentic-operating-model.md).
