# Execute Analysis Contract

Phase 8 runs the analysis approved by Phase 7. It must not invent a new execution path. It must invoke the routed specialist execution engine from Phase 3 after the Phase 7 premortem passes.

Required files:

- `analysis/execution-report.json`
- `tables/results-registry.csv`
- at least one canonical publication regression table for quantitative empirical papers, such as `tables/regression-main.html`, `tables/regression-main.tex`, or `tables/regression-main.docx`
- `figures/figure-registry.csv`
- `analysis/measurement-validation.json` (required when `design/design-blueprint.json.measurement_strategy.composite_validation_plan` is set; see L1.3 substantive-quality declarations in design-contract.md)
- `analysis/joint-tests.json` (required when any spec in `analysis/spec-registry.csv` declares interaction terms; see L1.4 substantive-quality declarations in design-contract.md)
- `tables/model-fit-stats.csv` (required for any quantitative empirical project — must include one row per spec with `spec_id`, `status` (focal/sensitivity/robustness), and at least one fit statistic: `r_squared`, `pseudo_r_squared`, `mcfadden_r2`, `adj_r_squared`, `aic`, or `bic`)

Required inputs:

- `analysis/analysis-plan.md`
- `analysis/spec-registry.csv`
- `analysis/scripts-inventory.json`
- `review/analysis-premortem.json`
- `review/analysis-premortem-fix-log.json`

`execution-report.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `ready_for_phase_9`: `true`
- `execution_engine`: object with the routed specialist skill, `mode: execute_analysis`, `auto_research_contract: phase_8`, and `phase7_handoff_only: true`
- `run_context`: object with `started_at_utc`, `completed_at_utc`, `working_directory`, `seed`, `environment`, and `session_info`
- `source_hashes`: SHA-256 hashes for `analysis_plan`, `spec_registry`, `scripts_inventory`, `analysis_premortem`, and `analysis_premortem_fix_log`
- `phase7_source_hash_check`: object confirming Phase 7 premortem source hashes still match the current analysis plan, spec registry, scripts inventory, and premortem fix log
- `phase7_go`: object with `decision: GO` and `ready_for_phase_8: true`
- `command_trace`: list matching `phase8_handoff.script_order`, each with `path`, `command`, `cwd`, `started_at`, `ended_at`, `exit_code`, `stdout_log`, and `stderr_log`
- `executed_scripts`: list matching `analysis-premortem.json.phase8_handoff.script_order` exactly and in order
- `exit_codes`: object mapping every executed script path to `0`
- `tests_run`: list covering every planned test from `analysis/scripts-inventory.json`
- `halt_checks`: list covering every halt check from `analysis-premortem.json.phase8_handoff.halt_checks`
- `expected_outputs`: list covering every expected output from `analysis-premortem.json.phase8_handoff.expected_outputs`
- `results_registry`: path, row count, and covered spec IDs
- `figure_registry`: path, row count, and covered figure IDs or explicit no-figure declaration
- `artifact_manifest`: list of all non-report produced Phase 8 artifacts with `path`, `sha256`, `artifact_role`, `produced_by`, and `registered`
- `analysis_stack`: object documenting the actual execution stack used for estimation, table export, marginal effects, and figures
- `publication_regression_tables`: list of canonical reader-facing regression table artifacts, with path, role, source script, table engine, model columns, statistic rows, and whether the table is main-text, appendix, or sensitivity evidence
- `errors`: empty list

`analysis_stack` must include:

- `primary_language`
- `table_engine`
- `figure_engine`
- `packages_used`
- `nonlinear_probability_models`
- `marginal_effects_engine`
- `viz_style_source`
- `ggplot2_style_consistency`
- `reader_facing_label_source`
- `table_label_translation_applied`
- `figure_label_translation_applied`
- `deviation_justification`

Each `executed_scripts` item must include `path`, `command`, `script_hash`, `exit_code: 0`, `status: success`, `started_at`, `ended_at`, `outputs`, and `output_hashes`.

Every planned script must exist by Phase 8 and its reported `script_hash` must match the current file. Every output listed by a script must have a SHA-256 entry in `output_hashes`. Every produced table, figure, model output, diagnostic output, and intermediate output must appear in `artifact_manifest`. Execution must halt on a nonzero exit code, missing expected output, failed test, stale source hash, changed output hash, unregistered planned spec, unregistered table/figure artifact, or Phase 7 source-hash drift.

When the routed execution skill is `scholar-analyze` for a quantitative / demographic / survey / observational / experimental paper, auto-research inherits the stronger full-paper defaults unless a justified exception is recorded in `analysis_stack.deviation_justification`:

- use `R` as the primary execution language;
- use `modelsummary` as the regression-table export engine;
- use `ggplot2` as the figure engine;
- use `marginaleffects` when nonlinear probability models are central to the reported results or figures.
- use the Phase 4 variable dictionary as the authoritative source for reader-facing labels in tables, figures, and captions;
- when `ggplot2` is used, provide `analysis/scripts/viz_setting.R`, source it from figure-producing R scripts, apply its theme/scale helpers materially in the figure code, and copy it into the replication package whenever packaged scripts source it. `scripts/gates/figure-style-source-check.sh` verifies the source, application, and packaging path.

Departures are allowed only when the design or required package ecosystem makes them necessary. In that case, the execution report must say what replaced the default and why.

**Fallback engines for `table_engine`.** `modelsummary` cannot tidy every model class (custom S4 classes, certain survey designs, hand-fit Bayesian draws, some `lavaan` SEM modes). When the planned model is incompatible with `modelsummary`, declare an `analysis_stack.table_engine_fallback` from this allowed list and write the deviation reason in `analysis_stack.deviation_justification`:

- `stargazer` — robust for `lm`/`glm`/`lme4`
- `texreg` / `htmlreg` — broad coverage; supports `lavaan`, `plm`, custom S4
- `huxtable::huxreg` — modern alternative to `stargazer`
- `gtsummary::tbl_regression` + `gt::gtsave` — health-sciences idiom
- `fixest::etable` — for `fixest` models
- `kableExtra::kable` on a hand-built coefficient frame — last-resort escape hatch for unsupported models

**Artifact requirement (audit 2026-05-03).** Whichever engine is used, Phase 8 must produce at least one publication-quality regression table file at `tables/*.html`, `tables/*.tex`, or `tables/*.docx`. A `tables/` folder containing only registry CSVs (`results-registry.csv`, `focal-coefs.csv`, `spec-registry.csv`, etc.) does not satisfy the contract — registries are metadata, not the publication artifact. The Phase 8 verifier inspects `tables/` for at least one `.html` / `.tex` / `.docx` file; if absent, it scans the analysis R scripts for a call to one of `modelsummary`, `stargazer`, `texreg`, `htmlreg`, `huxreg`, `tbl_regression`, `gtsave`, `etable`, or `kable` to distinguish a silently-failing engine call (YELLOW) from a contract violation where no engine was ever invoked (RED).

**Canonical regression-table requirement (audit 2026-05-03).** For quantitative empirical projects, the reader-facing empirical table must preserve the original regression-table architecture: model specifications as columns, substantive predictors/covariates as rows, standard errors or confidence intervals, p-values or significance markers where journal-appropriate, sample size, model fit or event counts where relevant, and footnotes describing weights, clustering, fixed effects, and covariate blocks. A row-per-spec registry, model ladder, focal-coefficient extract, or CSV audit table cannot satisfy the publication table requirement even when all numbers are correct. The main table must be registered in `artifact_manifest` as `main_regression_table` or `regression_table`; robustness or appendix tables should use `sensitivity_regression_table` or `regression_table`. `results-registry.csv` remains a provenance and verification artifact.

**Regression-engine purity.** When `analysis_stack.table_engine = modelsummary`, the analysis script must invoke `modelsummary(...)` or `msummary(...)` on FITTED model objects. `modelsummary::datasummary_df()`, `modelsummary::datasummary()`, and `gtsummary::tbl_summary()` consume DATA FRAMES rather than fitted models — they produce display tables but cannot produce a regression table with predictor rows, SE layout, and a goodness-of-fit block. A `tables/table-main-regression.*` file rendered solely by these descriptive engines is a hand-built focal extract regardless of how it is named. The gate `scripts/gates/regression-table-export-check.sh` (regression-engine purity branch) RED-fails this configuration. The same rule applies to fallback engines: `tbl_regression()` (gtsummary) is acceptable for the main regression table; `tbl_summary()` is not.

**Descriptive-table coverage.** `tables/table1-descriptives.csv` (or its appendix companion `tables/table-descriptives-all-variables.csv`) must cover every variable that appears in `analysis/spec-registry.csv` columns `outcome`, `predictors`, or `covariates` AND is listed in `data/variable-dictionary.csv`. The display venue (main text vs appendix) is journal-controlled; the COVERAGE is non-negotiable. Hardcoded Table 1 variable subsets fail. Phase 8 must drive descriptives from the spec-registry, not from a manually maintained list. The gate `scripts/gates/descriptives-coverage-check.sh` enforces the rule.

`publication_regression_tables` must include at least one entry with `role: main_regression_table` for quantitative empirical manuscripts unless the analysis design is genuinely non-regression and the exception is justified in `analysis_stack.deviation_justification`. Each listed table path must exist under `tables/`, appear in `artifact_manifest`, use reader-facing labels from Phase 4 display semantics, and be generated by an executed script rather than hand-authored after the run. Model columns in these tables must use reader-facing labels such as `Model 1`, `Model 2`, `M1`, or `M2`; internal specification identifiers such as `S1` and `S2` may remain in registries and trace metadata, but they must not appear as visible model labels in publication tables.

`tables/results-registry.csv` must include:

- `spec_id`
- `model_id`
- `outcome`
- `predictor`
- `estimate`
- `std_error`
- `p_value`
- `n`
- `status`
- `output_file`

Every planned `spec_id` from `analysis/spec-registry.csv` must appear exactly once. Unplanned extra `spec_id` rows fail. Completed rows must have non-placeholder numeric `estimate`, nonnegative `std_error`, `p_value` between 0 and 1, positive `n`, and an existing relative `output_file`.

`figures/figure-registry.csv` must include:

- `figure_id`
- `path`
- `source_script`
- `status`
- `description`

If no figures are planned, the registry may contain a single row with `figure_id: NONE`, `status: no_figures_planned`, and a substantive description. Otherwise every completed figure row must point to an existing file.

Phase 8 may not change the analysis plan, spec registry, scripts inventory, or Phase 7 premortem artifacts and then proceed by simply recomputing execution hashes. If any of those sources changed after Phase 7, route back to the earliest affected phase and rerun review before execution.

Expected routed skills:

- quantitative / demographic / survey / observational / experimental -> `scholar-analyze`
- computational -> `scholar-compute`
- qualitative -> `scholar-qual`
- linguistic -> `scholar-ling`
- mixed-methods -> the declared `primary_execution_skill` from Phase 3, with supporting skills preserved in routing metadata

## Substantive-quality artifacts (audit 2026-05-06)

`analysis/measurement-validation.json` schema:

```json
{
  "composites": [
    {
      "variable": "<dictionary variable name>",
      "items": ["<source item 1>", "<source item 2>"],
      "method": "cronbach_alpha | mcdonald_omega | efa | cfa | item_response_theory",
      "alpha": 0.74,
      "omega": null,
      "factor_loadings": null,
      "n_factors_recommended": 1,
      "decision": "retain_composite | drop_composite | report_components_separately"
    }
  ]
}
```

Every variable in `data/variable-dictionary.csv` whose `construct_type` is `composite`, `index`, or `scale` MUST appear as a `composites[]` entry. The `method` field MUST match the `composite_validation_plan` declared in the design blueprint. The `decision` field is what the analysis stack does with the composite — it can drop a composite that fails reliability and report components separately rather than forcing a composite into the model.

`analysis/joint-tests.json` schema:

```json
{
  "joint_tests": [
    {
      "spec_id": "<matching analysis/spec-registry.csv row>",
      "interaction_terms": ["x_var1:x_var2", "x_var1:x_var3"],
      "method": "joint_wald_test | likelihood_ratio_test | block_f_test | bayes_factor",
      "test_statistic": 12.34,
      "df": 3,
      "p_value": 0.015,
      "interpretation": "joint reject | joint fail to reject | bounded"
    }
  ]
}
```

Every `analysis/spec-registry.csv` row whose `predictors` column contains an interaction marker (`*`, `:`, or a `_x_` slug between two variable names) MUST appear as a `joint_tests[]` entry. The `method` field MUST match `analytic_strategy.interaction_inference_policy` declared in the design blueprint. Reporting individual interaction-term coefficients without a joint test does not satisfy the contract — Phase 8 RED-fails when interactions are declared without a corresponding joint test.

`tables/model-fit-stats.csv` schema (one row per fitted spec):

```
spec_id,status,n,r_squared,adj_r_squared,pseudo_r_squared,mcfadden_r2,aic,bic,deviance
S01,focal,19180,0.035,0.034,,,52431.2,52503.1,52340.0
S02,focal,19180,0.035,0.034,,,52432.0,52504.0,52341.0
S03,focal,19196,0.064,0.063,,,52201.4,52280.0,52102.0
```

This file feeds the `effect-size-narrative-check.sh` gate, which inspects whether focal models with R² < 0.05 are accompanied by an explicit acknowledgment in the manuscript. The fit-statistic columns may be empty for non-applicable rows (e.g., pseudo_r_squared empty for OLS), but at least one fit statistic must be populated for every spec.
