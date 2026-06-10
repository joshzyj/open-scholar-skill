# Design Contract

Phase 3 turns the research question and literature/theory into a testable design. It must use `scholar-design` as the primary design engine. If the design makes causal or quasi-causal claims, or uses DiD, fixed effects for identification, RD, IV, matching/reweighting, mediation, synthetic control, DML/causal forests, or related causal strategies, it must also invoke `scholar-causal` and record the handoff. If the project is computational, qualitative, linguistic, or mixed-methods, it must also route through the relevant specialist method skill and record that handoff.

Required inputs:

- `idea/research-question.json`
- `idea/journal-fit.json`
- `literature/lit-theory.md`
- `literature/lit-theory-manifest.json`
- `literature/literature-coverage-matrix.json`

Required files:

- `design/design-blueprint.md`
- `design/model-specs.json`
- `design/identification-strategy.json`
- `design/design-manifest.json`
- `design/design-evaluation.json`
- `design/design-evaluation.md`
- `design/design-revision-log.json`
- `design/design-revision-log.md`

`identification-strategy.json` must include:

- `design_type`
- `claim_strength`
- `estimand`
- `identification_strategy`
- `outcome_mechanism_alignment`
- `journal_method_bar`
- `hypothesis_model_coverage`
- `power_or_feasibility_assessment`
- `causal_gate`
- `method_specialist_routing`
- `assumptions`
- `measures`
- `threats`
- `robustness_plan`

Rules:

- `assumptions`, `threats`, and `robustness_plan` must each be non-empty lists; assumptions and threats should have at least two items.
- `measures` must define at least `x` and `y`, with names and operational definitions.
- `claim_strength`, `identification_strategy`, `journal_method_bar`, and `estimand` cannot be placeholders.
- `claim_strength` must align with the selected Phase 1 claim strength unless the revision log records a route-back or justified downgrade.
- `outcome_mechanism_alignment` must be one of `entry-process`, `prevalence-stock`, `dissolution`, or `multi-state`.
- `hypothesis_model_coverage` must cover every hypothesis ID from `literature/literature-coverage-matrix.json`, with at least one model ID for each modeled hypothesis. A hypothesis may be marked unmodeled only with an explicit rationale and reviewer acceptance.
- `power_or_feasibility_assessment` must state whether the design is powered, feasible with existing data, or feasibility-limited, with a rationale.
- `causal_gate` must record whether `scholar-causal` was required and invoked. Causal designs fail if `required: true` and `invoked: false`.
- `method_specialist_routing` must be an object with `method_orientation`, `primary_execution_skill`, `premortem_skill`, `supporting_skills`, and `rationale`.
- `primary_execution_skill` and `premortem_skill` must match the project method family:
  - quantitative / demographic / survey / observational / experimental -> `scholar-analyze`
  - computational -> `scholar-compute`
  - qualitative -> `scholar-qual`
  - linguistic -> `scholar-ling`
  - mixed-methods -> one declared primary skill plus a non-empty `supporting_skills` list covering the additional method families
- Computational projects must record `scholar-compute` in the Phase 3 specialist routing.
- Qualitative projects must record `scholar-qual` in the Phase 3 specialist routing.
- Linguistic projects must record `scholar-ling` in the Phase 3 specialist routing.

`model-specs.json` must include:

- `models`: non-empty list
- each model needs `id`, `outcome`, `predictors`, `estimator`, `covariates`, and `purpose`
- each primary hypothesis from Phase 2 must appear in at least one model's `hypothesis_ids` list, unless `hypothesis_model_coverage` records an accepted limitation

Each model should also carry enough design information for a journal-native Analytic Strategy later: unit of analysis, outcome family, focal predictor role, covariate blocks, fixed effects or time indices when applicable, planned uncertainty estimator, and the method-specific interpretation target. Computational models should record the corpus/input unit, feature or representation plan, algorithm/model family, validation target, and how outputs will enter the social-science analysis. These fields may be represented directly in each model object or summarized in a top-level `analytic_strategy` object, but the design must not leave Phase 3 with only an estimator name and empty technical detail.

`design-manifest.json` must include:

- `verdict`: `PASS`
- `source_phase`: `3`
- `design_engine`: `{"skill": "scholar-design", ...}`
- `causal_engine`: object with `required`, `invoked`, and `skill` when invoked
- `method_specialist_engines`: list of non-design specialist engines invoked in Phase 3 because of the method family
- `target_journal`: matching `idea/journal-fit.json`
- `claim_strength`: matching `identification-strategy.json`
- `source_hashes`: hashes for the research question, journal fit, lit-theory, lit-theory manifest, and literature coverage matrix
- `output_hashes`: hashes for the design blueprint, identification strategy, and model specs
- `claim_continuity`: object mapping claim strength, mechanisms, hypotheses, robustness checks, and accepted limitations forward to later manuscript claims
- `mechanism_result_matrix`: list connecting each mechanism to the model/specification, measurement, expected pattern, and manuscript implication
- `robustness_claim_matrix`: list connecting each planned robustness check to the claim it can strengthen, weaken, or bound
- `limitation_scope_matrix`: list connecting each design or data limitation to the scope language required in the manuscript
- `ready_for_phase_4`: `true`

Phase 3 should fail before data planning if the design cannot say what is being estimated, what assumptions make it interpretable, what variables operationalize X/Y, and what robustness checks will stress-test the design.

**Substantive-quality declarations (audit 2026-05-06).** The design blueprint MUST also record three intent fields when the corresponding triggering condition holds. Each field is read by a Phase 8 gate that compares the declaration against the executed analysis; missing declarations route back to Phase 3.

- `measurement_strategy.weights_policy` (required when `data/data-status.json.dataset_id` matches `references/weighted-survey-registry.json` — CFPS, GSS, ACS, CPS, ESS, WVS, PISA, DHS, NHANES, HRS, etc.). Allowed values: `apply_published_weights | apply_constructed_weights | unweighted_with_justification`. The `unweighted_with_justification` value requires prose at `measurement_strategy.weights_justification` naming why an unweighted analysis is defensible (e.g., regression-with-weights-as-controls argument, methodological-paper exception). Phase 8 gate: `scripts/gates/survey-weights-check.sh`.
- `measurement_strategy.composite_validation_plan` (required when any variable in `data/variable-dictionary.csv` has `construct_type ∈ {composite, index, scale}`). Allowed values: `cronbach_alpha | mcdonald_omega | efa | cfa | item_response_theory`. Phase 5 (scholar-eda) executes the validation and writes `analysis/measurement-validation.json`. Phase 8 gate: `scripts/gates/composite-measure-validation-check.sh`.
- `analytic_strategy.interaction_inference_policy` (required when any spec in `analysis/spec-registry.csv` lists an interaction term). Allowed values: `joint_wald_test | likelihood_ratio_test | block_f_test | bayes_factor`. Phase 8 must produce `analysis/joint-tests.json` reporting the declared inference for every interaction-bearing spec. Phase 8 gate: `scripts/gates/interaction-joint-test-check.sh`.

These three declarations are minimum-viable substantive-quality scaffolding. They prevent the systematic failure mode where (a) a national-population claim is made without survey weights, (b) a composite focal predictor is asserted as unidimensional without measurement evidence, and (c) interaction estimates are interpreted as heterogeneity without a joint test. Catching these at design time is cheaper than catching them at quality gate.

Method-specialist routing is not decorative. If the project method family requires `scholar-compute`, `scholar-qual`, or `scholar-ling`, the design must record that handoff in both `method_specialist_routing` and `method_specialist_engines`. A generic quantitative route is not a valid substitute.

## Evaluation and Revision Loop

Phase 3 must include:

1. Draft the design plan.
2. Evaluate it with a design panel.
3. Revise the design plan.
4. Record revisions.
5. Pass only after final evaluation has no unresolved critical issues.

`design-evaluation.json` must include:

- `overall_verdict`: `PASS`
- `unresolved_critical_count`: `0`
- `reviewers`: roles covering `identification`, `measurement`, `theory_mechanism`, `feasibility_data`, and `journal_skeptic`

`design-revision-log.json` must include:

- `required_revisions_completed`: `true`
- `unresolved_critical_count`: `0`
- `final_verdict`: `PASS`
- `revision_rounds`: non-empty list

The revision log should link critical issues to actions taken and affected files. If the evaluation found no critical issues, record a round saying no critical revisions were required and list any optional improvements made.

The evaluation panel must explicitly review `claim_strength`, `outcome_mechanism_alignment`, journal method fit, hypothesis-to-model coverage, power/feasibility, and causal-gate compliance. Do not defer critical design problems to Phase 4 or later.
