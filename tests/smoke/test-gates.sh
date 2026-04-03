#!/usr/bin/env bash
# Smoke tests for gate scripts
# Tests: version-check, safety-scan, verify-citations
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATES="$REPO_ROOT/scripts/gates"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "── version-check.sh ──"

# Test 1: New file (no collision)
mkdir -p "$TMPDIR/vc-test"
OUT=$(bash "$GATES/version-check.sh" "$TMPDIR/vc-test" "draft-intro" 2>&1)
if echo "$OUT" | grep -q "SAVE_PATH="; then
  ok "prints SAVE_PATH for new file"
else
  fail "missing SAVE_PATH output: $OUT"
fi

# Test 2: Version collision (existing file)
touch "$TMPDIR/vc-test/draft-intro.md"
OUT=$(bash "$GATES/version-check.sh" "$TMPDIR/vc-test" "draft-intro" 2>&1)
if echo "$OUT" | grep -q "v2\|v3"; then
  ok "increments version on collision"
else
  fail "no version increment on collision: $OUT"
fi

# Test 3: Missing arguments
if bash "$GATES/version-check.sh" 2>/dev/null; then
  fail "should exit non-zero with no args"
else
  ok "exits non-zero with no args"
fi

echo ""
echo "── safety-scan.sh ──"

# Test 4: Clean file (GREEN)
echo "This is a normal research paper about voting patterns." > "$TMPDIR/clean.txt"
if bash "$GATES/safety-scan.sh" "$TMPDIR/clean.txt" 2>/dev/null | grep -q "GREEN"; then
  ok "clean file returns GREEN"
else
  fail "clean file should be GREEN"
fi

# Test 5: SSN pattern (RED)
echo "Subject SSN: 123-45-6789" > "$TMPDIR/ssn.txt"
bash "$GATES/safety-scan.sh" "$TMPDIR/ssn.txt" > "$TMPDIR/ssn-out.txt" 2>&1 || true
if grep -q "RED" "$TMPDIR/ssn-out.txt"; then
  ok "SSN pattern triggers RED"
else
  fail "SSN pattern should trigger RED"
fi

# Test 6: Email pattern (YELLOW)
echo "Contact: researcher@university.edu" > "$TMPDIR/email.txt"
bash "$GATES/safety-scan.sh" "$TMPDIR/email.txt" > "$TMPDIR/email-out.txt" 2>&1 || true
if grep -q "YELLOW" "$TMPDIR/email-out.txt"; then
  ok "email pattern triggers YELLOW"
else
  fail "email pattern should trigger YELLOW"
fi

# Test 7: Missing file
if bash "$GATES/safety-scan.sh" "$TMPDIR/nonexistent.txt" 2>/dev/null; then
  fail "should exit non-zero for missing file"
else
  ok "exits non-zero for missing file"
fi

# Test 8: HIPAA pattern (RED)
echo "patient_id,medical_record,diagnosis" > "$TMPDIR/hipaa.csv"
bash "$GATES/safety-scan.sh" "$TMPDIR/hipaa.csv" > "$TMPDIR/hipaa-out.txt" 2>&1 || true
if grep -q "RED" "$TMPDIR/hipaa-out.txt"; then
  ok "HIPAA pattern triggers RED"
else
  fail "HIPAA pattern should trigger RED"
fi

# Test 9: Mental health pattern (RED — new category)
echo "Subjects were screened for depression and suicidal ideation." > "$TMPDIR/mental.txt"
bash "$GATES/safety-scan.sh" "$TMPDIR/mental.txt" > "$TMPDIR/mental-out.txt" 2>&1 || true
if grep -q "RED\|YELLOW" "$TMPDIR/mental-out.txt"; then
  ok "mental health pattern triggers warning"
else
  fail "mental health pattern should trigger warning"
fi

# Test 10: Immigration status pattern (RED — new category)
echo "Respondents reported their immigration status: undocumented, DACA, visa holder." > "$TMPDIR/immig.txt"
bash "$GATES/safety-scan.sh" "$TMPDIR/immig.txt" > "$TMPDIR/immig-out.txt" 2>&1 || true
if grep -q "RED\|YELLOW" "$TMPDIR/immig-out.txt"; then
  ok "immigration status pattern triggers warning"
else
  fail "immigration status pattern should trigger warning"
fi

echo ""
echo "── verify-citations.sh ──"

# Test 11: File with no citations (should pass)
echo "This paper discusses trends in education policy." > "$TMPDIR/nocite.md"
if bash "$GATES/verify-citations.sh" "$TMPDIR/nocite.md" 2>/dev/null; then
  ok "file with no citations passes"
else
  fail "file with no citations should pass"
fi

# Test 12: File with CITATION NEEDED markers
echo "Research shows inequality is rising [CITATION NEEDED]." > "$TMPDIR/needed.md"
OUT=$(bash "$GATES/verify-citations.sh" "$TMPDIR/needed.md" 2>&1) || true
if echo "$OUT" | grep -qi "CITATION NEEDED\|WARNING\|unfilled"; then
  ok "detects [CITATION NEEDED] markers"
else
  fail "should detect [CITATION NEEDED] markers"
fi

# Test 13: File with valid citation
cat > "$TMPDIR/cited.md" << 'EOF'
Research shows inequality is rising (Smith 2020).

## References
Smith, J. 2020. "Inequality trends." *ASR* 85(3): 100-120.
EOF
if bash "$GATES/verify-citations.sh" "$TMPDIR/cited.md" 2>/dev/null; then
  ok "file with valid citation passes"
else
  fail "file with valid citation should pass"
fi

echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
