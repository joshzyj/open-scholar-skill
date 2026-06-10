# Runtime Sanity Contract

Phase 10 is the final consistency gate before results are locked. It is not a desirability review; it is a deterministic anti-drift, anti-nonsense, and lock-candidate reconciliation gate over the already reviewed Phase 8/9 artifacts.

Required files:

- `verify/runtime-sanity.json`
- `verify/runtime-sanity.md`

Required inputs:

- `analysis/spec-registry.csv`
- `analysis/execution-report.json`
- `tables/results-registry.csv`
- `figures/figure-registry.csv`
- `review/post-execution-review.json`
- `review/post-execution-fix-log.json`

`runtime-sanity.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `decision`: `PROCEED_TO_RESULTS_LOCK`
- `ready_for_phase_11`: `true`
- `runtime_engine`: object with `skill: scholar-auto-research`, `mode: runtime_sanity`, `auto_research_contract: phase_10`, and `deterministic_gate: true`
- `source_hashes`: SHA-256 hashes for `spec_registry`, `execution_report`, `results_registry`, `figure_registry`, `post_execution_review`, and `post_execution_fix_log`
- `phase9_status`: confirms Phase 9 `PASS`, `decision: PROCEED_TO_RUNTIME_SANITY`, `ready_for_phase_10: true`, and zero unresolved blockers
- `phase9_constraint_carryforward`: object proving weak/null/unexpected-result classifications and Phase 9 claim constraints remain present in the runtime sanity decision
- `plausibility`: object with `verdict: PASS` and a non-empty `checks` list
- `clean_room`: object with `verdict: PASS`, `artifact_hashes`, `reviewed_artifacts_match: true`, and `run`
- `invariants`: object with `verdict: PASS` and required invariant checks
- `pap_drift`: object with `verdict: PASS`, planned spec IDs, executed spec IDs, and no unresolved drift
- `artifact_inventory`: lock-candidate artifact list for Phase 11
- `lock_candidate_reconciliation`: object proving Phase 10 lock candidates exactly match required execution/report/registry artifacts and the Phase 8 artifact manifest where applicable
- `critical_count`: `0`
- `unresolved_blocking_count`: `0`
- `route_back_phase`: `null`

Required plausibility check domains:

- `numeric_finite`
- `sample_size`
- `p_value_range`
- `effect_magnitude`
- `interpretation_constraints`

Required invariant checks:

- `planned_specs_equal_results`
- `execution_report_matches_registries`
- `expected_outputs_exist`
- `figure_registry_complete`
- `post_execution_review_current`
- `phase8_artifact_manifest_current`
- `phase9_constraints_current`

`clean_room.run` must include `mode`, `commands`, `exit_codes`, `input_hashes`, `output_hashes`, `numeric_tolerance`, `seed`, `session_info`, and `verdict: PASS`.

`pap_drift` must include `spec_fingerprints`: hashes of normalized `analysis/spec-registry.csv` rows keyed by `spec_id`.

`artifact_inventory` must include every result `output_file`, every completed figure path, the execution report, registries, and post-execution review artifacts. Files under `tables/` or `figures/` that are not lock candidates must have explicit exclusion records.

`lock_candidate_reconciliation` must include `status: PASS`, `required_paths`, `inventory_paths`, `extra_paths`, `missing_paths`, and `phase8_manifest_paths_checked`. `required_paths` and `inventory_paths` must match exactly except for explicit non-lock exclusions; `missing_paths` and `extra_paths` must be empty for a passing empirical project.

`phase9_constraint_carryforward` must include `unexpected_results_checked: true`, `claim_constraints_checked: true`, `forbidden_claim_verbs`, and `required_disclosures`. If Phase 9 classified any weak/null/opposite-sign/conflicting result, Phase 10 must not drop it from the sanity decision.

Runtime sanity does not decide whether a finding is desirable. Null, weak, or opposite-sign findings may pass when Phase 9 classified them and constrained interpretation. Runtime sanity fails only for stale artifacts, impossible values, missing registrations, unresolved drift, or contradictions between reviewed and lock-candidate outputs.

If `pap_drift.unresolved_drift_count` is greater than zero, Phase 10 must fail and route back to the earliest affected phase.
