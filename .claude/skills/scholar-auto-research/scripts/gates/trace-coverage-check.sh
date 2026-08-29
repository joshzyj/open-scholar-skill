#!/usr/bin/env bash
# trace-coverage-check.sh — hard gate: a skill/phase must produce a valid RAO
# trace (reasoning + action + observation), and every state-registered,
# successfully completed review role must appear in it.
#
# CONTRACT
#   Reads the run's trace sink(s) at <root>/logs/trace-<skill>-*.ndjson (written
#   by emit-trace.sh; agent steps folded in by ingest-agent-trace.sh). For an
#   auto-research project, review dispatch IDs come only from the locked state
#   evidence history plus digest-bound session/completion records.
#
# VERDICT
#   GREEN  (exit 0) — a non-empty, well-formed trace exists; every record has the
#           required fields + a non-empty RAO triad; and (when --phase names
#           registered review completions) every dispatch ID appears in trace.
#   RED    (exit 1) — trace present but empty / malformed line / missing field /
#           all-empty triad; OR the target skill has no trace while the project
#           is clearly a CURRENT run (a manifest or some other trace exists); OR
#           a registered completion is stale/corrupt or lacks a trace event.
#   YELLOW (exit 2) — no trace AND no trace/manifest infrastructure at all
#           (a legacy project predating trace adoption — bounded migration
#           window, mirrors the codex-prose-coverage legacy path).
#
#   Prints a `STATUS=GREEN|YELLOW|RED` line so it composes with
#   normalize-gate-status.sh.
#
# USAGE
#   bash scripts/gates/trace-coverage-check.sh <root> [--skill X] [--phase P]
#     <root> = project dir / OUTPUT_ROOT containing logs/

set -uo pipefail

ROOT="" SKILL="" PHASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skill) SKILL="${2:-}"; shift 2 ;;
    --phase) PHASE="${2:-}"; shift 2 ;;
    -h|--help) grep -E '^#' "$0" | sed 's/^# *//'; exit 0 ;;
    *) if [ -z "$ROOT" ]; then ROOT="$1"; shift; else echo "ERROR: unexpected arg $1" >&2; exit 64; fi ;;
  esac
done

if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "Usage: trace-coverage-check.sh <root> [--skill X] [--phase P]" >&2
  echo "ABORT: root dir not found: ${ROOT:-<none>}" >&2
  exit 64
fi

LOG_DIR="$ROOT/logs"
STATE="$ROOT/.auto-research/state.json"

# ── Discover trace files ────────────────────────────────────────────────────
TARGET_TRACES=()
ANY_TRACE=0
if [ -d "$LOG_DIR" ]; then
  for f in "$LOG_DIR"/trace-*.ndjson; do
    [ -f "$f" ] || continue
    ANY_TRACE=1
    if [ -n "$SKILL" ]; then
      case "$(basename "$f")" in
        trace-"$SKILL"-*.ndjson) TARGET_TRACES+=("$f") ;;
      esac
    else
      TARGET_TRACES+=("$f")
    fi
  done
fi
# ── Validate present traces + agent-dispatch cross-link (python3) ───────────
if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "WARN: python3 unavailable — cannot validate NDJSON trace schema; advisory only."
  exit 2
fi

VERDICT=$(python3 - "$ROOT" "$STATE" "$PHASE" "${TARGET_TRACES[@]}" <<'PY'
import hashlib, json, pathlib, sys
root, state_path, phase = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]), sys.argv[3]
trace_files = sys.argv[4:]
REQ = {"ts","seq","run_id","skill","phase","agent","agentId","step","reasoning","action","observation","refs","status"}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def red(message):
    print(f"RED|{message}")
    raise SystemExit(0)

required_agent_ids = set()
if phase and state_path.is_file():
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception as exc:
        red(f"review-evidence state is invalid: {exc}")
    history = state.get("review_evidence_history") or []
    if not isinstance(history, list):
        red("review-evidence state history is not an array")
    epoch = int((state.get("review_attempt_epochs") or {}).get(str(phase), 0))
    completions = [
        event for event in history
        if isinstance(event, dict)
        and event.get("event") == "review_role_completed"
        and str(event.get("phase_id")) == str(phase)
        and event.get("attempt_epoch") == epoch
    ]
    seen_completion_keys = set()
    for event in completions:
        session_id = str(event.get("session_id") or "")
        role = str(event.get("role") or "")
        dispatch_id = str(event.get("dispatch_id") or "")
        key = (session_id, role)
        if not session_id or not role or not dispatch_id or key in seen_completion_keys:
            red(f"Phase {phase} has malformed or duplicate registered review completion")
        seen_completion_keys.add(key)
        if any(
            isinstance(item, dict)
            and item.get("event") == "review_session_aborted"
            and str(item.get("phase_id")) == str(phase)
            and str(item.get("session_id")) == session_id
            for item in history
        ):
            continue
        registrations = [
            item for item in history
            if isinstance(item, dict)
            and item.get("event") == "review_session_registered"
            and str(item.get("phase_id")) == str(phase)
            and str(item.get("session_id")) == session_id
            and item.get("attempt_epoch") == epoch
        ]
        if len(registrations) != 1:
            red(f"Phase {phase}/{role} completion has no unique current session registration")
        session_paths = list((root / "review-evidence").glob(f"phase-*/{session_id}/session.json"))
        if len(session_paths) != 1:
            red(f"Phase {phase}/{role} registered session file is missing or ambiguous")
        session_path = session_paths[0]
        try:
            session_path.resolve().relative_to(root)
        except ValueError:
            red(f"Phase {phase}/{role} registered session path escapes the project")
        if (
            session_path.is_symlink()
            or session_path.parent.is_symlink()
            or registrations[0].get("reservation_sha256") != digest(session_path)
        ):
            red(f"Phase {phase}/{role} registered session digest mismatch")
        try:
            session = json.loads(session_path.read_text(encoding="utf-8"))
        except Exception:
            red(f"Phase {phase}/{role} registered session is invalid JSON")
        reservations = [
            item for item in session.get("reservations", [])
            if isinstance(item, dict)
            and str(item.get("dispatch_id")) == dispatch_id
            and str(item.get("role")) == role
        ]
        if (
            str(session.get("phase_id")) != str(phase)
            or str(session.get("session_id")) != session_id
            or session.get("attempt_epoch") != epoch
            or session.get("project_run_nonce") != state.get("run_nonce")
            or len(reservations) != 1
        ):
            red(f"Phase {phase}/{role} registered session identity mismatch")
        completion_path = session_path.parent / "completions" / f"{role}.json"
        try:
            completion = json.loads(completion_path.read_text(encoding="utf-8"))
        except Exception:
            red(f"Phase {phase}/{role} registered completion file is missing or invalid")
        if (
            completion_path.is_symlink()
            or completion_path.parent.is_symlink()
            or event.get("completion_sha256") != digest(completion_path)
        ):
            red(f"Phase {phase}/{role} registered completion digest mismatch")
        trace_path_raw = root / str(reservations[0].get("trace_path") or "")
        if trace_path_raw.is_symlink():
            red(f"Phase {phase}/{role} reserved trace must not be a symlink")
        trace_path = trace_path_raw
        try:
            trace_path = trace_path.resolve()
            trace_path.relative_to(root)
        except ValueError:
            red(f"Phase {phase}/{role} reserved trace path escapes the project")
        if (
            str(completion.get("dispatch_id")) != dispatch_id
            or str(completion.get("role")) != role
            or completion.get("driver_completion", {}).get("status") != "succeeded"
            or completion.get("trace_path") != reservations[0].get("trace_path")
            or not trace_path.is_file()
            or completion.get("trace_sha256") != digest(trace_path)
            or event.get("trace_sha256") != completion.get("trace_sha256")
        ):
            red(f"Phase {phase}/{role} completion trace binding mismatch")
        required_agent_ids.add(dispatch_id)

seen_agent_ids = set()
records = 0
for tf in trace_files:
    ln = 0
    for line in open(tf):
        line = line.strip()
        if not line:
            continue
        ln += 1
        try:
            r = json.loads(line)
        except Exception:
            red(f"malformed NDJSON line {ln} in {tf}")
        miss = REQ - set(r)
        if miss:
            red(f"record {ln} in {tf} missing fields: {sorted(miss)}")
        if not str(r.get("step") or "").strip():
            red(f"record {ln} in {tf} has empty step")
        if not (str(r.get('reasoning') or '') or str(r.get('action') or '') or str(r.get('observation') or '')):
            red(f"record {ln} in {tf} has an all-empty reasoning/action/observation triad")
        aid = r.get("agentId")
        if aid:
            seen_agent_ids.add(aid)
        records += 1

if records == 0:
    if trace_files:
        red("trace file(s) present but contain zero records")
    if required_agent_ids:
        red(f"no RAO trace contains the {len(required_agent_ids)} state-registered review dispatch ID(s) for phase {phase}")
    print("YELLOW|no RAO trace for the target skill — legacy/not-yet-run; emit one per references/process-logger.md")
    sys.exit(0)

# The legacy dispatch manifest is intentionally not consulted here. A row can
# be display metadata, but it cannot establish review execution.
missing = sorted(required_agent_ids - seen_agent_ids)
if missing:
    red(f"{len(missing)} state-registered review dispatch ID(s) for phase {phase} have no trace event: {missing[:5]}")

print(f"GREEN|{records} valid RAO record(s); {len(seen_agent_ids)} agent event(s)")
PY
)

CODE="${VERDICT%%|*}"
MSG="${VERDICT#*|}"
case "$CODE" in
  GREEN) echo "STATUS=GREEN"; echo "PASS: $MSG"; exit 0 ;;
  YELLOW) echo "STATUS=YELLOW"; echo "WARN: $MSG"; exit 2 ;;
  RED)   echo "STATUS=RED"; echo "FAIL: $MSG"; exit 1 ;;
  *)     echo "STATUS=RED"; echo "FAIL: trace validation produced no verdict (fail closed): ${VERDICT:-<empty>}"; exit 1 ;;
esac
