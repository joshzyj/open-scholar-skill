# Phase 16 Ethics And Open Science Contract

Phase 16 converts the verified manuscript and citation audit into submission-ready ethics and open-science declarations. It uses `scholar-ethics` for AI/privacy/originality/integrity/IRB/COI declarations and `scholar-open` for data availability, CRediT, preregistration, code sharing, and replication-package planning.

## Required Inputs

- `safety/safety-status.json`
- `data/data-status.json`
- `manuscript/manuscript-draft.md`
- `manuscript/draft-manifest.json`
- `citation/citation-audit.json`

## Required Outputs

- `ethics/ethics-open-science.json`
- `ethics/ethics-open-science.md`

## Required JSON Fields

`ethics/ethics-open-science.json` must include:

- `verdict`: `PASS` or `FAIL`
- `degraded`: `false` for PASS
- `source_phase`: `16`
- `ethics_engine`: `{ "skill": "scholar-ethics", "mode": "full" }` plus `ai_privacy`, `originality`, `integrity`, and `general_ethics` set to `true`
- `open_science_engine`: `{ "skill": "scholar-open", "mode": "full-package" }` plus `data_management`, `code_sharing`, `credit_coi`, and `replication_planning` set to `true`
- `source_hashes`: hashes for safety status, data status, manuscript, draft manifest, and citation audit
- `selected_manuscript_hash`: current manuscript hash
- `critical_flags`: empty list for PASS
- `ai_disclosure`: tool inventory and paste-ready disclosure statement
- `privacy_review`: AI/data privacy risk assessment tied to Phase 0 safety
- `irb_status`: IRB or non-human-subjects determination tied to Phase 4 data status
- `consent_status`: consent or waiver status
- `coi_status`: conflict-of-interest declaration
- `data_availability`: data sharing statement and sharing mode
- `open_science`: preregistration, code sharing, license, preprint/open-access, and replication readiness plan
- `authorship_credit`: CRediT/authorship statement
- `integrity_review`: originality, p-hacking/selective-reporting, and interpretation checks
- `findings`: structured open findings for FAIL; empty for PASS
- `fix_checklist`: structured same-phase or route-back fixes
- `route_back_phase`: earliest affected phase for FAIL; null/empty for PASS
- `ready_for_phase_17`: `true` for PASS

## PASS Rules

- Phase 15 citation audit must pass with `ready_for_phase_16: true`.
- `critical_flags` and `findings` must be empty.
- AI disclosure must name the tools used and state that human authors reviewed all AI-assisted content.
- AI tool inventory must include concrete tool/provider/model-or-version, stage, task, data shared, sensitivity, date, and cloud/local status. Auto-research projects may not claim that no AI tools were used.
- Privacy review must have no unresolved high-risk data sharing.
- IRB status must be compatible with Phase 4 `data-status.json`; `pending` cannot pass.
- Restricted or pending data access cannot be declared as public full-data sharing.
- Human-subjects or restricted data cannot use `consent_status: not-applicable` unless Phase 4 is explicitly `not-human-subjects` or `not-applicable`.
- COI declaration must be explicit, either no competing interests or named conflicts with no unresolved conflict.
- Data availability must match Phase 4 data status:
  - `existing-data` requires `public-data-full`, `restricted-data-code-only`, or `synthetic-demo`.
  - `collecting-new-data` requires a repository/access plan and consent/IRB sharing language.
  - `no-data` requires `no-data-conceptual`.
- Open-science plan must declare preregistration status, code sharing plan, license plan, and `replication_ready: true`.
- Integrity review must use the Phase 15 citation audit and Phase 9/13 result constraints rather than inventing new claims.
- Integrity review must list checked artifact paths and current hashes.
- JSON and Markdown outputs must not contain placeholders such as bracketed template fields, `XXXX`, `Author 1`, `Author X`, `TBD`, `TODO`, or `to be determined`.
- Markdown declarations must agree with the structured JSON declarations.
- Markdown summary must include AI use, IRB/consent, COI, data availability, and open-science declarations.

## FAIL Route Rules

- Phase 0: unresolved AI privacy/safety exposure.
- Phase 4: data status, IRB, consent, or data-sharing plan mismatch.
- Phase 13: manuscript ethics text needs revision.
- Phase 15: citation audit or source-support issue changes ethics/open-science declarations.
- Phase 16: same-phase declaration drafting, COI wording, CRediT, preregistration, open-access, or open-science packaging issue.
