#!/usr/bin/env bash
# Smoke tests for scripts/gates/code-review-coverage-check.sh
# (audit 2026-04-27 user-flagged finding: 3-of-6 agent-coverage gap).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${REPO_ROOT}/scripts/gates/code-review-coverage-check.sh"

if [ ! -f "$GATE" ]; then
  echo "FATAL: code-review-coverage-check.sh not found at $GATE"
  exit 1
fi

TMPDIR_BASE="$(mktemp -d -t code-review-coverage-smoke.XXXXXX)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; echo "    stdout: $(cat "$2" 2>/dev/null | tr '\n' '|' | head -c 600)"; }

run_gate() {
  local args=("$@") outfile="${!#}"
  unset 'args[${#args[@]}-1]'
  set +e
  bash "$GATE" "${args[@]}" > "$outfile" 2>&1
  local rc=$?
  set -u
  echo "$rc"
}

echo "=== code-review-coverage-check.sh Smoke Tests ==="
echo ""

# T1: GREEN — full report with all 6 agents
echo "Test 1: GREEN with all 6 agents present"
PROJ="$TMPDIR_BASE/proj1"
mkdir -p "$PROJ/reports"
cat > "$PROJ/reports/code-review-2026-04-27.md" <<'EOF'
# Code Review Report

## Overall Scorecard

| Dimension               | Agent                       | Issues | Critical | Warnings |
|-------------------------|-----------------------------|--------|----------|----------|
| Correctness & Logic     | review-code-correctness     | 9      | 7        | 2        |
| Robustness              | review-code-robustness      | 3      | 0        | 3        |
| Statistical Fidelity    | review-code-statistics      | 5      | 2        | 3        |
| Reproducibility         | review-code-reproducibility | 1      | 0        | 1        |
| Style & AI Patterns     | review-code-style           | 4      | 0        | 4        |
| Data Handling           | review-code-data-handling   | 6      | 2        | 4        |
EOF
OUT="$TMPDIR_BASE/t1.out"
RC=$(run_gate "$PROJ" "$OUT")
if [ "$RC" -eq 0 ] && grep -q "STATUS=GREEN" "$OUT"; then
  pass "GREEN with all 6 agents present"
else
  fail "Expected rc=0 + STATUS=GREEN (got rc=$RC)" "$OUT"
fi

# T2: RED — cohab fixture (only data-handling, correctness, statistics fired)
echo ""
echo "Test 2: RED on cohab fixture (3 of 6 agents missing)"
PROJ="$TMPDIR_BASE/proj2"
mkdir -p "$PROJ/reports"
cat > "$PROJ/reports/code-review-2026-04-26.md" <<'EOF'
# Code Review Report

## Overall Scorecard

| Dimension               | Agent                       | Issues | Critical | Warnings |
|-------------------------|-----------------------------|--------|----------|----------|
| Correctness & Logic     | review-code-correctness     | 7      | 4        | 3        |
| Statistical Fidelity    | review-code-statistics      | 3      | 1        | 2        |
| Data Handling           | review-code-data-handling   | 2      | 1        | 1        |
EOF
OUT="$TMPDIR_BASE/t2.out"
RC=$(run_gate "$PROJ" "$OUT")
if [ "$RC" -eq 1 ] && grep -q "STATUS=RED" "$OUT" \
   && grep -q "review-code-reproducibility" "$OUT" \
   && grep -q "review-code-robustness" "$OUT" \
   && grep -q "review-code-style" "$OUT"; then
  pass "RED on cohab fixture (3 missing agents named)"
else
  fail "Expected rc=1 + RED + 3 missing agents (got rc=$RC)" "$OUT"
fi

# T3: GREEN with explicit [EXCUSED:reason] annotation
echo ""
echo "Test 3: GREEN with explicit [EXCUSED] for review-code-style"
PROJ="$TMPDIR_BASE/proj3"
mkdir -p "$PROJ/reports"
cat > "$PROJ/reports/code-review-2026-04-27.md" <<'EOF'
# Code Review Report

| Agent                       | Issues |
|-----------------------------|--------|
| review-code-correctness     | 0      |
| review-code-data-handling   | 0      |
| review-code-statistics      | 0      |
| review-code-reproducibility | 0      |
| review-code-robustness      | 0      |

[EXCUSED: project is qualitative-only; no scripts to lint] review-code-style
EOF
OUT="$TMPDIR_BASE/t3.out"
RC=$(run_gate "$PROJ" "$OUT")
if [ "$RC" -eq 0 ] && grep -q "STATUS=GREEN" "$OUT" && grep -q "excused" "$OUT"; then
  pass "GREEN with explicit excuse for review-code-style"
else
  fail "Expected rc=0 + GREEN + 'excused' (got rc=$RC)" "$OUT"
fi

# T4: YELLOW — no report under PROJ
echo ""
echo "Test 4: YELLOW with no code-review report"
PROJ="$TMPDIR_BASE/proj4"
mkdir -p "$PROJ/reports"
OUT="$TMPDIR_BASE/t4.out"
RC=$(run_gate "$PROJ" "$OUT")
if [ "$RC" -eq 2 ] && grep -q "STATUS=YELLOW" "$OUT"; then
  pass "YELLOW on missing report"
else
  fail "Expected rc=2 + STATUS=YELLOW (got rc=$RC)" "$OUT"
fi

# T5: RED — only 1 agent fired (worst case)
echo ""
echo "Test 5: RED when only 1 of 6 agents fired"
PROJ="$TMPDIR_BASE/proj5"
mkdir -p "$PROJ/reports"
cat > "$PROJ/reports/code-review-2026-04-27.md" <<'EOF'
# Code Review Report
| Agent                   | Issues |
|-------------------------|--------|
| review-code-correctness | 5      |
EOF
OUT="$TMPDIR_BASE/t5.out"
RC=$(run_gate "$PROJ" "$OUT")
if [ "$RC" -eq 1 ] && grep -q "STATUS=RED" "$OUT"; then
  HITS=$(grep -cE "review-code-(data-handling|statistics|reproducibility|robustness|style)" "$OUT" | tr -d ' ')
  if [ "$HITS" -ge 5 ]; then
    pass "RED with 5 missing agents named ($HITS lines)"
  else
    fail "Expected ≥5 missing agents listed (got $HITS)" "$OUT"
  fi
else
  fail "Expected rc=1 + STATUS=RED (got rc=$RC)" "$OUT"
fi

# T6: GREEN — alternate report path under output/code-review/
echo ""
echo "Test 6: GREEN with report under output/code-review/"
PROJ="$TMPDIR_BASE/proj6"
mkdir -p "$PROJ/output/code-review"
cat > "$PROJ/output/code-review/code-review-2026-04-27.md" <<'EOF'
review-code-correctness review-code-data-handling review-code-statistics
review-code-reproducibility review-code-robustness review-code-style
EOF
OUT="$TMPDIR_BASE/t6.out"
RC=$(run_gate "$PROJ" "$OUT")
if [ "$RC" -eq 0 ] && grep -q "STATUS=GREEN" "$OUT"; then
  pass "GREEN with alternate report path"
else
  fail "Expected rc=0 + STATUS=GREEN (got rc=$RC)" "$OUT"
fi

# T7: explicit report path argument overrides auto-detect
echo ""
echo "Test 7: explicit report path arg honored"
PROJ="$TMPDIR_BASE/proj7"
mkdir -p "$PROJ/reports"
# Decoy report (incomplete) at conventional path
cat > "$PROJ/reports/code-review-old.md" <<'EOF'
review-code-correctness only.
EOF
# Real report elsewhere with all 6
EXPLICIT="$TMPDIR_BASE/explicit-report.md"
cat > "$EXPLICIT" <<'EOF'
review-code-correctness review-code-data-handling review-code-statistics
review-code-reproducibility review-code-robustness review-code-style
EOF
OUT="$TMPDIR_BASE/t7.out"
RC=$(run_gate "$PROJ" "$EXPLICIT" "$OUT")
if [ "$RC" -eq 0 ] && grep -q "STATUS=GREEN" "$OUT"; then
  pass "GREEN with explicit report path arg"
else
  fail "Expected rc=0 + STATUS=GREEN (got rc=$RC)" "$OUT"
fi

# T8 — fast mode: 3-agent fast subset present → GREEN (audit 2026-04-27-v2 ERROR-A2)
echo ""
echo "Test 8: --required=fast accepts 3-agent fast subset"
PROJ="$TMPDIR_BASE/proj8"
mkdir -p "$PROJ/reports"
cat > "$PROJ/reports/code-review-pre-2026-04-27.md" <<'EOF'
# Pre-Execution Code Review (Phase 5A.5)
review-code-correctness fired
review-code-data-handling fired
review-code-statistics fired
EOF
OUT="$TMPDIR_BASE/t8.out"
RC=$(run_gate "$PROJ" --required=fast "$OUT")
if [ "$RC" -eq 0 ] && grep -q "STATUS=GREEN" "$OUT" && grep -q "mode=fast" "$OUT"; then
  pass "GREEN with --required=fast and 3 fast agents present"
else
  fail "Expected rc=0 + STATUS=GREEN + mode=fast (got rc=$RC)" "$OUT"
fi

# T9 — fast mode: only 1 of 3 fast agents → RED
echo ""
echo "Test 9: --required=fast fails when only 1 of 3 fast agents present"
PROJ="$TMPDIR_BASE/proj9"
mkdir -p "$PROJ/reports"
cat > "$PROJ/reports/code-review-pre-2026-04-27.md" <<'EOF'
# Pre-Execution Code Review (Phase 5A.5)
Only review-code-correctness fired.
EOF
OUT="$TMPDIR_BASE/t9.out"
RC=$(run_gate "$PROJ" --required=fast "$OUT")
if [ "$RC" -eq 1 ] && grep -q "STATUS=RED" "$OUT" && grep -q "review-code-data-handling" "$OUT" && grep -q "review-code-statistics" "$OUT"; then
  pass "RED with --required=fast and 2 of 3 fast agents missing (named in output)"
else
  fail "Expected rc=1 + STATUS=RED + missing-agent listing (got rc=$RC)" "$OUT"
fi

# T10 — backward compat: no --required flag defaults to full mode
echo ""
echo "Test 10: no --required flag defaults to full mode"
PROJ="$TMPDIR_BASE/proj10"
mkdir -p "$PROJ/reports"
cat > "$PROJ/reports/code-review-pre-2026-04-27.md" <<'EOF'
review-code-correctness review-code-data-handling review-code-statistics
EOF
OUT="$TMPDIR_BASE/t10.out"
RC=$(run_gate "$PROJ" "$OUT")
if [ "$RC" -eq 1 ] && grep -q "STATUS=RED" "$OUT" && grep -q "mode=full" "$OUT"; then
  pass "Default mode is full (3 of 6 agents → RED)"
else
  fail "Expected rc=1 + STATUS=RED + mode=full default (got rc=$RC)" "$OUT"
fi

# T11 — --phase=<tag>: manifest-aware path honors a custom phase tag
# (pre-execution-review protocol, 2026-08-13)
echo ""
echo "Test 11: --phase=<tag> filters dispatch-manifest rows by the custom tag"
PROJ="$TMPDIR_BASE/proj11"
mkdir -p "$PROJ/reports" "$PROJ/logs"
cat > "$PROJ/reports/code-review-pre-2026-08-13.md" <<'EOF'
review-code-correctness review-code-data-handling review-code-statistics
Overall Verdict: CLEAN
EOF
for n in 1 2 3; do
  A=$( [ "$n" = 1 ] && echo correctness || { [ "$n" = 2 ] && echo data-handling || echo statistics; } )
  printf '{"ts":"2026-08-13T00:00:0%s","agentId":"phasetagagent0000%s","subagent":"review-code-%s","purpose":"pre-exec","manuscript_sha256":"null","phase":"pre-exec-analyze"}\n' "$n" "$n" "$A"
done >> "$PROJ/logs/dispatch-manifest.jsonl"
OUT="$TMPDIR_BASE/t11.out"
RC=$(run_gate "$PROJ" --required=fast --phase=pre-exec-analyze "$OUT")
if [ "$RC" -eq 0 ] && grep -q "STATUS=GREEN" "$OUT" && grep -q "dispatch-manifest verified" "$OUT"; then
  pass "GREEN with --phase=pre-exec-analyze rows in manifest"
else
  fail "Expected rc=0 + manifest-verified GREEN with custom phase (got rc=$RC)" "$OUT"
fi

# T11b — same manifest, mismatched tag → RED naming all 3 agents
OUT="$TMPDIR_BASE/t11b.out"
RC=$(run_gate "$PROJ" --required=fast --phase=pre-exec-compute "$OUT")
if [ "$RC" -eq 1 ] && grep -q "STATUS=RED" "$OUT" && grep -q "phase=pre-exec-compute" "$OUT"; then
  pass "RED when manifest rows carry a different phase tag"
else
  fail "Expected rc=1 RED on phase-tag mismatch (got rc=$RC)" "$OUT"
fi

# T12 — explicit --phase with NO dispatch manifest → YELLOW, never token-GREEN
echo ""
echo "Test 12: explicit --phase without dispatch manifest is YELLOW (no token fallback)"
PROJ="$TMPDIR_BASE/proj12"
mkdir -p "$PROJ/reports"
cat > "$PROJ/reports/code-review-pre-2026-08-13.md" <<'EOF'
review-code-correctness review-code-data-handling review-code-statistics
EOF
OUT="$TMPDIR_BASE/t12.out"
RC=$(run_gate "$PROJ" --required=fast --phase=pre-exec-analyze "$OUT")
if [ "$RC" -eq 2 ] && grep -q "STATUS=YELLOW" "$OUT" && grep -q "token-counting cannot stand in" "$OUT"; then
  pass "YELLOW (not token-GREEN) for explicit --phase without provenance"
else
  fail "Expected rc=2 YELLOW without token fallback (got rc=$RC)" "$OUT"
fi

# T12b — identical project WITHOUT --phase still token-falls-back (legacy unchanged)
OUT="$TMPDIR_BASE/t12b.out"
RC=$(run_gate "$PROJ" --required=fast "$OUT")
if [ "$RC" -eq 0 ] && grep -q "legacy token-mode" "$OUT"; then
  pass "legacy token fallback unchanged when --phase absent"
else
  fail "Expected legacy rc=0 token-mode GREEN without --phase (got rc=$RC)" "$OUT"
fi

# ── A6, 2026-08-16 ───────────────────────────────────────────────────────────
# T13/T13b: per-dimension layout. An orchestrator that dispatches the six agents
# separately gets one report per agent; 36 such files existed on the run that
# surfaced this while the gate reported "no code-review report found". They are
# AGGREGATED, not selected — one file carries one dimension, so picking the newest
# would scan a 1-of-6 surface and RED a project that did all six.
echo ""
echo "Test 13: per-dimension reviews/phase-5.5-iterN-<dim>.md is discovered and aggregated"
PROJ="$TMPDIR_BASE/proj13"
mkdir -p "$PROJ/reviews"
for d in correctness data-handling statistics reproducibility robustness style; do
  printf '# iter6 %s\nreview-code-%s\n' "$d" "$d" > "$PROJ/reviews/phase-5.5-iter6-$d.md"
done
OUT="$TMPDIR_BASE/t13.out"
RC=$(run_gate "$PROJ" --required=full "$OUT")
if [ "$RC" -eq 0 ] && grep -q "STATUS=GREEN" "$OUT" && grep -q "REPORT_LAYOUT=per-dimension" "$OUT"; then
  pass "GREEN via aggregated per-dimension layout"
else
  fail "Expected rc=0 + GREEN + REPORT_LAYOUT=per-dimension (got rc=$RC)" "$OUT"
fi

echo ""
echo "Test 13b: NEGATIVE CONTROL — 3 of 6 per-dimension reports still REDs"
PROJ="$TMPDIR_BASE/proj13b"
mkdir -p "$PROJ/reviews"
for d in correctness data-handling statistics; do
  printf '# iter6 %s\nreview-code-%s\n' "$d" "$d" > "$PROJ/reviews/phase-5.5-iter6-$d.md"
done
OUT="$TMPDIR_BASE/t13b.out"
RC=$(run_gate "$PROJ" --required=full "$OUT")
if [ "$RC" -eq 1 ] && grep -q "STATUS=RED" "$OUT" && grep -q "review-code-style" "$OUT"; then
  pass "RED when only 3 of 6 dimensions present (aggregation did not mask the gap)"
else
  fail "Expected rc=1 + RED naming missing dims (got rc=$RC)" "$OUT"
fi

# T14/T14b: a stray positional (e.g. the phase) was silently consumed as
# [<report_path>] and reported as "no report found", flipping a GREEN project to
# YELLOW with a message naming the wrong cause.
echo ""
echo "Test 14: a non-existent explicit report path is REJECTED, not treated as absent"
PROJ="$TMPDIR_BASE/proj14"
mkdir -p "$PROJ/reviews"
for d in correctness data-handling statistics reproducibility robustness style; do
  printf '# iter6 %s\nreview-code-%s\n' "$d" "$d" > "$PROJ/reviews/phase-5.5-iter6-$d.md"
done
OUT="$TMPDIR_BASE/t14.out"
RC=$(run_gate "$PROJ" 5.5 --required=full "$OUT")
if [ "$RC" -eq 1 ] && grep -q "STATUS=RED" "$OUT" && grep -q -- "--phase=5.5" "$OUT"; then
  pass "stray positional rejected with the --phase hint (no silent YELLOW)"
else
  fail "Expected rc=1 + RED + --phase hint (got rc=$RC)" "$OUT"
fi

echo ""
echo "Test 14b: NEGATIVE CONTROL — a genuinely absent report is still YELLOW, not RED"
PROJ="$TMPDIR_BASE/proj14b"
mkdir -p "$PROJ"
OUT="$TMPDIR_BASE/t14b.out"
RC=$(run_gate "$PROJ" --required=full "$OUT")
if [ "$RC" -eq 2 ] && grep -q "STATUS=YELLOW" "$OUT"; then
  pass "absent report remains YELLOW (rejection did not over-fire)"
else
  fail "Expected rc=2 + YELLOW (got rc=$RC)" "$OUT"
fi

echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
