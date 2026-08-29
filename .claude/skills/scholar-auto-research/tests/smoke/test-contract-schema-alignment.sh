#!/usr/bin/env bash
# Regression for F16: the machine contract must declare every unconditional or
# conditional result field enforced by the verifier.
set -uo pipefail

SOURCE_SKILL="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONTRACT="$SOURCE_SKILL/references/phase-contract.json"
LINT="$SOURCE_SKILL/scripts/auto-research-contract-lint.sh"
for required in "$CONTRACT" "$LINT"; do
  [ -f "$required" ] || { echo "FATAL: missing $required" >&2; exit 1; }
done

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-schema.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$LINT" >/dev/null || fail "baseline contract lint failed"
python3 - "$CONTRACT" <<'PY' || exit 1
import json, sys
contract = json.load(open(sys.argv[1], encoding="utf-8"))
by_id = {str(p["id"]): p for p in contract["phases"]}
errors = []
for phase, fields in {
    "12": {"journal_profile_resolution", "discussion_mode"},
    "19": {"journal_profile_resolution"},
}.items():
    missing = sorted(fields - set(by_id[phase].get("pass_schema", [])))
    if missing:
        errors.append(f"phase {phase} pass_schema missing {','.join(missing)}")
conditional = by_id["18"].get("conditional_pass_schema")
expected = {
    "when": "quantitative_empirical_regression_table_required",
    "fields": ["regression_table_audit"],
}
if not isinstance(conditional, list) or expected not in conditional:
    errors.append("phase 18 conditional_pass_schema missing regression_table_audit condition")
if errors:
    for error in errors:
        print(f"FAIL: {error}")
    raise SystemExit(1)
PY

run_deletion_case() {
  local label="$1" phase="$2" kind="$3" field="$4" expected="$5"
  local copy="$TMP_ROOT/$label"
  mkdir -p "$copy"
  cp -R "$SOURCE_SKILL/." "$copy/"
  python3 - "$copy/references/phase-contract.json" "$phase" "$kind" "$field" <<'PY'
import json, sys
path, phase, kind, field = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    contract = json.load(handle)
item = next(p for p in contract["phases"] if str(p["id"]) == phase)
if kind == "pass":
    item["pass_schema"].remove(field)
else:
    item["conditional_pass_schema"] = [
        rule for rule in item.get("conditional_pass_schema", [])
        if field not in rule.get("fields", [])
    ]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(contract, handle, indent=2)
    handle.write("\n")
PY
  set +e
  local out rc
  out="$(bash "$copy/scripts/auto-research-contract-lint.sh" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "$label deletion false-greened"
  case "$out" in
    *"$expected"*) ;;
    *) fail "$label deletion returned wrong diagnostic: $out" ;;
  esac
}

run_deletion_case p12-journal 12 pass journal_profile_resolution \
  "phase 12 pass_schema must include journal_profile_resolution"
run_deletion_case p12-discussion 12 pass discussion_mode \
  "phase 12 pass_schema must include discussion_mode"
run_deletion_case p18-regression 18 conditional regression_table_audit \
  "phase 18 conditional_pass_schema must require regression_table_audit"
run_deletion_case p19-journal 19 pass journal_profile_resolution \
  "phase 19 pass_schema must include journal_profile_resolution"

echo "PASS: contract declares every verifier-required Phase 12/18/19 field"
echo "PASS: contract lint rejects deletion of each unconditional/conditional field"
