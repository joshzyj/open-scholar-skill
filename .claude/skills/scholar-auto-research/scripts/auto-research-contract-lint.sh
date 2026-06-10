#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$SKILL_DIR/references/phase-contract.json"
SKILL_MD="$SKILL_DIR/SKILL.md"

python3 - "$CONTRACT" "$SKILL_MD" <<'PY'
import json
import sys
from pathlib import Path

contract_path = Path(sys.argv[1])
skill_path = Path(sys.argv[2])

errors = []
contract = json.loads(contract_path.read_text())
phases = contract.get("phases", [])
ids = [str(p.get("id", "")) for p in phases]

if contract.get("schema_version") != "1.1.0":
    errors.append("schema_version must be 1.1.0")
if len(ids) != len(set(ids)):
    errors.append("duplicate phase IDs")
if ids != [str(i) for i in range(21)]:
    errors.append(f"default phase IDs must be 0..20 in order; got {ids}")
if contract.get("default_terminal_phase") != "20":
    errors.append("default_terminal_phase must be 20")

by_id = {str(p["id"]): p for p in phases}
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

skill = skill_path.read_text()
for phase in phases:
    label = f"{phase['id']}. {phase['name']}"
    if label not in skill:
        errors.append(f"SKILL.md does not list default-chain label: {label}")

phase20 = by_id.get("20", {})
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
