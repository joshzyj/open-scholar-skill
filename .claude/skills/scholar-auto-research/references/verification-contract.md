# Verification Contract

Verification phases cannot pass by file existence alone.

Phase 14 `verify/manuscript-verification.json` must include:

- `verdict`: `PASS` or `FAIL`
- `degraded`: boolean
- `verification_engine`: object declaring `skill: scholar-verify`, `mode: full`, both stages enabled, active lock enforced, live output reads forbidden, and `agent_count: 4`
- `lock_id`: active Phase 11 lock ID
- `lock_manifest_sha256`: active lock manifest self-hash
- `source_hashes`: SHA-256 hashes for `manuscript`, `draft_manifest`, and `lock_manifest`
- `blueprint_hashes`: SHA-256 hashes for `manuscript/manuscript-blueprint.json`
- `scanned`: positive integer
- `critical_count`: integer
- `selected_manuscript_hash`: SHA-256
- `agent_reports`: list of report paths
- `agents`: four independent agent records for `verify-numerics`, `verify-figures`, `verify-logic`, and `verify-completeness`; each must include unique `task_invocation_id`, unique `report_path`, `agent_type`, input hashes, and role-specific `verification_scope`
- `input_artifacts_read`: every table/figure artifact read by scholar-verify, each under `results-locked/<lock_id>/`
- `stage_1_outputs_to_manuscript`: locked/raw outputs to manuscript table/figure/stat checks
- `blueprint_to_manuscript`: recomputed blueprint-execution checks covering headline claim, contribution order, hypothesis resolution, required disclosures, and result hierarchy preservation
- `stage_2_manuscript_to_prose`: manuscript table/figure/stat to prose-claim checks
- `lock_coverage`: coverage of all Phase 13 locked artifacts and proof that no live output reads were used
- `findings`: empty for PASS; nonempty structured findings for FAIL
- `fix_checklist`: empty critical fixes and empty route-back list for PASS
- `route_back_phase`: `null` for PASS; earliest phase to rerun for FAIL
- `ready_for_phase_15`: `true`

Any manuscript or blueprint edit after Phase 14 invalidates Phase 14 and downstream phases.

## Failure and Reroute Schema

If Phase 14 detects any error, it must write a structured `FAIL` report and stop. Do not continue to Phase 15.

Each `findings[]` entry must include:

- `finding_id`: stable unique ID
- `severity`: `CRITICAL`, `MAJOR`, or `WARNING`
- `category`: one of `draft_prose`, `manuscript_trace`, `locked_artifact_mismatch`, `lock_stale`, `analysis_output_error`, `post_execution_interpretation`, `design_issue`, `measurement_issue`, `analysis_plan_issue`, or `verification_process`
- `owner_phase`: phase responsible for the fix
- `route_back_phase`: earliest phase that must be rerun
- `detected_by`: one of the four verifier roles
- `affected_artifacts`: nonempty list of paths or manuscript locations
- `required_fix`: concrete fix instruction
- `status`: `open`

Deterministic reroute rules:

- Manuscript blueprint drift or whole-paper claim hierarchy error: route to Phase 12.
- Draft/prose, manuscript trace, citation placeholder, or unsupported manuscript display error: route to Phase 13.
- Locked artifact mismatch or stale lock: route to Phase 11, unless the lock is stale because Phase 10 artifacts changed.
- Post-execution interpretation or claim-constraint error: route to Phase 9.
- Analysis output or registry error: route to Phase 8.
- Analysis-plan mismatch: route to Phase 5.
- Measurement error: route to Phase 4.
- Design or identification error: route to Phase 3.
- Verification process failure only: route to Phase 14.

For `FAIL`, `ready_for_phase_15` must be `false`, `route_back_phase` must be set, and `fix_checklist.route_back` must be nonempty.

## Two-Stage Manuscript Verification

Stage 1 verifies locked outputs against manuscript displays:

- locked tables, figures, and statistics
- manuscript table and figure values
- sample sizes, coefficients, p-values, confidence intervals, labels, and units
- references from manuscript displays back to the results lock
- exact coverage of every Phase 13 reader-facing artifact in `manuscript/draft-manifest.json.locked_result_coverage`
- visual inspection evidence for every locked figure file
- no live `tables/` or `figures/` input paths outside the active lock

Stage 2 verifies manuscript displays and the approved blueprint against prose:

- blueprint-to-manuscript claim hierarchy, section obligations, and result emphasis
- direction and magnitude claims
- uncertainty and null findings
- causal language
- limitations and scope
- table/figure references in the Results and Discussion sections
- exact coverage of every Phase 13 row-level locked result claim in `manuscript/draft-manifest.json.locked_result_claims`
- exact claim IDs, row indexes, locked paths, numeric values, anchors, direction, uncertainty, causal-language, and Phase 9 constraint verdicts
- section-level substance: multi-paragraph Introduction, Literature/Theory, Methods, Results prose, and Discussion
- figure preservation: every Phase 13 reader-facing figure that is not `journal_exempt` must remain visibly represented in the downstream reader-facing manuscript route

Minimum JSON shape:

```json
{
  "verdict": "PASS",
  "degraded": false,
  "verification_engine": {
    "skill": "scholar-verify",
    "mode": "full",
    "stage_1": true,
    "stage_2": true,
    "lock_enforced": true,
    "live_output_reads_forbidden": true,
    "agent_count": 4
  },
  "lock_id": "LOCK-20260429-001",
  "lock_manifest_sha256": "<sha256>",
  "source_hashes": {
    "manuscript": "<sha256>",
    "draft_manifest": "<sha256>",
    "lock_manifest": "<sha256>"
  },
  "scanned": 2,
  "critical_count": 0,
  "selected_manuscript_hash": "<sha256>",
  "agent_reports": ["verify/agent-output-to-manuscript.md", "verify/agent-prose-consistency.md"],
  "agents": [
    {"role": "verify-numerics", "agent_id": "N1", "agent_type": "independent_scholar_verify_agent", "task_invocation_id": "phase13-numerics-001", "independent": true, "input_hashes": {"manuscript": "<sha256>", "draft_manifest": "<sha256>", "lock_manifest": "<sha256>"}, "report_path": "verify/agents/verify-numerics.md", "verdict": "PASS"},
    {"role": "verify-figures", "agent_id": "F1", "agent_type": "independent_scholar_verify_agent", "task_invocation_id": "phase13-figures-001", "independent": true, "input_hashes": {"manuscript": "<sha256>", "draft_manifest": "<sha256>", "lock_manifest": "<sha256>"}, "report_path": "verify/agents/verify-figures.md", "verdict": "PASS"},
    {"role": "verify-logic", "agent_id": "L1", "agent_type": "independent_scholar_verify_agent", "task_invocation_id": "phase13-logic-001", "independent": true, "input_hashes": {"manuscript": "<sha256>", "draft_manifest": "<sha256>", "lock_manifest": "<sha256>"}, "report_path": "verify/agents/verify-logic.md", "verdict": "PASS"},
    {"role": "verify-completeness", "agent_id": "C1", "agent_type": "independent_scholar_verify_agent", "task_invocation_id": "phase13-completeness-001", "independent": true, "input_hashes": {"manuscript": "<sha256>", "draft_manifest": "<sha256>", "lock_manifest": "<sha256>"}, "report_path": "verify/agents/verify-completeness.md", "verdict": "PASS"}
  ],
  "lock_coverage": {
    "lock_id": "LOCK-20260429-001",
    "all_locked_artifacts_accounted": true,
    "live_output_reads_detected": false,
    "covered_sources": ["tables/results-registry.csv"]
  },
  "findings": [],
  "input_artifacts_read": [
    {"path": "results-locked/LOCK-20260429-001/tables/results-registry.csv", "source_artifact": "tables/results-registry.csv", "sha256": "<sha256>"}
  ],
  "stage_1_outputs_to_manuscript": {
    "verdict": "PASS",
    "degraded": false,
    "items_scanned": 1,
    "critical_count": 0,
    "checked": [
      {
        "source_artifact": "tables/table1.csv",
        "locked_path": "results-locked/LOCK-20260429-001/tables/table1.csv",
        "manuscript_location": "Table 1",
        "manuscript_anchor": "<anchor text>",
        "visual_inspection": {"rendered": true, "caption_matches": true, "read_confirmed": "READ-CONFIRMED: results-locked/LOCK-20260429-001/figures/F1.png", "figure_sha256": "<sha256>", "rendered_dimensions": "800x600", "caption_claims_checked": ["caption claim"]},
        "check_type": "numeric_match",
        "verdict": "PASS"
      }
    ]
  },
  "stage_2_manuscript_to_prose": {
    "verdict": "PASS",
    "degraded": false,
    "claims_scanned": 1,
    "critical_count": 0,
    "checked": [
      {
        "manuscript_location": "Results paragraph 1",
        "referenced_artifact": "Table 1",
        "source_artifact": "tables/table1.csv",
        "locked_path": "results-locked/LOCK-20260429-001/tables/table1.csv",
        "claim_id": "tables/table1.csv#0:S1",
        "row_index": 0,
        "spec_id": "S1",
        "estimate": "-0.120",
        "std_error": "0.040",
        "p_value": "0.003",
        "n": "1200",
        "direction_verdict": "PASS",
        "uncertainty_verdict": "PASS",
        "causal_language_verdict": "PASS",
        "phase9_constraint_verdict": "PASS",
        "check_type": "prose_claim_match",
        "verdict": "PASS"
      }
    ]
  },
  "fix_checklist": {"critical_fixes": [], "route_back": []},
  "route_back_phase": null,
  "ready_for_phase_15": true
}
```

Phase 14 fails if either stage is missing, degraded, has zero scanned items, has any critical finding, has partial artifact or claim coverage, omits one of the four verifier agents, reports stale source hashes, reads live outputs instead of the lock, lacks required figure visual-inspection evidence, reports a blueprint/manuscript mismatch, reports a manuscript hash that differs from `manuscript/manuscript-draft.md`, or emits an unstructured failure without reroute fields.
Phase 14 also fails if the manuscript meets word-count minimums but still collapses key sections into single thin template paragraphs or if the Discussion does not visibly carry limitations/scope language required by the blueprint.

The four verifier roles must cover distinct surfaces:

- `verify-numerics`: `stage_1_numeric_values` and `stage_2_numeric_claims`
- `verify-figures`: `stage_1_visual_inspection` and `caption_claims`
- `verify-logic`: `stage_2_claim_scope` and `phase9_constraints`
- `verify-completeness`: `coverage` and `live_read_audit`

Phase 18 quality gate must score contribution, RQ answer, argument coherence, theory-results integration, limitation candor, journal fit, and abstract/introduction/discussion consistency.

## Codex cross-model review gate (added 2026-05-10)

Phase 14 verification runs `scripts/gates/codex-trigger-phase14.sh` after the four-agent verification + manuscript-blueprint alignment checks. The gate enforces the following rule whenever `SCHOLAR_CODEX_DEFAULT=true` (the default as of 2026-05-10) AND the `codex` CLI is on PATH:

- Either Codex full-mode artifacts must exist at `${PROJ}/reviews/codex/codex-review-consolidated-*.md` (or `${PROJ}/reviews/codex/A[4-5]-*.md` per-agent reports), OR
- The verification report must contain `[EXCUSED:codex-review: <reason>]` in `verify/manuscript-verification.md` (or any string-valued field in `verify/manuscript-verification.json`).

If neither is satisfied, the gate emits `STATUS=RED` and Phase 14 verification fails.

Verdict matrix is the same as the Phase 6 gate (see `pre-execution-review-contract.md`).

Opt-out paths:

- Per shell: `export SCHOLAR_CODEX_DEFAULT=false`
- Per phase: append `[EXCUSED:codex-review: <reason>]` to `verify/manuscript-verification.md`.

When not excused, dispatch via `/scholar-openai full <manuscript-path>`. The `full` mode runs the consolidated A1–A5 agent panel (numerics + figures + logic + completeness + senior synthesizer) and saves the consolidated report under `${PROJ}/reviews/codex/`.

The gate is **self-contained** within scholar-auto-research: it does not depend on the parent `scholar-skill/scripts/gates/` directory.
