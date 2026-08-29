#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

bash -n "$SCRIPT_DIR/auto-research-verify.sh"
python3 -m json.tool "$SKILL_DIR/references/phase-contract.json" >/dev/null
python3 -m json.tool "$SKILL_DIR/references/journal-profile-resolution-templates.json" >/dev/null
python3 "$SCRIPT_DIR/emit-journal-profile-resolution.py" --requested "Unresolved Test Journal" --origin fallback_asr --fallback-reason "fixture unresolved journal uses explicit ASR fallback" >/dev/null
bash "$SCRIPT_DIR/auto-research-contract-lint.sh" >/dev/null

python3 - "$SKILL_DIR" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

skill_dir = Path(sys.argv[1])
contract = json.loads((skill_dir / "references" / "phase-contract.json").read_text())
runtime_manifest = json.loads((skill_dir / "references" / "runtime-dependencies.json").read_text())
phase_by_id = {str(item["id"]): item for item in contract["phases"]}

required_schema = {
    "2": {"source_role_matrix"},
    "3": {"claim_continuity", "mechanism_result_matrix", "robustness_claim_matrix", "limitation_scope_matrix"},
    "12": {"publication_readiness"},
    "4": {"codebook_validation", "dataset_design_review", "outcome_family_screen"},
    "5": {"dataset_design_plan", "outcome_model_ladder", "missingness_sensitivity_plan"},
    "13": {"reader_facing_language", "drafting_plan", "self_critique"},
    "15": {"bibliography_provenance", "claim_specificity"},
    "18": {"reviewer_independence", "adversarial_review_coverage", "method_specialist_review"},
    "19": {"reader_facing_language", "declaration_visibility"},
    "20": {"reader_facing_language", "declaration_visibility", "figure_packaging"},
}
errors = []
for phase_id, fields in required_schema.items():
    schema = set(phase_by_id[phase_id].get("pass_schema", []))
    missing = sorted(fields - schema)
    if missing:
        errors.append(f"phase {phase_id} pass_schema missing {missing}")

verify_text = (skill_dir / "scripts" / "auto-research-verify.sh").read_text()
gate_dir = skill_dir / "scripts" / "gates"
inventory_helper = skill_dir / "tests" / "helpers" / "external_gate_inventory.py"
if not inventory_helper.exists():
    errors.append("missing packaged external-gate inventory helper")
    external_gates = []
else:
    inventory_result = subprocess.run(
        [sys.executable, str(inventory_helper), str(skill_dir / "scripts" / "auto-research-verify.sh"), "--self-test"],
        capture_output=True, text=True,
    )
    if inventory_result.returncode != 0:
        errors.append("external-gate inventory failed: " + inventory_result.stderr.strip())
        external_gates = []
    else:
        try:
            inventory = json.loads(inventory_result.stdout)
            external_gates = sorted({row["gate"] for row in inventory["obligations"]})
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            errors.append(f"external-gate inventory returned invalid JSON: {exc}")
            external_gates = []
if not gate_dir.exists():
    errors.append("missing bundled auto-research scripts/gates directory")
for gate_name in external_gates:
    gate_path = gate_dir / gate_name
    if not gate_path.exists():
        errors.append(f"bundled external gate missing: {gate_name}")
    elif not os.access(gate_path, os.X_OK):
        errors.append(f"bundled external gate not executable: {gate_name}")
    elif gate_path.suffix == ".sh":
        result = subprocess.run(["bash", "-n", str(gate_path)], capture_output=True, text=True)
        if result.returncode != 0:
            errors.append(f"bundled external gate bash syntax error: {gate_name}")
for helper_name in ["_section-role-helper.py", "derive-manuscript-path.sh"]:
    if not (gate_dir / helper_name).exists():
        errors.append(f"bundled gate helper missing: {helper_name}")

git_root = subprocess.run(
    ["git", "-C", str(skill_dir), "rev-parse", "--show-toplevel"],
    capture_output=True, text=True,
)
if git_root.returncode == 0:
    repo_root = Path(git_root.stdout.strip())
    packaged_dependencies = [
        skill_dir / str(relative)
        for relative in runtime_manifest.get("required_packaged_files", [])
    ]
    for path in (
        [gate_dir / name for name in external_gates]
        + [gate_dir / "_section-role-helper.py", gate_dir / "derive-manuscript-path.sh"]
        + packaged_dependencies
    ):
        if not path.exists():
            continue
        rel = path.relative_to(repo_root)
        tracked = subprocess.run(
            ["git", "-C", str(repo_root), "ls-files", "--error-unmatch", str(rel)],
            capture_output=True, text=True,
        )
        if tracked.returncode != 0:
            errors.append(f"bundled auto-research dependency is untracked: {rel}")
required_verify_tokens = [
    "JOURNAL_PROFILE_TEMPLATE_PATH",
    "structured_secondary_data_indicated",
    "complex_outcome_family_indicated",
    "reader_workflow_jargon_hits",
    "concrete_review_locator_present",
    "adversarial_review_terms_present",
    "dataset-design plan is incomplete",
    "outcome model ladder is incomplete",
    "missingness sensitivity plan is incomplete",
    "source_role_matrix does not assign sources to argument roles",
    "design-to-writing continuity is incomplete",
    "publication_readiness gate is incomplete",
    "drafting-plan is incomplete",
    "draft-self-critique is incomplete",
    "omnibus citation cluster",
    "authoritative method_orientation requires a fifth",
    "submission manuscript exposes internal workflow language",
    "referenced figure missing package inventory record",
]
for token in required_verify_tokens:
    if token not in verify_text:
        errors.append(f"verifier missing token: {token}")

if not (skill_dir / "scripts" / "emit-journal-profile-resolution.py").exists():
    errors.append("missing emit-journal-profile-resolution.py")
profile_templates = json.loads((skill_dir / "references" / "journal-profile-resolution-templates.json").read_text())
asr = profile_templates.get("profiles", {}).get("american sociological review", {})
if asr.get("theory_presentation") != "theory_section":
    errors.append("ASR fallback template must use theory_section")
if asr.get("display_architecture", {}).get("descriptive_table_requirement") != "table_1_required_for_quantitative":
    errors.append("ASR fallback template must require Table 1 descriptives")

contract_files = [
    "literature-theory-contract.md",
    "design-contract.md",
    "data-measurement-contract.md",
    "analysis-plan-contract.md",
    "citation-claim-contract.md",
    "quality-gate.md",
    "manuscript-blueprint-contract.md",
    "manuscript-drafting-contract.md",
    "final-assembly-contract.md",
    "submission-hygiene-contract.md",
    "review-evidence-contract.md",
]
doc_text = "\n".join((skill_dir / "references" / name).read_text() for name in contract_files)
required_doc_tokens = [
    "dataset_design_review",
    "source_role_matrix",
    "claim_continuity",
    "publication_readiness",
    "drafting-plan.json",
    "draft-self-critique.json",
    "outcome_model_ladder",
    "missingness_sensitivity_plan",
    "omnibus citation",
    "adversarial and non-boilerplate",
    "reader-facing prose",
    "declaration_visibility",
    "figure_packaging",
    "process_recorded",
    "runtime-preflight.py",
]
for token in required_doc_tokens:
    if token not in doc_text:
        errors.append(f"contract docs missing token: {token}")

if errors:
    print("auto-research system gate smoke: FAIL")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print("auto-research system gate smoke: PASS")
print("  checked phases: " + ", ".join(sorted(required_schema)))
print("  checked verifier gates: " + str(len(required_verify_tokens)))
print("  checked bundled external gates: " + str(len(external_gates)))
print("  checked contract docs: " + str(len(contract_files)))
PY
