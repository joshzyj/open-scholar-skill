# Phase Contract

The machine-readable source of truth is `phase-contract.json`. Do not duplicate phase definitions in scripts or prose.

Skill routing is governed separately by `skill-routing-contract.md`. Phase completion is invalid if a method-specialist branch should have been invoked but the workflow stayed on a generic default route.

Each phase defines:

- `id`: stable phase token.
- `name`: human-facing label.
- `route`: `default` or optional future route.
- `required_inputs`: artifacts that must exist before work starts.
- `required_outputs`: artifacts that must exist before completion.
- `gate`: verifier command.
- `next`: next phase token or `DONE`.
- `hash_dependencies`: upstream phase IDs that invalidate this phase when changed.
- `pass_schema`: structured fields that the phase verdict must report.
- `conditional_pass_schema`: structured fields required only when the named
  verifier predicate is true. Each rule declares one stable `when` predicate
  and a nonempty `fields` list; Phase 18 uses this for the quantitative
  empirical regression-table audit.
- `review_evidence_policy` (Phases 6, 7, 9, 14, 18, and 20): fixed evidence
  root, canonical summary output, minimum assurance, strict host claims, and
  declared review rounds. Each round defines required roles, exact input
  patterns, its semantic binding collection/object, and any conditional or
  optional-role rule.

Every evidence-required phase lists its fixed `review-evidence/phase-XX` root
as a required output. The verifier validates registered session/completion
events, exact roles and inputs, report/trace digests, semantic bindings,
attempt epoch, and assurance before ordinary output checks. See
`review-evidence-contract.md`; phase JSON is substantive scientific authority,
while the evidence ledger is reviewer-execution authority.

Phase 18 additionally binds `idea/research-question.json` so its fifth-reviewer
condition and permitted specialist evidence role are derived from the
authoritative method orientation; `method_specialist_review.method_family`
must record the same family. Phase 20
validates both the stable semantic-read package artifact and the registered
evidence report, and requires their decision-bearing audit fields to agree.

The default route must end at Phase 20. Optional products are outside this skill's default chain.
