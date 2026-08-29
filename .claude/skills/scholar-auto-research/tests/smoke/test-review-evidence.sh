#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VERIFY="$SKILL_DIR/scripts/auto-research-verify.sh"
STATE="$SKILL_DIR/scripts/auto-research-state.sh"
CONTRACT="$SKILL_DIR/references/phase-contract.json"
SEED="$SKILL_DIR/tests/helpers/seed-completed-phase.py"
FIXTURE="$SKILL_DIR/tests/fixtures/phase5-seed"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-review-evidence.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

PROJECT="$TMP_ROOT/project"
cp -pR "$FIXTURE" "$PROJECT"

# BEFORE (F09): this fixture contains complete-looking reports and distinct
# locally asserted task_invocation_id values, but no state-registered review
# session or completion events. The production Phase 6 verifier used to PASS.
set +e
bash "$VERIFY" 6 "$PROJECT" \
  >"$TMP_ROOT/phase6.out" 2>&1
RC=$?
set -e

[ "$RC" -ne 0 ] \
  || fail "Phase 6 accepted hand-authored reviewer provenance without process-recorded evidence"
grep -F "FAIL: Phase 6 review evidence is missing or invalid" "$TMP_ROOT/phase6.out" >/dev/null \
  || fail "Phase 6 rejected the adversarial fixture for the wrong reason"
grep -F "missing registered review session" "$TMP_ROOT/phase6.out" >/dev/null \
  || fail "Phase 6 diagnostic did not identify the missing registered session"

echo "PASS: Phase 6 rejects hand-authored reviewer provenance without process-recorded evidence"

VALID="$TMP_ROOT/valid"
cp -pR "$FIXTURE" "$VALID"
bash "$STATE" init "$VALID" >/dev/null
bash "$STATE" set-mode "$VALID" autonomous "F09 positive fixture" >/dev/null
for phase in 0 1 2 3 4 5; do
  python3 "$SEED" "$CONTRACT" "$VALID" "$phase" "$VALID/analysis/analysis-plan.md"
done

BEGIN_OUT="$(bash "$STATE" review-begin "$VALID" 6 initial_panel generic-host)"
SESSION_ID="$(printf '%s\n' "$BEGIN_OUT" | sed -n 's/^REVIEW_SESSION_ID=//p')"
[ -n "$SESSION_ID" ] || fail "review-begin returned no session ID"
BEGIN_JSON="$(printf '%s\n' "$BEGIN_OUT" | sed -n 's/^REVIEW_SESSION_JSON=//p')"
python3 - "$BEGIN_JSON" <<'PY'
import json, sys
envelope = json.loads(sys.argv[1])
assert envelope["reviewed_inputs"], "launch envelope omitted reviewed inputs"
assert all(path and len(digest) == 64
           for path, digest in envelope["reviewed_inputs"].items())
contract = envelope["completion_contract"]
assert contract["command"] == "auto-research-state.sh review-complete"
assert contract["required_driver_status"] == "succeeded"
assert contract["failure_action"] == "auto-research-state.sh review-abort"
assert set(contract["identity_availability"]) == {"reported", "unavailable"}
assert envelope["launches"]
assert all({"role", "dispatch_id", "report_path", "trace_path"} <= set(item)
           for item in envelope["launches"])
assert all(item["reviewed_inputs"] == envelope["reviewed_inputs"]
           for item in envelope["launches"])
assert all("--driver-status" in item["completion_argv_template"]
           and "succeeded" in item["completion_argv_template"]
           for item in envelope["launches"])
PY

python3 - "$VALID" "$SESSION_ID" <<'PY'
import json
import pathlib
import shutil
import sys

project = pathlib.Path(sys.argv[1])
session_id = sys.argv[2]
session_path = project / "review-evidence" / "phase-06" / session_id / "session.json"
session = json.loads(session_path.read_text())
for index, reservation in enumerate(session["reservations"], 1):
    role = reservation["role"]
    source = project / "review" / "agents" / f"{role}.md"
    report = project / reservation["report_path"]
    trace = project / reservation["trace_path"]
    report.parent.mkdir(parents=True, exist_ok=True)
    trace.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, report)
    with trace.open("w", encoding="utf-8") as handle:
        json.dump({
            "step": f"phase6-{role}",
            "reasoning": "independently inspect the assigned pre-execution scope",
            "action": f"review Phase 6 as {role}",
            "observation": f"role-specific review {index} completed",
            "status": "ok",
        }, handle)
        handle.write("\n")
PY

python3 - "$VALID" "$SESSION_ID" "$STATE" <<'PY'
import json
import os
import pathlib
import subprocess
import sys
import time

project = pathlib.Path(sys.argv[1])
session_id = sys.argv[2]
state_tool = sys.argv[3]
session = json.loads((project / "review-evidence" / "phase-06" / session_id / "session.json").read_text())
for index, reservation in enumerate(session["reservations"], 1):
    subprocess.run([
        "bash", state_tool, "review-complete", str(project), "6", session_id,
        reservation["role"], "--driver-status", "succeeded",
        "--host-task-id", f"agent-{index}",
        "--model-unavailable", "generic host does not expose model identity",
    ], check=True, stdout=subprocess.DEVNULL)

summary_path = project / "review" / "pre-execution-review.json"
summary = json.loads(summary_path.read_text())
by_role = {item["role"]: item for item in session["reservations"]}
for reviewer in summary["reviewers"]:
    reservation = by_role[reviewer["role"]]
    reviewer["report_path"] = reservation["report_path"]
    reviewer["task_invocation_id"] = reservation["dispatch_id"]
summary["review_evidence"] = {
    "profile": "normal",
    "attempt_epoch": 0,
    "rounds": {
        "initial_panel": {
            "session_id": session_id,
            "achieved_assurance": "process_recorded",
        },
        "fix_rereview": {"status": "not_applicable"},
    },
}
summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
stamp = time.time()
os.utime(summary_path, (stamp, stamp))
os.utime(project / "review" / "pre-execution-fix-log.json", (stamp + 1, stamp + 1))
os.utime(project / "review" / "pre-execution-rereview.json", (stamp + 2, stamp + 2))
PY

bash "$VERIFY" 6 "$VALID" >"$TMP_ROOT/valid.out" 2>&1 \
  || fail "valid generic-host process-recorded evidence did not pass: $(cat "$TMP_ROOT/valid.out")"
grep -F '"review_evidence"' "$TMP_ROOT/valid.out" >/dev/null \
  || fail "verification descriptor omitted review evidence"

LATE_ABORT="$TMP_ROOT/late-abort"
cp -pR "$VALID" "$LATE_ABORT"
bash "$STATE" complete "$LATE_ABORT" 6 >/dev/null
cp "$LATE_ABORT/.auto-research/state.json" "$TMP_ROOT/late-abort-before.json"
set +e
bash "$STATE" review-abort "$LATE_ABORT" 6 "$SESSION_ID" --reason "too late" \
  >"$TMP_ROOT/late-abort.out" 2>&1
LATE_ABORT_RC=$?
set -e
[ "$LATE_ABORT_RC" -ne 0 ] || fail "review-abort mutated already completed Phase 6 evidence"
grep -F "OUT_OF_ORDER_REVIEW_ABORT: requested Phase 6 but NEXT_PHASE=7" \
  "$TMP_ROOT/late-abort.out" >/dev/null || fail "late review-abort failed for the wrong reason"
cmp -s "$TMP_ROOT/late-abort-before.json" "$LATE_ABORT/.auto-research/state.json" \
  || fail "refused late review-abort mutated completed state"

FORGED_COMPLETION="$TMP_ROOT/forged-completion"
cp -pR "$VALID" "$FORGED_COMPLETION"
python3 - "$FORGED_COMPLETION/.auto-research/state.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path, encoding="utf-8"))
for index, event in enumerate(state["review_evidence_history"]):
    if event.get("event") == "review_role_completed":
        del state["review_evidence_history"][index]
        break
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
set +e
bash "$VERIFY" 6 "$FORGED_COMPLETION" >"$TMP_ROOT/forged.out" 2>&1
FORGED_RC=$?
set -e
[ "$FORGED_RC" -ne 0 ] || fail "registered session with an unregistered completion passed"
grep -F "missing registered role completion" "$TMP_ROOT/forged.out" >/dev/null \
  || fail "unregistered completion failed for the wrong reason"

echo "PASS: generic-host process-recorded evidence passes with opaque task IDs"
echo "PASS: role completion files without matching state events are rejected"
echo "PASS: launch envelope binds reviewed inputs and successful-completion contract"

UNREGISTERED_PERFECT="$TMP_ROOT/unregistered-perfect"
cp -pR "$VALID" "$UNREGISTERED_PERFECT"
python3 - "$UNREGISTERED_PERFECT/.auto-research/state.json" "$SESSION_ID" <<'PY'
import json, sys
path, session_id = sys.argv[1:]
state = json.load(open(path, encoding="utf-8"))
state["review_evidence_history"] = [
    event for event in state["review_evidence_history"]
    if not (event.get("event") == "review_session_registered"
            and event.get("session_id") == session_id)
]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
set +e
bash "$VERIFY" 6 "$UNREGISTERED_PERFECT" >"$TMP_ROOT/unregistered-perfect.out" 2>&1
UNREGISTERED_PERFECT_RC=$?
set -e
[ "$UNREGISTERED_PERFECT_RC" -ne 0 ] || fail "perfect session bundle without registration passed"
grep -F "missing registered review session" "$TMP_ROOT/unregistered-perfect.out" >/dev/null \
  || fail "perfect unregistered session failed for the wrong reason"

MISSING_BUNDLE="$TMP_ROOT/missing-bundle"
cp -pR "$VALID" "$MISSING_BUNDLE"
rm "$MISSING_BUNDLE/review-evidence/phase-06/$SESSION_ID/completions/correctness.json"
set +e
bash "$VERIFY" 6 "$MISSING_BUNDLE" >"$TMP_ROOT/missing-bundle.out" 2>&1
MISSING_BUNDLE_RC=$?
set -e
[ "$MISSING_BUNDLE_RC" -ne 0 ] || fail "missing completion bundle passed"
grep -F "completion missing" "$TMP_ROOT/missing-bundle.out" >/dev/null \
  || fail "missing completion bundle failed for the wrong reason"

MALFORMED_BUNDLE="$TMP_ROOT/malformed-bundle"
cp -pR "$VALID" "$MALFORMED_BUNDLE"
printf '{not-json}\n' >"$MALFORMED_BUNDLE/review-evidence/phase-06/$SESSION_ID/completions/correctness.json"
set +e
bash "$VERIFY" 6 "$MALFORMED_BUNDLE" >"$TMP_ROOT/malformed-bundle.out" 2>&1
MALFORMED_BUNDLE_RC=$?
set -e
[ "$MALFORMED_BUNDLE_RC" -ne 0 ] || fail "malformed completion bundle passed"
grep -F "completion is not valid JSON" "$TMP_ROOT/malformed-bundle.out" >/dev/null \
  || fail "malformed completion bundle failed for the wrong reason"

MISSING_REPORT="$TMP_ROOT/missing-report"
cp -pR "$VALID" "$MISSING_REPORT"
python3 - "$MISSING_REPORT" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
summary = json.loads((project / "review/pre-execution-review.json").read_text())
(project / summary["reviewers"][0]["report_path"]).unlink()
PY
set +e
bash "$VERIFY" 6 "$MISSING_REPORT" >"$TMP_ROOT/missing-report.out" 2>&1
MISSING_REPORT_RC=$?
set -e
[ "$MISSING_REPORT_RC" -ne 0 ] || fail "missing review report passed"
grep -F "review report missing" "$TMP_ROOT/missing-report.out" >/dev/null \
  || fail "missing report failed for the wrong reason"

REPORT_DRIFT="$TMP_ROOT/report-drift"
cp -pR "$VALID" "$REPORT_DRIFT"
python3 - "$REPORT_DRIFT" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
summary = json.loads((project / "review" / "pre-execution-review.json").read_text())
path = project / summary["reviewers"][0]["report_path"]
with path.open("a", encoding="utf-8") as handle:
    handle.write("\npost-completion mutation\n")
PY
set +e
bash "$VERIFY" 6 "$REPORT_DRIFT" >"$TMP_ROOT/report-drift.out" 2>&1
REPORT_DRIFT_RC=$?
set -e
[ "$REPORT_DRIFT_RC" -ne 0 ] || fail "mutated completed report passed"
grep -F "report digest mismatch" "$TMP_ROOT/report-drift.out" >/dev/null \
  || fail "mutated report failed for the wrong reason"

TRACE_DRIFT="$TMP_ROOT/trace-drift"
cp -pR "$VALID" "$TRACE_DRIFT"
python3 - "$TRACE_DRIFT" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
summary = json.loads((project / "review/pre-execution-review.json").read_text())
session_id = summary["review_evidence"]["rounds"]["initial_panel"]["session_id"]
session = json.loads((project / "review-evidence/phase-06" / session_id / "session.json").read_text())
path = project / session["reservations"][0]["trace_path"]
with path.open("a", encoding="utf-8") as handle:
    handle.write('{"step":"mutated","action":"after complete","status":"ok"}\n')
PY
set +e
bash "$VERIFY" 6 "$TRACE_DRIFT" >"$TMP_ROOT/trace-drift.out" 2>&1
TRACE_DRIFT_RC=$?
set -e
[ "$TRACE_DRIFT_RC" -ne 0 ] || fail "mutated completed trace passed"
grep -F "trace digest mismatch" "$TMP_ROOT/trace-drift.out" >/dev/null \
  || fail "mutated trace failed for the wrong reason"

INPUT_DRIFT="$TMP_ROOT/input-drift"
cp -pR "$VALID" "$INPUT_DRIFT"
printf '\ninput drift\n' >>"$INPUT_DRIFT/analysis/analysis-plan.md"
set +e
bash "$VERIFY" 6 "$INPUT_DRIFT" >"$TMP_ROOT/input-drift.out" 2>&1
INPUT_DRIFT_RC=$?
set -e
[ "$INPUT_DRIFT_RC" -ne 0 ] || fail "mutated reviewed input passed"
grep -F "reviewed input membership or digest changed" "$TMP_ROOT/input-drift.out" >/dev/null \
  || fail "mutated reviewed input failed for the wrong reason"

SEMANTIC_ROLE_MISMATCH="$TMP_ROOT/semantic-role-mismatch"
cp -pR "$VALID" "$SEMANTIC_ROLE_MISMATCH"
python3 - "$SEMANTIC_ROLE_MISMATCH/review/pre-execution-review.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
document = json.loads(path.read_text())
document["reviewers"][0]["role"] = "invented-role"
path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
PY
set +e
bash "$VERIFY" 6 "$SEMANTIC_ROLE_MISMATCH" >"$TMP_ROOT/semantic-role-mismatch.out" 2>&1
SEMANTIC_ROLE_MISMATCH_RC=$?
set -e
[ "$SEMANTIC_ROLE_MISMATCH_RC" -ne 0 ] || fail "semantic role mismatch passed"
grep -F "semantic reviewer roles do not match completed evidence roles" \
  "$TMP_ROOT/semantic-role-mismatch.out" >/dev/null \
  || fail "semantic role mismatch failed for the wrong reason"

SEMANTIC_PATH_MISMATCH="$TMP_ROOT/semantic-path-mismatch"
cp -pR "$VALID" "$SEMANTIC_PATH_MISMATCH"
python3 - "$SEMANTIC_PATH_MISMATCH/review/pre-execution-review.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
document = json.loads(path.read_text())
document["reviewers"][0]["report_path"] = document["reviewers"][1]["report_path"]
path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
PY
set +e
bash "$VERIFY" 6 "$SEMANTIC_PATH_MISMATCH" >"$TMP_ROOT/semantic-path-mismatch.out" 2>&1
SEMANTIC_PATH_MISMATCH_RC=$?
set -e
[ "$SEMANTIC_PATH_MISMATCH_RC" -ne 0 ] || fail "semantic report path mismatch passed"
grep -F "semantic report_path is not evidence-bound" "$TMP_ROOT/semantic-path-mismatch.out" >/dev/null \
  || fail "semantic report path mismatch failed for the wrong reason"

TRACE_PATH_MISMATCH="$TMP_ROOT/trace-path-mismatch"
cp -pR "$VALID" "$TRACE_PATH_MISMATCH"
python3 - "$TRACE_PATH_MISMATCH" "$SESSION_ID" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
root = project / "review-evidence/phase-06" / sys.argv[2]
session = json.loads((root / "session.json").read_text())
role = session["reservations"][0]["role"]
completion_path = root / "completions" / f"{role}.json"
completion = json.loads(completion_path.read_text())
completion["trace_path"] = session["reservations"][1]["trace_path"]
completion_path.write_text(json.dumps(completion, indent=2, sort_keys=True) + "\n")
PY
set +e
bash "$VERIFY" 6 "$TRACE_PATH_MISMATCH" >"$TMP_ROOT/trace-path-mismatch.out" 2>&1
TRACE_PATH_MISMATCH_RC=$?
set -e
[ "$TRACE_PATH_MISMATCH_RC" -ne 0 ] || fail "completion trace path mismatch passed"
grep -F "trace path mismatch" "$TMP_ROOT/trace-path-mismatch.out" >/dev/null \
  || fail "completion trace path mismatch failed for the wrong reason"

RUN_NONCE_MISMATCH="$TMP_ROOT/run-nonce-mismatch"
cp -pR "$VALID" "$RUN_NONCE_MISMATCH"
python3 - "$RUN_NONCE_MISMATCH/.auto-research/state.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
state = json.loads(path.read_text())
state["run_nonce"] = "run-forged-nonce"
path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY
set +e
bash "$VERIFY" 6 "$RUN_NONCE_MISMATCH" >"$TMP_ROOT/run-nonce-mismatch.out" 2>&1
RUN_NONCE_MISMATCH_RC=$?
set -e
[ "$RUN_NONCE_MISMATCH_RC" -ne 0 ] || fail "run nonce mismatch passed"
grep -F "run nonce mismatch" "$TMP_ROOT/run-nonce-mismatch.out" >/dev/null \
  || fail "run nonce mismatch failed for the wrong reason"

PHASE_MISMATCH="$TMP_ROOT/phase-mismatch"
cp -pR "$VALID" "$PHASE_MISMATCH"
python3 - "$PHASE_MISMATCH/review-evidence/phase-06/$SESSION_ID/session.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
session = json.loads(path.read_text())
session["phase_id"] = "7"
path.write_text(json.dumps(session, indent=2, sort_keys=True) + "\n")
PY
set +e
bash "$VERIFY" 6 "$PHASE_MISMATCH" >"$TMP_ROOT/phase-mismatch.out" 2>&1
PHASE_MISMATCH_RC=$?
set -e
[ "$PHASE_MISMATCH_RC" -ne 0 ] || fail "session phase mismatch passed"
grep -F "phase/round mismatch" "$TMP_ROOT/phase-mismatch.out" >/dev/null \
  || fail "session phase mismatch failed for the wrong reason"

PROFILE_DRIFT="$TMP_ROOT/profile-drift"
cp -pR "$VALID" "$PROFILE_DRIFT"
bash "$STATE" set-review-profile "$PROFILE_DRIFT" strict \
  --operator test-operator --reason "strict replay test" >/dev/null
set +e
bash "$VERIFY" 6 "$PROFILE_DRIFT" >"$TMP_ROOT/profile-drift.out" 2>&1
PROFILE_DRIFT_RC=$?
set -e
[ "$PROFILE_DRIFT_RC" -ne 0 ] || fail "old normal-profile session replayed after strict profile change"
grep -F "attempt_epoch does not match project state" "$TMP_ROOT/profile-drift.out" >/dev/null \
  || fail "profile-change replay failed for the wrong reason"

echo "PASS: report, trace, and reviewed-input mutations invalidate evidence"
echo "PASS: assurance-profile changes advance attempt epochs and block replay"

fresh_phase6_project() {
  local target="$1"
  cp -pR "$FIXTURE" "$target"
  bash "$STATE" init "$target" >/dev/null
  bash "$STATE" set-mode "$target" autonomous "F09 adversarial fixture" >/dev/null
  local phase
  for phase in 0 1 2 3 4 5; do
    python3 "$SEED" "$CONTRACT" "$target" "$phase" "$target/analysis/analysis-plan.md"
  done
}

begin_and_write_phase6() {
  local target="$1" output_file="$2"
  bash "$STATE" review-begin "$target" 6 initial_panel generic-host >"$output_file"
  local sid
  sid="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$output_file")"
  python3 - "$target" "$sid" <<'PY'
import json, pathlib, shutil, sys
project = pathlib.Path(sys.argv[1])
session_id = sys.argv[2]
session = json.loads((project / "review-evidence/phase-06" / session_id / "session.json").read_text())
for index, reservation in enumerate(session["reservations"], 1):
    role = reservation["role"]
    report = project / reservation["report_path"]
    trace = project / reservation["trace_path"]
    report.parent.mkdir(parents=True, exist_ok=True)
    trace.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(project / "review/agents" / f"{role}.md", report)
    trace.write_text(json.dumps({
        "step": f"adversarial-{role}",
        "action": f"exercise role {index}",
        "observation": "reserved artifacts written",
        "status": "ok",
    }) + "\n")
PY
}

# F09 reviewer-found lifecycle reproductions. These are intentionally placed
# beside the shared fixture helpers so every probe starts from the same ordered
# Phase 0-5 state and exercises production state commands.
HITL_PENDING="$TMP_ROOT/hitl-pending"
fresh_phase6_project "$HITL_PENDING"
bash "$STATE" set-mode "$HITL_PENDING" human-in-loop "require approval before review work" \
  >"$TMP_ROOT/hitl-mode.out"
bash "$STATE" next "$HITL_PENDING" >"$TMP_ROOT/hitl-next.out"
grep -F "APPROVAL_REQUIRED=1" "$TMP_ROOT/hitl-next.out" >/dev/null \
  || fail "HITL fixture did not establish a pending approval"
set +e
bash "$STATE" review-begin "$HITL_PENDING" 6 initial_panel generic-host \
  >"$TMP_ROOT/hitl-review-begin.out" 2>&1
HITL_BEGIN_RC=$?
set -e
[ "$HITL_BEGIN_RC" -ne 0 ] || fail "review-begin bypassed pending HITL approval"
grep -F "HUMAN_DECISION_REQUIRED" "$TMP_ROOT/hitl-review-begin.out" >/dev/null \
  || fail "HITL review-begin rejection emitted the wrong diagnostic"

COMPLETION_PARENT_ESCAPE="$TMP_ROOT/completion-parent-escape"
fresh_phase6_project "$COMPLETION_PARENT_ESCAPE"
begin_and_write_phase6 "$COMPLETION_PARENT_ESCAPE" "$TMP_ROOT/completion-parent-begin.out"
COMPLETION_PARENT_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/completion-parent-begin.out")"
COMPLETION_OUTSIDE="$TMP_ROOT/outside-completions"
mkdir -p "$COMPLETION_OUTSIDE"
ln -s "$COMPLETION_OUTSIDE" \
  "$COMPLETION_PARENT_ESCAPE/review-evidence/phase-06/$COMPLETION_PARENT_SESSION/completions"
set +e
bash "$STATE" review-complete "$COMPLETION_PARENT_ESCAPE" 6 "$COMPLETION_PARENT_SESSION" correctness \
  --driver-status succeeded --host-task-id completion-parent-escape --model-unavailable "not exposed" \
  >"$TMP_ROOT/completion-parent.out" 2>&1
COMPLETION_PARENT_RC=$?
set -e
[ "$COMPLETION_PARENT_RC" -ne 0 ] || fail "symlinked completions parent escaped the review session"
grep -F "review completions directory must not be a symlink" "$TMP_ROOT/completion-parent.out" >/dev/null \
  || fail "symlinked completions parent failed for the wrong reason"
[ ! -e "$COMPLETION_OUTSIDE/correctness.json" ] \
  || fail "review-complete wrote a completion record outside the project"

ABORT_RECOVERY="$TMP_ROOT/abort-recovery"
fresh_phase6_project "$ABORT_RECOVERY"
bash "$STATE" review-begin "$ABORT_RECOVERY" 6 initial_panel generic-host \
  >"$TMP_ROOT/abort-recovery-begin.out"
ABORT_RECOVERY_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/abort-recovery-begin.out")"
set +e
SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT=review-abort-before-state-save \
  bash "$STATE" review-abort "$ABORT_RECOVERY" 6 "$ABORT_RECOVERY_SESSION" \
  --reason "driver observed cancellation" >"$TMP_ROOT/abort-recovery-fail.out" 2>&1
ABORT_RECOVERY_RC=$?
set -e
[ "$ABORT_RECOVERY_RC" -ne 0 ] || fail "abort prepublication failpoint unexpectedly passed"
grep -F "INJECTED_REVIEW_ABORT_FAILURE: before state abort publication" \
  "$TMP_ROOT/abort-recovery-fail.out" >/dev/null \
  || fail "abort prepublication failpoint emitted the wrong diagnostic"
python3 "$SKILL_DIR/scripts/review_evidence.py" status \
  --project "$ABORT_RECOVERY" --phase 6 --contract "$CONTRACT" >"$TMP_ROOT/abort-recovery-status.json"
grep -F '"lifecycle": "abort_pending_publication"' "$TMP_ROOT/abort-recovery-status.json" >/dev/null \
  || fail "marker-only abort was not diagnosed as pending state publication"
bash "$STATE" review-abort "$ABORT_RECOVERY" 6 "$ABORT_RECOVERY_SESSION" \
  --reason "driver observed cancellation" >/dev/null
bash "$STATE" review-begin "$ABORT_RECOVERY" 6 initial_panel generic-host \
  >"$TMP_ROOT/abort-recovery-retry.out"
grep -F "REVIEW_SESSION_ID=" "$TMP_ROOT/abort-recovery-retry.out" >/dev/null \
  || fail "recovered abort did not permit a fresh review reservation"

REREVIEW_CURRENT="$TMP_ROOT/rereview-current"
fresh_phase6_project "$REREVIEW_CURRENT"
python3 "$SKILL_DIR/tests/helpers/register-review-evidence-fixture.py" \
  "$SKILL_DIR" "$REREVIEW_CURRENT" 6 initial_panel >/dev/null
python3 - "$REREVIEW_CURRENT" <<'PY'
import hashlib, json, pathlib, sys
project = pathlib.Path(sys.argv[1])
inventory_path = project / "analysis/scripts-inventory.json"
inventory = json.loads(inventory_path.read_text())
inventory["reviewer_verified_fix"] = True
inventory_path.write_text(json.dumps(inventory, indent=2, sort_keys=True) + "\n")
inventory_sha = hashlib.sha256(inventory_path.read_bytes()).hexdigest()
summary_path = project / "review/pre-execution-review.json"
summary = json.loads(summary_path.read_text())
summary["inventory_hash"] = inventory_sha
summary["source_hashes"]["scripts_inventory"] = inventory_sha
summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
fix_path = project / "review/pre-execution-fix-log.json"
fix = json.loads(fix_path.read_text())
fix["fixed_findings"] = [{
    "finding_id": "F09-REREVIEW-1", "status": "fixed",
    "action_taken": "Corrected the scripts inventory after the initial review.",
    "affected_files": ["analysis/scripts-inventory.json"],
}]
fix_path.write_text(json.dumps(fix, indent=2, sort_keys=True) + "\n")
rereview_path = project / "review/pre-execution-rereview.json"
rereview = json.loads(rereview_path.read_text())
rereview.update({
    "evidence_role": "fix_verifier",
    "report_path": "review/agents/correctness.md",
    "task_invocation_id": "fixture-fix-rereview",
    "rereviewed_findings": [{
        "finding_id": "F09-REREVIEW-1", "resolution_verdict": "RESOLVED"
    }],
})
rereview_path.write_text(json.dumps(rereview, indent=2, sort_keys=True) + "\n")
PY
python3 "$SKILL_DIR/tests/helpers/register-review-evidence-fixture.py" \
  "$SKILL_DIR" "$REREVIEW_CURRENT" 6 fix_rereview >/dev/null
bash "$VERIFY" 6 "$REREVIEW_CURRENT" >"$TMP_ROOT/rereview-current.out" 2>&1 \
  || fail "valid post-fix rereview rejected historical initial-panel evidence: $(cat "$TMP_ROOT/rereview-current.out")"

OUT_OF_ORDER_BEGIN="$TMP_ROOT/out-of-order-begin"
fresh_phase6_project "$OUT_OF_ORDER_BEGIN"
python3 - "$OUT_OF_ORDER_BEGIN/review/pre-execution-fix-log.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text())
value["fixed_findings"] = [{
    "finding_id": "F09-ORDER-1", "status": "fixed",
    "action_taken": "synthetic ordering probe",
    "affected_files": ["analysis/analysis-plan.md"],
}]
path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY
set +e
bash "$STATE" review-begin "$OUT_OF_ORDER_BEGIN" 6 fix_rereview generic-host \
  >"$TMP_ROOT/out-of-order-begin.out" 2>&1
OUT_OF_ORDER_BEGIN_RC=$?
set -e
[ "$OUT_OF_ORDER_BEGIN_RC" -ne 0 ] \
  || fail "fix/rereview reservation bypassed the initial-panel prerequisite"
grep -F "complete active prior round initial_panel" "$TMP_ROOT/out-of-order-begin.out" >/dev/null \
  || fail "out-of-order fix/rereview reservation failed for the wrong reason"

OUT_OF_ORDER_STATE="$TMP_ROOT/out-of-order-state"
cp -pR "$REREVIEW_CURRENT" "$OUT_OF_ORDER_STATE"
python3 - "$OUT_OF_ORDER_STATE/.auto-research/state.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
state = json.loads(path.read_text())
history = state["review_evidence_history"]
fix_registration = next(
    event for event in history
    if event.get("event") == "review_session_registered"
    and event.get("phase_id") == "6"
    and event.get("round") == "fix_rereview"
)
history.remove(fix_registration)
initial_registration_index = next(
    index for index, event in enumerate(history)
    if event.get("event") == "review_session_registered"
    and event.get("phase_id") == "6"
    and event.get("round") == "initial_panel"
)
history.insert(initial_registration_index, fix_registration)
path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY
set +e
bash "$VERIFY" 6 "$OUT_OF_ORDER_STATE" >"$TMP_ROOT/out-of-order-state.out" 2>&1
OUT_OF_ORDER_STATE_RC=$?
set -e
[ "$OUT_OF_ORDER_STATE_RC" -ne 0 ] \
  || fail "verification accepted a fix/rereview registration preceding initial-panel completion"
grep -F "registration event precedes completion of prior round initial_panel" \
  "$TMP_ROOT/out-of-order-state.out" >/dev/null \
  || fail "persisted round chronology attack failed for the wrong reason"

echo "PASS: HITL, containment, abort recovery, current-rereview, and round-order lifecycle checks"

STATUS_PROJECT="$TMP_ROOT/status-project"
fresh_phase6_project "$STATUS_PROJECT"
bash "$STATE" review-begin "$STATUS_PROJECT" 6 initial_panel generic-host >"$TMP_ROOT/status-begin.out"
python3 "$SKILL_DIR/scripts/review_evidence.py" status \
  --project "$STATUS_PROJECT" --phase 6 --contract "$CONTRACT" >"$TMP_ROOT/status.json"
python3 - "$TMP_ROOT/status.json" <<'PY'
import json, sys
status = json.load(open(sys.argv[1], encoding="utf-8"))
assert status["profile"] == "normal"
assert status["minimum_assurance"] == "process_recorded"
assert status["sessions"][0]["lifecycle"] == "active"
assert "complete each pending reservation" in status["sessions"][0]["next_action"]
assert status["verification_ready"] is False
PY

PREEXISTING="$TMP_ROOT/preexisting-reservation"
fresh_phase6_project "$PREEXISTING"
mkdir -p "$PREEXISTING/review-evidence/phase-06/s-deadbeef/reports"
printf 'pre-existing report\n' >"$PREEXISTING/review-evidence/phase-06/s-deadbeef/reports/correctness.md"
python3 - "$SKILL_DIR" "$PREEXISTING" <<'PY'
import json, pathlib, sys
skill = pathlib.Path(sys.argv[1])
project = pathlib.Path(sys.argv[2])
sys.path.insert(0, str(skill / "scripts"))
import review_evidence
contract = json.loads((skill / "references/phase-contract.json").read_text())
state = json.loads((project / ".auto-research/state.json").read_text())
review_evidence.secrets.token_hex = lambda _: "deadbeef"
try:
    review_evidence.begin_session(project, contract, state, "6", "initial_panel", "generic-host")
except review_evidence.EvidenceError as exc:
    assert str(exc) == "review session path already exists; retry with a fresh reservation", exc
else:
    raise AssertionError("pre-existing reservation path was accepted")
PY

BEGIN_BEFORE="$TMP_ROOT/begin-before-save"
fresh_phase6_project "$BEGIN_BEFORE"
set +e
SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT=review-begin-before-state-save \
  bash "$STATE" review-begin "$BEGIN_BEFORE" 6 initial_panel generic-host \
  >"$TMP_ROOT/begin-before-save.out" 2>&1
BEGIN_BEFORE_RC=$?
set -e
[ "$BEGIN_BEFORE_RC" -ne 0 ] || fail "begin prepublication failpoint unexpectedly passed"
grep -F "INJECTED_REVIEW_BEGIN_FAILURE: before state registration publication" \
  "$TMP_ROOT/begin-before-save.out" >/dev/null || fail "begin prepublication failpoint emitted wrong diagnostic"
python3 "$SKILL_DIR/scripts/review_evidence.py" status \
  --project "$BEGIN_BEFORE" --phase 6 --contract "$CONTRACT" >"$TMP_ROOT/begin-before-status.json"
grep -F '"lifecycle": "orphan_unregistered"' "$TMP_ROOT/begin-before-status.json" >/dev/null \
  || fail "orphan begin-session directory was not diagnosed as unregistered"

BEGIN_AFTER="$TMP_ROOT/begin-after-save"
fresh_phase6_project "$BEGIN_AFTER"
set +e
SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT=review-begin-after-state-save \
  bash "$STATE" review-begin "$BEGIN_AFTER" 6 initial_panel generic-host \
  >"$TMP_ROOT/begin-after-save.out" 2>&1
BEGIN_AFTER_RC=$?
set -e
[ "$BEGIN_AFTER_RC" -ne 0 ] || fail "begin postpublication failpoint unexpectedly passed"
grep -F "INJECTED_REVIEW_BEGIN_FAILURE: after state registration publication" \
  "$TMP_ROOT/begin-after-save.out" >/dev/null || fail "begin postpublication failpoint emitted wrong diagnostic"
python3 "$SKILL_DIR/scripts/review_evidence.py" status \
  --project "$BEGIN_AFTER" --phase 6 --contract "$CONTRACT" >"$TMP_ROOT/begin-after-status.json"
grep -F '"lifecycle": "active"' "$TMP_ROOT/begin-after-status.json" >/dev/null \
  || fail "postpublication begin-session was not resumable"

COMPLETE_BEFORE="$TMP_ROOT/complete-before-save"
fresh_phase6_project "$COMPLETE_BEFORE"
begin_and_write_phase6 "$COMPLETE_BEFORE" "$TMP_ROOT/complete-before-begin.out"
COMPLETE_BEFORE_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/complete-before-begin.out")"
set +e
SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT=review-complete-before-state-save \
  bash "$STATE" review-complete "$COMPLETE_BEFORE" 6 "$COMPLETE_BEFORE_SESSION" correctness \
  --driver-status succeeded --host-task-id complete-before --model-unavailable "not exposed" \
  >"$TMP_ROOT/complete-before-save.out" 2>&1
COMPLETE_BEFORE_RC=$?
set -e
[ "$COMPLETE_BEFORE_RC" -ne 0 ] || fail "completion prepublication failpoint unexpectedly passed"
grep -F "INJECTED_REVIEW_COMPLETION_FAILURE: before state completion publication" \
  "$TMP_ROOT/complete-before-save.out" >/dev/null || fail "completion prepublication failpoint emitted wrong diagnostic"
python3 - "$COMPLETE_BEFORE/.auto-research/state.json" "$COMPLETE_BEFORE_SESSION" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
assert not any(event.get("event") == "review_role_completed" and event.get("session_id") == sys.argv[2]
               for event in state["review_evidence_history"])
PY

COMPLETE_AFTER="$TMP_ROOT/complete-after-save"
fresh_phase6_project "$COMPLETE_AFTER"
begin_and_write_phase6 "$COMPLETE_AFTER" "$TMP_ROOT/complete-after-begin.out"
COMPLETE_AFTER_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/complete-after-begin.out")"
set +e
SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT=review-complete-after-state-save \
  bash "$STATE" review-complete "$COMPLETE_AFTER" 6 "$COMPLETE_AFTER_SESSION" correctness \
  --driver-status succeeded --host-task-id complete-after --model-unavailable "not exposed" \
  >"$TMP_ROOT/complete-after-save.out" 2>&1
COMPLETE_AFTER_RC=$?
set -e
[ "$COMPLETE_AFTER_RC" -ne 0 ] || fail "completion postpublication failpoint unexpectedly passed"
grep -F "INJECTED_REVIEW_COMPLETION_FAILURE: after state completion publication" \
  "$TMP_ROOT/complete-after-save.out" >/dev/null || fail "completion postpublication failpoint emitted wrong diagnostic"
python3 - "$COMPLETE_AFTER/.auto-research/state.json" "$COMPLETE_AFTER_SESSION" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
events = [event for event in state["review_evidence_history"]
          if event.get("event") == "review_role_completed" and event.get("session_id") == sys.argv[2]]
assert len(events) == 1 and events[0]["role"] == "correctness"
PY

NO_SESSION="$TMP_ROOT/no-session"
fresh_phase6_project "$NO_SESSION"
set +e
bash "$STATE" review-complete "$NO_SESSION" 6 s-does-not-exist correctness \
  --driver-status succeeded \
  --host-task-id opaque-1 --model-unavailable "not exposed" \
  >"$TMP_ROOT/no-session.out" 2>&1
NO_SESSION_RC=$?
set -e
[ "$NO_SESSION_RC" -ne 0 ] || fail "completion without a reservation passed"
grep -F "review session missing" "$TMP_ROOT/no-session.out" >/dev/null \
  || fail "completion without reservation failed for the wrong reason"

PRECOMPLETE_DRIFT="$TMP_ROOT/precomplete-drift"
fresh_phase6_project "$PRECOMPLETE_DRIFT"
begin_and_write_phase6 "$PRECOMPLETE_DRIFT" "$TMP_ROOT/precomplete-begin.out"
PRECOMPLETE_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/precomplete-begin.out")"
printf '\nchanged after reservation\n' >>"$PRECOMPLETE_DRIFT/analysis/analysis-plan.md"
set +e
bash "$STATE" review-complete "$PRECOMPLETE_DRIFT" 6 "$PRECOMPLETE_SESSION" correctness \
  --driver-status succeeded \
  --host-task-id opaque-2 --model-unavailable "not exposed" \
  >"$TMP_ROOT/precomplete.out" 2>&1
PRECOMPLETE_RC=$?
set -e
[ "$PRECOMPLETE_RC" -ne 0 ] || fail "input drift between reservation and completion passed"
grep -F "reviewed input membership or digest changed after session registration" "$TMP_ROOT/precomplete.out" >/dev/null \
  || fail "pre-completion input drift failed for the wrong reason"

TERMINAL="$TMP_ROOT/terminal-status"
fresh_phase6_project "$TERMINAL"
begin_and_write_phase6 "$TERMINAL" "$TMP_ROOT/terminal-begin.out"
TERMINAL_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/terminal-begin.out")"
set +e
bash "$STATE" review-complete "$TERMINAL" 6 "$TERMINAL_SESSION" correctness \
  --host-task-id terminal-omitted --model-unavailable "not exposed" \
  >"$TMP_ROOT/terminal-omitted.out" 2>&1
TERMINAL_OMITTED_RC=$?
set -e
[ "$TERMINAL_OMITTED_RC" -ne 0 ] || fail "omitted driver terminal status passed"
grep -F "review-complete requires --driver-status succeeded" "$TMP_ROOT/terminal-omitted.out" >/dev/null \
  || fail "omitted driver terminal status failed for the wrong reason"
for terminal_status in failed cancelled timed-out missing unknown; do
  set +e
  bash "$STATE" review-complete "$TERMINAL" 6 "$TERMINAL_SESSION" correctness \
    --driver-status "$terminal_status" --host-task-id "terminal-$terminal_status" \
    --model-unavailable "not exposed" >"$TMP_ROOT/terminal-$terminal_status.out" 2>&1
  TERMINAL_RC=$?
  set -e
  [ "$TERMINAL_RC" -ne 0 ] || fail "driver terminal status $terminal_status passed"
  grep -F "driver terminal status must be succeeded" "$TMP_ROOT/terminal-$terminal_status.out" >/dev/null \
    || fail "driver terminal status $terminal_status failed for the wrong reason"
done

MALFORMED_TRACE="$TMP_ROOT/malformed-trace"
fresh_phase6_project "$MALFORMED_TRACE"
begin_and_write_phase6 "$MALFORMED_TRACE" "$TMP_ROOT/malformed-trace-begin.out"
MALFORMED_TRACE_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/malformed-trace-begin.out")"
python3 - "$MALFORMED_TRACE" "$MALFORMED_TRACE_SESSION" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
session = json.loads((project / "review-evidence/phase-06" / sys.argv[2] / "session.json").read_text())
(project / session["reservations"][0]["trace_path"]).write_text("{not-json}\n")
PY
set +e
bash "$STATE" review-complete "$MALFORMED_TRACE" 6 "$MALFORMED_TRACE_SESSION" correctness \
  --driver-status succeeded --host-task-id malformed-trace --model-unavailable "not exposed" \
  >"$TMP_ROOT/malformed-trace.out" 2>&1
MALFORMED_TRACE_RC=$?
set -e
[ "$MALFORMED_TRACE_RC" -ne 0 ] || fail "malformed trace passed"
grep -F "review trace line 1 is not valid JSON" "$TMP_ROOT/malformed-trace.out" >/dev/null \
  || fail "malformed trace failed for the wrong reason"

MALFORMED_REPORT="$TMP_ROOT/malformed-report"
fresh_phase6_project "$MALFORMED_REPORT"
begin_and_write_phase6 "$MALFORMED_REPORT" "$TMP_ROOT/malformed-report-begin.out"
MALFORMED_REPORT_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/malformed-report-begin.out")"
python3 - "$MALFORMED_REPORT" "$MALFORMED_REPORT_SESSION" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
session = json.loads((project / "review-evidence/phase-06" / sys.argv[2] / "session.json").read_text())
(project / session["reservations"][0]["report_path"]).write_bytes(b"\xff\xfe")
PY
set +e
bash "$STATE" review-complete "$MALFORMED_REPORT" 6 "$MALFORMED_REPORT_SESSION" correctness \
  --driver-status succeeded --host-task-id malformed-report --model-unavailable "not exposed" \
  >"$TMP_ROOT/malformed-report.out" 2>&1
MALFORMED_REPORT_RC=$?
set -e
[ "$MALFORMED_REPORT_RC" -ne 0 ] || fail "non-UTF-8 report passed"
grep -F "review report must be valid UTF-8 text" "$TMP_ROOT/malformed-report.out" >/dev/null \
  || fail "non-UTF-8 report failed for the wrong reason"

ROLE_MISMATCH="$TMP_ROOT/role-mismatch"
fresh_phase6_project "$ROLE_MISMATCH"
begin_and_write_phase6 "$ROLE_MISMATCH" "$TMP_ROOT/role-mismatch-begin.out"
ROLE_MISMATCH_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/role-mismatch-begin.out")"
set +e
bash "$STATE" review-complete "$ROLE_MISMATCH" 6 "$ROLE_MISMATCH_SESSION" invented-role \
  --driver-status succeeded --host-task-id mismatched-role --model-unavailable "not exposed" \
  >"$TMP_ROOT/role-mismatch.out" 2>&1
ROLE_MISMATCH_RC=$?
set -e
[ "$ROLE_MISMATCH_RC" -ne 0 ] || fail "unreserved role passed"
grep -F "review role is not reserved exactly once: invented-role" "$TMP_ROOT/role-mismatch.out" >/dev/null \
  || fail "unreserved role failed for the wrong reason"

PROVIDER_METADATA="$TMP_ROOT/provider-metadata"
fresh_phase6_project "$PROVIDER_METADATA"
begin_and_write_phase6 "$PROVIDER_METADATA" "$TMP_ROOT/provider-metadata-begin.out"
PROVIDER_METADATA_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/provider-metadata-begin.out")"
bash "$STATE" review-complete "$PROVIDER_METADATA" 6 "$PROVIDER_METADATA_SESSION" correctness \
  --driver-status succeeded --host-task-id claude-like-task --model-id claude-like-model >/dev/null
bash "$STATE" review-complete "$PROVIDER_METADATA" 6 "$PROVIDER_METADATA_SESSION" robustness \
  --driver-status succeeded --host-task-id codex-like-task --model-id codex-like-model >/dev/null
python3 - "$PROVIDER_METADATA" "$PROVIDER_METADATA_SESSION" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
root = project / "review-evidence/phase-06" / sys.argv[2] / "completions"
claude_like = json.loads((root / "correctness.json").read_text())
codex_like = json.loads((root / "robustness.json").read_text())
assert claude_like["host_task_id"] == {"status": "reported", "value": "claude-like-task"}
assert claude_like["model_identity"] == {"status": "reported", "value": "claude-like-model"}
assert codex_like["host_task_id"] == {"status": "reported", "value": "codex-like-task"}
assert codex_like["model_identity"] == {"status": "reported", "value": "codex-like-model"}
PY

PLACEHOLDER="$TMP_ROOT/placeholder"
fresh_phase6_project "$PLACEHOLDER"
begin_and_write_phase6 "$PLACEHOLDER" "$TMP_ROOT/placeholder-begin.out"
PLACEHOLDER_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/placeholder-begin.out")"
set +e
bash "$STATE" review-complete "$PLACEHOLDER" 6 "$PLACEHOLDER_SESSION" correctness \
  --driver-status succeeded \
  --host-task-id TBD --model-unavailable "not exposed" \
  >"$TMP_ROOT/placeholder.out" 2>&1
PLACEHOLDER_RC=$?
set -e
[ "$PLACEHOLDER_RC" -ne 0 ] || fail "placeholder reported host task identity passed"
grep -F "placeholder must use structured unavailability" "$TMP_ROOT/placeholder.out" >/dev/null \
  || fail "placeholder identity failed for the wrong reason"

MODEL_PLACEHOLDER="$TMP_ROOT/model-placeholder"
fresh_phase6_project "$MODEL_PLACEHOLDER"
begin_and_write_phase6 "$MODEL_PLACEHOLDER" "$TMP_ROOT/model-placeholder-begin.out"
MODEL_PLACEHOLDER_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/model-placeholder-begin.out")"
set +e
bash "$STATE" review-complete "$MODEL_PLACEHOLDER" 6 "$MODEL_PLACEHOLDER_SESSION" correctness \
  --driver-status succeeded --host-task-unavailable "host has no stable task ID" --model-id unknown \
  >"$TMP_ROOT/model-placeholder.out" 2>&1
MODEL_PLACEHOLDER_RC=$?
set -e
[ "$MODEL_PLACEHOLDER_RC" -ne 0 ] || fail "placeholder reported model identity passed"
grep -F "model ID placeholder must use structured unavailability" "$TMP_ROOT/model-placeholder.out" >/dev/null \
  || fail "placeholder model identity failed for the wrong reason"

SYMLINKED="$TMP_ROOT/symlinked"
fresh_phase6_project "$SYMLINKED"
begin_and_write_phase6 "$SYMLINKED" "$TMP_ROOT/symlinked-begin.out"
SYMLINKED_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/symlinked-begin.out")"
python3 - "$SYMLINKED" "$SYMLINKED_SESSION" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
session = json.loads((project / "review-evidence/phase-06" / sys.argv[2] / "session.json").read_text())
report = project / session["reservations"][0]["report_path"]
report.unlink()
report.symlink_to(project / "review/agents/correctness.md")
PY
set +e
bash "$STATE" review-complete "$SYMLINKED" 6 "$SYMLINKED_SESSION" correctness \
  --driver-status succeeded \
  --host-task-id opaque-symlink --model-unavailable "not exposed" \
  >"$TMP_ROOT/symlinked.out" 2>&1
SYMLINKED_RC=$?
set -e
[ "$SYMLINKED_RC" -ne 0 ] || fail "symlinked report passed"
grep -F "must not be a symlink" "$TMP_ROOT/symlinked.out" >/dev/null \
  || fail "symlinked report failed for the wrong reason"

SYMLINKED_TRACE="$TMP_ROOT/symlinked-trace"
fresh_phase6_project "$SYMLINKED_TRACE"
begin_and_write_phase6 "$SYMLINKED_TRACE" "$TMP_ROOT/symlinked-trace-begin.out"
SYMLINKED_TRACE_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/symlinked-trace-begin.out")"
python3 - "$SYMLINKED_TRACE" "$SYMLINKED_TRACE_SESSION" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
session = json.loads((project / "review-evidence/phase-06" / sys.argv[2] / "session.json").read_text())
trace = project / session["reservations"][0]["trace_path"]
target = project / session["reservations"][1]["trace_path"]
trace.unlink()
trace.symlink_to(target)
PY
set +e
bash "$STATE" review-complete "$SYMLINKED_TRACE" 6 "$SYMLINKED_TRACE_SESSION" correctness \
  --driver-status succeeded --host-task-id opaque-trace-symlink --model-unavailable "not exposed" \
  >"$TMP_ROOT/symlinked-trace.out" 2>&1
SYMLINKED_TRACE_RC=$?
set -e
[ "$SYMLINKED_TRACE_RC" -ne 0 ] || fail "symlinked trace passed"
grep -F "review trace must not be a symlink" "$TMP_ROOT/symlinked-trace.out" >/dev/null \
  || fail "symlinked trace failed for the wrong reason"

BOUNDARY_ESCAPE="$TMP_ROOT/boundary-escape"
fresh_phase6_project "$BOUNDARY_ESCAPE"
begin_and_write_phase6 "$BOUNDARY_ESCAPE" "$TMP_ROOT/boundary-escape-begin.out"
BOUNDARY_ESCAPE_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/boundary-escape-begin.out")"
python3 - "$BOUNDARY_ESCAPE" "$BOUNDARY_ESCAPE_SESSION" <<'PY'
import hashlib, json, pathlib, sys
project = pathlib.Path(sys.argv[1])
session_id = sys.argv[2]
(project.parent / "outside-project-review.md").write_text("outside project\n")
session_path = project / "review-evidence/phase-06" / session_id / "session.json"
session = json.loads(session_path.read_text())
session["reservations"][0]["report_path"] = "../outside-project-review.md"
session_path.write_text(json.dumps(session, indent=2, sort_keys=True) + "\n")
digest = hashlib.sha256(session_path.read_bytes()).hexdigest()
state_path = project / ".auto-research/state.json"
state = json.loads(state_path.read_text())
registration = next(event for event in state["review_evidence_history"]
                    if event.get("event") == "review_session_registered"
                    and event.get("session_id") == session_id)
registration["reservation_sha256"] = digest
state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY
set +e
bash "$STATE" review-complete "$BOUNDARY_ESCAPE" 6 "$BOUNDARY_ESCAPE_SESSION" correctness \
  --driver-status succeeded --host-task-id opaque-boundary --model-unavailable "not exposed" \
  >"$TMP_ROOT/boundary-escape.out" 2>&1
BOUNDARY_ESCAPE_RC=$?
set -e
[ "$BOUNDARY_ESCAPE_RC" -ne 0 ] || fail "project-boundary report escape passed"
grep -F "review report resolves outside project" "$TMP_ROOT/boundary-escape.out" >/dev/null \
  || fail "project-boundary report escape failed for the wrong reason"

REUSED="$TMP_ROOT/reused-task"
fresh_phase6_project "$REUSED"
begin_and_write_phase6 "$REUSED" "$TMP_ROOT/reused-begin.out"
REUSED_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/reused-begin.out")"
bash "$STATE" review-complete "$REUSED" 6 "$REUSED_SESSION" correctness \
  --driver-status succeeded \
  --host-task-id opaque-reused --model-unavailable "not exposed" >/dev/null
set +e
bash "$STATE" review-complete "$REUSED" 6 "$REUSED_SESSION" robustness \
  --driver-status succeeded \
  --host-task-id opaque-reused --model-unavailable "not exposed" \
  >"$TMP_ROOT/reused.out" 2>&1
REUSED_RC=$?
set -e
[ "$REUSED_RC" -ne 0 ] || fail "reused reported host task identity passed"
grep -F "reported host task ID is reused" "$TMP_ROOT/reused.out" >/dev/null \
  || fail "reused host task identity failed for the wrong reason"

for DUP_KIND in dispatch path; do
  DUP_PROJECT="$TMP_ROOT/duplicate-$DUP_KIND"
  fresh_phase6_project "$DUP_PROJECT"
  begin_and_write_phase6 "$DUP_PROJECT" "$TMP_ROOT/duplicate-$DUP_KIND-begin.out"
  DUP_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/duplicate-$DUP_KIND-begin.out")"
  python3 - "$DUP_PROJECT" "$DUP_SESSION" "$DUP_KIND" <<'PY'
import hashlib, json, pathlib, sys
project, session_id, kind = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
session_path = project / "review-evidence/phase-06" / session_id / "session.json"
session = json.loads(session_path.read_text())
first, second = session["reservations"][:2]
if kind == "dispatch":
    second["dispatch_id"] = first["dispatch_id"]
else:
    second["report_path"] = first["report_path"]
session_path.write_text(json.dumps(session, indent=2, sort_keys=True) + "\n")
digest = hashlib.sha256(session_path.read_bytes()).hexdigest()
state_path = project / ".auto-research/state.json"
state = json.loads(state_path.read_text())
event = next(item for item in state["review_evidence_history"]
             if item.get("event") == "review_session_registered"
             and item.get("session_id") == session_id)
event["reservation_sha256"] = digest
state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY
  bash "$STATE" review-complete "$DUP_PROJECT" 6 "$DUP_SESSION" correctness \
    --driver-status succeeded --host-task-id "duplicate-$DUP_KIND-first" \
    --model-unavailable "not exposed" >/dev/null
  set +e
  bash "$STATE" review-complete "$DUP_PROJECT" 6 "$DUP_SESSION" robustness \
    --driver-status succeeded --host-task-id "duplicate-$DUP_KIND-second" \
    --model-unavailable "not exposed" >"$TMP_ROOT/duplicate-$DUP_KIND.out" 2>&1
  DUP_RC=$?
  set -e
  [ "$DUP_RC" -ne 0 ] || fail "duplicate $DUP_KIND passed"
  if [ "$DUP_KIND" = dispatch ]; then
    grep -F "review dispatch ID is reused across the attempt" "$TMP_ROOT/duplicate-$DUP_KIND.out" >/dev/null \
      || fail "duplicate dispatch failed for the wrong reason"
  else
    grep -F "review report or trace path is reused" "$TMP_ROOT/duplicate-$DUP_KIND.out" >/dev/null \
      || fail "duplicate report path failed for the wrong reason"
  fi
done

REUSED_REPORT="$TMP_ROOT/reused-report"
fresh_phase6_project "$REUSED_REPORT"
begin_and_write_phase6 "$REUSED_REPORT" "$TMP_ROOT/reused-report-begin.out"
REUSED_REPORT_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/reused-report-begin.out")"
python3 - "$REUSED_REPORT" "$REUSED_REPORT_SESSION" report <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
session = json.loads((project / "review-evidence/phase-06" / sys.argv[2] / "session.json").read_text())
first, second = session["reservations"][:2]
target_key = "report_path" if sys.argv[3] == "report" else "trace_path"
(project / second[target_key]).write_bytes((project / first[target_key]).read_bytes())
PY
bash "$STATE" review-complete "$REUSED_REPORT" 6 "$REUSED_REPORT_SESSION" correctness \
  --driver-status succeeded \
  --host-task-id report-1 --model-unavailable "not exposed" >/dev/null
set +e
bash "$STATE" review-complete "$REUSED_REPORT" 6 "$REUSED_REPORT_SESSION" robustness \
  --driver-status succeeded \
  --host-task-id report-2 --model-unavailable "not exposed" >"$TMP_ROOT/reused-report.out" 2>&1
REUSED_REPORT_RC=$?
set -e
[ "$REUSED_REPORT_RC" -ne 0 ] || fail "reused report digest passed"
grep -F "review report digest is reused" "$TMP_ROOT/reused-report.out" >/dev/null \
  || fail "reused report digest failed for the wrong reason"

REUSED_TRACE="$TMP_ROOT/reused-trace"
fresh_phase6_project "$REUSED_TRACE"
begin_and_write_phase6 "$REUSED_TRACE" "$TMP_ROOT/reused-trace-begin.out"
REUSED_TRACE_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/reused-trace-begin.out")"
python3 - "$REUSED_TRACE" "$REUSED_TRACE_SESSION" trace <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
session = json.loads((project / "review-evidence/phase-06" / sys.argv[2] / "session.json").read_text())
first, second = session["reservations"][:2]
target_key = "report_path" if sys.argv[3] == "report" else "trace_path"
(project / second[target_key]).write_bytes((project / first[target_key]).read_bytes())
PY
bash "$STATE" review-complete "$REUSED_TRACE" 6 "$REUSED_TRACE_SESSION" correctness \
  --driver-status succeeded \
  --host-task-id trace-1 --model-unavailable "not exposed" >/dev/null
set +e
bash "$STATE" review-complete "$REUSED_TRACE" 6 "$REUSED_TRACE_SESSION" robustness \
  --driver-status succeeded \
  --host-task-id trace-2 --model-unavailable "not exposed" >"$TMP_ROOT/reused-trace.out" 2>&1
REUSED_TRACE_RC=$?
set -e
[ "$REUSED_TRACE_RC" -ne 0 ] || fail "reused trace digest passed"
grep -F "review trace digest is reused" "$TMP_ROOT/reused-trace.out" >/dev/null \
  || fail "reused trace digest failed for the wrong reason"

for CROSS_KIND in task report trace; do
  CROSS_PROJECT="$TMP_ROOT/cross-session-$CROSS_KIND"
  fresh_phase6_project "$CROSS_PROJECT"
  begin_and_write_phase6 "$CROSS_PROJECT" "$TMP_ROOT/cross-session-$CROSS_KIND-old.out"
  CROSS_OLD_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/cross-session-$CROSS_KIND-old.out")"
  bash "$STATE" review-complete "$CROSS_PROJECT" 6 "$CROSS_OLD_SESSION" correctness \
    --driver-status succeeded --host-task-id cross-session-shared-task \
    --model-unavailable "not exposed" >/dev/null
  bash "$STATE" review-abort "$CROSS_PROJECT" 6 "$CROSS_OLD_SESSION" \
    --reason "exercise cross-session replay defense" >/dev/null
  begin_and_write_phase6 "$CROSS_PROJECT" "$TMP_ROOT/cross-session-$CROSS_KIND-new.out"
  CROSS_NEW_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/cross-session-$CROSS_KIND-new.out")"
  python3 - "$CROSS_PROJECT" "$CROSS_OLD_SESSION" "$CROSS_NEW_SESSION" "$CROSS_KIND" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
old_id, new_id, kind = sys.argv[2:]
root = project / "review-evidence/phase-06"
old = json.loads((root / old_id / "session.json").read_text())["reservations"][0]
new = json.loads((root / new_id / "session.json").read_text())["reservations"][0]
old_report, old_trace = project / old["report_path"], project / old["trace_path"]
new_report, new_trace = project / new["report_path"], project / new["trace_path"]
if kind == "task":
    new_report.write_text(new_report.read_text() + "\nunique report for task replay isolation\n")
    new_trace.write_text(new_trace.read_text() + '{"step":"unique-task","action":"isolate task replay","status":"ok"}\n')
elif kind == "report":
    new_report.write_bytes(old_report.read_bytes())
    new_trace.write_text(new_trace.read_text() + '{"step":"unique-report","action":"isolate report replay","status":"ok"}\n')
elif kind == "trace":
    new_report.write_text(new_report.read_text() + "\nunique report for trace replay isolation\n")
    new_trace.write_bytes(old_trace.read_bytes())
PY
  if [ "$CROSS_KIND" = task ]; then
    CROSS_TASK_ID="cross-session-shared-task"
    CROSS_EXPECT="reported host task ID is reused across the attempt"
  elif [ "$CROSS_KIND" = report ]; then
    CROSS_TASK_ID="cross-session-report-new-task"
    CROSS_EXPECT="review report digest is reused across the attempt"
  else
    CROSS_TASK_ID="cross-session-trace-new-task"
    CROSS_EXPECT="review trace digest is reused across the attempt"
  fi
  set +e
  bash "$STATE" review-complete "$CROSS_PROJECT" 6 "$CROSS_NEW_SESSION" correctness \
    --driver-status succeeded --host-task-id "$CROSS_TASK_ID" --model-unavailable "not exposed" \
    >"$TMP_ROOT/cross-session-$CROSS_KIND.out" 2>&1
  CROSS_RC=$?
  set -e
  [ "$CROSS_RC" -ne 0 ] || fail "cross-session $CROSS_KIND replay passed"
  grep -F "$CROSS_EXPECT" "$TMP_ROOT/cross-session-$CROSS_KIND.out" >/dev/null \
    || fail "cross-session $CROSS_KIND replay failed for the wrong reason"
done

SESSION_DRIFT="$TMP_ROOT/session-drift"
fresh_phase6_project "$SESSION_DRIFT"
begin_and_write_phase6 "$SESSION_DRIFT" "$TMP_ROOT/session-drift-begin.out"
SESSION_DRIFT_ID="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/session-drift-begin.out")"
python3 - "$SESSION_DRIFT/review-evidence/phase-06/$SESSION_DRIFT_ID/session.json" <<'PY'
import json, sys
path = sys.argv[1]
doc = json.load(open(path, encoding="utf-8"))
doc["forged_after_registration"] = True
with open(path, "w", encoding="utf-8") as out:
    json.dump(doc, out, indent=2, sort_keys=True)
    out.write("\n")
PY
set +e
bash "$STATE" review-complete "$SESSION_DRIFT" 6 "$SESSION_DRIFT_ID" correctness \
  --driver-status succeeded \
  --host-task-id opaque-session-drift --model-unavailable "not exposed" \
  >"$TMP_ROOT/session-drift.out" 2>&1
SESSION_DRIFT_RC=$?
set -e
[ "$SESSION_DRIFT_RC" -ne 0 ] || fail "mutated registered session passed"
grep -F "registered review session digest mismatch" "$TMP_ROOT/session-drift.out" >/dev/null \
  || fail "mutated session failed for the wrong reason"

ABORT_RESURRECTION="$TMP_ROOT/abort-resurrection"
cp -pR "$VALID" "$ABORT_RESURRECTION"
bash "$STATE" review-abort "$ABORT_RESURRECTION" 6 "$SESSION_ID" \
  --reason "exercise state-authoritative abort" >/dev/null
rm "$ABORT_RESURRECTION/review-evidence/phase-06/$SESSION_ID/aborted.json"
set +e
bash "$VERIFY" 6 "$ABORT_RESURRECTION" >"$TMP_ROOT/abort-resurrection.out" 2>&1
ABORT_RESURRECTION_RC=$?
set -e
[ "$ABORT_RESURRECTION_RC" -ne 0 ] || fail "deleted abort marker resurrected an aborted session"
grep -F "selected session has a registered abort event" "$TMP_ROOT/abort-resurrection.out" >/dev/null \
  || fail "abort-marker deletion failed for the wrong reason"

ABORTED="$TMP_ROOT/aborted"
fresh_phase6_project "$ABORTED"
bash "$STATE" review-begin "$ABORTED" 6 initial_panel generic-host >"$TMP_ROOT/abort-begin.out"
ABORT_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/abort-begin.out")"
bash "$STATE" review-abort "$ABORTED" 6 "$ABORT_SESSION" --reason "driver observed cancellation" >/dev/null
bash "$STATE" review-begin "$ABORTED" 6 initial_panel generic-host >"$TMP_ROOT/retry-begin.out"
RETRY_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/retry-begin.out")"
[ -n "$RETRY_SESSION" ] && [ "$RETRY_SESSION" != "$ABORT_SESSION" ] \
  || fail "aborted session did not permit a fresh reservation"

STRICT="$TMP_ROOT/strict"
fresh_phase6_project "$STRICT"
bash "$STATE" set-review-profile "$STRICT" strict \
  --operator test-operator --reason "exercise unsupported host verification" >/dev/null
begin_and_write_phase6 "$STRICT" "$TMP_ROOT/strict-begin.out"
STRICT_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$TMP_ROOT/strict-begin.out")"
python3 - "$STRICT" "$STRICT_SESSION" "$STATE" <<'PY'
import json, pathlib, subprocess, sys, time, os
project = pathlib.Path(sys.argv[1])
session_id = sys.argv[2]
state_tool = sys.argv[3]
session = json.loads((project / "review-evidence/phase-06" / session_id / "session.json").read_text())
for index, reservation in enumerate(session["reservations"], 1):
    subprocess.run([
        "bash", state_tool, "review-complete", str(project), "6", session_id,
        reservation["role"], "--driver-status", "succeeded",
        "--host-task-id", f"strict-{index}",
        "--model-unavailable", "generic host exposes no model identity",
    ], check=True, stdout=subprocess.DEVNULL)
summary_path = project / "review/pre-execution-review.json"
summary = json.loads(summary_path.read_text())
by_role = {item["role"]: item for item in session["reservations"]}
for reviewer in summary["reviewers"]:
    reservation = by_role[reviewer["role"]]
    reviewer["report_path"] = reservation["report_path"]
    reviewer["task_invocation_id"] = reservation["dispatch_id"]
summary["review_evidence"] = {
    "profile": "strict", "attempt_epoch": 1,
    "rounds": {
        "initial_panel": {"session_id": session_id, "achieved_assurance": "host_verified"},
        "fix_rereview": {"status": "not_applicable"},
    },
}
summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
stamp = time.time()
os.utime(summary_path, (stamp, stamp))
os.utime(project / "review/pre-execution-fix-log.json", (stamp + 1, stamp + 1))
os.utime(project / "review/pre-execution-rereview.json", (stamp + 2, stamp + 2))
PY
PARTIAL_STRICT="$TMP_ROOT/partial-strict"
cp -pR "$STRICT" "$PARTIAL_STRICT"
python3 - "$PARTIAL_STRICT" "$STRICT_SESSION" <<'PY'
import hashlib, json, pathlib, sys
project = pathlib.Path(sys.argv[1])
session_id = sys.argv[2]
path = project / "review-evidence/phase-06" / session_id / "completions/correctness.json"
completion = json.loads(path.read_text())
completion["host_verification"]["claims"]["task_identity"] = "verified"
completion["host_verification"]["claims"]["terminal_status"] = "verified"
path.write_text(json.dumps(completion, indent=2, sort_keys=True) + "\n")
digest = hashlib.sha256(path.read_bytes()).hexdigest()
state_path = project / ".auto-research/state.json"
state = json.loads(state_path.read_text())
event = next(item for item in state["review_evidence_history"]
             if item.get("event") == "review_role_completed"
             and item.get("session_id") == session_id
             and item.get("role") == "correctness")
event["completion_sha256"] = digest
state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY
set +e
bash "$VERIFY" 6 "$PARTIAL_STRICT" >"$TMP_ROOT/partial-strict.out" 2>&1
PARTIAL_STRICT_RC=$?
set -e
[ "$PARTIAL_STRICT_RC" -ne 0 ] || fail "partial host verification satisfied strict policy"
grep -F "strict profile requires host_verified claims" "$TMP_ROOT/partial-strict.out" >/dev/null \
  || fail "partial host verification failed for the wrong reason"
set +e
bash "$VERIFY" 6 "$STRICT" >"$TMP_ROOT/strict.out" 2>&1
STRICT_RC=$?
set -e
[ "$STRICT_RC" -ne 0 ] || fail "strict profile accepted unsupported host verification"
grep -F "strict profile requires host_verified claims" "$TMP_ROOT/strict.out" >/dev/null \
  || fail "strict unsupported-host evidence failed for the wrong reason"

CONCURRENT="$TMP_ROOT/concurrent"
fresh_phase6_project "$CONCURRENT"
set +e
CLAUDE_CODE_SESSION_ID=claude-conflict CODEX_TASK_ID=codex-conflict \
  bash "$STATE" review-begin "$CONCURRENT" 6 initial_panel generic-host \
  >"$TMP_ROOT/concurrent-1.out" 2>&1 &
CONCURRENT_PID_1=$!
CLAUDE_CODE_SESSION_ID=other-claude CODEX_TASK_ID=other-codex \
  bash "$STATE" review-begin "$CONCURRENT" 6 initial_panel generic-host \
  >"$TMP_ROOT/concurrent-2.out" 2>&1 &
CONCURRENT_PID_2=$!
wait "$CONCURRENT_PID_1"; CONCURRENT_RC_1=$?
wait "$CONCURRENT_PID_2"; CONCURRENT_RC_2=$?
set -e
if [ "$CONCURRENT_RC_1" -eq 0 ] && [ "$CONCURRENT_RC_2" -ne 0 ]; then
  CONCURRENT_BEGIN_OUT="$TMP_ROOT/concurrent-1.out"
  CONCURRENT_FAIL_OUT="$TMP_ROOT/concurrent-2.out"
elif [ "$CONCURRENT_RC_2" -eq 0 ] && [ "$CONCURRENT_RC_1" -ne 0 ]; then
  CONCURRENT_BEGIN_OUT="$TMP_ROOT/concurrent-2.out"
  CONCURRENT_FAIL_OUT="$TMP_ROOT/concurrent-1.out"
else
  fail "concurrent review-begin must yield exactly one registered session"
fi
grep -F "active review session already exists" "$CONCURRENT_FAIL_OUT" >/dev/null \
  || fail "losing concurrent review-begin failed for the wrong reason"
CONCURRENT_SESSION="$(sed -n 's/^REVIEW_SESSION_ID=//p' "$CONCURRENT_BEGIN_OUT")"
python3 - "$CONCURRENT" "$CONCURRENT_SESSION" <<'PY'
import json, pathlib, shutil, sys
project = pathlib.Path(sys.argv[1])
session = json.loads((project / "review-evidence/phase-06" / sys.argv[2] / "session.json").read_text())
assert session["host_backend"] == "generic-host"
assert not any("claude" in key.lower() or "codex" in key.lower() for key in session)
for index, reservation in enumerate(session["reservations"], 1):
    role = reservation["role"]
    report = project / reservation["report_path"]
    trace = project / reservation["trace_path"]
    report.parent.mkdir(parents=True, exist_ok=True)
    trace.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(project / "review/agents" / f"{role}.md", report)
    trace.write_text(json.dumps({
        "step": role, "action": "concurrent completion",
        "observation": f"unique trace {index}", "status": "ok",
    }) + "\n")
PY
CONCURRENT_PIDS=""
CONCURRENT_INDEX=0
for CONCURRENT_ROLE in correctness robustness statistical reproducibility style_ai_patterns data_handling; do
  CONCURRENT_INDEX=$((CONCURRENT_INDEX + 1))
  bash "$STATE" review-complete "$CONCURRENT" 6 "$CONCURRENT_SESSION" "$CONCURRENT_ROLE" \
    --driver-status succeeded \
    --host-task-id "concurrent-$CONCURRENT_INDEX" --model-unavailable "not exposed" \
    >"$TMP_ROOT/concurrent-complete-$CONCURRENT_INDEX.out" 2>&1 &
  CONCURRENT_PIDS="$CONCURRENT_PIDS $!"
done
for CONCURRENT_PID in $CONCURRENT_PIDS; do
  wait "$CONCURRENT_PID" || fail "concurrent role completion lost or cross-wired state"
done
python3 - "$CONCURRENT/.auto-research/state.json" "$CONCURRENT_SESSION" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
events = [event for event in state["review_evidence_history"]
          if event.get("event") == "review_role_completed"
          and event.get("session_id") == sys.argv[2]]
assert len(events) == 6
assert len({event["role"] for event in events}) == 6
assert len({event["completion_sha256"] for event in events}) == 6
PY

# Evidence-root mutations in each verify/publish observation window must not
# authorize completion. Each injected runtime is an isolated copy of the
# production skill; only the mutation timing shim differs.
EVIDENCE_DURING="$TMP_ROOT/evidence-during"
cp -pR "$VALID" "$EVIDENCE_DURING"
EVIDENCE_DURING_SKILL="$TMP_ROOT/evidence-during-skill"
cp -R "$SKILL_DIR/." "$EVIDENCE_DURING_SKILL/"
mv "$EVIDENCE_DURING_SKILL/scripts/auto-research-verify.sh" "$EVIDENCE_DURING_SKILL/scripts/auto-research-verify-real.sh"
cat >"$EVIDENCE_DURING_SKILL/scripts/auto-research-verify.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "6" ]; then
  python3 - "$2" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
summary = json.loads((project / "review/pre-execution-review.json").read_text())
path = project / summary["reviewers"][0]["report_path"]
path.write_text(path.read_text() + "\ninjected during semantic verification\n")
PY
fi
exec bash "$HERE/auto-research-verify-real.sh" "$@"
SH
cp "$EVIDENCE_DURING/.auto-research/state.json" "$TMP_ROOT/evidence-during-before.json"
set +e
bash "$EVIDENCE_DURING_SKILL/scripts/auto-research-state.sh" complete "$EVIDENCE_DURING" 6 \
  >"$TMP_ROOT/evidence-during.out" 2>&1
EVIDENCE_DURING_RC=$?
set -e
[ "$EVIDENCE_DURING_RC" -ne 0 ] || fail "evidence mutation during semantic verification committed"
grep -F "review evidence is missing or invalid" "$TMP_ROOT/evidence-during.out" >/dev/null \
  || fail "during-verification evidence mutation failed for the wrong reason"
cmp -s "$TMP_ROOT/evidence-during-before.json" "$EVIDENCE_DURING/.auto-research/state.json" \
  || fail "during-verification evidence mutation changed state"

EVIDENCE_BEFORE_PUBLISH="$TMP_ROOT/evidence-before-publish"
cp -pR "$VALID" "$EVIDENCE_BEFORE_PUBLISH"
EVIDENCE_BEFORE_SKILL="$TMP_ROOT/evidence-before-skill"
cp -R "$SKILL_DIR/." "$EVIDENCE_BEFORE_SKILL/"
mv "$EVIDENCE_BEFORE_SKILL/scripts/auto-research-verify.sh" "$EVIDENCE_BEFORE_SKILL/scripts/auto-research-verify-real.sh"
cat >"$EVIDENCE_BEFORE_SKILL/scripts/auto-research-verify.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
bash "$HERE/auto-research-verify-real.sh" "$@"
rc=$?
if [ "$rc" -eq 0 ] && [ "${1:-}" = "6" ]; then
  python3 - "$2" <<'PY'
import json, pathlib, sys
project = pathlib.Path(sys.argv[1])
summary = json.loads((project / "review/pre-execution-review.json").read_text())
path = project / summary["reviewers"][0]["report_path"]
path.write_text(path.read_text() + "\ninjected after verifier return\n")
PY
fi
exit "$rc"
SH
cp "$EVIDENCE_BEFORE_PUBLISH/.auto-research/state.json" "$TMP_ROOT/evidence-before-publish-state.json"
set +e
bash "$EVIDENCE_BEFORE_SKILL/scripts/auto-research-state.sh" complete "$EVIDENCE_BEFORE_PUBLISH" 6 \
  >"$TMP_ROOT/evidence-before-publish.out" 2>&1
EVIDENCE_BEFORE_RC=$?
set -e
[ "$EVIDENCE_BEFORE_RC" -ne 0 ] || fail "evidence mutation before state publication committed"
grep -F "VERIFIED_ARTIFACTS_CHANGED" "$TMP_ROOT/evidence-before-publish.out" >/dev/null \
  || fail "prepublication evidence mutation failed for the wrong reason"
cmp -s "$TMP_ROOT/evidence-before-publish-state.json" "$EVIDENCE_BEFORE_PUBLISH/.auto-research/state.json" \
  || fail "prepublication evidence mutation changed state"

EVIDENCE_AFTER_PUBLISH="$TMP_ROOT/evidence-after-publish"
cp -pR "$VALID" "$EVIDENCE_AFTER_PUBLISH"
EVIDENCE_AFTER_SKILL="$TMP_ROOT/evidence-after-skill"
cp -R "$SKILL_DIR/." "$EVIDENCE_AFTER_SKILL/"
python3 - "$EVIDENCE_AFTER_SKILL/scripts/auto-research-state.sh" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = "    state_tmp.replace(state_path)\n    published_changed = False\n"
replacement = """    state_tmp.replace(state_path)
    if pid == "6":
        injected = next((proj / "review-evidence/phase-06").glob("s-*/reports/*.md"))
        injected.write_text(injected.read_text() + "\\ninjected after state publication\\n")
    published_changed = False
"""
assert text.count(needle) == 1
path.write_text(text.replace(needle, replacement))
PY
cp "$EVIDENCE_AFTER_PUBLISH/.auto-research/state.json" "$TMP_ROOT/evidence-after-publish-state.json"
set +e
bash "$EVIDENCE_AFTER_SKILL/scripts/auto-research-state.sh" complete "$EVIDENCE_AFTER_PUBLISH" 6 \
  >"$TMP_ROOT/evidence-after-publish.out" 2>&1
EVIDENCE_AFTER_RC=$?
set -e
[ "$EVIDENCE_AFTER_RC" -ne 0 ] || fail "evidence mutation immediately after publication committed"
grep -F "state rolled back" "$TMP_ROOT/evidence-after-publish.out" >/dev/null \
  || fail "postpublication evidence mutation failed for the wrong reason"
cmp -s "$TMP_ROOT/evidence-after-publish-state.json" "$EVIDENCE_AFTER_PUBLISH/.auto-research/state.json" \
  || fail "postpublication evidence mutation did not restore exact prior state"

echo "PASS: reservation, terminal-state, identity, symlink, replay, abort, and strict-profile negatives"
echo "PASS: concurrent sessions/completions serialize without loss and ignore provider environment conflicts"
echo "PASS: evidence mutations in semantic, prepublication, and postpublication windows cannot commit"
