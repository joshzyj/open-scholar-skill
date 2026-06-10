# Analysis Plan Contract

Phase 5 creates an executable analysis plan without running the analysis. It must use `scholar-auto-research`'s internal `analysis_plan_compiler` as the planning engine. Do not invoke `scholar-analyze` in Phase 5; reserve it for Phase 8 execution after Phase 6 and Phase 7 pass.

Required inputs:

- `design/design-manifest.json`
- `design/identification-strategy.json`
- `design/model-specs.json`
- `data/data-status.json`
- `data/variable-dictionary.csv`
- `data/data-measurement-manifest.json`
- `data/measurement-plan.md`

Required files:

- `analysis/analysis-plan.md`
- `analysis/spec-registry.csv`
- `analysis/scripts-inventory.json`
- `analysis/analysis-plan-manifest.json`

`spec-registry.csv` must include:

- `spec_id`
- `model_id`
- `hypothesis_ids`
- `outcome`
- `predictors`
- `covariates`
- `estimator`
- `purpose`
- `robustness_type`
- `missing_data_strategy`
- `status`

Every row must have `status=planned` in Phase 5.

`analysis/analysis-plan.md` must also contain a manuscript-facing methods brief for each main method family. This brief is the upstream source that later prevents generic Methods prose. It must state, in reader-facing language:

- original/source data size expected before analytic restrictions, when known at planning time;
- planned analytic sample restrictions and final-sample denominator logic;
- method family and why it fits the outcome, data structure, and theoretical question;
- the planned estimating equation or computational workflow using the actual outcome, focal predictors, covariates/features, unit/time indices, corpus/input units, or network/simulation elements;
- inference or validation plan, including standard errors/clustering/weights for statistical models or performance, reliability, balance, calibration, error-analysis, or sensitivity checks for computational methods;
- robustness checks and how they would change the interpretation.

For computational projects routed to `scholar-compute`, the methods brief must introduce the method for social scientists rather than only naming an algorithm. It must explain how raw empirical material is transformed into analytic measures, predictions, classes, embeddings, networks, simulations, or visual/audio features, and what validation evidence makes those outputs usable in the substantive argument.

Rules:

- Every model ID in `design/model-specs.json` must appear in at least one planned spec.
- Every hypothesis ID listed in Phase 3 model specs must appear in at least one planned spec.
- Every planned spec variable must appear in `data/variable-dictionary.csv`.
- Every promised robustness check in `design/identification-strategy.json.robustness_plan` must have a planned spec or an accepted limitation in the manifest.
- Missing-data strategy must align with Phase 4 measurement planning.
- Secondary-data projects with survey, panel, clustered, administrative, experimental, weighted, or multistage structure must include a dataset-design plan. The plan must decide whether to use weights/design variables/clustering/panel identifiers or explicitly justify an unweighted/simplified analysis as a limitation.
- Outcomes that are bounded, skewed, zero-inflated, count-like, duration-like, or time-use-like must include a model ladder. The ladder must contain the headline estimator plus at least one sensitivity route appropriate to the outcome family, such as transformed outcome, positive-case model, two-part model, GLM, quantile model, top-code sensitivity, or distributional diagnostic.
- Complete-case strategies, high missingness, structural skips, or denominator-changing restrictions must include post-restriction missingness diagnostics and at least one sensitivity or bounding check unless an accepted limitation explains why it is impossible.

`scripts-inventory.json` must include:

- `no_execution_yet: true`
- `scripts`: non-empty list of planned scripts
- `test_inventory`: non-empty list of planned tests
- `script_order`: ordered list of script paths
- `dependency_graph`: object mapping each script to the scripts it depends on

Each script needs `path`, `purpose`, `uses`, `produces`, and `status=planned`. Dependencies must refer only to known scripts and must appear earlier in `script_order`.

`test_inventory` must include tests covering at least:

- `data_loading`
- `analytic_sample`
- `variable_construction`
- `missingness`
- `model_spec`
- `output_registry`

`analysis-plan-manifest.json` must include:

- `verdict`: `PASS`
- `source_phase`: `5`
- `analysis_planning_engine`: `{"skill": "scholar-auto-research", "mode": "analysis_plan_compiler", ...}`
- `source_hashes`: hashes for design manifest, identification strategy, model specs, variable dictionary, data-measurement manifest, and measurement plan
- `output_hashes`: hashes for analysis plan, spec registry, and scripts inventory
- `model_spec_coverage`: every Phase 3 model ID covered by spec IDs
- `hypothesis_spec_coverage`: every Phase 3 hypothesis ID covered by spec IDs
- `variable_coverage`: every spec variable covered by Phase 4 variable dictionary
- `robustness_coverage`: Phase 3 robustness plan mapped to planned specs or accepted limitations
- `missing_data_alignment`: Phase 5 missing-data strategy matches Phase 4
- `dataset_design_plan`: weight/design/clustering/panel decision inherited from Phase 4 `dataset_design_review`
- `outcome_model_ladder`: outcome-family diagnostics and estimator/sensitivity ladder for non-Gaussian, bounded, count, duration, or time-use outcomes
- `missingness_sensitivity_plan`: post-restriction missingness diagnostics, skip-vs-missing handling, denominator checks, and sensitivity specs or accepted limitations
- `script_dag`: script order and dependency validation summary
- `test_coverage`: required test categories and spec-level tests
- `ready_for_phase_6`: `true`

Phase 5 fails if result registries or execution reports already exist, because execution belongs to Phase 8 after pre-execution review and analysis premortem.

## Control-variable enforcement (added 2026-05-11, design-aware since v14 — 2026-05-11)

Phase 5 enforces control-variable inclusion at two layers. Both layers consume a single shared resolver helper at `scripts/gates/_phase5-skill-resolver.sh`, which reads `method_specialist_routing.primary_execution_skill` from `design/identification-strategy.json` and emits `COVARIATES_OPTIONAL=true|false`. This is the **single source of truth** for which method families allow empty covariates.

| `primary_execution_skill` | Layer 1 enforces `covariates` non-empty per row? | Layer 2 verdict |
|---|:---:|---|
| `scholar-analyze` (regression family — quantitative/observational/experimental/demographic) | ✅ yes | regression contract: ≥1 spec with controls; RCT/DAG refinements via free-form `design_type` pattern match |
| `scholar-compute` (computational) | ❌ skipped | GREEN — `not_applicable` |
| `scholar-qual` (qualitative) | ❌ skipped | GREEN — `not_applicable` |
| `scholar-ling` (linguistic) | ❌ skipped | GREEN — `not_applicable` |
| missing / unrecognized | ✅ yes (safe-default strict) | regression contract |

**Layer 1** (in `auto-research-verify.sh` Phase 5 block): the per-row "non-empty and non-placeholder" check applies to every required column. For the `covariates` column specifically, the check is skipped when the resolver emits `COVARIATES_OPTIONAL=true`. Other columns (`outcome`, `predictors`, `estimator`, `purpose`, `robustness_type`, `missing_data_strategy`, `status`, `spec_id`, `model_id`, `hypothesis_ids`) stay universally enforced.

**Layer 2** (`scripts/gates/control-variables-check.sh`): runs after Layer 1. Non-regression families short-circuit to GREEN. For the regression family, the gate refines verdicts based on free-form `design_type` prose:
- RCT (`design_type` contains `rct` or `randomi(s|z)ed trial`): requires both an unadjusted ITT spec AND a covariate-adjusted spec.
- DAG (`design_type` contains `dag`, `observational-causal`, or `causal-with-dag`): requires ≥1 spec with controls; adjustment-set match advised but not enforced.
- Otherwise (regression default): requires ≥1 spec with controls.

**Excuse mechanism:** add `[EXCUSED:control-variables: <reason>]` to `analysis/analysis-plan.md` to opt out at Layer 2 (e.g., methodology paper, decomposition with no overlap covariates). Layer 1 still applies. To opt out of Layer 1 also, change `primary_execution_skill` to a non-regression value.

**Maintenance invariant:** the resolver helper is the SINGLE place where the non-regression whitelist (`scholar-compute`, `scholar-qual`, `scholar-ling`) lives. Adding a new non-regression method family requires updating one file. Smoke tests:
- `tests/smoke/test-phase5-skill-resolver.sh` — 10 cases on the helper (4 skills, missing file, malformed JSON, unknown skill, usage error, real fixture)
- `tests/smoke/test-control-variables-check.sh` — 11 cases on Layer 2
- `tests/smoke/test-layer1-design-aware.sh` — 4 integration cases verifying Layer 1 behavior on the bundled fixture

**Self-contained:** all three files (`_phase5-skill-resolver.sh`, `control-variables-check.sh`, Layer 1 in `auto-research-verify.sh`) live within `skills/scholar-auto-research/`. No dependencies on parent `scholar-skill/scripts/gates/`.
