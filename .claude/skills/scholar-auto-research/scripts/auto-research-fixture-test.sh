#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$SKILL_DIR/tests/helpers/harness.sh"
CASE_RESULT="$SKILL_DIR/tests/helpers/case_result.py"
MANIFEST="$SKILL_DIR/tests/coverage-manifest.json"
source "$HARNESS"

# The heavy fixture is its own coordinator when no release coordinator has
# already supplied bindings.  Every default is computed from this finalized
# skill tree; caller-supplied bindings are verified rather than overwritten.
SCHOLAR_KEEP_FIXTURE="${SCHOLAR_KEEP_FIXTURE:-${KEEP_FIXTURE_TMP:-0}}"
export SCHOLAR_KEEP_FIXTURE
harness_make_temp_root TMP "scholar-auto-research-fixture"
SCHOLAR_HARNESS_SOURCE_ROOT="${SCHOLAR_HARNESS_SOURCE_ROOT:-$SKILL_DIR}"
SCHOLAR_HARNESS_MANIFEST="${SCHOLAR_HARNESS_MANIFEST:-$MANIFEST}"
SCHOLAR_HARNESS_RESULTS_DIR="${SCHOLAR_HARNESS_RESULTS_DIR:-$TMP/harness-results}"
SCHOLAR_HARNESS_RUN_ID="${SCHOLAR_HARNESS_RUN_ID:-fixture-$$}"
SCHOLAR_HARNESS_RUN_NONCE="${SCHOLAR_HARNESS_RUN_NONCE:-$(python3 -c 'import secrets; print(secrets.token_hex(32))')}"
SCHOLAR_HARNESS_SUITE_MODE="${SCHOLAR_HARNESS_SUITE_MODE:-heavy-only}"
SCHOLAR_HARNESS_SUITE_ORDER="${SCHOLAR_HARNESS_SUITE_ORDER:-normal}"
SCHOLAR_HARNESS_MANIFEST_SHA256="${SCHOLAR_HARNESS_MANIFEST_SHA256:-$(python3 "$CASE_RESULT" digest-file "$SCHOLAR_HARNESS_MANIFEST")}"
SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="${SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256:-$(python3 "$CASE_RESULT" source-digest "$SCHOLAR_HARNESS_SOURCE_ROOT")}"
export SCHOLAR_HARNESS_SOURCE_ROOT SCHOLAR_HARNESS_MANIFEST
export SCHOLAR_HARNESS_RESULTS_DIR SCHOLAR_HARNESS_RUN_ID SCHOLAR_HARNESS_RUN_NONCE
export SCHOLAR_HARNESS_SUITE_MODE SCHOLAR_HARNESS_SUITE_ORDER
export SCHOLAR_HARNESS_MANIFEST_SHA256 SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256
harness_init "$SCRIPT_DIR/auto-research-fixture-test.sh" "fixture-test"

PROJ="$TMP/project"
START_TS="$(date +%s)"

# Optional provider-diversity lanes are tested separately; the portable review
# evidence requirement is exercised directly throughout this fixture.

progress() {
  printf '[fixture] %s\n' "$1"
}

single_review_session_dir() {
  # single_review_session_dir <fixture-project> <zero-padded-phase>
  local project="$1" phase="$2"
  local candidates=("$project/review-evidence/phase-$phase"/s-*)
  if [ "${#candidates[@]}" -ne 1 ] || [ ! -d "${candidates[0]}" ]; then
    fail "expected exactly one source review session for phase $phase in $project"
    return 1
  fi
  printf '%s\n' "${candidates[0]}"
}

copy_review_role_evidence() {
  # Bind reusable fixture prose to the destination production reservation.
  python3 - "$1" "$2" "$3" <<'PY'
import json
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:3])
role = sys.argv[3]
source_session = json.loads((source / "session.json").read_text())
destination_session = json.loads((destination / "session.json").read_text())

def reservation(session):
    matches = [item for item in session["reservations"] if item.get("role") == role]
    if len(matches) != 1:
        raise SystemExit(f"expected one {role} reservation, observed {len(matches)}")
    return matches[0]

old = reservation(source_session)
new = reservation(destination_session)
for subdir, suffix in (("reports", ".md"), ("traces", ".trace.ndjson")):
    source_path = source / subdir / f"{role}{suffix}"
    destination_path = destination / subdir / f"{role}{suffix}"
    text = source_path.read_text(encoding="utf-8")
    text = text.replace(source.name, destination.name)
    text = text.replace(str(old["dispatch_id"]), str(new["dispatch_id"]))
    destination_path.write_text(text, encoding="utf-8")
PY
}

assert_import_fixture_source() {
  local project="$1" expected_json="$2"
  shift 2
  python3 - "$project" "$expected_json" "$@" <<'PY'
import json
import os
from pathlib import Path
import stat
import sys

project = Path(sys.argv[1])
expected = json.loads(sys.argv[2])
declared_files = set(sys.argv[3:])
sidecar = project / ".claude/safety-status.json"
if sidecar.is_symlink() or not stat.S_ISREG(os.lstat(sidecar).st_mode):
    raise SystemExit("fixture import sidecar must be a regular non-symlink file")
observed = json.loads(sidecar.read_text(encoding="utf-8"))
if observed != expected:
    raise SystemExit("fixture import sidecar does not match its exact declared source")
data_keys = {key for key in expected if not key.startswith("_")}
if declared_files != data_keys:
    raise SystemExit("fixture import source file declaration does not match sidecar data keys")
for relative in sorted(declared_files):
    source = project / relative
    if source.is_symlink() or not stat.S_ISREG(os.lstat(source).st_mode):
        raise SystemExit(f"fixture import source is not a regular non-symlink file: {relative}")
PY
}

rebind_execution_fixture_root() {
  python3 - "$1/analysis/execution-report.json" "$1" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["run_context"]["working_directory"] = sys.argv[2]
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
}

# Fixture-only dependency rebinding for Phase 10 mutations.  This updates the
# hashes that honestly follow from current project bytes; it never changes a
# verdict or computes whether Phase 10 should pass.  A named clean-room key may
# be left stale when that attestation is the invariant under test.
rebind_phase10_fixture_hashes() {
  python3 - "$1" "${2:-}" <<'PY'
import hashlib
import json
import pathlib
import sys

proj = pathlib.Path(sys.argv[1])
stale_clean_room_key = sys.argv[2]

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def load(relative):
    return json.loads((proj / relative).read_text(encoding="utf-8"))

def write(relative, document):
    (proj / relative).write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

execution = load("analysis/execution-report.json")
for script in execution.get("executed_scripts", []):
    if not isinstance(script, dict) or not isinstance(script.get("output_hashes"), dict):
        continue
    for relative in list(script["output_hashes"]):
        path = proj / relative
        if path.is_file():
            script["output_hashes"][relative] = sha(path)
for item in execution.get("artifact_manifest", []):
    if not isinstance(item, dict):
        continue
    relative = str(item.get("path", "")).strip()
    path = proj / relative
    if relative and path.is_file():
        item["sha256"] = sha(path)
write("analysis/execution-report.json", execution)

post_review = load("review/post-execution-review.json")
post_sources = {
    "spec_registry": "analysis/spec-registry.csv",
    "execution_report": "analysis/execution-report.json",
    "results_registry": "tables/results-registry.csv",
    "figure_registry": "figures/figure-registry.csv",
    "analysis_premortem": "review/analysis-premortem.json",
}
for key, relative in post_sources.items():
    path = proj / relative
    if path.is_file():
        post_review["source_hashes"][key] = sha(path)
write("review/post-execution-review.json", post_review)

sanity = load("verify/runtime-sanity.json")
phase10_sources = {
    "spec_registry": "analysis/spec-registry.csv",
    "execution_report": "analysis/execution-report.json",
    "results_registry": "tables/results-registry.csv",
    "figure_registry": "figures/figure-registry.csv",
    "post_execution_review": "review/post-execution-review.json",
    "post_execution_fix_log": "review/post-execution-fix-log.json",
}
current = {key: sha(proj / relative) for key, relative in phase10_sources.items()}
sanity["source_hashes"].update(current)
for key, digest in current.items():
    if key != stale_clean_room_key:
        sanity["clean_room"]["artifact_hashes"][key] = digest

clean_run = sanity["clean_room"]["run"]
if "spec_registry" in clean_run.get("input_hashes", {}):
    clean_run["input_hashes"]["spec_registry"] = current["spec_registry"]
if "post_execution_review" in clean_run.get("input_hashes", {}):
    clean_run["input_hashes"]["post_execution_review"] = current["post_execution_review"]
for relative in list(clean_run.get("output_hashes", {})):
    path = proj / relative
    if path.is_file():
        clean_run["output_hashes"][relative] = sha(path)
for item in sanity.get("artifact_inventory", []):
    if not isinstance(item, dict):
        continue
    relative = str(item.get("path", "")).strip()
    path = proj / relative
    if relative and path.is_file():
        item["sha256"] = sha(path)
write("verify/runtime-sanity.json", sanity)
PY
}

CONTRACT_JSON="$SKILL_DIR/references/phase-contract.json"
SEED_PHASE="$SKILL_DIR/tests/helpers/seed-completed-phase.py"
REGISTER_REVIEW="$SKILL_DIR/tests/helpers/register-review-evidence-fixture.py"
complete_sm() {  # test-only state fixture; completion authority is tested separately
  local proj="$1" phase="$2"; shift 2
  python3 "$SEED_PHASE" "$CONTRACT_JSON" "$proj" "$phase" "$@"
}

bash "$SCRIPT_DIR/auto-research-contract-lint.sh"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$PROJ" autonomous "fixture autonomous" >/dev/null
progress "initialized fixture workspace at $TMP"

NEXT="$(bash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ")"
case "$NEXT" in
  *"NEXT_PHASE=0"*) ;;
  *) echo "FAIL: expected NEXT_PHASE=0 after init, got $NEXT" >&2; exit 1 ;;
esac

mkdir -p "$PROJ/safety"
printf '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$PROJ/safety/safety-status.json"
# 2026-05-25: Phase 0 verify now requires the auto-managed CLAUDE.md marker
# block (workflow-contract: principles + operational rules). The setup
# script writes it idempotently per the SKILL.md Phase 0 step 5.
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$PROJ" >/dev/null
# CASE_ID: phase.0.positive
expect_pass phase.0.positive "$PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$PROJ"
# CASE_ID: l2.p0.state.complete
expect_pass l2.p0.state.complete "$PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$PROJ" 0 "$PROJ/safety/safety-status.json"

NEXT="$(bash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ")"
case "$NEXT" in
  *"NEXT_PHASE=1"*) ;;
  *) echo "FAIL: expected NEXT_PHASE=1 after completing 0, got $NEXT" >&2; exit 1 ;;
esac

# CASE_ID: l2.p1.reject.missing-outputs
expect_reject l2.p1.reject.missing-outputs "$PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$PROJ"

BAD_PHASE0_STATUS_PROJ="$TMP/bad-phase0-status-project"
mkdir -p "$BAD_PHASE0_STATUS_PROJ/safety" "$BAD_PHASE0_STATUS_PROJ/data/raw"
printf 'id\n1\n' > "$BAD_PHASE0_STATUS_PROJ/data/raw/a.csv"
printf '{"files_scanned":1,"no_data_declared":false,"high_risk_unresolved":0,"status_by_file":{"data/raw/a.csv":{"source_status":"CLEARED","category":"cleared"}}}\n' > "$BAD_PHASE0_STATUS_PROJ/safety/safety-status.json"
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$BAD_PHASE0_STATUS_PROJ" >/dev/null
# CASE_ID: phase.0.negative
expect_reject phase.0.negative "$BAD_PHASE0_STATUS_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$BAD_PHASE0_STATUS_PROJ"

progress "phase 1 question-formation fixtures"

RQ_PROJ="$TMP/rq-project"
mkdir -p "$RQ_PROJ/idea"
cat > "$RQ_PROJ/idea/research-question.json" <<'JSON'
{
  "verdict": "PASS",
  "engine": "scholar-idea",
  "engine_provenance": {
    "task_invocation_id": "phase1-idea-001",
    "invoked_at_utc": "2026-04-28T08:00:00Z",
    "input_artifacts": ["idea/topic-brief.txt"],
    "output_artifacts": [
      "idea/candidate-rqs.json",
      "idea/journal-fit.json",
      "idea/research-question.json",
      "idea/research-question.md"
    ]
  },
  "input_mode": "idea",
  "selected_rq_id": "RQ1",
  "selected_rq": "Among low-income United States households with adolescent children, what is the association between parental job loss and adolescent educational expectations?",
  "x": "parental job loss",
  "y": "adolescent educational expectations",
  "directional_relation": "negative",
  "mechanism": "income shock and household stress reduce perceived educational feasibility",
  "confounders": ["prior household income", "parental education", "baseline academic performance"],
  "scope": {
    "population": "low-income households with adolescent children",
    "place": "United States",
    "time": "contemporary household panel period",
    "unit": "adolescent-year"
  },
  "target_journal": {
    "primary": "Journal of Marriage and Family",
    "journal_family": "family sociology",
    "fit_rationale": "The question connects family economic instability to adolescent expectations with a family-process mechanism.",
    "method_bar": "transparent observational design with panel controls, robustness checks, and cautious associational language",
    "theory_bar": "clear family stress and status-attainment mechanism with explicit scope conditions",
    "desk_reject_risks": ["novelty must be distinguished from generic family stress replications"]
  },
  "paper_type": "research note",
  "method_orientation": "observational panel analysis",
  "recommended_dataset": "Panel Study of Income Dynamics Child Development Supplement",
  "claim_strength": "associational",
  "rationale": "The question links labor-market instability to intergenerational educational inequality and is testable with household panel data while preserving cautious associational language.",
  "selection_evidence": {
    "candidate_count": 3,
    "panel_consensus": "strong",
    "fatal_flaw": false,
    "data_feasible": true,
    "novelty_risk": "medium",
    "journal_fit": "strong"
  },
  "ready_for_phase_2": true
}
JSON
cat > "$RQ_PROJ/idea/candidate-rqs.json" <<'JSON'
{
  "verdict": "PASS",
  "engine": "scholar-idea",
  "input_mode": "idea",
  "candidates": [
    {
      "rq_id": "RQ1",
      "question": "Among low-income United States households with adolescent children, what is the association between parental job loss and adolescent educational expectations?",
      "x": "parental job loss",
      "y": "adolescent educational expectations",
      "mechanism": "income shock and household stress reduce perceived educational feasibility",
      "confounders": ["prior household income", "parental education", "baseline academic performance"],
      "scope": {"population": "low-income households with adolescent children", "place": "United States", "time": "contemporary household panel period", "unit": "adolescent-year"},
      "claim_strength": "associational",
      "recommended_dataset": "Panel Study of Income Dynamics Child Development Supplement",
      "novelty_risk": "medium",
      "data_feasible": true,
      "fatal_flaw": false
    },
    {
      "rq_id": "RQ2",
      "question": "Among United States adolescents, how are parental work-hour instability and school engagement associated across the school year?",
      "x": "parental work-hour instability",
      "y": "school engagement",
      "mechanism": "schedule volatility reduces parental monitoring and routine stability",
      "confounders": ["industry", "prior engagement", "household income"],
      "scope": {"population": "United States adolescents", "place": "United States", "time": "school-year panel period", "unit": "student-year"},
      "claim_strength": "associational",
      "recommended_dataset": "NLSY97 linked youth survey",
      "novelty_risk": "medium",
      "data_feasible": true,
      "fatal_flaw": false
    },
    {
      "rq_id": "RQ3",
      "question": "Among families experiencing income shocks, how do parental expectations mediate adolescents' expectations for college completion?",
      "x": "family income shock",
      "y": "adolescent college completion expectations",
      "mechanism": "parental expectations transmit perceived feasibility to adolescents",
      "confounders": ["wealth", "parental education", "school context"],
      "scope": {"population": "families with adolescents", "place": "United States", "time": "longitudinal survey period", "unit": "family-year"},
      "claim_strength": "associational",
      "recommended_dataset": "Add Health",
      "novelty_risk": "high",
      "data_feasible": true,
      "fatal_flaw": false
    }
  ]
}
JSON
cat > "$RQ_PROJ/idea/rq-evaluation-panel.json" <<'JSON'
{
  "verdict": "PASS",
  "selected_rq_id": "RQ1",
  "fatal_flaw_selected": false,
  "ready_for_selection": true,
  "reviewers": [
    {"role": "theorist", "verdict": "PASS", "rank_order": ["RQ1", "RQ3", "RQ2"]},
    {"role": "methodologist", "verdict": "PASS", "rank_order": ["RQ1", "RQ2", "RQ3"]},
    {"role": "domain_expert", "verdict": "PASS", "rank_order": ["RQ1", "RQ3", "RQ2"]},
    {"role": "journal_editor", "verdict": "PASS", "rank_order": ["RQ1", "RQ2", "RQ3"]},
    {"role": "devils_advocate", "verdict": "PASS", "viability": "VIABLE", "rank_order": ["RQ1", "RQ2", "RQ3"]}
  ],
  "consensus": {"top_pick": "RQ1", "panel_consensus": "strong"}
}
JSON
cat > "$RQ_PROJ/idea/journal-fit.json" <<'JSON'
{
  "verdict": "PASS",
  "target_source": "inferred",
  "selected_rq_id": "RQ1",
  "primary_target": "Journal of Marriage and Family",
  "journal_family": "family sociology",
  "paper_type": "research note",
  "journal_profile_resolution": {
    "requested_journal": "Journal of Marriage and Family",
    "resolved_profile_name": "Journal of Marriage and Family",
    "profile_origin": "built_in",
    "profile_source_engine": "scholar-journal",
    "source_strategy": "built_in_catalog",
    "web_lookup_attempted": false,
    "fallback_used": false,
    "fallback_reason": "",
    "journal_structure": {
      "profile_source": "scholar-journal:jmf",
      "section_sequence": ["Abstract", "Introduction", "Background", "Data and Methods", "Results", "Discussion", "Conclusion", "References", "Tables", "Figures"],
      "results_before_methods": false,
      "theory_presentation": "background_section",
      "methods_section_label": "Data and Methods",
      "discussion_conclusion_policy": "split_required",
      "supplement_policy": "journal_optional_appendix"
    },
    "display_architecture": {
      "table_placement_policy": "end_matter_after_references",
      "figure_placement_policy": "separate_files_after_tables",
      "descriptive_table_requirement": "journal_optional",
      "editable_text_tables": true,
      "image_tables_forbidden": true,
      "main_text_display_cap": null,
      "main_text_table_cap": null,
      "main_text_figure_cap": null,
      "supplement_label_prefix": "Appendix",
      "panel_label_style": "A_B_C",
      "table_rendering_mode": "editable_text_end_matter",
      "figure_rendering_mode": "separate_figure_files",
      "table_title_position": "above_table",
      "table_notes_policy": "below_table_notes",
      "display_callout_style": "numbered_tables_and_figures"
    }
  },
  "candidates": [
    {"rq_id": "RQ1", "primary_target": "Journal of Marriage and Family", "fit_score": 8, "fit_dimensions": {"audience": "strong", "theory": "strong", "method": "adequate", "contribution": "strong"}, "desk_reject_risks": ["novelty must be stated precisely"], "recommended": true},
    {"rq_id": "RQ2", "primary_target": "Journal of Marriage and Family", "fit_score": 7, "fit_dimensions": {"audience": "adequate", "theory": "adequate", "method": "adequate", "contribution": "adequate"}, "desk_reject_risks": ["measurement may be indirect"], "recommended": false},
    {"rq_id": "RQ3", "primary_target": "Journal of Marriage and Family", "fit_score": 7, "fit_dimensions": {"audience": "adequate", "theory": "strong", "method": "adequate", "contribution": "adequate"}, "desk_reject_risks": ["mediation evidence may be weak"], "recommended": false}
  ],
  "ready_for_phase_2": true
}
JSON
cat > "$RQ_PROJ/idea/rq-selection-rationale.md" <<'MD'
# RQ Selection Rationale

RQ1 was selected because it has the clearest connection between family economic instability, adolescent expectations, and a family-process mechanism. The theorist and domain expert ranked it first because it links family stress and status-attainment perspectives without requiring an implausible causal claim. The methodologist ranked it first because household panel data can observe parental job loss, adolescent expectations, and relevant baseline covariates. The journal editor judged the question a strong fit for Journal of Marriage and Family because it speaks to family instability, inequality, and adolescent development. The devil's advocate did not identify a fatal flaw, but flagged novelty as the main risk, so the selected question is framed as an associational panel study with explicit scope conditions rather than an overclaimed causal paper.
MD
cat > "$RQ_PROJ/idea/research-question.md" <<'MD'
# Research Question

Selected question: Among low-income United States households with adolescent children, what is the association between parental job loss and adolescent educational expectations?

The question uses parental job loss as the focal exposure and adolescent educational expectations as the outcome. It is framed for the Journal of Marriage and Family as an empirical article using cautious associational language, a family stress mechanism, and household panel data.
MD
# CASE_ID: phase.1.positive
expect_pass phase.1.positive "$RQ_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$RQ_PROJ"

CUSTOM_RQ_PROJ="$TMP/custom-rq-project"
cp -R "$RQ_PROJ" "$CUSTOM_RQ_PROJ"
python3 - "$CUSTOM_RQ_PROJ" <<'PY'
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
rq_path = proj / "idea/research-question.json"
jf_path = proj / "idea/journal-fit.json"
rq = json.loads(rq_path.read_text())
jf = json.loads(jf_path.read_text())
requested = "Annual Review of Digital Sociology"
rq["target_journal"]["primary"] = requested
rq["target_journal"]["journal_family"] = "digital sociology"
rq["target_journal"]["fit_rationale"] = "The paper fits a digital-society venue that accommodates family-process questions with computationally adjacent evidence."
rq["target_journal"]["method_bar"] = "transparent observational design with strong substantive framing"
rq["target_journal"]["theory_bar"] = "clear family-process mechanism linked to digital inequality debates"
rq["target_journal"]["desk_reject_risks"] = ["venue profile must be imported rather than assumed"]
jf["target_source"] = "user_provided"
jf["primary_target"] = requested
jf["journal_family"] = "digital sociology"
jf["journal_profile_resolution"] = {
    "requested_journal": requested,
    "resolved_profile_name": requested,
    "profile_origin": "imported_custom",
    "profile_source_engine": "scholar-journal",
    "source_strategy": "web_fetched_profile",
    "web_lookup_attempted": True,
    "fallback_used": False,
    "fallback_reason": "",
    "journal_structure": {
        "profile_source": "scholar-journal:imported-custom",
        "section_sequence": ["Abstract", "Introduction", "Background", "Data and Methods", "Results", "Discussion", "Conclusion", "References", "Tables", "Figures"],
        "results_before_methods": False,
        "theory_presentation": "background_section",
        "methods_section_label": "Data and Methods",
        "discussion_conclusion_policy": "split_required",
        "supplement_policy": "journal_optional_appendix"
    },
    "display_architecture": {
        "table_placement_policy": "end_matter_after_references",
        "figure_placement_policy": "separate_files_after_tables",
        "descriptive_table_requirement": "journal_optional",
        "editable_text_tables": True,
        "image_tables_forbidden": True,
        "main_text_display_cap": None,
        "main_text_table_cap": None,
        "main_text_figure_cap": None,
        "supplement_label_prefix": "Appendix",
        "panel_label_style": "A_B_C",
        "table_rendering_mode": "editable_text_end_matter",
        "figure_rendering_mode": "separate_figure_files",
        "table_title_position": "above_table",
        "table_notes_policy": "below_table_notes",
        "display_callout_style": "numbered_tables_and_figures"
    }
}
for item in jf["candidates"]:
    item["primary_target"] = requested
rq_path.write_text(json.dumps(rq, indent=2, sort_keys=True) + "\n")
jf_path.write_text(json.dumps(jf, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p1.verify.custom-journal
expect_pass l2.p1.verify.custom-journal "$CUSTOM_RQ_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$CUSTOM_RQ_PROJ"

FALLBACK_RQ_PROJ="$TMP/fallback-rq-project"
cp -R "$RQ_PROJ" "$FALLBACK_RQ_PROJ"
FALLBACK_RESOLUTION_JSON="$(python3 "$SCRIPT_DIR/emit-journal-profile-resolution.py" \
  --requested "New Journal of Stratification Dynamics" \
  --origin fallback_asr \
  --fallback-reason "The requested journal could not be resolved confidently from authoritative guidance, so the workflow falls back to ASR rather than a generic article shell.")"
python3 - "$FALLBACK_RQ_PROJ" "$FALLBACK_RESOLUTION_JSON" <<'PY'
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
resolution = json.loads(sys.argv[2])
rq_path = proj / "idea/research-question.json"
jf_path = proj / "idea/journal-fit.json"
rq = json.loads(rq_path.read_text())
jf = json.loads(jf_path.read_text())
resolved = resolution["resolved_profile_name"]
rq["target_journal"]["primary"] = resolved
rq["target_journal"]["journal_family"] = "general sociology"
rq["target_journal"]["fit_rationale"] = "The requested journal could not be resolved confidently, so the pipeline falls back to ASR as the explicit default sociology profile."
rq["target_journal"]["method_bar"] = "ASR-calibrated observational design with strong theory and disciplined claims"
rq["target_journal"]["theory_bar"] = "ASR-level theory development and contribution framing"
rq["target_journal"]["desk_reject_risks"] = ["original requested venue could not be calibrated from available guidance"]
jf["target_source"] = "user_provided"
jf["primary_target"] = resolved
jf["journal_family"] = "general sociology"
jf["journal_profile_resolution"] = resolution
for item in jf["candidates"]:
    item["primary_target"] = resolved
rq_path.write_text(json.dumps(rq, indent=2, sort_keys=True) + "\n")
jf_path.write_text(json.dumps(jf, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p1.verify.fallback-journal
expect_pass l2.p1.verify.fallback-journal "$FALLBACK_RQ_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$FALLBACK_RQ_PROJ"

BAD_RQ_PROJ="$TMP/bad-rq-project"
mkdir -p "$BAD_RQ_PROJ/idea"
cp -R "$RQ_PROJ/idea/." "$BAD_RQ_PROJ/idea/"
cat > "$BAD_RQ_PROJ/idea/research-question.json" <<'JSON'
{
  "verdict": "PASS",
  "engine": "scholar-idea",
  "input_mode": "idea",
  "selected_rq_id": "RQ1",
  "selected_rq": "Does X affect Y?",
  "x": "X",
  "y": "Y",
  "directional_relation": "unknown",
  "mechanism": "TBD",
  "confounders": ["TBD"],
  "scope": {"population": "unknown", "place": "unknown", "time": "unknown", "unit": "unknown"},
  "target_journal": {"primary": "TBD", "journal_family": "TBD", "fit_rationale": "TBD", "method_bar": "TBD", "theory_bar": "TBD", "desk_reject_risks": []},
  "paper_type": "TBD",
  "method_orientation": "TBD",
  "recommended_dataset": "TBD",
  "claim_strength": "exploratory",
  "rationale": "TBD",
  "selection_evidence": {"candidate_count": 1, "panel_consensus": "weak", "fatal_flaw": true, "data_feasible": false, "journal_fit": "weak"},
  "ready_for_phase_2": true
}
JSON
printf 'Does X affect Y?\n' > "$BAD_RQ_PROJ/idea/research-question.md"
if [[ "${SCHOLAR_FIXTURE_PHASE0_4_WRONG_REASON:-0}" == "1" ]]; then
  mv "$BAD_RQ_PROJ/idea/candidate-rqs.json" "$BAD_RQ_PROJ/idea/candidate-rqs.wrong-reason"
fi
# CASE_ID: phase.1.negative
expect_reject phase.1.negative "$BAD_RQ_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_RQ_PROJ"

BAD_CUSTOM_RQ_PROJ="$TMP/bad-custom-rq-project"
cp -R "$CUSTOM_RQ_PROJ" "$BAD_CUSTOM_RQ_PROJ"
python3 - "$BAD_CUSTOM_RQ_PROJ/idea/journal-fit.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc.pop("journal_profile_resolution", None)
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p1.reject.custom-profile-missing
expect_reject l2.p1.reject.custom-profile-missing "$BAD_CUSTOM_RQ_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_CUSTOM_RQ_PROJ"

BAD_IMPORTED_BUILTIN_RQ_PROJ="$TMP/bad-imported-builtin-rq-project"
cp -R "$RQ_PROJ" "$BAD_IMPORTED_BUILTIN_RQ_PROJ"
python3 - "$BAD_IMPORTED_BUILTIN_RQ_PROJ/idea/journal-fit.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["journal_profile_resolution"]["profile_origin"] = "imported_custom"
doc["journal_profile_resolution"]["source_strategy"] = "web_fetched_profile"
doc["journal_profile_resolution"]["web_lookup_attempted"] = True
doc["journal_profile_resolution"]["profile_source_engine"] = "scholar-journal"
doc["journal_profile_resolution"]["requested_journal"] = "Journal of Marriage and Family"
doc["journal_profile_resolution"]["resolved_profile_name"] = "Journal of Marriage and Family"
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p1.reject.imported-builtin
expect_reject l2.p1.reject.imported-builtin "$BAD_IMPORTED_BUILTIN_RQ_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_IMPORTED_BUILTIN_RQ_PROJ"

BAD_RQ_FATAL_PROJ="$TMP/bad-rq-fatal-project"
cp -R "$RQ_PROJ" "$BAD_RQ_FATAL_PROJ"
python3 - "$BAD_RQ_FATAL_PROJ/idea/candidate-rqs.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
for candidate in doc["candidates"]:
    if candidate["rq_id"] == "RQ1":
        candidate["fatal_flaw"] = True
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p1.reject.fatal-selected
expect_reject l2.p1.reject.fatal-selected "$BAD_RQ_FATAL_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_RQ_FATAL_PROJ"

BAD_RQ_JOURNAL_PROJ="$TMP/bad-rq-journal-project"
cp -R "$RQ_PROJ" "$BAD_RQ_JOURNAL_PROJ"
python3 - "$BAD_RQ_JOURNAL_PROJ/idea/rq-evaluation-panel.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
panel = json.loads(path.read_text())
panel["reviewers"] = [r for r in panel["reviewers"] if r["role"] != "journal_editor"]
path.write_text(json.dumps(panel, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p1.reject.reviewer-count
expect_reject l2.p1.reject.reviewer-count "$BAD_RQ_JOURNAL_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_RQ_JOURNAL_PROJ"

BRAINSTORM_DATA_PROJ="$TMP/brainstorm-data-rq-project"
mkdir -p "$BRAINSTORM_DATA_PROJ/idea" "$BRAINSTORM_DATA_PROJ/scripts"
cat > "$BRAINSTORM_DATA_PROJ/idea/research-question.json" <<'JSON'
{
  "verdict": "PASS",
  "engine": "scholar-brainstorm",
  "engine_provenance": {
    "task_invocation_id": "phase1-brainstorm-001",
    "invoked_at_utc": "2026-04-28T08:10:00Z",
    "input_artifacts": ["materials/data-dictionary.csv", "materials/codebook.pdf"],
    "output_artifacts": [
      "idea/candidate-rqs.json",
      "idea/journal-fit.json",
      "idea/research-question.json",
      "idea/brainstorm-mode.json"
    ]
  },
  "input_mode": "data",
  "selected_rq_id": "BD1",
  "selected_rq": "Among surveyed adolescents in the study data, what is the association between parental job loss and educational expectations?",
  "x": "parental job loss",
  "y": "educational expectations",
  "directional_relation": "negative",
  "mechanism": "economic disruption reduces perceived educational feasibility through family stress",
  "confounders": ["baseline income", "parent education", "prior grades"],
  "scope": {
    "population": "surveyed adolescents",
    "place": "study sample",
    "time": "observed survey waves",
    "unit": "adolescent"
  },
  "target_journal": {
    "primary": "Journal of Marriage and Family",
    "journal_family": "family sociology",
    "fit_rationale": "The data-supported question speaks to family instability and adolescent expectations.",
    "method_bar": "transparent observational analysis with signal caveats and robustness checks",
    "theory_bar": "family stress mechanism connected to adolescent educational expectations",
    "desk_reject_risks": ["preliminary signal must not be overinterpreted as causal evidence"]
  },
  "paper_type": "research note",
  "method_orientation": "observational survey analysis",
  "recommended_dataset": "provided adolescent survey data",
  "claim_strength": "associational",
  "rationale": "The selected question is grounded in measured variables, has a moderate exploratory bivariate signal, and is useful for a cautious family-process paper.",
  "selection_evidence": {
    "candidate_count": 15,
    "panel_consensus": "strong",
    "fatal_flaw": false,
    "data_feasible": true,
    "novelty_risk": "medium",
    "journal_fit": "strong",
    "empirical_signal": {
      "status": "MODERATE",
      "bivariate_only": true,
      "interpretation": "Exploratory bivariate evidence only; not causal evidence."
    }
  },
  "ready_for_phase_2": true
}
JSON
cat > "$BRAINSTORM_DATA_PROJ/idea/candidate-rqs.json" <<'JSON'
{
  "verdict": "PASS",
  "engine": "scholar-brainstorm",
  "input_mode": "data",
  "candidates": [
    {
      "rq_id": "BD1",
      "question": "Among surveyed adolescents in the study data, what is the association between parental job loss and educational expectations?",
      "x": "parental job loss",
      "y": "educational expectations",
      "mechanism": "economic disruption reduces perceived educational feasibility through family stress",
      "confounders": ["baseline income", "parent education", "prior grades"],
      "scope": {"population": "surveyed adolescents", "place": "study sample", "time": "observed survey waves", "unit": "adolescent"},
      "claim_strength": "associational",
      "recommended_dataset": "provided adolescent survey data",
      "novelty_risk": "medium",
      "data_feasible": true,
      "fatal_flaw": false,
      "empirical_signal": {
        "status": "MODERATE",
        "effect_size": "Pearson r",
        "effect_value": "-0.18",
        "p_value": "0.012",
        "n_obs": "1240",
        "signal": "MODERATE",
        "selection_allowed": true,
        "interpretation": "Moderate preliminary bivariate signal; not causal evidence."
      }
    },
    {
      "rq_id": "BD2",
      "question": "Among surveyed adolescents in the study data, what is the association between household income volatility and school engagement?",
      "x": "household income volatility",
      "y": "school engagement",
      "mechanism": "income volatility disrupts routines and school support",
      "confounders": ["parent education", "neighborhood disadvantage"],
      "scope": {"population": "surveyed adolescents", "place": "study sample", "time": "observed survey waves", "unit": "adolescent"},
      "claim_strength": "associational",
      "recommended_dataset": "provided adolescent survey data",
      "novelty_risk": "medium",
      "data_feasible": true,
      "fatal_flaw": false,
      "empirical_signal": {"status": "WEAK", "effect_size": "Pearson r", "effect_value": "-0.06", "p_value": "0.080", "n_obs": "1180", "selection_allowed": true, "interpretation": "Weak exploratory signal.", "theory_journal_justification": "The theory and journal fit are strong enough to keep as a backup candidate."}
    },
    {
      "rq_id": "BD3",
      "question": "Among surveyed adolescents in the study data, what is the association between parental monitoring and educational expectations?",
      "x": "parental monitoring",
      "y": "educational expectations",
      "mechanism": "monitoring increases school planning and perceived feasibility",
      "confounders": ["family structure", "parent education"],
      "scope": {"population": "surveyed adolescents", "place": "study sample", "time": "observed survey waves", "unit": "adolescent"},
      "claim_strength": "associational",
      "recommended_dataset": "provided adolescent survey data",
      "novelty_risk": "low",
      "data_feasible": true,
      "fatal_flaw": false,
      "empirical_signal": {"status": "NULL", "effect_size": "Pearson r", "effect_value": "0.01", "p_value": "0.740", "n_obs": "1210", "selection_allowed": false, "interpretation": "No preliminary bivariate signal."}
    }
  ]
}
JSON
cat > "$BRAINSTORM_DATA_PROJ/idea/rq-evaluation-panel.json" <<'JSON'
{
  "verdict": "PASS",
  "selected_rq_id": "BD1",
  "fatal_flaw_selected": false,
  "ready_for_selection": true,
  "reviewers": [
    {"role": "theorist", "verdict": "PASS", "rank_order": ["BD1", "BD2", "BD3"]},
    {"role": "methodologist", "verdict": "PASS", "rank_order": ["BD1", "BD2", "BD3"]},
    {"role": "domain_expert", "verdict": "PASS", "rank_order": ["BD1", "BD3", "BD2"]},
    {"role": "journal_editor", "verdict": "PASS", "rank_order": ["BD1", "BD2", "BD3"]},
    {"role": "devils_advocate", "verdict": "PASS", "viability": "VIABLE", "rank_order": ["BD1", "BD2", "BD3"]}
  ],
  "consensus": {"top_pick": "BD1", "panel_consensus": "strong"}
}
JSON
cat > "$BRAINSTORM_DATA_PROJ/idea/journal-fit.json" <<'JSON'
{
  "verdict": "PASS",
  "target_source": "inferred",
  "selected_rq_id": "BD1",
  "primary_target": "Journal of Marriage and Family",
  "journal_family": "family sociology",
  "paper_type": "research note",
  "journal_profile_resolution": {
    "requested_journal": "Journal of Marriage and Family",
    "resolved_profile_name": "Journal of Marriage and Family",
    "profile_origin": "built_in",
    "profile_source_engine": "scholar-journal",
    "source_strategy": "built_in_catalog",
    "web_lookup_attempted": false,
    "fallback_used": false,
    "fallback_reason": "",
    "journal_structure": {
      "profile_source": "scholar-journal:jmf",
      "section_sequence": ["Abstract", "Introduction", "Background", "Data and Methods", "Results", "Discussion", "Conclusion", "References", "Tables", "Figures"],
      "results_before_methods": false,
      "theory_presentation": "background_section",
      "methods_section_label": "Data and Methods",
      "discussion_conclusion_policy": "split_required",
      "supplement_policy": "journal_optional_appendix"
    },
    "display_architecture": {
      "table_placement_policy": "end_matter_after_references",
      "figure_placement_policy": "separate_files_after_tables",
      "descriptive_table_requirement": "journal_optional",
      "editable_text_tables": true,
      "image_tables_forbidden": true,
      "main_text_display_cap": null,
      "main_text_table_cap": null,
      "main_text_figure_cap": null,
      "supplement_label_prefix": "Appendix",
      "panel_label_style": "A_B_C",
      "table_rendering_mode": "editable_text_end_matter",
      "figure_rendering_mode": "separate_figure_files",
      "table_title_position": "above_table",
      "table_notes_policy": "below_table_notes",
      "display_callout_style": "numbered_tables_and_figures"
    }
  },
  "candidates": [
    {"rq_id": "BD1", "primary_target": "Journal of Marriage and Family", "fit_score": 8, "fit_dimensions": {"audience": "strong", "theory": "strong", "method": "adequate", "contribution": "strong"}, "desk_reject_risks": ["signal is preliminary"], "recommended": true},
    {"rq_id": "BD2", "primary_target": "Journal of Marriage and Family", "fit_score": 7, "fit_dimensions": {"audience": "adequate", "theory": "adequate", "method": "adequate", "contribution": "adequate"}, "desk_reject_risks": ["weak signal"], "recommended": false},
    {"rq_id": "BD3", "primary_target": "Journal of Marriage and Family", "fit_score": 7, "fit_dimensions": {"audience": "adequate", "theory": "adequate", "method": "weak", "contribution": "adequate"}, "desk_reject_risks": ["null bivariate signal"], "recommended": false}
  ],
  "ready_for_phase_2": true
}
JSON
cat > "$BRAINSTORM_DATA_PROJ/idea/brainstorm-mode.json" <<'JSON'
{
  "verdict": "PASS",
  "engine": "scholar-brainstorm",
  "operating_mode": "DATA",
  "safety_status": "PASS",
  "data_files": ["data/raw/adolescent-survey.csv"],
  "candidate_count": 15,
  "shortlist_count": 10,
  "empirical_signal_tests": {
    "required": true,
    "status": "PASS",
    "script_path": "scripts/brainstorm-signal-tests.R",
    "log_path": "scripts/brainstorm-signal-tests.log",
    "signal_table_path": "idea/empirical-signal-table.csv",
    "score_weight": 0.2
  }
}
JSON
cat > "$BRAINSTORM_DATA_PROJ/idea/variable-inventory.json" <<'JSON'
{
  "variables": [
    {"name": "parental_job_loss", "role": "x", "type": "binary", "missingness": 0.03},
    {"name": "educational_expectations", "role": "y", "type": "continuous", "missingness": 0.04},
    {"name": "baseline_income", "role": "confounder", "type": "continuous", "missingness": 0.05}
  ]
}
JSON
cat > "$BRAINSTORM_DATA_PROJ/idea/empirical-signal-table.csv" <<'CSV'
rq,x_var,y_var,test_type,estimate,effect_size,effect_value,p_value,n_obs,signal
BD1,parental_job_loss,educational_expectations,Pearson correlation,-0.18,Pearson r,-0.18,0.012,1240,MODERATE
BD2,income_volatility,school_engagement,Pearson correlation,-0.06,Pearson r,-0.06,0.080,1180,WEAK
BD3,parental_monitoring,educational_expectations,Pearson correlation,0.01,Pearson r,0.01,0.740,1210,NULL
CSV
cat > "$BRAINSTORM_DATA_PROJ/scripts/brainstorm-signal-tests.R" <<'RS'
library(dplyr)
library(tibble)
library(effectsize)
# Protocol marker: real DATA-mode scripts use effectsize::cohens_d(),
# effectsize::eta_squared(), or effectsize::cramers_v() as appropriate.
signal_results <- tibble(rq=character(), x_var=character(), y_var=character(), test_type=character(), estimate=double(), effect_size=character(), effect_value=double(), p_value=double(), n_obs=integer(), signal=character())
tryCatch({
  signal_results <- bind_rows(signal_results, tibble(rq="BD1", x_var="parental_job_loss", y_var="educational_expectations", test_type="Pearson correlation", estimate=-0.18, effect_size="Pearson r", effect_value=-0.18, p_value=0.012, n_obs=1240L, signal=""))
}, error=function(e) {
  signal_results <<- bind_rows(signal_results, tibble(rq="BD1", x_var="parental_job_loss", y_var="educational_expectations", test_type="ERROR", estimate=NA_real_, effect_size=NA_character_, effect_value=NA_real_, p_value=NA_real_, n_obs=NA_integer_, signal=paste("Error:", e$message)))
})
signal_results <- signal_results |> mutate(signal = case_when(p_value < 0.05 ~ "MODERATE", p_value >= 0.10 ~ "NULL", TRUE ~ "WEAK"))
print(signal_results)
RS
cat > "$BRAINSTORM_DATA_PROJ/scripts/brainstorm-signal-tests.log" <<'LOG'
Aggregated signal output from brainstorm-signal-tests.R. The selected question BD1 shows signal MODERATE with Pearson r -0.18, p value 0.012, and 1240 observations. These results are exploratory bivariate checks only and are not causal evidence.
LOG
cat > "$BRAINSTORM_DATA_PROJ/idea/rq-selection-rationale.md" <<'MD'
# Brainstorm DATA-Mode Selection Rationale

BD1 was selected because it combined a feasible measured X variable, a measured Y variable, an interpretable family-stress mechanism, and a moderate exploratory signal in the bivariate screening table. The panel agreed that the empirical signal should increase feasibility confidence without being treated as causal evidence. BD2 remains a backup because its signal was weak but theoretically plausible. BD3 was not selected because the preliminary signal was null and no user override was provided.

The selection is useful because it prevents the pipeline from treating all brainstormed questions as equally promising. The selected question has enough signal to justify investment, yet the rationale records that the signal is only a screening result. That caveat should shape Phase 2 theory claims, Phase 3 design language, and Phase 12 manuscript wording.
MD
cat > "$BRAINSTORM_DATA_PROJ/idea/research-question.md" <<'MD'
# Brainstorm Selected Research Question

Selected question: Among surveyed adolescents in the study data, what is the association between parental job loss and educational expectations?

The selected question comes from scholar-brainstorm DATA mode. It has measured X and Y variables, a moderate exploratory empirical signal, and journal fit for a cautious family sociology article. The signal is treated as preliminary bivariate evidence only.
MD
cat > "$BRAINSTORM_DATA_PROJ/idea/brainstorm-report.md" <<'MD'
# Brainstorm Report

The DATA-mode brainstorm classified the provided adolescent survey data, inherited safety clearance, built a variable inventory, generated fifteen candidate questions, and shortlisted ten candidates for panel review. The selected question was BD1 because it combined a measured exposure, measured outcome, plausible family-stress mechanism, and a moderate bivariate signal. The report treats empirical signal tests as exploratory screening rather than proof. The panel compared theoretical usefulness, data readiness, journal fit, literature novelty, and failure modes before selecting BD1. BD2 was retained as a backup because its weak signal could still be useful for theory, while BD3 was deprioritized because the preliminary signal was null. The final recommendation is to move BD1 into literature and theory development with an explicit caveat that all empirical signal results are preliminary and must be re-evaluated in the formal design and analysis phases.

The report also records that no raw data rows are part of the Phase 1 handoff. Only aggregated signal results, variable roles, sample sizes, and signal caveats move forward. This protects against HARKing while still letting the pipeline avoid spending a full-paper run on a question that the provided data cannot even preliminarily support.
MD
cat > "$BRAINSTORM_DATA_PROJ/idea/brainstorm-summary.md" <<'MD'
# Brainstorm Summary

Scholar-brainstorm DATA mode selected BD1 from a fifteen-candidate pool. The selected question uses parental job loss as X and educational expectations as Y. It has a moderate bivariate signal, feasible variables, and target-journal fit for Journal of Marriage and Family. The signal is preliminary and should not be written as causal evidence. Null-signal candidates were retained for transparency but were not selected without user override.
MD
# CASE_ID: l2.p1.verify.brainstorm-data
expect_pass l2.p1.verify.brainstorm-data "$BRAINSTORM_DATA_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BRAINSTORM_DATA_PROJ"

BAD_BRAINSTORM_NULL_PROJ="$TMP/bad-brainstorm-null-project"
cp -R "$BRAINSTORM_DATA_PROJ" "$BAD_BRAINSTORM_NULL_PROJ"
python3 - "$BAD_BRAINSTORM_NULL_PROJ" <<'PY'
import csv
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
rq_path = proj / "idea/research-question.json"
candidates_path = proj / "idea/candidate-rqs.json"
table_path = proj / "idea/empirical-signal-table.csv"
rq = json.loads(rq_path.read_text())
rq["selection_evidence"]["empirical_signal"]["status"] = "NULL"
rq_path.write_text(json.dumps(rq, indent=2, sort_keys=True) + "\n")
candidates = json.loads(candidates_path.read_text())
for candidate in candidates["candidates"]:
    if candidate["rq_id"] == "BD1":
        candidate["empirical_signal"]["status"] = "NULL"
        candidate["empirical_signal"]["signal"] = "NULL"
        candidate["empirical_signal"]["p_value"] = "0.650"
        candidate["empirical_signal"]["effect_value"] = "0.01"
        candidate["empirical_signal"]["selection_allowed"] = False
candidates_path.write_text(json.dumps(candidates, indent=2, sort_keys=True) + "\n")
rows = list(csv.DictReader(table_path.open()))
for row in rows:
    if row["rq"] == "BD1":
        row["signal"] = "NULL"
        row["p_value"] = "0.650"
        row["effect_value"] = "0.01"
with table_path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
PY
# CASE_ID: l2.p1.reject.null-signal
expect_reject l2.p1.reject.null-signal "$BAD_BRAINSTORM_NULL_PROJ" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_BRAINSTORM_NULL_PROJ"

LIT_PROJ="$TMP/lit-project"
mkdir -p "$LIT_PROJ/literature" "$LIT_PROJ/idea"
cp "$RQ_PROJ/idea/research-question.json" "$LIT_PROJ/idea/research-question.json"
cp "$RQ_PROJ/idea/journal-fit.json" "$LIT_PROJ/idea/journal-fit.json"
cat > "$LIT_PROJ/literature/search-log.md" <<'MD'
# Search Log

| # | Source | Query / Keywords | Hits | Retained | Key papers found |
|---|--------|-----------------|------|----------|-----------------|
| 0 | Knowledge-Graph | family stress educational expectations | 4 | 2 | Conger 1992; Sewell 2001 |
| 1 | RefLib | parental job loss | 12 | 4 | Brand 2008; Kalil 2010 |
| 2 | RefLib | educational expectations mechanism | 9 | 3 | Sewell 2001; Domina 2011 |
| 3 | RefLib | panel job loss inequality | 7 | 2 | Johnson 2012; Hill 2015 |
| 4 | RefLib | author: Conger | 6 | 2 | Conger 1992; Conger 2002 |
| 5 | WebSearch | parental job loss adolescent educational expectations | 18 | 3 | Brand 2019; Hill 2020 |
MD
cat > "$LIT_PROJ/literature/review-protocol.json" <<'JSON'
{
  "verdict": "PASS",
  "source_phase": "2",
  "primary_skill": "scholar-lit-review-hypothesis",
  "local_library_first": true,
  "reference_backend_detected": ["BibTeX", "Zotero"],
  "knowledge_graph_checked": true,
  "ref_queries": 3,
  "author_queries": 1,
  "web_queries": 1,
  "search_log_path": "literature/search-log.md",
  "source_integrity_completed": true,
  "verification_panel_completed": true,
  "prior_project_bibliographies_used": [],
  "ready_for_phase_3": true
}
JSON
python3 - "$LIT_PROJ/literature/lit-theory.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "Prior research links household economic instability to educational expectations through income constraints, stress processes, institutional navigation, and changing perceptions of feasible futures. "
with open(path, "w", encoding="utf-8") as f:
    f.write(sentence * 45)
PY
cat > "$LIT_PROJ/literature/literature-coverage-matrix.json" <<'JSON'
{
  "review_protocol": "literature/review-protocol.json",
  "verdict": "PASS",
  "engine_handoff": {
    "lit_review_engine": {
      "skill": "scholar-lit-review-hypothesis",
      "mode": "integrated_literature_theory_hypotheses",
      "task_invocation_id": "phase2-lit-review-001",
      "invoked_at_utc": "2026-04-28T09:00:00Z",
      "input_artifacts": ["idea/research-question.json", "idea/journal-fit.json"],
      "output_artifacts": ["literature/literature-coverage-matrix.json", "literature/references.bib", "literature/search-log.md", "literature/review-protocol.json"],
      "protocol_followed": true,
      "protocol_artifacts": ["literature/review-protocol.json", "literature/search-log.md"]
    },
    "writing_engine": {
      "skill": "scholar-write",
      "mode": "draft",
      "section": "Literature Review and Theory",
      "task_invocation_id": "phase2-write-001",
      "invoked_at_utc": "2026-04-28T09:30:00Z",
      "input_artifacts": ["literature/literature-coverage-matrix.json", "idea/journal-fit.json"],
      "output_artifacts": ["literature/lit-theory.md", "literature/lit-theory-manifest.json"]
    },
    "target_journal": "Journal of Marriage and Family"
  },
  "coverage_matrix": {
    "constructs": ["parental job loss", "educational expectations"],
    "theories": ["family stress model", "status attainment"],
    "methods": ["fixed effects", "event study"],
    "datasets_populations": ["household panel data", "low-income adolescents"],
    "competing_findings": ["income shock effects", "adaptive expectations"]
  },
  "must_cite_coverage": [],
  "mechanism_chain": [
    {"step": "job loss reduces resources", "link": "income shock"},
    {"step": "resource loss lowers expectations", "link": "perceived feasibility"}
  ],
  "hypotheses": [
    {"id": "H1", "text": "Parental job loss lowers adolescent educational expectations.", "direction": "negative"}
  ],
  "journal_calibration": {
    "target_journal": "Journal of Marriage and Family",
    "paper_type": "research note",
    "theory_depth": "family-process mechanism with explicit links to family stress and status-attainment theory",
    "citation_density": "dense enough to establish family, inequality, and adolescent-development conversations without padding",
    "must_cite_strategy": "prioritize family instability, status attainment, and adolescent expectations literatures relevant to JMF readers"
  },
  "ready_for_phase_3": true
}
JSON
python3 - "$LIT_PROJ/literature/literature-coverage-matrix.json" "$LIT_PROJ/literature/references.bib" <<'PY'
import hashlib
import json
import pathlib
import sys
matrix_path, bib_path = [pathlib.Path(p) for p in sys.argv[1:3]]
proj = matrix_path.parents[1]

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

with matrix_path.open(encoding="utf-8") as f:
    matrix = json.load(f)
matrix["must_cite_coverage"] = [
    {"key": f"work{i:02d}", "covered": True}
    for i in range(1, 32)
]
role_cycle = [
    "theory",
    "mechanism",
    "rival",
    "method",
    "context",
    "population",
    "empirical_prior",
    "journal_canon",
    "design",
    "data",
    "competing_explanation",
    "domain",
]
matrix["source_role_matrix"] = [
    {
        "key": f"work{i:02d}",
        "argument_role": role,
        "claim_supported": f"Source work{i:02d} supports the fixture's {role.replace('_', ' ')} argument role.",
        "target_section": "Literature Review and Theory",
        "why_it_matters": f"This fixture source demonstrates that {role.replace('_', ' ')} evidence is assigned to a concrete manuscript use.",
    }
    for i, role in enumerate(role_cycle, start=1)
]
with matrix_path.open("w", encoding="utf-8") as f:
    json.dump(matrix, f, indent=2, sort_keys=True)
with bib_path.open("w", encoding="utf-8") as f:
    for i in range(1, 32):
        f.write(f"@article{{work{i:02d}, title={{Title {i}}}, author={{Author {i}}}, year={{20{i%20:02d}}}}}\\n")
# Evidence Ledger assertion fixture (evidence-ledger plan 2026-08-12 D2):
# a declared evidence_ledger key must validate (path exists, records <= lines).
(proj / "evidence").mkdir(parents=True, exist_ok=True)
(proj / "evidence/claim-anchors.ndjson").write_text(
    '{"schema":"claim-anchor/v1","anchor_id":"work01-0a1b2c3d","cite_key":"work01",'
    '"claim_kind":"map_cell","stance":"supports","evidence_quote":"fixture passage",'
    '"evidence_form":"abstract_verbatim","access_tier":"T3_abstract",'
    '"produced_by":"scholar-lit-review-hypothesis","ts":"2026-08-12T00:00:00Z"}\n'
)
manifest = {
    "verdict": "PASS",
    "source_phase": "2",
    "engine_handoff": matrix["engine_handoff"],
    "selected_rq_hash": sha(proj / "idea/research-question.json"),
    "journal_fit_hash": sha(proj / "idea/journal-fit.json"),
    "coverage_matrix_hash": sha(matrix_path),
    "lit_theory_hash": sha(proj / "literature/lit-theory.md"),
    "references_bib_hash": sha(bib_path),
    "source_hashes": {
        "research_question": sha(proj / "idea/research-question.json"),
        "journal_fit": sha(proj / "idea/journal-fit.json")
    },
    "protocol_artifacts": {
        "search_log": "literature/search-log.md",
        "review_protocol": "literature/review-protocol.json"
    },
    "evidence_ledger": {"path": "evidence/claim-anchors.ndjson", "records": 1},
    "ready_for_phase_3": True
}
(proj / "literature/lit-theory-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.2.positive
expect_pass phase.2.positive "$LIT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 2 "$LIT_PROJ"

# Negative fixture: evidence_ledger claiming more records than the file has → FAIL
BAD_EVIDENCE_PROJ="$TMP/bad-evidence-project"
cp -R "$LIT_PROJ" "$BAD_EVIDENCE_PROJ"
python3 - "$BAD_EVIDENCE_PROJ/literature/lit-theory-manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["evidence_ledger"]["records"] = 99
open(p, "w").write(json.dumps(m, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.2.negative
expect_reject phase.2.negative "$BAD_EVIDENCE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 2 "$BAD_EVIDENCE_PROJ"

BAD_LIT_ENGINE_PROJ="$TMP/bad-lit-engine-project"
cp -R "$LIT_PROJ" "$BAD_LIT_ENGINE_PROJ"
python3 - "$BAD_LIT_ENGINE_PROJ/literature/literature-coverage-matrix.json" "$BAD_LIT_ENGINE_PROJ/literature/lit-theory-manifest.json" <<'PY'
import json
import pathlib
import sys
matrix_path = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
matrix = json.loads(matrix_path.read_text())
matrix["engine_handoff"]["writing_engine"]["skill"] = "manual-prose"
matrix_path.write_text(json.dumps(matrix, indent=2, sort_keys=True) + "\n")
manifest = json.loads(manifest_path.read_text())
manifest["engine_handoff"] = matrix["engine_handoff"]
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p2.reject.engine-handoff
expect_reject l2.p2.reject.engine-handoff "$BAD_LIT_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 2 "$BAD_LIT_ENGINE_PROJ"

BAD_LIT_PROTOCOL_PROJ="$TMP/bad-lit-protocol-project"
cp -R "$LIT_PROJ" "$BAD_LIT_PROTOCOL_PROJ"
python3 - "$BAD_LIT_PROTOCOL_PROJ/literature/review-protocol.json" "$BAD_LIT_PROTOCOL_PROJ/literature/literature-coverage-matrix.json" <<'PY'
import json
import pathlib
import sys
review = pathlib.Path(sys.argv[1])
matrix = pathlib.Path(sys.argv[2])
obj = json.loads(review.read_text())
obj["ref_queries"] = 0
review.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")
mat = json.loads(matrix.read_text())
mat["engine_handoff"]["lit_review_engine"]["protocol_followed"] = False
matrix.write_text(json.dumps(mat, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p2.reject.review-protocol
expect_reject l2.p2.reject.review-protocol "$BAD_LIT_PROTOCOL_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 2 "$BAD_LIT_PROTOCOL_PROJ"

BAD_LIT_PROJ="$TMP/bad-lit-project"
mkdir -p "$BAD_LIT_PROJ/literature"
printf 'Too short.\n' > "$BAD_LIT_PROJ/literature/lit-theory.md"
cat > "$BAD_LIT_PROJ/literature/literature-coverage-matrix.json" <<'JSON'
{
  "coverage_matrix": {
    "constructs": [],
    "theories": [],
    "methods": [],
    "datasets_populations": [],
    "competing_findings": []
  },
  "must_cite_coverage": [{"key": "one", "covered": false}],
  "mechanism_chain": [{"step": "something"}],
  "hypotheses": [{"id": "H1", "text": "TBD"}]
}
JSON
printf '@article{one, title={Title}}\n' > "$BAD_LIT_PROJ/literature/references.bib"
# CASE_ID: l2.p2.reject.missing-outputs
expect_reject l2.p2.reject.missing-outputs "$BAD_LIT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 2 "$BAD_LIT_PROJ"

progress "phases 2 to 4 literature, design, and data fixtures"

DESIGN_PROJ="$TMP/design-project"
cp -R "$LIT_PROJ" "$DESIGN_PROJ"
mkdir -p "$DESIGN_PROJ/design"
python3 - "$DESIGN_PROJ/design/design-blueprint.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "The design estimates how parental job loss changes adolescent educational expectations by comparing households before and after job displacement while adjusting for stable socioeconomic differences and observed time-varying confounders. "
with open(path, "w", encoding="utf-8") as f:
    f.write("outcome_mechanism_alignment: prevalence-stock\n\n")
    f.write(sentence * 25)
PY
cat > "$DESIGN_PROJ/design/identification-strategy.json" <<'JSON'
{
  "design_type": "observational panel design",
  "claim_strength": "associational",
  "estimand": "average within-household change in adolescent educational expectations after parental job loss",
  "identification_strategy": "household fixed effects with event-time indicators around parental job loss",
  "outcome_mechanism_alignment": "prevalence-stock",
  "journal_method_bar": "Journal of Marriage and Family requires transparent observational identification, careful family-process theory linkage, and robustness checks for attrition and pretrends.",
  "hypothesis_model_coverage": [
    {
      "hypothesis_id": "H1",
      "model_ids": ["M1"],
      "coverage": "primary model estimates the hypothesized association between parental job loss and adolescent expectations"
    }
  ],
  "power_or_feasibility_assessment": {
    "status": "feasible_existing_data",
    "rationale": "The planned household panel has repeated measures around job loss and enough observed covariates to support feasibility screening before final power calculations."
  },
  "method_specialist_routing": {
    "method_orientation": "observational panel analysis",
    "primary_execution_skill": "scholar-analyze",
    "premortem_skill": "scholar-analyze",
    "supporting_skills": [],
    "rationale": "This is a quantitative panel analysis with standard empirical execution rather than computational, qualitative, or linguistic methods."
  },
  "causal_gate": {
    "required": true,
    "invoked": true,
    "skill": "scholar-causal",
    "reason": "Fixed-effects event-time language requires causal-assumption auditing even though the paper will use associational wording."
  },
  "assumptions": [
    "No unmeasured time-varying shocks simultaneously cause job loss and expectation change",
    "Educational expectations are measured consistently before and after job loss"
  ],
  "measures": {
    "x": {
      "name": "parental job loss",
      "operationalization": "indicator for transition from employed to unemployed between waves"
    },
    "y": {
      "name": "adolescent educational expectations",
      "operationalization": "expected highest degree reported by adolescent respondent"
    }
  },
  "threats": [
    "Anticipatory changes before job loss",
    "Attrition after economic shocks"
  ],
  "robustness_plan": [
    "event-study pretrend check",
    "inverse probability attrition weights"
  ]
}
JSON
cat > "$DESIGN_PROJ/design/model-specs.json" <<'JSON'
{
  "models": [
    {
      "id": "M1",
      "outcome": "adolescent educational expectations",
      "predictors": ["parental job loss"],
      "estimator": "household fixed effects linear model",
      "covariates": ["child age", "wave", "household income"],
      "hypothesis_ids": ["H1"],
      "purpose": "primary estimate of within-household expectation change"
    }
  ]
}
JSON
python3 - "$DESIGN_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

manifest = {
    "verdict": "PASS",
    "source_phase": "3",
    "design_engine": {
        "skill": "scholar-design",
        "mode": "design_blueprint",
        "task_invocation_id": "phase3-design-001",
        "invoked_at_utc": "2026-04-28T10:00:00Z",
        "input_artifacts": [
            "idea/research-question.json",
            "idea/journal-fit.json",
            "literature/lit-theory.md",
            "literature/literature-coverage-matrix.json"
        ],
        "output_artifacts": [
            "design/design-blueprint.md",
            "design/identification-strategy.json",
            "design/model-specs.json"
        ]
    },
    "causal_engine": {
        "required": True,
        "invoked": True,
        "skill": "scholar-causal",
        "mode": "fixed_effects_event_time_audit",
        "task_invocation_id": "phase3-causal-001",
        "invoked_at_utc": "2026-04-28T10:15:00Z",
        "input_artifacts": ["design/identification-strategy.json", "design/model-specs.json"],
        "output_artifacts": ["design/identification-strategy.json", "design/design-manifest.json"]
    },
    "method_specialist_engines": [],
    "target_journal": "Journal of Marriage and Family",
    "claim_strength": "associational",
    "claim_continuity": {
        "claim_strength": "associational",
        "mechanisms_carried_forward": True,
        "hypotheses_carried_forward": True,
        "robustness_carried_forward": True,
        "limitations_carried_forward": True,
        "manuscript_claim_boundary": "The manuscript may report bounded observational associations but must not state that parental job loss causes expectation change."
    },
    "mechanism_result_matrix": [
        {
            "mechanism": "Income shock reduces perceived educational feasibility for adolescents.",
            "model_or_spec": "Primary household fixed effects model M1 with parental job loss as the focal predictor.",
            "expected_pattern": "A negative coefficient for parental job loss is expected if the feasibility mechanism is supported.",
            "manuscript_implication": "Results should connect negative estimates to feasibility beliefs without claiming causal proof."
        },
        {
            "mechanism": "Family stress changes planning routines and perceived support after job loss.",
            "model_or_spec": "Event-study pretrend robustness specification checks timing around the observed employment shock.",
            "expected_pattern": "A stable pre-period and negative post-shock pattern would support a cautious timing interpretation.",
            "manuscript_implication": "Discussion should describe stress-process interpretation as plausible but not directly observed."
        }
    ],
    "robustness_claim_matrix": [
        {
            "robustness_check": "event-study pretrend check",
            "claim_implication": "Can strengthen timing credibility if pretrends are weak and post-shock estimates are negative.",
            "weaken_or_bound_rule": "If pretrends are visible or estimates are imprecise, bound the claim to an observed association."
        },
        {
            "robustness_check": "inverse probability attrition weights",
            "claim_implication": "Can assess whether attrition after economic shocks changes the estimated association.",
            "weaken_or_bound_rule": "If weighted estimates attenuate, report robustness as partial and narrow manuscript claims."
        }
    ],
    "limitation_scope_matrix": [
        {
            "limitation": "Unmeasured time-varying shocks may coincide with parental job loss and adolescent planning.",
            "scope_language": "The manuscript should describe estimates as observational associations under fixed-effects assumptions.",
            "affected_claim": "The headline result cannot be written as a causal effect of job loss."
        },
        {
            "limitation": "Educational expectations may not capture every household conversation or support mechanism.",
            "scope_language": "Mechanism language should be framed as theoretically motivated interpretation rather than direct measurement.",
            "affected_claim": "The discussion should not claim that the feasibility mechanism is directly proven."
        }
    ],
    "source_hashes": {
        "research_question": sha(proj / "idea/research-question.json"),
        "journal_fit": sha(proj / "idea/journal-fit.json"),
        "lit_theory": sha(proj / "literature/lit-theory.md"),
        "lit_theory_manifest": sha(proj / "literature/lit-theory-manifest.json"),
        "literature_coverage_matrix": sha(proj / "literature/literature-coverage-matrix.json")
    },
    "output_hashes": {
        "design_blueprint": sha(proj / "design/design-blueprint.md"),
        "identification_strategy": sha(proj / "design/identification-strategy.json"),
        "model_specs": sha(proj / "design/model-specs.json")
    },
    "ready_for_phase_4": True
}
(proj / "design/design-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
cat > "$DESIGN_PROJ/design/design-evaluation.json" <<'JSON'
{
  "overall_verdict": "PASS",
  "unresolved_critical_count": 0,
  "reviewers": [
    {
      "role": "identification",
      "verdict": "PASS",
      "critical_issues_count": 0,
      "recommendations": ["clarify event-time estimand"]
    },
    {
      "role": "measurement",
      "verdict": "PASS",
      "critical_issues_count": 0,
      "recommendations": ["document educational expectations scale"]
    },
    {
      "role": "theory_mechanism",
      "verdict": "PASS",
      "critical_issues_count": 0,
      "recommendations": ["connect income shock to feasibility beliefs"]
    },
    {
      "role": "feasibility_data",
      "verdict": "PASS",
      "critical_issues_count": 0,
      "recommendations": ["check attrition"]
    },
    {
      "role": "journal_skeptic",
      "verdict": "PASS",
      "critical_issues_count": 0,
      "recommendations": ["avoid overclaiming causality"]
    }
  ]
}
JSON
printf 'Design evaluation panel passed after revisions.\n' > "$DESIGN_PROJ/design/design-evaluation.md"
cat > "$DESIGN_PROJ/design/design-revision-log.json" <<'JSON'
{
  "required_revisions_completed": true,
  "unresolved_critical_count": 0,
  "final_verdict": "PASS",
  "revision_rounds": [
    {
      "round": 1,
      "status": "resolved",
      "issue_id": "D-001",
      "action_taken": "Added event-study pretrend robustness and attrition weighting to the design.",
      "affected_files": [
        "design/design-blueprint.md",
        "design/identification-strategy.json",
        "design/model-specs.json"
      ]
    }
  ]
}
JSON
printf 'Revision log: all critical design issues resolved.\n' > "$DESIGN_PROJ/design/design-revision-log.md"
# CASE_ID: phase.3.positive
expect_pass phase.3.positive "$DESIGN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$DESIGN_PROJ"

BAD_DESIGN_CAUSAL_PROJ="$TMP/bad-design-causal-project"
cp -R "$DESIGN_PROJ" "$BAD_DESIGN_CAUSAL_PROJ"
python3 - "$BAD_DESIGN_CAUSAL_PROJ/design/identification-strategy.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["causal_gate"]["invoked"] = False
doc["causal_gate"].pop("skill", None)
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.3.negative
expect_reject phase.3.negative "$BAD_DESIGN_CAUSAL_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$BAD_DESIGN_CAUSAL_PROJ"

BAD_DESIGN_HYP_PROJ="$TMP/bad-design-hypothesis-project"
cp -R "$DESIGN_PROJ" "$BAD_DESIGN_HYP_PROJ"
python3 - "$BAD_DESIGN_HYP_PROJ/design/identification-strategy.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["hypothesis_model_coverage"] = []
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p3.reject.hypothesis-model-coverage
expect_reject l2.p3.reject.hypothesis-model-coverage "$BAD_DESIGN_HYP_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$BAD_DESIGN_HYP_PROJ"

BAD_DESIGN_PROJ="$TMP/bad-design-project"
cp -R "$LIT_PROJ" "$BAD_DESIGN_PROJ"
mkdir -p "$BAD_DESIGN_PROJ/design"
printf 'Too short.\n' > "$BAD_DESIGN_PROJ/design/design-blueprint.md"
cat > "$BAD_DESIGN_PROJ/design/identification-strategy.json" <<'JSON'
{
  "design_type": "TBD",
  "estimand": "unknown",
  "identification_strategy": "TBD",
  "assumptions": [],
  "measures": {
    "x": {"name": "X"},
    "y": {"name": "Y"}
  },
  "threats": [],
  "robustness_plan": []
}
JSON
cat > "$BAD_DESIGN_PROJ/design/model-specs.json" <<'JSON'
{"models": [{"id": "M1"}]}
JSON
printf '{}\n' > "$BAD_DESIGN_PROJ/design/design-evaluation.json"
printf 'Bad evaluation.\n' > "$BAD_DESIGN_PROJ/design/design-evaluation.md"
printf '{}\n' > "$BAD_DESIGN_PROJ/design/design-revision-log.json"
printf 'Bad revision log.\n' > "$BAD_DESIGN_PROJ/design/design-revision-log.md"
# CASE_ID: l2.p3.reject.missing-manifest
expect_reject l2.p3.reject.missing-manifest "$BAD_DESIGN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$BAD_DESIGN_PROJ"

UNRESOLVED_DESIGN_PROJ="$TMP/unresolved-design-project"
cp -R "$LIT_PROJ" "$UNRESOLVED_DESIGN_PROJ"
mkdir -p "$UNRESOLVED_DESIGN_PROJ/design"
cp "$DESIGN_PROJ/design/design-blueprint.md" "$UNRESOLVED_DESIGN_PROJ/design/design-blueprint.md"
cp "$DESIGN_PROJ/design/identification-strategy.json" "$UNRESOLVED_DESIGN_PROJ/design/identification-strategy.json"
cp "$DESIGN_PROJ/design/model-specs.json" "$UNRESOLVED_DESIGN_PROJ/design/model-specs.json"
cp "$DESIGN_PROJ/design/design-manifest.json" "$UNRESOLVED_DESIGN_PROJ/design/design-manifest.json"
cp "$DESIGN_PROJ/design/design-evaluation.md" "$UNRESOLVED_DESIGN_PROJ/design/design-evaluation.md"
cp "$DESIGN_PROJ/design/design-revision-log.md" "$UNRESOLVED_DESIGN_PROJ/design/design-revision-log.md"
cat > "$UNRESOLVED_DESIGN_PROJ/design/design-evaluation.json" <<'JSON'
{
  "overall_verdict": "REVISE",
  "unresolved_critical_count": 1,
  "reviewers": [
    {"role": "identification", "verdict": "RED", "critical_issues_count": 1},
    {"role": "measurement", "verdict": "PASS", "critical_issues_count": 0},
    {"role": "theory_mechanism", "verdict": "PASS", "critical_issues_count": 0},
    {"role": "feasibility_data", "verdict": "PASS", "critical_issues_count": 0},
    {"role": "journal_skeptic", "verdict": "PASS", "critical_issues_count": 0}
  ]
}
JSON
cat > "$UNRESOLVED_DESIGN_PROJ/design/design-revision-log.json" <<'JSON'
{
  "required_revisions_completed": false,
  "unresolved_critical_count": 1,
  "final_verdict": "REVISE",
  "revision_rounds": [
    {
      "round": 1,
      "status": "unresolved",
      "affected_files": ["design/design-blueprint.md"]
    }
  ]
}
JSON
# CASE_ID: l2.p3.reject.evaluation-revise
expect_reject l2.p3.reject.evaluation-revise "$UNRESOLVED_DESIGN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$UNRESOLVED_DESIGN_PROJ"

DATA_PROJ="$TMP/data-project"
cp -R "$DESIGN_PROJ" "$DATA_PROJ"
mkdir -p "$DATA_PROJ/data" "$DATA_PROJ/safety"
cat > "$DATA_PROJ/safety/safety-status.json" <<'JSON'
{
  "safety_status": "PASS",
  "files_scanned": 1,
  "high_risk_unresolved": 0,
  "status_by_file": {
    "data/raw/panel.csv": {
      "status": "PASS",
      "risk": "low",
      "rationale": "Public-use fixture file without direct identifiers."
    }
  }
}
JSON
cat > "$DATA_PROJ/data/data-status.json" <<'JSON'
{
  "data_status": "existing-data",
  "access_status": "available",
  "irb_status": "exempt",
  "source_type": "public",
  "files": [
    {
      "path": "data/raw/panel.csv",
      "source": "public household panel fixture",
      "provenance": "copied into project raw data after Phase 0 safety scan",
      "safety_status": "PASS"
    }
  ],
  "dataset_fit": {
    "verdict": "PASS",
    "unit_of_analysis": "adolescent-wave",
    "population": "low-income households with adolescent respondents",
    "time_period": "repeated survey waves surrounding parental job loss",
    "key_variables_available": true,
    "sample_size_feasibility": "sufficient for primary fixed-effects model and attrition robustness in the fixture plan",
    "access_timeline": "available immediately as public-use data"
  },
  "dataset_design_review": {
    "reviewed": true,
    "panel_structure_reviewed": true,
    "weights_reviewed": true,
    "clustering_reviewed": true,
    "sampling_frame_reviewed": true,
    "analytic_decision": "Use adolescent-wave panel structure with household fixed effects and report weights as a robustness design feature.",
    "accepted_limitations": [
      "The public-use fixture does not reproduce the full production survey design documentation."
    ],
    "limitation_rationale": "The fixture records the panel and weighting decision while limiting the example to reproducible public-use test data."
  }
}
JSON
cat > "$DATA_PROJ/data/variable-dictionary.csv" <<'CSV'
variable,role,construct,display_label,table_stub_label,manuscript_term,levels_display,operationalization,source,missing_values,design_source,post_treatment,measurement_quality
job_loss,x,parental job loss,Parental Job Loss,Parental job loss,parental job loss,binary indicator: 1 = parent experienced job loss between waves,indicator for transition from employed to unemployed between waves,panel.csv,0/NA,design/identification-strategy.json x,no,validated transition indicator with wave timing
edu_expect,y,adolescent educational expectations,Educational Expectations,Educational expectations,educational expectations,ordinal scale of expected highest degree,expected highest degree scale reported by adolescent,panel.csv,NA/refused,design/identification-strategy.json y,no,ordinal expectation measure treated cautiously
age,control,child age,Child Age,Child age,child age,continuous years measure,age in years at interview,panel.csv,system missing,design/model-specs.json covariate,no,standard demographic control measured at interview
wave,control,wave,Survey Wave,Survey wave,survey wave,categorical survey wave indicator,survey wave indicator,panel.csv,none,design/model-specs.json covariate,no,administrative wave marker
income,control,household income,Household Income,Household income,household income,continuous prior-year household income,total household income in prior year,panel.csv,negative/NA,design/model-specs.json covariate,no,self-reported income harmonized across waves
CSV
python3 - "$DATA_PROJ/data/measurement-plan.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "The measurement plan documents measurement validity by linking each variable to the construct in the design, describes missing data handling through explicit missing codes and sensitivity checks, states sample restrictions for low-income households with adolescent respondents, and explains access and IRB implications for public exempt data. It records data provenance from the raw panel file, data security through project-local storage and no identifier export, data sharing constraints for public-use replication, dataset fit for the adolescent-wave unit of analysis, variable coverage for design measures and model covariates, post-treatment review showing that no planned control is downstream of parental job loss, survey design decisions for panel weights and clustering, and outcome family handling for the ordinal educational-expectations measure. "
with open(path, "w", encoding="utf-8") as f:
    f.write(sentence * 8)
PY
python3 - "$DATA_PROJ" <<'PY'
import csv
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

with (proj / "data/data-status.json").open(encoding="utf-8") as f:
    data_status = json.load(f)
with (proj / "data/variable-dictionary.csv").open(newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))
names = {row["construct"]: row["variable"] for row in rows}
manifest = {
    "verdict": "PASS",
    "source_phase": "4",
    "data_engine": {
        "skill": "scholar-data",
        "mode": "data_measurement_plan",
        "task_invocation_id": "phase4-data-001",
        "invoked_at_utc": "2026-04-28T11:00:00Z",
        "input_artifacts": [
            "design/design-blueprint.md",
            "design/identification-strategy.json",
            "design/model-specs.json",
            "safety/safety-status.json"
        ],
        "output_artifacts": [
            "data/data-status.json",
            "data/variable-dictionary.csv",
            "data/measurement-plan.md",
            "data/data-measurement-manifest.json"
        ]
    },
    "source_hashes": {
        "safety_status": sha(proj / "safety/safety-status.json"),
        "design_blueprint": sha(proj / "design/design-blueprint.md"),
        "design_manifest": sha(proj / "design/design-manifest.json"),
        "identification_strategy": sha(proj / "design/identification-strategy.json"),
        "model_specs": sha(proj / "design/model-specs.json")
    },
    "output_hashes": {
        "data_status": sha(proj / "data/data-status.json"),
        "variable_dictionary": sha(proj / "data/variable-dictionary.csv"),
        "measurement_plan": sha(proj / "data/measurement-plan.md")
    },
    "dataset_fit": data_status["dataset_fit"],
    "dataset_design_review": data_status["dataset_design_review"],
    "outcome_family_screen": {
        "screened": True,
        "outcome_families": [
            {
                "outcome": "adolescent educational expectations",
                "family": "ordinal",
                "planned_model": "household fixed effects linear model with ordinal-measure robustness discussion",
                "decision": "Treat the scale as approximately ordered in the main model and discuss interpretation limits."
            }
        ],
        "phase5_implication": "Phase 5 must keep the ordinal outcome interpretation visible when translating the model plan into executable scripts."
    },
    "variable_coverage": {
        "design_measures": [
            {"name": "parental job loss", "variable": names["parental job loss"], "covered": True},
            {"name": "adolescent educational expectations", "variable": names["adolescent educational expectations"], "covered": True}
        ],
        "model_variables": [
            {"name": "adolescent educational expectations", "variable": names["adolescent educational expectations"], "covered": True},
            {"name": "parental job loss", "variable": names["parental job loss"], "covered": True},
            {"name": "child age", "variable": names["child age"], "covered": True},
            {"name": "wave", "variable": names["wave"], "covered": True},
            {"name": "household income", "variable": names["household income"], "covered": True}
        ],
        "accepted_limitations": []
    },
    "display_semantics": {
        "reader_facing_labels_complete": True,
        "machine_labels_eliminated": True,
        "ready_for_tables": True,
        "machine_like_variable_count": 2,
        "label_source": "data/variable-dictionary.csv"
    },
    "safety_provenance": {
        "files_scanned": 1,
        "high_risk_unresolved": 0
    },
    "post_treatment_review": {
        "reviewed": True,
        "unresolved_count": 0,
        "post_treatment_controls": []
    },
    "codebook_validation": {
        "reviewed": True,
        "value_labels_checked": True,
        "valid_ranges_checked": True,
        "missing_codes_checked": True,
        "skip_logic_checked": True,
        "measurement_units_checked": True
    },
    "ready_for_phase_5": True
}
(proj / "data/data-measurement-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.4.positive
expect_pass phase.4.positive "$DATA_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$DATA_PROJ"

BAD_DATA_MODEL_VAR_PROJ="$TMP/bad-data-model-variable-project"
cp -R "$DATA_PROJ" "$BAD_DATA_MODEL_VAR_PROJ"
python3 - "$BAD_DATA_MODEL_VAR_PROJ/data/variable-dictionary.csv" <<'PY'
import csv
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
with path.open(newline="", encoding="utf-8") as f:
    rows = [row for row in csv.DictReader(f) if row["construct"] != "wave"]
fieldnames = list(rows[0].keys())
with path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
PY
# CASE_ID: phase.4.negative
expect_reject phase.4.negative "$BAD_DATA_MODEL_VAR_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$BAD_DATA_MODEL_VAR_PROJ"

BAD_DATA_DISPLAY_PROJ="$TMP/bad-data-display-project"
cp -R "$DATA_PROJ" "$BAD_DATA_DISPLAY_PROJ"
python3 - "$BAD_DATA_DISPLAY_PROJ/data/variable-dictionary.csv" "$BAD_DATA_DISPLAY_PROJ/data/data-measurement-manifest.json" <<'PY'
import csv
import hashlib
import json
import pathlib
import sys
csv_path = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
with csv_path.open(newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))
fieldnames = list(rows[0].keys())
rows[0]["display_label"] = rows[0]["variable"]
rows[0]["table_stub_label"] = rows[0]["variable"]
rows[0]["manuscript_term"] = rows[0]["variable"]
with csv_path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
manifest = json.loads(manifest_path.read_text())
manifest["display_semantics"]["machine_like_variable_count"] = 2
manifest["output_hashes"]["variable_dictionary"] = sha(csv_path)
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p4.reject.display-semantics
expect_reject l2.p4.reject.display-semantics "$BAD_DATA_DISPLAY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$BAD_DATA_DISPLAY_PROJ"

BAD_DATA_SAFETY_PROJ="$TMP/bad-data-safety-project"
cp -R "$DATA_PROJ" "$BAD_DATA_SAFETY_PROJ"
python3 - "$BAD_DATA_SAFETY_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

safety_path = proj / "safety/safety-status.json"
safety = json.loads(safety_path.read_text())
safety["files_scanned"] = 0
safety["status_by_file"] = {}
safety_path.write_text(json.dumps(safety, indent=2, sort_keys=True) + "\n")
manifest_path = proj / "data/data-measurement-manifest.json"
manifest = json.loads(manifest_path.read_text())
manifest["source_hashes"]["safety_status"] = sha(safety_path)
manifest["safety_provenance"]["files_scanned"] = 0
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p4.reject.safety-scan
expect_reject l2.p4.reject.safety-scan "$BAD_DATA_SAFETY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$BAD_DATA_SAFETY_PROJ"

BAD_DATA_PROJ="$TMP/bad-data-project"
mkdir -p "$BAD_DATA_PROJ/data"
cat > "$BAD_DATA_PROJ/data/data-status.json" <<'JSON'
{
  "data_status": "existing-data",
  "access_status": "not-applicable",
  "irb_status": "unknown",
  "source_type": "public",
  "files": []
}
JSON
cat > "$BAD_DATA_PROJ/data/variable-dictionary.csv" <<'CSV'
variable,role,construct
job_loss,x,parental job loss
CSV
printf 'Too short.\n' > "$BAD_DATA_PROJ/data/measurement-plan.md"
# CASE_ID: l2.p4.reject.missing-manifest
expect_reject l2.p4.reject.missing-manifest "$BAD_DATA_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$BAD_DATA_PROJ"

# A rejection with the right exit status but a different production diagnostic
# must not satisfy the authoritative negative-case assertion.
if [[ "${SCHOLAR_FIXTURE_PHASE0_4_WRONG_REASON:-0}" != "1" ]]; then
  WRONG_REASON_OUT="$TMP/phase0-4-wrong-reason.out"
  if (
    unset SCHOLAR_HARNESS_SOURCE_ROOT SCHOLAR_HARNESS_MANIFEST
    unset SCHOLAR_HARNESS_RESULTS_DIR SCHOLAR_HARNESS_RUN_ID SCHOLAR_HARNESS_RUN_NONCE
    unset SCHOLAR_HARNESS_SUITE_MODE SCHOLAR_HARNESS_SUITE_ORDER
    unset SCHOLAR_HARNESS_MANIFEST_SHA256 SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256
    unset SCHOLAR_HARNESS_CAPABILITY
    export SCHOLAR_FIXTURE_PHASE0_4_WRONG_REASON=1
    export SCHOLAR_FIXTURE_STOP_AFTER_PHASE=4
    bash "$SCRIPT_DIR/auto-research-fixture-test.sh"
  ) >"$WRONG_REASON_OUT" 2>&1; then
    echo "FAIL: phase 0-4 wrong-reason mutation unexpectedly passed" >&2
    exit 1
  fi
  grep -F 'HARNESS_ASSERTION_FAILED: case=phase.1.negative exact diagnostic count expected=1 observed=0;' \
    "$WRONG_REASON_OUT" >/dev/null \
    || {
      echo "FAIL: phase 0-4 wrong-reason mutation did not fail at the exact diagnostic gate" >&2
      exit 1
    }
fi

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "4" ]]; then
  harness_validate_results --phase-through 4 >/dev/null
  progress "phases 0 to 4 authoritative harness assertions passed"
  exit 0
fi

ANALYSIS_PLAN_PROJ="$TMP/analysis-plan-project"
progress "phases 5 to 8 planning, review, premortem, and execution fixtures"
cp -R "$DATA_PROJ" "$ANALYSIS_PLAN_PROJ"
mkdir -p "$ANALYSIS_PLAN_PROJ/analysis"
python3 - "$ANALYSIS_PLAN_PROJ/analysis/analysis-plan.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "The analysis plan specifies the model sequence, hypothesis to spec mapping, robustness checks, missing data handling, variable construction plan, script inventory, test inventory, no execution boundary, and pre-execution review handoff before any analysis is executed. It carries forward the survey design and panel dataset decision by considering weights, clustering, denominator rules, and the adolescent-wave panel structure, and it records an outcome family ladder for the ordinal educational-expectations measure alongside post-restriction missingness, complete-case sensitivity, and skip-code checks. "
with open(path, "w", encoding="utf-8") as f:
    f.write(sentence * 25)
PY
cat > "$ANALYSIS_PLAN_PROJ/analysis/spec-registry.csv" <<'CSV'
spec_id,model_id,hypothesis_ids,outcome,predictors,covariates,estimator,purpose,robustness_type,missing_data_strategy,status
S1,M1,H1,adolescent educational expectations,parental job loss,child age;wave;household income,household fixed effects linear model,primary estimate,primary,complete-case plus missingness indicators aligned with Phase 4 plan,planned
S2,M1,H1,adolescent educational expectations,parental job loss,child age;wave;household income,event-study fixed effects model,pretrend and timing robustness,event-study pretrend robustness check,complete-case plus missingness indicators aligned with Phase 4 plan,planned
S3,M1,H1,adolescent educational expectations,parental job loss,child age;wave;household income,weighted household fixed effects model,attrition robustness,inverse probability attrition robustness weights,complete-case plus missingness indicators aligned with Phase 4 plan,planned
CSV
cat > "$ANALYSIS_PLAN_PROJ/analysis/scripts-inventory.json" <<'JSON'
{
  "no_execution_yet": true,
  "script_order": [
    "analysis/scripts/01_load_data.R",
    "analysis/scripts/02_build_sample.R",
    "analysis/scripts/03_construct_variables.R",
    "analysis/scripts/04_plan_models.R"
  ],
  "dependency_graph": {
    "analysis/scripts/01_load_data.R": [],
    "analysis/scripts/02_build_sample.R": ["analysis/scripts/01_load_data.R"],
    "analysis/scripts/03_construct_variables.R": ["analysis/scripts/02_build_sample.R"],
    "analysis/scripts/04_plan_models.R": ["analysis/scripts/03_construct_variables.R"]
  },
  "scripts": [
    {
      "path": "analysis/scripts/01_load_data.R",
      "purpose": "load public panel file without running models",
      "uses": ["data/raw/panel.csv"],
      "produces": ["data/interim/panel-loaded.rds"],
      "status": "planned"
    },
    {
      "path": "analysis/scripts/02_build_sample.R",
      "purpose": "construct analytic sample",
      "uses": ["data/interim/panel-loaded.rds"],
      "produces": ["data/processed/analytic-sample.rds"],
      "status": "planned"
    },
    {
      "path": "analysis/scripts/03_construct_variables.R",
      "purpose": "construct model variables and missingness indicators",
      "uses": ["data/processed/analytic-sample.rds"],
      "produces": ["data/processed/analytic-variables.rds"],
      "status": "planned"
    },
    {
      "path": "analysis/scripts/04_plan_models.R",
      "purpose": "prepare planned model calls without executing them",
      "uses": ["data/processed/analytic-variables.rds", "analysis/spec-registry.csv"],
      "produces": ["analysis/planned-model-calls.json"],
      "status": "planned"
    }
  ],
  "test_inventory": [
    {
      "id": "T1",
      "target": "analysis/scripts/01_load_data.R",
      "category": "data_loading",
      "assertion": "source file loads and required columns are present",
      "status": "planned"
    },
    {
      "id": "T2",
      "target": "analysis/scripts/02_build_sample.R",
      "category": "analytic_sample",
      "assertion": "analytic sample has nonzero rows and correct unit of analysis",
      "status": "planned"
    },
    {
      "id": "T3",
      "target": "analysis/scripts/03_construct_variables.R",
      "category": "variable_construction",
      "assertion": "constructed variables match the Phase 4 variable dictionary",
      "status": "planned"
    },
    {
      "id": "T4",
      "target": "analysis/scripts/03_construct_variables.R",
      "category": "missingness",
      "assertion": "missing value codes and indicators match the Phase 4 missing data plan",
      "status": "planned"
    },
    {
      "id": "T5",
      "target": "analysis/scripts/04_plan_models.R",
      "category": "model_spec",
      "spec_ids": ["S1", "S2", "S3"],
      "assertion": "every planned spec has a non-executed model call and valid variables",
      "status": "planned"
    },
    {
      "id": "T6",
      "target": "analysis/scripts/04_plan_models.R",
      "category": "output_registry",
      "assertion": "planned result and figure registry schemas can be written during Phase 8",
      "status": "planned"
    }
  ]
}
JSON
python3 - "$ANALYSIS_PLAN_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

manifest = {
    "verdict": "PASS",
    "source_phase": "5",
    "analysis_planning_engine": {
        "skill": "scholar-auto-research",
        "mode": "analysis_plan_compiler"
    },
    "source_hashes": {
        "design_manifest": sha(proj / "design/design-manifest.json"),
        "identification_strategy": sha(proj / "design/identification-strategy.json"),
        "model_specs": sha(proj / "design/model-specs.json"),
        "data_status": sha(proj / "data/data-status.json"),
        "variable_dictionary": sha(proj / "data/variable-dictionary.csv"),
        "data_measurement_manifest": sha(proj / "data/data-measurement-manifest.json"),
        "measurement_plan": sha(proj / "data/measurement-plan.md")
    },
    "output_hashes": {
        "analysis_plan": sha(proj / "analysis/analysis-plan.md"),
        "spec_registry": sha(proj / "analysis/spec-registry.csv"),
        "scripts_inventory": sha(proj / "analysis/scripts-inventory.json")
    },
    "model_spec_coverage": [
        {"model_id": "M1", "covered": True, "spec_ids": ["S1", "S2", "S3"]}
    ],
    "hypothesis_spec_coverage": [
        {"hypothesis_id": "H1", "covered": True, "spec_ids": ["S1", "S2", "S3"]}
    ],
    "variable_coverage": [
        {"name": "adolescent educational expectations", "covered": True},
        {"name": "parental job loss", "covered": True},
        {"name": "child age", "covered": True},
        {"name": "wave", "covered": True},
        {"name": "household income", "covered": True}
    ],
    "robustness_coverage": [
        {"design_item": "event-study pretrend check", "covered": True, "spec_ids": ["S2"]},
        {"design_item": "inverse probability attrition weights", "covered": True, "spec_ids": ["S3"]}
    ],
    "missing_data_alignment": {
        "strategy_matches_phase4": True,
        "variable_dictionary_hash": sha(proj / "data/variable-dictionary.csv")
    },
    "dataset_design_plan": {
        "reviewed": True,
        "weights_considered": True,
        "clustering_considered": True,
        "panel_structure_considered": True,
        "denominator_rules_considered": True,
        "analytic_decision": "Use adolescent-wave panel structure with household fixed effects and report weights as a robustness design feature.",
        "decision_rationale": "This inherits the Phase 4 panel and weighting review while keeping the primary model aligned with the planned within-household comparison."
    },
    "outcome_model_ladder": {
        "outcome_family": "ordinal",
        "headline_estimator": "household fixed effects linear model",
        "sensitivity_specs": [
            {
                "spec_id": "S2",
                "rationale": "Timing robustness checks whether the ordered expectation pattern is sensitive to event timing."
            },
            {
                "spec_id": "S3",
                "rationale": "Attrition-weighted robustness checks whether sample composition changes the ordinal-outcome estimate."
            }
        ],
        "bounded_scale_checked": True,
        "distributional_diagnostics_planned": True
    },
    "missingness_sensitivity_plan": {
        "post_restriction_diagnostics": True,
        "denominator_checks": True,
        "skip_vs_missing_reviewed": True,
        "sensitivity_specs": ["S3"],
        "rationale": "The plan checks complete-case restrictions, denominator stability, and skip-code handling before interpreting model estimates."
    },
    "script_dag": {
        "valid": True,
        "script_order": [
            "analysis/scripts/01_load_data.R",
            "analysis/scripts/02_build_sample.R",
            "analysis/scripts/03_construct_variables.R",
            "analysis/scripts/04_plan_models.R"
        ]
    },
    "test_coverage": {
        "categories": ["data_loading", "analytic_sample", "variable_construction", "missingness", "model_spec", "output_registry"],
        "spec_ids": ["S1", "S2", "S3"]
    },
    "ready_for_phase_6": True
}
(proj / "analysis/analysis-plan-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.5.positive
expect_pass phase.5.positive "$ANALYSIS_PLAN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 5 "$ANALYSIS_PLAN_PROJ"

BAD_ANALYSIS_HYP_PROJ="$TMP/bad-analysis-hypothesis-project"
cp -R "$ANALYSIS_PLAN_PROJ" "$BAD_ANALYSIS_HYP_PROJ"
python3 - "$BAD_ANALYSIS_HYP_PROJ/analysis/spec-registry.csv" <<'PY'
import csv
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
with path.open(newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))
for row in rows:
    row["hypothesis_ids"] = ""
with path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)
PY
if [[ "${SCHOLAR_FIXTURE_PHASE5_9_WRONG_REASON:-0}" == "1" ]]; then
  mv "$BAD_ANALYSIS_HYP_PROJ/analysis/analysis-plan-manifest.json" \
    "$BAD_ANALYSIS_HYP_PROJ/analysis/analysis-plan-manifest.wrong-reason"
fi
# CASE_ID: phase.5.negative
expect_reject phase.5.negative "$BAD_ANALYSIS_HYP_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 5 "$BAD_ANALYSIS_HYP_PROJ"

BAD_ANALYSIS_DAG_PROJ="$TMP/bad-analysis-dag-project"
cp -R "$ANALYSIS_PLAN_PROJ" "$BAD_ANALYSIS_DAG_PROJ"
python3 - "$BAD_ANALYSIS_DAG_PROJ/analysis/scripts-inventory.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["dependency_graph"]["analysis/scripts/02_build_sample.R"] = ["analysis/scripts/04_plan_models.R"]
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p5.reject.script-dag
expect_reject l2.p5.reject.script-dag "$BAD_ANALYSIS_DAG_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 5 "$BAD_ANALYSIS_DAG_PROJ"

BAD_ANALYSIS_PLAN_PROJ="$TMP/bad-analysis-plan-project"
mkdir -p "$BAD_ANALYSIS_PLAN_PROJ/analysis" "$BAD_ANALYSIS_PLAN_PROJ/tables"
printf 'Too short.\n' > "$BAD_ANALYSIS_PLAN_PROJ/analysis/analysis-plan.md"
cat > "$BAD_ANALYSIS_PLAN_PROJ/analysis/spec-registry.csv" <<'CSV'
spec_id,model_id,outcome,predictors,estimator,purpose,status
S1,M1,Y,X,OLS,TBD,executed
CSV
cat > "$BAD_ANALYSIS_PLAN_PROJ/analysis/scripts-inventory.json" <<'JSON'
{
  "no_execution_yet": false,
  "scripts": [
    {
      "path": "analysis/scripts/02_models.R",
      "purpose": "estimate models",
      "produces": "tables/results-registry.csv",
      "status": "executed"
    }
  ],
  "test_inventory": []
}
JSON
printf 'spec_id,result\nS1,0.1\n' > "$BAD_ANALYSIS_PLAN_PROJ/tables/results-registry.csv"
# CASE_ID: l2.p5.reject.missing-manifest
expect_reject l2.p5.reject.missing-manifest "$BAD_ANALYSIS_PLAN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 5 "$BAD_ANALYSIS_PLAN_PROJ"

PREEXEC_PROJ="$TMP/preexec-project"
cp -R "$ANALYSIS_PLAN_PROJ" "$PREEXEC_PROJ"
mkdir -p "$PREEXEC_PROJ/review/agents"
for role in correctness robustness statistical reproducibility style_ai_patterns data_handling; do
  printf 'Independent %s reviewer report. The planned scripts, tests, and model specifications were checked before execution. No critical defect remains for this role.\n' "$role" > "$PREEXEC_PROJ/review/agents/$role.md"
done
python3 - "$PREEXEC_PROJ" <<'PY'
import csv
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

inventory = json.loads((proj / "analysis/scripts-inventory.json").read_text())
script_paths = [script["path"] for script in inventory["scripts"]]
test_ids = [test["id"] for test in inventory["test_inventory"]]
with (proj / "analysis/spec-registry.csv").open(newline="", encoding="utf-8") as f:
    spec_ids = [row["spec_id"] for row in csv.DictReader(f)]
roles = ["correctness", "robustness", "statistical", "reproducibility", "style_ai_patterns", "data_handling"]
upstream = [
    "analysis/analysis-plan.md",
    "analysis/analysis-plan-manifest.json",
    "analysis/scripts-inventory.json",
    "analysis/spec-registry.csv",
    "design/identification-strategy.json",
    "design/model-specs.json",
    "data/variable-dictionary.csv",
    "data/data-measurement-manifest.json",
]
review = {
    "verdict": "PASS",
    "degraded": False,
    "review_engine": {
        "skill": "scholar-code-review",
        "mode": "pre_execution_planned",
        "task_invocation_id": "phase6-code-review-001",
        "invoked_at_utc": "2026-04-29T08:30:00Z",
        "input_artifacts": [
            "analysis/analysis-plan.md",
            "analysis/scripts-inventory.json",
            "analysis/spec-registry.csv",
            "design/identification-strategy.json",
            "data/variable-dictionary.csv"
        ],
        "output_artifacts": [
            "review/pre-execution-review.json",
            "review/pre-execution-fix-log.json",
            "review/pre-execution-rereview.json"
        ]
    },
    "source_hashes": {
        "analysis_plan": sha(proj / "analysis/analysis-plan.md"),
        "analysis_plan_manifest": sha(proj / "analysis/analysis-plan-manifest.json"),
        "scripts_inventory": sha(proj / "analysis/scripts-inventory.json"),
        "spec_registry": sha(proj / "analysis/spec-registry.csv"),
        "identification_strategy": sha(proj / "design/identification-strategy.json"),
        "model_specs": sha(proj / "design/model-specs.json"),
        "variable_dictionary": sha(proj / "data/variable-dictionary.csv"),
        "data_measurement_manifest": sha(proj / "data/data-measurement-manifest.json")
    },
    "inventory_hash": sha(proj / "analysis/scripts-inventory.json"),
    "ready_for_phase_7": True,
    "reviewers": [],
    "reviewed_scripts": [
        {
            "path": path,
            "status_in_inventory": "planned",
            "exists_or_stub_declared": True,
            "reviewed_by": roles
        }
        for path in script_paths
    ],
    "reviewed_specs": spec_ids,
    "reviewed_tests": test_ids,
    "reviewed_script_dag": {"reviewed": True, "status": "PASS", "reviewed_by": roles},
    "reviewed_spec_coverage": {"reviewed": True, "status": "PASS", "reviewed_by": roles},
    "reviewed_robustness_coverage": {"reviewed": True, "status": "PASS", "reviewed_by": roles},
    "reviewed_missing_data_alignment": {"reviewed": True, "status": "PASS", "reviewed_by": roles},
    "reviewed_no_execution_boundary": {"reviewed": True, "status": "PASS", "reviewed_by": roles},
    "blocking_findings": [],
    "unresolved_critical_count": 0,
    "fix_status": {
        "required": False,
        "all_blocking_fixed": True,
        "fix_log": "review/pre-execution-fix-log.json",
        "rereview": "review/pre-execution-rereview.json"
    }
}
for idx, role in enumerate(roles, start=1):
    review["reviewers"].append({
        "reviewer_id": f"A{idx}",
        "role": role,
        "agent_type": "scholar-code-review-preexecution-agent",
        "task_invocation_id": f"preexec-{role}-001",
        "report_path": f"review/agents/{role}.md",
        "reviewed_scripts": script_paths,
        "reviewed_specs": spec_ids,
        "reviewed_tests": test_ids,
        "reviewed_upstream_artifacts": upstream,
        "findings": [],
        "verdict": "PASS"
    })
(proj / "review/pre-execution-review.json").write_text(json.dumps(review, indent=2, sort_keys=True) + "\n")
PY
python3 - "$PREEXEC_PROJ/review/pre-execution-review.md" "$PREEXEC_PROJ/review/pre-execution-fix-log.md" <<'PY'
import sys
review_path, fix_path = sys.argv[1:3]
review_sentence = "Six independent scholar-code-review reviewers audited the planned scripts, statistical specifications, reproducibility checks, tests, script dependency graph, robustness coverage, missing data alignment, and no execution boundary before execution. "
fix_sentence = "The fix log records that no blocking repair was required and the re-review artifact confirms readiness for the next phase. "
with open(review_path, "w", encoding="utf-8") as f:
    f.write(review_sentence * 6)
with open(fix_path, "w", encoding="utf-8") as f:
    f.write(fix_sentence * 4)
PY
cat > "$PREEXEC_PROJ/review/pre-execution-fix-log.json" <<'JSON'
{
  "required_fixes_completed": true,
  "unfixed_blocking_count": 0,
  "final_verdict": "PASS",
  "fixed_findings": []
}
JSON
cat > "$PREEXEC_PROJ/review/pre-execution-rereview.json" <<'JSON'
{
  "verdict": "PASS",
  "degraded": false,
  "review_round": 2,
  "rereviewed_findings": [],
  "unresolved_blocking_count": 0,
  "ready_for_phase_7": true
}
JSON
python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$PREEXEC_PROJ" 6 initial_panel >/dev/null
# CASE_ID: phase.6.positive
expect_pass phase.6.positive "$PREEXEC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$PREEXEC_PROJ"

ACTIVE_REREVIEW_PROJ="$TMP/active-rereview-project"
cp -pR "$PREEXEC_PROJ" "$ACTIVE_REREVIEW_PROJ"
python3 - "$ACTIVE_REREVIEW_PROJ" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
review_path = project / "review/pre-execution-review.json"
review = json.loads(review_path.read_text())
review["fix_status"]["required"] = True
review_path.write_text(json.dumps(review, indent=2, sort_keys=True) + "\n")
fix_path = project / "review/pre-execution-fix-log.json"
fix_log = json.loads(fix_path.read_text())
fix_log["fixed_findings"] = [{
    "finding_id": "F09-REREVIEW-1", "status": "fixed",
    "action_taken": "corrected the planned robustness test inventory",
    "affected_files": ["analysis/analysis-plan.md"],
}]
fix_path.write_text(json.dumps(fix_log, indent=2, sort_keys=True) + "\n")
rereview_path = project / "review/pre-execution-rereview.json"
rereview = json.loads(rereview_path.read_text())
rereview.update({
    "evidence_role": "fix_verifier",
    "task_invocation_id": "legacy-rereview-placeholder",
    "report_path": "review/agents/fix_verifier.md",
    "rereviewed_findings": [{
        "finding_id": "F09-REREVIEW-1", "resolution_verdict": "RESOLVED",
    }],
})
rereview_path.write_text(json.dumps(rereview, indent=2, sort_keys=True) + "\n")
(project / "review/agents/fix_verifier.md").write_text(
    "Independent fix verification confirms the named planned-analysis repair and its evidence.\n"
)
PY
python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$ACTIVE_REREVIEW_PROJ" 6 fix_rereview >/dev/null
# CASE_ID: l2.p6.verify.active-rereview
expect_pass l2.p6.verify.active-rereview "$ACTIVE_REREVIEW_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$ACTIVE_REREVIEW_PROJ"

BAD_PREEXEC_ENGINE_PROJ="$TMP/bad-preexec-engine-project"
cp -R "$PREEXEC_PROJ" "$BAD_PREEXEC_ENGINE_PROJ"
python3 - "$BAD_PREEXEC_ENGINE_PROJ/review/pre-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["review_engine"] = {"skill": "manual-review", "mode": "pre_execution_planned"}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: phase.6.negative
expect_reject phase.6.negative "$BAD_PREEXEC_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_ENGINE_PROJ"

BAD_PREEXEC_DAG_PROJ="$TMP/bad-preexec-dag-project"
cp -R "$PREEXEC_PROJ" "$BAD_PREEXEC_DAG_PROJ"
python3 - "$BAD_PREEXEC_DAG_PROJ/review/pre-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewed_script_dag"]["reviewed"] = False
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p6.reject.review-dag
expect_reject l2.p6.reject.review-dag "$BAD_PREEXEC_DAG_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_DAG_PROJ"

BAD_PREEXEC_ROLE_PROJ="$TMP/bad-preexec-role-project"
cp -R "$PREEXEC_PROJ" "$BAD_PREEXEC_ROLE_PROJ"
python3 - "$BAD_PREEXEC_ROLE_PROJ/review/pre-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewers"] = [r for r in data["reviewers"] if r["role"] != "data_handling"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p6.reject.reviewer-role
expect_reject l2.p6.reject.reviewer-role "$BAD_PREEXEC_ROLE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_ROLE_PROJ"

BAD_PREEXEC_HASH_PROJ="$TMP/bad-preexec-hash-project"
cp -R "$PREEXEC_PROJ" "$BAD_PREEXEC_HASH_PROJ"
python3 - "$BAD_PREEXEC_HASH_PROJ/analysis/scripts-inventory.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["scripts"].append({
    "path": "analysis/scripts/03_robustness.R",
    "purpose": "estimate robustness checks",
    "produces": ["tables/robustness.csv"],
    "status": "planned"
})
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p6.reject.stale-input-hash
expect_reject l2.p6.reject.stale-input-hash "$BAD_PREEXEC_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_HASH_PROJ"

BAD_PREEXEC_SCRIPT_PROJ="$TMP/bad-preexec-script-project"
cp -R "$PREEXEC_PROJ" "$BAD_PREEXEC_SCRIPT_PROJ"
python3 - "$BAD_PREEXEC_SCRIPT_PROJ/review/pre-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewed_scripts"] = data["reviewed_scripts"][:1]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p6.reject.script-coverage
expect_reject l2.p6.reject.script-coverage "$BAD_PREEXEC_SCRIPT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_SCRIPT_PROJ"

BAD_PREEXEC_REREVIEW_PROJ="$TMP/bad-preexec-rereview-project"
cp -R "$PREEXEC_PROJ" "$BAD_PREEXEC_REREVIEW_PROJ"
python3 - "$BAD_PREEXEC_REREVIEW_PROJ/review/pre-execution-review.json" "$BAD_PREEXEC_REREVIEW_PROJ/review/pre-execution-fix-log.json" "$BAD_PREEXEC_REREVIEW_PROJ/review/pre-execution-rereview.json" <<'PY'
import json
import sys
review_path, fix_path, rereview_path = sys.argv[1:4]
with open(review_path, encoding="utf-8") as f:
    review = json.load(f)
review["fix_status"]["required"] = True
with open(review_path, "w", encoding="utf-8") as f:
    json.dump(review, f, indent=2, sort_keys=True)
with open(fix_path, encoding="utf-8") as f:
    fix = json.load(f)
fix["fixed_findings"] = [
    {
      "finding_id": "PX-001",
      "status": "fixed",
      "blocker_type": "executable",
      "action_taken": "Added missing test assertion before execution.",
      "affected_files": ["analysis/scripts-inventory.json"]
    }
]
with open(fix_path, "w", encoding="utf-8") as f:
    json.dump(fix, f, indent=2, sort_keys=True)
with open(rereview_path, encoding="utf-8") as f:
    rereview = json.load(f)
rereview["rereviewed_findings"] = [
    {"finding_id": "PX-001", "resolution_verdict": "STILL_OPEN"}
]
with open(rereview_path, "w", encoding="utf-8") as f:
    json.dump(rereview, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p6.reject.rereview-session
expect_reject l2.p6.reject.rereview-session "$BAD_PREEXEC_REREVIEW_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_REREVIEW_PROJ"

PREMORTEM_PROJ="$TMP/premortem-project"
cp -R "$PREEXEC_PROJ" "$PREMORTEM_PROJ"
mkdir -p "$PREMORTEM_PROJ/design" "$PREMORTEM_PROJ/data" "$PREMORTEM_PROJ/review/agents"
python3 - "$PREMORTEM_PROJ/analysis/analysis-plan.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "The analysis plan specifies the household fixed effects model, event-study robustness checks, missing data diagnostics, decision rules, test inventory, and pre-execution handoff before any analysis is executed. "
with open(path, "w", encoding="utf-8") as f:
    f.write(sentence * 24)
PY
cat > "$PREMORTEM_PROJ/design/identification-strategy.json" <<'JSON'
{
  "design_type": "observational panel design",
  "claim_strength": "associational",
  "estimand": "average within-household change in adolescent educational expectations after parental job loss",
  "identification_strategy": "household fixed effects with event-time indicators around parental job loss",
  "outcome_mechanism_alignment": "prevalence-stock",
  "journal_method_bar": "Quantitative family-demography evidence with careful observational interpretation and explicit robustness checks.",
  "hypothesis_model_coverage": [
    {
      "hypothesis_id": "H1",
      "model_ids": ["M1"],
      "coverage": "The primary model tests the planned association between parental job loss and adolescent expectations."
    }
  ],
  "power_or_feasibility_assessment": {
    "status": "feasible_existing_data",
    "rationale": "The panel data, planned scripts, and variable dictionary are sufficient for a cautious pre-execution audit."
  },
  "method_specialist_routing": {
    "method_orientation": "observational panel analysis",
    "primary_execution_skill": "scholar-analyze",
    "premortem_skill": "scholar-analyze",
    "supporting_skills": [],
    "rationale": "This project stays on the default quantitative route, so scholar-analyze owns the premortem and execution stages."
  },
  "causal_gate": {
    "required": true,
    "invoked": true,
    "skill": "scholar-causal"
  },
  "assumptions": [
    "No unmeasured time-varying shocks simultaneously cause job loss and expectation change",
    "Educational expectations are measured consistently before and after job loss"
  ],
  "measures": {
    "x": {"name": "parental job loss", "operationalization": "employment transition indicator"},
    "y": {"name": "adolescent educational expectations", "operationalization": "expected highest degree scale"}
  },
  "threats": ["anticipation", "attrition"],
  "robustness_plan": ["event-study pretrend check", "attrition weights"]
}
JSON
cat > "$PREMORTEM_PROJ/design/model-specs.json" <<'JSON'
{
  "models": [
    {
      "id": "M1",
      "outcome": "adolescent educational expectations",
      "predictors": ["parental job loss"],
      "estimator": "household fixed effects linear model",
      "covariates": ["child age", "wave", "household income"],
      "purpose": "primary estimate and robustness sequence"
    }
  ]
}
JSON
python3 - "$PREMORTEM_PROJ/data/measurement-plan.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "The measurement plan records construct validity, missing data codes, sample restrictions, access limits, IRB status, and sensitivity checks for parental job loss and adolescent educational expectations. "
with open(path, "w", encoding="utf-8") as f:
    f.write(sentence * 16)
PY
cat > "$PREMORTEM_PROJ/data/variable-dictionary.csv" <<'CSV'
variable,role,construct,operationalization,source,missing_values
job_loss,x,parental job loss,employment transition indicator,panel.csv,0/NA
edu_expect,y,adolescent educational expectations,expected highest degree scale,panel.csv,NA/refused
age,control,child age,age in years,panel.csv,system missing
income,control,household income,total household income,panel.csv,negative/NA
CSV
for role in identification measurement_missingness model_robustness interpretation_claims; do
  printf 'Independent %s premortem report. The reviewer inspected design, measurement, analysis plan, specifications, scripts, tests, and Phase 6 review artifacts before execution. No blocking risk remains for this role.\n' "$role" > "$PREMORTEM_PROJ/review/agents/premortem-$role.md"
done
IDENT_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/design/identification-strategy.json" | awk '{print $1}')"
MODEL_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/design/model-specs.json" | awk '{print $1}')"
MEASURE_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/data/measurement-plan.md" | awk '{print $1}')"
VARDICT_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/data/variable-dictionary.csv" | awk '{print $1}')"
PLAN_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/analysis/analysis-plan.md" | awk '{print $1}')"
SPEC_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/analysis/spec-registry.csv" | awk '{print $1}')"
INV_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/analysis/scripts-inventory.json" | awk '{print $1}')"
PREEXEC_REVIEW_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/review/pre-execution-review.json" | awk '{print $1}')"
PREEXEC_FIX_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/review/pre-execution-fix-log.json" | awk '{print $1}')"
PREEXEC_REREVIEW_HASH="$(shasum -a 256 "$PREMORTEM_PROJ/review/pre-execution-rereview.json" | awk '{print $1}')"
cat > "$PREMORTEM_PROJ/review/analysis-premortem.json" <<JSON
{
  "verdict": "PASS",
  "degraded": false,
  "ready_for_phase_8": true,
  "premortem_engine": {
    "skill": "scholar-analyze",
    "mode": "premortem",
    "auto_research_contract": "phase_7",
    "skip_premortem_ignored": true,
    "task_invocation_id": "phase7-premortem-001",
    "invoked_at_utc": "2026-04-29T10:20:00Z",
    "input_artifacts": [
      "design/identification-strategy.json",
      "design/model-specs.json",
      "analysis/analysis-plan.md",
      "analysis/spec-registry.csv",
      "analysis/scripts-inventory.json"
    ],
    "output_artifacts": [
      "review/analysis-premortem.json",
      "review/analysis-premortem.md",
      "review/analysis-premortem-fix-log.json"
    ]
  },
  "iteration": 1,
  "source_hashes": {
    "identification_strategy": "$IDENT_HASH",
    "model_specs": "$MODEL_HASH",
    "measurement_plan": "$MEASURE_HASH",
    "variable_dictionary": "$VARDICT_HASH",
    "analysis_plan": "$PLAN_HASH",
    "spec_registry": "$SPEC_HASH",
    "scripts_inventory": "$INV_HASH",
    "pre_execution_review": "$PREEXEC_REVIEW_HASH",
    "pre_execution_fix_log": "$PREEXEC_FIX_HASH",
    "pre_execution_rereview": "$PREEXEC_REREVIEW_HASH"
  },
  "reviewer_provenance": [
    {
      "reviewer_id": "P1",
      "role": "identification",
      "agent_name": "peer-reviewer-quant",
      "task_invocation_id": "premortem-identification-001",
      "dispatched_at_utc": "2026-04-29T10:30:00Z",
      "model_id": "gpt-5.5",
      "report_path": "review/agents/premortem-identification.md"
    },
    {
      "reviewer_id": "P2",
      "role": "measurement_missingness",
      "agent_name": "peer-reviewer-demographics",
      "task_invocation_id": "premortem-measurement-001",
      "dispatched_at_utc": "2026-04-29T10:30:00Z",
      "model_id": "gpt-5.5",
      "report_path": "review/agents/premortem-measurement_missingness.md"
    },
    {
      "reviewer_id": "P3",
      "role": "model_robustness",
      "agent_name": "peer-reviewer-senior",
      "task_invocation_id": "premortem-model-001",
      "dispatched_at_utc": "2026-04-29T10:30:00Z",
      "model_id": "gpt-5.5",
      "report_path": "review/agents/premortem-model_robustness.md"
    },
    {
      "reviewer_id": "P4",
      "role": "interpretation_claims",
      "agent_name": "peer-reviewer-theory",
      "task_invocation_id": "premortem-claims-001",
      "dispatched_at_utc": "2026-04-29T10:30:00Z",
      "model_id": "gpt-5.5",
      "report_path": "review/agents/premortem-interpretation_claims.md"
    }
  ],
  "reviewers": [
    {
      "reviewer_id": "P1",
      "role": "identification",
      "agent_type": "independent_codex_agent",
      "task_invocation_id": "premortem-identification-001",
      "report_path": "review/agents/premortem-identification.md",
      "reviewed_inputs": ["design/identification-strategy.json", "design/model-specs.json", "data/measurement-plan.md", "data/variable-dictionary.csv", "analysis/analysis-plan.md", "analysis/spec-registry.csv", "analysis/scripts-inventory.json", "review/pre-execution-review.json", "review/pre-execution-fix-log.json", "review/pre-execution-rereview.json"],
      "risks": ["R1", "R2"],
      "verdict": "PASS"
    },
    {
      "reviewer_id": "P2",
      "role": "measurement_missingness",
      "agent_type": "independent_codex_agent",
      "task_invocation_id": "premortem-measurement-001",
      "report_path": "review/agents/premortem-measurement_missingness.md",
      "reviewed_inputs": ["design/identification-strategy.json", "design/model-specs.json", "data/measurement-plan.md", "data/variable-dictionary.csv", "analysis/analysis-plan.md", "analysis/spec-registry.csv", "analysis/scripts-inventory.json", "review/pre-execution-review.json", "review/pre-execution-fix-log.json", "review/pre-execution-rereview.json"],
      "risks": ["R3", "R4"],
      "verdict": "PASS"
    },
    {
      "reviewer_id": "P3",
      "role": "model_robustness",
      "agent_type": "independent_codex_agent",
      "task_invocation_id": "premortem-model-001",
      "report_path": "review/agents/premortem-model_robustness.md",
      "reviewed_inputs": ["design/identification-strategy.json", "design/model-specs.json", "data/measurement-plan.md", "data/variable-dictionary.csv", "analysis/analysis-plan.md", "analysis/spec-registry.csv", "analysis/scripts-inventory.json", "review/pre-execution-review.json", "review/pre-execution-fix-log.json", "review/pre-execution-rereview.json"],
      "risks": ["R5", "R6", "R7"],
      "verdict": "PASS"
    },
    {
      "reviewer_id": "P4",
      "role": "interpretation_claims",
      "agent_type": "independent_codex_agent",
      "task_invocation_id": "premortem-claims-001",
      "report_path": "review/agents/premortem-interpretation_claims.md",
      "reviewed_inputs": ["design/identification-strategy.json", "design/model-specs.json", "data/measurement-plan.md", "data/variable-dictionary.csv", "analysis/analysis-plan.md", "analysis/spec-registry.csv", "analysis/scripts-inventory.json", "review/pre-execution-review.json", "review/pre-execution-fix-log.json", "review/pre-execution-rereview.json"],
      "risks": ["R8", "R9"],
      "verdict": "PASS"
    }
  ],
  "traffic_light_summary": [
    {"dimension": "identification", "verdict": "YELLOW", "lead_reviewer": "P1", "evidence": "Fixed-effects identification is coherent but requires cautious noncausal language."},
    {"dimension": "variable_construction", "verdict": "GREEN", "lead_reviewer": "P2", "evidence": "Variable construction is linked to the Phase 4 dictionary and planned construction script."},
    {"dimension": "sample_restrictions", "verdict": "GREEN", "lead_reviewer": "P2", "evidence": "Sample restrictions are explicit in the planned sample build script and tests."},
    {"dimension": "model_specification", "verdict": "YELLOW", "lead_reviewer": "P3", "evidence": "Primary model is aligned, with robustness checks required to bound fragility."},
    {"dimension": "standard_errors", "verdict": "GREEN", "lead_reviewer": "P3", "evidence": "The planned model call records clustered/robust variance handling for panel observations."},
    {"dimension": "missing_data", "verdict": "YELLOW", "lead_reviewer": "P2", "evidence": "Missingness needs diagnostics and attrition-weighted sensitivity before interpretation."},
    {"dimension": "robustness", "verdict": "GREEN", "lead_reviewer": "P3", "evidence": "S2 and S3 provide timing and attrition robustness checks."},
    {"dimension": "power_effect_size", "verdict": "YELLOW", "lead_reviewer": "P3", "evidence": "Power is feasible but null estimates must be interpreted with uncertainty."},
    {"dimension": "heterogeneity_multi_comparison", "verdict": "GREEN", "lead_reviewer": "P3", "evidence": "No K>=3 hypothesis family is planned in this fixture."},
    {"dimension": "mechanism_evidence", "verdict": "YELLOW", "lead_reviewer": "P4", "evidence": "Mechanism language must stay aligned with measured stress and feasibility proxies."},
    {"dimension": "table_figure_plan", "verdict": "GREEN", "lead_reviewer": "P3", "evidence": "The handoff requires result and figure registries before Phase 8 completion."},
    {"dimension": "preregistration_deviation", "verdict": "GREEN", "lead_reviewer": "P1", "evidence": "No preregistration deviation is introduced in the planned scripts."},
    {"dimension": "interpretive_reach", "verdict": "YELLOW", "lead_reviewer": "P4", "evidence": "The manuscript must concede weak or null robustness instead of reframing it as support."}
  ],
  "null_falsification_table": [
    {
      "hypothesis_id": "H1",
      "null_pattern": "Primary and robustness estimates near zero with confidence intervals excluding substantively meaningful negative effects would count against the expectation-lowering claim.",
      "precommitted": true,
      "discussion_concedes_null": true,
      "status": "PASS"
    }
  ],
  "reporting_depth_checklist": [
    {
      "risk_id": "R2",
      "diagnostic_outputs": ["event-time coefficient table", "pretrend p-value"],
      "sensitivity_range": "Report whether the negative direction survives event-study timing checks.",
      "failure_mode_disclosure": "Sparse event time cannot establish parallel pretrends or causal timing.",
      "reporting_location": "Results robustness paragraph and Appendix event-study table"
    },
    {
      "risk_id": "R4",
      "diagnostic_outputs": ["missingness rate table", "attrition-weighted sensitivity output"],
      "sensitivity_range": "Compare complete-case and attrition-weighted specifications.",
      "failure_mode_disclosure": "Differential attrition could bias observed expectation changes.",
      "reporting_location": "Methods missing-data subsection and Results robustness paragraph"
    },
    {
      "risk_id": "R5",
      "diagnostic_outputs": ["primary estimate", "event-study estimate", "attrition-weighted estimate"],
      "sensitivity_range": "Compare S1, S2, and S3 signs, magnitudes, and uncertainty intervals.",
      "failure_mode_disclosure": "Fixed-effects assumptions do not remove time-varying unobserved shocks.",
      "reporting_location": "Results table and robustness paragraph"
    },
    {
      "risk_id": "R9",
      "diagnostic_outputs": ["results registry", "figure registry", "execution halt-check log"],
      "sensitivity_range": "Confirm every planned spec and figure registry requirement is present before Phase 8 completion.",
      "failure_mode_disclosure": "Missing registries would make later manuscript verification rely on incomplete output evidence.",
      "reporting_location": "Phase 8 execution report and Phase 10 runtime sanity inventory"
    }
  ],
  "reviewed_scripts": ["analysis/scripts/01_load_data.R", "analysis/scripts/02_build_sample.R", "analysis/scripts/03_construct_variables.R", "analysis/scripts/04_plan_models.R"],
  "reviewed_specs": ["S1", "S2", "S3"],
  "reviewed_tests": ["T1", "T2", "T3", "T4", "T5", "T6"],
  "risk_register": [
    {"risk_id": "R1", "domain": "design_plan_alignment", "severity": "major", "description": "Analysis plan must stay aligned with the fixed-effects estimand.", "evidence": "Compared model registry to design model M1.", "affected_specs": ["S1"], "affected_scripts": ["analysis/scripts/04_plan_models.R"], "mitigation": "Added explicit alignment check before execution.", "status": "mitigated", "owner_phase": "7", "route_back_phase": null},
    {"risk_id": "R2", "domain": "identification", "severity": "moderate", "description": "Pretrend interpretation may be weak with sparse event time.", "evidence": "Event-study robustness is planned.", "affected_specs": ["S2"], "affected_scripts": ["analysis/scripts/04_plan_models.R"], "mitigation": "Report pretrend diagnostics before interpreting timing.", "status": "nonblocking", "owner_phase": "7", "route_back_phase": null},
    {"risk_id": "R3", "domain": "measurement", "severity": "moderate", "description": "Expectations scale comparability must be checked.", "evidence": "Measurement plan defines validity checks.", "affected_specs": ["S1"], "affected_scripts": ["analysis/scripts/03_construct_variables.R"], "mitigation": "Check valid scale range during variable construction.", "status": "nonblocking", "owner_phase": "7", "route_back_phase": null},
    {"risk_id": "R4", "domain": "missing_data", "severity": "moderate", "description": "Missing values may vary after job loss.", "evidence": "Variable dictionary records missing codes.", "affected_specs": ["S1"], "affected_scripts": ["analysis/scripts/03_construct_variables.R"], "mitigation": "Run missingness diagnostics and attrition weights.", "status": "nonblocking", "owner_phase": "7", "route_back_phase": null},
    {"risk_id": "R5", "domain": "model_fragility", "severity": "moderate", "description": "Estimates may depend on household fixed-effects assumptions.", "evidence": "Robustness specs S2 and S3 exist.", "affected_specs": ["S1", "S2", "S3"], "affected_scripts": ["analysis/scripts/04_plan_models.R"], "mitigation": "Compare primary, event-study, and attrition-weighted estimates.", "status": "nonblocking", "owner_phase": "7", "route_back_phase": null},
    {"risk_id": "R6", "domain": "robustness", "severity": "moderate", "description": "Robustness outputs must be registered.", "evidence": "Scripts inventory prepares registry schemas.", "affected_specs": ["S2", "S3"], "affected_scripts": ["analysis/scripts/04_plan_models.R"], "mitigation": "Halt if S2 or S3 is missing from the results registry.", "status": "nonblocking", "owner_phase": "7", "route_back_phase": null},
    {"risk_id": "R7", "domain": "null_or_conflicting_results", "severity": "minor", "description": "Null results may still be substantively meaningful.", "evidence": "Decision rules handle null estimates.", "affected_specs": ["S1"], "affected_scripts": ["analysis/scripts/04_plan_models.R"], "mitigation": "Use confidence intervals and avoid binary success language.", "status": "accepted_limitation", "owner_phase": "7", "route_back_phase": null},
    {"risk_id": "R8", "domain": "claim_support", "severity": "moderate", "description": "Causal wording must match observational design.", "evidence": "Identification strategy is observational.", "affected_specs": ["S1"], "affected_scripts": ["analysis/scripts/04_plan_models.R"], "mitigation": "Use cautious within-household change language.", "status": "nonblocking", "owner_phase": "7", "route_back_phase": null},
    {"risk_id": "R9", "domain": "execution_readiness", "severity": "moderate", "description": "Execution must halt if registries are missing.", "evidence": "Phase 8 handoff names required registries.", "affected_specs": ["S1", "S2", "S3"], "affected_scripts": ["analysis/scripts/01_load_data.R", "analysis/scripts/02_build_sample.R", "analysis/scripts/03_construct_variables.R", "analysis/scripts/04_plan_models.R"], "mitigation": "Halt checks require result and figure registry creation.", "status": "nonblocking", "owner_phase": "7", "route_back_phase": null}
  ],
  "blocking_items_resolved": true,
  "unresolved_blocking_count": 0,
  "accepted_limitations": [
    {
      "limitation_id": "L1",
      "severity": "minor",
      "rationale": "Null estimates may still be informative if uncertainty is reported.",
      "monitoring_plan": "Manuscript must report confidence intervals and avoid success/failure framing."
    }
  ],
  "decision_rules": [
    {"rule_id": "D1", "condition": "results registry lacks S1, S2, or S3", "action": "halt Phase 8 and repair execution"},
    {"rule_id": "D2", "condition": "pretrend diagnostics fail", "action": "downgrade causal language and flag robustness"},
    {"rule_id": "D3", "condition": "missingness exceeds planned threshold", "action": "run missingness sensitivity before drafting"}
  ],
  "phase8_handoff": {
    "script_order": ["analysis/scripts/01_load_data.R", "analysis/scripts/02_build_sample.R", "analysis/scripts/03_construct_variables.R", "analysis/scripts/04_plan_models.R"],
    "expected_outputs": ["data/interim/panel-loaded.rds", "data/processed/analytic-sample.rds", "data/processed/analytic-variables.rds", "analysis/planned-model-calls.json", "tables/results-registry.csv", "tables/regression-main.html", "figures/figure-registry.csv"],
    "expected_result_registry": "tables/results-registry.csv",
    "expected_figure_registry": "figures/figure-registry.csv",
    "halt_checks": ["missing result registry", "missing figure registry", "missing planned spec"]
  },
  "go_no_go": {
    "decision": "GO",
    "route_back_phase": null,
    "ready_for_phase_8": true
  }
}
JSON
python3 - "$PREMORTEM_PROJ/review/analysis-premortem.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "The analysis premortem used independent identification, measurement, model robustness, and interpretation reviewers to stress test design alignment, missing data handling, robustness coverage, claim scope, and execution readiness. "
with open(path, "w", encoding="utf-8") as f:
    f.write(sentence * 7)
PY
cat > "$PREMORTEM_PROJ/review/analysis-premortem-fix-log.json" <<'JSON'
{
  "required_fixes_completed": true,
  "unresolved_blocking_count": 0,
  "final_verdict": "PASS",
  "fixed_risks": [
    {
      "risk_id": "R1",
      "status": "mitigated",
      "action_taken": "Added an explicit design-plan alignment check to the Phase 8 handoff.",
      "affected_files": ["review/analysis-premortem.json"]
    }
  ]
}
JSON
# CASE_ID: l2.p7.reject.missing-review-evidence
expect_reject l2.p7.reject.missing-review-evidence "$PREMORTEM_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$PREMORTEM_PROJ"
python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$PREMORTEM_PROJ" 7 premortem_panel >/dev/null
# CASE_ID: phase.7.positive
expect_pass phase.7.positive "$PREMORTEM_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$PREMORTEM_PROJ"

BAD_PREMORTEM_ENGINE_PROJ="$TMP/bad-premortem-engine-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_ENGINE_PROJ"
python3 - "$BAD_PREMORTEM_ENGINE_PROJ/review/analysis-premortem.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["premortem_engine"]["skill"] = "scholar-auto-research"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: phase.7.negative
expect_reject phase.7.negative "$BAD_PREMORTEM_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_ENGINE_PROJ"

BAD_PREMORTEM_ROLE_PROJ="$TMP/bad-premortem-role-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_ROLE_PROJ"
python3 - "$BAD_PREMORTEM_ROLE_PROJ/review/analysis-premortem.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewers"] = [r for r in data["reviewers"] if r["role"] != "interpretation_claims"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p7.reject.reviewer-role
expect_reject l2.p7.reject.reviewer-role "$BAD_PREMORTEM_ROLE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_ROLE_PROJ"

BAD_PREMORTEM_PROVENANCE_PROJ="$TMP/bad-premortem-provenance-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_PROVENANCE_PROJ"
python3 - "$BAD_PREMORTEM_PROVENANCE_PROJ/review/analysis-premortem.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewer_provenance"][0]["agent_name"] = "inline-roleplay"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p7.verify.portable-agent-label
expect_pass l2.p7.verify.portable-agent-label "$BAD_PREMORTEM_PROVENANCE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_PROVENANCE_PROJ"

BAD_PREMORTEM_PROVENANCE_BINDING_PROJ="$TMP/bad-premortem-provenance-binding-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_PROVENANCE_BINDING_PROJ"
python3 - "$BAD_PREMORTEM_PROVENANCE_BINDING_PROJ/review/analysis-premortem.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewer_provenance"][0]["task_invocation_id"] = "contradictory-unregistered-task"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p7.reject.provenance-binding
expect_reject l2.p7.reject.provenance-binding "$BAD_PREMORTEM_PROVENANCE_BINDING_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_PROVENANCE_BINDING_PROJ"

BAD_PREMORTEM_HASH_PROJ="$TMP/bad-premortem-hash-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_HASH_PROJ"
printf '\nLate unreviewed analysis-plan change.\n' >> "$BAD_PREMORTEM_HASH_PROJ/analysis/analysis-plan.md"
# CASE_ID: l2.p7.reject.stale-input-hash
expect_reject l2.p7.reject.stale-input-hash "$BAD_PREMORTEM_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_HASH_PROJ"

BAD_PREMORTEM_RISK_PROJ="$TMP/bad-premortem-risk-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_RISK_PROJ"
python3 - "$BAD_PREMORTEM_RISK_PROJ/review/analysis-premortem.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["risk_register"][0]["status"] = "open"
data["unresolved_blocking_count"] = 1
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p7.reject.risk-register
expect_reject l2.p7.reject.risk-register "$BAD_PREMORTEM_RISK_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_RISK_PROJ"

BAD_PREMORTEM_LIMIT_PROJ="$TMP/bad-premortem-limit-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_LIMIT_PROJ"
python3 - "$BAD_PREMORTEM_LIMIT_PROJ/review/analysis-premortem.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["accepted_limitations"][0]["severity"] = "major"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p7.reject.accepted-limitation
expect_reject l2.p7.reject.accepted-limitation "$BAD_PREMORTEM_LIMIT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_LIMIT_PROJ"

BAD_PREMORTEM_NULL_PROJ="$TMP/bad-premortem-null-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_NULL_PROJ"
python3 - "$BAD_PREMORTEM_NULL_PROJ/review/analysis-premortem.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["null_falsification_table"][0]["precommitted"] = False
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p7.reject.null-falsification
expect_reject l2.p7.reject.null-falsification "$BAD_PREMORTEM_NULL_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_NULL_PROJ"

BAD_PREMORTEM_REPORTING_PROJ="$TMP/bad-premortem-reporting-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_REPORTING_PROJ"
python3 - "$BAD_PREMORTEM_REPORTING_PROJ/review/analysis-premortem.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reporting_depth_checklist"] = [row for row in data["reporting_depth_checklist"] if row["risk_id"] != "R5"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p7.reject.reporting-depth
expect_reject l2.p7.reject.reporting-depth "$BAD_PREMORTEM_REPORTING_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_REPORTING_PROJ"

BAD_PREMORTEM_EXEC_PROJ="$TMP/bad-premortem-exec-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_EXEC_PROJ"
mkdir -p "$BAD_PREMORTEM_EXEC_PROJ/analysis"
printf '{"status":"already executed"}\n' > "$BAD_PREMORTEM_EXEC_PROJ/analysis/execution-report.json"
# CASE_ID: l2.p7.reject.preexecution-artifact
expect_reject l2.p7.reject.preexecution-artifact "$BAD_PREMORTEM_EXEC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_EXEC_PROJ"

EXEC_PROJ="$TMP/execution-project"
cp -R "$PREMORTEM_PROJ" "$EXEC_PROJ"
mkdir -p "$EXEC_PROJ/analysis/scripts" "$EXEC_PROJ/data/interim" "$EXEC_PROJ/data/processed" "$EXEC_PROJ/tables" "$EXEC_PROJ/figures" "$EXEC_PROJ/logs"
cat > "$EXEC_PROJ/analysis/scripts/01_load_data.R" <<'RSCRIPT'
# Planned data loading script for fixture validation.
print("load data")
RSCRIPT
cat > "$EXEC_PROJ/analysis/scripts/02_build_sample.R" <<'RSCRIPT'
# Planned sample construction script for fixture validation.
print("build sample")
RSCRIPT
cat > "$EXEC_PROJ/analysis/scripts/03_construct_variables.R" <<'RSCRIPT'
# Planned variable construction script for fixture validation.
print("construct variables")
RSCRIPT
# Copy the canonical bundled viz_setting.R (the contract at
# auto-research-verify.sh:4485-4495 requires byte-for-byte match against
# references/viz_setting.R, not a local stub).
cp "$SKILL_DIR/references/viz_setting.R" "$EXEC_PROJ/analysis/scripts/viz_setting.R"
VIZ_STYLE_SHA256=$(shasum -a 256 "$SKILL_DIR/references/viz_setting.R" | awk '{print $1}')
cat > "$EXEC_PROJ/analysis/scripts/04_plan_models.R" <<'RSCRIPT'
# Planned model execution script for fixture validation.
library(modelsummary)
library(ggplot2)
source("analysis/scripts/viz_setting.R")
ggplot(data.frame(x = 1, y = 1), aes(x = x, y = y)) + geom_point() + theme_Publication()
print("run models")
RSCRIPT
printf 'loaded fixture\n' > "$EXEC_PROJ/data/interim/panel-loaded.rds"
printf 'sample fixture\n' > "$EXEC_PROJ/data/processed/analytic-sample.rds"
printf 'variables fixture\n' > "$EXEC_PROJ/data/processed/analytic-variables.rds"
printf '{"planned":true}\n' > "$EXEC_PROJ/analysis/planned-model-calls.json"
printf 'model fixture\n' > "$EXEC_PROJ/tables/model-results.csv"
cat > "$EXEC_PROJ/tables/regression-main.html" <<'HTML'
<table>
  <thead>
    <tr><th>Predictor</th><th>Model 1</th><th>Model 2</th><th>Model 3</th></tr>
  </thead>
  <tbody>
    <tr><td>Parental job loss</td><td>-0.120 (0.040)</td><td>-0.080 (0.050)</td><td>-0.090 (0.045)</td></tr>
    <tr><td>Controls</td><td>No</td><td>Yes</td><td>Yes</td></tr>
    <tr><td>N</td><td>1200</td><td>1200</td><td>1200</td></tr>
  </tbody>
</table>
HTML
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' | base64 -d > "$EXEC_PROJ/figures/event-study.png"
cat > "$EXEC_PROJ/tables/results-registry.csv" <<'CSV'
spec_id,model_id,outcome,predictor,estimate,std_error,p_value,n,status,output_file
S1,M1,adolescent educational expectations,parental job loss,-0.120,0.040,0.003,1200,completed,tables/model-results.csv
S2,M1,adolescent educational expectations,parental job loss,-0.080,0.050,0.110,1200,completed,tables/model-results.csv
S3,M1,adolescent educational expectations,parental job loss,-0.090,0.045,0.046,1200,completed,tables/model-results.csv
CSV
cat > "$EXEC_PROJ/figures/figure-registry.csv" <<'CSV'
figure_id,path,source_script,status,description
F1,figures/event-study.png,analysis/scripts/04_plan_models.R,completed,event-study diagnostic figure
CSV
for script in 01_load_data 02_build_sample 03_construct_variables 04_plan_models; do
  printf '%s stdout\n' "$script" > "$EXEC_PROJ/logs/$script.stdout.log"
  printf '%s stderr\n' "$script" > "$EXEC_PROJ/logs/$script.stderr.log"
done
EXEC_PLAN_HASH="$(shasum -a 256 "$EXEC_PROJ/analysis/analysis-plan.md" | awk '{print $1}')"
EXEC_SPEC_HASH="$(shasum -a 256 "$EXEC_PROJ/analysis/spec-registry.csv" | awk '{print $1}')"
EXEC_INV_HASH="$(shasum -a 256 "$EXEC_PROJ/analysis/scripts-inventory.json" | awk '{print $1}')"
EXEC_PREMORTEM_HASH="$(shasum -a 256 "$EXEC_PROJ/review/analysis-premortem.json" | awk '{print $1}')"
EXEC_PREMORTEM_FIX_HASH="$(shasum -a 256 "$EXEC_PROJ/review/analysis-premortem-fix-log.json" | awk '{print $1}')"
SCRIPT1_HASH="$(shasum -a 256 "$EXEC_PROJ/analysis/scripts/01_load_data.R" | awk '{print $1}')"
SCRIPT2_HASH="$(shasum -a 256 "$EXEC_PROJ/analysis/scripts/02_build_sample.R" | awk '{print $1}')"
SCRIPT3_HASH="$(shasum -a 256 "$EXEC_PROJ/analysis/scripts/03_construct_variables.R" | awk '{print $1}')"
SCRIPT4_HASH="$(shasum -a 256 "$EXEC_PROJ/analysis/scripts/04_plan_models.R" | awk '{print $1}')"
LOADED_HASH="$(shasum -a 256 "$EXEC_PROJ/data/interim/panel-loaded.rds" | awk '{print $1}')"
SAMPLE_HASH="$(shasum -a 256 "$EXEC_PROJ/data/processed/analytic-sample.rds" | awk '{print $1}')"
VARIABLES_HASH="$(shasum -a 256 "$EXEC_PROJ/data/processed/analytic-variables.rds" | awk '{print $1}')"
PLANNED_CALLS_HASH="$(shasum -a 256 "$EXEC_PROJ/analysis/planned-model-calls.json" | awk '{print $1}')"
RESULTS_REG_HASH="$(shasum -a 256 "$EXEC_PROJ/tables/results-registry.csv" | awk '{print $1}')"
FIGURE_REG_HASH="$(shasum -a 256 "$EXEC_PROJ/figures/figure-registry.csv" | awk '{print $1}')"
MODEL_RESULTS_HASH="$(shasum -a 256 "$EXEC_PROJ/tables/model-results.csv" | awk '{print $1}')"
REGRESSION_MAIN_HASH="$(shasum -a 256 "$EXEC_PROJ/tables/regression-main.html" | awk '{print $1}')"
EVENT_STUDY_HASH="$(shasum -a 256 "$EXEC_PROJ/figures/event-study.png" | awk '{print $1}')"
cat > "$EXEC_PROJ/analysis/execution-report.json" <<JSON
{
  "verdict": "PASS",
  "degraded": false,
  "ready_for_phase_9": true,
  "execution_engine": {
    "skill": "scholar-analyze",
    "mode": "execute_analysis",
    "auto_research_contract": "phase_8",
    "phase7_handoff_only": true,
    "task_invocation_id": "phase8-execution-001",
    "invoked_at_utc": "2026-04-29T10:00:00Z",
    "input_artifacts": [
      "analysis/analysis-plan.md",
      "analysis/spec-registry.csv",
      "analysis/scripts-inventory.json",
      "review/analysis-premortem.json"
    ],
    "output_artifacts": [
      "analysis/execution-report.json",
      "tables/results-registry.csv",
      "figures/figure-registry.csv"
    ]
  },
  "run_context": {
    "started_at_utc": "2026-04-29T10:00:00Z",
    "completed_at_utc": "2026-04-29T10:00:09Z",
    "working_directory": "$EXEC_PROJ",
    "seed": "not-used-fixture",
    "environment": "fixture shell with Rscript-compatible command records",
    "session_info": "fixture execution report for auto-research validation"
  },
  "source_hashes": {
    "analysis_plan": "$EXEC_PLAN_HASH",
    "spec_registry": "$EXEC_SPEC_HASH",
    "scripts_inventory": "$EXEC_INV_HASH",
    "analysis_premortem": "$EXEC_PREMORTEM_HASH",
    "analysis_premortem_fix_log": "$EXEC_PREMORTEM_FIX_HASH"
  },
  "phase7_source_hash_check": {
    "checked": true,
    "status": "PASS",
    "checked_sources": ["analysis_plan", "spec_registry", "scripts_inventory", "pre_execution_review", "pre_execution_fix_log", "pre_execution_rereview"],
    "mismatches": []
  },
  "phase7_go": {
    "decision": "GO",
    "ready_for_phase_8": true,
    "route_back_phase": null
  },
  "command_trace": [
    {
      "path": "analysis/scripts/01_load_data.R",
      "command": "Rscript analysis/scripts/01_load_data.R",
      "cwd": ".",
      "started_at": "2026-04-29T10:00:00Z",
      "ended_at": "2026-04-29T10:00:02Z",
      "exit_code": 0,
      "stdout_log": "logs/01_load_data.stdout.log",
      "stderr_log": "logs/01_load_data.stderr.log"
    },
    {
      "path": "analysis/scripts/02_build_sample.R",
      "command": "Rscript analysis/scripts/02_build_sample.R",
      "cwd": ".",
      "started_at": "2026-04-29T10:00:03Z",
      "ended_at": "2026-04-29T10:00:04Z",
      "exit_code": 0,
      "stdout_log": "logs/02_build_sample.stdout.log",
      "stderr_log": "logs/02_build_sample.stderr.log"
    },
    {
      "path": "analysis/scripts/03_construct_variables.R",
      "command": "Rscript analysis/scripts/03_construct_variables.R",
      "cwd": ".",
      "started_at": "2026-04-29T10:00:05Z",
      "ended_at": "2026-04-29T10:00:06Z",
      "exit_code": 0,
      "stdout_log": "logs/03_construct_variables.stdout.log",
      "stderr_log": "logs/03_construct_variables.stderr.log"
    },
    {
      "path": "analysis/scripts/04_plan_models.R",
      "command": "Rscript analysis/scripts/04_plan_models.R",
      "cwd": ".",
      "started_at": "2026-04-29T10:00:07Z",
      "ended_at": "2026-04-29T10:00:09Z",
      "exit_code": 0,
      "stdout_log": "logs/04_plan_models.stdout.log",
      "stderr_log": "logs/04_plan_models.stderr.log"
    }
  ],
  "executed_scripts": [
    {
      "path": "analysis/scripts/01_load_data.R",
      "command": "Rscript analysis/scripts/01_load_data.R",
      "script_hash": "$SCRIPT1_HASH",
      "exit_code": 0,
      "status": "success",
      "started_at": "2026-04-29T10:00:00Z",
      "ended_at": "2026-04-29T10:00:02Z",
      "outputs": ["data/interim/panel-loaded.rds"],
      "output_hashes": {
        "data/interim/panel-loaded.rds": "$LOADED_HASH"
      }
    },
    {
      "path": "analysis/scripts/02_build_sample.R",
      "command": "Rscript analysis/scripts/02_build_sample.R",
      "script_hash": "$SCRIPT2_HASH",
      "exit_code": 0,
      "status": "success",
      "started_at": "2026-04-29T10:00:03Z",
      "ended_at": "2026-04-29T10:00:04Z",
      "outputs": ["data/processed/analytic-sample.rds"],
      "output_hashes": {
        "data/processed/analytic-sample.rds": "$SAMPLE_HASH"
      }
    },
    {
      "path": "analysis/scripts/03_construct_variables.R",
      "command": "Rscript analysis/scripts/03_construct_variables.R",
      "script_hash": "$SCRIPT3_HASH",
      "exit_code": 0,
      "status": "success",
      "started_at": "2026-04-29T10:00:05Z",
      "ended_at": "2026-04-29T10:00:06Z",
      "outputs": ["data/processed/analytic-variables.rds"],
      "output_hashes": {
        "data/processed/analytic-variables.rds": "$VARIABLES_HASH"
      }
    },
    {
      "path": "analysis/scripts/04_plan_models.R",
      "command": "Rscript analysis/scripts/04_plan_models.R",
      "script_hash": "$SCRIPT4_HASH",
      "exit_code": 0,
      "status": "success",
      "started_at": "2026-04-29T10:00:07Z",
      "ended_at": "2026-04-29T10:00:09Z",
      "outputs": ["analysis/planned-model-calls.json", "tables/results-registry.csv", "figures/figure-registry.csv", "tables/model-results.csv", "tables/regression-main.html", "figures/event-study.png"],
      "output_hashes": {
        "analysis/planned-model-calls.json": "$PLANNED_CALLS_HASH",
        "tables/results-registry.csv": "$RESULTS_REG_HASH",
        "figures/figure-registry.csv": "$FIGURE_REG_HASH",
        "tables/model-results.csv": "$MODEL_RESULTS_HASH",
        "tables/regression-main.html": "$REGRESSION_MAIN_HASH",
        "figures/event-study.png": "$EVENT_STUDY_HASH"
      }
    }
  ],
  "exit_codes": {
    "analysis/scripts/01_load_data.R": 0,
    "analysis/scripts/02_build_sample.R": 0,
    "analysis/scripts/03_construct_variables.R": 0,
    "analysis/scripts/04_plan_models.R": 0
  },
  "tests_run": [
    {
      "id": "T1",
      "status": "pass",
      "evidence": "source file loads and required columns are present"
    },
    {
      "id": "T2",
      "status": "pass",
      "evidence": "analytic sample has nonzero rows and correct unit of analysis"
    },
    {
      "id": "T3",
      "status": "pass",
      "evidence": "constructed variables match the Phase 4 variable dictionary"
    },
    {
      "id": "T4",
      "status": "pass",
      "evidence": "missing value handling matches the Phase 4 missing data plan"
    },
    {
      "id": "T5",
      "status": "pass",
      "evidence": "every planned spec has valid variables"
    },
    {
      "id": "T6",
      "status": "pass",
      "evidence": "planned output registry schemas are available"
    }
  ],
  "halt_checks": [
    {
      "check": "missing result registry",
      "status": "pass"
    },
    {
      "check": "missing figure registry",
      "status": "pass"
    },
    {
      "check": "missing planned spec",
      "status": "pass"
    }
  ],
  "expected_outputs": [
    {
      "path": "data/interim/panel-loaded.rds",
      "status": "present"
    },
    {
      "path": "data/processed/analytic-sample.rds",
      "status": "present"
    },
    {
      "path": "data/processed/analytic-variables.rds",
      "status": "present"
    },
    {
      "path": "analysis/planned-model-calls.json",
      "status": "present"
    },
    {
      "path": "tables/results-registry.csv",
      "status": "present"
    },
    {
      "path": "tables/regression-main.html",
      "status": "present"
    },
    {
      "path": "figures/figure-registry.csv",
      "status": "present"
    }
  ],
  "results_registry": {
    "path": "tables/results-registry.csv",
    "row_count": 3,
    "covered_spec_ids": ["S1", "S2", "S3"]
  },
  "figure_registry": {
    "path": "figures/figure-registry.csv",
    "row_count": 1,
    "covered_figure_ids": ["F1"]
  },
  "analysis_stack": {
    "primary_language": "R",
    "table_engine": "modelsummary",
    "figure_engine": "ggplot2",
    "packages_used": ["modelsummary", "ggplot2"],
    "nonlinear_probability_models": false,
    "marginal_effects_engine": null,
    "viz_style_source": "analysis/scripts/viz_setting.R",
    "viz_style_reference": "references/viz_setting.R",
    "viz_style_sha256": "$VIZ_STYLE_SHA256",
    "ggplot2_style_consistency": true,
    "reader_facing_label_source": "data/variable-dictionary.csv",
    "table_label_translation_applied": true,
    "figure_label_translation_applied": true,
    "deviation_justification": ""
  },
  "publication_regression_tables": [
    {
      "path": "tables/regression-main.html",
      "role": "main_regression_table",
      "source_script": "analysis/scripts/04_plan_models.R",
      "table_engine": "modelsummary",
      "model_columns": ["Model 1", "Model 2", "Model 3"],
      "statistic_rows": ["Parental job loss", "Controls", "N"],
      "placement": "main_text"
    }
  ],
  "artifact_manifest": [
    {"path": "data/interim/panel-loaded.rds", "sha256": "$LOADED_HASH", "artifact_role": "intermediate_data", "produced_by": "analysis/scripts/01_load_data.R", "registered": true},
    {"path": "data/processed/analytic-sample.rds", "sha256": "$SAMPLE_HASH", "artifact_role": "intermediate_data", "produced_by": "analysis/scripts/02_build_sample.R", "registered": true},
    {"path": "data/processed/analytic-variables.rds", "sha256": "$VARIABLES_HASH", "artifact_role": "intermediate_data", "produced_by": "analysis/scripts/03_construct_variables.R", "registered": true},
    {"path": "analysis/planned-model-calls.json", "sha256": "$PLANNED_CALLS_HASH", "artifact_role": "planned_model_calls", "produced_by": "analysis/scripts/04_plan_models.R", "registered": true},
    {"path": "tables/results-registry.csv", "sha256": "$RESULTS_REG_HASH", "artifact_role": "results_registry", "produced_by": "analysis/scripts/04_plan_models.R", "registered": true},
    {"path": "tables/model-results.csv", "sha256": "$MODEL_RESULTS_HASH", "artifact_role": "diagnostic", "produced_by": "analysis/scripts/04_plan_models.R", "registered": true},
    {"path": "tables/regression-main.html", "sha256": "$REGRESSION_MAIN_HASH", "artifact_role": "main_regression_table", "produced_by": "analysis/scripts/04_plan_models.R", "registered": true},
    {"path": "figures/figure-registry.csv", "sha256": "$FIGURE_REG_HASH", "artifact_role": "figure_registry", "produced_by": "analysis/scripts/04_plan_models.R", "registered": true},
    {"path": "figures/event-study.png", "sha256": "$EVENT_STUDY_HASH", "artifact_role": "figure_file", "produced_by": "analysis/scripts/04_plan_models.R", "registered": true}
  ],
  "errors": []
}
JSON
# CASE_ID: phase.8.positive
expect_pass phase.8.positive "$EXEC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$EXEC_PROJ"

BAD_EXEC_ENGINE_PROJ="$TMP/bad-execution-engine-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_ENGINE_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_ENGINE_PROJ"
python3 - "$BAD_EXEC_ENGINE_PROJ/analysis/execution-report.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["execution_engine"]["skill"] = "scholar-auto-research"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: phase.8.negative
expect_reject phase.8.negative "$BAD_EXEC_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_ENGINE_PROJ"

BAD_EXEC_STACK_PROJ="$TMP/bad-execution-stack-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_STACK_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_STACK_PROJ"
python3 - "$BAD_EXEC_STACK_PROJ/analysis/execution-report.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["analysis_stack"]["table_engine"] = "stargazer"
data["analysis_stack"]["packages_used"] = ["ggplot2"]
data["analysis_stack"]["deviation_justification"] = ""
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p8.reject.analysis-stack
expect_reject l2.p8.reject.analysis-stack "$BAD_EXEC_STACK_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_STACK_PROJ"

BAD_EXEC_VIZ_PROJ="$TMP/bad-execution-viz-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_VIZ_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_VIZ_PROJ"
python3 - "$BAD_EXEC_VIZ_PROJ/analysis/execution-report.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["analysis_stack"]["viz_style_source"] = ""
data["analysis_stack"]["ggplot2_style_consistency"] = False
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
python3 - "$BAD_EXEC_VIZ_PROJ/analysis/scripts/04_plan_models.R" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = text.replace('source("analysis/scripts/viz_setting.R")\n', '')
text = text.replace(' + theme_Publication()', '')
path.write_text(text)
PY
python3 - "$BAD_EXEC_VIZ_PROJ/analysis/execution-report.json" "$BAD_EXEC_VIZ_PROJ/analysis/scripts/04_plan_models.R" <<'PY'
import hashlib
import json
import pathlib
import sys
report_path = pathlib.Path(sys.argv[1])
script_path = pathlib.Path(sys.argv[2])
data = json.loads(report_path.read_text())
script_hash = hashlib.sha256(script_path.read_bytes()).hexdigest()
for item in data["executed_scripts"]:
    if item.get("path") == "analysis/scripts/04_plan_models.R":
        item["script_hash"] = script_hash
report_path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p8.reject.viz-style
expect_reject l2.p8.reject.viz-style "$BAD_EXEC_VIZ_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_VIZ_PROJ"

BAD_EXEC_PHASE7_DRIFT_PROJ="$TMP/bad-execution-phase7-drift-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_PHASE7_DRIFT_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_PHASE7_DRIFT_PROJ"
printf '\nLate unreviewed Phase 7 source drift.\n' >> "$BAD_EXEC_PHASE7_DRIFT_PROJ/analysis/analysis-plan.md"
python3 - "$BAD_EXEC_PHASE7_DRIFT_PROJ/analysis/execution-report.json" "$BAD_EXEC_PHASE7_DRIFT_PROJ/analysis/analysis-plan.md" <<'PY'
import hashlib
import json
import sys
report_path, plan_path = sys.argv[1:3]
with open(report_path, encoding="utf-8") as f:
    data = json.load(f)
data["source_hashes"]["analysis_plan"] = hashlib.sha256(open(plan_path, "rb").read()).hexdigest()
with open(report_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p8.reject.phase7-source-drift
expect_reject l2.p8.reject.phase7-source-drift "$BAD_EXEC_PHASE7_DRIFT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_PHASE7_DRIFT_PROJ"

BAD_EXEC_TRACE_PROJ="$TMP/bad-execution-trace-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_TRACE_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_TRACE_PROJ"
python3 - "$BAD_EXEC_TRACE_PROJ/analysis/execution-report.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["command_trace"][0]["stdout_log"] = "logs/missing.stdout.log"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p8.reject.command-trace
expect_reject l2.p8.reject.command-trace "$BAD_EXEC_TRACE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_TRACE_PROJ"

BAD_EXEC_ARTIFACT_PROJ="$TMP/bad-execution-artifact-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_ARTIFACT_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_ARTIFACT_PROJ"
printf 'unregistered table artifact\n' > "$BAD_EXEC_ARTIFACT_PROJ/tables/unregistered-diagnostic.csv"
# CASE_ID: l2.p8.reject.unregistered-artifact
expect_reject l2.p8.reject.unregistered-artifact "$BAD_EXEC_ARTIFACT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_ARTIFACT_PROJ"

BAD_EXEC_HASH_PROJ="$TMP/bad-execution-hash-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_HASH_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_HASH_PROJ"
printf '\nLate unreviewed inventory change.\n' >> "$BAD_EXEC_HASH_PROJ/analysis/scripts-inventory.json"
# CASE_ID: l2.p8.reject.malformed-source-json
expect_reject l2.p8.reject.malformed-source-json "$BAD_EXEC_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_HASH_PROJ"

BAD_EXEC_EXIT_PROJ="$TMP/bad-execution-exit-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_EXIT_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_EXIT_PROJ"
python3 - "$BAD_EXEC_EXIT_PROJ/analysis/execution-report.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["executed_scripts"][1]["exit_code"] = 1
data["executed_scripts"][1]["status"] = "failed"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p8.reject.script-exit
expect_reject l2.p8.reject.script-exit "$BAD_EXEC_EXIT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_EXIT_PROJ"

BAD_EXEC_SPEC_PROJ="$TMP/bad-execution-spec-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_SPEC_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_SPEC_PROJ"
python3 - "$BAD_EXEC_SPEC_PROJ/tables/results-registry.csv" <<'PY'
import csv
import sys
path = sys.argv[1]
with open(path, newline="", encoding="utf-8") as f:
    rows = [row for row in csv.DictReader(f) if row.get("spec_id") != "S2"]
fieldnames = ["spec_id", "model_id", "outcome", "predictor", "estimate", "std_error", "p_value", "n", "status", "output_file"]
with open(path, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
PY
# CASE_ID: l2.p8.reject.results-hash
expect_reject l2.p8.reject.results-hash "$BAD_EXEC_SPEC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_SPEC_PROJ"

BAD_EXEC_OUTPUT_PROJ="$TMP/bad-execution-output-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_OUTPUT_PROJ"
rebind_execution_fixture_root "$BAD_EXEC_OUTPUT_PROJ"
python3 - "$BAD_EXEC_OUTPUT_PROJ/data/processed/analytic-sample.rds" <<'PY'
import os
import sys
os.remove(sys.argv[1])
PY
# CASE_ID: l2.p8.reject.missing-output
expect_reject l2.p8.reject.missing-output "$BAD_EXEC_OUTPUT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_OUTPUT_PROJ"

POSTEXEC_PROJ="$TMP/postexec-project"
progress "phases 9 to 12 post-execution, sanity, lock, and blueprint fixtures"
cp -R "$EXEC_PROJ" "$POSTEXEC_PROJ"
mkdir -p "$POSTEXEC_PROJ/review/agents"
for role in statistical_results robustness_consistency sample_data_integrity interpretation_claims; do
  printf 'Independent %s post-execution review. The reviewer inspected all executed specs, figure registry rows, sample integrity, robustness implications, and interpretation constraints before runtime sanity. No blocking issue remains.\n' "$role" > "$POSTEXEC_PROJ/review/agents/postexec-$role.md"
done
python3 - "$POSTEXEC_PROJ/review/stage1-raw-output-verification.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "Scholar-verify Stage 1 checked raw result tables, model output files, figure registry rows, and rendered figure files against the Phase 8 registries before any manuscript existed. "
with open(path, "w", encoding="utf-8") as f:
    f.write(sentence * 4)
PY
POST_SPEC_HASH="$(shasum -a 256 "$POSTEXEC_PROJ/analysis/spec-registry.csv" | awk '{print $1}')"
POST_PREMORTEM_HASH="$(shasum -a 256 "$POSTEXEC_PROJ/review/analysis-premortem.json" | awk '{print $1}')"
POST_EXEC_HASH="$(shasum -a 256 "$POSTEXEC_PROJ/analysis/execution-report.json" | awk '{print $1}')"
POST_RESULTS_HASH="$(shasum -a 256 "$POSTEXEC_PROJ/tables/results-registry.csv" | awk '{print $1}')"
POST_FIGURES_HASH="$(shasum -a 256 "$POSTEXEC_PROJ/figures/figure-registry.csv" | awk '{print $1}')"
POST_EVENT_STUDY_HASH="$(shasum -a 256 "$POSTEXEC_PROJ/figures/event-study.png" | awk '{print $1}')"
cat > "$POSTEXEC_PROJ/review/post-execution-review.json" <<JSON
{
  "verdict": "PASS",
  "degraded": false,
  "decision": "PROCEED_TO_RUNTIME_SANITY",
  "ready_for_phase_10": true,
  "review_engine": {
    "skill": "scholar-verify",
    "mode": "stage1_no_manuscript",
    "auto_research_contract": "phase_9",
    "read_live_outputs_pre_lock": true,
    "task_invocation_id": "phase9-verify-001",
    "invoked_at_utc": "2026-04-29T11:00:00Z",
    "input_artifacts": [
      "analysis/execution-report.json",
      "tables/results-registry.csv",
      "figures/figure-registry.csv",
      "analysis/spec-registry.csv"
    ],
    "output_artifacts": [
      "review/post-execution-review.json",
      "review/post-execution-review.md"
    ]
  },
  "source_hashes": {
    "spec_registry": "$POST_SPEC_HASH",
    "analysis_premortem": "$POST_PREMORTEM_HASH",
    "execution_report": "$POST_EXEC_HASH",
    "results_registry": "$POST_RESULTS_HASH",
    "figure_registry": "$POST_FIGURES_HASH"
  },
  "phase7_constraint_carryforward": {
    "null_falsification_checked": true,
    "reporting_depth_checked": true,
    "claim_constraints_reflect_phase7": true,
    "checked_hypothesis_ids": ["H1"],
    "evidence": "Phase 9 carried forward Phase 7 null-falsification and reporting-depth constraints into the reviewed spec classifications and claim constraints."
  },
  "raw_output_verification": {
    "verdict": "CLEAN",
    "stage": "stage1_no_manuscript",
    "checked_raw_tables": ["tables/results-registry.csv", "tables/model-results.csv"],
    "checked_figures": ["figures/event-study.png"],
    "registry_consistency": true,
    "visual_figure_inspection": true,
    "critical_count": 0,
    "report_path": "review/stage1-raw-output-verification.md"
  },
  "phase8_status": {
    "verdict": "PASS",
    "ready_for_phase_9": true,
    "errors_empty": true
  },
  "reviewer_provenance": [
    {
      "reviewer_id": "X1",
      "role": "statistical_results",
      "agent_name": "verify-numerics",
      "task_invocation_id": "postexec-statistical-001",
      "dispatched_at_utc": "2026-04-29T10:45:00Z",
      "model_id": "gpt-5.5",
      "report_path": "review/agents/postexec-statistical_results.md"
    },
    {
      "reviewer_id": "X2",
      "role": "robustness_consistency",
      "agent_name": "peer-reviewer-quant",
      "task_invocation_id": "postexec-robustness-001",
      "dispatched_at_utc": "2026-04-29T10:45:00Z",
      "model_id": "gpt-5.5",
      "report_path": "review/agents/postexec-robustness_consistency.md"
    },
    {
      "reviewer_id": "X3",
      "role": "sample_data_integrity",
      "agent_name": "verify-completeness",
      "task_invocation_id": "postexec-sample-001",
      "dispatched_at_utc": "2026-04-29T10:45:00Z",
      "model_id": "gpt-5.5",
      "report_path": "review/agents/postexec-sample_data_integrity.md"
    },
    {
      "reviewer_id": "X4",
      "role": "interpretation_claims",
      "agent_name": "verify-logic",
      "task_invocation_id": "postexec-claims-001",
      "dispatched_at_utc": "2026-04-29T10:45:00Z",
      "model_id": "gpt-5.5",
      "report_path": "review/agents/postexec-interpretation_claims.md"
    }
  ],
  "reviewers": [
    {
      "reviewer_id": "X1",
      "role": "statistical_results",
      "agent_type": "independent_codex_agent",
      "task_invocation_id": "postexec-statistical-001",
      "report_path": "review/agents/postexec-statistical_results.md",
      "reviewed_specs": ["S1", "S2", "S3"],
      "reviewed_figures": ["F1"],
      "findings": [],
      "verdict": "PASS"
    },
    {
      "reviewer_id": "X2",
      "role": "robustness_consistency",
      "agent_type": "independent_codex_agent",
      "task_invocation_id": "postexec-robustness-001",
      "report_path": "review/agents/postexec-robustness_consistency.md",
      "reviewed_specs": ["S1", "S2", "S3"],
      "reviewed_figures": ["F1"],
      "findings": [],
      "verdict": "PASS"
    },
    {
      "reviewer_id": "X3",
      "role": "sample_data_integrity",
      "agent_type": "independent_codex_agent",
      "task_invocation_id": "postexec-sample-001",
      "report_path": "review/agents/postexec-sample_data_integrity.md",
      "reviewed_specs": ["S1", "S2", "S3"],
      "reviewed_figures": ["F1"],
      "findings": [],
      "verdict": "PASS"
    },
    {
      "reviewer_id": "X4",
      "role": "interpretation_claims",
      "agent_type": "independent_codex_agent",
      "task_invocation_id": "postexec-claims-001",
      "report_path": "review/agents/postexec-interpretation_claims.md",
      "reviewed_specs": ["S1", "S2", "S3"],
      "reviewed_figures": ["F1"],
      "findings": [],
      "verdict": "PASS"
    }
  ],
  "reviewed_specs": [
    {
      "spec_id": "S1",
      "result_status": "completed",
      "review_verdict": "PASS",
      "planned_direction": "negative",
      "observed_direction": "negative",
      "estimate": -0.120,
      "std_error": 0.040,
      "p_value": 0.003,
      "ci_low": -0.198,
      "ci_high": -0.042,
      "n": 1200,
      "sample_id": "analytic-sample",
      "technical_validity": true,
      "substantive_classification": "expected_direction",
      "interpretation_constraint": "Interpret as within-household association under the stated identification assumptions.",
      "allowed_claim_verbs": ["is associated with", "is linked to"]
    },
    {
      "spec_id": "S2",
      "result_status": "completed",
      "review_verdict": "PASS_WITH_INTERPRETATION_CONSTRAINT",
      "planned_direction": "negative",
      "observed_direction": "negative",
      "estimate": -0.080,
      "std_error": 0.050,
      "p_value": 0.110,
      "ci_low": -0.178,
      "ci_high": 0.018,
      "n": 1200,
      "sample_id": "analytic-sample",
      "technical_validity": true,
      "substantive_classification": "weak",
      "interpretation_constraint": "Describe robustness as directionally similar but imprecise.",
      "allowed_claim_verbs": ["is directionally consistent with", "is imprecisely estimated"]
    },
    {
      "spec_id": "S3",
      "result_status": "completed",
      "review_verdict": "PASS",
      "planned_direction": "negative",
      "observed_direction": "negative",
      "estimate": -0.090,
      "std_error": 0.045,
      "p_value": 0.046,
      "ci_low": -0.178,
      "ci_high": -0.002,
      "n": 1200,
      "sample_id": "analytic-sample",
      "technical_validity": true,
      "substantive_classification": "expected_direction",
      "interpretation_constraint": "Describe attrition-weighted robustness as supportive but secondary.",
      "allowed_claim_verbs": ["is associated with", "is robust to attrition weighting"]
    }
  ],
  "reviewed_figures": [
    {
      "figure_id": "F1",
      "review_verdict": "PASS",
      "source_path": "figures/event-study.png",
      "sha256": "$POST_EVENT_STUDY_HASH",
      "visual_inspection": true,
      "caption_or_registry_match": "Rendered event-study diagnostic matches the figure registry description.",
      "interpretation_constraint": "Use as diagnostic figure, not standalone proof."
    }
  ],
  "sample_integrity": {
    "verdict": "PASS",
    "initial_n": 1500,
    "analytic_n": 1200,
    "exclusion_count": 300,
    "missingness_checked": true,
    "cluster_or_group_count": 240,
    "weights_status": "not required for fixture",
    "minimum_cell_count": 60
  },
  "result_interpretation": {
    "technically_valid": true,
    "direction_summary": "Primary and robustness estimates are negative.",
    "strength_summary": "Primary estimate is statistically precise; robustness is weaker.",
    "uncertainty_summary": "Confidence intervals show uncertainty in robustness specification.",
    "claim_constraints": ["Avoid proof language", "Describe robustness imprecision"]
  },
  "robustness_assessment": {
    "verdict": "PASS_WITH_CONFLICTS_DISCLOSED",
    "conflicts": ["S2 is weaker than S1"],
    "interpretation_implications": ["Report the primary estimate as stronger than robustness evidence"]
  },
  "robustness_matrix": [
    {
      "primary_spec_id": "S1",
      "comparison_spec_id": "S2",
      "conflict_type": "weaker_precision",
      "severity": "moderate",
      "adjudication": "WEAKENS",
      "manuscript_instruction": "State that the robustness estimate is directionally similar but less precise."
    },
    {
      "primary_spec_id": "S1",
      "comparison_spec_id": "S3",
      "conflict_type": "attrition_weighted_support",
      "severity": "minor",
      "adjudication": "SUPPORTS",
      "manuscript_instruction": "State that the attrition-weighted robustness estimate remains negative."
    }
  ],
  "unexpected_results": [
    {
      "spec_id": "S2",
      "classification": "weak",
      "action": "carry_forward_with_constraints",
      "manuscript_instruction": "Do not claim uniformly strong robustness."
    }
  ],
  "claim_constraints": {
    "allowed_claim_verbs": ["is associated with", "is linked to", "is directionally consistent with"],
    "forbidden_claim_verbs": ["prove", "causes", "guarantees"],
    "required_disclosures": ["observational design", "weaker robustness estimate"]
  },
  "critical_count": 0,
  "unresolved_blocking_count": 0,
  "fix_status": {
    "required": false,
    "all_blocking_fixed": true,
    "fix_log": "review/post-execution-fix-log.json"
  },
  "route_back_phase": null
}
JSON
python3 - "$POSTEXEC_PROJ/review/post-execution-review.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "The post execution review confirms that every planned specification and figure registry row was reviewed by independent statistical, robustness, sample integrity, and interpretation reviewers. The primary result is technically valid and the weaker robustness result is carried forward with interpretation constraints rather than rerun to match expectations. "
with open(path, "w", encoding="utf-8") as f:
    f.write(sentence * 5)
PY
cat > "$POSTEXEC_PROJ/review/post-execution-fix-log.json" <<'JSON'
{
  "required_fixes_completed": true,
  "unresolved_blocking_count": 0,
  "final_verdict": "PASS",
  "fixed_findings": []
}
JSON
# CASE_ID: l2.p9.reject.missing-review-evidence
expect_reject l2.p9.reject.missing-review-evidence "$POSTEXEC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$POSTEXEC_PROJ"
python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$POSTEXEC_PROJ" 9 post_execution_panel >/dev/null
# CASE_ID: phase.9.positive
expect_pass phase.9.positive "$POSTEXEC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$POSTEXEC_PROJ"

BAD_POSTEXEC_ENGINE_PROJ="$TMP/bad-postexec-engine-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_ENGINE_PROJ"
python3 - "$BAD_POSTEXEC_ENGINE_PROJ/review/post-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["review_engine"]["skill"] = "scholar-auto-research"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: phase.9.negative
expect_reject phase.9.negative "$BAD_POSTEXEC_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_ENGINE_PROJ"

BAD_POSTEXEC_JSON_PROJ="$TMP/bad-postexec-json-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_JSON_PROJ"
printf '{}\n' > "$BAD_POSTEXEC_JSON_PROJ/review/post-execution-review.json"
# CASE_ID: l2.p9.reject.placeholder-review
expect_reject l2.p9.reject.placeholder-review "$BAD_POSTEXEC_JSON_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_JSON_PROJ"

BAD_POSTEXEC_ROLE_PROJ="$TMP/bad-postexec-role-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_ROLE_PROJ"
python3 - "$BAD_POSTEXEC_ROLE_PROJ/review/post-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewers"] = [r for r in data["reviewers"] if r["role"] != "interpretation_claims"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p9.reject.reviewer-role
expect_reject l2.p9.reject.reviewer-role "$BAD_POSTEXEC_ROLE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_ROLE_PROJ"

BAD_POSTEXEC_PROVENANCE_BINDING_PROJ="$TMP/bad-postexec-provenance-binding-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_PROVENANCE_BINDING_PROJ"
python3 - "$BAD_POSTEXEC_PROVENANCE_BINDING_PROJ/review/post-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewer_provenance"][0]["report_path"] = data["reviewer_provenance"][1]["report_path"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p9.reject.provenance-binding
expect_reject l2.p9.reject.provenance-binding "$BAD_POSTEXEC_PROVENANCE_BINDING_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_PROVENANCE_BINDING_PROJ"

BAD_POSTEXEC_VALUE_PROJ="$TMP/bad-postexec-value-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_VALUE_PROJ"
python3 - "$BAD_POSTEXEC_VALUE_PROJ/review/post-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewed_specs"][0]["estimate"] = -9.999
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p9.reject.reviewed-spec-value
expect_reject l2.p9.reject.reviewed-spec-value "$BAD_POSTEXEC_VALUE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_VALUE_PROJ"

BAD_POSTEXEC_FIGURE_PROJ="$TMP/bad-postexec-figure-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_FIGURE_PROJ"
python3 - "$BAD_POSTEXEC_FIGURE_PROJ/review/post-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["reviewed_figures"][0]["visual_inspection"] = False
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p9.reject.figure-inspection
expect_reject l2.p9.reject.figure-inspection "$BAD_POSTEXEC_FIGURE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_FIGURE_PROJ"

BAD_POSTEXEC_RAW_VERIFY_PROJ="$TMP/bad-postexec-raw-verify-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_RAW_VERIFY_PROJ"
python3 - "$BAD_POSTEXEC_RAW_VERIFY_PROJ/review/post-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["raw_output_verification"]["checked_raw_tables"] = ["tables/results-registry.csv"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p9.reject.raw-output-coverage
expect_reject l2.p9.reject.raw-output-coverage "$BAD_POSTEXEC_RAW_VERIFY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_RAW_VERIFY_PROJ"

BAD_POSTEXEC_CARRY_PROJ="$TMP/bad-postexec-carryforward-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_CARRY_PROJ"
python3 - "$BAD_POSTEXEC_CARRY_PROJ/review/post-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["phase7_constraint_carryforward"]["claim_constraints_reflect_phase7"] = False
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p9.reject.phase7-carryforward
expect_reject l2.p9.reject.phase7-carryforward "$BAD_POSTEXEC_CARRY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_CARRY_PROJ"

BAD_POSTEXEC_HASH_PROJ="$TMP/bad-postexec-hash-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_HASH_PROJ"
printf 'S3,M1,Y,X,0.1,0.1,0.5,100,completed,tables/model-results.csv\n' >> "$BAD_POSTEXEC_HASH_PROJ/tables/results-registry.csv"
# CASE_ID: l2.p9.reject.stale-input-hash
expect_reject l2.p9.reject.stale-input-hash "$BAD_POSTEXEC_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_HASH_PROJ"

BAD_POSTEXEC_ROUTE_PROJ="$TMP/bad-postexec-route-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_ROUTE_PROJ"
python3 - "$BAD_POSTEXEC_ROUTE_PROJ/review/post-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["route_back_phase"] = "8"
data["decision"] = "ROUTE_BACK"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p9.reject.route-back
expect_reject l2.p9.reject.route-back "$BAD_POSTEXEC_ROUTE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_ROUTE_PROJ"

BAD_POSTEXEC_UNEXPECTED_PROJ="$TMP/bad-postexec-unexpected-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_UNEXPECTED_PROJ"
python3 - "$BAD_POSTEXEC_UNEXPECTED_PROJ/review/post-execution-review.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["unexpected_results"] = []
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p9.reject.unexpected-results
expect_reject l2.p9.reject.unexpected-results "$BAD_POSTEXEC_UNEXPECTED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_UNEXPECTED_PROJ"

BAD_POSTEXEC_MARKDOWN_PROJ="$TMP/bad-postexec-markdown-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_MARKDOWN_PROJ"
printf 'A blocking invalid result remains unresolved even though JSON says pass.\n' > "$BAD_POSTEXEC_MARKDOWN_PROJ/review/post-execution-review.md"
# CASE_ID: l2.p9.reject.markdown-contradiction
expect_reject l2.p9.reject.markdown-contradiction "$BAD_POSTEXEC_MARKDOWN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_MARKDOWN_PROJ"

if [[ "${SCHOLAR_FIXTURE_PHASE5_9_WRONG_REASON:-0}" != "1" ]]; then
  WRONG_REASON_5_9_OUT="$TMP/phase5-9-wrong-reason.out"
  if (
    unset SCHOLAR_HARNESS_SOURCE_ROOT SCHOLAR_HARNESS_MANIFEST
    unset SCHOLAR_HARNESS_RESULTS_DIR SCHOLAR_HARNESS_RUN_ID SCHOLAR_HARNESS_RUN_NONCE
    unset SCHOLAR_HARNESS_SUITE_MODE SCHOLAR_HARNESS_SUITE_ORDER
    unset SCHOLAR_HARNESS_MANIFEST_SHA256 SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256
    unset SCHOLAR_HARNESS_CAPABILITY
    export SCHOLAR_FIXTURE_PHASE5_9_WRONG_REASON=1
    export SCHOLAR_FIXTURE_STOP_AFTER_PHASE=9
    bash "$SCRIPT_DIR/auto-research-fixture-test.sh"
  ) >"$WRONG_REASON_5_9_OUT" 2>&1; then
    echo "FAIL: phase 5-9 wrong-reason mutation unexpectedly passed" >&2
    exit 1
  fi
  grep -F 'HARNESS_ASSERTION_FAILED: case=phase.5.negative exact diagnostic count expected=1 observed=0;' \
    "$WRONG_REASON_5_9_OUT" >/dev/null \
    || {
      echo "FAIL: phase 5-9 wrong-reason mutation did not fail at the exact diagnostic gate" >&2
      exit 1
    }
fi

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "9" ]]; then
  harness_validate_results --phase-through 9 >/dev/null
  progress "phases 0 to 9 authoritative harness assertions passed"
  exit 0
fi

SANITY_PROJ="$TMP/runtime-sanity-project"
cp -R "$POSTEXEC_PROJ" "$SANITY_PROJ"
mkdir -p "$SANITY_PROJ/verify"
SANITY_SPEC_HASH="$(shasum -a 256 "$SANITY_PROJ/analysis/spec-registry.csv" | awk '{print $1}')"
SANITY_EXEC_HASH="$(shasum -a 256 "$SANITY_PROJ/analysis/execution-report.json" | awk '{print $1}')"
SANITY_RESULTS_HASH="$(shasum -a 256 "$SANITY_PROJ/tables/results-registry.csv" | awk '{print $1}')"
SANITY_FIGURES_HASH="$(shasum -a 256 "$SANITY_PROJ/figures/figure-registry.csv" | awk '{print $1}')"
SANITY_POST_HASH="$(shasum -a 256 "$SANITY_PROJ/review/post-execution-review.json" | awk '{print $1}')"
SANITY_POST_FIX_HASH="$(shasum -a 256 "$SANITY_PROJ/review/post-execution-fix-log.json" | awk '{print $1}')"
SANITY_LOADED_HASH="$(shasum -a 256 "$SANITY_PROJ/data/interim/panel-loaded.rds" | awk '{print $1}')"
SANITY_SAMPLE_HASH="$(shasum -a 256 "$SANITY_PROJ/data/processed/analytic-sample.rds" | awk '{print $1}')"
SANITY_VARIABLES_HASH="$(shasum -a 256 "$SANITY_PROJ/data/processed/analytic-variables.rds" | awk '{print $1}')"
SANITY_PLANNED_CALLS_HASH="$(shasum -a 256 "$SANITY_PROJ/analysis/planned-model-calls.json" | awk '{print $1}')"
SANITY_MODEL_RESULTS_HASH="$(shasum -a 256 "$SANITY_PROJ/tables/model-results.csv" | awk '{print $1}')"
SANITY_REGRESSION_MAIN_HASH="$(shasum -a 256 "$SANITY_PROJ/tables/regression-main.html" | awk '{print $1}')"
SANITY_EVENT_STUDY_HASH="$(shasum -a 256 "$SANITY_PROJ/figures/event-study.png" | awk '{print $1}')"
SANITY_SPEC_FINGERPRINTS="$(python3 - "$SANITY_PROJ/analysis/spec-registry.csv" <<'PY'
import csv, hashlib, json, sys
with open(sys.argv[1], newline='', encoding='utf-8') as f:
    rows = list(csv.DictReader(f))
out = {}
for row in rows:
    spec_id = str(row.get("spec_id", "")).strip()
    if spec_id:
        normalized = json.dumps({k: str(v).strip() for k, v in sorted(row.items())}, sort_keys=True)
        out[spec_id] = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
print(json.dumps(out, sort_keys=True))
PY
)"
cat > "$SANITY_PROJ/verify/runtime-sanity.json" <<JSON
{
  "verdict": "PASS",
  "degraded": false,
  "decision": "PROCEED_TO_RESULTS_LOCK",
  "ready_for_phase_11": true,
  "runtime_engine": {
    "skill": "scholar-auto-research",
    "mode": "runtime_sanity",
    "auto_research_contract": "phase_10",
    "deterministic_gate": true
  },
  "source_hashes": {
    "spec_registry": "$SANITY_SPEC_HASH",
    "execution_report": "$SANITY_EXEC_HASH",
    "results_registry": "$SANITY_RESULTS_HASH",
    "figure_registry": "$SANITY_FIGURES_HASH",
    "post_execution_review": "$SANITY_POST_HASH",
    "post_execution_fix_log": "$SANITY_POST_FIX_HASH"
  },
  "phase9_status": {
    "verdict": "PASS",
    "decision": "PROCEED_TO_RUNTIME_SANITY",
    "ready_for_phase_10": true,
    "critical_count": 0,
    "unresolved_blocking_count": 0,
    "route_back_phase": null
  },
  "phase9_constraint_carryforward": {
    "unexpected_results_checked": true,
    "claim_constraints_checked": true,
    "unexpected_result_spec_ids": ["S2"],
    "forbidden_claim_verbs": ["prove", "causes", "guarantees"],
    "required_disclosures": ["observational design", "weaker robustness estimate"],
    "evidence": "Phase 9 weak robustness classification and claim constraints are carried into runtime sanity before results lock."
  },
  "plausibility": {
    "verdict": "PASS",
    "checks": [
      {"domain": "numeric_finite", "status": "PASS", "evidence": "All estimates and standard errors are finite."},
      {"domain": "sample_size", "status": "PASS", "evidence": "All result rows use n=1200."},
      {"domain": "p_value_range", "status": "PASS", "evidence": "All p-values fall between zero and one."},
      {"domain": "effect_magnitude", "status": "PASS", "evidence": "Effects are plausible for the educational expectation scale."},
      {"domain": "interpretation_constraints", "status": "PASS", "evidence": "Phase 9 claim constraints are present."}
    ]
  },
  "clean_room": {
    "verdict": "PASS",
    "reviewed_artifacts_match": true,
    "artifact_hashes": {
      "spec_registry": "$SANITY_SPEC_HASH",
      "execution_report": "$SANITY_EXEC_HASH",
      "results_registry": "$SANITY_RESULTS_HASH",
      "figure_registry": "$SANITY_FIGURES_HASH",
      "post_execution_review": "$SANITY_POST_HASH",
      "post_execution_fix_log": "$SANITY_POST_FIX_HASH"
    },
    "run": {
      "verdict": "PASS",
      "mode": "fixture_clean_room_hash_check",
      "commands": ["Rscript analysis/scripts/01_load_data.R", "Rscript analysis/scripts/02_build_sample.R", "Rscript analysis/scripts/03_construct_variables.R", "Rscript analysis/scripts/04_plan_models.R"],
      "exit_codes": {
        "analysis/scripts/01_load_data.R": 0,
        "analysis/scripts/02_build_sample.R": 0,
        "analysis/scripts/03_construct_variables.R": 0,
        "analysis/scripts/04_plan_models.R": 0
      },
      "input_hashes": {
        "spec_registry": "$SANITY_SPEC_HASH",
        "post_execution_review": "$SANITY_POST_HASH"
      },
      "output_hashes": {
        "data/interim/panel-loaded.rds": "$SANITY_LOADED_HASH",
        "data/processed/analytic-sample.rds": "$SANITY_SAMPLE_HASH",
        "data/processed/analytic-variables.rds": "$SANITY_VARIABLES_HASH",
        "analysis/planned-model-calls.json": "$SANITY_PLANNED_CALLS_HASH",
        "tables/results-registry.csv": "$SANITY_RESULTS_HASH",
        "figures/figure-registry.csv": "$SANITY_FIGURES_HASH",
        "tables/model-results.csv": "$SANITY_MODEL_RESULTS_HASH",
        "tables/regression-main.html": "$SANITY_REGRESSION_MAIN_HASH",
        "figures/event-study.png": "$SANITY_EVENT_STUDY_HASH"
      },
      "numeric_tolerance": 1e-09,
      "seed": "not-used-fixture",
      "session_info": "fixture shell validation"
    }
  },
  "invariants": {
    "verdict": "PASS",
    "checks": [
      {"name": "planned_specs_equal_results", "status": "PASS", "evidence": "S1, S2, and S3 appear in both planned and result registries."},
      {"name": "execution_report_matches_registries", "status": "PASS", "evidence": "Execution report registry paths match output registries."},
      {"name": "expected_outputs_exist", "status": "PASS", "evidence": "All Phase 8 expected outputs exist."},
      {"name": "figure_registry_complete", "status": "PASS", "evidence": "All figure files are registered."},
      {"name": "post_execution_review_current", "status": "PASS", "evidence": "Post-execution review hash matches current file."},
      {"name": "phase8_artifact_manifest_current", "status": "PASS", "evidence": "Every Phase 8 artifact_manifest path exists with a matching hash."},
      {"name": "phase9_constraints_current", "status": "PASS", "evidence": "Phase 9 unexpected result and claim-constraint records are unchanged."}
    ]
  },
  "pap_drift": {
    "verdict": "PASS",
    "planned_spec_ids": ["S1", "S2", "S3"],
    "executed_spec_ids": ["S1", "S2", "S3"],
    "spec_fingerprints": $SANITY_SPEC_FINGERPRINTS,
    "unresolved_drift_count": 0,
    "drift_items": [
      {"drift_id": "NONE", "status": "none", "description": "No unresolved analysis-plan drift detected."}
    ]
  },
  "artifact_inventory": [
    {"path": "analysis/execution-report.json", "sha256": "$SANITY_EXEC_HASH", "lock_candidate": true},
    {"path": "tables/results-registry.csv", "sha256": "$SANITY_RESULTS_HASH", "lock_candidate": true},
    {"path": "tables/model-results.csv", "sha256": "$SANITY_MODEL_RESULTS_HASH", "lock_candidate": true},
    {"path": "tables/regression-main.html", "sha256": "$SANITY_REGRESSION_MAIN_HASH", "lock_candidate": true},
    {"path": "figures/figure-registry.csv", "sha256": "$SANITY_FIGURES_HASH", "lock_candidate": true},
    {"path": "figures/event-study.png", "sha256": "$SANITY_EVENT_STUDY_HASH", "lock_candidate": true},
    {"path": "review/post-execution-review.json", "sha256": "$SANITY_POST_HASH", "lock_candidate": true}
  ],
  "lock_candidate_reconciliation": {
    "status": "PASS",
    "required_paths": [
      "analysis/execution-report.json",
      "figures/event-study.png",
      "figures/figure-registry.csv",
      "review/post-execution-review.json",
      "tables/model-results.csv",
      "tables/regression-main.html",
      "tables/results-registry.csv"
    ],
    "inventory_paths": [
      "analysis/execution-report.json",
      "figures/event-study.png",
      "figures/figure-registry.csv",
      "review/post-execution-review.json",
      "tables/model-results.csv",
      "tables/regression-main.html",
      "tables/results-registry.csv"
    ],
    "missing_paths": [],
    "extra_paths": [],
    "phase8_manifest_paths_checked": [
      "analysis/planned-model-calls.json",
      "data/interim/panel-loaded.rds",
      "data/processed/analytic-sample.rds",
      "data/processed/analytic-variables.rds",
      "figures/event-study.png",
      "figures/figure-registry.csv",
      "tables/model-results.csv",
      "tables/regression-main.html",
      "tables/results-registry.csv"
    ]
  },
  "critical_count": 0,
  "unresolved_blocking_count": 0,
  "route_back_phase": null
}
JSON
python3 - "$SANITY_PROJ/verify/runtime-sanity.md" <<'PY'
import sys
path = sys.argv[1]
sentence = "The runtime sanity check confirms that execution artifacts, result registries, figure registries, and post execution review artifacts are current and internally consistent. Plausibility, clean room artifact matching, invariant checks, and plan drift checks all pass before results locking. "
with open(path, "w", encoding="utf-8") as f:
    f.write(sentence * 5)
PY
# CASE_ID: phase.10.positive
expect_pass phase.10.positive "$SANITY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$SANITY_PROJ"

BAD_SANITY_VERDICT_PROJ="$TMP/bad-sanity-verdict-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_VERDICT_PROJ"
python3 - "$BAD_SANITY_VERDICT_PROJ/verify/runtime-sanity.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["verdict"] = "FAIL"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: phase.10.negative
expect_reject phase.10.negative "$BAD_SANITY_VERDICT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_VERDICT_PROJ"

BAD_SANITY_ENGINE_PROJ="$TMP/bad-sanity-engine-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_ENGINE_PROJ"
python3 - "$BAD_SANITY_ENGINE_PROJ/verify/runtime-sanity.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["runtime_engine"]["skill"] = "inline-runtime-check"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p10.reject.runtime-engine
expect_reject l2.p10.reject.runtime-engine "$BAD_SANITY_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_ENGINE_PROJ"

BAD_SANITY_CONSTRAINT_PROJ="$TMP/bad-sanity-constraint-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_CONSTRAINT_PROJ"
python3 - "$BAD_SANITY_CONSTRAINT_PROJ/verify/runtime-sanity.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["phase9_constraint_carryforward"]["unexpected_result_spec_ids"] = []
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p10.reject.constraint-carryforward
expect_reject l2.p10.reject.constraint-carryforward "$BAD_SANITY_CONSTRAINT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_CONSTRAINT_PROJ"

BAD_SANITY_PHASE8_MANIFEST_PROJ="$TMP/bad-sanity-phase8-manifest-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_PHASE8_MANIFEST_PROJ"
python3 - "$BAD_SANITY_PHASE8_MANIFEST_PROJ/analysis/execution-report.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["artifact_manifest"][0]["fixture_rebind_marker"] = "clean-room-negative"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
rebind_phase10_fixture_hashes "$BAD_SANITY_PHASE8_MANIFEST_PROJ" execution_report
# CASE_ID: l2.p10.reject.clean-room-artifact-hash
expect_reject l2.p10.reject.clean-room-artifact-hash "$BAD_SANITY_PHASE8_MANIFEST_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_PHASE8_MANIFEST_PROJ"

BAD_SANITY_RECON_PROJ="$TMP/bad-sanity-reconciliation-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_RECON_PROJ"
python3 - "$BAD_SANITY_RECON_PROJ/verify/runtime-sanity.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["lock_candidate_reconciliation"]["missing_paths"] = ["tables/model-results.csv"]
data["lock_candidate_reconciliation"]["required_paths"] = [
    path for path in data["lock_candidate_reconciliation"]["required_paths"]
    if path != "tables/model-results.csv"
]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p10.reject.lock-reconciliation
expect_reject l2.p10.reject.lock-reconciliation "$BAD_SANITY_RECON_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_RECON_PROJ"

BAD_SANITY_HASH_PROJ="$TMP/bad-sanity-hash-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_HASH_PROJ"
python3 - "$BAD_SANITY_HASH_PROJ/verify/runtime-sanity.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["source_hashes"]["results_registry"] = "0" * 64
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p10.reject.source-hash
expect_reject l2.p10.reject.source-hash "$BAD_SANITY_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_HASH_PROJ"

BAD_SANITY_PLAUS_PROJ="$TMP/bad-sanity-plausibility-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_PLAUS_PROJ"
python3 - "$BAD_SANITY_PLAUS_PROJ/verify/runtime-sanity.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["plausibility"]["checks"][0]["status"] = "FAIL"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p10.reject.plausibility
expect_reject l2.p10.reject.plausibility "$BAD_SANITY_PLAUS_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_PLAUS_PROJ"

BAD_SANITY_DRIFT_PROJ="$TMP/bad-sanity-drift-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_DRIFT_PROJ"
python3 - "$BAD_SANITY_DRIFT_PROJ/verify/runtime-sanity.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["pap_drift"]["unresolved_drift_count"] = 1
data["pap_drift"]["drift_items"] = [{"drift_id": "D1", "status": "open", "description": "Unresolved drift"}]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p10.reject.pap-drift
expect_reject l2.p10.reject.pap-drift "$BAD_SANITY_DRIFT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_DRIFT_PROJ"

BAD_SANITY_INV_PROJ="$TMP/bad-sanity-inventory-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_INV_PROJ"
python3 - "$BAD_SANITY_INV_PROJ/verify/runtime-sanity.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["artifact_inventory"] = data["artifact_inventory"][:2]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
# CASE_ID: l2.p10.reject.artifact-inventory
expect_reject l2.p10.reject.artifact-inventory "$BAD_SANITY_INV_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_INV_PROJ"

BAD_SANITY_MARKDOWN_PROJ="$TMP/bad-sanity-markdown-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_MARKDOWN_PROJ"
printf 'A critical drift remains unresolved even though JSON says pass.\n' > "$BAD_SANITY_MARKDOWN_PROJ/verify/runtime-sanity.md"
# CASE_ID: l2.p10.reject.markdown-contradiction
expect_reject l2.p10.reject.markdown-contradiction "$BAD_SANITY_MARKDOWN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_MARKDOWN_PROJ"

LOCK_PROJ="$TMP/results-lock-project"
cp -R "$SANITY_PROJ" "$LOCK_PROJ"
mkdir -p "$LOCK_PROJ/results-locked"
python3 - "$LOCK_PROJ" <<'PY'
import hashlib
import json
import pathlib
import shutil
import sys
from datetime import datetime, timezone

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def manifest_hash(manifest):
    clone = dict(manifest)
    clone.pop("manifest_sha256", None)
    payload = json.dumps(clone, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()

sanity = json.loads((proj / "verify/runtime-sanity.json").read_text())
lock_id = "LOCK-20260429-001"
active_dir = proj / "results-locked" / lock_id
active_dir.mkdir(parents=True, exist_ok=True)
roles = {
    "analysis/execution-report.json": "execution_report",
    "tables/results-registry.csv": "results_registry",
    "tables/model-results.csv": "diagnostic",
    "tables/regression-main.html": "main_regression_table",
    "figures/figure-registry.csv": "figure_registry",
    "figures/event-study.png": "figure_file",
    "review/post-execution-review.json": "post_execution_review",
}
locked_artifacts = []
for item in sanity["artifact_inventory"]:
    source = item["path"]
    locked = f"results-locked/{lock_id}/{source}"
    target = proj / locked
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(proj / source, target)
    locked_artifacts.append({
        "source_path": source,
        "locked_path": locked,
        "sha256": item["sha256"],
        "artifact_role": roles.get(source, "lock_candidate"),
        "lock_status": "copied"
    })
manifest = {
    "verdict": "PASS",
    "degraded": False,
    "lock_engine": {
        "skill": "scholar-auto-research",
        "mode": "results_lock",
        "auto_research_contract": "phase_11",
        "deterministic_lock": True
    },
    "lock_id": lock_id,
    "created_at": "2026-04-29T12:00:00Z",
    "source_hashes": {
        "runtime_sanity": sha(proj / "verify/runtime-sanity.json"),
        "runtime_sanity_md": sha(proj / "verify/runtime-sanity.md"),
        "execution_report": sha(proj / "analysis/execution-report.json"),
        "results_registry": sha(proj / "tables/results-registry.csv"),
        "figure_registry": sha(proj / "figures/figure-registry.csv"),
        "post_execution_review": sha(proj / "review/post-execution-review.json")
    },
    "locked_artifacts": locked_artifacts,
    "latest_matches": True,
    "stage1_verdict": "PASS",
    "ready_for_phase_12": True
}
manifest["manifest_sha256"] = manifest_hash(manifest)
(proj / "results-locked/LATEST.txt").write_text(lock_id + "\n")
(proj / "results-locked/manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
checked = []
for item in locked_artifacts:
    checked.append({
        "source_path": item["source_path"],
        "locked_path": item["locked_path"],
        "source_hash": item["sha256"],
        "locked_hash": sha(proj / item["locked_path"]),
        "verdict": "PASS"
    })
stage1 = {
    "verdict": "PASS",
    "degraded": False,
    "lock_id": lock_id,
    "manifest_sha256": manifest["manifest_sha256"],
    "input_manifest_sha256": manifest["manifest_sha256"],
    "checked_artifacts": checked,
    "checked_count": len(checked),
    "missing_count": 0,
    "mismatch_count": 0,
    "extra_locked_count": 0,
    "missing_paths": [],
    "mismatch_paths": [],
    "extra_locked_paths": [],
    "scanner_provenance": {
        "scanner": "auto-research-verify",
        "mode": "results_lock_stage1",
        "auto_research_contract": "phase_11",
        "verified_at": "2026-04-29T12:00:00Z"
    },
    "ready_for_phase_12": True
}
(proj / "verify/stage1-verify.json").write_text(json.dumps(stage1, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.11.positive
expect_pass phase.11.positive "$LOCK_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$LOCK_PROJ"

BAD_LOCK_VERDICT_PROJ="$TMP/bad-lock-verdict-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_VERDICT_PROJ"
python3 - "$BAD_LOCK_VERDICT_PROJ/results-locked/manifest.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.loads(open(path, encoding="utf-8").read())
data["verdict"] = "FAIL"
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.11.negative
expect_reject phase.11.negative "$BAD_LOCK_VERDICT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_VERDICT_PROJ"

BAD_LOCK_ENGINE_PROJ="$TMP/bad-lock-engine-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_ENGINE_PROJ"
python3 - "$BAD_LOCK_ENGINE_PROJ/results-locked/manifest.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.loads(open(path, encoding="utf-8").read())
data["lock_engine"]["skill"] = "manual-copy"
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p11.reject.lock-engine
expect_reject l2.p11.reject.lock-engine "$BAD_LOCK_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_ENGINE_PROJ"

BAD_LOCK_LATEST_FLAG_PROJ="$TMP/bad-lock-latest-flag-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_LATEST_FLAG_PROJ"
python3 - "$BAD_LOCK_LATEST_FLAG_PROJ/results-locked/manifest.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.loads(open(path, encoding="utf-8").read())
data["latest_matches"] = False
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p11.reject.latest-flag
expect_reject l2.p11.reject.latest-flag "$BAD_LOCK_LATEST_FLAG_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_LATEST_FLAG_PROJ"

BAD_LOCK_STAGE1_PROVENANCE_PROJ="$TMP/bad-lock-stage1-provenance-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_STAGE1_PROVENANCE_PROJ"
python3 - "$BAD_LOCK_STAGE1_PROVENANCE_PROJ/verify/stage1-verify.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.loads(open(path, encoding="utf-8").read())
data["scanner_provenance"]["scanner"] = "manual-stage1-check"
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p11.reject.stage1-provenance
expect_reject l2.p11.reject.stage1-provenance "$BAD_LOCK_STAGE1_PROVENANCE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_STAGE1_PROVENANCE_PROJ"

BAD_LOCK_STAGE1_VERDICT_PROJ="$TMP/bad-lock-stage1-verdict-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_STAGE1_VERDICT_PROJ"
python3 - "$BAD_LOCK_STAGE1_VERDICT_PROJ/results-locked/manifest.json" "$BAD_LOCK_STAGE1_VERDICT_PROJ/verify/stage1-verify.json" <<'PY'
import hashlib
import json
import pathlib
import sys
manifest_path = pathlib.Path(sys.argv[1])
stage1_path = pathlib.Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text())
stage1 = json.loads(stage1_path.read_text())
manifest["stage1_verdict"] = "FAIL"
clone = dict(manifest)
clone.pop("manifest_sha256", None)
manifest["manifest_sha256"] = hashlib.sha256(json.dumps(clone, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
stage1["manifest_sha256"] = manifest["manifest_sha256"]
stage1["input_manifest_sha256"] = manifest["manifest_sha256"]
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
stage1_path.write_text(json.dumps(stage1, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p11.reject.stage1-verdict
expect_reject l2.p11.reject.stage1-verdict "$BAD_LOCK_STAGE1_VERDICT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_STAGE1_VERDICT_PROJ"

BAD_LOCK_LATEST_PROJ="$TMP/bad-lock-latest-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_LATEST_PROJ"
printf 'OTHER-LOCK\n' > "$BAD_LOCK_LATEST_PROJ/results-locked/LATEST.txt"
# CASE_ID: l2.p11.reject.latest-pointer
expect_reject l2.p11.reject.latest-pointer "$BAD_LOCK_LATEST_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_LATEST_PROJ"

BAD_LOCK_MISSING_PROJ="$TMP/bad-lock-missing-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_MISSING_PROJ"
python3 - "$BAD_LOCK_MISSING_PROJ/results-locked/manifest.json" "$BAD_LOCK_MISSING_PROJ/verify/stage1-verify.json" <<'PY'
import json
import hashlib
import sys
manifest_path, stage1_path = sys.argv[1:3]
manifest = json.loads(open(manifest_path, encoding="utf-8").read())
stage1 = json.loads(open(stage1_path, encoding="utf-8").read())
manifest["locked_artifacts"] = manifest["locked_artifacts"][:-1]
stage1["checked_artifacts"] = stage1["checked_artifacts"][:-1]
clone = dict(manifest)
clone.pop("manifest_sha256", None)
manifest["manifest_sha256"] = hashlib.sha256(
    json.dumps(clone, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()
stage1["manifest_sha256"] = manifest["manifest_sha256"]
stage1["input_manifest_sha256"] = manifest["manifest_sha256"]
open(manifest_path, "w", encoding="utf-8").write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
open(stage1_path, "w", encoding="utf-8").write(json.dumps(stage1, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p11.reject.lock-candidate-coverage
expect_reject l2.p11.reject.lock-candidate-coverage "$BAD_LOCK_MISSING_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_MISSING_PROJ"

BAD_LOCK_HASH_PROJ="$TMP/bad-lock-hash-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_HASH_PROJ"
python3 - "$BAD_LOCK_HASH_PROJ/results-locked/manifest.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.loads(open(path, encoding="utf-8").read())
data["created_at"] = "2026-04-29T13:00:00Z"
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p11.reject.manifest-self-hash
expect_reject l2.p11.reject.manifest-self-hash "$BAD_LOCK_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_HASH_PROJ"

BAD_LOCK_STAGE1_PROJ="$TMP/bad-lock-stage1-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_STAGE1_PROJ"
python3 - "$BAD_LOCK_STAGE1_PROJ/verify/stage1-verify.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.loads(open(path, encoding="utf-8").read())
data["checked_artifacts"][0]["verdict"] = "FAIL"
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p11.reject.stage1-artifact-check
expect_reject l2.p11.reject.stage1-artifact-check "$BAD_LOCK_STAGE1_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_STAGE1_PROJ"

BAD_LOCK_EXTRA_PROJ="$TMP/bad-lock-extra-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_EXTRA_PROJ"
printf 'unmanifested\n' > "$BAD_LOCK_EXTRA_PROJ/results-locked/LOCK-20260429-001/unmanifested-extra.csv"
# CASE_ID: l2.p11.reject.unmanifested-file
expect_reject l2.p11.reject.unmanifested-file "$BAD_LOCK_EXTRA_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_EXTRA_PROJ"

BAD_LOCK_SOURCE_DRIFT_PROJ="$TMP/bad-lock-source-drift-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_SOURCE_DRIFT_PROJ"
printf '\n' >> "$BAD_LOCK_SOURCE_DRIFT_PROJ/tables/results-registry.csv"
rebind_phase10_fixture_hashes "$BAD_LOCK_SOURCE_DRIFT_PROJ"
# CASE_ID: l2.p11.reject.source-drift
expect_reject l2.p11.reject.source-drift "$BAD_LOCK_SOURCE_DRIFT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_SOURCE_DRIFT_PROJ"

BAD_LOCK_OUTSIDE_PROJ="$TMP/bad-lock-outside-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_OUTSIDE_PROJ"
python3 - "$BAD_LOCK_OUTSIDE_PROJ/results-locked/manifest.json" "$BAD_LOCK_OUTSIDE_PROJ/verify/stage1-verify.json" <<'PY'
import hashlib
import json
import pathlib
import sys
manifest_path = pathlib.Path(sys.argv[1])
stage1_path = pathlib.Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text())
stage1 = json.loads(stage1_path.read_text())
manifest["locked_artifacts"][0]["locked_path"] = manifest["locked_artifacts"][0]["source_path"]
clone = dict(manifest)
clone.pop("manifest_sha256", None)
manifest["manifest_sha256"] = hashlib.sha256(json.dumps(clone, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
stage1["manifest_sha256"] = manifest["manifest_sha256"]
stage1["input_manifest_sha256"] = manifest["manifest_sha256"]
stage1["checked_artifacts"][0]["locked_path"] = manifest["locked_artifacts"][0]["locked_path"]
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
stage1_path.write_text(json.dumps(stage1, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p11.reject.outside-lock-path
expect_reject l2.p11.reject.outside-lock-path "$BAD_LOCK_OUTSIDE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_OUTSIDE_PROJ"

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "11" ]]; then
  harness_validate_results --phase-through 11 >/dev/null
  progress "phases 0 to 11 authoritative harness assertions passed"
  exit 0
fi

DRAFT_PROJ="$TMP/draft-project"
progress "phases 13 to 15 drafting, verification, and citation fixtures"
cp -R "$LOCK_PROJ" "$DRAFT_PROJ"
mkdir -p "$DRAFT_PROJ/manuscript" "$DRAFT_PROJ/literature" "$DRAFT_PROJ/idea" "$DRAFT_PROJ/design" "$DRAFT_PROJ/analysis"
cp "$LIT_PROJ/literature/references.bib" "$DRAFT_PROJ/literature/references.bib"
cp "$LIT_PROJ/literature/lit-theory.md" "$DRAFT_PROJ/literature/lit-theory.md"
cp "$RQ_PROJ/idea/research-question.json" "$DRAFT_PROJ/idea/research-question.json"
cp "$RQ_PROJ/idea/journal-fit.json" "$DRAFT_PROJ/idea/journal-fit.json"
cp "$DESIGN_PROJ/design/design-blueprint.md" "$DRAFT_PROJ/design/design-blueprint.md"
cp "$ANALYSIS_PLAN_PROJ/analysis/analysis-plan.md" "$DRAFT_PROJ/analysis/analysis-plan.md"
python3 - "$DRAFT_PROJ" <<'PY'
import csv
import hashlib
import json
import pathlib
import re
import sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def wc(text):
    return len(re.findall(r"\b[\w'-]+\b", text))

def prose_only_text(text):
    visible = re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)
    visible = re.sub(r"(?is)<table\b.*?</table>", " ", visible)
    visible = re.sub(r"!\[[^\]]*\]\([^)]+\)", " ", visible)
    visible = re.sub(r"\[[^\]]+\]\([^)]+\)", " ", visible)
    kept = []
    in_fenced = False
    for line in visible.splitlines():
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fenced = not in_fenced
            continue
        if in_fenced or stripped.startswith("|"):
            continue
        if re.match(r"^(?:\*\*)?(?:Table|Figure)\s+\d+[.:]", stripped, flags=re.IGNORECASE):
            continue
        if re.match(r"^Notes?:", stripped, flags=re.IGNORECASE):
            continue
        kept.append(line)
    return "\n".join(kept)

def prose_wc(text):
    return wc(prose_only_text(text))

def section_counts(text):
    sections = {}
    current = None
    buffer = []
    for line in text.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            if current is not None:
                sections[current] = "\n".join(buffer)
            current = re.sub(r"[^a-z0-9]+", " ", m.group(1).lower()).strip()
            buffer = []
        elif current is not None:
            buffer.append(line)
    if current is not None:
        sections[current] = "\n".join(buffer)
    return {k: wc(v) for k, v in sections.items()}

def section_prose_counts(text):
    sections = {}
    current = None
    buffer = []
    for line in text.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            if current is not None:
                sections[current] = "\n".join(buffer)
            current = re.sub(r"[^a-z0-9]+", " ", m.group(1).lower()).strip()
            buffer = []
        elif current is not None:
            buffer.append(line)
    if current is not None:
        sections[current] = "\n".join(buffer)
    return {k: wc(prose_only_text(v)) for k, v in sections.items()}

lock_manifest = json.loads((proj / "results-locked/manifest.json").read_text())
registry_lock = next(item for item in lock_manifest["locked_artifacts"] if item["artifact_role"] == "results_registry")
journal_fit = json.loads((proj / "idea/journal-fit.json").read_text())
journal_profile_resolution = journal_fit["journal_profile_resolution"]
core_citations = " ".join(f"[@work{i:02d}]" for i in range(1, 13))
extended_citations = " ".join(f"[@work{i:02d}]" for i in range(13, 31))
all_citations = " ".join(f"[@work{i:02d}]" for i in range(1, 31))
anchors = []
coverage = []
reader_roles = {"result_table", "model_output", "main_regression_table", "sensitivity_regression_table", "regression_table", "figure_file"}
for item in lock_manifest["locked_artifacts"]:
    anchor = f"<!-- LOCKED_ARTIFACT: {item['source_path']} | LOCKED_PATH: {item['locked_path']} -->"
    used = item["artifact_role"] in reader_roles
    coverage_item = {
        "source_path": item["source_path"],
        "locked_path": item["locked_path"],
        "artifact_role": item["artifact_role"],
        "manuscript_anchor": anchor if used else "",
        "used_in_manuscript": used
    }
    if used:
        anchors.append(anchor)
    if item["artifact_role"] == "main_regression_table":
        coverage_item.update({
            "display_anchor": "<!-- DISPLAY_TABLE: tables/regression-main.html -->",
            "display_status": "rendered_inline",
            "display_type": "regression_table_html",
            "caption_text": "Table 2. Regression estimates for parental job loss and adolescent educational expectations.",
            "display_label": "Table 2",
            "results_callout": "Table 2 shows that the primary specification is negative and that weaker robustness evidence remains subordinate to the headline estimate.",
            "claim_source": {
                "schema_version": 2,
                "binding_type": "mapped_structured_source",
                "source_path": registry_lock["source_path"],
                "locked_path": registry_lock["locked_path"],
                "sha256": registry_lock["sha256"],
                "row_selector_field": "spec_id",
                "rendered_table": {"grammar": "markdown_pipe_v1", "orientation": "models_as_columns", "term_column": "Predictor", "field_rows": {"estimate_std_error": "Parental job loss", "p_value": "p-value", "n": "N"}},
                "selected_rows": [{"selector": "S1", "display_column": "Model 1"}, {"selector": "S2", "display_column": "Model 2"}, {"selector": "S3", "display_column": "Model 3"}]
            }
        })
    elif item["artifact_role"] == "figure_file":
        coverage_item.update({
            "display_anchor": "<!-- DISPLAY_FIGURE: figures/event-study.png -->",
            "display_status": "rendered_inline",
            "display_type": "markdown_image",
            "caption_text": "Figure 1. Event-study diagnostic figure.",
            "display_label": "Figure 1",
            "results_callout": "Figure 1 presents the event-study diagnostic and visually reinforces that the tabled pattern is negative but bounded."
        })
    coverage.append(coverage_item)
abstract = (
    "This article examines whether parental job loss is associated with adolescent educational expectations in household panel data. "
    "The question matters for family inequality research because adolescents form educational plans while households absorb labor-market risk, stress, and resource constraints. "
    "Using an observational panel design with household fixed effects, wave fixed effects, and robustness checks for timing and attrition, the analysis estimates bounded associations rather than causal effects. "
    "The findings show that parental job loss is linked to lower educational expectations, while one timing-oriented check is directionally similar but less precise. "
    "The article contributes to family sociology by showing how economic instability can enter expectation formation while making uncertainty and design limits part of the substantive claim. "
    f"{core_citations}"
)
intro_paragraphs = [
    "Educational expectations are a central bridge between family conditions and later attainment, because they organize course taking, institutional navigation, and the perceived value of continued schooling. Parental job loss can alter that bridge by changing material resources, stress exposure, and beliefs about what educational investments remain feasible. The puzzle is therefore not only whether economic instability matters, but how a household shock becomes attached to adolescents' own future-oriented judgments. [@work01] [@work02] [@work03]",
    "Prior literature has established strong links between family resources, parental employment, and educational attainment, yet less is known about how adolescents revise expectations during a parent's employment disruption. Existing research also leaves unresolved whether household shocks mainly depress expectations through stress and constraint or whether some families respond by emphasizing schooling as protection against future insecurity. This gap motivates a focused empirical test of expectation formation rather than a broad claim about every pathway from job loss to attainment. [@work04] [@work05] [@work06]",
    "The article advances a bounded contribution for family sociology. It integrates family stress and status attainment perspectives, estimates the association in panel data, and evaluates whether timing and attrition checks support the same interpretation. This contribution is deliberately disciplined: the analysis asks whether the pattern is consistent with a feasibility mechanism while recognizing that unobserved time-varying shocks may still shape both parental employment and adolescent planning.",
    "The remainder of the article therefore follows the structure of a quantitative family article. The next section develops the theory and states the hypothesis, the Data and Methods section explains the sample, measures, and analytic strategy, the Results section presents descriptive and regression evidence, and the Discussion and Conclusion return to the theoretical contribution and limits of the observational design."
]
lit_paragraphs = [
    """### Family Stress and Economic Shock
The family stress perspective defines parental job loss as a household-level disruption that can alter routines, emotional climate, and available resources. Educational expectations refer to adolescents' beliefs about the schooling they are likely to complete, so the concept is a future-oriented judgment rather than an observed attainment outcome. When employment instability enters the household, adolescents may hear new conversations about affordability, observe parental strain, or perceive reduced capacity to support educational plans. The mechanism is not simply income loss; it is the translation of economic uncertainty into everyday judgments about what schooling remains feasible. [@work07] [@work08] [@work09] [@work10] [@work11] [@work12]""",
    """### Status Attainment and Educational Feasibility
Status attainment research treats expectations as socially organized beliefs about plausible futures rather than private preferences alone. Adolescents learn what seems possible from parents, schools, peers, and the resources surrounding them. A parent's job loss can signal that economic security is fragile and that continued schooling may require tradeoffs the household cannot easily absorb. From this perspective, expectations are a point at which structural risk becomes translated into perceived opportunity. [@work13] [@work14] [@work15] [@work16] [@work17] [@work18]""",
    """### Rival Expectations and Scope Conditions
A competing account is that some families respond to economic insecurity by emphasizing education as protection against future vulnerability. This alternative is important because it prevents the theory from assuming a one-directional response to hardship. The association may also vary by savings, school context, timing of the shock, and adolescents' prior expectations. These scope conditions imply that a single estimate should be interpreted as an average pattern across heterogeneous household responses, not as a universal family process. [@work19] [@work20] [@work21] [@work22] [@work23] [@work24]""",
    """### Testable Expectation
The preceding arguments predict a testable hypothesis. If parental job loss reduces perceived educational feasibility through stress, resource constraints, and uncertainty, adolescents exposed to job loss should report lower educational expectations than comparable adolescents observed without that household shock. H1 is the study hypothesis: parental job loss is associated with lower adolescent educational expectations. The timing and attrition checks probe whether this expectation is sensitive to event timing and observed sample composition; they do not convert the observational design into a causal experiment. [@work25] [@work26] [@work27] [@work28] [@work29] [@work30]"""
]
methods_paragraphs = [
    """### Data and Sample
The analysis uses household panel data with repeated observations of adolescents and parental employment. The source file initially contains 2,500 adolescents from 1,760 households observed across eligible survey waves. I restrict the data to adolescents with nonmissing educational expectations, observed parental employment histories, household income, child age, and valid wave identifiers, and I exclude records outside the age range covered by the study question. These restrictions align the denominator with the outcome, exposure, and fixed-effects design. After applying the eligibility rules and complete-case requirements for modeled variables, the final analytic sample includes N = 1,200 observations. The final analytic sample is therefore justified by the need to compare observed changes in expectations within households while retaining the variables required for adjustment and robustness checks.""",
    """### Variables and Measures
#### Dependent Variable
The dependent variable is adolescent educational expectations. It measures the highest level of schooling the adolescent expects to complete, using a survey item recorded as an ordered expectation scale and treated as a continuous score in the linear models. Higher values indicate more ambitious expected attainment. This outcome captures perceived educational feasibility, not completed schooling.

#### Independent Variable
The independent variable is parental job loss. It is coded as a binary indicator equal to 1 when a parent experiences an employment transition into job loss between observed waves and 0 otherwise. The measure is based on panel employment reports and is interpreted as a household economic shock that may change adolescents' planning environment.

#### Control Variables
The control variables include child age, survey wave, and household income. Child age is measured in years and adjusts for developmental differences in expectations. Survey wave indicators absorb period-specific differences in the survey environment and educational context. Household income is measured as total household income and adjusts for observed economic resources that may confound the association between job loss and educational expectations.""",
    """### Analytic Strategy
The primary model is a household fixed-effects linear regression because the research question concerns within-household changes in adolescent educational expectations around parental job loss. I estimate this regression with household-clustered standard errors. The estimating equation is EducationalExpectations_it = alpha_i + lambda_t + beta JobLoss_it + gamma Age_it + delta Income_it + epsilon_it, where alpha_i denotes household fixed effects and lambda_t denotes wave fixed effects. The coefficient beta compares educational expectations within the same household after parental job loss with expectations in observations without job loss, net of child age, household income, and wave conditions. Standard errors are clustered at the household level to account for repeated observations within households. This estimator is appropriate for the panel structure, but it remains observational because time-varying unmeasured shocks may still coincide with job loss. Observational claims must remain bounded.""",
    """The analysis reports the full primary specification rather than presenting a long stepwise sequence in the main text. Robustness and sensitivity checks assess whether the association is sensitive to event timing and sample composition. A timing specification adds event-study indicators to inspect pre-shock patterns and the shape of adjustment around job loss. An attrition-weighted sensitivity analysis first estimates a logit propensity score for remaining in the final analytic sample using baseline observed characteristics, including parental job loss exposure, child age, wave, and household income. The weighting algorithm uses inverse probability weighting rather than nearest-neighbor matching, and overlap is evaluated with common support and standardized differences. After weighting, the outcome model re-estimates the household fixed-effects specification. Complete-case denominators are reported for the modeled variables, and survey design decisions are handled through the robustness weights rather than as causal identification."""
]
results_paragraphs = [
    "Table 1 reports descriptive statistics for all modeled variables in the analytic sample, including adolescent educational expectations, parental job loss, child age, survey wave, and household income. These descriptives establish the scale, coding, and denominator before the regression evidence is interpreted.",
    "Table 2 shows the headline regression estimates for the primary and robustness specifications. In Model 1, the primary specification, parental job loss is associated with lower adolescent educational expectations, with an estimate of -0.120, a standard error of 0.040, a p-value of 0.003, and n = 1200 [@work01]. This is the clearest result in the reviewed evidence, so the manuscript treats it as the main empirical anchor rather than spreading equal weight across every specification. Its direction matches the feasibility mechanism developed in the theory section, but the interpretation remains associational because the design cannot rule out all time-varying unobserved shocks.",
    "Table 2 also shows why the manuscript frames robustness evidence cautiously. For Model 2, the timing-oriented specification has a negative estimate of -0.080, a standard error of 0.050, a p-value of 0.110, and n = 1200 [@work02]. For Model 3, the attrition-weighted specification has a negative estimate of -0.090, a standard error of 0.045, a p-value of 0.046, and n = 1200 [@work03]. These side-by-side results support a negative pattern with uneven robustness instead of uniform confirmation. The weaker robustness estimate is treated as a boundary on the claim rather than as a finding to smooth over. Primary claims must stay aligned with reviewed evidence. All numerical claims must stay aligned with reviewed evidence.",
    "Figure 1 presents the event-study diagnostic and visually supports the same bounded reading. The figure is not treated as standalone proof; instead, it helps readers inspect timing and visual consistency while the tabled estimates carry the inferential claims. Read together, the descriptive statistics, regression table, and diagnostic figure indicate that the pattern is negative in the primary specification, weaker in one robustness check, and therefore best interpreted as evidence for a cautious observational claim rather than a decisive causal story."
]
discussion_paragraphs = [
    "The findings suggest that household economic instability may shape educational expectations through perceived feasibility and stress-linked constraints. The contribution is to connect family economic shocks with expectation formation while preserving the distinction between a reviewed association and broader causal interpretation. The pattern is substantively meaningful because educational expectations are part of the pathway through which family circumstances can become linked to later attainment. Table 2 and Figure 1 are discussed as evidence for this bounded interpretation rather than as proof of causation. At the same time, the evidence is not uniform enough to support a sweeping claim, which is why the interpretation stays close to the theory of constrained feasibility.",
    "The weaker robustness evidence narrows the claim and motivates future work with stronger identification, longer follow-up, and richer measures of household coping. The timing-sensitive evidence is less precise than the primary estimate, which may reflect sparse event-time information or limits in the measured shock. Future designs could combine administrative employment histories with repeated expectation measures to observe adjustment more directly. Such work would help distinguish short-term disruption from longer-term changes in educational planning.",
    "The manuscript also has measurement and design limitations. Educational expectations capture perceived futures, but they do not reveal every conversation, resource tradeoff, or emotional response inside the household. The observational design means that unmeasured shocks could coincide with parental job loss and adolescent planning. These limitations are disclosed because they define the claim's scope rather than merely qualifying it after the fact."
]
conclusion_paragraphs = [
    "This article began with a problem in family inequality research: adolescents form educational plans while families experience economic shocks, yet the literature has less evidence on how job loss enters expectation formation before attainment is observed. The theoretical argument joined family stress and status attainment perspectives to show why employment instability may reduce perceived educational feasibility. The empirical evidence supports a bounded conclusion: parental job loss is linked to lower adolescent educational expectations in the primary panel analysis, with some uncertainty across robustness checks. The contribution is not a causal demonstration; it is a bounded observational claim about how household economic instability is associated with future-oriented educational beliefs. Future research can extend this contribution by using stronger identification, longer panels, and richer measures of household coping to clarify when adolescents revise expectations after family employment shocks. This next step matters because expectation formation is one channel through which temporary household disruption may become connected to durable educational inequality."
]
display_descriptive_block = "\n".join([
    "Table 1. Descriptive statistics for modeled variables in the analytic sample.",
    "",
    "| Variable | Coding or scale | Mean / percent | N |",
    "| --- | --- | ---: | ---: |",
    "| Adolescent educational expectations | Ordered expected schooling scale | 4.20 | 1200 |",
    "| Parental job loss | Binary indicator, 1 = job loss | 0.18 | 1200 |",
    "| Child age | Continuous years | 15.10 | 1200 |",
    "| Survey wave | Categorical wave indicators | -- | 1200 |",
    "| Household income | Continuous household income | 52,300 | 1200 |",
    "Notes: Table 1 reports reader-facing descriptive statistics for every variable used in the modeled specifications."
])
display_table_block = "\n".join([
    "<!-- DISPLAY_TABLE: tables/regression-main.html -->",
    "Table 2. Regression estimates for parental job loss and adolescent educational expectations.",
    "",
    "| Predictor | Model 1 | Model 2 | Model 3 |",
    "| --- | ---: | ---: | ---: |",
    "| Parental job loss | -0.120 (0.040) | -0.080 (0.050) | -0.090 (0.045) |",
    "| p-value | 0.003 | 0.110 | 0.046 |",
    "| N | 1200 | 1200 | 1200 |",
])
display_figure_block = "\n".join([
    "<!-- DISPLAY_FIGURE: figures/event-study.png -->",
    "Figure 1. Event-study diagnostic figure.",
    "",
    "![Figure 1. Event-study diagnostic figure](figures/event-study.png)",
])
manuscript = "\n\n".join([
    "# Parental Job Loss and Adolescent Educational Expectations",
    "Keywords: parental job loss; educational expectations; family inequality; panel data",
    "## Abstract\n" + abstract,
    "## Introduction\n" + "\n\n".join(intro_paragraphs),
    "## Background\n" + "\n\n".join(lit_paragraphs),
    "## Data and Methods\n" + "\n\n".join(methods_paragraphs),
    "## Results\n" + "\n".join(anchors) + "\n\n" + display_descriptive_block + "\n\n" + display_table_block + "\n\n" + display_figure_block + "\n\n" + "\n\n".join(results_paragraphs),
    "## Discussion\n" + "\n\n".join(discussion_paragraphs),
    "## Conclusion\n" + "\n\n".join(conclusion_paragraphs),
    "## References\nAuthor, F. (2020). Verified citation fixture.",
])
(proj / "manuscript/manuscript-draft.md").write_text(manuscript + "\n")
counts = section_counts(manuscript)
prose_counts = section_prose_counts(manuscript)
main_text_word_count = sum(
    prose_counts.get(section, 0)
    for section in ("abstract", "introduction", "background", "data and methods", "results", "discussion", "conclusion")
)
sentence_counts = {}
for sentence in re.split(r"(?<=[.!?])\s+", re.sub(r"<!--.*?-->", " ", manuscript, flags=re.DOTALL)):
    normalized = re.sub(r"[^a-z0-9]+", " ", sentence.lower()).strip()
    if wc(normalized) >= 8:
        sentence_counts[normalized] = sentence_counts.get(normalized, 0) + 1
max_repeated_sentence_count = max(sentence_counts.values(), default=0)
section_budget = {
    "abstract": {"target_words": 180, "min_words": 80, "max_words": 300},
    "introduction": {"target_words": 500, "min_words": 280, "max_words": 850},
    "background": {"target_words": 650, "min_words": 320, "max_words": 1200},
    "data and methods": {"target_words": 850, "min_words": 520, "max_words": 1500},
    "results": {"target_words": 700, "min_words": 320, "max_words": 1100},
    "discussion": {"target_words": 420, "min_words": 220, "max_words": 850},
    "conclusion": {"target_words": 220, "min_words": 120, "max_words": 420},
}
journal_structure = {
    "profile_source": "scholar-journal:jmf",
    "section_sequence": ["Abstract", "Introduction", "Background", "Data and Methods", "Results", "Discussion", "Conclusion", "References", "Tables", "Figures"],
    "results_before_methods": False,
    "theory_presentation": "background_section",
    "methods_section_label": "Data and Methods",
    "discussion_conclusion_policy": "split_required",
    "supplement_policy": "journal_optional_appendix"
}
display_architecture = {
    "table_placement_policy": "end_matter_after_references",
    "figure_placement_policy": "separate_files_after_tables",
    "descriptive_table_requirement": "journal_optional",
    "editable_text_tables": True,
    "image_tables_forbidden": True,
    "main_text_display_cap": None,
    "main_text_table_cap": None,
    "main_text_figure_cap": None,
    "supplement_label_prefix": "Appendix",
    "panel_label_style": "A_B_C",
    "table_rendering_mode": "editable_text_end_matter",
    "figure_rendering_mode": "separate_figure_files",
    "table_title_position": "above_table",
    "table_notes_policy": "below_table_notes",
    "display_callout_style": "numbered_tables_and_figures"
}
journal_spec = {
    "verdict": "PASS",
    "source_engine": "scholar-journal",
    "mode": "prepare",
    "engine_provenance": {
        "skill": "scholar-journal",
        "mode": "prepare",
        "task_invocation_id": "phase13-journal-001",
        "invoked_at_utc": "2026-04-30T09:00:00Z",
        "input_artifacts": ["idea/journal-fit.json", "idea/research-question.json", "manuscript/manuscript-blueprint.json"],
        "output_artifacts": ["manuscript/journal-spec.json"]
    },
    "target_journal": "Journal of Marriage and Family",
    "journal_family": "family sociology",
    # Audit 2026-05-03: this fixture intentionally targets the JMF
    # research-note path so its compact (~3,000-word) manuscript stays
    # consistent with its declared total_word_range.min. Setting paper_type
    # to "empirical article" with a 1300-word floor would leak a hollow
    # floor into in-context training; full-empirical-article coverage is
    # now provided by tests/smoke/test-journal-spec-profile-check.sh.
    "paper_type": "research note",
    "journal_profile_resolution": journal_profile_resolution,
    "total_word_range": {"min": 1300, "max": 12000},
    "abstract_word_cap": 300,
    "section_word_budget": section_budget,
    "journal_structure": journal_structure,
    "display_architecture": display_architecture,
    "numeric_reporting_policy": {
        "policy_source": "default_auto_research_when_journal_silent",
        "inferential_digits": 3,
        "descriptive_digits": 2,
        "p_value_rule": "Report exact p-values to 3 decimals and use p < .001 below the reporting floor.",
        "allow_scientific_notation": False
    },
    "format_notes": {
        "citation_style": "APA-like author-date",
        "appendix_policy": "separate appendix if required by journal"
    },
    "ready_for_drafting": True
}
(proj / "manuscript/journal-spec.json").write_text(json.dumps(journal_spec, indent=2, sort_keys=True) + "\n")
blueprint = {
    "verdict": "PASS",
    "degraded": False,
    "blueprint_engine": {
        "skill": "scholar-auto-research",
        "mode": "manuscript_blueprint",
        "lock_enforced": True,
        "live_output_reads_forbidden": True
    },
    "lock_id": lock_manifest["lock_id"],
    "lock_manifest_sha256": lock_manifest["manifest_sha256"],
    "source_hashes": {
        "lock_manifest": sha(proj / "results-locked/manifest.json"),
        "stage1_verify": sha(proj / "verify/stage1-verify.json"),
        "research_question": sha(proj / "idea/research-question.json"),
        "journal_fit": sha(proj / "idea/journal-fit.json"),
        "lit_theory": sha(proj / "literature/lit-theory.md"),
        "design_blueprint": sha(proj / "design/design-blueprint.md"),
        "identification_strategy": sha(proj / "design/identification-strategy.json"),
        "analysis_plan": sha(proj / "analysis/analysis-plan.md"),
        "post_execution_review": sha(proj / "review/post-execution-review.json"),
        "results_registry": sha(proj / "tables/results-registry.csv"),
        "figure_registry": sha(proj / "figures/figure-registry.csv")
    },
    "paper_type": "research note",
    "target_journal": "Journal of Marriage and Family",
    "journal_profile_resolution": journal_profile_resolution,
    "paper_claim": "The locked manuscript should frame parental job loss as negatively associated with adolescent educational expectations while keeping the contribution observational and bounded.",
    "claim_strength": "descriptive_associational",
    "contribution_stack": [
        {
            "rank": 1,
            "contribution_type": "primary_result",
            "claim_text": "The primary locked specification links parental job loss to lower adolescent educational expectations.",
            "depends_on_results": True,
            "scope_note": "The claim is observational and bounded by the active lock."
        },
        {
            "rank": 2,
            "contribution_type": "mechanism_context",
            "claim_text": "The manuscript should interpret the estimate through family stress and status-attainment mechanisms without causal overclaim.",
            "depends_on_results": True,
            "scope_note": "Mechanisms are interpretive rather than causally identified."
        }
    ],
    "publication_readiness": {
        "status": "PASS",
        "ready_for_drafting": True,
        "route_back_if_not_ready": False,
        "contribution_sentence": "The paper contributes a bounded family-sociology account of how parental job loss is associated with adolescent educational expectations in panel data.",
        "target_journal_novelty_claim": "For the target journal, the novelty is the integration of family stress, status-attainment mechanisms, and transparent robustness limits around educational expectations.",
        "target_journal_fit": "The paper fits the venue because it links family economic instability to adolescent educational planning with clear empirical limits.",
        "mechanism_rival_matrix": [
            {
                "role": "mechanism",
                "label": "Perceived educational feasibility",
                "evidence_link": "Primary regression table and family-stress theory",
                "claim_implication": "Interpret negative estimates as evidence consistent with constrained educational planning."
            },
            {
                "role": "rival",
                "label": "Compensatory educational motivation",
                "evidence_link": "Theory section and weaker timing robustness evidence",
                "claim_implication": "Frame the result as bounded rather than universally deterministic."
            },
            {
                "role": "scope_condition",
                "label": "Observational panel design",
                "evidence_link": "Design blueprint and results table",
                "claim_implication": "Avoid causal language and state limitations in Results and Discussion."
            }
        ],
        "reviewer_risk_register": [
            {
                "risk_type": "strongest_rejection_reason",
                "strongest_rejection_reason": True,
                "objection": "The observational design may not separate job loss from concurrent household shocks.",
                "required_response": "State the associational claim, report uncertainty, and describe stronger follow-up designs.",
                "route_back_phase": "3"
            },
            {
                "risk_type": "robustness",
                "objection": "The timing robustness check is weaker than the headline estimate.",
                "required_response": "Keep Model 2 subordinate and describe uneven robustness as part of the finding.",
                "route_back_phase": "9"
            },
            {
                "risk_type": "measurement",
                "objection": "Educational expectations are ordinal and may not behave like a continuous outcome.",
                "required_response": "Disclose the outcome-family decision and interpret estimates as ordered-scale associations.",
                "route_back_phase": "5"
            }
        ],
        "evidence_claim_map": [
            {
                "claim": "Parental job loss is negatively associated with adolescent educational expectations.",
                "artifact_path": "tables/regression-main.html",
                "evidence_type": "canonical regression table",
                "claim_strength": "descriptive association",
                "claim_status": "headline"
            },
            {
                "claim": "Timing evidence is directionally similar but less precise.",
                "artifact_path": "figures/event-study.png",
                "evidence_type": "diagnostic figure",
                "claim_strength": "supporting diagnostic",
                "claim_status": "diagnostic"
            },
            {
                "claim": "The interpretation remains bounded by observational design limits.",
                "limitation": "unobserved time-varying shocks cannot be ruled out",
                "evidence_type": "design limitation",
                "claim_strength": "scope condition",
                "claim_status": "scope"
            }
        ]
    },
    "result_hierarchy": [
        {
            "artifact_path": "tables/results-registry.csv",
            "artifact_role": "results_registry",
            "narrative_role": "registry provenance for the locked manuscript claims",
            "headline_status": "diagnostic"
        },
        {
            "artifact_path": "tables/regression-main.html",
            "artifact_role": "main_regression_table",
            "spec_id": "S1",
            "narrative_role": "headline regression table",
            "headline_status": "headline"
        },
        {
            "artifact_path": "figures/event-study.png",
            "artifact_role": "figure_file",
            "figure_id": "F1",
            "narrative_role": "headline event-study figure",
            "headline_status": "headline"
        }
    ],
    "hypothesis_resolution": [
        {
            "hypothesis_id": "H1",
            "resolution_status": "supported",
            "evidence_specs": ["S1"],
            "manuscript_implication": "State the primary negative association directly and bound it to the locked observational design."
        }
    ],
    "mechanism_integration_plan": [
        {
            "mechanism_id": "M1",
            "theory_role": "family stress and status attainment",
            "evidence_role": "interpreted alongside the locked primary estimate",
            "integration_status": "discussion_only"
        }
    ],
    "journal_structure": journal_structure,
    "display_architecture": display_architecture,
    "discussion_mode": "split",
    "appendix_policy": {
        "draft": ["workflow_appendix", "traceability_appendix"],
        "final": ["traceability_appendix"],
        "submission": []
    },
    "section_obligations": {
        "abstract": {"required_moves": ["state the question", "name the data", "report the main finding", "state the contribution"], "required_artifacts": [], "required_disclosures": ["observational design"], "forbidden_moves": ["causal overclaim"]},
        "introduction": {"required_moves": ["pose the puzzle", "state the gap", "preview the answer"], "required_artifacts": [], "required_disclosures": [], "forbidden_moves": ["promise causality"]},
        "literature_review_and_theory": {"required_moves": ["summarize mechanisms", "set up expectations"], "required_artifacts": [], "required_disclosures": [], "forbidden_moves": ["treat theory as proof"]},
        "data_and_methods": {"required_moves": ["describe the sample", "state the estimator", "state observational limits"], "required_artifacts": [], "required_disclosures": ["Observational claims must remain bounded."], "forbidden_moves": ["describe the design as causal"]},
        "results": {"required_moves": ["present the primary estimate first", "show uncertainty", "keep robustness subordinate"], "required_artifacts": ["tables/regression-main.html", "figures/event-study.png"], "required_disclosures": ["Primary claims must stay aligned with reviewed evidence."], "forbidden_moves": ["elevate sensitivity checks over the headline result"]},
        "discussion": {"required_moves": ["answer the research question", "state limitations", "bound the contribution"], "required_artifacts": ["tables/regression-main.html", "figures/event-study.png"], "required_disclosures": ["observational design", "weaker robustness estimate"], "forbidden_moves": ["causal certainty"]},
        "conclusion": {"required_moves": ["summarize the contribution", "state the bounded conclusion"], "required_artifacts": [], "required_disclosures": ["bounded observational claim"], "forbidden_moves": ["causal certainty"]}
    },
    "required_disclosures": ["observational design", "weaker robustness estimate", "All numerical claims must stay aligned with reviewed evidence."],
    "forbidden_moves": ["Do not make causal claims.", "Do not outrank the headline regression result with subordinate checks."],
    "table_figure_narrative_map": [
        {"artifact_path": "tables/regression-main.html", "display_expected": True, "section": "results", "paragraph_role": "main finding paragraph", "claim_role": "headline estimate"},
        {"artifact_path": "figures/event-study.png", "display_expected": True, "section": "results", "paragraph_role": "visual evidence paragraph", "claim_role": "graphical support"}
    ],
    "abstract_alignment": {"required_elements": ["question", "data", "main finding", "contribution"], "forbidden_elements": ["causal language"]},
    "discussion_alignment": {"required_answer": "Parental job loss is negatively associated with adolescent educational expectations in the primary specification.", "required_limitations": ["observational design"], "forbidden_spins": ["causal certainty"]},
    "null_result_framing": {"status": "PASS", "primary_result_class": "directional_primary_result", "allowed_contribution": "bounded empirical contribution", "forbidden_salvage_moves": []},
    "route_back_phase": None,
    "ready_for_phase_13": True
}
(proj / "manuscript/manuscript-blueprint.json").write_text(json.dumps(blueprint, indent=2, sort_keys=True) + "\n")
(proj / "manuscript/manuscript-blueprint.md").write_text(
    "# Manuscript Blueprint\n\n"
    "## Core Claim\n"
    "The paper makes a bounded observational claim that parental job loss is negatively associated with adolescent educational expectations in the primary specification.\n\n"
    "## Contribution Stack\n"
    "The first contribution is the headline estimate from the regression table. The second contribution is interpretive: the manuscript relates that estimate to family stress and status-attainment mechanisms without making causal claims.\n\n"
    "## Result Hierarchy\n"
    "The regression table carries the headline estimate, and the event-study figure provides supporting visual evidence. Robustness checks remain subordinate to the main reviewed result.\n\n"
    "## Venue Structure and Display Policy\n"
    "The journal-calibrated structure uses a Background section and a separate Conclusion, with tables treated as editable end-matter displays and figures treated as separate-file style displays after the tables.\n\n"
    "## Section Obligations\n"
    "The abstract must state the question, data, main finding, and contribution. The introduction must pose the puzzle and preview the bounded answer. The methods section must disclose the observational design and active-lock discipline. The results and discussion sections must carry forward the observational-design and weaker-robustness disclosures.\n\n"
    "## Interpretation Limits\n"
    "This blueprint intentionally narrows the manuscript. It forbids causal language, prevents subordinate checks from outranking the main result, and requires the discussion to answer the research question with the same bounded language used in the abstract and results sections.\n"
)
section_briefs = {}
for section in section_budget:
    section_briefs[section] = {
        "section_purpose": f"Develop the {section} section around the approved blueprint and journal structure.",
        "key_claim": "Parental job loss is associated with educational expectations under bounded observational interpretation.",
        "required_evidence": ["tables/regression-main.html"] if section in {"abstract", "data and methods", "results", "discussion", "conclusion"} else ["literature/references.bib"],
        "source_roles": ["theory", "mechanism", "rival"] if section == "background" else ["evidence", "context"],
        "forbidden_moves": ["causal overclaim", "workflow language", "registry display"]
    }
paragraph_purpose_map = []
for idx, section in enumerate(section_budget, start=1):
    paragraph_purpose_map.append({
        "section": section,
        "paragraph_id": f"paragraph {idx}",
        "purpose": f"Advance the {section} argument",
        "claim": "Keep the empirical claim bounded and journal-facing",
        "source_roles": ["theory", "evidence"] if section != "results" else ["evidence"],
        "evidence_artifacts": ["tables/regression-main.html"] if section in {"results", "discussion"} else [],
        "mechanism_link": "perceived educational feasibility"
    })
source_use_plan = []
roles = ["theory", "mechanism", "rival", "alternative", "method", "context"]
sections_for_sources = [
    "introduction opening section",
    "background theory section",
    "background rival section",
    "data and methods section",
    "results evidence section",
    "discussion limitations section"
]
for idx in range(1, 13):
    source_use_plan.append({
        "citation_key": f"work{idx:02d}",
        "argument_role": roles[(idx - 1) % len(roles)],
        "target_section": sections_for_sources[(idx - 1) % len(sections_for_sources)],
        "claim_supported": "This source supports the family instability argument or an alternative interpretation.",
        "why_necessary": "It anchors a specific theoretical, empirical, or rival claim."
    })
drafting_plan = {
    "verdict": "PASS",
    "source_phase": "13",
    "section_briefs": section_briefs,
    "paragraph_purpose_map": paragraph_purpose_map,
    "source_use_plan": source_use_plan,
    "results_interpretation_plan": [
        {
            "artifact_path": "tables/regression-main.html",
            "interpretive_claim": "Model 1 is the headline empirical anchor for the negative association.",
            "uncertainty_language": "Report the standard error, p-value, and uneven robustness without overstating certainty.",
            "mechanism_link": "The estimate is interpreted through perceived educational feasibility.",
            "limitation_language": "The observational design does not rule out unobserved concurrent shocks."
        },
        {
            "artifact_path": "figures/event-study.png",
            "interpretive_claim": "The figure provides diagnostic timing context rather than standalone proof.",
            "uncertainty_language": "Describe the diagnostic as supportive but not decisive evidence.",
            "mechanism_link": "The timing pattern is linked to household adjustment after job loss.",
            "limitation_language": "Sparse event timing limits strong causal interpretation."
        }
    ],
    "revision_workflow": {
        "outline_completed": True,
        "draft_after_plan": True,
        "self_critique_required": True
    }
}
(proj / "manuscript/drafting-plan.json").write_text(json.dumps(drafting_plan, indent=2, sort_keys=True) + "\n")
self_critique = {
    "verdict": "PASS",
    "ready_for_verification": True,
    "strongest_rejection_reason": "A reviewer could object that the observational design cannot separate job loss from concurrent household shocks.",
    "unsupported_leap_scan": {
        "status": "PASS",
        "summary": "The manuscript uses associational language and avoids converting estimates into causal claims."
    },
    "missing_rival_scan": {
        "status": "PASS",
        "summary": "The background and discussion include compensatory motivation as a rival interpretation."
    },
    "claim_strength_scan": {
        "status": "PASS",
        "summary": "The draft keeps the main claim descriptive and flags uneven robustness evidence."
    },
    "workflow_language_scan": {
        "status": "PASS",
        "summary": "Visible prose uses journal-facing evidence language and avoids internal workflow labels."
    },
    "revision_actions": [
        {
            "action": "Replace internal model labels with reader-facing Model 1 through Model 3 labels.",
            "status": "completed"
        },
        {
            "action": "Keep the weaker timing check subordinate to the headline table result.",
            "status": "completed"
        }
    ]
}
(proj / "manuscript/draft-self-critique.json").write_text(json.dumps(self_critique, indent=2, sort_keys=True) + "\n")
polish_report = {
    "verdict": "PASS",
    "polish_engine": {
        "skill": "scholar-polish",
        "mode": "full",
        "intensity": "moderate",
        "auto_research_contract": "phase_13",
        "task_invocation_id": "phase13-polish-001",
        "invoked_at_utc": "2026-04-30T10:30:00Z",
        "input_artifacts": ["manuscript/manuscript-draft.md"],
        "output_artifacts": ["manuscript/manuscript-draft.md", "manuscript/polish-report.json"]
    },
    "source_manuscript_hash": sha(proj / "manuscript/manuscript-draft.md"),
    "polished_manuscript_hash": sha(proj / "manuscript/manuscript-draft.md"),
    "patterns_checked": [
        "generic_hedging_stacks",
        "formulaic_transitions",
        "over_enumeration",
        "generic_AI_prose_markers"
    ],
    "generic_markers_remaining": {
        "high": 0,
        "medium": 0,
        "low": 1
    },
    "citation_or_numeric_changes": False,
    "argument_structure_changed": False,
    "ready_for_verification": True
}
(proj / "manuscript/polish-report.json").write_text(json.dumps(polish_report, indent=2, sort_keys=True) + "\n")
registry_rows = list(csv.DictReader((proj / registry_lock["locked_path"]).open(newline="", encoding="utf-8")))
selected = [("S1", "Model 1", "In Model 1, the primary specification"), ("S2", "Model 2", "For Model 2, the timing-oriented specification"), ("S3", "Model 3", "For Model 3, the attrition-weighted specification")]
claim_rows = []
for selector, display_column, anchor in selected:
    row_index = next(i for i, row in enumerate(registry_rows) if row.get("spec_id") == selector)
    row = registry_rows[row_index]
    identity = ["locked_result_claim_v2", "mapped_structured_source", "tables/regression-main.html", registry_lock["source_path"], row_index, selector, "column", display_column]
    claim_rows.append({"claim_id": "lrc2:" + hashlib.sha256(json.dumps(identity, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest(), "row_index": row_index, "spec_id": selector, "display_coordinate_kind": "column", "display_coordinate": display_column, "display_column": display_column, "estimate": row["estimate"], "std_error": row["std_error"], "p_value": row["p_value"], "n": row["n"], "manuscript_anchor": anchor})
locked_result_claims = [{"schema_version": 2, "binding_type": "mapped_structured_source", "source_path": registry_lock["source_path"], "locked_path": registry_lock["locked_path"], "display_source_path": "tables/regression-main.html", "display_locked_path": next(item["locked_path"] for item in lock_manifest["locked_artifacts"] if item["source_path"] == "tables/regression-main.html"), "row_count": len(claim_rows), "rows": claim_rows}]
draft_manifest = {
    "verdict": "PASS",
    "degraded": False,
    "drafting_engine": {
        "skill": "scholar-write",
        "mode": "draft",
        "section": "full paper",
        "auto_research_contract": "phase_13",
        "lock_enforced": True,
        "live_output_reads_forbidden": True,
        "task_invocation_id": "phase13-write-001",
        "invoked_at_utc": "2026-04-30T10:00:00Z",
        "input_artifacts": [
            "manuscript/manuscript-blueprint.json",
            "results-locked/manifest.json",
            "verify/stage1-verify.json",
            "literature/references.bib",
            "manuscript/journal-spec.json"
        ],
        "output_artifacts": [
            "manuscript/manuscript-draft.md",
            "manuscript/drafting-plan.json",
            "manuscript/draft-self-critique.json",
            "manuscript/draft-manifest.json"
        ]
    },
    "blueprint": {
        "path": "manuscript/manuscript-blueprint.json",
        "sha256": sha(proj / "manuscript/manuscript-blueprint.json")
    },
    "drafting_plan": {
        "path": "manuscript/drafting-plan.json",
        "sha256": sha(proj / "manuscript/drafting-plan.json")
    },
    "self_critique": {
        "path": "manuscript/draft-self-critique.json",
        "sha256": sha(proj / "manuscript/draft-self-critique.json"),
        "ready_for_verification": True
    },
    "lock_id": lock_manifest["lock_id"],
    "selected_manuscript_hash": sha(proj / "manuscript/manuscript-draft.md"),
    "lock_manifest_sha256": lock_manifest["manifest_sha256"],
    "polish_report": {
        "skill": "scholar-polish",
        "mode": "full",
        "path": "manuscript/polish-report.json",
        "sha256": sha(proj / "manuscript/polish-report.json"),
        "ready_for_verification": True
    },
    "journal_spec": {
        "skill": "scholar-journal",
        "mode": "prepare",
        "path": "manuscript/journal-spec.json",
        "sha256": sha(proj / "manuscript/journal-spec.json"),
        "target_journal": "Journal of Marriage and Family",
        "paper_type": "research note"
    },
    "source_hashes": {
        "lock_manifest": sha(proj / "results-locked/manifest.json"),
        "stage1_verify": sha(proj / "verify/stage1-verify.json"),
        "manuscript_blueprint": sha(proj / "manuscript/manuscript-blueprint.json"),
        "references_bib": sha(proj / "literature/references.bib"),
        "lit_theory": sha(proj / "literature/lit-theory.md"),
        "research_question": sha(proj / "idea/research-question.json"),
        "journal_fit": sha(proj / "idea/journal-fit.json"),
        "design_blueprint": sha(proj / "design/design-blueprint.md"),
        "variable_dictionary": sha(proj / "data/variable-dictionary.csv"),
        "analysis_plan": sha(proj / "analysis/analysis-plan.md"),
        "post_execution_review": sha(proj / "review/post-execution-review.json")
    },
    "numeric_reporting_policy": journal_spec["numeric_reporting_policy"],
    "section_word_budget": section_budget,
    "section_word_counts": counts,
    "section_prose_word_counts": prose_counts,
    "reader_facing_language": {
        "status": "PASS",
        "workflow_jargon_hits": 0,
        "internal_spec_label_hits": 0,
        "model_labels": ["Model 1", "Model 2", "Model 3"]
    },
    "budget_compliance": {
        "status": "PASS",
        "target_journal": "Journal of Marriage and Family",
        "total_word_count": wc(manuscript),
        "main_text_word_count": main_text_word_count,
        "total_word_range": {"min": 1300, "max": 12000},
        "abstract_within_cap": True,
        "sections": {section: {"words": counts.get(section, 0), "min_words": limits["min_words"], "status": "PASS"} for section, limits in section_budget.items()}
    },
    "draft_quality_gate": {
        "status": "PASS",
        "anti_stub_checked": True,
        "repetition_checked": True,
        "section_substance_checked": True,
        "locked_evidence_integrated": True,
        "journal_fit_checked": True,
        "polish_applied": True,
        "reader_facing_translation_checked": True,
        "raw_variable_name_count": 0,
        "theory_synthesis_checked": True,
        "results_comparison_checked": True,
        "results_theory_link_checked": True,
        "repeated_sentence_limit": 2,
        "max_repeated_sentence_count": max_repeated_sentence_count,
        "section_quality": {
            "abstract": {"status": "PASS", "not_stub": True, "section_specific_evidence": True, "evidence": "Abstract states the China panel setting, the parental job-loss mechanism, the negative association in the reviewed estimates, and the bounded observational claim without causal overstatement."},
            "introduction": {"status": "PASS", "not_stub": True, "section_specific_evidence": True, "evidence": "Introduction develops the family-instability puzzle, explains why adolescent educational expectations are a consequential outcome, names the Social Forces style contribution, and previews robustness boundaries for empirical readers."},
            "background": {"status": "PASS", "not_stub": True, "section_specific_evidence": True, "evidence": "Background integrates family stress, status attainment, household economic insecurity, competing expectations about adaptation, and the hypothesis linking parental job loss to adolescents' educational planning in China."},
            "data and methods": {"status": "PASS", "not_stub": True, "section_specific_evidence": True, "evidence": "Methods section names the CFPS analytic sample, outcome construction, focal predictor, household fixed-effects strategy, survey design treatment, missingness handling, model comparison, and observational limits for interpretation."},
            "results": {"status": "PASS", "not_stub": True, "section_specific_evidence": True, "evidence": "Results section presents Model 1, Model 2, and Model 3 in the original regression table format, reports uncertainty, and links the event-study figure to the interpretation."},
            "discussion": {"status": "PASS", "not_stub": True, "section_specific_evidence": True, "evidence": "Discussion interprets the negative association through family stress and status attainment arguments, separates robustness from proof, and names measurement and unobserved-shock limits for future research."},
            "conclusion": {"status": "PASS", "not_stub": True, "section_specific_evidence": True, "evidence": "Conclusion restates the bounded contribution for research on family change in China, avoids causal escalation, and closes with the implications for adolescent educational stratification debates."}
        },
        "substantive_paragraph_counts": {
            "introduction": 4,
            "background": 4,
            "data and methods": 6,
            "results": 4,
            "discussion": 3,
            "conclusion": 1
        },
        "results_prose_paragraph_count": 4
    },
    "locked_result_coverage": coverage,
    "locked_result_claims_schema_version": 2,
    "display_evidence": {
        "status": "PASS",
        "displayed_sources": ["tables/regression-main.html", "figures/event-study.png"],
        "required_table_display_min": 1,
        "required_figure_display_min": 1,
        "table_display_count": 1,
        "figure_display_count": 1,
        "results_table_callouts": ["Table 2"],
        "results_figure_callouts": ["Figure 1"],
        "all_display_items_called_out_in_results": True
    },
    "locked_result_claims": locked_result_claims,
    "citation_plan": {
        "bib_entry_count": 31,
        "unique_citations_in_draft": 30,
        "all_citations_in_bib": True,
        "unresolved_citation_count": 0
    },
    "claim_discipline": {
        "phase9_constraints_used": True,
        "overclaim_count": 0,
        "required_disclosures_present": ["observational design", "weaker robustness estimate"]
    },
    "content_alignment": {
        "research_question_answered": True,
        "mechanism_integrated": True,
        "limitations_discussed": True
    },
    "blueprint_execution": {
        "status": "PASS",
        "headline_claim_rendered": True,
        "contribution_stack_rendered": True,
        "section_obligation_checks": {"status": "PASS"},
        "demoted_results_not_overstated": True,
        "headline_results_covered": True,
        "null_result_framing_applied": True
    },
    "ready_for_phase_14": True
}
(proj / "manuscript/draft-manifest.json").write_text(json.dumps(draft_manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.12.positive
expect_pass phase.12.positive "$DRAFT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 12 "$DRAFT_PROJ"
# CASE_ID: phase.13.positive
expect_pass phase.13.positive "$DRAFT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$DRAFT_PROJ"

sync_draft_fixture_hashes() {
  local project="$1"
  python3 - "$project" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

proj = pathlib.Path(sys.argv[1])
draft_path = proj / "manuscript/manuscript-draft.md"
manifest_path = proj / "manuscript/draft-manifest.json"
polish_path = proj / "manuscript/polish-report.json"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def wc(text):
    return len(re.findall(r"\b[\w'-]+\b", text))

def prose_only_text(text):
    visible = re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)
    visible = re.sub(r"(?is)<table\b.*?</table>", " ", visible)
    visible = re.sub(r"!\[[^\]]*\]\([^)]+\)", " ", visible)
    visible = re.sub(r"\[[^\]]+\]\([^)]+\)", " ", visible)
    kept = []
    for line in visible.splitlines():
        stripped = line.strip()
        if stripped.startswith("|"):
            continue
        if re.match(r"^(?:\*\*)?(?:Table|Figure)\s+\d+[.:]", stripped, flags=re.IGNORECASE):
            continue
        if re.match(r"^Notes?:", stripped, flags=re.IGNORECASE):
            continue
        kept.append(line)
    return "\n".join(kept)

def section_texts(text):
    sections = {}
    current = None
    buffer = []
    for line in text.splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            if current is not None:
                sections[current] = "\n".join(buffer)
            current = re.sub(r"[^a-z0-9]+", " ", match.group(1).lower()).strip()
            buffer = []
        elif current is not None:
            buffer.append(line)
    if current is not None:
        sections[current] = "\n".join(buffer)
    return sections

def max_repeat(text):
    counts = {}
    for sentence in re.split(r"(?<=[.!?])\s+", re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)):
        normalized = re.sub(r"[^a-z0-9]+", " ", sentence.lower()).strip()
        if wc(normalized) >= 8:
            counts[normalized] = counts.get(normalized, 0) + 1
    return max(counts.values(), default=0)

text = draft_path.read_text()
sections = section_texts(text)
raw_counts = {key: wc(value) for key, value in sections.items()}
prose_counts = {key: wc(prose_only_text(value)) for key, value in sections.items()}
manifest = json.loads(manifest_path.read_text())
polish = json.loads(polish_path.read_text())
polish["source_manuscript_hash"] = sha(draft_path)
polish["polished_manuscript_hash"] = sha(draft_path)
polish_path.write_text(json.dumps(polish, indent=2, sort_keys=True) + "\n")
manifest["selected_manuscript_hash"] = sha(draft_path)
manifest["polish_report"]["sha256"] = sha(polish_path)
manifest["section_word_counts"] = raw_counts
manifest["section_prose_word_counts"] = prose_counts
main_sections = tuple(manifest.get("section_word_budget", {}).keys())
manifest["budget_compliance"]["total_word_count"] = wc(text)
manifest["budget_compliance"]["main_text_word_count"] = sum(prose_counts.get(section, 0) for section in main_sections)
for section, count in raw_counts.items():
    if section in manifest["budget_compliance"].get("sections", {}):
        manifest["budget_compliance"]["sections"][section]["words"] = count
        manifest["budget_compliance"]["sections"][section]["prose_words"] = prose_counts.get(section, 0)
manifest["draft_quality_gate"]["max_repeated_sentence_count"] = max_repeat(text)
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
}

PHASE13_MISSING_BRIDGE_PROJ="$TMP/phase13-missing-bridge-project"
cp -R "$DRAFT_PROJ" "$PHASE13_MISSING_BRIDGE_PROJ"
python3 - "$PHASE13_MISSING_BRIDGE_PROJ/manuscript/draft-manifest.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
item = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "main_regression_table")
item.pop("claim_source")
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p13.reject.missing-bridge
expect_reject f20.p13.reject.missing-bridge "$PHASE13_MISSING_BRIDGE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_MISSING_BRIDGE_PROJ"

PHASE13_DIRECT_BINDING_PROJ="$TMP/phase13-direct-binding-project"
cp -R "$DRAFT_PROJ" "$PHASE13_DIRECT_BINDING_PROJ"
python3 - "$PHASE13_DIRECT_BINDING_PROJ/manuscript/draft-manifest.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
item = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "main_regression_table")
item["claim_source"]["binding_type"] = "direct_reader_csv"
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p13.reject.direct-binding
expect_reject f20.p13.reject.direct-binding "$PHASE13_DIRECT_BINDING_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_DIRECT_BINDING_PROJ"

PHASE13_MALFORMED_NESTED_PROJ="$TMP/phase13-malformed-nested-project"
cp -R "$DRAFT_PROJ" "$PHASE13_MALFORMED_NESTED_PROJ"
python3 - "$PHASE13_MALFORMED_NESTED_PROJ/manuscript/draft-manifest.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
item = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "main_regression_table")
item["claim_source"]["rendered_table"] = []
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p13.reject.malformed-nested-bridge
expect_reject f20.p13.reject.malformed-nested-bridge "$PHASE13_MALFORMED_NESTED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_MALFORMED_NESTED_PROJ"

PHASE13_UNHASHABLE_ROW_INDEX_PROJ="$TMP/phase13-unhashable-row-index-project"
cp -R "$DRAFT_PROJ" "$PHASE13_UNHASHABLE_ROW_INDEX_PROJ"
python3 - "$PHASE13_UNHASHABLE_ROW_INDEX_PROJ/manuscript/draft-manifest.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["locked_result_claims"][0]["rows"][0]["row_index"] = []
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p13.reject.unhashable-row-index
expect_reject f20.p13.reject.unhashable-row-index "$PHASE13_UNHASHABLE_ROW_INDEX_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_UNHASHABLE_ROW_INDEX_PROJ"

PHASE13_NONOBJECT_GROUP_PROJ="$TMP/phase13-nonobject-group-project"
cp -R "$DRAFT_PROJ" "$PHASE13_NONOBJECT_GROUP_PROJ"
python3 - "$PHASE13_NONOBJECT_GROUP_PROJ/manuscript/draft-manifest.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["locked_result_claims"].append([])
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p13.reject.nonobject-extra-group
expect_reject f20.p13.reject.nonobject-extra-group "$PHASE13_NONOBJECT_GROUP_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_NONOBJECT_GROUP_PROJ"

PHASE13_DUPLICATE_SELECTED_PROJ="$TMP/phase13-duplicate-selected-project"
cp -R "$DRAFT_PROJ" "$PHASE13_DUPLICATE_SELECTED_PROJ"
python3 - "$PHASE13_DUPLICATE_SELECTED_PROJ/manuscript/draft-manifest.json" <<'PY'
import copy, json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
item = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "main_regression_table")
item["claim_source"]["selected_rows"].append(copy.deepcopy(item["claim_source"]["selected_rows"][0]))
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p13.reject.duplicate-selected-row
expect_reject f20.p13.reject.duplicate-selected-row "$PHASE13_DUPLICATE_SELECTED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_DUPLICATE_SELECTED_PROJ"

PHASE13_DUPLICATE_FIELD_ROWS_PROJ="$TMP/phase13-duplicate-field-rows-project"
cp -R "$DRAFT_PROJ" "$PHASE13_DUPLICATE_FIELD_ROWS_PROJ"
python3 - "$PHASE13_DUPLICATE_FIELD_ROWS_PROJ/manuscript/draft-manifest.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
item = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "main_regression_table")
item["claim_source"]["rendered_table"]["field_rows"]["p_value"] = "N"
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p13.reject.duplicate-field-rows
expect_reject f20.p13.reject.duplicate-field-rows "$PHASE13_DUPLICATE_FIELD_ROWS_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_DUPLICATE_FIELD_ROWS_PROJ"

PHASE13_FORBIDDEN_SELECTED_FIELD_PROJ="$TMP/phase13-forbidden-selected-field-project"
cp -R "$DRAFT_PROJ" "$PHASE13_FORBIDDEN_SELECTED_FIELD_PROJ"
python3 - "$PHASE13_FORBIDDEN_SELECTED_FIELD_PROJ/manuscript/draft-manifest.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
item = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "main_regression_table")
item["claim_source"]["selected_rows"][0]["model_column"] = "Model 1"
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p13.reject.forbidden-selected-field
expect_reject f20.p13.reject.forbidden-selected-field "$PHASE13_FORBIDDEN_SELECTED_FIELD_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_FORBIDDEN_SELECTED_FIELD_PROJ"

PHASE13_HIDDEN_ANCHOR_PROJ="$TMP/phase13-hidden-anchor-project"
cp -R "$DRAFT_PROJ" "$PHASE13_HIDDEN_ANCHOR_PROJ"
python3 - "$PHASE13_HIDDEN_ANCHOR_PROJ" <<'PY'
import json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
manifest_path = proj / "manuscript/draft-manifest.json"
draft_path = proj / "manuscript/manuscript-draft.md"
doc = json.loads(manifest_path.read_text())
doc["locked_result_claims"][0]["rows"][0]["manuscript_anchor"] = "Hidden primary claim anchor"
manifest_path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
draft_path.write_text(draft_path.read_text() + "\n<!-- Hidden primary claim anchor -->\n")
PY
sync_draft_fixture_hashes "$PHASE13_HIDDEN_ANCHOR_PROJ"
# CASE_ID: f20.p13.reject.hidden-comment-anchor
expect_reject f20.p13.reject.hidden-comment-anchor "$PHASE13_HIDDEN_ANCHOR_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_HIDDEN_ANCHOR_PROJ"

PHASE13_AMBIGUOUS_ANCHOR_PROJ="$TMP/phase13-ambiguous-anchor-project"
cp -R "$DRAFT_PROJ" "$PHASE13_AMBIGUOUS_ANCHOR_PROJ"
python3 - "$PHASE13_AMBIGUOUS_ANCHOR_PROJ" <<'PY'
import json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
manifest_path = proj / "manuscript/draft-manifest.json"
draft_path = proj / "manuscript/manuscript-draft.md"
doc = json.loads(manifest_path.read_text())
doc["locked_result_claims"][0]["rows"][0]["manuscript_anchor"] = "the manuscript treats it as the main empirical anchor"
manifest_path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
text = draft_path.read_text().replace(
    "Table 2 also shows why the manuscript frames robustness evidence cautiously.",
    "For clarity, the manuscript treats it as the main empirical anchor. Table 2 also shows why the manuscript frames robustness evidence cautiously.",
)
draft_path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_AMBIGUOUS_ANCHOR_PROJ"
# CASE_ID: f20.p13.reject.ambiguous-anchor
expect_reject f20.p13.reject.ambiguous-anchor "$PHASE13_AMBIGUOUS_ANCHOR_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_AMBIGUOUS_ANCHOR_PROJ"

PHASE13_TABLE_DRIFT_PROJ="$TMP/phase13-table-drift-project"
cp -R "$DRAFT_PROJ" "$PHASE13_TABLE_DRIFT_PROJ"
python3 - "$PHASE13_TABLE_DRIFT_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = "| Parental job loss | -0.120 (0.040) |"
assert text.count(old) == 1
path.write_text(text.replace(old, "| Parental job loss | -0.121 (0.040) |", 1))
PY
sync_draft_fixture_hashes "$PHASE13_TABLE_DRIFT_PROJ"
# CASE_ID: f20.p13.reject.table-only-drift
expect_reject f20.p13.reject.table-only-drift "$PHASE13_TABLE_DRIFT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_TABLE_DRIFT_PROJ"

PHASE13_PROSE_SIGN_PROJ="$TMP/phase13-prose-sign-project"
cp -R "$DRAFT_PROJ" "$PHASE13_PROSE_SIGN_PROJ"
python3 - "$PHASE13_PROSE_SIGN_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = "negative estimate of -0.080"
assert text.count(old) == 1
path.write_text(text.replace(old, "positive estimate of -0.080", 1))
PY
sync_draft_fixture_hashes "$PHASE13_PROSE_SIGN_PROJ"
# CASE_ID: f20.p13.reject.prose-sign-drift
expect_reject f20.p13.reject.prose-sign-drift "$PHASE13_PROSE_SIGN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_PROSE_SIGN_PROJ"

PHASE13_NEIGHBOR_FIELD_PROJ="$TMP/phase13-neighbor-field-project"
cp -R "$DRAFT_PROJ" "$PHASE13_NEIGHBOR_FIELD_PROJ"
python3 - "$PHASE13_NEIGHBOR_FIELD_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = "a p-value of 0.110, and n = 1200 [@work02]."
assert text.count(old) == 1
new = "a p-value of 0.111, and n = 1200 [@work02]. The neighboring audit sentence reports a p-value of 0.110."
path.write_text(text.replace(old, new, 1))
PY
sync_draft_fixture_hashes "$PHASE13_NEIGHBOR_FIELD_PROJ"
# CASE_ID: f20.p13.reject.neighboring-sentence-field
expect_reject f20.p13.reject.neighboring-sentence-field "$PHASE13_NEIGHBOR_FIELD_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_NEIGHBOR_FIELD_PROJ"

PHASE13_INELIGIBLE_BRIDGE_OWNER_PROJ="$TMP/phase13-ineligible-bridge-owner-project"
cp -R "$DRAFT_PROJ" "$PHASE13_INELIGIBLE_BRIDGE_OWNER_PROJ"
python3 - "$PHASE13_INELIGIBLE_BRIDGE_OWNER_PROJ/manuscript/draft-manifest.json" <<'PY'
import copy, json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
main = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "main_regression_table")
nonregression = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "diagnostic")
nonregression["claim_source"] = copy.deepcopy(main["claim_source"])
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p13.reject.ineligible-bridge-owner
expect_reject f20.p13.reject.ineligible-bridge-owner "$PHASE13_INELIGIBLE_BRIDGE_OWNER_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_INELIGIBLE_BRIDGE_OWNER_PROJ"

PHASE13_FORGED_MASK_PROJ="$TMP/phase13-forged-mask-project"
cp -R "$DRAFT_PROJ" "$PHASE13_FORGED_MASK_PROJ"
python3 - "$PHASE13_FORGED_MASK_PROJ" <<'PY'
import copy, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
manifest_path = proj / "manuscript/draft-manifest.json"
draft_path = proj / "manuscript/manuscript-draft.md"
doc = json.loads(manifest_path.read_text())
main = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "main_regression_table")
nonregression = next(row for row in doc["locked_result_coverage"] if row.get("artifact_role") == "diagnostic")
nonregression["claim_source"] = copy.deepcopy(main["claim_source"])
manifest_path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
registry_table = """\n| Estimate | Standard Error | p-value | N |
|---:|---:|---:|---:|
| -0.120 | 0.040 | 0.003 | 1200 |
"""
text = draft_path.read_text().replace("\n## Discussion", registry_table + "\n## Discussion", 1)
draft_path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_FORGED_MASK_PROJ"
# CASE_ID: f20.p13.reject.forged-global-mask
expect_reject f20.p13.reject.forged-global-mask "$PHASE13_FORGED_MASK_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_FORGED_MASK_PROJ"

PHASE13_UNPIPED_REGISTRY_PROJ="$TMP/phase13-unpiped-registry-project"
cp -R "$DRAFT_PROJ" "$PHASE13_UNPIPED_REGISTRY_PROJ"
python3 - "$PHASE13_UNPIPED_REGISTRY_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
table = """\n[Estimate](#estimate) | [Standard Error](#se) | [p-value](#p) | [N](#n)
---:|---:|---:|---:
-0.120 | 0.040 | 0.003 | 1200
"""
path.write_text(path.read_text().replace("\n## Discussion", table + "\n## Discussion", 1))
PY
sync_draft_fixture_hashes "$PHASE13_UNPIPED_REGISTRY_PROJ"
# CASE_ID: f20.p13.reject.unpiped-registry-table
expect_reject f20.p13.reject.unpiped-registry-table "$PHASE13_UNPIPED_REGISTRY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_UNPIPED_REGISTRY_PROJ"

PHASE13_LINK_ONLY_ANCHOR_PROJ="$TMP/phase13-link-only-anchor-project"
cp -R "$DRAFT_PROJ" "$PHASE13_LINK_ONLY_ANCHOR_PROJ"
python3 - "$PHASE13_LINK_ONLY_ANCHOR_PROJ" <<'PY'
import json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
manifest_path = proj / "manuscript/draft-manifest.json"
draft_path = proj / "manuscript/manuscript-draft.md"
doc = json.loads(manifest_path.read_text())
doc["locked_result_claims"][0]["rows"][0]["manuscript_anchor"] = "Primary result evidence link"
manifest_path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
text = draft_path.read_text().replace("\n## Discussion", "\n[Primary result evidence link](tables/regression-main.html)\n\n## Discussion", 1)
draft_path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_LINK_ONLY_ANCHOR_PROJ"
# CASE_ID: f20.p13.reject.link-only-anchor
expect_reject f20.p13.reject.link-only-anchor "$PHASE13_LINK_ONLY_ANCHOR_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_LINK_ONLY_ANCHOR_PROJ"

PHASE13_FIELD_BOUNDARY_PROJ="$TMP/phase13-field-boundary-project"
cp -R "$DRAFT_PROJ" "$PHASE13_FIELD_BOUNDARY_PROJ"
python3 - "$PHASE13_FIELD_BOUNDARY_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = "a p-value of 0.110, and n = 1200 [@work02]"
assert text.count(old) == 1
path.write_text(text.replace(old, "a map value of 0.110, and mean = 1200 [@work02]", 1))
PY
sync_draft_fixture_hashes "$PHASE13_FIELD_BOUNDARY_PROJ"
# CASE_ID: f20.p13.reject.field-token-boundaries
expect_reject f20.p13.reject.field-token-boundaries "$PHASE13_FIELD_BOUNDARY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_FIELD_BOUNDARY_PROJ"

PHASE13_SWAPPED_BUNDLES_PROJ="$TMP/phase13-swapped-bundles-project"
cp -R "$DRAFT_PROJ" "$PHASE13_SWAPPED_BUNDLES_PROJ"
python3 - "$PHASE13_SWAPPED_BUNDLES_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
s2 = "negative estimate of -0.080, a standard error of 0.050, a p-value of 0.110"
s3 = "negative estimate of -0.090, a standard error of 0.045, a p-value of 0.046"
assert text.count(s2) == 1 and text.count(s3) == 1
text = text.replace(s2, "__S2_BUNDLE__", 1).replace(s3, s2, 1).replace("__S2_BUNDLE__", s3, 1)
path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_SWAPPED_BUNDLES_PROJ"
# CASE_ID: f20.p13.reject.swapped-sentence-bundles
expect_reject f20.p13.reject.swapped-sentence-bundles "$PHASE13_SWAPPED_BUNDLES_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_SWAPPED_BUNDLES_PROJ"

PHASE13_MULTIPLE_EDGE_PIPES_PROJ="$TMP/phase13-multiple-edge-pipes-project"
cp -R "$DRAFT_PROJ" "$PHASE13_MULTIPLE_EDGE_PIPES_PROJ"
python3 - "$PHASE13_MULTIPLE_EDGE_PIPES_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = "| Predictor | Model 1 | Model 2 | Model 3 |"
assert text.count(old) == 1
path.write_text(text.replace(old, "|| Predictor | Model 1 | Model 2 | Model 3 |", 1))
PY
sync_draft_fixture_hashes "$PHASE13_MULTIPLE_EDGE_PIPES_PROJ"
# CASE_ID: f20.p13.reject.multiple-edge-pipes
expect_reject f20.p13.reject.multiple-edge-pipes "$PHASE13_MULTIPLE_EDGE_PIPES_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_MULTIPLE_EDGE_PIPES_PROJ"

PHASE13_CONTIGUOUS_TABLE_PROJ="$TMP/phase13-contiguous-table-project"
cp -R "$DRAFT_PROJ" "$PHASE13_CONTIGUOUS_TABLE_PROJ"
python3 - "$PHASE13_CONTIGUOUS_TABLE_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = "| N | 1200 | 1200 | 1200 |"
extra = old + "\n| Statistic | Model 1 | Model 2 | Model 3 |\n|---|---:|---:|---:|\n| Estimate | -0.120 | -0.080 | -0.090 |"
assert text.count(old) == 1
path.write_text(text.replace(old, extra, 1))
PY
sync_draft_fixture_hashes "$PHASE13_CONTIGUOUS_TABLE_PROJ"
# CASE_ID: f20.p13.reject.contiguous-second-table
expect_reject f20.p13.reject.contiguous-second-table "$PHASE13_CONTIGUOUS_TABLE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_CONTIGUOUS_TABLE_PROJ"

PHASE13_HTML_REGISTRY_PROJ="$TMP/phase13-html-registry-project"
cp -R "$DRAFT_PROJ" "$PHASE13_HTML_REGISTRY_PROJ"
python3 - "$PHASE13_HTML_REGISTRY_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
table = """\n<table><tbody><tr><td>Model&nbsp;ID</td><td>Estimate</td><td>Standard Error</td><td>p-value</td><td>N</td></tr><tr><td>primary</td><td>-0.120</td><td>0.040</td><td>0.003</td><td>1200</td></tr></tbody></table>\n"""
path.write_text(path.read_text().replace("\n## Discussion", table + "\n## Discussion", 1))
PY
sync_draft_fixture_hashes "$PHASE13_HTML_REGISTRY_PROJ"
# CASE_ID: f20.p13.reject.html-registry-table
expect_reject f20.p13.reject.html-registry-table "$PHASE13_HTML_REGISTRY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_HTML_REGISTRY_PROJ"

PHASE13_UNPIPED_PROJ="$TMP/phase13-unpiped-project"
cp -R "$DRAFT_PROJ" "$PHASE13_UNPIPED_PROJ"
python3 - "$PHASE13_UNPIPED_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
anchor = "<!-- DISPLAY_TABLE: tables/regression-main.html -->"
before, after = text.split(anchor, 1)
lines = after.splitlines()
inside = False
for idx, line in enumerate(lines):
    if line.startswith("|"):
        inside = True
        lines[idx] = line[1:-1].strip() if line.endswith("|") else line[1:].strip()
    elif inside:
        break
path.write_text(before + anchor + "\n".join(lines))
PY
sync_draft_fixture_hashes "$PHASE13_UNPIPED_PROJ"
# CASE_ID: f20.p13.unpiped-table-positive
expect_pass f20.p13.unpiped-table-positive "$PHASE13_UNPIPED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_UNPIPED_PROJ"

PHASE13_SCIENTIFIC_PROJ="$TMP/phase13-scientific-project"
cp -R "$DRAFT_PROJ" "$PHASE13_SCIENTIFIC_PROJ"
python3 - "$PHASE13_SCIENTIFIC_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
draft_path = proj / "manuscript/manuscript-draft.md"
spec_path = proj / "manuscript/journal-spec.json"
manifest_path = proj / "manuscript/draft-manifest.json"
spec = json.loads(spec_path.read_text())
spec["numeric_reporting_policy"]["allow_scientific_notation"] = True
spec_path.write_text(json.dumps(spec, indent=2, sort_keys=True) + "\n")
text = draft_path.read_text().replace("-0.120 (0.040)", "-1.20e-1 (4.0e-2)", 1)
text = text.replace("| p-value | 0.003 |", "| p-value | 3e-3 |", 1)
text = text.replace("estimate of -0.120, a standard error of 0.040, a p-value of 0.003", "estimate of -1.20e-1, a standard error of 4.0e-2, a p-value of 3e-3", 1)
draft_path.write_text(text)
doc = json.loads(manifest_path.read_text())
doc["numeric_reporting_policy"] = spec["numeric_reporting_policy"]
doc["journal_spec"]["sha256"] = hashlib.sha256(spec_path.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
sync_draft_fixture_hashes "$PHASE13_SCIENTIFIC_PROJ"
# CASE_ID: f20.p13.scientific-policy-positive
expect_pass f20.p13.scientific-policy-positive "$PHASE13_SCIENTIFIC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_SCIENTIFIC_PROJ"

PHASE13_FORBIDDEN_SCIENTIFIC_PROJ="$TMP/phase13-forbidden-scientific-project"
cp -R "$DRAFT_PROJ" "$PHASE13_FORBIDDEN_SCIENTIFIC_PROJ"
python3 - "$PHASE13_FORBIDDEN_SCIENTIFIC_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text().replace("estimate of -0.120", "estimate of -1.20e-1", 1)
path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_FORBIDDEN_SCIENTIFIC_PROJ"
# CASE_ID: f20.p13.reject.scientific-policy-forbidden
expect_reject f20.p13.reject.scientific-policy-forbidden "$PHASE13_FORBIDDEN_SCIENTIFIC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_FORBIDDEN_SCIENTIFIC_PROJ"

PHASE13_ROUNDING_PROJ="$TMP/phase13-rounding-project"
cp -R "$DRAFT_PROJ" "$PHASE13_ROUNDING_PROJ"
python3 - "$PHASE13_ROUNDING_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
draft_path = proj / "manuscript/manuscript-draft.md"
spec_path = proj / "manuscript/journal-spec.json"
manifest_path = proj / "manuscript/draft-manifest.json"
spec = json.loads(spec_path.read_text())
policy = spec["numeric_reporting_policy"]
policy["inferential_digits"] = 2
policy["p_value_rule"] = "Report exact p-values to 2 decimals, but use p < .01 below that floor."
spec_path.write_text(json.dumps(spec, indent=2, sort_keys=True) + "\n")
text = draft_path.read_text()
for old, new in (
    ("-0.120 (0.040)", "-0.12 (0.04)"), ("-0.080 (0.050)", "-0.08 (0.05)"),
    ("-0.090 (0.045)", "-0.09 (0.04)"), ("| p-value | 0.003 | 0.110 | 0.046 |", "| p-value | p < .01 | 0.11 | 0.05 |"),
    ("estimate of -0.120, a standard error of 0.040, a p-value of 0.003", "estimate of -0.12, a standard error of 0.04, p < .01"),
    ("estimate of -0.080, a standard error of 0.050, a p-value of 0.110", "estimate of -0.08, a standard error of 0.05, a p-value of 0.11"),
    ("estimate of -0.090, a standard error of 0.045, a p-value of 0.046", "estimate of -0.09, a standard error of 0.04, a p-value of 0.05"),
):
    assert text.count(old) == 1, old
    text = text.replace(old, new, 1)
draft_path.write_text(text)
doc = json.loads(manifest_path.read_text())
doc["numeric_reporting_policy"] = policy
doc["journal_spec"]["sha256"] = hashlib.sha256(spec_path.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
sync_draft_fixture_hashes "$PHASE13_ROUNDING_PROJ"
# CASE_ID: f20.p13.p-floor-below-half-even-positive
expect_pass f20.p13.p-floor-below-half-even-positive "$PHASE13_ROUNDING_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_ROUNDING_PROJ"

PHASE13_P_FLOOR_EQUAL_PROJ="$TMP/phase13-p-floor-equal-project"
cp -R "$PHASE13_ROUNDING_PROJ" "$PHASE13_P_FLOOR_EQUAL_PROJ"
python3 - "$PHASE13_P_FLOOR_EQUAL_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text().replace("p < .01", "p < .003", 2)
path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_P_FLOOR_EQUAL_PROJ"
# CASE_ID: f20.p13.reject.p-floor-equal
expect_reject f20.p13.reject.p-floor-equal "$PHASE13_P_FLOOR_EQUAL_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_P_FLOOR_EQUAL_PROJ"

PHASE13_P_FLOOR_ABOVE_PROJ="$TMP/phase13-p-floor-above-project"
cp -R "$DRAFT_PROJ" "$PHASE13_P_FLOOR_ABOVE_PROJ"
python3 - "$PHASE13_P_FLOOR_ABOVE_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text().replace("| p-value | 0.003 |", "| p-value | p < .001 |", 1)
text = text.replace("a p-value of 0.003", "p < .001", 1)
path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_P_FLOOR_ABOVE_PROJ"
# CASE_ID: f20.p13.reject.p-floor-above
expect_reject f20.p13.reject.p-floor-above "$PHASE13_P_FLOOR_ABOVE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_P_FLOOR_ABOVE_PROJ"

PHASE13_WRONG_HALF_EVEN_PROJ="$TMP/phase13-wrong-half-even-project"
cp -R "$PHASE13_ROUNDING_PROJ" "$PHASE13_WRONG_HALF_EVEN_PROJ"
python3 - "$PHASE13_WRONG_HALF_EVEN_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text().replace("-0.09 (0.04)", "-0.09 (0.05)", 1)
text = text.replace("standard error of 0.04, a p-value of 0.05", "standard error of 0.05, a p-value of 0.05", 1)
path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_WRONG_HALF_EVEN_PROJ"
# CASE_ID: f20.p13.reject.wrong-half-even-rounding
expect_reject f20.p13.reject.wrong-half-even-rounding "$PHASE13_WRONG_HALF_EVEN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_WRONG_HALF_EVEN_PROJ"

PHASE13_LEADING_ZERO_PROJ="$TMP/phase13-leading-zero-project"
cp -R "$DRAFT_PROJ" "$PHASE13_LEADING_ZERO_PROJ"
python3 - "$PHASE13_LEADING_ZERO_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text().replace("-0.120 (0.040)", "-.120 (.040)", 1)
text = text.replace("estimate of -0.120, a standard error of 0.040, a p-value of 0.003", "estimate of -.120, a standard error of .040, a p-value of .003", 1)
path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_LEADING_ZERO_PROJ"
# CASE_ID: f20.p13.leading-zero-equivalence-positive
expect_pass f20.p13.leading-zero-equivalence-positive "$PHASE13_LEADING_ZERO_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_LEADING_ZERO_PROJ"

PHASE13_INVALID_N_PROJ="$TMP/phase13-invalid-n-project"
cp -R "$DRAFT_PROJ" "$PHASE13_INVALID_N_PROJ"
python3 - "$PHASE13_INVALID_N_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text().replace("| N | 1200 |", "| N | 12,00 |", 1)
text = text.replace("and n = 1200 [@work01]", "and n = 12,00 [@work01]", 1)
path.write_text(text)
PY
sync_draft_fixture_hashes "$PHASE13_INVALID_N_PROJ"
# CASE_ID: f20.p13.reject.invalid-n-grouping
expect_reject f20.p13.reject.invalid-n-grouping "$PHASE13_INVALID_N_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_INVALID_N_PROJ"

PHASE13_FULL_CSV_PROJ="$TMP/phase13-full-regression-csv-project"
cp -R "$DRAFT_PROJ" "$PHASE13_FULL_CSV_PROJ"
python3 - "$PHASE13_FULL_CSV_PROJ" <<'PY'
import copy, hashlib, json, pathlib, sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def manifest_hash(doc):
    payload = dict(doc)
    payload.pop("manifest_sha256", None)
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def replace_exact(value, replacements):
    if isinstance(value, dict):
        return {key: replace_exact(item, replacements) for key, item in value.items()}
    if isinstance(value, list):
        return [replace_exact(item, replacements) for item in value]
    return replacements.get(value, value) if isinstance(value, str) else value

execution_path = proj / "analysis/execution-report.json"
premortem_path = proj / "review/analysis-premortem.json"
post_path = proj / "review/post-execution-review.json"
sanity_path = proj / "verify/runtime-sanity.json"
lock_path = proj / "results-locked/manifest.json"
stage1_path = proj / "verify/stage1-verify.json"
blueprint_path = proj / "manuscript/manuscript-blueprint.json"
plan_path = proj / "manuscript/drafting-plan.json"
draft_path = proj / "manuscript/draft-manifest.json"
manuscript_path = proj / "manuscript/manuscript-draft.md"
old_source = "tables/regression-main.html"
display_source = "tables/model-results.csv"
source_path = proj / display_source
old_display_hash = sha(source_path)
old_execution_hash = sha(execution_path)
old_post_hash = sha(post_path)
old_sanity_hash = sha(sanity_path)
old_lock_file_hash = sha(lock_path)
old_stage1_hash = sha(stage1_path)

source_path.write_text("\n".join([
    "Predictor,Model 1,Model 2,Model 3",
    "Parental job loss,-0.120 (0.040),-0.080 (0.050),-0.090 (0.045)",
    "Child age,0.030 (0.010),0.029 (0.010),0.031 (0.011)",
    "Household income,0.015 (0.006),0.014 (0.006),0.015 (0.006)",
    "Survey wave controls,Yes,Yes,Yes",
    "Household fixed effects,Yes,Yes,Yes",
    "p-value,0.003,0.110,0.046",
    "N,1200,1200,1200",
    "R-squared,0.210,0.205,0.208",
]) + "\n")
display_hash = sha(source_path)

premortem = json.loads(premortem_path.read_text())
for key, relative in {
    "identification_strategy": "design/identification-strategy.json",
    "model_specs": "design/model-specs.json",
    "measurement_plan": "data/measurement-plan.md",
    "variable_dictionary": "data/variable-dictionary.csv",
    "analysis_plan": "analysis/analysis-plan.md",
    "spec_registry": "analysis/spec-registry.csv",
    "scripts_inventory": "analysis/scripts-inventory.json",
    "pre_execution_review": "review/pre-execution-review.json",
    "pre_execution_fix_log": "review/pre-execution-fix-log.json",
    "pre_execution_rereview": "review/pre-execution-rereview.json",
}.items():
    premortem["source_hashes"][key] = sha(proj / relative)
premortem_path.write_text(json.dumps(premortem, indent=2, sort_keys=True) + "\n")

execution = replace_exact(json.loads(execution_path.read_text()), {old_display_hash: display_hash})
execution["run_context"]["working_directory"] = str(proj)
for key, relative in {
    "analysis_plan": "analysis/analysis-plan.md",
    "spec_registry": "analysis/spec-registry.csv",
    "scripts_inventory": "analysis/scripts-inventory.json",
    "analysis_premortem": "review/analysis-premortem.json",
    "analysis_premortem_fix_log": "review/analysis-premortem-fix-log.json",
}.items():
    execution["source_hashes"][key] = sha(proj / relative)
execution_path.write_text(json.dumps(execution, indent=2, sort_keys=True) + "\n")
execution_hash = sha(execution_path)

post = replace_exact(json.loads(post_path.read_text()), {old_execution_hash: execution_hash})
post["source_hashes"]["analysis_premortem"] = sha(premortem_path)
post_path.write_text(json.dumps(post, indent=2, sort_keys=True) + "\n")
post_hash = sha(post_path)

sanity = replace_exact(json.loads(sanity_path.read_text()), {
    old_display_hash: display_hash,
    old_execution_hash: execution_hash,
    old_post_hash: post_hash,
})
sanity_path.write_text(json.dumps(sanity, indent=2, sort_keys=True) + "\n")
sanity_hash = sha(sanity_path)

lock = replace_exact(json.loads(lock_path.read_text()), {
    old_display_hash: display_hash,
    old_execution_hash: execution_hash,
    old_post_hash: post_hash,
    old_sanity_hash: sanity_hash,
})
display_lock = next(item for item in lock["locked_artifacts"] if item.get("source_path") == display_source)
old_lock = next(item for item in lock["locked_artifacts"] if item.get("source_path") == old_source)
display_lock["artifact_role"] = "main_regression_table"
old_lock["artifact_role"] = "diagnostic"
for artifact in (display_source, "analysis/execution-report.json", "review/post-execution-review.json"):
    artifact_lock = next(item for item in lock["locked_artifacts"] if item.get("source_path") == artifact)
    (proj / artifact_lock["locked_path"]).write_bytes((proj / artifact).read_bytes())
lock["manifest_sha256"] = manifest_hash(lock)
lock_path.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")
lock_file_hash = sha(lock_path)

stage1 = replace_exact(json.loads(stage1_path.read_text()), {
    old_display_hash: display_hash,
    old_execution_hash: execution_hash,
    old_post_hash: post_hash,
})
stage1["manifest_sha256"] = lock["manifest_sha256"]
stage1["input_manifest_sha256"] = lock["manifest_sha256"]
stage1_path.write_text(json.dumps(stage1, indent=2, sort_keys=True) + "\n")
stage1_hash = sha(stage1_path)

blueprint = replace_exact(json.loads(blueprint_path.read_text()), {
    old_source: display_source,
    old_lock_file_hash: lock_file_hash,
    old_stage1_hash: stage1_hash,
    old_post_hash: post_hash,
})
blueprint["lock_manifest_sha256"] = lock["manifest_sha256"]
blueprint_path.write_text(json.dumps(blueprint, indent=2, sort_keys=True) + "\n")
blueprint_hash = sha(blueprint_path)

plan = replace_exact(json.loads(plan_path.read_text()), {old_source: display_source})
plan_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
plan_hash = sha(plan_path)

old_locked = old_lock["locked_path"]
display_locked = display_lock["locked_path"]
old_trace = f"<!-- LOCKED_ARTIFACT: {old_source} | LOCKED_PATH: {old_locked} -->"
display_trace = f"<!-- LOCKED_ARTIFACT: {display_source} | LOCKED_PATH: {display_locked} -->"
old_anchor = f"<!-- DISPLAY_TABLE: {old_source} -->"
display_anchor = f"<!-- DISPLAY_TABLE: {display_source} -->"
old_table = "\n".join([
    "| Predictor | Model 1 | Model 2 | Model 3 |",
    "| --- | ---: | ---: | ---: |",
    "| Parental job loss | -0.120 (0.040) | -0.080 (0.050) | -0.090 (0.045) |",
    "| p-value | 0.003 | 0.110 | 0.046 |",
    "| N | 1200 | 1200 | 1200 |",
])
full_table = "\n".join([
    "| Predictor | Model 1 | Model 2 | Model 3 |",
    "| --- | ---: | ---: | ---: |",
    "| Parental job loss | -0.120 (0.040) | -0.080 (0.050) | -0.090 (0.045) |",
    "| Child age | 0.030 (0.010) | 0.029 (0.010) | 0.031 (0.011) |",
    "| Household income | 0.015 (0.006) | 0.014 (0.006) | 0.015 (0.006) |",
    "| Survey wave controls | Yes | Yes | Yes |",
    "| Household fixed effects | Yes | Yes | Yes |",
    "| p-value | 0.003 | 0.110 | 0.046 |",
    "| N | 1200 | 1200 | 1200 |",
    "| R-squared | 0.210 | 0.205 | 0.208 |",
])
text = manuscript_path.read_text()
assert text.count(old_trace) == 1 and text.count(old_anchor) == 1 and text.count(old_table) == 1
manuscript_path.write_text(text.replace(old_trace, display_trace, 1).replace(old_anchor, display_anchor, 1).replace(old_table, full_table, 1))

draft = json.loads(draft_path.read_text())
old_coverage = next(item for item in draft["locked_result_coverage"] if item.get("source_path") == old_source)
display_coverage = next(item for item in draft["locked_result_coverage"] if item.get("source_path") == display_source)
mapped_coverage = copy.deepcopy(old_coverage)
display_coverage.clear()
display_coverage.update(mapped_coverage)
display_coverage.update({"source_path": display_source, "locked_path": display_locked, "manuscript_anchor": display_trace, "display_anchor": display_anchor, "display_type": "regression_table_markdown"})
old_coverage.clear()
old_coverage.update({"source_path": old_source, "locked_path": old_locked, "artifact_role": "diagnostic", "manuscript_anchor": "", "used_in_manuscript": False})
draft["display_evidence"]["displayed_sources"] = [display_source if value == old_source else value for value in draft["display_evidence"]["displayed_sources"]]
claim_group = next(item for item in draft["locked_result_claims"] if item.get("display_source_path") == old_source)
claim_group["display_source_path"] = display_source
claim_group["display_locked_path"] = display_locked
for row in claim_group["rows"]:
    identity = ["locked_result_claim_v2", claim_group["binding_type"], display_source, claim_group["source_path"], row["row_index"], row["spec_id"], row["display_coordinate_kind"], row["display_coordinate"]]
    row["claim_id"] = "lrc2:" + hashlib.sha256(json.dumps(identity, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
draft["lock_manifest_sha256"] = lock["manifest_sha256"]
draft["blueprint"]["sha256"] = blueprint_hash
draft["drafting_plan"]["sha256"] = plan_hash
draft["source_hashes"]["lock_manifest"] = lock_file_hash
draft["source_hashes"]["stage1_verify"] = stage1_hash
draft["source_hashes"]["manuscript_blueprint"] = blueprint_hash
draft["source_hashes"]["post_execution_review"] = post_hash
draft_path.write_text(json.dumps(draft, indent=2, sort_keys=True) + "\n")
PY
sync_draft_fixture_hashes "$PHASE13_FULL_CSV_PROJ"
# CASE_ID: f20.p13.full-regression-csv-positive
expect_pass f20.p13.full-regression-csv-positive "$PHASE13_FULL_CSV_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_FULL_CSV_PROJ"

PHASE13_SIGNED_ZERO_PROJ="$TMP/phase13-signed-zero-project"
cp -R "$DRAFT_PROJ" "$PHASE13_SIGNED_ZERO_PROJ"
python3 - "$PHASE13_SIGNED_ZERO_PROJ" <<'PY'
import csv, hashlib, io, json, pathlib, sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def manifest_hash(doc):
    payload = dict(doc)
    payload.pop("manifest_sha256", None)
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def replace_exact(value, replacements):
    if isinstance(value, dict):
        return {key: replace_exact(item, replacements) for key, item in value.items()}
    if isinstance(value, list):
        return [replace_exact(item, replacements) for item in value]
    return replacements.get(value, value) if isinstance(value, str) else value

def set_s1_signed_zero(path):
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fields = reader.fieldnames
        rows = list(reader)
    assert fields and sum(row.get("spec_id") == "S1" for row in rows) == 1
    next(row for row in rows if row.get("spec_id") == "S1")["std_error"] = "-0.000"
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=fields, lineterminator="\n")
    writer.writeheader(); writer.writerows(rows)
    path.write_text(buffer.getvalue())

execution_path = proj / "analysis/execution-report.json"
post_path = proj / "review/post-execution-review.json"
sanity_path = proj / "verify/runtime-sanity.json"
lock_path = proj / "results-locked/manifest.json"
stage1_path = proj / "verify/stage1-verify.json"
blueprint_path = proj / "manuscript/manuscript-blueprint.json"
draft_path = proj / "manuscript/draft-manifest.json"
manuscript_path = proj / "manuscript/manuscript-draft.md"
old_execution_hash = sha(execution_path)
old_post_hash = sha(post_path)
old_sanity_hash = sha(sanity_path)
old_lock_file_hash = sha(lock_path)
old_stage1_hash = sha(stage1_path)
lock = json.loads(lock_path.read_text())
registry = next(item for item in lock["locked_artifacts"] if item.get("artifact_role") == "results_registry")
source_registry = proj / registry["source_path"]
locked_registry = proj / registry["locked_path"]
old_registry_hash = sha(source_registry)
set_s1_signed_zero(source_registry)
registry_hash = sha(source_registry)

execution = replace_exact(json.loads(execution_path.read_text()), {old_registry_hash: registry_hash})
execution_path.write_text(json.dumps(execution, indent=2, sort_keys=True) + "\n")
execution_hash = sha(execution_path)

post = replace_exact(json.loads(post_path.read_text()), {
    old_registry_hash: registry_hash,
    old_execution_hash: execution_hash,
})
s1_review = next(item for item in post["reviewed_specs"] if item.get("spec_id") == "S1")
s1_review["std_error"] = "-0.000"
post_path.write_text(json.dumps(post, indent=2, sort_keys=True) + "\n")
post_hash = sha(post_path)

sanity = replace_exact(json.loads(sanity_path.read_text()), {
    old_registry_hash: registry_hash,
    old_execution_hash: execution_hash,
    old_post_hash: post_hash,
})
sanity_path.write_text(json.dumps(sanity, indent=2, sort_keys=True) + "\n")
sanity_hash = sha(sanity_path)

lock = replace_exact(lock, {
    old_registry_hash: registry_hash,
    old_execution_hash: execution_hash,
    old_post_hash: post_hash,
    old_sanity_hash: sanity_hash,
})
for artifact in (registry["source_path"], "analysis/execution-report.json", "review/post-execution-review.json"):
    artifact_lock = next(item for item in lock["locked_artifacts"] if item.get("source_path") == artifact)
    (proj / artifact_lock["locked_path"]).write_bytes((proj / artifact).read_bytes())
lock["manifest_sha256"] = manifest_hash(lock)
lock_path.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")
lock_file_hash = sha(lock_path)

stage1 = replace_exact(json.loads(stage1_path.read_text()), {
    old_registry_hash: registry_hash,
    old_execution_hash: execution_hash,
    old_post_hash: post_hash,
})
stage1["manifest_sha256"] = lock["manifest_sha256"]
stage1["input_manifest_sha256"] = lock["manifest_sha256"]
stage1_path.write_text(json.dumps(stage1, indent=2, sort_keys=True) + "\n")
stage1_hash = sha(stage1_path)

blueprint = replace_exact(json.loads(blueprint_path.read_text()), {
    old_registry_hash: registry_hash,
    old_lock_file_hash: lock_file_hash,
    old_stage1_hash: stage1_hash,
    old_post_hash: post_hash,
})
blueprint["lock_manifest_sha256"] = lock["manifest_sha256"]
blueprint_path.write_text(json.dumps(blueprint, indent=2, sort_keys=True) + "\n")
blueprint_hash = sha(blueprint_path)

text = manuscript_path.read_text()
old_prose = "an estimate of -0.120, a standard error of 0.040, a p-value of 0.003"
new_prose = "an estimate of -0.120, a standard error of 0.000, a p-value of 0.003"
assert text.count("-0.120 (0.040)") == 1 and text.count(old_prose) == 1
text = text.replace("-0.120 (0.040)", "-0.120 (0.000)", 1).replace(old_prose, new_prose, 1)
manuscript_path.write_text(text)

draft = json.loads(draft_path.read_text())
coverage = next(item for item in draft["locked_result_coverage"] if item.get("artifact_role") == "main_regression_table")
coverage["claim_source"]["sha256"] = registry_hash
claim_group = next(item for item in draft["locked_result_claims"] if item.get("source_path") == registry["source_path"])
next(row for row in claim_group["rows"] if row.get("spec_id") == "S1")["std_error"] = "-0.000"
draft["lock_manifest_sha256"] = lock["manifest_sha256"]
draft["blueprint"]["sha256"] = blueprint_hash
draft["source_hashes"]["lock_manifest"] = lock_file_hash
draft["source_hashes"]["stage1_verify"] = stage1_hash
draft["source_hashes"]["manuscript_blueprint"] = blueprint_hash
draft["source_hashes"]["post_execution_review"] = post_hash
draft_path.write_text(json.dumps(draft, indent=2, sort_keys=True) + "\n")
PY
sync_draft_fixture_hashes "$PHASE13_SIGNED_ZERO_PROJ"
# CASE_ID: f20.p13.reject.signed-zero-mismatch
expect_reject f20.p13.reject.signed-zero-mismatch "$PHASE13_SIGNED_ZERO_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$PHASE13_SIGNED_ZERO_PROJ"

BAD_DRAFT_HYPOTHESIS_BULLETS_PROJ="$TMP/bad-draft-hypothesis-bullets-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_HYPOTHESIS_BULLETS_PROJ"
python3 - "$BAD_DRAFT_HYPOTHESIS_BULLETS_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = "The preceding arguments predict a testable hypothesis."
replacement = (
    "- **H1.** Parental job loss is associated with lower adolescent educational expectations.\n"
    "- **H2.** The association is weaker in timing-sensitive robustness checks.\n\n"
    + needle
)
if needle not in text:
    raise SystemExit("fixture manuscript missing hypothesis prose needle")
path.write_text(text.replace(needle, replacement, 1))
PY
sync_draft_fixture_hashes "$BAD_DRAFT_HYPOTHESIS_BULLETS_PROJ"
BAD_DRAFT_HYPOTHESIS_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_HYPOTHESIS_BULLETS_PROJ" 2>&1 || true)"
case "$BAD_DRAFT_HYPOTHESIS_OUT" in
  *"hypotheses must be integrated into theory prose"* ) ;;
  *) echo "FAIL: Phase 13 verify should fail proposal-style hypothesis bullet/list blocks" >&2; echo "$BAD_DRAFT_HYPOTHESIS_OUT" >&2; exit 1 ;;
esac

THIN_FULL_ARTICLE_PROJ="$TMP/thin-full-article-project"
cp -R "$DRAFT_PROJ" "$THIN_FULL_ARTICLE_PROJ"
python3 - "$THIN_FULL_ARTICLE_PROJ" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def wc(text):
    return len(re.findall(r"\b[\w'-]+\b", text))

def prose_only_text(text):
    visible = re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)
    visible = re.sub(r"(?is)<table\b.*?</table>", " ", visible)
    visible = re.sub(r"!\[[^\]]*\]\([^)]+\)", " ", visible)
    visible = re.sub(r"\[[^\]]+\]\([^)]+\)", " ", visible)
    kept = []
    for line in visible.splitlines():
        stripped = line.strip()
        if stripped.startswith("|"):
            continue
        if re.match(r"^(?:\*\*)?(?:Table|Figure)\s+\d+[.:]", stripped, flags=re.IGNORECASE):
            continue
        if re.match(r"^Notes?:", stripped, flags=re.IGNORECASE):
            continue
        kept.append(line)
    return "\n".join(kept)

def sections(text, prose=False):
    out = {}
    current = None
    buffer = []
    for line in text.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            if current is not None:
                body = "\n".join(buffer)
                out[current] = wc(prose_only_text(body) if prose else body)
            current = re.sub(r"[^a-z0-9]+", " ", m.group(1).lower()).strip()
            buffer = []
        elif current is not None:
            buffer.append(line)
    if current is not None:
        body = "\n".join(buffer)
        out[current] = wc(prose_only_text(body) if prose else body)
    return out

draft_path = proj / "manuscript/manuscript-draft.md"
spec_path = proj / "manuscript/journal-spec.json"
manifest_path = proj / "manuscript/draft-manifest.json"
polish_path = proj / "manuscript/polish-report.json"
rq_path = proj / "idea/research-question.json"
jf_path = proj / "idea/journal-fit.json"
blueprint_path = proj / "manuscript/manuscript-blueprint.json"

text = draft_path.read_text()
inflated_refs = " ".join(["Inflating reference and table matter must not count as article substance."] * 700)
inflated_table = "\n".join(["| filler | filler |", "| --- | --- |"] + ["| table words should not count | table words should not count |"] * 300)
text = text + "\n\n## References\n\n" + inflated_refs + "\n\n## Tables and Figures\n\n" + inflated_table + "\n"
draft_path.write_text(text)

section_budget = {
    "abstract": {"target_words": 180, "min_words": 80, "max_words": 300},
    "introduction": {"target_words": 1200, "min_words": 800, "max_words": 1600},
    "background": {"target_words": 1800, "min_words": 1200, "max_words": 2400},
    "data and methods": {"target_words": 1200, "min_words": 800, "max_words": 1800},
    "results": {"target_words": 1500, "min_words": 900, "max_words": 2200},
    "discussion": {"target_words": 900, "min_words": 600, "max_words": 1400},
    "conclusion": {"target_words": 220, "min_words": 120, "max_words": 500},
}

rq = json.loads(rq_path.read_text())
jf = json.loads(jf_path.read_text())
blueprint = json.loads(blueprint_path.read_text())
spec = json.loads(spec_path.read_text())
manifest = json.loads(manifest_path.read_text())
polish = json.loads(polish_path.read_text())

rq["paper_type"] = "empirical article"
jf["paper_type"] = "empirical article"
blueprint["paper_type"] = "empirical article"
spec["paper_type"] = "empirical article"
spec["total_word_range"] = {"min": 7000, "max": 9000}
spec["section_word_budget"] = section_budget

rq_path.write_text(json.dumps(rq, indent=2, sort_keys=True) + "\n")
jf_path.write_text(json.dumps(jf, indent=2, sort_keys=True) + "\n")
blueprint["source_hashes"]["research_question"] = sha(rq_path)
blueprint["source_hashes"]["journal_fit"] = sha(jf_path)
blueprint_path.write_text(json.dumps(blueprint, indent=2, sort_keys=True) + "\n")
spec_path.write_text(json.dumps(spec, indent=2, sort_keys=True) + "\n")

polish["source_manuscript_hash"] = sha(draft_path)
polish["polished_manuscript_hash"] = sha(draft_path)
polish_path.write_text(json.dumps(polish, indent=2, sort_keys=True) + "\n")

raw_counts = sections(text, prose=False)
prose_counts = sections(text, prose=True)
main_text_word_count = sum(prose_counts.get(section, 0) for section in section_budget)
manifest["selected_manuscript_hash"] = sha(draft_path)
manifest["blueprint"]["sha256"] = sha(blueprint_path)
manifest["journal_spec"]["sha256"] = sha(spec_path)
manifest["journal_spec"]["paper_type"] = "empirical article"
manifest["polish_report"]["sha256"] = sha(polish_path)
manifest["source_hashes"]["research_question"] = sha(rq_path)
manifest["source_hashes"]["journal_fit"] = sha(jf_path)
manifest["source_hashes"]["manuscript_blueprint"] = sha(blueprint_path)
manifest["section_word_budget"] = section_budget
manifest["section_word_counts"] = raw_counts
manifest["section_prose_word_counts"] = prose_counts
manifest["budget_compliance"]["total_word_count"] = wc(text)
manifest["budget_compliance"]["main_text_word_count"] = main_text_word_count
manifest["budget_compliance"]["total_word_range"] = {"min": 7000, "max": 9000}
manifest["budget_compliance"]["sections"] = {
    section: {"words": raw_counts.get(section, 0), "prose_words": prose_counts.get(section, 0), "min_words": budget["min_words"], "status": "PASS"}
    for section, budget in section_budget.items()
}
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
THIN_FULL_ARTICLE_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$THIN_FULL_ARTICLE_PROJ" 2>&1 || true)"
case "$THIN_FULL_ARTICLE_OUT" in
  *"main-text prose word count"*) ;;
  *) echo "FAIL: Phase 13 verify should fail thin full articles by main-text prose count even when references/tables inflate total words" >&2; echo "$THIN_FULL_ARTICLE_OUT" >&2; exit 1 ;;
esac

CUSTOM_DRAFT_PROJ="$TMP/custom-draft-project"
cp -R "$DRAFT_PROJ" "$CUSTOM_DRAFT_PROJ"
python3 - "$CUSTOM_DRAFT_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

requested = "Annual Review of Digital Sociology"
resolution = {
    "requested_journal": requested,
    "resolved_profile_name": requested,
    "profile_origin": "imported_custom",
    "profile_source_engine": "scholar-journal",
    "source_strategy": "web_fetched_profile",
    "web_lookup_attempted": True,
    "fallback_used": False,
    "fallback_reason": "",
    "journal_structure": {
        "profile_source": "scholar-journal:imported-custom",
        "section_sequence": ["Abstract", "Introduction", "Background", "Data and Methods", "Results", "Discussion", "Conclusion", "References", "Tables", "Figures"],
        "results_before_methods": False,
        "theory_presentation": "background_section",
        "methods_section_label": "Data and Methods",
        "discussion_conclusion_policy": "split_required",
        "supplement_policy": "journal_optional_appendix"
    },
    "display_architecture": {
        "table_placement_policy": "end_matter_after_references",
        "figure_placement_policy": "separate_files_after_tables",
        "descriptive_table_requirement": "journal_optional",
        "editable_text_tables": True,
        "image_tables_forbidden": True,
        "main_text_display_cap": None,
        "main_text_table_cap": None,
        "main_text_figure_cap": None,
        "supplement_label_prefix": "Appendix",
        "panel_label_style": "A_B_C",
        "table_rendering_mode": "editable_text_end_matter",
        "figure_rendering_mode": "separate_figure_files",
        "table_title_position": "above_table",
        "table_notes_policy": "below_table_notes",
        "display_callout_style": "numbered_tables_and_figures"
    }
}

rq_path = proj / "idea/research-question.json"
jf_path = proj / "idea/journal-fit.json"
blueprint_path = proj / "manuscript/manuscript-blueprint.json"
spec_path = proj / "manuscript/journal-spec.json"
manifest_path = proj / "manuscript/draft-manifest.json"

rq = json.loads(rq_path.read_text())
jf = json.loads(jf_path.read_text())
blueprint = json.loads(blueprint_path.read_text())
spec = json.loads(spec_path.read_text())
manifest = json.loads(manifest_path.read_text())

rq["target_journal"]["primary"] = requested
rq["target_journal"]["journal_family"] = "digital sociology"
jf["primary_target"] = requested
jf["journal_family"] = "digital sociology"
jf["target_source"] = "user_provided"
jf["journal_profile_resolution"] = resolution
for item in jf["candidates"]:
    item["primary_target"] = requested
rq_path.write_text(json.dumps(rq, indent=2, sort_keys=True) + "\n")
jf_path.write_text(json.dumps(jf, indent=2, sort_keys=True) + "\n")

blueprint["target_journal"] = requested
blueprint["journal_profile_resolution"] = resolution
blueprint["journal_structure"] = resolution["journal_structure"]
blueprint["display_architecture"] = resolution["display_architecture"]
blueprint["source_hashes"]["research_question"] = sha(rq_path)
blueprint["source_hashes"]["journal_fit"] = sha(jf_path)
blueprint_path.write_text(json.dumps(blueprint, indent=2, sort_keys=True) + "\n")

spec["target_journal"] = requested
spec["journal_family"] = "digital sociology"
spec["journal_profile_resolution"] = resolution
spec["journal_structure"] = resolution["journal_structure"]
spec["display_architecture"] = resolution["display_architecture"]
spec_path.write_text(json.dumps(spec, indent=2, sort_keys=True) + "\n")

manifest["blueprint"]["sha256"] = sha(blueprint_path)
manifest["journal_spec"]["sha256"] = sha(spec_path)
manifest["source_hashes"]["research_question"] = sha(rq_path)
manifest["source_hashes"]["journal_fit"] = sha(jf_path)
manifest["source_hashes"]["manuscript_blueprint"] = sha(blueprint_path)
manifest["budget_compliance"]["target_journal"] = requested
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
bash "$SCRIPT_DIR/auto-research-verify.sh" 12 "$CUSTOM_DRAFT_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$CUSTOM_DRAFT_PROJ" >/dev/null

BAD_BLUEPRINT_SCHEMA_PROJ="$TMP/bad-blueprint-schema-project"
cp -R "$DRAFT_PROJ" "$BAD_BLUEPRINT_SCHEMA_PROJ"
python3 - "$BAD_BLUEPRINT_SCHEMA_PROJ/manuscript/manuscript-blueprint.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc.pop("verdict", None)
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.12.negative
expect_reject phase.12.negative "$BAD_BLUEPRINT_SCHEMA_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 12 "$BAD_BLUEPRINT_SCHEMA_PROJ"

BAD_DRAFT_DEGRADED_PROJ="$TMP/bad-draft-degraded-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_DEGRADED_PROJ"
python3 - "$BAD_DRAFT_DEGRADED_PROJ/manuscript/draft-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["degraded"] = True
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.13.negative
expect_reject phase.13.negative "$BAD_DRAFT_DEGRADED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_DEGRADED_PROJ"

BAD_BLUEPRINT_JOURNAL_PROJ="$TMP/bad-blueprint-journal-project"
cp -R "$DRAFT_PROJ" "$BAD_BLUEPRINT_JOURNAL_PROJ"
python3 - "$BAD_BLUEPRINT_JOURNAL_PROJ/manuscript/manuscript-blueprint.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["journal_structure"]["discussion_conclusion_policy"] = "combined_only"
doc["discussion_mode"] = "combined"
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p12.reject.journal-structure
expect_reject l2.p12.reject.journal-structure "$BAD_BLUEPRINT_JOURNAL_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 12 "$BAD_BLUEPRINT_JOURNAL_PROJ"

BAD_DRAFT_QUALITY_PROJ="$TMP/bad-draft-quality-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_QUALITY_PROJ"
python3 - "$BAD_DRAFT_QUALITY_PROJ/manuscript/draft-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["draft_quality_gate"]["status"] = "FAIL"
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p13.reject.draft-quality
expect_reject l2.p13.reject.draft-quality "$BAD_DRAFT_QUALITY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_QUALITY_PROJ"

BAD_DRAFT_REPETITION_PROJ="$TMP/bad-draft-repetition-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_REPETITION_PROJ"
python3 - "$BAD_DRAFT_REPETITION_PROJ" <<'PY'
import hashlib
import json
import pathlib
import re
import sys
proj = pathlib.Path(sys.argv[1])
draft_path = proj / "manuscript/manuscript-draft.md"
manifest_path = proj / "manuscript/draft-manifest.json"
polish_path = proj / "manuscript/polish-report.json"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def wc(text):
    return len(re.findall(r"\b[\w'-]+\b", text))

def section_counts(text):
    sections = {}
    current = None
    buffer = []
    for line in text.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            if current is not None:
                sections[current] = "\n".join(buffer)
            current = re.sub(r"[^a-z0-9]+", " ", m.group(1).lower()).strip()
            buffer = []
        elif current is not None:
            buffer.append(line)
    if current is not None:
        sections[current] = "\n".join(buffer)
    return {k: wc(v) for k, v in sections.items()}

def prose_only_text(text):
    visible = re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)
    visible = re.sub(r"(?is)<table\b.*?</table>", " ", visible)
    visible = re.sub(r"!\[[^\]]*\]\([^)]+\)", " ", visible)
    visible = re.sub(r"\[[^\]]+\]\([^)]+\)", " ", visible)
    kept = []
    for line in visible.splitlines():
        stripped = line.strip()
        if stripped.startswith("|"):
            continue
        if re.match(r"^(?:\*\*)?(?:Table|Figure)\s+\d+[.:]", stripped, flags=re.IGNORECASE):
            continue
        if re.match(r"^Notes?:", stripped, flags=re.IGNORECASE):
            continue
        kept.append(line)
    return "\n".join(kept)

def section_prose_counts(text):
    sections = {}
    current = None
    buffer = []
    for line in text.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            if current is not None:
                sections[current] = "\n".join(buffer)
            current = re.sub(r"[^a-z0-9]+", " ", m.group(1).lower()).strip()
            buffer = []
        elif current is not None:
            buffer.append(line)
    if current is not None:
        sections[current] = "\n".join(buffer)
    return {k: wc(prose_only_text(v)) for k, v in sections.items()}

def max_repeat(text):
    counts = {}
    for sentence in re.split(r"(?<=[.!?])\s+", re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)):
        normalized = re.sub(r"[^a-z0-9]+", " ", sentence.lower()).strip()
        if wc(normalized) >= 8:
            counts[normalized] = counts.get(normalized, 0) + 1
    return max(counts.values(), default=0)

text = draft_path.read_text()
repeat = "This repeated quality-control sentence should not appear three times in a serious manuscript."
text = text + "\n" + " ".join([repeat, repeat, repeat]) + "\n"
draft_path.write_text(text)
manifest = json.loads(manifest_path.read_text())
polish = json.loads(polish_path.read_text())
polish["source_manuscript_hash"] = sha(draft_path)
polish["polished_manuscript_hash"] = sha(draft_path)
polish_path.write_text(json.dumps(polish, indent=2, sort_keys=True) + "\n")
manifest["selected_manuscript_hash"] = sha(draft_path)
manifest["polish_report"]["sha256"] = sha(polish_path)
manifest["section_word_counts"] = section_counts(text)
manifest["section_prose_word_counts"] = section_prose_counts(text)
manifest["budget_compliance"]["total_word_count"] = wc(text)
manifest["budget_compliance"]["main_text_word_count"] = sum(
    manifest["section_prose_word_counts"].get(section, 0)
    for section in ("abstract", "introduction", "background", "data and methods", "results", "discussion", "conclusion")
)
for section, count in manifest["section_word_counts"].items():
    if section in manifest["budget_compliance"]["sections"]:
        manifest["budget_compliance"]["sections"][section]["words"] = count
manifest["draft_quality_gate"]["max_repeated_sentence_count"] = max_repeat(text)
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
sync_draft_fixture_hashes "$BAD_DRAFT_REPETITION_PROJ"
# CASE_ID: l2.p13.reject.repetition
expect_reject l2.p13.reject.repetition "$BAD_DRAFT_REPETITION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_REPETITION_PROJ"

BAD_DRAFT_ANCHOR_PROJ="$TMP/bad-draft-anchor-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_ANCHOR_PROJ"
python3 - "$BAD_DRAFT_ANCHOR_PROJ/manuscript/manuscript-draft.md" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines()
for idx, line in enumerate(lines):
    if "LOCKED_ARTIFACT:" in line:
        del lines[idx]
        break
path.write_text("\n".join(lines) + "\n")
PY
sync_draft_fixture_hashes "$BAD_DRAFT_ANCHOR_PROJ"
# CASE_ID: l2.p13.reject.locked-anchor
expect_reject l2.p13.reject.locked-anchor "$BAD_DRAFT_ANCHOR_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_ANCHOR_PROJ"

BAD_DRAFT_BIB_PROJ="$TMP/bad-draft-bib-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_BIB_PROJ"
printf '\nUnresolved citation [@missingkey].\n' >> "$BAD_DRAFT_BIB_PROJ/manuscript/manuscript-draft.md"
sync_draft_fixture_hashes "$BAD_DRAFT_BIB_PROJ"
# CASE_ID: l2.p13.reject.missing-bib-key
expect_reject l2.p13.reject.missing-bib-key "$BAD_DRAFT_BIB_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_BIB_PROJ"

BAD_DRAFT_PLACEHOLDER_PROJ="$TMP/bad-draft-placeholder-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_PLACEHOLDER_PROJ"
printf '\nTBD\n' >> "$BAD_DRAFT_PLACEHOLDER_PROJ/manuscript/manuscript-draft.md"
sync_draft_fixture_hashes "$BAD_DRAFT_PLACEHOLDER_PROJ"
# CASE_ID: l2.p13.reject.placeholder
expect_reject l2.p13.reject.placeholder "$BAD_DRAFT_PLACEHOLDER_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_PLACEHOLDER_PROJ"

BAD_DRAFT_CALLOUT_PROJ="$TMP/bad-draft-callout-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_CALLOUT_PROJ"
python3 - "$BAD_DRAFT_CALLOUT_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
draft = proj / "manuscript/manuscript-draft.md"
text = draft.read_text()
start = text.index("## Results")
end = text.index("## Discussion")
text = text[:start] + text[start:end].replace("Table 1", "The regression table") + text[end:]
draft.write_text(text)
manifest_path = proj / "manuscript/draft-manifest.json"
manifest = json.loads(manifest_path.read_text())
manifest["selected_manuscript_hash"] = hashlib.sha256(draft.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
sync_draft_fixture_hashes "$BAD_DRAFT_CALLOUT_PROJ"
# CASE_ID: l2.p13.reject.table-callout
expect_reject l2.p13.reject.table-callout "$BAD_DRAFT_CALLOUT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_CALLOUT_PROJ"

BAD_DRAFT_PRECISION_PROJ="$TMP/bad-draft-precision-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_PRECISION_PROJ"
python3 - "$BAD_DRAFT_PRECISION_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
draft = proj / "manuscript/manuscript-draft.md"
text = draft.read_text().replace("with an estimate of -0.120, a standard error of 0.040, a p-value of 0.003, and n = 1200", "with an estimate of -1.0380185168761126e-8, a standard error of 0.062553350877615, a p-value of 0.9999998675979884, and n = 1200", 1)
draft.write_text(text)
manifest_path = proj / "manuscript/draft-manifest.json"
manifest = json.loads(manifest_path.read_text())
manifest["selected_manuscript_hash"] = hashlib.sha256(draft.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
sync_draft_fixture_hashes "$BAD_DRAFT_PRECISION_PROJ"
# CASE_ID: l2.p13.reject.numeric-policy
expect_reject l2.p13.reject.numeric-policy "$BAD_DRAFT_PRECISION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_PRECISION_PROJ"

BAD_DRAFT_POLISH_PROJ="$TMP/bad-draft-polish-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_POLISH_PROJ"
python3 - "$BAD_DRAFT_POLISH_PROJ/manuscript/polish-report.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["generic_markers_remaining"]["high"] = 1
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
python3 - "$BAD_DRAFT_POLISH_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
manifest_path = proj / "manuscript/draft-manifest.json"
polish_path = proj / "manuscript/polish-report.json"
manifest = json.loads(manifest_path.read_text())
manifest["polish_report"]["sha256"] = hashlib.sha256(polish_path.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p13.reject.polish-marker
expect_reject l2.p13.reject.polish-marker "$BAD_DRAFT_POLISH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_POLISH_PROJ"

BAD_DRAFT_BUDGET_PROJ="$TMP/bad-draft-budget-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_BUDGET_PROJ"
python3 - "$BAD_DRAFT_BUDGET_PROJ" <<'PY'
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
spec_path = proj / "manuscript/journal-spec.json"
manifest_path = proj / "manuscript/draft-manifest.json"
spec = json.loads(spec_path.read_text())
manifest = json.loads(manifest_path.read_text())
spec["section_word_budget"]["introduction"]["min_words"] = 5000
spec_path.write_text(json.dumps(spec, indent=2, sort_keys=True) + "\n")
manifest["section_word_budget"] = spec["section_word_budget"]
manifest["journal_spec"]["sha256"] = __import__("hashlib").sha256(spec_path.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p13.reject.section-budget
expect_reject l2.p13.reject.section-budget "$BAD_DRAFT_BUDGET_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_BUDGET_PROJ"

BAD_DRAFT_NUMERIC_PROJ="$TMP/bad-draft-numeric-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_NUMERIC_PROJ"
python3 - "$BAD_DRAFT_NUMERIC_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
draft = proj / "manuscript/manuscript-draft.md"
text = draft.read_text().replace("estimate of -0.120", "estimate of 0.120")
draft.write_text(text)
manifest_path = proj / "manuscript/draft-manifest.json"
manifest = json.loads(manifest_path.read_text())
manifest["selected_manuscript_hash"] = hashlib.sha256(draft.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
sync_draft_fixture_hashes "$BAD_DRAFT_NUMERIC_PROJ"
# CASE_ID: l2.p13.reject.fully-rebound-numeric
expect_reject l2.p13.reject.fully-rebound-numeric "$BAD_DRAFT_NUMERIC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_NUMERIC_PROJ"

BAD_DRAFT_CLAIM_PROJ="$TMP/bad-draft-claim-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_CLAIM_PROJ"
python3 - "$BAD_DRAFT_CLAIM_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
draft = proj / "manuscript/manuscript-draft.md"
text = draft.read_text().replace("is associated with", "causes", 1)
draft.write_text(text)
manifest_path = proj / "manuscript/draft-manifest.json"
manifest = json.loads(manifest_path.read_text())
manifest["selected_manuscript_hash"] = hashlib.sha256(draft.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
sync_draft_fixture_hashes "$BAD_DRAFT_CLAIM_PROJ"
# CASE_ID: l2.p13.reject.fully-rebound-overclaim
expect_reject l2.p13.reject.fully-rebound-overclaim "$BAD_DRAFT_CLAIM_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_CLAIM_PROJ"

BAD_DRAFT_ENGINE_PROJ="$TMP/bad-draft-engine-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_ENGINE_PROJ"
python3 - "$BAD_DRAFT_ENGINE_PROJ/manuscript/draft-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["drafting_engine"]["skill"] = "generic-llm"
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p13.reject.drafting-engine
expect_reject l2.p13.reject.drafting-engine "$BAD_DRAFT_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_ENGINE_PROJ"

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "13" ]]; then
  harness_validate_results --phase-through 13 >/dev/null
  progress "phases 0 to 13 authoritative harness assertions passed"
  exit 0
fi

VERIFY_MANUSCRIPT_PROJ="$TMP/verify-manuscript-project"
cp -R "$DRAFT_PROJ" "$VERIFY_MANUSCRIPT_PROJ"
mkdir -p "$VERIFY_MANUSCRIPT_PROJ/verify/agents"
python3 - "$VERIFY_MANUSCRIPT_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

lock = json.loads((proj / "results-locked/manifest.json").read_text())
draft = json.loads((proj / "manuscript/draft-manifest.json").read_text())
blueprint_path = proj / "manuscript/manuscript-blueprint.json"
roles = ["verify-numerics", "verify-figures", "verify-logic", "verify-completeness"]
role_scopes = {
    "verify-numerics": ["stage_1_numeric_values", "stage_2_numeric_claims"],
    "verify-figures": ["stage_1_visual_inspection", "caption_claims"],
    "verify-logic": ["stage_2_claim_scope", "phase9_constraints"],
    "verify-completeness": ["coverage", "live_read_audit"]
}
agents = []
for idx, role in enumerate(roles, 1):
    path = pathlib.Path("verify/agents") / f"{role}.md"
    report_text = (
        f"SCANNED: {role}\n"
        f"{role} independently reviewed the active results lock, the manuscript draft, "
        "the Phase 12 draft manifest, and the relevant verification inputs. The review "
        "found complete agreement for its assigned surface and no critical unresolved issues. "
    ) * 2
    (proj / path).write_text(report_text)
    agents.append({
        "role": role,
        "agent_id": f"agent-{idx}",
        "agent_type": "independent_scholar_verify_agent",
        "task_invocation_id": f"phase14-{role}-{idx}",
        "input_hashes": {
            "manuscript": sha(proj / "manuscript/manuscript-draft.md"),
            "draft_manifest": sha(proj / "manuscript/draft-manifest.json"),
            "lock_manifest": sha(proj / "results-locked/manifest.json")
        },
        "independent": True,
        "verification_scope": role_scopes[role],
        "report_path": str(path),
        "verdict": "PASS"
    })
coverage = draft["locked_result_coverage"]
reader_roles = {"result_table", "model_output", "main_regression_table", "sensitivity_regression_table", "regression_table", "figure_file"}
stage1_checked = []
for item in coverage:
    if item["used_in_manuscript"] is not True or item["artifact_role"] not in reader_roles:
        continue
    check = {
        "source_artifact": item["source_path"],
        "locked_path": item["locked_path"],
        "artifact_role": item["artifact_role"],
        "manuscript_location": "Results",
        "manuscript_anchor": item["manuscript_anchor"],
        "check_type": "locked_output_to_manuscript",
        "verdict": "PASS"
    }
    if item["artifact_role"] == "figure_file":
        check["visual_inspection"] = {
            "rendered": True,
            "caption_matches": True,
            "read_confirmed": f"READ-CONFIRMED: {item['locked_path']}",
            "figure_sha256": sha(proj / item["locked_path"]),
            "rendered_dimensions": "800x600",
            "caption_claims_checked": ["event-study diagnostic figure"]
        }
    stage1_checked.append(check)
stage2_checked = []
for source_claim in draft["locked_result_claims"]:
    for row in source_claim["rows"]:
        stage2_checked.append({
            "binding_type": source_claim["binding_type"],
            "display_source_path": source_claim["display_source_path"],
            "display_locked_path": source_claim["display_locked_path"],
            "source_artifact": source_claim["source_path"],
            "locked_path": source_claim["locked_path"],
            "claim_id": row["claim_id"],
            "row_index": row["row_index"],
            "spec_id": row["spec_id"],
            "display_coordinate_kind": row["display_coordinate_kind"],
            "display_coordinate": row["display_coordinate"],
            "estimate": row["estimate"],
            "std_error": row["std_error"],
            "p_value": row["p_value"],
            "n": row["n"],
            "manuscript_location": "Results",
            "manuscript_anchor": row["manuscript_anchor"],
            "referenced_artifact": source_claim["source_path"],
            "check_type": "prose_claim_match",
            "direction_verdict": "PASS",
            "uncertainty_verdict": "PASS",
            "causal_language_verdict": "PASS",
            "phase9_constraint_verdict": "PASS",
            "verdict": "PASS"
        })
input_artifacts_read = []
for item in coverage:
    if item["used_in_manuscript"] is True and item["artifact_role"] in reader_roles:
        input_artifacts_read.append({
            "path": item["locked_path"],
            "source_artifact": item["source_path"],
            "sha256": sha(proj / item["locked_path"])
        })
report = {
    "verdict": "PASS",
    "degraded": False,
    "verification_engine": {
        "skill": "scholar-verify",
        "mode": "full",
        "stage_1": True,
        "stage_2": True,
        "lock_enforced": True,
        "live_output_reads_forbidden": True,
        "agent_count": 4,
        "task_invocation_id": "phase14-verify-001",
        "invoked_at_utc": "2026-04-30T11:00:00Z",
        "input_artifacts": [
            "manuscript/manuscript-draft.md",
            "manuscript/draft-manifest.json",
            "results-locked/manifest.json"
        ],
        "output_artifacts": [
            "verify/manuscript-verification.json",
            "verify/manuscript-verification.md"
        ]
    },
    "lock_id": lock["lock_id"],
    "lock_manifest_sha256": lock["manifest_sha256"],
    "source_hashes": {
        "manuscript": sha(proj / "manuscript/manuscript-draft.md"),
        "draft_manifest": sha(proj / "manuscript/draft-manifest.json"),
        "lock_manifest": sha(proj / "results-locked/manifest.json")
    },
    "blueprint_hashes": {
        "manuscript_blueprint": sha(blueprint_path)
    },
    "scanned": len(stage1_checked) + len(stage2_checked),
    "critical_count": 0,
    "selected_manuscript_hash": sha(proj / "manuscript/manuscript-draft.md"),
    "agent_reports": [agent["report_path"] for agent in agents],
    "agents": agents,
    "input_artifacts_read": input_artifacts_read,
    "lock_coverage": {
        "lock_id": lock["lock_id"],
        "all_locked_artifacts_accounted": True,
        "live_output_reads_detected": False,
        "covered_sources": [item["source_path"] for item in coverage]
    },
    "stage_1_outputs_to_manuscript": {
        "verdict": "PASS",
        "degraded": False,
        "items_scanned": len(stage1_checked),
        "critical_count": 0,
        "checked": stage1_checked
    },
    "stage_2_manuscript_to_prose": {
        "verdict": "PASS",
        "degraded": False,
        "claims_scanned": len(stage2_checked),
        "critical_count": 0,
        "checked": stage2_checked
    },
    "findings": [],
    "fix_checklist": {
        "critical_fixes": [],
        "route_back": []
    },
    "blueprint_to_manuscript": {
        "status": "PASS",
        "headline_claim_aligned": True,
        "contribution_stack_aligned": True,
        "section_obligations_aligned": True,
        "headline_results_preserved": True,
        "forbidden_moves_absent": True
    },
    "route_back_phase": None,
    "ready_for_phase_15": True
}
(proj / "verify/manuscript-verification.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
summary = (
    "The manuscript verification panel completed the full scholar-verify workflow against the active locked snapshot. "
    "Stage 1 reviewed every reader-facing locked output against the manuscript anchors, including numeric table material and rendered figure evidence. "
    "Stage 2 reviewed every row-level locked result claim against the Results prose, direction language, uncertainty language, and the Phase 9 interpretation constraints. "
    "The completeness agent reconciled all locked sources listed in the Phase 12 draft manifest with the active lock manifest and found no live output reads. "
    "The consolidated report is ready for citation and claim support because all stages passed without critical findings. "
)
(proj / "verify/manuscript-verification.md").write_text(summary * 2)
PY
set +e
bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$VERIFY_MANUSCRIPT_PROJ" >"$TMP/phase14-no-evidence.out" 2>&1
NO_EVIDENCE_RC=$?
set -e
[ "$NO_EVIDENCE_RC" -ne 0 ] || fail "Phase 14 accepted review metadata without process-recorded evidence"
grep -F "missing registered review session" "$TMP/phase14-no-evidence.out" >/dev/null \
  || fail "Phase 14 no-evidence rejection emitted the wrong diagnostic"

BAD_VERIFY_SCHEMA_PROJ="$TMP/bad-verify-schema-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_SCHEMA_PROJ"
python3 - "$BAD_VERIFY_SCHEMA_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report.pop("blueprint_hashes", None)
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$BAD_VERIFY_SCHEMA_PROJ" 14 verification_panel >/dev/null
# CASE_ID: phase.14.negative
expect_reject phase.14.negative "$BAD_VERIFY_SCHEMA_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_SCHEMA_PROJ"

python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$VERIFY_MANUSCRIPT_PROJ" 14 verification_panel >/dev/null
# CASE_ID: phase.14.positive
expect_pass phase.14.positive "$VERIFY_MANUSCRIPT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$VERIFY_MANUSCRIPT_PROJ"
# CASE_ID: l2.p14.stage2-v2-positive
expect_pass l2.p14.stage2-v2-positive "$VERIFY_MANUSCRIPT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$VERIFY_MANUSCRIPT_PROJ"

VERIFY_STAGE2_REORDERED_PROJ="$TMP/verify-stage2-reordered-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$VERIFY_STAGE2_REORDERED_PROJ"
python3 - "$VERIFY_STAGE2_REORDERED_PROJ/verify/manuscript-verification.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_2_manuscript_to_prose"]["checked"].reverse()
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p14.stage2-reordered-positive
expect_pass f20.p14.stage2-reordered-positive "$VERIFY_STAGE2_REORDERED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$VERIFY_STAGE2_REORDERED_PROJ"

VERIFY_STAGE2_DUPLICATE_PROJ="$TMP/verify-stage2-duplicate-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$VERIFY_STAGE2_DUPLICATE_PROJ"
python3 - "$VERIFY_STAGE2_DUPLICATE_PROJ/verify/manuscript-verification.json" <<'PY'
import copy, json, pathlib, sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
checked = report["stage_2_manuscript_to_prose"]["checked"]
checked.append(copy.deepcopy(checked[0]))
report["stage_2_manuscript_to_prose"]["claims_scanned"] = len(checked)
report["scanned"] = report["stage_1_outputs_to_manuscript"]["items_scanned"] + len(checked)
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p14.reject.stage2-duplicate
expect_reject f20.p14.reject.stage2-duplicate "$VERIFY_STAGE2_DUPLICATE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$VERIFY_STAGE2_DUPLICATE_PROJ"

VERIFY_STAGE2_PAYLOAD_PROJ="$TMP/verify-stage2-payload-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$VERIFY_STAGE2_PAYLOAD_PROJ"
python3 - "$VERIFY_STAGE2_PAYLOAD_PROJ/verify/manuscript-verification.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_2_manuscript_to_prose"]["checked"][0]["estimate"] = "999.000"
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p14.reject.stage2-payload
expect_reject f20.p14.reject.stage2-payload "$VERIFY_STAGE2_PAYLOAD_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$VERIFY_STAGE2_PAYLOAD_PROJ"

FAIL_VERIFY_PROJ="$TMP/fail-verify-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$FAIL_VERIFY_PROJ"
python3 - "$FAIL_VERIFY_PROJ/verify/manuscript-verification.json" "$FAIL_VERIFY_PROJ/verify/manuscript-verification.md" <<'PY'
import json
import pathlib
import sys
json_path = pathlib.Path(sys.argv[1])
md_path = pathlib.Path(sys.argv[2])
report = json.loads(json_path.read_text())
report["verdict"] = "FAIL"
report["critical_count"] = 1
report["ready_for_phase_15"] = False
report["route_back_phase"] = "13"
report["findings"] = [
    {
        "finding_id": "P14-F001",
        "severity": "CRITICAL",
        "category": "draft_prose",
        "owner_phase": "13",
        "route_back_phase": "13",
        "detected_by": "verify-logic",
        "affected_artifacts": ["manuscript/manuscript-draft.md:Results"],
        "required_fix": "Revise the Results prose so the row-level claim matches the locked result and rerun Phase 13.",
        "status": "open"
    }
]
report["fix_checklist"] = {
    "critical_fixes": ["Revise the Results prose in Phase 13."],
    "route_back": ["13"]
}
json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
md_path.write_text("Phase 14 verification failed with a structured route back to Phase 13. The verification panel found a critical draft prose issue that must be repaired before citation and claim support can start. " * 2)
PY
FAIL_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$FAIL_VERIFY_PROJ" 2>&1 || true)"
case "$FAIL_OUT" in
  *"route_back_phase=13"* ) ;;
  *) echo "FAIL: Phase 14 structured FAIL report should expose route_back_phase=13, got $FAIL_OUT" >&2; exit 1 ;;
esac

BAD_VERIFY_FAIL_SCHEMA_PROJ="$TMP/bad-verify-fail-schema-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_FAIL_SCHEMA_PROJ"
python3 - "$BAD_VERIFY_FAIL_SCHEMA_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["verdict"] = "FAIL"
report["critical_count"] = 1
report["ready_for_phase_15"] = False
report["findings"] = []
report["route_back_phase"] = ""
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
BAD_FAIL_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_FAIL_SCHEMA_PROJ" 2>&1 || true)"
case "$BAD_FAIL_OUT" in
  *"FAIL report must include nonempty findings"* ) ;;
  *) echo "FAIL: Phase 13 malformed FAIL report should be rejected for missing findings, got $BAD_FAIL_OUT" >&2; exit 1 ;;
esac

ROUTE_STATE_PROJ="$TMP/route-state-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_PROJ/artifacts" "$ROUTE_STATE_PROJ/verify"
for pid in $(seq 0 14); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_PROJ/artifacts/phase-$pid.txt"
  complete_sm "$ROUTE_STATE_PROJ" "$pid" "$ROUTE_STATE_PROJ/artifacts/phase-$pid.txt"
done
cp "$FAIL_VERIFY_PROJ/verify/manuscript-verification.json" "$ROUTE_STATE_PROJ/verify/manuscript-verification.json"
ROUTE_OUT="$(bash "$SCRIPT_DIR/auto-research-state.sh" route-back "$ROUTE_STATE_PROJ" "$ROUTE_STATE_PROJ/verify/manuscript-verification.json")"
case "$ROUTE_OUT" in
  *"ROUTE_BACK_PHASE=13"*"INVALIDATED_PHASES=13,14"* ) ;;
  *) echo "FAIL: route-back should invalidate phases 13 and 14, got $ROUTE_OUT" >&2; exit 1 ;;
esac
ROUTE_NEXT="$(bash "$SCRIPT_DIR/auto-research-state.sh" next "$ROUTE_STATE_PROJ")"
case "$ROUTE_NEXT" in
  *"NEXT_PHASE=13"*"REASON=route_back"*"FINDING_IDS=P14-F001"* ) ;;
  *) echo "FAIL: next should route back to Phase 13 with finding ID, got $ROUTE_NEXT" >&2; exit 1 ;;
esac
ROUTE_RETRY="$(bash "$SCRIPT_DIR/auto-research-state.sh" route-back "$ROUTE_STATE_PROJ" "$ROUTE_STATE_PROJ/verify/manuscript-verification.json")"
case "$ROUTE_RETRY" in
  *"RETRY_MAX=2"* ) ;;
  *) echo "FAIL: repeated route-back should increment retry count, got $ROUTE_RETRY" >&2; exit 1 ;;
esac
complete_sm "$ROUTE_STATE_PROJ" 13 "$ROUTE_STATE_PROJ/artifacts/phase-13.txt"
ROUTE_NEXT_14="$(bash "$SCRIPT_DIR/auto-research-state.sh" next "$ROUTE_STATE_PROJ")"
case "$ROUTE_NEXT_14" in
  *"NEXT_PHASE=14"*"REASON=stale"* ) ;;
  *) echo "FAIL: after completing route target, downstream Phase 14 should remain stale, got $ROUTE_NEXT_14" >&2; exit 1 ;;
esac
complete_sm "$ROUTE_STATE_PROJ" 14 "$ROUTE_STATE_PROJ/artifacts/phase-14.txt"
ROUTE_NEXT_CLEAR="$(bash "$SCRIPT_DIR/auto-research-state.sh" next "$ROUTE_STATE_PROJ")"
case "$ROUTE_NEXT_CLEAR" in
  *"NEXT_PHASE=15"* ) ;;
  *) echo "FAIL: after rerunning invalidated phases, next should advance to 15, got $ROUTE_NEXT_CLEAR" >&2; exit 1 ;;
esac

BAD_VERIFY_ROLE_PROJ="$TMP/bad-verify-role-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_ROLE_PROJ"
python3 - "$BAD_VERIFY_ROLE_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["agents"] = [agent for agent in report["agents"] if agent["role"] != "verify-completeness"]
report["agent_reports"] = [agent["report_path"] for agent in report["agents"]]
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p14.reject.review-role-binding
expect_reject l2.p14.reject.review-role-binding "$BAD_VERIFY_ROLE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_ROLE_PROJ"

BAD_VERIFY_AGENT_SCOPE_PROJ="$TMP/bad-verify-agent-scope-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_AGENT_SCOPE_PROJ"
python3 - "$BAD_VERIFY_AGENT_SCOPE_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
for agent in report["agents"]:
    if agent["role"] == "verify-logic":
        agent["verification_scope"] = ["stage_2_claim_scope"]
        break
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p14.reject.agent-scope
expect_reject l2.p14.reject.agent-scope "$BAD_VERIFY_AGENT_SCOPE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_AGENT_SCOPE_PROJ"

BAD_VERIFY_AGENT_DUP_PROJ="$TMP/bad-verify-agent-duplicate-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_AGENT_DUP_PROJ"
python3 - "$BAD_VERIFY_AGENT_DUP_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["agents"][1]["task_invocation_id"] = report["agents"][0]["task_invocation_id"]
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p14.reject.task-identity-binding
expect_reject l2.p14.reject.task-identity-binding "$BAD_VERIFY_AGENT_DUP_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_AGENT_DUP_PROJ"

BAD_VERIFY_STAGE1_PROJ="$TMP/bad-verify-stage1-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_STAGE1_PROJ"
python3 - "$BAD_VERIFY_STAGE1_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_1_outputs_to_manuscript"]["checked"] = report["stage_1_outputs_to_manuscript"]["checked"][:-1]
report["stage_1_outputs_to_manuscript"]["items_scanned"] = len(report["stage_1_outputs_to_manuscript"]["checked"])
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p14.reject.stage1-coverage
expect_reject l2.p14.reject.stage1-coverage "$BAD_VERIFY_STAGE1_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_STAGE1_PROJ"

BAD_VERIFY_STAGE2_PROJ="$TMP/bad-verify-stage2-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_STAGE2_PROJ"
python3 - "$BAD_VERIFY_STAGE2_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_2_manuscript_to_prose"]["checked"] = [{
    "source_artifact": "tables/results-registry.csv",
    "row_index": 0,
    "spec_id": "S1",
    "claim_id": "unexpected-row-claim",
    "verdict": "PASS"
}]
report["stage_2_manuscript_to_prose"]["claims_scanned"] = len(report["stage_2_manuscript_to_prose"]["checked"])
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p14.reject.stage2-exact-coverage
expect_reject l2.p14.reject.stage2-exact-coverage "$BAD_VERIFY_STAGE2_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_STAGE2_PROJ"

BAD_VERIFY_UNHASHABLE_ROW_INDEX_PROJ="$TMP/bad-verify-unhashable-row-index-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_UNHASHABLE_ROW_INDEX_PROJ"
python3 - "$BAD_VERIFY_UNHASHABLE_ROW_INDEX_PROJ/verify/manuscript-verification.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_2_manuscript_to_prose"]["checked"][0]["row_index"] = []
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p14.reject.unhashable-row-index
expect_reject f20.p14.reject.unhashable-row-index "$BAD_VERIFY_UNHASHABLE_ROW_INDEX_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_UNHASHABLE_ROW_INDEX_PROJ"

BAD_VERIFY_FLOAT_ROW_INDEX_PROJ="$TMP/bad-verify-float-row-index-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_FLOAT_ROW_INDEX_PROJ"
python3 - "$BAD_VERIFY_FLOAT_ROW_INDEX_PROJ/verify/manuscript-verification.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_2_manuscript_to_prose"]["checked"][0]["row_index"] = 0.0
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p14.reject.float-row-index
expect_reject f20.p14.reject.float-row-index "$BAD_VERIFY_FLOAT_ROW_INDEX_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_FLOAT_ROW_INDEX_PROJ"

BAD_VERIFY_BOOLEAN_ROW_INDEX_PROJ="$TMP/bad-verify-boolean-row-index-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_BOOLEAN_ROW_INDEX_PROJ"
python3 - "$BAD_VERIFY_BOOLEAN_ROW_INDEX_PROJ/verify/manuscript-verification.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_2_manuscript_to_prose"]["checked"][1]["row_index"] = True
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p14.reject.boolean-row-index
expect_reject f20.p14.reject.boolean-row-index "$BAD_VERIFY_BOOLEAN_ROW_INDEX_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_BOOLEAN_ROW_INDEX_PROJ"

BAD_VERIFY_MALFORMED_COUNT_PROJ="$TMP/bad-verify-malformed-count-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_MALFORMED_COUNT_PROJ"
python3 - "$BAD_VERIFY_MALFORMED_COUNT_PROJ/verify/manuscript-verification.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_2_manuscript_to_prose"]["claims_scanned"] = 3.9
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p14.reject.malformed-stage-count
expect_reject f20.p14.reject.malformed-stage-count "$BAD_VERIFY_MALFORMED_COUNT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_MALFORMED_COUNT_PROJ"

BAD_VERIFY_FIGURE_PROJ="$TMP/bad-verify-figure-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_FIGURE_PROJ"
python3 - "$BAD_VERIFY_FIGURE_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
for check in report["stage_1_outputs_to_manuscript"]["checked"]:
    if check.get("artifact_role") == "figure_file":
        check["visual_inspection"] = {"rendered": False, "caption_matches": True}
        break
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p14.reject.figure-inspection
expect_reject l2.p14.reject.figure-inspection "$BAD_VERIFY_FIGURE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_FIGURE_PROJ"

BAD_VERIFY_LIVE_READ_PROJ="$TMP/bad-verify-live-read-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_LIVE_READ_PROJ"
python3 - "$BAD_VERIFY_LIVE_READ_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["input_artifacts_read"][0]["path"] = "tables/results-registry.csv"
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p14.reject.live-read
expect_reject l2.p14.reject.live-read "$BAD_VERIFY_LIVE_READ_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_LIVE_READ_PROJ"

BAD_VERIFY_STAGE_DEGRADED_PROJ="$TMP/bad-verify-stage-degraded-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_STAGE_DEGRADED_PROJ"
python3 - "$BAD_VERIFY_STAGE_DEGRADED_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_1_outputs_to_manuscript"]["degraded"] = True
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p14.reject.stage-degraded
expect_reject l2.p14.reject.stage-degraded "$BAD_VERIFY_STAGE_DEGRADED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_STAGE_DEGRADED_PROJ"

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "14" ]]; then
  harness_validate_results --phase-through 14 >/dev/null
  progress "phases 0 to 14 authoritative harness assertions passed"
  exit 0
fi

CITATION_PROJ="$TMP/citation-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$CITATION_PROJ"
mkdir -p "$CITATION_PROJ/citation"
python3 - "$CITATION_PROJ" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

manuscript_path = proj / "manuscript/manuscript-draft.md"
draft_manifest_path = proj / "manuscript/draft-manifest.json"
source_bib_path = proj / "literature/references.bib"
phase13_path = proj / "verify/manuscript-verification.json"
claim_map_path = proj / "citation/claim-source-map.json"
exported_bib_path = proj / "citation/references.bib"
audit_path = proj / "citation/citation-audit.json"

manuscript_text = manuscript_path.read_text()
draft_manifest = json.loads(draft_manifest_path.read_text())
cited_keys = sorted(set(re.findall(r"@([A-Za-z0-9_:\-]+)", manuscript_text)))
source_bib = source_bib_path.read_text()
source_keys = sorted(set(match.strip() for match in re.findall(r"@\w+\s*\{\s*([^,\s]+)", source_bib)))
exported_bib_path.write_text(
    "\n".join(
        f"@article{{{key}, title={{Verified citation fixture for {key}}}, author={{Fixture Author}}, year={{2020}}}}"
        for key in cited_keys
    ) + "\n"
)
claims = []
for idx, key in enumerate(cited_keys, 1):
    if idx == 1:
        manuscript_location = "abstract"
    elif idx == 2:
        manuscript_location = "results"
    elif idx == 3:
        manuscript_location = "discussion"
    else:
        manuscript_location = "literature review and theory"
    claims.append({
        "claim_id": f"C{idx:03d}",
        "manuscript_location": manuscript_location,
        "manuscript_anchor": f"[@{key}]",
        "claim_type": "background",
        "claim_text": f"The manuscript makes a literature-supported claim citing {key}.",
        "citation_keys": [key],
        "source_locator": f"literature/references.bib:{key}",
        "evidence_span_summary": f"Project BibTeX metadata and literature synthesis support the claim associated with {key}.",
        "support_verdict": "SUPPORTED",
        "contradiction": False
    })
for source_claim in draft_manifest.get("locked_result_claims", []):
    if not isinstance(source_claim, dict):
        continue
    for row in source_claim.get("rows", []):
        if not isinstance(row, dict):
            continue
        empirical_cite = {
            "S1": "work01",
            "S2": "work02",
            "S3": "work03",
        }.get(row.get("spec_id"), "work01")
        claims.append({
            "claim_id": row["claim_id"],
            "manuscript_location": "results",
            "manuscript_anchor": row["manuscript_anchor"],
            "claim_type": "empirical",
            "claim_text": f"Locked empirical row claim for {row['spec_id']}.",
            "citation_keys": [empirical_cite],
            "source_locator": source_claim["locked_path"],
            "result_binding": {
                "binding_type": source_claim["binding_type"],
                "display_source_path": source_claim["display_source_path"],
                "display_locked_path": source_claim["display_locked_path"],
                "value_source_path": source_claim["source_path"],
                "value_locked_path": source_claim["locked_path"],
                "row_index": row["row_index"],
                "spec_id": row["spec_id"],
                "display_coordinate_kind": row["display_coordinate_kind"],
                "display_coordinate": row["display_coordinate"]
            },
            "evidence_span_summary": f"Locked row {row['row_index']} in {source_claim['locked_path']} supports the reported estimate.",
            "support_verdict": "SUPPORTED",
            "contradiction": False
        })
claim_map = {
    "verdict": "PASS",
    "degraded": False,
    "selected_manuscript_hash": sha(manuscript_path),
    "source_hashes": {
        "manuscript": sha(manuscript_path),
        "references_bib": sha(source_bib_path)
    },
    "total_claims": len(claims),
    "supported_count": len(claims),
    "unsupported_count": 0,
    "contradicted_count": 0,
    "locator_missing_count": 0,
    "claim_specificity": {
        "status": "PASS",
        "omnibus_claim_count": 0,
        "max_citation_keys_per_claim": max((len(claim.get("citation_keys", [])) for claim in claims), default=0),
        "bulk_citation_exceptions_documented": True
    },
    "claims": claims
}
claim_map_path.write_text(json.dumps(claim_map, indent=2, sort_keys=True) + "\n")
verified_references = [
    {
        "key": key,
        "verification_status": "VERIFIED",
        "verification_sources": ["project_bib", "crossref_fixture"],
        "metadata_match": True,
        "fabricated": False,
        "retraction_status": "not_retracted"
    }
    for key in cited_keys
]
retraction_records = [
    {
        "key": key,
        "status": "not_retracted",
        "retracted": False,
        "checked_against": ["project_bib", "scholar-citation-retraction-workflow"]
    }
    for key in cited_keys
]
audit = {
    "verdict": "PASS",
    "degraded": False,
    "source_phase": "14",
    "citation_engine": {
        "skill": "scholar-citation",
        "mode": "verify",
        "source_verification": True,
        "claim_support": True,
        "retraction_check": True,
        "fabrication_guard": True,
        "task_invocation_id": "phase15-citation-001",
        "invoked_at_utc": "2026-04-30T12:00:00Z",
        "input_artifacts": [
            "manuscript/manuscript-draft.md",
            "manuscript/draft-manifest.json",
            "literature/references.bib",
            "verify/manuscript-verification.json"
        ],
        "output_artifacts": [
            "citation/citation-audit.json",
            "citation/claim-source-map.json",
            "citation/references.bib"
        ]
    },
    "source_hashes": {
        "manuscript": sha(manuscript_path),
        "draft_manifest": sha(draft_manifest_path),
        "source_bib": sha(source_bib_path),
        "phase13_verification": sha(phase13_path),
        "claim_source_map": sha(claim_map_path),
        "exported_references": sha(exported_bib_path)
    },
    "selected_manuscript_hash": sha(manuscript_path),
    "citation_inventory": {
        "unique_cited_keys": cited_keys,
        "unique_cited_count": len(cited_keys),
        "source_bib_keys": source_keys,
        "source_bib_count": len(source_keys),
        "exported_bib_keys": cited_keys,
        "exported_bib_count": len(cited_keys),
        "unresolved_citation_count": 0
    },
    "bibliography_provenance": {
        "source_bib_path": "literature/references.bib",
        "exported_bib_path": "citation/references.bib",
        "project_native_primary": True,
        "cross_project_imports_declared": False,
        "cross_project_import_count": 0,
        "cross_project_import_notes": ""
    },
    "verified_references": verified_references,
    "unresolved_citation_count": 0,
    "fabricated_reference_count": 0,
    "unsupported_claims": 0,
    "contradicted_claims": 0,
    "locator_missing": 0,
    "retraction_check": {
        "checked_count": len(cited_keys),
        "retracted_count": 0,
        "records": retraction_records
    },
    "claim_source_map": {
        "path": "citation/claim-source-map.json",
        "total_claims": len(claims),
        "supported_count": len(claims),
        "unsupported_count": 0,
        "contradicted_count": 0,
        "locator_missing_count": 0
    },
    "claim_specificity": {
        "status": "PASS",
        "omnibus_claim_count": 0,
        "max_citation_keys_per_claim": max((len(claim.get("citation_keys", [])) for claim in claims), default=0),
        "bulk_citation_exceptions_documented": True
    },
    "findings": [],
    "fix_checklist": {
        "critical_fixes": [],
        "route_back": []
    },
    "route_back_phase": None,
    "ready_for_phase_16": True
}
audit_path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# Deterministic local authority for Phase 15: a minimal read-only Zotero
# fixture matching work01. This exercises the production local-library gate;
# it does not disable or replace any citation check.
FIXTURE_ZOTERO_DIR="$TMP/zotero-fixture"
mkdir -p "$FIXTURE_ZOTERO_DIR"
python3 - "$FIXTURE_ZOTERO_DIR/zotero.sqlite" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""
CREATE TABLE itemTypes (itemTypeID INTEGER PRIMARY KEY, typeName TEXT);
CREATE TABLE items (itemID INTEGER PRIMARY KEY, itemTypeID INTEGER);
CREATE TABLE fields (fieldID INTEGER PRIMARY KEY, fieldName TEXT);
CREATE TABLE itemDataValues (valueID INTEGER PRIMARY KEY, value TEXT);
CREATE TABLE itemData (itemID INTEGER, fieldID INTEGER, valueID INTEGER);
CREATE TABLE creators (creatorID INTEGER PRIMARY KEY, lastName TEXT);
CREATE TABLE itemCreators (itemID INTEGER, creatorID INTEGER, orderIndex INTEGER);
CREATE TABLE deletedItems (itemID INTEGER);
INSERT INTO itemTypes VALUES (1, 'journalArticle');
INSERT INTO fields VALUES (1, 'title'), (2, 'date');
INSERT INTO creators VALUES (1, 'Author');
""")
for item_id in range(1, 31):
    title_value_id = item_id * 2 - 1
    date_value_id = item_id * 2
    db.execute("INSERT INTO items VALUES (?, 1)", (item_id,))
    db.execute("INSERT INTO itemDataValues VALUES (?, ?)", (title_value_id, f"Verified citation fixture for work{item_id:02d}"))
    db.execute("INSERT INTO itemDataValues VALUES (?, '2020')", (date_value_id,))
    db.execute("INSERT INTO itemData VALUES (?, 1, ?)", (item_id, title_value_id))
    db.execute("INSERT INTO itemData VALUES (?, 2, ?)", (item_id, date_value_id))
    db.execute("INSERT INTO itemCreators VALUES (?, 1, 0)", (item_id,))
db.commit()
db.close()
PY
export SCHOLAR_ZOTERO_DIR="$FIXTURE_ZOTERO_DIR"
# Make the optional CrossRef provider deterministically unavailable and fast;
# Phase 15 must still pass from complete keyed local-library authority.
FIXTURE_BIN="$TMP/fixture-bin"
mkdir -p "$FIXTURE_BIN"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FIXTURE_BIN/curl"
chmod +x "$FIXTURE_BIN/curl"
export PATH="$FIXTURE_BIN:$PATH"
# CASE_ID: phase.15.positive
expect_pass phase.15.positive "$CITATION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$CITATION_PROJ"

sync_claim_map_counts() {
  local project="$1"
  python3 - "$project" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
map_path = proj / "citation/claim-source-map.json"
audit_path = proj / "citation/citation-audit.json"
claim_map = json.loads(map_path.read_text())
count = len(claim_map["claims"])
for key, value in {"total_claims": count, "supported_count": count, "unsupported_count": 0, "contradicted_count": 0, "locator_missing_count": 0}.items():
    claim_map[key] = value
map_path.write_text(json.dumps(claim_map, indent=2, sort_keys=True) + "\n")
audit = json.loads(audit_path.read_text())
audit["source_hashes"]["claim_source_map"] = hashlib.sha256(map_path.read_bytes()).hexdigest()
for key, value in {"total_claims": count, "supported_count": count, "unsupported_count": 0, "contradicted_count": 0, "locator_missing_count": 0}.items():
    audit["claim_source_map"][key] = value
audit_path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
}

CITATION_REORDERED_PROJ="$TMP/citation-reordered-project"
cp -R "$CITATION_PROJ" "$CITATION_REORDERED_PROJ"
python3 - "$CITATION_REORDERED_PROJ/citation/claim-source-map.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["claims"].reverse()
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
sync_claim_map_counts "$CITATION_REORDERED_PROJ"
# CASE_ID: f20.p15.empirical-reordered-positive
expect_pass f20.p15.empirical-reordered-positive "$CITATION_REORDERED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$CITATION_REORDERED_PROJ"

for mode in missing extra duplicate; do
  project="$TMP/citation-empirical-$mode-project"
  cp -R "$CITATION_PROJ" "$project"
  python3 - "$project/citation/claim-source-map.json" "$mode" <<'PY'
import copy, json, pathlib, sys
path, mode = pathlib.Path(sys.argv[1]), sys.argv[2]
doc = json.loads(path.read_text())
indices = [idx for idx, claim in enumerate(doc["claims"]) if claim.get("claim_type") == "empirical"]
assert len(indices) == 3
if mode == "missing":
    del doc["claims"][indices[0]]
elif mode == "extra":
    claim = copy.deepcopy(doc["claims"][indices[0]])
    claim["claim_id"] = "lrc2:" + "f" * 64
    doc["claims"].append(claim)
else:
    doc["claims"].append(copy.deepcopy(doc["claims"][indices[0]]))
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
  sync_claim_map_counts "$project"
  case "$mode" in
    missing)
      # CASE_ID: f20.p15.reject.empirical-missing
      expect_reject f20.p15.reject.empirical-missing "$project" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$project"
      ;;
    extra)
      # CASE_ID: f20.p15.reject.empirical-extra
      expect_reject f20.p15.reject.empirical-extra "$project" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$project"
      ;;
    duplicate)
      # CASE_ID: f20.p15.reject.empirical-duplicate
      expect_reject f20.p15.reject.empirical-duplicate "$project" -- bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$project"
      ;;
  esac
done

BAD_EMPIRICAL_BINDING_PROJ="$TMP/bad-empirical-binding-project"
cp -R "$CITATION_PROJ" "$BAD_EMPIRICAL_BINDING_PROJ"
python3 - "$BAD_EMPIRICAL_BINDING_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
map_path = proj / "citation/claim-source-map.json"
audit_path = proj / "citation/citation-audit.json"
claim_map = json.loads(map_path.read_text())
empirical = next(item for item in claim_map["claims"] if item.get("claim_type") == "empirical")
empirical["result_binding"]["value_source_path"] = "tables/wrong-results.csv"
map_path.write_text(json.dumps(claim_map, indent=2, sort_keys=True) + "\n")
audit = json.loads(audit_path.read_text())
audit["source_hashes"]["claim_source_map"] = hashlib.sha256(map_path.read_bytes()).hexdigest()
audit_path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p15.reject.empirical-result-binding
expect_reject l2.p15.reject.empirical-result-binding "$BAD_EMPIRICAL_BINDING_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_EMPIRICAL_BINDING_PROJ"

BAD_CITATION_MALFORMED_SPECIFICITY_PROJ="$TMP/bad-citation-malformed-specificity-project"
cp -R "$CITATION_PROJ" "$BAD_CITATION_MALFORMED_SPECIFICITY_PROJ"
python3 - "$BAD_CITATION_MALFORMED_SPECIFICITY_PROJ/citation/citation-audit.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
audit = json.loads(path.read_text())
audit["claim_specificity"]["max_citation_keys_per_claim"] = []
path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: f20.p15.reject.malformed-specificity-count
expect_reject f20.p15.reject.malformed-specificity-count "$BAD_CITATION_MALFORMED_SPECIFICITY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_MALFORMED_SPECIFICITY_PROJ"

FAIL_CITATION_PROJ="$TMP/fail-citation-project"
cp -R "$CITATION_PROJ" "$FAIL_CITATION_PROJ"
python3 - "$FAIL_CITATION_PROJ/citation/citation-audit.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
audit = json.loads(path.read_text())
audit["verdict"] = "FAIL"
audit["ready_for_phase_16"] = False
audit["unsupported_claims"] = 1
audit["route_back_phase"] = "13"
audit["findings"] = [
    {
        "finding_id": "P14-F001",
        "severity": "CRITICAL",
        "category": "unsupported_claim",
        "owner_phase": "13",
        "route_back_phase": "13",
        "detected_by": "claim-source-map",
        "affected_artifacts": ["manuscript/manuscript-draft.md"],
        "required_fix": "Revise or remove the unsupported cited claim, then rerun drafting, manuscript verification, and citation audit.",
        "status": "open"
    }
]
audit["fix_checklist"] = {
    "critical_fixes": ["Revise unsupported cited claim."],
    "route_back": ["13"]
}
path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.15.negative
expect_reject phase.15.negative "$FAIL_CITATION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$FAIL_CITATION_PROJ"

ROUTE_STATE_14_PROJ="$TMP/route-state-14-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_14_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_14_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_14_PROJ/artifacts" "$ROUTE_STATE_14_PROJ/citation"
for pid in $(seq 0 14); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_14_PROJ/artifacts/phase-$pid.txt"
  complete_sm "$ROUTE_STATE_14_PROJ" "$pid" "$ROUTE_STATE_14_PROJ/artifacts/phase-$pid.txt"
done
cp "$FAIL_CITATION_PROJ/citation/citation-audit.json" "$ROUTE_STATE_14_PROJ/citation/citation-audit.json"
ROUTE_14_OUT="$(bash "$SCRIPT_DIR/auto-research-state.sh" route-back "$ROUTE_STATE_14_PROJ" "$ROUTE_STATE_14_PROJ/citation/citation-audit.json")"
case "$ROUTE_14_OUT" in
  *"ROUTE_BACK_PHASE=13"*"INVALIDATED_PHASES=13,14"* ) ;;
  *) echo "FAIL: Phase 15 route-back should invalidate phases 13 and 14, got $ROUTE_14_OUT" >&2; exit 1 ;;
esac
python3 - "$ROUTE_STATE_14_PROJ/.auto-research/state.json" <<'PY'
import json
import pathlib
import sys
state = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = state.get("active_route_back", {}).get("source_phase")
if source != "14":
    raise SystemExit(f"FAIL: citation route-back source_phase should remain 14, got {source}")
PY

BAD_CITATION_EXPORT_PROJ="$TMP/bad-citation-export-project"
cp -R "$CITATION_PROJ" "$BAD_CITATION_EXPORT_PROJ"
python3 - "$BAD_CITATION_EXPORT_PROJ/citation/references.bib" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
path.write_text("\n".join(lines[1:]) + "\n")
PY
python3 - "$BAD_CITATION_EXPORT_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
path = proj / "citation/citation-audit.json"
audit = json.loads(path.read_text())
audit["source_hashes"]["exported_references"] = hashlib.sha256((proj / "citation/references.bib").read_bytes()).hexdigest()
path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p15.reject.exported-reference-coverage
expect_reject l2.p15.reject.exported-reference-coverage "$BAD_CITATION_EXPORT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_EXPORT_PROJ"

BAD_CITATION_REFERENCE_PROJ="$TMP/bad-citation-reference-project"
cp -R "$CITATION_PROJ" "$BAD_CITATION_REFERENCE_PROJ"
python3 - "$BAD_CITATION_REFERENCE_PROJ/citation/citation-audit.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
audit = json.loads(path.read_text())
audit["verified_references"][0]["verification_status"] = "UNVERIFIED"
path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p15.reject.verified-reference
expect_reject l2.p15.reject.verified-reference "$BAD_CITATION_REFERENCE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_REFERENCE_PROJ"

BAD_CITATION_CLAIM_PROJ="$TMP/bad-citation-claim-project"
cp -R "$CITATION_PROJ" "$BAD_CITATION_CLAIM_PROJ"
python3 - "$BAD_CITATION_CLAIM_PROJ/citation/claim-source-map.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
claim_map = json.loads(path.read_text())
claim_map["claims"][0]["support_verdict"] = "UNSUPPORTED"
claim_map["unsupported_count"] = 1
path.write_text(json.dumps(claim_map, indent=2, sort_keys=True) + "\n")
PY
python3 - "$BAD_CITATION_CLAIM_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
path = proj / "citation/citation-audit.json"
audit = json.loads(path.read_text())
audit["source_hashes"]["claim_source_map"] = hashlib.sha256((proj / "citation/claim-source-map.json").read_bytes()).hexdigest()
path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p15.reject.claim-support
expect_reject l2.p15.reject.claim-support "$BAD_CITATION_CLAIM_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_CLAIM_PROJ"

BAD_CITATION_ANCHOR_PROJ="$TMP/bad-citation-anchor-project"
cp -R "$CITATION_PROJ" "$BAD_CITATION_ANCHOR_PROJ"
python3 - "$BAD_CITATION_ANCHOR_PROJ/citation/claim-source-map.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
claim_map = json.loads(path.read_text())
claim_map["claims"][0]["manuscript_anchor"] = "This anchored claim is not present in the manuscript [@work01]."
path.write_text(json.dumps(claim_map, indent=2, sort_keys=True) + "\n")
PY
python3 - "$BAD_CITATION_ANCHOR_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
path = proj / "citation/citation-audit.json"
audit = json.loads(path.read_text())
audit["source_hashes"]["claim_source_map"] = hashlib.sha256((proj / "citation/claim-source-map.json").read_bytes()).hexdigest()
path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p15.reject.manuscript-anchor
expect_reject l2.p15.reject.manuscript-anchor "$BAD_CITATION_ANCHOR_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_ANCHOR_PROJ"

BAD_CITATION_LOCATOR_PROJ="$TMP/bad-citation-locator-project"
cp -R "$CITATION_PROJ" "$BAD_CITATION_LOCATOR_PROJ"
python3 - "$BAD_CITATION_LOCATOR_PROJ/citation/claim-source-map.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
claim_map = json.loads(path.read_text())
claim_map["claims"][0]["claim_type"] = "causal"
claim_map["claims"][0]["source_locator"] = ""
claim_map["locator_missing_count"] = 1
path.write_text(json.dumps(claim_map, indent=2, sort_keys=True) + "\n")
PY
python3 - "$BAD_CITATION_LOCATOR_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
path = proj / "citation/citation-audit.json"
audit = json.loads(path.read_text())
audit["source_hashes"]["claim_source_map"] = hashlib.sha256((proj / "citation/claim-source-map.json").read_bytes()).hexdigest()
path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p15.reject.source-locator
expect_reject l2.p15.reject.source-locator "$BAD_CITATION_LOCATOR_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_LOCATOR_PROJ"

BAD_CITATION_RETRACTION_PROJ="$TMP/bad-citation-retraction-project"
cp -R "$CITATION_PROJ" "$BAD_CITATION_RETRACTION_PROJ"
python3 - "$BAD_CITATION_RETRACTION_PROJ/citation/citation-audit.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
audit = json.loads(path.read_text())
audit["retraction_check"]["retracted_count"] = 1
audit["retraction_check"]["records"][0]["status"] = "retracted"
audit["retraction_check"]["records"][0]["retracted"] = True
path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p15.reject.retraction
expect_reject l2.p15.reject.retraction "$BAD_CITATION_RETRACTION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_RETRACTION_PROJ"

BAD_CITATION_PLACEHOLDER_PROJ="$TMP/bad-citation-placeholder-project"
cp -R "$CITATION_PROJ" "$BAD_CITATION_PLACEHOLDER_PROJ"
printf '\nSOURCE NEEDED\n' >> "$BAD_CITATION_PLACEHOLDER_PROJ/manuscript/manuscript-draft.md"
sync_draft_fixture_hashes "$BAD_CITATION_PLACEHOLDER_PROJ"
python3 - "$BAD_CITATION_PLACEHOLDER_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

verification_path = proj / "verify/manuscript-verification.json"
verification = json.loads(verification_path.read_text())
manuscript_hash = sha(proj / "manuscript/manuscript-draft.md")
draft_manifest_hash = sha(proj / "manuscript/draft-manifest.json")
verification["source_hashes"]["manuscript"] = manuscript_hash
verification["source_hashes"]["draft_manifest"] = draft_manifest_hash
verification["selected_manuscript_hash"] = manuscript_hash
for agent in verification["agents"]:
    agent["input_hashes"]["manuscript"] = manuscript_hash
    agent["input_hashes"]["draft_manifest"] = draft_manifest_hash
verification_path.write_text(json.dumps(verification, indent=2, sort_keys=True) + "\n")
PY
OLD_PHASE14_SESSION="$(python3 - "$BAD_CITATION_PLACEHOLDER_PROJ/verify/manuscript-verification.json" <<'PY'
import json, pathlib, sys
document = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(document["review_evidence"]["rounds"]["verification_panel"]["session_id"])
PY
)"
bash "$SCRIPT_DIR/auto-research-state.sh" review-abort "$BAD_CITATION_PLACEHOLDER_PROJ" 14 "$OLD_PHASE14_SESSION" \
  --reason "fixture manuscript placeholder mutation requires renewed Phase 14 verification evidence" >/dev/null
python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$BAD_CITATION_PLACEHOLDER_PROJ" 14 verification_panel >/dev/null
python3 - "$BAD_CITATION_PLACEHOLDER_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

manuscript_hash = sha(proj / "manuscript/manuscript-draft.md")
draft_manifest_hash = sha(proj / "manuscript/draft-manifest.json")
verification_hash = sha(proj / "verify/manuscript-verification.json")
claim_path = proj / "citation/claim-source-map.json"
claim_map = json.loads(claim_path.read_text())
claim_map["selected_manuscript_hash"] = manuscript_hash
claim_map["source_hashes"]["manuscript"] = manuscript_hash
claim_path.write_text(json.dumps(claim_map, indent=2, sort_keys=True) + "\n")
audit_path = proj / "citation/citation-audit.json"
audit = json.loads(audit_path.read_text())
audit["selected_manuscript_hash"] = manuscript_hash
audit["source_hashes"]["manuscript"] = manuscript_hash
audit["source_hashes"]["draft_manifest"] = draft_manifest_hash
audit["source_hashes"]["phase13_verification"] = verification_hash
audit["source_hashes"]["claim_source_map"] = sha(claim_path)
audit_path.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p15.reject.placeholder
expect_reject l2.p15.reject.placeholder "$BAD_CITATION_PLACEHOLDER_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_PLACEHOLDER_PROJ"

ETHICS_PROJ="$TMP/ethics-project"
if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "15" ]]; then
  harness_validate_results --phase-through 15 >/dev/null
  progress "phases 0 to 15 authoritative harness assertions passed"
  exit 0
fi

progress "phases 16 to 18 ethics, replication, and quality fixtures"
cp -R "$CITATION_PROJ" "$ETHICS_PROJ"
mkdir -p "$ETHICS_PROJ/safety" "$ETHICS_PROJ/data" "$ETHICS_PROJ/ethics"
printf '{"safety_status":"PASS","files_scanned":2,"no_data_declared":false,"high_risk_unresolved":0,"status_by_file":{"data/raw/example.csv":{"source_status":"CLEARED"},"materials/codebook.md":{"source_status":"CLEARED"}},"counts":{"CLEARED":2}}\n' > "$ETHICS_PROJ/safety/safety-status.json"
printf '{"data_status":"existing-data","access_status":"available","irb_status":"exempt","source_type":"public secondary data","files":[{"path":"data/raw/example.csv","status":"available"}]}\n' > "$ETHICS_PROJ/data/data-status.json"
python3 - "$ETHICS_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

safety_path = proj / "safety/safety-status.json"
data_status_path = proj / "data/data-status.json"
manuscript_path = proj / "manuscript/manuscript-draft.md"
draft_manifest_path = proj / "manuscript/draft-manifest.json"
citation_audit_path = proj / "citation/citation-audit.json"
report = {
    "verdict": "PASS",
    "degraded": False,
    "source_phase": "16",
    "ethics_engine": {
        "skill": "scholar-ethics",
        "mode": "full",
        "ai_privacy": True,
        "originality": True,
        "integrity": True,
        "general_ethics": True,
        "task_invocation_id": "phase16-ethics-001",
        "invoked_at_utc": "2026-04-30T13:00:00Z",
        "input_artifacts": [
            "manuscript/manuscript-draft.md",
            "citation/citation-audit.json",
            "safety/safety-status.json",
            "data/data-status.json"
        ],
        "output_artifacts": ["ethics/ethics-open-science.json", "ethics/ethics-open-science.md"]
    },
    "open_science_engine": {
        "skill": "scholar-open",
        "mode": "full-package",
        "data_management": True,
        "code_sharing": True,
        "credit_coi": True,
        "replication_planning": True,
        "task_invocation_id": "phase16-open-001",
        "invoked_at_utc": "2026-04-30T13:10:00Z",
        "input_artifacts": [
            "manuscript/manuscript-draft.md",
            "data/data-status.json",
            "citation/citation-audit.json"
        ],
        "output_artifacts": ["ethics/ethics-open-science.json", "ethics/ethics-open-science.md"]
    },
    "source_hashes": {
        "safety_status": sha(safety_path),
        "data_status": sha(data_status_path),
        "manuscript": sha(manuscript_path),
        "draft_manifest": sha(draft_manifest_path),
        "citation_audit": sha(citation_audit_path)
    },
    "selected_manuscript_hash": sha(manuscript_path),
    "critical_flags": [],
    "ai_disclosure": {
        "tools": [
            {
                "tool": "AI coding assistant",
                "provider": "portable fixture provider",
                "model_or_version": "provider-neutral fixture model",
                "stage_used": "workflow design and validation",
                "task_performed": "contract design, fixture construction, and validation checks",
                "data_type_shared": "project structure, code, manuscript excerpts, aggregate non-identifying artifacts",
                "sensitivity": "Low"
                ,"date_used": "2026-04-30",
                "cloud_or_local": "cloud"
            }
        ],
        "statement": "The authors used AI-assisted coding and writing tools to help structure workflow checks, draft non-substantive disclosure language, and validate code paths. No personally identifiable participant data or restricted microdata were shared with AI tools. All AI-assisted content, code, citations, interpretations, and declarations were reviewed and verified by the human authors before inclusion in the manuscript.",
        "human_reviewed": True,
        "sensitive_data_shared": False
    },
    "privacy_review": {
        "risk_level": "Low",
        "high_risk_unresolved": 0,
        "safety_status": "PASS",
        "irb_consent_scope_checked": True,
        "dua_checked": True,
        "institutional_policy_checked": True
    },
    "irb_status": {
        "status": "exempt",
        "determination": "exempt secondary-data determination",
        "statement": "The project uses public secondary data without direct identifiers. The Institutional Review Board determined the research to be exempt from full review under the applicable secondary-data category."
    },
    "consent_status": {
        "status": "not-applicable",
        "statement": "The analysis uses public secondary data, so direct participant consent collection by the authors was not applicable to this manuscript."
    },
    "coi_status": {
        "status": "no_competing_interests",
        "statement": "The authors declare no competing interests.",
        "unresolved_conflicts": False
    },
    "data_availability": {
        "sharing_mode": "public-data-full",
        "matches_data_status": True,
        "statement": "The data used in this manuscript are public secondary data. The analysis dataset, codebook, and documentation will be deposited with the replication package, subject to repository metadata requirements and citation of the original data provider.",
        "repository_or_access_plan": "Project repository and archival deposit with DOI at release"
    },
    "open_science": {
        "preregistration_status": "Not preregistered because the study uses completed secondary data; confirmatory and exploratory analyses are labeled in the manuscript.",
        "code_sharing_plan": "All analysis scripts needed to reproduce the locked results will be shared in the Phase 16 replication package.",
        "license_plan": "Code will be released under an MIT license and data documentation under CC-BY where permitted.",
        "preprint_open_access_plan": "The authors plan to post a preprint or accepted manuscript according to journal policy.",
        "replication_ready": True,
        "phase16_handoff": "replication-package"
    },
    "authorship_credit": {
        "credit_roles": ["Conceptualization", "Methodology", "Formal analysis", "Writing - original draft", "Writing - review and editing"],
        "statement": "Author contributions will be reported using CRediT roles covering conceptualization, methodology, formal analysis, validation, and writing responsibilities."
    },
    "integrity_review": {
        "originality_check": "PASS",
        "p_hacking_review": "PASS",
        "selective_reporting_review": "PASS",
        "misinterpretation_review": "PASS",
        "citation_audit_used": True,
        "result_constraints_used": True,
        "checked_artifacts": [
            {
                "path": "citation/citation-audit.json",
                "sha256": sha(citation_audit_path)
            },
            {
                "path": "manuscript/draft-manifest.json",
                "sha256": sha(draft_manifest_path)
            }
        ]
    },
    "findings": [],
    "fix_checklist": {
        "critical_fixes": [],
        "route_back": []
    },
    "route_back_phase": None,
    "ready_for_phase_17": True
}
(proj / "ethics/ethics-open-science.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
summary = """
# Ethics and Open Science Declarations

## AI Use Disclosure
The authors used AI-assisted coding and writing tools to help structure workflow checks, draft non-substantive disclosure language, and validate code paths. No personally identifiable participant data or restricted microdata were shared with AI tools. Human authors reviewed all AI-assisted content before inclusion.

## IRB and Consent
The IRB statement records an exempt secondary-data determination. Consent collection by the authors was not applicable because the project uses public secondary data without direct identifiers.

## Conflict of Interest
The authors declare no competing interests, and no conflict requires follow-up.

## Data Availability
The data availability statement identifies public secondary data and a public-data-full sharing mode. The analysis dataset, codebook, and documentation will be deposited with the replication package, with citation of the original provider.

## Open Science
The open science plan states the preregistration status, the code sharing plan, the license plan, and the preprint or open-access plan. Phase 16 will assemble the replication package from the locked analysis artifacts and these ethics declarations.

## Authorship and Integrity
The CRediT statement covers conceptualization, methodology, formal analysis, validation, and writing responsibilities. The originality, selective reporting, p-hacking, and misinterpretation reviews pass using the Phase 14 citation audit and the locked-result interpretation constraints.
"""
(proj / "ethics/ethics-open-science.md").write_text((summary.strip() + "\n\n") * 3)
PY
# CASE_ID: phase.16.positive
expect_pass phase.16.positive "$ETHICS_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$ETHICS_PROJ"

FAIL_ETHICS_PROJ="$TMP/fail-ethics-project"
cp -R "$ETHICS_PROJ" "$FAIL_ETHICS_PROJ"
python3 - "$FAIL_ETHICS_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["verdict"] = "FAIL"
report["ready_for_phase_17"] = False
report["critical_flags"] = ["IRB status is pending"]
report["route_back_phase"] = "4"
report["findings"] = [
    {
        "finding_id": "P15-F001",
        "severity": "CRITICAL",
        "category": "irb_consent",
        "owner_phase": "4",
        "route_back_phase": "4",
        "detected_by": "scholar-ethics",
        "affected_artifacts": ["data/data-status.json", "ethics/ethics-open-science.json"],
        "required_fix": "Resolve the pending IRB/consent status in Phase 4 before ethics/open-science declarations can pass.",
        "status": "open"
    }
]
report["fix_checklist"] = {
    "critical_fixes": ["Resolve pending IRB/consent status."],
    "route_back": ["4"]
}
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.16.negative
expect_reject phase.16.negative "$FAIL_ETHICS_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$FAIL_ETHICS_PROJ"

ROUTE_STATE_15_PROJ="$TMP/route-state-15-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_15_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_15_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_15_PROJ/artifacts" "$ROUTE_STATE_15_PROJ/ethics"
for pid in $(seq 0 15); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_15_PROJ/artifacts/phase-$pid.txt"
  complete_sm "$ROUTE_STATE_15_PROJ" "$pid" "$ROUTE_STATE_15_PROJ/artifacts/phase-$pid.txt"
done
cp "$FAIL_ETHICS_PROJ/ethics/ethics-open-science.json" "$ROUTE_STATE_15_PROJ/ethics/ethics-open-science.json"
ROUTE_15_OUT="$(bash "$SCRIPT_DIR/auto-research-state.sh" route-back "$ROUTE_STATE_15_PROJ" "$ROUTE_STATE_15_PROJ/ethics/ethics-open-science.json")"
case "$ROUTE_15_OUT" in
  *"ROUTE_BACK_PHASE=4"*"INVALIDATED_PHASES=4,5,6,7,8,9,10,11,12,13,14,15"* ) ;;
  *) echo "FAIL: Phase 15 route-back should invalidate phases 4-15, got $ROUTE_15_OUT" >&2; exit 1 ;;
esac
python3 - "$ROUTE_STATE_15_PROJ/.auto-research/state.json" <<'PY'
import json
import pathlib
import sys
state = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = state.get("active_route_back", {}).get("source_phase")
if source != "16":
    raise SystemExit(f"FAIL: Phase 16 route-back source_phase should be 16, got {source}")
PY

BAD_ETHICS_ENGINE_PROJ="$TMP/bad-ethics-engine-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_ENGINE_PROJ"
python3 - "$BAD_ETHICS_ENGINE_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["ethics_engine"]["skill"] = "generic-ethics"
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.ethics-engine
expect_reject l2.p16.reject.ethics-engine "$BAD_ETHICS_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_ENGINE_PROJ"

BAD_ETHICS_ENGINE_CAPABILITY_PROJ="$TMP/bad-ethics-engine-capability-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_ENGINE_CAPABILITY_PROJ"
python3 - "$BAD_ETHICS_ENGINE_CAPABILITY_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["ethics_engine"]["integrity"] = False
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.ethics-capabilities
expect_reject l2.p16.reject.ethics-capabilities "$BAD_ETHICS_ENGINE_CAPABILITY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_ENGINE_CAPABILITY_PROJ"

BAD_OPEN_ENGINE_CAPABILITY_PROJ="$TMP/bad-open-engine-capability-project"
cp -R "$ETHICS_PROJ" "$BAD_OPEN_ENGINE_CAPABILITY_PROJ"
python3 - "$BAD_OPEN_ENGINE_CAPABILITY_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["open_science_engine"]["replication_planning"] = False
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.open-science-capabilities
expect_reject l2.p16.reject.open-science-capabilities "$BAD_OPEN_ENGINE_CAPABILITY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_OPEN_ENGINE_CAPABILITY_PROJ"

BAD_ETHICS_HASH_PROJ="$TMP/bad-ethics-hash-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_HASH_PROJ"
python3 - "$BAD_ETHICS_HASH_PROJ/ethics/ethics-open-science.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["source_hashes"]["manuscript"] = "0" * 64
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.manuscript-hash
expect_reject l2.p16.reject.manuscript-hash "$BAD_ETHICS_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_HASH_PROJ"

BAD_ETHICS_IRB_PROJ="$TMP/bad-ethics-irb-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_IRB_PROJ"
python3 - "$BAD_ETHICS_IRB_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["irb_status"]["status"] = "pending"
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.irb-status
expect_reject l2.p16.reject.irb-status "$BAD_ETHICS_IRB_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_IRB_PROJ"

BAD_ETHICS_DATA_PROJ="$TMP/bad-ethics-data-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_DATA_PROJ"
python3 - "$BAD_ETHICS_DATA_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["data_availability"]["sharing_mode"] = "no-data-conceptual"
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.data-availability
expect_reject l2.p16.reject.data-availability "$BAD_ETHICS_DATA_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_DATA_PROJ"

BAD_ETHICS_AI_PROJ="$TMP/bad-ethics-ai-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_AI_PROJ"
python3 - "$BAD_ETHICS_AI_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["ai_disclosure"]["human_reviewed"] = False
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.ai-human-review
expect_reject l2.p16.reject.ai-human-review "$BAD_ETHICS_AI_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_AI_PROJ"

BAD_ETHICS_CREDIT_PROJ="$TMP/bad-ethics-credit-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_CREDIT_PROJ"
python3 - "$BAD_ETHICS_CREDIT_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["authorship_credit"]["credit_roles"] = []
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.credit-roles-missing
expect_reject l2.p16.reject.credit-roles-missing "$BAD_ETHICS_CREDIT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_CREDIT_PROJ"

BAD_ETHICS_REPLICATION_PROJ="$TMP/bad-ethics-replication-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_REPLICATION_PROJ"
python3 - "$BAD_ETHICS_REPLICATION_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["open_science"]["replication_ready"] = False
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.replication-handoff
expect_reject l2.p16.reject.replication-handoff "$BAD_ETHICS_REPLICATION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_REPLICATION_PROJ"

BAD_ETHICS_PLACEHOLDER_PROJ="$TMP/bad-ethics-placeholder-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_PLACEHOLDER_PROJ"
python3 - "$BAD_ETHICS_PLACEHOLDER_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["irb_status"]["statement"] = "The [University] Institutional Review Board approved protocol [number] on [date] for this study."
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.json-placeholder
expect_reject l2.p16.reject.json-placeholder "$BAD_ETHICS_PLACEHOLDER_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_PLACEHOLDER_PROJ"

BAD_ETHICS_RESTRICTED_PUBLIC_PROJ="$TMP/bad-ethics-restricted-public-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_RESTRICTED_PUBLIC_PROJ"
printf '{"data_status":"existing-data","access_status":"restricted","irb_status":"exempt","source_type":"restricted human survey data","files":[{"path":"data/raw/example.csv","status":"restricted"}]}\n' > "$BAD_ETHICS_RESTRICTED_PUBLIC_PROJ/data/data-status.json"
python3 - "$BAD_ETHICS_RESTRICTED_PUBLIC_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
path = proj / "ethics/ethics-open-science.json"
report = json.loads(path.read_text())
report["source_hashes"]["data_status"] = hashlib.sha256((proj / "data/data-status.json").read_bytes()).hexdigest()
report["consent_status"]["status"] = "waived"
report["consent_status"]["statement"] = "Consent was waived for this restricted secondary-data fixture under the recorded exempt determination."
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.restricted-public-sharing
expect_reject l2.p16.reject.restricted-public-sharing "$BAD_ETHICS_RESTRICTED_PUBLIC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_RESTRICTED_PUBLIC_PROJ"

BAD_ETHICS_NO_AI_PROJ="$TMP/bad-ethics-no-ai-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_NO_AI_PROJ"
python3 - "$BAD_ETHICS_NO_AI_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["ai_disclosure"]["statement"] = "The authors did not use generative AI tools in preparing this manuscript. This placeholder denial is intentionally inconsistent with auto-research provenance and should not pass the Phase 15 verifier."
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.ai-denial
expect_reject l2.p16.reject.ai-denial "$BAD_ETHICS_NO_AI_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_NO_AI_PROJ"

BAD_ETHICS_EMPTY_TOOL_PROJ="$TMP/bad-ethics-empty-tool-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_EMPTY_TOOL_PROJ"
python3 - "$BAD_ETHICS_EMPTY_TOOL_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["ai_disclosure"]["tools"] = [{}]
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.ai-tool-record
expect_reject l2.p16.reject.ai-tool-record "$BAD_ETHICS_EMPTY_TOOL_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_EMPTY_TOOL_PROJ"

BAD_ETHICS_CONSENT_PROJ="$TMP/bad-ethics-consent-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_CONSENT_PROJ"
printf '{"data_status":"existing-data","access_status":"restricted","irb_status":"exempt","source_type":"restricted human interview data","files":[{"path":"data/raw/example.csv","status":"restricted"}]}\n' > "$BAD_ETHICS_CONSENT_PROJ/data/data-status.json"
python3 - "$BAD_ETHICS_CONSENT_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
path = proj / "ethics/ethics-open-science.json"
report = json.loads(path.read_text())
report["source_hashes"]["data_status"] = hashlib.sha256((proj / "data/data-status.json").read_bytes()).hexdigest()
report["data_availability"]["sharing_mode"] = "restricted-data-code-only"
report["data_availability"]["restriction_rationale"] = "Restricted interview data cannot be shared publicly."
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.consent-status
expect_reject l2.p16.reject.consent-status "$BAD_ETHICS_CONSENT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_CONSENT_PROJ"

BAD_ETHICS_MD_MISMATCH_PROJ="$TMP/bad-ethics-md-mismatch-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_MD_MISMATCH_PROJ"
printf '\nA critical unresolved conflict remains open despite the JSON pass status.\n' >> "$BAD_ETHICS_MD_MISMATCH_PROJ/ethics/ethics-open-science.md"
# CASE_ID: l2.p16.reject.markdown-contradiction
expect_reject l2.p16.reject.markdown-contradiction "$BAD_ETHICS_MD_MISMATCH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_MD_MISMATCH_PROJ"

BAD_ETHICS_CREDIT_ROLE_PROJ="$TMP/bad-ethics-credit-role-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_CREDIT_ROLE_PROJ"
python3 - "$BAD_ETHICS_CREDIT_ROLE_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["authorship_credit"]["credit_roles"] = ["Invalid Fixture Role"]
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p16.reject.credit-role-invalid
expect_reject l2.p16.reject.credit-role-invalid "$BAD_ETHICS_CREDIT_ROLE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_CREDIT_ROLE_PROJ"

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "16" ]]; then
  harness_validate_results --phase-through 16 >/dev/null
  progress "phases 0 to 16 authoritative harness assertions passed"
  exit 0
fi

REPLICATION_PROJ="$TMP/replication-project"
cp -R "$ETHICS_PROJ" "$REPLICATION_PROJ"
rm -rf "$REPLICATION_PROJ/replication-package"
mkdir -p "$REPLICATION_PROJ/replication-package"/{code,scripts,output/results-locked,logs}
python3 - "$REPLICATION_PROJ" <<'PY'
import hashlib
import json
import pathlib
import shutil
import sys

proj = pathlib.Path(sys.argv[1])
pkg = proj / "replication-package"

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def write(rel, text):
    path = proj / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path

def assemble_submission_from_final(text):
    allowed = {
        "abstract",
        "introduction",
        "background",
        "data and methods",
        "results",
        "discussion",
        "conclusion",
        "references",
        "tables",
        "figures",
        "ethics statement",
        "data availability",
        "ai use disclosure",
        "competing interests",
    }
    lines = []
    current_heading = None
    current_slug = None
    buffer = []
    title_written = False
    def flush():
        nonlocal lines, current_heading, current_slug, buffer
        if current_heading is None:
            return
        if current_slug in allowed:
            lines.extend([f"## {current_heading}", ""])
            lines.extend(buffer)
            if buffer and buffer[-1] != "":
                lines.append("")
        buffer = []
    for raw_line in text.splitlines():
        if raw_line.startswith("# ") and not title_written:
            lines.extend([raw_line, ""])
            title_written = True
            continue
        if title_written and current_heading is None and re.match(r"^Keywords?:\s+", raw_line, re.I):
            lines.extend([raw_line, ""])
            continue
        match = re.match(r"^##\s+(.+?)\s*$", raw_line)
        if match:
            flush()
            current_heading = match.group(1)
            current_slug = re.sub(r"[^a-z0-9]+", " ", current_heading.lower()).strip()
            continue
        if current_heading is not None:
            if "<!--" in raw_line or "results-locked/" in raw_line or "verify/" in raw_line or "logs/" in raw_line:
                continue
            buffer.append(raw_line)
    flush()
    assembled = "\n".join(lines).strip() + "\n"
    return re.sub(r"!\[([^\]]*)\]\((?:/Users/|/tmp/|/private/var/|/var/folders/|/home/|~)[^)]+\)", r"[\1 about here]", assembled)

lock_manifest_path = proj / "results-locked/manifest.json"
latest_path = proj / "results-locked/LATEST.txt"
stage1_path = proj / "verify/stage1-verify.json"
execution_path = proj / "analysis/execution-report.json"
ethics_path = proj / "ethics/ethics-open-science.json"
data_status_path = proj / "data/data-status.json"
lock = json.loads(lock_manifest_path.read_text())
execution = json.loads(execution_path.read_text())

readme = """# Replication Package

## Overview
This package reproduces the locked empirical outputs for the manuscript using public secondary data and packaged analysis scripts.

## Data Availability
The data availability mode is public-data-full. Public secondary data and derived analysis files are documented for replication.

## Dataset List
The package documents the analytic sample and the locked output files used in the manuscript.

## Computational Requirements
The package includes a requirements file, session information, and a master run script for the replication workflow.

## Description of Programs
The code directory contains a build-sample script and a model script. The scripts directory contains the run-all controller.

## Instructions to Replicators
Run bash scripts/run-all.sh from the replication package root, then compare generated outputs to the locked outputs.

## Output Correspondence
Every active locked artifact from the results lock is copied under output/results-locked and mapped in the replication report.

## Known Limitations
The fixture package is intentionally small but exercises the complete replication contract.

## References
References are inherited from the verified manuscript bibliography and citation audit.
"""
write("replication-package/README.md", readme)
write("replication-package/code/01_load_data.R", "# Purpose: load panel data\nset.seed(20260430)\nmessage('load data')\n")
write("replication-package/code/02_build_sample.R", "# Purpose: build analytic sample\nset.seed(20260430)\nmessage('sample built')\n")
write("replication-package/code/03_construct_variables.R", "# Purpose: construct analytic variables\nset.seed(20260430)\nmessage('variables constructed')\n")
write("replication-package/code/04_plan_models.R", "# Purpose: reproduce model outputs\nset.seed(20260430)\nmessage('models run')\n")
write("replication-package/scripts/run-all.sh", "#!/usr/bin/env bash\nset -euo pipefail\nRscript code/01_load_data.R\nRscript code/02_build_sample.R\nRscript code/03_construct_variables.R\nRscript code/04_plan_models.R\n")
write("replication-package/requirements.txt", "R>=4.3\n")
test_report = """# Clean Run Test Report

Overall verdict PASS.

Preflight checks passed for file existence, script syntax, path safety, and README completeness.
The isolated clean-room command log executed scripts/run-all.sh with zero exit codes.
Environment evidence used requirements.txt and recorded session information.
Output comparison covered every active locked artifact and all compared outputs matched the active results lock.
No unresolved failures, mismatches, or partial results remain.
"""
write("replication-package/TEST-REPORT.md", test_report)
verification_report = """# Paper To Code Verification Report

Overall verdict PASS.

All manuscript-facing tables, figures, output registries, and in-text locked result claims are mapped to packaged scripts or locked output files.
The active results lock coverage is complete and no manuscript-critical table, figure, statistic, or claim is unmapped.
Script coverage includes the sample-building and model scripts, and output correspondence links locked artifacts to package paths.
No orphaned critical outputs or unresolved mapping issues remain.
"""
write("replication-package/VERIFICATION-REPORT.md", verification_report)

coverage = []
for item in lock["locked_artifacts"]:
    source = item["source_path"]
    locked = item["locked_path"]
    package_path = "replication-package/output/" + locked
    dest = proj / package_path
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(proj / locked, dest)
    coverage.append({
        "source_path": source,
        "locked_path": locked,
        "package_path": package_path,
        "status": "copied",
        "sha256": sha(dest)
    })

write("replication-package/logs/run-all-summary.txt", "scripts/run-all.sh completed with zero exit codes and all locked outputs matched.\n")

def inventory_files():
    rels = sorted(str(path.relative_to(proj)) for path in pkg.rglob("*") if path.is_file())
    files = []
    for rel in rels:
        role = "documentation"
        if rel.endswith("replication-report.json") or rel.endswith("MANIFEST.json"):
            file_hash = "SELF_REFERENTIAL"
            role = "manifest"
        else:
            file_hash = sha(proj / rel)
        if "/code/" in rel:
            role = "code"
        elif "/scripts/" in rel:
            role = "run_script"
        elif "/output/" in rel:
            role = "locked_output"
        elif rel.endswith("requirements.txt"):
            role = "environment"
        elif rel.endswith("TEST-REPORT.md"):
            role = "test_report"
        elif rel.endswith("VERIFICATION-REPORT.md"):
            role = "verification_report"
        files.append({"path": rel, "role": role, "sha256": file_hash})
    return files

report_path = proj / "replication-package/replication-report.json"
manifest_path = proj / "replication-package/MANIFEST.json"
report_path.write_text("{}\n")
manifest_path.write_text('{"files":[]}\n')
files = inventory_files()
report = {
    "verdict": "PASS",
    "degraded": False,
    "source_phase": "17",
    "replication_engine": {
        "skill": "scholar-replication",
        "mode": "FULL",
        "task_invocation_id": "phase17-replication-001",
        "invoked_at_utc": "2026-04-30T14:00:00Z",
        "input_artifacts": [
            "results-locked/manifest.json",
            "analysis/execution-report.json",
            "ethics/ethics-open-science.json",
            "data/data-status.json"
        ],
        "output_artifacts": [
            "replication-package/replication-report.json",
            "replication-package/README.md"
        ]
    },
    "source_hashes": {
        "lock_manifest": sha(lock_manifest_path),
        "latest": sha(latest_path),
        "stage1_verify": sha(stage1_path),
        "execution_report": sha(execution_path),
        "ethics_open_science": sha(ethics_path),
        "data_status": sha(data_status_path)
    },
    "replication_mode": "public-data-full",
    "clean_room_verdict": "PASS",
    "reproduction_match": True,
    "restricted_data_rationale": "",
    "package_inventory": {
        "file_count": len(files),
        "files": files
    },
    "locked_artifact_coverage": {
        "lock_id": lock["lock_id"],
        "covered_artifacts": coverage
    },
    "script_coverage": {
        "scripts": [
            {
                "source_path": item["path"],
                "source_hash": item["script_hash"],
                "package_path": "replication-package/code/" + pathlib.Path(item["path"]).name,
                "syntax_check": "PASS",
                "produces": item.get("outputs", [])
            }
            for item in execution.get("executed_scripts", [])
        ],
        "executed_script_count": len(execution.get("executed_scripts", [])),
        "packaged_script_count": len(execution.get("executed_scripts", []))
    },
    "data_handling": {
        "mode": "public-data-full",
        "restricted_data_included": False,
        "synthetic_data_included": False
    },
    "path_safety": {
        "absolute_paths_found": False,
        "local_path_leaks_found": False
    },
    "environment": {
        "lockfile_present": True,
        "files": ["replication-package/requirements.txt"],
        "session_info": "R version and package requirements recorded for fixture replication."
    },
    "test_report": {
        "path": "replication-package/TEST-REPORT.md",
        "verdict": "PASS",
        "sha256": sha(proj / "replication-package/TEST-REPORT.md"),
        "command_log": "replication-package/logs/run-all-summary.txt"
    },
    "verification_report": {
        "path": "replication-package/VERIFICATION-REPORT.md",
        "verdict": "PASS",
        "sha256": sha(proj / "replication-package/VERIFICATION-REPORT.md"),
        "mapped_count": len(lock["locked_artifacts"]),
        "unmapped_count": 0
    },
    "findings": [],
    "fix_checklist": {
        "critical_fixes": [],
        "route_back": []
    },
    "route_back_phase": None,
    "ready_for_phase_18": True
}
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
manifest = {"files": files}
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.17.positive
expect_pass phase.17.positive "$REPLICATION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$REPLICATION_PROJ"

FAIL_REPLICATION_PROJ="$TMP/fail-replication-project"
cp -R "$REPLICATION_PROJ" "$FAIL_REPLICATION_PROJ"
python3 - "$FAIL_REPLICATION_PROJ/replication-package/replication-report.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["verdict"] = "FAIL"
report["ready_for_phase_18"] = False
report["route_back_phase"] = "11"
report["findings"] = [
    {
        "finding_id": "P16-F001",
        "severity": "CRITICAL",
        "category": "results_lock",
        "owner_phase": "11",
        "route_back_phase": "11",
        "detected_by": "scholar-replication",
        "affected_artifacts": ["results-locked/manifest.json", "replication-package/replication-report.json"],
        "required_fix": "Rebuild the active results lock and rerun the replication package assembly.",
        "status": "open"
    }
]
report["fix_checklist"] = {
    "critical_fixes": ["Rebuild the active results lock."],
    "route_back": ["11"]
}
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.17.negative
expect_reject phase.17.negative "$FAIL_REPLICATION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$FAIL_REPLICATION_PROJ"

ROUTE_STATE_16_PROJ="$TMP/route-state-16-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_16_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_16_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_16_PROJ/artifacts" "$ROUTE_STATE_16_PROJ/replication-package"
for pid in $(seq 0 16); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_16_PROJ/artifacts/phase-$pid.txt"
  complete_sm "$ROUTE_STATE_16_PROJ" "$pid" "$ROUTE_STATE_16_PROJ/artifacts/phase-$pid.txt"
done
cp "$FAIL_REPLICATION_PROJ/replication-package/replication-report.json" "$ROUTE_STATE_16_PROJ/replication-package/replication-report.json"
ROUTE_16_OUT="$(bash "$SCRIPT_DIR/auto-research-state.sh" route-back "$ROUTE_STATE_16_PROJ" "$ROUTE_STATE_16_PROJ/replication-package/replication-report.json")"
case "$ROUTE_16_OUT" in
  *"ROUTE_BACK_PHASE=11"*"INVALIDATED_PHASES=11,12,13,14,15,16"* ) ;;
  *) echo "FAIL: Phase 16 route-back should invalidate phases 11-16, got $ROUTE_16_OUT" >&2; exit 1 ;;
esac
python3 - "$ROUTE_STATE_16_PROJ/.auto-research/state.json" <<'PY'
import json
import pathlib
import sys
state = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = state.get("active_route_back", {}).get("source_phase")
if source != "17":
    raise SystemExit(f"FAIL: Phase 17 route-back source_phase should be 17, got {source}")
PY

BAD_REPLICATION_REPORT_PROJ="$TMP/bad-replication-report-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_REPORT_PROJ"
python3 - "$BAD_REPLICATION_REPORT_PROJ/replication-package/replication-report.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report.pop("verdict")
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p17.reject.report-schema
expect_reject l2.p17.reject.report-schema "$BAD_REPLICATION_REPORT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_REPORT_PROJ"

rebind_replication_readme_hashes() {
  local project="$1"
  python3 - "$project" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
readme_hash = hashlib.sha256((proj / "replication-package/README.md").read_bytes()).hexdigest()
for rel in ("replication-package/replication-report.json", "replication-package/MANIFEST.json"):
    path = proj / rel
    document = json.loads(path.read_text())
    files = document["package_inventory"]["files"] if rel.endswith("replication-report.json") else document["files"]
    item = next(row for row in files if row["path"] == "replication-package/README.md")
    item["sha256"] = readme_hash
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
PY
}

BAD_REPLICATION_README_PROJ="$TMP/bad-replication-readme-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_README_PROJ"
printf '\nTBD [Paper Title]\n' >> "$BAD_REPLICATION_README_PROJ/replication-package/README.md"
rebind_replication_readme_hashes "$BAD_REPLICATION_README_PROJ"
# CASE_ID: l2.p17.reject.readme-placeholder
expect_reject l2.p17.reject.readme-placeholder "$BAD_REPLICATION_README_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_README_PROJ"

BAD_REPLICATION_MANIFEST_PROJ="$TMP/bad-replication-manifest-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_MANIFEST_PROJ"
printf 'unlisted file\n' > "$BAD_REPLICATION_MANIFEST_PROJ/replication-package/unlisted.txt"
# CASE_ID: l2.p17.reject.manifest-coverage
expect_reject l2.p17.reject.manifest-coverage "$BAD_REPLICATION_MANIFEST_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_MANIFEST_PROJ"

BAD_REPLICATION_MODE_PROJ="$TMP/bad-replication-mode-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_MODE_PROJ"
python3 - "$BAD_REPLICATION_MODE_PROJ/replication-package/replication-report.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["replication_mode"] = "restricted-data-code-only"
report["data_handling"]["mode"] = "restricted-data-code-only"
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p17.reject.replication-mode
expect_reject l2.p17.reject.replication-mode "$BAD_REPLICATION_MODE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_MODE_PROJ"

BAD_REPLICATION_CLEAN_PROJ="$TMP/bad-replication-clean-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_CLEAN_PROJ"
python3 - "$BAD_REPLICATION_CLEAN_PROJ/replication-package/replication-report.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["clean_room_verdict"] = "FAIL"
report["reproduction_match"] = False
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p17.reject.clean-room
expect_reject l2.p17.reject.clean-room "$BAD_REPLICATION_CLEAN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_CLEAN_PROJ"

BAD_REPLICATION_LOCK_COVERAGE_PROJ="$TMP/bad-replication-lock-coverage-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_LOCK_COVERAGE_PROJ"
python3 - "$BAD_REPLICATION_LOCK_COVERAGE_PROJ/replication-package/replication-report.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["locked_artifact_coverage"]["covered_artifacts"] = report["locked_artifact_coverage"]["covered_artifacts"][:-1]
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p17.reject.lock-coverage
expect_reject l2.p17.reject.lock-coverage "$BAD_REPLICATION_LOCK_COVERAGE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_LOCK_COVERAGE_PROJ"

BAD_REPLICATION_SCRIPT_COVERAGE_PROJ="$TMP/bad-replication-script-coverage-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_SCRIPT_COVERAGE_PROJ"
python3 - "$BAD_REPLICATION_SCRIPT_COVERAGE_PROJ/replication-package/replication-report.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["script_coverage"]["scripts"] = report["script_coverage"]["scripts"][:-1]
report["script_coverage"]["packaged_script_count"] = len(report["script_coverage"]["scripts"])
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p17.reject.script-coverage
expect_reject l2.p17.reject.script-coverage "$BAD_REPLICATION_SCRIPT_COVERAGE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_SCRIPT_COVERAGE_PROJ"

BAD_REPLICATION_SCRIPT_HASH_PROJ="$TMP/bad-replication-script-hash-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_SCRIPT_HASH_PROJ"
python3 - "$BAD_REPLICATION_SCRIPT_HASH_PROJ/replication-package/replication-report.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["script_coverage"]["scripts"][0]["source_hash"] = "0" * 64
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p17.reject.script-hash
expect_reject l2.p17.reject.script-hash "$BAD_REPLICATION_SCRIPT_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_SCRIPT_HASH_PROJ"

BAD_REPLICATION_PATH_PROJ="$TMP/bad-replication-path-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_PATH_PROJ"
printf '\nLocal path leak: /Users/example/project/data.csv\n' >> "$BAD_REPLICATION_PATH_PROJ/replication-package/README.md"
rebind_replication_readme_hashes "$BAD_REPLICATION_PATH_PROJ"
# CASE_ID: l2.p17.reject.local-path
expect_reject l2.p17.reject.local-path "$BAD_REPLICATION_PATH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_PATH_PROJ"

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "17" ]]; then
  harness_validate_results --phase-through 17 >/dev/null
  progress "phases 0 to 17 authoritative harness assertions passed"
  exit 0
fi

QUALITY_PROJ="$TMP/quality-project"
cp -R "$REPLICATION_PROJ" "$QUALITY_PROJ"
mkdir -p "$QUALITY_PROJ/quality/agents"
python3 - "$QUALITY_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def write(rel, text):
    path = proj / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path

reviewers = [
    ("Q1", "methods-evidence", True, "MINOR_REVISION"),
    ("Q2", "theory-contribution", True, "MINOR_REVISION"),
    ("Q3", "senior-editor", False, "PROCEED_TO_FINAL_ASSEMBLY"),
    ("Q4", "interpretive-skeptic", True, "ACCEPT"),
    ("Q5", "survey-methods", True, "ACCEPT"),
]
dimensions = {
    "contribution": 8.2,
    "rq_answer": 8.4,
    "argument_coherence": 8.1,
    "theory_results_integration": 8.0,
    "limitation_candor": 8.3,
    "journal_fit": 8.1,
    "abstract_intro_discussion_consistency": 8.2,
    "substantive_conclusion_support": 8.3,
    "prose_quality": 8.0,
    "reviewer_consensus": 8.4,
}
role_to_agent = {
    "methods-evidence": "peer-reviewer-quant",
    "theory-contribution": "peer-reviewer-theory",
    "senior-editor": "peer-reviewer-senior",
    "interpretive-skeptic": "peer-reviewer-r2-skeptic",
    "survey-methods": "peer-reviewer-survey-methods",
}
reviewer_reports = []
# Improvement A (2026-05-03) — fixture must satisfy contribution_locator
# consensus. All four reviewers quote the same headline-contribution
# sentence so cross-reviewer Jaccard >= 0.7 holds for every pair.
contribution_sentence = (
    "The article contributes to family sociology by showing how economic "
    "instability can enter expectation formation while making uncertainty "
    "and design limits part of the substantive claim."
)
contribution_line_start = next(
    line_no for line_no, line in enumerate(
        (proj / "manuscript/manuscript-draft.md").read_text().splitlines(), start=1
    ) if contribution_sentence in line
)
# Improvement B (2026-05-03) — fixture lists rivals named in lit review
# AND addressed in discussion. missing_adjudications stays empty so the
# rival_consensus aggregate does not fire on a passing fixture.
rival_named = ["selection bias", "reverse causation"]
role_review_text = {
    "methods-evidence": (
        "The methods-evidence review checked Table 1, Figure 1, and the Data and Methods section. "
        "The main risk is that readers could overread the fixed-effects estimates as causal, but the draft repeatedly labels the design observational and keeps Model 2 as weaker robustness evidence. "
        "This reviewer found the regression table legible, the uncertainty reporting adequate, and the sample-size information visible."
    ),
    "theory-contribution": (
        "The theory-contribution review focused on the Background and Discussion sections rather than the mechanics of estimation. "
        "Its concern was whether family stress and status-attainment mechanisms were merely decorative; the review found that Table 1 is tied back to perceived educational feasibility and that rival compensation arguments are adjudicated. "
        "The remaining weakness is a transition-level issue, not an unsupported theoretical claim."
    ),
    "senior-editor": (
        "The senior-editor review used the Abstract, Introduction, Table 1, and Conclusion as the main locators. "
        "The desk-reject concern would be mismatch between the promised contribution and the actual evidence, but the manuscript presents a bounded family-sociology claim and preserves the observational limitation. "
        "The editor therefore treats remaining issues as copyediting concerns rather than route-back problems."
    ),
    "interpretive-skeptic": (
        "The interpretive-skeptic review stress-tested the Results paragraphs around Figure 1 and the Discussion limitation paragraph. "
        "The principal threat is a spun robustness story, because Model 2 is less precise than Model 1; the manuscript answers that concern by describing uneven robustness and refusing uniform confirmation language. "
        "The skeptic found no unsupported escalation after this check."
    ),
    "survey-methods": (
        "The survey-methods review checked the survey-data design, the Data and Methods section, and Table 1's regression layout. "
        "The key concern was whether model labels, standard errors, sample size, and design limitations were presented in a form empirical readers can audit. "
        "The review found that Model 1, Model 2, and Model 3 are reader-facing labels and that the regression table is not a registry extract."
    ),
}
for reviewer_id, role, primed, decision in reviewers:
    report_path = f"quality/agents/{reviewer_id.lower()}-{role}.md"
    task_id = f"fixture-task-{reviewer_id.lower()}"
    write(report_path, f"""# Reviewer {reviewer_id}: {role}

REVIEWER_ROLE: {role}
TASK_ID: {task_id}

{role_review_text[role]} The reviewer also inspected manuscript/manuscript-draft.md, verify/manuscript-verification.json, citation/claim-source-map.json, ethics/open-science report, and replication report. Decision: {decision}.

CONTRIBUTION LOCATOR
Quoted sentence: {contribution_sentence}

RIVAL ADJUDICATION
Rivals named in lit review: {", ".join(rival_named)}
Rivals adjudicated in discussion: {", ".join(rival_named)}
""")
    reviewer_reports.append({
        "reviewer_id": reviewer_id,
        "role": role,
        "agent_name": role_to_agent[role],
        "task_invocation_id": task_id,
        "report_path": report_path,
        "primed": primed,
        "reviewed_inputs": [
            "manuscript/manuscript-draft.md",
            "verify/manuscript-verification.json",
            "citation/claim-source-map.json",
            "ethics/ethics-open-science.json",
            "replication-package/replication-report.json"
        ],
        "score_vector": dimensions,
        "decision": decision,
        "findings": [],
        "contribution_locator": {
            "sentences": [contribution_sentence],
            "section": "abstract",
            "line_start": contribution_line_start,
            "clarity_score": 8,
            "specificity_score": 8,
            "notes": "Contribution is concrete and located in the abstract and discussion."
        },
        "rival_adjudication": {
            "rivals_in_lit_review": list(rival_named),
            "rivals_addressed_in_discussion": list(rival_named),
            "missing_adjudications": [],
            "adjudication_quality_score": 8,
            "notes": "Discussion engages each rival explanation explicitly."
        }
    })

quality_md = """# Manuscript Quality Gate

## Overall Verdict
PASS. The manuscript is ready to proceed to final assembly because the verified draft, citation support, ethics declarations, and replication package align with one another.

## Dimension Scores
The contribution, research-question answer, argument coherence, theory-results integration, limitation candor, journal fit, abstract introduction discussion consistency, substantive conclusion support, prose quality, and reviewer consensus all meet the required threshold. The mean score is above eight and every individual score is at least seven.

## Reviewer Consensus
Four independent reviewers evaluated the manuscript. The methods-evidence reviewer, theory-contribution reviewer, senior-editor reviewer, and interpretive-skeptic reviewer all found the paper publishable after only minor presentation refinements. The senior editor was unprimed, which protects the consensus from shared prompt contamination.

## Severity Confidence Matrix
No critical or major issue remains open. Minor comments were classified as presentation-level improvements and do not require a route back because they do not change manuscript claims, results, citations, ethics statements, or replication materials.

## Route Back
No route back is required. The decision is PROCEED_TO_FINAL_ASSEMBLY, and Phase 18 can assemble the same-source md, docx, tex, and pdf outputs from the verified manuscript.
"""
write("quality/manuscript-quality.md", quality_md)

quality = {
    "verdict": "PASS",
    "degraded": False,
    "source_phase": "18",
    "quality_engine": {
        "skill": "scholar-respond",
        "mode": "simulate",
        "borrowed_practices": ["journal-aware panel", "independent reviewers", "severity-confidence matrix"],
        "task_invocation_id": "phase18-quality-001",
        "invoked_at_utc": "2026-04-30T15:00:00Z",
        "input_artifacts": [
            "manuscript/manuscript-draft.md",
            "verify/manuscript-verification.json",
            "citation/citation-audit.json",
            "ethics/ethics-open-science.json",
            "replication-package/replication-report.json"
        ],
        "output_artifacts": ["quality/manuscript-quality.json", "quality/manuscript-quality.md"]
    },
    "selected_manuscript_hash": sha(proj / "manuscript/manuscript-draft.md"),
    "source_hashes": {
        "research_question": sha(proj / "idea/research-question.json"),
        "manuscript": sha(proj / "manuscript/manuscript-draft.md"),
        "draft_manifest": sha(proj / "manuscript/draft-manifest.json"),
        "polish_report": sha(proj / "manuscript/polish-report.json"),
        "manuscript_verification": sha(proj / "verify/manuscript-verification.json"),
        "citation_audit": sha(proj / "citation/citation-audit.json"),
        "claim_source_map": sha(proj / "citation/claim-source-map.json"),
        "ethics_open_science": sha(proj / "ethics/ethics-open-science.json"),
        "replication_report": sha(proj / "replication-package/replication-report.json")
    },
    "reviewer_reports": reviewer_reports,
    "reviewer_independence": {
        "status": "PASS",
        "duplicate_report_count": 0,
        "task_invocation_ids_unique": True,
        "report_paths_unique": True,
        "unprimed_senior_editor_present": True
    },
    "adversarial_review_coverage": {
        "status": "PASS",
        "all_reports_have_concrete_locator": True,
        "all_reports_have_risk_or_robustness_issue": True,
        "risk_domains_covered": ["methods", "theory", "editorial", "interpretation", "survey design"]
    },
    "method_specialist_review": {
        "status": "PASS",
        "reviewer_id": "Q5",
        "role": "survey-methods",
        "method_family": "structured_secondary_data",
        "covered_secondary_data_design": True,
        "covered_model_specification": True,
        "covered_regression_table_reporting": True
    },
    "regression_table_audit": {
        "status": "PASS",
        "canonical_main_regression_table_present": True,
        "registry_table_used_as_main_display": False,
        "model_columns_as_columns": True,
        "predictor_rows_as_rows": True,
        "standard_errors_or_intervals_present": True,
        "sample_size_present": True,
        "reader_facing_labels_used": True,
        "notes_cover_design_features": True
    },
    "dimension_scores": dimensions,
    "threshold_policy": {
        "min_dimension_score": 7,
        "mean_score_min": 8,
        "non_overridable_blockers": []
    },
    "severity_confidence_matrix": [
        {
            "issue_id": "Q-MINOR-001",
            "issue": "Tighten one transition in the Discussion during final copyediting.",
            "severity": "MINOR",
            "confidence": "MEDIUM",
            "raised_by": ["Q3"],
            "status": "accepted_nonblocking"
        }
    ],
    "polish_audit": {
        "skill": "scholar-polish",
        "mode": "scan",
        "task_invocation_id": "phase18-polish-scan-001",
        "invoked_at_utc": "2026-04-30T15:20:00Z",
        "input_artifacts": ["manuscript/manuscript-draft.md"],
        "output_artifacts": ["quality/manuscript-quality.json", "quality/manuscript-quality.md"],
        "manuscript_hash": sha(proj / "manuscript/manuscript-draft.md"),
        "rewrite_applied": False,
        "high_severity_markers": 0,
        "medium_severity_markers": 0,
        "route_back_required": False,
        "patterns_checked": [
            "generic_hedging_stacks",
            "formulaic_transitions",
            "over_enumeration",
            "generic_AI_prose_markers"
        ]
    },
    "decision": {
        "editorial_recommendation": "PROCEED_TO_FINAL_ASSEMBLY",
        "overall_score": 8.2,
        "journal_fit": "suitable"
    },
    "findings": [],
    "fix_checklist": {
        "critical_fixes": [],
        "route_back": []
    },
    "route_back_phase": None,
    "ready_for_phase_19": True
}
write("quality/manuscript-quality.json", json.dumps(quality, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p18.reject.missing-review-evidence
expect_reject l2.p18.reject.missing-review-evidence "$QUALITY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$QUALITY_PROJ"

prepare_phase18_method_family_fixture() {
  local project="$1"
  local method_orientation="$2"
  local include_specialist="$3"
  local specialist_role="${4:-survey-methods}"
  local specialist_family="${5:-structured_secondary_data}"
  cp -R "$QUALITY_PROJ" "$project"
  python3 - "$project" "$method_orientation" "$include_specialist" "$specialist_role" "$specialist_family" <<'PY'
import hashlib
import json
import pathlib
import sys

project = pathlib.Path(sys.argv[1])
method_orientation = sys.argv[2]
include_specialist = sys.argv[3] == "1"
specialist_role = sys.argv[4]
specialist_family = sys.argv[5]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load(relative):
    return json.loads((project / relative).read_text())

def write(relative, document):
    (project / relative).write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")

rq_path = project / "idea/research-question.json"
rq = load("idea/research-question.json")
rq["method_orientation"] = method_orientation
write("idea/research-question.json", rq)

# Preserve the real prerequisite chain: changing the authoritative RQ changes
# each downstream document that binds an upstream document by digest.
blueprint_path = project / "manuscript/manuscript-blueprint.json"
blueprint = load("manuscript/manuscript-blueprint.json")
blueprint["source_hashes"]["research_question"] = sha(rq_path)
write("manuscript/manuscript-blueprint.json", blueprint)

draft_manifest_path = project / "manuscript/draft-manifest.json"
draft_manifest = load("manuscript/draft-manifest.json")
draft_manifest["source_hashes"]["research_question"] = sha(rq_path)
draft_manifest["source_hashes"]["manuscript_blueprint"] = sha(blueprint_path)
draft_manifest["blueprint"]["sha256"] = sha(blueprint_path)
write("manuscript/draft-manifest.json", draft_manifest)

verification_path = project / "verify/manuscript-verification.json"
verification = load("verify/manuscript-verification.json")
verification["source_hashes"]["draft_manifest"] = sha(draft_manifest_path)
verification["blueprint_hashes"]["manuscript_blueprint"] = sha(blueprint_path)
for agent in verification["agents"]:
    agent["input_hashes"]["draft_manifest"] = sha(draft_manifest_path)
write("verify/manuscript-verification.json", verification)

citation_path = project / "citation/citation-audit.json"
citation = load("citation/citation-audit.json")
citation["source_hashes"]["draft_manifest"] = sha(draft_manifest_path)
citation["source_hashes"]["phase13_verification"] = sha(verification_path)
write("citation/citation-audit.json", citation)

ethics_path = project / "ethics/ethics-open-science.json"
ethics = load("ethics/ethics-open-science.json")
ethics["source_hashes"]["draft_manifest"] = sha(draft_manifest_path)
ethics["source_hashes"]["citation_audit"] = sha(citation_path)
write("ethics/ethics-open-science.json", ethics)

replication_path = project / "replication-package/replication-report.json"
replication = load("replication-package/replication-report.json")
replication["source_hashes"]["ethics_open_science"] = sha(ethics_path)
write("replication-package/replication-report.json", replication)

quality_path = project / "quality/manuscript-quality.json"
quality = load("quality/manuscript-quality.json")
quality["source_hashes"]["research_question"] = sha(rq_path)
quality["source_hashes"]["draft_manifest"] = sha(draft_manifest_path)
quality["source_hashes"]["manuscript_verification"] = sha(verification_path)
quality["source_hashes"]["citation_audit"] = sha(citation_path)
quality["source_hashes"]["ethics_open_science"] = sha(ethics_path)
quality["source_hashes"]["replication_report"] = sha(replication_path)
if not include_specialist:
    quality["reviewer_reports"] = [
        reviewer for reviewer in quality["reviewer_reports"]
        if reviewer.get("reviewer_id") != "Q5"
    ]
    quality["method_specialist_review"] = {"status": "NOT_APPLICABLE"}
else:
    specialist = next(
        reviewer for reviewer in quality["reviewer_reports"]
        if reviewer.get("reviewer_id") == "Q5"
    )
    specialist["role"] = specialist_role
    specialist["agent_name"] = f"peer-reviewer-{specialist_role}"
    specialist["report_path"] = f"quality/agents/q5-{specialist_role}.md"
    report = project / specialist["report_path"]
    report.write_text(
        f"# Reviewer Q5: {specialist_role}\n\n"
        f"REVIEWER_ROLE: {specialist_role}\nTASK_ID: {specialist['task_invocation_id']}\n\n"
        f"This {specialist_family} specialist review inspected the Data and Methods section, "
        "Table 1, Figure 1, and the limitation paragraph in the Discussion. The central "
        f"risk for the declared {specialist_family} orientation is that a reader could infer "
        "more design certainty than the observed evidence supports. The review therefore "
        "checked model labels, uncertainty reporting, sample-size disclosure, robustness "
        "language, and the boundary between the empirical pattern and the manuscript's "
        "substantive interpretation. Table 1 preserves reader-facing model labels and the "
        "Results section describes Model 2 as weaker evidence instead of uniform confirmation. "
        "The Discussion also retains the observational limitation and identifies selection "
        "bias and reverse causation as rival explanations.\n\n"
        "CONTRIBUTION LOCATOR\n"
        "The Abstract and Discussion state that economic instability can enter expectation "
        "formation while uncertainty and design limits remain part of the substantive claim.\n\n"
        "RIVAL ADJUDICATION\n"
        "Selection bias and reverse causation are named in the literature discussion and "
        "revisited in the limitations. The family-specific review found no unsupported claim "
        "escalation, but it recommends preserving those caveats in every final format. "
        "Decision: ACCEPT.\n"
    )
    quality["method_specialist_review"].update({
        "role": specialist_role,
        "method_family": specialist_family,
    })
write("quality/manuscript-quality.json", quality)
PY
  # Phase 14's registered review session binds draft-manifest bytes. Renew it
  # after the legitimate hash-chain update rather than weakening its evidence.
  local old_phase14_session
  old_phase14_session="$(python3 - "$project/verify/manuscript-verification.json" <<'PY'
import json
import sys
document = json.load(open(sys.argv[1], encoding="utf-8"))
print(document["review_evidence"]["rounds"]["verification_panel"]["session_id"])
PY
)"
  bash "$SCRIPT_DIR/auto-research-state.sh" review-abort "$project" 14 "$old_phase14_session" \
    --reason "fixture authoritative research question changed; renew dependent verification evidence" >/dev/null
  python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$project" 14 verification_panel >/dev/null
  # Registration writes the new Phase 14 evidence binding into the canonical
  # verification JSON, so propagate that final byte digest through 15–18.
  python3 - "$project" <<'PY'
import hashlib
import json
import pathlib
import sys

project = pathlib.Path(sys.argv[1])

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def update(relative, edits):
    path = project / relative
    document = json.loads(path.read_text())
    edits(document)
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")

verification_path = project / "verify/manuscript-verification.json"
citation_path = project / "citation/citation-audit.json"
ethics_path = project / "ethics/ethics-open-science.json"
replication_path = project / "replication-package/replication-report.json"

update("citation/citation-audit.json", lambda document: document["source_hashes"].update({
    "phase13_verification": sha(verification_path),
}))
def update_ethics(document):
    document["source_hashes"]["citation_audit"] = sha(citation_path)
    expected = {
        "citation/citation-audit.json": sha(citation_path),
        "manuscript/draft-manifest.json": sha(project / "manuscript/draft-manifest.json"),
    }
    for artifact in document["integrity_review"]["checked_artifacts"]:
        if artifact.get("path") in expected:
            artifact["sha256"] = expected[artifact["path"]]

update("ethics/ethics-open-science.json", update_ethics)
update("replication-package/replication-report.json", lambda document: document["source_hashes"].update({
    "ethics_open_science": sha(ethics_path),
}))
update("quality/manuscript-quality.json", lambda document: document["source_hashes"].update({
    "manuscript_verification": sha(verification_path),
    "citation_audit": sha(citation_path),
    "ethics_open_science": sha(ethics_path),
    "replication_report": sha(replication_path),
}))
PY
}

# Phase 18's specialist requirement is routed from the authoritative Phase 1
# method_orientation, not only inferred from whether the final manuscript
# happens to contain survey/secondary-data vocabulary. Exercise every family
# that requires a fifth specialist with both sides of the boundary.
while IFS='|' read -r family method_orientation specialist_role specialist_family; do
  FOUR_ROLE_PROJ="$TMP/quality-${family}-four-role-project"
  prepare_phase18_method_family_fixture "$FOUR_ROLE_PROJ" "$method_orientation" 0 \
    "$specialist_role" "$specialist_family"
  python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$FOUR_ROLE_PROJ" 18 adversarial_panel >/dev/null
  case "$family" in
    computational)
      # CASE_ID: f20.p18.reject.computational-four-role
      expect_reject f20.p18.reject.computational-four-role "$FOUR_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FOUR_ROLE_PROJ"
      ;;
    qualitative)
      # CASE_ID: f20.p18.reject.qualitative-four-role
      expect_reject f20.p18.reject.qualitative-four-role "$FOUR_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FOUR_ROLE_PROJ"
      ;;
    linguistic)
      # CASE_ID: f20.p18.reject.linguistic-four-role
      expect_reject f20.p18.reject.linguistic-four-role "$FOUR_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FOUR_ROLE_PROJ"
      ;;
    mixed-methods)
      # CASE_ID: f20.p18.reject.mixed-methods-four-role
      expect_reject f20.p18.reject.mixed-methods-four-role "$FOUR_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FOUR_ROLE_PROJ"
      ;;
    demographic)
      # CASE_ID: f20.p18.reject.demographic-four-role
      expect_reject f20.p18.reject.demographic-four-role "$FOUR_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FOUR_ROLE_PROJ"
      ;;
  esac

  FIVE_ROLE_PROJ="$TMP/quality-${family}-five-role-project"
  prepare_phase18_method_family_fixture "$FIVE_ROLE_PROJ" "$method_orientation" 1 \
    "$specialist_role" "$specialist_family"
  python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$FIVE_ROLE_PROJ" 18 adversarial_panel \
    --extra-role "$specialist_role" >/dev/null
  case "$family" in
    computational)
      # CASE_ID: f20.p18.accept.computational-five-role
      expect_pass f20.p18.accept.computational-five-role "$FIVE_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FIVE_ROLE_PROJ"
      ;;
    qualitative)
      # CASE_ID: f20.p18.accept.qualitative-five-role
      expect_pass f20.p18.accept.qualitative-five-role "$FIVE_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FIVE_ROLE_PROJ"
      ;;
    linguistic)
      # CASE_ID: f20.p18.accept.linguistic-five-role
      expect_pass f20.p18.accept.linguistic-five-role "$FIVE_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FIVE_ROLE_PROJ"
      ;;
    mixed-methods)
      # CASE_ID: f20.p18.accept.mixed-methods-five-role
      expect_pass f20.p18.accept.mixed-methods-five-role "$FIVE_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FIVE_ROLE_PROJ"
      ;;
    demographic)
      # CASE_ID: f20.p18.accept.demographic-five-role
      expect_pass f20.p18.accept.demographic-five-role "$FIVE_ROLE_PROJ" -- \
        bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FIVE_ROLE_PROJ"
      ;;
  esac
done <<'EOF'
computational|computational text-as-data analysis|computational-methods|computational
qualitative|qualitative interview study|qualitative-methods|qualitative
linguistic|sociolinguistic variation analysis|linguistic-methods|linguistic
mixed-methods|mixed-methods survey plus interview design|mixed-methods|mixed_methods
demographic|demographic event-history analysis|demographic-family-methods|demographic
EOF

verify_phase18_with_detail() {
  local project="$1"
  local required_detail="$2"
  local output rc
  if output="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$project" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$output" >&2
  printf '%s\n' "$output" | grep -Fx "  - $required_detail" >/dev/null || return 97
  return "$rc"
}

MISMATCH_ROLE_PROJ="$TMP/quality-computational-mismatched-specialist-project"
prepare_phase18_method_family_fixture "$MISMATCH_ROLE_PROJ" \
  "computational text-as-data analysis" 1 survey-methods computational
python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$MISMATCH_ROLE_PROJ" 18 adversarial_panel \
  --extra-role survey-methods >/dev/null
# CASE_ID: f20.p18.reject.computational-specialist-mismatch
expect_reject f20.p18.reject.computational-specialist-mismatch "$MISMATCH_ROLE_PROJ" -- \
  verify_phase18_with_detail "$MISMATCH_ROLE_PROJ" computational-methods

python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$QUALITY_PROJ" 18 adversarial_panel --extra-role survey-methods >/dev/null
# CASE_ID: phase.18.positive
expect_pass phase.18.positive "$QUALITY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$QUALITY_PROJ"

FAIL_QUALITY_PROJ="$TMP/fail-quality-project"
cp -R "$QUALITY_PROJ" "$FAIL_QUALITY_PROJ"
python3 - "$FAIL_QUALITY_PROJ/quality/manuscript-quality.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
quality = json.loads(path.read_text())
quality["verdict"] = "FAIL"
quality["ready_for_phase_19"] = False
quality["route_back_phase"] = "12"
quality["findings"] = [
    {
        "finding_id": "P17-F001",
        "severity": "MAJOR",
        "category": "argument_coherence",
        "owner_phase": "12",
        "route_back_phase": "12",
        "detected_by": "scholar-respond",
        "affected_artifacts": ["manuscript/manuscript-draft.md:Introduction", "manuscript/manuscript-draft.md:Discussion"],
        "required_fix": "Revise the manuscript argument so the Introduction, Results, and Discussion answer the same research question.",
        "status": "open"
    }
]
quality["fix_checklist"] = {
    "critical_fixes": ["Revise the argument through Phase 12 and rerun downstream gates."],
    "route_back": ["12"]
}
path.write_text(json.dumps(quality, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.18.negative
expect_reject phase.18.negative "$FAIL_QUALITY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FAIL_QUALITY_PROJ"

ROUTE_STATE_17_PROJ="$TMP/route-state-17-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_17_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_17_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_17_PROJ/artifacts" "$ROUTE_STATE_17_PROJ/quality"
for pid in $(seq 0 17); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_17_PROJ/artifacts/phase-$pid.txt"
  complete_sm "$ROUTE_STATE_17_PROJ" "$pid" "$ROUTE_STATE_17_PROJ/artifacts/phase-$pid.txt"
done
cp "$FAIL_QUALITY_PROJ/quality/manuscript-quality.json" "$ROUTE_STATE_17_PROJ/quality/manuscript-quality.json"
ROUTE_17_OUT="$(bash "$SCRIPT_DIR/auto-research-state.sh" route-back "$ROUTE_STATE_17_PROJ" "$ROUTE_STATE_17_PROJ/quality/manuscript-quality.json")"
case "$ROUTE_17_OUT" in
  *"ROUTE_BACK_PHASE=12"*"INVALIDATED_PHASES=12,13,14,15,16,17"* ) ;;
  *) echo "FAIL: Phase 17 route-back should invalidate phases 12-17, got $ROUTE_17_OUT" >&2; exit 1 ;;
esac
python3 - "$ROUTE_STATE_17_PROJ/.auto-research/state.json" <<'PY'
import json
import pathlib
import sys
state = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = state.get("active_route_back", {}).get("source_phase")
if source != "18":
    raise SystemExit(f"FAIL: Phase 18 route-back source_phase should be 18, got {source}")
PY

BAD_QUALITY_REPORT_PROJ="$TMP/bad-quality-report-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_REPORT_PROJ"
python3 - "$BAD_QUALITY_REPORT_PROJ/quality/manuscript-quality.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
quality = json.loads(path.read_text())
quality.pop("verdict")
path.write_text(json.dumps(quality, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p18.reject.report-schema
expect_reject l2.p18.reject.report-schema "$BAD_QUALITY_REPORT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_REPORT_PROJ"

BAD_QUALITY_LOW_SCORE_PROJ="$TMP/bad-quality-low-score-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_LOW_SCORE_PROJ"
python3 - "$BAD_QUALITY_LOW_SCORE_PROJ/quality/manuscript-quality.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
quality = json.loads(path.read_text())
quality["dimension_scores"]["rq_answer"] = 6.5
path.write_text(json.dumps(quality, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p18.reject.low-score
expect_reject l2.p18.reject.low-score "$BAD_QUALITY_LOW_SCORE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_LOW_SCORE_PROJ"

BAD_QUALITY_POLISH_PROJ="$TMP/bad-quality-polish-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_POLISH_PROJ"
python3 - "$BAD_QUALITY_POLISH_PROJ/quality/manuscript-quality.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
quality = json.loads(path.read_text())
quality["polish_audit"]["high_severity_markers"] = 1
quality["polish_audit"]["route_back_required"] = True
path.write_text(json.dumps(quality, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p18.reject.polish-audit
expect_reject l2.p18.reject.polish-audit "$BAD_QUALITY_POLISH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_POLISH_PROJ"

BAD_QUALITY_HASH_PROJ="$TMP/bad-quality-hash-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_HASH_PROJ"
python3 - "$BAD_QUALITY_HASH_PROJ/quality/manuscript-quality.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
quality = json.loads(path.read_text())
quality["source_hashes"]["manuscript"] = "0" * 64
path.write_text(json.dumps(quality, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p18.reject.source-hash
expect_reject l2.p18.reject.source-hash "$BAD_QUALITY_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_HASH_PROJ"

BAD_QUALITY_REVIEWER_PROJ="$TMP/bad-quality-reviewer-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_REVIEWER_PROJ"
python3 - "$BAD_QUALITY_REVIEWER_PROJ/quality/manuscript-quality.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
quality = json.loads(path.read_text())
quality["reviewer_reports"] = [r for r in quality["reviewer_reports"] if r["role"] != "interpretive-skeptic"]
path.write_text(json.dumps(quality, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p18.reject.reviewer-role-binding
expect_reject l2.p18.reject.reviewer-role-binding "$BAD_QUALITY_REVIEWER_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_REVIEWER_PROJ"

BAD_QUALITY_REVIEWER_TASK_PROJ="$TMP/bad-quality-reviewer-task-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_REVIEWER_TASK_PROJ"
python3 - "$BAD_QUALITY_REVIEWER_TASK_PROJ/quality/manuscript-quality.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
quality = json.loads(path.read_text())
quality["reviewer_reports"][1]["task_invocation_id"] = quality["reviewer_reports"][0]["task_invocation_id"]
path.write_text(json.dumps(quality, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p18.reject.reviewer-task-binding
expect_reject l2.p18.reject.reviewer-task-binding "$BAD_QUALITY_REVIEWER_TASK_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_REVIEWER_TASK_PROJ"

BAD_QUALITY_REVIEWER_FILE_PROJ="$TMP/bad-quality-reviewer-file-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_REVIEWER_FILE_PROJ"
python3 - "$BAD_QUALITY_REVIEWER_FILE_PROJ" <<'PY'
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
quality = json.loads((proj / "quality/manuscript-quality.json").read_text())
report_path = proj / quality["reviewer_reports"][0]["report_path"]
report_path.write_text("This file omits the required reviewer role and task id provenance tokens.\n")
PY
# CASE_ID: l2.p18.reject.reviewer-report-digest
expect_reject l2.p18.reject.reviewer-report-digest "$BAD_QUALITY_REVIEWER_FILE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_REVIEWER_FILE_PROJ"

BAD_QUALITY_BLOCKER_PROJ="$TMP/bad-quality-blocker-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_BLOCKER_PROJ"
python3 - "$BAD_QUALITY_BLOCKER_PROJ/quality/manuscript-quality.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
quality = json.loads(path.read_text())
quality["threshold_policy"]["non_overridable_blockers"] = ["unsupported empirical claim"]
path.write_text(json.dumps(quality, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p18.reject.non-overridable-blocker
expect_reject l2.p18.reject.non-overridable-blocker "$BAD_QUALITY_BLOCKER_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_BLOCKER_PROJ"

BAD_QUALITY_MD_PROJ="$TMP/bad-quality-md-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_MD_PROJ"
printf '# Quality\n\nPASS.\n' > "$BAD_QUALITY_MD_PROJ/quality/manuscript-quality.md"
# CASE_ID: l2.p18.reject.markdown-sections
expect_reject l2.p18.reject.markdown-sections "$BAD_QUALITY_MD_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_MD_PROJ"

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "18" ]]; then
  harness_validate_results --phase-through 18 >/dev/null
  progress "phases 0 to 18 authoritative harness assertions passed"
  exit 0
fi

FINAL_PROJ="$TMP/final-project"
progress "phases 19 to 20 final assembly, submission, and state fixtures"
cp -R "$QUALITY_PROJ" "$FINAL_PROJ"
mkdir -p "$FINAL_PROJ/final"
python3 - "$FINAL_PROJ" <<'PY'
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import zipfile

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def write(rel, data, binary=False):
    path = proj / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    if binary:
        path.write_bytes(data)
    else:
        path.write_text(data)
    return path

source_md = (proj / "manuscript/manuscript-draft.md").read_text()
rendered_md = re.sub(r"\[@work(\d{2})\]", lambda m: f"(Author {int(m.group(1))}, 20{int(m.group(1)) % 20:02d})", source_md)

def normalize_front_matter_keywords(text):
    keyword_match = re.search(r"(?m)^Keywords:\s*.+\n?", text)
    if not keyword_match:
        return text
    keyword_line = keyword_match.group(0).strip()
    text = text[:keyword_match.start()] + text[keyword_match.end():]
    text = re.sub(r"\n{3,}", "\n\n", text, count=1)
    introduction_match = re.search(r"(?m)^## Introduction\s*$", text)
    if introduction_match:
        text = (
            text[:introduction_match.start()].rstrip()
            + f"\n{keyword_line}\n\n"
            + text[introduction_match.start():]
        )
    return text

descriptive_table_block = "\n".join([
    "Table 1. Descriptive statistics for modeled variables in the analytic sample.",
    "",
    "| Variable | Coding or scale | Mean / percent | N |",
    "| --- | --- | ---: | ---: |",
    "| Adolescent educational expectations | Ordered expected schooling scale | 4.20 | 1200 |",
    "| Parental job loss | Binary indicator, 1 = job loss | 0.18 | 1200 |",
    "| Child age | Continuous years | 15.10 | 1200 |",
    "| Survey wave | Categorical wave indicators | -- | 1200 |",
    "| Household income | Continuous household income | 52,300 | 1200 |",
    "Notes: Table 1 reports reader-facing descriptive statistics for every variable used in the modeled specifications."
])
table_block = "\n".join([
    "<!-- DISPLAY_TABLE: tables/regression-main.html -->",
    "Table 2. Regression estimates for parental job loss and adolescent educational expectations.",
    "",
    "| Predictor | Model 1 | Model 2 | Model 3 |",
    "| --- | ---: | ---: | ---: |",
    "| Parental job loss | -0.120 (0.040) | -0.080 (0.050) | -0.090 (0.045) |",
    "| p-value | 0.003 | 0.110 | 0.046 |",
    "| N | 1200 | 1200 | 1200 |",
])
figure_block = "\n".join([
    "<!-- DISPLAY_FIGURE: figures/event-study.png -->",
    "Figure 1. Event-study diagnostic figure.",
    "",
    "![Figure 1. Event-study diagnostic figure](figures/event-study.png)",
])
rendered_md = rendered_md.replace(descriptive_table_block + "\n\n", "", 1).replace(table_block + "\n\n", "", 1).replace("\n\n" + figure_block + "\n\n", "\n\n", 1)
rendered_md = normalize_front_matter_keywords(rendered_md)
references = "\n".join(
    f"Author {i}. 20{i % 20:02d}. Title {i}. *Journal of Family Research* {i % 9 + 1}(1): {100 + i}-{110 + i}."
    for i in range(1, 31)
)
final_md = rendered_md + f"""

## References
{references}

## Tables
{descriptive_table_block}

{table_block}

## Figures
{figure_block}

## Ethics Statement
This study uses public secondary data and was classified as exempt in the ethics and open-science report.

## Data Availability
The data availability mode is public-data-full and the replication package documents the code and analysis outputs.

## AI Use Disclosure
AI-assisted coding and writing tools supported code checks, format checks, and non-substantive drafting under human review, as documented in the ethics report.

## Competing Interests
The authors declare no competing interests.
"""
write("final/manuscript-final.md", final_md)
(proj / "final/figures").mkdir(parents=True, exist_ok=True)
(proj / "final/figures/event-study.png").write_bytes((proj / "figures/event-study.png").read_bytes())

for extension, extra in (("docx", []), ("tex", []), ("pdf", ["--pdf-engine=xelatex"])):
    subprocess.run(
        ["pandoc", "-s", "final/manuscript-final.md", "-o",
         f"final/manuscript-final.{extension}", *extra],
        check=True, cwd=proj,
    )
journal_profile_resolution = json.loads((proj / "manuscript/manuscript-blueprint.json").read_text())["journal_profile_resolution"]
version_id = "2026-04-30T153012Z-v001"
created_at_utc = "2026-04-30T15:30:12Z"
write("final/LATEST.txt", version_id + "\n")
version_dir = proj / "final" / "versions" / version_id
version_dir.mkdir(parents=True, exist_ok=True)
versioned = {
    "md": f"final/versions/{version_id}/manuscript-final-{version_id}.md",
    "docx": f"final/versions/{version_id}/manuscript-final-{version_id}.docx",
    "tex": f"final/versions/{version_id}/manuscript-final-{version_id}.tex",
    "pdf": f"final/versions/{version_id}/manuscript-final-{version_id}.pdf",
    "manifest": f"final/versions/{version_id}/final-manifest-{version_id}.json",
}
for ext, src in {
    "md": "final/manuscript-final.md",
    "docx": "final/manuscript-final.docx",
    "tex": "final/manuscript-final.tex",
    "pdf": "final/manuscript-final.pdf",
}.items():
    (proj / versioned[ext]).write_bytes((proj / src).read_bytes())

manifest = {
    "verdict": "PASS",
    "degraded": False,
    "source_phase": "19",
    "assembly_engine": {
        "name": "pandoc",
        "mode": "same-source-final-assembly",
        "fallback_used": False
    },
    "journal_profile_resolution": journal_profile_resolution,
    "version_id": version_id,
    "created_at_utc": created_at_utc,
    "source_hashes": {
        "manuscript": sha(proj / "manuscript/manuscript-draft.md"),
        "draft_manifest": sha(proj / "manuscript/draft-manifest.json"),
        "quality_report": sha(proj / "quality/manuscript-quality.json"),
        "quality_markdown": sha(proj / "quality/manuscript-quality.md"),
        "references_bib": sha(proj / "citation/references.bib"),
        "citation_audit": sha(proj / "citation/citation-audit.json"),
        "claim_source_map": sha(proj / "citation/claim-source-map.json"),
        "ethics_open_science": sha(proj / "ethics/ethics-open-science.json"),
        "replication_report": sha(proj / "replication-package/replication-report.json")
    },
    "source_manuscript_path": "manuscript/manuscript-draft.md",
    "source_manuscript_hash": sha(proj / "manuscript/manuscript-draft.md"),
    "output_paths": {
        "md": "final/manuscript-final.md",
        "docx": "final/manuscript-final.docx",
        "tex": "final/manuscript-final.tex",
        "pdf": "final/manuscript-final.pdf"
    },
    "versioned_output_paths": versioned,
    "output_hashes": {
        "md": sha(proj / "final/manuscript-final.md"),
        "docx": sha(proj / "final/manuscript-final.docx"),
        "tex": sha(proj / "final/manuscript-final.tex"),
        "pdf": sha(proj / "final/manuscript-final.pdf")
    },
    "versioned_output_hashes": {
        "md": sha(proj / versioned["md"]),
        "docx": sha(proj / versioned["docx"]),
        "tex": sha(proj / versioned["tex"]),
        "pdf": sha(proj / versioned["pdf"]),
        "manifest": "SELF_REFERENTIAL"
    },
    "same_source": {
        "source_md_path": "final/manuscript-final.md",
        "source_md_sha256": sha(proj / "final/manuscript-final.md"),
        "shared_stem": "final/manuscript-final",
        "all_formats_from_source_md": True
    },
    "format_generation": {
        "docx": {"status": "PASS", "source_md_sha256": sha(proj / "final/manuscript-final.md"), "command": "pandoc final/manuscript-final.md -o final/manuscript-final.docx"},
        "tex": {"status": "PASS", "source_md_sha256": sha(proj / "final/manuscript-final.md"), "command": "pandoc final/manuscript-final.md -o final/manuscript-final.tex --standalone"},
        "pdf": {"status": "PASS", "source_md_sha256": sha(proj / "final/manuscript-final.md"), "command": "/usr/bin/pandoc final/manuscript-final.md -o final/manuscript-final.pdf --pdf-engine=xelatex"}
    },
    "content_checks": {
        "required_sections_present": True,
        "placeholder_free": True,
        "word_count": len(final_md.split()),
        "journal_structure_applied": True,
        "journal_display_architecture_applied": True,
        "section_sequence_matches_blueprint": True,
        "table_placement_policy_applied": "end_matter_after_references",
        "figure_placement_policy_applied": "separate_files_after_tables",
        "table_rendering_mode_applied": "editable_text_end_matter",
        "figure_rendering_mode_applied": "separate_figure_files",
        "descriptive_table_requirement_satisfied": True,
        "display_cap_respected": True,
        "main_text_table_count": 2,
        "main_text_figure_count": 1,
        "main_text_display_count": 3
    },
    "citation_checks": {
        "references_bib_used": True,
        "unresolved_citations": 0,
        "citation_audit_hash": sha(proj / "citation/citation-audit.json")
    },
    "declaration_checks": {
        "ethics_statement": True,
        "data_availability": True,
        "ai_use_disclosure": True,
        "coi_statement": True
    },
    "reader_facing_language": {
        "status": "PASS",
        "workflow_jargon_hits": 0,
        "internal_spec_label_hits": 0,
        "model_labels": ["Model 1", "Model 2", "Model 3"]
    },
    "declaration_visibility": {
        "status": "PASS",
        "visible_declarations": ["ethics_statement", "data_availability", "ai_use_disclosure", "coi_statement"],
        "missing_required_declarations": []
    },
    "findings": [],
    "fix_checklist": {
        "critical_fixes": [],
        "route_back": []
    },
    "route_back_phase": None,
    "ready_for_phase_20": True
}
write("final/final-manifest.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
(proj / versioned["manifest"]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.19.positive
expect_pass phase.19.positive "$FINAL_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$FINAL_PROJ"

BAD_FINAL_JOURNAL_POLICY_PROJ="$TMP/bad-final-journal-policy-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_JOURNAL_POLICY_PROJ"
python3 - "$BAD_FINAL_JOURNAL_POLICY_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["content_checks"]["table_placement_policy_applied"] = "embedded_main_text"
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.journal-table-policy
expect_reject l2.p19.reject.journal-table-policy "$BAD_FINAL_JOURNAL_POLICY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_JOURNAL_POLICY_PROJ"

BAD_FINAL_RAW_HTML_TABLE_PROJ="$TMP/bad-final-raw-html-table-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_RAW_HTML_TABLE_PROJ"
python3 - "$BAD_FINAL_RAW_HTML_TABLE_PROJ" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()

raw_html_table = """<!-- DISPLAY_TABLE: tables/regression-main.html -->
Table 2. Regression estimates for parental job loss and adolescent educational expectations.

<table class="tinytable" id="tinytable_fixture">
<thead><tr><th>Predictor</th><th>Model 1</th><th>Model 2</th><th>Model 3</th></tr></thead>
<tbody>
<tr><td>Parental job loss</td><td>-0.120 (0.040)</td><td>-0.080 (0.050)</td><td>-0.090 (0.045)</td></tr>
<tr><td>p-value</td><td>0.003</td><td>0.110</td><td>0.046</td></tr>
<tr><td>N</td><td>1200</td><td>1200</td><td>1200</td></tr>
</tbody>
</table>"""

md_path = proj / "final/manuscript-final.md"
text = md_path.read_text()
text = re.sub(
    r"<!-- DISPLAY_TABLE: tables/regression-main\.html -->\nTable 2\. Regression estimates for parental job loss and adolescent educational expectations\.[\s\S]*?(?=\n\n## Figures)",
    raw_html_table,
    text,
    count=1,
)
md_path.write_text(text)

manifest_path = proj / "final/final-manifest.json"
manifest = json.loads(manifest_path.read_text())
versioned_md = proj / manifest["versioned_output_paths"]["md"]
versioned_md.write_text(text)
md_hash = sha(md_path)
manifest["output_hashes"]["md"] = md_hash
manifest["versioned_output_hashes"]["md"] = sha(versioned_md)
manifest["same_source"]["source_md_sha256"] = md_hash
for record in manifest["format_generation"].values():
    record["source_md_sha256"] = md_hash
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
(proj / manifest["versioned_output_paths"]["manifest"]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.raw-html-table
expect_reject l2.p19.reject.raw-html-table "$BAD_FINAL_RAW_HTML_TABLE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_RAW_HTML_TABLE_PROJ"

BAD_FINAL_PROVENANCE_PROJ="$TMP/bad-final-provenance-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_PROVENANCE_PROJ"
python3 - "$BAD_FINAL_PROVENANCE_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["journal_profile_resolution"]["profile_origin"] = "fallback_asr"
manifest["journal_profile_resolution"]["fallback_used"] = True
manifest["journal_profile_resolution"]["fallback_reason"] = "spurious drift"
manifest["journal_profile_resolution"]["source_strategy"] = "asr_fallback"
manifest["journal_profile_resolution"]["resolved_profile_name"] = "American Sociological Review"
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.journal-provenance
expect_reject l2.p19.reject.journal-provenance "$BAD_FINAL_PROVENANCE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_PROVENANCE_PROJ"

FAIL_FINAL_PROJ="$TMP/fail-final-project"
cp -R "$FINAL_PROJ" "$FAIL_FINAL_PROJ"
python3 - "$FAIL_FINAL_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["verdict"] = "FAIL"
manifest["ready_for_phase_20"] = False
manifest["route_back_phase"] = "19"
manifest["findings"] = [
    {
        "finding_id": "P18-F001",
        "severity": "CRITICAL",
        "category": "format_generation",
        "owner_phase": "19",
        "route_back_phase": "19",
        "detected_by": "final-assembly",
        "affected_artifacts": ["final/manuscript-final.pdf", "final/final-manifest.json"],
        "required_fix": "Regenerate all four final formats from final/manuscript-final.md and update the manifest.",
        "status": "open"
    }
]
manifest["fix_checklist"] = {
    "critical_fixes": ["Regenerate final formats from the canonical Markdown source."],
    "route_back": ["19"]
}
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.19.negative
expect_reject phase.19.negative "$FAIL_FINAL_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$FAIL_FINAL_PROJ"

ROUTE_STATE_18_PROJ="$TMP/route-state-18-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_18_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_18_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_18_PROJ/artifacts" "$ROUTE_STATE_18_PROJ/final"
for pid in $(seq 0 18); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_18_PROJ/artifacts/phase-$pid.txt"
  complete_sm "$ROUTE_STATE_18_PROJ" "$pid" "$ROUTE_STATE_18_PROJ/artifacts/phase-$pid.txt"
done
cp "$FAIL_FINAL_PROJ/final/final-manifest.json" "$ROUTE_STATE_18_PROJ/final/final-manifest.json"
python3 - "$ROUTE_STATE_18_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest.pop("source_phase", None)
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
ROUTE_18_OUT="$(bash "$SCRIPT_DIR/auto-research-state.sh" route-back "$ROUTE_STATE_18_PROJ" "$ROUTE_STATE_18_PROJ/final/final-manifest.json")"
case "$ROUTE_18_OUT" in
  *"ROUTE_BACK_PHASE=19"*"INVALIDATED_PHASES=19"* ) ;;
  *) echo "FAIL: Phase 19 route-back should invalidate phase 19, got $ROUTE_18_OUT" >&2; exit 1 ;;
esac
python3 - "$ROUTE_STATE_18_PROJ/.auto-research/state.json" <<'PY'
import json
import pathlib
import sys
state = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = state.get("active_route_back", {}).get("source_phase")
if source != "19":
    raise SystemExit(f"FAIL: Phase 19 route-back source_phase should infer 19, got {source}")
PY

BAD_FINAL_MANIFEST_PROJ="$TMP/bad-final-manifest-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_MANIFEST_PROJ"
python3 - "$BAD_FINAL_MANIFEST_PROJ/final/final-manifest.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest.pop("verdict")
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.manifest-schema
expect_reject l2.p19.reject.manifest-schema "$BAD_FINAL_MANIFEST_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_MANIFEST_PROJ"

BAD_FINAL_HASH_PROJ="$TMP/bad-final-hash-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_HASH_PROJ"
printf '\nLate final edit.\n' >> "$BAD_FINAL_HASH_PROJ/final/manuscript-final.md"
# CASE_ID: l2.p19.reject.output-hash
expect_reject l2.p19.reject.output-hash "$BAD_FINAL_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_HASH_PROJ"

BAD_FINAL_SOURCE_PROJ="$TMP/bad-final-source-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_SOURCE_PROJ"
python3 - "$BAD_FINAL_SOURCE_PROJ/final/final-manifest.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["source_manuscript_hash"] = "0" * 64
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.source-manuscript-hash
expect_reject l2.p19.reject.source-manuscript-hash "$BAD_FINAL_SOURCE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_SOURCE_PROJ"

BAD_FINAL_DOCX_PROJ="$TMP/bad-final-docx-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_DOCX_PROJ"
printf 'not a docx\n' > "$BAD_FINAL_DOCX_PROJ/final/manuscript-final.docx"
python3 - "$BAD_FINAL_DOCX_PROJ/final/final-manifest.json" "$BAD_FINAL_DOCX_PROJ/final/manuscript-final.docx" <<'PY'
import hashlib
import json
import pathlib
import sys
manifest_path = pathlib.Path(sys.argv[1])
docx_path = pathlib.Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text())
versioned_docx = manifest_path.parents[1] / manifest["versioned_output_paths"]["docx"]
versioned_docx.write_bytes(docx_path.read_bytes())
manifest["output_hashes"]["docx"] = hashlib.sha256(docx_path.read_bytes()).hexdigest()
manifest["versioned_output_hashes"]["docx"] = hashlib.sha256(versioned_docx.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.docx-authenticity
expect_reject l2.p19.reject.docx-authenticity "$BAD_FINAL_DOCX_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_DOCX_PROJ"

BAD_FINAL_SAMESOURCE_PROJ="$TMP/bad-final-samesource-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_SAMESOURCE_PROJ"
python3 - "$BAD_FINAL_SAMESOURCE_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["same_source"]["all_formats_from_source_md"] = False
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.same-source
expect_reject l2.p19.reject.same-source "$BAD_FINAL_SAMESOURCE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_SAMESOURCE_PROJ"

BAD_FINAL_LATEST_PROJ="$TMP/bad-final-latest-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_LATEST_PROJ"
printf '2026-04-30T153013Z-v001\n' > "$BAD_FINAL_LATEST_PROJ/final/LATEST.txt"
# CASE_ID: l2.p19.reject.latest-pointer
expect_reject l2.p19.reject.latest-pointer "$BAD_FINAL_LATEST_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_LATEST_PROJ"

BAD_FINAL_VERSION_COPY_PROJ="$TMP/bad-final-version-copy-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_VERSION_COPY_PROJ"
python3 - "$BAD_FINAL_VERSION_COPY_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
versioned_docx = path.parents[1] / manifest["versioned_output_paths"]["docx"]
versioned_docx.unlink()
PY
# CASE_ID: l2.p19.reject.versioned-copy-missing
expect_reject l2.p19.reject.versioned-copy-missing "$BAD_FINAL_VERSION_COPY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_VERSION_COPY_PROJ"

BAD_FINAL_VERSION_HASH_PROJ="$TMP/bad-final-version-hash-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_VERSION_HASH_PROJ"
python3 - "$BAD_FINAL_VERSION_HASH_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
versioned_md = path.parents[1] / manifest["versioned_output_paths"]["md"]
versioned_md.write_text(versioned_md.read_text() + "\nVersion-only drift.\n")
PY
# CASE_ID: l2.p19.reject.versioned-hash
expect_reject l2.p19.reject.versioned-hash "$BAD_FINAL_VERSION_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_VERSION_HASH_PROJ"

BAD_FINAL_PLACEHOLDER_PROJ="$TMP/bad-final-placeholder-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_PLACEHOLDER_PROJ"
printf '\nTODO add journal title\n' >> "$BAD_FINAL_PLACEHOLDER_PROJ/final/manuscript-final.md"
python3 - "$BAD_FINAL_PLACEHOLDER_PROJ" <<'PY'
import hashlib, json, pathlib, sys
proj = pathlib.Path(sys.argv[1])
manifest_path = proj / "final/final-manifest.json"
manifest = json.loads(manifest_path.read_text())
canonical = proj / manifest["output_paths"]["md"]
versioned = proj / manifest["versioned_output_paths"]["md"]
versioned.write_bytes(canonical.read_bytes())
digest = hashlib.sha256(canonical.read_bytes()).hexdigest()
manifest["output_hashes"]["md"] = digest
manifest["versioned_output_hashes"]["md"] = hashlib.sha256(versioned.read_bytes()).hexdigest()
manifest["same_source"]["source_md_sha256"] = digest
for record in manifest["format_generation"].values():
    record["source_md_sha256"] = digest
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
(proj / manifest["versioned_output_paths"]["manifest"]).write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n"
)
PY
# CASE_ID: l2.p19.reject.placeholder
expect_reject l2.p19.reject.placeholder "$BAD_FINAL_PLACEHOLDER_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_PLACEHOLDER_PROJ"

BAD_FINAL_ENGINE_PROJ="$TMP/bad-final-engine-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_ENGINE_PROJ"
python3 - "$BAD_FINAL_ENGINE_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["assembly_engine"]["name"] = "manual-export"
manifest["assembly_engine"]["fallback_used"] = True
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.assembly-engine
expect_reject l2.p19.reject.assembly-engine "$BAD_FINAL_ENGINE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_ENGINE_PROJ"

BAD_FINAL_COMMAND_PROJ="$TMP/bad-final-command-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_COMMAND_PROJ"
python3 - "$BAD_FINAL_COMMAND_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["format_generation"]["pdf"]["command"] = "pandoc manuscript/manuscript-draft.md -o final/manuscript-final.pdf"
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.format-source-command
expect_reject l2.p19.reject.format-source-command "$BAD_FINAL_COMMAND_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_COMMAND_PROJ"

BAD_FINAL_NONPANDOC_PROJ="$TMP/bad-final-nonpandoc-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_NONPANDOC_PROJ"
python3 - "$BAD_FINAL_NONPANDOC_PROJ/final/final-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["format_generation"]["tex"]["command"] = "python render.py final/manuscript-final.md final/manuscript-final.tex"
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p19.reject.nonpandoc-command
expect_reject l2.p19.reject.nonpandoc-command "$BAD_FINAL_NONPANDOC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_NONPANDOC_PROJ"

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "19" ]]; then
  harness_validate_results --phase-through 19 >/dev/null
  progress "phases 0 to 19 authoritative harness assertions passed"
  exit 0
fi

SUBMISSION_PROJ="$TMP/submission-project"
cp -R "$FINAL_PROJ" "$SUBMISSION_PROJ"
mkdir -p "$SUBMISSION_PROJ/submission"
python3 - "$SUBMISSION_PROJ" <<'PY'
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import zipfile

proj = pathlib.Path(sys.argv[1])

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def write(rel, text):
    path = proj / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path

def assemble_submission_from_final(text):
    allowed = {
        "abstract",
        "introduction",
        "background",
        "data and methods",
        "results",
        "discussion",
        "conclusion",
        "references",
        "tables",
        "figures",
        "ethics statement",
        "data availability",
        "ai use disclosure",
        "competing interests",
    }
    lines = []
    current_heading = None
    current_slug = None
    buffer = []
    title_written = False
    def flush():
        nonlocal lines, current_heading, current_slug, buffer
        if current_heading is None:
            return
        if current_slug in allowed:
            lines.extend([f"## {current_heading}", ""])
            lines.extend(buffer)
            if buffer and buffer[-1] != "":
                lines.append("")
        buffer = []
    for raw_line in text.splitlines():
        if raw_line.startswith("# ") and not title_written:
            lines.extend([raw_line, ""])
            title_written = True
            continue
        if title_written and current_heading is None and re.match(r"^Keywords?:\s+", raw_line, re.I):
            lines.extend([raw_line, ""])
            continue
        match = re.match(r"^##\s+(.+?)\s*$", raw_line)
        if match:
            flush()
            current_heading = match.group(1)
            current_slug = re.sub(r"[^a-z0-9]+", " ", current_heading.lower()).strip()
            continue
        if current_heading is not None:
            if "<!--" in raw_line or "results-locked/" in raw_line or "verify/" in raw_line or "logs/" in raw_line:
                continue
            buffer.append(raw_line)
    flush()
    assembled = "\n".join(lines).strip() + "\n"
    assembled = re.sub(r"\[@work(\d{2})\]", lambda m: f"(Author {int(m.group(1))}, 20{int(m.group(1)) % 20:02d})", assembled)
    return re.sub(r"!\[([^\]]*)\]\((?:/Users/|/tmp/|/private/var/|/var/folders/|/home/|~)[^)]+\)", r"[\1 about here]", assembled)

final_manifest = json.loads((proj / "final/final-manifest.json").read_text())
journal_profile_resolution = final_manifest["journal_profile_resolution"]
submission_version_id = "2026-04-30T153500Z-v001"
created_at_utc = "2026-04-30T15:35:00Z"
source = (proj / "final/manuscript-final.md").read_text()
submission_text = assemble_submission_from_final(source)
write("submission/manuscript-submission.md", submission_text)
semantic_report = f"""STATUS: GREEN
REVIEWED_ARTIFACT: submission/manuscript-submission.md
MANUSCRIPT_SHA256: {sha(proj / "submission/manuscript-submission.md")}
BLOCKING_ISSUES: 0
STRUCTURAL_PATTERN_COUNT: 0
BORDERLINE_ISSUES: 0

The submission manuscript reads as journal-facing body prose. No structural machinery prose, citation-verification marker, spec-ID bullet run, or pipeline-style header remains.
"""
write("submission/semantic-body-prose-read.md", semantic_report)
(proj / "submission/figures").mkdir(parents=True, exist_ok=True)
(proj / "submission/figures/event-study.png").write_bytes((proj / "final/figures/event-study.png").read_bytes())
for extension, extra in (("docx", []), ("tex", []), ("pdf", ["--pdf-engine=xelatex"])):
    subprocess.run(
        ["pandoc", "-s", "submission/manuscript-submission.md", "-o",
         f"submission/manuscript-submission.{extension}", *extra],
        check=True, cwd=proj,
    )
write("submission/LATEST.txt", submission_version_id + "\n")
versioned = {
    "submission_md": f"submission/versions/{submission_version_id}/manuscript-submission-{submission_version_id}.md",
    "submission_docx": f"submission/versions/{submission_version_id}/manuscript-submission-{submission_version_id}.docx",
    "submission_tex": f"submission/versions/{submission_version_id}/manuscript-submission-{submission_version_id}.tex",
    "submission_pdf": f"submission/versions/{submission_version_id}/manuscript-submission-{submission_version_id}.pdf",
    "semantic_body_prose_read": f"submission/versions/{submission_version_id}/semantic-body-prose-read-{submission_version_id}.md",
    "hygiene_json": f"submission/versions/{submission_version_id}/submission-hygiene-{submission_version_id}.json",
    "package_manifest": f"submission/versions/{submission_version_id}/submission-package-manifest-{submission_version_id}.json",
}
(proj / versioned["submission_md"]).parent.mkdir(parents=True, exist_ok=True)
(proj / versioned["submission_md"]).write_bytes((proj / "submission/manuscript-submission.md").read_bytes())
(proj / versioned["submission_docx"]).write_bytes((proj / "submission/manuscript-submission.docx").read_bytes())
(proj / versioned["submission_tex"]).write_bytes((proj / "submission/manuscript-submission.tex").read_bytes())
(proj / versioned["submission_pdf"]).write_bytes((proj / "submission/manuscript-submission.pdf").read_bytes())
(proj / versioned["semantic_body_prose_read"]).write_bytes((proj / "submission/semantic-body-prose-read.md").read_bytes())

hygiene = {
    "verdict": "PASS",
    "degraded": False,
    "source_phase": "20",
    "submission_engine": {
        "name": "auto-research-submission-hygiene",
        "borrowed_practices": ["submission-prep path scrub", "submission-hygiene metadata scrub", "citation rendering check"]
    },
    "journal_profile_resolution": journal_profile_resolution,
    "final_version_id": final_manifest["version_id"],
    "submission_version_id": submission_version_id,
    "created_at_utc": created_at_utc,
    "source_hashes": {
        "final_manifest": sha(proj / "final/final-manifest.json"),
        "final_latest": sha(proj / "final/LATEST.txt"),
        "final_md": sha(proj / "final/manuscript-final.md"),
        "final_docx": sha(proj / "final/manuscript-final.docx"),
        "final_tex": sha(proj / "final/manuscript-final.tex"),
        "final_pdf": sha(proj / "final/manuscript-final.pdf"),
        "references_bib": sha(proj / "citation/references.bib"),
        "ethics_open_science": sha(proj / "ethics/ethics-open-science.json"),
        "replication_report": sha(proj / "replication-package/replication-report.json")
    },
    "hygiene_checks": {
        "status": "GREEN",
        "red_hits": 0,
        "yellow_hits": 0,
        "stage_a": {
            "status": "GREEN",
            "red_hits": 0,
            "machinery_prose_hits": 0,
            "known_rule_set": ["R8q", "R8r", "R8s", "R8t"]
        }
    },
    "citation_rendering": {
        "unresolved_citations": 0,
        "references_bullet_list": False,
        "bibliography_present": True
    },
    "path_scrub": {
        "absolute_paths": 0,
        "internal_paths": 0
    },
    "placeholder_scan": {
        "unresolved_placeholders": 0
    },
    "internal_metadata_scan": {
        "pipeline_metadata_hits": 0
    },
    "reader_facing_language": {
        "status": "PASS",
        "workflow_jargon_hits": 0,
        "internal_spec_label_hits": 0,
        "model_labels": ["Model 1", "Model 2", "Model 3"]
    },
    "semantic_body_prose_read": {
        "status": "GREEN",
        "report_path": "submission/semantic-body-prose-read.md",
        "reviewed_artifact": "submission/manuscript-submission.md",
        "manuscript_sha256": sha(proj / "submission/manuscript-submission.md"),
        "subagent_type": "semantic-body-prose-reader",
        "blocking_issue_count": 0,
        "structural_pattern_count": 0,
        "borderline_issue_count": 0,
        "unresolved_suggestion_count": 0
    },
    "declaration_visibility": {
        "status": "PASS",
        "visible_declarations": ["ethics_statement", "data_availability", "ai_use_disclosure", "coi_statement"],
        "missing_required_declarations": []
    },
    "figure_packaging": {
        "status": "PASS",
        "referenced_figures": ["submission/figures/event-study.png"],
        "packaged_figures": ["submission/figures/event-study.png"],
        "missing_or_uninventoried_figures": []
    },
    "format_generation": {
        "docx": {
            "status": "PASS",
            "source_md_sha256": sha(proj / "submission/manuscript-submission.md"),
            "command": "pandoc submission/manuscript-submission.md -o submission/manuscript-submission.docx"
        },
        "tex": {
            "status": "PASS",
            "source_md_sha256": sha(proj / "submission/manuscript-submission.md"),
            "command": "pandoc submission/manuscript-submission.md -o submission/manuscript-submission.tex"
        },
        "pdf": {
            "status": "PASS",
            "source_md_sha256": sha(proj / "submission/manuscript-submission.md"),
            "command": "/usr/local/bin/pandoc submission/manuscript-submission.md -o submission/manuscript-submission.pdf"
        }
    },
    "findings": [],
    "fix_checklist": {
        "critical_fixes": [],
        "route_back": []
    },
    "route_back_phase": None,
    "pipeline_complete": True
}
write("submission/submission-hygiene.json", json.dumps(hygiene, indent=2, sort_keys=True) + "\n")

package_manifest = {
    "verdict": "PASS",
    "source_phase": "20",
    "journal_profile_resolution": journal_profile_resolution,
    "final_version_id": final_manifest["version_id"],
    "submission_version_id": submission_version_id,
    "canonical_outputs": {
        "submission_md": "submission/manuscript-submission.md",
        "submission_docx": "submission/manuscript-submission.docx",
        "submission_tex": "submission/manuscript-submission.tex",
        "submission_pdf": "submission/manuscript-submission.pdf",
        "semantic_body_prose_read": "submission/semantic-body-prose-read.md",
        "hygiene_json": "submission/submission-hygiene.json",
        "package_manifest": "submission/submission-package-manifest.json"
    },
    "versioned_outputs": versioned,
    "output_hashes": {
        "submission_md": sha(proj / "submission/manuscript-submission.md"),
        "submission_docx": sha(proj / "submission/manuscript-submission.docx"),
        "submission_tex": sha(proj / "submission/manuscript-submission.tex"),
        "submission_pdf": sha(proj / "submission/manuscript-submission.pdf"),
        "semantic_body_prose_read": sha(proj / "submission/semantic-body-prose-read.md"),
        "hygiene_json": "SELF_REFERENTIAL",
        "package_manifest": "SELF_REFERENTIAL"
    },
    "versioned_output_hashes": {
        "submission_md": sha(proj / versioned["submission_md"]),
        "submission_docx": sha(proj / versioned["submission_docx"]),
        "submission_tex": sha(proj / versioned["submission_tex"]),
        "submission_pdf": sha(proj / versioned["submission_pdf"]),
        "semantic_body_prose_read": sha(proj / versioned["semantic_body_prose_read"]),
        "hygiene_json": "SELF_REFERENTIAL",
        "package_manifest": "SELF_REFERENTIAL"
    },
    "package_inventory": {
        "files": [
            {"path": "submission/manuscript-submission.md", "role": "reviewer_manuscript", "sha256": sha(proj / "submission/manuscript-submission.md")},
            {"path": "submission/manuscript-submission.docx", "role": "reviewer_manuscript_docx", "sha256": sha(proj / "submission/manuscript-submission.docx")},
            {"path": "submission/manuscript-submission.tex", "role": "reviewer_manuscript_tex", "sha256": sha(proj / "submission/manuscript-submission.tex")},
            {"path": "submission/manuscript-submission.pdf", "role": "reviewer_manuscript_pdf", "sha256": sha(proj / "submission/manuscript-submission.pdf")},
            {"path": "submission/semantic-body-prose-read.md", "role": "semantic_body_prose_read", "sha256": sha(proj / "submission/semantic-body-prose-read.md")},
            {"path": "submission/figures/event-study.png", "role": "submission_figure", "sha256": sha(proj / "submission/figures/event-study.png")},
            {"path": "submission/submission-hygiene.json", "role": "hygiene_report", "sha256": "SELF_REFERENTIAL"},
            {"path": "submission/submission-package-manifest.json", "role": "package_manifest", "sha256": "SELF_REFERENTIAL"},
            {"path": "submission/LATEST.txt", "role": "latest_pointer", "sha256": sha(proj / "submission/LATEST.txt")},
            {"path": versioned["submission_md"], "role": "versioned_reviewer_manuscript", "sha256": sha(proj / versioned["submission_md"])},
            {"path": versioned["submission_docx"], "role": "versioned_reviewer_manuscript_docx", "sha256": sha(proj / versioned["submission_docx"])},
            {"path": versioned["submission_tex"], "role": "versioned_reviewer_manuscript_tex", "sha256": sha(proj / versioned["submission_tex"])},
            {"path": versioned["submission_pdf"], "role": "versioned_reviewer_manuscript_pdf", "sha256": sha(proj / versioned["submission_pdf"])},
            {"path": versioned["semantic_body_prose_read"], "role": "versioned_semantic_body_prose_read", "sha256": sha(proj / versioned["semantic_body_prose_read"])},
            {"path": versioned["hygiene_json"], "role": "versioned_hygiene_report", "sha256": "SELF_REFERENTIAL"},
            {"path": versioned["package_manifest"], "role": "versioned_package_manifest", "sha256": "SELF_REFERENTIAL"}
        ]
    },
    "ready_for_done": True
}
write("submission/submission-package-manifest.json", json.dumps(package_manifest, indent=2, sort_keys=True) + "\n")
(proj / versioned["hygiene_json"]).write_text(json.dumps(hygiene, indent=2, sort_keys=True) + "\n")
(proj / versioned["package_manifest"]).write_text(json.dumps(package_manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p20.reject.missing-review-evidence
expect_reject l2.p20.reject.missing-review-evidence "$SUBMISSION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$SUBMISSION_PROJ"

# The stable semantic report is a package artifact, not review authority. A
# separately registered evidence report with RED content must control the
# verdict even when the stable report and hygiene counters still say GREEN.
BAD_SUBMISSION_EVIDENCE_RED_PROJ="$TMP/bad-submission-evidence-red-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_EVIDENCE_RED_PROJ"
cp "$BAD_SUBMISSION_EVIDENCE_RED_PROJ/submission/semantic-body-prose-read.md" \
  "$BAD_SUBMISSION_EVIDENCE_RED_PROJ/submission/semantic-body-prose-read-red-evidence.md"
python3 - "$BAD_SUBMISSION_EVIDENCE_RED_PROJ/submission/semantic-body-prose-read-red-evidence.md" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
report = path.read_text()
report = report.replace("STATUS: GREEN", "STATUS: RED")
report = report.replace("BLOCKING_ISSUES: 0", "BLOCKING_ISSUES: 2")
report = report.replace("STRUCTURAL_PATTERN_COUNT: 0", "STRUCTURAL_PATTERN_COUNT: 1")
path.write_text(report)
PY
python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$BAD_SUBMISSION_EVIDENCE_RED_PROJ" 20 semantic_body_reader \
  --evidence-report semantic_body_prose_reader=submission/semantic-body-prose-read-red-evidence.md >/dev/null
# CASE_ID: l2.p20.reject.evidence-red
expect_reject l2.p20.reject.evidence-red "$BAD_SUBMISSION_EVIDENCE_RED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_EVIDENCE_RED_PROJ"

python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$SUBMISSION_PROJ" 20 semantic_body_reader >/dev/null
# CASE_ID: phase.20.positive
expect_pass phase.20.positive "$SUBMISSION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$SUBMISSION_PROJ"

renew_submission_review_evidence() {
  local project="$1"
  local old_session
  old_session="$(python3 - "$project/submission/submission-hygiene.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
print(doc["review_evidence"]["rounds"]["semantic_body_reader"]["session_id"])
PY
)"
  bash "$SCRIPT_DIR/auto-research-state.sh" review-abort "$project" 20 "$old_session" \
    --reason "fixture input or semantic report changed; reserve fresh evidence" >/dev/null
  python3 "$REGISTER_REVIEW" "$SKILL_DIR" "$project" 20 semantic_body_reader >/dev/null
}

sync_submission_fixture_hashes() {
  local project="$1"
  local update_semantic_binding="${2:-1}"
  python3 - "$project" "$update_semantic_binding" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

proj = pathlib.Path(sys.argv[1])
update_semantic = sys.argv[2] == "1"
hygiene_path = proj / "submission/submission-hygiene.json"
manifest_path = proj / "submission/submission-package-manifest.json"
hygiene = json.loads(hygiene_path.read_text())
manifest = json.loads(manifest_path.read_text())

def sha(path):
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()

submission_hash = sha(proj / "submission/manuscript-submission.md")
for fmt in ("docx", "tex", "pdf"):
    if isinstance(hygiene.get("format_generation", {}).get(fmt), dict):
        hygiene["format_generation"][fmt]["source_md_sha256"] = submission_hash

semantic_path = proj / "submission/semantic-body-prose-read.md"
if update_semantic and semantic_path.exists():
    semantic = hygiene.get("semantic_body_prose_read", {})
    semantic["manuscript_sha256"] = submission_hash
    hygiene["semantic_body_prose_read"] = semantic
    report = semantic_path.read_text()
    report = re.sub(r"(?m)^MANUSCRIPT_SHA256:\s*[0-9a-f]{64}\s*$", f"MANUSCRIPT_SHA256: {submission_hash}", report)
    semantic_path.write_text(report)

for key, rel in manifest.get("canonical_outputs", {}).items():
    path = proj / rel
    if not path.exists():
        continue
    manifest["output_hashes"][key] = "SELF_REFERENTIAL" if rel.endswith(".json") else sha(path)
    versioned_rel = manifest.get("versioned_outputs", {}).get(key)
    if versioned_rel and not rel.endswith(".json"):
        versioned_path = proj / versioned_rel
        versioned_path.parent.mkdir(parents=True, exist_ok=True)
        versioned_path.write_bytes(path.read_bytes())
        manifest["versioned_output_hashes"][key] = sha(versioned_path)

for item in manifest.get("package_inventory", {}).get("files", []):
    rel = item.get("path")
    if not rel:
        continue
    path = proj / rel
    if path.exists():
        item["sha256"] = "SELF_REFERENTIAL" if rel.endswith(".json") else sha(path)

hygiene_path.write_text(json.dumps(hygiene, indent=2, sort_keys=True) + "\n")
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
for key in ("hygiene_json", "package_manifest"):
    rel = manifest.get("versioned_outputs", {}).get(key)
    if rel:
        target = proj / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        source = hygiene_path if key == "hygiene_json" else manifest_path
        target.write_text(source.read_text())
PY
  if [[ "$update_semantic_binding" == "1" ]]; then
    renew_submission_review_evidence "$project"
  fi
}

BAD_SUBMISSION_RAW_HTML_TABLE_PROJ="$TMP/bad-submission-raw-html-table-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_RAW_HTML_TABLE_PROJ"
python3 - "$BAD_SUBMISSION_RAW_HTML_TABLE_PROJ/submission/manuscript-submission.md" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
raw_html_table = """Table 2. Regression estimates for parental job loss and adolescent educational expectations.

<table class="tinytable" id="tinytable_fixture_submission">
<thead><tr><th>Predictor</th><th>Model 1</th><th>Model 2</th><th>Model 3</th></tr></thead>
<tbody>
<tr><td>Parental job loss</td><td>-0.120 (0.040)</td><td>-0.080 (0.050)</td><td>-0.090 (0.045)</td></tr>
<tr><td>p-value</td><td>0.003</td><td>0.110</td><td>0.046</td></tr>
<tr><td>N</td><td>1200</td><td>1200</td><td>1200</td></tr>
</tbody>
</table>"""
text = path.read_text()
text = re.sub(
    r"Table 2\. Regression estimates for parental job loss and adolescent educational expectations\.[\s\S]*?(?=\n\n## Figures)",
    raw_html_table,
    text,
    count=1,
)
path.write_text(text)
PY
sync_submission_fixture_hashes "$BAD_SUBMISSION_RAW_HTML_TABLE_PROJ" 1
# CASE_ID: l2.p20.reject.raw-html-table
expect_reject l2.p20.reject.raw-html-table "$BAD_SUBMISSION_RAW_HTML_TABLE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_RAW_HTML_TABLE_PROJ"

BAD_SUBMISSION_MISSING_STAGE_B_PROJ="$TMP/bad-submission-missing-stage-b-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_MISSING_STAGE_B_PROJ"
rm "$BAD_SUBMISSION_MISSING_STAGE_B_PROJ/submission/semantic-body-prose-read.md"
# CASE_ID: l2.p20.reject.missing-stage-b
expect_reject l2.p20.reject.missing-stage-b "$BAD_SUBMISSION_MISSING_STAGE_B_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_MISSING_STAGE_B_PROJ"

BAD_SUBMISSION_STALE_STAGE_B_PROJ="$TMP/bad-submission-stale-stage-b-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_STALE_STAGE_B_PROJ"
printf '\nA late edit after Stage B should stale the semantic read.\n' >> "$BAD_SUBMISSION_STALE_STAGE_B_PROJ/submission/manuscript-submission.md"
sync_submission_fixture_hashes "$BAD_SUBMISSION_STALE_STAGE_B_PROJ" 0
renew_submission_review_evidence "$BAD_SUBMISSION_STALE_STAGE_B_PROJ"
# CASE_ID: l2.p20.reject.stale-stage-b
expect_reject l2.p20.reject.stale-stage-b "$BAD_SUBMISSION_STALE_STAGE_B_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_STALE_STAGE_B_PROJ"

BAD_SUBMISSION_RED_STAGE_B_PROJ="$TMP/bad-submission-red-stage-b-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_RED_STAGE_B_PROJ"
python3 - "$BAD_SUBMISSION_RED_STAGE_B_PROJ/submission/submission-hygiene.json" "$BAD_SUBMISSION_RED_STAGE_B_PROJ/submission/semantic-body-prose-read.md" <<'PY'
import json
import pathlib
import sys
hygiene_path = pathlib.Path(sys.argv[1])
report_path = pathlib.Path(sys.argv[2])
hygiene = json.loads(hygiene_path.read_text())
hygiene["semantic_body_prose_read"]["status"] = "RED"
hygiene["semantic_body_prose_read"]["blocking_issue_count"] = 3
hygiene["semantic_body_prose_read"]["structural_pattern_count"] = 3
hygiene_path.write_text(json.dumps(hygiene, indent=2, sort_keys=True) + "\n")
report = report_path.read_text()
report = report.replace("STATUS: GREEN", "STATUS: RED")
report = report.replace("BLOCKING_ISSUES: 0", "BLOCKING_ISSUES: 3")
report = report.replace("STRUCTURAL_PATTERN_COUNT: 0", "STRUCTURAL_PATTERN_COUNT: 3")
report_path.write_text(report)
PY
sync_submission_fixture_hashes "$BAD_SUBMISSION_RED_STAGE_B_PROJ" 1
# CASE_ID: l2.p20.reject.red-stage-b
expect_reject l2.p20.reject.red-stage-b "$BAD_SUBMISSION_RED_STAGE_B_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_RED_STAGE_B_PROJ"

BAD_SUBMISSION_VERIFIED_MARKER_PROJ="$TMP/bad-submission-verified-marker-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_VERIFIED_MARKER_PROJ"
printf '\nPrior work supports this claim [VERIFIED-WEB: Example2020].\n' >> "$BAD_SUBMISSION_VERIFIED_MARKER_PROJ/submission/manuscript-submission.md"
sync_submission_fixture_hashes "$BAD_SUBMISSION_VERIFIED_MARKER_PROJ" 1
# CASE_ID: l2.p20.reject.verified-marker
expect_reject l2.p20.reject.verified-marker "$BAD_SUBMISSION_VERIFIED_MARKER_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_VERIFIED_MARKER_PROJ"

BAD_SUBMISSION_MACHINERY_PROJ="$TMP/bad-submission-machinery-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_MACHINERY_PROJ"
cat >> "$BAD_SUBMISSION_MACHINERY_PROJ/submission/manuscript-submission.md" <<'EOF'

### Robustness Ladder

- **M1.** Descriptive specification.
- **M2.** Controlled specification.
- **M3.** Robust specification.

We carry ten accepted limitations into the manuscript.
EOF
sync_submission_fixture_hashes "$BAD_SUBMISSION_MACHINERY_PROJ" 1
# CASE_ID: l2.p20.reject.machinery-prose
expect_reject l2.p20.reject.machinery-prose "$BAD_SUBMISSION_MACHINERY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_MACHINERY_PROJ"

BAD_SUBMISSION_HYPOTHESIS_PROJ="$TMP/bad-submission-hypothesis-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_HYPOTHESIS_PROJ"
cat >> "$BAD_SUBMISSION_HYPOTHESIS_PROJ/submission/manuscript-submission.md" <<'EOF'

## Hypotheses

- **H1.** Agricultural hukou is associated with lower current CCP membership.
- **H2.** The association is partly attenuated after adjustment.
EOF
sync_submission_fixture_hashes "$BAD_SUBMISSION_HYPOTHESIS_PROJ" 1
# CASE_ID: l2.p20.reject.hypothesis-list
expect_reject l2.p20.reject.hypothesis-list "$BAD_SUBMISSION_HYPOTHESIS_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_HYPOTHESIS_PROJ"

BAD_SUBMISSION_PROVENANCE_PROJ="$TMP/bad-submission-provenance-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_PROVENANCE_PROJ"
python3 - "$BAD_SUBMISSION_PROVENANCE_PROJ/submission/submission-hygiene.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
doc = json.loads(path.read_text())
doc["journal_profile_resolution"]["profile_origin"] = "fallback_asr"
doc["journal_profile_resolution"]["fallback_used"] = True
doc["journal_profile_resolution"]["fallback_reason"] = "spurious drift"
doc["journal_profile_resolution"]["source_strategy"] = "asr_fallback"
doc["journal_profile_resolution"]["resolved_profile_name"] = "American Sociological Review"
path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p20.reject.journal-provenance
expect_reject l2.p20.reject.journal-provenance "$BAD_SUBMISSION_PROVENANCE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_PROVENANCE_PROJ"

FAIL_SUBMISSION_PROJ="$TMP/fail-submission-project"
cp -R "$SUBMISSION_PROJ" "$FAIL_SUBMISSION_PROJ"
python3 - "$FAIL_SUBMISSION_PROJ/submission/submission-hygiene.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
hygiene = json.loads(path.read_text())
hygiene["verdict"] = "FAIL"
hygiene["pipeline_complete"] = False
hygiene["route_back_phase"] = "20"
hygiene["findings"] = [
    {
        "finding_id": "P19-F001",
        "severity": "CRITICAL",
        "category": "path_scrub",
        "owner_phase": "20",
        "route_back_phase": "20",
        "detected_by": "submission-hygiene",
        "affected_artifacts": ["submission/manuscript-submission.md"],
        "required_fix": "Remove reviewer-visible local or internal paths from the submission manuscript.",
        "status": "open"
    }
]
hygiene["fix_checklist"] = {
    "critical_fixes": ["Scrub the submission manuscript and rerun Phase 20."],
    "route_back": ["20"]
}
path.write_text(json.dumps(hygiene, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: phase.20.negative
expect_reject phase.20.negative "$FAIL_SUBMISSION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$FAIL_SUBMISSION_PROJ"

ROUTE_STATE_19_PROJ="$TMP/route-state-19-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_19_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_19_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_19_PROJ/artifacts" "$ROUTE_STATE_19_PROJ/submission"
for pid in $(seq 0 19); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_19_PROJ/artifacts/phase-$pid.txt"
  complete_sm "$ROUTE_STATE_19_PROJ" "$pid" "$ROUTE_STATE_19_PROJ/artifacts/phase-$pid.txt"
done
cp "$FAIL_SUBMISSION_PROJ/submission/submission-hygiene.json" "$ROUTE_STATE_19_PROJ/submission/submission-hygiene.json"
python3 - "$ROUTE_STATE_19_PROJ/submission/submission-hygiene.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
hygiene = json.loads(path.read_text())
hygiene.pop("source_phase", None)
path.write_text(json.dumps(hygiene, indent=2, sort_keys=True) + "\n")
PY
ROUTE_19_OUT="$(bash "$SCRIPT_DIR/auto-research-state.sh" route-back "$ROUTE_STATE_19_PROJ" "$ROUTE_STATE_19_PROJ/submission/submission-hygiene.json")"
case "$ROUTE_19_OUT" in
  *"ROUTE_BACK_PHASE=20"*"INVALIDATED_PHASES=20"* ) ;;
  *) echo "FAIL: Phase 20 route-back should invalidate phase 20, got $ROUTE_19_OUT" >&2; exit 1 ;;
esac
python3 - "$ROUTE_STATE_19_PROJ/.auto-research/state.json" <<'PY'
import json
import pathlib
import sys
state = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = state.get("active_route_back", {}).get("source_phase")
if source != "20":
    raise SystemExit(f"FAIL: Phase 20 route-back source_phase should infer 20, got {source}")
PY

BAD_SUBMISSION_PATH_PROJ="$TMP/bad-submission-path-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_PATH_PROJ"
printf '\nLocal figure path: /Users/example/figure.png\n' >> "$BAD_SUBMISSION_PATH_PROJ/submission/manuscript-submission.md"
sync_submission_fixture_hashes "$BAD_SUBMISSION_PATH_PROJ" 1
# CASE_ID: l2.p20.reject.local-path
expect_reject l2.p20.reject.local-path "$BAD_SUBMISSION_PATH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_PATH_PROJ"

BAD_SUBMISSION_INTERNAL_PROJ="$TMP/bad-submission-internal-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_INTERNAL_PROJ"
printf '\nSee verify/runtime-sanity.md for the derivation.\n' >> "$BAD_SUBMISSION_INTERNAL_PROJ/submission/manuscript-submission.md"
sync_submission_fixture_hashes "$BAD_SUBMISSION_INTERNAL_PROJ" 1
# CASE_ID: l2.p20.reject.internal-metadata
expect_reject l2.p20.reject.internal-metadata "$BAD_SUBMISSION_INTERNAL_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_INTERNAL_PROJ"

BAD_SUBMISSION_PLACEHOLDER_PROJ="$TMP/bad-submission-placeholder-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_PLACEHOLDER_PROJ"
printf '\nTODO add cover metadata.\n' >> "$BAD_SUBMISSION_PLACEHOLDER_PROJ/submission/manuscript-submission.md"
sync_submission_fixture_hashes "$BAD_SUBMISSION_PLACEHOLDER_PROJ" 1
# CASE_ID: l2.p20.reject.placeholder
expect_reject l2.p20.reject.placeholder "$BAD_SUBMISSION_PLACEHOLDER_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_PLACEHOLDER_PROJ"

BAD_SUBMISSION_REFS_PROJ="$TMP/bad-submission-refs-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_REFS_PROJ"
printf '\n- Bullet reference entry that should not render as a list.\n' >> "$BAD_SUBMISSION_REFS_PROJ/submission/manuscript-submission.md"
sync_submission_fixture_hashes "$BAD_SUBMISSION_REFS_PROJ" 1
# CASE_ID: l2.p20.reject.reference-bullets
expect_reject l2.p20.reject.reference-bullets "$BAD_SUBMISSION_REFS_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_REFS_PROJ"

BAD_SUBMISSION_LATEST_PROJ="$TMP/bad-submission-latest-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_LATEST_PROJ"
printf '2026-04-30T153501Z-v001\n' > "$BAD_SUBMISSION_LATEST_PROJ/submission/LATEST.txt"
# CASE_ID: l2.p20.reject.latest-pointer
expect_reject l2.p20.reject.latest-pointer "$BAD_SUBMISSION_LATEST_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_LATEST_PROJ"

BAD_SUBMISSION_VERSION_PROJ="$TMP/bad-submission-version-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_VERSION_PROJ"
python3 - "$BAD_SUBMISSION_VERSION_PROJ/submission/submission-package-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
versioned_md = path.parents[1] / manifest["versioned_outputs"]["submission_md"]
versioned_md.unlink()
PY
# CASE_ID: l2.p20.reject.versioned-copy-missing
expect_reject l2.p20.reject.versioned-copy-missing "$BAD_SUBMISSION_VERSION_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_VERSION_PROJ"

BAD_SUBMISSION_DOCX_PROJ="$TMP/bad-submission-docx-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_DOCX_PROJ"
python3 - "$BAD_SUBMISSION_DOCX_PROJ" <<'PY'
import hashlib
import json
import pathlib
import sys
proj = pathlib.Path(sys.argv[1])
manifest_path = proj / "submission/submission-package-manifest.json"
manifest = json.loads(manifest_path.read_text())
bad_bytes = b"not a valid docx archive\n"
(proj / "submission/manuscript-submission.docx").write_bytes(bad_bytes)
versioned_docx = proj / manifest["versioned_outputs"]["submission_docx"]
versioned_docx.write_bytes(bad_bytes)
bad_hash = hashlib.sha256(bad_bytes).hexdigest()
manifest["output_hashes"]["submission_docx"] = bad_hash
manifest["versioned_output_hashes"]["submission_docx"] = bad_hash
for item in manifest["package_inventory"]["files"]:
    if item.get("path") in {"submission/manuscript-submission.docx", manifest["versioned_outputs"]["submission_docx"]}:
        item["sha256"] = bad_hash
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p20.reject.docx-authenticity
expect_reject l2.p20.reject.docx-authenticity "$BAD_SUBMISSION_DOCX_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_DOCX_PROJ"

BAD_SUBMISSION_COMMAND_PROJ="$TMP/bad-submission-command-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_COMMAND_PROJ"
python3 - "$BAD_SUBMISSION_COMMAND_PROJ/submission/submission-hygiene.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
hygiene = json.loads(path.read_text())
hygiene["format_generation"]["pdf"]["command"] = "pandoc final/manuscript-final.md -o submission/manuscript-submission.pdf"
path.write_text(json.dumps(hygiene, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p20.reject.format-source-command
expect_reject l2.p20.reject.format-source-command "$BAD_SUBMISSION_COMMAND_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_COMMAND_PROJ"

BAD_SUBMISSION_NONPANDOC_PROJ="$TMP/bad-submission-nonpandoc-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_NONPANDOC_PROJ"
python3 - "$BAD_SUBMISSION_NONPANDOC_PROJ/submission/submission-hygiene.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
hygiene = json.loads(path.read_text())
hygiene["format_generation"]["docx"]["command"] = "python render.py submission/manuscript-submission.md submission/manuscript-submission.docx"
path.write_text(json.dumps(hygiene, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p20.reject.nonpandoc-command
expect_reject l2.p20.reject.nonpandoc-command "$BAD_SUBMISSION_NONPANDOC_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_NONPANDOC_PROJ"

BAD_SUBMISSION_INVENTORY_HASH_PROJ="$TMP/bad-submission-inventory-hash-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_INVENTORY_HASH_PROJ"
python3 - "$BAD_SUBMISSION_INVENTORY_HASH_PROJ/submission/submission-package-manifest.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
for item in manifest["package_inventory"]["files"]:
    if item.get("path") == "submission/manuscript-submission.md":
        item["sha256"] = "0" * 64
        break
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
# CASE_ID: l2.p20.reject.inventory-hash
expect_reject l2.p20.reject.inventory-hash "$BAD_SUBMISSION_INVENTORY_HASH_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_INVENTORY_HASH_PROJ"

BAD_SUBMISSION_MANIFEST_PROJ="$TMP/bad-submission-manifest-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_MANIFEST_PROJ"
printf '{}\n' > "$BAD_SUBMISSION_MANIFEST_PROJ/submission/submission-package-manifest.json"
# CASE_ID: l2.p20.reject.package-manifest-schema
expect_reject l2.p20.reject.package-manifest-schema "$BAD_SUBMISSION_MANIFEST_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_MANIFEST_PROJ"

if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "20" ]]; then
  harness_validate_results --phase-through 20 >/dev/null
  progress "phases 0 to 20 authoritative harness assertions passed"
  exit 0
fi

# P10_REVIEWED_POST_STOP20_START

HASH_STALE_PROJ="$TMP/hash-stale-project"
# POST_STOP20_CALL_BEGIN p10.hash.init
bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" >/dev/null
# POST_STOP20_CALL_END p10.hash.init
# POST_STOP20_CALL_BEGIN p10.hash.set-mode
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$HASH_STALE_PROJ" autonomous "fixture" >/dev/null
# POST_STOP20_CALL_END p10.hash.set-mode
mkdir -p "$HASH_STALE_PROJ/safety"
printf '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$HASH_STALE_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_BEGIN p10.hash.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$HASH_STALE_PROJ" >/dev/null
# POST_STOP20_CALL_END p10.hash.setup
# POST_STOP20_CALL_BEGIN p10.hash.complete
bash "$SCRIPT_DIR/auto-research-state.sh" complete "$HASH_STALE_PROJ" 0 >/dev/null
# POST_STOP20_CALL_END p10.hash.complete
printf '{"safety_status":"PASS","files_scanned":1,"no_data_declared":false,"high_risk_unresolved":0}\n' > "$HASH_STALE_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_BEGIN p10.hash.reject-stale
# CASE_ID: l2.p0.state.reject.hash-check-stale-safety
expect_reject l2.p0.state.reject.hash-check-stale-safety "$HASH_STALE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" hash-check "$HASH_STALE_PROJ"
# POST_STOP20_CALL_END p10.hash.reject-stale
# POST_STOP20_CALL_BEGIN p10.hash.accept-next
# CASE_ID: l2.p0.state.accept.next-stale-safety
expect_pass l2.p0.state.accept.next-stale-safety "$HASH_STALE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" next "$HASH_STALE_PROJ"
# POST_STOP20_CALL_END p10.hash.accept-next

INIT_PROJ="$TMP/init-project"
mkdir -p "$INIT_PROJ/.claude" "$INIT_PROJ/data/raw"
printf 'id\n1\n' > "$INIT_PROJ/data/raw/a.csv"
printf 'id\n2\n' > "$INIT_PROJ/data/raw/b.csv"
printf '{"data/raw/a.csv":"CLEARED","data/raw/b.csv":"LOCAL_MODE: sensitive microdata"}\n' > "$INIT_PROJ/.claude/safety-status.json"
assert_import_fixture_source "$INIT_PROJ" '{"data/raw/a.csv":"CLEARED","data/raw/b.csv":"LOCAL_MODE: sensitive microdata"}' data/raw/a.csv data/raw/b.csv
# POST_STOP20_CALL_BEGIN p10.import-local.accept-import
# CASE_ID: l2.p0.state.accept.import-local-mode
expect_pass l2.p0.state.accept.import-local-mode "$INIT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" import-init "$INIT_PROJ"
# POST_STOP20_CALL_END p10.import-local.accept-import
# 2026-05-25: Phase 0 verify requires CLAUDE.md marker block (workflow contract).
# POST_STOP20_CALL_BEGIN p10.import-local.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$INIT_PROJ" >/dev/null
# POST_STOP20_CALL_END p10.import-local.setup
# POST_STOP20_CALL_BEGIN p10.import-local.accept-verify
# CASE_ID: l2.p0.accept.imported-local-mode
expect_pass l2.p0.accept.imported-local-mode "$INIT_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$INIT_PROJ"
# POST_STOP20_CALL_END p10.import-local.accept-verify

BLOCKED_PROJ="$TMP/blocked-init-project"
mkdir -p "$BLOCKED_PROJ/.claude" "$BLOCKED_PROJ/data/raw"
printf 'id\n1\n' > "$BLOCKED_PROJ/data/raw/a.csv"
printf 'id\n2\n' > "$BLOCKED_PROJ/data/raw/b.csv"
printf '{"data/raw/a.csv":"CLEARED","data/raw/b.csv":"NEEDS_REVIEW: possible PII"}\n' > "$BLOCKED_PROJ/.claude/safety-status.json"
assert_import_fixture_source "$BLOCKED_PROJ" '{"data/raw/a.csv":"CLEARED","data/raw/b.csv":"NEEDS_REVIEW: possible PII"}' data/raw/a.csv data/raw/b.csv
# POST_STOP20_CALL_BEGIN p10.import-blocked.reject-import
# CASE_ID: l2.p0.state.reject.import-needs-review
expect_reject l2.p0.state.reject.import-needs-review "$BLOCKED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" import-init "$BLOCKED_PROJ"
# POST_STOP20_CALL_END p10.import-blocked.reject-import
# POST_STOP20_CALL_BEGIN p10.import-blocked.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$BLOCKED_PROJ" >/dev/null
# POST_STOP20_CALL_END p10.import-blocked.setup
# POST_STOP20_CALL_BEGIN p10.import-blocked.reject-verify
# CASE_ID: l2.p0.reject.imported-unresolved
expect_reject l2.p0.reject.imported-unresolved "$BLOCKED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$BLOCKED_PROJ"
# POST_STOP20_CALL_END p10.import-blocked.reject-verify

BARE_OVERRIDE_PROJ="$TMP/bare-override-project"
mkdir -p "$BARE_OVERRIDE_PROJ/.claude" "$BARE_OVERRIDE_PROJ/data/raw"
printf 'id\n1\n' > "$BARE_OVERRIDE_PROJ/data/raw/a.csv"
printf '{"data/raw/a.csv":"OVERRIDE"}\n' > "$BARE_OVERRIDE_PROJ/.claude/safety-status.json"
assert_import_fixture_source "$BARE_OVERRIDE_PROJ" '{"data/raw/a.csv":"OVERRIDE"}' data/raw/a.csv
# POST_STOP20_CALL_BEGIN p10.bare-override.reject-import
# CASE_ID: l2.p0.state.reject.import-bare-override
expect_reject l2.p0.state.reject.import-bare-override "$BARE_OVERRIDE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" import-init "$BARE_OVERRIDE_PROJ"
# POST_STOP20_CALL_END p10.bare-override.reject-import

# F2 (audit 2026-07-07): import-init must SKIP leading-underscore meta keys
# (_safety_level / _meta) when counting scanned files. Before the fix the meta
# key inflated files_scanned and — lacking a recognized status token — forced a
# spurious BLOCKED on every scholar-init project. Regression matrix:
#   (a) meta + one CLEARED data file   -> PASS, files_scanned=1, Phase 0 PASS
#   (b) meta only (no data)            -> PASS, files_scanned=0, no_data_declared
#   (c) meta + a genuine NEEDS_REVIEW  -> still BLOCK (partition must NOT unblock)
META_KEY_PROJ="$TMP/meta-key-project"
mkdir -p "$META_KEY_PROJ/.claude" "$META_KEY_PROJ/data/raw"
printf 'id\n1\n' > "$META_KEY_PROJ/data/raw/x.csv"
printf '{"_safety_level":"standard","data/raw/x.csv":"CLEARED: public demo"}\n' > "$META_KEY_PROJ/.claude/safety-status.json"
assert_import_fixture_source "$META_KEY_PROJ" '{"_safety_level":"standard","data/raw/x.csv":"CLEARED: public demo"}' data/raw/x.csv
# POST_STOP20_CALL_BEGIN p10.meta-cleared.accept-import
# CASE_ID: l2.p0.state.accept.import-meta-cleared
expect_pass l2.p0.state.accept.import-meta-cleared "$META_KEY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" import-init "$META_KEY_PROJ"
# POST_STOP20_CALL_END p10.meta-cleared.accept-import
# POST_STOP20_CALL_BEGIN p10.meta-cleared.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$META_KEY_PROJ" >/dev/null
# POST_STOP20_CALL_END p10.meta-cleared.setup
# POST_STOP20_CALL_BEGIN p10.meta-cleared.accept-verify
# CASE_ID: l2.p0.accept.import-meta-cleared
expect_pass l2.p0.accept.import-meta-cleared "$META_KEY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$META_KEY_PROJ"
# POST_STOP20_CALL_END p10.meta-cleared.accept-verify

META_ONLY_PROJ="$TMP/meta-only-project"
mkdir -p "$META_ONLY_PROJ/.claude"
printf '{"_safety_level":"standard"}\n' > "$META_ONLY_PROJ/.claude/safety-status.json"
assert_import_fixture_source "$META_ONLY_PROJ" '{"_safety_level":"standard"}'
# POST_STOP20_CALL_BEGIN p10.meta-only.accept-import
# CASE_ID: l2.p0.state.accept.import-meta-only
expect_pass l2.p0.state.accept.import-meta-only "$META_ONLY_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" import-init "$META_ONLY_PROJ"
# POST_STOP20_CALL_END p10.meta-only.accept-import

META_BLOCKED_PROJ="$TMP/meta-blocked-project"
mkdir -p "$META_BLOCKED_PROJ/.claude" "$META_BLOCKED_PROJ/data/raw"
printf 'id\n1\n' > "$META_BLOCKED_PROJ/data/raw/x.csv"
printf '{"_safety_level":"standard","data/raw/x.csv":"NEEDS_REVIEW: possible PII"}\n' > "$META_BLOCKED_PROJ/.claude/safety-status.json"
assert_import_fixture_source "$META_BLOCKED_PROJ" '{"_safety_level":"standard","data/raw/x.csv":"NEEDS_REVIEW: possible PII"}' data/raw/x.csv
# POST_STOP20_CALL_BEGIN p10.meta-blocked.reject-import
# CASE_ID: l2.p0.state.reject.import-meta-needs-review
expect_reject l2.p0.state.reject.import-meta-needs-review "$META_BLOCKED_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" import-init "$META_BLOCKED_PROJ"
# POST_STOP20_CALL_END p10.meta-blocked.reject-import

ZERO_SCAN_PROJ="$TMP/zero-scan-project"
mkdir -p "$ZERO_SCAN_PROJ/safety"
printf '{"safety_status":"PASS","files_scanned":0,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$ZERO_SCAN_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_BEGIN p10.zero-scan.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$ZERO_SCAN_PROJ" >/dev/null
# POST_STOP20_CALL_END p10.zero-scan.setup
# POST_STOP20_CALL_BEGIN p10.zero-scan.reject-verify
# CASE_ID: l2.p0.reject.zero-scan-undeclared
expect_reject l2.p0.reject.zero-scan-undeclared "$ZERO_SCAN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$ZERO_SCAN_PROJ"
# POST_STOP20_CALL_END p10.zero-scan.reject-verify

# F5 (audit 2026-07-07): Phase 0 verify enumerates data-like files (by filename)
# under data/raw/** and qualitative dirs, and RED-fails a hand-authored no-data
# or partial safety artifact when input data is present on disk (B0.5 hole).
#   (a) no-data artifact + data/raw/*.csv on disk -> Phase 0 FAILS
#   (b) genuinely data-free                        -> Phase 0 PASSES
#   (c) artifact omits an on-disk data file        -> Phase 0 FAILS
UNSCANNED_DATA_PROJ="$TMP/unscanned-data-project"
mkdir -p "$UNSCANNED_DATA_PROJ/safety" "$UNSCANNED_DATA_PROJ/data/raw"
printf 'id,v\n1,2\n' > "$UNSCANNED_DATA_PROJ/data/raw/secret.csv"
printf '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$UNSCANNED_DATA_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_BEGIN p10.unscanned.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$UNSCANNED_DATA_PROJ" >/dev/null
# POST_STOP20_CALL_END p10.unscanned.setup
# POST_STOP20_CALL_BEGIN p10.unscanned.reject-verify
# CASE_ID: l2.p0.reject.unscanned-data
expect_reject l2.p0.reject.unscanned-data "$UNSCANNED_DATA_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$UNSCANNED_DATA_PROJ"
# POST_STOP20_CALL_END p10.unscanned.reject-verify

DATA_FREE_PROJ="$TMP/data-free-project"
mkdir -p "$DATA_FREE_PROJ/safety"
printf '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$DATA_FREE_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_BEGIN p10.data-free.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$DATA_FREE_PROJ" >/dev/null
# POST_STOP20_CALL_END p10.data-free.setup
# POST_STOP20_CALL_BEGIN p10.data-free.accept-verify
# CASE_ID: l2.p0.accept.data-free
expect_pass l2.p0.accept.data-free "$DATA_FREE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$DATA_FREE_PROJ"
# POST_STOP20_CALL_END p10.data-free.accept-verify

PARTIAL_SCAN_PROJ="$TMP/partial-scan-project"
mkdir -p "$PARTIAL_SCAN_PROJ/safety" "$PARTIAL_SCAN_PROJ/data/raw"
printf 'id,v\n1,2\n' > "$PARTIAL_SCAN_PROJ/data/raw/on-disk.csv"
printf '{"safety_status":"PASS","files_scanned":1,"no_data_declared":false,"high_risk_unresolved":0,"status_by_file":{"data/raw/listed-only.csv":{"source_status":"CLEARED","category":"cleared"}}}\n' > "$PARTIAL_SCAN_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_BEGIN p10.partial-scan.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$PARTIAL_SCAN_PROJ" >/dev/null
# POST_STOP20_CALL_END p10.partial-scan.setup
# POST_STOP20_CALL_BEGIN p10.partial-scan.reject-verify
# CASE_ID: l2.p0.reject.partial-scan
expect_reject l2.p0.reject.partial-scan "$PARTIAL_SCAN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$PARTIAL_SCAN_PROJ"
# POST_STOP20_CALL_END p10.partial-scan.reject-verify

harness_validate_results --checkpoint state-tail
progress "state-tail authoritative harness assertions passed"
if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "state-tail" ]]; then
  exit 0
fi

# L4_COMPLETION_TAIL_START

# F05/F06 (audit 2026-08-25): completion runs the verifier internally and
# derives required outputs from the contract. A prior disk stamp is neither
# required nor authoritative.
F9_PROJ="$TMP/f9-stamp-project"
# POST_STOP20_CALL_BEGIN l4.f9.init
bash "$SCRIPT_DIR/auto-research-state.sh" init "$F9_PROJ" >/dev/null
# POST_STOP20_CALL_END l4.f9.init
# POST_STOP20_CALL_BEGIN l4.f9.set-mode
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$F9_PROJ" autonomous "fixture" >/dev/null
# POST_STOP20_CALL_END l4.f9.set-mode
mkdir -p "$F9_PROJ/safety"
printf '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$F9_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_BEGIN l4.f9.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$F9_PROJ" >/dev/null
# POST_STOP20_CALL_END l4.f9.setup
# POST_STOP20_CALL_BEGIN l4.f9.accept-complete
# CASE_ID: l4.f9.accept.complete-without-prior-stamp
expect_pass l4.f9.accept.complete-without-prior-stamp "$F9_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$F9_PROJ" 0
# POST_STOP20_CALL_END l4.f9.accept-complete

F9_STALE_PROJ="$TMP/f9-stale-project"
# POST_STOP20_CALL_BEGIN l4.f9-stale.init
bash "$SCRIPT_DIR/auto-research-state.sh" init "$F9_STALE_PROJ" >/dev/null
# POST_STOP20_CALL_END l4.f9-stale.init
# POST_STOP20_CALL_BEGIN l4.f9-stale.set-mode
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$F9_STALE_PROJ" autonomous "fixture" >/dev/null
# POST_STOP20_CALL_END l4.f9-stale.set-mode
mkdir -p "$F9_STALE_PROJ/safety"
printf '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$F9_STALE_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_BEGIN l4.f9-stale.setup
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$F9_STALE_PROJ" >/dev/null
# POST_STOP20_CALL_END l4.f9-stale.setup
# POST_STOP20_CALL_BEGIN l4.f9-stale.verify
bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$F9_STALE_PROJ" >/dev/null
# POST_STOP20_CALL_END l4.f9-stale.verify
printf '{"safety_status":"PASS"}\n' > "$F9_STALE_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_BEGIN l4.f9-stale.reject-complete
# CASE_ID: l4.f9.reject.stale-stamp-completion
expect_reject l4.f9.reject.stale-stamp-completion "$F9_STALE_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$F9_STALE_PROJ" 0 "$F9_STALE_PROJ/safety/safety-status.json"
# POST_STOP20_CALL_END l4.f9-stale.reject-complete

CHAIN_PROJ="$TMP/completion-chain-project"
# POST_STOP20_CALL_BEGIN l4.chain.artifact-setup
python3 - "$CHAIN_PROJ" "$PHASE13_WRONG_HALF_EVEN_PROJ" "$REPLICATION_PROJ" "$FINAL_PROJ" "$SUBMISSION_PROJ" "$TMP" "$SCRIPT_DIR/templates/claudemd-auto-rules.md" >/dev/null <<'PY'
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import zlib

project, phase13, replication, final, submission, fixture_root, workflow_template = map(Path, sys.argv[1:])
project.mkdir(parents=True, exist_ok=False)

if workflow_template.is_symlink() or not workflow_template.is_file():
    raise SystemExit(f"canonical workflow template missing/unsafe: {workflow_template}")
workflow_template = workflow_template.resolve(strict=True)
loaded_skill_root = workflow_template.parents[2]
if workflow_template != loaded_skill_root / "scripts/templates/claudemd-auto-rules.md":
    raise SystemExit(f"canonical workflow template is outside loaded skill: {workflow_template}")
required_executables = {
    "setup": loaded_skill_root / "scripts/setup-project-claudemd.sh",
    "verifier": loaded_skill_root / "scripts/auto-research-verify.sh",
}
for label, executable in required_executables.items():
    if executable.is_symlink() or not executable.is_file():
        raise SystemExit(f"canonical workflow {label} executable missing/unsafe: {executable}")
token = "__AUTO_RESEARCH_SKILL_DIR__"
template_source = workflow_template.read_text(encoding="utf-8")
if template_source.count(token) != 5:
    raise SystemExit(f"canonical workflow token cardinality mismatch: {template_source.count(token)}")
workflow_rules = template_source.replace(token, str(loaded_skill_root))
workflow_contract = (
    "<!-- scholar-auto-research:BEGIN auto-rules v1 -->\n"
    + workflow_rules.rstrip() + "\n"
    + "<!-- scholar-auto-research:END auto-rules -->\n"
)
for label, executable in required_executables.items():
    if f'bash "{executable}"' not in workflow_contract:
        raise SystemExit(f"canonical workflow {label} command is not bound to loaded skill: {executable}")
for filename in ("CLAUDE.md", "AGENTS.md"):
    destination = project / filename
    destination.write_text(workflow_contract, encoding="utf-8")
    if destination.read_text(encoding="utf-8") != workflow_contract:
        raise SystemExit(f"canonical workflow contract write mismatch: {destination}")

sources = {
    "idea": phase13 / "idea",
    "literature": phase13 / "literature",
    "design": phase13 / "design",
    "data": phase13 / "data",
    "analysis": phase13 / "analysis",
    "tables": phase13 / "tables",
    "figures": phase13 / "figures",
    "evidence": phase13 / "evidence",
    "review": phase13 / "review",
    "manuscript": phase13 / "manuscript",
    "verify": phase13 / "verify",
    "results-locked": phase13 / "results-locked",
    "citation": replication / "citation",
    "ethics": replication / "ethics",
    "replication-package": replication / "replication-package",
    "quality": fixture_root / "quality-computational-five-role-project" / "quality",
    "final": final / "final",
    "submission": submission / "submission",
}
for relative, source in sources.items():
    destination = project / relative
    if source.is_symlink() or not source.exists():
        raise SystemExit(f"canonical materialization source missing/unsafe: {source}")
    if source.is_dir():
        shutil.copytree(source, destination)
    elif source.is_file():
        shutil.copy2(source, destination)
    else:
        raise SystemExit(f"canonical materialization source is special: {source}")

for relative in (
    "review/agents",
    "quality/agents",
    "submission/semantic-body-prose-read-red-evidence.md",
):
    target = project / relative
    if target.is_dir():
        shutil.rmtree(target)
    elif target.exists():
        target.unlink()

overlays = {
    "manuscript/journal-spec.json": replication / "manuscript/journal-spec.json",
    "design/model-specs.json": fixture_root / "bad-preexec-engine-project/design/model-specs.json",
    "design/identification-strategy.json": fixture_root / "bad-preexec-engine-project/design/identification-strategy.json",
    "data/variable-dictionary.csv": fixture_root / "bad-preexec-engine-project/data/variable-dictionary.csv",
    "data/measurement-plan.md": fixture_root / "bad-preexec-engine-project/data/measurement-plan.md",
    "idea/research-question.md": fixture_root / "fallback-rq-project/idea/research-question.md",
    "idea/rq-evaluation-panel.json": fixture_root / "fallback-rq-project/idea/rq-evaluation-panel.json",
    "idea/rq-selection-rationale.md": fixture_root / "fallback-rq-project/idea/rq-selection-rationale.md",
    "idea/candidate-rqs.json": fixture_root / "fallback-rq-project/idea/candidate-rqs.json",
    "verify/manuscript-verification.md": replication / "verify/manuscript-verification.md",
}
for relative, source in overlays.items():
    if source.is_symlink() or not source.is_file():
        raise SystemExit(f"canonical overlay source missing/unsafe: {source}")
    target = project / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)

blob = r'''c-ri}*>>W}mNxn>b^Y&Cl7L;CGe%t)12Sw!P+%b;-2t)zHKc198>I8{=bI5~LPEG(+5ICu*2tA<gPMq#%{Tl1??0CNWt2Sap8hlc$3GsU<^CV>a=&}He>(g>!PB?>fBe7yaew@_8C{RJt9bZyzu=E+y?b1l!{=2TJ$rgLTE+h3DxU8qyWW3Y@2>FOtKG`!hTh%ipH0^-4F0lO^d48Hos4$Jf8+af|8!|YPpfNjP3juk7koFlb%wfc{_C)g?bLIIiEC_j^o)l)aox@{hnl<Kkw3)q@C?uBJgm*rcD2KOZl3acXYVk3bai~s!MhmIi}=p<*j^j+jqA+tJR8ropZ#mS<u1HvbkoCi_S5KwYwNuo_&0Xq-St|_#q8V2+`jmD?$Yc&dDp#ox!6YdJMv;La$B=>gmvQQ#9Q=U*8AzkH*CDyR$C{%E&UnYj9=Wno%&`cTDRE7!?Tx;|2#5r{bHuC<N33)H^J(LzH28-r?VIPx5rxXv*%1{-|79L+bcRJd_SH=t`XsW-RDJXy!B1273<H=W4<&aykGRZr28%Kt~ax9Sl4uE4pZ;$N-Nea*U<8uXurIf;f&WCoP)7+?AGYU|F(2a(a1bR9-SpV^UW>o8QxLfuJ_?a(13Hq-k#`OXn*A1$>(J>WQVxdBd&d1?euS}7M(Ml{dD6R-NPC*uv}ohyY^09-zx4NuoqZcH^CZpI=eUbWiQvYXesAucY~GD!CuXxHN8vlZR6jJb?>g&dz_*7=q-G_Khe}I@tyfoPUpqB>KE=a#j|fT`Tcm?S({yLNoT#_59?Mha_PF3hiis=aX!P0W((S->-dWwUsw~~VR;iBS1s(R<grIj^3aIgjq>*t{IxdiU|~ezI#HgJ-D92(cFH~J`xe`&*W*vb($OaWPS2O0^}6);BIC!E6Q$rSk_#c|c)Ku$Pej)%hxn?(lPUHG=V$Nl?d}2J4QO8$t=>1{XWq2eF=)XV?r_!*o*4xhT_?DnuK7lLK8oFzo6dGT;5#p7i5rZ!Jn$kGTxmQW>D==0^R&Z*;f}>TWQH9ulLu}*i<#x^y#AHuTI&-}!_*DtZ8yErC+46cbBZ+@#Jf00$PE0fEkP&#P1GcRzz3ZdT=$H1zO17ztu<J-SQCxDtXs1Ol6TmjN63;#&=swBi|5g2_+8U=O?*Dz$am@G&&zn~6#3@-;2Om5B%{C&akig(2EMQI7s)@@8AD!2+Wj5za|b-j|5`4ta1WC6I5YeXpFev^Z|6DQ3*^@Z*K6Kle8gHbl3OEFe*tge{v^vHI`e3qD15!=5%DiRGax5A;L{^ybxP;z9KR{F%61v;`O39;pWcJN=MM@EHu3JiiDu<><HO3pT8G_?Hzc3AjvuMdyjPx$^%_`HlPpm0m-8V1B|O-&H9BX=w)}mbpx>Y$M-?6I#$9~{S?Xc^poJ%rg@R6uMmZQRC7ta2g`mkT?i+$1_n;Lz&!EHwjn{vJ{+2XicO#<Xl{3^<EqW)&Fte+JkG`#pQwSaScyHn!rX71R$!WF`*FpamG*s$F=;0Y;uO2N7Z;P{kx|j418YG=HRKE+|0vV0>_hZnqEziAv7Rq@G`S0fIHRs}8ZP2cu=b8=&W`W*4q@)|Y1<B)))QRAsOebx;#g=GVllN?cKZhFWb@1pTaDnoEb6oo`eBT3406%2Uysgv2Uhv4nQs@Svq0z4RJl8vQeS))xzR?IDxTM2LZiaXd$QvO8c6zS!NoOZ3W31!6o*^fI8#vC9|AlvLfmTSDk$l(!&q40==p3Mncy=F>JHQZzonwsROm3Yna2@ouGvAQ>A<O`oq+p)xJ*AG!`N?9*sQCP0D$i+A(XqJiO-~0N6gt6Muqw?%rmb!wsef}heLYIO{u*+A7_fL?ctI3;!RW}-b%*x{ZO<9BSbx)D!Fb2gb;5(tn3%JWnZwAn<|mdypO{|2gK@|qJ15Qv{O9ddx^r9O$Mww&7$tg!jCm%xD(Q5jd3}!i&NY@^owzeHT<hwHzuU|h854)4__xOUcF0mMaIL8ZeROhzE9fR>u$1BYX~O!w9kZq_=&TO62AcY8A#+-gS-^xi<Brsmqqb{#u^Vil>$cIPA8p+r)L9zEEQM}Np)YYAbH=f2MFF!$9Tt07-!Q`YZ@D!;a%;Su^g;PC>(KMPeifTT?r%NlLoX(bCiVIvb!)n7T%oV;AcG4#0DKg!q%4TUo?q)&za8EKdy-DVAHug%<|QAI(+ZCbwSQN6t)MlD+Xc33l7|w<LQm~iQ5XDTALO|R`bfwoS(AK;hdbbG;EHeqnL+Yb@GWFa1YGqEvQgC;CBNJVx?g=%cdQK#yxr3l#%${)RlJtb@WZM#&UJ}$f5pyAx&^)8f~FV7=>_`dLD*_{ox2K;$3v1q9qdDT+u{M%cf^`rSbzKg*$T`7EMyD?X1R?<m9>_<%wF>MUMK%LvJ8vUegi)}D7Z0w?>+c1w^gOSStoe!Z0{DOPBVmU(~K=r=waBa_5;~fgl*}33p$Qxkat616??mGk#5i-=driW@OkNgW?E97gSS%VxZrmeJigYr<0c$uL%7s+=DO$1lL`Lj#uRdBV*vMtUO!B^IX#kGanp61_g&44hg;T<Le`(3c!^1*{cMx|hWr<@@(S2FJhC)wxdwPVn8lO62YCQI9e~ea->@KrjPYa0y4VZGv1f%E$tGq2GeaUxESKaXsLjXcZrcs~Siv#7+}6e3f@Y$a<iDi->52EFm|FtBM?Bc>xHF8oF%BT>TFe+6y#R99+8iO5PoCqpC)OCU3%|#{c$ODH3gfvh^p}nIn`@q<@JAdG4hR2ukH9;cw2ukX4Dmf*%0<Y1=6GAk-Gp1cm;u$`{u(#tZTwEB{hjpZ8i#y@oq>O2kDURohn;~xEZ7_&zp+0a_Qi$$;o@Cg<sEd`_Z;@UeV})NTm&|2i+y)vd&kXD2W!PTN4f{ygR|{;uvIwLJTVz?#0c~-(kFOF?qCmsHTGbWde%6=nWfBPx@(Z0Vr|Ik9WUjY^vO6UX?M2dS-WKa#AEEU9r2h)Uf^#@4`GcR=)DuO{J_I{aJCxu8ghRa;ys`%UHs04?(icw7`1t72Y5HUOD|N<`l8Jy<ucBeY1pIG1*Ncfl(?WB&w}m+%|XXN7rJ;Z(f>FAJx6ZZ3$Q-u=YiqI(<3*bo2_*Rx)Sfipp&*+!Kb-A-b0@(aIM`vO8<t?xq2ppc0So6!<r3V%DjMV6wl~l4fdHGlJU;d${2<M4>rg(!o{Gm3?Ef=jNvX|-#O!_+y{}#E5d~p8CA76S?x3BOshJKaPbj;$d=p-?7k11?4}Gq&Km5jiajFqUiIhF4pa5Mdghs~hV436^u<SXB;>Orad*{6*NeOxJ1DR@e!jmUx}I$_J2ro}ZvM_6zz{e)UE<<>Z@U(F4R(b2_~Pz*Pr$c@9(~B)^#lGI(ElN`(Sbc8@*j%*`9AOKZ(%!ppL@j>A183T!0Wpv+#uFV{4H_%bZT>Jw0Z1aZ~ptg|KtCZp62`0{rdT^`?mkbU-ysS{(8;FOgf2hS=EmMdp<k!ho!K+qId~BD(wxy+ls7(?cWkUKE+23zBPR4_O4dZNpZA?oPZ5^+PcC=I0FXlq`&}DPZ+}^Fvw%Gzt!L4vlkzj1vs{o(LMQu$Y=ZPw!(&MbkLPAY@vmb+qwJ!I$;l4BKCi^x1Uzm1=e`RnxE)1$c=|8HjExJIUsl#y8a3Hu~^%h_R)ZBgUv(dDb8KRv~h-UTJ{0>gJiQx4|}ggG(Sxm@DFe_`EkY_+BfX6p5ykBinI3P$R)pM)Qw$-W6k~p_H`%ZmI1pTdPmY5@$TTIlppg$RcCa9bxYBud*Gn>gfjz<C;2FOO8Pu*xW1Bp=!Wlq;*9s+<9!60yopF&gSUmudUg#-Q}}mGJOv(!fPanU;*tD<u<gkwrefZ){4ArBwXp?em>Uv%OjFOCC(PuqEje(_Y{!6SCRPNTG3`JvA6Wpsm~I1DZY>Ws7;Mrl@K?ee4(zkmVfz7rje*&QvDe>*uA}Z(WepiV&1Gv74sKY7s#|d;#D6$bt&Zgy?Y703u-DcV{>^Ugr+ftN#a`+W`8a)n6Ua`e(BRRfxPd|=nQ!rNb=N)O-J{jDF7z<Y?s*+Um#MmVPd<zpaFHD@jNJacWOo3Qo87H9l>Y0wy^!nDSL7$K{s7p~m9hr-+>58chdczH4H)nxY<JlA-j>BfVB9F4z~=YNK?hg{pY=lEnhtlSC!CGO;`z~qea^rSlYR*PVjb+;Yc?lne)b3%5CGR;-I;%f>`L-8IX3z1G@QR!Uu~bTw;TE1;taar?`}YLIrjA>qY<1TI}|qAeoQuU<*aZ`=sTSJio5%I46te&CO8irGAt}HQq4ZxXMPLwvOcZy&{gV^|Au&{4@8@8bneW_m(!Z`Hz`Y_oon?1o`$eB)*9^0EeH1W`g0w>-vPgFacxML*8|S>tX`D+|1av(??~4|t{XP+o*mvAC5F6Rc+eM-kYBJx6R&Rf<2u4a9_(y)AHKrVAG41?O79$d%<=9M3w!6du#?un^RNYtag4nNZIh1-wn+;5Fk$Zm1K3g1jvK%(wXR^}4#6k$1ol;j>^jzmt(Sa)-uGlzb)IQIa*Rwq?p1x?NcLZ!(P-hvzICK-yamQsnWywNeoX85{3Cnc=vVkV^d64`*o@E_&<M`F&7BeKGU$o`wvpi`lfDm|ZrYhxuwyM3HYGc86SiL9ws<^9CMKxgx;nwO+D=S6W-)_K8GVM{DUPJC$j7Pr8ZXEfU^_`~_%3kA6J+l}u~UGVxbb-zK9j!PD2spGu;+QjZ;p3${72~E%XY_}e{(^@Tw+R{oAVZIHRxL5Q^CGYPo$g4*UE)oWZGutK!e@fX5_O7LfxY?Nomi+bV4!4fONqe@@Q)CpclVxLnyknHGaus50yAzazU14I0tkr*MF@SXLAdQ=<hx)uQPu|r@)(kS6<M5aVzZbeiXRQ^yrxkdo|UC56OazPN$FovzVEq7QUx(bBI0N0^6(;27T&6p8*GxKN@?>V3~oIuRo(7^(`=ku$3wHD)K|3t|sjByEpfl=!y1N<Xk{z;9l+L<<0D{y8ey!8u-Ek-Fksfz7$}@IcSufJaa_;EQ1AC_!+VRG|P=y$Yb*HkML&$><PJSk>7{3B@ZZu4vZS}PhpY5F3b6_ZgVJlG5ap$Xl|q3E=u|GyU{b@bJib`|8qOBc<9B0l*c3JvWTz+a0y|&bsJbCVkXmBIt6yO3A-CEzUNttaEXq4q+SrF!0-B}^k2EhvB=Z8g!8gJ#lF;HB%R|bUjIIN4z>}aGwqY#k+Ab1Va@=U!HZbBX#qEErEDGVyuJ_G-gF3C18+cH%nkY-VY-Pk)krS_V?b_SeMZkwd`apWGcvHh@0Ahqd)DAU{_l(iAF=1ZolJJgcO3H_?8}7Ytw(zXjKET&S;&RJ#lC}vV|&L8*edA;pZPmC##MdDZwL0L#ah4}E#}N{R*)5?ocMR?e;iZ1_&~WM(iZ2h#r()O@tnnh?{ZqB9JSBbac;{OdVjR5VmS}*BItXO#b1J}gzvN?zt)n84V~Zrb`*c2Z`JD-+ehI?hQ6iyvg>AkyNJm%KQhJLU<cIk3i-l-2MGHNwIWUtxChps9#{~~nRWF~)~7$cWtGox?%=U?ME75dcfh{vo1O_d4B8$ixAE!4OX|;`kw2OCbT8!#zSC;hXYstQ?q7Gr^WN}7e(+4+5fl8I=gNoQ`COy!&Ud0Gkz?cNkcsoZakl*ZXWQ`H&z*0>p8wD@=F)fCA{j;4w_^9!V#mBC?>nmIjZj?wUHj=RYuB}x*aMl<hWqxfE?|=H@a}uc0UB%XqDlK(Eygd;k>ctiMt?oVIryXt@*G&1-#YA;F{TCk<oUn4rtG@uv$*b!m<ah}S8<l7w9oeKy7y_l_IG)GVt-#=e;f0B;LP=RpZWPd<#J&s`Lli>$`5@1ea`t@jr-s^u$P42l`tIa)l=%_pW%I1t+9+N>bcL@ZhH>bg}f_y=W=W?!v`{^kmsOGH=op_QI_wxm2s+3LRkIQy3%f~QO5>0p9EL*Cvj@m-J6j{yyZzd{8)+SVL#V5w5QuGFl)4~#H^H9@m)9b2}Xz8mdr)Jbwq9qaGCV!{cxYL%AeOtzFbqj(0hIDN>0%`d~5H|4a#N2P|5G62v9K9nKj!nhZ&U9;--{uH-}9HoNof-25a)&wzx$(2?LGwL)aK|*kP^#J2!C+7kq~ON$q$-IU?4)&Ld<~y@yVY&bclx@@UpAI}pCy*X_5D)A-w%;=OdP{UADjZ`^?1?Z^z+z2;N{ji;2)f^&;lf8Byz(Pk;@xG`uvU6Wt4#rrrv%3Cz1u=R-cL(n96#hf1}j=dvaznABLTvu_4x`w8_z7M{8aqZ&n`(wg9*G}Y)$uq?MtWUg8^$pk`$_EQ(5l<;k6}GO!G&g1m>|a=u<CyZFfOp#973^bZxE9&L<hvyP;5+a_%B;2VS^dP$_0!hBkvTHBj}A@~xhlU78~zXsSme|+=JaJb3c?O*k-wVufa2}lvi>a5tC%d7c{ihA3R?FguTQaD8+J6Vj7c_8-rZFKxwiBAvtZI+gDz*0OE$R4H0S}yLW%>E58u^Uus%*K*yH`HHh8Ex7rb0YJ?H0h@BexE|0-U6n<vK6#Nh!?2knVTbWZW5X^UA5yfIIhGw<+#G80K&;O8`KF>|g@92fdxno!&v`~kl5x1KdkCnn`u4)pJc(|-a_ycz3wuP*3(Z(UH4fAo$q)d1>wOd`N~2qXXR8a(|YV_CJDnt18>lz*At8n!_>n70eA`Od6!yYD?qOgz$9It(EHjfpiN*|}xGaLWi^SQNXwI=PM)K~L?7-n?Mb#`|=<cuX~CI;Y<OgHhfF@B1<2jt;qftk*UuzSr!X=I1dmDZ31pXfD`>t`(-92^^SuJMejj^dEHRiQ*%|zfZAki)k#dBj6nD%Xl{d_7S?1;;V++Va71#*1EngTE=%TS>2|nx%HhBbe7D!`GN78T20Hl;wp4b<VVLIQ;smz^0|Z^fCq;m={?q`oM{_tnS*2IE$kD{?@FgQ2XHZX9XK)tZZz;F1~YgcSi*4i`Z>KTRw>Sj<h74?A5y#<a%t4&{Q>rT4jDZ)Ab&uclpj3Bdu~8Ov}brf5mBL-Im5d^H(QibJqLZe1~c7@=Oo{2e!8XHs!UES7ha^E*AMmOe#n+k<yRh?pB{2r%VP7-%RSZlzCsUq9P`x}(A6j6Mpqw<n_hh){#Sc1S=)7hp3uFU@Of?4a)>LmC!fXc^lJP8dQ#Be=XLPg@q?l!gk=4u%vHDemdBtkW4xVMbKp{8Ye5ddHiJy^h}VNP;Te)!Ef2f^J=^ju*j?5voPcgYd%9=MgbrudpY@CS%X6JQ)1`fZ`%rG&Ldn^sda+^MA0gtsjlB%qg{`ebEh(qm%U~&dL>;Od$n#xgZn^!hwvy)uTVK?nmGQYVzNnmu@^4-Ek#1u>e5F?A=s9oXOf>r`sg6+Sy;Y0&pdp_ntMSkCkHqzh9@VJ4kX^jG%XId6J}B1gy(|rRW(%rAP2O!kt34xtJ%9%nvuL5bL#^gh;BX~Icb31d;ty}Jjog+k@;pfntj%uXUuWy6(9TC?jfy8S-oDe7xVDtV=Xv*8ox9$ZwbRf+3%twfrXg3DYMX(TG8`FDKDN6U9kTWPQ;9v2yhxXNSDZsp<6=Z%mJ=nOIl0#J{iRw1@YB_)n%Ak=Ko{#L-}Jkww$n##;rCtpMjl%QvwkdBh@P+3a^<xJgrgg6Cl$jhGFRGChRnTOIvQ{=us!shh?zmQHRMlLeMmQ;RZ;Kost@S{d4xrt<#`Ta#a<D80Z2c+YOkEF^&@uUWtn}H{a!lSt1*R3zLvLajqmu}kLR&{zvp@4nOyKNY{tjcuJg?|^{4Ooym#3sA9-Fy_crDMRqC(u+MtC|e7B*tb!--xbf~Fy4>@hVOGYd83NOCs%aZjh=?_#{0C{~PyEv<Zzu2=ye4gc&J&JRZ{d0s(HM+T!BU#-)ckyPeQR8#+bNkWHDS53YYNp@)43!Q_UASM>>wT)dnr<wmp0T;UeACn$<watN@zymCkoSaR1;%^ESv*y0*5zldMXRVA6tRc=ysI_5@^{TOLHTF1qQ>RS=d9?YybiRXmitnU+@+oZwLBvGLB&3lo9o9><R@=@4}5Yz?4HLDZ>UD9f|(P_E6VP9#)DM5NPRxs+($G#sI`YGePlIbYVBrE2NqLmbyb<ydB|nqB|Ti`eRrRHM}Kbe`CD0!s%oDW{0Xx@BmFb~5tlmU>OFqX!d9>3mF_6s69M0EwUu+M<)fcKqp~(w%}WJ-X!}+B=rg&iMNN9)SNwZ<)B>w4MgI;?IdZMWehIMSXgx0Wc^P+iBlGl9t7D~m^`%YKeX8OiI*Yd2Z$W*&metQz>icp#7H2MM)0$<Ds7dR9&Z!?$ZohSEx!}9P2d2M6N436BEv?$G>~lDS;_g1ty-xTI*QXU3x3^^vKG<^iH`6M<FZx5h+lEv9#*}+uEEnUKRjfzZvk61Av)*|WGkIF&ec*;gtn-lddIKGe^FA^%CJK3j&#G8;4{VwByII9u?RG&JV|pl`qv!~u;0Mr$_mbzv-rtBGdmB~e(X*so*o#-K(MH()iC)_M*FD+qA*&Zud#tFwijUg8KGm0JJ=3svWM{mrv;5lI-RJ{7CC>GUh*uco``vEclxm&aj%SKq60M0fJxxq|%hRj&#2O`Tz*;PDJLG5f`n|2^40L8OZDP%+jv<kCQPGZ@xQp`sm7Y4-L-1cx^fL*(fEfeL4dxovOz{2&_oLdXdCCLwrEgB2NxA6wUNEPa7bMVC+YJT@`6fM!YWi79{U3NbNLa8*xplQ`vg@$s(nmpg&x@^+&ormJVd@ESn)H3@DG^Qjo5YRh`h@m|dLKCChnfX$Fm2=KK*XBUt0NCaCuWQiF9<a*e9F{sCv5TlT&2lOZW8~O{uQ|gvk=$gy{9Sb4|F&1wy?SJ_a=3*-&mVYaVYLgQy%jzr?{;(+_C;P5Gzk-A@7fl%p76={2jMK@+a@=HT-Iwzp#mdE!DQ|CjCKcVp9K#;cjBh(~09!4+*>r<(ROO8;gDyCl-Vv@5FT|b}-O6`O4z~&S;H&2=V-JIJvISqb7RCK{on=)*5qo2pdq}jUe;w<aMWnQHj@u-++2zuHq@-<CE`1qE}X_x2XnS^ux(*VO0m@y`kpyUTYOQ8vOD`9!C8=72CC!`zAKTcO$a{+4%^W|F4bIdGg&!POYhq`?{yE;z%2r-B^v=Ref`rPbQise-D?FuWlyljwPKd@l@)ecB96~d$P~sbx)(-fOCm;H=N{JZkylrLg;eY8*EXt8OnD~zwbMj_Jof;_Z_j%&z^Y_zbo<M*?S+B!skxC1%=-u>vz~pAN=~e(g)Q`B=?m*rotyHX$1SeGNao5UwE(YOSk3wm{~lA`p_2GrANJWA)|?ohoqCY*z?Dgj3retN#0Y=?z^w~iMDD?`vW~8*1N-!Izjwr{*QkwpZ#6EBgBpn0jQC(43A6du6Z-2?i%2#Y{d!^12?ABg%E%LuP3U~ql3`sL)DsBJd3UIi|F8qdoE*<f$+Ez9eZaFge<)56x2?<7oS1h8(;yi1lm2zhRnT)FIi?8t?NOt6apZktc!)(U4W`Xz?q7+Ro<1liBbg#z5ip@x#6s9YHoeP`h9ePbW2a+iMoy@S-0VrY6pW3-fvXt=H?oamUrGzyHqIFFc3#{01DREVx3J^vA1>i<I<utd>vAzsaxcGq9=q9_1u!Vr49spyFirQ&3NnWr_U>ATI-lIeD?DQ+I2SsUB&*jK%00D(0)@?;2nFVK7%NK>3E&`J7vEw)}KdT&XB+80@wXZW}VC)sKe!11T5{%nKf#t`j8zkBzF=WMX}-)P%<~l3e$7X1a)xC-qBG0?F@BrwAK_gD(R#B;u<Gdq}m~;J&K5~8~0VYH(B?hYYzCDqMC8EYltubjf+a5jDAY5OpSgnbQ3S1r=s^9RoBm_;l9*u{4eQo=>|n7noLq=-lG%0(-nT!jzE1Ed8v*TOMbH3Laqp_Lh!C4!<Z7;IQ!mT-Xc1)K!uf&UY)9%+XpQ_9jjet$1S|eU#wq^4rJGBP1n~nSa!YJbbYJo`pI?E^<l&HgJZ+>C)V_QYt(do+H^f{dVVb{IJ@3xygq5Ve$#Y)r{Vg9H9bEVG+aMQ8n179elTsiUT?adH=Td5Zo0nRbp51h|I@3cZezJuRp>v}L&5IO`H^J6!Z<|ti!<4u(MZ!CT_ue)-n2*kraijS8)>|eN1FENs@+KAjWl}IL?fq08gF{O)x@I%t&v6>pWnozgC-t5HS(y{#G|8QBaJpaKWO67QQAnOjXcuCqa&m7`bHjU;?YqPkEV@0nhqLh+<smzpeL!D_CjF2X1RU-y)U`_CAWW5xotm_Cwyg`41q}%{G!P4V-@2N2Gk!)`-3oG&2uiZsD#Hs-nYD0iEmCKlLhalcJ^<y=PuY&WRpFv?)2RAMA7o&8HU~GcFP&hrb-7n%DQ|4?i99;z|ED<u}>}gSmH70yDXB!uG9>h!d4>B9qf*X-nWMTXsXGfve({X3vApI*c3KsxH72A9Yy{cJMJIc#kO+&(y%*ZyTW#P$S^wX^{L$J?qMZ5{PTzW{2I^Xt;n75LJ>}<X%*Ri(iup5I=c@=cl|_Gzu`Wnw_V-vyel~Dl5rwCJ5pptu?_5ovyZ*UmFO(**QyOg6f>J@aC($om6d2mOLV-a?2reF9%R{0E7jg0dx`Lho7ow-x9S0X!WqaZG)CdYQrDQ!)PsAw8x#FX`@nu+)_E87OLon9w0Ty=P1lNT<nWigqNLOzs<)_iAIGQ2Vd`I>MeXt~6q%2s;)75#Luq2ecD+;W9lf%a+Xcy*L%cG(tukU-kL1yN0q02%Rui_X>`}9SrNKKDcV4I~ihA99rXysN97NTGXMk?^)vkusu2hc{u@P9cmc6^VWP4IZAx*!@y8Rwx1ju_@wUmmTdSw}T<iNjKm)8dUFQb~-eH(bH*~3VFE|C>bUe}o2U8`~`CWS1F;hv(|8E>u5Xr%O4)%_$z<fO=GEPV(E*`a?J<P#}~COqf@U#YySMc(PXfT3jcBf~A}*+hxrzEWn^x}`SBx963d$Wva|SY7ykE1ylj`0Ncn<9A<t_6DCBUwrl!pRK?6><vDfTz~P|8+_LJ;<GpStm;$y;<Ix;JFzc)_6DB~k}p1ci_h2>pS{6n{7av`#b^2#pS{Ir?iZiE#b?PEpS{6n?Jquii_gL@K6{<dYVocwK0D{L(dmoN-r%$Ijyzv{R_C)XefAcgX<vNy7N5<(`0Ncn<6rT!xA?5}#b<Bv+2)JS-r%#zm%s51K4Zrp&1dI1UCLfo>todXmP-Ch-esXSos_C<pS&!Gt5RQ4>D+vkOib#)z_+f&BiGs()NPN&^Ok3Mk!Ou)QrvE0vBc}s<Z+q+4&Di9`ZIoty_mZBxyCH;f{nqgk;cqCcKudmY>{u3=N}*3#g(j%HQj`#+nr0D8!d0gf>|(eXact%dZNqfEEMk;Y-!T?i7G!`V;H&4=){AKCcCeOx|q(MZd#l=vR*3{(V`CJe6qVo6Ic3I$B8vfXiA=IjM}0Tn&_H1>TqMO)0A_X;7;8psS_p-sKenlcB#9h$y&_Xv?k_A$F&CJP`fhOeX%`)7R8xV>s91LGnO)qQFlL4={v-lvDRQjljaRK2vaYZcW9ELn}%(#&!}^vL0viVKB?EoJEc_JyzVe(Zg@e6{TT*o4T@Tu^W)FI>>|P}-dM*m3fvY|)ndO4Mit1xDB(CqG5tK~MX*awJhgXjI@iQ=(lvF8J>vZmFIZ!(*lR1=F{)U`S-8g3;Hla*M$K&>Wz!Ic)X6br)S(^p#DhT_&jTGXof(4;?yu8CcP=`7j_^)b26bkpu8_RHIWlXYdDQ9I+O%=z9gn8UUpH5Tmt9Rj(?xagSYPd_YPS32i!M5)Y_H@dW_;|Ej$QN$y2)|?)5>?6s`_^2XSDB)G}qWAr>qCNs4HL33)`(6TXP-K>B9$EDY|K%CZ)>hsQZ>~sZ468?)Q|Vndebn?CA2Q9?9wlDW5SC73!Mk(sQAcNS%%$zf^he%<S=a7DmI_>)pXBxs=Vi<Sfoyjeo^@g#8j7z9^5^H>FHJpPH!Rh0eoU80U?(N`6{2bQ66Y&*XKTR7d%sbcMLkv0c{46;s4(v|)$#-QC<9&*rapLc^Yd#srOA!Zhdkd)55!1NLSsy3h;#M3vf&)4Hm;qOCVD!0z?6X7Zz{6Zq@6I_AIz&|Khi(Je@J)VS2C<(!99+5iHXhmm<Vw+F9Rj(<j8OuyvCkCzwvm%RA#@}gGn@g*;Qh`d;T$%`K^FWO)7;>XL2T7B1-y!a9FqE^HEB`<!2yr|Vgf60p<AusAR=3nyShsX=|B`<!wywJYn#gCU4{0m?F1bN|p$%`K^FIr#n;>XL2TECDldGSN!MffEzez?4-^*H*H7e7K?)O$vK$%`K$FKRuwzU0LZkr(Ngy!i3*f`8$QpCB*hU-II|%M0U6Ui<`k@s)q^6XeC_OJ4kVdC~cj7e8EH)O)~w$qQ9p$mv@D#^2TH4$*QK|KsV~^Iz-xf5gkj+I$Du7t-#E>4B1-BCR%IYv((szpA;bb{l(e6nnC#xeMLEcWB~Nc9yjn2#_=F>h;u9nm^!~N#4s-<hYi7A755Z=h5BUY5sXbzU*0z!hA5a=1C<#SLu7%I31^~M``ZcUg>px;jHpK%qNQU#YEp~pZzTVJ)igmJ~6k^$gIpKph+uu2extVdQa4o7&NKL$>~aO)azc>PqjzyE~mC+J&JFu@x%PRwEIOboAe?kFz!L8`YN8*<_C12NfwFRVl$ig*uazC!h7^gF&hIk+1m>K&nLYJ+RSCmbTfslu}#~>ItzJ76M3+P%KAn(yaU?#=85Usy&?x1bo5P3Ba`dhLPouSKBZi~@j*|UOKY#>zl$l>#`a|`r&zA0H(CCttzDi?A*L^8d@rwq?&bN^@y4lsD^tuQ$e&X^!-n|^lROW#K7l4%|3XZ*qaLo3X6Cv*oe#Qq_TVj?Q0KKKolx|!Y?kvm&F0gqLw01<X^cgW;cPmhn5IJ$f~qq<dN_*%O%KA^SLS#e)Ly+KGm`@*y?gZRCB2OAM$Z>`sk1g^zP*bxSsFgo$~@PwNTtVdUW?G6&&w%3LKY55Pv|R}n~_cPn&&v>x_7;F#&gf!Y)ULO*obL))%9)GEt)*Njl}e+n_@1@#uvPwuXmUNA3^pCOb2?7wB_}swX5=i>hd~N6O~B5J6z?t<BPl3c;WO?sms_G6Ai0VhKjz?dH-iwQ?W854Z3M7F+#(voZvBk_uAB=?5u}f(rw~A<a={_KJ5L^Jes|Q%RV5h*+*n``U_-r`UlJE^i#50|B$Q>m-x&V)5*>zj^}kkMepc$&SUy#V^7<%Z}~&5HpjB<-qg~^^S7|@S&#4rJE@o>aKZM;WpO?WXG)V3ubXMigB>N$Uz}OBRt$8$Bzy~*R^@eFsZFA3d!m2&hTdIFfXmK_U$>ie#7%U}CZvg4Mh`ZJPcpO0durcus_(pD<CYWbsE4~t(|23;p_svSJ)Y)Rd^Dh$JhRAw9xCjGJ2^41y1rg|4}3|ri%alzA+NG&eZ_h~Q=pqiX}4sPR4=T(Mx%Hp|CY;9N6TgW%zsVBXP6?}i@N;nC4$EnYpH*T2c5Gi)PEbFoK5cgiTH%yeFUG(e*r$3|H1fV{uz9te+Zw%wRaZ0Z?`htMEokI^?qOMGXI6x#r+6&F@6DdG5%oeVtfX>@aRL>rS{H(_ai@>a!b4^X4QRPOk?~)Ow;-hrb&JQrb+%_Op|;D)A+wXrb&JsrkPxS1k-GO0jAmf!I)<A8BEju{V~nv7h;<5BbcW13ouRR55_c|&tRH~{o7-j&acBXgX0G<&58YdKMkJw$6}hZwZ99~SiRpJ)70tcXJQ(fY4LtcV-0>jrm+TpE~YtK`+G3W;Pl&Lni?JbR7_)yK7eUz^GtpUrWquEE~YtK`+G3WiT(C|ni?JbTuhUG2-76L0MjIYFsAv8pT^?9Kc@M0ej1t|^Z`sW{RNn2`Uhj0>1QyF_WNU+=`X}I^N(N}{TE;w{SU@8`e!f=|Ly%WH9Gpan8x@Brs2Dvk7@Ys&&4$LwZ9M3c)vZSsnOBT#WcxBFwOcGV4C$GjA_=N!8EPkAJeRVA*R`U1k<#C0j6pH!I-A~8B8-7{`Q!r{R=To=OdV=)}!>NV4BI@pNnbgYkwc6iGF)bGx>EjOf(ns{g@`W`uUh9xcYN3&Dq-DgK0*`-yYM{=;)_nn&2a~sH0y{i#qy)Yf(p^sYOlLZ||q6(a}%EG^6ALm?mLA-%o>Q{;`<mZ0+yDG{N|H$24_1`nj0qBYv8I{Q^wG{$NbQK7(n}-yhSkUx;a@AHg)*FTga~AB<_V&tMw<+xuy1bo6sEjs6i#!+*Y?2G9I+F%AEWpC+(>drZTBp`V6-q}NQ~{sK(n{=t~W{S2ltet%5k{z6Q%{s^XN{Q^wW`hzh|>r<FU|LrkN>lb30_D3+y<mcBt;hBFfrkQ-E?kU**_Lye!>*}78$w%s*g76n$n(z<CG~s73P3QN=G~utqH0jj`FbzBYd`!cRe=epuTl;%3P0D_IKTVB}er|u7(|a+^>Si3U;9HAXQ8cjzt%)-|dDbRz126WhdCLu=9e0L1*Ye{@e|>VT&|t=><5^RUSywuX-Ig1VTCT-Gf4EowO5>>?G3?n}d}Kj)VjYm7_F-*CqJR178Z_8i7udjyvF}6nj@Ybvj~}BCiuZ+H@RO_K2s(>sDeFagSY@BzYN!91YEK6iTqQiX(jfZ|)L;3wHQT!J33Ng|(sA#bS$YfF@t`Zfzn$9{JGU!&2>c{)5@@Wzh`0`Gp#JP1=wlY*JqP*=c>ihCA3SBec?7RW-oN2T;5wyucl#r}Rjj2-@7cbH9{HV6;90!OeN{depQ*YX&x3BTL+X3J-b4SAZgFNsPyTu@c<>U=>$JVMyEyAE@zyh8NxAl7-Ss~G)Nk_$I_glLZtO3;2gxV!R`i_d1KjTf8fd?AE$PEU<PEz=mvC#fKkdh8!trS@MgPxRobl3WKQC`)hbleOS<fCJzn|PiRP4zD@*FZ%_V+i3(96)jgg;yKE}YJku>9j{*ZJm~`cr)mp;uZ9S~qZAwO@IzuX~ZJ7kbjF_J0<A=b>-x=)3O6MIO2E>{cPOm1n=}e#KfJ?%tsTe&~9B(_Y%~DRI-$Kbh$s-PAQ0t<jktJ<E?K{Xxey+;q}s3Adt<$Kx2f!SKwvF|k<6jH$t_al~UU;(b5zf?>c6SLeZ0XC{x{?D-mIG<DsJR*T-Fn8Dy2H$<}~ruKjlde%E~8q|CI7#vl;uh3=et_QyBmFMr|pLdz1@!MN#M84xA?~gjS*42^Sbzx(SpMWO`U*O&+=mMSO1NeRhTeK6bTW)Dj-!N%kkS;20D_m!ie4j-hz*i=4{l;>-(1XVf+a0s}LMJ$6pXqp?D4UtkQ|2#Zw#5f*?s8qD+T07VM>O-}*%LOQI@cjPr~ETr)&J1bH$9R&#8<l8B77!vh~(kB%Q6(_{z81V0zS-Wgs+TQw7R}Z-m7cCXOD!-g>7ndpFj`KuUt#=<S(Jqh)=Jpdh~<zv8TO+y$N~+4dR?`<E^%;(sos6y(K5#tB3Z$LC^`S7?_UM0BlkHT;PfVYtGZNSviL5oOJK|?#Cs5x%BM9m!mxUUH2>2dZWF^H}oUd^Skz{e_F>ZnFL{*S#ynB!-&H!@|;0uV$Iv!#NVbJbH`0!Uqmb(L2q7lV0&ym%WXlQv|(E$6UW}d8VR{G+d`M5t~K1c!JD<~OwtrEv!frE3o(Q0Nn-cHE{#dv&C|E@f-3j;G5*!!eT81@k2c`DjdK1Ok4#^zLAQUGXbJ0&4A!3}lRNFm`hyo0_vQG6<OBE~I68cGTihspQo!rd4gg&i{s~-1vYzDN`~9vnve63rg5~zb*1wr0ODXdYzF|Ll##Y!c0!tdojH2ClnEjCL6U{MN30c0TbNH{S%+EjbRXhM4**gl^)1nzbT=)n`k4QeAzte7zbW-Tf<emD)?*2tKkknzg-wkMDclp{JZ>o6zvo!Kv+d$D<Z^_E{>LTDG|AE%+EyNm<+UEjW6xcIjY5kpi*zdk$f7kuE$TJt7{g&-@@qVRmru!Zr>knPe2mMm?cV;Kl@G{QeeBKpkhiGCLHq8Fp75Xvi9+m=cboNd6SR3|}C+5k`9%^#vo4b&6>PE1;CMNkv`PQ{~<XRg8Hi^#SdCRlB$g@U<XU%r7M-s0;Kk@)}M}YSU+>;yNr`U^G-ws`47I?wN;1+a|nd_KRr!UQ6O7X0UFQbBWCDy^Yv?)e`bA-;ax0Aky`_2=xmw0SPEPyR!jyfzIha9#NGv)>}y&VsRJBFXU7<j<JyO=zl^s$ZrwpNM1b``&)F6R)^b9sMAe!G+fz0eK(kOzY{i^s6hn9dC7TgTNsbCmL6WVpeo;{{g+k72u6cF6l1>T{=gftxUEgZH0zuy?U{U71g&#4Kkd%k<S=tT|<gJTKVEkO`-UOec%If)yy=eQ!UjF`%aNuF>IiYU4CEkKOCdf76^ee|cE`C;jgq@%{4Y`LFx<et-B!yxi{|?w<~4!{Pws-MIU*)Vl=u9zC;ECdvUuE;;IB`{3ba7A^Z3ii-xhee)c_aOVRjWBpMGPbd>?0t6Yy-`hw6yYqo^d61>?UVHu*lpP7PJ(S|B_aWi4BxMy3pFP8V{T)lE48Xnp1VRaxWV9J_NTe9<NJIE?Kp4v*o7e-qM<=T8QS`jNvB_Y>!9_6*Cp>dN!w`V*->-IJKcMj22N)GP07ioQX}7Un3r-i`7X~%mw*&<`8FJ*1+XL|aFNEXsg=-JeSkr~lSSJnN-E#m)Tf4vOrmo{f{!MtuhZEk$k12t+Ou&`Sa;(>nyTT}ekb3YJvp@<O0oD%?x(60)=U|wBvi=qR^p@o_$Ksu&QqKpM+FKAlK)e___&^F(QS>_q80{VVOM%B18F1J0L4wcAJ+Ff(5wN*!d0PldVc6Xk0JXDiR0P?*tM55I$oK3VYC%?ce?wezs9!@udP#x6)-->&f7gr!2z40D=20p*(C`X0y58wB&{XcD2EP1@9FsVUVz6XxP_E7Gc5TeHTN#iQ4mY7(tMr_DI6se)5FGzm41pEFpUS{UQXJ9xW=6md{G}HTw6imi2_8oupl9i@1C&uTGK=Au8_(=g;QM*inhM7~z<dZ$8D*e2h9U<*ra;?F&kP1~<RlP!ospT-bT5RW*Rik9`Fq?p>>+?M_?wbNXrLwddcg|^i!I)3i2J~($J*#zd}C<PyW=|WOHXl>%<~{LK)s!M&h}+x!f=YCwltui1Oz?GfLR`p7~S|0_VgP$pj;XJ#Ja{hc<Y%Q2+DeJeHIW^XdViJzDom3$(fTSUii%eInC&x7^q1`3)@u&yk$_fJO{jEK;XOxqEPS>z+5JEWbZAL4nhikNYL7AEzRi3qad!J0r9!G-dk+9t3{7K(^iQvn&cT85#9~=zp?2ZgWCo658t6c4c1R|smP+S-21AN>fv?WkkP9uv&*5QkY_rK5wU+Ubix4!#jE?68)EC`{Z<vd;6;EhjfTGpWnAZ%7JncoqX)gZinGLwg$Jd75;A9m&p^YWOmsMPDDeTbuj8{vH_>6_5x<ZuD`|oPn+rv5;XSv|d5{$ZZ08O81MqrdKUEWYx~*FnAJEGOoP|QuWc145GYs|@0?Gh&&;GS=&K^Ne6aZA6l8{Y9l7VEjKi=c4phvJL5dhce5qd<*p%%bc90f~9+)FqW);HrvY25c{2sHLskHAGV&=`D?8Ot)Dt{Tc@{O=%Bv=tdriEtcC`YVPU_sIBEX^H}ZWP}hOy?BN53`Vw0r~+W4;k@BS@V`vNN@OB|OhN!}P?C~HPW2_8KQd1*>y~0*?*$%uSQ*|!CUYpEOP+USAN3Z_UkT8SYtE=%Z>~${Q5LwU7?;o=0MewVm}<Q5=<Gp1WdN|yt1x)tA+Uv@jYHwMkB8?@GJtg8Dy)}`MsYu2CtL8jFvOcNo^nm}7kJBX$q7UTFFAl)v}SUAR)9GSA{r9x;ab6$PxyYcx*=TG6}03x((yRLUUqOD8AQ2JU3^d7Gr|gjw(Tx(0^a|I0)aFP+pgi-uI`(hbUNsEcp#cR8@63@uAk|V8@$&dOJKU;0WfqV_}CmCX%PB-7Gzl6gd38#WR!sB3c8h!g<giyr2e2YcUu{K?;-#9#DAG=-(|A*hMham<r-v=CC;4h=gx%}!fGo+&*-G01EI@EW=ow)^bWaBPU<|d;>^(?@K4+!T#&6n@Yh><@`>=XyBJ~p(jk=T*WB^*bnE0c$Gpz-)j^Pov)~M)?t5eaN8Ii{l5SEQYQk_LW7WI6(jjl4XQvy;)@Yq2U*?W0oJqM~CMB;yHc*00ZYSM%q#K2f^I@0JxsvU%23}M3W4=y_7sa{0j7%H*!gcACz&bOh-db(^x+i1ah9P^&CIJmYXXM6yM!$t@$cCv`hHCR5JhC)wxds{fGZ@g`j-`C(1+2rI8I13+!!1AN<}CJtF%0HVV<|qhLJDod7<P>bunS9leD1bkNXJaY>djbQB;tC`NOOZIU}-OAfgQq-h7ldb%o*vE{#DzB!S4p_<OVRV<ALs4!<eU=&ZN&H7SprYiKTYn#-o&_8^{4QIeM(hpCX~92s~0UPCCQ-vDTO+ZZO{Rz>6qY%j1#GEe}6WJHp8j^N<;Kz)bLTJd2s-?Y#b#=346$Pq7cd9PfIiPs~9@Uc+!taTXfMIp56IpC=HivWN6?3wD!`A2VrJ8`4=0ew4ulU3;f}Y(J9|4A&Vor^B)GZX|ml3n^&``cUx3BCX5Xab^QTW>PSKk`*cGr#e6$cBsG}poigePMev7gFgR8_;EoFALH=gI~~FgFRL3*VyXUB#bNTg^C-i}QFlkSy1)%`Z98s70Z+Zqi|0DdFXg5SIvGo+l1b+~>bUU$=S1fh;yXZPshi>~V+K0reLL_RhI5a0I8%-FL1&5+sj!I*=-oJq1!fg=G(GWt6mv_^QpAHTC4t4<z_U}<V#eU;1)C0N`^fu)ljpeYiA7E({N8aB&mw0R=owNTIthF>hkjM?giN&3)Znp5_7Qs6?-X{n<83DnB^3}at-(J7jT`g!gw_=BaMGV^JO$0BGyIzaiwtl*XdZu9usOQc75JPI*<9=u1=uQhKwvNm#z01;nFBrof9~ACj>H-q@RLPN1vfecp<wF^nKH2k9o`QU*P5Ta{x;y&HpcG^X05T_Q8MYTp<`ydNk2S#>QL$24^fj>coO7<js5cj2Du>4op#Wg>t2AfNash-0zXm!Ee8Ll^vrc@;tT^GW6k|R%Hmnb`ao@_9pXFfy3?+7+zXpo(pOFk`x0*phg^*BI)2UnL(WY5D4ljEN(d-*W{sB>y2|}(wP0dBFe9JY$orDtz@wQy-}knZV2u3(etvv$ffrUS-V`9naiLf%;aYO66RvFx+}4u}3=v3evZ1nfhVFFc4H&o=c{g@Y*r)jU{-#H`U+U&PI}b$XGCfOB!SxS0E_qe|7c{KcOErH*E#VHBRU~LP*piuUBO6k_2XJf`7!;I94qBYMpW};|_TFxjzfJLzoF!%D@02BIhQ8g+_G0?o&)`iPrg^XbcV&#p?+V=2oCNka_Ad~=1Yln8Jcw9-5AmJvy(iM&^TxUCec0FE|Jh3uwwhs+UoRwFDQ)q$Xr%aFc@|T-ZwnO@?rVv0gP}FY`Qf`1Ah<tlck8GBlz;u>+vENIA5ZJu{eFF43l40T1foFTL;xZ)ydv<nIyo{6hv5YW42Uiz<J~9cKn6yaf*7X_nE+!U_%lbT;<y?DByV5Vd$u8mB8aAUcc)X<JY{^y$^k<f>zM;9DJlreE`SGRfc<L&aPhQ0bL@4KrQtovtZEThNN=xuA(U+lVf9SWUx3*iImF5M_JtD@2AU9-!r=e|wzK!0;U4SAp6_j85Qiem76zs#9c<c?jJ84NWdtT)lj9eHf(%2E`G9+S`C;Ech?AjjMC1_59c3HgIH71KK#(if4TF!9qfLB{GZ0l}+5YB6751v9t&Hvy42#W_9IS)k_|~B+n<&jHjR<(so<C*p`y{K5a^VG`f%gD$AMyM`vE3F1t4$drNuls={79{w5!HKgU&sjq@JP?3%xdBE{pOQnW7pfl(1PJOhVe|5VO?4a&X7O((%=>uAO3lDNyXVC*ZGE!2lK&TB}anDTwUea%=G*7Y+@0h5E&5_+J#UpE1*=GQueS~1p}oO&>q5gC+F6lG7LO}vPmSJ6?CwVBrPw<dF5?|Q|v73Kx9Xd5DCu$FX>fXpi1Lhu9<{XT4sz;7N*G9Om1P6;|vmE_?Hf~+_0|+r}Db&J`^R-9Gi-xSr`!jw2QOsHbpi>T9M_`TAzK-r@d0wDzbAAF*!07C%UXwkpaMl%$X~Z#YYAS6mvrKMb6hEvqWSm38!>+zsep^l|+8VM2op|vKllsWw7yF*#iI>GMF=+hZ_orij03V=fNR4%3c@haV`V-HwuQjL_21rRb?_cxv-zZZX%pI_25iMGDie*bb9amxFIt&q>85P3xS)J;a97ELJ#|{Z>6JZ_;fF-nks>>1^8Q5=U!{%M0xa#NIH@z6JlS@O0)5~bdp>h>QzT#9Wul9JUAx6q6|jMjN)u>cD<~cCEEF=ETTZ##*M3$B0{Es$ELd2$2n!b5lAK8C9o~er+L3_Wo0jvHv!x3{{HT`k@Peabb;@7=v;4W^pVR;zgTzSSO-7Cur+D#>{JG`3gZN8iXQTSY}JV%9CMKfgeldg?!wlnx@9ecH%~6<ZWDTk*0bnE*|Vi{QRoxZnK-T(U#qyAIc9B5W}rwX7#YKAAfRI84=MY%6H~y4GSLb>U!iB>IW8R}A6Z-JU>8^bYs`a<8^{NGZYUf+QfEGmZaCIGdt6I7eUvg4bSrpH^0fr;cpvi=<v~YxA7;8n!5#)Vb~`V)j<TtRLs9DM*$e41dZ%ioZ^e<PiK@6ntc3!gBD0S6C<D5cGnae>-8AfCABTI%%LiW#J}m%XT_++3x}cr=s*{Es&y>)RE)1!|)P1huG@0cHyg-$H3t%GLn+)1?t#@TWrB(qcd5JIrRewvm#@-UBHw3?%+2?u1`e61yca-%=!6fHIhOZh35qee97a47t(UJ!ZvjDcYx1UyOmQP&{$l$XKlHZU6dYWSfs=lms9T+A`pt^~6o<~EOsaeXpUJ>-Wm6%f|&m<Y{GiNVuOTJGQa3c(cckb=zz4AR)uvuBbW){_DgcXCOA@L+(&kSSafz{%iD%Gb{-LSA9^CX=-7+qFHwl^!o&1f2!*YO{vp(?SXqNks0NdlA!NkN<NtTHerITHn-k!ThBS&*}IK7%&Ni3t5Z3?yw<gRP!nKT~xyXq<FT9@we{nckCFQ^8p;RUXtcEPs}yQD$`Sy2`)xtxvk=`g4ggl}Z>9yzR<lkVVe_*?lv|MOjre7V_95-5>&|=lk$x!cE$nGmE{EaO3HeSW@1%qy_9jr$IJQ0OW{24;4IG&3@mJK7_nVZ;gy5s2aw!pRsNc_;rnWQzA}&?k~mlPWR|Ju(=HWD5_2G#JRmUL8hRiQtnF32iam2m6=hIfqxW1AZuXUI{ABxOwno(Hm|6W^toD;zi;OWX5innmIP3d;S}Vq%J8g0L{!I6!oZWfcST1EUAw3I+!u)p>ne}s$#BE2uo=Ohxz4>9#8k4AKh6VU@3&hP%neC@&=b~N=l$@+QkJk_lT56zgMYVqaCKtXQ7>k?XTfgovyRv2u}jY9V02>fESNasfTw)RVscR1Td(g$uJb-8q_U2RY`--K%X=DC=j4w22L8<S&LH8ID;>@B@BY<sVoehcWbPWHwr9-(ZiO0UqjH1RIXJoLx=sAgED9F6ZE|n}UmhnWYcXrnnwTRU*BaQ1Hg9s)l)R-@mB>9GmUd2!4-X>nTn`9GDqR%L9wl)u$KaHZ5oO7fPmSMQQxFlfEGv$cM6f)|bf@BltP&0ML6rfN&F<gu2kD<_Nbt<El$Q%HqI=5>S2eMz^8P9of=(MZV?^jC!lG1trzW_-&Za6x4cITD_k$b;M#+-r%=2q%80`#mDt11djgq9(1I8d5VMa-VS+b7AJCuZ=;7%oh(@w|_Bm7!}i1rTWViy7Tc^)hrj9(ycL-l<HZpbSc4STze`8R<*O~UsSOxCHpOuUY}RPjl2zU*FdV?PU9J*z&c;@75q;v%_}aE6+crk(@zfA-AEc?r3{Xccn5Ca=0-?njYyM*cH-Zo)UE*iV#DA$0f+aCK})0)q&wJ*Gh53k4D=nM?%O%kBetX1|KP3ZGcvLmJ8e=%_z1WM$~7tkk^eQ8y8CI;(aO?N>xLOXZzuJ#^;c-DUR-*pXYo!}*>Qejey!`?^=$Bl92RG<l92MfJyMGu7B(8igXcK=@N6EokJotDK7rT%CACJlqLah8GtVLCV^07sc8Xx|a!iOA&-7{o8qf90({$QC(}@7n>zB5H2OGuZ<**%!9PTUn%d?6PUNw1&Na6vV@Pd^v}kWz$Ah~u!-@`t+0|DxE4V$S>=}}yH@Bi6t<cAJsFI^xnTVwp)O0*(I9I(!bYIP%p&oK&P?S6c|Maw*on~L!lt6`KN;SqAkXQA0<#j2=d??Hgkk0z7W5FxZW!m?&njnFu>(2}GGHHGNOI~$R9OvtFRSJVOH)Es)dmzc3V87w1yr)CuNtl_d`9?g6Yk6tv}tXADI06@9klZ%My#HHx4I8brnAqJ;NP3n{XQ(yh`YTPQ6&W)Sy1wr(0L<KJ#=ebX}1<T+WkQ~2?obWaCLMl$u7kILRX07<wpK0lXNa)wD)1*hD84yw-z?kLD0rdFK9#T>G`^e=gXw1NZR?UIIk+N>+eRqEoA)%6VgvSyG~Z~R&)n-T`?dtIu{brL*E&`S^$E**e{2$Y3My#YGRB`h^g3>72SJ!04AaR=)7Lo5+!cbE&N8L=V-rQFEo*fFpvXyk7M2~M@?KRlWtUb){qd|oWwI|)$k&9EYYc3i|7QWccq;}bZT}87i57#PO>ShPOEk#5Xm?K1Cf2Xr4EXL>kP2wL7T_;k2+QubF62c@OZAdL71|5s<XZed&)gR`xwj_rT8iKf-BuKdFUFz$^pLL@8vwMRP_;UWHyo_zs~Tne5aFZ40I0s&8UM$FltlM8g<i{^xY$~MlFV?a%WCHpmc&ic%L>i!PC|_bkk@D44=BzIKckE-k4$?!$3I?>0fK9KD&`Iv98jI<p-X1WpEQ~p(He89J4e$dFGt#9-SMm=9#c~VlRRnk@A?GCKji}AYm)udnt!*7D+>fo2bteeu|-xi;xj^nqkn;rE0tWRfqRSEuMOT8*C$PG9CA)eQ$ZzTw~S{cGPz3#o(`gXz*a8PfTxzcWq;>r%4|+OJL(#H<|P|y6PLK_{DyBwcziU=)<f$@##WB_Fnt<fBc{Sc-ZZi(SM5nU#h30kTg`}_z6pEbcvDsY$dk#P?}2hCMvPw0yQXKLeGn>59Eq~nQ)+{pn%@H)s50Pu$u1y2-6L!t~|BzO%bYko!u%$q(8>gS983}hM=69oa`1NkN7<~kJWrDc2y5Gh|p@TIvR2eCHYJ9RE9BynX0%{Ar5G7AWEV})uT2)aTmP@QS6<G*9LPQrl2qDTW}3XGJ8hvg&-jAk(p?D$dgBF8Dfv9-ee`*`VbeCOJ6imQgRpLXiq5{v<7NGlGP9iHz2M%l1Wg6u??HTBBHrhab5NdMNIrJ(IB}A7lu--FJ1ncmo)~c-n*_kAE~j5RJBSof!D901}h!exMJ9?G#4leV-r=BMbEN{-b`7G^4+`U?`DPJYVK^Jm`8x|JX%t|m#kd?jW*XPWb{Ifb+S-WhfFAPmt-j|XSJ>Q_a1N#C*P5clc>oA(JB=$SMy%$*XOh<-%-HxVK+0M=zK(oDazcPL<{2Hf^G`>sWjr<o!|Ry8j|5!xrf<VRi35L5j9Dv7B)jw@neNw6HnAcz2)kj|C6Ox|Ab1<UERA{D#`_ZA3h4X(vaR%<Iytos)U(p-+3hzSCbDJtj}OY-IS`-mSthvToxPT`hz?yT=Yt9c2Q>yx&!@0q8Z>>N=`kWya8q^b<tT(gWY_e2Dg80O=q>R4f~^hhf>YRwf0a=t*SSwtewTCDNW+FaFv%gIH~Rjet$pAYrjv}&uP_VCByYp+w&l5Sr(NrK-RFsrgR+9Xgs^OdY&<8o?HhHdC04%Ls3kdmBHJ!CXnPV6ZOJ*xI(&i*e1gP^-xzVYgQ;^a&=fGz3k_@sqM)co0!~An+uJM^-#DCtdY(|?Z&7B2x_o&O7Ok|zSmhW(0G3vFlt%^sO38D32?ma#?bv1pfQ;U{ds%RpB@1T1Lh0}#^Pr?oH*2YVP0>xp@zt_#s;-Ue%J%gbZgCPh&HI9O4cZ5hc&cDFVqO_mKxB}I^Wz2n8?@q3#BfJpDX6jG{;@fYjYNluC)XGed}Z{7fWw@4%PeE?F&tE57aP64K=`&0BmL&HMW>Q$77{{?byQ<yJ>pi#2m)V8l-^Xz)kanrGvz?raGWI_Rx#nbhs6v3P5?UA8jXn>~+0Sq5`c;w|XU{vh%ZsmOqW=_S6jR>L9|QxG#9>g)s8}6*O3pGYXa=S2Sd^tSuHziW+)oT*gfG{iphX%nTQ4v$<X^<$IYPTewUqweKd+sjtdk1v70|=7~a%Bu6`W?my`K;Ks6vY~CP;8XtNTwv-q(t+|{+vJ)gWsNkoxG4C7l)gyUs3l~#R)`dxT%O~({6+g$)&3=|X@-AE}TsjAGZ5GebyCko7OJ@c>+-|D5*onH$NH*cD;9=k*TF*+Ps#F_3Dmb=y_ji6@%WG=g#TC8Jvv4)4JR|D&PY*>cuyVdryL-LRng#)$a=a+r)WD6@IA<xFPVJ_m@mD9LpVez~dR)b{eqKGtnB3jnR$)UKofp5p->+iUFvF7_;ga%ifIDG}dVBGArGb9)J<qXfUSCnC*~&AjvNPXr*n_htLAN5+si+;reYysHUZ!qU<*I7uuSHFKmTtQnJ$=j<&}=iE%Z#jM*bsP;+>-(1P%3N3GMiGmsmVqaDWcwDs4r!`LZ!i6mfDyqHcUoW(semg2AWtRZK502c$4~ih#Enq!KipPHB%)#dF$lsI{tGR>v3aqY^n(dJ%SfW7s#|!HJz~9jJUy$nx8lJ4Tn1!uI5@jt>KQ+rer^o^R!reKD{_pgYK&gy%?15T1z*$YitI7O?#@GUp;MErtRiw@aOlu#1oWao6F_;^D=q3zBH6pHa>f5l+_ANu3EjqeePbA7jl3=X$Q~LI_%1Do|5L;XU+aa%DI%^4|!TcCUf+qXl@wQ!i6;&toY<AVT{7JQB83e>XbS{da(>mig*5Z@qM!!<Gi=)J=H7ud05w!eFwsdZ);7BZ-s9_Sw~q9^@)2H>r#3_$vp*5pyu+VqbLlsr8H&L2KO9M*Y&c59-y!n*;Jyxk0OKWJr!gcUZb17uw5W$fyD@$c@aw^;M_1_&TPj;qqiwA+4@Me<Q~<g8q+qj!nPZP)XXj9j<;hD<cvAjd0@xP7)KL_wI)ubE;TE62#*wM;C*sEM-lFqFl(w!Od!Fu7kmBf)(ZwFmTq@$8bvH%Cty8|Tbnj;v*E?;<XThQ13x>{j%#gzuU$1H9(tLqXMH;cmeg51-cGC`o<()*17PwV)eX1EHSbcRIFp*OPEXvJZ8?5+ow>%S*1R7DR3D3X#hRvg{zmnOXjzj-YEHKmI5iz<oLunGjlj1pFYtF_zk+GYjRzgqvGESr&y??2x-nQVO1%D>YL0<-2OS=Snrq<ibY!^IRPrK~FDpl?^$O?)_maLpW;f<%62ERct(<Ao{=Q)^i0_@*D{nnZd{6a#%l;vRAt;4Z_)93<30x{dwdy`(rB0d76^;FKeDsa_-c<(x6s0v;ACt4NZr&{WR4cQ{8p2k}V$=qy&1DZ4eKuuD%))rwu4A8YK>5B`XM2(NQjwuS`(FvG`?M?Ri3cTQqT)}{W2vg=l|D$YHy*Om2<oXMQj-*Ud}vM;+io)-DrB!F@!+err`nH5wH?dGqi@@;m+tWs?9U3F7JJj!&qEz@<1Pr(W(_qRzU9_jn^*(LKdP}Gbs&3FAs_mKgs0=!P3?#okX>mMGQ-<V`n?_AKk-b~!TVC*g2csHd(JTAz^rak=|v_QNGp4@U1#B8FBr8ZCiHkJ`Y<G%?gtqRIT&;7k7rJ)v1dFn=aBb<BZW{Y{^JG%1N(B~7G#|@huoXCL~np#e*6u>qFFixf2gP0Wc`(5ZiPo^pon^;aEF?hZc^+y*30nwDgHzOcc3>?d&l~r&Ql&ttS$DOdRD*=wxByqyu0X$u#KxdAbvs9)P=njzFF`k?B>6q4_Zav7HbX~f(~-#&~x(?bPWA8i(P7jYI%_xdt1_XJRKa}fQK%0stCFF*C)Isoqakn@qC;;^`F6>E0})_ye`wvi`39e54o0$bF_g2W;>VC3}T|6UNGt79a0*+G&g81_^gF<$5~D(9pHpN;%rz7U1*UGXKjx{%Kf=s!FURGrsmkL<a3-E)0i{HKJ|znpugP{$9+L32BkXCz1$!Q-85`_eeA6z^gYp3>Jd$)ls>fXFzlB{v=~&<3+kyiS(EXsuSq-rMu2?j4}ljzCqab$!)gqibst(E_vT{#)Kg;$dS@*{7WfbHhxUJd1bqMlao`glwyJAf3WNXZhQYPxmjf3*TGCO<%`(;HdUTrHjb5vXFF)J!N~)3=RI}5L{8~%dkYp6~IT<f+7p^D|P|^j2jV+ol|2`PG+OH<!Lu=qY%tPCp+2f%V&BoLD@e5ObA57g$0|I+&>v;wOH>-GrN==2$zh^IR(A)*=qSezBA-k?lEc$lv14^&!NV==0`>1*}$KS;|*2%x#xMw%JMpy3j=6lpq7sm(h^UrU#6|A%Pa7x(6+3AKDHdRS2&ErTv^(@3QmH2ve|Fic%K2y+dmev$6_s>u3zjlv@|MdS_K3wb-Ue81LuQK)gQW;LwHmml!u9f5LD>%Ci`3Sr*H9YFG1$jrYF-GM$edw0dg-nE=@6RGi>2oRXsE<7{Nay0a24s*q1umz??N^W;)FUgb;_P@#LkcL}lzh+8J>}^XB_x${g=f)jV{aFIxX52s`k5PZdtk%qFCwk7Rr)f?U%rq%VzM?TP5CZcvdu()#D$R$T6y(Z-w3aZ9=CQmL@n=A)%*-f0X;pGLqWVm_?D<wyP7X@UcwV(c;$u4Up(WrT(Wn^b1%dx3;DY9o!OpxRA*`Wj}86kw(ef^M+<P4qWp$pCwXk8UPe{P`=KFK!%DAG;LG*-n)j?8b1t8GeLjS1C7wYxxwOA0{j2)$r}Mq3_voT`6aEB|Th}~<uQvGhe5i{~KERgj^-Swy$@%cYSNsY}&Q5l{!KcjwI*3<9&uXKd+t9ox46>@B)kmEcp3VpJ<=4;K7lur!19^*hM#F&3gNU(}`wW}tZ=DnMu)J_ivq#89JsT+Vj&mCQ&2s|Yxo}R)dYt3!eM$Z%{U#UpMHyK1<7sz(;>WXoaor0o8tNsF_-riX(BF>*%xDnJQ^pIGoI~h%{nGd3OpAG44#8I6WHJIeuo^>t6nsc&(fR)0RPvJ4eBYwYgOVrrv>Ga<G<zCW*AaQS4RRH9HGUAS2li2Q@Jaa{$f$^7bCrBuirXx*l3h6r<?3Qv5#@aqnSE7lmm-I(iQK;BLiQT2^?fECoPSTfPraN@4zZGQo=R`i%lXJk?x!Jmo%$|{+=*KLr|KJiaVhU%?<su)^Y%lPcxuZN1Jp<LUdYNovcg|nYaP?kWN%q&i{w9-IfqY5S)($~LGKp*l`rJuMlS4IoMTFZ?6Q^x+Y33)V%;L&W!R;2PxIVz>}jjkE3cOS=+n@+hM2gT&r%MJYoJ@@dz5RVr&<0B(UHi3AzD@jZC=jjc9cPxXTxHPJQQkuV9;JuZWEOk-tK!;N_C!B@cv<7%D^m{yTI;rnjItU4l|;D^_8Jni-!F2%23XN)(2|YVVO5t<jE*Q)f^dTWp~xs=u!@X(~5q}#eNrZM}3CeXT6g9@<c7y8cN|z`JMTO-8IBP%6pZ0G0y2p*xu*!NMwm~b-;BN7svf~AC0r*c`cQJb%p${w2crguOPQezv@08ysgkGm4#DohfZZ>XY+^dn)2^GQLg#QcZ-3c>M&jr*CM`J%$jG2IK#H|zuH@AyNFnQR$kheLoaf6*2eaAyCEL7)E=x0%29JFx%S6epZ`jnj$+%87f-dE?n`r|j(P6*n)=OVYnSs;>UsTQt=jT^_swaJa!o0(?2-H#Z<PHNwjbpPuH|4r>K%+T=zUZ7lwY5<R)F4^;ojYZ2IAuE{(AjcO8!euZ+A5e9xJ&o=a?_@W#8#MSEpCnH$7>uF0w(&15WnUmdfOzhp5F?<ll%g?tHi<?T^UwSY7x2cV&zYvWG0NxWlPD9ebzc-+cy6ZiOtPwgix~zy|rOgJMpC+DelAn$TH9qeTl!+15zrkcd)qW1K?27)qbve5k3?o`G+n=VXt6^8F~e<+o=;COa>_m`h{tF7>um?BjCyv)--lYg1p?SM2078>^awbY^3f{GR3hRleU-^>r%rsuMlk---5>pj8@9n!k&fyFxjLazE;`k3`#x?txlo;XBj@Ll<pos0FIhF7CV!a*uN7bSnS%%;C|mx5g9axb3XXu12lPL`yX@dR`i$WnG=FHW^(}3xY~N=5?|@n`M#Bsu1l4s13wa%q|(6<#`D|O^bB+=u*G!)XQwAtUo%nZVl>qq>)B0l=n8+u$3IXckpY!@_lihGkMOE&vt?a%66{_@VcJyS)8|)h3rgRW3!<a6vaFdQ}FEGlY`p(OX^ol=e+P<u-;VRBdVi=?5UoqsOJ!EQ{-$RdB)K}ZA*bOjAgrsS9^tLc~0saJZf<$>G^l%Sx?EAT$TBfZ}M)LTiGk<ZDb1FnV)HY7WJ&W?F7}RfPb?&T*pl@2dA-psrMoWKKDfX2mJnJy*qBIeW|_2dulV{(EKKwS{7`w)*Fx^;gcAay!WDe(b`VTGu){2ET~OpKDacqS7d7v(SGt+%tVp$Vn`+XFVuEbw$|v<*(82k@^3cdjN}%z`fQkubCw(VylTxPw%T1h$5L;WgO?wwXVEMJF4k9k*!NSF8>6uD{YvZQd|n&&ldz;{M@_ZBz<ZBH>lkxO@_xU(?q&0jLUC?#=A7_J<nNAaXByca(k`Ug0lu88cO!H`k&}<-)@Ijv_*oOJkyeJAx5E{42&A4LikiCozCyM;o!s7~d0*+0TJ|KxJR{LUmD(0%Eq6=X@%nc?S891B+Yp`Cb2anyS&lKacLIi5wR$;E=VwMfIC__SmKx2_`{zB)s+2PmC^kTHv$eblHy@m_u#qic2OH78E6bP0XO($Jx8->XnwuLqFKTf+pf<pw^(thFm<L#EyIZtJKIXXXoPH!$BOFb*Ql7mHIS?hHWu9mgI;447zpY%a`VL+{_j&PMMV8+b`Os-OAb#*v{(F?~W1d5pDs6;t2GKs7QAO>J1b@r>7HzmiyJr9TShPOI^L5eEcrUP>#A`y{(u~4GPJ={~G_Q{KI21GbGJBlbG-dkxY!=q<bWRPvT}2*b?fj)(`<hMlnm-ulIhL)v$#${3qSlD8_1fHKw(VKW;T*sBr>|l@c6ZhaDLXH<9^%TV;*Clz0r}0<XFSRoQ^kB$x?a0T*ZpZj&0wC-&pWu+H`4v@n4K*AyRt^Bu~ikd|9=twhpe?-J`XFmSMzypi*%s&CBS;#Y_0V9xb$`Nfcb_QzUm&6fBDhdhcx4h@{3Qm3px6rc~&#zJ9tUZT0DQL3@=YQVt9G2_DpS~RrrN&7i5dDi!+5~3sl)El-f-CCTq-fV*PJN@n`r=$q_n<TEsHHMfhn_kwY9~t<YnuUDI6JF0~)RTBOcs_B$0Vw6eUekIsGmRQun?mZ3zSw+qqouIXHx+l-P7H{C;4Ck|aYfB&@&ElSVl7?w3LB40(+3X(0{Q|s0)wdiV*U9Qy9lTSItnTWP$#e6X%3RNCs7CXo`_4B5=(Iqbz?E&AD5Ax<7*ILW2H6Hj|mR=pbevj&)b!N~Mx2Y!j$OQOzI!bvAT1@d-;C3h{jPey(f0{7Ui@7t<+>}wyPRFyDPI6xL(JJ+`LjTlyD=4kV#{vth`-q>9;8Qso<Sw5pn`2g*aXpJFvyCt0HkR>3Iivmc+!&gV=o&QJP38@bL*{rpp1O%^G5oH#gRK^0?U5Ug+7k=^jwvT^NLiTyw_Jk<)Wc_kKXeb)ne;cuN-K8JHuGY=UbVGy>_?C#W&M<}UyARFmgAN)Ovv{OIhfVQ<$kA1o`;aF1s#T`|Cwq}2O*n+D~$!Aq{FPwM<!Rw{IgnpJ<bj1z1?w|2Wat7%&4^HC+x+^6EgwlEl#<-1_Pbg@q}`)A;a8&a;iruqr9VF8%``&XX%LYFHc1sN_=|BS}rSXa7BK6r9Vbh?`JKf^{#dgzRl@i4P5S3=Us<NEyaa8?&A3+O_g!<L*5GYR%_nF+oGPjTfvPai<ZQbH?zaV8uGGsLwWXx?^nbp6j@RDy>Fdteb-%PY5X?JX*=@%s3ThjcGWmquA7V2pl7p<Wjnl9bI+ix&ZWi9YDKI5Hqn<x=40hF8lMu#pMUa{WJ`GBR9E55+bkX#VkV_A>bL>qQB3)!n-+5@kCg8wlqcUG9Jw{7nUOng3{sc!+ac$8f8Fw^U0i(@SgpSlWIOEicIGF_YKGptCYuSI#h}U>q(RNTuJtQ0y7^pQ>TyEtq06y3H}>JIURBsXxsP7TPn_E`<@?lpt!H|X`VNrHSxZ?rUhN9o=X9HoODJcDmo|ejY^vE6z5=OB1_@~Ye4YE=1C0#wv%YEUx(!*$8omb_A)Og#Ih*x-7~$I$wPJZ|d8_F>K%XJ-FU=QEvON1|=&ECByVU)_@25j%x<{8L^b)T-(<9Y|OrZB5<<d!?av-A+x)O5m%7A<{s9hp6riQ3dioJ;U{fO!mnBnR?nCi^r5x@Qf9qv9$hohfEhZTMIE;=;HH(jppn6(k6+zaw$>ST+HSSk6|egI9LaAxnI$-&z+xqB~7&c6#yPOQy|Tc9Op-eM`<#iH5L8x4QAJ;&8On!#+$6E^@}>qk2t4<jJ=wx}@(Mjg)?#$G(tJ#&zHePBMy1^x_8CZDBA_LFEb{ChN+9P@ES8s#fzt&dxt6YZBbKa4J`GlMVE<>+m?Ox`Uk^%`AX>R&+qh=Xfa$KA2!{!GnSCdVU`=R#xJZpNM4n5X`3q~_B3Dt;B1rpT+7JR#>~ZzJfehoZ({r|e53o)qt$*CuDUq?&(R_&c(3Z)Hn<uGj0zD*l5EAFB1SO+F55(CyzPvZjITsmYxfjq;+5;Ci7^3vSEKTFd9Pdrdx$YI|YI;ieH~wVo)o7Oe#~R7NmWa`g|nU$e<?BYLXH9tdYGZnM5{HQ&}d_E*j6i0%E7#-Q!P@4CNb&R2=)m1oI(ukW|FAI8!@WM8Q^kMa{+Bpca}*-t~tbU~+bUw_zMX0gpf`JO*(A7$UDN`7Hf^eL+Nn%zY&%VD5eh<w~`o)_1qQ6x%^qLOQx$7^mb%o>+5ix1AnuJUfZ-n=3If&7`F^g+!!>%5nlLw!kQ?|}85V%D;+S#h6wuE)>jRq0O_{mROIYxDD%u<YR*txVD<-Bv@4DUTgfPVGVTO{0DZ!)~;O{>?DLv^ihqOxKpWKWv}tb2%D_Mp^2apX+$LpqyMgs_5c+d{o{SG&H1sf=S`?h!5ea<x^j($2Ikf4Vvsv8cQZ<tEf@P=ea|lZe<=G;k-`TfMY0Leh~2kiNVBPkZ*-rdjmJ^)b&5qV^ZWRXyvW(X%wRO=sBmn4>RTah&thV-1t=;uf(N`miw({zeAPJ8~gaF>uT;Va`wDThDGf3=9x9pSq1X~1M1Ij+HT6&C)#rn2TiMcUyG?W+ZLb0_gS8n80newgT<6sejPtneC`e7!MHVxxG~(h&iwyp@7<ac$FgnV|FU0C^l2oZc5x#1gE9BAM1zGudb1%72#NGgV*~p2-yCzTC9Ne1Y-hT<I=-mrsHm<?E@EBgb<8nR=F5oIHOCvKp$BdW%o_G~;0r))b=>J~!YF9E^C>3bZOlVcP7?(-W}Ye6_WYe21;?-?QT&TBX%+TF?VIk)qT}Z7zP6rrV{g_ywda0oHkpl_srP-Y+q97F8skt7%z3zNeqZ&i7jU5dYkRRiNzd!QNJ&nKzaDOjJxaNs2Hrxqjbz)!?8dhG_ZW3|t?rm}50>%tUuo|zuFXf|3AqRST{XYEsP*psZrq>D+!=b&AD9(bKi#&uMmn8MpJv_O?7s7T{pG)>yx01ispJ$b#t)F(g5N^Tu2)mI;3c>=A+b8hagz$S#8^)q*Tj<X)9=9oa;g4?_U#Or=3oz>*92a5t>G;2yAKi*gWi0em)|o!lxv5S6H;6Ptiw#h5zk(SpUDe9R^w(FKQY@><Z{X7oOJtV^b2wsCHVgrB{8INp8hGhN0{*fsyU6>pP74Tvon$-_WrNPJu-e;<_k1`pSzK~x`K;UJhwKV(pXOyA!fTE1#5)^$N-|()kN?AS@2HtYhN$fv3Klp|9-aeXS*5Zpu}@>-fev6>$1<1>mRepJGIt@m_d6c1E;*t=g)DT8NYd{H)Y1+=LdWGwqjlt%ap|W+Ot}~D>aXhI=hIO=(T|T`L1G;f8BNuclWs+o%o~K{VZ%xtjYUpJ~-y~+iJJ{?)o=Pg7E!boc-xNy=Z$Cr{}OEW%z8yamu=&IhzJ)N-f`(wl<{w$Lz?diQhoJ7u>6nocn-uH``F@Gj_=Tm^(MAu-$viS7h@T@7vepopmtY51hJ~-!riu`YhpR>pE@R*C)N6rAd%|W$#kSoxUxhJ8^3j>sgGKtg2^SJHzk$FZElP%eZzo*Xo2@OFdH+ZsnRE6Fj_=0;hvHbCltBknbo?>S~VjS)m4i`4CaR0ME7=Pj+92T~oJ5&aOPO-K{H3smM=QIyHghsN}=Vag?&Q$hI0>hGfTn+E!P@(C^G`emais{+V%f&ihtfGy1Z=z1;89-Q3*6syf+E+wMUYvx)EZx`)EKOGWO~{(abmeLnQ2z1C#nPlt52|BT<Yrt|WDE^=L~c~~huEY_cV^g!0tfsr?!f3_AgJ~3)QQ9eThDcUbM_t)d#ch>ahVqyGS$*V(`065CPQhki6(7DmLsEwI#=A9R^!*WK5Id^ht=pt|U$h?!7VW!w~B{?f}sYt1hR0IAUv%i#kOMI-O%V&!knNNE)mwqKyJ&`uqd7h=rYG-0@4VdmJ<`WKhHd#AmsoLf3&F@3TBXrjR&j>7Y`DZ1cjXm$T-j@38%RbW(Q@U}=<|e_y2QPFPYg=D^hwQJ8heIrk`CLPO5^KM}>ouOn9K);e?X&!}{!CenSHQ2z8RGTjUXICEE3mbB-dKg(Hn^k$8?x@*T8Q4W?Z<A%-Hag-=uH|SV<w!Y6FG=28{pRqq5!;&R^auvP6AH2pfT>W!POT7O95WRckyxy-UCQz>KHdQ)9{4&LtvpXlen^&FT^;{0$<Pb-eSfu({_M%h&X#UCWbcGe<<lRRbzy*+TppHo7kzsqF%$qgKOnSn4Hl6{a^5<FsEYvyrs3EGm02fatr%Uv?qoA)MqW*XNp~7lQ(5r)b=uFoFN68-{T@z(oO0{vlpG~%iu5Sbgl8Nsq<CEDdc)<O;)xz>vaRJP91|?;@)wh^|4w5v4HJ2xN_*(J0_=RzD{y|_Wmxk{o1wl`DV&9Hw=EJ^yX;#;cJ{$IX{lhTQ$ykXYzHvHp84)n{Pdx^M|nr29CPGO_Z9PO_k4KyI#d}T;r=MJ;&r+;?{`^&v|R=kw|Q;$?0@c;y?QcS5<j$yxH;k^UOZ*JZr1!c@+Ok#oTe}ImVsY)iVMf-U6S=8D~;|4V~j-X<p~O*}BsH&~LfA9>d1_>p^Q;UXLsee1A{6@9c^5fjwE~&oD7~!L#`#gR`!{;U8coX+U;P@Z5qo?()3@mz$w=SeQNXW(`vYzH;`+((FLR?9s618dB?}*(04>Y-`TG;Qc|FgG1-?($?p%m$IgKJ8mJap_spC73P~R;{OFt%;doD-&)%HOPr~O&qSZmz;l&(V2u71Fz_K_8v3(<*4ItLT^Nx~iiUO=O~7qmbJO-VNY^$vrok`m+RoASW)v%};=rTWA9EIcf9s^-ChSZT=UmMz&1)|8z;vz~%&F7aNb|Xoo2_F{>aMq;&mL{uBxq7h2JUR|d7s98f8(Y%jj;!wPxRb^CUE&7^Ky4Bhi4w9NstC-dY)bA#ap*epQ7t5fk$G#qTEB{{1oTG0(Y{TOle(aHhq3AjCKtt;qyUp;b`kb@iy=_k=qYWV-H;3l(k3B36m!jH`d&_%d;or`4G>09Cvn&YR%kGN|%r5`6l(yYsX=KXuI=aGmK_*&f;AVh4FZf@7&cW9<{>Gn(~QhGKOXVeP`I2Sz*$p2=u0jnFi)EPKI^JpKIR<9`z?RqbJVW<V;UnqxU!I`BHc8@91pP??KOUeRlid#)&317c%PUbVHFay$)&x>t;x{*|EF!cs@D1DY(c3^fIvq`fM2T<0ow<PReQz>mfh;jy^Ar>Fn)7$foz{&pXgTm^7UE#CFnl6n2*M9K&PSCmTxZGVY9a*nhXP+65lgYj%QOg02Nps0$SMX>Yb;vTqJ%h>{7dG4uu|HTqrKaeqR4x1{f&XGm`-FKBOh9eGa1#XQ`J?h36@d*^oWe7hr^e<4Y(&nlsQXK=?d?uP4k60b<>*-ZoJBX~2)DZn)y(D?$#_qsv01bafyv9syV>Fzo7dhA0OlP@9L?e8!TKsKGu`?@}!g9CeaRWDn7FJ@e3m|LOs#9Gr{cfjGlPF;_39}k?m(=BuCCg9f&j`W?7v8OXfd(!Ei=)BX~bsOV8_{HhmCzFDfk;)r|MpA~+U{3HM-Kp8pP3Ue#bg!cw&bj4^^`+kgtqkz%PijumwE{ZRbO*@ZPU*S8Yfm=Ep5gaXo;Ewt-fxZkgK{OuZ>bqesf`fRd8M2V_C56z2UzxbFQ)7SxgR*{$u7|u25&g61)XW!Rh$9a#k>Zcxd0mGSm!=;6X*=;Gjn+j1$=6e#4(+v-cmw#lKckUGH86zng(8Ahu-k$cEYU-+u{Xer@)OrqO%U0(WaY3`x?=Grgd@qU9z#urel*$>ci%4Hl{8}C4c=N6eIkP$>E&;-+w&Duiu`3Z1*LVdW|g?Oi}yCL@7$@O7$)B67de*)dizCtXO4Rb3-k(M-em-U0NnvW~0*?<KU?ef~BW0$+_1~)3!AEye%m(Zdq-VQDB9xU4h}Ik{yw!ub>G0%}^iI)<AgX;xw_I<>sGZc7J(&=>$slhS*R?D`nME&8WDx9Ld?3AQH;YLUkLJ-MCS)#^`!W#uafJ3o68#g=F=^eVG~a-!kP}K(!lQ`MqgYu3RyKQ(7Q%GF35V<9yRP)m6l0R%2-$$^J8&g<_Z4>WrB=lSPv|p@IE!35Bg#MD-4ZiFD|z>Tv}EKVx0EfTSEu-|+qwkPrRd4&5sH9k{C{b}RaRREaWHRg;aO{JXTOfA*{yTX|vnFI?~$r*j~>Vj5#_Nf{L^wGZdwGzuzXtz+o7#8hm)PKuT7d3kPEu%U8RtT9&sIU=gp$RJPw=d*V%s|A{h#sW>Mb?|4*qGMDd8L?u4-ArfPQH&Tl(<+^z0Xmzj?-dMcvXiQ+WR}6AhRi8rPeoVNj=}H*Hnb>MP)2}>**Yw}ILDvZLycL_dScdk@ms%OABWfXacBM}!7QV*gD|rn*bTme!4{olvfJ|ap0IX|;1Lyje|J|sUGW|xY*w+j!gQ;t`Z6ofvt)IDG*QuF9|EvX^_lgz`Hnx6Y_<~NhzbYoH9q4ZX>D<TaW2dbxsTtiu^pnDF4)mN%j5$lJJA&Yg9X^9!S<9f9+jD~45s1}CfG8YQS?6*EQ*ThEAwFn<Eg1an|A~D=xD}DaaHeHvJEHS7K`cUSwWHT%apJU1gT<+g`fDQIyF#5n2!X?C0Bxmdi+z4G|@h9K7CftW2iJQD(=(QD`0Okrrt}6$A!<+5l;H&2xN}0DSyA?>p!J@ZK^Hg?82^4kLyE;;#mFJ8H%&|wVzVFE~wdN?-?M2iiIlEPK&K{)_1`$%=V7XgP~F_x^k;0QxUs@E%?inuCwQXjX@_#C|TyQRZP#HsaK0V@}cC834t1HRQcI(j`<nimheXz+Ma$B`69IsW}Ky+5!`e5EF+d5bsx`QzyRZ6?+5&RZdV0Ug67+{)Bf*ktlf~=pfT<BqL@H4H57C`HH2!0a#eN{tWKz+f)Q&)zFo5Urox|Oe&qYNMf(k(Evisbl{fDsR>gQZ8<j6uLP~kdEs*Wq9NFG8m^{tz%or}#r)x;c2kyx0T~7KAw)?Y^y}!l=Nax|q2z+LVL-kgmvWBq7h%ZHaqtJHiD>nbNgj~qhu310~@_j?cJ{HPzC4Zh*#xyl#>?zRw<%++KiUC9E28>B!x~If)T!{7SxiY-;dm<LQsAPS-gs}Mvzp<{oqq%*rU^~-Lzw{hr5BT|us_qoqkuT*bWMSj2%$8(+$@pDg<3B`If8N{Uw}|g?pY+;6CG(q{Qj>mDpKPhJ^`G@4WtAUkpR0Y8Kqr97S|P5C{oVDRCUL7%K*s!}KhYWFn^1^K3;T%AL0!T0J5?$I*J6o8xA~(durA@>h3-n#Xa2fh$yEzz-QybH>wYVJ(Cip}&YO<<D|i1wpis9;X)9o6SgzP_t6!6;aug9hnw`-m0?Rf->)JP;jLvXu`fJ2HsIccTXkofqvG!W6yd!U*ueDBEH}9kwxfeR0NsP5N5Ij|i_2cCE5MD$G<2<&`thB6kmL*c&$m=vlYuL$*jdpHMU23fGg~_E|sbgFCdlP+8n6&C@U2r#h*23gu&Z1fTY!h`+_-vCIyZo6K?nJI0QU1ORt$fMnrz=)OsI=8uSEzMVwGN}UXW9#;0&o-z-OZXF6Bu3HUVi2(l-B6|!hX~Do`G~z>b`W2feL#znAl2Z&^Ky^f?=UWvH$R(DIyhAMKGy@JTqqxV;0=(_3gKC+jfJ+2-Wp{C|R<nih0~n%*|AQwBG?X?AgzLW<HUUvs#Na-TTjv1A#C{jg4%|o2KNlUD^H?EL@NF!CC@MN3r`O#T$kVGT1NkI0N4W^baHTO?A+(u|bKlDejZTt}4{&MeXaIyQZBJUDdss4eqyx#7YYL^cmY@Fu<awlCi$(@%2taEg49)Yc^+e3*QjdWxQ*=?|mCwZEHqd107?0CKM4|iib-!=!%VzDBnVCHqGP43UwNv?8K=um#nOT^eTH48jEYjLcGc1Zn6pb+QBC%#D-q)k#&E?;&K5UZLpkZU1Ch-Yiy4cgN~t~9Zl#?c2n+LM(FS}!{KJ!cPy7qpqsdn6Sd<oink7s0P`V~siB<K45OeCLgn3a&SNN{XR63%eN<Dz5xEO`S6l7O8L>gm&aO`|=rv;GO|TIZGo^TKF{jcP%XG!AA}g;{<`8#5NAnlzYV<w29V@GH$^CE(Xiq3=yg{8!pD6qsLwsc}_e%HVC95a*TFH`aZF66R(8lyYQB_s!f3Ds_G41gI$Zzf|mU?+Fl|9P3yCMI;wJeHTZKc$;F#KPk&jA!wzn4lh>kjo?iL%1Ixz-oCsN|6&r3E{vsCU%lbS!EbSwF~}U>sno!GEDY=k=>l(NStA8~P_#&0&R(yr0F0f7Ee4&A`#FKlGW+ozAR(<oz4S9*xQFUR5IyN*^5CA?H{2ZzNc1V~zDvLl02i_O{BVen!XD9BOp#CSxy}_fXG4U*$bj-b|@V@4*R%T;utHy5HzZK}zN1Zo##9y5FrmYV(0&i-f8p`G?hI^_gehlP{{}i@N4<EmT7^Kcd?qr3`FaBLCHVWq~C{pLY9&Y397QD$n}`=9ifMX~wJ!j43|Uobq}U&OECx{aP>6?DJ}9^jrz~{_^Xu^@a6&RFx~}YHC{VEuwo&cPfrpWyoaBQBzcv><k~;tIteEX1z{jZ{mYgVagRoc#o#2gDDit3)_DiuSIUzrh773<J{7@hJTAF=7~SJ2Rp>vk4cLslB%E0;usjYL^k!yF-<nna`iJV?1A|nHMRS(b(cNpyf3W#c2!5!*aggfbcIrlLL72`e~#&gQckLH1Lo8o*_@?01!=x^fEaS6ChtTqR@mpAs;?B@tJkhI=3%8W+BVcb%j`(3xTD8~WZ%{Ag`GnzGdlns^^KV@+d|a^eQ>+?Dr)*8)b1^w7#7oQ`JPNleN`h)Bb#k=ZI<riQr6Y-dPGr0Cu5*Al%+(?Me9f38j5oUt5vWt86|`|3a0DWeoNb>DZ*k6ihh-qS(>lRa$dSKx(x^R<3-f<^Z4+Bk_X3RnKDcks|{prpk(j#$<a3O1TpMeSoT2)lzJ$(dX|cT1vZ*I-lh1D@_mZk7w(~25#=-c!HV-LPL?_2gx5chAxfA5s0TBfqr?sDLilr_>=Q8o`O)?E6*_j1<uwwwv5JHF0WkxZL0BoSsJN>slU!bN<buFj>~Sty9QPO2{qV^6mFjz^#pmRkLey10ZpWa?%c{q&es9~W1bKmmGr^gv`#CGSz^uf|W@VTFOpNw2tcc8+je6TvKgsHS!Z&o4N|>&=A<uR`WueY|$rho;F6u{KIsQD-bHzG7p<oBKNq;wbthZUw6gjbh53IIH2I^j_y5ek9Dt_{my^Wqd6haRfQ;WcdXjqeiVi3jD{~KykVKRojq7Y5_!(u1;rkYZh8IK8-F0Lij!KBJ|%usTq9Q;l8NsD(s$BA(M(}vxX@wGfF5{qT1cJeby{1WdgGmt|4E22H)TyizoDQuUTz}<!dLxmg~_b;LS!o=%gwYbUrX@wt!YTOT<bp*DN&cq%#QatxVlGT^6kLhF8*{J*Io5@~+P{5FA<`T<W_KeKT<Nt47H`n?UIt#`1JNp(S&xX2(Z!k+2RkMUz5yx=4t%7p9*b6NN)@u#r->l)6aQBY5>(b`jA^+1<sLH){?jOt8c@F<h@epFuZSi?~0^7Ksuo8sm=>zM^_ou?{#ZV^Eb48u)=@a|5t5(%~@6PSs&5<`?{ZVV7@?KiwCg-xZZL(3Djld<wz&&ha{o?s?@4um*lB+U)YEQWCh<uarhrljopJQb;oUqTadhXBqM%+`1b?`fc3cHn})>695d*}T<LhWh6O826#UiM|y3cXkKDXi8JlR@G)4Xp~rE^X3y1SLAM)7&?DdYFe#LYY-egICs)-%;)^s+DL{IUM(kn$3_tH_nt6nOSH)!vsG2PN<;LTCyTD7#Fg&FDT;b%6(8xd#4tFUM|JUeCJi1`2sc8f-0U;OMEpjL2}|%tN*?NlSBTrscHo>?s{8pGZr77#Du?)wfszxS-n@-8U8b~KDp%{OR08vm)8vs1!YM+uFqAQg|fG-t4xZqR;CO|e=jjB@3Y7nHMoT0n?cNY1Z5vsJ<P-;Z1X<K^oeV&P^^{xJ<Vrd#Y5)jEVIi6TbMJoYJ1my>>t+|(}kV;PN-;NEks-f?9Pe4r<vDK23f4J)ARcR-YH`gf9S^)D>HVcc~PZCXPx^6hUg3Ib(*qy&R%KOv2(oFhwBP--k1B)MlyI9Ox@Xc48R;fXBrcT6z>Z5;sWl;#Da@hI_vL#fTgc`y)H2~eq_BQhDFD{H7l8ta#lm%#9?Xc`JpvSF5~U0zPCd0<fF`6KUd$n#3q&Dfq)~MRpXp8++A?`;F-HnPb6Ep7@Z}KTi-7u_PU^;xvgTlx#%NxT$45dPId(tcjcq6On@8fZ{Xkc9!Vi@S8CqC=$utO@dD1lz`++47)?b69e2+8BXSgGf2_cnT*-Te7Ze}#&$saGRiDfLNySjWxh(6Ib+cEkJ|P$y$}HZ@RwG}-cU6mRw^gdb>U&H5uRIP~m9bD}U-=jJRL{Zw-FvFlP0KaYPn@#~ym8hWXQuIo#dCb2cXfSV^4gQhhH!O%P#^7q84l-8V@CLyebRF(arUyB$%1RDV%Ac7o`O<o7RP8lC6%*)m)3Kqatnz$D6MNny+!%Q^&`c^D^?)p-jUG*{FS{_vmZgC@Xkuvepsah92e)bzz}y~uPbbes?%$>W%4;@6mwqoqW!r#U-YT{G(Y#VF~{0u-!<7m@AhrVLq1|>f60y)_VEL8^9R=H^4;paF6*mU<v#*Thj@5>%@3$EWAsT%ctD9=xMXv*dr)E_s$zutiE{<a7G{5A${&QS7xnxP>|s$^_i%A-t8$~C@WEgpRrmF{T0H;uSnhclb~yxYyXb#a{v-4B06912WUtz4U1{0R*cza$MYc%dV|G7hyZ7j6N~Uw}$uLd>`$D<$f8;(;E@uJX^85|;Dy_d$I^T4MS70S9V-~KSZG*ALz*N0AKcr^tPVq`GxC8gf7;@TkI@fKXHePqcyzI8j?w-vD{r}gtPVyP^uc#UPbWEM$l1nWAy6vXec)54W^+B7lH5Owd_dF|I?n5SrI9%Km>q7;W{|eu2GH59_Q`CXJ%X_2cO-j|w&GCS@!!+zHt#Q8>Im}WLgE8sorpu<=={CZ7x9)V-O(z;{9eN@++S%j&bm#PYaR9a9bkcPDVdO@mo!bY#aaarNP-l;n@m=%D=!tO+d)5R?P1uK8NJyVQO~BR@*zP9q+RQRCo{xZwtc6jxNv}!VXlaAB3ExQHZBdL7xgLE^gy#i|(t2Alld9En_&0+U1{lsp*zYzSdzu8EV+YZ$LC@cG@cX>>)=f7Xr$0Le=?qMSRycPPHwAlU9Mdz@+;nz?LigBnH(@lZYrk2W_jYr<;{f#tf3Kdw>GbG(W3cWVY0c{{lq5S)G>xHRP5S}`>*dkK@9(Tr%AGfE-`@rv{uwr$e)q_XP07rLBCpe#*ncxK{d<_1{u7vy{yK)DYK6dmgMtwEKSFx01#?KmiM&h4@tkY}*{5-T6uDq~vVDrR>Gwp#8t~Pw2UenCZ9I3NUY!OWYz6Iy7tp;AasIbX2aHL}1{m?ckZZCNshPISrWiFcsIvV+&G}<BRD~_OP>;KSyVhn8RWHHcRn9E#dA<^AX2*w;;$8ziBcbpvaH1RZN|yb#SueFUHcOpZa{W;T{hUSlGwK%=Ya@O~Ut$&&{_ggR*JdvjC2n=x%rC4D{CO`wbH#q1sPAU|Ebcjbl;hD|$Z;-R#o03ad1kHEkB6tj|4ml^_5c2Bcy8+|dw&2I>`9z9dR!B;@7F8z{d$FX`j6Y)A^x@ytfCa3RAY|Qmv=F<W34yI80v*DazgLL#28P$|3TiCo-?Z(|KayH0@J*wb-`Zt{RV#);=jS_dnj>P%PU+bUxE8&>=Cfnl-FX`EYxs5sL9@K+p|I)7k!)>_q-(=zQT9ovru;mWKUMl|Fzz(fteSdF*;np`0-k>VvzofjFG}@*$C@FcCmE^u6ju^Eb3&yt8kxG@CChS_$N7Q#q|T;3$6{E8*3l6-(*RjTZz3dVxJWL-@y4`E?LZ0gh|Lb=8<040|qjASZo9~ko*dAAl08O#M@cUCHrRzqav{Xi)oFSOMxT5&2n<36s)OjL4_d4-<x~|SX0D-n;h5D&uZ8C^T~bBY%V>M%p;`Q*fo4Qb8g}HLKO`B9r&*Iu=y|fUbkMkE+O!Nl)F+q%kxAN$vN@D=U?$Ih_lUj#gyOEM^AqQ&ZifF;Y97!rCe|JI_yb2Rd(<6*%x2(f#sZ2SU0*)Z(*HsJ@Ecu4Q$?%?@$Z4hDiWEcgS%#xW&vqI(-M(A4~Q6)m#Yq-UFY*0+vg|18JCIx(BciD>08LYHoF(V-(<Fn5#n6{ONZeZoq2%klvgY_wC2Y0QT?Y=)|@4yw+yEJ&Ma#+Usii>s()dU8ujVuD@>F(_a^Buj?MQ*PR^w^SsgOcKtmfJ3lJ07ymJR*M5<G6c`}b@H5wa_sD-%F>ukV0az*<nvK#hiF=8)BpV|32zCvaW9B@1!TUu&K-9<SJkYbRFa!1*+YsRW`0si@7>j%h3<sUZ#nj4cvCR$n<-NqXD_bP?s?W2r&jRNy)n0iPCc`r^ryb9PGPZU}`*`WzxxnwzXH3<-1}>b=^%V2DTT#!U?-pm5>jm)HkGfr4;12Tq2IFwQfnS6%{zt`Y5|e+6LtZyvhcE}ls#V3iP0!BrhmwOb?_Gom<qUSbWhIoJQJ>^H&2}mA;S*ws_Y$*snoqoT=W^e4lnPmFvo-}ECouG9V9DsS=CGH%_prY^VFPqOI!#CCHr;!Ae)>$rgm-hLo{Kuqvqk4k{?>+e{(Jg8IUD!Rs{L^rqZR=LCB0^f8e31+<bel>Q}ImLmlpO;;i9&*9+YGHubRCo?4^EIfN?s#eVePZ&F8SVZw8kho#$ql&#53@`9bSm$2mg}O5j|VChiJ033({j$xGP2-HLfH=snr&-DHomhQ8BdJ(e7P;Jg}HV!pQVI_&z52lj24m(yq4fKB@y&$r>a*}#95{5H0j(c8q*&sE}ahkfQqkvR9ZoXspfbIwJW-wol9F}uJs)8N%?1NTLC9NZL8(Zso$DZBFwJRrXpzU`LpBYrdLWY6COCQZNR+=~Q10CVsNA3^bTkL?TXw<S0>*xo=*?F{Zx;j`g?SDU4Ve`hS>J@CFRs{|GBZZ*UW!tPx4QN>vS%=nS5?(I}<bcpj>$DQ*rL(pXPy8fn)I%$YGhkIkD53zxH-nN>*G5m<H-y?fL@wAxp<h(6<<Tz+*2SU*Uzg6pl7iU`wG3!8|No=g|7m}M&%r3_|{_tb-yKT&*reYmgh3rMI(JIVikwdCHm#A#6&x%L#z1sP@92+VOGuLmyk&$C4QpQ{u+>v6h^RrW0FWh@5-#iBi+o)LJV9_6mkDU9@SqV&2ymCcugFB|#ZON%+C>mDJ|8z4yk=u1`Hb%vX1Ni6G9{yO((z256ys3Jk9D`D<6hjeexsS!XiFW^)SF{gxA^3zIX1(a_ppJjhcFKJ*^DM4sCr$Rzx9jJb?0<4CCFIzG?$@9Yd*Z(rlEdL%;qg}r4~qQ6lAMj4XVbYpt$?BHi`fyxcX?cs-38@WUzsmgo4*NJp_1}PrC6!;(Kr|3Sln0NZ*Z!qd}GRIQ@q|&JUr)i&WXY{1Tkkb)y^E0&t90DRp6Mj{72?5tdOa3geaWseLl02{|;Swv#8c4=4?z{oi=Y~#9vcGNki5W48<Dw1gw99@x}U@g-~^?oSm0=burhMYWserPv7|CcI!mLuEF2)2kS;;wUoAJ@ZWZQ<gnyp;%L|dXOa8kR?M@M?G@!&%RMVx$r;>f%z53yxmaHagdNrW=HZdg&ynx`a_=AI@0GEp5r6XB0M|q)4x`xbO`ltliqL8=$anXUv$3i*`)|P+gB-N?-aNP9+ZvYf-veh~8LtYQ3wU+j9z`t?_OvPU2zs^y+c*9^yM=on^Rtql(69&OXWBK9>vrFb3CsC5{?TSU&AdaOUs(GT!_c}G;-mPLIkP2axymt@nF4nUejYqlySv*`y@h9*(8s0cp);@)Sh)nbOg@7l<GW4BedPSR=<_n$YS_quoY&lfUwNqIHoT{(?Zjd>4s-w9UxxqB{nLf|kE%l$_Fv4vzcHUQY>TMB(Y{!*Jiq_V+>1H39?wR8=A>im;X7XGJy2&X^hOzr|EA&?^2bdx#?RKLE@~mhd6Kyfa?=p@?iqD^Bet>h*k+^0HccZ()?*+~&n3F&g{Udw?n^vvyKVAd^W7@mpT04RI(hak#4yZPL-Bd^aErC0_!_phoO`D-eiDkteX@%-_UIXV4Q#=4I1ke-F2tTLfcL|^emhwSj7Yg21>Vg?$a7GF?=MqplN>PQ<GN;kM*EKEeMM}57=X@y{K)pLmCAfm#h|L*%d-?R=Enc0-zM|M9A~8GQ>d++g>9aS8V&l4bVny<E~Ce|5$cI-<M~XB_(acNxgJkB5n>#!Y3)Z8=W{Jc%x?%)XvRCy-dfCc!yI+sA_VUM$1oY*4|8$g@P4$zq{<$!olf}f@YxicrJ|NfXS5HD6Q1*d*N%Q~o$W2|@x@s!<Z_QT=Rg~ACt{o%Eq=jo$E@ZH*MV_Q@of2>^yM7Y?`BP;-x56&%Ijo)liv;f4tZ1kZdm#qa`pO_x6)tN$nVeydD08=%;N9E9?S%10LKR4Xym^;KDXKTFWRx>RM7ZLgxwM65O!SpWXy-0+iLDi))_QE4!f?M2h<yxrw2+;i)TJ_dOcsx{++>Jna^0S*!Ivq$on;0ufWBL*gcy;C%+>55A3g#rkd5qpJBEcys{gPb<LS9;81L71Lcg9?6s>oSc*4Ra;}@s1@7v>tkWK|JXqAuen-9I91g%yev{W{^%*%ihYQX(@)@?kz3^-~YHO%XzhpL8-W9~YcenYBc{Uq45V2Aoe->hffvU-r=AN)-F{{SP^APCgL983%G#L+daqnM4(c8%}Iync?R?U1Z_Z(-!W^Q;-wup(aUn?VD3g+%v)cR1@@M*nQG3_hQJQ{a=kk1mso(YbK9>*$lKA)wpf6?kjz|ciJU#8u$v0kH%+S=V2>NVuEQA3XO8uGA~-?3@DR6N&(dv=@YdH4}H-$ngnv|lMb9IoGU{}5-2>lK3YrI4d++oN!MkwfS#?v5|w;ScjQRMmfuTAVsF>p+97-&BYxj-@&o{3&pnvQMHvYo?Qt%|K)tCGXD9s-6yP6MDv5SsyXJTlKgyE-RstA<u4At+cVe?{u>oE!F~9J9=%C?lNL%^q_vb-WRIm&{F-OPjYFA`}n~+2+lX|n_fTpE_!BqOe1O%$Ss+tofYq894N4N#&_v!NcV|z1-b4S&-*ybFYr0+cVV9pSJvLo3soH2&F2!tI)IlP@rKsd8R~xTZ1}xM_j|*J{yO81r)|}TspPNZ9M$|gPv-Wj9+#;P4hQ5jN_I(bK-2GIZb-TR;4g?}58GUey(8)#g|jQ-vy1f^<wLUj$sDV&wR|oF7n9I$K|R%3JKLk>bZ*M`ljFsk(_Lq2J4UaU^Ljmhi|BlD&jeauGQP#E2krAt^ne!*#jK(y&T~n1nTx8mDCe(geJDq1O3f+enR@459L;m7<@X`)RjVmu{O_o#b8nSvl*XN>wc`3U@^#eO@EiA89|*mwehe-bp2KI1E6*@de6!E&--s~{_KET)&H*E#z}m*lxz6FpxDmvHp|GX4n3v}ox$J53tfG!V5POUs1N%DEU)(%q>+{_axOU2ok>dfsio8^=X<@$qsBAIfCH4HWXK!Uaajjmno-p6{a1G6|$3dLs1N56QH~5_8=7N_=)r=AQg0r|5-dj<io?qk4SC|T^HjZ^byz?xvTB<IV<lG3Tw@#76syds<g$Mo)_s`qjw4f8^L^sFcOju?^`%)WC-d~>o&1Qi(CS;pQx!fD~r<gB7XbEY0QLo`#_0E*<nHgtM@Mo@Kj+M6MT8{8T1w0DhgUz$74RMaD@h0kPv(~tJ1%9I6+lgn@>b3)e?;_W*SgSZC+@LQixcjm?=SI!}h}Vz}lsZrRxqhZxsO%t}6Xu!bdzL?=Sj$iQIrJnR^Jh@H9nT>>`?AjcIj+mWRvNjXx?kq^iO=U6aIwbaOB>VWT$gMcFg@g}YuWu3coIk8WHN4x!d`CM8P|p6AW-&wBe)?=z7CG3*^Wq^B{64>`V?y=Jc5g%D}V2{&HWJeEv!rEa-HCD&NXz3XGh%IUunKwJhNWk$nqc9B3U<bH_L&lM|>teRPi;R`4<_-8$EmBQ&G$1UI1$p@?L0XO~$~_tP^qh>|BU#W#3BlQ}R8!Z)5g}^-J=#;@k#(gcrW6oi6uDxu2(es@zX{Hp!>VIf+?=<T^uBX%2ADtPsO${b`-gZY6rPY!BHcv2CHdpN99!9;rTozyt(IFBQ5eT93^1Ws(DFs_d-DV=Hp2f}hiCfC>{JV_>eUNX*2nDo@Nf=(zrx#Nb2{eN1Ib&h3tvQ)|5#cI7DgLvltLIjdpEGW*TnALBXUBa!1;sJqg0)dM=4Du*@eJMpWk9Z%S9!tSjkCuP=u;nxiZF=}RN&B#tXV<s@=zV8-2@sQ$~){)nk<1F}iO*4sYb=h9cl<mmkgZ%7q?R1a(E^5T|p55JodlQHsqRQ`3{V*9%(Hh$i3vfi~{kWnXWgA21cmmr|7262CIAvGmouOwGy^zW^&1we!3(Q{Tt2G~I)b_MqhN=e%9wWRa)aMzC^$zXs=s8p+W~1mwmA#=DCGV}x^4^;8QM$Gf#~Md**X}DZjfWi5$oLaFH^U+iE3h=c5$c?Ss)j6e3ix%he=-t$$dp@<-9Hp+l;E-1i@VVHG{<koWpg1HMV-K`$;f)A`Fmt9T0c7$&#SNc;=C}<E&)cG)@cE*tWl1e%&?f8FETb*>!+J_`C{GCYCW%RDQ*M4rN7xM?A`j0GwhAE4g0+(`nw;DZ6iN@PkAk4p~ZWC0Q>Ps-#hHGUXc7V_)yB(y7C-nf9@aYx4vL@<Y6&+5xsiguJZ5Y_?h)_-ov`8zGv?c(3&hLF45l0_6l+4H?H;iNtkd9qH;Al6Zo?@dJy&;=YNyOk+1_F;MNvrDW7GZ7i-@_>+iA_tl*Tc#z+@qXYqXk@1mV8aGx#&7h9m&-@5`<SoNzio+g14)_7*Q_l5op#R8PWfm@97(dAz0e==W1O~zlF)ooR+AG4kQi^Q`<wD%Tc!WmmULYyIM@72EzYpH*p%olKebq)ZDMdum|<`Ov`)A)ZBc3Q_XyhwcRbIxnfOe;An^7?ZL$FbsGSC2UrvN{#!RbgWXxPK@116XU3Z;JiZ`rPCjF7aeo@Rt_iYlY*`Fx45xL&smMTAiwmhpd66&1w#EKbLbJ_p*8v_lgv@LG~2zoQzq)J)-9q^=H<7VV<QtW)}ELp-D?V*u<3!d`Di_lK5ni`-r+6zs{(SRrsZ6f%Q;x!lHgJIfd4%j0;=fqf|aBa*Rx$iq^cFzqVpc$lmV+53IrO!@Mu(eZbC&GmSntY(MKi(Af~R{k&%0Obxs(<)5hA%bF7Va2Y>tB<7-UHn>+`L%l})ev5o^ynh&o7{4$ttz(}OiciuKA0TsKtz;jib(HVNxrhYbmE$gTANY*t`+GG<x0V9eyG2bw&SU8qD8#X>?E(%oJX64P5%H_2&tx-IRdsU{2W;B355=J(-dM#C^VN5Ct{?lTKO*0+t>IrqydDCl!m-ICI0>^Fit*ke4)GN;Ch)g+WM}ZYfOCKNUevA_mo0n~&+MImjeHj8tM{@pYtgXD2fmltyjG5l625-={Eg#hGfpL2-DWL7iW}q^!Tzawjh1Ih&QF}zc^MaIuA%Uk^g87)t8|CamsC0Yf$m4joHldrDZbKY=RSjNJ~-g<{5enI#affXIjXoj<6NKO8B)Cm%z0A(B=B}wzeL1=2G@w%OU4PCw$I?->GLdGP1kaldDS}84LW}ReRy9x47;a)O=^eUwAX6S;^}C*>vjCj_qEd7y)*dT8VA<E-8ShwS+ozwwbyNR?rVN`VYS<Scm12FDKZ!Hf%SK6+JhRt<K^H)H)l7x!Cddb>D-*|>L1a0xH;T;jX(Z%+dbUfw^_qyI-5RC{L$=w7PcqW<hP7Z{}M;ruRf>!&gb9O4*#O{z50xU?6->ko7X)Q^rO?e#7$S*_V3!BOeX$xINs*`(|2>F&(gY}XO!t_zDZ8J)7{+EkyxIY6LEcaU;96|(Q!lnUQfHRH|w6-bH6p4%tp@C)6al-cIVzwe8@+M&wUN*t}TB5v(Sn{&3}s;pZ2<Yf%g?SbXVobqCV9Z^BY>-@LAQL4Sb{Q5#by^-L~giZHLy&eUo+=pR4L;ze76<cjNBNxMESm!&#s;zTF@3`w#eU{oiA(KmDFN`u$Hg&%c{knGeha;`7V3y<%Mpb-NAx`_t`B?JgP~@jeH8c`Kgnl1@AQ_S>qu)ZOjPY1pY1UVC%Ai@J^CXB)MR!I7~U@DHnb3s|Tod;<OZ_hF}N(fiBKR;W?XGj%vWX5Bu<#mk(9=iee_N1t$)@A-4j=oyLit*$TNGZk(JvHyi03qI3ww#Sq|kJf-|^@HOdp3u7fjdCQ>H}7=y7?U~E$qydD9Vg<hg4T-Qn^*o`*2EPyKR>VBtD8^sSdx8|$Z-q)M${Li-JOnRR@<5Q@sr=}-Fn@bZX@2chrYyoI$Ol6M(%CIO(K`L)K^xut54O`|KKw)V9nKtYoa*wvJT>idzW!@(>}U<&u?#VH~tW3peD~k?YE2f?$WFlUhmz!;yey-*L1$gPT%hM^PJnpaZKmnj}HBPXLkJKo<9?>X*#zz-|_cuXZ9?fqkTj^#B*af-}HA*C%ZEzob@4p&cv3lAM5uZJHy(UtFWd0``OB$?Pl-$C}BhUl82Mlv9X?-uLE{?6WYx;K9lE+vlC}(Gp{L48MeQ@Li}H?KjYWFzcZ)*e5={@EC#B;jtl&|(78~xy?}Gb{64I*UXM|mtm?xR<LghJ(c>j-cBv=3G;NuR+p6mgT%Yn&$$O~#!L`EGkdOPGVfWb&9l5Wd$I`{VYM^HJRP9gKSSe{E>GLNPv#h^swt(~adL9oOd{gh(h$1(VnEN*4&tksGb(Rr*p1R{FHS3^h3i3RU5sTh_UaO3?`Oq`|Ts`w8*E(xxbw!cKDm#LGVS7*hl%5MUHegl7+=;LO@-;UHk@txAOPit2%q#q_v=8~LqF>`W9cmmI{zr1B^X!<4LvQoAM{&_`jZmMz$Z_-qZ9c*6hV@&CUX9F6de5@=^t_b%UzqcHV4GdU4ZBC?BiCxK@Z%yMn`rns<pWE#2g>=GmtNB;6nqD$m1K3DYqLq@gHdyX{z<5<$EvJ{qiSHa59nc4=zo~A$r@$|T4}G3sEO?T7m<5TgdHnuNforFME!*QW2|D1p~79Nds%<r`3O;SdfY1;I$`WG&(aop?55sR&l3Gv_XRlADb8r_YgN8nIs0GEeK9}Db(Lzpse9o3GoSh*`r5^s{V=-+t|wn}Yl$ASc)#?eY96n#{@1<qm&R;w@wa4H4b-B}vi5aY**^N%zy5o?5B#3a?85K4skz&$zb9SX>v&hn#qX`{w|h(Cc5<yEy-uR*66&~BSzDpA2Ao2p$a%ptt%zmCtdtKPEwVd8Qzt}Ub*|4S(s{T2%>%HIrE`|sMz&KW+<~ay3g6Ir&E|Pno31?HD&CXvO>?btX<KhRAJ_*@X^46JtdCZz8`Iu!T@ZMrB=-XsY$NK8s29Hi_nO(dU;NBlBOYsKJc5}myB?p3-UPJ2ByKL-?`(!p^jUOGF{vrK*EmEtKGWuQ#7qg-p?HQw_$@Kp!E?`ahW}g6IZ^(Ld3DV5kPRKQQ=a=oJzy{9|2b~bu-+1*rg)K<>xK29$ZveR&$u>}M#om@<{7oP2;5o<e@5RSw52h(sqG2<zI#5mgXtS|K2Xb2vBUM)@{)$7x|8^x71?l?>jv8Tsa!P9W?d_0YUy0;)qH5)56jPK+3p<kJ0*Huucf-3#L{N{DubtC#5kmqUUNa~PvoCn%?CJDTss%<V^(+MygcKqNrnEKnxQmw)Bf-cJtWN5x>jhf_<7}QjoH_{&Mg7|{T-UOAHrd0bx;FORK%C7`m)e>nP=QNWsV{dcU8@21ABwlzoL$#;rh$?mU@OOEn>Eqhe^dA8Rky(qt2^D%}UOA{u8y9Z03aadxd!`#t`ZJrv<H75o1D&VIyXuvpv+YI$2%YuQ=N#zm1RIh#ny0aL{kl<D&3m+%bsbYucPH>t?L%9^)F(7Ygk)uLpRnG#(j>M_ucYb0#^P#(Y0KlYS7hq)pa6f!}xp*D~Wpi#W6_@8NTxbm>v+5q;k5JS#t@^Sp76x)MEEjq{*9-(N9<DrSdl@IEl-4DUtOQ^;p!*}lUz!ahliYayRwn-1+r#pOk|%illT7H2#WudL#5(H3@Ea1%-1C-8Z&=Gu47?v`U>_&;82%7x|pP+^uGvz_|gskn0--(s)HU-o`5&)P)|$~N;XYIFI@K1p4&R!z(*q8^a(axk7g^UaxF-cZL%M>!|ZsY;VC<1NG5;JrEq6fs@_GxN6Oyr(!9VHy2e-5#^AC}<F?UQE$vXt9;HUvl<v9=@>M8L-Y&s%f)u&z}7j+5X4O4hYU0p$CxXNIDiva5TJ7Oq8vu;_+pUiq%~FX5c*^dG3FTe)6;A5D>rhGTyyv_Mm7FGi-shuld|_0aq-srz&UUyk=JSfqPQtKt3<xmz&IfhIOCr_L_g|l43BP>Eh3E&nwh$1qTby)jh%|lO4We-lkd!OMO}EEIaFFzAd?P1lLeOUoO{;WUf0yqZoR1-FJN-=Dc|(zUceZ%rC_eTQ!f5+8(X1$XPi@;Lj8}I{Q2B3um#4K6`~bPUrb8OoA72u6*Xbk?Wvo{BfS~9QIYdtk>d|Z@s27jXq2>)i_2fu_uhN=`%MF>igpR#96ykFDlO=n){dKVTFCr{lkl#BQr60qGy{3tts7haU8@Nt!2M}+=KlpV}vOeYl_|i;%|kYQalr`!n&Hg8H|nLd9R$G2Qle9%LO;G$NvIs`GdjFc9BE!w<0H(;3uk;{5*59?DM$+or8&EfCbkSVB4$WqZi;}Rb2-Df?mIoHi+|cX)|>n!MQuQu=L(lDEwFY4zJQy%~cd;@EM<;V>mLqUf>_07^bf7?em-RcfZJ4By(NnPUCt{!IpB)p3f7D`CP^G@Hzavx_bsEmA<xF{GjLXVxB}hbJ6#!T&b*)Y^(VcHB0#uT&cwxb2ihK&%WJdS^%QISLSk*b;wJzC^By@X;|g4)<%n+ci>l%dg*HB@L8T8W4*5AS_Yq+8CMkM(+%E{i!+^S_S~r771tM9-Vbv>L2fgZ94aQi8*|E#Uq-AsQE_fj`-SJ^SCYT=6S0=SCFb+GpNz9)&ecahC=~pJMXd65F1(Gz3u*eM#vN1kD675GIcu!=4*N&OHw{D$M8im4&FT0v>}D+S)jUT*YkHQky5eo9@pFJX8vS|Ww;Q~C63d?DJ6Zmzavr+(XNhkp^Ft<L28DSYa$Jw7vtZ`r_}pGGzIOOB>;|vH+x6M$43B@nUL=?spg5LoK%C_Uz$6Ph-T1@gm45ynZ(lb5`0?%e`;Wu_jb6U*|Lgz#m!L==f#TZYCGWK~h^qgjLM)bEL`pqyr40Ef%G_|=dRxY=tYo*aGw3>`FA|i_l>{n<Z?7ytYPDcGe!%2HdXifl?CNz1m(h2?q(Har+~)EIbUi_#eahtrEVQt#M^KJ;ZvM!nct%KLYYeluT7p*C7S!UIv`E7A0XX(gpqON8Pz&wV9*&(ZV*z(%!Bo(*OWKaODATlMcwO9zrPQiCg8AQTzrTI&11j7~LqA^&rXbI#$J=jAec7YWOI8T+O(~IuUwgD#`G`TUCCx%Fl2Q{w;?e*8<Y>=G?(s;+>Y5zQ)|4r28DaC?9Ai&m?Jlu)iZWf3vF9=d!c0j2f$E&0b-Wgud;#tCDrx-?vN+QxKm&zr0>hvVPG@p(()P^pZhmu8`lr)=&?GJxawKIvAzi6`E}8H_+gepf3Tl+|=I^nM7S16=IK7`xSTHeY;|ptY1O$jumxF?%+$GOxF2kiuOuIiAhRsy<OwsWYEQWvsi#D?%vF!d>*t|B%R6IS*1!X+O5tfjHI9u6w1J-6rB*-(<XDJ=+cR`w$LXKM@)!;-M$eBmMyi1{Fx8WxAKW`Mf_KZ@G+1X8IwIJH1PBO8aPLM*5A%wiie3;UIC1G@9g?)Dy*g?aM==GiUPX3O99I}vz$jhvmY<*EK$JmnvV9K_TARv?1fMhAT&5dJ23L}g{`p(c>#ctxqP87y&f7o<VNKD+=4*dqFA8y^Kw{_^hC@ng=^JzrSn~Xbw<wTQXc>5t*{{MY_h_{Ec&dD$TsAxdLfymF8PndPp$u=)mPjZ$Uvugz%pwkNspXejN`1GKW%X2|oJN8@93>LGBB`t&zxTc;m9FzsEp)g)xqoKo6A3Yhh9IHh>%e7dOL0|k_XPsg|F@LZCe-Cp_O-h$WaUdAlN_$mvGBh1vkh#tf6!bGH>RAP?Uo~@E&|&S>uIjJrdfb{my|L!tPr-VE|A6(~$!Ejqg(@czpLg%o+#YbBez)~B-Noa{?DRD8U2i(GZoQtS|B@&Th|?3a+~ozg;261YoL_9Aam#xyaqjfm@onQ=cy4H0?Bv>;j<e4*r;H_0pJD2qjWAOvjDN57%pBrY%g~a<-oh}WpG5IRQ$0ied-6OAuNCv|$Uop%*RM`~{z}?|ba@(gk>+G_jrinYF_C}Y%^jtl$Hy)7>vz!76t8pgy{7ztVy~x6S3*5Y9uTOz2FJ@aPps35gAaVxB>${E>!%9+KJnXYnvu2w&gYukyXCdY^l+O`ns$l!{&Q}$g`Qvhl<Ck}t%8ode9w($s1vOpqwA*9pMUGAV1<mlsjs|+F<-Hs3ZJ<~S(k6bypv=<VBmkq&(?z?b&sE94-D%H9VNMrOY{2_7X>s_feoSnv4{hzuuqYgGax5asVnYhwu|d3SKsf(f@7+8{^qw>k7HqHwxMLt9wi^^!p`(peq#;7JgBYwOzp1f=SgXfPu+V>|0vhDQF8%@$BYMd_+dMx0)U0x13s>1XmTbz>;JU0xduqVRQ$x6!#4Q&IMDq!26W*Y0%v;8+5&tbXQiDswC}u|+MVYd{Z7{!Q}8y9ZjN&;;5ELtCp7V-HWzfFHbQ5P_QPA-6iir7GOLGP7>C}_4!!Ai>^bMKGdsGG8@mzN#3(og5&aj`syaReAmrGiwe5Ptn$y<;HkB0k6ksnn2&sM318p;@$OFnff}+M}1Ij#)D+H6d-D>{tlFppzJF^<!o4G$${(04V@_u4tCL83Vr+eHr)}CiRD8pZKj!d>|gG31RWDek^_NEa8Ur%uGS^E&2w@3tQz0sl$Zaz0gFbZv&Wv1n+2gsv%#deJnPSm-;S6fOr`E{5fqR(QE;3tjir06eMck}^sz2g1~%s$=syM+vpa}BEP3V|`(?C?$5Gz!9Z;yf@vee8JaEMUJ|@ENHHzSVwG@JnmWHD}{aV|I0fy4w!x5-?wnTh=7a;))}k*A>qeNzR92EVa`)STg(z&bM*ST=b#@KR);N^Zpn5QM6Z$>U;m^BvLC;yC~fi`R6&lR3=oW##mPCc+>trt&>l&&gAuh5{klkg#H1r|8F7B^8#Ohxx>bRo?F(ytL`RZ^HcsT%-MTD9RJ3?tDn`=-cJBOob1jh(Y=!F(w%%<_%Doo(PPWS^j-U(+o6K(&-)BjYxfbmcA&djj?wMIGZJ%7T$zvOv{`PgocHsSN$*&<i98=Q)MFaPTakTFIQQZA_)m_<8q2li-jDOw<(TY6UFiu{`Co9vwqCgw-)k`j^<pfe=9O=&;t`%JL>~CEnp?2f8`x}G59<-Vv~uht_yX`6VQVw(){r@fGc9KAcX8q``5~t$#&NHneiw>sZ>xIM>m`0HZlQ;TIP?kp<Mgcb9-f7%d`}3Sg2AYntsTD>XU~1&B3|6e^!)JK$ZovQ{%Pkz%zu#|!VKxvwbSNJpA@&m!fu`Utn|4@`9kZI>jIb8QuTU_<lZ<pGEdhq0fi#llxxAz8C{|leQU;E$WH{f9{ZVBt~Kj+dM|npWo_!-PI8dSd{p*OOkH-7*Vz;cqK^by%=~OU`JCeWF?+j2A#e^(8T9eXy4vc@X7}n`t2ybU5hmT#g{E$_Za5T21nHFGs?9D)*SY5QAk*BgT04%Db<U>Z8is?+UdCC?1I5a^+;@FFr7aa2lpCDI*9Wpum9>kC_&Q(rDYQ4}_cm=&N8vp4IUG=Y1B}GNk1NiLMLv&tC26g3rk-I>RNVkR8^u=gwb|V;;`!YF=Cv8!x10OF7kPFQ*dl4`{8-pXxvpDFXkD0knT6cD`GmPwp3U19&Y0BXl(8?xK)`5lE?UsNX0EX(tml${+l^h&8J8R;e8xM)-jmWWA>V-cYo#Z~v6MMe*V_t?SU1C0==F)aZTZ|vd>yY(kZVU4b<k7MUt<hfAx07FP}0iL`iiR8Tdjw~9E^<n7Z?EU2kSlaVjr0K&PCsQSmIVSFhH5spS5|g)hvR+!LR0wB>p193l;Ht&?twkdzE;3+0$%n^>r{b*ZKZr7+8*3B?leXO|-jjXtfFr!Av{Vy`MGzHH%yKQ$HNdYVp53Gk!?KY-@8b?!jSY)cSa~=#tiJW+xbnDB>T9t2|p;Z@eX%9QQSf5nAb;H%Z;j23q14<&*Zfv&Q;IZa+AV`_qVClkuccOoQ0)EgU!p9WP#tS94tX^hxI0Rr>Tl6AR;goZpB0QVuBoT${@&$7dX;JZJhvw$Pxu%QQYMii>Y9ybtvX;ILaNK0W{o^SHI3X~g}<iuhaFec(D(LEkzepJXnKdNF2}dw473>$Uov_NsDy$!;qDH1oQJJ%};C@x+`Z^QlpLD*DTibt<yiw!C(D)dpJ6>?0`-Dt<@B*)7_{u5QPG{S56Mb9Yf(iheR{Imo#-aOSDrH2*i>zy7INwts??A2DOt7Z?_K2A@Jhx2KRlW;XGZbK)oQ#?1NiwGRbek^ASWCV$m#h`mS=hb?T%9n9Kc$@Wrw_mXQPk<DE=g)=2<0Ey6&l>8Us^=s{Qy;}AhPo}LPTRoG_MpcK?ZG>Ty#2N5gHl9h;oU>R(`R2?|ajZ!(*22~?_01<;vn#0YiuLbL*3+|EtBG|f*5}3ZXFAl-LC@;Zh0pq6eLc$^xJFaYazXjJo8oy?xc0N`C7{u3iF)Mv)x9m8lWX;M6`$*VOZLAWnS+)49M%%NJNwCn=a#)Ezm@T7$lPGBa6s~Vj~D#e)!Z|@tu=ylv~{?V7&OT@*yH&ub-i%o*rRRO2~@7%Qoqa4oF|+3xSu}JUL9n9!1^k%i)tP37M1<8zhk_=W4ym(yswDy>gs-3#h&Hgao&GKoHzVC&igyg`*fVAxCFSLVax*l9qaua>-|)$S9j-r>?C0vc7`W+J~=tIb8<Rv;-q2Xro%6Y^=J)~7%|-6vEJXY-hX1OH<|5Po#_nxiqn5BYT?M+^_)em=gn%qJK3E=qeprP!z3{Zm=CG$&HuY%KXu<MiANm%9rOK1#C*=*G2h=Y-=||f^ogNMc{c~vV_Nj1f5&=%$9f-(^{mKErsPAqmP=>CNk@_EtxrMPtx>dRla>C0SZ|1U??=cp>`np0WS$4QXK#Yjz3R-8-Iw@J-JciMoApQ-+lM%U*2diy&W+$v<=;Q4oT+5IGwTG&SWeC#D4iU^<CS5|GY&-ERy8W(I5)@EYxi$hcs{}RFZFIp{+IrVB^N*VhwM{<1ICwJ_!;L5`8M3=(_2^<8p1rsD`GO9@4UuwBREWip8Pv=%Zf*d;)8?IV<^nIGMAC!rF#KC6VF5<cD-eu4yo^_bGpnFFG$fw7USuRyAQZ1W40jMhx`neXCvq=%-qh@Z_j=*t~2pLCH#gM;88IE+3k!o<*qJpm3LmZaYylq+i_}R+CL}tqc92@;|^k3rxr#xjj-=D?y^}K=S`m>0ajnTXMe|c{}J)s<nQ?I@A&T1@!gesZJsCggZ|SBdJu9xu7sKU)mbR{Ioe<}#V{MGbulZ>GpYMrtVN0#uHft5nT^V8ICF(>MqCPQiI$4D(!z79LE;P}tKy^b{r}Lcl-irqg1&dj+SC_fL6eK@$>5`iTRHDl^>cr2cB;akUB&Jvz*SFbPP(>(Xu1iarA<C&7e;X$c6RkJnVr-b&CcZKF?!c#fc~!U{axStPpa>=CpEV>>zV#JOqf&iHLMqB2}KUcc-S&NTg4NowLL8n$B0=Q<xg}>-J8Vm9~^J}_5tkiTaKS?RopM0IVe1bxQ`**`?gh{RpB^6kL!vt+m8H2Lh;U_jGq=m?B&^s;&6M#97$<rh2#1Iz0LwZ5Hul{x7F{<=2dJJ?^$oaSY!U^L1>><$A`Z>yHd<G-kpi$*KnNFYZYR+MpYdK+;O{X-QwJDne)+w9CjY3OF__4j1w#J6nszfjdMfzf}O#Miu=At+zSq?06cyJ5wD4S?*uIa8T0UeKVuIc2fNZ9<?&Q+7cwWbE6!kS#v7G6E$S?SZ;Cmv9_GEY@cC-(g(jH6PdU_H*Dl7lVlTieFo(a1Yrx%$+WMayZ%(TH^ap2V|E}ZxUB~-W9na~s6Sp&soTPgUqwYEMZcah8t2^`AIiF!^xA5;pHmA|Dc-9n}L6+(-VcxU}G8sioBJbv3NTj08eoG#B(G%l2X7K5+H6N$n5so>NjGvb6pVgaoW8X7vcFqfOJDLf7L0@rS8ze_s4X}_eW2T;CA>hCSpIRN-Q<#}y?nZNFmEO0S`+2S4-V*q-ZSClEikR;n-D#}<s9907nL6j(2AVNTKJO}j`^ek1?h7-q@X3~pkuirJFQIAKL!8*$3N1M%q|#@fq@5ipO>1!$q>s^N2eZ14K3h19dQsrbEVr{eIjM7YqV;*~?V9xeY44#wusnx}V}&01kdD&~J8lw0>thfNPfjw8#`96+rtZc`Tsm|9ChUadyL6H&QA478nUm@)ZUl)=KRCN7omKjL*9*5!gwJ#6&a5aO3Qlf+y5rgVXcLb+-IGK45ycPm`NI>%XEn#0(OKWo8D7@hbX|AnL(9=-s6~xziWxv?7sN|Rs1x?Pbf#~PV{by=zqA8;*a*F8<a)arNPFm>(0X)FLAq=N^ghR%H0d@qTyK*E$?Q1pJ9UZ~>*M~=qW9XgW(}Q-LB&W5o3%ur@|j-VSNd(Urqg%mZU*Nt^1(CEaME3qes4s7UZa1SLF#W^^pm5Trt2-~UhW#S=62W*>0Hd3Zra|u^cs9OG${4iT!T;c-@|KQ*rMXhw0MS~9(cVit(on3H_b2_o?Y5YCmC(&yJCmV6Mj#S&T9N!>Czg{gCjj7t<m!AbZEW3cuRTnDWv@f?1}BBfi_#05tGUIU+ndm;u9yD&{>)_#~#Jv-Xx{pUw6}PZQQ5Wp7vqv4O3_`jypc>@6aB5z1W@8{ztTCo+JAC9-aL;Ix+PA?a-VJ)N6w>b``%l+>ARDdpw_<!id)14(NAp5+_~J@1CSiO1~>28=N|Hp1U<Vf2o^>Sn+7w?`<49UrvYa9lbVys^WY^mVBbmab}#1@WX-&TCKN3_j6b$TYsddrU-VkA)9aGj?ib2U2}JChwfTJ=WRZzk*~6Xq-)dJr0<+2?tDhi=Nw&-dqp6)n$fz?Os)`_FDzu;Tzqf0p?n263`5rbJ%L*Q`x7zuNzM<%9Pui?UO=~MYt$AHU%w)bLcL4XZ}J+%GJjnHyT-gQboSH?^$7i<j9a6?IfK_C-me*4DEk^X3V(cij<?H)!}k0BAI}fV-NX9ZKb;$Q*z4YV1)8k{>G#Ev%DvHYFw-3H`Jt?P-*P9j=4iU}J^!|H>|Yxt$xWGAe%#P8pV{K4xIM2MKFxN1f9j8VUOXL5X2+}TLo-#rP>#1oy~%9qPVdX9F6dfCd29L>$ndq2N=tvvs7q!QCZ!$GRiLXL*kLE$vYG3Qb^(PYffq;QcE}V{c<+UY+jr>NkCGsD=ryaYo6u(@Grqp`-*m)>U+_Dpy_q#R(E3e0YcylJlkFwQr!Q%Wgvq)5TbJZ=;_VpWmq#H}v?P~0Ba^nG-?Adtb7PG?a(8fP-j05+Pv*kkhTf9QWk{yjr|a5F#$MN^b)hR7@8D*C{kMj_*)Hzi&)l}(1&rRhpZe{8&EiQ#+bT<!3auo~?3v-r_rN1_!)2Z!B<r?tInF%Xx&0Bjn^gpJ4x>sYt`W}t1g6qSZ%*XyDb(nmDKtsRM5b<MN$z1nZg~y2O`)n!A?;>+wN(1CyBC4V;*P$PTi)~O6R6jM`{w<nJ%{98aeV6mA%z!6mlKft4mYk%t}P)~m9EH~I`qu5W7xso(mHrf8qCSPCf!q*bnD>%BhyTKPoI<GP9Q9yKlj{?+ZmpM`z+*psR*qNxZ0&Mi+Jwek51g$uIBLz#>u55;_GaC={`gLc6Q}luXgmyQo5Jqq9_#embD-ux99l@xs;|ut~3M<Q=e{ZGOUd$)Cmwu*>n#2v^MiDg?D~Jub~i*_B`qBD7^Ufb8Yi;zmc00X?GoELQ2i+x*YJ&?{SFVLasgFySY12C`WEJq_BzHv_0LqiN7J+R0AB4)(1kyjR0XwdQ*2P?4(ePLR&X>D3l`?xTW<tkH2t_-Cm2S>dB?D?AfpUR;M$wgLGIAJIlJ$8Exn{(*0~BC`5Wmzi~<_;{>7FiPoR?aud1pkiye7?I(rtUYEk_9sNV;frs`v{r>H*|5lXNA!oaqHx8gNyhA!KWHDY>gH7$y?+q!90xvKq|Eu8n`fsQ6*`!d&qJ5(fc}Ah4n~eKpqvsSVB@|+LD@u7dY-~`PKzmCzZBF*7v#SN^ghIA}{w$!7@`lofa2I;(rgQ#+-(L4?%Yk3x7Ws#z#x*K*+b4VL%9fy|{8ts-j%Ev_Jb14q>3y#GyIo3WBx24}n`~i+>^%8C@>>zz1qyZBv76qU!#<yr<G3?C1LQ>Zg6_W`jXO((+;)IFMLwVIQH|2hFR%-eI_<Xg8QF6whwEeAY{WKn)@rNyw0XC0BOU*O^`dlOjubl}n;B9%-96J8qq{@tC#AMdr?&|cN=xS$@mwX8l2Ggv)44+|G(#+ugp^j1|E#$-rPa}_MtlDsuwF_!*aFQF%fNiQXNmYrv4sfP$q%bDekG<jy9s}HgHrmYV*@@%XC>M-#`7Vi*odc)Ceu38ouzf6IAUlajiWS+;>?)V7Jdh11iIJcYbpJye?d&4_WLbsA)hVzyC!d5x7E2n*O;o%=}gG(bD8NagCtR^MDhJ0Tx?>Br8DS@D3!mHA4nUp$oB1;U0<gZUu>Od*`(C-gm{|L`!mJh@wh{2YKQ!o7c|CRNPj-5(>bK|qqLjsJjW?GYbnLt$#h5ewMlzme}xbGDce@h<jn;o=&hBXSK95>m)NwmMQLzz%;ksP&Ox~*-Ow6QS{?10h<)f;$iLyt&6;j!N_W<2P;5)_9r=HoVj+}aJW4dlW4g$BD8~Ma?x>J9TsUv0<e|m1Vt2`=_E@0y`^h^>aZj6b7Z))PO3EI}JH1_iGt~*sDEEZ(S)FWFJ?u}&&)!(HzqHmnvWX~<%xLXsB`K0}JG&!FSAW$VmGo+<em1dwkg!7B5g^k0g1hN@)7YhaDVWdFAaUsYpxil3DF!*Yoq*zy9^JV%{3@*z`GzQ<IAw~M%%*$Uq;nYs_7LYR#(KN7_u=+0znkLBdEJ94!|8wB9i^BQT<ih)N+-hoL*9&>+M#%&y(9lh`84I-kjIGJ-Pl`F+~(BDk5bNsl3Yx-ZkLh|CEG@4)Em)jy1#x$--9y#C)RuL%nScn$&XPEQTsNySQDUlI;7XOq;%1h+$maGK?GO@O8J!crcRUc-#YwGh_gz5-1X?sI+P#VUE0TC>X1zhy`V|^N3ZLqlusgeCVRF_-DDKIUvRcn$=t{(_PQ2AVf16~bLmn*HLlbHaK5+{JmP!k^t<&j?sqz)KZm~<QS3o6-h7CbLk+DIH^JHK!XDOKu7!+fO(sXgHRHY;X?K}hKv&9^-(L^UuZMsB`1bM|A71_ue_!stt^Rp8zWw7LcFq2+*05XusMV~0KI|Xj^UL<-pWja3maqH~)w(QbBY#`C&r79AVp6{E0L#eQqAa6S&|0`1>KY~@KJ;}x5zqv$Ah}a>be$3@!MU(c8%Pu_xZU1NAM>`>5qnz+15Z}_CFG?#BS6%epvWw@<BRVBJusdLZF4_Cn+386I*sn*-hX+#)o3#9CXYP?pxXltVxl1Ypvq?2&9st&Qu(EY`vjRdhO-#-yE2cj`v*{N7pPhGVZHtGSf8A$XqlBH7S@f{*uvcwc4N5x0QKgRD)Y<wF6|@v!GtLyA(46j<V8vjmSg+9D#ZiB9KT9iA!4*amakX5{wMaB?9VsAI|uPgi1z+G)S<D61#%gqbIX2MJcG)-CR)OJePks5PM(uuo)-2gkL^<|(|0LOo>Kfw|Mp_?$MCxpTSdreH&K|7t>PBtXcKxnikDr~^(@!x+D=M$o?@a9(6YI{UdC@wa*DDR(cC-^AhYb~wyOL)bo%Fn;fjfXrC1wC!J<v1x2}ybqMWYxNwe)j23XLSWBf+eNR2a?+gN!<By{@u@xCP_y>1a-v6RH?GAT-SKz0x^WO-|Sm}vD1WoHM@8~F{uRW}q5FirklT%_v|@fb@4R6_(!e>9(+DMqhRUP$(N6Oq3;l3hN!bL8Q@7<o3?T^l*3+waofwRb@>X<{6o_J-^=a?4HZ(0!nomF}0*46o-wIem4nrNuddLKf6CEZbI+0Wf1*u?MWz6bUH*<V~Itz|#+k*7j~cD#DrY9+m{8HQY)$g50j3TPik7@6wwy?T1A+3=##KM~W4~a&25t@b)u_mhuRWaffbF%DpKTqr1~VF21(h`HbR#WqpjClwvT-87M#6QLKxcYP4}FUkW=ji~gMaX?sKO-J#wQ&MBYw+VQx5Jx2S=bDh!KBIcDfH9&&z7DjFP91aR20-)s`_z_bR?{`=3^zTQ<YALB?NJKp4_LgGhUp()WGf;f%Q(TK$2;$r&+W)a*k0>S^(b=XrrSCM{l+H)r-=Z}gq?GeUlzVtLloR!K3=2wcn&VEF@}l+8J^#dc-}C6oE9a3JC3WxRvAAw|tg4?;DaA^AFc-e@4z$?)Q(8sQ{+YG^K<)f<=bds3w?8DGK^|c~Yq+RQd6OpheC*&n?yO?UJ(`q@SYt1+(C>8nKG_}0CX?=&;yu*%PGQI0jQi-TIOJ1?KXcx5$Xh+9&Awz`KA-D;#)bo)P4P%9>oo(X)Ps`sLY7>qrs^{443^uU0U|-Z*4<JZP3t;2!8en?t+^596Z1)fV(;3xGi#8oPTXi`h1io6YrabnR|nAW;yUZZ1_b7vQH<QT*7g2EO!-9fjh_8EIA5?O`%l%YK4Y&j=7@Wh#hbrsFR)&&w`;l`Nc>EWAs{pT3C^lL_IBvY9swC~`op?_Q1xg{Hx%0d-m;<h_+(Rh8`s0yI(4!er;MKeQ~r_Vz@ChHRV-@?_wTN=L9-8t`@_8P`Y@Ot9&i7H)|%prumiZzDgxAw)}GF&a|-)IveP%V!_Z8!4RmH*?lY3#^oI1$nqp7%P8^Hv1%rsl#?b$Fe<~Kq@-nS%f5|V(*ODDoIU4F4%D()kooB@7sOydU)6Lj(cRccuP+kpu2G@uX<1JCQjGew?Iq8IAcVG16>2;y!ATF`!Gg8!w0`z{*zqH1TA-Wjn$u;HC+61)~i`LcOQLc4-OqTySe(o>mVO{WZkf#v7MnJ?rY9l^VpZrVDZ~%C2;%+IwJj33GSTl+doD^qviaHamJDuUg-#RwsD(Ra3ZnX^n1@Dmko}=dE)VZ%SpVD5Dt+=m*6;m9Fo<MUaa&b`ysLUN%x)39IycYKv1hxNjd0bFmiIGW@!h!NN$Yw*{V<PYK&Dq`7j_z&kJod@wcfKF_pZL4^zQyKQjLZt@8t1n9zFmyTS^ly|u?^<|#drm^u(N>X_i806ohTN%u_Y-T0sE%&c3#H#{H5v@?5n<$>@aj|&v(h`t<ZO-@1LSRjy2t@x_MZySZDq|$ci`l`>x)vPw(l7?2iBZ*r)rb^3N~cSGV`Y`}#f}>JxkGetd5$zW3+$w_?rz)II(LrYdpk;&X>)k0W7OmJh6F_)vIX;{mc#0<)ycv=m~JFL?I7psxAQne@LGBxA)s0#g{CRnK$<Uy#Z%DELyu12(91WH0t7_y6i|lJA?m^82plGxS_@)ClDm%wF|2+CS~re)X=8{ja_2@5el!*mLW{dtP2AWf!*MeilCmeb$eEPWhheqh(hme5HhyDfg<dVJu6k?#`95E)gGyp2A3tGOvHqkFs<iWTk{&ye{cEZ2A<NL(Y@_InN94`-YKHf&0Y19ZiWy(YF>F-kZ22eRZ4FQ)NvsKHN$9E5=gHAz>wIdVhM&xJXB$<UT9M$3IwWzeJT&U0c)d_&d1hDjC&fJ-}FtH{CkGJp-$r4r}zgDW{@1zfUo4v_$Q;4y+%oQO)V>D94yl9v0ZZ1qOCN_l(vj^?|pnVf3VMN03u}<eVJmWnZ4juPy6-#I@Y(`P=8u`1>)%N6&ffPdeux?Hh=ZQk(ML{-j1{oO0eJFg&r-S=K49XgI0UL@z!_mrcgNc4+^Ai?%0}>*4J0=uFaG>CcYixxYoNKlC;m?M$|+e#5dn7XI01zc7mVH8Eku=q;_!68M~Ykka}@!P$w>=N}${g?8soEl8ZRi!rWrlwjV0;++O?P;R=j0}pvHYL~blzyMH|=Pm7@^-oUOKjqSNkQT>yY2En?W5Yis2F#>KE5~3ZMuGDn$N=*ipx@q-_762%%Z$kqLC-dfCJl`4g&p*AeafSk7_Y0L-W*22GNZ0B1$G&<T5-T5tWIr=u~hB@qlO<?PP9CZJ<7*BHx0T&+Y4jn>UUI8!+rkwf8PFIjaT2l6Qg(xD&(}=8253`(O;U>9S@_%v$HdwHQmS|n*w`5|DEpYPJf2cPx2R&Gy3LqKj>bqHW=L;_sQDKyVe)R>Hmg1@oul<qrRZ|)xN;6e@rpbq_bqHo<sx;)KX!N|HNKaf#Tskygl1mC+$UK|7|f7H`+K+Z{r}o@X))wIbn30{L~ibEsWNUG4Nvv-BFC2<Igb4?ZrE{vr5SBSY)@4CAyou_9~xgR_=ib+hqrgd)({-Z<mHl8yRlto;TtD$akL5AL05wdfT2;b1?dCV_im=3rxlQ$juqDPLAD6TyI%imkhHj;{W3z$F2(8&7at>Dbi?sq_6Vl;eQMJ^r2oQ?-T4bFzY?^yU8vM8*ZmdYd#|zJ+aCD(Aiuc18>q``rSF!jGm7>D(IOz^ep6?$yZZMYB8R)A6(og@m#ah9k5l>PJl*G->*Nlmiwt(LbqS4H$OS3vnG4<7wDa|^Pu{eS9?G=KhZb3`DEYp<|q1ph3BHZdfZPA<R`3fuzOwhoBPXWPkfhiZ<+lE@{@f2e%=Sa-#?INOW1lD+a{opa5rv3=gS^##@?(BI%&{ojQf<EkxdG5*D;%ne|tM%Ysu%5ZS*Mb@}|2nom)D47Sm&p4|i^Vwl2DQxI%S8Hq7OCKC4fGvZ+_BM{vJa!-?vW*naKN;<E?rW%R%`qNb#U7IfH5spJ3N&~Sc&mJJftsy|n{7sj4w|KH*|QfW5atUDgV`8$}2>N@2C64CH`EGJZjXHm04`b^&fa_bhT@8ZXMlOk8cgEB3pm_z8%x$<kl`NR3MkdBvl?{A<Yf_%324BFaeak$o_E5@=${85~Dx{QzitgRV+XdX?*d@GGoglR2YtM#3!u*e53K-oB`zzXl(9}g5O$v854=(k>i#qc11-)~y)@j5-I{Lb;MrPi0{Rxn3l;ySe)NYGX0cj4o8H$&$9lezH6-un)Y&4^h)hZVy2>vSHVJ_cQ!HYZ}9w+r(RB9{^rVDxM?ii0V(Cx6F1GqP<J_(`*dG+-JQ%shN-2H{;CVTQ9TV+f6WC6|8x;H<~z^Tx|I8<faQnflRLtWV_{U--SB$FY6g_l5kOOz()C@%eGv{J!d2FJJk6AIeca^L>Wzt;7N8^B&P-opJWNg`K_jIV}6peioDFG@km|{M^j&p8N}JOP%i>*@CWa3&>udkQaZaxZ%e|Zk|N^y~LJDy7uK-<y6DLC5)uGet{mhRQJ^?zenxcpZz`gU2CV1jrj0)=;t8!h5N_iypKueJMhj1J=P{1#803sRy0wIbY0;;IbHx|6Xvm=BsDKy_ey*5V$e>BzpHDMa@>1R`(2>D<3FpO2~vMI&1PImHD}Eyi5R>Phk^dsx`>g>Vt7Fp3HgqatTOK3lOFqMw5Zo#NB87guT}0J4lpBS#LVX~n;$RVK~UI&PC8IEB3+umJRg&Z?|McYLh&=jV%a?1!mxSGCuIvS`QaS*-FjKgt=FoWzbEp~wR2y{({`eVJM5I|N3QTGHy^2cetr&`?i2ZKo{7|PsT4mnRu_4(K8#(>XdDd+zn{lZbFA{f)Nn2^a`mb;o>3mhoL#ie4@qka>UGpX3+pOr+gmRsD&E~inr87E3-f&{kEK25*|ch#!!v13I_Gc8xTW&9W&sPn)oA+P_fedafr7Z4i_B7!>T{M33;*p@<p@6+XQ1!C!nwB|1yx~c*f`9Va@~CzW9HU~@9h@%xK!T#fgDb+8v}b`KP*OXkBJq_??w#Kpt$lJGEF^Z8r$^;#H+om*Le`%i+heU+s=EUWN(;~Pmfji6kAF<RmeQuEf8Z&4*B<JKElrK1D%iXO<`ld4M5{MTkAFt-zD<GcJf#st~u{NTY27p+XnUZbEu?|^7S@q6`##}SM>WH1kLx3)(&~b+fw3d?|2qBi#^_<VJ-U;?pN5T{cbividm<i8TL^ZUDn6m<TUR48#ldajJ@GGh`<F9G*M>`JMB$4?^=%M)W+Tva|~xO7Zq>aK7ESz{CVu{VlFkN`-inSNSeyXvAeY(nt{{m<aXBdd6=yNuO4dY>r>bV7M)%f&Cv5A3v|;6qV5^B$<T9-F8It+)QY>HkWF3hW?Pll(QnRc6u><%HX5F32HbGs_GhPYXO+12C?0p#XUy`Cu{H_L6zWjZD2OHv`tOK)&FRh21s$zDJcrS)=5kGWaz>rY?acHuDeWdxkZ1K3u?Eu}y`P?Yk~*EPg?Vktx#{2QG>E|G1}fG`&7DtDHvuObeZSY+I-O0#zdW7p+|Kam^oO*5tF7yS3r(l$6n00m2O=kmHkfVOjyv7@xIb%*fd>K4)SNzZKBQ*>#>6=>ryBj+iFS-T3Fhb>bS>}(I!TxIXi4j^qwgQ>#<#|KtYO|0wsFO0trEkdNt=p#oSZvFjEcL?b%W(uNJ-FdIIZR}FyZUmZ?`wNt6DB>P&&(A+041Wl1I~hc?XA4d`>NQZL8YE8uxD4Z<6hNCY%5JTKGKi?66Zy%yHjBCL<Q|7yYXG70#`!$;6ZMuf^rL#F*mL%lfI1vK#0<@-}F+VaHg4Z6;#fwF|qZa`XE()0V=%vG1&Y=JacyInO5`NwAvpI=_aH6QMuL<Hyo-A0D{o4%ri~dx(5wTYWy<+b=yIOu7B-zMahq4hLM56=#Ij{jnbx*8jqDeeJo;pQo?5VA@*jLT8!Q@)6Pth|BIN#z=b4kD`}kQkP2~>vw`{b)t>l)7G(pSRbC>zt!XW=hp4|fBxqe`6PaPd)t0H{`2|!%i$k7r3C)8Kq(=VX8f#F$jUWlyLyDt&bJkptrep<Lb_2YjAJDsI&x53q$7{CSA;U=HAz_sCjmuLn?i^J1O2(J+&t14e0Ni*J4$t~{baoY3;k_5okFS`V7vPq!d-n<lmJ)Btf0gRwKBh8idGg~^$n{~EvmxMjH+cPRVQ8^p@fi>lq<K7_9&%v(3TV(V8=(h>Nza57-+3G4^Ux1nUZNdnt(>E1<N$lCTH1m=%FjZMU*iEk=Cj3R+f3+QTMh+KIm(_ng2Aa^~U%9RH=Jkhp|#vDU?Q~i8Ig5Qy?gWnAQTXtu6=T>9nB`Sw+V-r`IyXa#?JLZZ-FqKj*|qnN=ypIPY{;Hp~5}iSx6v>Du3#Da->@GWq;(niK*<rHsS5s#NB_(=DG7#l)}RJTNJHISQPx(uyj()XU?xB@;Fg3KciF7kF+^a;)=bZ>ztrO9hLApghs3V6t$6se|DnxJ^EwyV^IO5lRnG*J1^*L8d5@nR8YstGhZSaVpipq>5F$U|Y1ap5XaTPo?LJTiKddtcOyW5@)LKAL-eiV73MAS~kL^hhidy^)^qsdCpS<pF$G~Pb^B6DeV_2tT6_5p`2FLj)J|Rut+K%%(^{qb~eJobFf%t^lidE6=-@Y&tBFVFP3-TgY1;-WVTkl7C%c>sp!Mdj_UT{C5S-zS+3eFZ4`0<8lAFA<At+Pr9g(UaL`Si?#Q06&X%GyI}}wD%+@l89Q#bI2>;*fJyB}?WGaSfDXZz)J6_jsdwNPsJ`f65dfEO_q$!z-0RJw-c2$;SPEK)TaWD6(C*kzms+v}wt&6^2FH!A!_9I%P1GKIXvTIaE`rhv(%x2DIb;ECw&q4_`QyMPY$LTYt27Rd#sY+8q9RP}RpekC+lE(#~=&O+JmBP7=P||DYX<!YML}7jU9ZE%t{)q4BVDv1go!T*|0}xWv=O7l*OL!s{86aGQAD#Vo>32ejQ2OpWeZO&s`^{$o<B8FVeR-&)QDVjG^QzCbw^@A7iLUx{-<JCeWiLl4T9*|FpUKwKzKtyUU9SxD800F^N{!eoD@z-1{W9F6`3rClqXl17r7I|Ye$GaHeq`Q&2BD2p@%oZoLz&}I*w_vIZfn(ds^PJogpBK>l}tG%sk5ZbTG-7uQ+Y~Pfsv`q_4Uo|V4v<-0p^g!T-P8k*XeN&VMR>Nev@K5K<_g8&4DO|38nj&4?{Ynoz~CQRYfovQ#F+`<2OMiYAUJ7-?p&Lv|B41)=;hkv>Lu85D+iTKjD6b&lzo`PzZf7%gtnW22Me_j#AM&sKJbOksKkaf(yIf={aoywRWMJx5-Kb`wUiqG8YtGI94yItY&J*3i9GmY&bhR9@K460t7T|Mr(8fddIWd?>6;O5j~A9t{<K&Z--xO`))AS&#JfekyereMIXu-qMSby;|W~mD!>5OCdG>^*}(P-H8RzPUu!mCty2oHy{obZex_vEFO<s4el#|Hrtnifln^(Zzs`GmItQR%jD~&HQa`RyjwkzDgCC=K=j~CH?cN^kph!ciY;dJg&cB-m!u-BWdFZETGV<6be&rT!rVuP_K(#_&e#XRmE{;Tgv{s>N4ai-f7Q7MVz|}K;Q{mp=b)c3+D;r9~m)dR7gWviN)jWLHop<w!Qn*=Ph*5H{XMgYQ8s>;?p5N2D9-Q08$uVmu43&cI%oXMId`;NBdrdig$mKTtt_{Tk)_1Z+X*l1!J@zMht%j98R~QXm3}vpzIX!ALtlDc*iSoKxkF3VtdR-P&{e+SfoxQ?%P_RdA62d2HHJ*mFoBkfpQLM=<G4?V)S#sQn*7PPVwuBjC@tMz*ZA+tWAw~_46id{?lKhVJ5%tR4&V(IsDLhv+tQwIkl!s+oRDNcm6^fB$@)4Y$im~g)(NONh=nN}ZH*3Pj(z$0lUr>Qdpj@jIEVX#sjCC+p`~5Ky`Iv}Pr&3|myq}fhIpnh+>#Vx0atqk6ZB^SFu`=26v&wn!-fyy2z;rCItC#QN^W#Fr;r@#ew`a8O*Y79R(ec*Bzo+M4W_Qm`jlb7&1Du!I@h-Y)m?h!--l<qbjpPB+Amih%gs5-HUzo8uw@<XaNsuq>D7KHGY`$4;+gr+4^?WKeRo6$n*A6J>Z;jCdw0h60q_p>V9xY!oVJ{dVd>r_4+@EZbIm($)2<rPN&KliEoIN^^MZYF<Q=^Qpx79!H2i+&X7SHZ`t&tZ`d$YKGKlP_VN-J)4yjs)qd!zRKtT`*(Hv#d?{k;yuRIRKksF8ZT=agU`hz$|vNmy-kW0~*wIgY0|0+dEi<(iqWSDZVZ|GNA5ZtY&aj%*Q~L)weM^lgZJ9B>T>et~>+ynjHPl`KEuCvV>Ilgsz~<Z*oec|SRoabZAl82x7YyIAHlt5~Yvmg)@wet+FRG8BUEjJT6@zhJv|s9XFS?<B?Pf${gMz4eLDR5d!IHp;D1+!H<v!z%Unr^*)ASKqbsyLYYT-v9OfurgkiROE<>169AT%!_(^p*l{n!d%K5%3Swu-n1U)`2TL9FGbJHF*u-<$O)%Ul*>n#MuFVUtW19;sm-%|Fj*Z}w>9f7D#c4&f6-(9tR^te^X5BQ7pFVhysN*TTMB6gx<><tYqPZesj3BQ<CTXC=MR+W>YN0HobCT(@7=l+SCVbv|I)AD*JmRE=Pb?``@xutVOwH>g@p8GpbY5ZaxZKH`t>Jfq%N6~xVc=ewR_j-QKMFuF^J5_$hgdyQ=+=%81IGiMV<1FyiQcCBOM<Ni2$GK1%d|B3?P{Wi2##jL6$z0WY5r*miCuyFI=$vSMpsp+J1?8vie;qrZsm-j(Y)oYOGbzZirfZFI%f;K+4RAhE}?pu@}9TBH18nJDSvkN)^&;<a1l`Jye>ZwC;Q1$O4q99b%8k_Ue!Uq1U7}dDQ46UuqU*04iiJ^K+EO$4+N(Oa?=VrAobmLZ4!xzdnf?UDk6-*C)7#a=RZ;%x3J34xm=Zp%-<}>NY*Uw|37^PI`dh^bpf(i4CUpCr!#R_&!l7mdO6mw?Kd9Y~8T)y=Gd4x}gN?P1nn-x5+-HZ)VBoAMKO8^51=??|)BfXyi+R_r*brJPYdMuI^!+xj)!>kTmL$4+hPQ6}+dug2yP6T!^VdY|)SK(C@jsbgzwLdwuG?uR7N(@#=JA6BNZh#_K_q0t(lGZbaSPwdXqb+xvG<5B+~<pIx2r?AH{V#TC-MY47-uJ$tx1DiwL^y{|gULit=9VZ_^^tid0yjR+FIQ2ib^+-mC0+%G>LuQes-y!LI@&SV78j}{bb&4eDpZp?IHC&jwsJmMa<N&)tT=Tqrz^`w!`<9m0a4~-t6yFUv1KUu>|{)EQ9m~RxI;HxAiJVGy2X=D4NGD1gV4mAcm)no8(HS!+`oq`S@LiS}XG^Rh-je`P%Jqr7}z{k`l%|(7T0<sULE+M~{jH0fe(371Pq_91<N&1tlcX7S`ws-!qenRrPiQhezUuI_)W3!0yE5|O>I@_w8*RwswXYKj#7n{gyQQ1E@T{Bp+O)c-jT_)8*c1G*?#&zI?0`eQhCtewD9Kkk$Cn}9IeN`Tj)L6x+b?=Gq5odXLoK2elW_~R`>eo)J!F6{hq?UVYBepr`G5DO5uZ+<fB0qQgKik$m82|itw6(uOoOZFTskInUtDIx>Pivv>ihC#<A(X~d-{+ABImR*uDx}q-IAL(N3|;4ya&<uMdvAlDv9G52DD{icugIkypG(+`heQTE>AmHcC#lw%)E*~vmo%S~KHa*6@99f8hVrwWs-vT3-nY78$L^U=lWu5@Yx_T^HM?8D2PyYC`XQ9tHjYx$JClDcorzj|3zxm|^tES&Mgf1#V{YW9OvZuX?#^w{I27ouv;C4|qZEH7#+@>}vr-Rnou-!4_JkQ_V*Y%h_X$jaJ4^TEC>DElq?Z-b&oMecwll<-!B*g}GW^(EQNl;;dH7VSffhy}Jb`DaeUl{p77_QQPS+*+FPhg^dk$009#6Zi2fKIGUc{H|g<Mmg)$^J<aBYh_w)aBqLc&urelZ=@$!gdZau)A_&tEOUe5{vu6Wnc#W1{_k@$@zNfGg$f9~5jKM&W?nz_?P@tGX}AOeFG+^)o$M;BIHbq%O>3-EXK*AMr<^cYboCp8u$&aW#E6fz?jVSY9`m>lzhQGdx;c(Ql{y+iNW06t;jDea7c5dNOUppqBR|Kq+Kymoqc%S!ScL@_W*Hq0fU{G3jYcrJlwR)Jf#$Y~b8O#{TE;qbsjV#*z}Bd<yG*8vpW~*c9+&O7Eii&SO2Zp7zMH9%5uw8iD=j*r-JF#5Gvmjm<UX*&0SS4N%v00#NOS7)=~?77fFh_@2L_*U@WY5As1fy65(W@9GAq2RrmfH)1nh>>*Wd#8Zh1aVTN*c!Zr}8c{C_=>6Ni(f2l{?m>=vPxs~l@tLU)=+111pmX-{^LVx6_)Rx`!-7<i4XV_gXBoN+nd(0Mt-F-Rt*Yc<)zR+T!NH8UR@DH-wxLfV7w_W-4M^mIHqWpi!@gc4c5>rsY<3`b2f0CS<N6`34c+N6Xj#o@WSMKvpVno(T%}anS5OH4x=~SWF88CP9>uZRlZ<nryY+y3Bbx!~wYYa%oHr@>?CQSQGh&?WwSKufKeWl`jaMS}s{u>&;xQHym}xvi>&-i;u}Z<;mhbyYY6ANWb(*=p7g$JXzNlj6sX9*lamnV_$9ec|EB?~{x%{?W{Iz*`-MoL>{;$RM{U87LA9gO&yB+JTK#XCw4zw1iHHG(Gjn=ubx<9mc9;j3>w?QUy8}tJ7t`<7eOReZTYU%!fBEp-kc}^gmwYl%o`OL7A;%9vK>E`#j-rDl#rk~jvzZw3`mV41Rwf{OoJ+U1G$io;9&oxSXKKair-7%{_AKL$#>x0$2-@@qS7Pyen?T&2zX4e_NbRPTRmi#R+%lO{FjlC@$x_b`orst5I9(H^4p|Lme-?5f6>{GC^^`7oM>^qD<z}P?PlDF-;3mi$G>sW|g$p0E!W7E*2_ZY~yHu}!!v(OqdjRV=M{l1)G^t6TfK3bQ3fcHa;LwAj4_{J`OukXjkFXex$)aUl+eH(lr7?gND2^Ncz#5|wlRW5gl>u<MohFgHg1pm4gfs?1;ED>a-jqEhx_vd$Z)xaJfv~OsR_iYXyvIYt{ge7Y&AQ%D2zzk)e@5v#+60b%6U3iXtRs}|v5~7W^a~<<96a+ZI76X->q%9838hAL$LnD0fS-*`h=7f)}0!*H9;?TN8a{=~y7~IkRJo7+GGFX!7(Mxmo_&($~Q=Sa~Li*l2C4k^hsHGfIimtuNNpYk|F=YOQWDslnnCL=F$tVZ3+^`1MP&%BY$-sIkkWAiN-Y+_!$>5l*Lu~?#a7cB?<>Z$O)6OZ*NcjTF)*nSyrFfhUVWgjbPf6sswteLWrhikT%aJ)175+>a1kX)zP7aRn-KP6w7n&nS>?s{OxRn|lPV(%xEyJpr_xBbDG&>4Zn)hg!JhVPCj8fK=q=3Wd8#^x=)V&D$r(MmX&!Qkf=ydd_b?E-$=Ob{^`-7N5l0CSWO$YoR?GRknUNo(_U~2a#n^B1mI^*K1)?m77Z3}?ddizBIRLVU0g#m@k-qeCy(on&`E^~psTisUY;ZS4n0szt@F_iIs^&pSnlA_P-JuBb+xo{q5*|~mChc4yMIBTc%5AZ90g+6X^Eh>QdA6nA_2yD?0!)&mpz-e93c1ZTP*tER(%$?;}FPydPj2CQfH_wY4ubGWJq}-(A_Yc`+qFcrMxMD4<*H0P9SZTDU&5<>3l062L9Qj7PrUWdYJq((L1&#Han&%^7nl{bOWbH*p!-Gx(C4=-kq1UHipOO^=Nld)h85M&)8E;tyx7vkkSp?+n9v!;tDs^H$`5vf$fG7NG?tp9g>Ap%+_`LuB2>1Fg^!-=!sD732*FVCOulW9-Tr9b0DC_by{dK<o9EriNIR95Zld|t$qLK20!+5{g@25bM77xPSJH<Ga!A`$22l(i~bXoVjvx*Ih{S1H6q`QCbb(S02^Mlt3!%=4)86EQdmP<B3u|Bj!;uZM;iu0oB-mvI>FpwFe@Hq)aokf#;i9WjM9{7<p{yXFXXLLP&Z9Z^?W_i&+3@Hv=>8?H`A26uF7f_s_(RYt=4?v5@^t&3}3meZF#2$1*=x3%r+@Me|bpKq65th(Gqj;iAwiN8I%L%Sr+jDorxYTUsea;HHLG^kTIE}M&UF3<(YZVx_x8-8*L252>J*e2gFWglZ*@iXkjUJ|6Z>k;3m2(gT3gnNphl~37q#u~pY-19(9wvC-z#iG%ux(v-zh3mr^q%cWSL>C)Cn^{%pnbtm$=kBT)moLqbepD+CRUqlmhumPOFJROCIk9=7`T?ZbFI*a-k2M=eV2Je4IMg*Zfszvd}BuR9uYWADc9+cAM*zn`H_o!yEefdz0!9dTiS4X=DRZ|=PU*B+@8F{DF>sx4KbKM1utx!fhloNhc*|*YCC9nd7UoKE#>frM$Z(w%+U(q6vc5I`v-ga{<;ZXSMpC6-L20T<+IMj9u6l#*cscCp;c>Kx(3{=mI%A@#^OmkKoenb@GSB-Xl_M=rl}h-`6b<ry~yjVL(icY20pCQZ5R~07!>zV4s$R&2Hjs>aKhF`og2z?-95dQa+^=I1EIzDZghH2tRK>A3C)eL1b&jZ!G(U`=^PFmwB8!Nm*O(|Z}Pd&)`gZT`CK>dZ47YmI_}<$y0kXkI&1Pd6i?vpj&XJt<m>6*p$XL)?A?dYJM%(|^Ag=u)n_Fdo+s^}a#lL?6CWD1CI+7Rbf&F9^L%Jp(RX#md()!$C8o9MP)^ey=+GfF<90A|dbDP)Mz*rY9W`>iwbz**KGFUe9C)2h=Cx};-`7V|-xCdBs~1xKMQ3|T{*7{aXy!SH@3F^j?8eYvUaz75XLJ@6vk!e}X}bC}_N*|Z^HcY%LGvf9!8x6>tL@(COaWRT8(5%5y`~6ZKkBq2@_jLV=bB5oEXAsHA51BiF>(HV(_ydy<uTCB>oz<qpg;DSa-JH!_TX+l&+frpjrzvYX}kh(bwA6<vfh?=>)NN?e^HNY-45x@@8}NGj5vrre;tBM1(g{(<8{{=YslTm7a~`$Lt~Ndx+XMeP3TF+Q`Gx*qYgB<rxfQKpXm3#w7((QP?rCtb=6<d3;8^I`qBE(1$u>&4QBO{^m9+&y+4Q8=NH@Hb-F`8Xn%(9ZIEY<`V%_OCfOO~QxwCDD3%>r?SSHzo$D{4nHrLv(m5YPn^D}|^g8lkxW_2gqkPN{aNld@;TPNA57khl{3YuZr~7y^E+9W<Fy}wT!rBOcGJQxkH>5kCd|RLPxKC%+CmSUDqcx)#(SSC9PPy{lusANJ470bP`;*Rfh#cZG@5Ha^^L+R$|D2xCFFwm3>6Lu^F8Miqm0x_8KhkIZ@EQI&J?X#88NRl*_0h8&A^)YwA910Nb7}{a<5J#dKx;f;fT=aDkNU&V1#yJ6puCvkooGn+3f<{(xWQdQcQV;+kNhC{P^<fSXSrUq(G%LP>N;RZ;>E+-pR}W)HJR@FGi}(L1op#Z+MGU2d&Vc)K?dUHc%6Llnb@9UFz*FmQ-1yFXQvZoZ%n$c42N=*&P|<S`-9n81^{rAP1n7?i+F!$`aPfg?ZNPkgF$;qu@%Ml%YgQ>;rYFdYhl0|VCt#<iQhffp{@@#+Sm2Gzk7qm^ie<hOs@-DWrEo1c)Sj+9o*Y=l6Q30>mzFta{hukoeynuiY=YNp8P}2h|G-{!A85#il_U$+w?lLhSqq8UMBp3x2dQHs|5UOkhL!;C-N|ir~>U#uimm2A=j(dG03h#N{H79lK7mE9sZ7ows8)6wEs@;uZ7l%m~8b3hOwH&z1yhJHIw$F`Q$mx=SQbmz|4hjOyDlz>q>)TRsArK_(oxbI%E~u?uT@lBYF)zFZcZV>le39pI2{(WHXdQg<{aL;<E&%G^vx#(tgj6=vNy%n{wbY`qh1Vx;L)Xt3K@`6#sVu<94c!JnW696La!#gvb~m^ZqUwum!jpgnU}z{jSrRrdaQ__`S+K5!Hv!bcr1L&feg6?;Y0ndG(&5A2-N<?{4_+-DSk;iM~-4Vf+MO>zW|*V?6L76DdhPD-{E|aDXWt7D)8}5(534d_L1K=X#~^b8=6oChPnqJs}K^N$;BuGL5A@O7*YL^nb3yjioiVJrh=^YxK~3DBVNJdRGqi=I2ceh(_V-eH}s^lxsNrz7$^z-D&yvl;K>tr>BGXLp(boLy9{<_(8tfC4Wpg1$s8tdTm->;6^sxbs@zd3yRfD^5NvOEs8BIL#OBkbr*_9y1P+-8k>&W@Nf@2T!}MPv@y@t;2DGNW*F#gK`i5fIQ(OKc$n!!?a|r8mQt<nkM84+&VmnY6=KpVqSr*fTzYS1pu0SLb}O(Wv`>4=m+Nk9hm>bg+<|+U@|T!$YR9O#k#R5`#4p3hbL_}~CZ10@bsPX|LNPjGdfHzfceWdopV2Sr4PU84U$l=V+4cHcFB#}NlnGAG#YER(I?{fRnUSn6c>q<`6#M+WU1ozllxKWse}^FxOi|o1>SND_0Wd%mOVU15jOkF$?;EIaMy^i(KMv|ff2xffw}xJVX9Wl7A-evOa<?(%VMc5?UG0bVHy1?GAV#Eo$G^|ny`;y1eGAAAsz_ssVh$Nu=Dm~De1ynHTwVLVQE`=*=IFN{!s4y2$MD{K4EK3^EoMyloO2kMYtIJoE}EgEr@W#(x!W{Bu*mn-qTzwis?&oODcyO%NurjEJdAQO^c@|yY4*oW@(UW}b{K4>bG6$2$k{M^!cJyMU9i%p)Im7gYsfn2Dk()uFvc<E6~o73o=d^r_-@na7)?{B__5>Gc(@o!sO0BSi$#BNWKHXyKMBZ#pgz+yJCvKoz@Ngipw76a*BNzqm{ET~ua(YGnoDS{cM!24=6ZCPY)s$_DJLFTZQs!8-ich=1M*|^Jd`^Iz<-#Xwm$+E!bdDI*x^|Woqpa27IuO>DWttbt({&oARp+35^2$<sK=h*G;l9Ajd-=A&xpwPMHuomEZmPb=*c7g*?AW5DfAisqG5Da<WDKHjk|lVGu2>E2I89t!@m>XjOc&;K|{(zwirBIB=dUop7b5**?{w)&o!cHjdEnl@lms#Hfhb9+~>8{6l<ZLHm(_+Kr{R$`hYvvnyfvCPPWB0p}l8O3?}D8$OpBSTxY>|+|%!e^xY043m9Sgeh%%Uzk<IHa1Jo&?RDr*@0$UWy7_I2=Wb{{-G&j3>6yAUQ=hE)JXqbPYptV_n3dIg%EVOIrf$%)tz)2?VhhdlZ|WXuB3$zr@9BLt%Krn#!^A7Pf6TSPJ*L$jSwHRThH=i;O~Z`Wp^4hHAE-hr`I+O~C&3n_SZ0VM#minw99Gud2FA)$MFNlA7xbE?Tr+v49Q;)XJc(JtDh=@y?>C*;=Jehk_LwN+Rw1M<)b<w#6a6G-dN8e!_HChgsQ+1HuVhac1jjjH;sguW5fI$i8?sxSi70*8N-q+aVOKLcVc<G4;lWvPxf6s5CvZQC&(YS4yS5+=&vL9){(UdPWC7n6_8+FEAY|WY4->on=QJFvgl}q1I;I?VL+7k+I9_1(hno?6e@r$O(MgQP4aB-5hwPDZu@Tpwx(C;q#$=Z<FeYX^1`z}KoUv}uYfWptk!)X^SAMsfW5R8D>`K1-DIE+xGa3H){1_g#o9%zd%BvN_!g(N~F%zQ*nDYcVK=UqR8)W90f=b}+po*<QQtcvVsxQf?TQx%#p-(P*N@nR2x3@D^Cuqj=j48dhL&2e1sdM?ffWk^=h)b!N05N4ozlz_XMdxS2FsmJTVA{Sjm7?053m4f&z0r5Z<T@0_m_eJI?uL@Km*riU1%FjV!R*k^%%>$e87>6ML14n3nmYugIP~mMfH|*^4;96)oDD{o6!7?vN&6sF`oOw^i;h_dARY`x-qZn##F+~=?|Gm-ePzQFst@JncM@>X`n^%G`Q}N?Kl8g>C9eGX5A5-?_wo%Ye0Skiuz$em<N*NvcjTcU52d+7OMjfb(08+InDqCQ;Akj*me@%V&_F@j0hbv42}hmD2F)i7Jd8SHy6A6qXxP(bf;6b^!D0GnRt1#!nrO;vbh+t9jK*^h;3IOB@_H%XAr)0W5$IKX54i{z$wSn60rx2DRbI$^lA04q;YSOhVzo@!iwg|@d2vP9NW!r8GJi<b!88_yr@ecl%OEbYNRdrwE*EJN)|8JGX*Ows;xU6xNfEWwQ1F~7vz|}@98iFXpooH!o1N(Zu+l@*gq-(4#~_s12iT&G#J6dZL#Mr|k>jV}ZcPDCj{>NG&X>_V$7q$Q-St{hGg+uV%pDs_Ts7K%{(gmZ$_HkyE9Mj!qC~PuYq&|+xD>U(tbub$;VD%*6>J{mb6E;DZerJ`AOmNogMqP?W;zH~7xfVaPU3LmQlM_e0e~wt2JuCn&%v<O2Iyr?zZ(D;grv)}+Tp0*J<ZtoiFVC?T?bGAO%Y+EVB)=>DFqxZh$?H47H~jTkTUfAcwysed#6AnHg&KHArVCbccG(jYUslVKsGlTQV;{+8retRrhvFxb7KI?r+W$n4|M+MoKT<`-!zdhP(Zyi4<E31Nr@+Ae-}!lg>}mVw~rP<u3G!EiSxDg9u0j;*yzpxWBasWVt~@3y8>Wq-8}$!>`{V3$t4BZ04W%I6Ce<u5}T-dV8DlUL&=l59`%vD8g!=&K4S0H3{^+`%k?VC*Z6P@T<$?Slf(i=!1FK#)Zq@VU|9QFV8{`M>-=u5=YSSf>G6m!Ij=bVQGb1|*m$+Sz<QZhz(oVs8SlKlL2EUJt?DDNwZ~)f0h7q+59$~!G5bAQ(>2953rfP*^gA~Bl-}C3u(n1WL!?=w@~ZohnGc^7pjMa^@*d8v^M!@QU%b{o6CifgT352@9k~~;Rwn+XYy49IwI5q!9{xKT=Ut&v`b+P*p9=QA>Yh`<bN0nP;)=o8Uu(l|Oz~M{ZcylizxA+Y6eAcIHt0_Pi~_rUgL3GNp;N9BujpsXjf>)Ohy1q#kd#s9p>1cfMgi8SRulmv9g4ky$i+n+pfYz%i=84?dq{0<(EnH-=hl}3bh0Uce^{jipqueAg(0C#9;ymM-faDnGP4U6y6W?GG$x12Cgrb!tgc&(S5ON(EEBb>W6C&2=ccTT^Gy2=)xR(=5{n_B@@GO-6)JM~(f-{lE6f3qgf)Fm!O32|Vx9T(TH5lq$)9)fd|kb#L-ITJ%e+5%%JR=o-dD5t$@_X1Byi2%nwRfw#pix(e=FAfr|$6;z=g=Hi}xKAfqzg+xL`fKf{K*gc$_85F%L=+ybzOo!m~4x#ISaeP1@f}>c`ke0I$453eaB0=Y~E%w*M!;Q}TP`H~zho`3yamgBoGdq)EYWx9tz#Yd?C{NA~BQ_46^$6??8-yyxY0O8vq{oX_I>0K|X!`;^bQ%-nvG0F@O<hbl>Dln!G_z{TT?&RKjQdJ4l7#J&39J<94(tRi@OOf8Z@x`%>VWcaNgCdy?~iAgzWS|>vh0(`g@Ae+Kq!lfX`pI$RAfRF}JG8l7L0sOkO)_zQxrMk8zpYhY+(Ht;~=J@xdnJfllp+W<~0W^cr@Yko5Q(=%80KWxlw*VRVv_=3RP>unRgR6u6-PK(>XS6=C9gX^6PcN$NPLNYwVkbpaQH3~aQMY}r<(|&puD9{?F~y~JUi(RQerex;2PZ+KfZ++UamslY4HE#C&Z16vMMIGKkd4O+)HUm7hxQMk038F+u>F8+lFkY%RN5QV`T_8*23O|ap-TPiqX1S_Dd=-z!W8`dr2yC~?kA&sKjmO7s7>o8E4lu<*zl*sfZ0$+B`__)C~zKBN4=U!wlN?oD}1XlSu{xiY-6(ZW$1O#%e65eTsI^5Cd$KoC|01ZF@Zt_+2tg3k%RY*+6cfv?gOKS?`np>*o`d8$3Yg*SyT_r<=>+?Q1Y?o|G59Zf~2JCOnd=o_{ZY(FE|rtdmWeF1<lXC3l#r{XN;O;OIq5Kz@XYT8?5??y{rPj_8fubml0K71b`O4OLuuNdL6h{5PN-!17i^HteUw0=<eL3Kf?8W^tLUdX82H9!MY3qyo>qnM1NIxn+C{NtP<(vSzz@~?AH{ACNAo$V4qM&XK<jYn*n_{#0~+7W^nJZ`fLY+4<H|#)|r?Hsx$tLMsaZr5)~t+xKXDk(G49cMYLw6p@EBfm0zL6Q`jf*T+{tMuvLklfMS=tUq7{$dsQwW`>(V&KYmSZE$Pi4A?5hMfI;*TlHzOnrXL(Eh^`~Yxp;X0<9G1+{z0Y+m=D*%UQ7_TMPy$(h|fUq#JLvvAt;27_a4qVz`yw03hDr+(mh)T=o^6F5!o%-p2om)y2A^~saMoRmyhK;J0oc&A7*kqU#XlFN#ro0j1!fB)-$^{*Vy)ez4RZsM%09YR0@g}1E2OEGH{-9eL4$t?`HkE(z#IfMEY-y>qsTSLbdL=^PDr7iRwD#t4tzViDyYkd}T3`nXK~mBg4=~^JjS&Iva$YNzZWYaP)_U#;^7@!;1);N<ux!u(PSPz9aXa(;YOUXPMsxRboAVJwo6}#F74EzqNH|gV*Hy{coxFc+r6Ms6g6W8m^XeATbbFR9L*E?xujqugrxn``t4*HYH}g4l9Jumj?*KZ+B1@o=9Xos=diEyySC5E~N|X<)c%hIGAF4y6?DWM!u~AKdIJ`AfzNzo=??~uD}syILk7IP{~(v@u*YzO6j{^lQ$ms*-%c7S&jHqPvKat<y@}uiJyBtj_vb4&*RTzu`c9{FY`_F`?9ZXKlAgh9@0GbdCJ{;L`^fF_eh8mBz17R_2QN9(S8<_%H$NeZC*#J_e}STCJ)1OWnV!4dS6S28kIVt+V9GT9wY6A_bFPe(wqtcY1J4>b^Tm9ZmI68RenyoZ$JBU^0U@vrOJyxLs75H?!xDJao#6atHyiWS<+BsHF3?V;{N1#fntdvhUv-QBaY=5?+wC%%0Qm@S$$T|h#k21AP=!h0&)Cr)iXiq&nDT7OR46ps_0S-UWmhl;`K3%To%Jat(&o16w?%ObhJiK#o<vwj(FyE5ZFrw3kw)9%-hH@^8vV`<ULDgaPEXL)TQ0DMwE&DmFz<vEKBV|qgX5_c~N{`^C|U($L`@A_ubkq9qp~E=5LAob7d5XJp$3g9dt_dBU9WdH<#2suO$H7;5^a2%_5I7E|ubkhDzKu{0Me67sX2Jia&;<=2+#CRo|fy+^Sct@exJU;<|Q3PSx5jiXt*WBd=rklsdNfj)nQYG>@e{=h?JspTje0O^|6V!d9BUH7iK3L=8;4;Eu`^(aX6=Q5}664+{U^sLByO7-yjGt|<S;ijRA?-$dPg5@PVTI8=-tSDJTUki*G!;|kGJjv*3-@iuxUTd3DUiFwe=dY!N0b8*gLv+cYmnu?6dvFbC$mWk^8JZjbMXNWPzuac6vG>Dv?2eJ?EJ;la;yPF`ES;;<6h?XKR6w2tF_aC%8@4s#9bWUEp5<#|FtGG7rT|(6t^NU(50I4748Skmec0oAx8dY|_Pq<&9qxQRAyD?^+T!=Ot&|e){<Nc^_ug&<TF|q~+*Ei~h?>3nTq0?S_PFFK5qc*Z8m}5AIxu|es_UT=u=g(tr6LYB{oj<I_tEky{zM*$(t`Cs|klwH8{V-bv;S1E#S9`AyEIPf;pQ7hQ9_Xgw`rQL+lb&VlOb7|Ys1<h)hQEqU>t<7x*C|T$z&+2_5}s)a+;C*}r~6T78JYSp9CcO)kW`MaHW6$Jb*PCCa(nv!KKGjAo1N(onAq3z0}%EeK(2{8m)V)hHktTMvn0|o@FxNNK0WssA`lt~1}W#JzgMyALr4L{5aXKZjAJu`7y^C1)!P`Iwa?!?o&;uRurvAtTEFGSv;x$V{|*Z6EF1#gxMW+a#PA?CAb;HSliE%?ce-K`<cBub4HgIBVaAfkFjUjid%L~HS(S2O`3`tVdSz4N;Y1!y=j99zqxhUs?%Gak6Dyp%LBC19^M!o=A1iU^iD!qOT40X*wyn*hur}zoBDrs;*5*=0_wnJ!;&RmLCOmhXiWuZd^fviVxkuhk$nM&;NBS;P5$mo@__Z`Qe`qsN0xPS}3OPgm%<<<wbDmEuY0Z}ouX8E_zRKgr(sRE)a?Kqo@?7^2`N*c)KFr%swGYfoKn*^d6&&1gO;*?lt^2$m7S{jBbA7Je=FihlNsrr7>_WCoYe{QLcHG0AyrwmOnTuYM5|cb8cdXrUPt}Rma!*^v238YCytHmt|9KH<#9!auH{W*u@$!B9`cIiR0{>bTnWyhyXZ1kD!!@-hJ;eOx`;u$ZCf$u;B1S(f#cGc;V+9+Y>n6A+klTuQMLi3&ey~pvfVU}5Q1_N>HNDFd!pMDd(C4$sbB7cgt(JO-JfV~`A)j@zr+tpoPChH@e9K7PH_DeZ#69ZsE;TyOYs7r0>6T;7Okf^0T*|r4?YwSs&7}C5bA1?7&ZlQ&n73{8q+Yy2AA#0-{ixfA0cw%V)zJk0VdZhYpwW4qX3rtVr-%trt8_)~md3D2Ew@w?7*B&%XEL?BGi~zcOdHx(I2l?~`)OM1jUMcYmy+q6#Hv#4Nb!5_$5gv{as?SXb64QC)j5BjGbfx7qK{H<Q@%s-soaBb=(UWaEC~^8q&qNwPL(h?t(PeFPPVdMJP(_&pQTP``&P|Un1GP&f8C@ww}$u;F<Vu>^3ds)Z6r!;F~#h_Z#*aSzU1F{PAaLNlxJ#7erha8Qg3iB@Z8|tSmn>&PJdocNK{`1uZhg}lEn;6*n@k3d*OF<R{QER4*ICU|FK&3*IX0hdWD|*Y!}3}bO%X9K=6-m^c=#sa84ro7RlBlJm3DQ^n76}Tl0$bNJyO~!lwH64kXZmJn&VX(~{#Yk*8W~h5Rg!|80stC<f6eAEw-1<f+Q6*O8i8RnO@xsnWrnEi*!R;hzdzJe9VW^}mZX+;g~`lAp}hs@LLYsj3HEjNhp40UpBvl%M6K&ywaH@4%HK-2;)?JYgFJ($7SAmG<7#r~7;I=gWhZiUPbQ<YhUrz0yBUNY0WNJS9A%{P_uZvt^1YkVw1=_jkwY+HFhDTj>s5I^ZwLYx8rFi-`O<{a$00xVfV4vNtLTm}#$i31*)AQIksBI(qlZb*P}H&(R0HLw^c!xx`l_?|qP9X&kPdEB6-NS*VlxWH;!!RQSiq3&;QB?C13-K{|GL6nsRhq^@z~PPEgw?2Tf!HDf#;8gi~z1MiSmpM0nLD&sifGkQ0C5&TVUkXPfsYxF*dMdUi2h(+!Y6XG77{-4tKr1&SjyYCh9Zu;*1=8M4Ugy^?!A1k?%z>8!bmVNfU&Ej*8_12r0-39Gre?d%dtQPwEeR)9sWYWJ)crU-<H5=^PP^0hl##j#a+p@oIycG$;*~e=?jOl3p0H)(o5wYui)b(@m3jPPZnu^z#{2FQ*bKzsx^u4uZ->AmGS_v*(o}Y{)Quf4W&GhCwb45MdWkH4%KX!V3KPo_dIv&e<7)OZiac@#=2Yg*7CUYn1T|C3Wguj>JHZqdQ+^#6@WKrO^Wz@=u2-Ey4iK&|RGjYd$6T&W=f`|iux0$Zy)>3V-hMFAk)3{q)f#Z_yC!8;c2v5_x>Vf>nR;?+M-?>xpARLoGWUJ5<O6G*BFu~?`dQM&7smbP$lcaTk=L|c5T9!{|g=6(1L2in(%W*9R#fH;^VGSdb>wLhUO=*p8c4lXBF#BCaNK4LDi|fZ^|5?xbXm59o*?sI0J)=~20}mf+6{2Q86*CB2%PL^~Rw|E6QkQ}6r`VNzV%lq8Nj_jD^9HcLtMUivj|>0RFVw@z_h_iznc|+ZW7GsVe|37#WC!3_^auU4Z@ych=1%^%hI@?So%gw@&Arcc_pQkBkoe#e1e{;T^`L%Une6x)E{r_(3E#L+%Xxky^8r=$5ZT7W?;M?bytG!4)*6tz(3xhQF^VmgFZfP{bA#7`KN9_F%7gwm)>HEz?G~NUCF6<it(!O0yVd$ah`M?``?(b~)H&Kbzo&J5HEtVwL#>@K9tys5nQ<@5`I_*14`S{RF&E|^V)4D!6boqI$rr_*vwolV$8xO(d$58yjyD@5xgO{AsL{Njo}%)F^15lrmGBHoPKP=N<G{%F3Nt|NGh!1DccN6|X(WEre#UbYYcdPWwm5q&nJJ<*y@`u`U&c{f^PWj>QmI>rdBPpV619Tw%<qVLWp1Zp3%K5GXLnH599*FWob*1E_bl`~F?URN1m~w>wz@&FgYx^D`^-M2Chl0Wd-n5rJ|k+yb_21C=(S1lwi@eTcJ})`68V^jQ)&GqY~{%r9J;gT^`#)h6}bic*QTnsjaZp{`611D@VnoVS^;yez^@)Zk1z9C8i(6kC2p6+3s0O+tfOJAia)34Uu0*`jFq2DxdH5@w!8Ol8fx7)KX+*?lFr=$w~)lg-2{ieq5DFO&ACS+?M;MyA)weke5H73z1Xxjl&{M9RCurMAMdpRLB(5Tz5xB)!!j!EJ)TF(msD&E<^<<=b~4jXzDS+d%y<IjeH6Av=MlC?_E@~vlH63O)yuu}%kM$+$*zUdhhA%Fg_GViY(Grwi6Dp$TOF&`wCvun{V;7#3+GMXIP?2n##*NRswzBD`g+SKVL1>RBF;;&v;K{y{=Us|JjD^<EqW@~%!I$<-0|@1&g0qIeeyc;MP!Gx7k88Q0rv5ZYdE+U=#CDb9}#Coi!1KQn=|+1;@myC8$DcqPfn7!(4{zxzBBzSOmdoKi02bAftusH`2KZ!$9M-mGvZ9r`GW5XP`CKPGf8o}tNc9eVO{Z_X^l=5hCn|Q=Y(yc_<H1#%csgd)n}iz!`ZV|Gar8aeOMW<CVb<FiQTk*Uzr#6o;~hEP^{pHJTlF7@0}*Z<sqn6=u6Qva|{l=Byz&Z6Xo*$v3Vb}Gc9vmCH&=CJ{T=`%iEfE@0a2wuD=unc0^6U$@Av>q%KZpws~JapIhFif*f}S*Jf$`<Fpnm%}~A`u|M#lr*`5NayE(2mSemZ&KGscJMubFv5s_n{v!fLsuu{ZM>8081_uaNlC{SkL<Rh@c7~I*w7+C~;UW{&UgE#^OVpFq?@BSPxl3}~3oue+t%6%a)Z%;DT0H|dW<E5u(%p=`=(QA4Vo}@Cq#jf%(pMv&+lucU$}Row!SlUvWC5?#4zb5%dv%D|jvi7G4i+Aje5qOF`d7sq3g;+|kDX4Dqc7*tm1C(=ub|MUSm>`$qDGhXoYM6P?wxMK^aG07jJ?qTo(ehiqV8GUrswz8?ipT54_KQXVp=V+!L<IQNjV1JCj|k`Fh<`3{h70M!_N1bX%*^*5_UITFR$Jv`<T9&C7*w^Px8ut_nD*rJ*lCQFA3fk2QBif!QO}<z8*jzaOXj=y92@6LCv*-_taPLtYnf4B_fbqNAb|_xw~|)jbnR#>b<Wz*DRFcbYl}d#6D)|!G{8#)`4zB-QBh4I``ZAcTW%fe`lXvo$u_|6r07R8O-ObcYMg6JzUiaugUnDPrdh5XW8m)M*V>{!W_3lS%W`Z8xe$Zx^#ZV4Y!(KGxy8S$7@Z=Ij?=2wKJ^%^rHojS~KB*up2X7*h#VOIFGo8t@3<*;rUd0TRmxR^Z4GK=tH9i=<bhV`%l*Jl0TubFXkHsy!R@J36F3HRodA8n2jBeIn)^NRFA>C)yRJ&oC!L72-%ml(3s;~Hx3Hc^^_>kIUiG>G#B~V2*^H|pM?BgGH<$mLQfXCjdG{3P12uay^HJhx4rX^^%IiUP5kb${4zVcn2kk@UpZT$*4b9&yq@hbK5Nf^zt}`xi^~4N>6*ckZEATJ?lL_NvNMSHaUD3}dHhE4iC4xHN3c!ciApm|UzJBBHC8cC-FxDD#91C5XOrf?nO}>K`n3~laNXV6)hX{;8?ntfkHP1hd}WN@5c#>=|Jk<o!T9IDqpkfN;<SrxO|8X<TIC$`eOe23SKLF{oS-z5`aX|52oRPrP$8`r#R-GEW#~Gul&b?z-+LSMjD0niN2y<oenl>B_*}wfJS0MuN$)MkJV~|Ar1m(WyQKM?^y$_md{1A(F_fR}R2>~P^S;#$J9f`}nsh^JT-*OSt=ZiIK1jLG(GQ{AwsDky-kJPs=}gqxTe$3vr>{LLGz$1@o@FCHWik#7cXw`s#-YGro$Z$#8>RRwG1HXcot1is>om2Tn<vb85%cF0y-#2Y+*!ION3qzeBfYGcevbJ7vYjDj3AO@%mEp(UiaI@F&%>uu4YV-l;0ZiS?VF_Aw}`keb-FImf6=_Y+H;s{_Lzl8dspp6e92zOHT79Nuc-sqwzw0*tZMB-!c#JSF`dWBYS<QX7Vm-2UoF9Wte1Ba+-;0wqWypI^fmf`E9LAT6l@>n-GJS|Oj6dXx-V%-BpQwNGd)`1ZfC=!F3hvrZ>Ucn@kiiresZH81bdUXn!cOBYA0tbubaztjS4;)o*%C0x6}UZHP&egTfmDx<8v2^Q0btS_and?WNw!;GwoSs^RM!I(t4rKgIqD`X-uV_#t{5S<mYVQ+(X9x=kKE{uS;f+5}$ku>wOyk@|@Td@MKEwqWR9VJF}kl$l4uZE>)Uy{pf6{#O1^_Slx}yHRah5ime&or|See7Fv$oc+^=m3}@oAsCG=Ri9Kip?dYD{8@{U>;1}%BAKi$}ctQU*Xc+NS;yWBl7(G>Bci;!~{%zmrdmB^t)(~>0d-H(!%+v>TXSPFdHhcJayxMX62ElF%dPFw(P<NhX=x*de*j#sYm-4t(l?JRjzkLhgZLU={z@u&GlgP#U_z;*LG{KE$SZ!!+t`R%A@iaC&(6oc5pto`Tkk*Fo^cdW$W;C+QwdYUkGG4Ay5A7>>0)O2+s5Y1TQBsfMSnWy1xzOEuz`c>pfb?42yDiR}6nu7dU+ft%&h}cr+?^lV<nzWW5&PAEC3^7~3kl3Lo}u;T9n@H*;BU+KeI@^Z{f0WtT;B^Uq%>btG4oU%CqCEy>ykOT*T;GIZ7crL{<-|NUHr9qdELB!+y1Y`_Wd9K_aAmHxVs(etw0P^whr`#QBVr+yBaNKV|9OM?>vyAU^s*9;5O(5XizP5CW>0o7tzv90NH~#Tk|kLI#6@pr9+qjBE`@6g450KbG^0Y&rLtGGk!Dtn=Ln-Z)*Q_ghXOH2#{<s=$#9Z_<VAbTe?VAe?GMTHP;8LdB24r$}PYjquU)B_RX#{e(5~+!!0>g0F&{(0S<dxI&{Gt+D*?PV?6Bk=0js|<iBGrXV{EjW$QiNd)RjvWPkyF6d!Nfbr)cfJ{PMHppcU_w#KHRN$)X`!E5xL(M+K=W<mxsO8b2|!w_i;LwvL@`vC8UK!z?9&G3y~{$5q;+tK6m=IPtED6Q=S!hD)eaZr>HIyo{2*<^%|fOB&zK%{{Z1RBy3C^<^<%+gpLT?g;%A}G{dL}qf#Sq7>m)78!5u9ONwev4&QX}3km^C<jUhM(s&9{f!5Sj?jyZUvp}5Tmj02zBqB9)&l5ybAiN-T{za87@o~g|H_LZ4Ikt-rrlio|Iw_n)fJIr{S(R+T04OhP7WJ=T@ZLsR%p8GZi68J4&?+G?Ll#DCN?0?10|~v~iR+jceOiZrS-aHM$O%Do~+?lwsf82Il9gpm8lo5z-ZA^o^Yt4eDM5+03ry(fZM~Bjg?W(>mm0@$(U=%>4oF4P8kNX#YVQ(GEd@>_yX>3xaQdvKieTp}MK2Ks`B{@l)ha#k!Z^DT{tsgr=~Ka(P5)n<Q-wC)vN-))BjF$+SaBE8qm(SqXmq(`k$=;nx?9z<jP`s_;)m_-wuXQiRT?XQEJsOV>8pukpLpZFL?FHHI_*Ha!xf8t>V6OQeCAf>eCRDhfSWdKPP}jjW(Hq8rBRv;$B&dmT{QyUh{c8z}4bUC2t(>kzJa{;2N-v~Qq9Uy~hCnuYKU@c0Gb^M#ULMs;?LgzV3hSpE8axtvZ>*_)qEKYn^|PSH;P3|ZDM+m{c}PRjf8lT*7R`*PVx-seiWe%+mNZan*hBs`^*WDBMr>><-Y`?Pm0@<-7WrG*{jvT;waG(4RlIve`Pp?$!8Vv!%yz0l|cO|Ju~g@JD34my9=Up7vDouoYOkW1(kzwDe`IMP@}dn=!p-H7%G6jx>(&>hmFH6KPJioZtAv@xQ)#q3ku<*%A%G=ww_?VABAEb?dFJ>?A=_QuqEbk|Z$5Ql+lxy|!_EPcKfj}YEF#aNPIB55r7fpeqEBFqvB{a+oEos(@i8ka>z44O1hmI0pNMRcY*<fAMDvL6A*S=O{Z>JLK~@J?&dpr6(0Tv2>Hj*U3nKvJ5{82L83qb%BAt9wOUc9{f$O7RQH$1vhNu`b)(5L9yEs6VI~k+~)xy`ksYn^yPW(S7P#YdZV1I`rgjJlJ`T+jRW_`Ez?iUOGY+JVM;rA5$DOjSYWIIYlo@^VVvbi|(OB@0fnyN*SB~k!8!Oao+SS3J7Os6&sehG5kf-w2%ud$*xwkZ?vDCb!2oV^c~5MTa=$64vJUw3}c=AJ^2c{7ciC?Bfppgv<^-B9{T7(p}(o7+`J{*p}dgJ(HgQ?6w4k!Daa5di@uX@G!4KX`^YD!4cseq=V%_}gks1A(Vq1wYW5*LgYi*%CchoYCEF$7_KrsOZ^CZV))al$VQA3jx{*<%{D;oaU<WEb`VNujkWZ%g+|}uBf*ej~S~F<9A;&{GEZHwTS>HgMPI3E<MsazQ;`RN>&$U~xNo|4bI;a~MV|B=%ID<N*AU)2l26Ug&ooU^~W=v-&UX#zJv(~4(mF(8**c;D+tjl!o^<BC@0fTUN<R@xsD->e}%h0e-jp?2#K{8X<<MU&9*lxD}eEI8J^!=~bZ&9HJwPp#dJEqa!qOF*YwHzO{-oMP9uvUbtS)FbXF8ub0YForKnmj(j&lxCG1FQLrY>QheqD}3dprT-!j($oTlF4^bY)83)pfimYQSX&$htyifA*04ha!~7;X;1Uk-OK>39ha1uB7l50R}ID3y%;&8Ty}7$QfY|xeFEKpe8A>(OO>AOeX*&8h9<EGuh$Dx0|+{d_xYVymWijk)TKB!iFveBw9BqCLbs;19A}h$quZRa$#ufRpfBI~%6H*0q(`a6o5w{8o!!=D8uqqjJnUA}c(CQlb<ZfmiZpqgb&}It9f9=7-(m8;)SIFX`q1`WvLRHVVPoW@Q9Vv<#iM6g6xy|Cz7s~fK$%KwqSPtSnunbgMn>rShgoYO7$45mL*&*5C^}c5<6dCTb<zF@o#p~GbmZTccfrby?1=6-vOUycJ*Lzux5y_i()+4y&_f$7SWu|~B9O{F0eS%264mUJ`(j)#Gpx6m#>mtEP+H4gKd0*9_pbdRQ~X!a5H+f(m_Ttw_b_bYuQZmx>*hGqH?nL>2nbP5QPk-s|9+GnEUkSU@qJ9gr=@h~@Kwm8XdR#Uvu{iEUMx@WjeHxR9^C59Y^4AnPM!&|EJh4dD!mjckWil$AvvhGgQ@~loNuU$5AFmFs-QCDvF9j*?exX?BF4=UyVwFk!?FSDC@Ekjuk?Ozup^JYn+#{5&y75cwcUZ1sHO49zi5%sxmz;)VVO{xsvV~WYT0#`E~d{+T6!h83cViE<YfPovfrzq<jkqiN<KBCXA|_Lt;pLH;>lb_Ce2SvZQAQ<ALpfMu92Ts$9S%i!&Sz;en<-D!%}g>tLxrZ*Z;1m@yL{(S+{fYl+!j8U;)=jPi@G?FoG^%CnX4F?w2`UK&@G!fmNYoIgM^g^K!v!CI8M)uL_F39G)gRzo#U+u8?s*CS`Y+k-wsND&RO;$Q(UfAc=ORwD47O3F(?BG>&8gugE1mM|+~!^O@GONY_L$QR^x1Kd$-tK-H7dc8HM~`^l6fQRscn%A$cri2Taiz0PrOO`!~&G0Xxm>q=?3{CCqn218Bas@KYUEB*JYplB|Q!(Kv9cHRaYSqkMdWa<W|Wa^}StbLfqOj#R=KL3N#d`HHNPkc_9inih$zrM`-y9Accaol>b(ULuQ2@C!7U4e@Kh2z?&5*l|2^;up0j+OLh7f1n}q+H$Nem$1cD6zTLIwhZ-Qb%z<4;os}@euR92r8J08sx2-2P|&2lq#qi+8%in$Lu+FU|Y078D#oExv=Dufd1~t2Y|{ed7gIqJfIl@tPr^<o`qt})d~<<z<nWwlRpb+b19di-&xKW-BM#HaI|=<9J%guF1gKM@gk;tNbj;D^jLi6l5*wt_axqIFYb68jO?*ppx|m(^$7v%{VRuB4T@CyA;yzXqr}Jv-M66pOx7op`l!?W2`c160>hQ)C1eWk24Yr<Wx3v2qH{xBEbh-#7VI>J;0k*x=2wRV(p_ms$LT-RwaBUAf5659_%@cld1E;3tpZ^dF*;&(x<~1`bJ{H0+azX9X}Eljmvy@crBlu;>J>8N+j6jPEl5XXYjp1<G62Xg^c31BY7SGWexOo`LSCYW{Brkrd(ysY7u#3Bv?DBAk<$WA5xX+I9?L}>->U+(X*0e*-TzRi`f_^8im{sK%8`uXSWWTl$&^tAIb)eNM@wmQc#oyu`2icFy9sqJC(i+yHqy~{$q35I>;I8Z67rp<GpwF`-TlnN7=n<MaGJ9H#gC|c)r}AOvE=Mk<;a)YlJ*f>n#SGjpl2NJlRDZoMhz!?rgfm4S%Xh`!Jd(i+9uCerqa!8oNuS=N93C*)<Zvl;rR*Gchwkbb#3m5^!3B3*U0t2HcKtuJBjpOfB)_se#Dj(8Ag#$M<Hq%b^2~Vg1%xb3e?c3TVOrq+HsLyo9&H!KYU$+;uMq^5ABqadnJvyUt?=2^?gIFk4klG)Ej$AEsEk)dKQh*qt2A<q4y?y{83rJqAfPBvPIg*MO5QE5Pqa20V(XRlEO5XHeh)$9y!WoecBs}mEPIT^LlZ%uIwi_Cut6zr1dV)Jx`Ep0rrh`_ql&7jf8;SNXQWhiYbce$rg61Bq*)9+8<2oM_HWv<+QgWNLqDnv=Q)KeMqaf*QRd79{Qr49D05U?QNca%jf%OuDxg6Ez{<qP9*2ZAI;B?{$8Ao006EJDov?=G_8~(Q|k$4PxORlN#4pi{YsSs%*I;9n3NieDdVWhh<zsAS4Hy*I`_goys_opl_LK%oJurd^t!S9I!%6^DP-ZwG#???>wtI3?5ny*BSw~Ky<gK@)^qGbh8Y3%`>dzACAyF6s9%iu<}0aR>KJ`KcP7-)XQrM|Xyh-U^qCg=j}i{Jf@by_8jf1cjez4YfOm>bXVCO4;5;T2{|sW+nqD-DesW*&ot>75Q7B$4)^4w(>N0j;N!4YNU%0md-Sfvg(+bz7H3>|8x^qEarcZ(qB=$BEZHKOfwBCpdUImp+8UrlF=*~s-J~xMBW8-tjUL!9Q_Zh9b+F!elnynMAf#)@1qhb2%wc+$a!(Y`6pZ+Bp2A@F91}W|rjCB40T~}P9`TwbOU5od{q1H4bw`O#vO|t)**I9-}zgu@>Gw?b=&4>pw9Z+g}>WJ25`y3zNXYu_`^mfmk>$=eg4yPBHaeD(S_Xt>SI*W!s@kjmckDqHgL!MKL_5RJyb0sAzQ>0%=u{bu5$|#?D@2jYke9vD-hBH1G)_Cvwz$mT#krgxyobim>`6%6HeD2=<Al1lMoWF|u@A$rWJcfCsR>Am9%567Q@2RnD0qxgwR_8C&!mj95<UPy6eQ`fy8Qo$`AoV!&KG8ksAriU2N{sr|J&{tc2~uUJaqvfDU=8;UYzNZ96}{6N1&@oK^Tk+VRa%AedsUJJ<LXQ!_<`SDfM%=;2YeCT%T19o?Pa0AR@GP^O7ichB_E})`MOx|S5mHhMf`mxemY63mh?KS_A`~EtcvennZ_PdyY(aIAon}z>{CL&cFfN(P6GH9t~JqjLhY3E%~ITvzh08u)fCCya<8-C2h`r*G5>UBKlNx|`&E{+KH@ubNhZ2G&*1nk_c_NUGB5I1MJcFrG<$N4P@u-=dRZm?o^KS_;=#N<>Z5*5-k|uvW3rBCX@EaQ5BfDZo~S1%6pg=q$8X>9i+so7Qr|Hx`;HQI=b(N;98#I{UPoKE*txzPx{ixHwdv~JhS8s_z5euI_KmA(>wW@7;+NztmGWr7-OqmelHb1M*Z30i_EKL`l9zfIJ)Dn2K8^Mg^JTib_d0{U+39V-7cuG^&5^a*Q6A9rZa+$U86x&c`^Dj6b5wdn-~$9LUurWIHH8mgH%q-{<+IAYqO?bJ6!##_eWo)eLH=9<SKCNum4H159)F8k2G3Fmti8ay3n}_nV9Y$G{LF9{Z{BSYyV-h$d{;gjOTHyc`(on#h0jp-swmsuK|j_NbaaVdQs!}L^FurJd#ePqy|S!sL9P<BU*WTi=NUVbAZ3P{Q=a=cL!WyO?4Y1I?WZ^Z$j!HaBamwah4*jO=aGGo=QRfYqTs{Xwo)5@C`qrJn)^_t>q5o`py!_QTtMbd?WxPN;IF_)VZOnWYJt`Frr6ix{n-!pJuBh~<+F~{@*b^=6y!-$N$L#OSoSpyF$0I$H>RZBrnZfK!~y;P1ZT(iIz<M%WY1+RvuY2jEbbssIRUC9uyb5PK^D>hW@}l%1_@losd=t^wo0xuhoF<I##MgAhBu#P!>|{DH9T&|Z**VebA;#e$jD3QRI=WFh2Q)r2H*>QbxLuV&aSp&%%pe^0;@vLwRWR$D=;`3#pA$00td)A<M6a!R_o8FZMg8-<ldlt1En}{O*;F}KITE&>72-UKg`cbXHm$zgPjj^tgA%?j3%AQJK&%&|B=_efpb>r6bomjj(+R#DT&VoFUa8}CaKhmBR?O`bj%RHO7GKtTRQvgX&PJ9IEO`?<EBWpI*$a$1An*Eb=4n?HO|bM{Fr~<U*n&xwC*HqMa$=sJ;sP)1{4(C660dQekSi?R!W@(P3Cq~J6Et-Hyep{a>aFRAr*=kf@ku0F07wp_C&4vy!}p}?YI2*mdWg*f@O>ojGBU1PAQj5GQii{ZtdUKc7IBoye-8TCF+0USl%Rak)-!=uQX@hPihUfZN`<#44f4)^hsIhg1=6%Ode(#Ugqp;PsYy=Dqc8QmmaA3*(NQ6XJsirJ|A~vvA9IFzXf%^!gq9g25+v+_5QH!Yrk#(3fsRzs;4r(R;l6hIT9)ENc+Ve=WHizS&>9APWtX?mSeQ#zOumbf~l9~btT-dj@*sx^KjOt2f%zY_XVGcgv$ZE7t&qep@#7wa^Pz0`48K%{@ad!R{YEo0rI|)?+I4yv+3X2X3y{g6y}5i@`K<$6zh%LrpIyt%ttU6u?2AU*<AJMxH{)LVO%}9P9RYdO%UVrexLN2Wt+B<%U;Yi)6W>KX?;vz#4pH2mm2Emh3^h-k}%`25Ijls3fx1ET`lF17f3mr=9f9jmEiL8w>f5=V@58mt#5v6t_aKmX49V%++KVi4vxhS%4eODS-T?s=%gGmOP+h@`1+Nl#`}URoBUcLn=P@Wr+B3kww=^wpEBw0)3v%`8K2UYa8vCUX)bS_#NWlUmDQ?pSs6P{cyRD<U`uD3etO1Nm9^ab?&7>MM^E#4>GYnxANR|Re_y}c!;Isa>`-9K!okU2%2m7vr??h0_LHy+4V>1?EHAU;E1uz}oVg#7Hmr)5CQ@%Ejggo~<F@_cZSwfx(SgtJp~jrgmYz75MNUwcd2UJ=;o|v}=DhfRdG{iB#TZ`^KP9tL<HEe!r7=`Gi=0cyNL(PC6Qmp_`1g#9q;Jw^_R@K)AG~XVPrGX*d8niJ%{(Gsnn`Ias(VVOIUjTTmU-lSGcdu`>=*~v@}iM5i46ayZpJ~)uxRhC#ctFI4n{PH>9*EK7Wf&*JJ+$-rqzwjPEcc(=V)B>`qQTCPkb+u&Q?YJ8vL;-7e_W<<FGW#!L-`+`3r5->DEjgQZ9yOvZVX8X3|-7V{j{);QglGAFfUMWBA}~ziFEE{GR0=T;?a0_;3ofM{%B$dnd9tCU60<vGaWJy>{s{r;zI0nCS8K4Z7zBkde_w^o*v{-FyC`F|t;%XAOODCK{HZx%zO!IHi71_VYQuKC5ftuCsk38g5L-4o%uG&tI;M_-0SvvFSPBon87KeIIZyjx73)RxhCE&_;ci{>|N+@iGKws2STnJsUksJCNtLkgF7UE~CfU8b0_r(Og(V62}F<V`N5j4#`{FksEb2HyV>I(0A}xu|ex>>Vu{ck86fMZ7`ds?#A@l2QTW0847=@89HzXQhyv+1G`n^7*)77z0QKUDveH1A32ad?t;HD9+7RCdRH5<T+g^}L>~D&Bc^p-d-Qpu4y}2gxgW_smw`w2;`-s*v({^=7hAOk%IA-)F}+uho@2ckVRoV4Z5V!+zTKMEdr$+PEIrSG)`V<2j12UC!8z;G=k|L6WTjjyq_eXQ&CWQc&sm%D=co6Oz_+D&q=*ChV_HM9>yEKAEbzX9Pt)GOu1!BAo1%Z~jL8<U;&cu=z`hM&i(uTOwZMMd>|7sbge4jG%4Z9Cx&p`Oa5L(ICv(s+tVP4KR!!P}Ix_~@I<2*D(3zq9Af`3JcaFP<5x6)zleOpAzH4ExrsN}5<Qs<m$fD0DTajk>^1cOTlqI}{usOF*XP3U8N$*d-#wWY>Aya%)Goyh<XP5pzIB&_WB5=;r83CthME(eTs~tM~)`Dz5ptU1^72jy-Y)LxviTIB^0C*?1Tmzyzc<E@b=`$SRKY>q(b56u-`)%bp{t8SC_uVK@`i@!!^SeFUJlDUN*)PZ!1s4guwvPWsY?g789FH;kHexDi4l2QEoy0VSJ*&I_(>|QzUC?+|I*l)+*h#7JpIx8uR4;|&bf_c!CAbv-5K@lW{P(z6KNlRE`CPUf-w7_0<lGhR_buJ~LB?sW3%;)M{F{m)ooK_}WO|nGM75t>8W1@-;u=4d6g^#c5}b1)jzOGerad_3N06}t6q}_oq&ZJn`ulwmFGFpL<L@LMO6GM7d$mVA_mt1)43Zhp!6|(H-88U!*5*3<QSL$g=v+Z5j?8%*MLk;7%QDQ!c5t_RS@u^&Dao`asKlDEFPGvpjt`%K{}sK=3vDGnWh>6qHmq)Ic8+%fIFv;4^nWKY-kaBFNjS<?hfviz-CHW`dx}G0?!a5Qzr=EpNo_R6PlD@#&oSO_CAb{-qV5P>$DQC#Eavc~xcr#kIVEi#EFUIQdvxXcT-A583LLQXT|)29DB~4GP3joGOU&nahWZ@$mox5$3Y^DhoF{Jr`fzP=rJuQ?rcIfo;MFi#-gaKc&!-Z%Q@Lk&<UC#YeT`4|9}B^E`jqyvD2I6Y7EMooZ~mQukpHEamu!Q3vV8Z7yiDQ>vX$O~yw?&ot-v|+3FqR2_c6G==zZRSDJI)xUUk%*AMI9()p#jkX-lz7^L^0W{(pa36tmogyLo-`-Q)TPc!;$ZaKNZ|q4vw1rM2OMDek$OfCuH5*#!9t=GP)0@k+6N{@u=DOLWvE!g#LK?~*#^9dJNFiqFG$<{BW`Mw&wgLN1ffMN(@Jwng_Yb4`PD<y*g^o^ixJ%-f$3uL=Iwr?d`|=DcU`7O7s7-JPOl!#$0o95{k+=n|frAHHip7MGz`l+}V#oNs_NNHG>C@0REf(F4rBZ;~7ICwTU?6wjjnLH8{bLv2>LO!)V><}w%dlh#HrJUiV_KRdF26B;t8?U~<C$MXC=6nXZ{XQmw94{f?jdw&Uj#k3!$+$Ahei+!ipL|mVvSPYWf9{mjQDsX4ZSzG89US=<~t75aCC0EN@5ij4jumAkE|F(F0-F$!kr})>RWGRnd*jag+uai=_uD^e0+MZ-oe^$rW8kT5pIkluPX|9_uJa&<~EM+U<vJvV5rUxjqvaB#$i4qd>4*O=3t}#5Fp{jfZR!~4w=;$JBr{i+&S>YO&g=?EaSF~0Nt;?kbxFM^n&oT)8Ql`02QfE*pgHC=sud{nDeI|vzF>RZkNmtxvFmCl&>Gt{&CRKpU%5;M1bI4@}l;S~8NLNOc$poN0ltS9^G-!1w6z<Nn$)7WAXj|cAXie>>X{|SUuqWOn619N#C^B5C-6&?9z<?@bWa$d;fue1pjzCvQZXF*L*+?l?{+wf3hDD_Frl#6E*~*$yo@S<st<Z}NGu8Q-zHU<Z2P#tv%gv`pr%e6)kjq}=HWDSaSWww!dUCj0$eboLycP7l$66XV7kKU$hV*C8-cEmBPu$*XNfu#~ON79+CA6N9jrpFHMp7kkhEgZxkh`41OTelOru+wFM5fYAu4ds|9@+)pBH8+J*@kS*tK=e1Pz=lR0ty{?DjOiT9&;*i`#@L2VWG7`K+?EOsY(<ap+64FwtRH_H+z<YJ6mQ{kHSAGWr!oTm(k)EX|6Am;gkGiwpJ7Z;#pFP{-P~kBo|v4VY*1tRDPC|K1=x5v~8B0A8`*vX7hw?RE;qr?S_=h{vIvqgO*ZAz7}aG)loh!jXWo3PyDylV>uK>?OrN-7s8^B)wSE!M*cZ{AE&p?_S8mco}oV(1c1Mn;=3y4RQ5(uP9v3>?p2Ii7HsS2-7mL^gH)ag6p9okNiZ2@?}G$}<Z!D~9rbWDgm;-#OxZt9aDV#A*;h*C6xw8Tx?DOqdM9S>WQkr{@-^(!C`F~zat7$Bc+Yf%22j?6O2f+`G`Bt<`7=xri`;Q(i|*0s|EU^jN$>7^dB1Un`^^_2s}VjWu>T6*p-NE|pL2Wy-n7uy@5@64744=-pIf9pZoH{dWr>f6FN~JtV~aGOc5N<TUX+HCf8w#?Chm*W-c#F@C{Krig6K3||Habb$K*vW@==$`i(D(4Q1WYHjPvz8-JA7&SE74k$a6w5m-wui-h7|w3SI7p<q#I2?7c0~04XE1m68ajB~U@FRF*Y}xYV%a)GnjVHlIXW6tUs9;v4`9wBIIe3_3fltvef}ep<GxOQa2&_X6e+eXEu=;P0lCZB&_%8cVm`L6){n&$}wzPdH!ROGY~)<mI-q^dQ~!Z=To>ITfywf&6lMTQ8a(3~Lyf(X?q;lMN&-4al8$76-H6ZC*ofo69O48zH86^-k;&J)<Pc6yh$eC2PBxMod|75TmN941g*%4_GVH?!`%IqmmN208@Ia^apk};@2;<Evsn@q&riB?5#O}m8jx#xu0D^p$;j?W<c@I`y9_ncgS3K-zupSwNrAD74o%^pmog9>j0kNt&OOAFr4n*w7k%WSCFM&3t7(L#_KGjQD@aO{V;MP$ktDF{2SmNBgltB4%463O#kMre61v>RiL$R?f?-|OGatz6TS&3N(vnlKHwy6U*%Yq3TwTvR*}{kkh{>CM%fHG4Y%-$=cd>iJ_fn-AMMt6wEOW{_twoDWTe&lLI~(fJ^Q&8G}KaGp5N2Dz8bfUy`k1ls^}A?d`<Yh2dSh+F;OhO*P3DhO&QCPYBgd!i>b>7Nv_8^J(t=mAg(9JcM@s7gOSsJGqf#}2k5nA*^k6;+B{-btjR1ehAO05KqpRXdJ`)@Pg?@lyk{m4R*(-*>E(}5kqBEV<#q~G&UN@bvOB0s&aE)+i+C)D^TpjFRF-U6<fpJ3vI&YEl;77}mX~dc@+s_|{k#Ml5m2jSq&BHjrSW!wPLH1D`#ci)n21v+37l6wpVg!E`|Z5Wl#^+00spnBf}V0KtdCkv0?(n}{g%`Uc$9|6ZI7PEm-#G>!+CTekK40x|I_Ca>u6Z3;?L>%7une}W98?v+y>c8ZFleADCf7D>O(+OFangs$K3?ZzJW}GD*xEyG0JRjBIFAg?Lm7Ka!~Efl3^EFK2;o5;Jr2=jee_)xhHM((%$okd7dvR@3q6&?EKCSll9sg3dKp<`UgFIzK;o{JC~L$Qk99^R2^Z+<Xi0E@_W#HvTNb=q1PH(;iNYW+Yb|a(zd(dpH|rFShc2Q_lE6<X>(dQZz(J$z3*k&#N_-I;pz-yOJ84rNTViz*bs5vK*Warji&y-GHUZwu9+pRGUSejUw0nQ*6x$nrEL_7x!zUyLOX>oNYLO*?#Y`o_vGT-J-Hh_Tz^kalDLqm1CB}ssX4xj@1Kr_2nj1blaNA!^f1#pechP^yjb~p+S<F~J<}T9lRB2ck~mwBZK0A{_^FaE^|Q~~;p|zfnGe7IK0HD*{UrKKHr;PY{l1!7sYETG=DPPzQ=2>Z?*iT2l`;`#XZn>g5lzt4p35y|n%aesDvQ%va6Y<t5#_jBq83Ui#|53r3+Ib^4-}SZo#;9W(5M%f@r`cq2*BXrTHQKXd+dQS(;sV}ARVw@qMm&FBh>O^?JKF}M-Q#|-T`#Fd+>ZO99i9(>$gMfG1*?-@F#0}O->`K(1#`z9jK!L-cS!Nk_B-J5H^XTQHiBWy@IQ#*18ST4=83c_6FrKrjHzYQTMDa#xd6JWpu7|=C#BI)B2Mp<ro!kx$9&iYNqv-G7-W1;-E#IHP{=Gt9w?kH~WK~XJN0&2gewl2xPj)EEi%LL|gPDygH8uUbxrBvAsU^-dCM#!}226>BgorZWunDDe_Sx$Mj7fBPre8wdXqb+xvG<5B+~<pM8qj@G?1&RqdD@$fwaJTD{Gv&!Z^^)1j=vAFhqaUh_DMH3seKDY>%{Fz92orXQkhjy%w_qK7SNQ(EoI&!^Jc>PeF5$M^0;9~wPCcYmBp_f!q<ra}TN9Z?;WM^q2jNEEF0$879)%yE?z3HcAY>pJei(BVVKzO02taYAV7#(~c8FO?YZ*e2;uvfjn@`rF?5$NCA$>n48pEY0iB9DV*9$0om$MjEtu0q{g(&0m*ao<}4#Rxzg0d*XY<Su*Y7znNb<Dy4O54X(R8F{asD8?ntfkHP1hd}WN@5c#>=|Jk<o!T9IDqpkfN;<OLaTT75{t%bTP?jb?vsr30-c6a;8^mK*$0(5y8HDL<fSIX5fdeVCv^l~c5d<`r6#pqXTv;Nt037e78+a}|bRTAP!?Gcdv=5x}gTbJ-XeF?`<ezsF}bkxlIRyXX}J@aYO4Xtr)|L3%3cMJF+<vvG0gmT-)aXGcgzn0EKt-XcI-gx@jvqGbQzeXRR2Ra(Yf#L4XZLmODDD9UV8>RTGSv~C!m1=s**nsFmOC!YmS)%s|Oo2N~_v9!Rdv&Cj6*J{9eIJa%E^kpwW%=?HKUV1Zr+Xegm1>{`I*t>x9jEIO{TB_fr$Xha+2d)q^<ej|+Kc#-y^w3_vwB`r2d-^#$M#;RT}XIJ#xKev+F~t`v#|U;{heSw<Z;2*lwwp+x+vowGPV!0K)`Nb#69a(73%i8bmTXoWjo%ZEzur@Z>Ucn@ki(BS){tTT-Q)=cv)YW&S1IU4jL<s>HI^cX?w=!E^wdLZPAD93~G5lVi<lCW4dY2GR5J>@_W*Hq0fU{G3jYcrJe>;m64ybfpZTT`=7s$uDmW8rA>VDDXjNt{L6D<Q^1oID5aLSIVBIq#ArX5hLm1&5a%SrW5={62UoYBuosX0A~rmyk`g{8ks=q=JUZw%D9_f+&Z=h6J!N)+-N>=&gt+mjvuGI3#P|Fay^dZJd!ZS-JG$rghVSZzGo|&VKe`c{@q+$s&@kfZPQs2AsY^Jf5%r>g-oNb|eQ#sx-kLstPxs~l@tLU)=+11@XWdY)Nk5NQJC5IU(>JVMU|P0M&$ja{Lw6&3ralv@P#!1s+H+h~fxcsKFe9#2H9U%k41E&0cppD#jGRH!=uZN}YSU+~*NC0mcp94>$g-LdegBQ?hqN|yr_=YO961_U=Gyb8br~<0)**O4BBe~??>wz})^bf}Cp7e-Pu{cv84N=wtFXqjioxFNfP#ni!CLKI$JIxc9e9!Fn?A*`meFu^b7O)|#F}behxVZF${1lj=Mr{I_%VOIHY0B{>U8U)KB#~wR<Wk>$Z<i(6NAFWW11MI4x)Vw4qgOW8#|=<MKi4%&4?&(BQNB}!OrLpgVC*GgW6o~M@c=3W3?w4=R$Yu0ry5W1JY}8@3uH^Qt;W;eX(bj3AolTcjt#T`MmK;#C|nkiC#R$LIN|5XJ}!pPL&KU^wCTA{nw1i{q^nKlw3~0ueFY39Y9<z4-gyXTf2`gt(hQNhfI1@J$cdtk*50ov$Z_MB2Bl24IpN{Lt(0+EW|_av3do`QVGo~O{?KK#N>@K<)V-iT`wG(S+qnp6bjGE(afOcb<7QUxf+P3Oou$EMcI`@o=+d>bb27tSu;C!V8otJC%HE2clWM;({R~O8ua^P@^bABop_KSHBGCVW+z9cbQT4Kao)kEEZ`YL{_37kM2N{8I!Qpixm6j#bs|k46pX!A*y%^aur3tat;}}3cQK)Ksylhps1Uvu-Ks=voA&NWCHc$9MLv#nze=R)gJ<fa0=qIw9v-Z}OR6^}$UWDKjmFiF9APg{l$_{lrBjZj-~U^o--S<9{Ehtc3L%s_I%aJq9};3}c?ILCfc`-?z!iN=B09VBdn5YphoL~<^kN8wy7`19*<y=Hfq59631;n*xEm&gIlIiO7%|y<!=$K#;-Q^^4opl@iaw@D0pgkzAxc#jzSYvdi_<rJo-%=jw9C1s?@m#(7K&Rg&j#|!P}NkC{GKWSS(51;1p1}ikybOPGAU%%Jt~U{Cd3078ATD*+GGMRC*%$n&{`#8D)F5`a2w3~VdW&F67@?}psMKvOzbKCMIXKc@tjVYWi~IZSM`Kp)?L_qdnn!uCi!wkAy)`Q9w*9CJ5jq*CztjiSUToQCVEp44EpAv+S_~KYUdrQ0nH*>NK}GzqNR#ScICX~ovA9@EO&JfX<<_7w_RRomw6>>vi8&o`rOuTD<_h(_i#B=QSLxY0dYmDVvSCSn5t;05<=*1`0m|Nw(bn8gg7WJ2~o9JKib?;L}mD`@Yx(^%ydEaE)zaWF@=H-u9~2hJA75-<q84IY>n>|&ve9un2a7`Y8;5zL#18vR6*8tKSsv9=jk;@KSSiRKn8u<w$JR(Nndfs#xL2Y3w_2ZTQ7AD65oNCBrFq+=EO}WE0jW%<<1n-VRbsEAjWZ!sSc~o09Wa<&h=5!?;)KJo7MqmO?1Wzq}ylC(iy*g(jT2UQ<wPn%ly*GvsLOOCH@K3Z-H#Ugik9aXw3<NP9hWR23JWmt}tTaYePOPWORE}b$4>Sn04bmfh_&^zWt5%tx^c{w@<vrCsrcRQWOiSc|Z>_^TO|V^~!j)LRd%Xlq=|;Obo4R0yQD9m3_^|mWk2AvDB#?PNfM3dfixlohHA|6!o(oLm*1i@{9_5$m$)hsA;H7N?(CWbRiPI8+Gi+^v%fVbeo2SD)=%m;t*o-4YOm&sKkN~IFA1Rpm5FUxb2jPM@V;tL-B1dMK(_%>a_h7LCOoC;To~wFGh>d8JnQPTD2F`vH;<@BtU3)N<MvR-j;q(EB~H*2@+6S2(rxe+&)!1yt=kqv^D9!HQuXxM+3=c1jIl^?eMs*I`aMA{8x!YwP+{U<AWx3>ze+e?v`SWkJpHAa#8b5#_*INEUTYSoH0pA_(4+$`O7uz)c1Ga#qVkmB?H?<D1_5Bpf~85A>5vP<`oFdvDH0>&^(ndpFsfE8b${_i^ajv?a0u(4G1E*KE-v`pzigJPe%YBuMzWPuu^~i3RJMUX<bnJJcbH3PNIN6BFb)Hl3VWu30e0Qe)?>#_#*<^+fNq{JQw49jsUFeM{6u5P_Y+wr-Z1UmJ!wCxa_~jWxrp(FZ4_9x#f(-*Fw6VpJ?qNo`FvJx%i;$vy14>f~`sa{mOf_sqjk|-Rb9gfF(Nt>*8sKt3;TKh3@pSh{*jc7d<+1A7yt$LhApT#1F^r1oqc?o<4n5#WJezA?`Pd^Z81?eT^QB$K=4{*EtJOdgL3%YR~Kvv}({j97RSSuN$BB@m|M>U2C`=b&S1db?Zid&@lSLwb_BMU;Os*B_FTWPfjADe~bB@67&1oiI(adH}%8&vi}~G{r;ikziZ{+o0k3lMfaS&L!3%+;p<6^##x_T%q`Ex{#AbIk~<y9NM>fG7_)gv4sagpp~T`93{9FOLV7GVPwxnkOVYi-@x!q@;UauUb^I@W*HOjqs`8?9_AgERw~fPP6aUvuA=shUneN^ArcSXSeNVTEsXjMe2VQ?rGd_R1Dt2|SarF-O4yHw?ITIr@94Q!-ub6_-F$H6ER+{I#vFG3HN4V=EqfYl<)3e%i|BYj1;;N$F_uJS1_VvGg{cm6YS-!p?Oe6XFvzUZ)alP(!x)i%Y-Jq)(mL0h9^x*pB>m74r6zUSc<9ZR-SM_gx`~2TN|F_To?ejm)=bvEoI@>=!8|ROkm~8i)sc!f;F$Bg(5YFwGYr`kM_wYN;FUI+0+{5qQ?C;*}@80b1-t1@fX5C}G*)l%vIu;YnjBlDFit*jZt$F?K!Nf#p+>2cFYd^{?kuu@yz`Cr%lKNR{H=6JZVuIBS%y`;x9pm6yUNmwh5#2v^GY)FFgIsH|8+C$%5e;H99_S+rQ?}!s>)314>c(a#sCkj08_}4)$F%AC6W@y@pP)`FC-G+%(+K=t)T3{|3`XSpjea+FecLzub>MX<_V15lH!{gKT+NN?Z)>ul`=I7wvY0;0wT!*dH^l5-Y(uCKjANRNaZ2t9)i!!9$u`7%m>U~=&+lzaf3P#-G2KJxmG^w3W3N5b;j97OLsPnsy735;y7~kYyfv@W4#f2Ds%H8Vu=njo&Ui=bBjc&cF%x4Q)0iopQ6n3$Li+yG9X=mZ!)9k0jxa@S(Y;7(WOf!ivyabR(c1LZX5Zep7XG0BL!WI;buXegA{yvMXDr1?8S`cy)87t#4|^YBB6_OB{!G0a8=Y>$v_jhd?%veR(C7qoACH?xL^-L0`s1|W`IMLWU5di&jp48Areg-KziQH+$#}EON0srRKXvvppWrP{ZAXI!Y@ME!Y-WwMUAumu8F3gHagUzorbcV(8_rPd1?{^Ld4bvQg%lH!-A`$6(RW)QK563fX)mOi*8IK(ldlxBiX7ix`evW@Mu*D9a6@aVn_&5&y`t}+nfU*mKsOw+Ny>R?e|DG>r!%lOqhVllCTlb9)<+g5$Jb<^(}Xopn%+j<t+%#fp3G!63TB%HW;0=$Nf;20)DT`;x2ymB&wu>?|JXi0eS1CphxqHC+t<g}w{1zZ6C@7mNFA=5_xW@9`Z#+LP<fRMBFrH49U~`n==Ziva-BaOYn#H2lG(EP7Jl|dp=z+uTJo6iP8!dIIO3u3I}BT0p!6U_9OR{=<4IwbMpvtzK$r2m2eDL-{qXs**8&O2Uz8R~gWt-KH^_CElz~Z8Z<X=W#yuTVyK}>%r}*<<vG_Y387B8cR~cOQYx+!YbFGzJIVvn#8JB);zhe|phy`YDpTgsPO&Uy(D<HYb`pzH<27T~KVaz5S0YQY25aEkaaS<*SUdtm`2ZRnxARxxPW0YP5BotR|^JU4Rf2p|YR3Wm?#*=iqB4#W=R)*N7qt-e|Otm$OVn}+v#-;&M?u|;WAxdAK&<baw5N^+iarYYQLMJ5~Xbl&MIV8Ag_WHqHmdZdQeYc!t1P2mK9-@KicxrxDlF&yGHAUeorA2gIQ;O_x`a$QUd8im!^*Q{~Gq}AE9c{LaA{oxJAZAp=c_KR$Zq4@TswI~Svf06ouDb}Z0?%@ro*!;Z3b97kWR0JBAd0Za9Xn=dc7`Ecy$#Rmt>N}fr{|BHg6=%ZI+U8_Wlj-Bro=Rte(y@bpA<?0I5&SE5eg;*U@!BBRJ=-K=oQ&Bo!3cmyzHI!&i8Cp0AgI*_r~_HH|cy|m2BkD-YqFSeRPZhfr~swlzq2sbeBH=y-IxL{&^Uvp_&k;LRf(EO+tPTedj|_2nK25QV`R{j|d|vWM!MDYn4K|0EDZC?$$@0speS->lTes$B0MHkoME4gDjImogJ<qFET;If_<hdyhpz~0l8jC;TY}nv`Bas2*Rmm9^Q)ZCMAJN$~T!180}@NifsSXp8SmW{PKNP%C$dXuT2UADFmZ)i4e}E{aol2CWDYBGCH(o6f#h_*f3*SFA5b+Ktba%h3eD2Y26^?3`~D|;FP4(rSreqnTJo^YXx@riTi!&`+nA*p9rzw)9rLb;lG~7-#K)m0AjP<ZoWVNNB*DxTpw1OZ_nR~G1OyD&UawKX85pZp~h5ENOlyyd-dUZ(O);20E+IMWc<D~&g>zyLwjXr0!F$8(fdr_zlhXJ5zej(8(&hf61G`2PV!M6S)LRDFm`sQtBrg^6#<CS7$%{KsCyvA%f_GO?>l!wP#S=SCMVD8Wh0mhdEuFHT}ABn5jJC2zmGir36V0lo{)L<MH#tjEXbXCYX~A$ju%BJ3)?Y1kK#tUqg$MY7VqfC#7+~)VWpt@8R2s#Cq~JY;=Hw|^C*}c3uZ)TV)WR4liCC?WrAa=r2Cw{=Skt`n9fe}8LhW_T@p4`MHAl^{mL<GvQ-cXvgqv3{G4;++$e1$9!C7C3RKFZ_;Gt`SRhR69-NIvsrJo26R59li6)duh*QnK<``Ei2)he%LXO3mcB#A%Lx@BpHeDw|rSq9g*AaQ|i%5e|!!rvyL^+XGPN6b+ck8QCEIHS?T$WO{ptSYwLU34FYen$&6+%+U8GRS+t(({Rb-xpkZ*Ls&+pk{nu8UWiLGcI(<UHS|^I%Y(hWG~MsmW$!Ed#GZxq@ZrW{k4Iv_`QE-FZ_c4mKU6+9*@dd*I&m$2<3-OxIAh4fW1n^e2(BrU^kMN?W4LH=yre9`0FCwzs|4$(L_99;NTgf=$vIv=jo+`<bb^Q9`w%a|wBM@BDGq@9^{eH(OKkuZ`1dI{dQr<7fHrv3|1O`u@#XzTn)aK4wv*?;s!lNbyy2pDXkr<lCRzhhl8{`ZljG>5it@pig<PZr3VWHV>n_5)^>`ZBX%VM#aA!6-ay)BE#gzKtg*rd|xmrX6gA)eYev3O*D%Arj1g&v@pJVHx2BbC5_;Ib8N1Q%=Gn(sCC`!<hwb^J5la_;u?-4VuJ;0E2_}_?h#@MxF29o6!)dA%*UB%i5WMtPk({!@%u8gC}K(z#C`AcJG;uiL)3-hn(&DQ(P>REM#eEm;e5$L#1H~Z#LGd0wO=}6I{qMtwL#b#@xAz-h$a{5Y*-v>-tRSMx+#QjXDs5@%;>nD?N^s$(n<PRF~yH>9_~99O12AQ*LHxom`kbkN%-w9|Gi3DfSe>0&*6*b$M{kUWWdd&T_1u-*yVdv#O?G95vUO8Gm<uIvDMAbhIL^fXc0q6qUgH46LF-S#ZXyJpbF+Pgev<Strb!1MYc1cn66Pt{X+f^<N9P<>lzEgrF*OQcKAMX#Py1h9}@`!Qqx%G>w4+yYp#fmeRp<)=XqN?`)z@W<_&^Qw7whsE${ExZr#pm#nF6-6YkTt%l7}Z_jS#QBiXk9WnOR0JxIVr`$n7xV?Y+;6a$u!r8fg*Ku9j1Ha4J$``_<cnfjK%xT;(|H)5irquVw}%2ejg{jv61xIRk|gqD%QPJQp8Cq-)bb44sku15-0GlnU>#|YQqeoW?)g7nMkd_SjahovVgeTMxUF_70za!|N0h3qA4BfMJs&+@-TU-ZN^M^f-)5y|)@%S|_}+0s2Kf_}+-GmrHu*KON+DG-_BI`Bhh$$M$aKajH1pg*|d`drI0C!eEWyNaKIU(!GcTCp<;^q|>hgs>SI)f}N|0qjtmP$cF#Xjy(a$oy_jd|W0zhwb~0d1FpE5lZeR>uR3}VluZvUv#pvVN)NCt8Ha(GVdaD_PB;RqigV%bX@y?JVsj7C;)ql_!#REdlBnMW8C+i<XbB-vOFiUXT`pUos<*<4Z;b-jS||mYEU!^VkZ!FWxp$bpO6kvUn;7?Dy(5E^PDT`s}J&Lt)8nXX>s-1)8hN9meaQ+PEU!qJN0Xx+7pCUq;|P_zdWWqMN2~R_18vQU09Rzb}uEfm$Zw`_F^3}kCx{}lAMa#OB=k4KmE3%*~`~llP{3cNY0*QY>Zesu{o>>NRs|SnX$eGXIHQd%a?gngV_ELYY5C?l?kSYnlDAB;lrfotnzvPnSI{4itxVIi)ZG%mZ3>IeA6>LlKK~E<BB<)c3~XRaF^_jAGl^AmsToSk0i`Vk}!u7&b%fiX<=+_-yIP)`~HY?fVrZCzO!V5O0^#5oD^J3^U8kH+Iv<$kFV(5zE}O&q7Npo)8MBqj1X&w6fQgyQ=w<4O39n}540ijJdpLkGR;ky_?Zw-><hkU=I-i#9BFM_c`d?6C5<Lw81PqWG=-&cDDj2#+{}H%n_5|4eWp%7Ybp56bs4_3Rj@F#A`)e*7TcA$kVddTe*eCRc9HUtU)GCg$@8Jvr_F`53lQ+~yXILrmo$VkoY&U(%9yh~mlEtV?@{narLe&~n#R@h3pRTv#duxX{HyIZNhm**b-v$5%j!A@&t7zWLRcbG^IXJ@?&K(#yYDZfjDqPjEo&hUgmYif+f@9uQOtTM>unzEwE9%qMfexeck$dwCAXXtmos;RbFG2EoO6OWO!_@)51s#P4)uI!f4UXmC~mGUn5$ANKq$%K;e(J)mDJm5+$gEI;k%dH0!I0Lu?`B5-Vd*H;u;^eZF}~5<J+Q*=WkoO6MMlnwscds`cBJ=3UPE)%$rqex51)gvEE}ZI)c!sXc`D+5#kl+rG;y@ePeR)BPX_kh35B#X7zh(FYq)g^4Fd{TU&u2_y(^r>4?~C31d(`Lu&7;lp}f1_mSAieRR)uk*iozJYhdo=D7&3%psM@e)wFD(QLLy+vWY#nT?C^pQL31=P8AjGiY}6T9xB#YL7WT&Kw`ma3-{8&%Q2e;L2Cd#7?e1A^1VRHw+{_o-uoq_=(Ktyq3_ovE2(K)l1}QzB^!zw>!3{TQBYfc<;g36`B_~gi{e7))qScZcsRba5XC&+l#%2J9vTF85@4+72$J;Z+H&*##Qi5y|0k)D+y1xMHg$WD}v$H3zk?{)^_aT`h5y`Ot9t%>l^T1UD2OyePRnJ3JCjQ*?87~kiIam;;`VCXZiP6#^@<baE#Aec8LG3x0a2y>kf3!^(0K(4|=c-v#sX}tbM07#@X!!taW0a7|g}3LrW*Ta=N8ZB%U=Ct{)X3{n<FH@I;F?#tuWv9Yxqr2aZi(?Gkb(Yo-)W=?`>2xIPkwhbO}r!wudi=9Qm!j+Whvd}AtMeWE{Hi(}J$({Wz!tw6Md?r@GVR`X!>3Aq!oF#IjX772S0kBt%W7TE8DBlfU1rr=8-_l}2ai})f!>HFb&+#iM3rhdOPhiyiKy(I-Soud~Gx`Ov~CkJ7hxS!eP+7SJ4Bl;9%F}r>r^KA@t+-r^d9)&)_I~QHN4?MGkD7MB$pF&c&asMF}P9zruMI-yyZ4pdx9kYwId=&OFvT!ZSp1>9^H=Z4?iS5E?vD!>RE{`I>-{W3H$_rs{b*%Bgv$wd8zbV<8LYxBo{UZIy8&e}>kg&cnY@sjlD&D~g%meHq1!H1AAcQr<zS)vqL-*}#tT6|3zreT_3M12BV2&KTZ`jyi7?f>XK~ybF&!uD?QE;X2b(sqmI(*9@jK+os+wUAn<zeC47R7gB%q`z1&IpUpT3vJqDfPH^blDQJ!HLUOaNWOY77oh&0V&j-;g^bb7Jk*6tPz&|t_^9Y=51-GVdsXVO$k1%!LeoJ;d-TTQN7f6e?9qmciqLk;TJfoJXbncF(1El%?j=zOoaS8t787mG*phep}v<3okv4$Y5c*~mYA3dPhVBe6D`Y`m#G?yXI=M6;sr}ST)oasp(HW<zFP*@`wYS@h1LlHos@F-2|i%=I1j(Q{+IlZ_V?wt*TtWkm)++5+w1>cyuSbK|NL#1Q`o#t^sB8J_tnw7wI~oA-XZ??+|KImh<KRs8QYw&%x<>BEq$4VF0lbCoJCqnx8uRL_aD}5y-EcV<GX?MU5Po#{w4*>WZZhCAnxfs`;#}UsaM#Cy|`}u(~-2*-4?Hl*mYwXhxbKWyqa6$7f83$lN64;|GaG?-WaU@b>I7+xo)ml3uit@+;k4(oBaXT-S;OieVli%h(j3{aoqI7;MXE9KK8nNkBj5}VBL2PBL9w!_*C~FwyT*w)cyNIKgGr=`qf_Bd+-t8%DOE5GVDw7DmERha1C?LI=zhfCdBZuCW<+h__-JOB=EV#>e0Y+Byk?E#~9MT-)kZe`}|t+{l0(ubMtikujujlO}*N`%inAkkCgVQ06<di%*>fB6<W?a$_I;%vb{LMkguh>cE7jvB0=X5MjHoRf4lcKMMqgG_C;`JFtHl{Kd5k9e$cNqXt7@lMoaS}f`%q=Ag3ET1}u76k=KG#vMKg!<x2Ef!M@xd^L1l<o$JdN@3)N)3x++u54>i^8Cv90Rqy)tLmt&MU`+b&T89d-<U=LyEb$adFvE-g95$+Qm%rD{L7#wHo1N680E7c0s`pk%-a$Ag*Ilb`!fEp1oUN(yhC^<mf)(3o340h&rHxJ&@$Xi!(%_83K_uRPaiDq~dqZ$oAL-mw18oUJ)@pqn*pSQ6gQGIGsR%cN<2T*<!3y_XZgJ4=sZ{6p@n#M7!kAPK-?9$@_vwge(j}jkrBB!F!?5f@7Xe&UyLVBMOx<@cf;AJ4Fq(syPC3G}$g<&#!LeiiiWNB=dyIQ%aIRwC_Vzw|He55tPZ1nS&BrsrHR(uz9@cxIf9dMy`YnHEeRnk++BB?9J@y&5S<~k~*C$1Xd4ymej*&jm`TpSyw>Tfz@4+S9H&w2LBJUgnsd-!R6jut`EEqrgvp)_GdiLz>yMJA}^#pfXJQv|rW=kJ*>(z6^T`B23xqz1;1sWwk-`N#s=wpTItnl%W+P_(&T6Ot*%~}RH^rW^G*Ub0C39KZ@Sm5wmEN-QJizyfz&OO%Ewj~0%QIWM78(8nLgZ(5y5!g!zGF;JSK;vUQBEZ8tb~=7E3PpbnTR?@v^~Q27_GBTbt@ZD-apBL}y%FG9`V9NkL=e1!!{8hce8K6*y4EMKE!PN82zq5-%>=;%RkiWF{T}YKf-}zEw+VwB?0YIXB8W0-y^$pViMsFgaV(2$76W0}oE23pH4!<mZ$A6S2+YOU1@7S>$g@H#=pk725P*=4+K(6{BS@7Bom}g}D1akwf0Fy!o{;+*<0ZhK3gQz2`U3%Xo&89DFzF)TD{@~aXU2Ay0|V<l)_Kw_J8zqd`5*3g+Ghk^eX4_Qbzz9TFZ;oVSOZS?5_R{V-tPpXwr5N}P*rm8pD56=n4TqdjN!}tp~O{sUiG;7Y>)qQw*TjB|Lf28!#e`=;IeaFefE>R&qqJlVo$R<!D;!y0=C&-WA;M!WLjUp$B*gRoPD->o-2FVt*O-(ddDx}+DMcB$)4O*##Yx#kf7n2ENrX2pEt^-bN-+=X(W`t*9?qGHAI_w!;{3|?TFx)S^`w|r!%35ea7YzPd7U_#{$dVws3BAc}8L%9k7o(9utW+_7(P*g}vlO&VFo&wy;+?=S>aY)kU!C)cBND@u_xiLB4V(7K3ef+z)Yv4!6F6Ya1r}uwi#59pO@Gxfl3-#D=m-4Qn3f*|^VUHJ<lN?D+}p&|!?d>en~~N(G0cfy(Sq5gqGlE#OOx`##QO=jhXKVdGptm1?sqVkRuFbtY@2@-@yXrtJL4+gnuHHZ1rZ@B!cpm5O>l$C33ju`rVwdp3edfOsR<dB$^)o&R~EeAb}L^3k4Ohiov!{CCDSo;SeR9+-P3{VZ|}e4QVU-*ep9GxhZ*0gtkn$0l8O`m(%f@YRb-&(Vnf|DJ%a6FzZOnR+w7oskdjB?VEASv<fyvT*kJ!EEgX6ZoR^jVCx47Fe?b_QJP(*k=)$ZJZx_HuH(#`XJ9Vyl41rR2JV0d&z=A*DC8A7w$>0<keH{{3<jY%yj~h!cC^=PB0zbrRN@Ae7$=@_xbARaZR!qrE5Gp2%u!4tSOGzz@Jzv%^Vhqsm86Hy?*iY^dXn-f!a`enZ#w1uTi_P03g%Zz_m=8daSee`bZa%HbH3$9h%g<&ueTq>vBt-S;S}|=K1w8iCOYuU$Ix;fBBX-m6d=E1e(%5Jto(#0Fk9HSLB;76#Sd=O(naND828L2Ka1y*E;-b(t6!t4IZuFnzneyW|zAREK2~zl7Oouxlcf8=k4)!x~l+$OThUt?6lvX9LR^@_h}~`_(bABURx`^CJz>VCa~Vq;G=EfQ|%EG;olYPF5)*EKBgg=Q}7RC7b~i8bY%sRd@j^JOhLr-fqbcMFN@kc3AWvIzb_5#^(>F#bIBJ|YxJnec$5vG_TZ|2e{9Jj0nVu7_+DxqzvpojfiIGyhI(h)Z};6joBhg-&c%ZNBxch!>}XfehDL*<a0dqqaixe?Z59>bTWgj(+7J{09~x(Hi1U{m6OIB(*w@{$JAuFJ;XOJnD=Q3D8>@4UJLQ*L)?oE3=P7?bYK@6|jZLV^h8dyG+;NTn?b-T{SVXfF*bi|n<8S!n%o)L_z*>VZK0qwsz(<%M1|bj6n)#&|F@GDjH@5T<Vml8uSac=Va=gS@N*{H=yujf^Q%Dui&`O$8lW{nQI|9FwT)`ve5OK8RTWaF*Nn)Mi*;VH8F$lg^d$Ytxs9iDlAo)F-$s3ejo6;~*@A|xsd{w7h7Bic4%Cqqn-tjqZseJ!sT!5L~X?U-nwli7&A!`o2KmR<R+LyVu`aAs8T}i_%<4$ehxXQ<&=F1-JDh(KM!f{mt-p#q@XIBJ$N!u>{mRsvdHZZGVT~kAEk{?TTD4OkfsqmTj;c4u0Vt=Lu<y!s?zF2V&ZV8+ilczkg;72q6=D}uhFOlbHjTi#EA|T@*{C3yt5`ZF`)Dcg!pf+|r9ljB4nG-YS9^1nxBh`>|5I)f#c}Qa4hj^e>;-9}#Q(pPc8E0DeFVKJgC`R}-K*J(gj+GIz%wE;noIX|jV(B}7WzO_6VAWrgyZ&op-QSzX%7GLu+3*w(pYSeP%t7FsYR$E)TK>G?1503sU-DNgeg%E=+`oM)#H_e(`1Vlp>$*wPSgn45JvZZ7Tgbu4cSG<?W@{T_sHWV71kC&%Ke`SMrLA}*FhuUD{rc{{wUV~GH5)v%hWE2UXiOZ-p-)gatDkvBCO{ZDZ+FqUHFx)`r<<OzTh`swnLas#p>yB=zWOo$?TmkY)7t%ObADW$y9E5B05sV%)U<Lx^u^AMx4JIQa4uHrFqf^#tO-vxZ`N`VYP}b8{keaKSnpQW;Ocv(DMv23Rlhtosnx&O#L2qjLILgmFz;JCbHMe!8%~E;Jtv%wrrTkEM$(n@_xb6y_tEvSH~!bz9RKj@HOpfuKjvgJ)epx^mFqNe@YOyOVh)%W2;US(Z@MokzC>ev%1Uz%DpyhFEziLEvgV9)aOqCFrZHtx(A&Jt8kor5Tb>7RXy(d@$yBqJY<e`ZJXy8wRBhU=5F3dDi9js!Od{TeUwQDzof<juxWCv7muIh|NrEGsKdc#!U4P>-BVhaZoloA%F5<qnADB9UrJ`y_Q$KPj8yTa=htVz}^V>MvS#Nry_3c*IxSx%zsWU+w_6fVLe`*aRz*R~7)0C?!KJS|X>yei_Bq>dtk@Vb{9ntUMEWX~C-qUTXG51`l@#VI2SZIcb%CT$Oa9gj5%Jo&mCM0`xnw|al?)yU-;NMu&R}EFgy0+SXk{C{|;VWq)?rcfOvS+RT&L;5k>f+e@SJ|_Ra}~Gy{7lw*z1d*(x%Je(G=99^-PxTF#wUqMGV%a3%$}pBWB+ju?Grhg4>U{CTu6zZIXcT<`avF6*1kxpB#9?62XD##jthLPjUe43usW|Dmi-g@hN>~B+`xCr)>ii0Ce0C-&VF~eUl>xOMCrEPmUA`@SOmOR&dmXF%u-VX1C3+)(C<i_oYFi!o~6Zjxav2{Gi8>=nXijT9LK=|F^5Avb%NYO#3YF0eZ)%3&Ddq*)@V&TZN<Yi;-%ON!qDnZWP^ksEH`W*5jr`s1#8x-IZCe)i)`6Qp62>5IXBs`&gRT-Gun8@&XSN)*|w|+vgtk<nZ^6OO@FW}2_7B^n!ia1H}!)ycROdk`&YyUIY~t3pA>w;i+uCy97+N}p5<ztz}CJI0RF3e(BiYDbM%q6Y{hrO9<aX8+orttz1vx34XyY46&u9O+uo65!Sz<skJ5`eCch{ii8^Uazpwcm&%Fdom^5hIbTIas-Bq<-JIu5o7_Tf9DcQODXakX2#WyYHQ`2+xBkdRFfwU`$8T@urCD^$*{<<VLobz_4dCLaf349mhB8hVv^I|>rC$;ssl;nqe2F%@U_;i_{eg1sPpS7C9lbA}`KwI#Ec8aWES|ZgTiBw8NT(zy<1J;`&SV@}0XBRzpga4%(6=zqey~eXlgU6b^NboQj_VjS{V)Gxu@b<9Mti!d0JJ}Qaz-B&A_uzjE`03%+ibj#JuXW#W^sy~sp~J^!{)l$JzYN(RC3H`-f{7*!E3}$yRWu8dSmlzneZnrQy_D_s&1sv6{lo@lHm8tC;LpdD^e&R*0=xN{@BT{rcCqcv&#xu|>L1B(P<!QtXS-S_=8iUK+`s-ZU;Gn$|BN3#GGNzpd%j8SImbe>OAYr4iM_%z^`s3c;zWK`%&-1#%0{1>U4nha-qn(M-QNX+LxcU7wTkg9({&>OQ|lt1tw`$XPS4i0FFikDBihU<_z3}@xW6#R@k8f`#MEZ>r3U>V_}Z+)u%=>W=c8rU)~3cf4$c}mci0=3*p461>!pOArCc$5h})jD<$0sI^xIP+qN<%;W4)=yX88O|moddf&t1<`KPN;EDV8zGv((Q7<;SP<J-;0VBKS_CXU*z62j5=A!kEDy-)iGNiQd<+*=!^qw0#@?d*9rTsmtLyx)rb3bi5Jp+dbEheAZoTYb*4@!E?=4gWWo&`02~ykrOsron<MBNqnh){~*aM5)38@aa`@~%y)mKt-I6?=Vw_?98`!Ce#G~eWCOb_zS*=We$W+PS+lrw@1Lt#Y<<}HUiOafZhEap!&%|kT8b2xwe@BA=q|rYfsk8iM~Zq>zbfDHmiCZ{`gypg78~((1)o#D5I=m84@Xiw=KpBh8i+D}<UD0F_mk=Ykp9Z?^ZA`moF$5^D9sDlqF$$IVO+4=qcpe1_1UW7fuCjUg7ZesUH7uH@l+nCT;DD<if6fTNzxg0Yl1ZA@qdcUoMi02(ICijE|$pZqi4pI^wSgw1q!5MMWG#qH!nP2tC0IjaNlQiOUwA@_j0XMQ+*#dwZ5M+fv&D<=^yCVHTud88mBe<i^3M~l%UR#_(zeF8yqdzIP0briy=uXzQfP{&PM!Vy<K8`^BlA!;))-1l4Vnu3pQs{$A%_2EX+ASXEowSrIv0|<0BrTfC<U!$3+}w1*4qzQdCH9su<^{xxD<l+O~-V{ZS8J6Oy@{Eb$@5iJLWYU~%7!pOt@Wn7<`47t9$v`<d;{V$8$`7IyZ$$vLX>t~bxEf94JJf4)8MHqp1gzdk;1cE@Vpe4%E+dvPzkE3K_YtZRZ<;(o{XjKsgF_de$5;*VkC%2-!hbYwqUWVZci(4zn4+w`qO+mo>|NpnV9{vB~xM+7D#?*rm)&2lN;(F;ZFZ+zl0V)i0TH{%=gT%XzJ$N6c0zC1?Do|0q-_Q;97NVG+;YLP^SSQM-8#nd|_@ru=7!PgwF{lM#5?vw}~-Et>g5w8PJH#H%1#;p5!dw=s~V@x$E^Ra#~KH_^Ud)u}8JP+7ADc}#2sKwLAQlp%hp=m_Y9Mu~$jJ$Xq5vwBtjLn6=Ou}zic#N6kK?naU-{HRxCi~Zpu~=JAYSN!srz8tvUS@1C-m$Rf2C)^H#9U#Y_O^bXWIKzFXZI*@rHOcQwA>l?+(P#vYCsCC=Y@uAU?*;4&&6CEzi^Bn)s9QJXS0R(5a3+JnjGj9@)E&tEvN};(~evph=sPO7a6fGzUquA^c9U@TZCruckJ0>Zm++L1PSB%-u^7cJHfLN0|;Mdo5mis9<=9%{>4vYXiH<=OCl)UJX$g0SJ)RzC%F>|shrN(KzxS%X;GXk8WG3Myk!gH!CVYTaHaXO&NM_EIKkZD*)bQtdaVDpSoT#@kCPOiB7W|DuD8m5W&zuDqEC2Je2*F7qrw{E{;Rzg6T7*LJdzID?4!Hxdf2U2ALAg=7zydH_e6gMn~4)39vpnwAdfu`h7<EW%HBib6b-X1(vagw3Neu)Yr_6!yxzgsyF$l3Y(c`W&e)~c*>o%H-iH0joKG*tefkvBBB7$cVVzRM6iRb&4cJ86!rA4t%kPWpn0c$h_}RZB^NI^)cc_y}BDwymg>|O1P2)w&mwRl|q8$~wgL8xAdbCH^2Z1%~^K<OkV1F#;WX$&mzW`T=#${Vh@^BKS<~~YT62^qxTgAd=KiQ&-GYWIN-1w67APmR-b%gT^Hr!*M9)3S*<DJFqH?v55XTyfFe?*dxO>velx+H?DXwzrsX-#)Ea9Y02?+!zymuq&cKH_Z2u^@Ze4($Es+Mw>ON9;HJ0AHRa6gU$d>Y!ToNaB8cYVaBrjb;^pR^I=J=b8@R3TtlB@o`ppm|vV#T|W>9FA#gHKMlPYb|4yHJr0gz-lIPy0bStXUaV1j_6leAC?G)}Y-gutCr*)E-db55y+Nc)D~m%Uf{ikcYSc%+&+vc7DgF2%>lDN^DFL;xF2wQiHAWN+dzl-=9V9}9KXjeXY1uo^Y24Xs);W)_Te*%j>i~zC&vimTB>ZNCE#_hTW=?}s_c+LWk;GS#fF93T!kaYcsVDQWIR3F0;guxCW?ncIBy=_nHPh$^=j;>DVhxqn_e0WWlYRfXnQPzz9*BPf8<W=&3i&9N=MC0tc%Sgq2ko%|AHW^Lr*q=5>&3*ZlMBIjvF9Uyjo9lTf-QXU3C`46=;=5^?Q6sz#O^PS9(!ylczUXDJIVz>GO<8eYn`n*Cv*L3m-O2w*vr?Ft)dtT`$Ih9;YrrV^`J-_5B_~?KQ7%X!vUY+;wi2txkrd~+NpiA-w{7GzZGe$stEDpDc(~LF&ObWv&~rcGLX-MzTc`%K}p0mjAt05;k`~nAMp;(#WiCZ`ih8AV^7u%;HUJ>V?D=yskkl0I2`#t@NN<RtpnL79#9jUJ&(hXJ&mkK@Eo@c`swUxnRH25in(ivi0Ah@6nyXft>%%Kv{r{vLb1d;d9r6_w!PEU+%ea8#~Ka!+wSw{`g%dtOP;G_2eN1TdI8YukK>Ww)1!KEZ{HWjc@;bKVLm}(a^cS)KH0X$E__G!Va1{Yzm_~1T@o0RU&A8aB3LNi9M^}R=aaMMh<F-)$P_l7_K9<~;9S=Fzb?WS$oE7)chVBB*OvP7!Ac`ng}^;9-o1rAXK`P$H&2R}5l2mZdh$02`r|Qm=Sek;f5;_6Zj9=Cx~Nw1g?Xb>@9Cr7%P)_&YWzO>EKKSpZ*#=LN}xx}g~iKpVb;@xvpSj|t0LsYbRJ&KTYo)Q@##xb-uM*0so=|=td(ERjbObbA~W(n&i1N5b%=eQ{_8;-4IOPJW<%>qVP$f0*pu}X@@^<X+>|@Binp!!%hmI--2X{j+1*XgCXPgk=?p~-KbF|r^<vY*p6PAo?df;(Haknz=Tgk}O)p!|k1p0vt=<WrEW!A(#w_bg@Ck`aS!h?`;z9C^9Z&X_oZzPT2&+)wep4b!g_u-6yNt<ug}vBI#8i3-KCGA2E+(tYzluWaom!2xK(t)-2NgG+ihI@+IxEf9SB-VTwLes~1+%{@kr`+GhsPe{f_Qmzems0nO5iy0z1VO4u$JP<b<D~MfyVRw7G?31n^A9W?DIYwBN31z!Sa3fzKHAGo?C0V5O5xU%UX28N&8iE?@-wIM#J1<-g3fjnddWQO?<V=*2A%f&&Yn4mKvv1$7kh&MQ37;<rCKSaS>JdEo*{~pTKce?8J6PTi7kGt70y!P`^wG(AE076|1El^5?Z_D1440@RoCNcDxGvyMAiE&-ClZ9HwL4u9j{${B|q*&4{Z@>{Vh54TV3FoW~i~LE4Rg*i5`<_^b}E5j+yls-IuGr?}Vfv$l91Rk;m6-h1_$|A*&V%D>^s-V7=H{UpbuV+`)$CC7i~=MTjh@vH^WsgfXhp)MJgK2zj_E94@IduW&P|25TsKf_y5_-x`sJLmBn83&mZC2ZZf)!L_w`Oor!q_Jo21D@dmxfB!o`8wri`B)0QM~MhPv^@20v%Ol}pX#$`dM-Z~tCvJpWloO*LsAH#^`3A_>}1Xl=hfZws49}Ez9Yrpr2j}9Te9A!FWynh@>Gkc;)nb|O#1uQ=cj79pT*~W9{=<c{4TlR?({$Q;r}Q5aO%9x@Lf3nhF4o+YAW1&>UYDd7s)+yJliK&tQV&7)OddEA?C`(9!oj+2ila*%D*Ll<78Ff394gY<!5rfQhR$fp5CAJE8cJxhUa@W)3qS+&<W<dj(>9EQr}$_500Nj!<?t~a{83v4eR^G7UjB>UG52y*u(~bLwP-N_dUZ;P+X67ULRW|_<rV>MNHh;pyRV<9`v@N&zv%Li)(5Yxov_T`9rtNsc_}_hG?_?C~S%fiFnM~m+LWi+4bT|T`?3%f0HHiBg6tRw`Q?-QWpp29sEed!k$HAL+E}mI8aPW82Eflz8HtQHWu-6E%})vd_VGzcwSA|^|_YuL$Ja+@yKBsi^%L+F|J8mi)(hs%QLoDu`omzW7_!rl`dE}$Mx}@j>r6#J;W1{dwtTuz1z&^)p0zsH!Be__Zb(b`=Kb3_6Z#2iJl7GqPS_798pUhaa5K6QuRfZzJpj*;q7&mgDBVbYcbnIak5@_&D&+@xv%hjuQp5AOr`zN<2`uR6nYGmps~W{w^pV8KEw>3jQ!+uzc6m)GhweEmr{gIV~&Ry%NFAHjqehh=oI)ddJ=1LR}%ax@^z-%$He)KYWtDr{4#PX0!-{Lt_qniH42`~UYm!eJvw53<3;vEP_!KP#TlVE;Vbu?>m$kQnQ&xLtcUjQ#jobA^w}Ek<Y>|tc_z+X^4G44y{Yx*AYW~o1DIxfqUUXrdGU1`*UF@ET^8b$Lf+~Ee6a_6p5xYg_jbz~k{e|<xO#HJ*?2Yxt?BH_o;cmnY*-co_S|V#;#|XoJ9zd7`;qE6&LXF%mhud<m%gjbjs2-ToAmq2zL+1~x3BDXd~^{b8C=ul{VC_REza^l`Noy>;SwR(Os|7NcaIJEj>epkk@rn7X6625UStmccM(w(i#YmGnv3E2fcI9<S^RJ=r8tJ?r2a%cl!uqgp1+WjoVS;;iD$rbzWvLVeGFgpoM|63<73A5wHiQUers`~sUEopA@jS~?-<jx?Ypx#^Y#UH>5nA0aP{WjcYal_Z9CT`1~REL`Vsds`=)#y?-D+7y-rxm14TZ2RZ|;%o2}hft_k)g%6>%nJj>M9OOfp~mzeaQq(W+&UzNL=zAIli(Su=~^_h8^={n;8DxPo055`%@{hU3cZc~x<$!FJB&F}iyPMol1RUGAIe1+LrdO`$ojcdG1{2I=jMPz+f`6!M*?S0JnCJQ~F^wXK2)n4Z0YLeo?%XM8`yo?>d?<sJ%<9?^U#j-5C{^uk2x3UX~9)JluHG@we<J}PNf<4`z5tMDn)la?>r(P5vt>vbbe{1TV>@iz!J$oBd6N1;FevcPyS#vu`F;e1_?OtHnq9p=iHsEJRqs<t;u@q!wJzMv>LLWw!U5Ic0dVJny!Tk8J7`u0$vi!K}C+moK5PJbdSDh~AwCzPor^L5c9Y45k`F%$x&lP@;XT!US@mv8l7X}B+$JXj2N_Fvm`YZU|Q^W~ne?a9i>bRLNuEG9(TwZ23%7V;Ak@JR{Wpi%0)Qj@Edt80fl#pY!6(w^8Pqtgtp~Q5f3UsL37}Fd`DGA-@bRR5g{Px2Dp%j*24<Y0=OeOvvQzps8a<>9O=(9ZwNQ>qZ+RE2pP=lG8y{j_p=qD)*icqsEY+IEU8)4gNd+To<YZLv=k3IjH*1|K8e=a#`f)xZ>vtT|+gXG%`&lkrr>5oWhOW05#xaDDfX?C3s>Fq2^<rorZq4|Bxmw}B%84?MjAq=5cmMi-0ZM~JF=68+r`Ga=p%bxuV9YC|RPfp7zOL$+|7WCS*mVUN1{gQNRPWSLz$9R_7<f1h3C9swc?eCXEqc*>tLZ;F7e*HLq3H8{ovAbX2{_(SRSO0uVTZ7&G4Q(zBcK7q`c)!H%emy<xPutxBRJBa4d-vRX^N%0C&#!6a`^@|Nu=Vhl?9Z=h<NKw4(GQn8o8If!kGIi3`r$GBlKo1^Go=);Cy(?Ge8RkKgwRYGz&63-J0N85coD*IebR-`kH0Okw(%_mv4>3(ZP_w{(3W9wrNsAFPzN{qOTS^PXZ@wmJpWn0soWZx$TF0uMmiTrp@rXWr$?_qvD6TH*FMt#x5?U*N>H1kOja}vxre-9g1H&QKBY4PmO4jU;ri>b0lOG`I%YW#K`-=!a0CAo&u%h)Jc{_b>+}4iM6E53W43O%UPbQa138^U{^T!u#@*wCrC_{GrBuS15~?uem#xe4as{|k!#m=&V?|fo@ZD1>+A1~3b3()XFnUtu#@SmYb@O8>*aAK1NJ4?i_T73)AbpC)*&Y<rtI4w{s=0bvRZAr>H)XnLmUCsECz1Y^wgm5gg7pwOu+jg(TEM@(#|!9w{)v6|-+%kR{|{mDRk#'''
try:
    replacements = json.loads(zlib.decompress(base64.b85decode(blob.encode())).decode())
except Exception as exc:
    raise SystemExit(f"canonical materialization blob invalid: {exc}")
if len(replacements) != 30:
    raise SystemExit(f"canonical replacement cardinality mismatch: {len(replacements)}")
for relative, encoded in replacements.items():
    pure = PurePosixPath(relative)
    if pure.is_absolute() or ".." in pure.parts or not pure.parts:
        raise SystemExit(f"canonical replacement path unsafe: {relative}")
    if pure.parts[0] in {".auto-research", "review-evidence", "logs", ".fixture-shim"}:
        raise SystemExit(f"canonical replacement crosses authority boundary: {relative}")
    target = project.joinpath(*pure.parts)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(base64.b64decode(encoded, validate=True))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

# Bind copied final binaries and their versioned copies to this materialized
# generation.  DOCX/PDF container bytes can differ across authentic builds.
final_manifest_path = project / "final/final-manifest.json"
final_manifest = json.loads(final_manifest_path.read_text())
for key, relative in final_manifest["output_paths"].items():
    canonical = project / relative
    versioned = project / final_manifest["versioned_output_paths"][key]
    versioned.parent.mkdir(parents=True, exist_ok=True)
    versioned.write_bytes(canonical.read_bytes())
    final_manifest["output_hashes"][key] = sha(canonical)
    final_manifest["versioned_output_hashes"][key] = sha(versioned)
final_md_hash = sha(project / final_manifest["output_paths"]["md"])
final_manifest["same_source"]["source_md_sha256"] = final_md_hash
for record in final_manifest["format_generation"].values():
    record["source_md_sha256"] = final_md_hash
final_bytes = (json.dumps(final_manifest, indent=2, sort_keys=True) + "\n").encode()
final_manifest_path.write_bytes(final_bytes)
(project / final_manifest["versioned_output_paths"]["manifest"]).write_bytes(final_bytes)

# Phase 20 consumes the now-rebound Phase 19 package.  Rebind only declared
# source/output hashes and keep self-referential JSON entries explicit.
hygiene_path = project / "submission/submission-hygiene.json"
hygiene = json.loads(hygiene_path.read_text())
final_sources = {
    "final_manifest": "final/final-manifest.json",
    "final_latest": "final/LATEST.txt",
    "final_md": "final/manuscript-final.md",
    "final_docx": "final/manuscript-final.docx",
    "final_tex": "final/manuscript-final.tex",
    "final_pdf": "final/manuscript-final.pdf",
    "references_bib": "citation/references.bib",
    "ethics_open_science": "ethics/ethics-open-science.json",
    "replication_report": "replication-package/replication-report.json",
}
for key, relative in final_sources.items():
    hygiene["source_hashes"][key] = sha(project / relative)
hygiene_bytes = (json.dumps(hygiene, indent=2, sort_keys=True) + "\n").encode()
hygiene_path.write_bytes(hygiene_bytes)

package_path = project / "submission/submission-package-manifest.json"
package = json.loads(package_path.read_text())
for key, relative in package["canonical_outputs"].items():
    canonical = project / relative
    if relative.endswith(".json"):
        package["output_hashes"][key] = "SELF_REFERENTIAL"
        continue
    package["output_hashes"][key] = sha(canonical)
    versioned = project / package["versioned_outputs"][key]
    versioned.parent.mkdir(parents=True, exist_ok=True)
    versioned.write_bytes(canonical.read_bytes())
    package["versioned_output_hashes"][key] = sha(versioned)
for item in package["package_inventory"]["files"]:
    relative = item["path"]
    item["sha256"] = "SELF_REFERENTIAL" if relative.endswith(".json") else sha(project / relative)
versioned_hygiene = project / package["versioned_outputs"]["hygiene_json"]
versioned_hygiene.parent.mkdir(parents=True, exist_ok=True)
versioned_hygiene.write_bytes(hygiene_bytes)
package_bytes = (json.dumps(package, indent=2, sort_keys=True) + "\n").encode()
package_path.write_bytes(package_bytes)
(project / package["versioned_outputs"]["package_manifest"]).write_bytes(package_bytes)

data_like = sorted(
    path.relative_to(project).as_posix()
    for path in project.rglob("*")
    if path.is_file() and path.suffix.lower() in {".rds", ".rdata", ".sav", ".dta", ".sas7bdat"}
)
expected_data = [
    "data/interim/panel-loaded.rds",
    "data/processed/analytic-sample.rds",
    "data/processed/analytic-variables.rds",
]
if data_like != expected_data:
    raise SystemExit(f"canonical data-like inventory mismatch: {data_like}")
for path in project.rglob("*"):
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode) or not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
        raise SystemExit(f"canonical materialization contains unsupported entry: {path}")

# The vendored bundle authenticates bytes, not host filesystem timestamps.
# Normalize every materialized artifact to one fixed epoch so extraction order
# cannot make a manifest look older than the artifacts it records.
materialized_epoch = 1_700_000_000
for path in project.rglob("*"):
    if path.is_file():
        os.utime(path, (materialized_epoch, materialized_epoch), follow_symlinks=False)

# Phase 5's pre-execution gate must observe no Phase 8 result artifacts.  Hold
# exactly those late outputs outside the project until Phase 7 is complete.
stage_root = fixture_root / "completion-chain-staged"
for relative in (
    "analysis/execution-report.json",
    "tables/results-registry.csv",
    "figures/figure-registry.csv",
):
    source = project / relative
    destination = stage_root / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    source.replace(destination)

shim = project / ".fixture-shim/secrets.py"
shim.parent.mkdir(parents=True, exist_ok=True)
shim.write_text(
    'import json, os\n'
    '_values=json.loads(os.environ["SCHOLAR_FIXTURE_TOKEN_HEX_SEQUENCE"])\n'
    'def token_hex(nbytes=None):\n'
    ' value=_values.pop(0)\n'
    ' if nbytes is not None and len(value)!=2*nbytes: raise RuntimeError("fixture token length mismatch")\n'
    ' return value\n',
    encoding="utf-8",
)

deny = fixture_root / "completion-chain-deny"
deny.mkdir(parents=True, exist_ok=True)
curl = deny / "curl"
curl.write_text('#!/usr/bin/env bash\necho "F20_L4_NETWORK_DENIED: curl" >&2\nexit 1\n', encoding="utf-8")
curl.chmod(0o755)
PY
# POST_STOP20_CALL_END l4.chain.artifact-setup

export PATH="$TMP/completion-chain-deny:$PATH"
export SCHOLAR_ZOTERO_DIR="$FIXTURE_ZOTERO_DIR"

# POST_STOP20_CALL_BEGIN l4.chain.init
bash "$SCRIPT_DIR/auto-research-state.sh" init "$CHAIN_PROJ" >/dev/null
# POST_STOP20_CALL_END l4.chain.init
# POST_STOP20_CALL_BEGIN l4.chain.set-mode
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$CHAIN_PROJ" autonomous "F20 L4 canonical completion chain" >/dev/null
# POST_STOP20_CALL_END l4.chain.set-mode

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-0
# CASE_ID: l4.chain.accept.complete-phase-0
expect_pass l4.chain.accept.complete-phase-0 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 0
# POST_STOP20_CALL_END l4.chain.complete-phase-0

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-1
# CASE_ID: l4.chain.accept.complete-phase-1
expect_pass l4.chain.accept.complete-phase-1 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 1
# POST_STOP20_CALL_END l4.chain.complete-phase-1

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-2
# CASE_ID: l4.chain.accept.complete-phase-2
expect_pass l4.chain.accept.complete-phase-2 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 2
# POST_STOP20_CALL_END l4.chain.complete-phase-2

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-3
# CASE_ID: l4.chain.accept.complete-phase-3
expect_pass l4.chain.accept.complete-phase-3 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 3
# POST_STOP20_CALL_END l4.chain.complete-phase-3

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-4
# CASE_ID: l4.chain.accept.complete-phase-4
expect_pass l4.chain.accept.complete-phase-4 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 4
# POST_STOP20_CALL_END l4.chain.complete-phase-4

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-5
# CASE_ID: l4.chain.accept.complete-phase-5
expect_pass l4.chain.accept.complete-phase-5 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 5
# POST_STOP20_CALL_END l4.chain.complete-phase-5

# POST_STOP20_CALL_BEGIN l4.chain.review-begin-phase-6
PYTHONPATH="$CHAIN_PROJ/.fixture-shim" \
  SCHOLAR_FIXTURE_TOKEN_HEX_SEQUENCE='["085f63f019172c7d39e0a843","80244723ef3a8b14b2da27dc","8d33a2a831e170b80ba414b7","5ed51c0702abf93d8c8ddb43","6d10a1dea515dc52b241cb1d","49faaee620318e9efd3a2439","1570991dbf4da26fc71fcef1"]' \
  bash "$SCRIPT_DIR/auto-research-state.sh" review-begin "$CHAIN_PROJ" 6 initial_panel generic-fixture-host >/dev/null
# POST_STOP20_CALL_END l4.chain.review-begin-phase-6
CHAIN_REVIEW_SOURCE="$(single_review_session_dir "$PREEXEC_PROJ" 06)"
CHAIN_REVIEW_DEST="$CHAIN_PROJ/review-evidence/phase-06/s-085f63f019172c7d39e0a843"
mkdir -p "$CHAIN_REVIEW_DEST/reports" "$CHAIN_REVIEW_DEST/traces"
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" correctness
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-6-correctness
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 6 s-085f63f019172c7d39e0a843 correctness \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-6-correctness
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" robustness
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-6-robustness
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 6 s-085f63f019172c7d39e0a843 robustness \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-6-robustness
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" statistical
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-6-statistical
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 6 s-085f63f019172c7d39e0a843 statistical \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-6-statistical
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" reproducibility
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-6-reproducibility
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 6 s-085f63f019172c7d39e0a843 reproducibility \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-6-reproducibility
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" style_ai_patterns
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-6-style_ai_patterns
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 6 s-085f63f019172c7d39e0a843 style_ai_patterns \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-6-style_ai_patterns
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" data_handling
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-6-data_handling
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 6 s-085f63f019172c7d39e0a843 data_handling \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-6-data_handling

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-6
# CASE_ID: l4.chain.accept.complete-phase-6
expect_pass l4.chain.accept.complete-phase-6 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 6
# POST_STOP20_CALL_END l4.chain.complete-phase-6

# POST_STOP20_CALL_BEGIN l4.chain.review-begin-phase-7
PYTHONPATH="$CHAIN_PROJ/.fixture-shim" \
  SCHOLAR_FIXTURE_TOKEN_HEX_SEQUENCE='["96f4059a54d7e0a7c3dd9432","4bf6139d435b9e5d44ffb3a5","d9a91733868a1ae2872332bd","70b5eaf70b9ca80dade24c8a","cf7f1d2141b4128c99809a9d"]' \
  bash "$SCRIPT_DIR/auto-research-state.sh" review-begin "$CHAIN_PROJ" 7 premortem_panel generic-fixture-host >/dev/null
# POST_STOP20_CALL_END l4.chain.review-begin-phase-7
CHAIN_REVIEW_SOURCE="$(single_review_session_dir "$PREMORTEM_PROJ" 07)"
CHAIN_REVIEW_DEST="$CHAIN_PROJ/review-evidence/phase-07/s-96f4059a54d7e0a7c3dd9432"
mkdir -p "$CHAIN_REVIEW_DEST/reports" "$CHAIN_REVIEW_DEST/traces"
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" identification
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-7-identification
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 7 s-96f4059a54d7e0a7c3dd9432 identification \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-7-identification
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" measurement_missingness
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-7-measurement_missingness
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 7 s-96f4059a54d7e0a7c3dd9432 measurement_missingness \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-7-measurement_missingness
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" model_robustness
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-7-model_robustness
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 7 s-96f4059a54d7e0a7c3dd9432 model_robustness \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-7-model_robustness
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" interpretation_claims
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-7-interpretation_claims
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 7 s-96f4059a54d7e0a7c3dd9432 interpretation_claims \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-7-interpretation_claims

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-7
# CASE_ID: l4.chain.accept.complete-phase-7
expect_pass l4.chain.accept.complete-phase-7 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 7
# POST_STOP20_CALL_END l4.chain.complete-phase-7

mkdir -p "$CHAIN_PROJ/analysis" "$CHAIN_PROJ/tables" "$CHAIN_PROJ/figures"
mv "$TMP/completion-chain-staged/analysis/execution-report.json" "$CHAIN_PROJ/analysis/execution-report.json"
mv "$TMP/completion-chain-staged/tables/results-registry.csv" "$CHAIN_PROJ/tables/results-registry.csv"
mv "$TMP/completion-chain-staged/figures/figure-registry.csv" "$CHAIN_PROJ/figures/figure-registry.csv"
mkdir -p "$CHAIN_PROJ/logs"
cp -R "$EXEC_PROJ/logs/." "$CHAIN_PROJ/logs/"

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-8
# CASE_ID: l4.chain.accept.complete-phase-8
expect_pass l4.chain.accept.complete-phase-8 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 8
# POST_STOP20_CALL_END l4.chain.complete-phase-8

# POST_STOP20_CALL_BEGIN l4.chain.review-begin-phase-9
PYTHONPATH="$CHAIN_PROJ/.fixture-shim" \
  SCHOLAR_FIXTURE_TOKEN_HEX_SEQUENCE='["fe212f6e914b0e00004724a9","fad70623d822a17523e7c245","a8692ac1012611577e19f1ac","16faa35d82220e09cc6262a0","1b8b59525e562a2eaca4548a"]' \
  bash "$SCRIPT_DIR/auto-research-state.sh" review-begin "$CHAIN_PROJ" 9 post_execution_panel generic-fixture-host >/dev/null
# POST_STOP20_CALL_END l4.chain.review-begin-phase-9
CHAIN_REVIEW_SOURCE="$(single_review_session_dir "$POSTEXEC_PROJ" 09)"
CHAIN_REVIEW_DEST="$CHAIN_PROJ/review-evidence/phase-09/s-fe212f6e914b0e00004724a9"
mkdir -p "$CHAIN_REVIEW_DEST/reports" "$CHAIN_REVIEW_DEST/traces"
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" statistical_results
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-9-statistical_results
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 9 s-fe212f6e914b0e00004724a9 statistical_results \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-9-statistical_results
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" robustness_consistency
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-9-robustness_consistency
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 9 s-fe212f6e914b0e00004724a9 robustness_consistency \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-9-robustness_consistency
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" sample_data_integrity
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-9-sample_data_integrity
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 9 s-fe212f6e914b0e00004724a9 sample_data_integrity \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-9-sample_data_integrity
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" interpretation_claims
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-9-interpretation_claims
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 9 s-fe212f6e914b0e00004724a9 interpretation_claims \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-9-interpretation_claims

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-9
# CASE_ID: l4.chain.accept.complete-phase-9
expect_pass l4.chain.accept.complete-phase-9 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 9
# POST_STOP20_CALL_END l4.chain.complete-phase-9

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-10
# CASE_ID: l4.chain.accept.complete-phase-10
expect_pass l4.chain.accept.complete-phase-10 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 10
# POST_STOP20_CALL_END l4.chain.complete-phase-10

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-11
# CASE_ID: l4.chain.accept.complete-phase-11
expect_pass l4.chain.accept.complete-phase-11 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 11
# POST_STOP20_CALL_END l4.chain.complete-phase-11

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-12
# CASE_ID: l4.chain.accept.complete-phase-12
expect_pass l4.chain.accept.complete-phase-12 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 12
# POST_STOP20_CALL_END l4.chain.complete-phase-12

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-13
# CASE_ID: l4.chain.accept.complete-phase-13
expect_pass l4.chain.accept.complete-phase-13 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 13
# POST_STOP20_CALL_END l4.chain.complete-phase-13

# POST_STOP20_CALL_BEGIN l4.chain.review-begin-phase-14
PYTHONPATH="$CHAIN_PROJ/.fixture-shim" \
  SCHOLAR_FIXTURE_TOKEN_HEX_SEQUENCE='["725fa00440dbc3674b6f490b","4c22beb27d6878524cf8b6c3","989c6d808960c0d85f1b5e90","12f95f2f054f71dfa6cea6f4","8ed68e5896a296220ada58ec"]' \
  bash "$SCRIPT_DIR/auto-research-state.sh" review-begin "$CHAIN_PROJ" 14 verification_panel generic-fixture-host >/dev/null
# POST_STOP20_CALL_END l4.chain.review-begin-phase-14
CHAIN_REVIEW_SOURCE="$(single_review_session_dir "$REPLICATION_PROJ" 14)"
CHAIN_REVIEW_DEST="$CHAIN_PROJ/review-evidence/phase-14/s-725fa00440dbc3674b6f490b"
mkdir -p "$CHAIN_REVIEW_DEST/reports" "$CHAIN_REVIEW_DEST/traces"
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" verify-numerics
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-14-verify-numerics
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 14 s-725fa00440dbc3674b6f490b verify-numerics \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-14-verify-numerics
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" verify-figures
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-14-verify-figures
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 14 s-725fa00440dbc3674b6f490b verify-figures \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-14-verify-figures
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" verify-logic
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-14-verify-logic
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 14 s-725fa00440dbc3674b6f490b verify-logic \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-14-verify-logic
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" verify-completeness
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-14-verify-completeness
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 14 s-725fa00440dbc3674b6f490b verify-completeness \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-14-verify-completeness

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-14
# CASE_ID: l4.chain.accept.complete-phase-14
expect_pass l4.chain.accept.complete-phase-14 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 14
# POST_STOP20_CALL_END l4.chain.complete-phase-14

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-15
# CASE_ID: l4.chain.accept.complete-phase-15
expect_pass l4.chain.accept.complete-phase-15 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 15
# POST_STOP20_CALL_END l4.chain.complete-phase-15

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-16
# CASE_ID: l4.chain.accept.complete-phase-16
expect_pass l4.chain.accept.complete-phase-16 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 16
# POST_STOP20_CALL_END l4.chain.complete-phase-16

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-17
# CASE_ID: l4.chain.accept.complete-phase-17
expect_pass l4.chain.accept.complete-phase-17 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 17
# POST_STOP20_CALL_END l4.chain.complete-phase-17

# POST_STOP20_CALL_BEGIN l4.chain.review-begin-phase-18
PYTHONPATH="$CHAIN_PROJ/.fixture-shim" \
  SCHOLAR_FIXTURE_TOKEN_HEX_SEQUENCE='["4348fa35cf6880ecc4f08dc8","8c2b21b3f9ce69e356a3bbd6","75ee2fed215d13c103f36f72","c6dfa156ab32c581c146c667","344386b4ab768fdf9ed97fe1","c00f44c2a0f12e01b971e2c8"]' \
  bash "$SCRIPT_DIR/auto-research-state.sh" review-begin "$CHAIN_PROJ" 18 adversarial_panel generic-fixture-host --extra-role survey-methods >/dev/null
# POST_STOP20_CALL_END l4.chain.review-begin-phase-18
CHAIN_REVIEW_SOURCE="$(single_review_session_dir "$FINAL_PROJ" 18)"
CHAIN_REVIEW_DEST="$CHAIN_PROJ/review-evidence/phase-18/s-4348fa35cf6880ecc4f08dc8"
mkdir -p "$CHAIN_REVIEW_DEST/reports" "$CHAIN_REVIEW_DEST/traces"
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" methods-evidence
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-18-methods-evidence
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 18 s-4348fa35cf6880ecc4f08dc8 methods-evidence \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-18-methods-evidence
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" theory-contribution
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-18-theory-contribution
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 18 s-4348fa35cf6880ecc4f08dc8 theory-contribution \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-18-theory-contribution
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" senior-editor
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-18-senior-editor
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 18 s-4348fa35cf6880ecc4f08dc8 senior-editor \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-18-senior-editor
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" interpretive-skeptic
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-18-interpretive-skeptic
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 18 s-4348fa35cf6880ecc4f08dc8 interpretive-skeptic \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-18-interpretive-skeptic
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" survey-methods
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-18-survey-methods
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 18 s-4348fa35cf6880ecc4f08dc8 survey-methods \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-18-survey-methods

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-18
# CASE_ID: l4.chain.accept.complete-phase-18
expect_pass l4.chain.accept.complete-phase-18 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 18
# POST_STOP20_CALL_END l4.chain.complete-phase-18

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-19
# CASE_ID: l4.chain.accept.complete-phase-19
expect_pass l4.chain.accept.complete-phase-19 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 19
# POST_STOP20_CALL_END l4.chain.complete-phase-19

# POST_STOP20_CALL_BEGIN l4.chain.review-begin-phase-20
PYTHONPATH="$CHAIN_PROJ/.fixture-shim" \
  SCHOLAR_FIXTURE_TOKEN_HEX_SEQUENCE='["e1a79f4cbb5aebed2376d7fd","8a8be373777e3b937b64546a"]' \
  bash "$SCRIPT_DIR/auto-research-state.sh" review-begin "$CHAIN_PROJ" 20 semantic_body_reader generic-fixture-host >/dev/null
# POST_STOP20_CALL_END l4.chain.review-begin-phase-20
CHAIN_REVIEW_SOURCE="$(single_review_session_dir "$SUBMISSION_PROJ" 20)"
CHAIN_REVIEW_DEST="$CHAIN_PROJ/review-evidence/phase-20/s-e1a79f4cbb5aebed2376d7fd"
mkdir -p "$CHAIN_REVIEW_DEST/reports" "$CHAIN_REVIEW_DEST/traces"
copy_review_role_evidence "$CHAIN_REVIEW_SOURCE" "$CHAIN_REVIEW_DEST" semantic_body_prose_reader
# POST_STOP20_CALL_BEGIN l4.chain.review-complete-phase-20-semantic_body_prose_reader
bash "$SCRIPT_DIR/auto-research-state.sh" review-complete "$CHAIN_PROJ" 20 s-e1a79f4cbb5aebed2376d7fd semantic_body_prose_reader \
  --driver-status succeeded \
  --host-task-unavailable "fixture host does not expose task identifiers" \
  --model-unavailable "fixture backend does not expose model identifiers" >/dev/null
# POST_STOP20_CALL_END l4.chain.review-complete-phase-20-semantic_body_prose_reader

# POST_STOP20_CALL_BEGIN l4.chain.complete-phase-20
# CASE_ID: l4.chain.accept.complete-phase-20
expect_pass l4.chain.accept.complete-phase-20 "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$CHAIN_PROJ" 20
# POST_STOP20_CALL_END l4.chain.complete-phase-20

# POST_STOP20_CALL_BEGIN l4.chain.next-done
# CASE_ID: l4.chain.accept.next-done
expect_pass l4.chain.accept.next-done "$CHAIN_PROJ" -- \
  bash "$SCRIPT_DIR/auto-research-state.sh" next "$CHAIN_PROJ"
# POST_STOP20_CALL_END l4.chain.next-done

harness_validate_results --checkpoint completion-tail
progress "completion-tail authoritative harness assertions passed"
if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "completion-tail" ]]; then
  exit 0
fi

harness_validate_results

END_TS="$(date +%s)"
echo "auto-research fixture test: PASS"
echo "fixture_project=$PROJ"
echo "elapsed_seconds=$((END_TS - START_TS))"
