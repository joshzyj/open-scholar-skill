#!/usr/bin/env bash
# Regression for ordered completion: a valid-looking verify stamp must not let
# an operator complete a later phase while the authoritative next phase is 0.
set -uo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE_SH="$SKILL_DIR/scripts/auto-research-state.sh"
VERIFY_SH="$SKILL_DIR/scripts/auto-research-verify.sh"
SETUP_SH="$SKILL_DIR/scripts/setup-project-claudemd.sh"
CONTRACT="$SKILL_DIR/references/phase-contract.json"

for required in "$STATE_SH" "$VERIFY_SH" "$SETUP_SH" "$CONTRACT"; do
  [ -f "$required" ] || { echo "FATAL: missing $required" >&2; exit 1; }
done

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-order.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mint_stamp() {
  local proj="$1" phase="$2"
  mkdir -p "$proj/.auto-research/verify-stamps"
  python3 - "$CONTRACT" "$proj/.auto-research/verify-stamps/$phase.json" "$phase" <<'PY'
import hashlib, json, sys
contract, output, phase = sys.argv[1:]
digest = hashlib.sha256(open(contract, "rb").read()).hexdigest()
with open(output, "w", encoding="utf-8") as handle:
    json.dump({
        "phase_id": phase,
        "verdict": "PASS",
        "contract_sha256": digest,
        "artifact_hashes": {},
        "verified_at": "ordered-completion-regression",
    }, handle, indent=2, sort_keys=True)
PY
}

# Negative contract: Phase 17 cannot be committed when Phase 0 is next, even
# when the stamp has the current contract hash and valid schema fields.
OUT_OF_ORDER="$TMP_ROOT/out-of-order"
bash "$STATE_SH" init "$OUT_OF_ORDER" >/dev/null
bash "$STATE_SH" set-mode "$OUT_OF_ORDER" autonomous "ordered completion test" >/dev/null
mint_stamp "$OUT_OF_ORDER" 17
cp "$OUT_OF_ORDER/.auto-research/state.json" "$TMP_ROOT/state-before.json"

set +e
ORDER_OUT="$(bash "$STATE_SH" complete "$OUT_OF_ORDER" 17 2>&1)"
ORDER_RC=$?
set -e

[ "$ORDER_RC" -ne 0 ] \
  || fail "out-of-order Phase 17 completion returned rc=0: $ORDER_OUT"
[ "$ORDER_OUT" = "OUT_OF_ORDER_PHASE: requested Phase 17 but authoritative NEXT_PHASE=0" ] \
  || fail "unexpected refusal text: $ORDER_OUT"
cmp -s "$TMP_ROOT/state-before.json" "$OUT_OF_ORDER/.auto-research/state.json" \
  || fail "refused completion mutated state.json"
if grep -q '"17"' "$OUT_OF_ORDER/.auto-research/state.json"; then
  fail "refused completion recorded Phase 17"
fi

# Positive contract: a genuinely verified authoritative Phase 0 still commits
# and advances normally to Phase 1.
IN_ORDER="$TMP_ROOT/in-order"
bash "$STATE_SH" init "$IN_ORDER" >/dev/null
bash "$STATE_SH" set-mode "$IN_ORDER" autonomous "ordered completion positive" >/dev/null
mkdir -p "$IN_ORDER/safety"
printf '%s\n' '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}' \
  > "$IN_ORDER/safety/safety-status.json"
bash "$SETUP_SH" "$IN_ORDER" >/dev/null
bash "$VERIFY_SH" 0 "$IN_ORDER" >/dev/null \
  || fail "legitimate Phase 0 verification did not pass"
bash "$STATE_SH" complete "$IN_ORDER" 0 "$IN_ORDER/safety/safety-status.json" >/dev/null \
  || fail "legitimate authoritative Phase 0 completion was refused"
NEXT_OUT="$(bash "$STATE_SH" next "$IN_ORDER")"
case "$NEXT_OUT" in
  *"NEXT_PHASE=1"*) ;;
  *) fail "Phase 0 completion did not advance to Phase 1: $NEXT_OUT" ;;
esac

echo "PASS: ordered completion rejects Phase 17 at NEXT_PHASE=0 without mutation"
echo "PASS: verified authoritative Phase 0 completes and advances to Phase 1"
