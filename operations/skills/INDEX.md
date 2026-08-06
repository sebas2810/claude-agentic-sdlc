# Ops Skills — the catalog

Same skill model as the [Principal skills](../../skills/INDEX.md): a skill is a **domain operating standard a seat embodies** — the floor it holds itself to — in the official Agent Skills shape (`name` + `description` frontmatter + instructions), portable across Claude Code, Claude.ai, and product agents. Seats compose the skills their work needs; more than one can govern a surface.

| Skill | Embodied by | The floor it sets |
|---|---|---|
| [`incident-rca.md`](incident-rca.md) | Investigator | Hypothesis-driven root-cause analysis — enumerate, test, prune; never summarize-and-guess |
| [`finops-cost.md`](finops-cost.md) | Watcher (and the Cloud Architect at build time) | Unit economics + anomaly discipline for cloud spend **and the fleet's own token bill** |

Runbooks are deliberately **not** a skill — they are versioned *code* in [`../runbooks/`](../runbooks/README.md) with tiers and a promotion rule; a skill can't be demoted by a graded regression, a runbook can.

**Add a skill:** copy [`../../skills/SKILL.template.md`](../../skills/SKILL.template.md), fill in the operating standard + hard rules + a falsifiable decision checklist, register it here. The honest-eval discipline applies: a skill without its bundled discriminating eval is marked `status: TBD (follow-up)` — never silently presented as done.
