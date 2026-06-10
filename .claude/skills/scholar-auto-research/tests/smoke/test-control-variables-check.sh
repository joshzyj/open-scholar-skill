#!/usr/bin/env bash
# Smoke tests for scholar-auto-research control-variables-check.sh gate.
# Self-contained within scholar-auto-research.

set -u

GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/gates" && pwd)/control-variables-check.sh"

PASS=0
FAIL=0
note() {
  local outcome="$1"; shift
  if [ "$outcome" = "PASS" ]; then
    PASS=$((PASS + 1)); echo "  ✓ $*"
  else
    FAIL=$((FAIL + 1)); echo "  ✗ $*"
  fi
}

# Helper: build a minimal project with given design_type label and spec rows.
# v14 pivot: maps the legacy design_type label to the controlled-vocabulary
# `method_specialist_routing.primary_execution_skill` used by the resolver.
# Mapping:
#   observational-descriptive | observational-causal-with-DAG | RCT → scholar-analyze
#   predictive-ML                                                   → scholar-compute
#   qualitative                                                     → scholar-qual
#   decomposition:*                                                 → scholar-analyze (decomposition is a scholar-analyze sub-family)
build_proj() {
  local design_type="$1"; shift
  local P; P=$(mktemp -d)
  mkdir -p "$P/analysis" "$P/design"
  cat > "$P/analysis/spec-registry.csv" <<'HDR'
spec_id,model_id,hypothesis_ids,outcome,predictors,covariates,estimator,purpose,robustness_type,missing_data_strategy,status
HDR
  for row in "$@"; do
    printf '%s\n' "$row" >> "$P/analysis/spec-registry.csv"
  done
  if [ -n "$design_type" ]; then
    local skill
    case "$design_type" in
      predictive-ML|predictive_ml|ml) skill=scholar-compute ;;
      qualitative)                    skill=scholar-qual ;;
      *)                              skill=scholar-analyze ;;
    esac
    cat > "$P/design/identification-strategy.json" <<EOF
{"design_type": "$design_type", "method_specialist_routing": {"primary_execution_skill": "$skill"}}
EOF
  fi
  touch "$P/analysis/analysis-plan.md"
  echo "$P"
}

# ── T1: observational-descriptive + spec with non-empty covariates → GREEN ──
echo ""
echo "=== T1: observational-descriptive + controls present → GREEN ==="
P=$(build_proj "observational-descriptive" \
  "desc:M2,M2,H1,Y,X,age+income+edu,lm,with_controls,baseline,complete-case,planned")
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && echo "$OUT" | grep -q "REASON=controls_present" && [ "$RC" = "0" ]; then
  note PASS "T1: GREEN with controls present"
else
  note FAIL "T1 (rc=$RC): expected GREEN+controls_present. Got: $OUT"
fi
rm -rf "$P"

# ── T2: observational-descriptive + all empty covariates → RED ──
echo ""
echo "=== T2: observational-descriptive + no controls → RED ==="
P=$(build_proj "observational-descriptive" \
  "desc:M1,M1,H1,Y,X,,lm,bivariate,baseline,complete-case,planned")
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=RED" && echo "$OUT" | grep -q "REASON=no_controls" && [ "$RC" = "1" ]; then
  note PASS "T2: RED with no controls"
else
  note FAIL "T2 (rc=$RC): expected RED+no_controls. Got: $OUT"
fi
rm -rf "$P"

# ── T3: predictive-ML design type → GREEN (N/A) ──
echo ""
echo "=== T3: predictive-ML → GREEN (N/A) ==="
P=$(build_proj "predictive-ML" \
  "ml:holdout-v1,ML1,H1,Y,X,,xgb,holdout,n/a,complete-case,planned")
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && echo "$OUT" | grep -q "REASON=not_applicable" && [ "$RC" = "0" ]; then
  note PASS "T3: GREEN N/A for predictive-ML"
else
  note FAIL "T3 (rc=$RC): expected GREEN+not_applicable. Got: $OUT"
fi
rm -rf "$P"

# ── T4: qualitative design type → GREEN (N/A) ──
echo ""
echo "=== T4: qualitative → GREEN (N/A) ==="
P=$(build_proj "qualitative" \
  "qual:M1,M1,H1,interview,theme,,coding,thematic,n/a,n/a,planned")
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && echo "$OUT" | grep -q "REASON=not_applicable" && [ "$RC" = "0" ]; then
  note PASS "T4: GREEN N/A for qualitative"
else
  note FAIL "T4 (rc=$RC): expected GREEN+not_applicable. Got: $OUT"
fi
rm -rf "$P"

# ── T5: observational-causal-with-DAG + controls present → GREEN ──
echo ""
echo "=== T5: causal-with-DAG + DAG-implied controls → GREEN ==="
P=$(build_proj "observational-causal-with-DAG" \
  "dag:focal,DAG1,H1,Y,X,age+race+edu,lm,focal,causal,complete-case,planned")
# Add adjustment_set to identification-strategy.json (preserve routing field — v14)
cat > "$P/design/identification-strategy.json" <<'EOF'
{"design_type": "observational-causal-with-DAG", "adjustment_set": ["age", "race", "edu"], "method_specialist_routing": {"primary_execution_skill": "scholar-analyze"}}
EOF
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && [ "$RC" = "0" ]; then
  note PASS "T5: GREEN for DAG with controls present"
else
  note FAIL "T5 (rc=$RC): expected GREEN. Got: $OUT"
fi
rm -rf "$P"

# ── T6: observational-causal-with-DAG + missing controls → RED ──
echo ""
echo "=== T6: causal-with-DAG + missing controls → RED ==="
P=$(build_proj "observational-causal-with-DAG" \
  "dag:focal,DAG1,H1,Y,X,,lm,focal,causal,complete-case,planned")
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=RED" && echo "$OUT" | grep -q "REASON=dag_missing_controls" && [ "$RC" = "1" ]; then
  note PASS "T6: RED for DAG missing controls"
else
  note FAIL "T6 (rc=$RC): expected RED+dag_missing_controls. Got: $OUT"
fi
rm -rf "$P"

# ── T7: RCT with both unadjusted + adjusted → GREEN ──
echo ""
echo "=== T7: RCT with S1 unadjusted + S2 adjusted → GREEN ==="
P=$(build_proj "RCT" \
  "rct:S1,S1,H1,Y,X,,lm,unadjusted-ITT,baseline,complete-case,planned" \
  "rct:S2,S2,H1,Y,X,age+sex,lm,covariate-adjusted,baseline,complete-case,planned")
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && echo "$OUT" | grep -q "REASON=rct_both_rungs_present" && [ "$RC" = "0" ]; then
  note PASS "T7: GREEN for RCT with both rungs"
else
  note FAIL "T7 (rc=$RC): expected GREEN+rct_both_rungs_present. Got: $OUT"
fi
rm -rf "$P"

# ── T8: RCT missing the unadjusted rung → RED ──
echo ""
echo "=== T8: RCT missing unadjusted rung → RED ==="
P=$(build_proj "RCT" \
  "rct:S2,S2,H1,Y,X,age+sex,lm,covariate-adjusted,baseline,complete-case,planned")
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=RED" && echo "$OUT" | grep -q "REASON=rct_missing_rung" && [ "$RC" = "1" ]; then
  note PASS "T8: RED for RCT missing rung"
else
  note FAIL "T8 (rc=$RC): expected RED+rct_missing_rung. Got: $OUT"
fi
rm -rf "$P"

# ── T9: excuse annotation → GREEN ──
echo ""
echo "=== T9: excuse annotation → GREEN ==="
P=$(build_proj "observational-descriptive" \
  "desc:M1,M1,H1,Y,X,,lm,bivariate,baseline,complete-case,planned")
printf '\n[EXCUSED:control-variables: tutorial project — no controls needed]\n' >> "$P/analysis/analysis-plan.md"
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && echo "$OUT" | grep -q "REASON=excused" && [ "$RC" = "0" ]; then
  note PASS "T9: GREEN with excuse annotation"
else
  note FAIL "T9 (rc=$RC): expected GREEN+excused. Got: $OUT"
fi
rm -rf "$P"

# ── T10: missing identification-strategy.json → defaults to strict regression ──
echo ""
echo "=== T10: missing identification-strategy.json + controls present → GREEN (default strict, but controls present) ==="
P=$(build_proj "" \
  "desc:M2,M2,H1,Y,X,age+income,lm,with_controls,baseline,complete-case,planned")
# build_proj with empty design_type already skips writing the JSON file
[ -f "$P/design/identification-strategy.json" ] && rm "$P/design/identification-strategy.json"
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
# v14: when identification-strategy.json is missing, resolver returns COVARIATES_OPTIONAL=false
# (safe default), and the gate falls into the regression default branch. Controls are
# present, so STATUS=GREEN+REASON=controls_present.
if echo "$OUT" | grep -q "STATUS=GREEN" && echo "$OUT" | grep -q "REASON=controls_present" && [ "$RC" = "0" ]; then
  note PASS "T10: GREEN+controls_present when ID file missing (safe default strict + populated covariates)"
else
  note FAIL "T10 (rc=$RC): expected GREEN+controls_present. Got: $OUT"
fi
rm -rf "$P"

# ── T11: decomposition → semantic CHANGE in v14 ──
# Decomposition is done by scholar-analyze (it's a quantitative sub-family).
# Under v14, primary_execution_skill=scholar-analyze → covariates REQUIRED.
# Projects that genuinely have no controls in a decomposition spec must use
# the [EXCUSED:control-variables: <reason>] annotation.
echo ""
echo "=== T11: decomposition + empty covariates → RED (v14 semantic — use excuse to opt out) ==="
P=$(build_proj "decomposition:Oaxaca" \
  "oaxaca:threefold,Oaxaca1,H1,Y,X,,Oaxaca-Blinder,decomposition,n/a,complete-case,planned")
OUT=$(bash "$GATE" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "STATUS=RED" && echo "$OUT" | grep -q "REASON=no_controls" && [ "$RC" = "1" ]; then
  note PASS "T11: decomposition under scholar-analyze → strict (use excuse for opt-out)"
else
  note FAIL "T11 (rc=$RC): expected RED+no_controls (v14 semantic). Got: $OUT"
fi
rm -rf "$P"

echo ""
echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
echo "===================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
