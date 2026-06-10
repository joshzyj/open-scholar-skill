# Post-Execution Review Contract

Phase 9 evaluates executed analysis outputs after Phase 8 and before runtime sanity checks. It must invoke `scholar-verify` Stage 1 in pre-draft/no-manuscript mode to compare raw output artifacts against the result and figure registries before any result becomes lockable evidence.

Required files:

- `review/post-execution-review.json`
- `review/post-execution-review.md`
- `review/post-execution-fix-log.json`

Required independent reviewer roles:

- `statistical_results`
- `robustness_consistency`
- `sample_data_integrity`
- `interpretation_claims`

`post-execution-review.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `decision`: `PROCEED_TO_RUNTIME_SANITY`
- `ready_for_phase_10`: `true`
- `review_engine`: object with `skill: scholar-verify`, `mode: stage1_no_manuscript`, `auto_research_contract: phase_9`, and `read_live_outputs_pre_lock: true`
- `source_hashes`: SHA-256 hashes for `spec_registry`, `analysis_premortem`, `execution_report`, `results_registry`, and `figure_registry`
- `phase7_constraint_carryforward`: object proving the Phase 7 null-falsification table and reporting-depth checklist were read and carried forward into interpretation constraints
- `raw_output_verification`: object with `verdict`, `stage`, `checked_raw_tables`, `checked_figures`, `registry_consistency`, `visual_figure_inspection`, `critical_count`, and `report_path`
- `reviewer_provenance`: list covering every reviewer, each with `reviewer_id`, `role`, `agent_name`, `task_invocation_id`, `dispatched_at_utc`, `model_id`, and `report_path`
- `phase8_status`: confirms Phase 8 `PASS`, `ready_for_phase_9: true`, and no errors
- `reviewers`: list covering all required roles, each with `reviewer_id`, `role`, `agent_type`, `task_invocation_id`, `report_path`, `reviewed_specs`, `reviewed_figures`, `findings`, and `verdict`
- `reviewed_specs`: all planned specs from `analysis/spec-registry.csv`, each with `spec_id`, `planned_direction`, `observed_direction`, `estimate`, `std_error`, `p_value`, `ci_low`, `ci_high`, `n`, `sample_id`, `technical_validity`, `substantive_classification`, `interpretation_constraint`, and `allowed_claim_verbs`
- `reviewed_figures`: all figure IDs from `figures/figure-registry.csv`
- `sample_integrity`: object with `verdict`, `initial_n`, `analytic_n`, `exclusion_count`, `missingness_checked`, `cluster_or_group_count`, `weights_status`, and `minimum_cell_count`
- `result_interpretation`: object with `technically_valid`, `direction_summary`, `strength_summary`, `uncertainty_summary`, and `claim_constraints`
- `robustness_assessment`: object with `verdict`, `conflicts`, and `interpretation_implications`
- `robustness_matrix`: list comparing primary and robustness specs, each with `primary_spec_id`, `comparison_spec_id`, `conflict_type`, `severity`, `adjudication`, and `manuscript_instruction`
- `unexpected_results`: list of null, opposite-sign, weak, or conflicting results, each with `spec_id`, `classification`, `action`, and `manuscript_instruction`
- `claim_constraints`: object with `allowed_claim_verbs`, `forbidden_claim_verbs`, and `required_disclosures`
- `critical_count`: `0`
- `unresolved_blocking_count`: `0`
- `fix_status`: object with `required`, `all_blocking_fixed`, and `fix_log`
- `route_back_phase`: `null`

Every `reviewed_specs` numeric field must match the corresponding row in `tables/results-registry.csv`. The post-execution review may add interpretation, classifications, confidence intervals, and claim constraints, but it may not change estimate, standard error, p-value, or sample size values.

Every `reviewed_figures` row for a completed figure must include `source_path`, `sha256`, `visual_inspection: true`, and a substantive `caption_or_registry_match` note. File existence is not enough.

`phase7_constraint_carryforward` must confirm that every hypothesis id represented in `analysis/spec-registry.csv` appears in the Phase 7 null-falsification table, that reporting-depth checklist items were considered, and that Phase 9 claim constraints reflect those constraints.

Unexpected or null results are not errors when execution and measurement are valid. They must be carried forward with interpretation constraints. Do not alter valid outputs to match expectations.

`decision` must be `PROCEED_TO_RUNTIME_SANITY` only when `critical_count` and `unresolved_blocking_count` are zero, `route_back_phase` is null, and `ready_for_phase_10` is true. If a real defect requires rerunning analysis or changing upstream design, use `decision: ROUTE_BACK`, set `route_back_phase`, and do not pass Phase 9.

Blocking defects include invalid numeric results, missing planned specs, failed Phase 8 tests, stale source hashes, impossible interpretation, unregistered figures, unsupported causal language, or sample/data defects that invalidate the analysis. Blocking defects must be fixed by routing back to the earliest affected phase or by repairing a Phase 9 review artifact when the analysis itself is sound.

`post-execution-fix-log.json` must include:

- `required_fixes_completed`: `true`
- `unresolved_blocking_count`: `0`
- `final_verdict`: `PASS`
- `fixed_findings`: list of fixed finding records

If no blocking findings were found, `fixed_findings` may be empty. If fixes were required, every fixed finding must include `finding_id`, `status`, `action_taken`, `affected_files`, and `owner_phase`.

Markdown summaries must not contradict JSON pass status. If markdown says a critical, blocking, or invalid result remains unresolved, Phase 9 fails even when JSON says `PASS`.
