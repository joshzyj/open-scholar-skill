#!/usr/bin/env bash
# test-pre-exec-review-check.sh — smoke tests for scripts/gates/pre-exec-review-check.sh
#
# Covers the full state table of the pre-execution review gate
# (_shared/pre-execution-review.md §5): INERT / RED / YELLOW / GREEN,
# hash binding (R2), completeness (R3), the FULL blocking-verdict regex
# shape matrix (R4 — CLAUDE.md rule 10: every accepted label × verdict
# form gets a fixture, plus near-miss negatives), escalation (R5),
# fix chain (R6), and coverage delegation incl. YELLOW→RED mapping (R7).

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${REPO_ROOT}/scripts/gates/pre-exec-review-check.sh"

if [ ! -f "$GATE" ]; then
  echo "FATAL: gate not found at $GATE"
  exit 1
fi

TMPDIR_BASE=$(mktemp -d -t pre-exec-review-smoke.XXXXXX)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        out: $(tr '\n' ' ' < "$2" | head -c 600)"; }

sha() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}

run_gate() {
  # args... ; last arg = capture file
  local args=("$@")
  local outfile="${args[${#args[@]}-1]}"
  unset 'args[${#args[@]}-1]'
  set +e
  bash "$GATE" "${args[@]}" > "$outfile" 2>&1
  local rc=$?
  set -e 2>/dev/null || true
  echo "$rc"
}

# ── happy-path project builder ────────────────────────────────────────────
# build_proj <dir> : scripts/04-models.R + 05-margins.R, clean report,
# hash-correct manifest, dispatch-manifest rows tagged pre-exec-test.
RID="cr-20260813-smoke"
build_proj() {
  local P="$1"
  mkdir -p "$P/scripts" "$P/code-review" "$P/logs"
  printf '# models\nlibrary(fixest)\nm <- feols(y ~ x | st, df, cluster = ~st)\n' > "$P/scripts/04-models.R"
  printf '# margins\nlibrary(marginaleffects)\navg_slopes(m)\n' > "$P/scripts/05-margins.R"
  cat > "$P/code-review/code-review-report-2026-08-13.md" <<EOF
# Consolidated Code Review Report
Review ID: ${RID}
| review-code-correctness | 0 | PASS |
| review-code-data-handling | 0 | PASS |
| review-code-statistics | 0 | PASS |
Overall Verdict: CLEAN — READY TO USE
EOF
  local H1 H2
  H1=$(sha "$P/scripts/04-models.R")
  H2=$(sha "$P/scripts/05-margins.R")
  cat > "$P/code-review/reviewed-scripts-${RID}.json" <<EOF
{"schema": "code-review-manifest/v1",
 "review_id": "${RID}",
 "report": "code-review/code-review-report-2026-08-13.md",
 "mode": "fast", "phase_tag": "pre-exec-test", "ts": "2026-08-13T00:00:00Z",
 "scripts": [{"path": "scripts/04-models.R", "sha256": "${H1}"},
             {"path": "scripts/05-margins.R", "sha256": "${H2}"}],
 "out_of_scope": [],
 "supersedes_review_id": null,
 "fixed_finding_ids": [],
 "remaining_blocking_count": 0}
EOF
  for n in 01 02 03; do
    printf '{"ts":"2026-08-13T00:00:0%s","agentId":"smokeagentid0000%s","subagent":"review-code-%s","purpose":"pre-exec","manuscript_sha256":"null","phase":"pre-exec-test"}\n' \
      "$n" "$n" "$( [ "$n" = 01 ] && echo correctness || { [ "$n" = 02 ] && echo data-handling || echo statistics; } )"
  done >> "$P/logs/dispatch-manifest.jsonl"
}

GATE_ARGS=(--required=fast --phase pre-exec-test)

echo "Test 1: GREEN — hash-bound clean review"
P="$TMPDIR_BASE/p1"; build_proj "$P"; OUT="$TMPDIR_BASE/t1.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "0" ] && grep -q "STATUS=GREEN" "$OUT"; then pass "GREEN on happy path"; else fail "expected GREEN/rc0, got rc=$rc" "$OUT"; fi

echo "Test 2: INERT — no scripts in scope"
P="$TMPDIR_BASE/p2"; mkdir -p "$P/scripts"; OUT="$TMPDIR_BASE/t2.out"
rc=$(run_gate "$P" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "3" ] && grep -q "STATUS=INERT" "$OUT"; then pass "INERT on empty script set"; else fail "expected INERT/rc3, got rc=$rc" "$OUT"; fi

echo "Test 3: RED — scripts but no manifest"
P="$TMPDIR_BASE/p3"; mkdir -p "$P/scripts"; printf 'x<-1\n' > "$P/scripts/04-models.R"; OUT="$TMPDIR_BASE/t3.out"
rc=$(run_gate "$P" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "STATUS=RED" "$OUT" && grep -q "no reviewed-scripts manifest" "$OUT"; then pass "RED scripts-without-manifest"; else fail "expected RED/rc1, got rc=$rc" "$OUT"; fi

echo "Test 4: YELLOW — same, with --legacy-ok"
OUT="$TMPDIR_BASE/t4.out"
rc=$(run_gate "$P" --legacy-ok "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "2" ] && grep -q "STATUS=YELLOW" "$OUT" && grep -q "non-executable" "$OUT"; then pass "YELLOW legacy is declared non-executable"; else fail "expected YELLOW/rc2, got rc=$rc" "$OUT"; fi

echo "Test 5: RED — hash mismatch (script edited after review)"
P="$TMPDIR_BASE/p5"; build_proj "$P"; printf '\n# post-review edit\n' >> "$P/scripts/04-models.R"; OUT="$TMPDIR_BASE/t5.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "HASH MISMATCH" "$OUT"; then pass "RED on single-byte post-review edit"; else fail "expected RED hash mismatch, got rc=$rc" "$OUT"; fi

echo "Test 6: RED — reviewed script missing from disk"
P="$TMPDIR_BASE/p6"; build_proj "$P"; rm "$P/scripts/05-margins.R"; OUT="$TMPDIR_BASE/t6.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "MISSING" "$OUT"; then pass "RED on reviewed-but-deleted script"; else fail "expected RED missing, got rc=$rc" "$OUT"; fi

echo "Test 7: RED — unreviewed extra script in scope"
P="$TMPDIR_BASE/p7"; build_proj "$P"; printf 'y<-2\n' > "$P/scripts/06-extra.R"; OUT="$TMPDIR_BASE/t7.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "06-extra.R" "$OUT"; then pass "RED on unreviewed extra script"; else fail "expected RED extra, got rc=$rc" "$OUT"; fi

echo "Test 8: GREEN — extra script declared out_of_scope"
P="$TMPDIR_BASE/p8"; build_proj "$P"; printf 'y<-2\n' > "$P/scripts/E01-eda.R"
M="$P/code-review/reviewed-scripts-${RID}.json"
jq '.out_of_scope = [{"path": "scripts/E01-eda.R", "reason": "already executed EDA; context only"}]' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
OUT="$TMPDIR_BASE/t8.out"
rc=$(run_gate "$P" --manifest "$M" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "0" ] && grep -q "STATUS=GREEN" "$OUT"; then pass "GREEN with declared out_of_scope"; else fail "expected GREEN, got rc=$rc" "$OUT"; fi

echo "Test 9: verdict shape matrix — every label × blocking string is RED"
VERD_OK=1
for LABEL in "Overall Verdict:" "overall verdict:" "VERDICT:"; do
  for V in "CRITICAL" "HALT" "FAIL" "MAJOR ISSUES" "FIXES NEEDED" "DO NOT TRUST RESULTS"; do
    P="$TMPDIR_BASE/p9"; rm -rf "$P"; build_proj "$P"
    R="$P/code-review/code-review-report-2026-08-13.md"
    grep -v "Overall Verdict" "$R" > "$R.tmp" && mv "$R.tmp" "$R"
    printf '%s %s\n' "$LABEL" "$V" >> "$R"
    OUT="$TMPDIR_BASE/t9.out"
    rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
    if [ "$rc" != "1" ] || ! grep -q "blocking verdict" "$OUT"; then
      VERD_OK=0; fail "verdict shape not caught: '$LABEL $V' (rc=$rc)" "$OUT"
    fi
  done
done
[ "$VERD_OK" = "1" ] && pass "all 18 label×verdict shapes RED"

echo "Test 10: near-miss negatives — blocking strings in prose stay GREEN"
P="$TMPDIR_BASE/p10"; build_proj "$P"
R="$P/code-review/code-review-report-2026-08-13.md"
printf 'Findings included two CRITICAL items, both resolved before this verdict.\nPREVIOUS VERDICT: CRITICAL (superseded)\n' >> "$R"
OUT="$TMPDIR_BASE/t10.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "0" ]; then pass "prose mentions of CRITICAL do not false-RED"; else fail "false positive on prose near-miss (rc=$rc)" "$OUT"; fi

echo "Test 11: RED — non-empty escalation log"
P="$TMPDIR_BASE/p11"; build_proj "$P"; printf 'Escalated: tautological outcome in 04-models.R\n' > "$P/logs/code-review-escalation-2026-08-13.md"
OUT="$TMPDIR_BASE/t11.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "escalation log" "$OUT"; then pass "RED on unresolved escalation"; else fail "expected RED escalation, got rc=$rc" "$OUT"; fi

echo "Test 12: RED — remaining_blocking_count > 0"
P="$TMPDIR_BASE/p12"; build_proj "$P"
M="$P/code-review/reviewed-scripts-${RID}.json"
jq '.remaining_blocking_count = 2' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
OUT="$TMPDIR_BASE/t12.out"
rc=$(run_gate "$P" --manifest "$M" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "remaining_blocking_count=2" "$OUT"; then pass "RED on unresolved blocking count"; else fail "expected RED blocking-count, got rc=$rc" "$OUT"; fi

echo "Test 13: RED — supersedes chain names a nonexistent prior review"
P="$TMPDIR_BASE/p13"; build_proj "$P"
M="$P/code-review/reviewed-scripts-${RID}.json"
jq '.supersedes_review_id = "cr-20260812-ghost"' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
OUT="$TMPDIR_BASE/t13.out"
rc=$(run_gate "$P" --manifest "$M" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "broken fix chain" "$OUT"; then pass "RED on broken supersedes chain"; else fail "expected RED chain, got rc=$rc" "$OUT"; fi

echo "Test 14: GREEN — valid supersedes chain (re-review after fixes)"
P="$TMPDIR_BASE/p14"; build_proj "$P"
RID2="cr-20260813-rerev"
R2="$P/code-review/code-review-report-2026-08-13-v2.md"
sed "s/${RID}/${RID2}/" "$P/code-review/code-review-report-2026-08-13.md" > "$R2"
H1=$(sha "$P/scripts/04-models.R"); H2=$(sha "$P/scripts/05-margins.R")
cat > "$P/code-review/reviewed-scripts-${RID2}.json" <<EOF
{"schema": "code-review-manifest/v1", "review_id": "${RID2}",
 "report": "code-review/code-review-report-2026-08-13-v2.md",
 "mode": "fast", "phase_tag": "pre-exec-test", "ts": "2026-08-13T01:00:00Z",
 "scripts": [{"path": "scripts/04-models.R", "sha256": "${H1}"},
             {"path": "scripts/05-margins.R", "sha256": "${H2}"}],
 "out_of_scope": [],
 "supersedes_review_id": "${RID}",
 "fixed_finding_ids": ["CRIT-001"],
 "remaining_blocking_count": 0}
EOF
OUT="$TMPDIR_BASE/t14.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID2}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "0" ] && grep -q "STATUS=GREEN" "$OUT"; then pass "GREEN on valid re-review chain"; else fail "expected GREEN chain, got rc=$rc" "$OUT"; fi

echo "Test 15: RED — coverage delegation maps provenance YELLOW to RED"
P="$TMPDIR_BASE/p15"; build_proj "$P"; rm "$P/logs/dispatch-manifest.jsonl"
OUT="$TMPDIR_BASE/t15.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "NOTE: a coverage YELLOW" "$OUT"; then pass "delegated YELLOW mapped to RED with note"; else fail "expected RED via coverage map, got rc=$rc" "$OUT"; fi

echo "Test 16: RED — report/manifest review_id pair mismatch"
P="$TMPDIR_BASE/p16"; build_proj "$P"
sed 's/Review ID: .*/Review ID: cr-20260813-other/' "$P/code-review/code-review-report-2026-08-13.md" > "$P/code-review/tmp.md" && mv "$P/code-review/tmp.md" "$P/code-review/code-review-report-2026-08-13.md"
OUT="$TMPDIR_BASE/t16.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "pair mismatch" "$OUT"; then pass "RED on report/manifest id mismatch"; else fail "expected RED pair mismatch, got rc=$rc" "$OUT"; fi


echo "Test 17: R6b — fixed_finding_ids FIXED-never-VERIFIED → YELLOW (DC-03)"
P="$TMPDIR_BASE/p17"; build_proj "$P"
M="$P/code-review/reviewed-scripts-${RID}.json"
jq '.fixed_finding_ids = ["CRIT-STAT-301", "CRIT-CORR-101"]' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
mkdir -p "$P/logs"
cat > "$P/logs/findings.ndjson" <<'EOF'
{"id": "CRIT-STAT-301", "ts": "2026-08-22T10:00:00Z", "status": "OPEN", "locus": "scripts/04-models.R:10", "report": "r.md"}
{"id": "CRIT-STAT-301", "ts": "2026-08-22T11:00:00Z", "status": "FIXED", "locus": "scripts/04-models.R:10", "report": "r.md"}
{"id": "CRIT-CORR-101", "ts": "2026-08-22T10:00:00Z", "status": "OPEN", "locus": "scripts/05-margins.R:4", "report": "r.md"}
{"id": "CRIT-CORR-101", "ts": "2026-08-22T11:00:00Z", "status": "FIXED", "locus": "scripts/05-margins.R:4", "report": "r.md"}
{"id": "CRIT-CORR-101", "ts": "2026-08-22T12:00:00Z", "status": "VERIFIED", "locus": "scripts/05-margins.R:4", "report": "r.md"}
EOF
OUT="$TMPDIR_BASE/t17.out"
rc=$(run_gate "$P" --manifest "$M" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "2" ] && grep -q "CRIT-STAT-301" "$OUT" && ! grep -q "CRIT-CORR-101 " "$OUT" && grep -q "closure authority" "$OUT"; then
  pass "YELLOW names only the FIXED-unverified id"
else fail "expected YELLOW naming CRIT-STAT-301 only, got rc=$rc" "$OUT"; fi

echo "Test 18: R6b — all fixed ids VERIFIED → GREEN"
P="$TMPDIR_BASE/p18"; build_proj "$P"
M="$P/code-review/reviewed-scripts-${RID}.json"
jq '.fixed_finding_ids = ["CRIT-CORR-101"]' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
mkdir -p "$P/logs"
cat > "$P/logs/findings.ndjson" <<'EOF'
{"id": "CRIT-CORR-101", "ts": "2026-08-22T11:00:00Z", "status": "FIXED", "locus": "scripts/05-margins.R:4", "report": "r.md"}
{"id": "CRIT-CORR-101", "ts": "2026-08-22T12:00:00Z", "status": "VERIFIED", "locus": "scripts/05-margins.R:4", "report": "r.md"}
EOF
OUT="$TMPDIR_BASE/t18.out"
rc=$(run_gate "$P" --manifest "$M" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "0" ] && grep -q "STATUS=GREEN" "$OUT"; then pass "GREEN when every fixed id has a VERIFIED line"; else fail "expected GREEN, got rc=$rc" "$OUT"; fi

echo "Test 19: R4 RED text names the §7b acceptance lane"
P="$TMPDIR_BASE/p19"; build_proj "$P"
R="$P/code-review/code-review-report-2026-08-13.md"
grep -v "Overall Verdict" "$R" > "$R.tmp" && mv "$R.tmp" "$R"
printf 'Overall Verdict: CRITICAL\n' >> "$R"
OUT="$TMPDIR_BASE/t19.out"
rc=$(run_gate "$P" --manifest "$P/code-review/reviewed-scripts-${RID}.json" "${GATE_ARGS[@]}" "$OUT")
if [ "$rc" = "1" ] && grep -q "PROPOSED-ACCEPTANCE" "$OUT" && grep -q "gate-acceptances.md" "$OUT"; then
  pass "RED text routes acceptance through the §7b lane"
else fail "expected RED naming the acceptance lane, got rc=$rc" "$OUT"; fi

echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
