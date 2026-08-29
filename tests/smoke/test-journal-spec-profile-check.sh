#!/usr/bin/env bash
# test-journal-spec-profile-check.sh — Smoke tests for journal-spec-profile-check.sh
# (audit 2026-05-03 — profile→spec gap fix).
#
# The gate compares ${PROJ}/manuscript/journal-spec.json against the
# resolved journal profile and fails RED when total_word_range disagrees
# with the profile's total_word_budget. Smoke covers the canonical
# "fixture-leak" failure mode: a JMF empirical-article spec carrying
# total_word_range.min=1300 instead of the profile's 7000.
#
# Coverage
# --------
#   T1 GREEN  — JMF spec mirrors profile (correct min=7000, max=9000)
#   T2 RED    — JMF spec has min=1300 (the canonical bug)
#   T3 RED    — JMF spec has compressed section targets (sum < 85% of floor)
#   T4 RED    — spec.total_word_range missing
#   T5 YELLOW — unknown journal (cannot resolve profile)
#   T6 GREEN  — short-format paper (research note) → gate skipped
#   T7 YELLOW — journal-spec.json missing (Phase 12/13 not yet authored it)
#   T8 YELLOW — usage error (no project dir)
#   T9 GREEN  — ASR spec mirrors ASR profile
#   T10 RED   — abstract_word_cap below profile (soft warning + RED only when
#               total_word_range also wrong; standalone abstract drift is
#               warning-only)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${REPO_ROOT}/scripts/gates/journal-spec-profile-check.sh"

if [ ! -x "$GATE" ]; then
  echo "FATAL: gate not executable at $GATE"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not installed; gate cannot run."
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; profile resolver cannot run."
  exit 0
fi

TMP="$(mktemp -d -t jspc.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    out: $(tr '\n' '|' < "$2" | head -c 800)"; }

run_gate() {
  local out="$1" proj="$2"
  set +e
  bash "$GATE" "$proj" > "$out" 2>&1
  local rc=$?
  set -u
  echo "$rc"
}

# Helper: write a journal-spec.json with the given JSON body.
write_spec() {
  local proj="$1"; shift
  local body="$1"; shift
  mkdir -p "$proj/manuscript"
  printf '%s\n' "$body" > "$proj/manuscript/journal-spec.json"
}

# Canonical JMF-correct spec (mirrors the JMF profile's calibrated values).
# Only the budget-bearing fields are needed for this gate.
JMF_CORRECT_SPEC='{
  "target_journal": "Journal of Marriage and Family",
  "paper_type": "empirical article",
  "total_word_range": {"min": 7000, "max": 9000},
  "abstract_word_cap": 200,
  "section_word_budget": {
    "abstract":         {"min_words": 150, "target_words": 180, "max_words": 200},
    "introduction":     {"min_words": 800, "target_words": 1000, "max_words": 1200},
    "background":       {"min_words": 1200, "target_words": 1600, "max_words": 2000},
    "data and methods": {"min_words": 1200, "target_words": 1500, "max_words": 1800},
    "results":          {"min_words": 1200, "target_words": 1500, "max_words": 1800},
    "discussion":       {"min_words": 800, "target_words": 1000, "max_words": 1200}
  }
}'

# Canonical buggy JMF spec — the failure mode this gate exists to catch.
JMF_BUGGY_SPEC='{
  "target_journal": "Journal of Marriage and Family",
  "paper_type": "empirical article",
  "total_word_range": {"min": 1300, "max": 9000},
  "abstract_word_cap": 250,
  "section_word_budget": {
    "abstract":         {"min_words": 80, "target_words": 180, "max_words": 250},
    "introduction":     {"min_words": 250, "target_words": 650, "max_words": 1200},
    "background":       {"min_words": 300, "target_words": 900, "max_words": 1600},
    "data and methods": {"min_words": 250, "target_words": 650, "max_words": 1100},
    "results":          {"min_words": 250, "target_words": 1000, "max_words": 1800},
    "discussion":       {"min_words": 200, "target_words": 700, "max_words": 1400}
  }
}'

echo "=== journal-spec-profile-check.sh smoke tests ==="
echo ""

# ── T1 GREEN — JMF spec mirrors profile ──────────────────────────────
echo "T1: JMF spec mirrors profile (GREEN)"
P1="$TMP/t1"; mkdir -p "$P1/manuscript"
write_spec "$P1" "$JMF_CORRECT_SPEC"
RC=$(run_gate "$P1/out" "$P1")
if [ "$RC" = "0" ] && grep -q "STATUS=GREEN" "$P1/out"; then
  pass "T1 GREEN on correct JMF spec"
else
  fail "T1 expected GREEN/exit-0; got rc=$RC" "$P1/out"
fi

# ── T2 RED — JMF spec carries min=1300 (canonical bug) ───────────────
echo ""
echo "T2: JMF spec with 1300-floor (canonical bug, RED)"
P2="$TMP/t2"; mkdir -p "$P2/manuscript"
write_spec "$P2" "$JMF_BUGGY_SPEC"
RC=$(run_gate "$P2/out" "$P2")
if [ "$RC" = "1" ] && grep -q "STATUS=RED" "$P2/out" && grep -q "spec.total_word_range.min=1300" "$P2/out"; then
  pass "T2 RED with explicit 1300 vs 7000 violation"
else
  fail "T2 expected RED/exit-1 with 1300 violation; got rc=$RC" "$P2/out"
fi

# ── T3 RED — JMF spec with compressed section targets ────────────────
# Total range is correct (7000-9000) but per-section target_words sum to
# only 50% of profile.min — should still RED via the section-target sum
# safety check.
echo ""
echo "T3: JMF spec with compressed section targets (RED)"
P3="$TMP/t3"; mkdir -p "$P3/manuscript"
write_spec "$P3" '{
  "target_journal": "Journal of Marriage and Family",
  "paper_type": "empirical article",
  "total_word_range": {"min": 7000, "max": 9000},
  "abstract_word_cap": 200,
  "section_word_budget": {
    "abstract":         {"min_words": 80, "target_words": 100, "max_words": 250},
    "introduction":     {"min_words": 250, "target_words": 400, "max_words": 1200},
    "background":       {"min_words": 300, "target_words": 600, "max_words": 1600},
    "data and methods": {"min_words": 250, "target_words": 500, "max_words": 1100},
    "results":          {"min_words": 250, "target_words": 700, "max_words": 1800},
    "discussion":       {"min_words": 200, "target_words": 500, "max_words": 1400}
  }
}'
RC=$(run_gate "$P3/out" "$P3")
if [ "$RC" = "1" ] && grep -q "STATUS=RED" "$P3/out" && grep -q "section_word_budget.target_words" "$P3/out"; then
  pass "T3 RED on compressed section target sum"
else
  fail "T3 expected RED with section-target violation; got rc=$RC" "$P3/out"
fi

# ── T4 RED — total_word_range missing ────────────────────────────────
echo ""
echo "T4: spec missing total_word_range (RED)"
P4="$TMP/t4"; mkdir -p "$P4/manuscript"
write_spec "$P4" '{
  "target_journal": "Journal of Marriage and Family",
  "paper_type": "empirical article",
  "abstract_word_cap": 200,
  "section_word_budget": {}
}'
RC=$(run_gate "$P4/out" "$P4")
if [ "$RC" = "1" ] && grep -q "STATUS=RED" "$P4/out"; then
  pass "T4 RED on missing total_word_range"
else
  fail "T4 expected RED on missing total_word_range; got rc=$RC" "$P4/out"
fi

# ── T5 YELLOW — unknown journal ──────────────────────────────────────
echo ""
echo "T5: unknown journal name (YELLOW)"
P5="$TMP/t5"; mkdir -p "$P5/manuscript"
write_spec "$P5" '{
  "target_journal": "Quarterly Journal of Imaginary Studies",
  "paper_type": "empirical article",
  "total_word_range": {"min": 7000, "max": 9000},
  "abstract_word_cap": 200,
  "section_word_budget": {}
}'
RC=$(run_gate "$P5/out" "$P5")
if [ "$RC" = "2" ] && grep -q "STATUS=YELLOW" "$P5/out" && grep -q "profile_not_found" "$P5/out"; then
  pass "T5 YELLOW on unknown journal"
else
  fail "T5 expected YELLOW/exit-2 with profile_not_found; got rc=$RC" "$P5/out"
fi

# ── T6 GREEN — short-format paper (research note) skipped ───────────
echo ""
echo "T6: short-format paper (research note) skipped (GREEN)"
P6="$TMP/t6"; mkdir -p "$P6/manuscript"
write_spec "$P6" '{
  "target_journal": "Journal of Marriage and Family",
  "paper_type": "research note",
  "total_word_range": {"min": 1300, "max": 4000},
  "abstract_word_cap": 200,
  "section_word_budget": {}
}'
RC=$(run_gate "$P6/out" "$P6")
if [ "$RC" = "0" ] && grep -q "STATUS=GREEN" "$P6/out" && grep -q "short_format_skip" "$P6/out"; then
  pass "T6 GREEN with short_format_skip on research note"
else
  fail "T6 expected GREEN with short_format_skip; got rc=$RC" "$P6/out"
fi

# ── T7 YELLOW — journal-spec.json missing ────────────────────────────
echo ""
echo "T7: journal-spec.json missing (YELLOW)"
P7="$TMP/t7"; mkdir -p "$P7/manuscript"
RC=$(run_gate "$P7/out" "$P7")
if [ "$RC" = "2" ] && grep -q "STATUS=YELLOW" "$P7/out" && grep -q "spec_missing" "$P7/out"; then
  pass "T7 YELLOW when spec absent"
else
  fail "T7 expected YELLOW/exit-2 spec_missing; got rc=$RC" "$P7/out"
fi

# ── T8 YELLOW — usage error ──────────────────────────────────────────
echo ""
echo "T8: missing project dir argument (YELLOW)"
set +e
bash "$GATE" > "$TMP/t8.out" 2>&1
RC=$?
set -u
if [ "$RC" = "2" ] && grep -q "STATUS=YELLOW" "$TMP/t8.out"; then
  pass "T8 YELLOW on usage error"
else
  fail "T8 expected YELLOW/exit-2 on missing arg; got rc=$RC" "$TMP/t8.out"
fi

# ── T9 GREEN — ASR spec mirrors ASR profile ─────────────────────────
echo ""
echo "T9: ASR spec mirrors profile (GREEN)"
P9="$TMP/t9"; mkdir -p "$P9/manuscript"
write_spec "$P9" '{
  "target_journal": "American Sociological Review",
  "paper_type": "empirical article",
  "total_word_range": {"min": 9000, "max": 12000},
  "abstract_word_cap": 200,
  "section_word_budget": {
    "abstract":         {"min_words": 150, "target_words": 175, "max_words": 200},
    "introduction":     {"min_words": 1000, "target_words": 1250, "max_words": 1500},
    "background":       {"min_words": 1800, "target_words": 2300, "max_words": 2800},
    "theory":           {"min_words": 1200, "target_words": 1600, "max_words": 2000},
    "data and methods": {"min_words": 1800, "target_words": 2300, "max_words": 2800},
    "results":          {"min_words": 1800, "target_words": 2300, "max_words": 2800},
    "discussion":       {"min_words": 1200, "target_words": 1600, "max_words": 2000}
  }
}'
RC=$(run_gate "$P9/out" "$P9")
if [ "$RC" = "0" ] && grep -q "STATUS=GREEN" "$P9/out"; then
  pass "T9 GREEN on correct ASR spec"
else
  fail "T9 expected GREEN/exit-0 on correct ASR spec; got rc=$RC" "$P9/out"
fi

# ── T10 — abstract_word_cap soft warning (does not flip GREEN to RED) ─
# Verify standalone abstract-cap drift is a soft warning, not a hard fail.
echo ""
echo "T10: low abstract_word_cap is soft warning when total_word_range correct (GREEN with WARNINGS)"
P10="$TMP/t10"; mkdir -p "$P10/manuscript"
write_spec "$P10" '{
  "target_journal": "Journal of Marriage and Family",
  "paper_type": "empirical article",
  "total_word_range": {"min": 7000, "max": 9000},
  "abstract_word_cap": 100,
  "section_word_budget": {
    "abstract":         {"min_words": 150, "target_words": 180, "max_words": 200},
    "introduction":     {"min_words": 800, "target_words": 1000, "max_words": 1200},
    "background":       {"min_words": 1200, "target_words": 1600, "max_words": 2000},
    "data and methods": {"min_words": 1200, "target_words": 1500, "max_words": 1800},
    "results":          {"min_words": 1200, "target_words": 1500, "max_words": 1800},
    "discussion":       {"min_words": 800, "target_words": 1000, "max_words": 1200}
  }
}'
RC=$(run_gate "$P10/out" "$P10")
if [ "$RC" = "0" ] && grep -q "STATUS=GREEN" "$P10/out" && grep -q "WARNINGS" "$P10/out"; then
  pass "T10 GREEN with WARNINGS on low abstract_word_cap"
else
  fail "T10 expected GREEN with WARNINGS; got rc=$RC" "$P10/out"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo ">>> FAILED"
  exit 1
else
  echo ">>> PASSED"
  exit 0
fi
