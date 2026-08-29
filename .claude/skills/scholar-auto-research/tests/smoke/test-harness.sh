#!/usr/bin/env bash
# F20-L1-HARNESS-SELFTEST: negative controls for authoritative test evidence.

if [ "${1:-}" = "fixture" ]; then
  mode="${2:-}"
  project="${3:-}"
  case "$mode" in
    pass) exit 0 ;;
    reject) echo "E_TARGET: intended refusal" >&2; exit 7 ;;
    wrong-exit) echo "E_TARGET: intended refusal" >&2; exit 8 ;;
    wrong-diagnostic) echo "E_OTHER: unrelated refusal" >&2; exit 7 ;;
    ambiguous)
      echo "E_TARGET: intended refusal" >&2
      echo "E_TARGET: intended refusal" >&2
      exit 7
      ;;
    mutate)
      printf '%s\n' '{"counter":1}' > "$project/state.json"
      echo "E_TARGET: intended refusal" >&2
      exit 7
      ;;
    transcript-good)
      echo "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 concept-to-measure bridge: INERT (no_labeled_variables)"
      echo "FAIL: Phase 13 external manuscript gates failed"
      echo "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"
      exit 7
      ;;
    transcript-extra)
      echo "unexpected extra line"
      echo "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 concept-to-measure bridge: INERT (no_labeled_variables)"
      echo "FAIL: Phase 13 external manuscript gates failed"
      echo "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"
      exit 7
      ;;
    transcript-missing)
      echo "FAIL: Phase 13 external manuscript gates failed"
      echo "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"
      exit 7
      ;;
    transcript-duplicate)
      echo "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 concept-to-measure bridge: INERT (no_labeled_variables)"
      echo "FAIL: Phase 13 external manuscript gates failed"
      echo "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"
      echo "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"
      exit 7
      ;;
    transcript-reordered)
      echo "FAIL: Phase 13 external manuscript gates failed"
      echo "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 concept-to-measure bridge: INERT (no_labeled_variables)"
      echo "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"
      exit 7
      ;;
    transcript-spoofed)
      echo "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 spoofed bridge: INERT (no_labeled_variables)"
      echo "FAIL: Phase 13 external manuscript gates failed"
      echo "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"
      exit 7
      ;;
    transcript-wrong-stream)
      echo "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 concept-to-measure bridge: INERT (no_labeled_variables)" >&2
      echo "FAIL: Phase 13 external manuscript gates failed"
      echo "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"
      exit 7
      ;;
    capability-private)
      if env | grep -Eq '^(SCHOLAR_HARNESS_CAPABILITY|_HARNESS_CAPABILITY|HARNESS_TOKEN_ALIAS)='; then
        echo "HARNESS_CAPABILITY_LEAKED" >&2
        exit 42
      fi
      exit 0
      ;;
    typed-owned)
      echo "OWNED_PROJECT=$project/state.json"
      exit 0
      ;;
    typed-descriptor)
      fixture_contract="$(cd "$(dirname "$0")/../.." && pwd)/references/phase-contract.json"
      python3 - "$project" "$fixture_contract" <<'PY'
import hashlib, json, pathlib, sys
project = pathlib.Path(sys.argv[1])
contract = pathlib.Path(sys.argv[2])
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
descriptor = {
    "schema_version": "scholar-auto-research-verification-descriptor/v1",
    "phase_id": "0",
    "verdict": "PASS",
    "contract_sha256": sha(contract),
    "required_outputs": {"state.json": sha(project / "state.json")},
    "required_inputs": {"input.txt": sha(project / "input.txt")},
}
print("VERIFICATION_DESCRIPTOR_JSON=" + json.dumps(descriptor, sort_keys=True, separators=(",", ":")))
PY
      exit $?
      ;;
    *) echo "fixture mode unknown: $mode" >&2; exit 99 ;;
  esac
fi

set -uo pipefail

SOURCE_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SOURCE_SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_HELPER="$SOURCE_SKILL_DIR/tests/helpers/case_result.py"
SOURCE_HARNESS="$SOURCE_SKILL_DIR/tests/helpers/harness.sh"
OUTER_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-harness-selftest.XXXXXX")"
OUTER_NONCE="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
python3 "$SOURCE_HELPER" write-sentinel --root "$OUTER_ROOT" --nonce "$OUTER_NONCE" \
  --tmp-parent "$(dirname "$OUTER_ROOT")" || exit 1

outer_cleanup() {
  python3 "$SOURCE_HELPER" cleanup-owned-root --root "$OUTER_ROOT" --nonce "$OUTER_NONCE" \
    --tmp-parent "$(dirname "$OUTER_ROOT")"
}
trap outer_cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[ -f "$SOURCE_HELPER" ] || fail "missing case-result helper"
[ -f "$SOURCE_HARNESS" ] || fail "missing shell harness"

# Bind the whole self-test to one finalized isolated source generation.  This
# also proves that no parent repository helpers or Git metadata are needed.
SKILL_DIR="$OUTER_ROOT/isolated skill's tree"
mkdir -p "$SKILL_DIR/tests/helpers" "$SKILL_DIR/tests/smoke" "$SKILL_DIR/references"
cp "$SOURCE_HELPER" "$SKILL_DIR/tests/helpers/case_result.py"
cp "$SOURCE_HARNESS" "$SKILL_DIR/tests/helpers/harness.sh"
cp "$SOURCE_SELF" "$SKILL_DIR/tests/smoke/test-harness.sh"
HELPER="$SKILL_DIR/tests/helpers/case_result.py"
HARNESS="$SKILL_DIR/tests/helpers/harness.sh"
SELF="$SKILL_DIR/tests/smoke/test-harness.sh"
cat > "$SKILL_DIR/references/phase-contract.json" <<'JSON'
{"schema_version":"synthetic/v1","phases":[{"id":"0","required_outputs":["state.json"],"required_inputs":["input.txt"]}]}
JSON

MANIFEST="$OUTER_ROOT/coverage-manifest.json"
python3 - "$MANIFEST" "$SELF" <<'PY'
import hashlib, json, pathlib, sys

unchanged = {
    "authoritative_closure": ["state.json"],
    "mode": "unchanged",
    "permitted": {"added": [], "changed": [], "removed": []},
    "forbidden": ["*"],
    "ephemeral": [],
}
declared = {
    "authoritative_closure": ["state.json"],
    "mode": "declared_delta",
    "permitted": {"added": [], "changed": ["state.json#/counter"], "removed": []},
    "forbidden": ["*"],
    "ephemeral": [],
}
whole_unchanged = {
    "authoritative_closure": ["."],
    "mode": "unchanged",
    "permitted": {"added": [], "changed": [], "removed": []},
    "forbidden": ["*"],
    "ephemeral": [],
}

transcript = {
    "mode": "exact_lines",
    "stdout": [
        "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 concept-to-measure bridge: INERT (no_labeled_variables)",
        "FAIL: Phase 13 external manuscript gates failed",
        "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display",
    ],
    "stderr": [],
}

def case(polarity, rc, diagnostic, policy=unchanged, transcript_policy=None, postconditions=None, checkpoint=None):
    result = {
        "path": "tests/smoke/test-harness.sh",
        "anchor": "F20-L1-HARNESS-SELFTEST",
        "runner_label": "assigned-below",
        "tier": "fast",
        "gating": True,
        "production_entrypoint": "tests/smoke/test-harness.sh",
        "polarity": polarity,
        "expected_exit": {"kind": "exact", "value": rc},
        "diagnostic_match": {"kind": "exact" if diagnostic else "none", "value": diagnostic},
        "mutation_policy": policy,
        "finding_ids": ["F20"],
        "phase_ids": [],
        "invariant_ids": [],
        "trust_boundary_ids": ["harness_integrity"],
        "setup_authority": "fixture_setup_only",
    }
    if transcript_policy is not None:
        result["transcript_policy"] = transcript_policy
    if postconditions is not None:
        result["postconditions"] = postconditions
    if checkpoint is not None:
        result["execution_checkpoint"] = checkpoint
    return result

cases = {
    "l1-happy-pass": case("positive", 0, ""),
    "l1-happy-reject": case("negative", 7, "E_TARGET: intended refusal"),
    "l1-wrong-exit": case("negative", 7, "E_TARGET: intended refusal"),
    "l1-wrong-diagnostic": case("negative", 7, "E_TARGET: intended refusal"),
    "l1-ambiguous-diagnostic": case("negative", 7, "E_TARGET: intended refusal"),
    "l1-undeclared-delta": case("negative", 7, "E_TARGET: intended refusal"),
    "l1-declared-delta": case("negative", 7, "E_TARGET: intended refusal", declared),
    "l1-duplicate": case("positive", 0, ""),
    "l1-result-closure": case("positive", 0, ""),
    "l1-transcript-happy": case("negative", 7, transcript["stdout"][2], transcript_policy=transcript),
    "l1-transcript-extra": case("negative", 7, transcript["stdout"][2], transcript_policy=transcript),
    "l1-transcript-missing": case("negative", 7, transcript["stdout"][2], transcript_policy=transcript),
    "l1-transcript-duplicate": case("negative", 7, transcript["stdout"][2], transcript_policy=transcript),
    "l1-transcript-reordered": case("negative", 7, transcript["stdout"][2], transcript_policy=transcript),
    "l1-transcript-spoofed": case("negative", 7, transcript["stdout"][2], transcript_policy=transcript),
    "l1-transcript-wrong-stream": case("negative", 7, transcript["stdout"][2], transcript_policy=transcript),
    "l1-capability-private": case("positive", 0, ""),
    "l1-capability-preexport": case("positive", 0, ""),
    "l1-capability-allexport": case("positive", 0, ""),
    "l1-typed-owned": case("positive", 0, "", policy=whole_unchanged, transcript_policy={
        "mode": "typed_lines", "stdout": [{"kind": "owned_project_path", "prefix": "OWNED_PROJECT=", "suffix": "state.json"}], "stderr": [],
    }),
    "l1-typed-descriptor": case("positive", 0, "", policy=whole_unchanged, transcript_policy={
        "mode": "typed_lines", "stdout": [{"kind": "verification_descriptor", "phase_id": "0", "required_output_path": "state.json"}], "stderr": [],
    }),
    "l1-postconditions": case("positive", 0, "", policy=whole_unchanged, postconditions=[
        {"kind": "json_exact", "path": "state.json", "pointer": "/counter", "value": 0},
        {"kind": "json_absent", "path": "state.json", "pointer": "/absent"},
        {"kind": "json_digest_equals_path", "path": "state.json", "pointer": "/typed_input_digest", "source_path": "input.txt", "source_type": "file"},
        {"kind": "json_sha256_equals_file", "path": "state.json", "pointer": "/input_sha256", "source_path": "input.txt"},
        {"kind": "json_digest_equals_path", "path": "state.json", "pointer": "/bundle_digest", "source_path": "bundle", "source_type": "directory"},
        {"kind": "json_digest_equals_path", "path": "state.json", "pointer": "/empty_bundle_digest", "source_path": "empty-bundle", "source_type": "directory"},
        {"kind": "json_iso8601_utc", "path": "state.json", "pointer": "/imported_at"},
        {"kind": "json_pointer_equal", "path": "state.json", "pointer": "/imported_at", "other_path": "other.json", "other_pointer": "/imported_at"},
    ]),
    "l1-checkpoint-base": case("positive", 0, ""),
    "l1-checkpoint-tail": case("positive", 0, "", checkpoint="state-tail"),
    "l1-preempt": case("positive", 0, ""),
    "l1-suppressed-tail": case("positive", 0, "", checkpoint="state-tail"),
    "l1-replay": case("positive", 0, ""),
    "l1-structural": case("structural", 0, ""),
}
for case_id, spec in cases.items():
    spec["runner_label"] = case_id
cases["l1-checkpoint-base"]["runner_label"] = "l1-checkpoint-suite"
cases["l1-checkpoint-tail"]["runner_label"] = "l1-checkpoint-suite"
cases["l1-structural"]["runner_label"] = "l1-result-closure"
reviewed_path = "tests/smoke/test-harness.sh"
reviewed_digest = hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest()
json.dump({
    "schema_version": "1.2.0",
    "execution_checkpoints": ["state-tail"],
    "reviewed_test_sources": {reviewed_path: reviewed_digest},
    "cases": cases,
}, open(sys.argv[1], "w"), indent=2, sort_keys=True)
PY

# Reviewed-source authority is generic runtime input, not coverage-only metadata.
python3 - "$HELPER" "$MANIFEST" "$SKILL_DIR" "$OUTER_ROOT/reviewed-source-probes" <<'PY' \
  || fail "reviewed-source and source-digest attack matrix failed"
import copy
import hashlib
import importlib.util
import os
from pathlib import Path
import sys

helper_path, manifest_path, skill_dir, probe_root = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("case_result_reviewed_probe", helper_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
manifest = module.read_manifest(manifest_path)
expected_projection = module.validate_reviewed_sources(skill_dir, manifest)
if len(expected_projection) != 64:
    raise SystemExit("reviewed source projection digest malformed")


def refused(label, expected, callback):
    try:
        callback()
    except module.HarnessError as exc:
        if expected not in str(exc):
            raise SystemExit(f"{label}: wrong diagnostic: {exc}")
    else:
        raise SystemExit(f"{label}: mutation survived")


for label, mutate, diagnostic in (
    ("missing-map", lambda value: value.pop("reviewed_test_sources"), "HARNESS_REVIEWED_SOURCE_SCHEMA"),
    ("empty-map", lambda value: value.__setitem__("reviewed_test_sources", {}), "HARNESS_REVIEWED_SOURCE_SCHEMA"),
    ("path-escape", lambda value: value.__setitem__("reviewed_test_sources", {"../escape.sh": "0" * 64}), "HARNESS_PATH_UNSAFE"),
    ("undeclared-path", lambda value: value.__setitem__("reviewed_test_sources", {"tests/smoke/other.sh": "0" * 64}), "HARNESS_REVIEWED_SOURCE_UNDECLARED"),
    ("uppercase-digest", lambda value: value["reviewed_test_sources"].__setitem__("tests/smoke/test-harness.sh", "A" * 64), "HARNESS_REVIEWED_SOURCE_DIGEST"),
):
    mutant = copy.deepcopy(manifest)
    mutate(mutant)
    refused(label, diagnostic, lambda mutant=mutant: module.reviewed_source_projection(mutant))

mutant = copy.deepcopy(manifest)
mutant["reviewed_test_sources"]["tests/smoke/test-harness.sh"] = "0" * 64
refused("digest-mismatch", "HARNESS_REVIEWED_SOURCE_BINDING", lambda: module.validate_reviewed_sources(skill_dir, mutant))

probe_root.mkdir(parents=True)
source_bytes = (skill_dir / "tests/smoke/test-harness.sh").read_bytes()
source_digest = hashlib.sha256(source_bytes).hexdigest()

def special_root(name):
    root = probe_root / name
    (root / "tests/smoke").mkdir(parents=True)
    local = copy.deepcopy(manifest)
    local["reviewed_test_sources"] = {"tests/smoke/test-harness.sh": source_digest}
    return root, local

root, local = special_root("leaf-symlink")
(root / "tests/smoke/test-harness.sh").symlink_to(skill_dir / "tests/smoke/test-harness.sh")
refused("leaf-symlink", "HARNESS_REVIEWED_SOURCE_FILE", lambda: module.validate_reviewed_sources(root, local))

root = probe_root / "component-symlink"
(root / "tests").mkdir(parents=True)
(root / "tests/smoke").symlink_to(skill_dir / "tests/smoke")
local = copy.deepcopy(manifest)
local["reviewed_test_sources"] = {"tests/smoke/test-harness.sh": source_digest}
refused("component-symlink", "HARNESS_REVIEWED_SOURCE_FILE", lambda: module.validate_reviewed_sources(root, local))

root, local = special_root("fifo")
os.mkfifo(root / "tests/smoke/test-harness.sh")
refused("fifo", "HARNESS_REVIEWED_SOURCE_FILE", lambda: module.validate_reviewed_sources(root, local))

root, local = special_root("directory")
(root / "tests/smoke/test-harness.sh").mkdir()
refused("directory", "HARNESS_REVIEWED_SOURCE_FILE", lambda: module.validate_reviewed_sources(root, local))

root, local = special_root("atomic-swap")
target = root / "tests/smoke/test-harness.sh"
target.write_bytes(source_bytes + b"x" * (2 * 1024 * 1024))
local["reviewed_test_sources"]["tests/smoke/test-harness.sh"] = hashlib.sha256(target.read_bytes()).hexdigest()
real_read = module.os.read
swapped = False
def swapping_read(fd, size):
    global swapped
    payload = real_read(fd, size)
    if not swapped:
        swapped = True
        old = target.with_suffix(".old")
        target.rename(old)
        target.write_bytes(source_bytes)
    return payload
module.os.read = swapping_read
try:
    refused("same-path-atomic-swap", "HARNESS_REVIEWED_SOURCE_RACE", lambda: module.validate_reviewed_sources(root, local))
finally:
    module.os.read = real_read

digest_root = probe_root / "source-digest-cache-boundary"
digest_root.mkdir()
authored = digest_root / "authored.py"
authored.write_text("VALUE = 1\n", encoding="utf-8")
baseline_digest = module.source_digest(digest_root)
cache_dir = digest_root / "__pycache__"
cache_dir.mkdir()
(cache_dir / "authored.cpython-test.pyc").write_bytes(b"runtime-cache")
assert module.source_digest(digest_root) == baseline_digest, "runtime cache changed source digest"
authored.write_text("VALUE = 2\n", encoding="utf-8")
assert module.source_digest(digest_root) != baseline_digest, "authored source edit escaped source digest"

symlink_root = probe_root / "source-digest-cache-symlink"
symlink_root.mkdir()
(symlink_root / "target").mkdir()
(symlink_root / "__pycache__").symlink_to(symlink_root / "target")
assert module.source_digest(symlink_root) != module.source_digest(symlink_root / "target"), \
    "__pycache__ symlink was incorrectly treated as runtime cache"
print("HARNESS_REVIEWED_SOURCE_ATTACKS=PASS")
PY

MANIFEST_SHA="$(python3 "$HELPER" digest-file "$MANIFEST")" || fail "manifest digest failed"
SOURCE_SHA="$(python3 "$HELPER" source-digest "$SKILL_DIR")" || fail "source digest failed"
if ! SELF_LINT="$(python3 "$HELPER" lint --manifest "$MANIFEST" --source-root "$SKILL_DIR" "$SELF" 2>&1)"; then
  echo "$SELF_LINT" >&2
  fail "harness self-test does not pass its own lint"
fi

run_case() {
  # run_case <case-id> <expect-function> <fixture-mode> <expected-harness-rc>
  local case_id="$1" expectation="$2" fixture_mode="$3" expected_harness_rc="$4"
  local result_dir="$OUTER_ROOT/results-$case_id"
  local output="$OUTER_ROOT/output-$case_id"
  (
    export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR"
    export SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
    export SCHOLAR_HARNESS_RESULTS_DIR="$result_dir"
    export SCHOLAR_HARNESS_RUN_ID="run-$case_id"
    export SCHOLAR_HARNESS_RUN_NONCE="nonce-$case_id"
    export SCHOLAR_HARNESS_SUITE_MODE="self-test"
    export SCHOLAR_HARNESS_SUITE_ORDER="normal"
    export SCHOLAR_HARNESS_MANIFEST_SHA256="$MANIFEST_SHA"
    export SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$SOURCE_SHA"
    if [ "$case_id" = "l1-capability-preexport" ]; then
      export _HARNESS_CAPABILITY="caller-preexport-canary"
    elif [ "$case_id" = "l1-capability-allexport" ]; then
      set -a
    fi
    source "$HARNESS"
    harness_init "$SELF" "$case_id" || exit 91
    if [ "$case_id" = "l1-capability-preexport" ] || [ "$case_id" = "l1-capability-allexport" ]; then
      export HARNESS_TOKEN_ALIAS="$_HARNESS_CAPABILITY"
    fi
    harness_make_temp_root WORK_ROOT "owned space's $case_id" || exit 92
    mkdir -p "$WORK_ROOT/project"
    printf '%s\n' '{"counter":0}' > "$WORK_ROOT/project/state.json"
    if [ "$case_id" = "l1-typed-descriptor" ]; then
      printf 'input\n' > "$WORK_ROOT/project/input.txt"
    fi
    if [ "$case_id" = "l1-postconditions" ]; then
      printf 'input\n' > "$WORK_ROOT/project/input.txt"
      mkdir -p "$WORK_ROOT/project/bundle/sub" "$WORK_ROOT/project/empty-bundle"
      printf 'a\n' > "$WORK_ROOT/project/bundle/a.txt"
      printf 'b\n' > "$WORK_ROOT/project/bundle/sub/b.txt"
      input_sha="$(python3 "$HELPER" digest-file "$WORK_ROOT/project/input.txt")"
      printf '%s\n' '{"imported_at":"2026-08-28T12:00:00+00:00"}' > "$WORK_ROOT/project/other.json"
      bundle_digest="$(python3 - "$HELPER" "$MANIFEST" "$WORK_ROOT/project" <<'PY'
from pathlib import Path
import runpy
import sys
cr = runpy.run_path(sys.argv[1])
snapshot = cr["snapshot"](Path(sys.argv[2]), "l1-postconditions", Path(sys.argv[3]))
print(cr["descriptor_digest_from_snapshot"](snapshot, "bundle"))
PY
)"
      empty_bundle_digest="$(python3 - "$HELPER" "$MANIFEST" "$WORK_ROOT/project" <<'PY'
from pathlib import Path
import runpy
import sys
cr = runpy.run_path(sys.argv[1])
snapshot = cr["snapshot"](Path(sys.argv[2]), "l1-postconditions", Path(sys.argv[3]))
print(cr["descriptor_digest_from_snapshot"](snapshot, "empty-bundle"))
PY
)"
      [ "$empty_bundle_digest" = "$(printf '' | shasum -a 256 | awk '{print $1}')" ] || exit 93
      printf '%s\n' "{\"counter\":0,\"imported_at\":\"2026-08-28T12:00:00+00:00\",\"input_sha256\":\"$input_sha\",\"typed_input_digest\":\"$input_sha\",\"bundle_digest\":\"$bundle_digest\",\"empty_bundle_digest\":\"$empty_bundle_digest\"}" > "$WORK_ROOT/project/state.json"
    fi
    if "$expectation" "$case_id" "$WORK_ROOT/project" -- bash "$SELF" fixture "$fixture_mode" "$WORK_ROOT/project"; then
      assertion_rc=0
    else
      assertion_rc=$?
    fi
    if harness_validate_results >/dev/null 2>&1; then
      join_rc=0
    else
      join_rc=$?
    fi
    if [ "$expected_harness_rc" -eq 0 ]; then
      [ "$join_rc" -eq 0 ] || exit 93
    else
      [ "$join_rc" -ne 0 ] || exit 93
    fi
    [ "$assertion_rc" -eq "$expected_harness_rc" ] || exit 94
    python3 - "$result_dir/$case_id.json" "$expected_harness_rc" <<'PY'
import json, sys
record = json.load(open(sys.argv[1]))
expected = "PASS" if int(sys.argv[2]) == 0 else "FAIL"
assert record["terminal_status"] == expected
assert record["state_delta_verdict"] in {"PASS", "FAIL"}
assert len(record["case_nonce"]) == 64
assert len(record["source_generation_sha256"]) == 64
assert len(record["manifest_sha256"]) == 64
assert len(record["production_entrypoint"]["sha256"]) == 64
assert len(record["record_mac_sha256"]) == 64
assert record["postcondition_verdict"] in {"PASS", "not_applicable"}
assert len(record["postcondition_evidence_sha256"]) == 64
PY
  ) >"$output" 2>&1
  local rc=$?
  [ "$rc" -eq 0 ] || {
    sed -n '1,220p' "$output" >&2
    fail "$case_id scenario failed with rc=$rc"
  }
}

run_case l1-happy-pass expect_pass pass 0
run_case l1-happy-reject expect_reject reject 0
run_case l1-wrong-exit expect_reject wrong-exit 1
run_case l1-wrong-diagnostic expect_reject wrong-diagnostic 1
run_case l1-ambiguous-diagnostic expect_reject ambiguous 1
run_case l1-undeclared-delta expect_reject mutate 1
run_case l1-declared-delta expect_reject mutate 0
run_case l1-transcript-happy expect_reject transcript-good 0
run_case l1-transcript-extra expect_reject transcript-extra 1
run_case l1-transcript-missing expect_reject transcript-missing 1
run_case l1-transcript-duplicate expect_reject transcript-duplicate 1
run_case l1-transcript-reordered expect_reject transcript-reordered 1
run_case l1-transcript-spoofed expect_reject transcript-spoofed 1
run_case l1-transcript-wrong-stream expect_reject transcript-wrong-stream 1
run_case l1-capability-private expect_pass capability-private 0
run_case l1-capability-preexport expect_pass capability-private 0
run_case l1-capability-allexport expect_pass capability-private 0
run_case l1-typed-owned expect_pass typed-owned 0
run_case l1-typed-descriptor expect_pass typed-descriptor 0
run_case l1-postconditions expect_pass pass 0

grep -F -- "E_TARGET: intended refusal" "$OUTER_ROOT/output-l1-wrong-exit" >/dev/null \
  || fail "failed assertion did not preserve captured diagnostic"
grep -F -- "exact diagnostic count expected=1 observed=0" "$OUTER_ROOT/output-l1-wrong-diagnostic" >/dev/null \
  || fail "wrong diagnostic was not rejected"
grep -F -- "exact diagnostic count expected=1 observed=2" "$OUTER_ROOT/output-l1-ambiguous-diagnostic" >/dev/null \
  || fail "ambiguous diagnostic was not rejected"
grep -F -- "authoritative state delta failed" "$OUTER_ROOT/output-l1-undeclared-delta" >/dev/null \
  || fail "undeclared state mutation was not rejected"
grep -F -- "HARNESS_TRANSCRIPT_EXTRA: l1-transcript-extra" "$OUTER_ROOT/output-l1-transcript-extra" >/dev/null \
  || fail "extra transcript line was not rejected distinctly"
grep -F -- "HARNESS_TRANSCRIPT_MISSING: l1-transcript-missing" "$OUTER_ROOT/output-l1-transcript-missing" >/dev/null \
  || fail "missing advisory was not rejected distinctly"
grep -F -- "HARNESS_TRANSCRIPT_DUPLICATE: l1-transcript-duplicate" "$OUTER_ROOT/output-l1-transcript-duplicate" >/dev/null \
  || fail "duplicated transcript line was not rejected distinctly"
grep -F -- "HARNESS_TRANSCRIPT_ORDER: l1-transcript-reordered" "$OUTER_ROOT/output-l1-transcript-reordered" >/dev/null \
  || fail "reordered transcript was not rejected distinctly"
grep -F -- "HARNESS_TRANSCRIPT_MISMATCH: l1-transcript-spoofed" "$OUTER_ROOT/output-l1-transcript-spoofed" >/dev/null \
  || fail "spoofed advisory was not rejected distinctly"
grep -F -- "HARNESS_TRANSCRIPT_WRONG_STREAM: l1-transcript-wrong-stream" "$OUTER_ROOT/output-l1-transcript-wrong-stream" >/dev/null \
  || fail "cross-stream transcript was not rejected distinctly"

# Exercise the complete typed-descriptor and postcondition vocabularies against
# sentinel-owned snapshots without reproducing any production decision logic.
python3 - "$HELPER" "$SKILL_DIR" "$MANIFEST" "$OUTER_ROOT/helper-attacks" <<'PY' \
  || fail "typed descriptor/postcondition attack matrix failed"
import copy
import hashlib
import json
from pathlib import Path
import runpy
import sys

cr = runpy.run_path(sys.argv[1])
skill = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])
root = Path(sys.argv[4])
root.mkdir()
manifest = cr["read_manifest"](manifest_path)

# Structural cases are static lint declarations: their absent receipt is valid,
# while any attempt to invoke/record one is rejected before execution.
try:
    cr["check_case_binding"](
        skill, manifest, "l1-structural", skill / "tests/smoke/test-harness.sh",
        "l1-result-closure",
    )
except cr["HarnessError"] as exc:
    assert str(exc).startswith("HARNESS_STRUCTURAL_CASE_STATIC_ONLY:")
else:
    raise AssertionError("structural case invocation was accepted")


def write_json(path, value):
    path.write_bytes(cr["canonical_json"](value))


project = root / "typed project"
project.mkdir()
(project / "state.json").write_text('{"counter":0}\n')
(project / "input.txt").write_text("input\n")
typed_after = root / "typed-after.json"
typed_snapshot = cr["snapshot"](manifest_path, "l1-typed-descriptor", project)
write_json(typed_after, typed_snapshot)
descriptor = cr["expected_descriptor"](skill, project, typed_snapshot, "0")
stdout = root / "stdout"
stderr = root / "stderr"
stderr.write_text("")
# A semantically exact descriptor with noncanonical whitespace proves that the
# item is parsed as JSON rather than accepted by string interpolation.
stdout.write_text("VERIFICATION_DESCRIPTOR_JSON=" + json.dumps(descriptor, sort_keys=False) + "\n")
typed_case = cr["read_case"](manifest, "l1-typed-descriptor")
verdict, reason, _, _ = cr["evaluate_transcript"](
    typed_case, "l1-typed-descriptor", stdout, stderr, skill, project, typed_after,
)
assert verdict == "PASS" and reason is None


def typed_refused(lines, expected_reason, stderr_lines=None, case=typed_case, case_id="l1-typed-descriptor"):
    stdout.write_text("\n".join(lines) + ("\n" if lines else ""))
    stderr.write_text("\n".join(stderr_lines or []) + ("\n" if stderr_lines else ""))
    verdict, reason, _, _ = cr["evaluate_transcript"](
        case, case_id, stdout, stderr, skill, project, typed_after,
    )
    assert verdict == "FAIL" and reason == expected_reason, (expected_reason, verdict, reason)


prefix = "VERIFICATION_DESCRIPTOR_JSON="
descriptor_mutations = []
for field, value in (
    ("schema_version", "wrong/v1"), ("phase_id", "1"), ("verdict", "FAIL"),
    ("contract_sha256", "0" * 64),
):
    item = copy.deepcopy(descriptor); item[field] = value; descriptor_mutations.append(item)
item = copy.deepcopy(descriptor); item["required_outputs"]["state.json"] = "0" * 64; descriptor_mutations.append(item)
item = copy.deepcopy(descriptor); item["required_outputs"].pop("state.json"); descriptor_mutations.append(item)
item = copy.deepcopy(descriptor); item["required_outputs"]["foreign.json"] = "0" * 64; descriptor_mutations.append(item)
item = copy.deepcopy(descriptor); item["required_inputs"]["input.txt"] = "0" * 64; descriptor_mutations.append(item)
item = copy.deepcopy(descriptor); item["required_inputs"].pop("input.txt"); descriptor_mutations.append(item)
item = copy.deepcopy(descriptor); item["required_inputs"]["foreign.txt"] = "0" * 64; descriptor_mutations.append(item)
item = copy.deepcopy(descriptor); item["extra"] = True; descriptor_mutations.append(item)
for item in descriptor_mutations:
    typed_refused([prefix + json.dumps(item)], "HARNESS_TRANSCRIPT_DESCRIPTOR_BINDING")
typed_refused([prefix + "{"], "HARNESS_TRANSCRIPT_DESCRIPTOR_JSON")
typed_refused([prefix + '{"schema_version":"a","schema_version":"b"}'], "HARNESS_TRANSCRIPT_DESCRIPTOR_JSON")
typed_refused([prefix + '{"value":NaN}'], "HARNESS_TRANSCRIPT_DESCRIPTOR_JSON")
typed_refused([], "HARNESS_TRANSCRIPT_MISSING")
good_line = prefix + json.dumps(descriptor)
typed_refused([good_line, good_line], "HARNESS_TRANSCRIPT_DUPLICATE")
typed_refused([], "HARNESS_TRANSCRIPT_WRONG_STREAM", [good_line])
typed_refused([good_line, "extra"], "HARNESS_TRANSCRIPT_EXTRA")

owned_case = cr["read_case"](manifest, "l1-typed-owned")
typed_refused(
    [f"OWNED_PROJECT={root / 'foreign'}/state.json"],
    "HARNESS_TRANSCRIPT_MISMATCH", case=owned_case, case_id="l1-typed-owned",
)
bad_policy = copy.deepcopy(owned_case)
bad_policy["transcript_policy"]["stdout"].append({
    "kind": "owned_project_path", "prefix": "SECOND=", "suffix": "state.json",
})
try:
    cr["typed_transcript_expectations"](bad_policy, "l1-typed-owned", skill, project, typed_snapshot)
except cr["HarnessError"] as exc:
    assert str(exc).startswith("HARNESS_TRANSCRIPT_DYNAMIC_COUNT:")
else:
    raise AssertionError("multiple dynamic transcript slots were accepted")

post_project = root / "post project"
post_project.mkdir()
(post_project / "input.txt").write_text("input\n")
(post_project / "bundle").mkdir()
(post_project / "bundle/a.txt").write_text("a\n")
(post_project / "bundle/sub").mkdir()
(post_project / "bundle/sub/b.txt").write_text("b\n")
(post_project / "empty-bundle").mkdir()
input_sha = hashlib.sha256((post_project / "input.txt").read_bytes()).hexdigest()
stamp = "2026-08-28T12:00:00+00:00"
(post_project / "state.json").write_text(json.dumps({"counter": 0}) + "\n")
(post_project / "other.json").write_text(json.dumps({"imported_at": stamp}) + "\n")
digest_snapshot = cr["snapshot"](manifest_path, "l1-postconditions", post_project)
bundle_digest = cr["descriptor_digest_from_snapshot"](digest_snapshot, "bundle")
empty_bundle_digest = cr["descriptor_digest_from_snapshot"](digest_snapshot, "empty-bundle")
assert empty_bundle_digest == hashlib.sha256(b"").hexdigest()
(post_project / "state.json").write_text(json.dumps({
    "counter": 0, "input_sha256": input_sha, "typed_input_digest": input_sha,
    "bundle_digest": bundle_digest, "empty_bundle_digest": empty_bundle_digest,
    "imported_at": stamp,
}) + "\n")
(post_project / "other.json").write_text(json.dumps({"imported_at": stamp}) + "\n")
post_after = root / "post-after.json"
post_snapshot = cr["snapshot"](manifest_path, "l1-postconditions", post_project)
write_json(post_after, post_snapshot)
post_case = cr["read_case"](manifest, "l1-postconditions")
verdict, evidence, evidence_sha = cr["evaluate_postconditions"](
    post_case, "l1-postconditions", post_project, post_after,
)
assert verdict == "PASS" and len(evidence) == 8
assert evidence_sha == hashlib.sha256(cr["canonical_json"](evidence)).hexdigest()
assert str(post_project) not in cr["canonical_json"](evidence).decode()
assert not cr["json_identical"]({"nested": [1]}, {"nested": [True]})

# Postconditions must remain bound to the authenticated AFTER snapshot even
# when every corresponding live source is removed, edited, extended, or
# replaced after the snapshot has been persisted.
(post_project / "input.txt").unlink()
(post_project / "bundle/sub/b.txt").write_text("live substitution\n")
(post_project / "bundle/live-extra.txt").write_text("live extra\n")
(post_project / "empty-bundle/live-extra.txt").write_text("no longer empty live\n")
(post_project / "state.json").write_text("{}\n")
live_verdict, live_evidence, live_evidence_sha = cr["evaluate_postconditions"](
    post_case, "l1-postconditions", post_project, post_after,
)
assert live_verdict == verdict
assert live_evidence == evidence
assert live_evidence_sha == evidence_sha


def post_refused(mutator, expected):
    mutant = copy.deepcopy(post_snapshot)
    mutator(mutant)
    path = root / "post-mutant.json"
    write_json(path, mutant)
    try:
        cr["evaluate_postconditions"](post_case, "l1-postconditions", post_project, path)
    except cr["HarnessError"] as exc:
        assert str(exc).startswith(expected), (expected, str(exc))
    else:
        raise AssertionError(f"postcondition attack survived: {expected}")


post_refused(lambda s: s["entries"]["state.json"]["json"].__setitem__("counter", 1), "HARNESS_POSTCONDITION_VALUE:")
post_refused(lambda s: s["entries"]["state.json"]["json"].__setitem__("counter", False), "HARNESS_POSTCONDITION_VALUE:")
post_refused(lambda s: s["entries"]["state.json"]["json"].pop("counter"), "HARNESS_POSTCONDITION_VALUE:")
post_refused(lambda s: s["entries"]["state.json"].pop("json"), "HARNESS_POSTCONDITION_JSON:")
post_refused(lambda s: s["entries"]["state.json"].update(type="symlink", target="foreign"), "HARNESS_SNAPSHOT_SYMLINK:")
post_refused(lambda s: s["entries"]["input.txt"].__setitem__("sha256", "0" * 64), "HARNESS_POSTCONDITION_DIGEST:")
post_refused(lambda s: s["entries"].pop("input.txt"), "HARNESS_SNAPSHOT_PATH_MISSING:")
post_refused(lambda s: s["entries"]["input.txt"].update(type="directory"), "HARNESS_POSTCONDITION_SOURCE_TYPE:")
post_refused(lambda s: s["entries"]["input.txt"].update(type="symlink", target="foreign"), "HARNESS_SNAPSHOT_SYMLINK:")
post_refused(lambda s: s["entries"]["bundle"].update(type="special"), "HARNESS_POSTCONDITION_SOURCE_TYPE:")
post_refused(lambda s: s["entries"]["bundle/a.txt"].__setitem__("sha256", "0" * 64), "HARNESS_POSTCONDITION_DIGEST:")
post_refused(lambda s: s["entries"].__setitem__("bundle/added.txt", {
    "path": "bundle/added.txt", "mode": "0644", "type": "file",
    "sha256": "1" * 64, "size": 1,
}), "HARNESS_POSTCONDITION_DIGEST:")
post_refused(lambda s: s["entries"].pop("bundle/sub/b.txt"), "HARNESS_POSTCONDITION_DIGEST:")
post_refused(lambda s: s["entries"]["bundle/sub/b.txt"].update(type="symlink", target="foreign"), "HARNESS_DESCRIPTOR_PATH_TYPE:")
post_refused(lambda s: s["entries"]["state.json"]["json"].__setitem__("bundle_digest", "2" * 64), "HARNESS_POSTCONDITION_DIGEST:")
post_refused(lambda s: (
    s["entries"]["state.json"]["json"].__setitem__("input_sha256", input_sha.upper()),
    s["entries"]["input.txt"].__setitem__("sha256", input_sha.upper()),
), "HARNESS_DESCRIPTOR_DIGEST:")
post_refused(lambda s: s["entries"]["state.json"]["json"].__setitem__("imported_at", "2026-08-28T12:00:00-04:00"), "HARNESS_POSTCONDITION_UTC:")
post_refused(lambda s: s["entries"]["state.json"]["json"].__setitem__("imported_at", "2026-08-28T12:00:00-00:00"), "HARNESS_POSTCONDITION_UTC:")
post_refused(lambda s: s["entries"]["state.json"]["json"].__setitem__("imported_at", "not-a-time"), "HARNESS_POSTCONDITION_UTC:")
post_refused(lambda s: s["entries"]["other.json"]["json"].__setitem__("imported_at", "2026-08-28T13:00:00+00:00"), "HARNESS_POSTCONDITION_EQUALITY:")

for bad in (
    [{"kind": "shell_callback", "path": "state.json", "pointer": ""}],
    [{"kind": "json_exact", "path": "../state.json", "pointer": "", "value": {}}],
    [{"kind": "json_exact", "path": "state.json", "pointer": "/bad~2pointer", "value": 0}],
    [{"kind": "json_digest_equals_path", "path": "state.json", "pointer": "/bundle_digest", "source_path": "../bundle", "source_type": "directory"}],
    [{"kind": "json_digest_equals_path", "path": "state.json", "pointer": "/bundle_digest", "source_path": "bundle"}],
    [{"kind": "json_digest_equals_path", "path": "state.json", "pointer": "/bundle_digest", "source_path": "bundle", "source_type": "special"}],
):
    try:
        cr["validate_postcondition_schema"](bad, "attack")
    except cr["HarnessError"]:
        pass
    else:
        raise AssertionError(f"invalid postcondition schema accepted: {bad!r}")

# Descriptor globbing is byte-for-byte aligned with production's default
# glob.glob(...): no recursive **, no slash-spanning *, and no implicit hidden
# matches. Directories are included and duplicate pattern hits are deduplicated.
glob_project = root / "glob project"
for relative, payload in {
    "data/a.csv": "a", "data/sub/b.csv": "b", "data/sub/deep/c.csv": "c",
    "data/.hidden.csv": "h", "data/.hidden/d.csv": "hd", "user_request": "request",
}.items():
    target = glob_project / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(payload)
glob_snapshot = cr["snapshot"](manifest_path, "l1-typed-descriptor", glob_project)
pattern_map = cr["snapshot_pattern_map"]
assert set(pattern_map(glob_snapshot, ["data/*"], required=True)) == {"data/a.csv", "data/sub"}
assert set(pattern_map(glob_snapshot, ["data/**/*.csv"], required=True)) == {"data/sub/b.csv"}
assert set(pattern_map(glob_snapshot, ["data/**"], required=True)) == {"data/a.csv", "data/sub"}
assert set(pattern_map(glob_snapshot, ["data/.*"], required=True)) == {"data/.hidden", "data/.hidden.csv"}
assert set(pattern_map(glob_snapshot, ["user_request"], required=False)) == {"user_request"}
assert len(pattern_map(glob_snapshot, ["data/*", "data/*"], required=True)) == 2
assert "data/sub" in pattern_map(glob_snapshot, ["data/sub"], required=True)

for payload in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}', '{"a":-Infinity}'):
    try:
        cr["strict_json_loads"](payload, "attack")
    except cr["HarnessError"] as exc:
        assert str(exc).startswith("HARNESS_JSON_INVALID:")
    else:
        raise AssertionError(f"non-strict JSON accepted: {payload}")
try:
    cr["canonical_json"]({"value": float("nan")})
except cr["HarnessError"] as exc:
    assert str(exc).startswith("HARNESS_JSON_INVALID:")
else:
    raise AssertionError("non-finite canonical JSON accepted")
strict_file = root / "strict.json"
strict_file.write_text('{"a":1,"a":2}\n')
try:
    cr["load_json"](strict_file)
except cr["HarnessError"] as exc:
    assert str(exc).startswith("HARNESS_JSON_INVALID:")
else:
    raise AssertionError("duplicate-key JSON file accepted")
bool_manifest = copy.deepcopy(manifest)
bool_manifest["cases"]["l1-happy-pass"]["expected_exit"]["value"] = True
try:
    cr["read_case"](bool_manifest, "l1-happy-pass")
except cr["HarnessError"] as exc:
    assert str(exc).startswith("HARNESS_CASE_SCHEMA:")
else:
    raise AssertionError("boolean expected_exit accepted")

sha_a, sha_b = "a" * 64, "b" * 64
binding = (
    "operator=source_roles,target_matches=1,changed=scripts/auto-research-verify.sh,"
    f"before={sha_a},after={sha_b}"
)
for case_id, verdict in (
    ("l3.source_roles.pristine_positive", f"pristine:{sha_a}"),
    ("l3.source_roles.pristine_negative", f"pristine:{sha_a}"),
    ("l3.source_roles.mutant_valid", f"valid_control:{binding}"),
    ("l3.source_roles.mutant_kill", f"killed:{binding}"),
):
    assert cr["validate_mutation_verdict"](case_id, verdict) is not None
for case_id, verdict in (
    ("l1-happy-pass", "PASS"),
    ("l1-happy-pass", f"pristine:{sha_a}"),
    ("l3.source_roles.pristine_positive", "pristine:arbitrary"),
    ("l3.source_roles.mutant_valid", "valid_control:arbitrary"),
    ("l3.source_roles.mutant_valid", f"valid_control:{binding.replace('source_roles', 'other', 1)}"),
    ("l3.source_roles.mutant_kill", f"killed:{binding.replace('after=' + sha_b, 'after=' + sha_a)}"),
):
    try:
        cr["validate_mutation_verdict"](case_id, verdict)
    except cr["HarnessError"] as exc:
        assert str(exc).startswith("HARNESS_RESULT_MUTATION:")
    else:
        raise AssertionError(f"mutation verdict attack survived: {case_id} {verdict}")

print("PASS: strict descriptor/glob/postcondition/mutation attack matrix")
PY

# Completeness is derived from this test's bound path/runner, not from static
# anchors or caller-selected IDs. Wrong bindings and malformed ceilings refuse.
CLOSURE_OUTPUT="$OUTER_ROOT/output-l1-result-closure"
(
  export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR"
  export SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
  export SCHOLAR_HARNESS_RESULTS_DIR="$OUTER_ROOT/results-l1-result-closure"
  export SCHOLAR_HARNESS_RUN_ID="run-l1-result-closure"
  export SCHOLAR_HARNESS_RUN_NONCE="nonce-l1-result-closure"
  export SCHOLAR_HARNESS_SUITE_MODE="self-test"
  export SCHOLAR_HARNESS_SUITE_ORDER="normal"
  export SCHOLAR_HARNESS_MANIFEST_SHA256="$MANIFEST_SHA"
  export SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$SOURCE_SHA"
  source "$HARNESS"
  harness_init "$SELF" "l1-result-closure" || exit 91
  harness_make_temp_root WORK_ROOT "owned result closure" || exit 92
  mkdir -p "$WORK_ROOT/project"
  printf '%s\n' '{"counter":0}' > "$WORK_ROOT/project/state.json"
  expect_pass l1-result-closure "$WORK_ROOT/project" -- bash "$SELF" fixture pass "$WORK_ROOT/project" >/dev/null || exit 93
  harness_validate_results >/dev/null || exit 94

  set +e
  wrong_path="$(python3 "$HELPER" validate-results --result-dir "$SCHOLAR_HARNESS_RESULTS_DIR" \
    --capability "$_HARNESS_CAPABILITY" --test-path "$HARNESS" \
    --runner-label l1-result-closure --phase-through 20 2>&1)"
  wrong_path_rc=$?
  wrong_runner="$(python3 "$HELPER" validate-results --result-dir "$SCHOLAR_HARNESS_RESULTS_DIR" \
    --capability "$_HARNESS_CAPABILITY" --test-path "$SELF" \
    --runner-label spoofed-runner --phase-through 20 2>&1)"
  wrong_runner_rc=$?
  malformed="$(harness_validate_results --phase-through nope 2>&1)"
  malformed_rc=$?
  set -e
  [ "$wrong_path_rc" -ne 0 ] && [ "$wrong_runner_rc" -ne 0 ] && [ "$malformed_rc" -ne 0 ] || exit 95
  echo "$wrong_path"
  echo "$wrong_runner"
  echo "$malformed"

  rm "$SCHOLAR_HARNESS_RESULTS_DIR/l1-result-closure.json"
  set +e
  missing="$(harness_validate_results 2>&1)"
  missing_rc=$?
  set -e
  [ "$missing_rc" -ne 0 ] || exit 96
  echo "$missing"
) >"$CLOSURE_OUTPUT" 2>&1 || {
  sed -n '1,240p' "$CLOSURE_OUTPUT" >&2
  fail "manifest-derived result-closure scenario failed"
}
grep -F 'HARNESS_EXPECTED_CASE_SET_EMPTY: tests/helpers/harness.sh:l1-result-closure:phase-through=20' "$CLOSURE_OUTPUT" >/dev/null \
  || fail "wrong test path did not fail closed"
grep -F 'HARNESS_EXPECTED_CASE_SET_EMPTY: tests/smoke/test-harness.sh:spoofed-runner:phase-through=20' "$CLOSURE_OUTPUT" >/dev/null \
  || fail "wrong runner label did not fail closed"
grep -F "HARNESS_PHASE_THROUGH_INVALID: 'nope'" "$CLOSURE_OUTPUT" >/dev/null \
  || fail "malformed phase ceiling did not fail closed"
grep -F 'HARNESS_RESULT_MISSING: l1-result-closure' "$CLOSURE_OUTPUT" >/dev/null \
  || fail "deleted valid result record was not detected"

# Ordered checkpoints exclude tagged cases from phase ceilings, include them at
# their registered checkpoint, and revalidate authenticated terminal semantics.
CHECKPOINT_OUTPUT="$OUTER_ROOT/output-l1-checkpoint"
(
  export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR"
  export SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
  export SCHOLAR_HARNESS_RESULTS_DIR="$OUTER_ROOT/results-l1-checkpoint"
  export SCHOLAR_HARNESS_RUN_ID="run-l1-checkpoint"
  export SCHOLAR_HARNESS_RUN_NONCE="nonce-l1-checkpoint"
  export SCHOLAR_HARNESS_SUITE_MODE="self-test"
  export SCHOLAR_HARNESS_SUITE_ORDER="normal"
  export SCHOLAR_HARNESS_MANIFEST_SHA256="$MANIFEST_SHA"
  export SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$SOURCE_SHA"
  source "$HARNESS"
  harness_init "$SELF" "l1-checkpoint-suite" || exit 91
  [ -z "${SCHOLAR_HARNESS_CAPABILITY:-}" ] || exit 92
  export CHECKPOINT_CAPABILITY_ALIAS="$_HARNESS_CAPABILITY"
  capability_shell_function() {
    [ -z "${SCHOLAR_HARNESS_CAPABILITY+x}" ] \
      && [ -z "${_HARNESS_CAPABILITY+x}" ] \
      && [ -z "${CHECKPOINT_CAPABILITY_ALIAS+x}" ]
  }
  harness_make_temp_root WORK_ROOT "owned checkpoint root" || exit 93
  mkdir -p "$WORK_ROOT/project"
  printf '%s\n' '{"counter":0}' > "$WORK_ROOT/project/state.json"
  expect_pass l1-checkpoint-base "$WORK_ROOT/project" -- capability_shell_function >/dev/null || exit 94
  harness_validate_results --phase-through 20 | grep -F 'HARNESS_RESULT_RECORDS=1' >/dev/null || exit 95

  set +e
  missing="$(harness_validate_results --checkpoint state-tail 2>&1)"
  missing_rc=$?
  unknown="$(harness_validate_results --checkpoint absent 2>&1)"
  unknown_rc=$?
  ambiguous="$(python3 "$HELPER" validate-results --result-dir "$SCHOLAR_HARNESS_RESULTS_DIR" \
    --capability "$_HARNESS_CAPABILITY" --test-path "$SELF" --runner-label l1-checkpoint-suite \
    --phase-through 20 --checkpoint state-tail 2>&1)"
  ambiguous_rc=$?
  set -e
  [ "$missing_rc" -ne 0 ] && [ "$unknown_rc" -ne 0 ] && [ "$ambiguous_rc" -ne 0 ] || exit 96
  echo "$missing"
  echo "$unknown"
  echo "$ambiguous"

  expect_pass l1-checkpoint-tail "$WORK_ROOT/project" -- bash "$SELF" fixture pass "$WORK_ROOT/project" >/dev/null || exit 97
  harness_validate_results --checkpoint state-tail | grep -F 'HARNESS_RESULT_RECORDS=2' >/dev/null || exit 98
  harness_validate_results | grep -F 'HARNESS_RESULT_RECORDS=2' >/dev/null || exit 99

  record="$SCHOLAR_HARNESS_RESULTS_DIR/l1-checkpoint-base.json"
  cp "$record" "$WORK_ROOT/original-record.json"
  remac_mutation() {
    local field="$1" value_json="$2"
    python3 - "$WORK_ROOT/original-record.json" "$record" "$_HARNESS_CAPABILITY" "$field" "$value_json" <<'PY'
import hashlib, hmac, json, sys
source, target, capability, field, value_json = sys.argv[1:]
record = json.load(open(source))
record[field] = json.loads(value_json)
record.pop("record_mac_sha256", None)
payload = (json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
record["record_mac_sha256"] = hmac.new(capability.encode(), payload, hashlib.sha256).hexdigest()
with open(target, "w", encoding="utf-8") as handle:
    json.dump(record, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY
  }
  semantic_refusal() {
    local field="$1" value_json="$2" expected="$3" output rc
    remac_mutation "$field" "$value_json"
    set +e
    output="$(harness_validate_results --checkpoint state-tail 2>&1)"
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || exit 100
    printf '%s\n' "$output" | grep -F "$expected" >/dev/null || exit 101
    cp "$WORK_ROOT/original-record.json" "$record"
  }
  semantic_refusal terminal_status '"FAIL"' 'HARNESS_RESULT_TERMINAL: l1-checkpoint-base'
  semantic_refusal state_delta_verdict '"FAIL"' 'HARNESS_RESULT_STATE_DELTA: l1-checkpoint-base'
  semantic_refusal mutation_verdict '"FAIL"' 'HARNESS_RESULT_MUTATION: l1-checkpoint-base'
  semantic_refusal transcript_verdict '"FAIL"' 'HARNESS_RESULT_TRANSCRIPT: l1-checkpoint-base'
  semantic_refusal postcondition_verdict '"FAIL"' 'HARNESS_RESULT_POSTCONDITION: l1-checkpoint-base'
  semantic_refusal observed_exit '1' 'HARNESS_RESULT_EXIT: l1-checkpoint-base'
  semantic_refusal observed_exit 'true' 'HARNESS_RECORD_SCHEMA: l1-checkpoint-base.json: observed_exit'
  semantic_refusal observed_exact_diagnostic_count 'false' 'HARNESS_RECORD_SCHEMA: l1-checkpoint-base.json: observed_exact_diagnostic_count'
  semantic_refusal observed_exact_diagnostic '"forged"' 'HARNESS_RESULT_DIAGNOSTIC: l1-checkpoint-base'
  semantic_refusal suite_mode '"forged-mode"' 'HARNESS_RESULT_STALE: l1-checkpoint-base: suite_mode'
  semantic_refusal suite_order '"forged-order"' 'HARNESS_RESULT_STALE: l1-checkpoint-base: suite_order'
  semantic_refusal recorded_at '"2026-08-28T12:00:00-00:00"' 'HARNESS_RECORD_SCHEMA: l1-checkpoint-base: recorded_at'
  semantic_refusal postcondition_evidence_sha256 '"0000000000000000000000000000000000000000000000000000000000000000"' 'HARNESS_RESULT_POSTCONDITION_EVIDENCE: l1-checkpoint-base'

  # Any unauthenticated field/evidence change, deletion, or cross-case replay
  # is rejected at the MAC boundary before semantic fields are trusted.
  python3 - "$record" <<'PY'
import json, sys
path = sys.argv[1]
record = json.load(open(path))
record["terminal_status"] = "FAIL"
json.dump(record, open(path, "w"), sort_keys=True)
PY
  set +e
  mac_flip="$(harness_validate_results --checkpoint state-tail 2>&1)"; mac_flip_rc=$?
  set -e
  [ "$mac_flip_rc" -ne 0 ] && printf '%s\n' "$mac_flip" | grep -F 'HARNESS_RESULT_MAC: l1-checkpoint-base.json' >/dev/null || exit 102
  cp "$WORK_ROOT/original-record.json" "$record"
  for attack in evidence stdout cross_case; do
    python3 - "$record" "$attack" <<'PY'
import json, sys
path, attack = sys.argv[1:]
record = json.load(open(path))
if attack == "evidence":
    record["postcondition_evidence"] = [{"kind": "forged"}]
elif attack == "stdout":
    record["stdout_sha256"] = "0" * 64
else:
    record["case_id"] = "l1-checkpoint-tail"
json.dump(record, open(path, "w"), sort_keys=True)
PY
    set +e
    attack_output="$(harness_validate_results --checkpoint state-tail 2>&1)"; attack_rc=$?
    set -e
    [ "$attack_rc" -ne 0 ] && printf '%s\n' "$attack_output" | grep -F 'HARNESS_RESULT_MAC: l1-checkpoint-base.json' >/dev/null || exit 107
    cp "$WORK_ROOT/original-record.json" "$record"
  done
  python3 - "$record" <<'PY'
import json, sys
path = sys.argv[1]
record = json.load(open(path)); record.pop("record_mac_sha256")
json.dump(record, open(path, "w"), sort_keys=True)
PY
  set +e
  mac_missing="$(harness_validate_results --checkpoint state-tail 2>&1)"; mac_missing_rc=$?
  set -e
  [ "$mac_missing_rc" -ne 0 ] && printf '%s\n' "$mac_missing" | grep -F 'HARNESS_RESULT_MAC: l1-checkpoint-base.json' >/dev/null || exit 103
  cp "$WORK_ROOT/original-record.json" "$record"
  harness_validate_results --checkpoint state-tail >/dev/null || exit 104

  # Strict decoding precedes authentication, so duplicate keys/non-finite
  # constants and special result/context files refuse without blocking reads.
  python3 - "$WORK_ROOT/original-record.json" "$record" duplicate <<'PY'
import sys
source, target, attack = sys.argv[1:]
text = open(source, encoding="utf-8").read().rstrip()
assert text.endswith("}")
open(target, "w", encoding="utf-8").write(text[:-1] + ',"case_id":"l1-checkpoint-base"}\n')
PY
  set +e
  strict_duplicate="$(harness_validate_results --checkpoint state-tail 2>&1)"; strict_duplicate_rc=$?
  set -e
  [ "$strict_duplicate_rc" -ne 0 ] && printf '%s\n' "$strict_duplicate" | grep -F 'HARNESS_JSON_INVALID:' >/dev/null || exit 108
  python3 - "$WORK_ROOT/original-record.json" "$record" <<'PY'
import sys
source, target = sys.argv[1:]
text = open(source, encoding="utf-8").read()
needle = '"observed_exit":0'
assert text.count(needle) == 1
open(target, "w", encoding="utf-8").write(text.replace(needle, '"observed_exit":NaN'))
PY
  set +e
  strict_nan="$(harness_validate_results --checkpoint state-tail 2>&1)"; strict_nan_rc=$?
  set -e
  [ "$strict_nan_rc" -ne 0 ] && printf '%s\n' "$strict_nan" | grep -F 'HARNESS_JSON_INVALID:' >/dev/null || exit 109
  cp "$WORK_ROOT/original-record.json" "$record"

  mv "$record" "$WORK_ROOT/regular-record.json"
  ln -s "$WORK_ROOT/regular-record.json" "$record"
  set +e
  symlink_result="$(harness_validate_results --checkpoint state-tail 2>&1)"; symlink_result_rc=$?
  set -e
  [ "$symlink_result_rc" -ne 0 ] && printf '%s\n' "$symlink_result" | grep -F 'HARNESS_FILE_INVALID:' >/dev/null || exit 110
  rm "$record"; mv "$WORK_ROOT/regular-record.json" "$record"

  mv "$record" "$WORK_ROOT/regular-record.json"
  mkfifo "$record"
  python3 - "$HELPER" "$SCHOLAR_HARNESS_RESULTS_DIR" "$_HARNESS_CAPABILITY" "$SELF" <<'PY'
import subprocess, sys
helper, result_dir, capability, test_path = sys.argv[1:]
command = [
    "python3", helper, "validate-results", "--result-dir", result_dir,
    "--capability", capability, "--test-path", test_path,
    "--runner-label", "l1-checkpoint-suite", "--checkpoint", "state-tail",
]
try:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=3)
except subprocess.TimeoutExpired:
    raise SystemExit("FIFO result validation blocked")
assert result.returncode != 0 and "HARNESS_FILE_INVALID:" in result.stdout, result.stdout
PY
  rm "$record"; mv "$WORK_ROOT/regular-record.json" "$record"

  context="$SCHOLAR_HARNESS_RESULTS_DIR/.run-context.json"
  mv "$context" "$WORK_ROOT/regular-context.json"
  ln -s "$WORK_ROOT/regular-context.json" "$context"
  set +e
  symlink_context="$(harness_validate_results --checkpoint state-tail 2>&1)"; symlink_context_rc=$?
  set -e
  [ "$symlink_context_rc" -ne 0 ] && printf '%s\n' "$symlink_context" | grep -F 'HARNESS_FILE_INVALID:' >/dev/null || exit 111
  rm "$context"; mv "$WORK_ROOT/regular-context.json" "$context"
  harness_validate_results --checkpoint state-tail >/dev/null || exit 112

  # A record from this run cannot be replayed under a freshly keyed run.
  replay_dir="$OUTER_ROOT/results-l1-checkpoint-replay"
  replay_cap="$(python3 "$HELPER" init-run --result-dir "$replay_dir" --source-root "$SKILL_DIR" \
    --manifest "$MANIFEST" --run-id replay --run-nonce replay --suite-mode self-test --suite-order normal \
    --manifest-sha256 "$MANIFEST_SHA" --source-generation-sha256 "$SOURCE_SHA")" || exit 105
  cp "$WORK_ROOT/original-record.json" "$replay_dir/l1-checkpoint-base.json"
  set +e
  replay="$(python3 "$HELPER" validate-results --result-dir "$replay_dir" --capability "$replay_cap" \
    --test-path "$SELF" --runner-label l1-checkpoint-suite --phase-through 20 2>&1)"; replay_rc=$?
  set -e
  [ "$replay_rc" -ne 0 ] && printf '%s\n' "$replay" | grep -F 'HARNESS_RESULT_MAC: l1-checkpoint-base.json' >/dev/null || exit 106
) >"$CHECKPOINT_OUTPUT" 2>&1 || {
  sed -n '1,280p' "$CHECKPOINT_OUTPUT" >&2
  fail "checkpoint/authenticated join scenario failed"
}
grep -F 'HARNESS_RESULT_MISSING: l1-checkpoint-tail' "$CHECKPOINT_OUTPUT" >/dev/null \
  || fail "synthetic checkpoint did not report its exact missing case"
grep -F 'HARNESS_CHECKPOINT_UNKNOWN: absent' "$CHECKPOINT_OUTPUT" >/dev/null \
  || fail "unknown checkpoint did not fail closed"
grep -F 'HARNESS_SELECTOR_AMBIGUOUS:' "$CHECKPOINT_OUTPUT" >/dev/null \
  || fail "ambiguous checkpoint selector did not fail closed"

# Two concurrent assertions for the same ID must publish exactly one record.
DUP_RESULTS="$OUTER_ROOT/results-l1-duplicate"
DUP_OUTPUT="$OUTER_ROOT/output-l1-duplicate"
(
  export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR"
  export SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
  export SCHOLAR_HARNESS_RESULTS_DIR="$DUP_RESULTS"
  export SCHOLAR_HARNESS_RUN_ID="run-l1-duplicate"
  export SCHOLAR_HARNESS_RUN_NONCE="nonce-l1-duplicate"
  export SCHOLAR_HARNESS_SUITE_MODE="self-test"
  export SCHOLAR_HARNESS_SUITE_ORDER="concurrent"
  export SCHOLAR_HARNESS_MANIFEST_SHA256="$MANIFEST_SHA"
  export SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$SOURCE_SHA"
  source "$HARNESS"
  harness_init "$SELF" "l1-duplicate" || exit 91
  harness_make_temp_root WORK_ROOT "owned duplicate's root" || exit 92
  mkdir -p "$WORK_ROOT/project"
  printf '%s\n' '{"counter":0}' > "$WORK_ROOT/project/state.json"
  (expect_pass l1-duplicate "$WORK_ROOT/project" -- bash "$SELF" fixture pass "$WORK_ROOT/project" >"$WORK_ROOT/a.out" 2>&1; echo $? >"$WORK_ROOT/a.rc") &
  pid_a=$!
  (expect_pass l1-duplicate "$WORK_ROOT/project" -- bash "$SELF" fixture pass "$WORK_ROOT/project" >"$WORK_ROOT/b.out" 2>&1; echo $? >"$WORK_ROOT/b.rc") &
  pid_b=$!
  wait "$pid_a"
  wait "$pid_b"
  rc_a="$(cat "$WORK_ROOT/a.rc")"
  rc_b="$(cat "$WORK_ROOT/b.rc")"
  case "$rc_a:$rc_b" in 0:1|1:0) ;; *) exit 95 ;; esac
  cat "$WORK_ROOT/a.out" "$WORK_ROOT/b.out"
  harness_validate_results | grep -F 'HARNESS_RESULT_RECORDS=1' >/dev/null || exit 96
) >"$DUP_OUTPUT" 2>&1 || {
  sed -n '1,220p' "$DUP_OUTPUT" >&2
  fail "atomic duplicate scenario failed"
}
grep -F 'HARNESS_DUPLICATE_CASE: l1-duplicate' "$DUP_OUTPUT" >/dev/null \
  || fail "duplicate case did not produce exact refusal"

# Direct-file preemption cannot reserve a case ID, and a suppressed failed
# assertion remains an authenticated FAIL that both checkpoint/final joins reject.
PREEMPT_OUTPUT="$OUTER_ROOT/output-l1-preempt"
(
  export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR" SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
  export SCHOLAR_HARNESS_RESULTS_DIR="$OUTER_ROOT/results-l1-preempt"
  export SCHOLAR_HARNESS_RUN_ID=preempt SCHOLAR_HARNESS_RUN_NONCE=preempt
  export SCHOLAR_HARNESS_SUITE_MODE=self-test SCHOLAR_HARNESS_SUITE_ORDER=normal
  export SCHOLAR_HARNESS_MANIFEST_SHA256="$MANIFEST_SHA" SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$SOURCE_SHA"
  source "$HARNESS"; harness_init "$SELF" l1-preempt || exit 91
  harness_make_temp_root WORK_ROOT "owned preemption root" || exit 92
  mkdir -p "$WORK_ROOT/project"; printf '%s\n' '{"counter":0}' > "$WORK_ROOT/project/state.json"
  printf '%s\n' '{"case_id":"l1-preempt","terminal_status":"PASS"}' > "$SCHOLAR_HARNESS_RESULTS_DIR/l1-preempt.json" # HARNESS_LINT_NEGATIVE_CONTROL
  set +e
  assertion="$(expect_pass l1-preempt "$WORK_ROOT/project" -- bash "$SELF" fixture pass "$WORK_ROOT/project" 2>&1)"; assertion_rc=$?
  join="$(harness_validate_results 2>&1)"; join_rc=$?
  set -e
  [ "$assertion_rc" -ne 0 ] && [ "$join_rc" -ne 0 ] || exit 93
  echo "$assertion"; echo "$join"
) >"$PREEMPT_OUTPUT" 2>&1 || {
  sed -n '1,220p' "$PREEMPT_OUTPUT" >&2
  fail "direct-file preemption scenario failed"
}
grep -F 'HARNESS_DUPLICATE_CASE: l1-preempt' "$PREEMPT_OUTPUT" >/dev/null \
  || fail "preempted case did not refuse atomic publication"
grep -F 'HARNESS_RESULT_MAC: l1-preempt.json' "$PREEMPT_OUTPUT" >/dev/null \
  || fail "forged valid-looking result did not fail at MAC boundary"

SUPPRESSED_OUTPUT="$OUTER_ROOT/output-l1-suppressed"
(
  export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR" SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
  export SCHOLAR_HARNESS_RESULTS_DIR="$OUTER_ROOT/results-l1-suppressed"
  export SCHOLAR_HARNESS_RUN_ID=suppressed SCHOLAR_HARNESS_RUN_NONCE=suppressed
  export SCHOLAR_HARNESS_SUITE_MODE=self-test SCHOLAR_HARNESS_SUITE_ORDER=normal
  export SCHOLAR_HARNESS_MANIFEST_SHA256="$MANIFEST_SHA" SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$SOURCE_SHA"
  source "$HARNESS"; harness_init "$SELF" l1-suppressed-tail || exit 91
  harness_make_temp_root WORK_ROOT "owned suppressed root" || exit 92
  mkdir -p "$WORK_ROOT/project"; printf '%s\n' '{"counter":0}' > "$WORK_ROOT/project/state.json"
  expect_pass l1-suppressed-tail "$WORK_ROOT/project" -- bash "$SELF" fixture wrong-exit "$WORK_ROOT/project" >/dev/null 2>&1 || true
  set +e
  checkpoint="$(harness_validate_results --checkpoint state-tail 2>&1)"; checkpoint_rc=$?
  final="$(harness_validate_results 2>&1)"; final_rc=$?
  set -e
  [ "$checkpoint_rc" -ne 0 ] && [ "$final_rc" -ne 0 ] || exit 93
  echo "$checkpoint"; echo "$final"
) >"$SUPPRESSED_OUTPUT" 2>&1 || {
  sed -n '1,220p' "$SUPPRESSED_OUTPUT" >&2
  fail "suppressed FAIL-record scenario failed"
}
[ "$(grep -c 'HARNESS_RESULT_EXIT: l1-suppressed-tail' "$SUPPRESSED_OUTPUT")" -eq 2 ] \
  || fail "checkpoint and final joins did not both reject suppressed failure"

# The recorder cannot be called directly, even with syntactically complete arguments.
set +e
DIRECT_OUT="$(HARNESS_LINT_NEGATIVE_CONTROL=1 python3 "$HELPER" record \
  --result-dir "$OUTER_ROOT/results-l1-happy-pass" --capability bogus \
  --case-id l1-happy-pass --test-path "$SELF" --runner-label harness-self-test \
  --project-root /tmp --after /dev/null \
  --observed-exit 0 --observed-exact-diagnostic '' \
  --diagnostic-count 0 \
  --stdout-file /dev/null --stderr-file /dev/null \
  --stdout-sha256 "$SOURCE_SHA" --stderr-sha256 "$SOURCE_SHA" \
  --mutation-verdict not_applicable --state-delta-verdict PASS --terminal-status PASS 2>&1)"
DIRECT_RC=$?
set -e
[ "$DIRECT_RC" -ne 0 ] || fail "direct recorder call succeeded"
[ "$DIRECT_OUT" = "HARNESS_DIRECT_RECORD_FORBIDDEN: recorder is callable only through harness assertions" ] \
  || fail "direct recorder refusal changed: $DIRECT_OUT"

# Coordinator source and manifest bindings fail before any case can run.
binding_refusal() {
  local which="$1" expected="$2" result_dir output
  result_dir="$OUTER_ROOT/binding-$which"
  set +e
  output="$({
    export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR"
    export SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
    export SCHOLAR_HARNESS_RESULTS_DIR="$result_dir"
    export SCHOLAR_HARNESS_RUN_ID="binding-$which"
    export SCHOLAR_HARNESS_RUN_NONCE="binding-$which"
    export SCHOLAR_HARNESS_SUITE_MODE="self-test"
    export SCHOLAR_HARNESS_SUITE_ORDER="normal"
    export SCHOLAR_HARNESS_MANIFEST_SHA256="$MANIFEST_SHA"
    export SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$SOURCE_SHA"
    if [ "$which" = "source" ]; then SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$(printf '0%.0s' {1..64})"; fi
    if [ "$which" = "manifest" ]; then SCHOLAR_HARNESS_MANIFEST_SHA256="$(printf '0%.0s' {1..64})"; fi
    source "$HARNESS"
    harness_init "$SELF" harness-self-test
  } 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "$which binding mismatch succeeded"
  case "$output" in *"$expected"*) ;; *) fail "$which binding refusal changed: $output" ;; esac
}
binding_refusal source "HARNESS_SOURCE_BINDING"
binding_refusal manifest "HARNESS_MANIFEST_BINDING"

# The capability-validated context binds the canonical reviewed-source map.
CONTEXT_RESULTS="$OUTER_ROOT/reviewed-context-results"
CONTEXT_CAP="$(python3 "$HELPER" init-run --result-dir "$CONTEXT_RESULTS" \
  --source-root "$SKILL_DIR" --manifest "$MANIFEST" --run-id reviewed-context --run-nonce reviewed-context \
  --suite-mode self-test --suite-order normal --manifest-sha256 "$MANIFEST_SHA" \
  --source-generation-sha256 "$SOURCE_SHA")" || fail "reviewed context setup failed"
python3 - "$CONTEXT_RESULTS/.run-context.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["reviewed_test_sources_sha256"] = "0" * 64
path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
set +e
CONTEXT_OUT="$(python3 "$HELPER" check-run --result-dir "$CONTEXT_RESULTS" --capability "$CONTEXT_CAP" \
  --run-id reviewed-context --run-nonce reviewed-context --suite-mode self-test --suite-order normal \
  --manifest-sha256 "$MANIFEST_SHA" --source-generation-sha256 "$SOURCE_SHA" 2>&1)"
CONTEXT_RC=$?
set -e
[ "$CONTEXT_RC" -ne 0 ] || fail "reviewed context projection mutation survived"
case "$CONTEXT_OUT" in *"HARNESS_REVIEWED_SOURCE_CONTEXT"*) ;; *) fail "wrong reviewed context diagnostic: $CONTEXT_OUT" ;; esac

SWAP_RESULTS="$OUTER_ROOT/reviewed-swap-results"
SWAP_CAP="$(python3 "$HELPER" init-run --result-dir "$SWAP_RESULTS" \
  --source-root "$SKILL_DIR" --manifest "$MANIFEST" --run-id reviewed-swap --run-nonce reviewed-swap \
  --suite-mode self-test --suite-order normal --manifest-sha256 "$MANIFEST_SHA" \
  --source-generation-sha256 "$SOURCE_SHA")" || fail "reviewed swap setup failed"
cp "$SELF" "$OUTER_ROOT/reviewed-self.original"
printf '\n# post-init reviewed source swap\n' >> "$SELF"
set +e
SWAP_OUT="$(python3 "$HELPER" check-run --result-dir "$SWAP_RESULTS" --capability "$SWAP_CAP" \
  --run-id reviewed-swap --run-nonce reviewed-swap --suite-mode self-test --suite-order normal \
  --manifest-sha256 "$MANIFEST_SHA" --source-generation-sha256 "$SOURCE_SHA" 2>&1)"
SWAP_RC=$?
set -e
mv "$OUTER_ROOT/reviewed-self.original" "$SELF"
[ "$SWAP_RC" -ne 0 ] || fail "post-init reviewed source swap survived"
case "$SWAP_OUT" in *"HARNESS_SOURCE_BINDING"*|*"HARNESS_REVIEWED_SOURCE_BINDING"*) ;; *) fail "wrong reviewed swap diagnostic: $SWAP_OUT" ;; esac

# A pre-existing result directory is stale by definition.
mkdir "$OUTER_ROOT/preexisting-results"
set +e
PREEXISTING_OUT="$({
  export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR" SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
  export SCHOLAR_HARNESS_RESULTS_DIR="$OUTER_ROOT/preexisting-results"
  export SCHOLAR_HARNESS_RUN_ID=preexisting SCHOLAR_HARNESS_RUN_NONCE=preexisting
  export SCHOLAR_HARNESS_SUITE_MODE=self-test SCHOLAR_HARNESS_SUITE_ORDER=normal
  export SCHOLAR_HARNESS_MANIFEST_SHA256="$MANIFEST_SHA" SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$SOURCE_SHA"
  source "$HARNESS"
  harness_init "$SELF" harness-self-test
} 2>&1)"
PREEXISTING_RC=$?
set -e
[ "$PREEXISTING_RC" -ne 0 ] || fail "pre-existing result directory was reused"
case "$PREEXISTING_OUT" in *"HARNESS_RESULTS_NOT_FRESH"*) ;; *) fail "wrong pre-existing result diagnostic: $PREEXISTING_OUT" ;; esac

# Result validation rejects wrong-run and unexpected records.
STALE_RESULTS="$OUTER_ROOT/stale-results"
STALE_CAP="$(python3 "$HELPER" init-run --result-dir "$STALE_RESULTS" \
  --source-root "$SKILL_DIR" --manifest "$MANIFEST" --run-id stale-run --run-nonce stale-nonce \
  --suite-mode self-test --suite-order normal --manifest-sha256 "$MANIFEST_SHA" \
  --source-generation-sha256 "$SOURCE_SHA")" || fail "stale result context setup failed"
cp "$OUTER_ROOT/results-l1-happy-pass/l1-happy-pass.json" "$STALE_RESULTS/l1-happy-pass.json"
set +e
STALE_OUT="$(python3 "$HELPER" validate-results --result-dir "$STALE_RESULTS" --capability "$STALE_CAP" \
  --test-path "$SELF" --runner-label l1-happy-pass --phase-through 20 2>&1)"
STALE_RC=$?
set -e
[ "$STALE_RC" -ne 0 ] || fail "wrong-run record validated"
case "$STALE_OUT" in *"HARNESS_RESULT_MAC: l1-happy-pass.json"*) ;; *) fail "wrong stale-record diagnostic: $STALE_OUT" ;; esac
mv "$STALE_RESULTS/l1-happy-pass.json" "$OUTER_ROOT/stale-record.checked"
printf '%s\n' '{}' > "$STALE_RESULTS/unexpected.json"
set +e
UNEXPECTED_OUT="$(python3 "$HELPER" validate-results --result-dir "$STALE_RESULTS" --capability "$STALE_CAP" \
  --test-path "$SELF" --runner-label l1-happy-pass --phase-through 20 2>&1)"
UNEXPECTED_RC=$?
set -e
[ "$UNEXPECTED_RC" -ne 0 ] || fail "unexpected record validated"
case "$UNEXPECTED_OUT" in *"HARNESS_RESULT_MAC: unexpected.json"*) ;; *) fail "wrong unexpected-record diagnostic: $UNEXPECTED_OUT" ;; esac

# Caller-shell lifecycle traps clean special-character roots and release mode
# refuses the keep escape hatch.
SPECIAL_PARENT="$OUTER_ROOT/tmp space's parent"
mkdir -p "$SPECIAL_PARENT"
ROOT_NOTE="$OUTER_ROOT/owned-root-path"
TMPDIR="$SPECIAL_PARENT" ROOT_NOTE="$ROOT_NOTE" HARNESS="$HARNESS" bash -c '
  set -uo pipefail
  source "$HARNESS"
  harness_make_temp_root OWNED "fixture space'"'"'s"
  printf "%s\n" "$OWNED" > "$ROOT_NOTE"
  test -f "$OWNED/.scholar-auto-research-owned-root.json"
' || fail "special-character owned-root subprocess failed"
OWNED_PATH="$(cat "$ROOT_NOTE")"
[ ! -e "$OWNED_PATH" ] || fail "owned root remained after caller-shell exit"

set +e
KEEP_OUT="$(SCHOLAR_HARNESS_SUITE_MODE=release SCHOLAR_KEEP_FIXTURE=1 HARNESS="$HARNESS" bash -c '
  source "$HARNESS"
  harness_make_temp_root OWNED release-root
' 2>&1)"
KEEP_RC=$?
set -e
[ "$KEEP_RC" -ne 0 ] || fail "release keep escape hatch was accepted"
[ "$KEEP_OUT" = "HARNESS_KEEP_FORBIDDEN_IN_RELEASE" ] || fail "release keep diagnostic changed: $KEEP_OUT"

# The first observable signal point is after traps are installed but before
# create-owned-root runs.  Intercept that call, signal the caller, and prove
# the precomputed candidate never becomes residue.
SHIM_DIR="$OUTER_ROOT/python shim"
mkdir -p "$SHIM_DIR"
REAL_PYTHON="$(command -v python3)"
ROOT_NOTE="$OUTER_ROOT/race-candidate"
cat > "$SHIM_DIR/python3" <<'SH'
#!/usr/bin/env bash
if [ "${2:-}" = "create-owned-root" ]; then
  shift 2
  candidate=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--root" ]; then candidate="$2"; break; fi
    shift
  done
  printf '%s\n' "$candidate" > "$ROOT_NOTE"
  kill -TERM "$PPID"
  exit 143
fi
exec "$REAL_PYTHON" "$@"
SH
chmod 700 "$SHIM_DIR/python3"
set +e
RACE_OUT="$(PATH="$SHIM_DIR:/usr/bin:/bin" REAL_PYTHON="$REAL_PYTHON" ROOT_NOTE="$ROOT_NOTE" \
  TMPDIR="$SPECIAL_PARENT" HARNESS="$HARNESS" bash -c '
    source "$HARNESS"
    harness_make_temp_root OWNED first-observable-race
  ' 2>&1)"
RACE_RC=$?
set -e
[ "$RACE_RC" -eq 143 ] || fail "first-observable TERM returned rc=$RACE_RC: $RACE_OUT"
RACE_CANDIDATE="$(cat "$ROOT_NOTE")"
[ -n "$RACE_CANDIDATE" ] || fail "signal race did not expose proposed candidate"
[ ! -e "$RACE_CANDIDATE" ] || fail "signal before root creation left residue: $RACE_CANDIDATE"

# TMPDIR is an authority boundary: absent, non-directory, and filesystem-root
# values must refuse before installing ownership over any path.
printf 'not a directory\n' > "$OUTER_ROOT/tmpdir-file"
invalid_tmpdir() {
  local label="$1" value="$2" diagnostic="$3" output rc
  set +e
  output="$(TMPDIR="$value" HARNESS="$HARNESS" bash -c '
    source "$HARNESS"
    harness_make_temp_root OWNED invalid-tmpdir
  ' 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "$label TMPDIR was accepted"
  case "$output" in *"$diagnostic"*) ;; *) fail "$label TMPDIR diagnostic changed: $output" ;; esac
}
invalid_tmpdir missing "$OUTER_ROOT/does-not-exist" HARNESS_TMPDIR_MISSING
invalid_tmpdir file "$OUTER_ROOT/tmpdir-file" HARNESS_TMPDIR_INVALID
invalid_tmpdir root / HARNESS_TMPDIR_UNSAFE

# A proposed-name collision is not ownership.  The constructor must refuse it
# without deleting or changing the pre-existing canary directory.
COLLISION_PARENT="$OUTER_ROOT/collision-parent"
mkdir -p "$COLLISION_PARENT"
COLLISION_PROPOSAL="$(python3 "$HELPER" prepare-owned-root --tmpdir "$COLLISION_PARENT" --prefix collision-canary)"
IFS=$'\t' read -r COLLISION_ROOT COLLISION_NONCE COLLISION_PARENT_REAL <<< "$COLLISION_PROPOSAL"
mkdir "$COLLISION_ROOT"
printf 'do not delete\n' > "$COLLISION_ROOT/canary"
set +e
COLLISION_OUT="$(python3 "$HELPER" create-owned-root --root "$COLLISION_ROOT" \
  --nonce "$COLLISION_NONCE" --tmp-parent "$COLLISION_PARENT_REAL" 2>&1)"
COLLISION_RC=$?
set -e
[ "$COLLISION_RC" -ne 0 ] || fail "pre-existing root collision was accepted"
case "$COLLISION_OUT" in *HARNESS_TEMP_COLLISION*) ;; *) fail "collision diagnostic changed: $COLLISION_OUT" ;; esac
[ "$(cat "$COLLISION_ROOT/canary")" = "do not delete" ] || fail "collision canary was changed or deleted"

# Harness lint catches the five prohibited evidence shapes independently.
LINT_ROOT="$OUTER_ROOT/lint-source"
mkdir -p "$LINT_ROOT/tests/smoke"
cp "$MANIFEST" "$LINT_ROOT/coverage-manifest.json"
printf '%s\n' '#!/bin/bash' 'bash auto-research-verify.sh 1 x >/dev/null 2>&1' > "$LINT_ROOT/tests/smoke/discard.sh" # HARNESS_LINT_NEGATIVE_CONTROL
printf '%s\n' '#!/bin/bash' 'x="$(mktemp -d)"' > "$LINT_ROOT/tests/smoke/mktemp.sh"
printf '%s\n' '#!/bin/bash' 'find /tmp -name fixture -print | sort -r | head -1' > "$LINT_ROOT/tests/smoke/latest.sh" # HARNESS_LINT_NEGATIVE_CONTROL
printf '%s\n' '#!/bin/bash' 'python3 case_result.py record --case-id x' > "$LINT_ROOT/tests/smoke/direct.sh" # HARNESS_LINT_NEGATIVE_CONTROL
printf '%s\n' '#!/bin/bash' 'expect_reject NOT-REGISTERED root -- false' > "$LINT_ROOT/tests/smoke/unregistered.sh" # HARNESS_LINT_NEGATIVE_CONTROL
set +e
LINT_OUT="$(python3 "$HELPER" lint --manifest "$LINT_ROOT/coverage-manifest.json" --source-root "$LINT_ROOT" \
  "$LINT_ROOT/tests/smoke/discard.sh" "$LINT_ROOT/tests/smoke/mktemp.sh" \
  "$LINT_ROOT/tests/smoke/latest.sh" "$LINT_ROOT/tests/smoke/direct.sh" \
  "$LINT_ROOT/tests/smoke/unregistered.sh" 2>&1)"
LINT_RC=$?
set -e
[ "$LINT_RC" -ne 0 ] || fail "prohibited harness shapes passed lint"
for code in HARNESS_LINT_OUTPUT_DISCARD HARNESS_LINT_UNTRAPPED_MKTEMP \
  HARNESS_LINT_GLOBAL_LATEST HARNESS_LINT_DIRECT_RECORD HARNESS_LINT_UNREGISTERED_CASE; do
  case "$LINT_OUT" in *"$code"*) ;; *) fail "lint omitted $code: $LINT_OUT" ;; esac
done

echo "PASS: harness enforces exact exit, unique diagnostic, and declared authoritative state delta"
echo "PASS: exact per-stream transcripts reject extra, missing, duplicated, reordered, spoofed, and cross-stream lines"
echo "PASS: manifest-derived expected sets reject missing records and caller-spoofed path, runner, or phase bindings"
echo "PASS: case records are source/manifest/run bound, atomic, exact-once, and direct-write resistant"
echo "PASS: HMAC joins revalidate checkpoint/final terminal semantics and keep the capability out of production environments"
echo "PASS: schema 1.2 typed transcripts and closed typed-path postconditions reject descriptor, path, digest, type, timestamp, and equality attacks"
echo "PASS: sentinel-owned lifecycle cleanup and prohibited-shape lint fail closed"
