#!/usr/bin/env bash
# Regression for F04: hash-check owns artifact staleness only and must not erase
# an explicit route-back cause whose artifacts happen to be byte-unchanged.
set -uo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE_SH="$SKILL_DIR/scripts/auto-research-state.sh"
VERIFY_SH="$SKILL_DIR/scripts/auto-research-verify.sh"
SETUP_SH="$SKILL_DIR/scripts/setup-project-claudemd.sh"
for required in "$STATE_SH" "$VERIFY_SH" "$SETUP_SH"; do
  [ -f "$required" ] || { echo "FATAL: missing $required" >&2; exit 1; }
done

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-route-cause.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
PROJ="$TMP_ROOT/project"
REPORT="$TMP_ROOT/route.json"

fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$STATE_SH" init "$PROJ" >/dev/null
bash "$STATE_SH" set-mode "$PROJ" autonomous "route cause test" >/dev/null
mkdir -p "$PROJ/safety"
printf '%s\n' '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}' \
  > "$PROJ/safety/safety-status.json"
bash "$SETUP_SH" "$PROJ" >/dev/null
bash "$VERIFY_SH" 0 "$PROJ" >/dev/null || fail "Phase 0 baseline verification failed"
bash "$STATE_SH" complete "$PROJ" 0 "$PROJ/safety/safety-status.json" >/dev/null \
  || fail "Phase 0 baseline completion failed"

python3 - "$REPORT" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "verdict": "FAIL",
        "source_phase": "1",
        "route_back_phase": "0",
        "findings": [{
            "finding_id": "F04-route",
            "route_back_phase": "0",
            "status": "open",
        }],
    }, handle, indent=2, sort_keys=True)
PY
bash "$STATE_SH" route-back "$PROJ" "$REPORT" >/dev/null \
  || fail "valid backward route failed"

set +e
HASH_OUT="$(bash "$STATE_SH" hash-check "$PROJ" 2>&1)"
HASH_RC=$?
set -e
[ "$HASH_RC" -eq 1 ] || fail "hash-check erased route cause (rc=$HASH_RC): $HASH_OUT"
case "$HASH_OUT" in
  *"STALE_PHASES=0"*) ;;
  *) fail "hash-check did not retain routed Phase 0: $HASH_OUT" ;;
esac
NEXT_OUT="$(bash "$STATE_SH" next "$PROJ")"
case "$NEXT_OUT" in
  *"NEXT_PHASE=0"*"REASON=route_back"*"ROUTE_BACK_FROM_PHASE=1"*) ;;
  *) fail "next lost route-back provenance after hash-check: $NEXT_OUT" ;;
esac

# A fresh successful verification and authoritative recompletion discharges the
# route cause; hash-check itself cannot.
bash "$VERIFY_SH" 0 "$PROJ" >/dev/null || fail "routed Phase 0 re-verification failed"
bash "$STATE_SH" complete "$PROJ" 0 "$PROJ/safety/safety-status.json" >/dev/null \
  || fail "routed Phase 0 recompletion failed"
NEXT_AFTER="$(bash "$STATE_SH" next "$PROJ")"
case "$NEXT_AFTER" in
  *"NEXT_PHASE=1"*) ;;
  *) fail "recompletion did not discharge route cause: $NEXT_AFTER" ;;
esac
case "$NEXT_AFTER" in
  *"REASON=route_back"*) fail "route provenance remained after verified recompletion" ;;
  *) ;;
esac

echo "PASS: hash-check preserves explicit route-back provenance"
echo "PASS: verified recompletion, not hash-check, discharges the route cause"
