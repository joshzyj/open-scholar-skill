#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: auto-research-state.sh <init|import-init|set-mode|decision|next|complete|route-back|clear-halt|status|migration-status|hash-check|review-begin|review-complete|review-abort|set-review-profile|migrate-contract> <project_dir> [options]" >&2
  exit 2
fi

CMD="$1"
PROJ="$2"
shift 2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$(cd "$SCRIPT_DIR/.." && pwd)/references/phase-contract.json"

# Capture the state machine's exit code so the run-view refresh appended after
# this block cannot change it (2026-08-20). Temporarily disabling `errexit`
# keeps the Python stdin heredoc one standalone simple command while still
# allowing a non-zero SystemExit to reach the unchanged optional refresh.
_ARS_RC=0
set +e
python3 - "$CONTRACT" "$CMD" "$PROJ" "$@" <<'PY'
import hashlib
import json
import glob
import fcntl
import os
import secrets
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

contract_path = Path(sys.argv[1])
cmd = sys.argv[2]
proj = Path(sys.argv[3])
args = sys.argv[4:]
skill_scripts = contract_path.parent.parent / "scripts"
sys.path.insert(0, str(skill_scripts))
from safety_inventory import (
    canonicalize_status_mapping,
    inventory_observation,
    sha256_file,
)
from review_evidence import (
    EvidenceError,
    abort_session,
    begin_session,
    complete_role,
)
state_dir = proj / ".auto-research"
state_path = state_dir / "state.json"
state_dir.mkdir(parents=True, exist_ok=True)
# Every command shares one exclusive project lock. Several nominally read-only
# commands refresh safety/staleness state, and readers must never observe a
# provisional completion between atomic publication and its rollback check.
completion_lock = (state_dir / "state.lock").open("a+")
fcntl.flock(completion_lock.fileno(), fcntl.LOCK_EX)

contract_bytes = contract_path.read_bytes()
transaction_contract_sha256 = hashlib.sha256(contract_bytes).hexdigest()

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def digest_path(path: Path) -> str:
    if path.is_file():
        return sha(path)
    if not path.is_dir():
        raise SystemExit(f"required output is neither file nor directory: {path}")
    digest = hashlib.sha256()
    for child in sorted(path.rglob("*"), key=lambda item: item.as_posix()):
        if child.is_symlink():
            raise SystemExit(f"required output contains unsupported symlink: {child}")
        relative = child.relative_to(path).as_posix()
        if child.is_dir():
            digest.update(f"D\0{relative}\0".encode())
        elif child.is_file():
            digest.update(f"F\0{relative}\0{sha(child)}\0".encode())
    return digest.hexdigest()

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def load_contract():
    return json.loads(contract_bytes)

def contract_hash():
    return transaction_contract_sha256

def live_contract_hash():
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
        "schema_version": "1.3.0",
        "run_nonce": secrets.token_hex(16),
        "contract_sha256": contract_hash(),
        "created_at": now(),
        "updated_at": now(),
        "phases_completed": [],
        "phase_records": {},
        "stale_phases": [],
        "route_back_history": [],
        "route_back_retry_counts": {},
        "halted": False,
        "halt": None,
        "halt_history": [],
        "safety_blocked": None,
        "safety_inventory": None,
        "run_mode": {
            "mode": "unset",
            "selected_at": None,
            "selected_by": None,
            "note": ""
        },
        "pending_transition": None,
        "transition_decisions": [],
        "review_assurance_profile": "normal",
        "review_attempt_epochs": {pid: 0 for pid in ("6", "7", "9", "14", "18", "20")},
        "review_evidence_history": [],
        "contract_migration_history": [],
    }

def _check_contract_drift(state, mutating):
    """Compare recorded contract sha256 against live contract on disk.

    Audit 2026-05-02: contract_sha256 was previously written but never
    compared. If the operator edits phase-contract.json mid-project, the
    drift was silently encoded into per-phase records, violating the
    invariant that phases were verified against the same contract that
    initialized the project.

    Mutating commands fail closed. Read-only callers may request a diagnostic
    warning, but state-driving read paths use the fail-closed mode too so they
    cannot route work under a different contract generation.
    """
    expected = state.get("contract_sha256", "")
    actual = contract_hash()
    if expected == actual:
        return False
    if not expected:
        raise SystemExit("CONTRACT_DRIFT: state has no recorded contract_sha256 — refusing command")
    msg = (
        f"CONTRACT_DRIFT: state recorded contract_sha256={expected[:12]}... "
        f"but on-disk contract={actual[:12]}..."
    )
    if mutating:
        raise SystemExit(
            msg
            + " — refusing command. Run migration-status, then apply the exact "
            "allowlisted transition with migrate-contract, or restore the recorded contract."
        )
    print(msg, file=sys.stderr)
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
    state.setdefault("halted", False)
    state.setdefault("halt", None)
    state.setdefault("halt_history", [])
    state.setdefault("safety_blocked", None)
    state.setdefault("safety_inventory", None)
    state.setdefault("run_nonce", hashlib.sha256(
        (str(state.get("created_at", "legacy")) + "|" + str(proj.resolve())).encode()
    ).hexdigest()[:32])
    state.setdefault("review_assurance_profile", "normal")
    state.setdefault("review_attempt_epochs", {pid: 0 for pid in ("6", "7", "9", "14", "18", "20")})
    state.setdefault("review_evidence_history", [])
    state.setdefault("contract_migration_history", [])
    return state

def bump_review_attempt_epochs(state, affected_phases):
    epochs = state.setdefault("review_attempt_epochs", {})
    for phase in ("6", "7", "9", "14", "18", "20"):
        if phase in {str(value) for value in affected_phases}:
            epochs[phase] = int(epochs.get(phase, 0)) + 1

def option_map(values, *, repeatable=()):
    result = {}
    repeat = set(repeatable)
    idx = 0
    while idx < len(values):
        flag = str(values[idx])
        if not flag.startswith("--") or idx + 1 >= len(values):
            raise SystemExit(f"invalid option sequence near {flag}")
        value = str(values[idx + 1])
        if not value:
            raise SystemExit(f"{flag} requires a nonempty value")
        if flag in repeat:
            result.setdefault(flag, []).append(value)
        elif flag in result:
            raise SystemExit(f"option repeated: {flag}")
        else:
            result[flag] = value
        idx += 2
    return result

def resolve_contract_paths(patterns):
    project_root = proj.resolve()
    resolved = {}
    missing = []
    for pattern in patterns:
        matches = sorted(glob.glob(str(proj / str(pattern))))
        if not matches:
            missing.append(str(pattern))
            continue
        for raw in matches:
            path = Path(raw)
            if path.is_symlink():
                raise SystemExit(f"REQUIRED_OUTPUT_SYMLINK_FORBIDDEN: {path}")
            try:
                relative = path.resolve().relative_to(project_root).as_posix()
            except ValueError:
                raise SystemExit(f"REQUIRED_OUTPUT_OUTSIDE_PROJECT: {path}")
            if relative in resolved:
                raise SystemExit(f"DUPLICATE_REQUIRED_OUTPUT: {relative}")
            resolved[relative] = digest_path(path)
    if missing:
        raise SystemExit("REQUIRED_OUTPUTS_MISSING: " + ",".join(missing))
    return dict(sorted(resolved.items()))

def resolve_auxiliary_inputs(patterns):
    project_root = proj.resolve()
    resolved = {}
    for pattern in patterns:
        for raw in sorted(glob.glob(str(proj / str(pattern)))):
            path = Path(raw)
            if path.is_symlink():
                continue
            try:
                relative = path.resolve().relative_to(project_root).as_posix()
            except ValueError:
                continue
            if path.is_file() or path.is_dir():
                resolved[relative] = digest_path(path)
    return dict(sorted(resolved.items()))

def refresh_safety_inventory(state):
    """Persist fail-closed staleness when a completed Phase 0 inventory drifts."""
    completed = set(map(str, state.get("phases_completed", [])))
    expected = state.get("safety_inventory")
    if "0" not in completed or not isinstance(expected, dict):
        return False
    current = inventory_observation(proj, proj / "safety" / "safety-status.json")
    if expected.get("digest") == current.get("digest"):
        return False
    prior_block = state.get("safety_blocked")
    if (
        isinstance(prior_block, dict)
        and prior_block.get("reason") == "safety_inventory_changed"
        and prior_block.get("current_digest") == current.get("digest")
    ):
        return False
    invalidated = {pid for pid in phase_ids if pid in completed}
    previously_stale = set(map(str, state.get("stale_phases", [])))
    bump_review_attempt_epochs(state, review_phase_ids)
    state["stale_phases"] = sorted(
        previously_stale | invalidated,
        key=lambda value: int(value),
    )
    state["safety_blocked"] = {
        "status": "STALE",
        "reason": "safety_inventory_changed",
        "expected_digest": expected.get("digest"),
        "current_digest": current.get("digest"),
        "detected_at": now(),
    }
    state["pending_transition"] = None
    state["updated_at"] = now()
    save_state(state)
    stamp_dir = state_dir / "verify-stamps"
    for stale_pid in invalidated:
        stamp_path = stamp_dir / (stale_pid + ".json")
        if stamp_path.exists():
            stamp_path.unlink()
    return True

def enforce_not_halted(state):
    if not state.get("halted"):
        return
    halt = state.get("halt") if isinstance(state.get("halt"), dict) else {}
    finding_ids = [str(value) for value in halt.get("finding_ids", [])]
    raise SystemExit(
        "PIPELINE_HALTED: findings="
        + (",".join(finding_ids) if finding_ids else "unknown")
        + " — inspect status, then use clear-halt with matching --finding, "
        "nonempty --reason, and --operator after manual correction."
    )

def compute_next_info(state):
    completed = set(map(str, state.get("phases_completed", [])))
    stale = set(map(str, state.get("stale_phases", [])))
    if isinstance(state.get("safety_blocked"), dict):
        reason = state["safety_blocked"].get("reason", "safety_blocked")
        return {"phase": "0", "reason": reason}
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
    # F15 (audit 2026-07-07): suppress the seam advisory while a route-back is
    # active — the operator is re-doing invalidated phases, not sitting at a
    # clean forward seam, so a "/clear" nudge keyed on the highest completed
    # phase would be misleading.
    if state.get("active_route_back"):
        return
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
            f"HUMAN_DECISION_REQUIRED: pending transition to Phase {target} "
            f"must be approved before completing Phase {pid}"
        )

def normalize_scholar_init_status(raw, project):
    if not isinstance(raw, dict):
        raise SystemExit(".claude/safety-status.json must be a JSON object")
    # F2 (audit 2026-07-07): partition meta keys (leading underscore, e.g.
    # "_safety_level" / "_meta") from per-file status entries BEFORE
    # classification. Meta keys are scan configuration, not data files; counting
    # them inflated files_scanned, forced no_data_declared False, and — because a
    # meta value like "strict" carries no recognized status token — classified
    # the meta key as unresolved and BLOCKED every scholar-init project. All four
    # coupled fields (files_scanned, no_data_declared, counts, status_by_file)
    # are computed over file entries only, so the Phase 0 verifier's
    # len(status_by_file)==files_scanned and sum(counts)==files_scanned
    # cross-checks stay consistent. Meta is preserved under a new top-level
    # "meta" key (additive; Phase 0 required-field tuple is unaffected).
    meta = {k: v for k, v in raw.items() if str(k).startswith("_")}
    file_entries = {k: v for k, v in raw.items() if not str(k).startswith("_")}
    path_mapping, path_issues = canonicalize_status_mapping(project, file_entries)
    if path_issues:
        raise SystemExit(
            "SAFETY_PATH_IDENTITY_INVALID: " + "; ".join(path_issues)
            + ". scholar-auto-research uses a strict copy-only policy; "
            "materialize linked inputs inside the project and rescan."
        )
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
    unresolved_reasons = []
    for path, value in file_entries.items():
        relative_path = path_mapping.get(str(path))
        if not relative_path:
            raise SystemExit(f"SAFETY_PATH_IDENTITY_INVALID: no canonical destination for {path}")
        current_path = project / relative_path
        if not current_path.is_file() or current_path.is_symlink():
            raise SystemExit(f"SAFETY_PATH_IDENTITY_INVALID: current regular file missing for {relative_path}")
        text = str(value)
        token = text.split(":", 1)[0].strip().upper()
        rationale = text.split(":", 1)[1].strip() if ":" in text else ""
        block_reason = None
        if token in ("CLEARED", "GREEN", "PASS"):
            category = "cleared"
        elif token == "OVERRIDE":
            if rationale:
                category = "override"
            else:
                category = "other"
                block_reason = "override_without_rationale"
        elif token == "LOCAL_MODE":
            category = "local_mode"
        elif token in ("ANONYMIZED", "ANONYMIZE"):
            category = "anonymized"
        elif token == "NEEDS_REVIEW":
            category = "needs_review"
            block_reason = "needs_review"
        elif token in ("HALT", "HALTED"):
            category = "halted"
            block_reason = "halted"
        else:
            category = "other"
            block_reason = "unrecognized_status"
        if block_reason is not None:
            unresolved.append(relative_path)
            unresolved_reasons.append((relative_path, block_reason))
        counts[category] += 1
        status_by_file[relative_path] = {
            "source_status": text,
            "category": category,
            "content_sha256": sha256_file(current_path),
            "source_identity": str(path),
            "destination_identity": relative_path,
        }

    if unresolved:
        safety_status = "BLOCKED"
    elif counts["local_mode"]:
        safety_status = "PASS_LOCAL_MODE"
    else:
        safety_status = "PASS"

    normalized = {
        "schema_version": "2.0.0",
        "source": "scholar-init",
        "source_path": ".claude/safety-status.json",
        "imported_at": now(),
        "safety_status": safety_status,
        "files_scanned": len(file_entries),
        "no_data_declared": len(file_entries) == 0,
        "high_risk_unresolved": len(unresolved),
        "unresolved_files": unresolved,
        "counts": counts,
        "status_by_file": status_by_file,
        "meta": meta,
        "policy": {
            "needs_review_blocks": True,
            "halted_blocks": True,
            "local_mode_allowed": True,
            "override_requires_scholar_init_rationale": True
        }
    }
    return normalized, sorted(unresolved_reasons)

contract = load_contract()
phase_ids = [str(p["id"]) for p in contract["phases"]]
phase_by_id = {str(p["id"]): p for p in contract["phases"]}
review_phase_ids = {pid for pid, item in phase_by_id.items() if isinstance(item.get("review_evidence_policy"), dict)}

def acquire_review_lock(pid):
    lock_dir = state_dir / "review-evidence-locks"
    lock_dir.mkdir(parents=True, exist_ok=True)
    handle = (lock_dir / f"phase-{int(pid):02d}.lock").open("a+")
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    return handle

if cmd == "init":
    if state_path.exists():
        enforce_not_halted(ensure_state_defaults(load_state()))
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
    if state_path.exists():
        state = ensure_state_defaults(load_state())
        enforce_not_halted(state)
        _check_contract_drift(state, mutating=True)
    else:
        state = new_state()
    raw = json.loads(source.read_text())
    normalized, unresolved_reasons = normalize_scholar_init_status(raw, proj)
    safety_dir = proj / "safety"
    safety_dir.mkdir(parents=True, exist_ok=True)
    dest = safety_dir / "safety-status.json"
    completed = set(map(str, state.get("phases_completed", [])))
    invalidated = {pid for pid in phase_ids if pid in completed}
    bump_review_attempt_epochs(state, review_phase_ids)
    if invalidated:
        previously_stale = set(map(str, state.get("stale_phases", [])))
        state["stale_phases"] = sorted(
            previously_stale | invalidated,
            key=lambda value: int(value),
        )
        state["pending_transition"] = None
    if normalized["high_risk_unresolved"]:
        state["safety_blocked"] = {
            "status": "BLOCKED",
            "high_risk_unresolved": normalized["high_risk_unresolved"],
            "unresolved_files": normalized["unresolved_files"],
            "imported_at": normalized["imported_at"],
        }
    else:
        state["safety_blocked"] = None
    state["safety_inventory"] = None
    state["scholar_init_import"] = {
        "source": str(source),
        "dest": str(dest),
        "imported_at": normalized["imported_at"],
        "safety_status": normalized["safety_status"],
        "high_risk_unresolved": normalized["high_risk_unresolved"]
    }
    state["updated_at"] = now()
    destination_original = dest.read_bytes() if dest.exists() else None
    dest_tmp = dest.with_suffix(".json.tmp")
    state_tmp = state_path.with_suffix(".json.tmp")
    try:
        dest_tmp.write_text(json.dumps(normalized, indent=2, sort_keys=True) + "\n")
        state_tmp.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
        dest_tmp.replace(dest)
        state_tmp.replace(state_path)
    except Exception:
        for temporary in (dest_tmp, state_tmp):
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
        if destination_original is None:
            try:
                dest.unlink()
            except FileNotFoundError:
                pass
        else:
            rollback = dest.with_suffix(".json.rollback")
            rollback.write_bytes(destination_original)
            rollback.replace(dest)
        raise
    stamp_dir = state_dir / "verify-stamps"
    for stale_pid in invalidated:
        stamp_path = stamp_dir / (stale_pid + ".json")
        try:
            stamp_path.unlink()
        except FileNotFoundError:
            pass
    print(f"IMPORTED_SAFETY={dest}")
    print(f"SAFETY_STATUS={normalized['safety_status']}")
    print(f"HIGH_RISK_UNRESOLVED={normalized['high_risk_unresolved']}")
    if normalized["high_risk_unresolved"]:
        for relative_path, reason in unresolved_reasons:
            path_json = json.dumps(relative_path, ensure_ascii=True)
            print(f"IMPORT_INIT_BLOCKED: reason={reason} path_json={path_json}")
        print("NEXT_ACTION=run scholar-init review before Phase 0 completion")
        raise SystemExit(1)
    print_mode_selection()
    raise SystemExit(0)

state = ensure_state_defaults(load_state())

if cmd == "migration-status":
    registry_path = contract_path.parent / "contract-migrations.json"
    registry = json.loads(registry_path.read_text())
    observed_schema = str(state.get("schema_version", ""))
    observed_hash = str(state.get("contract_sha256", ""))
    installed_hash = contract_hash()
    eligible = [
        item for item in registry.get("migrations", [])
        if isinstance(item, dict)
        and str(item.get("from_state_schema", "")) == observed_schema
        and str(item.get("from_contract_sha256", "")) == observed_hash
        and str(item.get("to_contract_sha256", "")) == installed_hash
    ]
    print(json.dumps({
        "state_schema": observed_schema,
        "recorded_contract_sha256": observed_hash,
        "installed_contract_sha256": installed_hash,
        "contract_drift": observed_hash != installed_hash,
        "eligible_migration_ids": [str(item.get("id")) for item in eligible],
        "next_action": (
            "migrate-contract <eligible-id> --operator <name> --reason <reason>"
            if eligible else
            ("restore the recorded contract; no allowlisted migration matches" if observed_hash != installed_hash else "none")
        ),
    }, indent=2, sort_keys=True))
    raise SystemExit(0)

if cmd == "migrate-contract":
    if not args:
        raise SystemExit("migrate-contract requires <migration_id> --operator <name> --reason <reason>")
    migration_id = str(args[0]).strip()
    options = option_map(args[1:])
    missing = [flag for flag in ("--operator", "--reason") if flag not in options]
    if missing:
        raise SystemExit("migrate-contract missing required option(s): " + ",".join(missing))
    registry_path = contract_path.parent / "contract-migrations.json"
    registry = json.loads(registry_path.read_text())
    migration = next((item for item in registry.get("migrations", []) if item.get("id") == migration_id), None)
    if not isinstance(migration, dict):
        raise SystemExit(f"UNKNOWN_CONTRACT_MIGRATION: {migration_id}")
    if any(event.get("migration_id") == migration_id for event in state.get("contract_migration_history", []) if isinstance(event, dict)):
        raise SystemExit(f"CONTRACT_MIGRATION_ALREADY_APPLIED: {migration_id}")
    observed = (str(state.get("schema_version", "")), str(state.get("contract_sha256", "")))
    expected = (str(migration.get("from_state_schema", "")), str(migration.get("from_contract_sha256", "")))
    target = (str(migration.get("to_state_schema", "")), str(migration.get("to_contract_sha256", "")))
    if observed != expected:
        raise SystemExit(
            "CONTRACT_MIGRATION_PREDECESSOR_MISMATCH: "
            f"expected schema/hash={expected[0]}/{expected[1]}, got {observed[0]}/{observed[1]}"
        )
    if target[0] != "1.3.0" or target[1] != contract_hash():
        raise SystemExit("CONTRACT_MIGRATION_TARGET_MISMATCH: installed contract is not the allowlisted target")
    invalidate_from_phase = migration.get("invalidate_from_phase")
    invalidate_review_evidence = migration.get("invalidate_review_evidence")
    if (
        isinstance(invalidate_from_phase, bool)
        or not isinstance(invalidate_from_phase, int)
        or str(invalidate_from_phase) not in phase_by_id
        or not isinstance(invalidate_review_evidence, bool)
    ):
        raise SystemExit(
            "CONTRACT_MIGRATION_POLICY_INVALID: invalidate_from_phase must name a phase "
            "and invalidate_review_evidence must be boolean"
        )
    completed = set(map(str, state.get("phases_completed", [])))
    invalidated = {
        pid for pid in completed
        if pid.isdigit() and int(pid) >= invalidate_from_phase
    }
    if invalidate_review_evidence:
        completed_review = sorted(review_phase_ids & completed, key=int)
        if completed_review:
            earliest_review = int(completed_review[0])
            invalidated.update(
                pid for pid in completed
                if pid.isdigit() and int(pid) >= earliest_review
            )
        for pid in completed_review:
            record = state.get("phase_records", {}).get(pid)
            if isinstance(record, dict):
                record["review_evidence_status"] = "legacy_unverified"
        epoch_bump_phases = set(review_phase_ids)
    else:
        epoch_bump_phases = {
            pid for pid in review_phase_ids if int(pid) >= invalidate_from_phase
        }
    state["schema_version"] = target[0]
    state["contract_sha256"] = target[1]
    if invalidate_review_evidence:
        state["review_assurance_profile"] = "normal"
    state.setdefault("review_attempt_epochs", {pid: 0 for pid in review_phase_ids})
    bump_review_attempt_epochs(state, epoch_bump_phases)
    state["stale_phases"] = sorted(set(map(str, state.get("stale_phases", []))) | invalidated, key=int)
    if invalidated:
        state["pending_transition"] = None
    event = {
        "migration_id": migration_id,
        "migrated_at": now(),
        "operator": options["--operator"],
        "reason": options["--reason"],
        "from_state_schema": expected[0],
        "from_contract_sha256": expected[1],
        "to_state_schema": target[0],
        "to_contract_sha256": target[1],
        "invalidation_policy": {
            "invalidate_from_phase": invalidate_from_phase,
            "invalidate_review_evidence": invalidate_review_evidence,
        },
        "invalidated_phases": sorted(invalidated, key=int),
        "epoch_bump_phases": sorted(epoch_bump_phases, key=int),
    }
    state.setdefault("contract_migration_history", []).append(event)
    state["updated_at"] = event["migrated_at"]
    if os.environ.get("SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT") == "migration-before-save":
        raise SystemExit("INJECTED_MIGRATION_FAILURE: before atomic state publication")
    save_state(state)
    print(f"CONTRACT_MIGRATED={migration_id}")
    print(f"STALE_PHASES={','.join(state['stale_phases'])}")
    raise SystemExit(0)

if cmd in {"review-begin", "review-complete", "review-abort", "set-review-profile"}:
    _check_contract_drift(state, mutating=True)
    enforce_not_halted(state)

if cmd == "review-begin":
    if len(args) < 3:
        raise SystemExit("review-begin requires <phase_id> <round> <backend> [--extra-role <role>]...")
    pid, round_name, backend = map(str, args[:3])
    if pid not in review_phase_ids:
        raise SystemExit(f"Phase {pid} does not require review evidence")
    enforce_run_mode_for_complete(state, pid)
    authoritative_next = str(compute_next_info(state).get("phase", ""))
    if pid != authoritative_next:
        raise SystemExit(f"OUT_OF_ORDER_REVIEW_SESSION: requested Phase {pid} but NEXT_PHASE={authoritative_next}")
    options = option_map(args[3:], repeatable={"--extra-role"})
    unknown = set(options) - {"--extra-role"}
    if unknown:
        raise SystemExit("review-begin unknown option(s): " + ",".join(sorted(unknown)))
    review_lock = acquire_review_lock(pid)
    try:
        envelope = begin_session(proj, contract, state, pid, round_name, backend, options.get("--extra-role", []))
        state["updated_at"] = now()
        if os.environ.get("SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT") == "review-begin-before-state-save":
            raise SystemExit("INJECTED_REVIEW_BEGIN_FAILURE: before state registration publication")
        save_state(state)
        if os.environ.get("SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT") == "review-begin-after-state-save":
            raise SystemExit("INJECTED_REVIEW_BEGIN_FAILURE: after state registration publication")
    except EvidenceError as exc:
        raise SystemExit(f"REVIEW_EVIDENCE_BEGIN_FAILED: {exc}")
    print("REVIEW_SESSION_JSON=" + json.dumps(envelope, sort_keys=True, separators=(",", ":")))
    print(f"REVIEW_SESSION_ID={envelope['session_id']}")
    raise SystemExit(0)

if cmd == "review-complete":
    if len(args) < 3:
        raise SystemExit("review-complete requires <phase_id> <session_id> <role> plus host/model availability options")
    pid, session_id, role = map(str, args[:3])
    if pid not in review_phase_ids:
        raise SystemExit(f"Phase {pid} does not require review evidence")
    enforce_run_mode_for_complete(state, pid)
    authoritative_next = str(compute_next_info(state).get("phase", ""))
    if pid != authoritative_next:
        raise SystemExit(f"OUT_OF_ORDER_REVIEW_COMPLETION: requested Phase {pid} but NEXT_PHASE={authoritative_next}")
    options = option_map(args[3:])
    allowed = {"--driver-status", "--host-task-id", "--host-task-unavailable", "--model-id", "--model-unavailable"}
    unknown = set(options) - allowed
    if unknown:
        raise SystemExit("review-complete unknown option(s): " + ",".join(sorted(unknown)))
    if "--driver-status" not in options:
        raise SystemExit("review-complete requires --driver-status succeeded")
    review_lock = acquire_review_lock(pid)
    try:
        result = complete_role(
            proj, contract, state, pid, session_id, role,
            driver_status=options["--driver-status"],
            host_task_id=options.get("--host-task-id"),
            host_task_unavailable=options.get("--host-task-unavailable"),
            model_id=options.get("--model-id"),
            model_unavailable=options.get("--model-unavailable"),
        )
        state["updated_at"] = now()
        if os.environ.get("SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT") == "review-complete-before-state-save":
            raise SystemExit("INJECTED_REVIEW_COMPLETION_FAILURE: before state completion publication")
        save_state(state)
        if os.environ.get("SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT") == "review-complete-after-state-save":
            raise SystemExit("INJECTED_REVIEW_COMPLETION_FAILURE: after state completion publication")
    except EvidenceError as exc:
        raise SystemExit(f"REVIEW_EVIDENCE_COMPLETION_FAILED: {exc}")
    print("REVIEW_COMPLETION_JSON=" + json.dumps(result, sort_keys=True, separators=(",", ":")))
    print(f"REVIEW_ROLE_COMPLETED={role}")
    raise SystemExit(0)

if cmd == "review-abort":
    if len(args) < 2:
        raise SystemExit("review-abort requires <phase_id> <session_id> --reason <reason>")
    pid, session_id = map(str, args[:2])
    if pid not in review_phase_ids:
        raise SystemExit(f"Phase {pid} does not require review evidence")
    authoritative_next = str(compute_next_info(state).get("phase", ""))
    if pid != authoritative_next:
        raise SystemExit(f"OUT_OF_ORDER_REVIEW_ABORT: requested Phase {pid} but NEXT_PHASE={authoritative_next}")
    options = option_map(args[2:])
    if set(options) != {"--reason"}:
        raise SystemExit("review-abort requires exactly --reason <reason>")
    review_lock = acquire_review_lock(pid)
    try:
        record = abort_session(proj, contract, state, pid, session_id, options["--reason"])
        state["updated_at"] = now()
        if os.environ.get("SCHOLAR_AUTO_RESEARCH_TEST_FAILPOINT") == "review-abort-before-state-save":
            raise SystemExit("INJECTED_REVIEW_ABORT_FAILURE: before state abort publication")
        save_state(state)
    except EvidenceError as exc:
        raise SystemExit(f"REVIEW_EVIDENCE_ABORT_FAILED: {exc}")
    print("REVIEW_SESSION_ABORTED=" + str(record["session_id"]))
    raise SystemExit(0)

if cmd == "set-review-profile":
    if not args or str(args[0]) not in {"normal", "strict"}:
        raise SystemExit("set-review-profile requires normal or strict plus --operator and --reason")
    profile = str(args[0])
    options = option_map(args[1:])
    if set(options) != {"--operator", "--reason"}:
        raise SystemExit("set-review-profile requires exactly --operator and --reason")
    previous = str(state.get("review_assurance_profile", "normal"))
    if profile == previous:
        raise SystemExit(f"REVIEW_PROFILE_UNCHANGED: already {profile}")
    completed = set(map(str, state.get("phases_completed", [])))
    affected_review = sorted(review_phase_ids & completed, key=int)
    invalidated = set()
    if affected_review:
        earliest = int(affected_review[0])
        invalidated = {pid for pid in completed if pid.isdigit() and int(pid) >= earliest}
    state["review_assurance_profile"] = profile
    bump_review_attempt_epochs(state, review_phase_ids)
    state["stale_phases"] = sorted(set(map(str, state.get("stale_phases", []))) | invalidated, key=int)
    if invalidated:
        state["pending_transition"] = None
    state.setdefault("review_profile_history", []).append({
        "changed_at": now(), "from": previous, "to": profile,
        "operator": options["--operator"], "reason": options["--reason"],
        "invalidated_phases": sorted(invalidated, key=int),
    })
    state["updated_at"] = now()
    save_state(state)
    print(f"REVIEW_ASSURANCE_PROFILE={profile}")
    print(f"STALE_PHASES={','.join(state['stale_phases'])}")
    raise SystemExit(0)

status_contract_drift = False
if cmd in {"next", "hash-check", "complete"}:
    _check_contract_drift(state, mutating=True)
elif cmd == "status":
    status_contract_drift = _check_contract_drift(state, mutating=False)

if cmd not in {"status", "clear-halt"}:
    enforce_not_halted(state)

safety_inventory_changed = False
if cmd in {"next", "hash-check", "complete"} or (cmd == "status" and not status_contract_drift):
    safety_inventory_changed = refresh_safety_inventory(state)
if cmd == "complete" and safety_inventory_changed:
    raise SystemExit(
        "SAFETY_INVENTORY_CHANGED: Phase 0 safety evidence no longer matches "
        "the current project inventory; re-run scholar-init, import-init, and Phase 0 verification."
    )

if cmd == "status":
    print(json.dumps(state, indent=2, sort_keys=True))
    raise SystemExit(0)

if cmd == "clear-halt":
    _check_contract_drift(state, mutating=True)
    values = {}
    idx = 0
    while idx < len(args):
        flag = args[idx]
        if flag not in {"--finding", "--reason", "--operator"}:
            raise SystemExit(f"clear-halt unknown option: {flag}")
        if idx + 1 >= len(args) or str(args[idx + 1]).strip() == "":
            raise SystemExit(f"clear-halt requires a nonempty value for {flag}")
        if flag in values:
            raise SystemExit(f"clear-halt option repeated: {flag}")
        values[flag] = str(args[idx + 1]).strip()
        idx += 2
    missing = [flag for flag in ("--finding", "--reason", "--operator") if flag not in values]
    if missing:
        raise SystemExit("clear-halt missing required option(s): " + ",".join(missing))
    if not state.get("halted") or not isinstance(state.get("halt"), dict):
        raise SystemExit("PIPELINE_NOT_HALTED: no persistent halt is active")
    finding = values["--finding"]
    halt = state["halt"]
    active_findings = [str(value) for value in halt.get("finding_ids", [])]
    if finding not in active_findings:
        raise SystemExit(
            "HALT_FINDING_MISMATCH: active findings="
            + ",".join(active_findings)
            + f"; requested={finding}"
        )
    cleared_at = now()
    retry_count = int(state.get("route_back_retry_counts", {}).get(finding, 0))
    remaining = [value for value in active_findings if value != finding]
    state.setdefault("halt_history", []).append({
        "action": "clear_halt",
        "finding_id": finding,
        "reason": values["--reason"],
        "operator": values["--operator"],
        "cleared_at": cleared_at,
        "halted_at": halt.get("halted_at"),
        "retry_count_at_clear": retry_count,
    })
    if remaining:
        halt["finding_ids"] = remaining
        state["halt"] = halt
        state["halted"] = True
    else:
        state["halt"] = None
        state["halted"] = False
    state["updated_at"] = cleared_at
    save_state(state)
    print(f"HALT_CLEARED_FOR={finding}")
    print("HALT_REMAINING_FINDINGS=" + ",".join(remaining))
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
    if not args:
        raise SystemExit("complete requires phase_id")
    pid = str(args[0])
    original_state_bytes = state_path.read_bytes()
    enforce_run_mode_for_complete(state, pid)
    if pid not in phase_by_id:
        raise SystemExit(f"unknown phase: {pid}")
    authoritative_next = str(compute_next_info(state).get("phase", ""))
    if pid != authoritative_next:
        raise SystemExit(
            f"OUT_OF_ORDER_PHASE: requested Phase {pid} but authoritative "
            f"NEXT_PHASE={authoritative_next}"
        )
    verified_safety_inventory = None
    if pid == "0":
        verified_safety_inventory = inventory_observation(
            proj, proj / "safety" / "safety-status.json"
        )
    # Snapshot the exact generation that is about to undergo semantic
    # verification. The verifier's late descriptor must equal this entry
    # snapshot; otherwise a write between semantic reads and descriptor
    # creation could bless bytes that were never semantically checked.
    pre_verification_outputs = resolve_contract_paths(
        phase_by_id[pid].get("required_outputs", [])
    )
    pre_verification_inputs = resolve_auxiliary_inputs(
        phase_by_id[pid].get("required_inputs", [])
    )
    verifier_path = skill_scripts / "auto-research-verify.sh"
    verifier_generation_sha256 = sha(verifier_path)
    verification = subprocess.run(
        ["bash", str(verifier_path), pid, str(proj)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if verification.returncode != 0:
        detail = verification.stdout.strip()
        raise SystemExit(
            f"VERIFY_AND_COMPLETE_FAILED: Phase {pid} verifier rc={verification.returncode}"
            + ("\n" + detail if detail else "")
        )
    if sha(verifier_path) != verifier_generation_sha256:
        raise SystemExit(
            f"VERIFIER_GENERATION_CHANGED: Phase {pid} verifier changed while executing; no state committed."
        )
    expected_pass = f"PASS: Phase {pid} {phase_by_id[pid]['name']} required outputs exist"
    if expected_pass not in verification.stdout.splitlines():
        raise SystemExit(
            f"VERIFY_AND_COMPLETE_FAILED: Phase {pid} verifier returned no exact PASS attestation"
        )
    descriptor_lines = [
        line.removeprefix("VERIFICATION_DESCRIPTOR_JSON=")
        for line in verification.stdout.splitlines()
        if line.startswith("VERIFICATION_DESCRIPTOR_JSON=")
    ]
    if len(descriptor_lines) != 1:
        raise SystemExit(
            f"VERIFY_AND_COMPLETE_FAILED: Phase {pid} verifier returned "
            f"{len(descriptor_lines)} verification descriptors"
        )
    try:
        descriptor = json.loads(descriptor_lines[0])
    except Exception as exc:
        raise SystemExit(
            f"VERIFY_AND_COMPLETE_FAILED: Phase {pid} descriptor is invalid JSON: {exc}"
        )
    if (
        descriptor.get("schema_version")
        != "scholar-auto-research-verification-descriptor/v1"
        or str(descriptor.get("phase_id")) != pid
        or descriptor.get("verdict") != "PASS"
        or descriptor.get("contract_sha256") != contract_hash()
    ):
        raise SystemExit(
            f"VERIFY_AND_COMPLETE_FAILED: Phase {pid} descriptor identity mismatch"
        )
    descriptor_review_evidence = descriptor.get("review_evidence")
    if pid in review_phase_ids:
        if not isinstance(descriptor_review_evidence, dict):
            raise SystemExit(f"VERIFY_AND_COMPLETE_FAILED: Phase {pid} descriptor lacks review evidence")
        expected_epoch = int(state.get("review_attempt_epochs", {}).get(pid, 0))
        if (
            descriptor_review_evidence.get("profile") != state.get("review_assurance_profile", "normal")
            or descriptor_review_evidence.get("attempt_epoch") != expected_epoch
        ):
            raise SystemExit(f"VERIFY_AND_COMPLETE_FAILED: Phase {pid} review evidence state binding mismatch")
    if descriptor.get("required_outputs") != pre_verification_outputs:
        raise SystemExit(
            f"VERIFIED_ARTIFACTS_CHANGED: Phase {pid} required outputs changed "
            "during semantic verification; no state committed."
        )
    if descriptor.get("required_inputs") != pre_verification_inputs:
        raise SystemExit(
            f"VERIFIED_INPUTS_CHANGED: Phase {pid} required inputs changed "
            "during semantic verification; no state committed."
        )
    if pid == "0":
        post_verify_inventory = inventory_observation(
            proj, proj / "safety" / "safety-status.json"
        )
        if post_verify_inventory.get("digest") != verified_safety_inventory.get("digest"):
            raise SystemExit(
                "SAFETY_INVENTORY_CHANGED_DURING_VERIFICATION: Phase 0 inventory "
                "or safety receipt changed while the verifier was running; no state committed."
            )
        verified_safety_inventory = post_verify_inventory
    required_outputs = resolve_contract_paths(phase_by_id[pid].get("required_outputs", []))
    asserted = []
    for raw in args[1:]:
        candidate = Path(raw)
        if not candidate.is_absolute():
            candidate = proj / candidate
        try:
            asserted.append(candidate.resolve().relative_to(proj.resolve()).as_posix())
        except ValueError:
            raise SystemExit(f"ARTIFACT_ASSERTION_OUTSIDE_PROJECT: {raw}")
    if asserted and set(asserted) != set(required_outputs):
        missing_assertions = sorted(set(required_outputs) - set(asserted))
        extra_assertions = sorted(set(asserted) - set(required_outputs))
        raise SystemExit(
            "ARTIFACT_ASSERTION_MISMATCH: "
            f"missing={','.join(missing_assertions) or '<none>'}; "
            f"extra={','.join(extra_assertions) or '<none>'}"
        )
    auxiliary_inputs = resolve_auxiliary_inputs(phase_by_id[pid].get("required_inputs", []))
    if required_outputs != descriptor.get("required_outputs"):
        raise SystemExit(
            f"VERIFIED_ARTIFACTS_CHANGED: Phase {pid} required outputs changed "
            "after verification; no state committed."
        )
    if auxiliary_inputs != descriptor.get("required_inputs"):
        raise SystemExit(
            f"VERIFIED_INPUTS_CHANGED: Phase {pid} required inputs changed "
            "after verification; no state committed."
        )
    record = {
        "phase_id": pid,
        "phase_name": phase_by_id[pid]["name"],
        "completed_at": now(),
        "contract_sha256": contract_hash(),
        "run_nonce": state["run_nonce"],
        "verdict": "PASS",
        "verification_authority": "internal_verifier",
        "verifier_sha256": verifier_generation_sha256,
        "required_outputs": required_outputs,
        "auxiliary_inputs": auxiliary_inputs,
        "artifacts": [
            {"path": path, "sha256": digest}
            for path, digest in required_outputs.items()
        ],
        "dependencies": phase_by_id[pid].get("hash_dependencies", [])
    }
    if pid in review_phase_ids:
        record["review_evidence"] = descriptor_review_evidence
        record["review_assurance_profile"] = state.get("review_assurance_profile", "normal")
        record["review_attempt_epoch"] = int(state.get("review_attempt_epochs", {}).get(pid, 0))
    completed = list(map(str, state.get("phases_completed", [])))
    if pid not in completed:
        completed.append(pid)
    state["phases_completed"] = completed
    state.setdefault("phase_records", {})[pid] = record
    if pid == "0":
        state["safety_inventory"] = verified_safety_inventory
        state["safety_blocked"] = None
    stale = [p for p in state.get("stale_phases", []) if str(p) != pid]
    state["stale_phases"] = stale
    active_route = state.get("active_route_back")
    if isinstance(active_route, dict):
        target = str(active_route.get("route_back_phase", "")).strip()
        if target.isdigit() and not any(str(p).isdigit() and int(str(p)) >= int(target) for p in stale):
            state.pop("active_route_back", None)
    make_pending_transition(state, pid, compute_next_info(state))
    state["updated_at"] = now()
    state_tmp = state_path.with_suffix(".json.tmp")
    state_tmp.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    if live_contract_hash() != transaction_contract_sha256:
        state_tmp.unlink()
        raise SystemExit(
            f"CONTRACT_GENERATION_CHANGED: Phase {pid} contract changed during completion; no state committed."
        )
    if sha(verifier_path) != verifier_generation_sha256:
        state_tmp.unlink()
        raise SystemExit(
            f"VERIFIER_GENERATION_CHANGED: Phase {pid} verifier changed before publication; no state committed."
        )
    final_outputs = resolve_contract_paths(phase_by_id[pid].get("required_outputs", []))
    final_inputs = resolve_auxiliary_inputs(phase_by_id[pid].get("required_inputs", []))
    if final_outputs != descriptor.get("required_outputs") or final_inputs != descriptor.get("required_inputs"):
        state_tmp.unlink()
        raise SystemExit(
            f"VERIFIED_ARTIFACTS_CHANGED: Phase {pid} outputs or inputs changed "
            "before state publication; no state committed."
        )
    if pid == "0":
        final_inventory = inventory_observation(
            proj, proj / "safety" / "safety-status.json"
        )
        if final_inventory.get("digest") != verified_safety_inventory.get("digest"):
            state_tmp.unlink()
            raise SystemExit(
                "SAFETY_INVENTORY_CHANGED_DURING_VERIFICATION: Phase 0 inventory "
                "changed before state publication; no state committed."
            )
    state_tmp.replace(state_path)
    published_changed = False
    try:
        if live_contract_hash() != transaction_contract_sha256:
            raise RuntimeError("contract generation changed after publication")
        if sha(verifier_path) != verifier_generation_sha256:
            raise RuntimeError("verifier generation changed after publication")
        published_outputs = resolve_contract_paths(phase_by_id[pid].get("required_outputs", []))
        published_inputs = resolve_auxiliary_inputs(phase_by_id[pid].get("required_inputs", []))
        published_changed = (
            published_outputs != descriptor.get("required_outputs")
            or published_inputs != descriptor.get("required_inputs")
        )
        if pid == "0":
            published_inventory = inventory_observation(
                proj, proj / "safety" / "safety-status.json"
            )
            published_changed = published_changed or (
                published_inventory.get("digest") != verified_safety_inventory.get("digest")
            )
    except BaseException:
        # resolve_contract_paths deliberately raises SystemExit on missing,
        # outside-project, or symlinked outputs. Once state publication has
        # occurred, every such observation failure is a rollback condition.
        published_changed = True
    if published_changed:
        rollback = state_path.with_suffix(".json.rollback")
        rollback.write_bytes(original_state_bytes)
        rollback.replace(state_path)
        raise SystemExit(
            f"VERIFIED_ARTIFACTS_CHANGED: Phase {pid} outputs, inputs, or safety "
            "inventory changed during state publication; state rolled back."
        )
    stamp_path = state_dir / "verify-stamps" / (pid + ".json")
    try:
        stamp_path.parent.mkdir(parents=True, exist_ok=True)
        stamp_tmp = stamp_path.with_suffix(".json.tmp")
        stamp_tmp.write_text(json.dumps({
                "schema_version": "scholar-auto-research-completion-audit/v1",
                "phase_id": pid,
                "verdict": "PASS",
                "authority": "audit_only_not_completion_input",
                "contract_sha256": record["contract_sha256"],
                "run_nonce": record["run_nonce"],
                "required_outputs": required_outputs,
                "completed_at": record["completed_at"],
            }, indent=2, sort_keys=True) + "\n")
        stamp_tmp.replace(stamp_path)
    except OSError as exc:
        print(f"ADVISORY: completion committed but audit receipt could not be refreshed: {exc}", file=sys.stderr)
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
    if int(target) > int(source_phase):
        raise SystemExit(
            f"INVALID_ROUTE_BACK_DIRECTION: source Phase {source_phase} cannot "
            f"route forward to Phase {target}"
        )
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
        if finding_id in finding_ids:
            raise SystemExit(f"DUPLICATE_ROUTE_BACK_FINDING_ID: {finding_id}")
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
    bump_review_attempt_epochs(state, {pid for pid in review_phase_ids if int(pid) >= target_int})
    stale.update(invalidated)
    state["stale_phases"] = sorted(stale, key=lambda x: int(x))
    # F9 (audit 2026-07-07): invalidate verify-stamps for every phase this
    # route-back marks stale, so a pre-route stamp cannot re-legitimize a phase
    # whose upstream inputs changed. The next verify of each phase re-mints it.
    stamp_dir = state_dir / "verify-stamps"
    for _pid in invalidated:
        _sp = stamp_dir / (str(_pid) + ".json")
        if _sp.exists():
            _sp.unlink()
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
        state["halted"] = True
        state["halt"] = {
            "reason": "route_back_retry_cap",
            "finding_ids": escalated,
            "source_phase": source_phase,
            "route_back_phase": target,
            "retry_cap": ESCALATE_CAP,
            "halted_at": event["routed_at"],
        }
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
        print("# To proceed after manual correction, use clear-halt with a matching")
        print("# --finding, nonempty --reason, and --operator; do not edit state.json.")
        raise SystemExit(2)
    state["active_route_back"] = {
        "source_phase": source_phase,
        "report_path": str(report_path),
        "route_back_phase": target,
        "invalidated_phases": event["invalidated_phases"],
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
    artifact_stale = set()
    records = state.get("phase_records", {})
    for pid, record in records.items():
        for artifact in record.get("artifacts", []):
            path = Path(artifact["path"])
            if not path.is_absolute():
                path = proj / path
            old = artifact["sha256"]
            if old == "DIR":
                if not path.exists():
                    artifact_stale.add(pid)
            elif not path.exists() or digest_path(path) != old:
                artifact_stale.add(pid)
    artifact_downstream = set(artifact_stale)
    if artifact_stale:
        changed = True
        while changed:
            changed = False
            for phase in contract["phases"]:
                pid = str(phase["id"])
                deps = set(map(str, phase.get("hash_dependencies", [])))
                if pid not in artifact_downstream and deps & artifact_downstream:
                    artifact_downstream.add(pid)
                    changed = True
    route_stale = set()
    active_route = state.get("active_route_back")
    if isinstance(active_route, dict):
        declared = active_route.get("invalidated_phases")
        if isinstance(declared, list) and declared:
            route_stale.update(str(pid) for pid in declared if str(pid) in phase_by_id)
        else:
            target = str(active_route.get("route_back_phase", ""))
            if target in phase_by_id:
                route_stale.add(target)
                route_stale.update(
                    str(pid) for pid in state.get("stale_phases", [])
                    if str(pid) in phase_by_id and int(str(pid)) >= int(target)
                )
    safety_stale = set()
    if isinstance(state.get("safety_blocked"), dict):
        safety_stale.update(
            str(pid) for pid in state.get("stale_phases", []) if str(pid) in phase_by_id
        )
    durable_stale = set(map(str, state.get("stale_phases", [])))
    combined_stale = durable_stale | artifact_downstream | route_stale | safety_stale
    bump_review_attempt_epochs(state, combined_stale - durable_stale)
    state["stale_phases"] = sorted(combined_stale, key=lambda x: int(x))
    if artifact_downstream and not isinstance(active_route, dict):
        make_pending_transition(state, "hash-check", compute_next_info(state), reason="stale")
    state["updated_at"] = now()
    save_state(state)
    print(f"STALE_PHASES={','.join(state['stale_phases'])}")
    raise SystemExit(1 if combined_stale else 0)

raise SystemExit(f"unknown command: {cmd}")
PY
_ARS_RC=$?
set -e

# ── Run-view refresh (2026-08-20) ───────────────────────────────────────────
# Re-render <proj>/logs/run-html/index.html after a phase boundary so the run
# view tracks an auto-research pipeline as it executes — including route-backs,
# which is where this orchestrator's spine differs most from full-paper's.
#
# Same contract as the pipeline-state.sh hook: refresh-run-html.sh writes
# nothing to stdout (this script's stdout is parsed for KEY=VALUE lines) and
# always exits 0, and the captured exit code is re-raised unchanged below, so
# the instrumentation can neither mask a failure nor invent one.
case "$CMD" in
  complete|route-back|next)
    if [ "${SCHOLAR_RUN_HTML_AUTO:-1}" != "0" ]; then
      _ars_refresh="$SCRIPT_DIR/gates/refresh-run-html.sh"
      if [ ! -f "$_ars_refresh" ]; then
        echo "ADVISORY: optional run-view refresh unavailable: $_ars_refresh" >&2
      else
        _ars_view_err="$(mktemp "${TMPDIR:-/tmp}/auto-research-run-view.XXXXXX")"
        if ! bash "$_ars_refresh" "$PROJ" >/dev/null 2>"$_ars_view_err"; then
          echo "ADVISORY: optional run-view refresh failed for $PROJ" >&2
        elif [ -s "$_ars_view_err" ]; then
          sed 's/^/ADVISORY: optional run-view: /' "$_ars_view_err" >&2
        fi
        rm -f "$_ars_view_err"
      fi
    fi
    ;;
esac

exit "$_ARS_RC"
