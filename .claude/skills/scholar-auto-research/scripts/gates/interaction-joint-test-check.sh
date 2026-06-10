#!/usr/bin/env bash
# interaction-joint-test-check.sh — Phase 8 substantive-quality gate.
#
# Rationale: a common failure is a model that declares several interaction
# terms (e.g. treatment_x_education, treatment_x_region, treatment_x_cohort)
# whose Results prose interprets them as a "stratified pattern" without any
# joint-test evidence that the interaction block significantly improved fit.
# Reading individual interaction estimates against zero is not the same as
# testing whether the moderation set jointly matters.
#
# Contract
# --------
# Every spec in `analysis/spec-registry.csv` whose `predictors` column
# contains an interaction marker (`*`, `:`, or `_x_` slug between two
# variable names) MUST have a corresponding entry in
# `analysis/joint-tests.json` reporting the inference method declared in
# `design/design-blueprint.json.analytic_strategy.interaction_inference_policy`.
#
# Severity
# --------
#   RED    — interaction declared in spec but joint test missing
#   YELLOW — joint test method does not match declared policy
#   GREEN  — every interaction-bearing spec has a matching joint test
#   INERT  — no interaction terms in any spec (nothing to test)
#
# Inputs
# ------
#   $1   project directory (required)
#
# Exit codes
# ----------
#   0  STATUS=GREEN
#   1  STATUS=RED
#   2  STATUS=YELLOW
#   3  STATUS=INERT
#

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: interaction-joint-test-check.sh <project_dir>"
  exit 2
fi

SPEC="$PROJ/analysis/spec-registry.csv"
if [ ! -f "$SPEC" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_spec_registry"
  exit 3
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

JT="$PROJ/analysis/joint-tests.json"
BLUEPRINT="$PROJ/design/design-blueprint.json"

result=$(python3 - "$SPEC" "$JT" "$BLUEPRINT" <<'PY'
import csv, json, pathlib, re, sys

spec_path, jt_path, blueprint_path = (pathlib.Path(p) for p in sys.argv[1:4])

# Detect interaction markers in predictor strings.
# Patterns:
#   - R formula style: x1*x2 or x1:x2
#   - Slug style: x1_x_x2 (e.g. treatment_x_education)
INTERACTION_PATTERNS = [
    re.compile(r"[A-Za-z0-9_]+\s*\*\s*[A-Za-z0-9_]+"),
    re.compile(r"[A-Za-z0-9_]+\s*:\s*[A-Za-z0-9_]+"),
    re.compile(r"[A-Za-z0-9_]+_x_[A-Za-z0-9_]+"),
]

def has_interaction(predictor_cell):
    if not predictor_cell:
        return False
    return any(p.search(predictor_cell) for p in INTERACTION_PATTERNS)

def extract_interaction_terms(predictor_cell):
    terms = []
    for p in INTERACTION_PATTERNS:
        for m in p.finditer(predictor_cell or ""):
            terms.append(m.group(0).strip())
    return sorted(set(terms))

# 1. Identify interaction-bearing specs
interaction_specs = []
with spec_path.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        spec_id = (row.get("spec_id") or "").strip()
        predictors = row.get("predictors") or ""
        if has_interaction(predictors):
            interaction_specs.append({
                "spec_id": spec_id,
                "interaction_terms": extract_interaction_terms(predictors),
                "status": (row.get("status") or "").strip(),
            })

if not interaction_specs:
    print("INERT:no_interaction_specs")
    sys.exit(0)

# 2. Read declared inference policy from blueprint (best-effort)
declared_method = None
if blueprint_path.exists():
    try:
        bp = json.loads(blueprint_path.read_text(encoding="utf-8"))
        declared_method = ((bp.get("analytic_strategy") or {})
                            .get("interaction_inference_policy"))
        if declared_method:
            declared_method = str(declared_method).strip()
    except Exception:
        pass

# 3. Read joint-tests.json
if not jt_path.exists():
    missing = [s["spec_id"] for s in interaction_specs]
    print("RED:missing_file:" + ",".join(missing))
    sys.exit(0)

try:
    jt_data = json.loads(jt_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"YELLOW:bad_json:{exc}")
    sys.exit(0)

joint_tests = jt_data.get("joint_tests") or []
if not isinstance(joint_tests, list):
    print("RED:malformed_joint_tests_field")
    sys.exit(0)

tested_spec_ids = {(t.get("spec_id") or "").strip()
                   for t in joint_tests if isinstance(t, dict)}

missing = [s["spec_id"] for s in interaction_specs if s["spec_id"] not in tested_spec_ids]
if missing:
    print("RED:declared_but_not_tested:" + ",".join(missing))
    sys.exit(0)

# 4. Method-match check (YELLOW if mismatch)
if declared_method:
    mismatches = []
    for t in joint_tests:
        if not isinstance(t, dict):
            continue
        spec_id = (t.get("spec_id") or "").strip()
        method = (t.get("method") or "").strip()
        if spec_id in {s["spec_id"] for s in interaction_specs} and method and method != declared_method:
            mismatches.append(f"{spec_id}:declared={declared_method}:got={method}")
    if mismatches:
        print("YELLOW:method_mismatch:" + ";".join(mismatches))
        sys.exit(0)

print(f"GREEN:{len(interaction_specs)}")
PY
)

echo "PROJECT=${PROJ}"

case "$result" in
  GREEN:*)
    n="${result#GREEN:}"
    echo "STATUS=GREEN"
    echo "REASON=interactions_jointly_tested"
    echo "DETAIL: ${n} interaction-bearing spec(s) reported with joint test"
    exit 0 ;;
  INERT:*)
    echo "STATUS=INERT"
    echo "REASON=${result#INERT:}"
    exit 3 ;;
  YELLOW:*)
    rest="${result#YELLOW:}"
    echo "STATUS=YELLOW"
    echo "REASON=${rest%%:*}"
    echo "DETAIL: ${rest#*:}"
    exit 2 ;;
  RED:*)
    rest="${result#RED:}"
    reason="${rest%%:*}"
    detail="${rest#*:}"
    echo "STATUS=RED"
    echo "REASON=${reason}"
    echo "DETAIL: ${detail}"
    cat >&2 <<EOF
FAIL: interaction joint-test — at least one spec in spec-registry.csv
declares interaction terms but no corresponding entry exists in
analysis/joint-tests.json. Heterogeneity claims require a joint Wald,
likelihood-ratio, or block-F test of the interaction set, not just
individual interaction-term coefficients.
EOF
    exit 1 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
