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

# Delegate ownership acquisition/deletion to the shared nonce-bound lifecycle.
# The proposal exists before traps; the helper atomically creates the directory
# and sentinel while the caller shell defers handled signals.
CASE_RESULT_HELPER="$SKILL_DIR/tests/helpers/case_result.py"
TEST_TMP_PROPOSAL="$(python3 "$CASE_RESULT_HELPER" prepare-owned-root \
  --tmpdir "${TMPDIR:-/tmp}" --prefix scholar-ar-codex-trigger)" || exit 1
IFS=$'\t' read -r TEST_TMP_ROOT TEST_TMP_NONCE TEST_TMP_PARENT <<< "$TEST_TMP_PROPOSAL"
cleanup_test_root() {
  [ -n "${TEST_TMP_ROOT:-}" ] && [ -e "$TEST_TMP_ROOT" ] || return 0
  python3 "$CASE_RESULT_HELPER" cleanup-owned-root --root "$TEST_TMP_ROOT" \
    --nonce "$TEST_TMP_NONCE" --tmp-parent "$TEST_TMP_PARENT"
}
trap cleanup_test_root EXIT
trap 'cleanup_test_root; exit 130' INT
trap 'cleanup_test_root; exit 143' TERM
trap 'cleanup_test_root; exit 129' HUP
python3 "$CASE_RESULT_HELPER" create-owned-root --root "$TEST_TMP_ROOT" \
  --nonce "$TEST_TMP_NONCE" --tmp-parent "$TEST_TMP_PARENT" || exit 1

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
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
mkdir -p "$P/review"
touch "$P/review/pre-execution-review.md"
OUT=$(SCHOLAR_CODEX_REVIEW=1 CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-6)
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
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
mkdir -p "$P/review" "$P/reviews/codex"
touch "$P/review/pre-execution-review.md" "$P/reviews/codex/A1-correctness-2026-05-10.md"
OUT=$(SCHOLAR_CODEX_REVIEW=1 CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-6)
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
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
mkdir -p "$P/review"
cat > "$P/review/pre-execution-review.md" <<MD
# Pre-Execution Review
[EXCUSED:codex-review: codex CLI not available in clean-room]
PASS verdict.
MD
OUT=$(SCHOLAR_CODEX_REVIEW=1 CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-6)
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
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
mkdir -p "$P/verify"
touch "$P/verify/manuscript-verification.md"
OUT=$(SCHOLAR_CODEX_REVIEW=1 CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-14)
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
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
mkdir -p "$P/verify" "$P/reviews/codex"
touch "$P/verify/manuscript-verification.md" "$P/reviews/codex/codex-review-consolidated-2026-05-10.md"
OUT=$(SCHOLAR_CODEX_REVIEW=1 CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-14)
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
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
mkdir -p "$P/verify"
touch "$P/verify/manuscript-verification.md"
OUT=$(SCHOLAR_CODEX_REVIEW=1 CODEX_AVAILABLE_OVERRIDE=false run_trigger "$P" ar-14)
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
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
OUT=$(run_trigger "$P" ar-99 2>&1)
RC=$?
if [ "$RC" != "0" ] && echo "$OUT" | grep -qE "ERROR.*phase|got 'ar-99'"; then
  note PASS "T7: invalid phase rejected (rc=$RC)"
else
  note FAIL "T7 (rc=$RC): expected non-zero with error. Got: $OUT"
fi
rm -rf "$P"

# ── T8: optional lane not requested → GREEN no_trigger ──
echo ""
echo "=== T8: ar-6 GREEN when SCHOLAR_CODEX_REVIEW=0 ==="
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
mkdir -p "$P/review"
touch "$P/review/pre-execution-review.md"
OUT=$(SCHOLAR_CODEX_REVIEW=0 CODEX_AVAILABLE_OVERRIDE=true run_trigger "$P" ar-6)
RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && echo "$OUT" | grep -q "REASON=no_trigger" && [ "$RC" = "0" ]; then
  note PASS "T8: ar-6 GREEN when optional lane is not requested"
else
  note FAIL "T8 (rc=$RC): expected GREEN+no_trigger. Got: $OUT"
fi
rm -rf "$P"

# ── T9: phase wrapper (codex-trigger-phase6.sh) end-to-end ──
echo ""
echo "=== T9: phase6 wrapper integration (RED → exit 1) ==="
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
mkdir -p "$P/review"
touch "$P/review/pre-execution-review.md"
OUT=$(SCHOLAR_CODEX_REVIEW=1 CODEX_AVAILABLE_OVERRIDE=true run_phase6 "$P")
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
P=$(mktemp -d "$TEST_TMP_ROOT/case.XXXXXX")
mkdir -p "$P/verify" "$P/reviews/codex"
touch "$P/verify/manuscript-verification.md" "$P/reviews/codex/A4-numerics-2026-05-10.md"
OUT=$(SCHOLAR_CODEX_REVIEW=1 CODEX_AVAILABLE_OVERRIDE=true run_phase14 "$P")
RC=$?
if echo "$OUT" | grep -q "STATUS=GREEN" && [ "$RC" = "0" ]; then
  note PASS "T10: phase14 wrapper GREEN with A[4-5]-*.md present"
else
  note FAIL "T10 (rc=$RC): expected GREEN via phase14 wrapper. Got: $OUT"
fi
rm -rf "$P"

# ── T11: F3 space/apostrophe-path glob matrix ──
# Before the fix, glob_has_match used unquoted `ls $1`, which word-split any
# project path containing a space or apostrophe and reported fired=false even
# when the dispatch artifact was present (a false RED forcing redundant
# re-dispatch). Every test above uses mktemp -d (space-free), so this dimension
# was untested. Matrix: {space, apostrophe} roots x {reviews/codex,
# output/reviews/codex} x {ar-6 code A[1-3], ar-14 prose consolidated/A[4-5]}
# x {present->GREEN/fired, absent->RED}.
echo ""
echo "=== T11: F3 space/apostrophe path glob matrix ==="
codex_case() {
  # codex_case <label> <root> <phase> <report-rel> <artifact-rel|""> <GREEN|RED>
  local label="$1" root="$2" phase="$3" report="$4" artifact="$5" expect="$6"
  mkdir -p "$root/$(dirname "$report")"; : > "$root/$report"
  if [ -n "$artifact" ]; then mkdir -p "$root/$(dirname "$artifact")"; : > "$root/$artifact"; fi
  local out rc
  out=$(SCHOLAR_CODEX_REVIEW=1 CODEX_AVAILABLE_OVERRIDE=true run_trigger "$root" "$phase")
  rc=$?
  if [ "$expect" = GREEN ]; then
    if echo "$out" | grep -q "STATUS=GREEN" && echo "$out" | grep -q "fired=true" && [ "$rc" = 0 ]; then
      note PASS "$label"
    else note FAIL "$label (rc=$rc): want GREEN/fired. Got: $out"; fi
  else
    if echo "$out" | grep -q "STATUS=RED" && [ "$rc" = 1 ]; then
      note PASS "$label"
    else note FAIL "$label (rc=$rc): want RED. Got: $out"; fi
  fi
  rm -rf "$root"
}
codex_case "T11a: space + ar-6 code + reviews/codex present -> GREEN" \
  "$TEST_TMP_ROOT/ar sp-1" ar-6 "review/pre-execution-review.md" "reviews/codex/A1-correctness-2026-07-08.md" GREEN
codex_case "T11b: space + ar-6 code + output/reviews/codex present -> GREEN" \
  "$TEST_TMP_ROOT/ar sp-2" ar-6 "review/pre-execution-review.md" "output/reviews/codex/A3-data-2026-07-08.md" GREEN
codex_case "T11c: space + ar-6 + absent -> RED" \
  "$TEST_TMP_ROOT/ar sp-3" ar-6 "review/pre-execution-review.md" "" RED
codex_case "T11d: space + ar-14 consolidated + reviews/codex present -> GREEN" \
  "$TEST_TMP_ROOT/ar sp-4" ar-14 "verify/manuscript-verification.md" "reviews/codex/codex-review-consolidated-2026-07-08.md" GREEN
codex_case "T11e: space + ar-14 A[4-5] + output/reviews/codex present -> GREEN" \
  "$TEST_TMP_ROOT/ar sp-5" ar-14 "verify/manuscript-verification.md" "output/reviews/codex/A5-repro-2026-07-08.md" GREEN
codex_case "T11f: space + ar-14 + absent -> RED" \
  "$TEST_TMP_ROOT/ar sp-6" ar-14 "verify/manuscript-verification.md" "" RED
codex_case "T11g: apostrophe + ar-6 code + reviews/codex present -> GREEN" \
  "$TEST_TMP_ROOT/o'brien-7" ar-6 "review/pre-execution-review.md" "reviews/codex/A2-style-2026-07-08.md" GREEN
codex_case "T11h: apostrophe + ar-6 + absent -> RED" \
  "$TEST_TMP_ROOT/o'brien-8" ar-6 "review/pre-execution-review.md" "" RED

echo ""
echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
echo "===================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
