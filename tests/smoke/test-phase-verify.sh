#!/usr/bin/env bash
# Smoke tests for scripts/gates/phase-verify.sh
#
# Covers:
#   - H4 phase-entry regex correctness (Phase 0 vs Phase 0-PRE, 7 vs 7b)
#   - Phase -1 passes for handshake-created projects (artifact contract)
#   - Phase with no entry in PROJECT STATE fails closed
#   - Phase with entry + required artifacts passes
#
# The most important thing this test catches is the H4 regex boundary
# bug that let `Phase 0` match `Phase 0-PRE` (and `Phase 7` match `7b`)
# before the J4 fix.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PV="${REPO_ROOT}/scripts/gates/phase-verify.sh"

if [ ! -f "$PV" ]; then
  echo "FATAL: phase-verify.sh not found at $PV"
  exit 1
fi

TMPDIR_BASE="$(mktemp -d -t phase-verify-smoke.XXXXXX)"
trap 'rm -rf "$TMPDIR_BASE" 2>/dev/null' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Helper: make a minimal project with a given list of phase headings,
# plus whatever artifacts are needed for the phase-specific checks.
make_proj() {
  local proj_dir="$1"
  shift
  mkdir -p "$proj_dir/logs" "$proj_dir/drafts" "$proj_dir/tables" \
           "$proj_dir/figures" "$proj_dir/scripts" "$proj_dir/reports" \
           "$proj_dir/replication-package/code"
  {
    echo "# PROJECT STATE"
    echo ""
    echo "- Project Slug: test"
    echo "- Target Journal: ASR"
    for phase_hdr in "$@"; do
      printf '\n## %s\n- Status: COMPLETE\n' "$phase_hdr"
    done
  } > "$proj_dir/logs/project-state.md"
}

# Helper: run phase-verify, return exit code (no output)
pv_exit() {
  local phase="$1" proj="$2"
  set +e
  bash "$PV" "$phase" "$proj" >/dev/null 2>&1
  local rc=$?
  set +e
  echo "$rc"
}

echo "=== phase-verify.sh Smoke Tests ==="
echo ""

# ─── Test 1: Phase 0 does NOT match Phase 0-PRE ────────────────────────
echo "Test 1: Phase 0 regex does not match Phase 0-PRE"
T1="$TMPDIR_BASE/t1"
make_proj "$T1" "Phase 0-PRE — Brainstorm"
RC=$(pv_exit 0 "$T1")
if [ "$RC" != "0" ]; then
  pass "phase-verify 0 fails when only Phase 0-PRE is present"
else
  fail "phase-verify 0 PASSED with only 0-PRE — regex too loose"
fi

# ─── Test 2: Phase 0-PRE matches Phase 0-PRE ───────────────────────────
echo ""
echo "Test 2: Phase 0-PRE regex matches its own entry"
T2="$TMPDIR_BASE/t2"
make_proj "$T2" "Phase 0-PRE — Brainstorm"
# Phase 0-PRE's case arm checks for a brainstorm report; provide one
echo "# brainstorm" > "$T2/scholar-brainstorm-test-2026-04-09.md"
RC=$(pv_exit 0-PRE "$T2")
if [ "$RC" = "0" ]; then
  pass "phase-verify 0-PRE passes its own entry + brainstorm artifact"
else
  fail "phase-verify 0-PRE failed (exit $RC) — H4 regex or phase arm broken"
fi

# ─── Test 3: Phase 7 does NOT match Phase 7b ───────────────────────────
echo ""
echo "Test 3: Phase 7 regex does not match Phase 7b"
T3="$TMPDIR_BASE/t3"
make_proj "$T3" "Phase 7b — Verify"
# Phase 7's case arm needs a draft with 5000+ words
awk 'BEGIN { for(i=0;i<100;i++) { for(j=0;j<51;j++) printf "word "; print "" } }' > "$T3/drafts/draft.md"
RC=$(pv_exit 7 "$T3")
if [ "$RC" != "0" ]; then
  pass "phase-verify 7 fails when only Phase 7b is present"
else
  fail "phase-verify 7 PASSED with only 7b — regex too loose"
fi

# ─── Test 4: Phase 7 matches Phase 7 entry with draft ──────────────────
echo ""
echo "Test 4: Phase 7 passes when Phase 7 entry + draft present"
T4="$TMPDIR_BASE/t4"
make_proj "$T4" "Phase 7 — Drafting"
awk 'BEGIN { for(i=0;i<100;i++) { for(j=0;j<51;j++) printf "word "; print "" } }' > "$T4/drafts/draft.md"
RC=$(pv_exit 7 "$T4")
if [ "$RC" = "0" ]; then
  pass "phase-verify 7 passes with Phase 7 entry + valid draft"
else
  fail "phase-verify 7 failed (exit $RC) — regression"
fi

# ─── Test 5: Phase -1 passes for handshake-created project ────────────
echo ""
echo "Test 5: Phase -1 passes when handshake wrote scholar-safety-log.md"
T5="$TMPDIR_BASE/t5"
mkdir -p "$T5/logs"
cat > "$T5/logs/project-state.md" <<'STATE'
# PROJECT STATE
- Project Slug: test
- Initialized via: scholar-init (detected at Phase -1)

## Phase -1 — Safety Gate
- Status: COMPLETE (inherited)
STATE
# H3 writes scholar-safety-log.md — simulate it
{
  echo "# Safety Gate — Phase -1 (inherited)"
  echo ""
  echo "- Date: 2026-04-09"
  echo "- Files: 3 CLEARED"
} > "$T5/logs/scholar-safety-log.md"
RC=$(pv_exit -1 "$T5")
if [ "$RC" = "0" ]; then
  pass "Phase -1 passes for handshake project (H3+H4 contract)"
else
  fail "Phase -1 FAILED for handshake project (exit $RC) — contract broken"
fi

# ─── Test 6: Phase -1 fails when state has no Phase -1 entry ──────────
echo ""
echo "Test 6: Phase -1 fails when PROJECT STATE lacks the phase entry"
T6="$TMPDIR_BASE/t6"
mkdir -p "$T6/logs"
# State file with NO Phase -1 section
echo "# PROJECT STATE" > "$T6/logs/project-state.md"
echo "- Project Slug: test" >> "$T6/logs/project-state.md"
# Still provide a safety log (to isolate the phase-entry check)
echo "# Safety" > "$T6/logs/scholar-safety-log.md"
RC=$(pv_exit -1 "$T6")
if [ "$RC" != "0" ]; then
  pass "Phase -1 fails when state lacks Phase -1 entry"
else
  fail "Phase -1 passed without a Phase -1 entry — H4 check missing"
fi

# ─── Summary ────────────────────────────────────────────────────────────
echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo ">>> FAILED"
  exit 1
else
  echo ">>> PASSED"
  exit 0
fi
