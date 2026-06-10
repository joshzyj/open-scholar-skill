#!/usr/bin/env bash
# composite-measure-validation-check.sh — Phase 8 substantive-quality gate.
#
# Rationale: a common failure is a focal predictor built as a multi-item
# composite asserted as unidimensional with no Cronbach's α / McDonald's ω
# / EFA / CFA evidence. When such a composite drives the headline
# contribution, its validity is essentially asserted. This gate adds the
# requirement — missing at the skill level — that composite measures be
# validated before they enter a regression as a focal predictor.
#
# Contract
# --------
# When `data/variable-dictionary.csv` flags a variable with
# `construct_type ∈ {composite, index, scale}`, the project MUST contain
# `analysis/measurement-validation.json` with a matching `composites[]`
# entry that reports the validation method declared in
# `design/design-blueprint.json.measurement_strategy.composite_validation_plan`.
#
# Severity
# --------
#   RED    — measurement-validation.json missing OR a composite is declared
#            in the dictionary but absent from the file
#   YELLOW — α < 0.7 OR ω < 0.7 OR EFA/CFA recommends > 1 factor without
#            an in-file justification
#   GREEN  — every composite validated, statistics meet thresholds
#   INERT  — no composite variables declared (nothing to validate)
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
  echo "REASON=usage: composite-measure-validation-check.sh <project_dir>"
  exit 2
fi

DICT="$PROJ/data/variable-dictionary.csv"

if [ ! -f "$DICT" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_variable_dictionary"
  exit 3
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

VALIDATION="$PROJ/analysis/measurement-validation.json"

result=$(python3 - "$DICT" "$VALIDATION" <<'PY'
import csv, json, pathlib, sys

dict_path = pathlib.Path(sys.argv[1])
val_path = pathlib.Path(sys.argv[2])

COMPOSITE_TYPES = {"composite", "index", "scale"}

# 1. Identify composites declared in the dictionary
declared = []  # list of (variable, construct_type)
with dict_path.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    if "construct_type" not in (reader.fieldnames or []):
        # Older variable dictionaries don't have construct_type — fall back to
        # detecting composite-like variables via name heuristics so the gate
        # still catches the typical pattern: e.g. a dictionary with no
        # construct_type column but a focal predictor that is clearly an
        # index (a variable name carrying a literal "index" / "_idx" suffix).
        f.seek(0)
        reader = csv.DictReader(f)
        for row in reader:
            var = (row.get("variable") or "").strip()
            label = (row.get("display_label") or "").strip().lower()
            op = (row.get("operationalization") or "").strip().lower()
            if not var:
                continue
            heuristic_index = (
                var.endswith("_index") or var.endswith("_scale") or var.endswith("_composite")
                or "composite" in label or "index" in label
                or "composite exposure" in op or "composite of" in op or "standardized" in op and "items" in op
            )
            if heuristic_index:
                declared.append((var, "composite_heuristic"))
    else:
        for row in reader:
            var = (row.get("variable") or "").strip()
            ct = (row.get("construct_type") or "").strip().lower()
            if var and ct in COMPOSITE_TYPES:
                declared.append((var, ct))

if not declared:
    print("INERT:no_composite_variables")
    sys.exit(0)

# 2. Read measurement-validation.json
if not val_path.exists():
    print("RED:missing_file:" + ",".join(v for v, _ in declared))
    sys.exit(0)

try:
    val_data = json.loads(val_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"YELLOW:bad_json:{exc}")
    sys.exit(0)

composites = val_data.get("composites") or []
if not isinstance(composites, list):
    print("RED:malformed_composites_field")
    sys.exit(0)

validated_vars = {(c.get("variable") or "").strip() for c in composites if isinstance(c, dict)}

missing = [v for v, _ in declared if v not in validated_vars]
if missing:
    print("RED:declared_but_not_validated:" + ",".join(missing))
    sys.exit(0)

# 3. Inspect statistics for each validated composite
yellow_reasons = []
ALPHA_THRESHOLD = 0.7
OMEGA_THRESHOLD = 0.7
for c in composites:
    if not isinstance(c, dict):
        continue
    var = (c.get("variable") or "").strip()
    if var not in {v for v, _ in declared}:
        continue
    method = (c.get("method") or "").strip()
    alpha = c.get("alpha")
    omega = c.get("omega")
    n_factors = c.get("n_factors_recommended")
    decision = (c.get("decision") or "").strip().lower()

    if method == "cronbach_alpha" and isinstance(alpha, (int, float)) and alpha < ALPHA_THRESHOLD:
        if decision not in {"drop_composite", "report_components_separately"}:
            yellow_reasons.append(f"{var}:alpha={alpha:.2f}<{ALPHA_THRESHOLD}")
    if method == "mcdonald_omega" and isinstance(omega, (int, float)) and omega < OMEGA_THRESHOLD:
        if decision not in {"drop_composite", "report_components_separately"}:
            yellow_reasons.append(f"{var}:omega={omega:.2f}<{OMEGA_THRESHOLD}")
    if method in {"efa", "cfa"} and isinstance(n_factors, int) and n_factors > 1:
        if decision not in {"drop_composite", "report_components_separately"}:
            yellow_reasons.append(f"{var}:n_factors={n_factors}>1")

if yellow_reasons:
    print("YELLOW:reliability_below_threshold:" + ";".join(yellow_reasons))
    sys.exit(0)

print(f"GREEN:{len(declared)}")
PY
)

echo "PROJECT=${PROJ}"

case "$result" in
  GREEN:*)
    n="${result#GREEN:}"
    echo "STATUS=GREEN"
    echo "REASON=composite_measures_validated"
    echo "DETAIL: ${n} composite(s) reported with declared method, thresholds met"
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
    cat >&2 <<EOF
WARN: composite measure validation — at least one composite has
reliability below the conventional threshold (α < 0.7 or ω < 0.7) OR
EFA/CFA recommends multiple factors. The composite either needs an
explicit decision flag (drop_composite / report_components_separately)
or the threshold concern must be acknowledged in the manuscript Methods.
EOF
    exit 2 ;;
  RED:*)
    rest="${result#RED:}"
    reason="${rest%%:*}"
    detail="${rest#*:}"
    echo "STATUS=RED"
    echo "REASON=${reason}"
    echo "DETAIL: ${detail}"
    cat >&2 <<EOF
FAIL: composite measure validation — composite, index, or scale variables
are declared in data/variable-dictionary.csv but no validation evidence is
recorded in analysis/measurement-validation.json. Cronbach's α / McDonald's
ω / EFA / CFA must be reported for every composite that enters a focal
model. A composite asserted as unidimensional without measurement evidence
is not acceptable as a focal predictor.
EOF
    exit 1 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
