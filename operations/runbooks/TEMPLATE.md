# RB-<nnn> — <verb-first title, e.g. "Restart the scoring service">

- **Tier:** 2 (new runbooks start 2 or 1 — Tier 0 is earned; see the promotion rule)
- **Owner:** <human accountable for this runbook>
- **Trigger:** <the RCA finding / signal pattern this remediates>
- **Blast radius:** <worst case if this runs against the wrong target, computed against the Operator's full privilege set>
- **Credentials:** <the exact scoped credential released for this action, and how (environment name / token scope)>

## Preconditions (verified at execution time — any N ⇒ abort)

1. <falsifiable check, e.g. "the deviation from RB's trigger is still present: <query>"> — Y/N
2. <safety check, e.g. "no deploy in flight: <query>"> — Y/N

## Steps (deterministic — commands, not intentions)

```
<exact commands, with placeholders only for the incident-specific target>
```

## Verification (independent signal — never this action's exit code)

- <the health signal + threshold that defines success, and how long to watch it>

## Rollback (part of the action, not a follow-up)

```
<exact commands that restore the prior state>
```

## Promotion history

| Date | Change | Evidence |
|---|---|---|
| <YYYY-MM-DD> | Created at Tier 2 | PR #<n> |
