#!/usr/bin/env bash
# Regression for F01-F03/F07: Phase 0 safety evidence must be current,
# internally consistent, path-exact, and invalidating when re-imported.
set -uo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE_SH="$SKILL_DIR/scripts/auto-research-state.sh"
VERIFY_SH="$SKILL_DIR/scripts/auto-research-verify.sh"
SETUP_SH="$SKILL_DIR/scripts/setup-project-claudemd.sh"

for required in "$STATE_SH" "$VERIFY_SH" "$SETUP_SH"; do
  [ -f "$required" ] || { echo "FATAL: missing $required" >&2; exit 1; }
done

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-phase0.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

setup_project() {
  local proj="$1"
  bash "$STATE_SH" init "$proj" >/dev/null
  bash "$STATE_SH" set-mode "$proj" autonomous "Phase 0 safety regression" >/dev/null
  bash "$SETUP_SH" "$proj" >/dev/null
}

write_safety() {
  local proj="$1" payload="$2"
  mkdir -p "$proj/safety"
  printf '%s\n' "$payload" > "$proj/safety/safety-status.json"
}

# F01: standalone verification never mints completion authority. A failed
# re-verification may leave the post-commit audit receipt in place because
# transactional completion never consumes that receipt.
P1="$TMP_ROOT/stale-stamp"
setup_project "$P1"
write_safety "$P1" '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}'
bash "$VERIFY_SH" 0 "$P1" >/dev/null || fail "F01 baseline Phase 0 verification failed"
[ ! -e "$P1/.auto-research/verify-stamps/0.json" ] || fail "standalone verifier minted a receipt"
bash "$STATE_SH" complete "$P1" 0 >/dev/null || fail "F01 baseline completion failed"
[ -f "$P1/.auto-research/verify-stamps/0.json" ] || fail "completion did not mint audit receipt"
mkdir -p "$P1/data/raw"
printf 'id,value\n1,secret\n' > "$P1/data/raw/new.csv"
set +e
OUT="$(bash "$VERIFY_SH" 0 "$P1" 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "F01 changed inventory re-verification returned rc=0"
case "$OUT" in *"data-like files are present on disk"*) ;; *) fail "F01 failed for wrong reason: $OUT" ;; esac
python3 - "$P1/.auto-research/verify-stamps/0.json" <<'PY' || fail "receipt is not explicitly audit-only"
import json, sys
receipt = json.load(open(sys.argv[1]))
assert receipt["authority"] == "audit_only_not_completion_input"
PY

# F02: top-level PASS cannot override a HALTED per-file entry.
P2="$TMP_ROOT/contradictory"
setup_project "$P2"
mkdir -p "$P2/data/raw"
printf 'id\n1\n' > "$P2/data/raw/blocked.csv"
write_safety "$P2" '{"safety_status":"PASS","files_scanned":1,"no_data_declared":false,"high_risk_unresolved":0,"status_by_file":{"data/raw/blocked.csv":{"source_status":"HALTED","category":"halted"}}}'
set +e
OUT="$(bash "$VERIFY_SH" 0 "$P2" 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "F02 contradictory per-file HALTED evidence returned rc=0"
case "$OUT" in *"per-file safety entries are not terminally allowed"*"data/raw/blocked.csv"*) ;; *) fail "F02 failed for wrong reason: $OUT" ;; esac

# F03: a basename match cannot cover a different project-relative path.
P3="$TMP_ROOT/basename-collision"
setup_project "$P3"
mkdir -p "$P3/data/raw" "$P3/data/interim"
printf 'id\n1\n' > "$P3/data/raw/a.csv"
printf 'id\n2\n' > "$P3/data/interim/a.csv"
write_safety "$P3" '{"safety_status":"PASS","files_scanned":1,"no_data_declared":false,"high_risk_unresolved":0,"status_by_file":{"data/raw/a.csv":{"source_status":"CLEARED","category":"cleared"}}}'
set +e
OUT="$(bash "$VERIFY_SH" 0 "$P3" 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "F03 basename collision returned rc=0"
case "$OUT" in *"missing from status_by_file"*"data/interim/a.csv"*) ;; *) fail "F03 failed for wrong reason: $OUT" ;; esac

# F07: importing newly blocked evidence invalidates completed Phase 0 and its stamp.
P7="$TMP_ROOT/import-blocked"
setup_project "$P7"
write_safety "$P7" '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}'
bash "$VERIFY_SH" 0 "$P7" >/dev/null || fail "F07 baseline verify failed"
bash "$STATE_SH" complete "$P7" 0 "$P7/safety/safety-status.json" >/dev/null || fail "F07 baseline complete failed"
mkdir -p "$P7/.claude" "$P7/data/raw"
printf 'id\n1\n' > "$P7/data/raw/blocked.csv"
ABS_BLOCKED="$(cd "$P7/data/raw" && pwd -P)/blocked.csv"
printf '{"%s":"HALTED"}\n' "$ABS_BLOCKED" > "$P7/.claude/safety-status.json"
set +e
OUT="$(bash "$STATE_SH" import-init "$P7" 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "F07 blocked import returned rc=0"
case "$OUT" in *"SAFETY_STATUS=BLOCKED"*) ;; *) fail "F07 import lacked BLOCKED diagnostic: $OUT" ;; esac
python3 - "$P7/.auto-research/state.json" <<'PY' || fail "F07 blocked import did not invalidate Phase 0"
import json, sys
s = json.load(open(sys.argv[1]))
assert "0" in set(map(str, s.get("stale_phases", [])))
assert isinstance(s.get("safety_blocked"), dict)
assert s["safety_blocked"].get("status") == "BLOCKED"
PY
[ ! -e "$P7/.auto-research/verify-stamps/0.json" ] || fail "F07 blocked import retained Phase 0 stamp"
set +e
OUT="$(bash "$STATE_SH" next "$P7" 2>&1)"; RC=$?
set -e
[ "$RC" -eq 0 ] || fail "F07 next should route to blocked Phase 0 diagnostically: $OUT"
case "$OUT" in *"NEXT_PHASE=0"*"REASON=safety_blocked"*) ;; *) fail "F07 next did not route to blocked Phase 0: $OUT" ;; esac

# Exact identity also rejects aliases and stale extra receipt rows.
P_EXTRA="$TMP_ROOT/identity-extras"
setup_project "$P_EXTRA"
mkdir -p "$P_EXTRA/data/raw"
printf 'id\n1\n' > "$P_EXTRA/data/raw/a.csv"
write_safety "$P_EXTRA" '{"safety_status":"PASS","files_scanned":2,"no_data_declared":false,"high_risk_unresolved":0,"status_by_file":{"data/raw/a.csv":{"source_status":"CLEARED","category":"cleared"},"./data/raw/a.csv":{"source_status":"CLEARED","category":"cleared"}}}'
set +e
OUT="$(bash "$VERIFY_SH" 0 "$P_EXTRA" 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "duplicate normalized safety identities returned rc=0"
case "$OUT" in *"duplicate normalized identity data/raw/a.csv"*) ;; *) fail "duplicate identity failed for wrong reason: $OUT" ;; esac
write_safety "$P_EXTRA" '{"safety_status":"PASS","files_scanned":2,"no_data_declared":false,"high_risk_unresolved":0,"status_by_file":{"data/raw/a.csv":{"source_status":"CLEARED","category":"cleared"},"data/raw/gone.csv":{"source_status":"CLEARED","category":"cleared"}}}'
set +e
OUT="$(bash "$VERIFY_SH" 0 "$P_EXTRA" 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "stale extra safety record returned rc=0"
case "$OUT" in *"records absent from current inventory"*"data/raw/gone.csv"*) ;; *) fail "extra record failed for wrong reason: $OUT" ;; esac
P_EMPTY="$TMP_ROOT/empty-extra"
setup_project "$P_EMPTY"
write_safety "$P_EMPTY" '{"safety_status":"PASS","files_scanned":1,"no_data_declared":false,"high_risk_unresolved":0,"status_by_file":{"data/raw/gone.csv":{"source_status":"CLEARED","category":"cleared"}}}'
set +e
OUT="$(bash "$VERIFY_SH" 0 "$P_EMPTY" 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "stale receipt over empty inventory returned rc=0"
case "$OUT" in *"records absent from current inventory"*"data/raw/gone.csv"*) ;; *) fail "empty-inventory extra failed for wrong reason: $OUT" ;; esac

# Strict copy-only policy rejects a relative symlink that resolves outside.
P_LINK="$TMP_ROOT/symlink"
setup_project "$P_LINK"
mkdir -p "$P_LINK/data/raw"
printf 'id\n1\n' > "$TMP_ROOT/outside.csv"
ln -s "$TMP_ROOT/outside.csv" "$P_LINK/data/raw/link.csv"
write_safety "$P_LINK" '{"safety_status":"PASS","files_scanned":1,"no_data_declared":false,"high_risk_unresolved":0,"status_by_file":{"data/raw/link.csv":{"source_status":"CLEARED","category":"cleared"}}}'
set +e
OUT="$(bash "$VERIFY_SH" 0 "$P_LINK" 2>&1)"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "outside-project data symlink returned rc=0"
case "$OUT" in *"symlink"*|*"resolves through"*) ;; *) fail "symlink failed for wrong reason: $OUT" ;; esac

# Once Phase 0 is complete, every state-driving read/mutation must notice an
# inventory change even if the caller never explicitly reruns verification.
for COMMAND in next status hash-check complete; do
  PM="$TMP_ROOT/matrix-$COMMAND"
  setup_project "$PM"
  write_safety "$PM" '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}'
  bash "$VERIFY_SH" 0 "$PM" >/dev/null || fail "$COMMAND matrix baseline verify failed"
  bash "$STATE_SH" complete "$PM" 0 "$PM/safety/safety-status.json" >/dev/null || fail "$COMMAND matrix baseline complete failed"
  mkdir -p "$PM/data/raw"
  printf 'id\n1\n' > "$PM/data/raw/new.csv"
  set +e
  if [ "$COMMAND" = "complete" ]; then
    OUT="$(bash "$STATE_SH" complete "$PM" 1 2>&1)"; RC=$?
  else
    OUT="$(bash "$STATE_SH" "$COMMAND" "$PM" 2>&1)"; RC=$?
  fi
  set -e
  case "$COMMAND" in
    next)
      [ "$RC" -eq 0 ] || fail "next inventory refresh returned rc=$RC: $OUT"
      case "$OUT" in *"NEXT_PHASE=0"*"REASON=safety_inventory_changed"*) ;; *) fail "next missed inventory change: $OUT" ;; esac
      ;;
    status)
      [ "$RC" -eq 0 ] || fail "status inventory refresh returned rc=$RC: $OUT"
      case "$OUT" in *'"reason": "safety_inventory_changed"'*) ;; *) fail "status missed inventory change: $OUT" ;; esac
      ;;
    hash-check)
      [ "$RC" -eq 1 ] || fail "hash-check inventory refresh returned rc=$RC: $OUT"
      case "$OUT" in *"STALE_PHASES=0"*) ;; *) fail "hash-check missed inventory change: $OUT" ;; esac
      ;;
    complete)
      [ "$RC" -ne 0 ] || fail "complete ignored inventory change"
      case "$OUT" in *"SAFETY_INVENTORY_CHANGED"*) ;; *) fail "complete failed for wrong reason: $OUT" ;; esac
      ;;
  esac
  python3 - "$PM/.auto-research/state.json" <<'PY' || fail "$COMMAND did not persist safety invalidation"
import json, sys
s = json.load(open(sys.argv[1]))
assert "0" in set(map(str, s.get("stale_phases", [])))
assert s.get("safety_blocked", {}).get("reason") == "safety_inventory_changed"
PY
  [ ! -e "$PM/.auto-research/verify-stamps/0.json" ] || fail "$COMMAND retained stale Phase 0 stamp"
done

# Same-path byte changes are detected from local content digests without
# printing file contents. Exercise each state-driving path independently.
for COMMAND in next status hash-check complete; do
  PB="$TMP_ROOT/bytes-$COMMAND"
  setup_project "$PB"
  mkdir -p "$PB/data/raw" "$PB/.claude"
  printf 'id,value\n1,clean\n' > "$PB/data/raw/a.csv"
  ABS_DATA="$(cd "$PB/data/raw" && pwd -P)/a.csv"
  printf '{"%s":"CLEARED"}\n' "$ABS_DATA" > "$PB/.claude/safety-status.json"
  bash "$STATE_SH" import-init "$PB" >/dev/null || fail "$COMMAND byte baseline import failed"
  bash "$VERIFY_SH" 0 "$PB" >/dev/null || fail "$COMMAND byte baseline verify failed"
  bash "$STATE_SH" complete "$PB" 0 >/dev/null || fail "$COMMAND byte baseline complete failed"
  printf 'id,value\n1,changed\n' > "$PB/data/raw/a.csv"
  set +e
  if [ "$COMMAND" = "complete" ]; then
    OUT="$(bash "$STATE_SH" complete "$PB" 1 2>&1)"; RC=$?
  else
    OUT="$(bash "$STATE_SH" "$COMMAND" "$PB" 2>&1)"; RC=$?
  fi
  set -e
  case "$COMMAND" in
    next) case "$OUT" in *"NEXT_PHASE=0"*"REASON=safety_inventory_changed"*) ;; *) fail "next missed byte drift: $OUT" ;; esac ;;
    status) case "$OUT" in *'"reason": "safety_inventory_changed"'*) ;; *) fail "status missed byte drift: $OUT" ;; esac ;;
    hash-check) [ "$RC" -eq 1 ] && case "$OUT" in *"STALE_PHASES=0"*) ;; *) fail "hash-check missed byte drift: $OUT" ;; esac ;;
    complete) [ "$RC" -ne 0 ] && case "$OUT" in *"SAFETY_INVENTORY_CHANGED"*) ;; *) fail "complete missed byte drift: $OUT" ;; esac ;;
  esac
done

# Import prepares both publications before replacing either. A forced state
# temp-file failure leaves safety, state, and existing audit receipt untouched.
PA="$TMP_ROOT/atomic-import"
setup_project "$PA"
write_safety "$PA" '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}'
bash "$STATE_SH" complete "$PA" 0 >/dev/null || fail "atomic baseline complete failed"
cp "$PA/.auto-research/state.json" "$TMP_ROOT/atomic-state-before.json"
cp "$PA/safety/safety-status.json" "$TMP_ROOT/atomic-safety-before.json"
mkdir -p "$PA/.claude" "$PA/data/raw" "$PA/.auto-research/state.json.tmp"
printf 'id\n1\n' > "$PA/data/raw/blocked.csv"
ABS_BLOCKED="$(cd "$PA/data/raw" && pwd -P)/blocked.csv"
printf '{"%s":"HALTED"}\n' "$ABS_BLOCKED" > "$PA/.claude/safety-status.json"
set +e
bash "$STATE_SH" import-init "$PA" >"$TMP_ROOT/atomic.out" 2>&1; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "forced import publication failure returned rc=0"
cmp -s "$TMP_ROOT/atomic-state-before.json" "$PA/.auto-research/state.json" || fail "failed import changed state"
cmp -s "$TMP_ROOT/atomic-safety-before.json" "$PA/safety/safety-status.json" || fail "failed import changed safety receipt"
[ -f "$PA/.auto-research/verify-stamps/0.json" ] || fail "failed import deleted audit receipt"

echo "PASS: standalone Phase 0 verification creates no reusable authority"
echo "PASS: Phase 0 derives safety from exact per-file evidence"
echo "PASS: blocked safety import invalidates completed Phase 0"
echo "PASS: all state-driving paths detect post-completion inventory drift"
echo "PASS: content digests, symlink policy, and import rollback fail closed"
