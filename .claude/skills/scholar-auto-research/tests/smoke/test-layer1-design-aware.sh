#!/usr/bin/env bash
# Integration test for design-aware Layer 1 in auto-research-verify.sh Phase 5.
#
# Strategy: reuse the vendored lightweight Phase 5 seed. Copy it, mutate
# identification-strategy.json + spec-registry.csv, run verify.sh 5, and
# assert on the FAIL message content.
#
# Falsifiable observable: the SAME spec-registry with empty covariates should
# produce different verify.sh 5 outcomes depending on primary_execution_skill.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$SKILL_DIR/scripts/auto-research-verify.sh"
SRC="$SKILL_DIR/tests/fixtures/phase5-seed"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-layer1.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
[ -d "$SRC" ] || { echo "FAIL: missing vendored Phase 5 seed: $SRC"; exit 1; }

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

echo "Source fixture: vendored Phase 5 seed"

# Clone the fixture to a fresh dir for each test (so we never mutate the source).
clone_fixture() {
  local dest; dest=$(mktemp -d "$TMP_ROOT/case.XXXXXX")
  cp -R "$SRC"/. "$dest"/
  echo "$dest"
}

# Mutate primary_execution_skill in identification-strategy.json
set_skill() {
  local proj="$1" skill="$2"
  python3 -c "
import json
path = '$proj/design/identification-strategy.json'
d = json.load(open(path))
d.setdefault('method_specialist_routing', {})['primary_execution_skill'] = '$skill'
d['method_specialist_routing']['premortem_skill'] = '$skill'  # contract requires both
json.dump(d, open(path, 'w'), indent=2)
"
}

# Clear all covariates cells in spec-registry.csv
clear_covariates() {
  local proj="$1"
  python3 -c "
import csv
path = '$proj/analysis/spec-registry.csv'
rows = list(csv.reader(open(path)))
header = rows[0]
ci = header.index('covariates')
for r in rows[1:]:
    if len(r) > ci: r[ci] = ''
with open(path, 'w', newline='') as f:
    w = csv.writer(f); w.writerows(rows)
"
}

# ── T1: scholar-analyze + empty covariates → FAIL with "covariates" in error ──
echo ""
echo "=== T1: scholar-analyze (regression) + empty covariates → FAIL on covariates ==="
P=$(clone_fixture)
set_skill "$P" "scholar-analyze"
clear_covariates "$P"
OUT=$(bash "$VERIFY" 5 "$P" 2>&1); RC=$?
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE "row [0-9]+ covariates"; then
  note PASS "T1: scholar-analyze + empty covariates → FAIL mentions 'covariates' (Layer 1 blocks as expected)"
else
  note FAIL "T1: expected FAIL with 'row N covariates'. Got: $(echo "$OUT" | head -3)"
fi
rm -rf "$P"

# ── T2: scholar-compute + empty covariates → Layer 1 ADVANCES past covariates ──
echo ""
echo "=== T2: scholar-compute (ML) + empty covariates → Layer 1 advances past covariates ==="
P=$(clone_fixture)
set_skill "$P" "scholar-compute"
clear_covariates "$P"
OUT=$(bash "$VERIFY" 5 "$P" 2>&1); RC=$?
# The mutation intentionally invalidates the manifest hash after Layer 1. Pin
# that exact downstream sentinel so an unrelated early failure cannot pass.
if [ "$RC" -eq 1 ] \
   && ! printf '%s\n' "$OUT" | grep -qE "row [0-9]+ covariates" \
   && printf '%s\n' "$OUT" | grep -q 'FAIL: Phase 5 analysis-plan manifest source_hashes are stale' \
   && printf '%s\n' "$OUT" | grep -q 'identification_strategy mismatch'; then
  note PASS "T2: scholar-compute bypasses covariates and reaches exact stale-hash sentinel"
else
  note FAIL "T2: scholar-compute should bypass covariates emptiness check. Got: $(echo "$OUT" | head -3)"
fi
rm -rf "$P"

# ── T3: scholar-qual + empty covariates → Layer 1 ADVANCES past covariates ──
echo ""
echo "=== T3: scholar-qual + empty covariates → Layer 1 advances past covariates ==="
P=$(clone_fixture)
set_skill "$P" "scholar-qual"
clear_covariates "$P"
OUT=$(bash "$VERIFY" 5 "$P" 2>&1); RC=$?
if [ "$RC" -eq 1 ] \
   && ! printf '%s\n' "$OUT" | grep -qE "row [0-9]+ covariates" \
   && printf '%s\n' "$OUT" | grep -q 'FAIL: Phase 5 analysis-plan manifest source_hashes are stale' \
   && printf '%s\n' "$OUT" | grep -q 'identification_strategy mismatch'; then
  note PASS "T3: scholar-qual bypasses covariates and reaches exact stale-hash sentinel"
else
  note FAIL "T3: scholar-qual should bypass covariates emptiness check. Got: $(echo "$OUT" | head -3)"
fi
rm -rf "$P"

# ── T4: pristine fixture (scholar-analyze + populated covariates) → no regression ──
echo ""
echo "=== T4: pristine fixture → Phase 5 passes (no regression on baseline) ==="
P=$(clone_fixture)
# Do NOT mutate the fixture — verify the baseline still passes after my edits.
# (Mutating identification-strategy.json invalidates the source-hash in the
# analysis-plan manifest, which is a separate failure mode unrelated to
# Layer 1's design-awareness.)
OUT=$(bash "$VERIFY" 5 "$P" 2>&1); RC=$?
if [ "$RC" = "0" ]; then
  note PASS "T4: pristine fixture → Phase 5 PASS (no regression from my Layer 1 patch)"
else
  note FAIL "T4 (rc=$RC): expected Phase 5 PASS. Got: $(echo "$OUT" | head -5)"
fi
rm -rf "$P"

echo ""
echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
echo "===================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
