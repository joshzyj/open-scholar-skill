#!/usr/bin/env python3
"""Test-only adapter that drives the production review-evidence lifecycle.

It may seed prior phase state for isolated verifier fixtures, but it never
authors evidence/session/completion records: those come only from the
production state commands under test.
"""

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import time


def nested(value, dotted):
    if dotted == ".":
        return value
    for key in dotted.split("."):
        value = value[key]
    return value


parser = argparse.ArgumentParser()
parser.add_argument("skill_dir")
parser.add_argument("project")
parser.add_argument("phase")
parser.add_argument("round")
parser.add_argument("--extra-role", action="append", default=[])
parser.add_argument(
    "--evidence-report",
    action="append",
    default=[],
    metavar="ROLE=PROJECT_RELATIVE_PATH",
    help="copy alternate test report bytes into one role's evidence path before completion",
)
args = parser.parse_args()

evidence_report_overrides = {}
for value in args.evidence_report:
    role, separator, relative = value.partition("=")
    if not separator or not role.strip() or not relative.strip():
        parser.error("--evidence-report must be ROLE=PROJECT_RELATIVE_PATH")
    relative_path = pathlib.PurePosixPath(relative.strip())
    if relative_path.is_absolute() or ".." in relative_path.parts:
        parser.error("--evidence-report path must stay project-relative")
    evidence_report_overrides[role.strip()] = relative_path

skill = pathlib.Path(args.skill_dir).resolve()
project = pathlib.Path(args.project).resolve()
state_tool = skill / "scripts" / "auto-research-state.sh"
contract_path = skill / "references" / "phase-contract.json"
state_path = project / ".auto-research" / "state.json"
contract = json.loads(contract_path.read_text())
phase = next(item for item in contract["phases"] if str(item["id"]) == args.phase)
policy = phase["review_evidence_policy"]
round_policy = policy["rounds"][args.round]

if not state_path.exists():
    subprocess.run(["bash", str(state_tool), "init", str(project)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([
        "bash", str(state_tool), "set-mode", str(project), "autonomous",
        "isolated verifier fixture",
    ], check=True, stdout=subprocess.DEVNULL)

state = json.loads(state_path.read_text())
state["schema_version"] = "1.3.0"
state["contract_sha256"] = hashlib.sha256(contract_path.read_bytes()).hexdigest()
state["review_assurance_profile"] = "normal"
state.setdefault("review_attempt_epochs", {pid: 0 for pid in ("6", "7", "9", "14", "18", "20")})
state.setdefault("review_evidence_history", [])
state.setdefault("contract_migration_history", [])
state["phases_completed"] = [str(value) for value in range(int(args.phase))]
state["stale_phases"] = []
state["pending_transition"] = None
for phase_id in state["phases_completed"]:
    state.setdefault("phase_records", {}).setdefault(phase_id, {
        "phase_id": phase_id,
        "phase_name": "fixture prerequisite",
        "fixture_only": True,
        "artifacts": [],
        "dependencies": [],
    })
temporary = state_path.with_suffix(".json.tmp")
temporary.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
temporary.replace(state_path)

command = [
    "bash", str(state_tool), "review-begin", str(project), args.phase,
    args.round, "generic-fixture-host",
]
for role in args.extra_role:
    command.extend(["--extra-role", role])
output = subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE).stdout
session_id = next(line.split("=", 1)[1] for line in output.splitlines() if line.startswith("REVIEW_SESSION_ID="))
session_path = project / policy["evidence_root"] / session_id / "session.json"
session = json.loads(session_path.read_text())

binding_path = project / round_policy.get("binding_output", policy["summary_output"])
binding_document = json.loads(binding_path.read_text())
role_field = round_policy.get("role_field", "role")
report_path_field = round_policy.get("report_path_field", "report_path")
task_id_field = round_policy.get("task_id_field", "task_invocation_id")
if round_policy.get("binding_collection"):
    records = nested(binding_document, round_policy["binding_collection"])
else:
    records = [nested(binding_document, round_policy["binding_object"])]
by_role = {str(record.get(role_field, "")): record for record in records}

for index, reservation in enumerate(session["reservations"], 1):
    role = reservation["role"]
    record = by_role.get(role)
    if record is None and len(records) == 1:
        record = records[0]
        record[role_field] = role
        by_role[role] = record
    if record is None:
        raise SystemExit(f"fixture summary has no semantic record for role {role}")
    source_relative = record.get("report_path")
    if not source_relative:
        raise SystemExit(f"fixture semantic record has no report_path for role {role}")
    source = project / evidence_report_overrides.get(role, pathlib.PurePosixPath(source_relative))
    if not source.is_file():
        raise SystemExit(f"fixture evidence report source is missing for role {role}: {source}")
    destination = project / reservation["report_path"]
    trace = project / reservation["trace_path"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    trace.parent.mkdir(parents=True, exist_ok=True)
    text = source.read_text(encoding="utf-8")
    old_task = str(record.get("task_invocation_id", ""))
    if old_task:
        text = text.replace(old_task, reservation["dispatch_id"])
    destination.write_text(
        text + f"\nEVIDENCE_ROLE: {role}\nEVIDENCE_SESSION: {session_id}\n",
        encoding="utf-8",
    )
    trace.write_text(json.dumps({
        "step": f"phase-{args.phase}-{role}",
        "reasoning": "exercise production evidence lifecycle in an isolated semantic fixture",
        "action": f"persist the {role} report and trace for session {session_id}",
        "observation": f"fixture role {index} completed in session {session_id}",
        "status": "ok",
    }) + "\n", encoding="utf-8")
    subprocess.run([
        "bash", str(state_tool), "review-complete", str(project), args.phase,
        session_id, role, "--driver-status", "succeeded",
        "--host-task-id", f"fixture-{args.phase}-{session_id}-{index}",
        "--model-unavailable", "fixture host intentionally exposes no model identity",
    ], check=True, stdout=subprocess.DEVNULL)
    record[report_path_field] = reservation["report_path"]
    record[task_id_field] = reservation["dispatch_id"]

# Some canonical phase schemas carry a denormalized report-path inventory in
# addition to the semantic reviewer records. Keep that inventory derived from
# the evidence-bound records instead of leaving stale pre-registration paths.
if isinstance(binding_document.get("agent_reports"), list):
    binding_document["agent_reports"] = [
        record["report_path"] for record in records if isinstance(record, dict)
    ]

# Phases 7 and 9 retain reviewer_provenance as descriptive metadata. Derive
# its duplicated execution identity from the evidence-bound reviewer records
# so the fixture exercises the production single-authority rule.
if isinstance(binding_document.get("reviewer_provenance"), list):
    canonical_by_id = {
        str(record.get("reviewer_id", "")): record
        for record in records if isinstance(record, dict)
    }
    for provenance in binding_document["reviewer_provenance"]:
        if not isinstance(provenance, dict):
            continue
        canonical = canonical_by_id.get(str(provenance.get("reviewer_id", "")))
        if canonical is None:
            continue
        for field in ("role", "task_invocation_id", "report_path"):
            provenance[field] = canonical[field]

binding_path.write_text(json.dumps(binding_document, indent=2, sort_keys=True) + "\n")
summary_path = project / policy["summary_output"]
summary = json.loads(summary_path.read_text())
evidence = summary.setdefault("review_evidence", {
    "profile": "normal",
    "attempt_epoch": int(state.get("review_attempt_epochs", {}).get(args.phase, 0)),
    "rounds": {},
})
evidence["profile"] = "normal"
evidence["attempt_epoch"] = int(state.get("review_attempt_epochs", {}).get(args.phase, 0))
for name, candidate in policy["rounds"].items():
    condition = candidate.get("when_nonempty_array")
    active = True
    if condition:
        document = json.loads((project / condition["path"]).read_text())
        active = bool(document[condition["field"]])
    if not active:
        evidence["rounds"][name] = {"status": "not_applicable"}
evidence["rounds"][args.round] = {
    "session_id": session_id,
    "achieved_assurance": "process_recorded",
}
summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")

if args.phase == "6":
    stamp = time.time()
    os.utime(summary_path, (stamp, stamp))
    os.utime(project / "review" / "pre-execution-fix-log.json", (stamp + 1, stamp + 1))
    os.utime(project / "review" / "pre-execution-rereview.json", (stamp + 2, stamp + 2))

print(f"FIXTURE_REVIEW_SESSION_ID={session_id}")
