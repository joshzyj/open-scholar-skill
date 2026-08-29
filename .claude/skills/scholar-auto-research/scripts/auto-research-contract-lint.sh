#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$SKILL_DIR/references/phase-contract.json"
SKILL_MD="$SKILL_DIR/SKILL.md"

python3 - "$CONTRACT" "$SKILL_MD" <<'PY'
import json
import re
import sys
from pathlib import Path

contract_path = Path(sys.argv[1])
skill_path = Path(sys.argv[2])

errors = []
contract = json.loads(contract_path.read_text())
phases = contract.get("phases", [])
ids = [str(p.get("id", "")) for p in phases]

if contract.get("schema_version") != "1.4.0":
    errors.append("schema_version must be 1.4.0")
if len(ids) != len(set(ids)):
    errors.append("duplicate phase IDs")
if ids != [str(i) for i in range(21)]:
    errors.append(f"default phase IDs must be 0..20 in order; got {ids}")
if contract.get("default_terminal_phase") != "20":
    errors.append("default_terminal_phase must be 20")

by_id = {str(p["id"]): p for p in phases}
review_phases = {"6", "7", "9", "14", "18", "20"}
expected_round_roles = {
    ("6", "initial_panel"): {"correctness", "robustness", "statistical", "reproducibility", "style_ai_patterns", "data_handling"},
    ("6", "fix_rereview"): {"fix_verifier"},
    ("7", "premortem_panel"): {"identification", "measurement_missingness", "model_robustness", "interpretation_claims"},
    ("9", "post_execution_panel"): {"statistical_results", "robustness_consistency", "sample_data_integrity", "interpretation_claims"},
    ("14", "verification_panel"): {"verify-numerics", "verify-figures", "verify-logic", "verify-completeness"},
    ("18", "adversarial_panel"): {"methods-evidence", "theory-contribution", "senior-editor", "interpretive-skeptic"},
    ("20", "semantic_body_reader"): {"semantic_body_prose_reader"},
}
expected_optional_roles = {
    ("18", "adversarial_panel"): {
        "computational-methods", "qualitative-methods", "linguistic-methods",
        "mixed-methods", "survey-methods", "demographic-family-methods",
        "quantitative-family-methods", "domain-methods", "methods-specialist",
    },
}
required_host_claims = {
    "task_identity", "terminal_status", "completion_time",
    "report_digest", "reviewed_inputs_digest",
}
for i, phase in enumerate(phases):
    pid = str(phase.get("id"))
    for key in ("name", "route", "trigger", "required_inputs", "required_outputs", "gate", "next", "hash_dependencies", "pass_schema"):
        if key not in phase:
            errors.append(f"phase {pid} missing {key}")
    if phase.get("route") != "default":
        errors.append(f"phase {pid} must be in default route")
    if not phase.get("required_outputs"):
        errors.append(f"phase {pid} has no required_outputs")
    if not phase.get("pass_schema"):
        errors.append(f"phase {pid} has no pass_schema")
    expected_next = str(i + 1) if i < 20 else "DONE"
    if str(phase.get("next")) != expected_next:
        errors.append(f"phase {pid} next must be {expected_next}, got {phase.get('next')}")
    for dep in phase.get("hash_dependencies", []):
        if str(dep) not in by_id:
            errors.append(f"phase {pid} depends on unknown phase {dep}")
        elif int(dep) >= int(pid):
            errors.append(f"phase {pid} dependency {dep} is not upstream")
    policy = phase.get("review_evidence_policy")
    if pid in review_phases:
        if not isinstance(policy, dict):
            errors.append(f"phase {pid} missing review_evidence_policy")
            continue
        expected_root = f"review-evidence/phase-{int(pid):02d}"
        if policy.get("evidence_root") != expected_root:
            errors.append(f"phase {pid} evidence_root must be {expected_root}")
        if expected_root not in phase.get("required_outputs", []):
            errors.append(f"phase {pid} evidence_root must be a required output")
        if "review_evidence" not in phase.get("pass_schema", []):
            errors.append(f"phase {pid} pass_schema must include review_evidence")
        if policy.get("minimum_assurance") != "process_recorded":
            errors.append(f"phase {pid} minimum assurance must be process_recorded")
        if set(policy.get("strict_required_host_claims", [])) != required_host_claims:
            errors.append(f"phase {pid} strict host claims are incomplete")
        if policy.get("summary_output") not in phase.get("required_outputs", []):
            errors.append(f"phase {pid} summary_output must be a required output")
        rounds = policy.get("rounds")
        if not isinstance(rounds, dict) or not rounds:
            errors.append(f"phase {pid} review policy must declare rounds")
        else:
            for round_name, round_policy in rounds.items():
                if not isinstance(round_policy, dict):
                    errors.append(f"phase {pid} round {round_name} must be an object")
                    continue
                roles = round_policy.get("roles")
                if not isinstance(roles, list) or not roles or len(set(roles)) != len(roles):
                    errors.append(f"phase {pid} round {round_name} roles are missing/duplicate")
                elif any(not isinstance(role, str) or not re.fullmatch(r"[a-z][a-z0-9_-]{1,63}", role) for role in roles):
                    errors.append(f"phase {pid} round {round_name} has an invalid role token")
                elif set(roles) != expected_round_roles.get((pid, round_name), set()):
                    errors.append(
                        f"phase {pid} round {round_name} roles do not map to verifier-owned semantic outputs"
                    )
                optional_roles = {
                    str(role) for group in round_policy.get("optional_role_groups", [])
                    if isinstance(group, list) for role in group
                }
                if optional_roles != expected_optional_roles.get((pid, round_name), set()):
                    errors.append(
                        f"phase {pid} round {round_name} optional roles do not map to verifier-owned semantic outputs"
                    )
                inputs = round_policy.get("input_patterns")
                if not isinstance(inputs, list) or not inputs:
                    errors.append(f"phase {pid} round {round_name} input_patterns are missing")
                elif any(not isinstance(item, str) or not item.strip() or item.startswith("/") or ".." in item.split("/") for item in inputs):
                    errors.append(f"phase {pid} round {round_name} has an invalid input pattern")
                binding_keys = [key for key in ("binding_collection", "binding_object") if round_policy.get(key)]
                if len(binding_keys) != 1:
                    errors.append(f"phase {pid} round {round_name} must declare exactly one semantic binding")
                for field_key in ("role_field", "report_path_field", "task_id_field"):
                    value = round_policy.get(field_key)
                    if value is not None and (not isinstance(value, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value)):
                        errors.append(f"phase {pid} round {round_name} has invalid {field_key}")
    elif policy is not None:
        errors.append(f"phase {pid} unexpectedly declares review_evidence_policy")

skill = skill_path.read_text()
for phase in phases:
    label = f"{phase['id']}. {phase['name']}"
    if label not in skill:
        errors.append(f"SKILL.md does not list default-chain label: {label}")

phase20 = by_id.get("20", {})
for phase_id, field in (
    ("12", "journal_profile_resolution"),
    ("12", "discussion_mode"),
    ("19", "journal_profile_resolution"),
):
    if field not in set(by_id.get(phase_id, {}).get("pass_schema", [])):
        errors.append(f"phase {phase_id} pass_schema must include {field}")

phase18_conditional = by_id.get("18", {}).get("conditional_pass_schema", [])
regression_rule = {
    "when": "quantitative_empirical_regression_table_required",
    "fields": ["regression_table_audit"],
}
if not isinstance(phase18_conditional, list) or regression_rule not in phase18_conditional:
    errors.append("phase 18 conditional_pass_schema must require regression_table_audit")

phase20_schema = set(phase20.get("pass_schema", []))
for field in ("journal_profile_resolution", "hygiene_checks", "semantic_body_prose_read", "pipeline_complete"):
    if field not in phase20_schema:
        errors.append(f"phase 20 pass_schema must include {field}")
if "submission/semantic-body-prose-read.md" not in phase20.get("required_outputs", []):
    errors.append("phase 20 must require submission/semantic-body-prose-read.md")

verify_path = contract_path.parent.parent / "scripts" / "auto-research-verify.sh"
verify_text = verify_path.read_text()
phase20_start = verify_text.find('if phase_id == "20":')
if phase20_start == -1:
    errors.append("auto-research-verify.sh missing Phase 20 verifier block")
elif "FAIL: Phase 19" in verify_text[phase20_start:]:
    errors.append("Phase 20 verifier block contains stale 'FAIL: Phase 19' message")

if "manuscript-final.docx" not in contract_path.read_text():
    errors.append("contract must require docx final output")
if "manuscript-final.pdf" not in contract_path.read_text():
    errors.append("contract must require pdf final output")
if "manuscript-final.tex" not in contract_path.read_text():
    errors.append("contract must require tex final output")
if "manuscript-final.md" not in contract_path.read_text():
    errors.append("contract must require md final output")

if errors:
    print("auto-research contract lint: FAIL")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)

print("auto-research contract lint: PASS")
print(f"  phases: {len(phases)}")
print(f"  terminal: {contract['default_terminal_phase']} -> DONE")
PY
