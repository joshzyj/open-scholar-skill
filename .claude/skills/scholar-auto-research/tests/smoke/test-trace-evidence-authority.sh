#!/usr/bin/env bash
# Review trace authority regression: locked state digests, never a legacy
# dispatch-manifest row or a discoverable session file, authorize a Phase
# reviewer ID.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INGEST="$SKILL_DIR/scripts/gates/ingest-agent-trace.sh"
COVERAGE="$SKILL_DIR/scripts/gates/trace-coverage-check.sh"
EMIT="$SKILL_DIR/scripts/gates/emit-trace.sh"
BUILD="$SKILL_DIR/scripts/gates/build-run-model.py"
RENDER="$SKILL_DIR/scripts/gates/render-run-html.py"

FAILS=0
ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/auto-trace-authority.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

make_project() {
  local project="$1"
  python3 - "$project" <<'PY'
import hashlib, json, pathlib, sys
project = pathlib.Path(sys.argv[1])
session_id = "s-authorityfixture000000001"
dispatch_id = "d-authorityfixture000000001"
role = "review-code-correctness"
session_dir = project / "review-evidence/phase-06" / session_id
(session_dir / "reports").mkdir(parents=True)
(session_dir / "traces").mkdir()
(session_dir / "completions").mkdir()
(project / ".auto-research").mkdir(parents=True)
(project / "logs").mkdir()
report_rel = f"review-evidence/phase-06/{session_id}/reports/{role}.md"
trace_rel = f"review-evidence/phase-06/{session_id}/traces/{role}.trace.ndjson"
report = project / report_rel
trace = project / trace_rel
report.write_text("# Independent review\n\nNo blocking defect.\n", encoding="utf-8")
trace.write_text(json.dumps({
    "step": "verdict",
    "reasoning": "check the reserved review scope",
    "action": "inspect the registered inputs",
    "observation": "no blocking defect",
    "status": "ok",
}) + "\n", encoding="utf-8")
session = {
    "schema_version": "scholar-auto-research-review-evidence/v1",
    "session_id": session_id,
    "project_run_nonce": "run-authority-fixture",
    "phase_id": "6",
    "round": "initial_panel",
    "requested_profile": "normal",
    "attempt_epoch": 0,
    "host_backend": "generic-test-host",
    "reviewed_inputs": {"analysis/analysis-plan.md": "a" * 64},
    "reservations": [{
        "role": role,
        "dispatch_id": dispatch_id,
        "report_path": report_rel,
        "trace_path": trace_rel,
    }],
}
session_path = session_dir / "session.json"
session_path.write_text(json.dumps(session, indent=2, sort_keys=True) + "\n", encoding="utf-8")
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
completion = {
    "schema_version": "scholar-auto-research-review-evidence/v1",
    "session_id": session_id,
    "phase_id": "6",
    "round": "initial_panel",
    "attempt_epoch": 0,
    "role": role,
    "dispatch_id": dispatch_id,
    "driver_completion": {"status": "succeeded", "observed_at": "2026-08-26T00:00:01Z"},
    "report_path": report_rel,
    "report_sha256": sha(report),
    "trace_path": trace_rel,
    "trace_sha256": sha(trace),
}
completion_path = session_dir / "completions" / f"{role}.json"
completion_path.write_text(json.dumps(completion, indent=2, sort_keys=True) + "\n", encoding="utf-8")
state = {
    "schema_version": "1.3.0",
    "run_nonce": "run-authority-fixture",
    "phases_completed": ["6"],
    "phase_records": {"6": {"phase_id": "6", "phase_name": "Pre-Execution Review"}},
    "review_attempt_epochs": {"6": 0},
    "review_evidence_history": [
        {
            "event": "review_session_registered",
            "recorded_at": "2026-08-26T00:00:00Z",
            "phase_id": "6",
            "round": "initial_panel",
            "session_id": session_id,
            "reservation_sha256": sha(session_path),
            "project_run_nonce": "run-authority-fixture",
            "attempt_epoch": 0,
        },
        {
            "event": "review_role_completed",
            "recorded_at": "2026-08-26T00:00:01Z",
            "phase_id": "6",
            "round": "initial_panel",
            "session_id": session_id,
            "role": role,
            "dispatch_id": dispatch_id,
            "attempt_epoch": 0,
            "driver_completion": "succeeded",
            "completion_sha256": sha(completion_path),
            "report_sha256": sha(report),
            "trace_sha256": sha(trace),
        },
    ],
    "review_assurance_profile": "normal",
    "review_migration": {"status": "not-required"},
    "route_back_history": [],
    "route_back_retry_counts": {},
    "stale_phases": [],
    "transition_decisions": [],
    "run_mode": {"mode": "autonomous"},
}
(project / ".auto-research/state.json").write_text(
    json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY
}

session="s-authorityfixture000000001"
dispatch="d-authorityfixture000000001"
role="review-code-correctness"
trace_rel="review-evidence/phase-06/$session/traces/$role.trace.ndjson"

VALID="$TMP_ROOT/valid"
make_project "$VALID"
OUT="$(bash "$INGEST" --sidecar "$VALID/$trace_rel" --skill scholar-auto-research \
  --agent "$role" --agentId "$dispatch" --phase 6 --proj "$VALID" \
  --output-root "$VALID" 2>&1)"
RC=$?
if [ "$RC" -eq 0 ] && grep -q 'AGENTID_BOUND=yes' <<<"$OUT" && grep -q 'INGESTED=1' <<<"$OUT"; then
  ok "digest-bound state completion authorizes ingest"
else
  bad "valid registered completion did not authorize ingest (rc=$RC): $OUT"
fi

COV="$(bash "$COVERAGE" "$VALID" --skill scholar-auto-research --phase 6 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q 'STATUS=GREEN' <<<"$COV"; then
  ok "trace coverage joins the dispatch ID through state"
else
  bad "state-bound trace coverage was not GREEN (rc=$RC): $COV"
fi

TAMPER="$TMP_ROOT/tampered"
make_project "$TAMPER"
printf '\n' >> "$TAMPER/review-evidence/phase-06/$session/session.json"
OUT="$(bash "$INGEST" --sidecar "$TAMPER/$trace_rel" --skill scholar-auto-research \
  --agent "$role" --agentId "$dispatch" --phase 6 --proj "$TAMPER" \
  --output-root "$TAMPER" 2>&1)"; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'registered session digest mismatch' <<<"$OUT" \
    && [ ! -e "$TAMPER/logs/trace-scholar-auto-research-$(date +%Y-%m-%d).ndjson" ]; then
  ok "tampered session is rejected before master-trace append"
else
  bad "tampered session was not rejected transactionally (rc=$RC): $OUT"
fi

OUTPUT_ROOT="$TAMPER" bash "$EMIT" --skill scholar-auto-research --phase 6 \
  --agent "$role" --agentId "$dispatch" --step forged --action forged >/dev/null
COV="$(bash "$COVERAGE" "$TAMPER" --skill scholar-auto-research --phase 6 2>&1)"; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'registered session digest mismatch' <<<"$COV"; then
  ok "coverage rejects a trace backed by stale registration bytes"
else
  bad "coverage trusted stale registration bytes (rc=$RC): $COV"
fi

ORPHAN="$TMP_ROOT/orphan"
make_project "$ORPHAN"
python3 - "$ORPHAN/.auto-research/state.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); state = json.loads(p.read_text())
state["review_evidence_history"] = []
p.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY
OUT="$(bash "$INGEST" --sidecar "$ORPHAN/$trace_rel" --skill scholar-auto-research \
  --agent "$role" --agentId "$dispatch" --phase 6 --proj "$ORPHAN" \
  --output-root "$ORPHAN" 2>&1)"; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'not bound to exactly one current state completion' <<<"$OUT"; then
  ok "discoverable session file without state registration is rejected"
else
  bad "orphan session file authorized ingest (rc=$RC): $OUT"
fi

MANIFEST_ONLY="$TMP_ROOT/manifest-only"
mkdir -p "$MANIFEST_ONLY/logs"
printf '{"phase":"6","agentId":"manifest-only-fake"}\n' > "$MANIFEST_ONLY/logs/dispatch-manifest.jsonl"
OUTPUT_ROOT="$MANIFEST_ONLY" bash "$EMIT" --skill scholar-auto-research --phase 6 \
  --step self --action valid >/dev/null
COV="$(bash "$COVERAGE" "$MANIFEST_ONLY" --skill scholar-auto-research --phase 6 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q 'STATUS=GREEN' <<<"$COV"; then
  ok "legacy dispatch manifest is not trace-coverage authority"
else
  bad "legacy manifest still controlled coverage (rc=$RC): $COV"
fi

MISSING="$TMP_ROOT/missing-agent-trace"
make_project "$MISSING"
OUTPUT_ROOT="$MISSING" bash "$EMIT" --skill scholar-auto-research --phase 6 \
  --step self --action valid >/dev/null
COV="$(bash "$COVERAGE" "$MISSING" --skill scholar-auto-research --phase 6 2>&1)"; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'state-registered review dispatch ID' <<<"$COV"; then
  ok "registered completion without an agent trace is RED"
else
  bad "missing registered agent trace was not RED (rc=$RC): $COV"
fi

printf '{"phase":"6","agentId":"legacy-fake"}\n' > "$VALID/logs/dispatch-manifest.jsonl"
python3 "$BUILD" "$VALID" -o "$VALID/logs/run-model.json" >/dev/null
python3 - "$VALID/logs/run-model.json" "$dispatch" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
phase = next(item for item in m["phases"] if item["id"] == "6")
assert m["model_version"] == "1.4.0"
assert m["coverage"]["n_dispatches"] == 1
assert m["coverage"]["n_legacy_dispatches"] == 1
assert [item["agentId"] for item in phase["dispatches"]] == [sys.argv[2]]
assert phase["dispatch_suspect"] is False
PY
if [ $? -eq 0 ]; then ok "run model sources reviewer IDs from state, not manifest"
else bad "run model review authority is incorrect"; fi

python3 "$RENDER" "$VALID/logs/run-model.json" -o "$VALID/logs/run-html/index.html" >/dev/null
if grep -q 'digest-verified state ledger' "$VALID/logs/run-html/index.html" \
    && grep -q 'display metadata only, not review-evidence authority' "$VALID/logs/run-html/index.html"; then
  ok "run HTML labels state authority and legacy display metadata"
else
  bad "run HTML does not explain the authority boundary"
fi

if ! rg -n '_shared/process-logger\.md' "$COVERAGE" \
    "$SKILL_DIR/references/process-logger.md" "$SKILL_DIR/references/agent-trace-contract.md" >/dev/null; then
  ok "self-contained trace docs contain no _shared/process-logger residue"
else
  bad "self-contained trace docs still reference _shared/process-logger.md"
fi

if [ "$FAILS" -eq 0 ]; then
  echo "trace evidence authority smoke: PASS"
  exit 0
fi
echo "trace evidence authority smoke: FAIL ($FAILS)"
exit 1
