# Skill Routing Contract

`scholar-auto-research` must route work to the right specialist skill for the paper type. Listing a skill name in a manifest is not enough; the phase artifacts must show that the correct specialist engine actually owned the relevant work.

Routing principles:

- The goal is a publishable paper, not a phase-complete shell. Use the most method-appropriate specialist skill whenever a project is outside the default quantitative route.
- `scholar-write` and `scholar-citation` remain protected primary engines for drafting and citation/claim support. Builder code may package outputs but must not replace them.
- `scholar-causal` is additive, not substitutive. A causal or quasi-causal project may still be quantitative, computational, linguistic, or mixed-methods, but it must also pass causal review.

## Full Workflow Map

Every skill designed into the workflow must appear in the correct phase route.

- Phase 1:
  - primary: `scholar-idea` or `scholar-brainstorm`
- Phase 2:
  - primary: `scholar-lit-review-hypothesis`
  - required writing handoff: `scholar-write`
  - optional support: `scholar-lit-review`, `scholar-hypothesis`
- Phase 3:
  - primary: `scholar-design`
  - conditional additive review: `scholar-causal`
  - conditional method specialist: `scholar-compute`, `scholar-qual`, `scholar-ling`
- Phase 4:
  - primary: `scholar-data`
- Phase 5:
  - primary compiler: internal `scholar-auto-research` analysis planner
- Phase 6:
  - primary: `scholar-code-review`
- Phase 7:
  - primary premortem: routed empirical specialist
    - `scholar-analyze` or `scholar-compute` or `scholar-qual` or `scholar-ling`
- Phase 8:
  - primary execution: routed empirical specialist
    - `scholar-analyze` or `scholar-compute` or `scholar-qual` or `scholar-ling`
- Phase 9:
  - primary: `scholar-verify`
- Phase 10:
  - primary deterministic gate: internal `scholar-auto-research`
- Phase 11:
  - primary deterministic lock: internal `scholar-auto-research`
- Phase 12:
  - primary compiler: internal `scholar-auto-research`
- Phase 13:
  - journal prep: `scholar-journal`
  - primary drafting: `scholar-write`
  - polish: `scholar-polish`
- Phase 14:
  - primary: `scholar-verify`
- Phase 15:
  - primary: `scholar-citation`
- Phase 16:
  - primary: `scholar-ethics`
  - primary: `scholar-open`
- Phase 17:
  - primary: `scholar-replication`
- Phase 18:
  - primary: `scholar-respond`
  - prose audit: `scholar-polish`
- Phases 19-20:
  - primary deterministic assembly/hygiene: internal `scholar-auto-research`

If one of those skills is designed into the workflow, the phase must either:

- invoke it and record the handoff in a phase artifact; or
- record a valid route-back / inapplicability explanation allowed by the phase contract.

Silently replacing a designed skill with a builder, template, or manifest stub is a workflow failure.

Normalized method routing:

- Quantitative / demographic / survey / observational / experimental route:
  - Phase 7 premortem: `scholar-analyze`
  - Phase 8 execution: `scholar-analyze`
- Computational social science route:
  - Phase 3 specialist support: `scholar-compute`
  - Phase 7 premortem: `scholar-compute`
  - Phase 8 execution: `scholar-compute`
- Qualitative route:
  - Phase 3 specialist support: `scholar-qual`
  - Phase 7 premortem: `scholar-qual`
  - Phase 8 execution: `scholar-qual`
- Linguistic / sociolinguistic route:
  - Phase 3 specialist support: `scholar-ling`
  - Phase 7 premortem: `scholar-ling`
  - Phase 8 execution: `scholar-ling`
- Mixed-methods route:
  - Phase 3 must declare a primary execution skill plus supporting specialist skills
  - The supporting set must include every non-quantitative component present in the design
  - Phase 7 and Phase 8 must use the declared primary execution skill and preserve the supporting-skill handoff in the routing metadata

Expected routing metadata:

- `idea/research-question.json` must carry a non-placeholder `method_orientation` that is specific enough to map onto a routing family.
- `design/identification-strategy.json` must include `method_specialist_routing` with:
  - `method_orientation`
  - `primary_execution_skill`
  - `premortem_skill`
  - `supporting_skills`
  - `rationale`
- `design/design-manifest.json` must include `method_specialist_engines`, a list of invoked Phase 3 specialist engines required by the method family.
- `review/analysis-premortem.json` and `analysis/execution-report.json` must use the routed specialist skill, not a hard-coded quantitative default.
- Every phase that names a specialist skill must preserve that skill in a phase-specific engine object or engine-handoff object so the verifier can audit the route.

Common invocation provenance:

- Every phase-specific skill engine object must include:
  - `task_invocation_id`
  - `invoked_at_utc`
  - `input_artifacts`
  - `output_artifacts`
- `task_invocation_id` must be a non-placeholder stable token for that skill handoff.
- `invoked_at_utc` must be an ISO-like UTC timestamp.
- `input_artifacts` and `output_artifacts` must be non-empty lists of project-relative artifact paths relevant to the handoff.
- A bare `skill` and `mode` label without provenance does not count as a real invocation.

Allowed specialist skills in this contract:

- `scholar-analyze`
- `scholar-compute`
- `scholar-qual`
- `scholar-ling`
- `scholar-causal`

Optional supporting skills:

- `scholar-lit-review`
- `scholar-hypothesis`

Optional supporting skills may strengthen a phase, but they do not replace the required primary or routed specialist engines.


Phase 2 specialist protocol:

- `scholar-auto-research` must not manual-emulate `scholar-lit-review-hypothesis`. The integrated literature engine is considered invoked only if the project preserves its local-library-first search trace and review-protocol artifact in canonical Phase 2 outputs.
- Reusing references from earlier project bibliographies is allowed only as a logged `RefLib`/BibTeX backend within that protocol; silent bibliography mining is not an acceptable substitute for Phase 2 search.
