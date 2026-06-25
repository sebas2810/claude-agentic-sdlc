# Instance overlay — ORBIS

This folder is the **ORBIS-specific layer** of the agentic SDLC. Everything *outside* `instance/` is the **generic framework** — the operating model (spine), the seat model, the learning-loop mechanics, the onboarding + native-start machinery, and the portable workflow rules. This folder is what makes that framework concrete for *this* product.

**To fork the framework for your own product:** take the repo and **replace `instance/orbis/` with your own `instance/<you>/`** — your domain rules, your Principal skills, your stack-specific gotchas. The framework above stays as-is.

## What's here

| Path | What |
|---|---|
| `skills/` | ORBIS's 5 Principal-grade engineer skills (AWS Cloud Architect · Agentic Engineer · GenAI & Agentic AI · Data Science · Data Analytics) + their index. The generic *"what a Principal skill is"* lives in the framework at [`../../skills/INDEX.md`](../../skills/INDEX.md). |
| `rules/` | ORBIS-specific feedback rules (AgentCore-first, the AWS/Next.js gotchas, dev-environment practices, the Project-#4 status flip) + their index. The portable framework rules stay at [`../../feedback/`](../../feedback/INDEX.md). |
| `engineering-standard.md` | ORBIS's EPIC-#1065 cluster bar (per-cluster "done means" + wave plan + hygiene) on top of the framework floor + ADR-0006. |

## What stays in the framework (not here)

The portable rules a fork keeps as-is: PR-not-push · rebase-before-push · no-AI-attribution · finish-report-stop · produce≠adjudicate / no-silent-degradation · deployed-env-smoke · branch-per-EPIC. A few (e.g. `run-oversight-gates-locally`) are ORBIS-flavoured but stay in the framework because the enforcement hooks reference their path — they'll be generalised when the hook paths are batched (a later stage).
