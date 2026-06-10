#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: auto-research-state.sh <init|import-init|set-mode|decision|next|complete|route-back|status|hash-check> <project_dir> [phase_id|report-json] [artifact-paths...]" >&2
  exit 2
fi

CMD="$1"
PROJ="$2"
shift 2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$(cd "$SCRIPT_DIR/.." && pwd)/references/phase-contract.json"

python3 - "$CONTRACT" "$CMD" "$PROJ" "$@" <<'PY'
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

contract_path = Path(sys.argv[1])
cmd = sys.argv[2]
proj = Path(sys.argv[3])
args = sys.argv[4:]
state_dir = proj / ".auto-research"
state_path = state_dir / "state.json"

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def load_contract():
    return json.loads(contract_path.read_text())

def contract_hash():
    return sha(contract_path)

def load_state():
    if not state_path.exists():
        raise SystemExit(f"state missing: run init first for {proj}")
    return json.loads(state_path.read_text())

def save_state(state):
    state_dir.mkdir(parents=True, exist_ok=True)
    tmp = state_path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    tmp.replace(state_path)

def new_state():
    return {
        "schema_version": "1.1.0",
        "contract_sha256": contract_hash(),
        "created_at": now(),
        "updated_at": now(),
        "phases_completed": [],
        "phase_records": {},
        "stale_phases": [],
        "route_back_history": [],
        "route_back_retry_counts": {},
        "run_mode": {
            "mode": "unset",
            "selected_at": None,
            "selected_by": None,
            "note": ""
        },
        "pending_transition": None,
        "transition_decisions": []
    }

def _check_contract_drift(state, mutating):
    """Compare recorded contract sha256 against live contract on disk.

    Audit 2026-05-02: contract_sha256 was previously written but never
    compared. If the operator edits phase-contract.json mid-project, the
    drift was silently encoded into per-phase records, violating the
    invariant that phases were verified against the same contract that
    initialized the project.

    For mutating commands (complete, route-back) the helper raises
    SystemExit unless `AUTO_RESEARCH_ALLOW_CONTRACT_DRIFT=1` is set in the
    environment. For read commands it prints a warning to stderr.
    """
    expected = state.get("contract_sha256", "")
    actual = contract_hash()
    if not expected or expected == actual:
        return False
    msg = (
        f"CONTRACT_DRIFT: state recorded contract_sha256={expected[:12]}... "
        f"but on-disk contract={actual[:12]}..."
    )
    if mutating and os.environ.get("AUTO_RESEARCH_ALLOW_CONTRACT_DRIFT", "") != "1":
        raise SystemExit(
            msg
            + " — refusing to mutate state. Either revert the contract or "
            "set AUTO_RESEARCH_ALLOW_CONTRACT_DRIFT=1 to override."
        )
    print(msg, file=sys.stderr)
    if mutating:
        print(
            "# AUTO_RESEARCH_ALLOW_CONTRACT_DRIFT=1 active — proceeding with mutation",
            file=sys.stderr,
        )
    return True

def normalize_run_mode(value):
    token = str(value).strip().lower().replace("_", "-")
    aliases = {
        "auto": "autonomous",
        "autonomous": "autonomous",
        "autonomy": "autonomous",
        "full-auto": "autonomous",
        "human": "human_in_loop",
        "human-in-loop": "human_in_loop",
        "human-in-the-loop": "human_in_loop",
        "hitl": "human_in_loop",
        "step-by-step": "human_in_loop",
        "stepwise": "human_in_loop",
        "manual": "human_in_loop",
        "ask-me": "human_in_loop",
    }
    mode = aliases.get(token)
    if mode is None:
        raise SystemExit("run mode must be autonomous or human-in-loop")
    return mode

def normalize_decision(value):
    token = str(value).strip().lower().replace("_", "-")
    aliases = {
        "approve": "approve",
        "approved": "approve",
        "go": "approve",
        "continue": "approve",
        "proceed": "approve",
        "revise": "revise",
        "revision": "revise",
        "redo": "revise",
        "pause": "pause",
        "hold": "pause",
        "stop": "pause",
        "switch-autonomous": "switch_autonomous",
        "switch-to-autonomous": "switch_autonomous",
        "autonomous": "switch_autonomous",
        "auto": "switch_autonomous",
    }
    decision = aliases.get(token)
    if decision is None:
        raise SystemExit("decision must be approve, revise, pause, or switch-autonomous")
    return decision

def ensure_state_defaults(state):
    state.setdefault("run_mode", {
        "mode": "unset",
        "selected_at": None,
        "selected_by": None,
        "note": ""
    })
    if not isinstance(state.get("run_mode"), dict):
        state["run_mode"] = {
            "mode": "unset",
            "selected_at": None,
            "selected_by": None,
            "note": ""
        }
    mode = state["run_mode"].get("mode", "unset")
    if mode not in {"unset", "autonomous", "human_in_loop"}:
        state["run_mode"]["mode"] = "unset"
    state.setdefault("pending_transition", None)
    state.setdefault("transition_decisions", [])
    return state

def compute_next_info(state):
    completed = set(map(str, state.get("phases_completed", [])))
    stale = set(map(str, state.get("stale_phases", [])))
    active_route = state.get("active_route_back")
    for pid in phase_ids:
        if pid in stale:
            info = {"phase": pid, "reason": "stale"}
            if isinstance(active_route, dict) and str(active_route.get("route_back_phase")) == pid:
                info.update({
                    "reason": "route_back",
                    "route_back_from_phase": active_route.get("source_phase"),
                    "finding_ids": active_route.get("finding_ids", []),
                    "retry_max": active_route.get("retry_max", 1),
                })
            return info
        if pid not in completed:
            return {"phase": pid, "reason": "incomplete"}
    return {"phase": "DONE", "reason": "complete"}

CONTEXT_CLEAR_SEAMS = {
    "5":  "planning epoch complete; Phase 6 spawns 6 independent code-reviewer agents — fresh context recommended",
    "7":  "premortem GO; Phase 8 execution will dump heavy command traces and model output — fresh context recommended",
    "11": "results locked; Phase 12+ only need the lock manifest + Stage 1 verify — clean handoff to drafting",
    "14": "manuscript verified against lock; Phases 15-18 audit independent dimensions (citations, ethics, replication, quality)",
    "18": "quality gate passed; Phases 19-20 are deterministic assembly + hygiene — no upstream reasoning needed",
}

def print_context_advisory(state):
    """Emit advisory to /clear when the latest completed phase is a context-rot seam.

    Designed as a pure additive output: existing parsers use glob-match on
    NEXT_PHASE= and are unaffected. Suppressed when the run is DONE, in
    mode-selection, or under a pending human-in-loop approval gate.
    """
    completed = [str(p) for p in state.get("phases_completed", [])]
    if not completed:
        return
    numeric = [c for c in completed if c.isdigit()]
    if not numeric:
        return
    latest = max(numeric, key=int)
    reason = CONTEXT_CLEAR_SEAMS.get(latest)
    if not reason:
        return
    print("CONTEXT_CLEAR_RECOMMENDED=1")
    print(f"CONTEXT_CLEAR_REASON={reason}")
    print(f"CONTEXT_CLEAR_RESUME_HINT=bash .claude/skills/scholar-auto-research/scripts/auto-research-state.sh next \"$PROJ\"")

def print_next_info(info, approval_required=False):
    print(f"NEXT_PHASE={info['phase']}")
    if info.get("reason") and info["reason"] != "incomplete":
        print(f"REASON={info['reason']}")
    if info.get("reason") == "route_back":
        print(f"ROUTE_BACK_FROM_PHASE={info.get('route_back_from_phase')}")
        print("FINDING_IDS=" + ",".join(info.get("finding_ids", [])))
        print(f"RETRY_MAX={info.get('retry_max', 1)}")
    if approval_required:
        print("APPROVAL_REQUIRED=1")
        print("NEXT_ACTION=record user decision before completing this phase")

def print_mode_selection():
    print("NEXT_PHASE=MODE_SELECTION")
    print("RUN_MODE=unset")
    print("DECISION_REQUIRED=1")
    print("NEXT_ACTION=set run mode: auto-research-state.sh set-mode <project> autonomous|human-in-loop")

def make_pending_transition(state, from_phase, next_info, reason=None):
    if state.get("run_mode", {}).get("mode") != "human_in_loop":
        return
    to_phase = str(next_info.get("phase", ""))
    if not to_phase or to_phase == "DONE":
        state["pending_transition"] = None
        return
    state["pending_transition"] = {
        "from_phase": str(from_phase),
        "to_phase": to_phase,
        "reason": reason or next_info.get("reason", "incomplete"),
        "status": "pending",
        "created_at": now(),
    }

def enforce_run_mode_for_complete(state, pid):
    mode = state.get("run_mode", {}).get("mode", "unset")
    if mode == "unset":
        raise SystemExit("RUN_MODE_REQUIRED: choose autonomous or human-in-loop before completing phases")
    pending = state.get("pending_transition")
    if mode == "human_in_loop" and isinstance(pending, dict) and pending.get("status") == "pending":
        target = str(pending.get("to_phase", ""))
        raise SystemExit(
            "HUMAN_DECISION_REQUIRED: pending transition to Phase "
            + target
            + " must be approved before completing Phase "
            + str(pid)
        )

def normalize_scholar_init_status(raw):
    if not isinstance(raw, dict):
        raise SystemExit(".claude/safety-status.json must be a JSON object")
    counts = {
        "cleared": 0,
        "override": 0,
        "local_mode": 0,
        "anonymized": 0,
        "needs_review": 0,
        "halted": 0,
        "other": 0,
    }
    status_by_file = {}
    unresolved = []
    for path, value in raw.items():
        text = str(value)
        token = text.split(":", 1)[0].strip().upper()
        rationale = text.split(":", 1)[1].strip() if ":" in text else ""
        if token in ("CLEARED", "GREEN", "PASS"):
            category = "cleared"
        elif token == "OVERRIDE":
            if rationale:
                category = "override"
            else:
                category = "other"
                unresolved.append(path)
        elif token == "LOCAL_MODE":
            category = "local_mode"
        elif token in ("ANONYMIZED", "ANONYMIZE"):
            category = "anonymized"
        elif token == "NEEDS_REVIEW":
            category = "needs_review"
            unresolved.append(path)
        elif token in ("HALT", "HALTED"):
            category = "halted"
            unresolved.append(path)
        else:
            category = "other"
            unresolved.append(path)
        counts[category] += 1
        status_by_file[path] = {
            "source_status": text,
            "category": category,
        }

    if unresolved:
        safety_status = "BLOCKED"
    elif counts["local_mode"]:
        safety_status = "PASS_LOCAL_MODE"
    else:
        safety_status = "PASS"

    return {
        "schema_version": "1.0.0",
        "source": "scholar-init",
        "source_path": ".claude/safety-status.json",
        "imported_at": now(),
        "safety_status": safety_status,
        "files_scanned": len(raw),
        "no_data_declared": len(raw) == 0,
        "high_risk_unresolved": len(unresolved),
        "unresolved_files": unresolved,
        "counts": counts,
        "status_by_file": status_by_file,
        "policy": {
            "needs_review_blocks": True,
            "halted_blocks": True,
            "local_mode_allowed": True,
            "override_requires_scholar_init_rationale": True
        }
    }

contract = load_contract()
phase_ids = [str(p["id"]) for p in contract["phases"]]
phase_by_id = {str(p["id"]): p for p in contract["phases"]}

if cmd == "init":
    proj.mkdir(parents=True, exist_ok=True)
    state = new_state()
    save_state(state)
    print(f"STATE={state_path}")
    print_mode_selection()
    raise SystemExit(0)

if cmd == "import-init":
    proj.mkdir(parents=True, exist_ok=True)
    source = proj / ".claude" / "safety-status.json"
    if not source.exists():
        raise SystemExit(f"scholar-init safety file missing: {source}")
    raw = json.loads(source.read_text())
    normalized = normalize_scholar_init_status(raw)
    safety_dir = proj / "safety"
    safety_dir.mkdir(parents=True, exist_ok=True)
    dest = safety_dir / "safety-status.json"
    dest.write_text(json.dumps(normalized, indent=2, sort_keys=True) + "\n")
    if state_path.exists():
        state = load_state()
    else:
        state = new_state()
    state["scholar_init_import"] = {
        "source": str(source),
        "dest": str(dest),
        "imported_at": normalized["imported_at"],
        "safety_status": normalized["safety_status"],
        "high_risk_unresolved": normalized["high_risk_unresolved"]
    }
    state["updated_at"] = now()
    save_state(state)
    print(f"IMPORTED_SAFETY={dest}")
    print(f"SAFETY_STATUS={normalized['safety_status']}")
    print(f"HIGH_RISK_UNRESOLVED={normalized['high_risk_unresolved']}")
    if normalized["high_risk_unresolved"]:
        print("NEXT_ACTION=run scholar-init review before Phase 0 completion")
        raise SystemExit(1)
    print_mode_selection()
    raise SystemExit(0)

state = ensure_state_defaults(load_state())

if cmd == "status":
    print(json.dumps(state, indent=2, sort_keys=True))
    raise SystemExit(0)

if cmd == "set-mode":
    _check_contract_drift(state, mutating=True)
    if not args:
        raise SystemExit("set-mode requires autonomous or human-in-loop")
    mode = normalize_run_mode(args[0])
    note = " ".join(args[1:]).strip()
    previous = state.get("run_mode", {}).get("mode", "unset")
    state["run_mode"] = {
        "mode": mode,
        "selected_at": now(),
        "selected_by": "user",
        "previous_mode": previous,
        "note": note,
    }
    state.setdefault("transition_decisions", []).append({
        "recorded_at": state["run_mode"]["selected_at"],
        "decision": "set_mode",
        "mode": mode,
        "previous_mode": previous,
        "note": note,
    })
    if mode == "autonomous":
        state["pending_transition"] = None
    else:
        info = compute_next_info(state)
        if info["phase"] != "DONE" and state.get("phases_completed"):
            make_pending_transition(state, "mode_switch", info, reason="mode_switch")
        else:
            state["pending_transition"] = None
    state["updated_at"] = now()
    save_state(state)
    print(f"RUN_MODE={mode}")
    info = compute_next_info(state)
    if mode == "human_in_loop" and isinstance(state.get("pending_transition"), dict):
        print_next_info({"phase": state["pending_transition"]["to_phase"], "reason": state["pending_transition"].get("reason", "pending_decision")}, approval_required=True)
    else:
        print_next_info(info)
    raise SystemExit(0)

if cmd == "decision":
    _check_contract_drift(state, mutating=True)
    if len(args) < 2:
        raise SystemExit("decision requires <next_phase> <approve|revise|pause|switch-autonomous> [note]")
    phase = str(args[0]).strip()
    decision = normalize_decision(args[1])
    note = " ".join(args[2:]).strip()
    pending = state.get("pending_transition")
    if state.get("run_mode", {}).get("mode") != "human_in_loop":
        raise SystemExit("decision is only valid in human-in-loop mode")
    if not isinstance(pending, dict) or pending.get("status") != "pending":
        raise SystemExit("no pending human-in-loop transition to decide")
    target = str(pending.get("to_phase", ""))
    if phase != target:
        raise SystemExit(f"decision phase mismatch: pending transition is to {target}, got {phase}")
    event = {
        "recorded_at": now(),
        "decision": decision,
        "from_phase": pending.get("from_phase"),
        "to_phase": target,
        "pending_reason": pending.get("reason"),
        "note": note,
    }
    state.setdefault("transition_decisions", []).append(event)
    if decision == "approve":
        state["pending_transition"] = None
    elif decision == "switch_autonomous":
        state["run_mode"] = {
            "mode": "autonomous",
            "selected_at": event["recorded_at"],
            "selected_by": "user",
            "previous_mode": "human_in_loop",
            "note": note or "switched from human-in-loop decision gate",
        }
        state["pending_transition"] = None
    else:
        pending["last_decision"] = decision
        pending["last_decision_at"] = event["recorded_at"]
        pending["last_decision_note"] = note
        state["pending_transition"] = pending
    state["updated_at"] = now()
    save_state(state)
    print(f"DECISION={decision}")
    print(f"NEXT_PHASE={target}")
    print(f"RUN_MODE={state.get('run_mode', {}).get('mode')}")
    if decision in {"revise", "pause"}:
        print("APPROVAL_REQUIRED=1")
    raise SystemExit(0)

if cmd == "next":
    mode = state.get("run_mode", {}).get("mode", "unset")
    if mode == "unset":
        print_mode_selection()
        raise SystemExit(0)
    pending = state.get("pending_transition")
    if mode == "human_in_loop" and isinstance(pending, dict) and pending.get("status") == "pending":
        print_next_info({"phase": pending.get("to_phase"), "reason": pending.get("reason", "pending_decision")}, approval_required=True)
        print(f"PENDING_FROM_PHASE={pending.get('from_phase')}")
        if pending.get("last_decision"):
            print(f"LAST_DECISION={pending.get('last_decision')}")
        raise SystemExit(0)
    next_info = compute_next_info(state)
    print_next_info(next_info)
    if next_info.get("phase") != "DONE":
        print_context_advisory(state)
    raise SystemExit(0)

if cmd == "complete":
    _check_contract_drift(state, mutating=True)
    if not args:
        raise SystemExit("complete requires phase_id")
    pid = str(args[0])
    enforce_run_mode_for_complete(state, pid)
    artifacts = [Path(a) for a in args[1:]]
    if pid not in phase_by_id:
        raise SystemExit(f"unknown phase: {pid}")
    for artifact in artifacts:
        if not artifact.exists():
            raise SystemExit(f"artifact missing: {artifact}")
    record = {
        "phase_id": pid,
        "phase_name": phase_by_id[pid]["name"],
        "completed_at": now(),
        "contract_sha256": contract_hash(),
        "artifacts": [
            {"path": str(p), "sha256": sha(p) if p.is_file() else "DIR"}
            for p in artifacts
        ],
        "dependencies": phase_by_id[pid].get("hash_dependencies", [])
    }
    completed = list(map(str, state.get("phases_completed", [])))
    if pid not in completed:
        completed.append(pid)
    state["phases_completed"] = completed
    state.setdefault("phase_records", {})[pid] = record
    stale = [p for p in state.get("stale_phases", []) if str(p) != pid]
    state["stale_phases"] = stale
    active_route = state.get("active_route_back")
    if isinstance(active_route, dict):
        target = str(active_route.get("route_back_phase", "")).strip()
        if target.isdigit() and not any(str(p).isdigit() and int(str(p)) >= int(target) for p in stale):
            state.pop("active_route_back", None)
    make_pending_transition(state, pid, compute_next_info(state))
    state["updated_at"] = now()
    save_state(state)
    print(f"COMPLETED_PHASE={pid}")
    raise SystemExit(0)

if cmd == "route-back":
    _check_contract_drift(state, mutating=True)
    if not args:
        raise SystemExit("route-back requires verification FAIL report path")
    report_path = Path(args[0])
    if not report_path.exists():
        raise SystemExit(f"route-back report missing: {report_path}")
    try:
        report = json.loads(report_path.read_text())
    except Exception as exc:
        raise SystemExit(f"route-back report is not valid JSON: {exc}")
    if report.get("verdict") != "FAIL":
        raise SystemExit("route-back requires report verdict FAIL")
    source_phase = str(report.get("source_phase", "")).strip()
    if not source_phase:
        if "pipeline_complete" in report:
            source_phase = "20"
        elif "ready_for_phase_20" in report:
            source_phase = "19"
        elif "ready_for_phase_19" in report:
            source_phase = "18"
        elif "ready_for_phase_18" in report:
            source_phase = "17"
        elif "ready_for_phase_17" in report:
            source_phase = "16"
        elif "ready_for_phase_16" in report:
            source_phase = "15"
        elif "ready_for_phase_15" in report:
            source_phase = "14"
        elif "ready_for_phase_14" in report:
            source_phase = "13"
    if source_phase not in phase_by_id:
        raise SystemExit("route-back report must identify a valid source_phase")
    target = str(report.get("route_back_phase", "")).strip()
    if target not in phase_by_id:
        raise SystemExit(f"route-back report has invalid route_back_phase: {target}")
    findings = report.get("findings")
    if not isinstance(findings, list) or not findings:
        raise SystemExit("route-back report must include nonempty findings")
    finding_ids = []
    finding_route_phases = []
    for idx, finding in enumerate(findings):
        if not isinstance(finding, dict):
            raise SystemExit(f"route-back findings[{idx}] is not an object")
        finding_id = str(finding.get("finding_id", "")).strip()
        if not finding_id:
            raise SystemExit(f"route-back findings[{idx}].finding_id missing")
        finding_route = str(finding.get("route_back_phase", "")).strip()
        if finding_route not in phase_by_id:
            raise SystemExit(f"route-back finding {finding_id} has invalid route_back_phase")
        finding_route_phases.append(finding_route)
        if finding.get("status") != "open":
            raise SystemExit(f"route-back finding {finding_id} status must be open")
        finding_ids.append(finding_id)
    earliest_finding_route = str(min(int(phase) for phase in finding_route_phases))
    if target != earliest_finding_route:
        raise SystemExit("route-back report route_back_phase must be the earliest finding route_back_phase")
    retry_counts = state.setdefault("route_back_retry_counts", {})
    for finding_id in finding_ids:
        retry_counts[finding_id] = int(retry_counts.get(finding_id, 0)) + 1
    # Cap-3 ESCALATE (audit 2026-05-02): mirrors scholar-full-paper back-route.sh.
    # When the same finding has triggered three route-backs without forward
    # progress, halt the loop so the operator can intervene. The retry_counts
    # increment above is preserved in saved state below so the diagnostic
    # history is intact, but no new active_route_back is recorded.
    ESCALATE_CAP = 3
    escalated = [fid for fid in finding_ids if retry_counts[fid] >= ESCALATE_CAP]
    completed = set(map(str, state.get("phases_completed", [])))
    target_int = int(target)
    invalidated = {
        pid for pid in phase_ids
        if int(pid) >= target_int and (pid in completed or pid == target)
    }
    stale = set(map(str, state.get("stale_phases", [])))
    stale.update(invalidated)
    state["stale_phases"] = sorted(stale, key=lambda x: int(x))
    event = {
        "routed_at": now(),
        "source_phase": source_phase,
        "report_path": str(report_path),
        "route_back_phase": target,
        "finding_ids": finding_ids,
        "findings": findings,
        "invalidated_phases": sorted(invalidated, key=lambda x: int(x)),
        "retry_counts": {finding_id: retry_counts[finding_id] for finding_id in finding_ids}
    }
    if escalated:
        event["escalated"] = True
        event["escalated_findings"] = escalated
    state.setdefault("route_back_history", []).append(event)
    if escalated:
        state.pop("active_route_back", None)
        state["updated_at"] = now()
        save_state(state)
        print(f"ROUTE_BACK_PHASE={target}")
        print("INVALIDATED_PHASES=" + ",".join(event["invalidated_phases"]))
        print("FINDING_IDS=" + ",".join(finding_ids))
        print(f"ESCALATE_FOR_FINDINGS={','.join(escalated)}")
        print(f"RETRY_MAX={max(retry_counts[fid] for fid in finding_ids)}")
        print(f"# ESCALATE: route-back retry cap (>= {ESCALATE_CAP}) reached for findings: {','.join(escalated)}.")
        print("# Autonomous loop must halt — operator must inspect the underlying issue.")
        print(f"# Inspect: cat {state_path}  (route_back_history + route_back_retry_counts)")
        print("# To proceed after manual fix: clear affected finding_id entries from")
        print("# route_back_retry_counts in state.json, then resume.")
        raise SystemExit(2)
    state["active_route_back"] = {
        "source_phase": source_phase,
        "report_path": str(report_path),
        "route_back_phase": target,
        "finding_ids": finding_ids,
        "retry_max": max(retry_counts[finding_id] for finding_id in finding_ids),
        "created_at": event["routed_at"]
    }
    make_pending_transition(state, source_phase, {"phase": target, "reason": "route_back"}, reason="route_back")
    state["updated_at"] = now()
    save_state(state)
    print(f"ROUTE_BACK_PHASE={target}")
    print("INVALIDATED_PHASES=" + ",".join(event["invalidated_phases"]))
    print("FINDING_IDS=" + ",".join(finding_ids))
    print(f"RETRY_MAX={state['active_route_back']['retry_max']}")
    raise SystemExit(0)

if cmd == "hash-check":
    stale = set()
    records = state.get("phase_records", {})
    for pid, record in records.items():
        for artifact in record.get("artifacts", []):
            path = Path(artifact["path"])
            old = artifact["sha256"]
            if old == "DIR":
                if not path.exists():
                    stale.add(pid)
            elif not path.exists() or sha(path) != old:
                stale.add(pid)
    if stale:
        downstream = set(stale)
        changed = True
        while changed:
            changed = False
            for phase in contract["phases"]:
                pid = str(phase["id"])
                deps = set(map(str, phase.get("hash_dependencies", [])))
                if pid not in downstream and deps & downstream:
                    downstream.add(pid)
                    changed = True
        state["stale_phases"] = sorted(downstream, key=lambda x: int(x))
        make_pending_transition(state, "hash-check", compute_next_info(state), reason="stale")
        state["updated_at"] = now()
        save_state(state)
        print("STALE_PHASES=" + ",".join(state["stale_phases"]))
        raise SystemExit(1)
    state["stale_phases"] = []
    state["updated_at"] = now()
    save_state(state)
    print("STALE_PHASES=")
    raise SystemExit(0)

raise SystemExit(f"unknown command: {cmd}")
PY
