# Pre-Execution Review Contract

Phase 6 reviews planned analysis scripts and specifications before any execution. It must invoke `scholar-code-review` in a pre-execution planned-script mode. This is a review gate only; it must not execute analysis scripts.

Required inputs:

- `analysis/analysis-plan.md`
- `analysis/analysis-plan-manifest.json`
- `analysis/scripts-inventory.json`
- `analysis/spec-registry.csv`
- `design/identification-strategy.json`
- `design/model-specs.json`
- `data/variable-dictionary.csv`
- `data/data-measurement-manifest.json`

Required files:

- `review/pre-execution-review.json`
- `review/pre-execution-review.md`
- `review/pre-execution-fix-log.json`
- `review/pre-execution-fix-log.md`
- `review/pre-execution-rereview.json`

The review process must use multiple independent reviewers. Minimum required roles mirror the useful `scholar-code-review` lenses:

- `correctness`
- `robustness`
- `statistical`
- `reproducibility`
- `style_ai_patterns`
- `data_handling`

## Review-Fix-Rereview Loop

Phase 6 has five functions:

1. `dispatch_reviewers`: run six independent reviewers through `scholar-code-review` pre-execution mode against the same current `analysis/analysis-plan-manifest.json`, `analysis/scripts-inventory.json`, `analysis/spec-registry.csv`, planned scripts, planned tests, design artifacts, and data-measurement artifacts.
2. `collect_findings`: merge reviewer reports into a blocker list. Treat `BLOCKER`, `CRITICAL`, `MAJOR`, stale inventory, missing review coverage, unsafe raw-data exposure, and impossible execution paths as blocking.
3. `apply_phase6_fixes`: fix blockers before Phase 6 completes. Valid Phase 6 fixes include planned-script edits, test-inventory corrections, path/output repairs, reproducibility repairs, and data-safety repairs. If the fix changes the research question, literature/theory, design, data plan, or analysis plan, route back to the earliest affected phase.
4. `record_fix_log`: write every fixed blocker to `review/pre-execution-fix-log.json` and summarize it in `review/pre-execution-fix-log.md`.
5. `dispatch_rereview`: re-review every fixed blocker and write `review/pre-execution-rereview.json`.

Do not advance to Phase 7 with unresolved Phase 6 blockers. The next phase is not the repair mechanism for pre-execution defects.

The final `pre-execution-review.json` is a final-state artifact. It may summarize first-round findings, but it must be written only after blockers are fixed and re-reviewed. First-round reviewer details live in each `report_path` under `review/agents/`.

`pre-execution-review.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `review_engine`: `{"skill": "scholar-code-review", "mode": "pre_execution_planned"}`
- `source_hashes`: hashes for analysis plan, analysis-plan manifest, scripts inventory, spec registry, identification strategy, model specs, variable dictionary, and data-measurement manifest
- `inventory_hash`: SHA-256 hash of `analysis/scripts-inventory.json`
- `ready_for_phase_7`: `true`
- `reviewers`: list covering all required roles, each with `reviewer_id`, `role`, `agent_type`, `task_invocation_id`, `report_path`, `reviewed_scripts`, `reviewed_specs`, `reviewed_tests`, `reviewed_upstream_artifacts`, `findings`, and `verdict`
- `reviewed_scripts`: all planned scripts from `analysis/scripts-inventory.json`; each script must record `path`, `status_in_inventory`, `exists_or_stub_declared`, and `reviewed_by`
- `reviewed_tests`: all planned tests from `analysis/scripts-inventory.json`
- `reviewed_specs`: all specs from `analysis/spec-registry.csv` when present
- `reviewed_script_dag`: confirms `script_order` and `dependency_graph` were reviewed
- `reviewed_spec_coverage`: confirms Phase 5 model and hypothesis coverage were reviewed
- `reviewed_robustness_coverage`: confirms Phase 3 robustness promises were reviewed against planned specs
- `reviewed_missing_data_alignment`: confirms Phase 5 missing-data alignment was reviewed against Phase 4
- `reviewed_no_execution_boundary`: confirms no execution artifacts or executed-script statuses are present
- `blocking_findings`: empty final list
- `unresolved_critical_count`: `0`
- `fix_status`: object with `required`, `all_blocking_fixed`, `fix_log`, and `rereview`

Every planned script, test, spec, and required upstream artifact must be reviewed by all six required roles. Reviewer IDs and task invocation IDs must be unique and non-placeholder. Each `report_path` must point to an existing reviewer report inside the project.

`pre-execution-fix-log.json` must include:

- `required_fixes_completed`: `true`
- `unfixed_blocking_count`: `0`
- `final_verdict`: `PASS`
- `fixed_findings`: list of fixed finding records

If no blocking findings were found, `fixed_findings` may be empty. If blocking findings were found during the first review, every fixed finding must include `finding_id`, `status`, `action_taken`, and `affected_files`. Accepted limitations are not allowed for executable blockers.

Example fixed finding:

```json
{
  "finding_id": "PX-code-001",
  "status": "fixed",
  "blocker_type": "executable",
  "action_taken": "Added required output path and pre-run assertions to the planned model script.",
  "affected_files": ["analysis/scripts/02_models.R", "analysis/scripts-inventory.json"]
}
```

`pre-execution-rereview.json` must include:

- `verdict`: `PASS`
- `degraded`: `false`
- `unresolved_blocking_count`: `0`
- `ready_for_phase_7`: `true`
- `rereviewed_findings`: all fixed blocking findings, each with `finding_id` and `resolution_verdict: RESOLVED`

Example re-review finding:

```json
{
  "finding_id": "PX-code-001",
  "original_role": "code",
  "resolution_verdict": "RESOLVED",
  "evidence_checked": ["analysis/scripts/02_models.R", "analysis/scripts-inventory.json"]
}
```

Phase 6 fails if any execution artifacts already exist. Execution belongs to Phase 8.

Markdown summaries must not contradict JSON pass status. If the markdown says a critical or blocking issue remains unresolved, Phase 6 fails even when JSON says `PASS`.

## Codex cross-model review gate (added 2026-05-10)

Phase 6 verification runs `scripts/gates/codex-trigger-phase6.sh` after the JSON/markdown integrity checks. The gate enforces the following rule whenever `SCHOLAR_CODEX_DEFAULT=true` (the default as of 2026-05-10) AND the `codex` CLI is on PATH:

- Either Codex code-mode artifacts must exist under `${PROJ}/reviews/codex/A[1-3]-*.md` (canonical layout for `/scholar-openai code` runs), OR
- The phase report must contain the literal annotation `[EXCUSED:codex-review: <reason>]` in `review/pre-execution-review.md` (or any string-valued field in `review/pre-execution-review.json`).

If neither is satisfied, the gate emits `STATUS=RED` and Phase 6 verification fails.

Verdict matrix:

| `SCHOLAR_CODEX_DEFAULT` | codex CLI | artifacts | excuse | verdict |
|:-----------------------:|:---------:|:---------:|:------:|:--------|
| true (default)          | present   | present   | —      | GREEN (fired) |
| true (default)          | present   | absent    | present | GREEN (excused) |
| true (default)          | present   | absent    | absent | RED (strong trigger, no dispatch) |
| true (default)          | missing   | —         | —      | YELLOW (cannot fire) |
| false                   | —         | —         | —      | GREEN (no trigger) |

Opt-out paths:

- Per shell: `export SCHOLAR_CODEX_DEFAULT=false`
- Per phase: append `[EXCUSED:codex-review: codex CLI not available]` (or any reason ≤ 200 chars) to `review/pre-execution-review.md`.

When not excused, dispatch via `/scholar-openai code <manuscript-path> <scripts-dir>`. The `code` mode runs three Codex agents (A1 correctness, A2 robustness, A3 statistics) and saves reports under `${PROJ}/reviews/codex/`.

The gate is **self-contained** within scholar-auto-research: it does not depend on the parent `scholar-skill/scripts/gates/` directory. The phase wrapper calls a sibling `codex-trigger-check.sh` in the same `skills/scholar-auto-research/scripts/gates/` dir.
