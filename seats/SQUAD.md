# The Agentic Squad — suggested team

The framework's **core** is a PM + Engineer pair. For a full delivery team, this is the suggested **agentic squad** — a roster of seats across three tiers. Each seat is a Claude Code session with its own `KICKOFF.md` (authority + work cycle) and **embodies the skills** its domain needs ([`../skills/INDEX.md`](../skills/INDEX.md)). It's a *suggestion*, not a mandate — staff a seat when the work needs it; add or rename freely (see *Add a seat*).

## Suggested roster

| Tier | Seat | × | Role | Embodies (skills) |
|---|---|---|---|---|
| **Steer** | **PM** | 1 | The **human interface + merge authority**. Frames Epics with pre-committed AC, approves work to Ready, adjudicates **once at merge**, carries owner touchpoints. **Prep + adjudicate — not the dispatch loop.** | [autonomous-runner](pm/autonomous-runner.md) |
| **Orchestrate** | **Scrum-Master / Orchestrator** | 1 | **THE board orchestrator** — explodes Epics into nested issues, enforces WIP, dispatches `Scoped` to producers, routes the failure back-edges, wakes idle seats, drives `Merged`→`Released`. **Dispatches + flows; never adjudicates, merges, or codes.** | [Orchestrator-Runner](scrum-master/orchestrator-runner.md) · [Flow-Master](scrum-master/flow-master.md) |
| **Build** | **Full-Stack Engineer** | 2 | End-to-end feature delivery (frontend · backend · API). The default producer. | Agentic Engineer · AWS Cloud Architect (as needed) |
| **Build** | **Data Scientist** | 1 | Modelling, scoring, calibration, training-data extraction, model evaluation. | Data Science |
| **Build** | **Data Architect** | 1 | Data model, pipelines, ingestion + retrieval, analytics surfaces. | Data Analytics · Data & Pipelines |
| **Build** | **Cloud Architect** | 1 | Infrastructure, CDK, AgentCore/Bedrock, IAM scoping, cost ceilings. | AWS Cloud Architect |
| **Assure** | **Quality Engineer** | 1 | Independent test + quality verification — the independent check. Owns the `Delivered → Tested` gate. | Quality & Testing |

**= 8 core seats** · 1 steer (PM) · 1 orchestrate (SM) · 5 build · 1 assure. The PM↔SM split frees
the PM for roadmap + adjudication while the SM runs the board — see [work-preparation.md](../workflow/work-preparation.md).

## Why this shape — the seat-vs-skill rule

A capability is a **seat** when it operates **independently** (its own context, runs in parallel, and *especially* when it **reviews someone else's work**); it's a **skill** when it's a build-lens the *same* seat applies. The rule is the spine's `#985` granularity + **produce ≠ adjudicate**.

- **Producers** (Full-Stack / Data Scientist / Data Architect / Cloud Architect) are distinct seats because they build different surfaces in parallel — each composing its domain skill.
- **The Quality Engineer is a seat, not a skill, on purpose** — an *independent* verifier strengthens **produce ≠ adjudicate** (a check by someone who didn't author the work). The PM still adjudicates at merge; the Quality Engineer is the assurance gate (`Delivered → Tested`) that feeds it.
- **The Scrum-Master is the orchestrator, and the PM is the human interface** — the load-bearing split. The **PM** owns *product*: frames Epics with pre-committed AC, approves work to Ready, adjudicates at merge, carries owner touchpoints — and is freed to do roadmap + prioritisation. The **SM** owns *flow*: it explodes Epics into nested issues, dispatches, routes failures, wakes idle seats, drives `Merged`→`Released` — the board's heartbeat and the single board-reader (one GraphQL consumer, so the autonomous loop stays within rate). The SM **dispatches + flows; it never adjudicates, merges, or codes** — produce ≠ adjudicate intact. On a tiny/manual run the PM can embody the SM inline, but autonomous runs want a dedicated SM. See [work-preparation.md](../workflow/work-preparation.md) for the prep handoff.
- The invariants don't move: producers never self-merge; the PM is the merge authority; the owner holds the fixed, countable touchpoints.

## Add a seat

Mirror the skills flow:

1. Copy [`SEAT.template.md`](SEAT.template.md).
2. Fill in the seat's authority + work cycle + the skills it embodies.
3. Drop it as `seats/<role>/KICKOFF.md` and add a row above.
4. Wire its identity via `onboarding/setup-seat.sh` (native start).

All specialist seats now ship a `KICKOFF.md` + an `seat.<role>.template.md`, so each is **startable** — `SEAT_ROLE=quality-engineer source onboarding/setup-seat.sh` (or `SEAT_ROLE=scrum-master`) boots it with its identity, work cycle, and skills. Where an official Anthropic skill fits, the seat **references** it (Cloud Architect → `mcp-builder` · `claude-api`; Quality Engineer → `webapp-testing`) via `/plugin marketplace add anthropics/skills` — referenced, not vendored. Staff each seat **when the work needs it** — the roster is the suggested shape, not a requirement.
