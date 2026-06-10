#!/usr/bin/env bash
# Smoke tests for _phase5-skill-resolver.sh — the shared design-aware
# helper used by both Layer 1 (verify.sh Phase 5) and Layer 2
# (control-variables-check.sh).

set -u

HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/gates" && pwd)/_phase5-skill-resolver.sh"

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

# Build a minimal project with given JSON content for identification-strategy.json.
# Pass "__SKIP__" to skip writing the file entirely.
build_proj() {
  local payload="$1"
  local P; P=$(mktemp -d)
  mkdir -p "$P/design"
  if [ "$payload" != "__SKIP__" ]; then
    printf '%s' "$payload" > "$P/design/identification-strategy.json"
  fi
  echo "$P"
}

# ── T1: scholar-analyze → COVARIATES_OPTIONAL=false ──
echo ""
echo "=== T1: scholar-analyze (regression) → COVARIATES_OPTIONAL=false ==="
P=$(build_proj '{"method_specialist_routing":{"primary_execution_skill":"scholar-analyze"}}')
OUT=$(bash "$HELPER" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=scholar-analyze$" \
   && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=false$" && [ "$RC" = "0" ]; then
  note PASS "T1: scholar-analyze → strict"
else
  note FAIL "T1 (rc=$RC): expected strict for scholar-analyze. Got: $OUT"
fi
rm -rf "$P"

# ── T2: scholar-compute → COVARIATES_OPTIONAL=true ──
echo ""
echo "=== T2: scholar-compute → COVARIATES_OPTIONAL=true ==="
P=$(build_proj '{"method_specialist_routing":{"primary_execution_skill":"scholar-compute"}}')
OUT=$(bash "$HELPER" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=scholar-compute$" \
   && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=true$" && [ "$RC" = "0" ]; then
  note PASS "T2: scholar-compute → optional"
else
  note FAIL "T2 (rc=$RC): expected optional for scholar-compute. Got: $OUT"
fi
rm -rf "$P"

# ── T3: scholar-qual → COVARIATES_OPTIONAL=true ──
echo ""
echo "=== T3: scholar-qual → COVARIATES_OPTIONAL=true ==="
P=$(build_proj '{"method_specialist_routing":{"primary_execution_skill":"scholar-qual"}}')
OUT=$(bash "$HELPER" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=scholar-qual$" \
   && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=true$" && [ "$RC" = "0" ]; then
  note PASS "T3: scholar-qual → optional"
else
  note FAIL "T3 (rc=$RC): expected optional for scholar-qual. Got: $OUT"
fi
rm -rf "$P"

# ── T4: scholar-ling → COVARIATES_OPTIONAL=true ──
echo ""
echo "=== T4: scholar-ling → COVARIATES_OPTIONAL=true ==="
P=$(build_proj '{"method_specialist_routing":{"primary_execution_skill":"scholar-ling"}}')
OUT=$(bash "$HELPER" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=scholar-ling$" \
   && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=true$" && [ "$RC" = "0" ]; then
  note PASS "T4: scholar-ling → optional"
else
  note FAIL "T4 (rc=$RC): expected optional for scholar-ling. Got: $OUT"
fi
rm -rf "$P"

# ── T5: missing identification-strategy.json → safe default ──
echo ""
echo "=== T5: missing identification-strategy.json → safe default (strict) ==="
P=$(build_proj "__SKIP__")
OUT=$(bash "$HELPER" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=$" \
   && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=false$" && [ "$RC" = "0" ]; then
  note PASS "T5: missing file → empty PRIMARY + strict (safe default)"
else
  note FAIL "T5 (rc=$RC): expected safe default. Got: $OUT"
fi
rm -rf "$P"

# ── T6: malformed JSON → safe default ──
echo ""
echo "=== T6: malformed JSON → safe default (strict) ==="
P=$(build_proj '{this is not valid json')
OUT=$(bash "$HELPER" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=$" \
   && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=false$" && [ "$RC" = "0" ]; then
  note PASS "T6: malformed JSON → safe default"
else
  note FAIL "T6 (rc=$RC): expected safe default. Got: $OUT"
fi
rm -rf "$P"

# ── T7: missing method_specialist_routing → safe default ──
echo ""
echo "=== T7: routing object absent → safe default (strict) ==="
P=$(build_proj '{"design_type":"observational panel design","claim_strength":"associational"}')
OUT=$(bash "$HELPER" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=$" \
   && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=false$" && [ "$RC" = "0" ]; then
  note PASS "T7: no routing object → safe default"
else
  note FAIL "T7 (rc=$RC): expected safe default. Got: $OUT"
fi
rm -rf "$P"

# ── T8: unknown skill value → safe default ──
echo ""
echo "=== T8: unrecognized skill value → safe default (strict) ==="
P=$(build_proj '{"method_specialist_routing":{"primary_execution_skill":"scholar-something-new"}}')
OUT=$(bash "$HELPER" "$P" 2>&1); RC=$?
if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=scholar-something-new$" \
   && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=false$" && [ "$RC" = "0" ]; then
  note PASS "T8: unknown skill → strict but PRIMARY echoed for debugging"
else
  note FAIL "T8 (rc=$RC): expected strict + echoed value. Got: $OUT"
fi
rm -rf "$P"

# ── T9: usage error (no args) → rc=2 + safe-default output ──
echo ""
echo "=== T9: usage error (no args) → rc=2 ==="
OUT=$(bash "$HELPER" 2>&1); RC=$?
if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=$" \
   && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=false$" \
   && echo "$OUT" | grep -q "ERROR=usage" && [ "$RC" = "2" ]; then
  note PASS "T9: usage error → rc=2 with safe-default stdout"
else
  note FAIL "T9 (rc=$RC): expected usage error rc=2. Got: $OUT"
fi

# ── T10: real fixture (if available) ──
echo ""
echo "=== T10: bundled fixture preexec-project → scholar-analyze ==="
FP=$(ls -td /tmp/scholar-auto-research-fixture-* 2>/dev/null | head -1)
if [ -d "$FP/preexec-project" ]; then
  OUT=$(bash "$HELPER" "$FP/preexec-project" 2>&1); RC=$?
  if echo "$OUT" | grep -q "^PRIMARY_EXECUTION_SKILL=scholar-analyze$" \
     && echo "$OUT" | grep -q "^COVARIATES_OPTIONAL=false$" && [ "$RC" = "0" ]; then
    note PASS "T10: bundled fixture → scholar-analyze, strict"
  else
    note FAIL "T10 (rc=$RC): bundled fixture output unexpected. Got: $OUT"
  fi
else
  echo "  ⊘ T10 skipped (no /tmp/scholar-auto-research-fixture-* available; run auto-research-fixture-test.sh first)"
fi

echo ""
echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
echo "===================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
