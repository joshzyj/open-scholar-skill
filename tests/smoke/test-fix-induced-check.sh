#!/usr/bin/env bash
# test-fix-induced-check.sh — locks the ≥50%-fix-induced escalation rule
# (scripts/gates/fix-induced-check.sh; RCA Round 3 #11, 2026-08-22).
#
# WHY: F-96 — a fix round's blast radius is the next review's finding
# population (ses: 4 of 5 iter-3 CRITICALs were created by iter-2 fixes).
# These tests pin: attribution via receipt write-sets (changed-set when a
# prior manifest exists), UNKNOWN excluded from BOTH sides of the ratio,
# the >=2-attributable floor, and the INERT ladder.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${REPO_ROOT}/scripts/gates/fix-induced-check.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMPROOT="$(mktemp -d -t fixind-smoke.XXXXXX)"
trap 'rm -rf "$TMPROOT" 2>/dev/null' EXIT

run() { set +e; OUT=$(bash "$GATE" "$1" 2>&1); RC=$?; set -u; }

mk_ledger() {
  # $1 proj; stdin = ndjson
  mkdir -p "$1/logs"
  cat > "$1/logs/findings.ndjson"
}
mk_receipt() {
  # $1 proj, $2 name, $3 json
  mkdir -p "$1/code-review"
  printf '%s\n' "$3" > "$1/code-review/$2"
}

echo ""
echo "T1: no ledger → INERT"
P="$TMPROOT/t1"; mkdir -p "$P"
run "$P"
[ "$RC" = 3 ] && grep -q "STATUS=INERT" <<<"$OUT" && pass "T1 INERT without lineage" || fail "T1 (rc=$RC)"

echo ""
echo "T2: iter-1-only findings → INERT (no fix round reviewed yet)"
P="$TMPROOT/t2"
mk_ledger "$P" <<'EOF'
{"id":"CRIT-A-1","ts":"t","iter":1,"status":"OPEN","locus":"scripts/a.R:10","report":"r.md"}
EOF
run "$P"
[ "$RC" = 3 ] && grep -q "iteration >= 2" <<<"$OUT" && pass "T2 INERT at iter 1" || fail "T2 (rc=$RC)"

echo ""
echo "T3: ses-shaped RED — most iter-2 findings live in files the fix round wrote"
P="$TMPROOT/t3"
mk_ledger "$P" <<'EOF'
{"id":"CRIT-A-1","ts":"t1","iter":1,"status":"OPEN","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-B-1","ts":"t1","iter":1,"status":"OPEN","locus":"scripts/b.R:5","report":"r.md"}
{"id":"CRIT-A-1","ts":"t2","iter":1,"status":"FIXED","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-B-1","ts":"t2","iter":1,"status":"FIXED","locus":"scripts/b.R:5","report":"r.md"}
{"id":"CRIT-C-2","ts":"t3","iter":2,"status":"OPEN","locus":"scripts/a.R:44","report":"r2.md"}
{"id":"CRIT-D-2","ts":"t3","iter":2,"status":"OPEN","locus":"scripts/b.R:9","report":"r2.md"}
{"id":"CRIT-E-2","ts":"t3","iter":2,"status":"OPEN","locus":"scripts/z.R:1","report":"r2.md"}
EOF
mk_receipt "$P" "reviewed-scripts-fix-r1.json" '{"schema":"code-review-manifest/v1","review_id":"fix-r1","report":"logs/f.md","scripts":[{"path":"scripts/a.R","sha256":"aa"},{"path":"scripts/b.R","sha256":"bb"}],"fixed_finding_ids":["CRIT-A-1","CRIT-B-1"],"remaining_blocking_count":0,"supersedes_review_id":null}'
mkdir -p "$P/scripts"; touch "$P/scripts/a.R" "$P/scripts/b.R" "$P/scripts/z.R"
run "$P"
if [ "$RC" = 1 ] && grep -q "FIX_INDUCED=2" <<<"$OUT" && grep -q "NOT_INDUCED=1" <<<"$OUT" && grep -q "HALT-ESCALATE" <<<"$OUT"; then
  pass "T3 2/3 induced → RED escalate (F-96)"
else fail "T3 (rc=$RC): $(grep -E 'STATUS|FIX_IND' <<<"$OUT" | tr '\n' ' ')"; fi

echo ""
echo "T4: minority induced → GREEN"
P="$TMPROOT/t4"
mk_ledger "$P" <<'EOF'
{"id":"CRIT-A-1","ts":"t1","iter":1,"status":"OPEN","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-C-2","ts":"t3","iter":2,"status":"OPEN","locus":"scripts/a.R:44","report":"r2.md"}
{"id":"CRIT-D-2","ts":"t3","iter":2,"status":"OPEN","locus":"scripts/x.R:9","report":"r2.md"}
{"id":"CRIT-E-2","ts":"t3","iter":2,"status":"OPEN","locus":"scripts/y.R:1","report":"r2.md"}
EOF
mk_receipt "$P" "reviewed-scripts-fix-r1.json" '{"schema":"code-review-manifest/v1","review_id":"fix-r1","report":"logs/f.md","scripts":[{"path":"scripts/a.R","sha256":"aa"}],"fixed_finding_ids":["CRIT-A-1"],"remaining_blocking_count":0,"supersedes_review_id":null}'
mkdir -p "$P/scripts"; touch "$P/scripts/a.R" "$P/scripts/x.R" "$P/scripts/y.R"
run "$P"
[ "$RC" = 0 ] && grep -q "FIX_INDUCED=1" <<<"$OUT" && pass "T4 1/3 induced → GREEN" || fail "T4 (rc=$RC)"

echo ""
echo "T5: UNKNOWN excluded from both sides — unattributable loci cannot fire the rule"
P="$TMPROOT/t5"
mk_ledger "$P" <<'EOF'
{"id":"CRIT-A-1","ts":"t1","iter":1,"status":"OPEN","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-C-2","ts":"t3","iter":2,"status":"OPEN","locus":"design-level concern","report":"r2.md"}
{"id":"CRIT-D-2","ts":"t3","iter":2,"status":"OPEN","locus":"estimand framing","report":"r2.md"}
{"id":"CRIT-E-2","ts":"t3","iter":2,"status":"OPEN","locus":"scripts/a.R:44","report":"r2.md"}
EOF
mk_receipt "$P" "reviewed-scripts-fix-r1.json" '{"schema":"code-review-manifest/v1","review_id":"fix-r1","report":"logs/f.md","scripts":[{"path":"scripts/a.R","sha256":"aa"}],"fixed_finding_ids":["CRIT-A-1"],"remaining_blocking_count":0,"supersedes_review_id":null}'
run "$P"
if [ "$RC" = 2 ] && grep -q "UNKNOWN=2" <<<"$OUT" && grep -q "inconclusive" <<<"$OUT"; then
  pass "T5 UNKNOWN-majority → YELLOW, never RED"
else fail "T5 (rc=$RC): $(grep STATUS <<<"$OUT")"; fi

echo ""
echo "T6: changed-set refinement — untouched receipt paths do not attribute"
P="$TMPROOT/t6"
mk_ledger "$P" <<'EOF'
{"id":"CRIT-A-1","ts":"t1","iter":1,"status":"OPEN","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-C-2","ts":"t3","iter":2,"status":"OPEN","locus":"scripts/b.R:44","report":"r2.md"}
{"id":"CRIT-D-2","ts":"t3","iter":2,"status":"OPEN","locus":"scripts/c.R:9","report":"r2.md"}
EOF
mk_receipt "$P" "reviewed-scripts-2026.json" '{"schema":"code-review-manifest/v1","review_id":"cr-base","report":"logs/f.md","scripts":[{"path":"scripts/a.R","sha256":"OLD"},{"path":"scripts/b.R","sha256":"SAME"},{"path":"scripts/c.R","sha256":"SAME2"}]}'
mk_receipt "$P" "reviewed-scripts-fix-r1.json" '{"schema":"code-review-manifest/v1","review_id":"fix-r1","report":"logs/f.md","scripts":[{"path":"scripts/a.R","sha256":"NEW"},{"path":"scripts/b.R","sha256":"SAME"},{"path":"scripts/c.R","sha256":"SAME2"}],"fixed_finding_ids":["CRIT-A-1"],"remaining_blocking_count":0,"supersedes_review_id":"cr-base"}'
mkdir -p "$P/scripts"; touch "$P/scripts/a.R" "$P/scripts/b.R" "$P/scripts/c.R"
run "$P"
if [ "$RC" = 0 ] && grep -q "FIX_INDUCED=0" <<<"$OUT" && grep -q "NOT_INDUCED=2" <<<"$OUT"; then
  pass "T6 only CHANGED paths (sha drift vs superseded manifest) attribute"
else fail "T6 (rc=$RC): $(grep -E 'FIX_IND|NOT_IND|STATUS' <<<"$OUT" | tr '\n' ' ')"; fi

echo ""
echo "T7: consumer-edge attribution — damage in a file the fixer never touched (HIGH)"
P="$TMPROOT/t7"
mk_ledger "$P" <<'EOF'
{"id":"CRIT-A-1","ts":"2026-08-22T10:00:00Z","iter":1,"status":"OPEN","locus":"scripts/a.R:10","affected_consumers":["scripts/b.R"],"report":"r.md"}
{"id":"CRIT-A-1","ts":"2026-08-22T11:00:00Z","iter":1,"status":"FIXED","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-C-2","ts":"2026-08-22T12:00:00Z","iter":2,"status":"OPEN","locus":"scripts/a.R:44","report":"r2.md"}
{"id":"CRIT-D-2","ts":"2026-08-22T12:00:01Z","iter":2,"status":"OPEN","locus":"scripts/b.R:9","report":"r2.md"}
{"id":"CRIT-E-2","ts":"2026-08-22T12:00:02Z","iter":2,"status":"OPEN","locus":"scripts/b.R:22","report":"r2.md"}
EOF
mk_receipt "$P" "reviewed-scripts-fix-r1.json" '{"schema":"code-review-manifest/v1","review_id":"fix-r1","ts":"2026-08-22T11:30:00Z","report":"logs/f.md","scripts":[{"path":"scripts/a.R","sha256":"aa"}],"fixed_finding_ids":["CRIT-A-1"],"remaining_blocking_count":0,"supersedes_review_id":null}'
mkdir -p "$P/scripts"; touch "$P/scripts/a.R" "$P/scripts/b.R"
run "$P"
if [ "$RC" = 1 ] && grep -q "FIX_INDUCED=3" <<<"$OUT" && grep -q "consumer-edge" <<<"$OUT"; then
  pass "T7 affected_consumers edges attribute — 3/3 induced → RED"
else fail "T7 (rc=$RC): $(grep -E 'FIX_IND|NOT_IND|UNKNOWN|STATUS' <<<"$OUT" | tr '\n' ' ')"; fi

echo ""
echo "T8: regression re-OPEN — pure churn is RED, never INERT (F5)"
P="$TMPROOT/t8"
mk_ledger "$P" <<'EOF'
{"id":"CRIT-A-1","ts":"2026-08-22T10:00:00Z","iter":1,"status":"OPEN","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-B-1","ts":"2026-08-22T10:00:01Z","iter":1,"status":"OPEN","locus":"scripts/b.R:5","report":"r.md"}
{"id":"CRIT-A-1","ts":"2026-08-22T11:00:00Z","iter":1,"status":"FIXED","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-B-1","ts":"2026-08-22T11:00:01Z","iter":1,"status":"FIXED","locus":"scripts/b.R:5","report":"r.md"}
{"id":"CRIT-A-1","ts":"2026-08-22T12:00:00Z","iter":2,"status":"OPEN","locus":"scripts/a.R:10","report":"r2.md"}
{"id":"CRIT-B-1","ts":"2026-08-22T12:00:01Z","iter":2,"status":"OPEN","locus":"scripts/b.R:5","report":"r2.md"}
EOF
mk_receipt "$P" "reviewed-scripts-fix-r1.json" '{"schema":"code-review-manifest/v1","review_id":"fix-r1","ts":"2026-08-22T11:30:00Z","report":"logs/f.md","scripts":[{"path":"scripts/a.R","sha256":"aa"},{"path":"scripts/b.R","sha256":"bb"}],"fixed_finding_ids":["CRIT-A-1","CRIT-B-1"],"remaining_blocking_count":0,"supersedes_review_id":null}'
mkdir -p "$P/scripts"; touch "$P/scripts/a.R" "$P/scripts/b.R"
run "$P"
if [ "$RC" = 1 ] && grep -q "regression-reopen" <<<"$OUT" && grep -q "FIX_INDUCED=2" <<<"$OUT"; then
  pass "T8 re-OPENed FIXED findings are induced instances → RED"
else fail "T8 (rc=$RC): $(grep -E 'STATUS|FIX_IND|REASON' <<<"$OUT" | head -3 | tr '\n' ' ')"; fi

echo ""
echo "T9: time discipline — a cleanup receipt post-dating the latest findings cannot attribute (F6)"
P="$TMPROOT/t9"
mk_ledger "$P" <<'EOF'
{"id":"CRIT-A-1","ts":"2026-08-22T10:00:00Z","iter":1,"status":"OPEN","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-B-1","ts":"2026-08-22T10:00:01Z","iter":1,"status":"OPEN","locus":"scripts/q.R:5","report":"r.md"}
{"id":"CRIT-C-2","ts":"2026-08-22T12:00:00Z","iter":2,"status":"OPEN","locus":"scripts/z.R:44","report":"r2.md"}
{"id":"CRIT-D-2","ts":"2026-08-22T12:00:01Z","iter":2,"status":"OPEN","locus":"scripts/y.R:9","report":"r2.md"}
EOF
mk_receipt "$P" "reviewed-scripts-fix-r1.json" '{"schema":"code-review-manifest/v1","review_id":"fix-r1","ts":"2026-08-22T11:00:00Z","report":"logs/f.md","scripts":[{"path":"scripts/a.R","sha256":"aa"}],"fixed_finding_ids":["CRIT-A-1"],"remaining_blocking_count":0,"supersedes_review_id":null}'
mk_receipt "$P" "reviewed-scripts-fix-r2.json" '{"schema":"code-review-manifest/v1","review_id":"fix-r2","ts":"2026-08-22T14:00:00Z","report":"logs/f.md","scripts":[{"path":"scripts/z.R","sha256":"zz"},{"path":"scripts/y.R","sha256":"yy"}],"fixed_finding_ids":["CRIT-B-1"],"remaining_blocking_count":0,"supersedes_review_id":null}'
mkdir -p "$P/scripts"; touch "$P/scripts/a.R" "$P/scripts/q.R" "$P/scripts/z.R" "$P/scripts/y.R"
run "$P"
if [ "$RC" != 1 ] && grep -q "time discipline" <<<"$OUT" && grep -q "FIX_INDUCED=0" <<<"$OUT"; then
  pass "T9 late cleanup receipt excluded — no false RED"
else fail "T9 (rc=$RC): $(grep -E 'STATUS|FIX_IND|NOTE' <<<"$OUT" | tr '\n' ' ')"; fi

echo ""
echo "T10: locus anchor formats reduce to the file, never phantom NOT_INDUCED (F7)"
P="$TMPROOT/t10"
mk_ledger "$P" <<'EOF'
{"id":"CRIT-A-1","ts":"2026-08-22T10:00:00Z","iter":1,"status":"OPEN","locus":"scripts/a.R:10","report":"r.md"}
{"id":"CRIT-C-2","ts":"2026-08-22T12:00:00Z","iter":2,"status":"OPEN","locus":"scripts/a.R line 44","report":"r2.md"}
{"id":"CRIT-D-2","ts":"2026-08-22T12:00:01Z","iter":2,"status":"OPEN","locus":"scripts/a.R#L99","report":"r2.md"}
EOF
mk_receipt "$P" "reviewed-scripts-fix-r1.json" '{"schema":"code-review-manifest/v1","review_id":"fix-r1","ts":"2026-08-22T11:00:00Z","report":"logs/f.md","scripts":[{"path":"scripts/a.R","sha256":"aa"}],"fixed_finding_ids":["CRIT-A-1"],"remaining_blocking_count":0,"supersedes_review_id":null}'
mkdir -p "$P/scripts"; touch "$P/scripts/a.R"
run "$P"
if [ "$RC" = 1 ] && grep -q "FIX_INDUCED=2" <<<"$OUT" && grep -q "NOT_INDUCED=0" <<<"$OUT"; then
  pass "T10 space/#L anchors attribute to the real file → RED"
else fail "T10 (rc=$RC): $(grep -E 'FIX_IND|NOT_IND|UNKNOWN' <<<"$OUT" | tr '\n' ' ')"; fi


echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "── Results: PASS=$PASS FAIL=0 ──"; exit 0
else
  echo "── Results: PASS=$PASS FAIL=$FAIL ──"; exit 1
fi
