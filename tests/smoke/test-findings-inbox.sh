#!/usr/bin/env bash
# test-findings-inbox.sh — locks the single-writer findings ingestion path
# (system-fix plan v2 S1.3, 2026-08-23): seats write their own
# logs/findings-inbox/<nonce>.ndjson; the orchestrator ingests via
# ingest-findings-inbox.sh — atomically, idempotently, OPEN-only — so four
# parallel seats never race one ledger (handoff P2-4 / CLAUDE.md §7a).
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ING="$REPO_ROOT/scripts/gates/ingest-findings-inbox.sh"
LEDGER_CHECK="$REPO_ROOT/scripts/gates/findings-ledger-check.sh"
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
TMP="$(mktemp -d -t inbox.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/p"; mkdir -p "$P/logs/findings-inbox"
N1="aaaabbbbccccddddeeee0001"
N2="aaaabbbbccccddddeeee0002"

line1='{"id":"CRIT-TH-1","ts":"2026-08-23T12:00:00Z","status":"OPEN","locus":"design/blueprint.md:12","report":"reviews/3.5-theory.md","phase":"3.5"}'
line2='{"id":"MAJ-TH-2","ts":"2026-08-23T12:01:00Z","status":"OPEN","locus":"design/blueprint.md:40","report":"reviews/3.5-theory.md"}'

echo ""
echo "T1: valid inbox ingests into the ledger with source stamps"
printf '%s\n%s\n' "$line1" "$line2" > "$P/logs/findings-inbox/$N1.ndjson"
set +e; OUT=$(bash "$ING" "$P" "$N1" --agentId a1b2c3d4e5f6a7b8c 2>&1); RC=$?; set -u
if [ "$RC" = 0 ] && grep -q "INGESTED=2" <<<"$OUT" && [ "$(grep -c . "$P/logs/findings.ndjson")" = 2 ]; then
  pass "T1a two OPEN lines ingested"
else fail "T1a (rc=$RC): $OUT"; fi
python3 - "$P/logs/findings.ndjson" "$N1" <<'PY' && pass "T1b ledger lines carry source_nonce, source_line_sha, source_agent_id" || fail "T1b stamps missing"
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1])]
assert all(r["source_nonce"] == sys.argv[2] for r in recs)
assert all(len(r["source_line_sha"]) == 16 for r in recs)
assert all(r["source_agent_id"] == "a1b2c3d4e5f6a7b8c" for r in recs)
PY
if [ -x "$LEDGER_CHECK" ]; then
  set +e; LOUT=$(bash "$LEDGER_CHECK" "$P" 2>&1); LRC=$?; set -u
  if [ "$LRC" != 1 ]; then
    pass "T1c stamped lines stay valid under findings-ledger-check (rc=$LRC, not RED)"
  else fail "T1c ledger check REDs stamped lines: $LOUT"; fi
fi

echo ""
echo "T2: re-running the same ingest is idempotent (no duplicate lines)"
set +e; OUT=$(bash "$ING" "$P" "$N1" 2>&1); RC=$?; set -u
if [ "$RC" = 0 ] && grep -q "INGESTED=0" <<<"$OUT" && grep -q "SKIPPED_DUPLICATE=2" <<<"$OUT" \
   && [ "$(grep -c . "$P/logs/findings.ndjson")" = 2 ]; then
  pass "T2 re-ingest skips both lines, ledger unchanged"
else fail "T2 (rc=$RC): $OUT"; fi

echo ""
echo "T3: atomic rejection — one bad line, nothing ingested"
printf '%s\n%s\n' \
  '{"id":"CRIT-Q-1","ts":"2026-08-23T13:00:00Z","status":"OPEN","locus":"scripts/m.R:9","report":"reviews/3.5-quant.md"}' \
  '{"id":"CRIT-Q-2","ts":"2026-08-23T13:01:00Z","status":"FIXED","locus":"scripts/m.R:22","report":"reviews/3.5-quant.md"}' \
  > "$P/logs/findings-inbox/$N2.ndjson"
set +e; OUT=$(bash "$ING" "$P" "$N2" 2>&1); RC=$?; set -u
if [ "$RC" = 1 ] && grep -q "status 'FIXED'" <<<"$OUT" && grep -q "INGESTED=0" <<<"$OUT" \
   && [ "$(grep -c . "$P/logs/findings.ndjson")" = 2 ]; then
  pass "T3 seat-filed FIXED rejected; ledger untouched (atomic)"
else fail "T3 (rc=$RC): $OUT"; fi

echo ""
echo "T4: missing inbox fails closed; --allow-empty is the explicit zero path"
set +e; OUT=$(bash "$ING" "$P" "ffffffffffffffffffffffff" 2>&1); RC=$?; set -u
[ "$RC" = 1 ] && grep -q "fail closed" <<<"$OUT" && pass "T4a typo'd nonce → RED, nothing silently ingested" || fail "T4a (rc=$RC): $OUT"
set +e; OUT=$(bash "$ING" "$P" "ffffffffffffffffffffffff" --allow-empty 2>&1); RC=$?; set -u
[ "$RC" = 0 ] && grep -q "INGESTED=0" <<<"$OUT" && pass "T4b --allow-empty legitimizes a zero-findings seat" || fail "T4b (rc=$RC): $OUT"

echo ""
echo "T5: missing required ledger keys rejected"
N5="aaaabbbbccccddddeeee0005"
printf '{"id":"X-1","status":"OPEN"}\n' > "$P/logs/findings-inbox/$N5.ndjson"
set +e; OUT=$(bash "$ING" "$P" "$N5" 2>&1); RC=$?; set -u
[ "$RC" = 1 ] && grep -q "missing required key" <<<"$OUT" && pass "T5 ledger-schema keys enforced at the inbox door" || fail "T5 (rc=$RC): $OUT"

echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
