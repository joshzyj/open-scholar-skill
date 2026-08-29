#!/usr/bin/env bash
# Smoke test for auto-research-verify.sh prerequisite failure reporting.

set -uo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VERIFY="${SKILL_DIR}/scripts/auto-research-verify.sh"

TMP="$(mktemp -d -t auto-research-prereq-output.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PROJ="$TMP/empty-project"
OUT="$TMP/verify.out"
mkdir -p "$PROJ"

echo "=== auto-research-verify.sh prerequisite output smoke ==="

set +e
bash "$VERIFY" 11 "$PROJ" > "$OUT" 2>&1
RC=$?
set -u

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
  echo "    out: $(tr '\n' '|' < "$OUT" | head -c 900)"
}

if [ "$RC" -ne 0 ]; then
  pass "phase 11 fails when prerequisite phase 10 fails"
else
  fail "expected phase 11 to fail through prerequisite phase 10"
fi

if grep -q "FAIL: Phase 11 prerequisite Phase 10 failed" "$OUT"; then
  pass "outer phase reports the failed prerequisite phase"
else
  fail "missing prerequisite failure wrapper"
fi

if grep -q "FAIL:" "$OUT" && [ "$(wc -l < "$OUT" | tr -d ' ')" -ge 2 ]; then
  pass "nested prerequisite verifier output remains visible"
else
  fail "nested prerequisite output was hidden"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
