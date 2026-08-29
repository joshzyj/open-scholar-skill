#!/usr/bin/env python3
"""Test-only fixture constructor for state tests unrelated to completion.

This script never calls or imitates the production completion authority. It
marks one already-assumed phase complete so route, drift, dependency, and HITL
tests can start from a declared state without forging project-local receipts.
"""

import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


if len(sys.argv) < 5:
    raise SystemExit("usage: seed-completed-phase.py <contract> <project> <phase> <artifact> [artifact...]")

contract_path = Path(sys.argv[1])
project = Path(sys.argv[2])
phase_id = sys.argv[3]
artifacts = [Path(value) for value in sys.argv[4:]]
state_path = project / ".auto-research" / "state.json"
contract = json.loads(contract_path.read_text())
state = json.loads(state_path.read_text())
phases = {str(item["id"]): item for item in contract["phases"]}
if phase_id not in phases:
    raise SystemExit(f"unknown fixture phase: {phase_id}")
if state.get("run_mode", {}).get("mode") == "human_in_loop":
    raise SystemExit(
        "fixture seeder refuses human_in_loop mode; use production completion authority"
    )


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


for artifact in artifacts:
    if not artifact.is_file():
        raise SystemExit(f"fixture artifact missing/not-file: {artifact}")

completed = list(map(str, state.get("phases_completed", [])))
if phase_id not in completed:
    completed.append(phase_id)
state["phases_completed"] = completed
state.setdefault("phase_records", {})[phase_id] = {
    "phase_id": phase_id,
    "phase_name": phases[phase_id]["name"],
    "completed_at": datetime.now(timezone.utc).isoformat(),
    "fixture_only": True,
    "artifacts": [{"path": str(path), "sha256": digest(path)} for path in artifacts],
    "dependencies": phases[phase_id].get("hash_dependencies", []),
}
state["stale_phases"] = [value for value in state.get("stale_phases", []) if str(value) != phase_id]

active = state.get("active_route_back")
if isinstance(active, dict):
    target = str(active.get("route_back_phase", ""))
    if target.isdigit() and not any(
        str(value).isdigit() and int(str(value)) >= int(target)
        for value in state["stale_phases"]
    ):
        state.pop("active_route_back", None)

state["updated_at"] = datetime.now(timezone.utc).isoformat()
temporary = state_path.with_suffix(".json.tmp")
temporary.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
temporary.replace(state_path)
