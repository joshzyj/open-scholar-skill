# Results Lock Contract

Phase 11 freezes verified analysis artifacts so drafting cannot drift from reviewed outputs.

Required files:

- `results-locked/LATEST.txt`
- `results-locked/manifest.json`
- `verify/stage1-verify.json`

Required inputs:

- `verify/runtime-sanity.json`
- `verify/runtime-sanity.md`
- `analysis/execution-report.json`
- `tables/results-registry.csv`
- `figures/figure-registry.csv`
- `review/post-execution-review.json`

`results-locked/manifest.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `lock_engine`: provenance object with `skill: scholar-auto-research`, `mode: results_lock`, `auto_research_contract: phase_11`, and `deterministic_lock: true`
- `lock_id`: stable non-placeholder ID
- `created_at`: timestamp string
- `source_hashes`: SHA-256 hashes for `runtime_sanity`, `runtime_sanity_md`, `execution_report`, `results_registry`, `figure_registry`, and `post_execution_review`
- `locked_artifacts`: list covering every Phase 10 `artifact_inventory` item with `source_path`, `locked_path`, `sha256`, `artifact_role`, and `lock_status`
- `manifest_sha256`: SHA-256 of the manifest content excluding the `manifest_sha256` field
- `latest_matches`: `true`
- `stage1_verdict`: `PASS`
- `ready_for_phase_12`: `true`

`results-locked/LATEST.txt` must contain exactly the active `lock_id` and a trailing newline.

Each locked artifact must be copied under `results-locked/<lock_id>/`; `locked_path` must point inside that active lock directory and `lock_status` must be `copied`. The verifier also reconstructs lock candidates from the current execution report, result registry, figure registry, and all files under `tables/` and `figures/`, then requires exact agreement with Phase 10 `artifact_inventory`, the manifest, and Stage 1 checks.

Allowed `artifact_role` values are: `runtime_sanity`, `execution_report`, `results_registry`, `result_table`, `model_output`, `main_regression_table`, `sensitivity_regression_table`, `regression_table`, `figure_registry`, `figure_file`, `post_execution_review`, and `diagnostic`.

`results_registry` is provenance-only by default. It is required for numeric verification and row-level traceability, but it is not a reader-facing empirical display and must not be promoted to a headline, main-text, final, or submission table. Quantitative empirical projects must lock at least one canonical regression-table artifact using `main_regression_table` or `regression_table`; sensitivity or appendix regression outputs should use `sensitivity_regression_table` or `regression_table`. Row-per-spec registries, model ladders, or focal-coefficient extracts remain trace artifacts even when they contain the same estimates used in prose. Internal specification IDs such as `S1` and `S2` may remain in lock metadata, but the locked publication table itself must use reader-facing model column labels such as `Model 1`/`Model 2` or `M1`/`M2`.

`verify/stage1-verify.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `lock_id`: same lock ID as the manifest and `LATEST.txt`
- `manifest_sha256`: same manifest hash as the manifest
- `input_manifest_sha256`: manifest hash used as the Stage 1 input
- `checked_artifacts`: all locked artifacts, each with source path, locked path, source hash, locked hash, and `verdict: PASS`
- `checked_count`: number of checked artifacts
- `missing_count`: `0`
- `mismatch_count`: `0`
- `extra_locked_count`: `0`
- `missing_paths`, `mismatch_paths`, `extra_locked_paths`: empty lists
- `scanner_provenance`: scanner name and verification timestamp
- `ready_for_phase_12`: `true`

`scanner_provenance` must identify Phase 11 explicitly with `scanner: auto-research-verify`, `mode: results_lock_stage1`, `auto_research_contract: phase_11`, and a verification timestamp. Each copy hash must equal the source hash. Source artifacts may not be used as their own locked copies.

Phase 11 fails if Phase 10 validation fails, if Phase 10 artifacts are stale, if lock-engine provenance is missing, if `LATEST.txt` points to a different lock, if the manifest omits any rebuilt lock candidate, if the active lock directory contains unmanifested files, if a locked copy differs from its source, if the manifest Stage 1 verdict disagrees with `verify/stage1-verify.json`, or if Stage 1 verification reports any missing, mismatch, or extra locked artifact.
