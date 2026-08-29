#!/usr/bin/env bash
# Regression for route-back directionality: a correction route cannot point to
# a later phase than the verifier source phase; same-phase retry remains legal.
set -uo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE_SH="$SKILL_DIR/scripts/auto-research-state.sh"
[ -f "$STATE_SH" ] || { echo "FATAL: missing $STATE_SH" >&2; exit 1; }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-route-direction.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

write_report() {
  local path="$1" source="$2" target="$3" finding="$4"
  python3 - "$path" "$source" "$target" "$finding" <<'PY'
import json, sys
path, source, target, finding = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({
        "verdict": "FAIL",
        "source_phase": source,
        "route_back_phase": target,
        "findings": [{
            "finding_id": finding,
            "route_back_phase": target,
            "status": "open",
        }],
    }, handle, indent=2, sort_keys=True)
PY
}

# A forward transition presented as a route-back must fail before state changes.
FORWARD="$TMP_ROOT/forward"
bash "$STATE_SH" init "$FORWARD" >/dev/null
bash "$STATE_SH" set-mode "$FORWARD" autonomous "route direction negative" >/dev/null
write_report "$TMP_ROOT/forward.json" 5 8 F14-forward
cp "$FORWARD/.auto-research/state.json" "$TMP_ROOT/forward-before.json"
set +e
FORWARD_OUT="$(bash "$STATE_SH" route-back "$FORWARD" "$TMP_ROOT/forward.json" 2>&1)"
FORWARD_RC=$?
set -e
[ "$FORWARD_RC" -ne 0 ] || fail "forward route-back returned rc=0: $FORWARD_OUT"
[ "$FORWARD_OUT" = "INVALID_ROUTE_BACK_DIRECTION: source Phase 5 cannot route forward to Phase 8" ] \
  || fail "unexpected forward-route diagnostic: $FORWARD_OUT"
cmp -s "$TMP_ROOT/forward-before.json" "$FORWARD/.auto-research/state.json" \
  || fail "rejected forward route-back mutated state.json"

# A same-phase retry is a valid corrective route.
SAME="$TMP_ROOT/same"
bash "$STATE_SH" init "$SAME" >/dev/null
bash "$STATE_SH" set-mode "$SAME" autonomous "route direction positive" >/dev/null
write_report "$TMP_ROOT/same.json" 5 5 F14-same
SAME_OUT="$(bash "$STATE_SH" route-back "$SAME" "$TMP_ROOT/same.json" 2>&1)"
SAME_RC=$?
[ "$SAME_RC" -eq 0 ] || fail "same-phase route-back failed rc=$SAME_RC: $SAME_OUT"
case "$SAME_OUT" in
  *"ROUTE_BACK_PHASE=5"*) ;;
  *) fail "same-phase route-back did not publish Phase 5 target: $SAME_OUT" ;;
esac

echo "PASS: forward Phase 5 to Phase 8 route-back is rejected without mutation"
echo "PASS: same-phase Phase 5 route-back remains legal"
