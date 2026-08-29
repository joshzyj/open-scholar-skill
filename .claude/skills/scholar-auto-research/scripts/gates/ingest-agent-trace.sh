#!/usr/bin/env bash
# ingest-agent-trace.sh — fold a dispatched agent's RAO trace sidecar into the
# run's master trace sink.
#
# WHY THIS EXISTS
#   Most agents (peer-reviewer-*, review-code-*) have NO Bash tool, so they
#   cannot append to a shared NDJSON file. Instead each agent, in one Write,
#   emits a sidecar `<report>.trace.ndjson` (RAO steps; schema in
#   references/agent-trace-contract.md) and echoes `TRACE: <sidecar>`. The
#   dispatching orchestrator (which HAS Bash) calls this helper to fold the
#   sidecar into the master trace via emit-trace.sh — so seq/ts/run_id are
#   stamped consistently and the agent's steps carry agent=<type> + agentId.
#   When --proj is supplied, it validates agentId, role, phase, reserved trace
#   path, and trace digest through the registered session + completion records
#   in locked project state. The review-evidence ledger is the authority.
#
# USAGE
#   bash scripts/gates/ingest-agent-trace.sh \
#     --sidecar <path-to-agent.trace.ndjson> \
#     --skill <dispatching-skill>  --agent <subagent_type>  --agentId <id> \
#     [--phase X.X] [--output-root DIR] [--proj DIR]
#
# EXIT CODES
#   0  ingested >=1 record
#   1  usage / missing or unregistered sidecar / zero valid records (fail-loud)
#   2  emit-trace.sh helper missing / python3 unavailable

set -uo pipefail

SIDECAR="" SKILL="" AGENT="" AGENT_ID="" PHASE="" OUTPUT_ROOT_ARG="" PROJ=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sidecar)      SIDECAR="${2:-}"; shift 2 ;;
    --skill)        SKILL="${2:-}"; shift 2 ;;
    --agent)        AGENT="${2:-}"; shift 2 ;;
    --agentId)      AGENT_ID="${2:-}"; shift 2 ;;
    --phase)        PHASE="${2:-}"; shift 2 ;;
    --output-root)  OUTPUT_ROOT_ARG="${2:-}"; shift 2 ;;
    --proj)         PROJ="${2:-}"; shift 2 ;;
    -h|--help)      grep -E '^#' "$0" | sed 's/^# *//'; exit 0 ;;
    *)              echo "ERROR: unknown flag $1" >&2; exit 1 ;;
  esac
done

if [ -z "$SIDECAR" ] || [ -z "$SKILL" ] || [ -z "$AGENT" ] || [ -z "$AGENT_ID" ]; then
  echo "ERROR: --sidecar, --skill, --agent, --agentId are required" >&2
  exit 1
fi
if [ ! -f "$SIDECAR" ]; then
  echo "ERROR: sidecar trace not found: $SIDECAR" >&2
  exit 1
fi

GATES_DIR="$(cd "$(dirname "$0")" && pwd)"
EMIT="$GATES_DIR/emit-trace.sh"
if [ ! -f "$EMIT" ] || [ ! -r "$EMIT" ]; then
  echo "ERROR: required helper missing/unreadable: $EMIT" >&2
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required to parse the sidecar" >&2; exit 2; }

OUTPUT_ROOT="${OUTPUT_ROOT_ARG:-${OUTPUT_ROOT:-output}}"

# Validate before appending.  Checking a session file by discovery is not a
# state binding: a caller can create or alter that file independently.  The
# registration and completion digests in state are the authority, and the
# reserved trace must be the exact completed trace bytes.
if [ -n "$PROJ" ]; then
  if [ -z "$PHASE" ]; then
    echo "ERROR: --phase is required when --proj enables review-evidence binding" >&2
    exit 1
  fi
  BINDING=$(python3 - "$PROJ" "$SIDECAR" "$AGENT_ID" "$AGENT" "$PHASE" <<'PY'
import hashlib
import json
import pathlib
import sys

project = pathlib.Path(sys.argv[1]).resolve()
sidecar_raw = pathlib.Path(sys.argv[2])
agent_id, role, phase = sys.argv[3:6]

def fail(message):
    print(message)
    raise SystemExit(1)

if sidecar_raw.is_symlink():
    fail("sidecar trace must not be a symlink")
sidecar = sidecar_raw.resolve()

def read_object(path, label):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"{label} is missing or invalid: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

state = read_object(project / ".auto-research/state.json", "review-evidence state")
history = state.get("review_evidence_history")
if not isinstance(history, list):
    fail("review-evidence state has no history ledger")
epoch = int((state.get("review_attempt_epochs") or {}).get(str(phase), 0))
completions = [
    event for event in history
    if isinstance(event, dict)
    and event.get("event") == "review_role_completed"
    and str(event.get("phase_id")) == str(phase)
    and str(event.get("dispatch_id")) == agent_id
    and str(event.get("role")) == role
    and event.get("attempt_epoch") == epoch
]
if len(completions) != 1:
    fail("dispatch ID is not bound to exactly one current state completion")
completion_event = completions[0]
session_id = str(completion_event.get("session_id") or "")
if not session_id:
    fail("registered completion has no session ID")
if any(
    isinstance(event, dict)
    and event.get("event") == "review_session_aborted"
    and str(event.get("phase_id")) == str(phase)
    and str(event.get("session_id")) == session_id
    for event in history
):
    fail("registered review session is aborted")
registrations = [
    event for event in history
    if isinstance(event, dict)
    and event.get("event") == "review_session_registered"
    and str(event.get("phase_id")) == str(phase)
    and str(event.get("session_id")) == session_id
    and event.get("attempt_epoch") == epoch
]
if len(registrations) != 1:
    fail("completion has no unique current state session registration")

session_paths = list((project / "review-evidence").glob(f"phase-*/{session_id}/session.json"))
if len(session_paths) != 1:
    fail("registered session file is missing or ambiguous")
session_path = session_paths[0]
try:
    session_path.resolve().relative_to(project)
except ValueError:
    fail("registered session path escapes the project")
if session_path.is_symlink() or session_path.parent.is_symlink():
    fail("registered session file must not be a symlink")
if registrations[0].get("reservation_sha256") != digest(session_path):
    fail("registered session digest mismatch")
session = read_object(session_path, "registered session")
if (
    str(session.get("phase_id")) != str(phase)
    or str(session.get("session_id")) != session_id
    or session.get("attempt_epoch") != epoch
    or session.get("project_run_nonce") != state.get("run_nonce")
):
    fail("registered session identity does not match state")
reservations = [
    item for item in session.get("reservations", [])
    if isinstance(item, dict)
    and str(item.get("dispatch_id")) == agent_id
    and str(item.get("role")) == role
]
if len(reservations) != 1:
    fail("dispatch ID and role do not match one registered reservation")
reservation = reservations[0]

completion_path = session_path.parent / "completions" / f"{role}.json"
if completion_path.is_symlink() or completion_path.parent.is_symlink():
    fail("registered completion file must not be a symlink")
completion = read_object(completion_path, "registered completion")
if completion_event.get("completion_sha256") != digest(completion_path):
    fail("registered completion digest mismatch")
if (
    str(completion.get("dispatch_id")) != agent_id
    or str(completion.get("role")) != role
    or str(completion.get("session_id")) != session_id
    or completion.get("driver_completion", {}).get("status") != "succeeded"
):
    fail("completion identity or terminal status does not match state")

reserved_trace_raw = project / str(reservation.get("trace_path") or "")
if reserved_trace_raw.is_symlink():
    fail("reserved trace must not be a symlink")
reserved_trace = reserved_trace_raw
try:
    reserved_trace = reserved_trace.resolve()
    reserved_trace.relative_to(project)
except ValueError:
    fail("reserved trace path escapes the project")
if sidecar != reserved_trace:
    fail("sidecar is not the trace path reserved in state")
trace_sha = digest(sidecar)
if (
    completion.get("trace_path") != reservation.get("trace_path")
    or completion.get("trace_sha256") != trace_sha
    or completion_event.get("trace_sha256") != trace_sha
):
    fail("sidecar digest does not match the registered completion")
print(f"yes:{session_id}")
PY
)
  BINDING_RC=$?
  if [ "$BINDING_RC" -ne 0 ]; then
    echo "ERROR: agentId '$AGENT_ID' is not valid registered review evidence: ${BINDING:-unknown binding error}" >&2
    echo "AGENTID_BOUND=no"
    exit 1
  fi
  echo "AGENTID_BOUND=yes"
  echo "REVIEW_SESSION_ID=${BINDING#yes:}"
fi

# ── Fold each valid sidecar record into the master trace via emit-trace ──────
# python drives the loop (safe subprocess quoting) and reports the count.
INGESTED=$(python3 - "$SIDECAR" "$EMIT" "$SKILL" "$AGENT" "$AGENT_ID" "$PHASE" "$OUTPUT_ROOT" <<'PY'
import json, os, subprocess, sys
sidecar, emit, skill, agent, agent_id, phase, output_root = sys.argv[1:8]
n = 0
for line in open(sidecar):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
    except Exception:
        print("WARN: skipping malformed sidecar line", file=sys.stderr)
        continue
    step = str(r.get("step") or "").strip()
    reasoning = str(r.get("reasoning") or "")
    action = str(r.get("action") or "")
    observation = str(r.get("observation") or "")
    if not step or not (reasoning or action or observation):
        print("WARN: skipping sidecar record with no step or empty RAO triad", file=sys.stderr)
        continue
    refs = r.get("refs") or []
    if isinstance(refs, list):
        refs = ",".join(str(x) for x in refs)
    else:
        refs = str(refs)
    status = str(r.get("status") or "ok")
    if status not in ("ok", "fail", "skipped"):
        status = "ok"
    args = ["bash", emit, "--skill", skill, "--agent", agent,
            "--agentId", agent_id, "--step", step, "--status", status]
    if phase:
        args += ["--phase", phase]
    if reasoning:
        args += ["--reasoning", reasoning]
    if action:
        args += ["--action", action]
    if observation:
        args += ["--observation", observation]
    if refs:
        args += ["--refs", refs]
    env = dict(os.environ, OUTPUT_ROOT=output_root)
    res = subprocess.run(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if res.returncode == 0:
        n += 1
    else:
        print(f"WARN: emit-trace rejected a record (step={step!r})", file=sys.stderr)
print(n)
PY
)
INGESTED=${INGESTED:-0}

if [ "$INGESTED" -lt 1 ]; then
  echo "ERROR: no valid RAO records ingested from $SIDECAR (agent produced an empty/invalid trace)" >&2
  exit 1
fi

echo "INGESTED=$INGESTED"
echo "TRACE_FILE=${OUTPUT_ROOT}/logs/trace-${SKILL}-$(date +%Y-%m-%d).ndjson"
exit 0
