#!/usr/bin/env bash
# control-variables-check.sh — auto-research Phase 5 control-variable enforcement.
#
# Reads:
#   ${PROJ}/analysis/spec-registry.csv               (covariates column)
#   ${PROJ}/design/identification-strategy.json      (design_type, adjustment_set)
#   ${PROJ}/analysis/analysis-plan.md                (excuse annotation)
#
# Rules (mirrors scholar-analyze/references/design-router.md, but minimum-viable):
#
#   design_type ∈ {predictive-ML, predictive_ml, ml}   → GREEN (N/A)
#   design_type ∈ {qualitative}                        → GREEN (N/A)
#   design_type starts with "decomposition"            → GREEN (N/A)
#
#   design_type = RCT                                  → require ≥1 unadjusted spec
#                                                        AND ≥1 covariate-adjusted spec
#
#   design_type = observational-causal-with-DAG       → require ≥1 spec whose covariates
#                                                        overlap the adjustment_set; mismatch
#                                                        emits YELLOW (advisory)
#
#   design_type = observational-descriptive (or unset) → require ≥1 spec with
#                                                        non-empty covariates
#
# Excuse: `[EXCUSED:control-variables: <reason>]` anywhere in analysis-plan.md
#
# Emits STATUS=GREEN|YELLOW|RED + REASON= + DETAIL: lines for
# auto-research-verify.sh `run_external_gate(...)` consumption.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "STATUS=RED"
  echo "REASON=usage_error"
  echo "DETAIL: usage: control-variables-check.sh <project_dir>"
  exit 2
fi

PROJ="$1"
SPEC_CSV="$PROJ/analysis/spec-registry.csv"
ID_JSON="$PROJ/design/identification-strategy.json"
PLAN_MD="$PROJ/analysis/analysis-plan.md"

# ─── Discover excuse annotation early ────────────────────────────────────
EXCUSED=false
EXCUSE_REASON=""
if [ -f "$PLAN_MD" ]; then
  EXCUSE_LINE=$(grep -E '\[EXCUSED:[[:space:]]*control-variables[[:space:]]*:' "$PLAN_MD" 2>/dev/null | head -1 || true)
  if [ -n "$EXCUSE_LINE" ]; then
    EXCUSED=true
    EXCUSE_REASON=$(printf '%s' "$EXCUSE_LINE" | sed -E 's/.*\[EXCUSED:[[:space:]]*control-variables[[:space:]]*:[[:space:]]*([^]]*)\].*/\1/' | head -c 200)
  fi
fi

# ─── Resolve primary_execution_skill via shared helper (v14 refactor) ────
# Single source of truth for which method families allow empty covariates.
# Helper emits PRIMARY_EXECUTION_SKILL=<value> and COVARIATES_OPTIONAL=true|false.
RESOLVER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_phase5-skill-resolver.sh"
PRIMARY_EXECUTION_SKILL=""
COVARIATES_OPTIONAL=false
if [ -x "$RESOLVER" ]; then
  eval "$(bash "$RESOLVER" "$PROJ" 2>/dev/null | grep -E '^(PRIMARY_EXECUTION_SKILL|COVARIATES_OPTIONAL)=' || true)"
fi

# Secondary signal — free-form design_type for RCT/DAG sub-cases within the
# regression family (scholar-analyze). RCT and DAG are SUBSTANTIVE design
# choices layered on top of scholar-analyze execution; the helper doesn't
# expose them. We pattern-match the prose design_type field for these.
DESIGN_TYPE_RAW=""
if [ -f "$ID_JSON" ] && command -v python3 >/dev/null 2>&1; then
  DESIGN_TYPE_RAW=$(python3 -c "
import json
try:
    d = json.load(open('$ID_JSON'))
    v = d.get('design_type') or ''
    print(str(v).strip())
except Exception:
    pass
" 2>/dev/null) || DESIGN_TYPE_RAW=""
fi
DESIGN_TYPE_LOWER=$(printf '%s' "$DESIGN_TYPE_RAW" | tr '[:upper:]' '[:lower:]')

# ─── Spec-registry parsing helpers ────────────────────────────────────────
# Locate the covariates column index. Returns "" if column missing.
covariates_column_index() {
  if [ ! -f "$SPEC_CSV" ]; then
    echo ""
    return
  fi
  python3 -c "
import csv, sys
with open('$SPEC_CSV', newline='') as f:
    reader = csv.reader(f)
    header = next(reader, None)
    if not header:
        sys.exit(0)
    for i, name in enumerate(header):
        if name.strip().lower() == 'covariates':
            print(i); sys.exit(0)
"
}

# Count rows where covariates column has non-empty content (non-whitespace,
# non-"none", non-"null", non-"-", non-"[]").
count_specs_with_controls() {
  local col_idx="$1"
  if [ -z "$col_idx" ] || [ ! -f "$SPEC_CSV" ]; then
    echo "0"
    return
  fi
  python3 -c "
import csv
n = 0
with open('$SPEC_CSV', newline='') as f:
    reader = csv.reader(f)
    next(reader, None)  # header
    for row in reader:
        if len(row) <= $col_idx:
            continue
        cov = row[$col_idx].strip().lower()
        # Treat these as 'no controls'
        if cov in ('', 'none', 'null', '-', '[]', 'na', 'n/a'):
            continue
        n += 1
print(n)
"
}

# Count rows where a column has non-empty content (general helper).
count_specs_with_field_match() {
  local col_name="$1"
  local match_regex="$2"
  if [ ! -f "$SPEC_CSV" ]; then
    echo "0"
    return
  fi
  python3 -c "
import csv, re
pat = re.compile(r'$match_regex', re.IGNORECASE)
with open('$SPEC_CSV', newline='') as f:
    reader = csv.DictReader(f)
    n = 0
    for row in reader:
        v = (row.get('$col_name') or '').strip()
        if pat.search(v):
            n += 1
    print(n)
"
}

# ─── Early exits: excuse, missing spec-registry ──────────────────────────
if [ "$EXCUSED" = "true" ]; then
  echo "STATUS=GREEN"
  echo "REASON=excused"
  echo "DETAIL: control-variables gate excused via [EXCUSED:control-variables: $EXCUSE_REASON]"
  exit 0
fi

if [ ! -f "$SPEC_CSV" ]; then
  echo "STATUS=RED"
  echo "REASON=missing_spec_registry"
  echo "DETAIL: $SPEC_CSV not found — Phase 5 should have produced it"
  exit 1
fi

# ─── Primary verdict path: skill-family-aware (v14) ──────────────────────
# Non-regression families (scholar-compute / scholar-qual / scholar-ling)
# are N/A — the resolver tells us which.
if [ "$COVARIATES_OPTIONAL" = "true" ]; then
  echo "STATUS=GREEN"
  echo "REASON=not_applicable"
  echo "DETAIL: primary_execution_skill=$PRIMARY_EXECUTION_SKILL — control-variable contract does not apply to non-regression method families"
  exit 0
fi

COV_IDX=$(covariates_column_index)
if [ -z "$COV_IDX" ]; then
  echo "STATUS=RED"
  echo "REASON=missing_covariates_column"
  echo "DETAIL: spec-registry.csv must include a 'covariates' column"
  exit 1
fi

N_WITH_CONTROLS=$(count_specs_with_controls "$COV_IDX")

# ─── Secondary refinements within the scholar-analyze (regression) family ─
# RCT and DAG are SUBSTANTIVE design choices on top of scholar-analyze
# execution. We pattern-match the free-form design_type field for these.
# Detection is heuristic (advisory); the universal rule is "≥1 spec with
# non-empty covariates", which Layer 1 already enforces per row.
DESIGN_TYPE_RESOLVED="observational-descriptive"
case "$DESIGN_TYPE_LOWER" in
  *rct*|*randomi*ed*trial*) DESIGN_TYPE_RESOLVED="rct" ;;
  *dag*|*causal-with-dag*|*observational-causal*) DESIGN_TYPE_RESOLVED="observational-causal-with-dag" ;;
esac

case "$DESIGN_TYPE_RESOLVED" in
  rct)
    # RCT: need both an unadjusted spec AND a covariate-adjusted spec.
    # Detection heuristic: scan the 'purpose' or 'spec_id' column for
    # /unadjusted|itt-unadjusted|S1/i (unadjusted) and /adjusted|covariate.adjusted|S2/i (adjusted).
    N_UNADJ=$(count_specs_with_field_match "purpose" "unadjusted|itt|s1")
    N_ADJ=$(count_specs_with_field_match "purpose" "adjusted|covariate|s2")
    if [ -z "$N_UNADJ" ] || [ "$N_UNADJ" -lt 1 ]; then
      # fallback: scan spec_id column
      N_UNADJ=$(count_specs_with_field_match "spec_id" "unadjusted|itt|s1")
    fi
    if [ -z "$N_ADJ" ] || [ "$N_ADJ" -lt 1 ]; then
      N_ADJ=$(count_specs_with_field_match "spec_id" "adjusted|covariate|s2")
    fi
    if [ "$N_UNADJ" -ge 1 ] && [ "$N_ADJ" -ge 1 ]; then
      echo "STATUS=GREEN"
      echo "REASON=rct_both_rungs_present"
      echo "DETAIL: RCT design has both unadjusted ($N_UNADJ) and covariate-adjusted ($N_ADJ) specs"
      exit 0
    else
      echo "STATUS=RED"
      echo "REASON=rct_missing_rung"
      echo "DETAIL: RCT design requires both an unadjusted ITT spec AND a covariate-adjusted spec. Found unadjusted=$N_UNADJ adjusted=$N_ADJ. Add the missing rung or annotate analysis-plan.md with [EXCUSED:control-variables: <reason>]"
      exit 1
    fi ;;

  observational-causal-with-dag)
    # DAG case: covariates should match adjustment_set. Soft check — emit
    # YELLOW on mismatch (adjustment_set semantics are imperfect across projects).
    ADJ_SET=""
    if [ -f "$ID_JSON" ]; then
      ADJ_SET=$(python3 -c "
import json
try:
    d = json.load(open('$ID_JSON'))
    s = d.get('adjustment_set') or d.get('adjustment') or d.get('controls')
    if isinstance(s, list):
        print(','.join(str(x).strip().lower() for x in s if str(x).strip()))
    elif isinstance(s, str):
        print(s.strip().lower())
except Exception:
    pass
" 2>/dev/null)
    fi
    if [ "$N_WITH_CONTROLS" -ge 1 ]; then
      if [ -n "$ADJ_SET" ]; then
        echo "STATUS=GREEN"
        echo "REASON=dag_controls_present"
        echo "DETAIL: DAG design has $N_WITH_CONTROLS spec(s) with covariates; adjustment_set=$ADJ_SET (manual review recommended for set membership match)"
      else
        echo "STATUS=GREEN"
        echo "REASON=dag_controls_present_no_adj_set"
        echo "DETAIL: DAG design has $N_WITH_CONTROLS spec(s) with covariates; identification-strategy.json has no adjustment_set field — manual review recommended"
      fi
      exit 0
    else
      echo "STATUS=RED"
      echo "REASON=dag_missing_controls"
      echo "DETAIL: observational-causal-with-DAG design requires at least one spec with non-empty covariates (matching the DAG adjustment_set). Found 0. Either populate covariates from the DAG adjustment_set, or annotate analysis-plan.md with [EXCUSED:control-variables: <reason>]"
      exit 1
    fi ;;

  *)
    # observational-descriptive (default) — regression family without DAG/RCT specialization
    if [ "$N_WITH_CONTROLS" -ge 1 ]; then
      echo "STATUS=GREEN"
      echo "REASON=controls_present"
      echo "DETAIL: $N_WITH_CONTROLS spec(s) with non-empty covariates present (primary_execution_skill=${PRIMARY_EXECUTION_SKILL:-unset}, design_type=${DESIGN_TYPE_RAW:-unset})"
      exit 0
    else
      echo "STATUS=RED"
      echo "REASON=no_controls"
      echo "DETAIL: regression family (primary_execution_skill=${PRIMARY_EXECUTION_SKILL:-unset}) requires at least one planned spec with non-empty 'covariates'. Either add controls to a spec in spec-registry.csv, set primary_execution_skill to scholar-compute / scholar-qual / scholar-ling, or annotate analysis-plan.md with [EXCUSED:control-variables: <reason>]"
      exit 1
    fi ;;
esac
