#!/usr/bin/env bash
# Smoke tests for scholar-auto-research run-mode and human-in-the-loop gates.
set -uo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE_SH="${SKILL_DIR}/scripts/auto-research-state.sh"
CONTRACT="${SKILL_DIR}/references/phase-contract.json"
SEED_PHASE="${SKILL_DIR}/tests/helpers/seed-completed-phase.py"
SETUP_SH="${SKILL_DIR}/scripts/setup-project-claudemd.sh"
HARNESS="${SKILL_DIR}/tests/helpers/harness.sh"
CASE_RESULT="${SKILL_DIR}/tests/helpers/case_result.py"
MANIFEST="${SKILL_DIR}/tests/coverage-manifest.json"
source "$HARNESS"

if [ ! -f "$STATE_SH" ]; then
  echo "FATAL: missing $STATE_SH"
  exit 1
fi

SCHOLAR_KEEP_FIXTURE="${SCHOLAR_KEEP_FIXTURE:-0}"
SCHOLAR_HARNESS_SUITE_MODE="${SCHOLAR_HARNESS_SUITE_MODE:-fast-only}"
SCHOLAR_HARNESS_SUITE_ORDER="${SCHOLAR_HARNESS_SUITE_ORDER:-normal}"
export SCHOLAR_KEEP_FIXTURE SCHOLAR_HARNESS_SUITE_MODE SCHOLAR_HARNESS_SUITE_ORDER
harness_make_temp_root TMPDIR_BASE "auto-research-hitl"
SCHOLAR_HARNESS_SOURCE_ROOT="${SCHOLAR_HARNESS_SOURCE_ROOT:-$SKILL_DIR}"
SCHOLAR_HARNESS_MANIFEST="${SCHOLAR_HARNESS_MANIFEST:-$MANIFEST}"
SCHOLAR_HARNESS_RESULTS_DIR="${SCHOLAR_HARNESS_RESULTS_DIR:-$TMPDIR_BASE/harness-results}"
SCHOLAR_HARNESS_RUN_ID="${SCHOLAR_HARNESS_RUN_ID:-hitl-$$}"
SCHOLAR_HARNESS_RUN_NONCE="${SCHOLAR_HARNESS_RUN_NONCE:-$(python3 -c 'import secrets; print(secrets.token_hex(32))')}"
SCHOLAR_HARNESS_MANIFEST_SHA256="${SCHOLAR_HARNESS_MANIFEST_SHA256:-$(python3 "$CASE_RESULT" digest-file "$SCHOLAR_HARNESS_MANIFEST")}"
SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="${SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256:-$(python3 "$CASE_RESULT" source-digest "$SCHOLAR_HARNESS_SOURCE_ROOT")}"
export SCHOLAR_HARNESS_SOURCE_ROOT SCHOLAR_HARNESS_MANIFEST SCHOLAR_HARNESS_RESULTS_DIR
export SCHOLAR_HARNESS_RUN_ID SCHOLAR_HARNESS_RUN_NONCE SCHOLAR_HARNESS_MANIFEST_SHA256
export SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256
harness_init "$SKILL_DIR/tests/smoke/test-human-in-loop.sh" "human-in-loop"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    detail: $2"; }

make_artifact() {
  local proj="$1" phase="$2"
  mkdir -p "$proj/artifacts"
  printf 'phase %s artifact\n' "$phase" > "$proj/artifacts/phase-$phase.txt"
}

seed_complete() {
  python3 "$SEED_PHASE" "$CONTRACT" "$1" "$2" "$1/artifacts/phase-$2.txt"
}

prepare_phase0() {
  local proj="$1" mode="$2" note="$3"
  bash "$STATE_SH" init "$proj" >/dev/null
  bash "$STATE_SH" set-mode "$proj" "$mode" "$note" >/dev/null
  mkdir -p "$proj/safety"
  printf '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$proj/safety/safety-status.json"
  bash "$SETUP_SH" "$proj" >/dev/null
}

prepare_phase1_artifacts() {
  local proj="$1"
  mkdir -p "$proj/idea"
  cp "$SKILL_DIR/tests/fixtures/publication-quality-seed/idea/research-question.json" "$proj/idea/research-question.json"
  cp "$SKILL_DIR/tests/fixtures/publication-quality-seed/idea/journal-fit.json" "$proj/idea/journal-fit.json"
  cat > "$proj/idea/candidate-rqs.json" <<'JSON'
{
  "verdict": "PASS",
  "engine": "scholar-idea",
  "input_mode": "idea",
  "candidates": [
    {"rq_id":"RQ1","question":"Among low-income United States households with adolescent children, what is the association between parental job loss and adolescent educational expectations?","x":"parental job loss","y":"adolescent educational expectations","mechanism":"income shock and household stress reduce perceived educational feasibility","confounders":["prior household income","parental education","baseline academic performance"],"scope":{"population":"low-income households with adolescent children","place":"United States","time":"contemporary household panel period","unit":"adolescent-year"},"claim_strength":"associational","recommended_dataset":"Panel Study of Income Dynamics Child Development Supplement","novelty_risk":"medium","data_feasible":true,"fatal_flaw":false},
    {"rq_id":"RQ2","question":"Among United States adolescents, how are parental work-hour instability and school engagement associated across the school year?","x":"parental work-hour instability","y":"school engagement","mechanism":"schedule volatility reduces parental monitoring and routine stability","confounders":["industry","prior engagement","household income"],"scope":{"population":"United States adolescents","place":"United States","time":"school-year panel period","unit":"student-year"},"claim_strength":"associational","recommended_dataset":"NLSY97 linked youth survey","novelty_risk":"medium","data_feasible":true,"fatal_flaw":false},
    {"rq_id":"RQ3","question":"Among families experiencing income shocks, how do parental expectations mediate adolescents' expectations for college completion?","x":"family income shock","y":"adolescent college completion expectations","mechanism":"parental expectations transmit perceived feasibility to adolescents","confounders":["wealth","parental education","school context"],"scope":{"population":"families with adolescents","place":"United States","time":"longitudinal survey period","unit":"family-year"},"claim_strength":"associational","recommended_dataset":"Add Health","novelty_risk":"high","data_feasible":true,"fatal_flaw":false}
  ]
}
JSON
  cat > "$proj/idea/rq-evaluation-panel.json" <<'JSON'
{"verdict":"PASS","selected_rq_id":"RQ1","fatal_flaw_selected":false,"ready_for_selection":true,"reviewers":[{"role":"theorist","verdict":"PASS","rank_order":["RQ1","RQ3","RQ2"]},{"role":"methodologist","verdict":"PASS","rank_order":["RQ1","RQ2","RQ3"]},{"role":"domain_expert","verdict":"PASS","rank_order":["RQ1","RQ3","RQ2"]},{"role":"journal_editor","verdict":"PASS","rank_order":["RQ1","RQ2","RQ3"]},{"role":"devils_advocate","verdict":"PASS","viability":"VIABLE","rank_order":["RQ1","RQ2","RQ3"]}],"consensus":{"top_pick":"RQ1","panel_consensus":"strong"}}
JSON
  cat > "$proj/idea/rq-selection-rationale.md" <<'MD'
# RQ Selection Rationale

RQ1 was selected because it has the clearest connection between family economic instability, adolescent expectations, and a family-process mechanism. The theorist and domain expert ranked it first because it links family stress and status-attainment perspectives without requiring an implausible causal claim. The methodologist ranked it first because household panel data can observe parental job loss, adolescent expectations, and relevant baseline covariates. The journal editor judged the question a strong fit for Journal of Marriage and Family. The devil's advocate did not identify a fatal flaw, but flagged novelty as the main risk, so the question uses cautious associational language.
MD
  cat > "$proj/idea/research-question.md" <<'MD'
# Research Question

Selected question: Among low-income United States households with adolescent children, what is the association between parental job loss and adolescent educational expectations?

The question uses parental job loss as the focal exposure and adolescent educational expectations as the outcome. It is framed for the Journal of Marriage and Family as an empirical article using cautious associational language, a family stress mechanism, and household panel data.
MD
}

echo "=== auto-research human-in-loop smoke tests ==="

# T1: run mode starts unset and blocks completion.
echo ""
echo "T1: unset run mode blocks phase completion"
T1="$TMPDIR_BASE/t1"
bash "$STATE_SH" init "$T1" >/dev/null
NEXT="$(bash "$STATE_SH" next "$T1")"
make_artifact "$T1" 0
OUT="$(bash "$STATE_SH" complete "$T1" 0 "$T1/artifacts/phase-0.txt" 2>&1)"
RC=$?
if printf '%s\n' "$NEXT" | grep -q 'NEXT_PHASE=MODE_SELECTION' \
   && [ "$RC" -ne 0 ] \
   && printf '%s\n' "$OUT" | grep -q 'RUN_MODE_REQUIRED'; then
  pass "unset mode returns MODE_SELECTION and refuses complete"
else
  fail "unset mode did not enforce mode selection" "next=$NEXT rc=$RC out=$OUT"
fi

# T2: autonomous mode preserves old forward behavior.
echo ""
echo "T2: autonomous mode advances without approval gates"
T2="$TMPDIR_BASE/t2"
bash "$STATE_SH" init "$T2" >/dev/null
bash "$STATE_SH" set-mode "$T2" autonomous "test autonomous" >/dev/null
NEXT0="$(bash "$STATE_SH" next "$T2")"
make_artifact "$T2" 0
seed_complete "$T2" 0
NEXT1="$(bash "$STATE_SH" next "$T2")"
if printf '%s\n' "$NEXT0" | grep -q 'NEXT_PHASE=0' \
   && printf '%s\n' "$NEXT1" | grep -q 'NEXT_PHASE=1' \
   && ! printf '%s\n' "$NEXT1" | grep -q 'APPROVAL_REQUIRED=1'; then
  pass "autonomous mode returns next phase directly"
else
  fail "autonomous mode did not preserve direct advancement" "next0=$NEXT0 next1=$NEXT1"
fi

# T3: human-in-loop requires production completion and approval after each phase.
echo ""
echo "T3: human-in-loop blocks next phase until approve"
T3="$TMPDIR_BASE/t3"
prepare_phase0 "$T3" human-in-loop "test hitl"
prepare_phase1_artifacts "$T3"

# CASE_ID: l4.hitl.accept.complete-phase0
if expect_pass l4.hitl.accept.complete-phase0 "$T3" -- \
  bash "$STATE_SH" complete "$T3" 0; then
  pass "production Phase 0 completion creates the HITL gate"
else
  fail "production Phase 0 completion did not create the HITL gate"
fi

# CASE_ID: l4.hitl.reject.complete-phase1-before-approval
if expect_reject l4.hitl.reject.complete-phase1-before-approval "$T3" -- \
  bash "$STATE_SH" complete "$T3" 1; then
  pass "Phase 1 completion is refused before approval"
else
  fail "Phase 1 completion bypassed or misreported the approval gate"
fi

# CASE_ID: l4.hitl.accept.revise-phase1
if expect_pass l4.hitl.accept.revise-phase1 "$T3" -- \
  bash "$STATE_SH" decision "$T3" 1 revise "needs changes"; then
  pass "revise preserves the pending Phase 1 transition"
else
  fail "revise did not preserve the pending Phase 1 transition"
fi

# CASE_ID: l4.hitl.accept.approve-phase1
if expect_pass l4.hitl.accept.approve-phase1 "$T3" -- \
  bash "$STATE_SH" decision "$T3" 1 approve "approved"; then
  pass "approve clears the pending Phase 1 transition"
else
  fail "approve did not clear the pending Phase 1 transition"
fi

# CASE_ID: l4.hitl.accept.complete-phase1
if expect_pass l4.hitl.accept.complete-phase1 "$T3" -- \
  bash "$STATE_SH" complete "$T3" 1; then
  pass "production Phase 1 completion creates the next HITL gate"
else
  fail "production Phase 1 completion did not create the next HITL gate"
fi

# T4: switch-autonomous clears a pending HITL gate.
echo ""
echo "T4: switch-autonomous clears pending gate"
bash "$STATE_SH" decision "$T3" 2 switch-autonomous "continue automatically" >/dev/null
NEXT_SWITCH="$(bash "$STATE_SH" next "$T3")"
if printf '%s\n' "$NEXT_SWITCH" | grep -q 'NEXT_PHASE=2' \
   && ! printf '%s\n' "$NEXT_SWITCH" | grep -q 'APPROVAL_REQUIRED=1'; then
  pass "switch-autonomous clears pending transition"
else
  fail "switch-autonomous did not clear pending transition" "$NEXT_SWITCH"
fi

# T5: route-back in HITL creates a pending transition to the route-back target.
echo ""
echo "T5: route-back is approval-gated in human-in-loop mode"
T5="$TMPDIR_BASE/t5"
bash "$STATE_SH" init "$T5" >/dev/null
bash "$STATE_SH" set-mode "$T5" autonomous "seed" >/dev/null
for pid in 0 1 2 3; do
  make_artifact "$T5" "$pid"
  seed_complete "$T5" "$pid"
done
bash "$STATE_SH" set-mode "$T5" human-in-loop "review reruns" >/dev/null
mkdir -p "$T5/verify"
cat > "$T5/verify/fail.json" <<'JSON'
{
  "verdict": "FAIL",
  "source_phase": "3",
  "route_back_phase": "1",
  "findings": [
    {"finding_id": "HITL-RB-1", "status": "open", "route_back_phase": "1"}
  ]
}
JSON
bash "$STATE_SH" route-back "$T5" "$T5/verify/fail.json" >/dev/null
RB_NEXT="$(bash "$STATE_SH" next "$T5")"
if printf '%s\n' "$RB_NEXT" | grep -q 'NEXT_PHASE=1' \
   && printf '%s\n' "$RB_NEXT" | grep -q 'REASON=route_back' \
   && printf '%s\n' "$RB_NEXT" | grep -q 'APPROVAL_REQUIRED=1'; then
  pass "route-back target requires approval in human-in-loop mode"
else
  fail "route-back did not create HITL approval gate" "$RB_NEXT"
fi

# T6: hash staleness in HITL creates a pending transition to the stale phase.
echo ""
echo "T6: hash-check stale phase is approval-gated in human-in-loop mode"
T6="$TMPDIR_BASE/t6"
bash "$STATE_SH" init "$T6" >/dev/null
bash "$STATE_SH" set-mode "$T6" autonomous "seed" >/dev/null
make_artifact "$T6" 0
seed_complete "$T6" 0
bash "$STATE_SH" set-mode "$T6" human-in-loop "review stale reruns" >/dev/null
printf 'mutated\n' >> "$T6/artifacts/phase-0.txt"
bash "$STATE_SH" hash-check "$T6" >/dev/null 2>&1
STALE_NEXT="$(bash "$STATE_SH" next "$T6")"
if printf '%s\n' "$STALE_NEXT" | grep -q 'NEXT_PHASE=0' \
   && printf '%s\n' "$STALE_NEXT" | grep -q 'APPROVAL_REQUIRED=1'; then
  pass "stale phase requires approval in human-in-loop mode"
else
  fail "hash-check stale phase did not create HITL approval gate" "$STALE_NEXT"
fi

# T7: the fixture seeder must never mint HITL completion authority.
echo ""
echo "T7: fixture seeder refuses human-in-loop state"
T7="$TMPDIR_BASE/t7"
bash "$STATE_SH" init "$T7" >/dev/null
bash "$STATE_SH" set-mode "$T7" human-in-loop "seeder refusal" >/dev/null
make_artifact "$T7" 0
T7_BEFORE="$(python3 "$CASE_RESULT" digest-file "$T7/.auto-research/state.json")"
T7_OUT="$(python3 "$SEED_PHASE" "$CONTRACT" "$T7" 0 "$T7/artifacts/phase-0.txt" 2>&1)"
T7_RC=$?
T7_AFTER="$(python3 "$CASE_RESULT" digest-file "$T7/.auto-research/state.json")"
if [ "$T7_RC" -ne 0 ] \
   && [ "$T7_OUT" = "fixture seeder refuses human_in_loop mode; use production completion authority" ] \
   && [ "$T7_BEFORE" = "$T7_AFTER" ]; then
  pass "fixture seeder refuses HITL without changing state"
else
  fail "fixture seeder did not fail closed in HITL" "rc=$T7_RC out=$T7_OUT before=$T7_BEFORE after=$T7_AFTER"
fi

# T8: copied-skill mutation family authenticates the completion-site kill.
echo ""
echo "T8: pending-transition completion mutant is killed"
MUT_SKILL="$TMPDIR_BASE/mutant-skill"
cp -R "$SKILL_DIR" "$MUT_SKILL"
MUT_STATE="$MUT_SKILL/scripts/auto-research-state.sh"
MUT_SETUP="$MUT_SKILL/scripts/setup-project-claudemd.sh"

prepare_copied_phase0() {
  local proj="$1" mode="$2" note="$3"
  bash "$MUT_STATE" init "$proj" >/dev/null
  bash "$MUT_STATE" set-mode "$proj" "$mode" "$note" >/dev/null
  mkdir -p "$proj/safety"
  printf '{"safety_status":"PASS","files_scanned":0,"no_data_declared":true,"high_risk_unresolved":0,"status_by_file":{}}\n' > "$proj/safety/safety-status.json"
  bash "$MUT_SETUP" "$proj" >/dev/null
}

MUT_PRISTINE="$(python3 "$CASE_RESULT" digest-file "$MUT_STATE")"
bash -n "$MUT_STATE"
MUT_POS="$TMPDIR_BASE/mutation-pristine-positive"
MUT_NEG="$TMPDIR_BASE/mutation-pristine-negative"
MUT_VALID="$TMPDIR_BASE/mutation-valid-control"
MUT_KILL="$TMPDIR_BASE/mutation-kill"
prepare_copied_phase0 "$MUT_POS" autonomous "pristine positive"
prepare_copied_phase0 "$MUT_NEG" human-in-loop "pristine negative"
bash "$MUT_STATE" complete "$MUT_NEG" 0 >/dev/null
prepare_copied_phase0 "$MUT_VALID" autonomous "mutant valid"
prepare_copied_phase0 "$MUT_KILL" human-in-loop "mutant kill"

# CASE_ID: f20.mutation.remove_complete_pending_transition.pristine_positive
if SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUT_PRISTINE" \
  expect_pass f20.mutation.remove_complete_pending_transition.pristine_positive "$MUT_POS" -- \
    bash "$MUT_STATE" complete "$MUT_POS" 0; then
  pass "pristine copied completion accepts the positive control"
else
  fail "pristine copied completion rejected the positive control"
fi

# CASE_ID: f20.mutation.remove_complete_pending_transition.pristine_negative
if SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUT_PRISTINE" \
  expect_reject f20.mutation.remove_complete_pending_transition.pristine_negative "$MUT_NEG" -- \
    bash "$MUT_STATE" complete "$MUT_NEG" 1; then
  pass "pristine copied completion rejects preapproval Phase 1"
else
  fail "pristine copied completion did not reject preapproval Phase 1"
fi

python3 - "$MUT_STATE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = "    make_pending_transition(state, pid, compute_next_info(state))"
replacement = '    state["pending_transition"] = None'
if source.count(needle) != 1:
    raise SystemExit(f"F20_L4_MUTATION_SOURCE_CARDINALITY: expected 1, observed {source.count(needle)}")
path.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
PY
bash -n "$MUT_STATE"
MUT_AFTER="$(python3 "$CASE_RESULT" digest-file "$MUT_STATE")"
if [ "$MUT_AFTER" = "$MUT_PRISTINE" ]; then
  fail "completion mutant did not change copied state bytes"
fi
MUTATION_BINDING="operator=remove_complete_pending_transition,target_matches=1,changed=scripts/auto-research-state.sh,before=$MUT_PRISTINE,after=$MUT_AFTER"

# CASE_ID: f20.mutation.remove_complete_pending_transition.mutant_valid
if SCHOLAR_HARNESS_MUTATION_VERDICT="valid_control:$MUTATION_BINDING" \
  expect_pass f20.mutation.remove_complete_pending_transition.mutant_valid "$MUT_VALID" -- \
    bash "$MUT_STATE" complete "$MUT_VALID" 0; then
  pass "mutant remains valid under autonomous control"
else
  fail "mutant failed its autonomous validity control"
fi

mutation_kill_oracle() {
  local state_script="$1" project="$2" rc
  if bash "$state_script" complete "$project" 0 >/dev/null; then
    rc=0
  else
    rc=$?
  fi
  [ "$rc" -eq 0 ] || return 96
  if python3 - "$project/.auto-research/state.json" <<'PY'
import json
import sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
raise SystemExit(0 if state.get("pending_transition") is None else 1)
PY
  then
    echo "F20_L4_MUTANT_ACCEPTED: remove_complete_pending_transition copied state accepted Phase 0 completion without pending transition" >&2
    return 97
  fi
  return 0
}

# CASE_ID: f20.mutation.remove_complete_pending_transition.mutant_kill
if SCHOLAR_HARNESS_MUTATION_VERDICT="killed:$MUTATION_BINDING" \
  expect_reject f20.mutation.remove_complete_pending_transition.mutant_kill "$MUT_KILL" -- \
    mutation_kill_oracle "$MUT_STATE" "$MUT_KILL"; then
  pass "HITL completion test kills the pending-transition mutant"
else
  fail "HITL completion test did not kill the pending-transition mutant"
fi

if HARNESS_COUNT="$(harness_validate_results)" && [ "$HARNESS_COUNT" = "HARNESS_RESULT_RECORDS=9" ]; then
  pass "all nine authenticated HITL and mutation receipts joined"
else
  fail "authenticated HITL/mutation result join failed" "$HARNESS_COUNT"
fi

echo ""
echo "=== auto-research human-in-loop summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
