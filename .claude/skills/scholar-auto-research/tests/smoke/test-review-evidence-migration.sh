#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE="$SKILL_DIR/scripts/auto-research-state.sh"
CONTRACT="$SKILL_DIR/references/phase-contract.json"
SEED="$SKILL_DIR/tests/helpers/seed-completed-phase.py"
MIGRATION_ID="f09-portable-review-evidence-v1"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-review-migration.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_legacy_state() {
  local project="$1" through="$2"
  mkdir -p "$project"
  printf 'fixture\n' >"$project/artifact.txt"
  bash "$STATE" init "$project" >/dev/null
  bash "$STATE" set-mode "$project" autonomous "migration fixture" >/dev/null
  python3 - "$project/.auto-research/state.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path, encoding="utf-8"))
state["schema_version"] = "1.2.0"
state["contract_sha256"] = "c73cabcadc74bd09a29df2ccef4473349c02eded6d74e82fc8a756999f90db70"
state.pop("review_assurance_profile", None)
state.pop("review_attempt_epochs", None)
state.pop("review_evidence_history", None)
state.pop("contract_migration_history", None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  local phase=0
  while [ "$phase" -le "$through" ]; do
    python3 "$SEED" "$CONTRACT" "$project" "$phase" "$project/artifact.txt"
    phase=$((phase + 1))
  done
}

PRE_REVIEW="$TMP_ROOT/pre-review"
make_legacy_state "$PRE_REVIEW" 5
bash "$STATE" migration-status "$PRE_REVIEW" >"$TMP_ROOT/migration-status.out"
grep -F '"contract_drift": true' "$TMP_ROOT/migration-status.out" >/dev/null \
  || fail "migration-status did not report predecessor contract drift"
grep -F "$MIGRATION_ID" "$TMP_ROOT/migration-status.out" >/dev/null \
  || fail "migration-status did not identify the eligible allowlisted transition"
set +e
bash "$STATE" status "$PRE_REVIEW" >"$TMP_ROOT/drift-status.out" 2>"$TMP_ROOT/drift-status.err"
DRIFT_STATUS_RC=$?
set -e
[ "$DRIFT_STATUS_RC" -eq 0 ] || fail "read-only status was blocked by contract drift"
grep -F "CONTRACT_DRIFT" "$TMP_ROOT/drift-status.err" >/dev/null \
  || fail "read-only status did not surface contract drift"
bash "$STATE" migrate-contract "$PRE_REVIEW" "$MIGRATION_ID" \
  --operator test-operator --reason "install portable review evidence" >"$TMP_ROOT/pre.out"
python3 - "$PRE_REVIEW/.auto-research/state.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
assert state["schema_version"] == "1.3.0"
assert state["review_assurance_profile"] == "normal"
assert state["stale_phases"] == []
assert state["contract_migration_history"][-1]["migration_id"] == "f09-portable-review-evidence-v1"
PY

POST_REVIEW="$TMP_ROOT/post-review"
make_legacy_state "$POST_REVIEW" 7
python3 - "$POST_REVIEW/.auto-research/state.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path, encoding="utf-8"))
state["run_mode"]["mode"] = "human_in_loop"
state["pending_transition"] = {
    "from_phase": "7", "to_phase": "8", "reason": "obsolete",
    "status": "pending", "created_at": "2026-01-01T00:00:00+00:00",
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
bash "$STATE" migrate-contract "$POST_REVIEW" "$MIGRATION_ID" \
  --operator test-operator --reason "re-run review phases" >"$TMP_ROOT/post.out"
python3 - "$POST_REVIEW/.auto-research/state.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
assert state["stale_phases"] == ["6", "7"]
assert state["phase_records"]["6"]["review_evidence_status"] == "legacy_unverified"
assert state["review_attempt_epochs"]["6"] == 1
assert state["review_attempt_epochs"]["7"] == 1
assert state["pending_transition"] is None
PY
bash "$STATE" next "$POST_REVIEW" >"$TMP_ROOT/post-next.out"
grep -F "NEXT_PHASE=6" "$TMP_ROOT/post-next.out" >/dev/null \
  || fail "migration with an obsolete HITL transition did not resume at earliest stale Phase 6"

PROFILE_PENDING="$TMP_ROOT/profile-pending"
cp -pR "$POST_REVIEW" "$PROFILE_PENDING"
python3 - "$PROFILE_PENDING/.auto-research/state.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path, encoding="utf-8"))
state["pending_transition"] = {
    "from_phase": "7", "to_phase": "8", "reason": "obsolete",
    "status": "pending", "created_at": "2026-01-01T00:00:00+00:00",
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
bash "$STATE" set-review-profile "$PROFILE_PENDING" strict \
  --operator test-operator --reason "invalidate completed review evidence" >/dev/null
python3 - "$PROFILE_PENDING/.auto-research/state.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
assert state["pending_transition"] is None
assert state["stale_phases"][:2] == ["6", "7"]
PY

cp "$POST_REVIEW/.auto-research/state.json" "$TMP_ROOT/before-repeat.json"
set +e
bash "$STATE" migrate-contract "$POST_REVIEW" "$MIGRATION_ID" \
  --operator test-operator --reason "repeat must fail" >"$TMP_ROOT/repeat.out" 2>&1
REPEAT_RC=$?
set -e
[ "$REPEAT_RC" -ne 0 ] || fail "repeat migration unexpectedly passed"
grep -F "CONTRACT_MIGRATION_ALREADY_APPLIED" "$TMP_ROOT/repeat.out" >/dev/null \
  || fail "repeat migration failed for the wrong reason"
cmp -s "$TMP_ROOT/before-repeat.json" "$POST_REVIEW/.auto-research/state.json" \
  || fail "refused repeat migration mutated state"

WRONG="$TMP_ROOT/wrong-predecessor"
make_legacy_state "$WRONG" 5
python3 - "$WRONG/.auto-research/state.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path, encoding="utf-8"))
state["contract_sha256"] = "0" * 64
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
cp "$WRONG/.auto-research/state.json" "$TMP_ROOT/before-wrong.json"
set +e
bash "$STATE" migrate-contract "$WRONG" "$MIGRATION_ID" \
  --operator test-operator --reason "wrong predecessor" >"$TMP_ROOT/wrong.out" 2>&1
WRONG_RC=$?
set -e
[ "$WRONG_RC" -ne 0 ] || fail "wrong-predecessor migration unexpectedly passed"
grep -F "CONTRACT_MIGRATION_PREDECESSOR_MISMATCH" "$TMP_ROOT/wrong.out" >/dev/null \
  || fail "wrong-predecessor migration failed for the wrong reason"
cmp -s "$TMP_ROOT/before-wrong.json" "$WRONG/.auto-research/state.json" \
  || fail "refused wrong-predecessor migration mutated state"

CLOSURE="$TMP_ROOT/portable-v1-closure"
mkdir -p "$CLOSURE"
bash "$STATE" init "$CLOSURE" >/dev/null
bash "$STATE" set-mode "$CLOSURE" autonomous "portable v1 closure migration" >/dev/null
python3 - "$CLOSURE/.auto-research/state.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path, encoding="utf-8"))
state["schema_version"] = "1.3.0"
state["contract_sha256"] = "7293db09192e8dae5eeda2f6fe49d3354f51c7e52dcf37d569e12d41a094d994"
state["phases_completed"] = [str(value) for value in range(19)]
state["phase_records"] = {
    str(value): {"phase_id": str(value), "phase_name": "migration fixture", "artifacts": [], "dependencies": []}
    for value in range(19)
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
bash "$STATE" migration-status "$CLOSURE" >"$TMP_ROOT/closure-status.out"
grep -F "f09-review-evidence-closure-v2" "$TMP_ROOT/closure-status.out" >/dev/null \
  || fail "portable-v1 state did not identify the closure migration"
bash "$STATE" migrate-contract "$CLOSURE" f09-review-evidence-closure-v2 \
  --operator test-operator --reason "bind method orientation and semantic evidence verdict" >/dev/null
python3 - "$CLOSURE/.auto-research/state.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
assert state["schema_version"] == "1.3.0"
assert state["contract_sha256"] == "beb6125aa0b17e6505f99cc8950dc0a87a355f6ab5f886ef7b3f77b4702028f4"
assert state["stale_phases"] == [str(value) for value in range(6, 19)]
event = state["contract_migration_history"][-1]
assert event["migration_id"] == "f09-review-evidence-closure-v2"
assert event["invalidation_policy"] == {
    "invalidate_from_phase": 13,
    "invalidate_review_evidence": True,
}
assert "13" in event["invalidated_phases"]
PY

EDITED="$TMP_ROOT/edited-contract-project"
make_legacy_state "$EDITED" 5
EDITED_SKILL="$TMP_ROOT/edited-skill"
cp -R "$SKILL_DIR" "$EDITED_SKILL"
python3 - "$EDITED_SKILL/references/phase-contract.json" <<'PY'
import json, sys
path = sys.argv[1]
doc = json.load(open(path, encoding="utf-8"))
doc["unallowlisted_local_edit"] = True
with open(path, "w", encoding="utf-8") as out:
    json.dump(doc, out, indent=2, sort_keys=True)
    out.write("\n")
PY
cp "$EDITED/.auto-research/state.json" "$TMP_ROOT/before-edited.json"
set +e
bash "$EDITED_SKILL/scripts/auto-research-state.sh" migrate-contract "$EDITED" "$MIGRATION_ID" \
  --operator test-operator --reason "edited target must fail" >"$TMP_ROOT/edited.out" 2>&1
EDITED_RC=$?
set -e
[ "$EDITED_RC" -ne 0 ] || fail "migration accepted an arbitrary edited target contract"
grep -F "CONTRACT_MIGRATION_TARGET_MISMATCH" "$TMP_ROOT/edited.out" >/dev/null \
  || fail "edited target contract failed for the wrong reason"
cmp -s "$TMP_ROOT/before-edited.json" "$EDITED/.auto-research/state.json" \
  || fail "edited-target refusal mutated state"

DOWNGRADE="$TMP_ROOT/downgrade-project"
make_legacy_state "$DOWNGRADE" 5
DOWNGRADE_SKILL="$TMP_ROOT/downgrade-skill"
cp -R "$SKILL_DIR" "$DOWNGRADE_SKILL"
python3 - "$DOWNGRADE_SKILL/references/contract-migrations.json" <<'PY'
import json, sys
path = sys.argv[1]
doc = json.load(open(path, encoding="utf-8"))
doc["migrations"][0]["to_state_schema"] = "1.2.0"
with open(path, "w", encoding="utf-8") as out:
    json.dump(doc, out, indent=2, sort_keys=True)
    out.write("\n")
PY
cp "$DOWNGRADE/.auto-research/state.json" "$TMP_ROOT/before-downgrade.json"
set +e
bash "$DOWNGRADE_SKILL/scripts/auto-research-state.sh" migrate-contract "$DOWNGRADE" "$MIGRATION_ID" \
  --operator test-operator --reason "downgrade must fail" >"$TMP_ROOT/downgrade.out" 2>&1
DOWNGRADE_RC=$?
set -e
[ "$DOWNGRADE_RC" -ne 0 ] || fail "migration accepted a downgrade target"
grep -F "CONTRACT_MIGRATION_TARGET_MISMATCH" "$TMP_ROOT/downgrade.out" >/dev/null \
  || fail "downgrade target failed for the wrong reason"
cmp -s "$TMP_ROOT/before-downgrade.json" "$DOWNGRADE/.auto-research/state.json" \
  || fail "downgrade refusal mutated state"

CRASH="$TMP_ROOT/crash-project"
make_legacy_state "$CRASH" 5
cp "$CRASH/.auto-research/state.json" "$TMP_ROOT/before-crash.json"
set +e
SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT=migration-before-save \
  bash "$STATE" migrate-contract "$CRASH" "$MIGRATION_ID" \
  --operator test-operator --reason "injected prepublication failure" >"$TMP_ROOT/crash.out" 2>&1
CRASH_RC=$?
set -e
[ "$CRASH_RC" -ne 0 ] || fail "injected prepublication migration failure unexpectedly passed"
grep -F "INJECTED_MIGRATION_FAILURE" "$TMP_ROOT/crash.out" >/dev/null \
  || fail "injected migration failure emitted the wrong diagnostic"
cmp -s "$TMP_ROOT/before-crash.json" "$CRASH/.auto-research/state.json" \
  || fail "prepublication migration failure mutated predecessor state"

echo "PASS: allowlisted migration preserves pre-review completions"
echo "PASS: completed legacy review phases become stale and unverified"
echo "PASS: repeat and wrong-predecessor migrations fail without mutation"
echo "PASS: edited targets, downgrade targets, and injected prepublication failure preserve predecessor state"
