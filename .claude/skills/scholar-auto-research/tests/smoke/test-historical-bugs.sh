#!/usr/bin/env bash
# Verification probe for scholar-auto-research bugs B1, B2, B6 (audit 2026-05-02).
#
# Each B-prefixed test exercises a specific failure path:
#
#   B1  Phase 12 (Manuscript Blueprint) is a dependency island. It emits
#       manuscript/manuscript-blueprint.json which is required_input for
#       Phases 13, 14, 18, etc.  But Phase 12 does NOT appear in any
#       downstream hash_dependencies array.  Result: editing the blueprint
#       after Phase 12 completes leaves Phase 13+ falsely "fresh".
#
#   B2  route-back has no retry cap.  retry_counts[finding_id] increments
#       every call; RETRY_MAX is printed but never compared.  An infinite
#       fail/route-back loop is possible because nothing escalates.
#
#   B6  contract_sha256 is recorded at init() and at each complete(), but
#       never compared.  If the operator edits phase-contract.json between
#       init and a later phase complete, the drift is silently encoded into
#       the state record.
#
# Pre-fix: each test exits 1 (RED). Post-fix: each exits 0 (GREEN).
# After fix this file lives in tests/smoke/ so run-all.sh picks it up.

set -uo pipefail

TMPDIR_BASE="$(mktemp -d -t auto-research-bugs.XXXXXX)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# B6 deliberately mutates the contract.  It must therefore exercise a private
# copy of the skill, never shared production bytes that another test may read.
SOURCE_SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SKILL_DIR="$TMPDIR_BASE/skill-under-test"
mkdir -p "$SKILL_DIR"
cp -R "$SOURCE_SKILL_DIR/." "$SKILL_DIR/"
STATE_SH="${SKILL_DIR}/scripts/auto-research-state.sh"
CONTRACT="${SKILL_DIR}/references/phase-contract.json"
SEED_PHASE="${SKILL_DIR}/tests/helpers/seed-completed-phase.py"

for f in "$STATE_SH" "$CONTRACT"; do
  [ -f "$f" ] || { echo "FATAL: missing $f"; exit 1; }
done

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    detail: $2"; }

# Helper: complete phases 0..N with placeholder file artifacts.
seed_phases_through() {
  local proj="$1"
  local last="$2"
  local pid
  mkdir -p "$proj/artifacts"
  bash "$STATE_SH" init "$proj" >/dev/null
  bash "$STATE_SH" set-mode "$proj" autonomous "smoke autonomous" >/dev/null
  for pid in $(seq 0 "$last"); do
    printf 'phase %s artifact\n' "$pid" > "$proj/artifacts/phase-$pid.txt"
    python3 "$SEED_PHASE" "$CONTRACT" "$proj" "$pid" "$proj/artifacts/phase-$pid.txt"
  done
}

# ── B1: Phase 12 dependency island ──────────────────────────────────
echo ""
echo "=== B1: Phase 12 dependency island ==="
B1_PROJ="$TMPDIR_BASE/b1-project"
seed_phases_through "$B1_PROJ" 13   # complete through Phase 13

# Now mutate the Phase 12 artifact (simulate operator edit to blueprint).
# Phase 12's artifact in this fixture is artifacts/phase-12.txt; mutating it
# changes its sha256, so hash-check should mark Phase 12 stale and propagate
# to 13.
echo "MUTATED $(date)" >> "$B1_PROJ/artifacts/phase-12.txt"

B1_HC="$(bash "$STATE_SH" hash-check "$B1_PROJ" 2>&1 || true)"
B1_STALE="$(printf '%s\n' "$B1_HC" | grep -E '^STALE_PHASES=' | head -1 | sed 's/^STALE_PHASES=//')"

# Expectation: STALE_PHASES contains 12 AND 13 (because 13 reads the
# blueprint).  Pre-fix: 12 only.  Post-fix: 12,13.
case ",${B1_STALE}," in
  *,12,*) ;;
  *) fail "B1: hash-check did not mark Phase 12 stale after artifact mutation" "got: $B1_STALE" ;;
esac
case ",${B1_STALE}," in
  *,13,*) pass "B1: Phase 13 staleness propagates from Phase 12" ;;
  *) fail "B1: Phase 13 NOT marked stale even though it consumes blueprint" \
          "STALE_PHASES=$B1_STALE — Phase 13 hash_dependencies missing 12" ;;
esac

# ── B2: route-back retry cap ────────────────────────────────────────
echo ""
echo "=== B2: route-back retry cap ==="
B2_PROJ="$TMPDIR_BASE/b2-project"
seed_phases_through "$B2_PROJ" 14   # complete through Phase 14

# Build a structured FAIL report from Phase 14 routing back to Phase 13.
mkdir -p "$B2_PROJ/verify"
cat > "$B2_PROJ/verify/manuscript-verification.json" <<'JSON'
{
  "verdict": "FAIL",
  "source_phase": "14",
  "route_back_phase": "13",
  "findings": [
    {
      "finding_id": "P14-LOOP-001",
      "status": "open",
      "route_back_phase": "13",
      "category": "drafting",
      "summary": "intentional retry-loop fixture finding"
    }
  ]
}
JSON

B2_FAIL_AT_3=0
for attempt in 1 2 3; do
  B2_OUT="$(bash "$STATE_SH" route-back "$B2_PROJ" "$B2_PROJ/verify/manuscript-verification.json" 2>&1)"
  B2_RC=$?
  if [ "$attempt" -eq 3 ]; then
    if [ "$B2_RC" -ne 0 ]; then
      case "$B2_OUT" in
        *ESCALATE*) B2_FAIL_AT_3=1 ;;
      esac
    fi
    break
  fi
  if [ "$B2_RC" -ne 0 ]; then
    fail "B2: route-back attempt $attempt should succeed (only attempt 3 caps)" "rc=$B2_RC out=$B2_OUT"
    break
  fi
  # Mark target stale-completed again so route-back can re-fire. This is a
  # test-only state fixture; completion authority is covered separately.
  python3 "$SEED_PHASE" "$CONTRACT" "$B2_PROJ" 13 "$B2_PROJ/artifacts/phase-13.txt"
  python3 "$SEED_PHASE" "$CONTRACT" "$B2_PROJ" 14 "$B2_PROJ/artifacts/phase-14.txt"
done

if [ "$B2_FAIL_AT_3" -eq 1 ]; then
  pass "B2: route-back escalates with non-zero exit at retry cap"
else
  fail "B2: route-back attempt 3 did NOT escalate" \
       "expected non-zero exit + ESCALATE keyword; route-back has no cap-3 enforcement"
fi

# ── B6: contract_sha256 drift detection ─────────────────────────────
echo ""
echo "=== B6: contract_sha256 drift detection ==="
B6_PROJ="$TMPDIR_BASE/b6-project"
seed_phases_through "$B6_PROJ" 0   # init + complete Phase 0

# Mutate the contract: copy current contract to a temp, append a comment-
# free whitespace change that flips the file sha but preserves valid JSON.
B6_CONTRACT_BACKUP="$TMPDIR_BASE/contract-backup.json"
cp "$CONTRACT" "$B6_CONTRACT_BACKUP"

# Append a trailing newline (idempotent if already present? we test the sha
# differs by adding multiple newlines plus a bogus key under schema_version
# — we restore from backup at end of test).
python3 - "$CONTRACT" <<'PY'
import json
import sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text())
data["__drift_test_marker__"] = "test-drift-2026-05-02"
p.write_text(json.dumps(data, indent=2) + "\n")
PY

# Now try to complete Phase 1; expect the state machine to detect drift
# and refuse the mutation.
mkdir -p "$B6_PROJ/idea"
echo '{"verdict":"PASS"}' > "$B6_PROJ/idea/research-question.json"

B6_OUT="$(bash "$STATE_SH" complete "$B6_PROJ" 1 "$B6_PROJ/idea/research-question.json" 2>&1)"
B6_RC=$?

# Restore the contract immediately so other tests aren't disturbed.
cp "$B6_CONTRACT_BACKUP" "$CONTRACT"

if [ "$B6_RC" -ne 0 ]; then
  case "$B6_OUT" in
    *CONTRACT_DRIFT*|*contract_sha256*)
      pass "B6: complete refuses to mutate state when contract drifted"
      ;;
    *)
      fail "B6: complete failed with non-zero rc but message lacks drift signal" \
           "rc=$B6_RC out=$B6_OUT"
      ;;
  esac
else
  fail "B6: complete accepted mutation despite contract drift" \
       "rc=0 out=$B6_OUT — contract_sha256 is recorded but never compared"
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "=== auto-research-bugs probe summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
