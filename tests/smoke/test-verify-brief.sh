#!/usr/bin/env bash
# test-verify-brief.sh — locks the agent-side brief verification helper
# (scripts/gates/verify-brief.sh; real-project eval finding 15, 2026-08-22).
#
# WHY: the brief's strip directive mandates "verify each input's sha256
# before reading" but was honor-system — no helper existed. These tests pin
# the helper's DC-07 semantics: GREEN on intact inputs, RED STOP-and-report
# on any post-emission mutation, fail-closed on unreadable briefs, seam
# drift as WARN only.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VB="${REPO_ROOT}/scripts/gates/verify-brief.sh"
EAB="${REPO_ROOT}/scripts/gates/emit-agent-brief.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

[ -f "$VB" ] || { echo "  FAIL: helper not found at $VB"; echo "── Results: PASS=0 FAIL=1 ──"; exit 1; }

TMPROOT="$(mktemp -d -t vbrief-smoke.XXXXXX)"
trap 'rm -rf "$TMPROOT" 2>/dev/null' EXIT
P="$TMPROOT/proj"; mkdir -p "$P/design" "$P/logs"
printf 'blueprint v2 contents\n' > "$P/design/blueprint.md"
printf 'stats report\n' > "$P/logs/stats.md"

# set -u (NOT set -e): re-arming -e after set +e under `set -uo pipefail`
# silently ARMS errexit for the rest of the suite (T6-class landmine,
# system-fix 2026-08-23).
run() { set +e; OUT=$(bash "$VB" "$@" 2>&1); RC=$?; set -u; }

echo ""
echo "T1: GREEN on a freshly emitted brief with intact inputs"
B_OUT=$(bash "$EAB" "$P" 3.5 fixer --report-to "reviews/3.5-fixer.md" --inputs "design/blueprint.md:the design,logs/stats.md:the numbers" --return report-md --purpose "test" 2>/dev/null)
BRIEF=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
run "$P" "$BRIEF"
if [ "$RC" = 0 ] && grep -q "STATUS=GREEN" <<<"$OUT" && grep -q "INPUTS_BAD=0" <<<"$OUT"; then
  pass "T1 intact inputs verify GREEN"
else fail "T1 (rc=$RC): $OUT"; fi

echo ""
echo "T2: RED STOP-and-report when an input mutates after emission"
printf 'blueprint v3 — moved after brief\n' > "$P/design/blueprint.md"
run "$P" "$BRIEF"
if [ "$RC" = 1 ] && grep -q "MISMATCH: design/blueprint.md" <<<"$OUT" && grep -q "STOP and" <<<"$OUT" \
   && grep -q "OK: logs/stats.md" <<<"$OUT"; then
  pass "T2 post-emission mutation → RED naming only the moved file"
else fail "T2 (rc=$RC): $OUT"; fi

echo ""
echo "T3: RED when an input is deleted"
printf 'blueprint v2 contents\n' > "$P/design/blueprint.md"
mv "$P/logs/stats.md" "$P/logs/stats-gone.md"
run "$P" "$BRIEF"
if [ "$RC" = 1 ] && grep -q "MISSING: logs/stats.md" <<<"$OUT"; then
  pass "T3 deleted input → RED MISSING"
else fail "T3 (rc=$RC): $OUT"; fi
mv "$P/logs/stats-gone.md" "$P/logs/stats.md"

echo ""
echo "T4: fail closed on a brief that is not agent-brief/v1"
printf '{"schema":"other/v9"}\n' > "$P/briefs/not-a-brief.json"
run "$P" "briefs/not-a-brief.json"
if [ "$RC" = 2 ] && grep -q "not agent-brief/v1" <<<"$OUT"; then
  pass "T4 wrong schema → exit 2, verifies nothing"
else fail "T4 (rc=$RC): $OUT"; fi

echo ""
echo "T5: fail closed on a missing brief path"
run "$P" "briefs/does-not-exist.json"
if [ "$RC" = 2 ] && grep -q "fail closed" <<<"$OUT"; then
  pass "T5 missing brief → exit 2"
else fail "T5 (rc=$RC): $OUT"; fi

echo ""
echo "T6: seam-summary drift is WARN, not RED (inputs govern the verdict)"
mkdir -p "$P/seams"
printf '{"phase":"3","verdict":"PASS"}\n' > "$P/seams/3-summary.json"
B_OUT=$(bash "$EAB" "$P" 5.5 fixer --report-to "reviews/5.5-fixer.md" --inputs "design/blueprint.md:the design" --return report-md --purpose "seam test" 2>/dev/null)
BRIEF2=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
printf '{"phase":"3","verdict":"PASS","refreshed":true}\n' > "$P/seams/3-summary.json"
run "$P" "$BRIEF2"
if [ "$RC" = 0 ] && grep -q "WARN: seam summary" <<<"$OUT" && grep -q "STATUS=GREEN" <<<"$OUT"; then
  pass "T6 seam drift warns without failing intact inputs"
else fail "T6 (rc=$RC): $OUT"; fi

echo ""
echo "T7: relative PROJ, direct agent-side use — handoff 2026-08-25 P1-A"
mkdir -p "$TMPROOT/rel/output/p7/design"
printf 'bp\n' > "$TMPROOT/rel/output/p7/design/blueprint.md"
T7_OUT=$(cd "$TMPROOT/rel" && {
  B_OUT=$(bash "$EAB" "output/p7" 3.5 theory --report-to "reviews/3.5-theory.md" \
    --inputs "design/blueprint.md:d" --return findings-ndjson --purpose "t7" 2>&1)
  BRIEF=$(printf '%s\n' "$B_OUT" | grep '^BRIEF=' | cut -d= -f2)
  R1=$(bash "$VB" "output/p7" "$BRIEF" 2>&1); RC1=$?          # printed, PROJ-prefixed form
  R2=$(bash "$VB" "output/p7" "briefs/3.5-theory.json" 2>&1); RC2=$?  # bare form
  R3=$(bash "$VB" "output/p7" "briefs/nope.json" 2>&1); RC3=$?        # missing
  echo "RC1=$RC1 RC2=$RC2 RC3=$RC3"
  printf '%s\n' "$R1" | grep -c "STATUS=GREEN" | sed 's/^/G1=/'
  printf '%s\n' "$R2" | grep -c "STATUS=GREEN" | sed 's/^/G2=/'
  printf '%s\n' "$R3" | grep -c "output/p7/briefs/nope.json or briefs/nope.json" | sed 's/^/C3=/'
})
if grep -q "RC1=0" <<<"$T7_OUT" && grep -q "G1=1" <<<"$T7_OUT" \
   && grep -q "RC2=0" <<<"$T7_OUT" && grep -q "G2=1" <<<"$T7_OUT"; then
  pass "T7a both invocation forms GREEN under relative PROJ"
else fail "T7a: $T7_OUT"; fi
if grep -q "RC3=2" <<<"$T7_OUT" && grep -q "C3=1" <<<"$T7_OUT"; then
  pass "T7b missing brief fails closed naming both candidates"
else fail "T7b: $T7_OUT"; fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "── Results: PASS=$PASS FAIL=0 ──"; exit 0
else
  echo "── Results: PASS=$PASS FAIL=$FAIL ──"; exit 1
fi
