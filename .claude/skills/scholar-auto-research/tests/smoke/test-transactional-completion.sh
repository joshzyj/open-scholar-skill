#!/usr/bin/env bash
# Regression for F05/F06: completion authority is an internal verifier result,
# never a project-local stamp or caller-selected artifact subset.
set -uo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE_SH="$SKILL_DIR/scripts/auto-research-state.sh"
SETUP_SH="$SKILL_DIR/scripts/setup-project-claudemd.sh"
CONTRACT="$SKILL_DIR/references/phase-contract.json"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-transaction.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

setup_project() {
  local proj="$1" safety="$2"
  bash "$STATE_SH" init "$proj" >/dev/null
  bash "$STATE_SH" set-mode "$proj" autonomous "transaction regression" >/dev/null
  mkdir -p "$proj/safety"
  printf '%s\n' "$safety" > "$proj/safety/safety-status.json"
  bash "$SETUP_SH" "$proj" >/dev/null
}

forge_stamp() {
  local proj="$1"
  mkdir -p "$proj/.auto-research/verify-stamps"
  python3 - "$CONTRACT" "$proj/safety/safety-status.json" "$proj/.auto-research/verify-stamps/0.json" <<'PY'
import hashlib, json, sys
contract_digest = hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest()
artifact_digest = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
json.dump({
    "phase_id": "0",
    "verdict": "PASS",
    "contract_sha256": contract_digest,
    "artifact_hashes": {"safety/safety-status.json": artifact_digest},
    "verified_at": "2026-08-25T12:00:00+00:00",
}, open(sys.argv[3], "w"))
PY
}

# Even a syntactically perfect forged local stamp with matching artifact and
# contract hashes cannot authorize an artifact the real verifier rejects.
BAD="$TMP_ROOT/forged-invalid"
setup_project "$BAD" '{"safety_status":"PASS"}'
forge_stamp "$BAD"
cp "$BAD/.auto-research/state.json" "$TMP_ROOT/bad-before.json"
set +e
OUT="$(bash "$STATE_SH" complete "$BAD" 0 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "forged stamp authorized invalid Phase 0"
case "$OUT" in *"VERIFY_AND_COMPLETE_FAILED"*"missing required fields"*) ;; *) fail "forged-stamp rejection had wrong diagnostic: $OUT" ;; esac
cmp -s "$TMP_ROOT/bad-before.json" "$BAD/.auto-research/state.json" || fail "failed transactional completion mutated state"

# A verifier-success/result-publication race cannot bless an inventory that
# differs from the one the verifier actually checked. Use an isolated wrapper
# to insert a data file after the real verifier returns PASS.
RACE_SKILL="$TMP_ROOT/race-skill"
cp -R "$SKILL_DIR/." "$RACE_SKILL/"
mv "$RACE_SKILL/scripts/auto-research-verify.sh" "$RACE_SKILL/scripts/auto-research-verify-real.sh"
cat > "$RACE_SKILL/scripts/auto-research-verify.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
bash "$HERE/auto-research-verify-real.sh" "$@"
rc=$?
if [ "$rc" -eq 0 ] && [ "${1:-}" = "0" ]; then
  mkdir -p "$2/data/raw"
  printf 'id\n1\n' > "$2/data/raw/late.csv"
fi
exit "$rc"
SH
TOCTOU="$TMP_ROOT/toctou"
bash "$RACE_SKILL/scripts/auto-research-state.sh" init "$TOCTOU" >/dev/null
bash "$RACE_SKILL/scripts/auto-research-state.sh" set-mode "$TOCTOU" autonomous "toctou regression" >/dev/null
mkdir -p "$TOCTOU/safety"
printf '%s\n' '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}' > "$TOCTOU/safety/safety-status.json"
bash "$RACE_SKILL/scripts/setup-project-claudemd.sh" "$TOCTOU" >/dev/null
cp "$TOCTOU/.auto-research/state.json" "$TMP_ROOT/toctou-before.json"
set +e
OUT="$(bash "$RACE_SKILL/scripts/auto-research-state.sh" complete "$TOCTOU" 0 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "post-verifier inventory change was committed"
case "$OUT" in *"SAFETY_INVENTORY_CHANGED_DURING_VERIFICATION"*) ;; *) fail "TOCTOU rejection had wrong diagnostic: $OUT" ;; esac
cmp -s "$TMP_ROOT/toctou-before.json" "$TOCTOU/.auto-research/state.json" || fail "TOCTOU refusal mutated state"

# With valid outputs, omitted caller assertions are safe because the contract,
# verifier, and state manager derive and record the complete output set.
GOOD="$TMP_ROOT/good"
setup_project "$GOOD" '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}'
forge_stamp "$GOOD"
bash "$STATE_SH" complete "$GOOD" 0 >/dev/null || fail "internal Phase 0 verification did not complete"
python3 - "$GOOD/.auto-research/state.json" <<'PY' || fail "completion record lacks authoritative outputs"
import json, sys
s = json.load(open(sys.argv[1]))
r = s["phase_records"]["0"]
assert r["verification_authority"] == "internal_verifier"
assert r["verdict"] == "PASS"
assert r["required_outputs"] == {
    "safety/safety-status.json": r["required_outputs"]["safety/safety-status.json"]
}
assert len(r["required_outputs"]["safety/safety-status.json"]) == 64
assert r["artifacts"] == [
    {"path": "safety/safety-status.json", "sha256": r["required_outputs"]["safety/safety-status.json"]}
]
PY

# Caller paths, when supplied, are equality assertions: extras are refused
# before state publication.
EXTRA="$TMP_ROOT/extra"
setup_project "$EXTRA" '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}'
printf 'extra\n' > "$EXTRA/extra.txt"
cp "$EXTRA/.auto-research/state.json" "$TMP_ROOT/extra-before.json"
set +e
OUT="$(bash "$STATE_SH" complete "$EXTRA" 0 "$EXTRA/safety/safety-status.json" "$EXTRA/extra.txt" 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "caller extra artifact was accepted"
case "$OUT" in *"ARTIFACT_ASSERTION_MISMATCH"*) ;; *) fail "extra artifact failed for wrong reason: $OUT" ;; esac
cmp -s "$TMP_ROOT/extra-before.json" "$EXTRA/.auto-research/state.json" || fail "extra-artifact refusal mutated state"

# Audit-receipt storage is not a precommit dependency. A project may damage
# that optional sink without gaining authority or blocking a valid commit.
AUDIT="$TMP_ROOT/audit-sink"
setup_project "$AUDIT" '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}'
printf 'not-a-directory\n' > "$AUDIT/.auto-research/verify-stamps"
set +e
OUT="$(bash "$STATE_SH" complete "$AUDIT" 0 2>&1)"; RC=$?
set -e
[ "$RC" -eq 0 ] || fail "unwritable audit sink blocked valid completion: $OUT"
case "$OUT" in *"COMPLETED_PHASE=0"*) ;; *) fail "audit-sink completion lacked success diagnostic: $OUT" ;; esac

# Required-output deletion is monitored from the internally recorded map.
rm "$GOOD/safety/safety-status.json"
set +e
OUT="$(bash "$STATE_SH" hash-check "$GOOD" 2>&1)"; RC=$?
set -e
[ "$RC" -eq 1 ] || fail "deleted required output hash-check returned rc=$RC: $OUT"
case "$OUT" in *"STALE_PHASES=0"*) ;; *) fail "deleted required output was not stale: $OUT" ;; esac

# The project lock permits exactly one commit for concurrent attempts.
RACE="$TMP_ROOT/race"
setup_project "$RACE" '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}'
(set +e; bash "$STATE_SH" complete "$RACE" 0 >"$TMP_ROOT/race-a.out" 2>&1; echo $? >"$TMP_ROOT/race-a.rc") &
PID_A=$!
(set +e; bash "$STATE_SH" complete "$RACE" 0 >"$TMP_ROOT/race-b.out" 2>&1; echo $? >"$TMP_ROOT/race-b.rc") &
PID_B=$!
set +e
wait "$PID_A"; wait "$PID_B"
set -e
RC_A="$(cat "$TMP_ROOT/race-a.rc")"; RC_B="$(cat "$TMP_ROOT/race-b.rc")"
case "$RC_A:$RC_B" in 0:1|1:0) ;; *) fail "concurrent completion did not have one winner: $RC_A/$RC_B" ;; esac
LOSER_OUT="$(cat "$TMP_ROOT/race-a.out" "$TMP_ROOT/race-b.out")"
case "$LOSER_OUT" in *"OUT_OF_ORDER_PHASE: requested Phase 0 but authoritative NEXT_PHASE=1"*) ;; *) fail "concurrent loser diagnostic unexpected: $LOSER_OUT" ;; esac

echo "PASS: completion uses internal verifier authority and exact contract outputs"
echo "PASS: failed/extra/concurrent completion paths cannot publish illegal state"
