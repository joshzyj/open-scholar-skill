#!/usr/bin/env bash
# descriptives-coverage-check.sh — Phase 8 / Phase 13 coverage gate.
#
# Rationale: a common failure is a descriptives script that builds
# `tables/table1-descriptives.csv` from a HARDCODED variable subset rather
# than from the live spec-registry × variable-dictionary. Every modeled
# variable should have a descriptive row; this gate closes the gap that
# would otherwise let a hardcoded subset pass.
#
# Contract
# --------
# Every variable that appears in `analysis/spec-registry.csv` columns
# `outcome`, `predictors`, or `covariates` (semicolon-separated lists)
# AND is listed in `data/variable-dictionary.csv` MUST have a row in at
# least one descriptive table:
#   - tables/table1-descriptives.csv          (main-text Table 1)
#   - tables/table-descriptives-all-variables.csv  (appendix coverage)
# The display venue is journal-controlled; the COVERAGE is non-negotiable.
#
# Matching is fuzzy by design — Table 1 may use the dictionary's
# `display_label` rather than the raw `variable` name, so we accept
# either (lowercased, alphanumeric-normalized).
#
# Inputs
# ------
#   $1   project directory (required)
#
# Exit codes
# ----------
#   0  STATUS=GREEN   every modeled variable has a descriptive row
#   1  STATUS=RED     ≥1 modeled variable is missing from all descriptive
#                     tables AND no override is declared
#   2  STATUS=YELLOW  inputs are not yet present (Phase 8 has not run)
#   3  STATUS=INERT   no analysis/spec-registry.csv (no quant work)

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: descriptives-coverage-check.sh <project_dir>"
  exit 2
fi

SPEC="$PROJ/analysis/spec-registry.csv"
DICT="$PROJ/data/variable-dictionary.csv"

if [ ! -f "$SPEC" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_spec_registry"
  exit 3
fi

if [ ! -f "$DICT" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_variable_dictionary"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

DESC_MAIN="$PROJ/tables/table1-descriptives.csv"
DESC_APPX="$PROJ/tables/table-descriptives-all-variables.csv"

result=$(python3 - "$SPEC" "$DICT" "$DESC_MAIN" "$DESC_APPX" <<'PY'
import csv, re, sys, pathlib

spec_path, dict_path, desc_main_path, desc_appx_path = (pathlib.Path(p) for p in sys.argv[1:5])

def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s or "").lower()).strip()

# 1. Collect modeled variables from spec-registry
modeled = set()
with spec_path.open(newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        for col in ("outcome", "predictors", "covariates"):
            cell = row.get(col, "") or ""
            for v in cell.split(";"):
                v = v.strip()
                if v:
                    modeled.add(v)

if not modeled:
    print("INERT:no_modeled_variables")
    sys.exit(0)

# 2. Build dictionary mapping (variable -> display_label)
dict_rows = {}
display_labels = {}
with dict_path.open(newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        var = (row.get("variable") or "").strip()
        if not var:
            continue
        dict_rows[var] = row
        for label_field in ("display_label", "table_stub_label", "manuscript_term"):
            label = (row.get(label_field) or "").strip()
            if label:
                display_labels.setdefault(var, set()).add(norm(label))

# 3. Collect names appearing in any descriptive table (column 1, or columns
# `variable` / `Variable` / `display_label` if present).
seen_names = set()
def ingest_descriptive(path):
    if not path.exists():
        return
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)
    if not rows:
        return
    header = [norm(h) for h in rows[0]]
    name_col_idx = 0
    for cand in ("variable", "display label", "label", "term", "name"):
        if cand in header:
            name_col_idx = header.index(cand); break
    for r in rows[1:]:
        if len(r) > name_col_idx:
            seen_names.add(norm(r[name_col_idx]))

ingest_descriptive(desc_main_path)
ingest_descriptive(desc_appx_path)

# 4. For each modeled variable, accept if either the raw variable name OR
# any of its display labels appears among seen_names.
missing = []
for v in sorted(modeled):
    if v not in dict_rows:
        # Variable not in dictionary — different concern, not this gate.
        continue
    candidates = {norm(v)} | display_labels.get(v, set())
    if not (candidates & seen_names):
        missing.append(v)

if missing:
    print("RED:" + ",".join(missing))
else:
    print("GREEN:" + str(len(modeled)))
PY
)

echo "PROJECT=${PROJ}"

case "$result" in
  GREEN:*)
    count="${result#GREEN:}"
    echo "STATUS=GREEN"
    echo "REASON=all_modeled_variables_covered"
    echo "DETAIL: ${count} modeled variables, all present in descriptive table(s)"
    exit 0 ;;
  INERT:*)
    echo "STATUS=INERT"
    echo "REASON=${result#INERT:}"
    exit 3 ;;
  RED:*)
    missing="${result#RED:}"
    echo "STATUS=RED"
    echo "REASON=descriptives_coverage_gap"
    echo "DETAIL: missing=${missing}"
    cat >&2 <<EOF
FAIL: descriptive table coverage — modeled variable(s) appear in the
spec-registry's outcome / predictors / covariates AND in the variable
dictionary, but are absent from every descriptive table:
  ${missing}
Either include them in tables/table1-descriptives.csv (main-text Table 1)
or in tables/table-descriptives-all-variables.csv (appendix coverage).
A hardcoded subset of variables is not acceptable; descriptives must be
driven from the spec-registry.
EOF
    exit 1 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
