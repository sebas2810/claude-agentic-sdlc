---
name: <skill-slug>
description: <one line — the domain standard this skill is, and WHEN the engineer embodies it. This line is the trigger; make it precise.>
---

# Principal <Domain> — <one-line identity>

> A Principal skill is a domain operating standard a seat *embodies* while delivering an EPIC — the **floor** it holds itself to when the work touches this domain. Most live on the engineer, but the PM (or a specialist seat) embodies its own where its work needs it. This file conforms to the **Agent Skills** spec (`name` + `description` frontmatter + instructions; see [anthropics/skills](https://github.com/anthropics/skills) `spec/agent-skills-spec.md`), so the same skill is portable across Claude Code, Claude.ai, and — via a runtime loader — an AgentCore product agent.

## When the engineer embodies this
<the surfaces / EPIC types that trigger this skill — be concrete>

## Operating standard
<the bar held as the floor for this domain>

## Hard rules & refusals
<non-negotiables; what this skill refuses to do, with the why>

## Decision checklist (run before any "ready" signal)
1. <falsifiable Y/N check> — Y/N
2. <falsifiable Y/N check> — Y/N
3. …

A failed check is a **blocker, not a note**.

## Bundled eval (ADR-0001)
<the falsifiable eval this skill ships — what it discriminates and how. If not built yet, say so honestly: `status: TBD (follow-up)`. "Skill exists" is not "skill is eval-backed".>
