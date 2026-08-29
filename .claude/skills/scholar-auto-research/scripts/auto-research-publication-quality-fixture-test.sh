#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SELF="$SCRIPT_DIR/auto-research-publication-quality-fixture-test.sh"
BUILDER="$SKILL_DIR/tests/helpers/build-publication-quality-fixture.py"
CASE_TOOL="$SKILL_DIR/tests/helpers/case_result.py"
HARNESS="$SKILL_DIR/tests/helpers/harness.sh"
VERIFY="$SCRIPT_DIR/auto-research-verify.sh"
MANIFEST="$SKILL_DIR/tests/coverage-manifest.json"
export PYTHONDONTWRITEBYTECODE=1

mutant_diagnostic() {
  case "$1" in
    source_roles) printf '%s\n' 'F20_L3_MUTANT_ACCEPTED: source_roles production verifier accepted mapped invalid fixture' ;;
    design_continuity) printf '%s\n' 'F20_L3_MUTANT_ACCEPTED: design_continuity production verifier accepted mapped invalid fixture' ;;
    publication_readiness) printf '%s\n' 'F20_L3_MUTANT_ACCEPTED: publication_readiness production verifier accepted mapped invalid fixture' ;;
    drafting_plan) printf '%s\n' 'F20_L3_MUTANT_ACCEPTED: drafting_plan production verifier accepted mapped invalid fixture' ;;
    self_critique) printf '%s\n' 'F20_L3_MUTANT_ACCEPTED: self_critique production verifier accepted mapped invalid fixture' ;;
    source_roles_callsite) printf '%s\n' 'F20_L3_MUTANT_ACCEPTED: source_roles_callsite production verifier accepted mapped invalid fixture' ;;
    *) printf 'F20_L3_MUTANT_UNKNOWN: %s\n' "$1" >&2; return 1 ;;
  esac
}

# The mutation oracle deliberately inverts one observation for expect_reject:
# rc=97 means the syntactically valid mutant accepted the mapped invalid input.
# Any rejection/crash is not a kill and therefore cannot emit the kill diagnostic.
if [ "${1:-}" = "__mutation_oracle" ]; then
  [ "$#" -eq 5 ] || { printf 'F20_L3_MUTANT_ORACLE_USAGE\n' >&2; exit 99; }
  operator="$2"
  verifier="$3"
  phase="$4"
  project="$5"
  set +e
  oracle_output="$(bash "$verifier" "$phase" "$project" 2>&1)"
  oracle_rc=$?
  set -e
  if [ "$oracle_rc" -eq 0 ]; then
    mutant_diagnostic "$operator"
    exit 97
  fi
  printf '%s\n' "$oracle_output" >&2
  printf 'F20_L3_MUTANT_NOT_KILLED: %s verifier_rc=%s\n' "$operator" "$oracle_rc" >&2
  exit 98
fi

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

source "$HARNESS"
harness_make_temp_root TMP_ROOT "publication quality's root" || exit 1

# Honor a release coordinator when present; otherwise create one fresh focused
# run bound to this finalized skill tree and manifest generation.
if [ -z "${SCHOLAR_HARNESS_SOURCE_ROOT:-}" ]; then
  export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR"
  export SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
  export SCHOLAR_HARNESS_RESULTS_DIR="$TMP_ROOT/results"
  export SCHOLAR_HARNESS_RUN_ID="publication-quality-$$"
  export SCHOLAR_HARNESS_RUN_NONCE="publication-quality-$$-$(date +%s)"
  export SCHOLAR_HARNESS_SUITE_MODE="focused"
  export SCHOLAR_HARNESS_SUITE_ORDER="normal"
  export SCHOLAR_HARNESS_MANIFEST_SHA256="$(python3 "$CASE_TOOL" digest-file "$MANIFEST")"
  export SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$(python3 "$CASE_TOOL" source-digest "$SKILL_DIR")"
fi
harness_init "$SELF" "publication-quality-fixture" || exit 1

bash -n "$VERIFY"
PYTHONPYCACHEPREFIX="$TMP_ROOT/pycache" python3 -m py_compile "$BUILDER"
python3 -m json.tool "$SKILL_DIR/references/phase-contract.json" >/dev/null
python3 -m json.tool "$SKILL_DIR/tests/fixtures/publication-quality-seed/fixture-metadata.json" >/dev/null
bash "$SCRIPT_DIR/auto-research-contract-lint.sh" >/dev/null
bash "$SCRIPT_DIR/auto-research-system-gate-smoke.sh" >/dev/null

python3 - "$SKILL_DIR/references/phase-contract.json" <<'PY'
import json
import sys
contract = json.load(open(sys.argv[1], encoding="utf-8"))
phase_by_id = {str(item["id"]): item for item in contract["phases"]}
for phase_id, fields in {
    "2": {"source_role_matrix"},
    "3": {"claim_continuity", "mechanism_result_matrix", "robustness_claim_matrix", "limitation_scope_matrix"},
    "12": {"publication_readiness"},
    "13": {"drafting_plan", "self_critique"},
}.items():
    missing = sorted(fields - set(phase_by_id[phase_id].get("pass_schema", [])))
    if missing:
        raise SystemExit(f"phase {phase_id} missing pass_schema fields {missing}")
PY

PHASE23_GOOD="$TMP_ROOT/phase23-good"
PHASE1215_GOOD="$TMP_ROOT/phase1215-good"
python3 "$BUILDER" phase23 "$PHASE23_GOOD"
python3 "$BUILDER" phase1215 "$PHASE1215_GOOD"

# The immutable seed is also the canonical schema-v2 handoff snapshot.  These
# setup assertions do not duplicate verifier semantics: they prove only that
# the fixture carries exactly the Phase 13 identities/payloads into the
# deterministic Phase 14 and Phase 15 artifacts that later mutation cases use.
python3 - "$PHASE1215_GOOD" <<'PY'
import json
import hashlib
import sys
from pathlib import Path

project = Path(sys.argv[1])
draft = json.loads((project / "manuscript/draft-manifest.json").read_text(encoding="utf-8"))
phase14 = json.loads((project / "verify/manuscript-verification.json").read_text(encoding="utf-8"))
phase15 = json.loads((project / "citation/claim-source-map.json").read_text(encoding="utf-8"))

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

expected_source_hashes = {
    "manuscript": sha256(project / "manuscript/manuscript-draft.md"),
    "draft_manifest": sha256(project / "manuscript/draft-manifest.json"),
}
for label, artifact in (("Phase 14", phase14), ("Phase 15", phase15)):
    if artifact.get("selected_manuscript_hash") != expected_source_hashes["manuscript"]:
        raise SystemExit(f"publication fixture {label} manuscript hash is stale")
    if artifact.get("source_hashes") != expected_source_hashes:
        raise SystemExit(f"publication fixture {label} source hashes are stale")

if draft.get("locked_result_claims_schema_version") != 2:
    raise SystemExit("publication fixture Phase 13 claims are not schema v2")

expected14 = {}
expected15 = {}
for group in draft.get("locked_result_claims", []):
    for row in group.get("rows", []):
        identity = (
            group["binding_type"], group["display_source_path"], group["display_locked_path"],
            group["source_path"], group["locked_path"], row["row_index"], row["spec_id"],
            row["display_coordinate_kind"], row["display_coordinate"], row["claim_id"],
        )
        expected14[identity] = {
            "manuscript_anchor": row["manuscript_anchor"],
            "estimate": row["estimate"],
            "std_error": row["std_error"],
            "p_value": row["p_value"],
            "n": row["n"],
        }
        expected15[row["claim_id"]] = {
            "manuscript_anchor": row["manuscript_anchor"],
            "result_binding": {
                "binding_type": group["binding_type"],
                "display_source_path": group["display_source_path"],
                "display_locked_path": group["display_locked_path"],
                "value_source_path": group["source_path"],
                "value_locked_path": group["locked_path"],
                "row_index": row["row_index"],
                "spec_id": row["spec_id"],
                "display_coordinate_kind": row["display_coordinate_kind"],
                "display_coordinate": row["display_coordinate"],
            },
        }

actual14 = {}
for row in phase14.get("stage_2_manuscript_to_prose", {}).get("checked", []):
    identity = (
        row.get("binding_type"), row.get("display_source_path"), row.get("display_locked_path"),
        row.get("source_artifact"), row.get("locked_path"), row.get("row_index"), row.get("spec_id"),
        row.get("display_coordinate_kind"), row.get("display_coordinate"), row.get("claim_id"),
    )
    if identity in actual14:
        raise SystemExit(f"publication fixture duplicate Phase 14 identity: {identity}")
    actual14[identity] = {field: row.get(field) for field in ("manuscript_anchor", "estimate", "std_error", "p_value", "n")}
stage2 = phase14.get("stage_2_manuscript_to_prose", {})
if actual14 != expected14 or stage2.get("claims_scanned") != len(expected14):
    raise SystemExit("publication fixture Phase 14 bindings do not exactly match Phase 13")
if (
    phase14.get("locked_result_claims_schema_version") != 2
    or stage2.get("verdict") != "PASS"
    or stage2.get("degraded") is not False
    or stage2.get("critical_count") != 0
    or any(
        row.get(field) != "PASS"
        for row in stage2.get("checked", [])
        for field in ("verdict", "direction_verdict", "uncertainty_verdict", "causal_language_verdict", "phase9_constraint_verdict")
    )
):
    raise SystemExit("publication fixture Phase 14 Stage 2 verdict surface is not canonical")

actual15 = {}
for row in phase15.get("claims", []):
    if row.get("claim_type") != "empirical":
        continue
    claim_id = row.get("claim_id")
    if claim_id in actual15:
        raise SystemExit(f"publication fixture duplicate Phase 15 identity: {claim_id}")
    actual15[claim_id] = {
        "manuscript_anchor": row.get("manuscript_anchor"),
        "result_binding": row.get("result_binding"),
    }
if actual15 != expected15:
    raise SystemExit("publication fixture Phase 15 bindings do not exactly match Phase 13")
if (
    phase15.get("verdict") != "PASS"
    or phase15.get("degraded") is not False
    or phase15.get("total_claims") != len(expected15)
    or phase15.get("supported_count") != len(expected15)
    or any(phase15.get(field) != 0 for field in ("unsupported_count", "contradicted_count", "locator_missing_count"))
    or any(row.get("support_verdict") != "SUPPORTED" or row.get("contradiction") is not False for row in phase15.get("claims", []))
):
    raise SystemExit("publication fixture Phase 15 empirical verdict surface is not canonical")

registry = next(item for item in draft["locked_result_coverage"] if item.get("artifact_role") == "results_registry")
if registry.get("used_in_manuscript") is not False or registry.get("manuscript_anchor"):
    raise SystemExit("publication fixture provenance registry became reader-facing")
print(f"PUBLICATION_V2_HANDOFF_CLAIMS={len(expected14)}")
PY

PHASE2_BAD="$TMP_ROOT/phase2-bad"
PHASE3_BAD="$TMP_ROOT/phase3-bad"
PHASE12_BAD="$TMP_ROOT/phase12-bad"
PHASE13_PLAN_BAD="$TMP_ROOT/phase13-plan-bad"
PHASE13_CRITIQUE_BAD="$TMP_ROOT/phase13-critique-bad"
cp -R "$PHASE23_GOOD" "$PHASE2_BAD"
cp -R "$PHASE23_GOOD" "$PHASE3_BAD"
cp -R "$PHASE1215_GOOD" "$PHASE12_BAD"
cp -R "$PHASE1215_GOOD" "$PHASE13_PLAN_BAD"
cp -R "$PHASE1215_GOOD" "$PHASE13_CRITIQUE_BAD"

mutate_fixture() {
  local operation="$1" project="$2"
  python3 - "$operation" "$project" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

operation, project_arg = sys.argv[1:3]
project = Path(project_arg)

def load(rel):
    path = project / rel
    return path, json.loads(path.read_text(encoding="utf-8"))

def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

if operation == "phase2-source-roles":
    path, doc = load("literature/literature-coverage-matrix.json")
    for row in doc["source_role_matrix"]:
        row["argument_role"] = "background"
    save(path, doc)
    manifest_path, manifest = load("literature/lit-theory-manifest.json")
    manifest["coverage_matrix_hash"] = digest(path)
    save(manifest_path, manifest)
elif operation == "phase3-continuity":
    path, doc = load("design/design-manifest.json")
    doc.pop("mechanism_result_matrix")
    save(path, doc)
    design_mtime = max(
        (project / rel).stat().st_mtime_ns
        for rel in ("design/design-blueprint.md", "design/identification-strategy.json", "design/model-specs.json")
    )
    for rel in ("design/design-manifest.json", "design/design-evaluation.json", "design/design-evaluation.md"):
        os.utime(project / rel, ns=(design_mtime + 1_000_000, design_mtime + 1_000_000))
    for rel in ("design/design-revision-log.json", "design/design-revision-log.md"):
        os.utime(project / rel, ns=(design_mtime + 2_000_000, design_mtime + 2_000_000))
elif operation == "phase12-readiness":
    path, doc = load("manuscript/manuscript-blueprint.json")
    rows = doc["publication_readiness"]["mechanism_rival_matrix"]
    doc["publication_readiness"]["mechanism_rival_matrix"] = [row for row in rows if row.get("role") == "mechanism"][:1]
    save(path, doc)
elif operation in {"phase13-plan", "phase13-critique"}:
    manifest_path, manifest = load("manuscript/draft-manifest.json")
    if operation == "phase13-plan":
        target_path, target = load("manuscript/drafting-plan.json")
        target.pop("section_briefs")
        save(target_path, target)
        manifest["drafting_plan"]["sha256"] = digest(target_path)
    else:
        target_path, target = load("manuscript/draft-self-critique.json")
        target["strongest_rejection_reason"] = "Too thin."
        save(target_path, target)
        manifest["self_critique"]["sha256"] = digest(target_path)
    save(manifest_path, manifest)
else:
    raise SystemExit(f"unknown fixture mutation: {operation}")
PY
}

mutate_fixture phase2-source-roles "$PHASE2_BAD"
mutate_fixture phase3-continuity "$PHASE3_BAD"
mutate_fixture phase12-readiness "$PHASE12_BAD"
mutate_fixture phase13-plan "$PHASE13_PLAN_BAD"
mutate_fixture phase13-critique "$PHASE13_CRITIQUE_BAD"

prepare_mutant() {
  local operator="$1"
  MUTANT_PARENT="$TMP_ROOT/mutant-$operator"
  MUTANT_SKILL="$MUTANT_PARENT/scholar-auto-research"
  MUTANT_VERIFY="$MUTANT_SKILL/scripts/auto-research-verify.sh"
  mkdir -p "$MUTANT_PARENT"
  cp -R "$SKILL_DIR" "$MUTANT_SKILL"
  LIVE_SOURCE_BEFORE="$(python3 "$CASE_TOOL" source-digest "$SKILL_DIR")"
  MUTANT_SOURCE_PRISTINE="$(python3 "$CASE_TOOL" source-digest "$MUTANT_SKILL")"
  [ "$MUTANT_SOURCE_PRISTINE" = "$LIVE_SOURCE_BEFORE" ] \
    || fail "mutation $operator pristine copy differs from source generation"
  bash -n "$MUTANT_VERIFY"
}

apply_production_mutation() {
  local operator="$1" mutation_kind="$2" token="$3"
  MUTANT_SOURCE_BEFORE="$(python3 "$CASE_TOOL" source-digest "$MUTANT_SKILL")"
  [ "$MUTANT_SOURCE_BEFORE" = "$MUTANT_SOURCE_PRISTINE" ] \
    || fail "mutation $operator pristine baseline changed copied source"
  python3 - "$MUTANT_SKILL" "$mutation_kind" "$token" <<'PY'
import hashlib
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve(strict=True)
kind = sys.argv[2]
token = sys.argv[3]
target = root / "scripts/auto-research-verify.sh"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inventory():
    result = {}
    for path in sorted(root.rglob("*"), key=lambda item: os.fsencode(item.relative_to(root).as_posix())):
        rel = path.relative_to(root).as_posix()
        info = path.lstat()
        item = {"mode": f"{stat.S_IMODE(info.st_mode):04o}"}
        if path.is_symlink():
            item.update(type="symlink", target=os.readlink(path))
        elif path.is_dir():
            item["type"] = "directory"
        elif path.is_file():
            item.update(type="file", sha256=sha(path), size=info.st_size)
        else:
            raise SystemExit(f"special file in copied skill: {rel}")
        result[rel] = item
    return result

before = inventory()
text = target.read_text(encoding="utf-8")
if kind == "condition":
    needle = f"    if {token}:\n"
    replacement = f"    if False and {token}:\n"
elif kind == "callsite":
    needle = '        fail("FAIL: Phase 2 source_role_matrix does not assign sources to argument roles", source_role_issues[:30])\n'
    replacement = "        pass  # F20 mutant: source-role fail callsite removed\n"
else:
    raise SystemExit(f"unknown mutation kind: {kind}")
matches = text.count(needle)
if matches != 1:
    raise SystemExit(f"mutation target must match exactly once: kind={kind} token={token} matches={matches}")
target.write_text(text.replace(needle, replacement), encoding="utf-8")
after = inventory()
changed = sorted(path for path in set(before) | set(after) if before.get(path) != after.get(path))
if changed != ["scripts/auto-research-verify.sh"]:
    raise SystemExit(f"copy-only mutation violated: changed={changed}")
print("MUTATION_TARGET_MATCHES=1")
print("MUTATION_CHANGED_PATH=scripts/auto-research-verify.sh")
PY
  MUTANT_SOURCE_AFTER="$(python3 "$CASE_TOOL" source-digest "$MUTANT_SKILL")"
  LIVE_SOURCE_AFTER="$(python3 "$CASE_TOOL" source-digest "$SKILL_DIR")"
  [ "$MUTANT_SOURCE_AFTER" != "$MUTANT_SOURCE_BEFORE" ] \
    || fail "mutation $operator did not change canonical copied-source digest"
  [ "$LIVE_SOURCE_AFTER" = "$LIVE_SOURCE_BEFORE" ] \
    || fail "mutation $operator changed the live source generation"
  bash -n "$MUTANT_VERIFY"
  MUTATION_BINDING="operator=$operator,target_matches=1,changed=scripts/auto-research-verify.sh,before=$MUTANT_SOURCE_BEFORE,after=$MUTANT_SOURCE_AFTER"
}

# CASE:l3.source_roles.pristine_positive
prepare_mutant source_roles
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_pass l3.source_roles.pristine_positive "$PHASE23_GOOD" -- bash "$MUTANT_VERIFY" 2 "$PHASE23_GOOD"
# CASE:l3.source_roles.pristine_negative
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_reject l3.source_roles.pristine_negative "$PHASE2_BAD" -- bash "$MUTANT_VERIFY" 2 "$PHASE2_BAD"
apply_production_mutation source_roles condition source_role_issues
# CASE:l3.source_roles.mutant_valid
SCHOLAR_HARNESS_MUTATION_VERDICT="valid_control:$MUTATION_BINDING" expect_pass l3.source_roles.mutant_valid "$PHASE23_GOOD" -- bash "$MUTANT_VERIFY" 2 "$PHASE23_GOOD"
# CASE:l3.source_roles.mutant_kill
SCHOLAR_HARNESS_MUTATION_VERDICT="killed:$MUTATION_BINDING" expect_reject l3.source_roles.mutant_kill "$PHASE2_BAD" -- bash "$SELF" __mutation_oracle source_roles "$MUTANT_VERIFY" 2 "$PHASE2_BAD"

# CASE:l3.design_continuity.pristine_positive
prepare_mutant design_continuity
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_pass l3.design_continuity.pristine_positive "$PHASE23_GOOD" -- bash "$MUTANT_VERIFY" 3 "$PHASE23_GOOD"
# CASE:l3.design_continuity.pristine_negative
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_reject l3.design_continuity.pristine_negative "$PHASE3_BAD" -- bash "$MUTANT_VERIFY" 3 "$PHASE3_BAD"
apply_production_mutation design_continuity condition continuity_issues
# CASE:l3.design_continuity.mutant_valid
SCHOLAR_HARNESS_MUTATION_VERDICT="valid_control:$MUTATION_BINDING" expect_pass l3.design_continuity.mutant_valid "$PHASE23_GOOD" -- bash "$MUTANT_VERIFY" 3 "$PHASE23_GOOD"
# CASE:l3.design_continuity.mutant_kill
SCHOLAR_HARNESS_MUTATION_VERDICT="killed:$MUTATION_BINDING" expect_reject l3.design_continuity.mutant_kill "$PHASE3_BAD" -- bash "$SELF" __mutation_oracle design_continuity "$MUTANT_VERIFY" 3 "$PHASE3_BAD"

# CASE:l3.publication_readiness.pristine_positive
prepare_mutant publication_readiness
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_pass l3.publication_readiness.pristine_positive "$PHASE1215_GOOD" -- bash "$MUTANT_VERIFY" 12 "$PHASE1215_GOOD"
# CASE:l3.publication_readiness.pristine_negative
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_reject l3.publication_readiness.pristine_negative "$PHASE12_BAD" -- bash "$MUTANT_VERIFY" 12 "$PHASE12_BAD"
apply_production_mutation publication_readiness condition readiness_issues
# CASE:l3.publication_readiness.mutant_valid
SCHOLAR_HARNESS_MUTATION_VERDICT="valid_control:$MUTATION_BINDING" expect_pass l3.publication_readiness.mutant_valid "$PHASE1215_GOOD" -- bash "$MUTANT_VERIFY" 12 "$PHASE1215_GOOD"
# CASE:l3.publication_readiness.mutant_kill
SCHOLAR_HARNESS_MUTATION_VERDICT="killed:$MUTATION_BINDING" expect_reject l3.publication_readiness.mutant_kill "$PHASE12_BAD" -- bash "$SELF" __mutation_oracle publication_readiness "$MUTANT_VERIFY" 12 "$PHASE12_BAD"

# CASE:l3.drafting_plan.pristine_positive
prepare_mutant drafting_plan
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_pass l3.drafting_plan.pristine_positive "$PHASE1215_GOOD" -- bash "$MUTANT_VERIFY" 13 "$PHASE1215_GOOD"
# CASE:l3.drafting_plan.pristine_negative
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_reject l3.drafting_plan.pristine_negative "$PHASE13_PLAN_BAD" -- bash "$MUTANT_VERIFY" 13 "$PHASE13_PLAN_BAD"
apply_production_mutation drafting_plan condition plan_issues
# CASE:l3.drafting_plan.mutant_valid
SCHOLAR_HARNESS_MUTATION_VERDICT="valid_control:$MUTATION_BINDING" expect_pass l3.drafting_plan.mutant_valid "$PHASE1215_GOOD" -- bash "$MUTANT_VERIFY" 13 "$PHASE1215_GOOD"
# CASE:l3.drafting_plan.mutant_kill
SCHOLAR_HARNESS_MUTATION_VERDICT="killed:$MUTATION_BINDING" expect_reject l3.drafting_plan.mutant_kill "$PHASE13_PLAN_BAD" -- bash "$SELF" __mutation_oracle drafting_plan "$MUTANT_VERIFY" 13 "$PHASE13_PLAN_BAD"

# CASE:l3.self_critique.pristine_positive
prepare_mutant self_critique
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_pass l3.self_critique.pristine_positive "$PHASE1215_GOOD" -- bash "$MUTANT_VERIFY" 13 "$PHASE1215_GOOD"
# CASE:l3.self_critique.pristine_negative
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_reject l3.self_critique.pristine_negative "$PHASE13_CRITIQUE_BAD" -- bash "$MUTANT_VERIFY" 13 "$PHASE13_CRITIQUE_BAD"
apply_production_mutation self_critique condition critique_issues
# CASE:l3.self_critique.mutant_valid
SCHOLAR_HARNESS_MUTATION_VERDICT="valid_control:$MUTATION_BINDING" expect_pass l3.self_critique.mutant_valid "$PHASE1215_GOOD" -- bash "$MUTANT_VERIFY" 13 "$PHASE1215_GOOD"
# CASE:l3.self_critique.mutant_kill
SCHOLAR_HARNESS_MUTATION_VERDICT="killed:$MUTATION_BINDING" expect_reject l3.self_critique.mutant_kill "$PHASE13_CRITIQUE_BAD" -- bash "$SELF" __mutation_oracle self_critique "$MUTANT_VERIFY" 13 "$PHASE13_CRITIQUE_BAD"

# Distinct callsite-removal operator with its own pristine and mutant controls.
# CASE:l3.source_roles_callsite.pristine_positive
prepare_mutant source_roles_callsite
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_pass l3.source_roles_callsite.pristine_positive "$PHASE23_GOOD" -- bash "$MUTANT_VERIFY" 2 "$PHASE23_GOOD"
# CASE:l3.source_roles_callsite.pristine_negative
SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_SOURCE_PRISTINE" expect_reject l3.source_roles_callsite.pristine_negative "$PHASE2_BAD" -- bash "$MUTANT_VERIFY" 2 "$PHASE2_BAD"
apply_production_mutation source_roles_callsite callsite source_role_issues
# CASE:l3.source_roles_callsite.mutant_valid
SCHOLAR_HARNESS_MUTATION_VERDICT="valid_control:$MUTATION_BINDING" expect_pass l3.source_roles_callsite.mutant_valid "$PHASE23_GOOD" -- bash "$MUTANT_VERIFY" 2 "$PHASE23_GOOD"
# CASE:l3.source_roles_callsite.mutant_kill
SCHOLAR_HARNESS_MUTATION_VERDICT="killed:$MUTATION_BINDING" expect_reject l3.source_roles_callsite.mutant_kill "$PHASE2_BAD" -- bash "$SELF" __mutation_oracle source_roles_callsite "$MUTANT_VERIFY" 2 "$PHASE2_BAD"

harness_validate_results >/dev/null
python3 - "$MANIFEST" "$SCHOLAR_HARNESS_RESULTS_DIR" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
expected = {
    case_id for case_id, case in manifest["cases"].items()
    if case.get("gating") and case.get("runner_label") == "publication-quality-fixture"
}
records = {}
for path in Path(sys.argv[2]).glob("*.json"):
    if path.name == ".run-context.json":
        continue
    record = json.load(open(path, encoding="utf-8"))
    if record.get("runner_label") == "publication-quality-fixture":
        records[record.get("case_id")] = record
observed = set(records)
if observed != expected:
    raise SystemExit(f"L3_RESULT_SET_MISMATCH: missing={sorted(expected-observed)} unexpected={sorted(observed-expected)}")
failed = sorted(case_id for case_id, record in records.items() if record.get("terminal_status") != "PASS")
if failed:
    raise SystemExit(f"L3_RESULT_STATUS_FAILED: {failed}")
print(f"L3_AUTHORITATIVE_RECORDS={len(records)}")
PY

printf 'auto-research publication-quality fixture test: PASS\n'
printf '  production verifier phases: 2, 3, 12, 13\n'
printf '  authoritative cases: pristine positive/negative + mutant valid/kill per operator\n'
printf '  production semantic mutations killed: 6 (five families + one callsite removal)\n'
printf '  copied semantic validators: 0\n'
printf '  project data used: deterministic vendored fixtures only\n'
