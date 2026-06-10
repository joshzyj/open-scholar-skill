#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP="/tmp/scholar-auto-research-fixture-$$"
PROJ="$TMP/project"
START_TS="$(date +%s)"

# The fixture test exercises schema/JSON contract integrity, not codex
# cross-model review behavior. The Phase 6 + Phase 14 codex-trigger gate
# (added 2026-05-10) defaults to STRONG (RED if not dispatched), so without
# this opt-out every fixture's verify call would fail at the codex gate.
# The dedicated codex smoke suite is at tests/smoke/test-codex-trigger-auto-research.sh.
export SCHOLAR_CODEX_DEFAULT=false

progress() {
  printf '[fixture] %s\n' "$1"
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" complete "$PROJ" 0 "$PROJ/safety/safety-status.json" >/dev/null

NEXT="$(bash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ")"
case "$NEXT" in
  *"NEXT_PHASE=1"*) ;;
  *) echo "FAIL: expected NEXT_PHASE=1 after completing 0, got $NEXT" >&2; exit 1 ;;
esac

if bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$PROJ" >/dev/null 2>&1; then
  echo "FAIL: phase 1 verify should fail without required outputs" >&2
  exit 1
fi

BAD_PHASE0_STATUS_PROJ="$TMP/bad-phase0-status-project"
mkdir -p "$BAD_PHASE0_STATUS_PROJ/safety"
printf '{"safety_status":"PASS","files_scanned":1,"no_data_declared":false,"high_risk_unresolved":0}\n' > "$BAD_PHASE0_STATUS_PROJ/safety/safety-status.json"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$BAD_PHASE0_STATUS_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 0 verify should fail when status_by_file is missing" >&2
  exit 1
fi

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$RQ_PROJ" >/dev/null

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$CUSTOM_RQ_PROJ" >/dev/null

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$FALLBACK_RQ_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_RQ_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 1 verify should fail on placeholder research question" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_CUSTOM_RQ_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 1 verify should fail when a custom journal has no journal_profile_resolution" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_IMPORTED_BUILTIN_RQ_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 1 verify should fail when a built-in journal is mislabeled as imported_custom" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_RQ_FATAL_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 1 verify should fail when selected candidate has fatal flaw" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_RQ_JOURNAL_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 1 verify should fail when journal editor review is missing" >&2
  exit 1
fi

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BRAINSTORM_DATA_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 1 "$BAD_BRAINSTORM_NULL_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 1 verify should fail when DATA-mode selected RQ has NULL signal without user override" >&2
  exit 1
fi

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
    "ready_for_phase_3": True
}
(proj / "literature/lit-theory-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
bash "$SCRIPT_DIR/auto-research-verify.sh" 2 "$LIT_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 2 "$BAD_LIT_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 2 verify should fail when lit-theory.md is not routed through scholar-write" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 2 "$BAD_LIT_PROTOCOL_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 2 verify should fail when the literature protocol proof is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 2 "$BAD_LIT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 2 verify should fail on thin literature/theory artifacts" >&2
  exit 1
fi

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$DESIGN_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$BAD_DESIGN_CAUSAL_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 3 verify should fail when a fixed-effects design skips scholar-causal" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$BAD_DESIGN_HYP_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 3 verify should fail when Phase 2 hypotheses are not covered by models" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$BAD_DESIGN_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 3 verify should fail on incomplete design artifacts" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 3 "$UNRESOLVED_DESIGN_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 3 verify should fail with unresolved design evaluation criticals" >&2
  exit 1
fi

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$DATA_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$BAD_DATA_MODEL_VAR_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 4 verify should fail when a model-spec variable is missing from the dictionary" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$BAD_DATA_DISPLAY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 4 verify should fail when reader-facing display labels are left as raw machine variable names" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$BAD_DATA_SAFETY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 4 verify should fail when existing data have no safety scan" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 4 "$BAD_DATA_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 4 verify should fail on incomplete data/measurement artifacts" >&2
  exit 1
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 5 "$ANALYSIS_PLAN_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 5 "$BAD_ANALYSIS_HYP_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 5 verify should fail when planned specs do not cover hypotheses" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 5 "$BAD_ANALYSIS_DAG_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 5 verify should fail on invalid script dependency order" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 5 "$BAD_ANALYSIS_PLAN_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 5 verify should fail on executed or incomplete analysis plan artifacts" >&2
  exit 1
fi

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$PREEXEC_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 6 verify should fail without scholar-code-review provenance" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_DAG_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 6 verify should fail when script DAG review is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_ROLE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 6 verify should fail when a required independent role is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 6 verify should fail on stale scripts inventory hash" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_SCRIPT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 6 verify should fail when a planned script is not reviewed" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 6 "$BAD_PREEXEC_REREVIEW_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 6 verify should fail when fixed blockers do not pass re-review" >&2
  exit 1
fi

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$PREMORTEM_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 7 verify should fail when scholar-analyze premortem provenance is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_ROLE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 7 verify should fail when a premortem reviewer role is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_PROVENANCE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 7 verify should fail on inline reviewer provenance" >&2
  exit 1
fi

BAD_PREMORTEM_HASH_PROJ="$TMP/bad-premortem-hash-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_HASH_PROJ"
printf '\nLate unreviewed analysis-plan change.\n' >> "$BAD_PREMORTEM_HASH_PROJ/analysis/analysis-plan.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 7 verify should fail on stale source hashes" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_RISK_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 7 verify should fail on unresolved blocking premortem risk" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_LIMIT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 7 verify should fail when a major risk is accepted as a limitation" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_NULL_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 7 verify should fail when null-falsification rules are not precommitted" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_REPORTING_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 7 verify should fail when reporting-depth checklist misses a reporting mitigation" >&2
  exit 1
fi

BAD_PREMORTEM_EXEC_PROJ="$TMP/bad-premortem-exec-project"
cp -R "$PREMORTEM_PROJ" "$BAD_PREMORTEM_EXEC_PROJ"
mkdir -p "$BAD_PREMORTEM_EXEC_PROJ/analysis"
printf '{"status":"already executed"}\n' > "$BAD_PREMORTEM_EXEC_PROJ/analysis/execution-report.json"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 7 "$BAD_PREMORTEM_EXEC_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 7 verify should fail if execution artifacts exist before Phase 8" >&2
  exit 1
fi

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
printf 'figure fixture\n' > "$EXEC_PROJ/figures/event-study.png"
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$EXEC_PROJ" >/dev/null

BAD_EXEC_ENGINE_PROJ="$TMP/bad-execution-engine-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_ENGINE_PROJ"
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail when scholar-analyze execution provenance is missing" >&2
  exit 1
fi

BAD_EXEC_STACK_PROJ="$TMP/bad-execution-stack-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_STACK_PROJ"
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_STACK_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail when quantitative analysis stack drops modelsummary without justification" >&2
  exit 1
fi

BAD_EXEC_VIZ_PROJ="$TMP/bad-execution-viz-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_VIZ_PROJ"
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_VIZ_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail when ggplot2 execution skips viz_setting.R and theme_Publication" >&2
  exit 1
fi

BAD_EXEC_PHASE7_DRIFT_PROJ="$TMP/bad-execution-phase7-drift-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_PHASE7_DRIFT_PROJ"
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_PHASE7_DRIFT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail when Phase 7 source hashes are stale even if execution hashes are recomputed" >&2
  exit 1
fi

BAD_EXEC_TRACE_PROJ="$TMP/bad-execution-trace-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_TRACE_PROJ"
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_TRACE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail when command trace logs are missing" >&2
  exit 1
fi

BAD_EXEC_ARTIFACT_PROJ="$TMP/bad-execution-artifact-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_ARTIFACT_PROJ"
printf 'unregistered table artifact\n' > "$BAD_EXEC_ARTIFACT_PROJ/tables/unregistered-diagnostic.csv"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_ARTIFACT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail on unregistered table artifacts" >&2
  exit 1
fi

BAD_EXEC_HASH_PROJ="$TMP/bad-execution-hash-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_HASH_PROJ"
printf '\nLate unreviewed inventory change.\n' >> "$BAD_EXEC_HASH_PROJ/analysis/scripts-inventory.json"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail on stale execution source hashes" >&2
  exit 1
fi

BAD_EXEC_EXIT_PROJ="$TMP/bad-execution-exit-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_EXIT_PROJ"
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_EXIT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail on nonzero exit code" >&2
  exit 1
fi

BAD_EXEC_SPEC_PROJ="$TMP/bad-execution-spec-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_SPEC_PROJ"
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_SPEC_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail when a planned spec is missing from results registry" >&2
  exit 1
fi

BAD_EXEC_OUTPUT_PROJ="$TMP/bad-execution-output-project"
cp -R "$EXEC_PROJ" "$BAD_EXEC_OUTPUT_PROJ"
python3 - "$BAD_EXEC_OUTPUT_PROJ/data/processed/analytic-sample.rds" <<'PY'
import os
import sys
os.remove(sys.argv[1])
PY
if bash "$SCRIPT_DIR/auto-research-verify.sh" 8 "$BAD_EXEC_OUTPUT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 8 verify should fail when an expected output is missing" >&2
  exit 1
fi

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$POSTEXEC_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail when scholar-verify stage1 provenance is missing" >&2
  exit 1
fi

BAD_POSTEXEC_JSON_PROJ="$TMP/bad-postexec-json-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_JSON_PROJ"
printf '{}\n' > "$BAD_POSTEXEC_JSON_PROJ/review/post-execution-review.json"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_JSON_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail on placeholder post-execution review JSON" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_ROLE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail when a post-execution reviewer role is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_VALUE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail when reviewed spec values differ from results registry" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_FIGURE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail when completed figures lack visual inspection" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_RAW_VERIFY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail when raw output verification misses model output tables" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_CARRY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail when Phase 7 constraints are not carried forward" >&2
  exit 1
fi

BAD_POSTEXEC_HASH_PROJ="$TMP/bad-postexec-hash-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_HASH_PROJ"
printf 'S3,M1,Y,X,0.1,0.1,0.5,100,completed,tables/model-results.csv\n' >> "$BAD_POSTEXEC_HASH_PROJ/tables/results-registry.csv"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail on stale post-execution source hashes" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_ROUTE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail when route_back_phase is set" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_UNEXPECTED_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail when weak/unexpected specs are not classified" >&2
  exit 1
fi

BAD_POSTEXEC_MARKDOWN_PROJ="$TMP/bad-postexec-markdown-project"
cp -R "$POSTEXEC_PROJ" "$BAD_POSTEXEC_MARKDOWN_PROJ"
printf 'A blocking invalid result remains unresolved even though JSON says pass.\n' > "$BAD_POSTEXEC_MARKDOWN_PROJ/review/post-execution-review.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 9 "$BAD_POSTEXEC_MARKDOWN_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 9 verify should fail on markdown/JSON contradiction" >&2
  exit 1
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$SANITY_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 10 verify should fail when runtime engine provenance is invalid" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_CONSTRAINT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 10 verify should fail when Phase 9 constraints are not carried forward" >&2
  exit 1
fi

BAD_SANITY_PHASE8_MANIFEST_PROJ="$TMP/bad-sanity-phase8-manifest-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_PHASE8_MANIFEST_PROJ"
python3 - "$BAD_SANITY_PHASE8_MANIFEST_PROJ/analysis/execution-report.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["artifact_manifest"][0]["sha256"] = "0" * 64
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
if bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_PHASE8_MANIFEST_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 10 verify should fail on stale Phase 8 artifact manifest" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_RECON_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 10 verify should fail on inconsistent lock-candidate reconciliation" >&2
  exit 1
fi

BAD_SANITY_HASH_PROJ="$TMP/bad-sanity-hash-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_HASH_PROJ"
printf 'S3,M1,Y,X,0.1,0.1,0.5,100,completed,tables/model-results.csv\n' >> "$BAD_SANITY_HASH_PROJ/tables/results-registry.csv"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 10 verify should fail on stale runtime sanity hashes" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_PLAUS_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 10 verify should fail on failed plausibility check" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_DRIFT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 10 verify should fail on unresolved PAP drift" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_INV_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 10 verify should fail on incomplete artifact inventory" >&2
  exit 1
fi

BAD_SANITY_MARKDOWN_PROJ="$TMP/bad-sanity-markdown-project"
cp -R "$SANITY_PROJ" "$BAD_SANITY_MARKDOWN_PROJ"
printf 'A critical drift remains unresolved even though JSON says pass.\n' > "$BAD_SANITY_MARKDOWN_PROJ/verify/runtime-sanity.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 10 "$BAD_SANITY_MARKDOWN_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 10 verify should fail on markdown/JSON contradiction" >&2
  exit 1
fi

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$LOCK_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when lock engine provenance is invalid" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_LATEST_FLAG_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when manifest latest_matches is false" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_STAGE1_PROVENANCE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when Stage 1 scanner provenance is invalid" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_STAGE1_VERDICT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when manifest Stage 1 verdict disagrees with Stage 1 report" >&2
  exit 1
fi

BAD_LOCK_LATEST_PROJ="$TMP/bad-lock-latest-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_LATEST_PROJ"
printf 'OTHER-LOCK\n' > "$BAD_LOCK_LATEST_PROJ/results-locked/LATEST.txt"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_LATEST_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when LATEST.txt does not match lock_id" >&2
  exit 1
fi

BAD_LOCK_MISSING_PROJ="$TMP/bad-lock-missing-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_MISSING_PROJ"
python3 - "$BAD_LOCK_MISSING_PROJ/results-locked/manifest.json" "$BAD_LOCK_MISSING_PROJ/verify/stage1-verify.json" <<'PY'
import json
import sys
manifest_path, stage1_path = sys.argv[1:3]
manifest = json.loads(open(manifest_path, encoding="utf-8").read())
stage1 = json.loads(open(stage1_path, encoding="utf-8").read())
manifest["locked_artifacts"] = manifest["locked_artifacts"][:-1]
stage1["checked_artifacts"] = stage1["checked_artifacts"][:-1]
open(manifest_path, "w", encoding="utf-8").write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
open(stage1_path, "w", encoding="utf-8").write(json.dumps(stage1, indent=2, sort_keys=True) + "\n")
PY
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_MISSING_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when manifest omits a Phase 10 lock candidate" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when manifest content changes without manifest_sha256 update" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_STAGE1_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when Stage 1 artifact check fails" >&2
  exit 1
fi

BAD_LOCK_EXTRA_PROJ="$TMP/bad-lock-extra-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_EXTRA_PROJ"
printf 'unmanifested\n' > "$BAD_LOCK_EXTRA_PROJ/results-locked/LOCK-20260429-001/unmanifested-extra.csv"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_EXTRA_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when active lock directory has an unmanifested file" >&2
  exit 1
fi

BAD_LOCK_SOURCE_DRIFT_PROJ="$TMP/bad-lock-source-drift-project"
cp -R "$LOCK_PROJ" "$BAD_LOCK_SOURCE_DRIFT_PROJ"
printf 'spec_id,model_id,outcome,predictor,estimate,std_error,p_value,n,status,output_file\nS1,M1,Y,X,9,9,0.9,999,completed,tables/model-results.csv\n' > "$BAD_LOCK_SOURCE_DRIFT_PROJ/tables/results-registry.csv"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_SOURCE_DRIFT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when source artifacts drift after lock" >&2
  exit 1
fi

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
manifest["locked_artifacts"][0]["lock_status"] = "source_locked"
clone = dict(manifest)
clone.pop("manifest_sha256", None)
manifest["manifest_sha256"] = hashlib.sha256(json.dumps(clone, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
stage1["manifest_sha256"] = manifest["manifest_sha256"]
stage1["input_manifest_sha256"] = manifest["manifest_sha256"]
stage1["checked_artifacts"][0]["locked_path"] = manifest["locked_artifacts"][0]["locked_path"]
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
stage1_path.write_text(json.dumps(stage1, indent=2, sort_keys=True) + "\n")
PY
if bash "$SCRIPT_DIR/auto-research-verify.sh" 11 "$BAD_LOCK_OUTSIDE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 11 verify should fail when locked_path is outside active lock directory" >&2
  exit 1
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
            "results_callout": "Table 2 shows that the primary specification is negative and that weaker robustness evidence remains subordinate to the headline estimate."
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
    "Table 2 also shows why the manuscript frames robustness evidence cautiously. Model 2, the timing-oriented specification, remains negative at -0.080 with a standard error of 0.050 and a p-value of 0.110 [@work02], so it is directionally consistent without being uniformly strong. By contrast, Model 3, the attrition-weighted specification, is -0.090 with a standard error of 0.045 and a p-value of 0.046 [@work03], which keeps the bounded association in view while preserving uncertainty. These side-by-side rows are why the Results section reports a negative pattern with uneven robustness instead of a claim of uniform confirmation. The weaker robustness estimate is treated as a boundary on the claim rather than as a finding to smooth over. Primary claims must stay aligned with reviewed evidence. All numerical claims must stay aligned with reviewed evidence.",
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
claim_anchor_comments = "\n".join([
    "<!-- CLAIM_ANCHOR: The primary specification S1 shows a negative association between parental job loss and adolescent educational expectations, with estimate -0.120, standard error 0.040, p-value 0.003, and n 1200 [@work01]. -->",
    "<!-- CLAIM_ANCHOR: The robustness specification S2 points in the same direction with estimate -0.080, standard error 0.050, p-value 0.110, and n 1200 [@work02] -->",
    "<!-- CLAIM_ANCHOR: The attrition-weighted robustness specification S3 remains negative with estimate -0.090, standard error 0.045, p-value 0.046, and n 1200 [@work03] -->",
])
manuscript = "\n\n".join([
    "# Parental Job Loss and Adolescent Educational Expectations",
    "Keywords: parental job loss; educational expectations; family inequality; panel data",
    "## Abstract\n" + abstract,
    "## Introduction\n" + "\n\n".join(intro_paragraphs),
    "## Background\n" + "\n\n".join(lit_paragraphs),
    "## Data and Methods\n" + "\n\n".join(methods_paragraphs),
    "## Results\n" + "\n".join(anchors) + "\n\n" + claim_anchor_comments + "\n\n" + display_descriptive_block + "\n\n" + display_table_block + "\n\n" + display_figure_block + "\n\n" + "\n\n".join(results_paragraphs),
    "## Discussion\n" + "\n\n".join(discussion_paragraphs),
    "## Conclusion\n" + "\n\n".join(conclusion_paragraphs),
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
locked_result_claims = []
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
        "sections": {section: {"words": count, "min_words": section_budget[section]["min_words"], "status": "PASS"} for section, count in counts.items()}
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 12 "$DRAFT_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$DRAFT_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 12 "$BAD_BLUEPRINT_JOURNAL_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when blueprint journal structure collapses a split-close journal into a combined close" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_QUALITY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when draft quality gate is not PASS" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_REPETITION_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when manuscript repeats substantive sentences too often" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_ANCHOR_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when a locked artifact anchor is missing" >&2
  exit 1
fi

BAD_DRAFT_BIB_PROJ="$TMP/bad-draft-bib-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_BIB_PROJ"
printf '\nUnresolved citation [@missingkey].\n' >> "$BAD_DRAFT_BIB_PROJ/manuscript/manuscript-draft.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_BIB_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when draft cites a missing BibTeX key" >&2
  exit 1
fi

BAD_DRAFT_PLACEHOLDER_PROJ="$TMP/bad-draft-placeholder-project"
cp -R "$DRAFT_PROJ" "$BAD_DRAFT_PLACEHOLDER_PROJ"
printf '\nTBD\n' >> "$BAD_DRAFT_PLACEHOLDER_PROJ/manuscript/manuscript-draft.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_PLACEHOLDER_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when draft contains placeholder text" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_CALLOUT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 13 verify should fail when Results drops the numbered table callout" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_PRECISION_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when Results exposes raw scientific-notation precision" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_POLISH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when scholar-polish leaves high-severity markers" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_BUDGET_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when manuscript misses journal section budget" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_NUMERIC_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when a locked numeric value is drifted in the draft" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_CLAIM_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when draft violates Phase 9 claim constraints" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 13 "$BAD_DRAFT_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 12 verify should fail when scholar-write drafting engine metadata is absent or wrong" >&2
  exit 1
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
            "source_artifact": source_claim["source_path"],
            "locked_path": source_claim["locked_path"],
            "claim_id": row["claim_id"],
            "row_index": row["row_index"],
            "spec_id": row["spec_id"],
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$VERIFY_MANUSCRIPT_PROJ" >/dev/null

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
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$ROUTE_STATE_PROJ" "$pid" "$ROUTE_STATE_PROJ/artifacts/phase-$pid.txt" >/dev/null
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
bash "$SCRIPT_DIR/auto-research-state.sh" complete "$ROUTE_STATE_PROJ" 13 "$ROUTE_STATE_PROJ/artifacts/phase-13.txt" >/dev/null
ROUTE_NEXT_14="$(bash "$SCRIPT_DIR/auto-research-state.sh" next "$ROUTE_STATE_PROJ")"
case "$ROUTE_NEXT_14" in
  *"NEXT_PHASE=14"*"REASON=stale"* ) ;;
  *) echo "FAIL: after completing route target, downstream Phase 14 should remain stale, got $ROUTE_NEXT_14" >&2; exit 1 ;;
esac
bash "$SCRIPT_DIR/auto-research-state.sh" complete "$ROUTE_STATE_PROJ" 14 "$ROUTE_STATE_PROJ/artifacts/phase-14.txt" >/dev/null
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_ROLE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 13 verify should fail when a scholar-verify agent role is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_AGENT_SCOPE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 13 verify should fail when an agent omits its required verification scope" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_AGENT_DUP_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 13 verify should fail when agents reuse a task_invocation_id" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_STAGE1_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 13 verify should fail when Stage 1 omits a reader-facing locked artifact" >&2
  exit 1
fi

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
    "spec_id": "S1",
    "claim_id": "unexpected-row-claim",
    "verdict": "PASS"
}]
report["stage_2_manuscript_to_prose"]["claims_scanned"] = len(report["stage_2_manuscript_to_prose"]["checked"])
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
if bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_STAGE2_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 14 verify should fail when Stage 2 invents row-level claims for a regression-table manuscript" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_FIGURE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 13 verify should fail when figure visual inspection is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_LIVE_READ_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 13 verify should fail when input_artifacts_read includes a live table path" >&2
  exit 1
fi

BAD_VERIFY_STAGE2_VALUE_PROJ="$TMP/bad-verify-stage2-value-project"
cp -R "$VERIFY_MANUSCRIPT_PROJ" "$BAD_VERIFY_STAGE2_VALUE_PROJ"
python3 - "$BAD_VERIFY_STAGE2_VALUE_PROJ/verify/manuscript-verification.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["stage_2_manuscript_to_prose"]["checked"] = [{
    "source_artifact": "tables/model-results.csv",
    "spec_id": "S1",
    "claim_id": "unexpected-row-value",
    "estimate": "0.120",
    "verdict": "PASS"
}]
report["stage_2_manuscript_to_prose"]["claims_scanned"] = len(report["stage_2_manuscript_to_prose"]["checked"])
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
if bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_STAGE2_VALUE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 14 verify should fail when Stage 2 reports row values for a regression-table manuscript" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 14 "$BAD_VERIFY_STAGE_DEGRADED_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 13 verify should fail when a verification stage is degraded" >&2
  exit 1
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$CITATION_PROJ" >/dev/null

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
FAIL_CITATION_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$FAIL_CITATION_PROJ" 2>&1 || true)"
case "$FAIL_CITATION_OUT" in
  *"route_back_phase=13"* ) ;;
  *) echo "FAIL: Phase 15 structured FAIL report should expose route_back_phase=13, got $FAIL_CITATION_OUT" >&2; exit 1 ;;
esac

ROUTE_STATE_14_PROJ="$TMP/route-state-14-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_14_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_14_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_14_PROJ/artifacts" "$ROUTE_STATE_14_PROJ/citation"
for pid in $(seq 0 14); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_14_PROJ/artifacts/phase-$pid.txt"
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$ROUTE_STATE_14_PROJ" "$pid" "$ROUTE_STATE_14_PROJ/artifacts/phase-$pid.txt" >/dev/null
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_EXPORT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 14 verify should fail when exported references omit a cited key" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_REFERENCE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 14 verify should fail when a cited reference is unverified" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_CLAIM_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 14 verify should fail when a claim is unsupported" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_ANCHOR_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 14 verify should fail when a claim-source record is not anchored to manuscript text" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_LOCATOR_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 14 verify should fail when a locator-required claim lacks a source locator" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_RETRACTION_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 14 verify should fail when a cited work is retracted" >&2
  exit 1
fi

BAD_CITATION_PLACEHOLDER_PROJ="$TMP/bad-citation-placeholder-project"
cp -R "$CITATION_PROJ" "$BAD_CITATION_PLACEHOLDER_PROJ"
printf '\nSOURCE NEEDED\n' >> "$BAD_CITATION_PLACEHOLDER_PROJ/manuscript/manuscript-draft.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 15 "$BAD_CITATION_PLACEHOLDER_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 14 verify should fail when manuscript contains unresolved source placeholder text" >&2
  exit 1
fi

ETHICS_PROJ="$TMP/ethics-project"
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
                "tool": "Codex",
                "provider": "OpenAI",
                "model_or_version": "Codex CLI session model",
                "stage_used": "workflow design and validation",
                "task_performed": "contract design, fixture construction, and validation checks",
                "data_type_shared": "project structure, code, manuscript excerpts, aggregate non-identifying artifacts",
                "sensitivity": "Low"
                ,"date_used": "2026-04-30",
                "cloud_or_local": "cloud"
            }
        ],
        "statement": "The authors used AI-assisted coding and writing tools, including Codex, to help structure workflow checks, draft non-substantive disclosure language, and validate code paths. No personally identifiable participant data or restricted microdata were shared with AI tools. All AI-assisted content, code, citations, interpretations, and declarations were reviewed and verified by the human authors before inclusion in the manuscript.",
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
The authors used AI-assisted coding and writing tools, including Codex, to help structure workflow checks, draft non-substantive disclosure language, and validate code paths. No personally identifiable participant data or restricted microdata were shared with AI tools. Human authors reviewed all AI-assisted content before inclusion.

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
bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$ETHICS_PROJ" >/dev/null

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
FAIL_ETHICS_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$FAIL_ETHICS_PROJ" 2>&1 || true)"
case "$FAIL_ETHICS_OUT" in
  *"route_back_phase=4"* ) ;;
  *) echo "FAIL: Phase 15 structured FAIL report should expose route_back_phase=4, got $FAIL_ETHICS_OUT" >&2; exit 1 ;;
esac

ROUTE_STATE_15_PROJ="$TMP/route-state-15-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_15_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_15_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_15_PROJ/artifacts" "$ROUTE_STATE_15_PROJ/ethics"
for pid in $(seq 0 15); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_15_PROJ/artifacts/phase-$pid.txt"
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$ROUTE_STATE_15_PROJ" "$pid" "$ROUTE_STATE_15_PROJ/artifacts/phase-$pid.txt" >/dev/null
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when scholar-ethics engine metadata is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_ENGINE_CAPABILITY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when scholar-ethics capability flags are incomplete" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_OPEN_ENGINE_CAPABILITY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when scholar-open capability flags are incomplete" >&2
  exit 1
fi

BAD_ETHICS_HASH_PROJ="$TMP/bad-ethics-hash-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_HASH_PROJ"
printf '\nMinor manuscript drift after ethics audit.\n' >> "$BAD_ETHICS_HASH_PROJ/manuscript/manuscript-draft.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when manuscript hash is stale" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_IRB_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when IRB status is pending" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_DATA_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when data availability sharing mode conflicts with data status" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_AI_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when AI disclosure lacks human review" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_CREDIT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when CRediT roles are missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_REPLICATION_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when replication handoff is not ready" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_PLACEHOLDER_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when ethics JSON contains bracket placeholders" >&2
  exit 1
fi

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
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_RESTRICTED_PUBLIC_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when restricted data is declared public-data-full" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_NO_AI_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when auto-research claims no AI tools were used" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_EMPTY_TOOL_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when AI tool inventory contains an empty object" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_CONSENT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when restricted human data has consent_status not-applicable" >&2
  exit 1
fi

BAD_ETHICS_MD_MISMATCH_PROJ="$TMP/bad-ethics-md-mismatch-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_MD_MISMATCH_PROJ"
printf '\nA critical unresolved conflict remains open despite the JSON pass status.\n' >> "$BAD_ETHICS_MD_MISMATCH_PROJ/ethics/ethics-open-science.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_MD_MISMATCH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when markdown contradicts JSON pass status" >&2
  exit 1
fi

BAD_ETHICS_CREDIT_ROLE_PROJ="$TMP/bad-ethics-credit-role-project"
cp -R "$ETHICS_PROJ" "$BAD_ETHICS_CREDIT_ROLE_PROJ"
python3 - "$BAD_ETHICS_CREDIT_ROLE_PROJ/ethics/ethics-open-science.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
report = json.loads(path.read_text())
report["authorship_credit"]["credit_roles"] = ["Author 1"]
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
if bash "$SCRIPT_DIR/auto-research-verify.sh" 16 "$BAD_ETHICS_CREDIT_ROLE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 15 verify should fail when CRediT roles are placeholders or invalid" >&2
  exit 1
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$REPLICATION_PROJ" >/dev/null

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
FAIL_REPLICATION_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$FAIL_REPLICATION_PROJ" 2>&1 || true)"
case "$FAIL_REPLICATION_OUT" in
  *"route_back_phase=11"* ) ;;
  *) echo "FAIL: Phase 16 structured FAIL report should expose route_back_phase=11, got $FAIL_REPLICATION_OUT" >&2; exit 1 ;;
esac

ROUTE_STATE_16_PROJ="$TMP/route-state-16-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_16_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_16_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_16_PROJ/artifacts" "$ROUTE_STATE_16_PROJ/replication-package"
for pid in $(seq 0 16); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_16_PROJ/artifacts/phase-$pid.txt"
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$ROUTE_STATE_16_PROJ" "$pid" "$ROUTE_STATE_16_PROJ/artifacts/phase-$pid.txt" >/dev/null
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
printf '{}\n' > "$BAD_REPLICATION_REPORT_PROJ/replication-package/replication-report.json"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_REPORT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when replication report is empty" >&2
  exit 1
fi

BAD_REPLICATION_README_PROJ="$TMP/bad-replication-readme-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_README_PROJ"
printf '\nTBD [Paper Title]\n' >> "$BAD_REPLICATION_README_PROJ/replication-package/README.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_README_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when README contains placeholders" >&2
  exit 1
fi

BAD_REPLICATION_MANIFEST_PROJ="$TMP/bad-replication-manifest-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_MANIFEST_PROJ"
printf 'unlisted file\n' > "$BAD_REPLICATION_MANIFEST_PROJ/replication-package/unlisted.txt"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_MANIFEST_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when MANIFEST omits a package file" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_MODE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when replication_mode conflicts with Phase 15 sharing mode" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_CLEAN_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when public-data clean-room reproduction fails" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_LOCK_COVERAGE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when a locked artifact is not covered" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_SCRIPT_COVERAGE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when script coverage omits a Phase 8 executed script" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_SCRIPT_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when script coverage source_hash differs from Phase 8" >&2
  exit 1
fi

BAD_REPLICATION_PATH_PROJ="$TMP/bad-replication-path-project"
cp -R "$REPLICATION_PROJ" "$BAD_REPLICATION_PATH_PROJ"
printf '\nLocal path leak: /Users/example/project/data.csv\n' >> "$BAD_REPLICATION_PATH_PROJ/replication-package/README.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 17 "$BAD_REPLICATION_PATH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 16 verify should fail when package text contains local absolute paths" >&2
  exit 1
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
    ("Q5", "methods-specialist", True, "ACCEPT"),
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
    "methods-specialist": "peer-reviewer-survey-methods",
}
reviewer_reports = []
# Improvement A (2026-05-03) — fixture must satisfy contribution_locator
# consensus. All four reviewers quote the same headline-contribution
# sentence so cross-reviewer Jaccard >= 0.7 holds for every pair.
contribution_sentence = (
    "The paper demonstrates that exposure to neighborhood violence increases "
    "adolescent depressive symptoms by 0.34 standard deviations using a "
    "sibling fixed-effects design."
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
    "methods-specialist": (
        "The methods-specialist review checked the survey-data design, the Data and Methods section, and Table 1's regression layout. "
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
        "role": "methods-specialist",
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$QUALITY_PROJ" >/dev/null

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
FAIL_QUALITY_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$FAIL_QUALITY_PROJ" 2>&1 || true)"
case "$FAIL_QUALITY_OUT" in
  *"route_back_phase=12"* ) ;;
  *) echo "FAIL: Phase 17 structured FAIL report should expose route_back_phase=12, got $FAIL_QUALITY_OUT" >&2; exit 1 ;;
esac

ROUTE_STATE_17_PROJ="$TMP/route-state-17-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_17_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_17_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_17_PROJ/artifacts" "$ROUTE_STATE_17_PROJ/quality"
for pid in $(seq 0 17); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_17_PROJ/artifacts/phase-$pid.txt"
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$ROUTE_STATE_17_PROJ" "$pid" "$ROUTE_STATE_17_PROJ/artifacts/phase-$pid.txt" >/dev/null
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
printf '{}\n' > "$BAD_QUALITY_REPORT_PROJ/quality/manuscript-quality.json"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_REPORT_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 17 verify should fail when quality report is empty" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_LOW_SCORE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 17 verify should fail when a quality dimension is below threshold" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_POLISH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 17 verify should fail when scholar-polish scan requires route-back" >&2
  exit 1
fi

BAD_QUALITY_HASH_PROJ="$TMP/bad-quality-hash-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_HASH_PROJ"
printf '\nLate manuscript edit after quality review.\n' >> "$BAD_QUALITY_HASH_PROJ/manuscript/manuscript-draft.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 17 verify should fail when manuscript hash is stale" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_REVIEWER_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 17 verify should fail when a required reviewer role is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_REVIEWER_TASK_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 17 verify should fail when reviewer task IDs are duplicated" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_REVIEWER_FILE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 17 verify should fail when reviewer report file lacks provenance tokens" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_BLOCKER_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 17 verify should fail when non-overridable blockers remain" >&2
  exit 1
fi

BAD_QUALITY_MD_PROJ="$TMP/bad-quality-md-project"
cp -R "$QUALITY_PROJ" "$BAD_QUALITY_MD_PROJ"
printf '# Quality\n\nPASS.\n' > "$BAD_QUALITY_MD_PROJ/quality/manuscript-quality.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 18 "$BAD_QUALITY_MD_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 17 verify should fail when markdown summary is too thin" >&2
  exit 1
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
Codex assisted with code checks, format checks, and non-substantive drafting support under human review, as documented in the ethics report.

## Competing Interests
The authors declare no competing interests.
"""
write("final/manuscript-final.md", final_md)
(proj / "final/figures").mkdir(parents=True, exist_ok=True)
(proj / "final/figures/event-study.png").write_bytes((proj / "figures/event-study.png").read_bytes())

with zipfile.ZipFile(proj / "final/manuscript-final.docx", "w") as zf:
    zf.writestr("[Content_Types].xml", "<?xml version='1.0' encoding='UTF-8'?><Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Default Extension='xml' ContentType='application/xml'/><Override PartName='/word/document.xml' ContentType='application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml'/></Types>")
    zf.writestr("_rels/.rels", "<?xml version='1.0' encoding='UTF-8'?><Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument' Target='word/document.xml'/></Relationships>")
    zf.writestr("word/document.xml", "<?xml version='1.0' encoding='UTF-8'?><w:document xmlns:w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'><w:body><w:p><w:r><w:t>Parental Job Loss and Adolescent Educational Expectations</w:t></w:r></w:p></w:body></w:document>")

write("final/manuscript-final.tex", "\\documentclass{article}\n\\begin{document}\nParental Job Loss and Adolescent Educational Expectations\n\\end{document}\n")
write("final/manuscript-final.pdf", b"%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n", binary=True)
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$FINAL_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_JOURNAL_POLICY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when final assembly claims the wrong journal table-placement policy" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_RAW_HTML_TABLE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when editable-text final markdown contains a raw HTML table" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_PROVENANCE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when final-manifest journal_profile_resolution drifts from the blueprint" >&2
  exit 1
fi

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
FAIL_FINAL_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$FAIL_FINAL_PROJ" 2>&1 || true)"
case "$FAIL_FINAL_OUT" in
  *"route_back_phase=19"* ) ;;
  *) echo "FAIL: Phase 19 structured FAIL report should expose route_back_phase=19, got $FAIL_FINAL_OUT" >&2; exit 1 ;;
esac

ROUTE_STATE_18_PROJ="$TMP/route-state-18-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_18_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_18_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_18_PROJ/artifacts" "$ROUTE_STATE_18_PROJ/final"
for pid in $(seq 0 18); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_18_PROJ/artifacts/phase-$pid.txt"
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$ROUTE_STATE_18_PROJ" "$pid" "$ROUTE_STATE_18_PROJ/artifacts/phase-$pid.txt" >/dev/null
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
printf '{}\n' > "$BAD_FINAL_MANIFEST_PROJ/final/final-manifest.json"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_MANIFEST_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when final manifest is empty" >&2
  exit 1
fi

BAD_FINAL_HASH_PROJ="$TMP/bad-final-hash-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_HASH_PROJ"
printf '\nLate final edit.\n' >> "$BAD_FINAL_HASH_PROJ/final/manuscript-final.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when final md hash is stale" >&2
  exit 1
fi

BAD_FINAL_SOURCE_PROJ="$TMP/bad-final-source-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_SOURCE_PROJ"
printf '\nLate draft edit after final assembly.\n' >> "$BAD_FINAL_SOURCE_PROJ/manuscript/manuscript-draft.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_SOURCE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when source manuscript hash is stale" >&2
  exit 1
fi

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
manifest["output_hashes"]["docx"] = hashlib.sha256(docx_path.read_bytes()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_DOCX_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when DOCX is not a valid Word zip" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_SAMESOURCE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when same-source proof is false" >&2
  exit 1
fi

BAD_FINAL_LATEST_PROJ="$TMP/bad-final-latest-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_LATEST_PROJ"
printf '2026-04-30T153013Z-v001\n' > "$BAD_FINAL_LATEST_PROJ/final/LATEST.txt"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_LATEST_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when final/LATEST.txt does not match version_id" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_VERSION_COPY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when a versioned final copy is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_VERSION_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when a versioned final copy differs from canonical" >&2
  exit 1
fi

BAD_FINAL_PLACEHOLDER_PROJ="$TMP/bad-final-placeholder-project"
cp -R "$FINAL_PROJ" "$BAD_FINAL_PLACEHOLDER_PROJ"
printf '\nTODO add journal title\n' >> "$BAD_FINAL_PLACEHOLDER_PROJ/final/manuscript-final.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_PLACEHOLDER_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when final markdown contains placeholders" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_ENGINE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when assembly_engine does not use Pandoc same-source rendering" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_COMMAND_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when format_generation command does not use final/manuscript-final.md" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 19 "$BAD_FINAL_NONPANDOC_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 18 verify should fail when format_generation command does not invoke Pandoc" >&2
  exit 1
fi

SUBMISSION_PROJ="$TMP/submission-project"
cp -R "$FINAL_PROJ" "$SUBMISSION_PROJ"
mkdir -p "$SUBMISSION_PROJ/submission"
python3 - "$SUBMISSION_PROJ" <<'PY'
import hashlib
import json
import pathlib
import re
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
with zipfile.ZipFile(proj / "submission/manuscript-submission.docx", "w") as zf:
    zf.writestr("[Content_Types].xml", "<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'><Default Extension='xml' ContentType='application/xml'/></Types>")
    zf.writestr("word/document.xml", "<w:document xmlns:w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'><w:body><w:p><w:r><w:t>Submission manuscript fixture</w:t></w:r></w:p></w:body></w:document>")
write("submission/manuscript-submission.tex", "\\documentclass{article}\n\\begin{document}\nSubmission manuscript fixture.\n\\end{document}\n")
(proj / "submission/manuscript-submission.pdf").write_bytes(b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n")
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
bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$SUBMISSION_PROJ" >/dev/null

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_RAW_HTML_TABLE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 20 verify should fail when editable-text submission markdown contains a raw HTML table" >&2
  exit 1
fi

BAD_SUBMISSION_MISSING_STAGE_B_PROJ="$TMP/bad-submission-missing-stage-b-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_MISSING_STAGE_B_PROJ"
rm "$BAD_SUBMISSION_MISSING_STAGE_B_PROJ/submission/semantic-body-prose-read.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_MISSING_STAGE_B_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 20 verify should fail when semantic body-prose report is missing" >&2
  exit 1
fi

BAD_SUBMISSION_STALE_STAGE_B_PROJ="$TMP/bad-submission-stale-stage-b-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_STALE_STAGE_B_PROJ"
printf '\nA late edit after Stage B should stale the semantic read.\n' >> "$BAD_SUBMISSION_STALE_STAGE_B_PROJ/submission/manuscript-submission.md"
sync_submission_fixture_hashes "$BAD_SUBMISSION_STALE_STAGE_B_PROJ" 0
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_STALE_STAGE_B_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 20 verify should fail when semantic body-prose report hash is stale" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_RED_STAGE_B_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 20 verify should fail when semantic body-prose report is RED" >&2
  exit 1
fi

BAD_SUBMISSION_VERIFIED_MARKER_PROJ="$TMP/bad-submission-verified-marker-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_VERIFIED_MARKER_PROJ"
printf '\nPrior work supports this claim [VERIFIED-WEB: Example2020].\n' >> "$BAD_SUBMISSION_VERIFIED_MARKER_PROJ/submission/manuscript-submission.md"
sync_submission_fixture_hashes "$BAD_SUBMISSION_VERIFIED_MARKER_PROJ" 1
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_VERIFIED_MARKER_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 20 verify should fail when submission manuscript leaks VERIFIED citation markers" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_MACHINERY_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 20 verify should fail when submission manuscript leaks machinery prose" >&2
  exit 1
fi

BAD_SUBMISSION_HYPOTHESIS_PROJ="$TMP/bad-submission-hypothesis-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_HYPOTHESIS_PROJ"
cat >> "$BAD_SUBMISSION_HYPOTHESIS_PROJ/submission/manuscript-submission.md" <<'EOF'

## Hypotheses

- **H1.** Agricultural hukou is associated with lower current CCP membership.
- **H2.** The association is partly attenuated after adjustment.
EOF
sync_submission_fixture_hashes "$BAD_SUBMISSION_HYPOTHESIS_PROJ" 1
BAD_SUBMISSION_HYPOTHESIS_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_HYPOTHESIS_PROJ" 2>&1 || true)"
case "$BAD_SUBMISSION_HYPOTHESIS_OUT" in
  *"proposal-style hypothesis bullet/list blocks"* ) ;;
  *) echo "FAIL: Phase 20 verify should fail when submission manuscript leaks hypothesis bullet/list blocks" >&2; echo "$BAD_SUBMISSION_HYPOTHESIS_OUT" >&2; exit 1 ;;
esac

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_PROVENANCE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 20 verify should fail when submission provenance drifts from the final manifest" >&2
  exit 1
fi

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
FAIL_SUBMISSION_OUT="$(bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$FAIL_SUBMISSION_PROJ" 2>&1 || true)"
case "$FAIL_SUBMISSION_OUT" in
  *"route_back_phase=20"* ) ;;
  *) echo "FAIL: Phase 20 structured FAIL report should expose route_back_phase=20, got $FAIL_SUBMISSION_OUT" >&2; exit 1 ;;
esac

ROUTE_STATE_19_PROJ="$TMP/route-state-19-project"
bash "$SCRIPT_DIR/auto-research-state.sh" init "$ROUTE_STATE_19_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-state.sh" set-mode "$ROUTE_STATE_19_PROJ" autonomous "fixture autonomous" >/dev/null
mkdir -p "$ROUTE_STATE_19_PROJ/artifacts" "$ROUTE_STATE_19_PROJ/submission"
for pid in $(seq 0 19); do
  printf 'phase %s artifact\n' "$pid" > "$ROUTE_STATE_19_PROJ/artifacts/phase-$pid.txt"
  bash "$SCRIPT_DIR/auto-research-state.sh" complete "$ROUTE_STATE_19_PROJ" "$pid" "$ROUTE_STATE_19_PROJ/artifacts/phase-$pid.txt" >/dev/null
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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_PATH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when submission manuscript leaks a local path" >&2
  exit 1
fi

BAD_SUBMISSION_INTERNAL_PROJ="$TMP/bad-submission-internal-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_INTERNAL_PROJ"
printf '\nSee verify/runtime-sanity.md for the derivation.\n' >> "$BAD_SUBMISSION_INTERNAL_PROJ/submission/manuscript-submission.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_INTERNAL_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when submission manuscript leaks internal metadata" >&2
  exit 1
fi

BAD_SUBMISSION_PLACEHOLDER_PROJ="$TMP/bad-submission-placeholder-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_PLACEHOLDER_PROJ"
printf '\nTODO add cover metadata.\n' >> "$BAD_SUBMISSION_PLACEHOLDER_PROJ/submission/manuscript-submission.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_PLACEHOLDER_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when submission manuscript contains placeholders" >&2
  exit 1
fi

BAD_SUBMISSION_REFS_PROJ="$TMP/bad-submission-refs-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_REFS_PROJ"
printf '\n- Bullet reference entry that should not render as a list.\n' >> "$BAD_SUBMISSION_REFS_PROJ/submission/manuscript-submission.md"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_REFS_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when References render as a Markdown bullet list" >&2
  exit 1
fi

BAD_SUBMISSION_LATEST_PROJ="$TMP/bad-submission-latest-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_LATEST_PROJ"
printf '2026-04-30T153501Z-v001\n' > "$BAD_SUBMISSION_LATEST_PROJ/submission/LATEST.txt"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_LATEST_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when submission/LATEST.txt does not match submission_version_id" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_VERSION_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when versioned submission manuscript is missing" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_DOCX_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when submission DOCX is invalid" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_COMMAND_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when format_generation command does not use submission/manuscript-submission.md" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_NONPANDOC_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when format_generation command does not invoke Pandoc" >&2
  exit 1
fi

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
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_INVENTORY_HASH_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when package inventory records a stale hash" >&2
  exit 1
fi

BAD_SUBMISSION_MANIFEST_PROJ="$TMP/bad-submission-manifest-project"
cp -R "$SUBMISSION_PROJ" "$BAD_SUBMISSION_MANIFEST_PROJ"
printf '{}\n' > "$BAD_SUBMISSION_MANIFEST_PROJ/submission/submission-package-manifest.json"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 20 "$BAD_SUBMISSION_MANIFEST_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 19 verify should fail when submission package manifest is empty" >&2
  exit 1
fi

printf '{"safety_status":"PASS","files_scanned":1,"no_data_declared":false,"high_risk_unresolved":0}\n' > "$PROJ/safety/safety-status.json"
if bash "$SCRIPT_DIR/auto-research-state.sh" hash-check "$PROJ" >/dev/null 2>&1; then
  echo "FAIL: hash-check should detect changed completed artifact" >&2
  exit 1
fi

STALE="$(bash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ")"
case "$STALE" in
  *"NEXT_PHASE=0"* ) ;;
  *) echo "FAIL: expected stale NEXT_PHASE=0 after safety artifact mutation, got $STALE" >&2; exit 1 ;;
esac

INIT_PROJ="$TMP/init-project"
mkdir -p "$INIT_PROJ/.claude"
printf '{"data/raw/a.csv":"CLEARED","data/raw/b.csv":"LOCAL_MODE: sensitive microdata"}\n' > "$INIT_PROJ/.claude/safety-status.json"
IMPORT_OUT="$(bash "$SCRIPT_DIR/auto-research-state.sh" import-init "$INIT_PROJ")"
case "$IMPORT_OUT" in
  *"SAFETY_STATUS=PASS_LOCAL_MODE"* ) ;;
  *) echo "FAIL: expected PASS_LOCAL_MODE import, got $IMPORT_OUT" >&2; exit 1 ;;
esac
# 2026-05-25: Phase 0 verify requires CLAUDE.md marker block (workflow contract).
bash "$SCRIPT_DIR/setup-project-claudemd.sh" "$INIT_PROJ" >/dev/null
bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$INIT_PROJ" >/dev/null

BLOCKED_PROJ="$TMP/blocked-init-project"
mkdir -p "$BLOCKED_PROJ/.claude"
printf '{"data/raw/a.csv":"CLEARED","data/raw/b.csv":"NEEDS_REVIEW: possible PII"}\n' > "$BLOCKED_PROJ/.claude/safety-status.json"
if bash "$SCRIPT_DIR/auto-research-state.sh" import-init "$BLOCKED_PROJ" >/dev/null 2>&1; then
  echo "FAIL: import-init should block unresolved NEEDS_REVIEW entries" >&2
  exit 1
fi
if bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$BLOCKED_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 0 verify should fail on imported unresolved safety entries" >&2
  exit 1
fi

BARE_OVERRIDE_PROJ="$TMP/bare-override-project"
mkdir -p "$BARE_OVERRIDE_PROJ/.claude"
printf '{"data/raw/a.csv":"OVERRIDE"}\n' > "$BARE_OVERRIDE_PROJ/.claude/safety-status.json"
if bash "$SCRIPT_DIR/auto-research-state.sh" import-init "$BARE_OVERRIDE_PROJ" >/dev/null 2>&1; then
  echo "FAIL: import-init should block bare OVERRIDE without rationale" >&2
  exit 1
fi

ZERO_SCAN_PROJ="$TMP/zero-scan-project"
mkdir -p "$ZERO_SCAN_PROJ/safety"
printf '{"safety_status":"PASS","files_scanned":0,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$ZERO_SCAN_PROJ/safety/safety-status.json"
if bash "$SCRIPT_DIR/auto-research-verify.sh" 0 "$ZERO_SCAN_PROJ" >/dev/null 2>&1; then
  echo "FAIL: Phase 0 verify should fail on zero scanned files without no_data_declared" >&2
  exit 1
fi

END_TS="$(date +%s)"
echo "auto-research fixture test: PASS"
echo "fixture_project=$PROJ"
echo "elapsed_seconds=$((END_TS - START_TS))"
