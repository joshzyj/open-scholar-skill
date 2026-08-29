#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SELF="$SCRIPT_DIR/test-phase13-locked-claim-mutations.sh"
VERIFY="$SKILL_DIR/scripts/auto-research-verify.sh"
FULL_FIXTURE="$SKILL_DIR/scripts/auto-research-fixture-test.sh"
CASE_TOOL="$SKILL_DIR/tests/helpers/case_result.py"
HARNESS="$SKILL_DIR/tests/helpers/harness.sh"
MANIFEST="$SKILL_DIR/tests/coverage-manifest.json"
export PYTHONDONTWRITEBYTECODE=1
readonly F20_P6_BOOTSTRAP_TIMEOUT_SECONDS=600
readonly F20_P6_VERIFIER_TIMEOUT_SECONDS=120
readonly F20_P6_PROBE_TIMEOUT_SECONDS=1
_F20_ACTIVE_WRAPPER_PID=""
_F20_WRAPPER_READY_FILE=""

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

_f20_outer_signal() {
  local signal_name="$1" signal_rc="$2" wrapper_rc=0 cleanup_rc=0
  trap - HUP INT TERM
  if [ -n "${_F20_ACTIVE_WRAPPER_PID:-}" ]; then
    kill -s "$signal_name" "$_F20_ACTIVE_WRAPPER_PID" 2>/dev/null || true
    if wait "$_F20_ACTIVE_WRAPPER_PID"; then
      wrapper_rc=0
    else
      wrapper_rc=$?
    fi
  fi
  _F20_ACTIVE_WRAPPER_PID=""
  if ! harness_cleanup; then
    cleanup_rc=1
  fi
  [ "$cleanup_rc" -eq 0 ] || signal_rc=1
  [ "$wrapper_rc" -eq 0 ] || :
  exit "$signal_rc"
}

_f20_install_outer_signal_traps() {
  trap '_f20_outer_signal HUP 129' HUP
  trap '_f20_outer_signal INT 130' INT
  trap '_f20_outer_signal TERM 143' TERM
}

run_bounded() {
  local deadline="$1"
  shift
  local signal_probe=0
  if [ "$deadline" = "__term_probe" ]; then
    signal_probe=1
    deadline=10
  fi
  [ "$deadline" -ge 1 ] && [ "$#" -ge 1 ] || return 125
  python3 - "$signal_probe" "$deadline" "$@" <<'PY' &
import os
import signal
import subprocess
import sys
import threading

signal_probe = sys.argv[1] == "1"
deadline = int(sys.argv[2])
command = sys.argv[3:]
proc = subprocess.Popen(command, start_new_session=True)

def terminate_and_reap(sig):
    try:
        os.killpg(proc.pid, sig)
    except ProcessLookupError:
        pass
    try:
        return proc.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        return proc.wait()

def forward_signal(sig, _frame):
    terminate_and_reap(sig)
    raise SystemExit(128 + sig)

for handled in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(handled, forward_signal)

if signal_probe:
    timer = threading.Timer(0.2, lambda: os.kill(os.getpid(), signal.SIGTERM))
    timer.daemon = True
    timer.start()

try:
    rc = proc.wait(timeout=deadline)
except subprocess.TimeoutExpired:
    terminate_and_reap(signal.SIGTERM)
    print(f"F20_P6_COMMAND_TIMEOUT: deadline_seconds={deadline}", file=sys.stderr)
    raise SystemExit(124)

raise SystemExit(rc if 0 <= rc <= 255 else 128 + abs(rc))
PY
  local wrapper_pid=$!
  _F20_ACTIVE_WRAPPER_PID="$wrapper_pid"
  if [ -n "${_F20_WRAPPER_READY_FILE:-}" ]; then
    printf '%s\n' "$wrapper_pid" >"$_F20_WRAPPER_READY_FILE"
  fi
  local wrapper_rc
  if wait "$wrapper_pid"; then
    wrapper_rc=0
  else
    wrapper_rc=$?
  fi
  _F20_ACTIVE_WRAPPER_PID=""
  return "$wrapper_rc"
}

observe_verifier() {
  local stdout_path="$1" stderr_path="$2"
  shift 2
  local rc
  if run_bounded "$F20_P6_VERIFIER_TIMEOUT_SECONDS" "$@" >"$stdout_path" 2>"$stderr_path"; then
    rc=0
  else
    rc=$?
  fi
  cat "$stdout_path"
  [ ! -s "$stderr_path" ] || cat "$stderr_path" >&2
  return "$rc"
}

validate_verifier_transcript() {
  local verifier="$1" phase="$2" project="$3" transcript="$4" trusted_project="$5" trusted_transcript="$6"
  python3 - "$verifier" "$phase" "$project" "$transcript" "$trusted_project" "$trusted_transcript" <<'PY'
import glob
import hashlib
import json
import subprocess
import sys
from pathlib import Path

verifier = Path(sys.argv[1]).resolve(strict=True)
phase_id = sys.argv[2]
project = Path(sys.argv[3]).resolve(strict=True)
transcript = Path(sys.argv[4]).resolve(strict=True)
trusted_project = Path(sys.argv[5]).resolve(strict=True)
trusted_transcript = Path(sys.argv[6]).resolve(strict=True)
skill = verifier.parent.parent
contract_path = skill / "references/phase-contract.json"
contract_bytes = contract_path.read_bytes()
contract = json.loads(contract_bytes)
phase = next((row for row in contract["phases"] if str(row.get("id")) == phase_id), None)
if phase is None:
    print(f"F20_P6_TRANSCRIPT_INVALID: unknown phase {phase_id}", file=sys.stderr)
    raise SystemExit(1)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def digest_path(path):
    if path.is_symlink():
        raise ValueError(f"descriptor path is symlink: {path}")
    if path.is_file():
        return sha(path)
    if not path.is_dir():
        raise ValueError(f"descriptor path missing or special: {path}")
    digest = hashlib.sha256()
    for child in sorted(path.rglob("*"), key=lambda item: item.as_posix()):
        if child.is_symlink():
            raise ValueError(f"descriptor child is symlink: {child}")
        relative = child.relative_to(path).as_posix()
        if child.is_dir():
            digest.update(f"D\0{relative}\0".encode())
        elif child.is_file():
            digest.update(f"F\0{relative}\0{sha(child)}\0".encode())
        else:
            raise ValueError(f"descriptor child is special: {child}")
    return digest.hexdigest()

def descriptor_paths(root, patterns, required):
    resolved = {}
    for pattern in patterns:
        matches = sorted(glob.glob(str(root / str(pattern))))
        if required and not matches:
            raise ValueError(f"descriptor required pattern missing: {pattern}")
        for raw in matches:
            path = Path(raw)
            if path.is_symlink():
                raise ValueError(f"descriptor match is symlink: {path}")
            try:
                relative = path.resolve().relative_to(root).as_posix()
            except ValueError as exc:
                raise ValueError(f"descriptor path escapes project: {path}") from exc
            resolved[relative] = digest_path(path)
    return dict(sorted(resolved.items()))

expected_tail = [
    f"PASS: Phase {phase_id} {phase['name']} required outputs exist",
    "Required verdict fields:",
    *[f"  - {field}" for field in phase["pass_schema"]],
]
inventory_helper = skill / "tests/helpers/external_gate_inventory.py"
if not inventory_helper.is_file() or inventory_helper.is_symlink():
    print("F20_P6_TRANSCRIPT_INVALID: packaged external-gate inventory helper missing or symlinked", file=sys.stderr)
    raise SystemExit(1)
inventory_result = subprocess.run(
    [sys.executable, str(inventory_helper), str(verifier)],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10,
)
if inventory_result.returncode != 0 or inventory_result.stderr:
    print("F20_P6_TRANSCRIPT_INVALID: packaged external-gate inventory helper failed", file=sys.stderr)
    raise SystemExit(1)
try:
    gate_inventory = json.loads(inventory_result.stdout)
except json.JSONDecodeError:
    print("F20_P6_TRANSCRIPT_INVALID: packaged external-gate inventory JSON is invalid", file=sys.stderr)
    raise SystemExit(1)
if (
    not isinstance(gate_inventory, dict)
    or gate_inventory.get("schema_version") != "1.0.0"
    or gate_inventory.get("supported_invocation_shapes") != ["direct_consume_literal", "tuple_literal"]
    or not isinstance(gate_inventory.get("obligations"), list)
):
    print("F20_P6_TRANSCRIPT_INVALID: packaged external-gate inventory shape is invalid", file=sys.stderr)
    raise SystemExit(1)
advisory_labels = set()
for obligation in gate_inventory["obligations"]:
    if not isinstance(obligation, dict):
        print("F20_P6_TRANSCRIPT_INVALID: external-gate obligation is not an object", file=sys.stderr)
        raise SystemExit(1)
    labels = obligation.get("labels")
    if (
        str(obligation.get("owning_phase")) == phase_id
        and (not isinstance(labels, list) or not labels or any(not isinstance(label, str) or not label for label in labels))
    ):
        print("F20_P6_TRANSCRIPT_INVALID: phase external-gate labels are invalid", file=sys.stderr)
        raise SystemExit(1)
    if str(obligation.get("owning_phase")) == phase_id:
        advisory_labels.update(labels)
if not advisory_labels:
    print("F20_P6_TRANSCRIPT_INVALID: copied verifier has no phase external-gate labels", file=sys.stderr)
    raise SystemExit(1)
base_keys = {
    "schema_version", "phase_id", "verdict", "contract_sha256",
    "required_outputs", "required_inputs",
}
expected_keys = base_keys | ({"review_evidence"} if phase_id == "14" else set())

def parse_and_validate(path, root):
    raw = path.read_text(encoding="utf-8")
    if not raw.endswith("\n") or "\r" in raw:
        raise ValueError("transcript newline framing is noncanonical")
    lines = raw.splitlines()
    prefix = "VERIFICATION_DESCRIPTOR_JSON="
    descriptor_indexes = [index for index, line in enumerate(lines) if line.startswith(prefix)]
    if len(descriptor_indexes) != 1:
        raise ValueError("transcript must contain exactly one descriptor line")
    descriptor_index = descriptor_indexes[0]
    if lines[descriptor_index + 1:] != expected_tail:
        raise ValueError("transcript tail differs from contract advisory sequence")
    advisory_prefix = "ADVISORY: external gate not GREEN (non-fatal) — "
    for line in lines[:descriptor_index]:
        if not line.startswith(advisory_prefix):
            raise ValueError("pre-descriptor transcript line is not a canonical advisory")
        payload = line[len(advisory_prefix):]
        matching = [label for label in advisory_labels if payload.startswith(label + ": ")]
        if len(matching) != 1:
            raise ValueError("advisory does not carry a phase-declared gate label")
        verdict = payload[len(matching[0]) + 2:]
        if not ((verdict.startswith("YELLOW (") or verdict.startswith("INERT (")) and verdict.endswith(")")):
            raise ValueError("advisory status framing is invalid")
    try:
        descriptor = json.loads(lines[descriptor_index][len(prefix):])
    except json.JSONDecodeError as exc:
        raise ValueError("descriptor JSON is invalid") from exc
    if not isinstance(descriptor, dict) or set(descriptor) != expected_keys:
        raise ValueError("descriptor key set is invalid")
    if descriptor.get("schema_version") != "scholar-auto-research-verification-descriptor/v1":
        raise ValueError("descriptor schema is invalid")
    if str(descriptor.get("phase_id")) != phase_id or descriptor.get("verdict") != "PASS":
        raise ValueError("descriptor phase/verdict binding is invalid")
    if descriptor.get("contract_sha256") != hashlib.sha256(contract_bytes).hexdigest():
        raise ValueError("descriptor contract digest is invalid")
    if descriptor.get("required_outputs") != descriptor_paths(root, phase.get("required_outputs", []), True):
        raise ValueError("descriptor required-output closure is invalid")
    if descriptor.get("required_inputs") != descriptor_paths(root, phase.get("required_inputs", []), False):
        raise ValueError("descriptor required-input closure is invalid")
    if phase_id == "14" and not isinstance(descriptor.get("review_evidence"), dict):
        raise ValueError("descriptor review evidence is invalid")
    non_descriptor = lines[:descriptor_index] + lines[descriptor_index + 1:]
    return descriptor, non_descriptor

try:
    trusted_descriptor, trusted_non_descriptor = parse_and_validate(trusted_transcript, trusted_project)
    candidate_descriptor, candidate_non_descriptor = parse_and_validate(transcript, project)
    if candidate_non_descriptor != trusted_non_descriptor:
        raise ValueError("candidate non-descriptor transcript differs from trusted pristine transcript")
    if phase_id == "14" and candidate_descriptor["review_evidence"] != trusted_descriptor["review_evidence"]:
        raise ValueError("candidate review evidence differs from trusted pristine descriptor")
except (OSError, ValueError) as exc:
    print(f"F20_P6_TRANSCRIPT_INVALID: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
}

generate_registry_runner() {
  local manifest="$1" output="$2"
  python3 - "$manifest" "$output" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
lines = ["#!/usr/bin/env bash"]
for label, spec in manifest["suite_registry"].items():
    command = "run_heavy" if spec["tier"] == "heavy" else "run_test"
    lines.append(f'{command} "{label}" "{spec["path"]}"')
Path(sys.argv[2]).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

configure_coverage_lint_authority() {
  LINT_HOME="$TMP_ROOT/empty-home"
  mkdir -p "$LINT_HOME"
  if [ -n "${SCHOLAR_AUTO_RESEARCH_REPO_ROOT:-}" ]; then
    REPO_ROOT="$(cd "$SCHOLAR_AUTO_RESEARCH_REPO_ROOT" && pwd -P)" \
      || fail "explicit repository root is not resolvable"
    local expected_skill="$REPO_ROOT/.claude/skills/scholar-auto-research"
    [ "$(cd "$expected_skill" 2>/dev/null && pwd -P)" = "$(cd "$SKILL_DIR" && pwd -P)" ] \
      || fail "explicit repository root does not own this packaged skill"
    LINT_SUITE_RUNNER="$REPO_ROOT/tests/smoke/test-auto-research-suite.sh"
    [ -f "$LINT_SUITE_RUNNER" ] || fail "explicit repository root lacks canonical suite runner"
  else
    REPO_ROOT=""
    LINT_SUITE_RUNNER="$TMP_ROOT/generated-test-auto-research-suite.sh"
    generate_registry_runner "$MANIFEST" "$LINT_SUITE_RUNNER"
  fi
}

cleanup_preserved_root_from_log() {
  local log="$1" expected_parent="$2"
  python3 - "$log" "$expected_parent" "$CASE_TOOL" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

log = Path(sys.argv[1])
expected_parent = Path(sys.argv[2]).resolve(strict=True)
case_tool = sys.argv[3]
roots = [
    line.split("=", 1)[1]
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines()
    if line.startswith("HARNESS_FIXTURE_PRESERVED=")
]
if len(roots) != 1:
    raise SystemExit(f"preserved-root record count must be one, observed={len(roots)}")
root = Path(roots[0]).resolve(strict=True)
try:
    root.relative_to(expected_parent)
except ValueError as exc:
    raise SystemExit(f"preserved root escapes outer-owned parent: {root}") from exc
sentinel = json.loads((root / ".scholar-auto-research-owned-root.json").read_text(encoding="utf-8"))
subprocess.run([
    "python3", case_tool, "cleanup-owned-root", "--root", str(root),
    "--nonce", sentinel["nonce"], "--tmp-parent", sentinel["tmp_parent"],
], check=True)
if root.exists():
    raise SystemExit(f"preserved root survived cleanup: {root}")
PY
}

run_lifecycle_probes() {
  local grandchild_script="$TMP_ROOT/grandchild-timeout-probe.sh"
  local grandchild_pid_file="$TMP_ROOT/grandchild-timeout.pid"
  local timeout_stdout="$TMP_ROOT/grandchild-timeout.stdout"
  local timeout_stderr="$TMP_ROOT/grandchild-timeout.stderr"
  printf '%s\n' '#!/usr/bin/env bash' 'sleep 30 &' 'printf "%s\n" "$!" > "$1"' 'wait' >"$grandchild_script"
  chmod +x "$grandchild_script"
  local timeout_rc
  if run_bounded "$F20_P6_PROBE_TIMEOUT_SECONDS" bash "$grandchild_script" "$grandchild_pid_file" >"$timeout_stdout" 2>"$timeout_stderr"; then
    timeout_rc=0
  else
    timeout_rc=$?
  fi
  [ "$timeout_rc" -eq 124 ] || fail "bounded grandchild probe returned rc=$timeout_rc"
  [ "$(grep -c '^F20_P6_COMMAND_TIMEOUT: deadline_seconds=1$' "$timeout_stderr" || true)" -eq 1 ] \
    || fail "bounded grandchild probe lacks exact timeout diagnostic"
  [ -s "$grandchild_pid_file" ] || fail "bounded grandchild probe did not record child pid"
  local child_pid probe_try
  child_pid="$(cat "$grandchild_pid_file")"
  for probe_try in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$child_pid" 2>/dev/null || break
    sleep 0.05
  done
  ! kill -0 "$child_pid" 2>/dev/null || fail "bounded timeout left grandchild alive"

  local failure_parent="$TMP_ROOT/failure-residue-parent"
  local failure_script="$TMP_ROOT/failure-residue-probe.sh"
  local failure_log="$TMP_ROOT/failure-residue-probe.log"
  mkdir -p "$failure_parent"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'source "$1"' 'harness_make_temp_root PROBE_ROOT "f20 failure residue"' 'exit 23' >"$failure_script"
  chmod +x "$failure_script"
  local failure_rc preserved
  if run_bounded 5 env TMPDIR="$failure_parent" SCHOLAR_KEEP_FIXTURE=1 bash "$failure_script" "$HARNESS" >"$failure_log" 2>&1; then
    failure_rc=0
  else
    failure_rc=$?
  fi
  [ "$failure_rc" -eq 23 ] || fail "failure-residue probe returned rc=$failure_rc"
  preserved="$(grep -F 'HARNESS_FIXTURE_PRESERVED=' "$failure_log" | cut -d= -f2-)"
  [ -n "$preserved" ] && [ -d "$preserved" ] || fail "failure-residue probe did not preserve owned child root"
  cleanup_preserved_root_from_log "$failure_log" "$failure_parent" \
    || fail "failure-residue probe cleanup failed"
  [ ! -e "$preserved" ] || fail "failure-residue probe left owned child root"

  local signal_parent="$TMP_ROOT/signal-residue-parent"
  local signal_script="$TMP_ROOT/signal-reap-probe.sh"
  local signal_log="$TMP_ROOT/signal-reap-probe.log"
  local signal_marker="$TMP_ROOT/signal-delayed-grandchild.marker"
  local signal_rc
  mkdir -p "$signal_parent"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'source "$1"' \
    'harness_make_temp_root SIGNAL_ROOT "f20 signal residue"' \
    '(sleep 2; printf marked > "$2") &' 'wait' >"$signal_script"
  chmod +x "$signal_script"
  if run_bounded __term_probe env TMPDIR="$signal_parent" SCHOLAR_KEEP_FIXTURE=0 \
    bash "$signal_script" "$HARNESS" "$signal_marker" >"$signal_log" 2>&1; then
    signal_rc=0
  else
    signal_rc=$?
  fi
  [ "$signal_rc" -eq 143 ] || fail "TERM process-group probe returned rc=$signal_rc"
  sleep 1.5
  [ ! -e "$signal_marker" ] || fail "TERM process-group probe left delayed marked grandchild alive"
  [ -z "$(find "$signal_parent" -name '.scholar-auto-research-owned-root.json' -print -quit)" ] \
    || fail "TERM process-group probe left owned-root residue"
  printf 'F20_P6_LIFECYCLE_PROBES=PASS\n'
}

run_outer_driver_signal_probe() {
  local probe_parent="$TMP_ROOT/outer-driver-signal-probe"
  local marker="$probe_parent/delayed-grandchild.marker"
  local wrapper_ready="$probe_parent/wrapper.ready"
  local nested_ready="$probe_parent/nested.ready"
  local probe_log="$probe_parent/outer-driver.log"
  local outer_pid probe_rc ready_try started elapsed
  mkdir -p "$probe_parent"
  bash "$SELF" __outer_driver_signal_target "$probe_parent" "$marker" "$wrapper_ready" "$nested_ready" >"$probe_log" 2>&1 &
  outer_pid=$!
  for ready_try in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40; do
    if [ -s "$wrapper_ready" ] && [ -s "$nested_ready" ]; then
      break
    fi
    kill -0 "$outer_pid" 2>/dev/null || { cat "$probe_log" >&2; fail "outer-driver signal target exited before readiness"; }
    sleep 0.05
  done
  [ -s "$wrapper_ready" ] && [ -s "$nested_ready" ] \
    || { kill -TERM "$outer_pid" 2>/dev/null || true; wait "$outer_pid" 2>/dev/null || true; fail "outer-driver signal target readiness timed out"; }
  [ "$(find "$probe_parent" -name '.scholar-auto-research-owned-root.json' | wc -l | tr -d ' ')" -eq 2 ] \
    || { kill -TERM "$outer_pid" 2>/dev/null || true; wait "$outer_pid" 2>/dev/null || true; fail "outer-driver signal target did not create outer and nested sentinel roots"; }
  started="$(date +%s)"
  kill -TERM "$outer_pid"
  if wait "$outer_pid"; then
    probe_rc=0
  else
    probe_rc=$?
  fi
  elapsed=$(( $(date +%s) - started ))
  [ "$probe_rc" -eq 143 ] || { cat "$probe_log" >&2; fail "outer-driver TERM probe returned rc=$probe_rc"; }
  [ "$elapsed" -le 3 ] || fail "outer-driver TERM probe was not prompt: ${elapsed}s"
  sleep 2.2
  [ ! -e "$marker" ] || fail "outer-driver TERM probe left delayed marked grandchild alive"
  [ -z "$(find "$probe_parent" -name '.scholar-auto-research-owned-root.json' -print -quit)" ] \
    || fail "outer-driver TERM probe left outer or nested sentinel root"
  printf 'F20_P6_OUTER_SIGNAL_PROBE=PASS\n'
}

if [ "${1:-}" = "__outer_driver_signal_target" ]; then
  [ "$#" -eq 5 ] || { printf 'F20_P6_OUTER_SIGNAL_PROBE_USAGE\n' >&2; exit 99; }
  probe_parent="$2" marker="$3" wrapper_ready="$4" nested_ready="$5"
  export SCHOLAR_KEEP_FIXTURE=0
  export TMPDIR="$probe_parent"
  source "$HARNESS"
  harness_make_temp_root OUTER_SIGNAL_ROOT "f20 outer signal" || exit 1
  _f20_install_outer_signal_traps
  nested_parent="$OUTER_SIGNAL_ROOT/nested-parent"
  nested_script="$OUTER_SIGNAL_ROOT/nested-signal-child.sh"
  mkdir -p "$nested_parent"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'source "$1"' \
    'harness_make_temp_root NESTED_SIGNAL_ROOT "f20 nested signal"' \
    'printf ready > "$3"' '(sleep 2; printf marked > "$2") &' 'wait' >"$nested_script"
  chmod +x "$nested_script"
  _F20_WRAPPER_READY_FILE="$wrapper_ready"
  run_bounded 30 env TMPDIR="$nested_parent" SCHOLAR_KEEP_FIXTURE=1 \
    bash "$nested_script" "$HARNESS" "$marker" "$nested_ready"
  printf 'F20_P6_OUTER_SIGNAL_TARGET_UNEXPECTED_RETURN\n' >&2
  exit 96
fi

validate_verifier_syntax() {
  local verifier="$1"
  bash -n "$verifier"
  PYTHONPYCACHEPREFIX="$TMP_ROOT/embedded-pycache" python3 - "$verifier" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "<<'PY'\n"
if text.count(marker) != 1 or not text.endswith("\nPY\n"):
    raise SystemExit("embedded verifier Python heredoc is not uniquely bounded")
payload = text.split(marker, 1)[1][:-4]
compile(payload, str(path) + ":embedded-python", "exec")
PY
}

mutation_diagnostic() {
  case "$1" in
    bridge_obligation) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: bridge_obligation copied verifier accepted operator-specific invalid fixture' ;;
    paragraph_scope) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: paragraph_scope copied verifier accepted operator-specific invalid fixture' ;;
    raw_global_scope) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: raw_global_scope copied verifier accepted operator-specific invalid fixture' ;;
    whole_table_membership) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: whole_table_membership copied verifier accepted operator-specific invalid fixture' ;;
    unordered_token_bag) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: unordered_token_bag copied verifier accepted operator-specific invalid fixture' ;;
    sign_preservation) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: sign_preservation copied verifier accepted operator-specific invalid fixture' ;;
    display_comparison) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: display_comparison copied verifier accepted operator-specific invalid fixture' ;;
    phase14_partial) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: phase14_partial copied verifier accepted operator-specific invalid fixture' ;;
    phase15_partial) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: phase15_partial copied verifier accepted operator-specific invalid fixture' ;;
    manifest_masking) printf '%s\n' 'F20_P6_MUTANT_ACCEPTED: manifest_masking copied verifier accepted operator-specific invalid fixture' ;;
    *) printf 'F20_P6_MUTATION_ORACLE_UNKNOWN: %s\n' "$1" >&2; return 1 ;;
  esac
}

# Trusted inversion oracle. A mutant is killed only by an rc=0 from the
# mutated production verifier. Any rejection, crash, timeout, or wrong reason
# is rc=98 and therefore fails the enclosing expect_reject assertion.
if [ "${1:-}" = "__mutation_oracle" ] || [ "${1:-}" = "__mutation_oracle_probe" ]; then
  [ "$#" -eq 9 ] || { printf 'F20_P6_MUTATION_ORACLE_USAGE\n' >&2; exit 99; }
  operator="$2" verifier="$3" phase="$4" project="$5"
  trusted_project="$6" trusted_transcript="$7" candidate_transcript="$8" candidate_stderr="$9"
  oracle_deadline="$F20_P6_VERIFIER_TIMEOUT_SECONDS"
  [ "$1" != "__mutation_oracle_probe" ] || oracle_deadline="$F20_P6_PROBE_TIMEOUT_SECONDS"
  if run_bounded "$oracle_deadline" bash "$verifier" "$phase" "$project" >"$candidate_transcript" 2>"$candidate_stderr"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    if [ ! -s "$candidate_stderr" ] \
      && validate_verifier_transcript "$verifier" "$phase" "$project" "$candidate_transcript" "$trusted_project" "$trusted_transcript"; then
      mutation_diagnostic "$operator"
      exit 97
    fi
    [ ! -s "$candidate_stderr" ] || { printf 'F20_P6_TRANSCRIPT_INVALID: verifier stderr must be empty on rc0\n' >&2; cat "$candidate_stderr" >&2; }
    cat "$candidate_transcript" >&2
    printf 'F20_P6_MUTANT_NOT_KILLED: %s verifier_rc=0 transcript=invalid\n' "$operator" >&2
    exit 98
  fi
  [ ! -s "$candidate_transcript" ] || cat "$candidate_transcript" >&2
  [ ! -s "$candidate_stderr" ] || cat "$candidate_stderr" >&2
  printf 'F20_P6_MUTANT_NOT_KILLED: %s verifier_rc=%s\n' "$operator" "$rc" >&2
  exit 98
fi

source "$HARNESS"
harness_make_temp_root TMP_ROOT "phase13 locked-claim mutations" || exit 1
_f20_install_outer_signal_traps
MUTANT_ROOT="$TMP_ROOT/F20-P6-SENTINEL-OWNED"
mkdir -p "$MUTANT_ROOT"
configure_coverage_lint_authority

if [ -z "${SCHOLAR_HARNESS_SOURCE_ROOT:-}" ]; then
  export SCHOLAR_HARNESS_SOURCE_ROOT="$SKILL_DIR"
  export SCHOLAR_HARNESS_MANIFEST="$MANIFEST"
  export SCHOLAR_HARNESS_RESULTS_DIR="$TMP_ROOT/results"
  export SCHOLAR_HARNESS_RUN_ID="phase13-locked-claim-mutations-$$"
  export SCHOLAR_HARNESS_RUN_NONCE="phase13-locked-claim-mutations-$$-$(date +%s)"
  export SCHOLAR_HARNESS_SUITE_MODE="heavy-only"
  export SCHOLAR_HARNESS_SUITE_ORDER="normal"
  export SCHOLAR_HARNESS_MANIFEST_SHA256="$(python3 "$CASE_TOOL" digest-file "$MANIFEST")"
  export SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256="$(python3 "$CASE_TOOL" source-digest "$SKILL_DIR")"
fi
harness_init "$SELF" "phase13-locked-claim-mutations" || exit 1
run_outer_driver_signal_probe
run_lifecycle_probes

validate_verifier_syntax "$VERIFY"
PYTHONPYCACHEPREFIX="$TMP_ROOT/pycache" python3 -m py_compile "$CASE_TOOL"
LIVE_SOURCE_FROZEN="$(python3 "$CASE_TOOL" source-digest "$SKILL_DIR")"

GOOD="$TMP_ROOT/pristine-good"
BOOTSTRAP_LOG="$TMP_ROOT/phase0-15-bootstrap.log"
BOOTSTRAP_PARENT="$TMP_ROOT/bootstrap-owned-parent"
mkdir -p "$BOOTSTRAP_PARENT"
if run_bounded "$F20_P6_BOOTSTRAP_TIMEOUT_SECONDS" env \
  -u SCHOLAR_HARNESS_SOURCE_ROOT -u SCHOLAR_HARNESS_MANIFEST \
  -u SCHOLAR_HARNESS_RESULTS_DIR -u SCHOLAR_HARNESS_RUN_ID \
  -u SCHOLAR_HARNESS_RUN_NONCE -u SCHOLAR_HARNESS_SUITE_MODE \
  -u SCHOLAR_HARNESS_SUITE_ORDER -u SCHOLAR_HARNESS_MANIFEST_SHA256 \
  -u SCHOLAR_HARNESS_SOURCE_GENERATION_SHA256 \
  TMPDIR="$BOOTSTRAP_PARENT" \
  SCHOLAR_KEEP_FIXTURE=1 SCHOLAR_FIXTURE_STOP_AFTER_PHASE=15 SCHOLAR_RUN_HTML_AUTO=0 \
  bash "$FULL_FIXTURE" >"$BOOTSTRAP_LOG" 2>&1; then
  BOOTSTRAP_RC=0
else
  BOOTSTRAP_RC=$?
fi
if [ "$BOOTSTRAP_RC" -ne 0 ]; then
  if grep -q '^HARNESS_FIXTURE_PRESERVED=' "$BOOTSTRAP_LOG"; then
    cleanup_preserved_root_from_log "$BOOTSTRAP_LOG" "$BOOTSTRAP_PARENT" \
      || fail "failed bootstrap residue could not be cleaned"
  fi
  tail -80 "$BOOTSTRAP_LOG" >&2
  fail "Phase 0-15 bootstrap fixture failed rc=$BOOTSTRAP_RC"
fi
BOOTSTRAP_ROOT="$(grep -F 'HARNESS_FIXTURE_PRESERVED=' "$BOOTSTRAP_LOG" | tail -1 | cut -d= -f2-)"
[ -n "$BOOTSTRAP_ROOT" ] && [ -d "$BOOTSTRAP_ROOT/citation-project" ] \
  || fail "Phase 0-15 bootstrap did not preserve citation-project"
cp -R "$BOOTSTRAP_ROOT/citation-project" "$GOOD"
cleanup_preserved_root_from_log "$BOOTSTRAP_LOG" "$BOOTSTRAP_PARENT" \
  || fail "successful bootstrap residue could not be cleaned"
[ ! -e "$BOOTSTRAP_ROOT" ] || fail "successful bootstrap root survived cleanup"

# Phase 15's production contract requires at least one keyed citation
# authority. Build the same deterministic read-only Zotero authority used by
# the full fixture; CrossRef remains explicitly unavailable rather than mocked.
FIXTURE_ZOTERO_DIR="$TMP_ROOT/zotero-authority"
mkdir -p "$FIXTURE_ZOTERO_DIR"
python3 - "$FIXTURE_ZOTERO_DIR/zotero.sqlite" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""
CREATE TABLE itemTypes (itemTypeID INTEGER PRIMARY KEY, typeName TEXT);
CREATE TABLE items (itemID INTEGER PRIMARY KEY, itemTypeID INTEGER);
CREATE TABLE fields (fieldID INTEGER PRIMARY KEY, fieldName TEXT);
CREATE TABLE itemDataValues (valueID INTEGER PRIMARY KEY, value TEXT);
CREATE TABLE itemData (itemID INTEGER, fieldID INTEGER, valueID INTEGER);
CREATE TABLE creators (creatorID INTEGER PRIMARY KEY, lastName TEXT);
CREATE TABLE itemCreators (itemID INTEGER, creatorID INTEGER, orderIndex INTEGER);
CREATE TABLE deletedItems (itemID INTEGER);
INSERT INTO itemTypes VALUES (1, 'journalArticle');
INSERT INTO fields VALUES (1, 'title'), (2, 'date');
INSERT INTO creators VALUES (1, 'Author');
""")
for item_id in range(1, 31):
    title_id, date_id = item_id * 2 - 1, item_id * 2
    db.execute("INSERT INTO items VALUES (?, 1)", (item_id,))
    db.execute("INSERT INTO itemDataValues VALUES (?, ?)", (title_id, f"Verified citation fixture for work{item_id:02d}"))
    db.execute("INSERT INTO itemDataValues VALUES (?, '2020')", (date_id,))
    db.execute("INSERT INTO itemData VALUES (?, 1, ?)", (item_id, title_id))
    db.execute("INSERT INTO itemData VALUES (?, 2, ?)", (item_id, date_id))
    db.execute("INSERT INTO itemCreators VALUES (?, 1, 0)", (item_id,))
db.commit(); db.close()
PY
export SCHOLAR_ZOTERO_DIR="$FIXTURE_ZOTERO_DIR"
FIXTURE_BIN="$TMP_ROOT/fixture-bin"
mkdir -p "$FIXTURE_BIN"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FIXTURE_BIN/curl"
chmod +x "$FIXTURE_BIN/curl"
export PATH="$FIXTURE_BIN:$PATH"

make_bad_fixture() {
  local operator="$1" target="$TMP_ROOT/bad-$1"
  cp -R "$GOOD" "$target"
  python3 - "$operator" "$target" <<'PY'
import copy
import hashlib
import json
import re
import sys
from pathlib import Path

operator, root_arg = sys.argv[1:]
root = Path(root_arg)

def load(rel):
    path = root / rel
    return path, json.loads(path.read_text(encoding="utf-8"))

def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")

def digest(rel):
    return hashlib.sha256((root / rel).read_bytes()).hexdigest()

manifest_path, manifest = load("manuscript/draft-manifest.json")
draft_path = root / "manuscript/manuscript-draft.md"
text = draft_path.read_text(encoding="utf-8")

if operator == "bridge_obligation":
    manifest["locked_result_claims"] = []
elif operator == "paragraph_scope":
    old = "a p-value of 0.003, and n = 1200 [@work01]."
    new = "n = 1200 [@work01]. The neighboring audit sentence reports a p-value of 0.003 for the audit."
    assert text.count(old) == 1
    draft_path.write_text(text.replace(old, new, 1), encoding="utf-8")
elif operator == "raw_global_scope":
    manifest["locked_result_claims"][0]["rows"][0]["manuscript_anchor"] = "Hidden primary claim anchor"
    hidden = "\n<!-- Hidden primary claim anchor reports a negative estimate of -0.120, a standard error of 0.040, a p-value of 0.003, and n = 1200 for the audit. -->\n"
    draft_path.write_text(text + hidden, encoding="utf-8")
elif operator == "whole_table_membership":
    replacements = {
        "| Parental job loss | -0.120 (0.040) | -0.080 (0.050) | -0.090 (0.045) |":
        "| Parental job loss | -0.120 (0.040) | -0.090 (0.045) | -0.080 (0.050) |",
        "| p-value | 0.003 | 0.110 | 0.046 |": "| p-value | 0.003 | 0.046 | 0.110 |",
    }
    for old, new in replacements.items():
        assert text.count(old) == 1
        text = text.replace(old, new, 1)
    draft_path.write_text(text, encoding="utf-8")
elif operator == "unordered_token_bag":
    old = "negative estimate of -0.080, a standard error of 0.050, a p-value of 0.110"
    new = "negative estimate of 0.050, a standard error of -0.080, a p-value of 0.110"
    assert text.count(old) == 1
    draft_path.write_text(text.replace(old, new, 1), encoding="utf-8")
elif operator == "sign_preservation":
    import csv
    import io
    def manifest_hash(doc):
        payload = dict(doc); payload.pop("manifest_sha256", None)
        return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    def replace_exact(value, replacements):
        if isinstance(value, dict): return {key: replace_exact(item, replacements) for key, item in value.items()}
        if isinstance(value, list): return [replace_exact(item, replacements) for item in value]
        return replacements.get(value, value) if isinstance(value, str) else value
    def set_s1_estimate(path):
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle); fields = reader.fieldnames; rows = list(reader)
        assert fields and sum(row.get("spec_id") == "S1" for row in rows) == 1
        next(row for row in rows if row.get("spec_id") == "S1")["estimate"] = "-0.0004"
        buffer = io.StringIO(newline="")
        writer = csv.DictWriter(buffer, fieldnames=fields, lineterminator="\n")
        writer.writeheader(); writer.writerows(rows); path.write_text(buffer.getvalue(), encoding="utf-8")
    execution_path = root / "analysis/execution-report.json"
    post_path = root / "review/post-execution-review.json"
    sanity_path = root / "verify/runtime-sanity.json"
    lock_path = root / "results-locked/manifest.json"
    stage1_path = root / "verify/stage1-verify.json"
    blueprint_path = root / "manuscript/manuscript-blueprint.json"
    old_execution_hash, old_post_hash = digest("analysis/execution-report.json"), digest("review/post-execution-review.json")
    old_sanity_hash, old_lock_hash = digest("verify/runtime-sanity.json"), digest("results-locked/manifest.json")
    old_stage1_hash = digest("verify/stage1-verify.json")
    lock = json.loads(lock_path.read_text())
    registry = next(item for item in lock["locked_artifacts"] if item.get("artifact_role") == "results_registry")
    source_registry, locked_registry = root / registry["source_path"], root / registry["locked_path"]
    old_registry_hash = hashlib.sha256(source_registry.read_bytes()).hexdigest()
    set_s1_estimate(source_registry)
    registry_hash = hashlib.sha256(source_registry.read_bytes()).hexdigest()
    execution = replace_exact(json.loads(execution_path.read_text()), {old_registry_hash: registry_hash})
    execution_path.write_text(json.dumps(execution, indent=2, sort_keys=True) + "\n")
    execution_hash = hashlib.sha256(execution_path.read_bytes()).hexdigest()
    post = replace_exact(json.loads(post_path.read_text()), {old_registry_hash: registry_hash, old_execution_hash: execution_hash})
    next(item for item in post["reviewed_specs"] if item.get("spec_id") == "S1")["estimate"] = "-0.0004"
    post_path.write_text(json.dumps(post, indent=2, sort_keys=True) + "\n")
    post_hash = hashlib.sha256(post_path.read_bytes()).hexdigest()
    sanity = replace_exact(json.loads(sanity_path.read_text()), {old_registry_hash: registry_hash, old_execution_hash: execution_hash, old_post_hash: post_hash})
    sanity_path.write_text(json.dumps(sanity, indent=2, sort_keys=True) + "\n")
    sanity_hash = hashlib.sha256(sanity_path.read_bytes()).hexdigest()
    lock = replace_exact(lock, {old_registry_hash: registry_hash, old_execution_hash: execution_hash, old_post_hash: post_hash, old_sanity_hash: sanity_hash})
    for artifact in (registry["source_path"], "analysis/execution-report.json", "review/post-execution-review.json"):
        artifact_lock = next(item for item in lock["locked_artifacts"] if item.get("source_path") == artifact)
        (root / artifact_lock["locked_path"]).write_bytes((root / artifact).read_bytes())
    lock["manifest_sha256"] = manifest_hash(lock)
    lock_path.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")
    lock_hash = hashlib.sha256(lock_path.read_bytes()).hexdigest()
    stage1 = replace_exact(json.loads(stage1_path.read_text()), {old_registry_hash: registry_hash, old_execution_hash: execution_hash, old_post_hash: post_hash})
    stage1["manifest_sha256"] = lock["manifest_sha256"]
    stage1["input_manifest_sha256"] = lock["manifest_sha256"]
    stage1_path.write_text(json.dumps(stage1, indent=2, sort_keys=True) + "\n")
    stage1_hash = hashlib.sha256(stage1_path.read_bytes()).hexdigest()
    blueprint = replace_exact(json.loads(blueprint_path.read_text()), {old_registry_hash: registry_hash, old_lock_hash: lock_hash, old_stage1_hash: stage1_hash, old_post_hash: post_hash})
    blueprint["lock_manifest_sha256"] = lock["manifest_sha256"]
    blueprint_path.write_text(json.dumps(blueprint, indent=2, sort_keys=True) + "\n")
    blueprint_hash = hashlib.sha256(blueprint_path.read_bytes()).hexdigest()
    old_table = "| Parental job loss | -0.120 (0.040) |"
    old_prose = "an estimate of -0.120, a standard error of 0.040"
    assert text.count(old_table) == 1 and text.count(old_prose) == 1
    text = text.replace(old_table, "| Parental job loss | 0.000 (0.040) |", 1)
    text = text.replace(old_prose, "an estimate of 0.000, a standard error of 0.040", 1)
    draft_path.write_text(text, encoding="utf-8")
    coverage = next(item for item in manifest["locked_result_coverage"] if item.get("artifact_role") == "main_regression_table")
    coverage["claim_source"]["sha256"] = registry_hash
    row = next(item for item in manifest["locked_result_claims"][0]["rows"] if item.get("spec_id") == "S1")
    row["estimate"] = "-0.0004"
    manifest["lock_manifest_sha256"] = lock["manifest_sha256"]
    manifest["blueprint"]["sha256"] = blueprint_hash
    manifest["source_hashes"].update(lock_manifest=lock_hash, stage1_verify=stage1_hash, manuscript_blueprint=blueprint_hash, post_execution_review=post_hash)
elif operator == "display_comparison":
    old = "| Parental job loss | -0.120 (0.040) |"
    assert text.count(old) == 1
    draft_path.write_text(text.replace(old, "| Parental job loss | -0.121 (0.040) |", 1), encoding="utf-8")
elif operator == "phase14_partial":
    report_path, report = load("verify/manuscript-verification.json")
    stage2 = report["stage_2_manuscript_to_prose"]
    stage2["checked"] = stage2["checked"][:-1]
    stage2["claims_scanned"] = len(stage2["checked"])
    report["scanned"] = report["stage_1_outputs_to_manuscript"]["items_scanned"] + stage2["claims_scanned"]
    save(report_path, report)
elif operator == "phase15_partial":
    claim_path, claim_map = load("citation/claim-source-map.json")
    claim_index = next(i for i, row in enumerate(claim_map["claims"]) if row.get("claim_type") == "empirical" and row.get("citation_keys") == ["work03"])
    removed = claim_map["claims"][claim_index]
    replacement = copy.deepcopy(removed)
    replacement.pop("result_binding", None)
    replacement["claim_id"] = "f20-partial-work03-support"
    replacement["claim_type"] = "result_interpretation"
    replacement["claim_text"] = "The attrition-weighted specification remains negative with uneven robustness."
    replacement["manuscript_anchor"] = "For Model 3, the attrition-weighted specification has a negative estimate of -0.090, a standard error of 0.045, a p-value of 0.046, and n = 1200 [@work03]."
    claim_map["claims"][claim_index] = replacement
    save(claim_path, claim_map)
    audit_path, audit = load("citation/citation-audit.json")
    audit["source_hashes"]["claim_source_map"] = hashlib.sha256(claim_path.read_bytes()).hexdigest()
    save(audit_path, audit)
elif operator == "manifest_masking":
    diagnostic = next(row for row in manifest["locked_result_coverage"] if row.get("artifact_role") == "diagnostic")
    diagnostic["mask_start"] = "<!-- F20_FORGED_MASK_START -->"
    diagnostic["mask_end"] = "<!-- F20_FORGED_MASK_END -->"
    forged = """
<!-- F20_FORGED_MASK_START -->
| Estimate | Standard Error | p-value | N |
| ---: | ---: | ---: | ---: |
| -0.120 | 0.040 | 0.003 | 1200 |
<!-- F20_FORGED_MASK_END -->
"""
    assert text.count("\n## Discussion") == 1
    draft_path.write_text(text.replace("\n## Discussion", forged + "\n## Discussion", 1), encoding="utf-8")
else:
    raise SystemExit(f"unknown fixture operator: {operator}")

# Phase 13 authenticates the manuscript in its manifest. Phases 14/15 also
# authenticate both Phase 13 inputs; update only those legitimate derived
# hashes, never semantic claims or the invalid payload itself.
current_manuscript_hash = digest("manuscript/manuscript-draft.md")
if manifest.get("selected_manuscript_hash") != current_manuscript_hash:
    polish_path, polish = load("manuscript/polish-report.json")
    polish["source_manuscript_hash"] = current_manuscript_hash
    polish["polished_manuscript_hash"] = current_manuscript_hash
    save(polish_path, polish)
    def wc(value): return len(re.findall(r"\b[\w'-]+\b", value))
    def prose_only(value):
        value = re.sub(r"<!--.*?-->", " ", value, flags=re.DOTALL)
        value = re.sub(r"(?is)<table\b.*?</table>", " ", value)
        value = re.sub(r"!\[[^\]]*\]\([^)]+\)", " ", value)
        value = re.sub(r"\[[^\]]+\]\([^)]+\)", " ", value)
        return "\n".join(line for line in value.splitlines() if not line.strip().startswith("|") and not re.match(r"^(?:\*\*)?(?:Table|Figure)\s+\d+[.:]", line.strip(), re.I) and not re.match(r"^Notes?:", line.strip(), re.I))
    sections, current, buffer = {}, None, []
    for line in draft_path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            if current is not None: sections[current] = "\n".join(buffer)
            current = re.sub(r"[^a-z0-9]+", " ", match.group(1).lower()).strip(); buffer = []
        elif current is not None: buffer.append(line)
    if current is not None: sections[current] = "\n".join(buffer)
    raw_counts = {key: wc(value) for key, value in sections.items()}
    prose_counts = {key: wc(prose_only(value)) for key, value in sections.items()}
    manifest["polish_report"]["sha256"] = hashlib.sha256(polish_path.read_bytes()).hexdigest()
    manifest["section_word_counts"] = raw_counts
    manifest["section_prose_word_counts"] = prose_counts
    main_sections = tuple(manifest.get("section_word_budget", {}).keys())
    whole_text = draft_path.read_text(encoding="utf-8")
    manifest["budget_compliance"]["total_word_count"] = wc(whole_text)
    manifest["budget_compliance"]["main_text_word_count"] = sum(prose_counts.get(section, 0) for section in main_sections)
    for section, count in raw_counts.items():
        if section in manifest["budget_compliance"].get("sections", {}):
            manifest["budget_compliance"]["sections"][section]["words"] = count
            manifest["budget_compliance"]["sections"][section]["prose_words"] = prose_counts.get(section, 0)
    sentence_counts = {}
    for sentence in re.split(r"(?<=[.!?])\s+", re.sub(r"<!--.*?-->", " ", whole_text, flags=re.DOTALL)):
        normalized = re.sub(r"[^a-z0-9]+", " ", sentence.lower()).strip()
        if wc(normalized) >= 8: sentence_counts[normalized] = sentence_counts.get(normalized, 0) + 1
    manifest["draft_quality_gate"]["max_repeated_sentence_count"] = max(sentence_counts.values(), default=0)
manifest["selected_manuscript_hash"] = current_manuscript_hash
save(manifest_path, manifest)
if operator == "phase14_partial":
    pass
elif operator == "phase15_partial_duplicate":
    pass
PY
  printf '%s\n' "$target"
}

for operator in bridge_obligation paragraph_scope raw_global_scope whole_table_membership unordered_token_bag sign_preservation display_comparison phase14_partial phase15_partial manifest_masking; do
  make_bad_fixture "$operator" >/dev/null
done
# The Phase 0-15 bootstrap project already carries authentic Phase 14 review
# evidence; cloning preserves that immutable prerequisite for every operator.

phase_for() {
  case "$1" in
    phase14_partial) printf '14\n' ;;
    phase15_partial) printf '15\n' ;;
    *) printf '13\n' ;;
  esac
}

diagnostic_for() {
  case "$1" in
    bridge_obligation|raw_global_scope) printf '%s\n' 'FAIL: Phase 13 locked result claims do not exactly cover mapped rows' ;;
    paragraph_scope|whole_table_membership|unordered_token_bag|sign_preservation|display_comparison) printf '%s\n' 'FAIL: Phase 13 locked numeric claims do not match visible Results evidence' ;;
    phase14_partial) printf '%s\n' 'FAIL: Phase 14 Stage 2 checks must exactly cover Phase 13 locked result claims' ;;
    phase15_partial) printf '%s\n' 'FAIL: Phase 15 claim-source map must exactly cover every Phase 13 empirical row claim' ;;
    manifest_masking) printf '%s\n' 'FAIL: Phase 13 manuscript uses registry/model-ladder evidence as reader-facing empirical tables' ;;
    *) fail "unknown diagnostic operator: $1" ;;
  esac
}

prepare_mutant() {
  local operator="$1"
  MUTANT_SKILL="$MUTANT_ROOT/$operator/scholar-auto-research"
  MUTANT_VERIFY="$MUTANT_SKILL/scripts/auto-research-verify.sh"
  mkdir -p "$(dirname "$MUTANT_SKILL")"
  cp -R "$SKILL_DIR" "$MUTANT_SKILL"
  MUTANT_PRISTINE="$(python3 "$CASE_TOOL" source-digest "$MUTANT_SKILL")"
  [ "$MUTANT_PRISTINE" = "$LIVE_SOURCE_FROZEN" ] || fail "$operator pristine copied inventory differs from frozen live inventory"
  validate_verifier_syntax "$MUTANT_VERIFY"
}

apply_mutation() {
  local operator="$1"
  python3 - "$MUTANT_SKILL" "$operator" <<'PY'
import hashlib
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve(strict=True)
operator = sys.argv[2]
target = root / "scripts/auto-research-verify.sh"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inventory():
    result = {}
    for path in sorted(root.rglob("*"), key=lambda item: os.fsencode(item.relative_to(root).as_posix())):
        rel = path.relative_to(root).as_posix()
        info = path.lstat()
        item = {"mode": f"{stat.S_IMODE(info.st_mode):04o}"}
        if path.is_symlink(): item.update(type="symlink", target=os.readlink(path))
        elif path.is_dir(): item["type"] = "directory"
        elif path.is_file(): item.update(type="file", sha256=sha(path), size=info.st_size)
        else: raise SystemExit(f"special file in copied skill: {rel}")
        result[rel] = item
    return result

mutations = {
"bridge_obligation": (
'''        expected_groups[(display_source, value_source)] = (coverage_item, bridge, mapped)\n''',
'''        if any(isinstance(_claim_group, dict) and str(_claim_group.get("display_source_path", "")).strip() == display_source and str(_claim_group.get("source_path", "")).strip() == value_source for _claim_group in claims):\n            expected_groups[(display_source, value_source)] = (coverage_item, bridge, mapped)  # F20 P6 mutant: obligation follows self-declared claims\n'''),
"paragraph_scope": (
'''            sentence = result_matches[0]["sentence"]\n''',
'''            sentence = result_matches[0]["sentence"]\n            if "p-value" not in sentence.lower():\n                sentence = next((claim_norm(_paragraph) for _paragraph in prose_paragraphs(results_text, min_words=1) if anchor in claim_norm(_paragraph)), sentence)  # F20 P6 mutant: paragraph-wide fallback\n'''),
"raw_global_scope": (
'''    sentence_records = substantive_sentence_locations(manuscript_text)\n''',
'''    sentence_records = [{"sentence": claim_norm(_sentence), "section": "results", "line_start": _index} for _index, _sentence in enumerate(re.split(r"(?<=[.!?])\\s+", manuscript_text)) if claim_norm(_sentence)]\n'''),
"whole_table_membership": (
'''                display_token = display_values[field]\n''',
'''                display_token = display_values[field]\n                for _candidate_mapping in mapped:\n                    _candidate_token = _candidate_mapping[5][field]\n                    _probe_issues = []\n                    if reported_value_matches(locked_value, _candidate_token, field, _probe_issues, "whole-table mutant") and not _probe_issues:\n                        display_token = _candidate_token\n                        break\n'''),
"unordered_token_bag": (
'''            for field, pattern in patterns.items():\n                raw_values = re.findall(pattern, sentence, flags=re.I)\n                values = raw_values\n                if len(values) != 1 or not reported_value_matches(source_row.get(field, ""), values[0] if values else "", field, numeric_issues, f"{expected_id}:prose:{field}"):\n                    numeric_issues.append(f"{expected_id}: prose {field} mismatch")\n            p_exact = re.findall(rf"(?<![A-Za-z])(?:p-value|p)(?![A-Za-z])\\s*(?:of|=)\\s*{bounded_number}", sentence, flags=re.I)\n            p_inequality = re.findall(rf"(?<![A-Za-z])(?:p-value|p)(?![A-Za-z])\\s*<\\s*{bounded_number}", sentence, flags=re.I)\n            p_values = list(p_exact) + ["p < " + value for value in p_inequality]\n            if len(p_values) != 1 or not reported_value_matches(source_row.get("p_value", ""), p_values[0] if p_values else "", "p_value", numeric_issues, f"{expected_id}:prose:p_value"):\n                numeric_issues.append(f"{expected_id}: prose p_value mismatch")\n''',
'''            _bag = re.findall(bounded_number, sentence)\n            for field in ("estimate", "std_error", "p_value"):\n                _matched = False\n                for _token in _bag:\n                    _probe_issues = []\n                    if reported_value_matches(source_row.get(field, ""), _token, field, _probe_issues, "unordered-bag mutant") and not _probe_issues:\n                        _matched = True\n                        break\n                if not _matched:\n                    numeric_issues.append(f"{expected_id}: prose {field} mismatch")\n            _n_values = re.findall(bounded_n, sentence)\n            if not any(reported_value_matches(source_row.get("n", ""), _token, "n", [], "unordered-bag mutant") for _token in _n_values):\n                numeric_issues.append(f"{expected_id}: prose n mismatch")\n'''),
"sign_preservation": (
'''        if source != 0 and source.is_signed() != visible.is_signed():\n            return False\n''',
'''        if False and source != 0 and source.is_signed() != visible.is_signed():\n            return False\n'''),
"display_comparison": (
'''                if not reported_value_matches(locked_value, display_token, field, numeric_issues, f"{expected_id}:display:{field}"):\n                    numeric_issues.append(f"{expected_id}: display {field} mismatch")\n''',
'''                pass  # F20 P6 mutant: display-window comparison removed\n'''),
"phase14_partial": (
'''    if stage2_keys != expected_claim_keys:\n''',
'''    if not stage2_keys.issubset(expected_claim_keys):\n'''),
"phase15_partial": (
'''    if set(actual_empirical) != set(expected_empirical):\n''',
'''    expected_empirical = {claim_id: expected for claim_id, expected in expected_empirical.items() if claim_id in actual_empirical}  # F20 P6 mutant: missing empirical obligations dropped\n    if set(actual_empirical) != set(expected_empirical):\n'''),
"manifest_masking": (
'''    registry_display_issues = displayed_registry_sources_from_coverage(coverage) + registry_like_table_display_hits(manuscript_text)\n    if registry_display_issues:\n        fail("FAIL: Phase 13 manuscript uses registry/model-ladder evidence as reader-facing empirical tables", registry_display_issues[:25])\n''',
'''    registry_scan_text = manuscript_text\n    for _coverage_item in coverage:\n        _start = str(_coverage_item.get("mask_start", "")) if isinstance(_coverage_item, dict) else ""\n        _end = str(_coverage_item.get("mask_end", "")) if isinstance(_coverage_item, dict) else ""\n        if _start and _end and registry_scan_text.count(_start) == 1 and registry_scan_text.count(_end) == 1:\n            registry_scan_text = registry_scan_text.split(_start, 1)[0] + registry_scan_text.split(_end, 1)[1]\n    registry_display_issues = displayed_registry_sources_from_coverage(coverage) + registry_like_table_display_hits(registry_scan_text)\n    if registry_display_issues:\n        fail("FAIL: Phase 13 manuscript uses registry/model-ladder evidence as reader-facing empirical tables", registry_display_issues[:25])\n'''),
}

needle, replacement = mutations[operator]
before = inventory()
text = target.read_text(encoding="utf-8")
matches = text.count(needle)
if matches != 1:
    raise SystemExit(f"mutation target must match exactly once: operator={operator} matches={matches}")
target.write_text(text.replace(needle, replacement), encoding="utf-8")
after = inventory()
changed = sorted(path for path in set(before) | set(after) if before.get(path) != after.get(path))
if changed != ["scripts/auto-research-verify.sh"]:
    raise SystemExit(f"copy-only mutation violated: changed={changed}")
print("MUTATION_TARGET_MATCHES=1")
print("MUTATION_CHANGED_PATH=scripts/auto-research-verify.sh")
PY
  MUTANT_CHANGED="$(python3 "$CASE_TOOL" source-digest "$MUTANT_SKILL")"
  [ "$MUTANT_CHANGED" != "$MUTANT_PRISTINE" ] || fail "$operator mutation left copied inventory unchanged"
  [ "$(python3 "$CASE_TOOL" source-digest "$SKILL_DIR")" = "$LIVE_SOURCE_FROZEN" ] || fail "$operator changed frozen live source inventory"
  validate_verifier_syntax "$MUTANT_VERIFY"
  MUTATION_BINDING="operator=$operator,target_matches=1,changed=scripts/auto-research-verify.sh,before=$MUTANT_PRISTINE,after=$MUTANT_CHANGED"
}

run_transcript_oracle_probes() {
  local verifier="$1" phase="$2" project="$3" trusted="$4"
  local probe_skill="$MUTANT_ROOT/bridge_obligation/oracle-probe-skill"
  local fake_verifier="$probe_skill/scripts/auto-research-verify.sh"
  local invalid_descriptor="$MUTANT_ROOT/bridge_obligation/oracle-invalid-descriptor.txt"
  local candidate_stdout="$MUTANT_ROOT/bridge_obligation/oracle-probe.stdout"
  local candidate_stderr="$MUTANT_ROOT/bridge_obligation/oracle-probe.stderr"
  local probe_output probe_rc delayed_marker
  cp -R "$MUTANT_SKILL" "$probe_skill"

  inject_probe_verifier() {
    local mode="$1" payload="$2"
    python3 - "$MUTANT_VERIFY" "$fake_verifier" "$mode" "$payload" <<'PY'
import shlex
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
target = Path(sys.argv[2])
mode = sys.argv[3]
payload = shlex.quote(sys.argv[4])
needle = "set -euo pipefail\n"
if source.count(needle) != 1:
    raise SystemExit("copied full verifier has nonunique strict-mode line")
if mode == "extra":
    branch = f"cat {payload}\nprintf '%s\\n' 'UNRECOGNIZED EXTRA OUTPUT'\nexit 0\n"
elif mode == "transcript":
    branch = f"cat {payload}\nexit 0\n"
elif mode == "hang":
    branch = f"(sleep 2; printf marked > {payload}) &\nwait\nexit 0\n"
else:
    raise SystemExit(f"unknown probe verifier mode: {mode}")
target.write_text(source.replace(needle, needle + branch, 1), encoding="utf-8")
PY
    chmod +x "$fake_verifier"
  }

  # Exercise the real oracle path: a copied-skill rc0 verifier emits the exact
  # trusted transcript plus one unrecognized line. It must map to rc98.
  inject_probe_verifier extra "$trusted"
  if probe_output="$(bash "$SELF" __mutation_oracle bridge_obligation "$fake_verifier" "$phase" "$project" "$project" "$trusted" "$candidate_stdout" "$candidate_stderr" 2>&1)"; then
    probe_rc=0
  else
    probe_rc=$?
  fi
  [ "$probe_rc" -eq 98 ] \
    && [ "$(printf '%s\n' "$probe_output" | grep -c '^F20_P6_MUTANT_NOT_KILLED: bridge_obligation verifier_rc=0 transcript=invalid$' || true)" -eq 1 ] \
    || fail "actual oracle accepted copied-skill extra-output verifier"

  # Invalid descriptor content must likewise be rejected through the oracle,
  # not only by a direct parser unit check.
  python3 - "$trusted" "$invalid_descriptor" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
indexes = [index for index, line in enumerate(source) if line.startswith("VERIFICATION_DESCRIPTOR_JSON=")]
if len(indexes) != 1:
    raise SystemExit("trusted probe input lacks one descriptor")
source[indexes[0]] = "VERIFICATION_DESCRIPTOR_JSON={}"
Path(sys.argv[2]).write_text("\n".join(source) + "\n", encoding="utf-8")
PY
  inject_probe_verifier transcript "$invalid_descriptor"
  if probe_output="$(bash "$SELF" __mutation_oracle bridge_obligation "$fake_verifier" "$phase" "$project" "$project" "$trusted" "$candidate_stdout" "$candidate_stderr" 2>&1)"; then
    probe_rc=0
  else
    probe_rc=$?
  fi
  [ "$probe_rc" -eq 98 ] \
    && [ "$(printf '%s\n' "$probe_output" | grep -c '^F20_P6_MUTANT_NOT_KILLED: bridge_obligation verifier_rc=0 transcript=invalid$' || true)" -eq 1 ] \
    || fail "actual oracle accepted copied-skill invalid descriptor"

  # The private probe mode uses the same oracle body with a fixed one-second
  # deadline. Its marked delayed grandchild must be terminated before it can
  # create the marker, and the timeout must map to NOT_KILLED rc98.
  delayed_marker="$MUTANT_ROOT/bridge_obligation/oracle-delayed-grandchild.marker"
  inject_probe_verifier hang "$delayed_marker"
  if probe_output="$(bash "$SELF" __mutation_oracle_probe bridge_obligation "$fake_verifier" "$phase" "$project" "$project" "$trusted" "$candidate_stdout" "$candidate_stderr" 2>&1)"; then
    probe_rc=0
  else
    probe_rc=$?
  fi
  [ "$probe_rc" -eq 98 ] \
    && [ "$(printf '%s\n' "$probe_output" | grep -c '^F20_P6_MUTANT_NOT_KILLED: bridge_obligation verifier_rc=124$' || true)" -eq 1 ] \
    || fail "actual oracle timeout did not map to rc98 NOT_KILLED"
  sleep 1.5
  [ ! -e "$delayed_marker" ] || fail "oracle timeout left delayed marked grandchild alive"
  printf 'F20_P6_TRANSCRIPT_PROBES=PASS\n'
}

run_operator() {
  local operator="$1" phase invalid diagnostic
  phase="$(phase_for "$operator")"
  invalid="$TMP_ROOT/bad-$operator"
  diagnostic="$(diagnostic_for "$operator")"
  local invalid_digest good_digest trusted_stdout trusted_stderr mutant_stdout mutant_stderr candidate_stdout candidate_stderr
  invalid_digest="$(python3 "$CASE_TOOL" source-digest "$invalid")"
  good_digest="$(python3 "$CASE_TOOL" source-digest "$GOOD")"
  prepare_mutant "$operator"
  trusted_stdout="$MUTANT_ROOT/$operator/trusted-pristine.stdout"
  trusted_stderr="$MUTANT_ROOT/$operator/trusted-pristine.stderr"
  mutant_stdout="$MUTANT_ROOT/$operator/mutant-valid.stdout"
  mutant_stderr="$MUTANT_ROOT/$operator/mutant-valid.stderr"
  candidate_stdout="$MUTANT_ROOT/$operator/mutant-invalid.stdout"
  candidate_stderr="$MUTANT_ROOT/$operator/mutant-invalid.stderr"
  # CASE anchors below are static and intentionally repeated as explicit
  # declarations for coverage-manifest discovery.
  SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_PRISTINE" expect_pass "f20.mutation.$operator.pristine_positive" "$GOOD" -- observe_verifier "$trusted_stdout" "$trusted_stderr" bash "$MUTANT_VERIFY" "$phase" "$GOOD"
  [ ! -s "$trusted_stderr" ] || fail "$operator trusted pristine verifier emitted stderr on rc0"
  validate_verifier_transcript "$MUTANT_VERIFY" "$phase" "$GOOD" "$trusted_stdout" "$GOOD" "$trusted_stdout" \
    || fail "$operator trusted pristine transcript failed exact validation"
  if [ "$operator" = "bridge_obligation" ]; then
    run_transcript_oracle_probes "$MUTANT_VERIFY" "$phase" "$GOOD" "$trusted_stdout"
  fi
  SCHOLAR_HARNESS_MUTATION_VERDICT="pristine:$MUTANT_PRISTINE" SCHOLAR_HARNESS_EXPECTED_DIAGNOSTIC="$diagnostic" expect_reject "f20.mutation.$operator.pristine_negative" "$invalid" -- run_bounded "$F20_P6_VERIFIER_TIMEOUT_SECONDS" bash "$MUTANT_VERIFY" "$phase" "$invalid"
  apply_mutation "$operator"
  SCHOLAR_HARNESS_MUTATION_VERDICT="valid_control:$MUTATION_BINDING" expect_pass "f20.mutation.$operator.mutant_valid" "$GOOD" -- observe_verifier "$mutant_stdout" "$mutant_stderr" bash "$MUTANT_VERIFY" "$phase" "$GOOD"
  [ ! -s "$mutant_stderr" ] || fail "$operator mutant valid verifier emitted stderr on rc0"
  validate_verifier_transcript "$MUTANT_VERIFY" "$phase" "$GOOD" "$mutant_stdout" "$GOOD" "$trusted_stdout" \
    || fail "$operator mutant valid transcript differs from trusted pristine semantics"
  SCHOLAR_HARNESS_MUTATION_VERDICT="killed:$MUTATION_BINDING" expect_reject "f20.mutation.$operator.mutant_kill" "$invalid" -- bash "$SELF" __mutation_oracle "$operator" "$MUTANT_VERIFY" "$phase" "$invalid" "$GOOD" "$trusted_stdout" "$candidate_stdout" "$candidate_stderr"
  [ "$(python3 "$CASE_TOOL" source-digest "$invalid")" = "$invalid_digest" ] || fail "$operator invalid fixture changed between pristine and mutant observations"
  [ "$(python3 "$CASE_TOOL" source-digest "$GOOD")" = "$good_digest" ] || fail "$operator valid fixture changed between pristine and mutant observations"
  printf 'MUTATION_KILLED=%s\n' "$operator"
}

# The 40 static case anchors are consumed by coverage lint; run_operator emits
# exactly the corresponding authoritative records.
# CASE_ID: f20.mutation.bridge_obligation.pristine_positive
# CASE_ID: f20.mutation.bridge_obligation.pristine_negative
# CASE_ID: f20.mutation.bridge_obligation.mutant_valid
# CASE_ID: f20.mutation.bridge_obligation.mutant_kill
# CASE_ID: f20.mutation.paragraph_scope.pristine_positive
# CASE_ID: f20.mutation.paragraph_scope.pristine_negative
# CASE_ID: f20.mutation.paragraph_scope.mutant_valid
# CASE_ID: f20.mutation.paragraph_scope.mutant_kill
# CASE_ID: f20.mutation.raw_global_scope.pristine_positive
# CASE_ID: f20.mutation.raw_global_scope.pristine_negative
# CASE_ID: f20.mutation.raw_global_scope.mutant_valid
# CASE_ID: f20.mutation.raw_global_scope.mutant_kill
# CASE_ID: f20.mutation.whole_table_membership.pristine_positive
# CASE_ID: f20.mutation.whole_table_membership.pristine_negative
# CASE_ID: f20.mutation.whole_table_membership.mutant_valid
# CASE_ID: f20.mutation.whole_table_membership.mutant_kill
# CASE_ID: f20.mutation.unordered_token_bag.pristine_positive
# CASE_ID: f20.mutation.unordered_token_bag.pristine_negative
# CASE_ID: f20.mutation.unordered_token_bag.mutant_valid
# CASE_ID: f20.mutation.unordered_token_bag.mutant_kill
# CASE_ID: f20.mutation.sign_preservation.pristine_positive
# CASE_ID: f20.mutation.sign_preservation.pristine_negative
# CASE_ID: f20.mutation.sign_preservation.mutant_valid
# CASE_ID: f20.mutation.sign_preservation.mutant_kill
# CASE_ID: f20.mutation.display_comparison.pristine_positive
# CASE_ID: f20.mutation.display_comparison.pristine_negative
# CASE_ID: f20.mutation.display_comparison.mutant_valid
# CASE_ID: f20.mutation.display_comparison.mutant_kill
# CASE_ID: f20.mutation.phase14_partial.pristine_positive
# CASE_ID: f20.mutation.phase14_partial.pristine_negative
# CASE_ID: f20.mutation.phase14_partial.mutant_valid
# CASE_ID: f20.mutation.phase14_partial.mutant_kill
# CASE_ID: f20.mutation.phase15_partial.pristine_positive
# CASE_ID: f20.mutation.phase15_partial.pristine_negative
# CASE_ID: f20.mutation.phase15_partial.mutant_valid
# CASE_ID: f20.mutation.phase15_partial.mutant_kill
# CASE_ID: f20.mutation.manifest_masking.pristine_positive
# CASE_ID: f20.mutation.manifest_masking.pristine_negative
# CASE_ID: f20.mutation.manifest_masking.mutant_valid
# CASE_ID: f20.mutation.manifest_masking.mutant_kill

for operator in bridge_obligation paragraph_scope raw_global_scope whole_table_membership unordered_token_bag sign_preservation display_comparison phase14_partial phase15_partial manifest_masking; do
  run_operator "$operator"
done

# Installed-skill proof: no repository authority, Git command, or populated
# HOME is available. The packaged coverage test must select its generated
# canonical runner and pass entirely from the isolated skill closure.
ISOLATED_PARENT="$TMP_ROOT/isolated-no-git"
ISOLATED_SKILL="$ISOLATED_PARENT/scholar-auto-research"
NO_GIT_BIN="$TMP_ROOT/no-git-bin"
NO_GIT_MARKER="$TMP_ROOT/git-was-invoked.marker"
mkdir -p "$ISOLATED_PARENT" "$NO_GIT_BIN"
cp -R "$SKILL_DIR" "$ISOLATED_SKILL"
printf '#!/usr/bin/env bash\nprintf invoked > %q\nexit 97\n' "$NO_GIT_MARKER" >"$NO_GIT_BIN/git"
chmod +x "$NO_GIT_BIN/git"
ISOLATED_LINT_LOG="$TMP_ROOT/isolated-no-git-coverage.log"
if ! env -u SCHOLAR_AUTO_RESEARCH_REPO_ROOT \
  HOME="$LINT_HOME" PATH="$NO_GIT_BIN:$PATH" \
  SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR="$ISOLATED_SKILL" \
  /bin/bash "$ISOLATED_SKILL/tests/smoke/test-coverage-manifest.sh" >"$ISOLATED_LINT_LOG" 2>&1; then
  cat "$ISOLATED_LINT_LOG" >&2
  fail "isolated no-Git packaged coverage proof failed"
fi
grep -q '^coverage manifest lint: PASS$' "$ISOLATED_LINT_LOG" \
  || fail "isolated no-Git packaged coverage proof lacks PASS"
[ ! -e "$NO_GIT_MARKER" ] || fail "isolated packaged coverage proof invoked Git"
printf 'F20_P6_ISOLATED_NO_GIT=PASS\n'

# Bidirectional label/path proof: coverage lint must reject both a stale case
# label and a registry path that no longer matches the case path.
python3 - "$MANIFEST" "$TMP_ROOT" <<'PY'
import json, sys
from pathlib import Path
source = json.load(open(sys.argv[1], encoding="utf-8"))
root = Path(sys.argv[2])
label = json.loads(json.dumps(source))
label["cases"]["f20.mutation.bridge_obligation.pristine_positive"]["runner_label"] = "fixture-test"
(root / "bad-label.json").write_text(json.dumps(label), encoding="utf-8")
path = json.loads(json.dumps(source))
path["suite_registry"]["phase13-locked-claim-mutations"]["path"] = "tests/smoke/test-harness.sh"
(root / "bad-path.json").write_text(json.dumps(path), encoding="utf-8")
PY
for mutant_manifest in "$TMP_ROOT/bad-label.json" "$TMP_ROOT/bad-path.json"; do
  if [ -n "$REPO_ROOT" ]; then
    if lint_output="$(HOME="$LINT_HOME" python3 "$SKILL_DIR/tests/helpers/coverage_lint.py" --skill-dir "$SKILL_DIR" --manifest "$mutant_manifest" --suite-runner "$LINT_SUITE_RUNNER" --repo-root "$REPO_ROOT" 2>&1)"; then
      lint_rc=0
    else
      lint_rc=$?
    fi
  else
    if lint_output="$(HOME="$LINT_HOME" python3 "$SKILL_DIR/tests/helpers/coverage_lint.py" --skill-dir "$SKILL_DIR" --manifest "$mutant_manifest" --suite-runner "$LINT_SUITE_RUNNER" 2>&1)"; then
      lint_rc=0
    else
      lint_rc=$?
    fi
  fi
  [ "$lint_rc" -ne 0 ] || fail "coverage lint accepted label/path mismatch: $mutant_manifest"
  case "$lint_output" in *CASE_RUNNER_PATH_MISMATCH*|*RUNNER_PATH_MISMATCH*|*RUNNER_PATH_WITHOUT_CASE*|*CASE_RUNNER_LABEL_STALE*|*PACKAGED_TEST_PATH_SET_MISMATCH*) ;; *) fail "coverage lint rejected mismatch without structural diagnostic: $lint_output" ;; esac
done

harness_validate_results >/dev/null
[ "$(python3 "$CASE_TOOL" source-digest "$SKILL_DIR")" = "$LIVE_SOURCE_FROZEN" ] || fail "live source inventory changed after mutation suite"
find "$MUTANT_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | grep -Eq '^ *10$' || fail "sentinel-owned mutation copy count is not 10"
printf 'LIVE_SOURCE_DIGEST_UNCHANGED=%s\n' "$LIVE_SOURCE_FROZEN"
printf 'MUTATION_CLEANUP=sentinel-owned-root-trap\n'
printf 'PASS: all 10 Phase 13-15 locked-claim mutants killed\n'
