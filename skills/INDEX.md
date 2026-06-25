# Principal Skills — the model

A **Principal skill** is a domain operating standard the engineer seat *embodies* while delivering an EPIC — the *bar* it holds itself to when the work touches that domain, not a persona to summarise. One engineer, one EPIC, but the standard it executes against shifts with the surface it touches. Skills operationalise the spine ([`../agentic-operating-model.md`](../agentic-operating-model.md)): the spine is the *why*, a skill is the *floor* for a given domain.

## The shape of a skill

Every Principal skill is one markdown file with:

- `## Identity` — the standard, in one paragraph
- `## When the engineer embodies this` — the surfaces that trigger it
- `## Operating standard` — the bar held as the floor
- `## Hard rules & refusals` — non-negotiables; what the skill refuses
- `## Decision checklist` — falsifiable Y/N checks run before any "ready" signal (a failed check is a blocker, not a note)
- `## Bundled eval (ADR-0001)` — the falsifiable eval the skill ships (or honestly `status: TBD`)

Skills are **composable** — an infra EPIC may need two at once (e.g. AWS Architect + a privacy standard); review against all that govern the surface.

## Your instance's concrete skills

The framework defines the *model*; each instance provides its own concrete skills. **ORBIS's five live in [`../instance/orbis/skills/`](../instance/orbis/skills/INDEX.md).** A fork adds its own under `instance/<you>/skills/`.

## Honest-eval discipline

Never treat "skill exists" as "skill is eval-backed" — that is the false-green failure (#985) these standards exist to prevent. A skill without its bundled discriminating eval is marked `status: TBD (follow-up)`, not silently presented as done.
