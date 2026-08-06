# The Evidence Store — machine-checkable or it isn't evidence

Engagement evidence packs live here (or in a dedicated audit repo for multi-target setups). The contract:

- **One directory per engagement**: `evidence/<yyyy-qq-or-epic>/` containing the engagement report, the recorded scope + sample, and one artifact file per check: **the exact query/command, its raw output, timestamp, and the identity that ran it**.
- **Machine-checkable over prose.** The artifact is the `gh api` call + JSON, the `aws` CLI read + output, the mutation score, the alarm-history export — with the reperform instruction inline. Narrative belongs in the report; artifacts ground it. (The cautionary tale is the 2026 Delve scandal: AI-generated audit *narratives* without verifiable evidence are how an assurance function loses its license to operate.)
- **Provenance on the pack itself.** Packs are committed by the Auditor's own identity; a pack is never amended after signature — corrections are a new dated artifact referencing the old.
- **Retention** — packs are kept for the instance's declared audit window (default: 3 years). Nothing in a pack may contain secrets or personal data; evidence that would is referenced by pointer (where it lives + how access is controlled), never copied.
- **Toward machine-readable compliance**: when an instance needs external attestation, packs are the raw material for OSCAL-style assessment results — structure new artifact types with that mapping in mind rather than inventing bespoke formats.
