#!/usr/bin/env bash
# Regression for F12: the route-back retry cap must latch persistently and may
# be cleared only by an explicit, audited operator action.
set -uo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE_SH="$SKILL_DIR/scripts/auto-research-state.sh"
[ -f "$STATE_SH" ] || { echo "FATAL: missing $STATE_SH" >&2; exit 1; }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-halt.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
PROJ="$TMP_ROOT/project"
REPORT="$TMP_ROOT/fail.json"

fail() { echo "FAIL: $*" >&2; exit 1; }

python3 - "$REPORT" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "verdict": "FAIL",
        "source_phase": "0",
        "route_back_phase": "0",
        "findings": [{
            "finding_id": "F12-loop",
            "route_back_phase": "0",
            "status": "open",
        }],
    }, handle, indent=2, sort_keys=True)
PY

bash "$STATE_SH" init "$PROJ" >/dev/null
bash "$STATE_SH" set-mode "$PROJ" autonomous "persistent halt test" >/dev/null

for attempt in 1 2; do
  bash "$STATE_SH" route-back "$PROJ" "$REPORT" >/dev/null \
    || fail "route-back attempt $attempt failed before cap"
done
set +e
THIRD_OUT="$(bash "$STATE_SH" route-back "$PROJ" "$REPORT" 2>&1)"
THIRD_RC=$?
set -e
[ "$THIRD_RC" -eq 2 ] || fail "third route-back did not escalate with rc=2: $THIRD_OUT"
case "$THIRD_OUT" in
  *"ESCALATE_FOR_FINDINGS=F12-loop"*) ;;
  *) fail "third route-back did not identify escalated finding: $THIRD_OUT" ;;
esac

STATUS_OUT="$(bash "$STATE_SH" status "$PROJ" 2>&1)"
printf '%s\n' "$STATUS_OUT" | grep -q '"halted": true' \
  || fail "status does not expose durable halted=true: $STATUS_OUT"
printf '%s\n' "$STATUS_OUT" | grep -q '"F12-loop"' \
  || fail "status does not expose the halting finding: $STATUS_OUT"

cp "$PROJ/.auto-research/state.json" "$TMP_ROOT/halted-before.json"
for blocked in next hash-check; do
  set +e
  BLOCK_OUT="$(bash "$STATE_SH" "$blocked" "$PROJ" 2>&1)"
  BLOCK_RC=$?
  set -e
  [ "$BLOCK_RC" -ne 0 ] || fail "$blocked resumed a halted pipeline"
  case "$BLOCK_OUT" in
    *"PIPELINE_HALTED: findings=F12-loop"*) ;;
    *) fail "$blocked returned wrong halt diagnostic: $BLOCK_OUT" ;;
  esac
  cmp -s "$TMP_ROOT/halted-before.json" "$PROJ/.auto-research/state.json" \
    || fail "$blocked mutated halted state"
done

set +e
COMPLETE_OUT="$(bash "$STATE_SH" complete "$PROJ" 0 2>&1)"
COMPLETE_RC=$?
set -e
[ "$COMPLETE_RC" -ne 0 ] || fail "complete resumed a halted pipeline"
case "$COMPLETE_OUT" in
  *"PIPELINE_HALTED: findings=F12-loop"*) ;;
  *) fail "complete returned wrong halt diagnostic: $COMPLETE_OUT" ;;
esac
cmp -s "$TMP_ROOT/halted-before.json" "$PROJ/.auto-research/state.json" \
  || fail "blocked complete mutated halted state"

# Re-initialization and safety import are also mutations; neither may bypass a
# latched halt in a later process invocation.
set +e
INIT_OUT="$(bash "$STATE_SH" init "$PROJ" 2>&1)"
INIT_RC=$?
set -e
[ "$INIT_RC" -ne 0 ] || fail "init overwrote a halted pipeline"
case "$INIT_OUT" in
  *"PIPELINE_HALTED: findings=F12-loop"*) ;;
  *) fail "init returned wrong halt diagnostic: $INIT_OUT" ;;
esac
cmp -s "$TMP_ROOT/halted-before.json" "$PROJ/.auto-research/state.json" \
  || fail "blocked init mutated halted state"

mkdir -p "$PROJ/.claude"
printf '%s\n' '{"data/raw/new.csv":"CLEARED"}' > "$PROJ/.claude/safety-status.json"
set +e
IMPORT_OUT="$(bash "$STATE_SH" import-init "$PROJ" 2>&1)"
IMPORT_RC=$?
set -e
[ "$IMPORT_RC" -ne 0 ] || fail "import-init mutated a halted pipeline"
case "$IMPORT_OUT" in
  *"PIPELINE_HALTED: findings=F12-loop"*) ;;
  *) fail "import-init returned wrong halt diagnostic: $IMPORT_OUT" ;;
esac
cmp -s "$TMP_ROOT/halted-before.json" "$PROJ/.auto-research/state.json" \
  || fail "blocked import-init mutated halted state"
[ ! -e "$PROJ/safety/safety-status.json" ] \
  || fail "blocked import-init published new safety evidence"

set +e
WRONG_OUT="$(bash "$STATE_SH" clear-halt "$PROJ" --finding wrong --reason reviewed --operator tester 2>&1)"
WRONG_RC=$?
set -e
[ "$WRONG_RC" -ne 0 ] || fail "wrong finding cleared halt"
case "$WRONG_OUT" in
  *"HALT_FINDING_MISMATCH"*) ;;
  *) fail "wrong-finding clear returned wrong diagnostic: $WRONG_OUT" ;;
esac
cmp -s "$TMP_ROOT/halted-before.json" "$PROJ/.auto-research/state.json" \
  || fail "invalid clear-halt mutated state"

CLEAR_OUT="$(bash "$STATE_SH" clear-halt "$PROJ" --finding F12-loop --reason 'manual correction reviewed' --operator tester 2>&1)"
CLEAR_RC=$?
[ "$CLEAR_RC" -eq 0 ] || fail "valid clear-halt failed rc=$CLEAR_RC: $CLEAR_OUT"
case "$CLEAR_OUT" in
  *"HALT_CLEARED_FOR=F12-loop"*) ;;
  *) fail "valid clear-halt returned wrong output: $CLEAR_OUT" ;;
esac

STATUS_AFTER="$(bash "$STATE_SH" status "$PROJ")"
printf '%s\n' "$STATUS_AFTER" | grep -q '"halted": false' \
  || fail "clear-halt did not release latch: $STATUS_AFTER"
printf '%s\n' "$STATUS_AFTER" | grep -q '"retry_count_at_clear": 3' \
  || fail "clear-halt did not retain retry-count audit evidence: $STATUS_AFTER"
printf '%s\n' "$STATUS_AFTER" | grep -q '"stale_phases": \[' \
  || fail "clear-halt erased stale state: $STATUS_AFTER"
NEXT_AFTER="$(bash "$STATE_SH" next "$PROJ")"
case "$NEXT_AFTER" in
  *"NEXT_PHASE=0"*) ;;
  *) fail "cleared pipeline did not resume at stale Phase 0: $NEXT_AFTER" ;;
esac

# One report cannot accelerate the retry counter by repeating a finding id.
DUP_PROJ="$TMP_ROOT/duplicate-project"
DUP_REPORT="$TMP_ROOT/duplicate.json"
bash "$STATE_SH" init "$DUP_PROJ" >/dev/null
bash "$STATE_SH" set-mode "$DUP_PROJ" autonomous "duplicate finding test" >/dev/null
python3 - "$DUP_REPORT" <<'PY'
import json, sys
finding = {"finding_id": "DUP", "route_back_phase": "0", "status": "open"}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "verdict": "FAIL",
        "source_phase": "0",
        "route_back_phase": "0",
        "findings": [finding, dict(finding)],
    }, handle, indent=2, sort_keys=True)
PY
cp "$DUP_PROJ/.auto-research/state.json" "$TMP_ROOT/duplicate-before.json"
set +e
DUP_OUT="$(bash "$STATE_SH" route-back "$DUP_PROJ" "$DUP_REPORT" 2>&1)"
DUP_RC=$?
set -e
[ "$DUP_RC" -ne 0 ] || fail "duplicate finding ids were accepted"
[ "$DUP_OUT" = "DUPLICATE_ROUTE_BACK_FINDING_ID: DUP" ] \
  || fail "duplicate finding returned wrong diagnostic: $DUP_OUT"
cmp -s "$TMP_ROOT/duplicate-before.json" "$DUP_PROJ/.auto-research/state.json" \
  || fail "duplicate-finding rejection mutated state"

echo "PASS: third repeated finding latches halt across next/hash-check/complete"
echo "PASS: audited matching clear releases latch without erasing stale/retry evidence"
echo "PASS: duplicate finding ids are rejected before retry counting"
