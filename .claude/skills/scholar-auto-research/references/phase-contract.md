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

The default route must end at Phase 20. Optional products are outside this skill's default chain.
