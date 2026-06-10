# Data and Measurement Contract

Phase 4 turns the design into an auditable data and measurement plan. It must invoke `scholar-data` as the data and measurement engine, inherit Phase 3 design artifacts, and prove that the planned data can support the model variables before Phase 5 analysis planning.

Required inputs:

- `safety/safety-status.json`
- `design/design-blueprint.md`
- `design/design-manifest.json`
- `design/identification-strategy.json`
- `design/model-specs.json`

Required files:

- `data/variable-dictionary.csv`
- `data/data-status.json`
- `data/measurement-plan.md`
- `data/data-measurement-manifest.json`

`data-status.json` must include:

- `data_status`: one of `existing-data`, `collecting-new-data`, `no-data`
- `access_status`: one of `available`, `restricted`, `pending`, `not-applicable`
- `irb_status`: one of `exempt`, `approved`, `pending`, `not-human-subjects`, `not-applicable`
- `source_type`: e.g. `public`, `restricted`, `original-collection`, `conceptual`
- `files`: list of data files or planned files
- `dataset_fit`: object covering unit of analysis, population/scope, time period, key variable availability, sample size feasibility, and access timeline
- `dataset_design_review`: object covering the data-generating design before modeling. For survey, panel, administrative, experimental, clustered, multistage, or weighted data, it must record whether weights, clusters, strata, panel identifiers, sampling frame, collection mode, and denominator rules were reviewed; the analytic decision; and any accepted limitations.

`variable-dictionary.csv` must include columns:

- `variable`
- `role`
- `construct`
- `display_label`
- `table_stub_label`
- `manuscript_term`
- `levels_display`
- `operationalization`
- `source`
- `missing_values`
- `design_source`
- `post_treatment`
- `measurement_quality`

At minimum it must define one `x` role and one `y` role, aligned with Phase 3 measures. Every X/Y measure from `design/identification-strategy.json` and every outcome, predictor, and covariate from `design/model-specs.json` must appear in the dictionary unless the manifest records an accepted limitation. Post-treatment variables must be flagged explicitly; unflagged post-treatment controls fail the phase.

The variable dictionary must also serve as the reader-facing translation layer for downstream tables, figures, and manuscript prose.

- `display_label`: the plain-language label that should appear in figure axes, legends, and coefficient labels when the concept is shown directly;
- `table_stub_label`: the label that should appear in reader-facing table stubs or row labels;
- `manuscript_term`: the prose term the manuscript should use when naming the measure in sentences;
- `levels_display`: the category labels or value-description scheme for the variable. Continuous measures may use a prose descriptor such as `continuous years measure` or `binary indicator: 1 = female`.

Raw dataset names such as `gender_var`, `hukou_2020`, `x1`, or other machine-style field names are not acceptable reader-facing labels. If a dataset-native variable name is cryptic, coded, underscored, or otherwise non-reader-facing, the display fields must translate it into concept-level language.

Phase 13 (manuscript drafting) MUST consume `construct`, `display_label`, `levels_display`, `operationalization`, `source`, and `role` to author a measurement bridge inside the Methods section. The bridge must pair every modeled variable's display label with operationalization-style language plus concrete measurement detail: whether the measure is binary, categorical, continuous, ordinal, a scale/index, a duration/count/rate, how it is coded, and which survey item, file, or construction rule supplies it. The Variables and Measures prose must visibly distinguish dependent variables/outcomes, independent variables/predictors/treatment/exposure, and control variables/covariates when those roles appear in the design. The gate `scripts/gates/concept-to-measure-check.sh` enforces ≥80% modeled-variable coverage and rejects repeated dictionary-template phrasing. (A common failure: the Methods section ignores these fields and names only broad construct categories.)

`measurement-plan.md` must describe measurement validity, missing data handling, sample restrictions, and access/IRB implications.

It must also discuss data provenance, data security, sharing constraints, dataset fit, key-variable coverage, post-treatment risks, and whether the data path is feasible for the target journal and project timeline.

It must also distinguish true missingness from structural skips, inapplicable items, top-coded values, negative special codes, and denominator-changing restrictions. When an outcome is bounded, skewed, zero-inflated, count-like, duration-like, or time-use-like, the measurement plan must name the outcome family so Phase 5 can plan an appropriate model ladder.

`data-measurement-manifest.json` must include:

- `verdict`: `PASS`
- `source_phase`: `4`
- `data_engine`: `{"skill": "scholar-data", ...}`
- `source_hashes`: hashes for safety status, design blueprint, design manifest, identification strategy, and model specs
- `output_hashes`: hashes for data status, variable dictionary, and measurement plan
- `dataset_fit`: object with verdict `PASS`
- `variable_coverage`: coverage of design measures and model variables
- `display_semantics`: object confirming reader-facing label coverage and translation readiness
- `codebook_validation`: object confirming that value labels, valid ranges, missing/special codes, skip logic, top codes, and measurement units were checked against source documentation or accepted as unavailable with rationale
- `dataset_design_review`: exact carried-forward review from `data-status.json`
- `outcome_family_screen`: object identifying whether planned outcomes are approximately continuous, bounded, skewed, zero-inflated, count-like, duration-like, or time-use-like, so Phase 5 can plan the right model ladder
- `safety_provenance`: scanned-file count and unresolved-risk count from Phase 0
- `post_treatment_review`: reviewed flag and unresolved count
- `ready_for_phase_5`: `true`

Phase 4 fails if existing data are claimed but data files/provenance are vague, the safety scan has no scanned files, Phase 3 measures are missing from the dictionary, model variables are missing, dataset fit is not `PASS`, codebook validation is missing, dataset-design review is missing for structured secondary data, or unresolved post-treatment-control risks remain.
