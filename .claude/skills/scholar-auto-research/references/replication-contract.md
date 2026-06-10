# Replication Contract

Phase 17 requires a replication mode:

- `public-data-full`: run package in a clean temp directory and compare outputs to locked results.
- `restricted-data-code-only`: provide access instructions, non-disclosive synthetic/test data, and executable schema/preprocessing checks.
- `synthetic-demo`: reproduce workflow behavior on synthetic data with clear non-equivalence statement.
- `no-data-conceptual`: provide rationale and nonempirical artifact package.

Folder shape is not enough. A package with only a README cannot pass for empirical article mode.

Required outputs:

- `replication-package/README.md`
- `replication-package/replication-report.json`
- `replication-package/MANIFEST.json`
- `replication-package/TEST-REPORT.md`
- `replication-package/VERIFICATION-REPORT.md`

`replication-package/replication-report.json` must include mode, clean-room verdict where applicable, lockfile/session info, seed capture, runtime expectation, reproduction match status, source hashes, package inventory, locked artifact coverage, script coverage, data handling, path safety, environment, test report, verification report, findings, route-back fields, and `ready_for_phase_18`.

PASS requires:

- `replication_engine.skill == scholar-replication` and `mode == FULL`.
- `replication_mode` matches Phase 16 `data_availability.sharing_mode`.
- `source_hashes` match `results-locked/manifest.json`, `results-locked/LATEST.txt`, `verify/stage1-verify.json`, `analysis/execution-report.json`, `ethics/ethics-open-science.json`, and `data/data-status.json`.
- `replication-package/MANIFEST.json` lists every package file with relative path, role, and SHA-256.
- `replication-package/MANIFEST.json` must exactly match the files present under `replication-package/`; no unlisted files, missing files, absolute paths, or `..` path escapes.
- README includes overview, data availability, dataset list, computational requirements, programs, instructions, output correspondence, limitations, and references.
- No package path is absolute and no package text contains local machine paths such as `/Users/`, `/tmp/`, or `C:\`.
- All active locked artifacts are either copied into the package or explicitly represented by restricted/synthetic/no-data instructions.
- For empirical modes, `script_coverage.scripts` must cover every Phase 8 `execution-report.json.executed_scripts[].path`, with matching `source_hash` values from the execution report.
- For `public-data-full`, clean-room verdict is `PASS`, reproduction match is true, and output comparison covers every reader-facing locked artifact.
- For `restricted-data-code-only`, restricted data are not bundled; restriction rationale, access instructions, and schema/synthetic validation must be present.
- For `synthetic-demo`, synthetic data and non-equivalence statements must be present.
- For `no-data-conceptual`, empirical clean-room tests are not required, but the rationale must be explicit.

FAIL route rules:

- Phase 4: data status/access/share-mode mismatch.
- Phase 8: execution report or produced output defect.
- Phase 11: stale or incomplete results lock.
- Phase 16: ethics/open-science data availability contradiction.
- Phase 17: same-phase README, manifest, path safety, clean-room, verification, or packaging defect.
