#!/usr/bin/env bash
# Smoke tests for scholar-auto-research codex-trigger gates (ar-6, ar-14).
# Self-contained within scholar-auto-research; does NOT depend on the
# parent scholar-skill smoke suite.
#
# Tests the vendored codex-trigger-check.sh and the two phase wrappers
# (codex-trigger-phase6.sh, codex-trigger-phase14.sh).

set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE_DIR="$SKILL_DIR/scripts/gates"
PHASE6="$GATE_DIR/codex-trigger-phase6.sh"
PHASE14="$GATE_DIR/codex-trigger-phase14.sh"
TRIGGER="$GATE_DIR/codex-trigger-check.sh"

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

run_phase6() { bash "$PHASE6" "$1" 2>&1; }
run_phase14() { bash "$PHASE14" "$1" 2>&1; }
run_trigger() { bash "$TRIGGER" "$1" "$2" 2>&1; }

# ── T1: ar-6 RED when env=true + cli=true + no artifacts + no excuse ──
echo ""
echo "=== T1: ar-6 RED (strong trigger, no dispatch, no excuse) ==="
P=$(mktemp -d)
mkdir -p "$P/review"
touch "$P/review/pre-execution-review.md"
OUT=$(SCHOLAR_CODEX_DEFAULT=true CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-6)
RC=$?
if echo "$OUT" | grep -q "STATUS=RED" && [ "$RC" = "1" ]; then
  note PASS "T1: ar-6 RED with strong trigger missing dispatch"
else
  note FAIL "T1 (rc=$RC): expected RED. Got: $OUT"
fi
rm -rf "$P"

# ── T2: ar-6 GREEN when codex code-mode artifacts present ──
echo ""
echo "=== T2: ar-6 GREEN (artifacts present) ==="
P=$(mktemp -d)
mkdir -p "$P/review" "$P/reviews/codex"
touch "$P/review/pre-execution-review.md" "$P/reviews/codex/A1-correctness-2026-05-10.md"
OUT=$(SCHOLAR_CODEX_DEFAULT=true CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-6)
RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && [ "$RC" = "0" ]; then
  note PASS "T2: ar-6 GREEN when A[1-3]-*.md present"
else
  note FAIL "T2 (rc=$RC): expected GREEN. Got: $OUT"
fi
rm -rf "$P"

# ── T3: ar-6 GREEN with [EXCUSED:codex-review: ...] in .md ──
echo ""
echo "=== T3: ar-6 GREEN via excuse annotation in .md report ==="
P=$(mktemp -d)
mkdir -p "$P/review"
cat > "$P/review/pre-execution-review.md" <<MD
# Pre-Execution Review
[EXCUSED:codex-review: codex CLI not available in clean-room]
PASS verdict.
MD
OUT=$(SCHOLAR_CODEX_DEFAULT=true CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-6)
RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && echo "$OUT" | grep -q "REASON=excused" && [ "$RC" = "0" ]; then
  note PASS "T3: ar-6 GREEN via excuse annotation"
else
  note FAIL "T3 (rc=$RC): expected GREEN+excused. Got: $OUT"
fi
rm -rf "$P"

# ── T4: ar-14 RED when env=true + cli=true + no artifacts + no excuse ──
echo ""
echo "=== T4: ar-14 RED (strong trigger, no dispatch, no excuse) ==="
P=$(mktemp -d)
mkdir -p "$P/verify"
touch "$P/verify/manuscript-verification.md"
OUT=$(SCHOLAR_CODEX_DEFAULT=true CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-14)
RC=$?
if echo "$OUT" | grep -q "STATUS=RED" && [ "$RC" = "1" ]; then
  note PASS "T4: ar-14 RED with strong trigger missing dispatch"
else
  note FAIL "T4 (rc=$RC): expected RED. Got: $OUT"
fi
rm -rf "$P"

# ── T5: ar-14 GREEN with full-mode consolidated artifact present ──
echo ""
echo "=== T5: ar-14 GREEN (consolidated artifact present) ==="
P=$(mktemp -d)
mkdir -p "$P/verify" "$P/reviews/codex"
touch "$P/verify/manuscript-verification.md" "$P/reviews/codex/codex-review-consolidated-2026-05-10.md"
OUT=$(SCHOLAR_CODEX_DEFAULT=true CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-14)
RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && [ "$RC" = "0" ]; then
  note PASS "T5: ar-14 GREEN when consolidated artifact present"
else
  note FAIL "T5 (rc=$RC): expected GREEN. Got: $OUT"
fi
rm -rf "$P"

# ── T6: ar-14 YELLOW when env=true but cli missing ──
echo ""
echo "=== T6: ar-14 YELLOW (cli missing) ==="
P=$(mktemp -d)
mkdir -p "$P/verify"
touch "$P/verify/manuscript-verification.md"
OUT=$(SCHOLAR_CODEX_DEFAULT=true CODEX_AVAILABLE_OVERRIDE=false run_trigger "$P" ar-14)
RC=$?
if echo "$OUT" | grep -q "STATUS=YELLOW" && echo "$OUT" | grep -q "REASON=cli_missing" && [ "$RC" = "2" ]; then
  note PASS "T6: ar-14 YELLOW when codex CLI missing"
else
  note FAIL "T6 (rc=$RC): expected YELLOW+cli_missing. Got: $OUT"
fi
rm -rf "$P"

# ── T7: invalid phase token rejected ──
echo ""
echo "=== T7: invalid phase token rejected ==="
P=$(mktemp -d)
OUT=$(run_trigger "$P" ar-99 2>&1)
RC=$?
if [ "$RC" != "0" ] && echo "$OUT" | grep -qE "ERROR.*phase|got 'ar-99'"; then
  note PASS "T7: invalid phase rejected (rc=$RC)"
else
  note FAIL "T7 (rc=$RC): expected non-zero with error. Got: $OUT"
fi
rm -rf "$P"

# ── T8: SCHOLAR_CODEX_DEFAULT=false → GREEN no_trigger ──
echo ""
echo "=== T8: ar-6 GREEN when SCHOLAR_CODEX_DEFAULT=false (opt out) ==="
P=$(mktemp -d)
mkdir -p "$P/review"
touch "$P/review/pre-execution-review.md"
OUT=$(SCHOLAR_CODEX_DEFAULT=false CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-6)
RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && echo "$OUT" | grep -q "REASON=no_trigger" && [ "$RC" = "0" ]; then
  note PASS "T8: ar-6 GREEN when SCHOLAR_CODEX_DEFAULT=false"
else
  note FAIL "T8 (rc=$RC): expected GREEN+no_trigger. Got: $OUT"
fi
rm -rf "$P"

# ── T9: phase wrapper (codex-trigger-phase6.sh) end-to-end ──
echo ""
echo "=== T9: phase6 wrapper integration (RED → exit 1) ==="
P=$(mktemp -d)
mkdir -p "$P/review"
touch "$P/review/pre-execution-review.md"
OUT=$(SCHOLAR_CODEX_DEFAULT=true CODEX_AVAILABLE_OVERRIDE=true run_phase6 "$P")
RC=$?
if echo "$OUT" | grep -q "STATUS=RED" && [ "$RC" = "1" ]; then
  note PASS "T9: phase6 wrapper emits STATUS=RED rc=1"
else
  note FAIL "T9 (rc=$RC): expected RED via phase6 wrapper. Got: $OUT"
fi
rm -rf "$P"

# ── T10: phase wrapper (codex-trigger-phase14.sh) end-to-end ──
echo ""
echo "=== T10: phase14 wrapper integration (GREEN with artifact) ==="
P=$(mktemp -d)
mkdir -p "$P/verify" "$P/reviews/codex"
touch "$P/verify/manuscript-verification.md" "$P/reviews/codex/A4-numerics-2026-05-10.md"
OUT=$(SCHOLAR_CODEX_DEFAULT=true CODEX_AVAILABLE_OVERRIDE=true run_phase14 "$P")
RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && [ "$RC" = "0" ]; then
  note PASS "T10: phase14 wrapper GREEN with A[4-5]-*.md present"
else
  note FAIL "T10 (rc=$RC): expected GREEN via phase14 wrapper. Got: $OUT"
fi
rm -rf "$P"

echo ""
echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
echo "===================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
