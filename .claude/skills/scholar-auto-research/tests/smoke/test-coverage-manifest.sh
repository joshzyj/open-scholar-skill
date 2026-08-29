#!/usr/bin/env bash
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
SKILL_DIR="$(cd "$SKILL_DIR" 2>/dev/null && pwd -P)" || {
  echo "FAIL: packaged skill directory is not resolvable" >&2
  exit 1
}
LINT="$SKILL_DIR/tests/helpers/coverage_lint.py"
MANIFEST="$SKILL_DIR/tests/coverage-manifest.json"

[ -f "$LINT" ] || { echo "FAIL: missing packaged coverage lint: $LINT" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "FAIL: missing packaged coverage manifest: $MANIFEST" >&2; exit 1; }

fixture_root=""
probe_root=""
cleanup() {
  if [ -n "$probe_root" ] && [ -d "$probe_root" ]; then
    rm -rf -- "$probe_root"
  fi
  if [ -n "$fixture_root" ] && [ -d "$fixture_root" ]; then
    rm -rf -- "$fixture_root"
  fi
}
trap cleanup EXIT

args=(--skill-dir "$SKILL_DIR" --manifest "$MANIFEST")
if [ "${SCHOLAR_AUTO_RESEARCH_REPO_ROOT+x}" = x ]; then
  [ -n "$SCHOLAR_AUTO_RESEARCH_REPO_ROOT" ] || {
    echo "FAIL: explicit repository root is empty" >&2
    exit 1
  }
  repo_root="$(cd "$SCHOLAR_AUTO_RESEARCH_REPO_ROOT" 2>/dev/null && pwd -P)" || {
    echo "FAIL: explicit repository root is not resolvable" >&2
    exit 1
  }
  expected_skill="$repo_root/.claude/skills/scholar-auto-research"
  [ ! -L "$expected_skill" ] || {
    echo "FAIL: explicit repository root does not own this packaged skill" >&2
    exit 1
  }
  canonical_expected_skill="$(cd "$expected_skill" 2>/dev/null && pwd -P)" || {
    echo "FAIL: explicit repository root does not own this packaged skill" >&2
    exit 1
  }
  [ "$canonical_expected_skill" = "$SKILL_DIR" ] || {
    echo "FAIL: explicit repository root does not own this packaged skill" >&2
    exit 1
  }
  suite_runner="$repo_root/tests/smoke/test-auto-research-suite.sh"
  [ -f "$suite_runner" ] && [ ! -L "$suite_runner" ] || {
    echo "FAIL: explicit repository root lacks canonical suite runner" >&2
    exit 1
  }
  canonical_suite_runner="$(cd "$(dirname "$suite_runner")" && pwd -P)/$(basename "$suite_runner")"
  [ "$canonical_suite_runner" = "$suite_runner" ] || {
    echo "FAIL: explicit repository root suite runner is not canonical" >&2
    exit 1
  }
  args+=(--suite-runner "$suite_runner" --repo-root "$repo_root" --self-test)
else
  # Installed skills never infer repository authority from Git, ancestors, or
  # the caller's working directory. Exercise mutations against a generated
  # runner carrying only the packaged registry's canonical labels and paths.
  fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-coverage.XXXXXX")"
  runner="$fixture_root/test-auto-research-suite.sh"
  python3 - "$MANIFEST" "$runner" <<'PY'
import json
import hashlib
from pathlib import Path
import sys
manifest = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w") as out:
    out.write("#!/usr/bin/env bash\n")
    for label, spec in manifest["suite_registry"].items():
        fn = "run_heavy" if spec["tier"] == "heavy" else "run_test"
        out.write(f'{fn} "{label}" "{spec["path"]}"\n')
PY
  args+=(--suite-runner "$runner" --self-test)
fi

python3 "$LINT" "${args[@]}"

# F20/L4 registers both ordered checkpoints and their closed accounting.
python3 - "$MANIFEST" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
if manifest.get("schema_version") != "1.2.0":
    raise SystemExit("live manifest is not schema 1.2.0")
if manifest.get("execution_checkpoints") != ["state-tail", "completion-tail"]:
    raise SystemExit("F20/L4 execution_checkpoints must be state-tail then completion-tail")
fixture_relative = "scripts/auto-research-fixture-test.sh"
hitl_relative = "tests/smoke/test-human-in-loop.sh"
reviewed = manifest.get("reviewed_test_sources")
if not isinstance(reviewed, dict) or set(reviewed) != {fixture_relative, hitl_relative}:
    raise SystemExit("F20/L4 reviewed source authority is not the exact fixture/HITL pair")
for relative in (fixture_relative, hitl_relative):
    source = Path(sys.argv[1]).parents[1] / relative
    if hashlib.sha256(source.read_bytes()).hexdigest() != reviewed[relative]:
        raise SystemExit(f"F20/L4 reviewed source bytes do not match manifest authority: {relative}")
inventory = manifest.get("post_stop20_call_inventory")
if not isinstance(inventory, dict) or len(inventory.get("rows", [])) != 90:
    raise SystemExit("F20/L4 post-STOP20 inventory must contain exactly 90 rows")
rows = inventory["rows"]
stream_counts = {value: sum(row.get("stream_policy") == value for row in rows) for value in {
    "harness_captured", "stdout_discarded_stderr_observed_fail_closed",
    "captured_both_streams_pattern_checked_open", "both_streams_discarded",
}}
if stream_counts != {
    "harness_captured": 39,
    "stdout_discarded_stderr_observed_fail_closed": 51,
    "captured_both_streams_pattern_checked_open": 0,
    "both_streams_discarded": 0,
}:
    raise SystemExit(f"F20/L4 post-STOP20 stream accounting mismatch: {stream_counts}")
if len(manifest.get("cases", {})) != 427:
    raise SystemExit("F20/L4 live case universe mismatch")
if sum(manifest.get("phase_invariant_counts", {}).values()) != 705:
    raise SystemExit("P10.2 live phase-invariant universe mismatch")
if manifest.get("external_gate_invariant_count") != 69:
    raise SystemExit("P10.2 live external-gate universe changed")
checkpoint_counts = {
    checkpoint: sum(
        case.get("execution_checkpoint") == checkpoint
        for case in manifest.get("cases", {}).values()
    )
    for checkpoint in manifest["execution_checkpoints"]
}
if checkpoint_counts != {"state-tail": 15, "completion-tail": 24}:
    raise SystemExit(f"F20/L4 checkpoint case universe mismatch: {checkpoint_counts}")
negative = sum(case.get("polarity") == "negative" for case in manifest.get("cases", {}).values() if case.get("runner_label") == "fixture-test")
positive = sum(case.get("polarity") == "positive" for case in manifest.get("cases", {}).values() if case.get("runner_label") == "fixture-test")
if (negative, positive) != (246, 70):
    raise SystemExit(f"F20/L4 fixture polarity accounting mismatch: {(negative, positive)}")
PY
echo "coverage F20/L4 checkpoint/accounting: PASS"

if [ "${SCHOLAR_AUTO_RESEARCH_COVERAGE_INTERNAL_PROBE:-0}" != 1 ]; then
  probe_root="$(mktemp -d "${TMPDIR:-/tmp}/scholar-auto-research-coverage-authority.XXXXXX")"

  # P10.0: the production import diagnostic is reason-specific, deterministically
  # ordered, and line-safe for every canonical path byte representable in JSON.
  python3 - "$SKILL_DIR/scripts/auto-research-state.sh" "$probe_root/import-diagnostics" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys

state_script = Path(sys.argv[1])
root = Path(sys.argv[2])
root.mkdir(parents=True)


def run_import(project: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["SCHOLAR_RUN_HTML_AUTO"] = "0"
    return subprocess.run(
        ["bash", str(state_script), "import-init", str(project)],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )


blocked = root / "blocked paths with apostrophe's"
blocked_entries = [
    ("data/raw/a space.csv", "NEEDS_REVIEW: possible PII", "needs_review"),
    ("data/raw/b'apostrophe.csv", "HALTED: policy stop", "halted"),
    ("data/raw/c=equals.csv", "OVERRIDE", "override_without_rationale"),
    ('data/raw/d"quote.csv', "UNKNOWN: unsupported", "unrecognized_status"),
    ("data/raw/e\rreturn.csv", "NEEDS_REVIEW", "needs_review"),
    ("data/raw/f\nline.csv", "HALT", "halted"),
    ("data/raw/g\ttab.csv", "OVERRIDE", "override_without_rationale"),
    ("data/raw/h\\backslash.csv", "MYSTERY", "unrecognized_status"),
    ("data/raw/i\u2603unicode.csv", "NEEDS_REVIEW", "needs_review"),
]
sidecar = {"_safety_level": "standard", "_meta": {"probe": True}}
for relative, status, _ in reversed(blocked_entries):
    path = blocked / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"id\n1\n")
    sidecar[relative] = status
(blocked / ".claude").mkdir(parents=True)
(blocked / ".claude/safety-status.json").write_text(
    json.dumps(sidecar, ensure_ascii=True) + "\n", encoding="utf-8",
)
blocked_result = run_import(blocked)
blocked_lines = [
    f"IMPORTED_SAFETY={blocked}/safety/safety-status.json",
    "SAFETY_STATUS=BLOCKED",
    f"HIGH_RISK_UNRESOLVED={len(blocked_entries)}",
]
blocked_lines.extend(
    f"IMPORT_INIT_BLOCKED: reason={reason} path_json={json.dumps(relative, ensure_ascii=True)}"
    for relative, _, reason in sorted(blocked_entries)
)
blocked_lines.append("NEXT_ACTION=run scholar-init review before Phase 0 completion")
expected_blocked = "\n".join(blocked_lines) + "\n"
if blocked_result.returncode != 1:
    raise SystemExit(f"blocked import exit mismatch: {blocked_result.returncode}")
if blocked_result.stdout != expected_blocked:
    raise SystemExit(
        "blocked import stdout mismatch\n"
        f"expected={expected_blocked!r}\nobserved={blocked_result.stdout!r}"
    )
if blocked_result.stderr != "":
    raise SystemExit(f"blocked import stderr was not empty: {blocked_result.stderr!r}")
if any("\r" in line or "\n" in line for line in blocked_result.stdout.splitlines()):
    raise SystemExit("blocked import emitted an unescaped control character")
normalized = json.loads((blocked / "safety/safety-status.json").read_text(encoding="utf-8"))
if normalized.get("meta") != {"_meta": {"probe": True}, "_safety_level": "standard"}:
    raise SystemExit(f"blocked import meta partition mismatch: {normalized.get('meta')!r}")
if normalized.get("files_scanned") != len(blocked_entries):
    raise SystemExit("blocked import counted meta keys as files")
if set(normalized.get("status_by_file", {})) != {row[0] for row in blocked_entries}:
    raise SystemExit("blocked import canonical path set mismatch")

positive = root / "positive import"
positive_entries = {
    "data/raw/a.csv": "CLEARED: public",
    "data/raw/b.csv": "LOCAL_MODE: sensitive",
}
for relative in positive_entries:
    path = positive / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"id\n1\n")
(positive / ".claude").mkdir(parents=True)
(positive / ".claude/safety-status.json").write_text(
    json.dumps(positive_entries) + "\n", encoding="utf-8",
)
positive_result = run_import(positive)
expected_positive = "\n".join([
    f"IMPORTED_SAFETY={positive}/safety/safety-status.json",
    "SAFETY_STATUS=PASS_LOCAL_MODE",
    "HIGH_RISK_UNRESOLVED=0",
    "NEXT_PHASE=MODE_SELECTION",
    "RUN_MODE=unset",
    "DECISION_REQUIRED=1",
    "NEXT_ACTION=set run mode: auto-research-state.sh set-mode <project> autonomous|human-in-loop",
]) + "\n"
if positive_result.returncode != 0:
    raise SystemExit(f"positive import exit mismatch: {positive_result.returncode}")
if positive_result.stdout != expected_positive or positive_result.stderr != "":
    raise SystemExit(
        "positive import transcript mismatch\n"
        f"stdout={positive_result.stdout!r}\nstderr={positive_result.stderr!r}"
    )
if "IMPORT_INIT_BLOCKED" in positive_result.stdout:
    raise SystemExit("positive import emitted a blocked diagnostic")
PY
  echo "coverage state import diagnostic behavior probe: PASS"

  # A supplied root is authority, not a hint. It must fail closed when it does
  # not own this exact packaged skill and canonical root-suite path.
  invalid_root="$probe_root/invalid-explicit-root"
  mkdir -p "$invalid_root"
  set +e
  invalid_output="$(SCHOLAR_AUTO_RESEARCH_COVERAGE_INTERNAL_PROBE=1 \
    SCHOLAR_AUTO_RESEARCH_REPO_ROOT="$invalid_root" \
    SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR="$SKILL_DIR" \
    /bin/bash "$SELF" 2>&1)"
  invalid_rc=$?
  set -e
  [ "$invalid_rc" -ne 0 ] || {
    echo "FAIL: invalid explicit repository root was accepted" >&2
    exit 1
  }
  [ "$(printf '%s\n' "$invalid_output" | grep -c '^FAIL: explicit repository root does not own this packaged skill$' || true)" -eq 1 ] || {
    echo "FAIL: invalid explicit repository root lacked exact rejection diagnostic" >&2
    exit 1
  }
  echo "coverage explicit-authority rejection probe: PASS"

  # A recognized Python program heredoc is authoritative even when malformed:
  # its bytes must never fall back to the legacy shell-literal extractor.
  malformed_skill="$probe_root/malformed-python-skill"
  malformed_log="$probe_root/malformed-python.log"
  cp -R "$SKILL_DIR" "$malformed_skill"
  python3 - "$malformed_skill/scripts/auto-research-verify.sh" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = "    specialist_review_needed, specialist_family = phase18_specialist_requirement(\n"
if source.count(needle) != 1:
    raise SystemExit("malformed-Python probe fixture drift")
path.write_text(source.replace(needle, "    if\n" + needle, 1), encoding="utf-8")
PY
  set +e
  malformed_output="$(env -u SCHOLAR_AUTO_RESEARCH_REPO_ROOT \
    SCHOLAR_AUTO_RESEARCH_COVERAGE_INTERNAL_PROBE=1 \
    SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR="$malformed_skill" \
    /bin/bash "$malformed_skill/tests/smoke/test-coverage-manifest.sh" 2>&1)"
  malformed_rc=$?
  set -e
  printf '%s\n' "$malformed_output" >"$malformed_log"
  [ "$malformed_rc" -ne 0 ] || {
    echo "FAIL: malformed recognized Python heredoc was accepted" >&2
    exit 1
  }
  [ "$(grep -c '^  - DIAGNOSTIC_SOURCE_PARSE_ERROR:python-heredoc-line-' "$malformed_log" || true)" -eq 1 ] || {
    cat "$malformed_log" >&2
    echo "FAIL: malformed recognized Python heredoc lacked exact parser rejection" >&2
    exit 1
  }
  echo "coverage recognized-Python fail-closed probe: PASS"

  # An installed copy nested below an unrelated .git directory must remain on
  # the generated-runner branch. The marker proves Git was never invoked.
  unrelated_root="$probe_root/unrelated-repository"
  installed_skill="$unrelated_root/vendor/scholar-auto-research"
  shim_dir="$probe_root/git-shim"
  git_marker="$probe_root/git-invoked.marker"
  installed_log="$probe_root/installed-nested-git.log"
  mkdir -p "$unrelated_root/.git" "$(dirname "$installed_skill")" "$shim_dir"
  cp -R "$SKILL_DIR" "$installed_skill"
  printf '#!/usr/bin/env bash\nprintf invoked > %q\nexit 97\n' "$git_marker" >"$shim_dir/git"
  chmod +x "$shim_dir/git"
  if ! env -u SCHOLAR_AUTO_RESEARCH_REPO_ROOT \
    HOME="$probe_root/empty-home" PATH="$shim_dir:$PATH" \
    SCHOLAR_AUTO_RESEARCH_COVERAGE_INTERNAL_PROBE=1 \
    SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR="$installed_skill" \
    /bin/bash "$installed_skill/tests/smoke/test-coverage-manifest.sh" >"$installed_log" 2>&1; then
    cat "$installed_log" >&2
    echo "FAIL: installed nested-Git coverage proof failed" >&2
    exit 1
  fi
  grep -q '^coverage manifest lint: PASS$' "$installed_log" || {
    echo "FAIL: installed nested-Git coverage proof lacks PASS" >&2
    exit 1
  }
  [ ! -e "$git_marker" ] || {
    echo "FAIL: installed coverage proof invoked Git" >&2
    exit 1
  }
  echo "coverage installed nested-Git no-inference probe: PASS"
fi
