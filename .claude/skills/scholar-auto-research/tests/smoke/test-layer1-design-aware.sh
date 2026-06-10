#!/usr/bin/env bash
# Integration test for design-aware Layer 1 in auto-research-verify.sh Phase 5.
#
# Strategy: reuse the bundled fixture-test's preexec-project. Copy it, mutate
# identification-strategy.json + spec-registry.csv, run verify.sh 5, and
# assert on the FAIL message content.
#
# Falsifiable observable: the SAME spec-registry with empty covariates should
# produce different verify.sh 5 outcomes depending on primary_execution_skill.

set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$SKILL_DIR/scripts/auto-research-verify.sh"

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

# Materialize the bundled fixture if not already present. The fixture-test
# fails at Phase 8 (pre-existing unrelated bug) but creates Phases 0-7
# fixtures cleanly. We only need the preexec-project for Phase 5.
ensure_fixture() {
  local existing
  existing=$(ls -td /tmp/scholar-auto-research-fixture-* 2>/dev/null | head -1)
  if [ -n "$existing" ] && [ -d "$existing/preexec-project" ]; then
    echo "$existing/preexec-project"
    return 0
  fi
  echo "Materializing bundled fixture (this takes ~60 seconds)..." >&2
  bash "$SKILL_DIR/scripts/auto-research-fixture-test.sh" >/dev/null 2>&1 || true
  existing=$(ls -td /tmp/scholar-auto-research-fixture-* 2>/dev/null | head -1)
  if [ -n "$existing" ] && [ -d "$existing/preexec-project" ]; then
    echo "$existing/preexec-project"
    return 0
  fi
  echo "ERROR: could not materialize fixture" >&2
  return 1
}

SRC=$(ensure_fixture) || { echo "FAIL: no fixture available"; exit 1; }
echo "Source fixture: $SRC"

# Clone the fixture to a fresh dir for each test (so we never mutate the source).
clone_fixture() {
  local dest; dest=$(mktemp -d)
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
OUT=$(bash "$VERIFY" 5 "$P" 2>&1) || true
if echo "$OUT" | grep -qE "row [0-9]+ covariates"; then
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
OUT=$(bash "$VERIFY" 5 "$P" 2>&1) || true
# Layer 1's covariates emptiness check should now skip. Verify.sh 5 may
# still fail at a LATER check (variable_coverage etc.), but NOT at covariates.
if ! echo "$OUT" | grep -qE "row [0-9]+ covariates"; then
  note PASS "T2: scholar-compute + empty covariates → Layer 1 passes covariates check (FAIL message has no 'covariates', if any FAIL at all)"
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
OUT=$(bash "$VERIFY" 5 "$P" 2>&1) || true
if ! echo "$OUT" | grep -qE "row [0-9]+ covariates"; then
  note PASS "T3: scholar-qual + empty covariates → Layer 1 passes covariates check"
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
