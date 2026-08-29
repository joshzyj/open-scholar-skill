#!/usr/bin/env bash
# Regression for F13: semantic contract drift must be detected consistently by
# next, status, and hash-check, and none may mutate state while refusing it.
set -uo pipefail

SOURCE_SKILL="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-contract-drift.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
SKILL="$TMP_ROOT/scholar-auto-research"
PROJ="$TMP_ROOT/project"
mkdir -p "$SKILL"
cp -R "$SOURCE_SKILL/." "$SKILL/"
STATE_SH="$SKILL/scripts/auto-research-state.sh"
CONTRACT="$SKILL/references/phase-contract.json"
CURRENT_CONTRACT_SHA="$(shasum -a 256 "$CONTRACT" | awk '{print $1}')"
cp "$CONTRACT" "$TMP_ROOT/phase-contract-original.json"

fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$STATE_SH" init "$PROJ" >/dev/null
bash "$STATE_SH" set-mode "$PROJ" autonomous "contract drift read-path test" >/dev/null

# Change a semantic field while keeping valid JSON.
python3 - "$CONTRACT" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    contract = json.load(handle)
contract["phases"][0]["name"] += " — changed"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(contract, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

cp "$PROJ/.auto-research/state.json" "$TMP_ROOT/state-before.json"
COMMON=""
for command in next hash-check; do
  set +e
  OUT="$(env -u AUTO_RESEARCH_ALLOW_CONTRACT_DRIFT bash "$STATE_SH" "$command" "$PROJ" 2>&1)"
  RC=$?
  set -e
  [ "$RC" -ne 0 ] || fail "$command ignored contract drift (rc=0): $OUT"
  FIRST="$(printf '%s\n' "$OUT" | grep -m1 '^CONTRACT_DRIFT:' || true)"
  [ -n "$FIRST" ] || fail "$command did not report CONTRACT_DRIFT: $OUT"
  case "$OUT" in
    *"Run migration-status, then apply the exact allowlisted transition with migrate-contract, or restore the recorded contract."*) ;;
    *) fail "$command advertised an unavailable or unactionable recovery path: $OUT" ;;
  esac
  if [ -z "$COMMON" ]; then
    COMMON="$FIRST"
  elif [ "$FIRST" != "$COMMON" ]; then
    fail "$command reported inconsistent drift evidence: $FIRST (expected $COMMON)"
  fi
  cmp -s "$TMP_ROOT/state-before.json" "$PROJ/.auto-research/state.json" \
    || fail "$command mutated state while refusing contract drift"
done

set +e
STATUS_OUT="$(env -u AUTO_RESEARCH_ALLOW_CONTRACT_DRIFT bash "$STATE_SH" status "$PROJ" 2>"$TMP_ROOT/status.err")"
STATUS_RC=$?
set -e
[ "$STATUS_RC" -eq 0 ] || fail "read-only status was blocked by contract drift"
grep -F "CONTRACT_DRIFT:" "$TMP_ROOT/status.err" >/dev/null \
  || fail "read-only status omitted the contract-drift warning"
printf '%s\n' "$STATUS_OUT" | grep -F '"contract_sha256"' >/dev/null \
  || fail "read-only status did not return state JSON"
cmp -s "$TMP_ROOT/state-before.json" "$PROJ/.auto-research/state.json" \
  || fail "read-only status mutated state during contract drift"

bash "$STATE_SH" migration-status "$PROJ" >"$TMP_ROOT/migration-status.out"
grep -F '"contract_drift": true' "$TMP_ROOT/migration-status.out" >/dev/null \
  || fail "migration-status did not diagnose contract drift"
grep -F 'restore the recorded contract; no allowlisted migration matches' \
  "$TMP_ROOT/migration-status.out" >/dev/null \
  || fail "migration-status did not provide the safe recovery for an arbitrary edit"

set +e
OVERRIDE_OUT="$(AUTO_RESEARCH_ALLOW_CONTRACT_DRIFT=1 bash "$STATE_SH" next "$PROJ" 2>&1)"
OVERRIDE_RC=$?
set -e
[ "$OVERRIDE_RC" -ne 0 ] \
  || fail "legacy AUTO_RESEARCH_ALLOW_CONTRACT_DRIFT bypassed read-path refusal"
printf '%s\n' "$OVERRIDE_OUT" | grep -q '^CONTRACT_DRIFT:' \
  || fail "override attempt did not retain contract-drift diagnostic: $OVERRIDE_OUT"
cmp -s "$TMP_ROOT/state-before.json" "$PROJ/.auto-research/state.json" \
  || fail "override attempt mutated state"

cp "$TMP_ROOT/phase-contract-original.json" "$CONTRACT"
[ "$CURRENT_CONTRACT_SHA" = "beb6125aa0b17e6505f99cc8950dc0a87a355f6ab5f886ef7b3f77b4702028f4" ] \
  || fail "fixture migration target hash is stale: $CURRENT_CONTRACT_SHA"

make_predecessor_project() {
  local project="$1" schema="$2" predecessor_hash="$3" through="$4"
  mkdir -p "$project"
  printf 'migration sentinel\n' >"$project/migration-sentinel.txt"
  bash "$STATE_SH" init "$project" >/dev/null
  bash "$STATE_SH" set-mode "$project" autonomous "contract migration fixture" >/dev/null
  python3 - "$project/.auto-research/state.json" "$schema" "$predecessor_hash" "$through" <<'PY'
import json, sys
path, schema, predecessor_hash, through = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
state = json.load(open(path, encoding="utf-8"))
state["schema_version"] = schema
state["contract_sha256"] = predecessor_hash
state["phases_completed"] = [str(value) for value in range(through + 1)]
state["phase_records"] = {
    str(value): {
        "phase_id": str(value),
        "phase_name": "migration fixture",
        "artifacts": [],
        "dependencies": [],
        **({"review_evidence_status": "verified"} if value in {6, 7, 9, 14} else {}),
    }
    for value in range(through + 1)
}
state["stale_phases"] = []
state["pending_transition"] = {
    "from_phase": str(through),
    "to_phase": str(through + 1),
    "reason": "obsolete migration fixture transition",
    "status": "pending",
    "created_at": "2026-01-01T00:00:00+00:00",
}
state["review_assurance_profile"] = "strict"
state["review_attempt_epochs"] = {phase: 0 for phase in ("6", "7", "9", "14", "18", "20")}
state["review_evidence_history"] = []
state["contract_migration_history"] = []
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

exercise_direct_migration() {
  local label="$1" schema="$2" predecessor_hash="$3" migration_id="$4" combined="$5"
  local project="$TMP_ROOT/$label"
  make_predecessor_project "$project" "$schema" "$predecessor_hash" 15
  local sentinel_before
  sentinel_before="$(shasum -a 256 "$project/migration-sentinel.txt" | awk '{print $1}')"

  bash "$STATE_SH" migration-status "$project" >"$TMP_ROOT/$label-status.out"
  grep -F '"contract_drift": true' "$TMP_ROOT/$label-status.out" >/dev/null \
    || fail "$label migration-status omitted contract drift"
  grep -F "\"$migration_id\"" "$TMP_ROOT/$label-status.out" >/dev/null \
    || fail "$label migration-status omitted eligible direct-to-final migration"

  bash "$STATE_SH" migrate-contract "$project" "$migration_id" \
    --operator test-operator --reason "exercise direct-to-final migration" >"$TMP_ROOT/$label-migrate.out"
  bash "$STATE_SH" status "$project" >"$TMP_ROOT/$label-post-status.out" 2>"$TMP_ROOT/$label-post-status.err"
  [ ! -s "$TMP_ROOT/$label-post-status.err" ] \
    || fail "$label status retained contract drift after migration"
  bash "$STATE_SH" next "$project" >"$TMP_ROOT/$label-next.out"

  python3 - "$project/.auto-research/state.json" "$CURRENT_CONTRACT_SHA" "$migration_id" "$combined" <<'PY'
import json, sys
path, target_hash, migration_id, combined = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "true"
state = json.load(open(path, encoding="utf-8"))
expected_stale = [str(value) for value in range(6 if combined else 13, 16)]
expected_epoch_phases = {"6", "7", "9", "14", "18", "20"} if combined else {"14", "18", "20"}
assert state["schema_version"] == "1.3.0"
assert state["contract_sha256"] == target_hash
assert state["stale_phases"] == expected_stale
assert state["pending_transition"] is None
assert state["review_assurance_profile"] == ("normal" if combined else "strict")
for phase in ("6", "7", "9", "14", "18", "20"):
    assert state["review_attempt_epochs"][phase] == (1 if phase in expected_epoch_phases else 0)
for phase in ("6", "7", "9", "14"):
    expected_status = "legacy_unverified" if combined else "verified"
    assert state["phase_records"][phase]["review_evidence_status"] == expected_status
event = state["contract_migration_history"][-1]
assert event["migration_id"] == migration_id
assert event["invalidation_policy"] == {
    "invalidate_from_phase": 13,
    "invalidate_review_evidence": combined,
}
assert event["invalidated_phases"] == expected_stale
assert event["epoch_bump_phases"] == sorted(expected_epoch_phases, key=int)
PY
  grep -F "NEXT_PHASE=$( [ "$combined" = true ] && printf 6 || printf 13 )" "$TMP_ROOT/$label-next.out" >/dev/null \
    || fail "$label did not resume at its exact invalidation boundary"
  [ "$(shasum -a 256 "$project/migration-sentinel.txt" | awk '{print $1}')" = "$sentinel_before" ] \
    || fail "$label migration changed project artifact bytes"

  cp "$project/.auto-research/state.json" "$TMP_ROOT/$label-before-replay.json"
  set +e
  bash "$STATE_SH" migrate-contract "$project" "$migration_id" \
    --operator test-operator --reason "replay must refuse" >"$TMP_ROOT/$label-replay.out" 2>&1
  local replay_rc=$?
  set -e
  [ "$replay_rc" -ne 0 ] || fail "$label migration replay unexpectedly passed"
  grep -F "CONTRACT_MIGRATION_ALREADY_APPLIED" "$TMP_ROOT/$label-replay.out" >/dev/null \
    || fail "$label migration replay failed for the wrong reason"
  cmp -s "$TMP_ROOT/$label-before-replay.json" "$project/.auto-research/state.json" \
    || fail "$label refused replay mutated state or appended history"
}

# CASE_ID: f20.migration.direct-to-final.pure
exercise_direct_migration \
  pure-f20 1.3.0 fc650fe7b9d5c675c24c99174927d0fb7aac16ed392f350a773c5c726f12cf72 \
  f20-phase13-locked-claims-v2 false
# CASE_ID: f20.migration.direct-to-final.combined-v1
exercise_direct_migration \
  combined-v1 1.2.0 c73cabcadc74bd09a29df2ccef4473349c02eded6d74e82fc8a756999f90db70 \
  f09-portable-review-evidence-v1 true
# CASE_ID: f20.migration.direct-to-final.combined-closure
exercise_direct_migration \
  combined-closure 1.3.0 7293db09192e8dae5eeda2f6fe49d3354f51c7e52dcf37d569e12d41a094d994 \
  f09-review-evidence-closure-v2 true

make_phase14_collision_project() {
  local project="$1" completed="$2"
  make_predecessor_project "$project" 1.3.0 \
    fc650fe7b9d5c675c24c99174927d0fb7aac16ed392f350a773c5c726f12cf72 \
    "$([ "$completed" = true ] && printf 14 || printf 13)"
  mkdir -p \
    "$project/manuscript" "$project/results-locked" \
    "$project/review-evidence/phase-14/s-old/reports" \
    "$project/review-evidence/phase-14/s-old/traces"
  printf '{}\n' >"$project/manuscript/manuscript-blueprint.json"
  printf '# Fixture manuscript\n' >"$project/manuscript/manuscript-draft.md"
  printf '{}\n' >"$project/manuscript/draft-manifest.json"
  printf '{}\n' >"$project/results-locked/manifest.json"
  printf 'LOCK-OLD\n' >"$project/results-locked/LATEST.txt"
  python3 - "$project" "$completed" <<'PY'
import hashlib, json, pathlib, sys
project, completed = pathlib.Path(sys.argv[1]), sys.argv[2] == "true"
state_path = project / ".auto-research/state.json"
state = json.loads(state_path.read_text(encoding="utf-8"))
roles = ("verify-numerics", "verify-figures", "verify-logic", "verify-completeness")
session_id = "s-old"
session_rel = f"review-evidence/phase-14/{session_id}"
reservations = [
    {
        "role": role,
        "dispatch_id": f"d-old-{index}",
        "report_path": f"{session_rel}/reports/{role}.md",
        "trace_path": f"{session_rel}/traces/{role}.trace.ndjson",
    }
    for index, role in enumerate(roles, 1)
]
session = {
    "schema_version": "scholar-auto-research-review-evidence/v1",
    "session_id": session_id,
    "project_run_nonce": state["run_nonce"],
    "phase_id": "14",
    "round": "verification_panel",
    "requested_profile": "normal",
    "attempt_epoch": 0,
    "host_backend": "legacy-fixture-host",
    "registered_at": "2026-01-01T00:00:00+00:00",
    "reviewed_inputs": {},
    "reservations": reservations,
}
session_path = project / session_rel / "session.json"
session_path.write_text(json.dumps(session, indent=2, sort_keys=True) + "\n", encoding="utf-8")
state["review_evidence_history"] = [{
    "event": "review_session_registered",
    "recorded_at": "2026-01-01T00:00:00+00:00",
    "phase_id": "14",
    "round": "verification_panel",
    "session_id": session_id,
    "reservation_sha256": hashlib.sha256(session_path.read_bytes()).hexdigest(),
    "project_run_nonce": state["run_nonce"],
    "attempt_epoch": 0,
}]
if completed:
    completion_dir = project / session_rel / "completions"
    completion_dir.mkdir(parents=True)
    for role in roles:
        completion_path = completion_dir / f"{role}.json"
        completion_path.write_text(json.dumps({"role": role}) + "\n", encoding="utf-8")
        state["review_evidence_history"].append({
            "event": "review_role_completed",
            "recorded_at": "2026-01-01T00:01:00+00:00",
            "phase_id": "14",
            "session_id": session_id,
            "role": role,
            "completion_sha256": hashlib.sha256(completion_path.read_bytes()).hexdigest(),
            "attempt_epoch": 0,
        })
state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

exercise_phase14_collision() {
  local label="$1" completed="$2"
  local project="$TMP_ROOT/$label"
  make_phase14_collision_project "$project" "$completed"
  bash "$STATE_SH" migrate-contract "$project" f20-phase13-locked-claims-v2 \
    --operator test-operator --reason "advance Phase 14 evidence epoch" >/dev/null
  python3 - "$project/.auto-research/state.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path, encoding="utf-8"))
assert state["review_attempt_epochs"]["14"] == 1
state["stale_phases"] = [phase for phase in state["stale_phases"] if phase != "13"]
state["pending_transition"] = None
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  bash "$STATE_SH" review-begin "$project" 14 verification_panel generic-fixture-host \
    >"$TMP_ROOT/$label-review-begin.out"
  local new_session
  new_session="$(grep '^REVIEW_SESSION_ID=' "$TMP_ROOT/$label-review-begin.out" | cut -d= -f2-)"
  [ -n "$new_session" ] || fail "$label did not create a new Phase 14 review session"
  python3 "$SKILL/scripts/review_evidence.py" status \
    --project "$project" --phase 14 --contract "$CONTRACT" >"$TMP_ROOT/$label-review-status.json"
  python3 - "$project" "$new_session" "$TMP_ROOT/$label-review-status.json" <<'PY'
import json, pathlib, sys
project, new_session, status_path = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
new_doc = json.loads((project / "review-evidence/phase-14" / new_session / "session.json").read_text())
status = json.loads(status_path.read_text())
lifecycles = {row["session_id"]: row["lifecycle"] for row in status["sessions"]}
assert new_doc["attempt_epoch"] == 1
assert lifecycles["s-old"] == "stale"
assert lifecycles[new_session] == "active"
PY
}

# CASE_ID: f20.migration.phase14-session.completed
exercise_phase14_collision phase14-completed-session true
# CASE_ID: f20.migration.phase14-session.active
exercise_phase14_collision phase14-active-session false

echo "PASS: next/hash-check reject drift while status and migration-status diagnose it without mutation"
echo "PASS: legacy contract-drift environment override cannot bypass refusal"
echo "PASS: all predecessor tuples migrate directly to the installed contract with exact invalidation policy"
echo "PASS: completed and active Phase 14 sessions become stale and reopen in a fresh epoch"
