#!/usr/bin/env python3
"""Host-neutral, state-anchored review evidence for scholar-auto-research.

Mutation functions are called by auto-research-state.sh while it holds the
project state lock.  The CLI is deliberately read-only.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import re
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path


SCHEMA = "scholar-auto-research-review-evidence/v1"
SESSION_EVENT = "review_session_registered"
COMPLETION_EVENT = "review_role_completed"
ABORT_EVENT = "review_session_aborted"
HOST_CLAIMS = (
    "task_identity",
    "terminal_status",
    "completion_time",
    "report_digest",
    "reviewed_inputs_digest",
)


class EvidenceError(ValueError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_bytes(value) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def canonical_digest(value) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def validate_trace_sidecar(path: Path) -> None:
    """Validate the binding host-neutral RAO NDJSON contract."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError as exc:
        raise EvidenceError("review trace must be UTF-8 NDJSON") from exc
    if not lines:
        raise EvidenceError("review trace must contain at least one NDJSON record")
    for line_number, line in enumerate(lines, 1):
        if not line.strip():
            raise EvidenceError(f"review trace line {line_number} must not be blank")
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise EvidenceError(f"review trace line {line_number} is not valid JSON") from exc
        if not isinstance(record, dict):
            raise EvidenceError(f"review trace line {line_number} must be a JSON object")
        if not isinstance(record.get("step"), str) or not record["step"].strip():
            raise EvidenceError(f"review trace line {line_number} requires nonempty step")
        if not any(
            isinstance(record.get(key), str) and record[key].strip()
            for key in ("reasoning", "action", "observation")
        ):
            raise EvidenceError(
                f"review trace line {line_number} requires reasoning, action, or observation"
            )
        if record.get("status") not in {"ok", "fail", "skipped"}:
            raise EvidenceError(
                f"review trace line {line_number} status must be ok, fail, or skipped"
            )
        refs = record.get("refs")
        if refs is not None and (
            not isinstance(refs, list)
            or any(not isinstance(ref, str) or not ref.strip() for ref in refs)
        ):
            raise EvidenceError(f"review trace line {line_number} refs must be a string array")


def validate_report(path: Path) -> None:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise EvidenceError("review report must be valid UTF-8 text") from exc
    if not text.strip():
        raise EvidenceError("review report must contain non-whitespace text")


def write_json_exclusive(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(value, indent=2, sort_keys=True) + "\n"
    try:
        with path.open("x", encoding="utf-8") as handle:
            handle.write(payload)
    except FileExistsError as exc:
        raise EvidenceError(f"evidence record already exists: {path}") from exc


def read_json(path: Path, label: str):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise EvidenceError(f"{label} missing: {path}") from exc
    except Exception as exc:
        raise EvidenceError(f"{label} is not valid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} must be a JSON object: {path}")
    return value


def normalize_relative(project: Path, raw, label: str, *, must_exist=True) -> tuple[str, Path]:
    text = str(raw or "").strip()
    if not text or Path(text).is_absolute():
        raise EvidenceError(f"{label} must be a nonempty project-relative path")
    candidate = project / text
    if must_exist and not candidate.exists():
        raise EvidenceError(f"{label} missing: {text}")
    if candidate.is_symlink():
        raise EvidenceError(f"{label} must not be a symlink: {text}")
    try:
        relative = candidate.resolve().relative_to(project.resolve()).as_posix()
    except ValueError as exc:
        raise EvidenceError(f"{label} resolves outside project: {text}") from exc
    return relative, candidate


def resolve_input_patterns(project: Path, patterns) -> dict[str, str]:
    if not isinstance(patterns, list) or not patterns:
        raise EvidenceError("review evidence input_patterns must be a nonempty list")
    result: dict[str, str] = {}
    for raw_pattern in patterns:
        pattern = str(raw_pattern or "").strip()
        if not pattern or Path(pattern).is_absolute():
            raise EvidenceError(f"invalid review input pattern: {pattern!r}")
        matches = sorted(glob.glob(str(project / pattern)))
        if not matches:
            raise EvidenceError(f"review input pattern matched no files: {pattern}")
        for raw in matches:
            relative, path = normalize_relative(project, Path(raw).relative_to(project), "review input")
            if not path.is_file():
                raise EvidenceError(f"review input must be a regular file: {relative}")
            if relative in result:
                raise EvidenceError(f"duplicate review input after normalization: {relative}")
            result[relative] = sha256_file(path)
    return dict(sorted(result.items()))


def phase_policy(contract: dict, phase_id: str) -> tuple[dict, dict]:
    phase = next((item for item in contract.get("phases", []) if str(item.get("id")) == str(phase_id)), None)
    if not isinstance(phase, dict):
        raise EvidenceError(f"unknown review phase: {phase_id}")
    policy = phase.get("review_evidence_policy")
    if not isinstance(policy, dict):
        raise EvidenceError(f"Phase {phase_id} does not declare review_evidence_policy")
    return phase, policy


def policy_round(policy: dict, round_name: str) -> dict:
    rounds = policy.get("rounds")
    if not isinstance(rounds, dict) or round_name not in rounds or not isinstance(rounds[round_name], dict):
        raise EvidenceError(f"unknown review round: {round_name}")
    return rounds[round_name]


def round_is_active(project: Path, round_policy: dict) -> bool:
    condition = round_policy.get("when_nonempty_array")
    if condition is None:
        return True
    if not isinstance(condition, dict):
        raise EvidenceError("when_nonempty_array must be an object")
    relative, path = normalize_relative(project, condition.get("path"), "conditional round input")
    value = read_json(path, f"conditional round input {relative}")
    field = str(condition.get("field", "")).strip()
    if not field:
        raise EvidenceError("conditional round field is missing")
    items = value.get(field)
    if not isinstance(items, list):
        raise EvidenceError(f"conditional round field must be a list: {relative}.{field}")
    return bool(items)


def evidence_root(project: Path, policy: dict) -> tuple[str, Path]:
    relative, path = normalize_relative(
        project,
        policy.get("evidence_root"),
        "review evidence root",
        must_exist=False,
    )
    expected = str(policy.get("evidence_root", "")).rstrip("/")
    if relative != expected:
        raise EvidenceError("review evidence root normalization mismatch")
    return relative, path


def opaque_value(value, label: str) -> str:
    text = str(value or "")
    if not text.strip() or len(text) > 512 or any(ord(char) < 32 or ord(char) == 127 for char in text):
        raise EvidenceError(f"{label} must be a bounded nonempty control-free opaque string")
    if label in {"host task ID", "model ID"} and re.fullmatch(
        r"(?i)(?:tbd|todo|unknown|none|null|placeholder|unavailable|n/?a|not[-_ ]?available)",
        text.strip(),
    ):
        raise EvidenceError(f"{label} placeholder must use structured unavailability")
    return text


def unavailable(reason, label: str) -> dict:
    text = str(reason or "").strip()
    if not text:
        raise EvidenceError(f"{label} unavailability requires a reason")
    return {"status": "unavailable", "reason": text}


def reported(value, label: str) -> dict:
    return {"status": "reported", "value": opaque_value(value, label)}


def _events(state: dict, event_type: str, **identity) -> list[dict]:
    matches = []
    for event in state.get("review_evidence_history", []):
        if not isinstance(event, dict) or event.get("event") != event_type:
            continue
        if all(str(event.get(key, "")) == str(value) for key, value in identity.items()):
            matches.append(event)
    return matches


def _require_round_registration_order(
    project: Path,
    policy: dict,
    state: dict,
    phase_id: str,
    round_name: str,
    attempt_epoch: int,
) -> None:
    """Reject a reservation that would violate the declared round lifecycle.

    State history is an append-only event sequence.  A later round may only be
    reserved after every active earlier round has one live session and every
    reservation in that session has a registered, digest-bound completion.
    Conversely, an earlier round cannot be inserted after a later live round.
    """
    declared = policy.get("rounds")
    if not isinstance(declared, dict) or round_name not in declared:
        raise EvidenceError(f"review round is not declared: {round_name}")
    ordered_names = list(declared)
    requested_index = ordered_names.index(round_name)
    history = state.get("review_evidence_history", [])
    aborted_ids = {
        str(event.get("session_id")) for event in history
        if isinstance(event, dict)
        and event.get("event") == ABORT_EVENT
        and str(event.get("phase_id")) == str(phase_id)
    }
    live_registrations = [
        event for event in history
        if isinstance(event, dict)
        and event.get("event") == SESSION_EVENT
        and str(event.get("phase_id")) == str(phase_id)
        and event.get("attempt_epoch") == attempt_epoch
        and str(event.get("session_id")) not in aborted_ids
    ]
    later_names = set(ordered_names[requested_index + 1:])
    if any(event.get("round") in later_names for event in live_registrations):
        raise EvidenceError(
            f"review round order violation: {round_name} cannot be registered after a later round"
        )
    _, root = evidence_root(project, policy)
    for prior_name in ordered_names[:requested_index]:
        prior_policy = policy_round(policy, prior_name)
        if not round_is_active(project, prior_policy):
            continue
        registrations = [
            event for event in live_registrations if event.get("round") == prior_name
        ]
        if len(registrations) != 1:
            raise EvidenceError(
                f"review round order violation: complete active prior round {prior_name} "
                f"before registering {round_name}"
            )
        registration = registrations[0]
        session_id = str(registration.get("session_id", ""))
        session_path = root / session_id / "session.json"
        session = read_json(session_path, f"prior round {prior_name} session")
        if (
            session.get("round") != prior_name
            or session.get("attempt_epoch") != attempt_epoch
            or registration.get("reservation_sha256") != sha256_file(session_path)
        ):
            raise EvidenceError(f"review round order violation: prior round {prior_name} is not validly registered")
        reservations = session.get("reservations")
        if not isinstance(reservations, list) or not reservations:
            raise EvidenceError(f"review round order violation: prior round {prior_name} has invalid reservations")
        for reservation in reservations:
            if not isinstance(reservation, dict):
                raise EvidenceError(f"review round order violation: prior round {prior_name} has invalid reservations")
            role = str(reservation.get("role", ""))
            completions = _events(
                state,
                COMPLETION_EVENT,
                phase_id=phase_id,
                session_id=session_id,
                role=role,
            )
            completion_path = root / session_id / "completions" / f"{role}.json"
            if (
                len(completions) != 1
                or not completion_path.is_file()
                or completions[0].get("completion_sha256") != sha256_file(completion_path)
            ):
                raise EvidenceError(
                    f"review round order violation: complete active prior round {prior_name} "
                    f"before registering {round_name}"
                )


def begin_session(
    project: Path,
    contract: dict,
    state: dict,
    phase_id: str,
    round_name: str,
    backend: str,
    extra_roles=None,
) -> dict:
    _, policy = phase_policy(contract, phase_id)
    round_policy = policy_round(policy, round_name)
    profile = str(state.get("review_assurance_profile", "normal"))
    if profile not in {"normal", "strict"}:
        raise EvidenceError(f"invalid state review_assurance_profile: {profile}")
    backend = opaque_value(backend, "host backend")
    if not round_is_active(project, round_policy):
        raise EvidenceError(f"review round is not applicable: {round_name}")
    attempt_epoch = int(state.get("review_attempt_epochs", {}).get(str(phase_id), 0))
    _require_round_registration_order(
        project, policy, state, str(phase_id), round_name, attempt_epoch
    )
    registered = [
        event for event in state.get("review_evidence_history", [])
        if isinstance(event, dict)
        and event.get("event") == SESSION_EVENT
        and str(event.get("phase_id")) == str(phase_id)
        and event.get("round") == round_name
        and event.get("attempt_epoch") == attempt_epoch
    ]
    aborted_ids = {
        str(event.get("session_id")) for event in state.get("review_evidence_history", [])
        if isinstance(event, dict)
        and event.get("event") == ABORT_EVENT
        and str(event.get("phase_id")) == str(phase_id)
    }
    if any(str(event.get("session_id")) not in aborted_ids for event in registered):
        raise EvidenceError(f"active review session already exists for Phase {phase_id} round {round_name}")
    roles = round_policy.get("roles")
    if not isinstance(roles, list) or not roles or len(set(map(str, roles))) != len(roles):
        raise EvidenceError(f"Phase {phase_id} round {round_name} roles are invalid")
    roles = list(map(str, roles))
    extras = list(map(str, extra_roles or []))
    optional_groups = round_policy.get("optional_role_groups", [])
    allowed_extras = {str(role) for group in optional_groups if isinstance(group, list) for role in group}
    if any(role not in allowed_extras for role in extras):
        raise EvidenceError(f"Phase {phase_id} round {round_name} has an unallowed extra role")
    for group in optional_groups:
        chosen = set(extras) & set(map(str, group))
        if len(chosen) > 1:
            raise EvidenceError(f"Phase {phase_id} round {round_name} selects multiple roles from one optional group")
    roles.extend(extras)
    if len(set(roles)) != len(roles):
        raise EvidenceError(f"Phase {phase_id} round {round_name} roles are duplicated")
    inputs = resolve_input_patterns(project, round_policy.get("input_patterns"))
    root_relative, root = evidence_root(project, policy)
    root.mkdir(parents=True, exist_ok=True)
    session_id = "s-" + secrets.token_hex(12)
    session_relative = f"{root_relative}/{session_id}"
    session_dir = project / session_relative
    try:
        session_dir.mkdir(parents=False, exist_ok=False)
    except FileExistsError as exc:
        raise EvidenceError("review session path already exists; retry with a fresh reservation") from exc
    reservations = []
    for raw_role in roles:
        role = str(raw_role).strip()
        if not re.fullmatch(r"[a-z][a-z0-9_-]{1,63}", role):
            raise EvidenceError(f"invalid review role: {role}")
        report_path = f"{session_relative}/reports/{role}.md"
        trace_path = f"{session_relative}/traces/{role}.trace.ndjson"
        if (project / report_path).exists() or (project / trace_path).exists():
            raise EvidenceError(f"reserved review artifact already exists for role {role}")
        reservations.append({
            "role": role,
            "dispatch_id": "d-" + secrets.token_hex(12),
            "report_path": report_path,
            "trace_path": trace_path,
        })
    session = {
        "schema_version": SCHEMA,
        "session_id": session_id,
        "project_run_nonce": state.get("run_nonce"),
        "phase_id": str(phase_id),
        "round": round_name,
        "requested_profile": profile,
        "attempt_epoch": attempt_epoch,
        "host_backend": backend,
        "registered_at": utc_now(),
        "reviewed_inputs": inputs,
        "reservations": reservations,
    }
    session_path = session_dir / "session.json"
    write_json_exclusive(session_path, session)
    reservation_sha = sha256_file(session_path)
    event = {
        "event": SESSION_EVENT,
        "recorded_at": utc_now(),
        "phase_id": str(phase_id),
        "round": round_name,
        "session_id": session_id,
        "reservation_sha256": reservation_sha,
        "project_run_nonce": state.get("run_nonce"),
        "attempt_epoch": session["attempt_epoch"],
    }
    state.setdefault("review_evidence_history", []).append(event)
    launches = []
    for reservation in reservations:
        launches.append({
            **reservation,
            "reviewed_inputs": inputs,
            "completion_argv_template": [
                "auto-research-state.sh", "review-complete", "<project>",
                str(phase_id), session_id, reservation["role"],
                "--driver-status", "succeeded",
                "<host-task-or-unavailable-option>",
                "<model-or-unavailable-option>",
            ],
        })
    return {
        "schema_version": SCHEMA,
        "session_id": session_id,
        "phase_id": str(phase_id),
        "round": round_name,
        "requested_profile": profile,
        "attempt_epoch": session["attempt_epoch"],
        "reservation_sha256": reservation_sha,
        "reviewed_inputs": inputs,
        "completion_contract": {
            "command": "auto-research-state.sh review-complete",
            "required_driver_status": "succeeded",
            "failure_action": "auto-research-state.sh review-abort",
            "identity_availability": ["reported", "unavailable"],
        },
        "launches": launches,
    }


def complete_role(
    project: Path,
    contract: dict,
    state: dict,
    phase_id: str,
    session_id: str,
    role: str,
    *,
    driver_status: str,
    host_task_id: str | None,
    host_task_unavailable: str | None,
    model_id: str | None,
    model_unavailable: str | None,
) -> dict:
    _, policy = phase_policy(contract, phase_id)
    _, root = evidence_root(project, policy)
    session_dir = root / session_id
    if session_dir.is_symlink():
        raise EvidenceError("review session directory must not be a symlink")
    session_path = session_dir / "session.json"
    if session_path.is_symlink():
        raise EvidenceError("review session record must not be a symlink")
    session = read_json(session_path, "review session")
    if session.get("schema_version") != SCHEMA:
        raise EvidenceError("review session schema mismatch")
    if (
        session.get("session_id") != session_id
        or session.get("phase_id") != str(phase_id)
        or session.get("project_run_nonce") != state.get("run_nonce")
    ):
        raise EvidenceError("review session phase or run nonce mismatch")
    current_epoch = int(state.get("review_attempt_epochs", {}).get(str(phase_id), 0))
    if session.get("attempt_epoch") != current_epoch:
        raise EvidenceError("review session attempt epoch is stale")
    if session.get("requested_profile") != state.get("review_assurance_profile", "normal"):
        raise EvidenceError("review session assurance profile is stale")
    if (session_dir / "aborted.json").exists():
        raise EvidenceError("review session is aborted")
    if _events(state, ABORT_EVENT, phase_id=phase_id, session_id=session_id):
        raise EvidenceError("review session has a registered abort event")
    registration = _events(state, SESSION_EVENT, phase_id=phase_id, session_id=session_id)
    if len(registration) != 1:
        raise EvidenceError("missing registered review session")
    if registration[0].get("reservation_sha256") != sha256_file(session_path):
        raise EvidenceError("registered review session digest mismatch")
    if (
        registration[0].get("round") != session.get("round")
        or registration[0].get("project_run_nonce") != state.get("run_nonce")
    ):
        raise EvidenceError("registered review session identity mismatch")
    if registration[0].get("attempt_epoch") != current_epoch:
        raise EvidenceError("registered review session attempt epoch mismatch")
    reservations = [item for item in session.get("reservations", []) if isinstance(item, dict) and item.get("role") == role]
    if len(reservations) != 1:
        raise EvidenceError(f"review role is not reserved exactly once: {role}")
    reservation = reservations[0]
    if driver_status != "succeeded":
        raise EvidenceError(
            "driver terminal status must be succeeded; abort failed, cancelled, "
            "timed-out, missing, or unknown work"
        )
    current_inputs = resolve_input_patterns(project, policy_round(policy, str(session.get("round"))).get("input_patterns"))
    if current_inputs != session.get("reviewed_inputs"):
        raise EvidenceError("reviewed input membership or digest changed after session registration")
    report_relative, report_path = normalize_relative(project, reservation.get("report_path"), "review report")
    trace_relative, trace_path = normalize_relative(project, reservation.get("trace_path"), "review trace")
    session_resolved = session_dir.resolve()
    for label, path in (("report", report_path), ("trace", trace_path)):
        try:
            path.resolve().relative_to(session_resolved)
        except ValueError as exc:
            raise EvidenceError(f"review {label} must remain inside its session") from exc
        if path.is_symlink():
            raise EvidenceError(f"review {label} must not be a symlink")
        if not path.is_file() or path.stat().st_size == 0:
            raise EvidenceError(f"review {label} must be a nonempty regular file")
    validate_trace_sidecar(trace_path)
    validate_report(report_path)
    if bool(host_task_id) == bool(host_task_unavailable):
        raise EvidenceError("provide exactly one of host task ID or host task unavailability reason")
    if bool(model_id) == bool(model_unavailable):
        raise EvidenceError("provide exactly one of model ID or model unavailability reason")
    report_digest = sha256_file(report_path)
    trace_digest = sha256_file(trace_path)
    normalized_host_task = reported(host_task_id, "host task ID") if host_task_id else unavailable(host_task_unavailable, "host task ID")
    normalized_model = reported(model_id, "model ID") if model_id else unavailable(model_unavailable, "model ID")
    host_task_fingerprint = (
        canonical_digest({"host_task_id": normalized_host_task["value"]})
        if normalized_host_task.get("status") == "reported" else None
    )
    completions_dir = session_dir / "completions"
    if completions_dir.is_symlink():
        raise EvidenceError("review completions directory must not be a symlink")
    if completions_dir.exists() and not completions_dir.is_dir():
        raise EvidenceError("review completions path must be a directory")
    try:
        completions_dir.resolve().relative_to(session_resolved)
    except ValueError as exc:
        raise EvidenceError("review completions directory must remain inside its session") from exc
    completions_dir.mkdir(parents=False, exist_ok=True)
    for prior_path in completions_dir.glob("*.json"):
        prior = read_json(prior_path, "prior review completion")
        if prior.get("report_path") == report_relative or prior.get("trace_path") == trace_relative:
            raise EvidenceError("review report or trace path is reused")
        if prior.get("report_sha256") == report_digest:
            raise EvidenceError("review report digest is reused")
        if prior.get("trace_sha256") == trace_digest:
            raise EvidenceError("review trace digest is reused")
        prior_task = prior.get("host_task_id", {})
        if (
            normalized_host_task.get("status") == "reported"
            and isinstance(prior_task, dict)
            and prior_task.get("status") == "reported"
            and prior_task.get("value") == normalized_host_task.get("value")
        ):
            raise EvidenceError("reported host task ID is reused")
    for prior in state.get("review_evidence_history", []):
        if (
            not isinstance(prior, dict)
            or prior.get("event") != COMPLETION_EVENT
            or str(prior.get("phase_id")) != str(phase_id)
            or prior.get("attempt_epoch") != current_epoch
        ):
            continue
        if prior.get("dispatch_id") == reservation.get("dispatch_id"):
            raise EvidenceError("review dispatch ID is reused across the attempt")
        if prior.get("report_sha256") == report_digest:
            raise EvidenceError("review report digest is reused across the attempt")
        if prior.get("trace_sha256") == trace_digest:
            raise EvidenceError("review trace digest is reused across the attempt")
        if host_task_fingerprint and prior.get("host_task_fingerprint") == host_task_fingerprint:
            raise EvidenceError("reported host task ID is reused across the attempt")
    completion = {
        "schema_version": SCHEMA,
        "session_id": session_id,
        "phase_id": str(phase_id),
        "round": session.get("round"),
        "attempt_epoch": current_epoch,
        "role": role,
        "dispatch_id": reservation.get("dispatch_id"),
        "driver_completion": {"status": driver_status, "observed_at": utc_now()},
        "host_backend": session.get("host_backend"),
        "host_task_id": normalized_host_task,
        "model_identity": normalized_model,
        "host_verification": {
            "adapter": {"status": "unsupported", "reason": "no trusted host adapter configured"},
            "claims": {claim: "unsupported" for claim in HOST_CLAIMS},
        },
        "report_path": report_relative,
        "report_sha256": report_digest,
        "trace_path": trace_relative,
        "trace_sha256": trace_digest,
        "reviewed_inputs": current_inputs,
    }
    completion_path = session_dir / "completions" / f"{role}.json"
    write_json_exclusive(completion_path, completion)
    completion_sha = sha256_file(completion_path)
    event = {
        "event": COMPLETION_EVENT,
        "recorded_at": utc_now(),
        "phase_id": str(phase_id),
        "round": session.get("round"),
        "attempt_epoch": current_epoch,
        "session_id": session_id,
        "role": role,
        "dispatch_id": reservation.get("dispatch_id"),
        "driver_completion": "succeeded",
        "completion_sha256": completion_sha,
        "report_sha256": completion["report_sha256"],
        "trace_sha256": completion["trace_sha256"],
        "host_task_fingerprint": host_task_fingerprint,
    }
    state.setdefault("review_evidence_history", []).append(event)
    return {"completion": completion, "completion_sha256": completion_sha}


def abort_session(project: Path, contract: dict, state: dict, phase_id: str, session_id: str, reason: str) -> dict:
    _, policy = phase_policy(contract, phase_id)
    _, root = evidence_root(project, policy)
    session_path = root / session_id / "session.json"
    if session_path.parent.is_symlink():
        raise EvidenceError("review session directory must not be a symlink")
    if session_path.is_symlink():
        raise EvidenceError("review session record must not be a symlink")
    session = read_json(session_path, "review session")
    if session.get("session_id") != session_id or session.get("phase_id") != str(phase_id):
        raise EvidenceError("cannot abort a review session with mismatched identity")
    registration = _events(state, SESSION_EVENT, phase_id=phase_id, session_id=session_id)
    if len(registration) != 1 or registration[0].get("reservation_sha256") != sha256_file(session_path):
        raise EvidenceError("cannot abort an unregistered review session")
    abort_events = _events(state, ABORT_EVENT, phase_id=phase_id, session_id=session_id)
    if len(abort_events) > 1:
        raise EvidenceError("review session has duplicate registered abort events")
    current_epoch = int(state.get("review_attempt_epochs", {}).get(str(phase_id), 0))
    if session.get("attempt_epoch") != current_epoch:
        raise EvidenceError("cannot abort a stale review session")
    if session.get("project_run_nonce") != state.get("run_nonce"):
        raise EvidenceError("cannot abort a review session from another project run")
    reason = str(reason or "").strip()
    if not reason:
        raise EvidenceError("abort-session requires a reason")
    abort_path = session_path.parent / "aborted.json"
    if abort_path.is_symlink():
        raise EvidenceError("review abort record must not be a symlink")
    if abort_path.exists():
        record = read_json(abort_path, "review abort record")
        if (
            record.get("schema_version") != SCHEMA
            or record.get("session_id") != session_id
            or record.get("phase_id") != str(phase_id)
            or record.get("reason") != reason
        ):
            raise EvidenceError("existing review abort record does not match this abort request")
        abort_sha = sha256_file(abort_path)
        if abort_events:
            if abort_events[0].get("abort_sha256") != abort_sha:
                raise EvidenceError("registered abort record digest mismatch")
            return record
    else:
        if abort_events:
            raise EvidenceError("registered abort event is missing its abort record")
        record = {
            "schema_version": SCHEMA,
            "session_id": session_id,
            "phase_id": str(phase_id),
            "reason": reason,
            "aborted_at": utc_now(),
        }
        write_json_exclusive(abort_path, record)
        abort_sha = sha256_file(abort_path)
    if abort_events:
        return record
    state.setdefault("review_evidence_history", []).append({
        "event": ABORT_EVENT,
        "recorded_at": utc_now(),
        "phase_id": str(phase_id),
        "session_id": session_id,
        "abort_sha256": abort_sha,
    })
    return record


def _summary_path(project: Path, policy: dict) -> Path:
    _, path = normalize_relative(project, policy.get("summary_output"), "review evidence summary output")
    return path


def nested_value(value, dotted: str):
    if dotted == ".":
        return value
    current = value
    for key in str(dotted or "").split("."):
        if not key or not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def validate_phase_evidence(project: Path, phase: dict, state: dict) -> tuple[dict | None, list[str]]:
    policy = phase.get("review_evidence_policy")
    if not isinstance(policy, dict):
        return None, []
    phase_id = str(phase.get("id"))
    issues: list[str] = []
    try:
        summary = read_json(_summary_path(project, policy), "phase summary")
    except EvidenceError as exc:
        return None, [str(exc)]
    selection = summary.get("review_evidence")
    if not isinstance(selection, dict):
        return None, ["missing registered review session: canonical phase output lacks review_evidence"]
    profile = str(state.get("review_assurance_profile", "normal"))
    if selection.get("profile") != profile:
        issues.append("review_evidence.profile does not match locked project state")
    selected_rounds = selection.get("rounds")
    declared_rounds = policy.get("rounds")
    if not isinstance(selected_rounds, dict) or not isinstance(declared_rounds, dict):
        return None, issues + ["review_evidence.rounds must be an object"]
    if set(selected_rounds) != set(declared_rounds):
        issues.append("review_evidence rounds do not exactly match phase policy")
    current_epoch = int(state.get("review_attempt_epochs", {}).get(phase_id, 0))
    if selection.get("attempt_epoch") != current_epoch:
        issues.append("review_evidence.attempt_epoch does not match project state")
    try:
        _, root = evidence_root(project, policy)
    except EvidenceError as exc:
        return None, issues + [str(exc)]
    seen_sessions = set()
    seen_dispatches = set()
    seen_host_tasks = set()
    seen_report_paths = set()
    seen_report_digests = set()
    computed_rounds = {}
    active_round_names = []
    for candidate_name, candidate_policy in declared_rounds.items():
        try:
            if round_is_active(project, candidate_policy):
                active_round_names.append(candidate_name)
        except EvidenceError:
            # The main validation loop emits the actionable condition error.
            pass
    terminal_active_round = active_round_names[-1] if active_round_names else None
    previous_active_round = None
    previous_round_completed = True
    previous_last_completion_index = None
    history = state.get("review_evidence_history", [])
    for round_name, round_policy in declared_rounds.items():
        selected = selected_rounds.get(round_name)
        if not isinstance(selected, dict):
            issues.append(f"round {round_name}: selection missing")
            continue
        try:
            active = round_is_active(project, round_policy)
        except EvidenceError as exc:
            issues.append(f"round {round_name}: {exc}")
            continue
        if not active:
            if selected != {"status": "not_applicable"}:
                issues.append(f"round {round_name}: inactive round must be exactly not_applicable")
            computed_rounds[round_name] = {"status": "not_applicable"}
            continue
        session_id = str(selected.get("session_id", "")).strip()
        if not session_id or session_id in seen_sessions:
            issues.append(f"round {round_name}: session_id missing or reused")
            continue
        seen_sessions.add(session_id)
        session_dir = root / session_id
        if session_dir.is_symlink():
            issues.append(f"round {round_name}: session directory must not be a symlink")
            continue
        try:
            session_path = session_dir / "session.json"
            if session_path.is_symlink():
                raise EvidenceError("review session record must not be a symlink")
            session = read_json(session_path, f"round {round_name} session")
        except EvidenceError as exc:
            issues.append(f"round {round_name}: {exc}")
            continue
        if (session_dir / "aborted.json").exists():
            issues.append(f"round {round_name}: selected session is aborted")
        abort_events = _events(state, ABORT_EVENT, phase_id=phase_id, session_id=session_id)
        if abort_events:
            issues.append(f"round {round_name}: selected session has a registered abort event")
            abort_path = session_dir / "aborted.json"
            if abort_path.is_file() and (
                len(abort_events) != 1
                or abort_events[0].get("abort_sha256") != sha256_file(abort_path)
            ):
                issues.append(f"round {round_name}: registered abort record digest mismatch")
        if session.get("schema_version") != SCHEMA or session.get("session_id") != session_id:
            issues.append(f"round {round_name}: session identity/schema mismatch")
        if session.get("phase_id") != phase_id or session.get("round") != round_name:
            issues.append(f"round {round_name}: phase/round mismatch")
        if session.get("project_run_nonce") != state.get("run_nonce"):
            issues.append(f"round {round_name}: run nonce mismatch")
        if session.get("requested_profile") != profile:
            issues.append(f"round {round_name}: session assurance profile mismatch")
        if session.get("attempt_epoch") != current_epoch:
            issues.append(f"round {round_name}: attempt epoch mismatch")
        registrations = _events(state, SESSION_EVENT, phase_id=phase_id, session_id=session_id)
        registration_indices = [
            index for index, event in enumerate(history)
            if isinstance(event, dict)
            and event.get("event") == SESSION_EVENT
            and str(event.get("phase_id")) == phase_id
            and str(event.get("session_id")) == session_id
        ]
        registration_index = registration_indices[0] if len(registration_indices) == 1 else None
        if len(registrations) != 1:
            issues.append(f"round {round_name}: missing registered review session")
        elif registrations[0].get("reservation_sha256") != sha256_file(session_path):
            issues.append(f"round {round_name}: registered session digest mismatch")
        elif registrations[0].get("round") != round_name:
            issues.append(f"round {round_name}: registered session round mismatch")
        if previous_active_round is not None:
            if not previous_round_completed:
                issues.append(
                    f"round {round_name}: registered before prior round "
                    f"{previous_active_round} was fully completed"
                )
            elif (
                registration_index is not None
                and previous_last_completion_index is not None
                and registration_index <= previous_last_completion_index
            ):
                issues.append(
                    f"round {round_name}: registration event precedes completion of prior round "
                    f"{previous_active_round}"
                )
        try:
            current_inputs = resolve_input_patterns(project, round_policy.get("input_patterns"))
        except EvidenceError as exc:
            issues.append(f"round {round_name}: {exc}")
            current_inputs = None
        if (
            round_name == terminal_active_round
            and current_inputs is not None
            and session.get("reviewed_inputs") != current_inputs
        ):
            issues.append(f"round {round_name}: reviewed input membership or digest changed")
        reservations = session.get("reservations")
        if not isinstance(reservations, list):
            issues.append(f"round {round_name}: reservations must be a list")
            continue
        by_role = {str(item.get("role")): item for item in reservations if isinstance(item, dict)}
        expected_roles = set(map(str, round_policy.get("roles", [])))
        optional_groups = round_policy.get("optional_role_groups", [])
        allowed_optional = {str(role) for group in optional_groups if isinstance(group, list) for role in group}
        actual_roles = set(by_role)
        extra_roles = actual_roles - expected_roles
        group_conflict = any(len(extra_roles & set(map(str, group))) > 1 for group in optional_groups if isinstance(group, list))
        if not expected_roles.issubset(actual_roles) or not extra_roles.issubset(allowed_optional) or group_conflict or len(by_role) != len(reservations):
            issues.append(f"round {round_name}: reserved roles do not exactly match policy")
        expected_roles = actual_roles
        completions_dir = session_dir / "completions"
        if completions_dir.is_symlink():
            issues.append(f"round {round_name}: review completions directory must not be a symlink")
            continue
        try:
            completions_dir.resolve().relative_to(session_dir.resolve())
        except ValueError:
            issues.append(f"round {round_name}: review completions directory must remain inside its session")
            continue
        completed_bindings = {}
        completion_event_indices = []
        for role in sorted(expected_roles):
            reservation = by_role.get(role)
            if not isinstance(reservation, dict):
                continue
            dispatch_id = str(reservation.get("dispatch_id", ""))
            if not dispatch_id or dispatch_id in seen_dispatches:
                issues.append(f"round {round_name}/{role}: dispatch_id missing or reused")
            seen_dispatches.add(dispatch_id)
            completion_path = session_dir / "completions" / f"{role}.json"
            try:
                if completion_path.is_symlink():
                    raise EvidenceError("review completion record must not be a symlink")
                completion = read_json(completion_path, f"round {round_name}/{role} completion")
            except EvidenceError as exc:
                issues.append(str(exc))
                continue
            if completion.get("dispatch_id") != dispatch_id or completion.get("role") != role:
                issues.append(f"round {round_name}/{role}: completion identity mismatch")
            completion_events = _events(state, COMPLETION_EVENT, phase_id=phase_id, session_id=session_id, role=role)
            role_completion_indices = [
                index for index, event in enumerate(history)
                if isinstance(event, dict)
                and event.get("event") == COMPLETION_EVENT
                and str(event.get("phase_id")) == phase_id
                and str(event.get("session_id")) == session_id
                and str(event.get("role")) == role
            ]
            if len(completion_events) != 1:
                issues.append(f"round {round_name}/{role}: missing registered role completion")
            else:
                if len(role_completion_indices) == 1:
                    completion_event_indices.append(role_completion_indices[0])
                    if registration_index is not None and role_completion_indices[0] <= registration_index:
                        issues.append(
                            f"round {round_name}/{role}: completion event precedes session registration"
                        )
                event = completion_events[0]
                expected_event = {
                    "completion_sha256": sha256_file(completion_path),
                    "report_sha256": completion.get("report_sha256"),
                    "trace_sha256": completion.get("trace_sha256"),
                    "dispatch_id": dispatch_id,
                    "driver_completion": "succeeded",
                    "attempt_epoch": current_epoch,
                }
                for key, value in expected_event.items():
                    if event.get(key) != value:
                        issues.append(f"round {round_name}/{role}: state completion {key} mismatch")
            if completion.get("driver_completion", {}).get("status") != "succeeded":
                issues.append(f"round {round_name}/{role}: driver completion is not succeeded")
            if completion.get("reviewed_inputs") != session.get("reviewed_inputs"):
                issues.append(f"round {round_name}/{role}: completion reviewed inputs mismatch")
            for kind in ("report", "trace"):
                relative = str(completion.get(f"{kind}_path", ""))
                expected_relative = str(reservation.get(f"{kind}_path", ""))
                if relative != expected_relative:
                    issues.append(f"round {round_name}/{role}: {kind} path mismatch")
                    continue
                try:
                    normalized, path = normalize_relative(project, relative, f"review {kind}")
                    path.resolve().relative_to(session_dir.resolve())
                    if not path.is_file():
                        raise EvidenceError(f"review {kind} must be a regular file")
                except (EvidenceError, ValueError) as exc:
                    issues.append(f"round {round_name}/{role}: invalid {kind} path: {exc}")
                    continue
                if completion.get(f"{kind}_sha256") != sha256_file(path):
                    issues.append(f"round {round_name}/{role}: {kind} digest mismatch")
                if kind == "report":
                    try:
                        validate_report(path)
                    except EvidenceError as exc:
                        issues.append(f"round {round_name}/{role}: {exc}")
                if kind == "trace":
                    try:
                        validate_trace_sidecar(path)
                    except EvidenceError as exc:
                        issues.append(f"round {round_name}/{role}: {exc}")
                if kind == "report":
                    if normalized in seen_report_paths:
                        issues.append(f"round {round_name}/{role}: report path reused")
                    if completion.get("report_sha256") in seen_report_digests:
                        issues.append(f"round {round_name}/{role}: report digest reused")
                    seen_report_paths.add(normalized)
                    seen_report_digests.add(completion.get("report_sha256"))
            host_task = completion.get("host_task_id")
            if not isinstance(host_task, dict) or host_task.get("status") not in {"reported", "unavailable"}:
                issues.append(f"round {round_name}/{role}: host_task_id availability state invalid")
            elif host_task.get("status") == "reported":
                value = host_task.get("value")
                try:
                    value = opaque_value(value, "host task ID")
                except EvidenceError as exc:
                    issues.append(f"round {round_name}/{role}: {exc}")
                    value = None
                if value is not None and value in seen_host_tasks:
                    issues.append(f"round {round_name}/{role}: reported host task ID reused")
                seen_host_tasks.add(value)
            model = completion.get("model_identity")
            if not isinstance(model, dict) or model.get("status") not in {"reported", "unavailable"}:
                issues.append(f"round {round_name}/{role}: model identity availability state invalid")
            completed_bindings[role] = completion
        binding_output = round_policy.get("binding_output", policy.get("summary_output"))
        try:
            _, binding_path = normalize_relative(project, binding_output, f"round {round_name} binding output")
            binding_document = read_json(binding_path, f"round {round_name} binding output")
        except EvidenceError as exc:
            issues.append(f"round {round_name}: {exc}")
            binding_document = None
        role_field = str(round_policy.get("role_field", "role"))
        report_path_field = str(round_policy.get("report_path_field", "report_path"))
        task_id_field = str(round_policy.get("task_id_field", "task_invocation_id"))
        records = None
        if binding_document is not None and round_policy.get("binding_collection"):
            records = nested_value(binding_document, str(round_policy.get("binding_collection")))
            if not isinstance(records, list):
                issues.append(f"round {round_name}: binding collection must be a list")
                records = []
        elif binding_document is not None and round_policy.get("binding_object"):
            record = nested_value(binding_document, str(round_policy.get("binding_object")))
            if not isinstance(record, dict):
                issues.append(f"round {round_name}: binding object must be an object")
                records = []
            else:
                records = [record]
        if records is None:
            issues.append(f"round {round_name}: policy lacks a semantic report binding")
            records = []
        semantic_by_role = {
            str(record.get(role_field, "")): record
            for record in records if isinstance(record, dict)
        }
        if set(semantic_by_role) != set(completed_bindings) or len(semantic_by_role) != len(records):
            issues.append(f"round {round_name}: semantic reviewer roles do not match completed evidence roles")
        for role, completion in completed_bindings.items():
            semantic = semantic_by_role.get(role)
            if not isinstance(semantic, dict):
                continue
            if semantic.get(report_path_field) != completion.get("report_path"):
                issues.append(f"round {round_name}/{role}: semantic {report_path_field} is not evidence-bound")
            declared_task = str(semantic.get(task_id_field, "")).strip()
            host_task = completion.get("host_task_id", {})
            allowed_tasks = {str(completion.get("dispatch_id", ""))}
            if isinstance(host_task, dict) and host_task.get("status") == "reported":
                allowed_tasks.add(str(host_task.get("value", "")))
            if declared_task not in allowed_tasks:
                issues.append(f"round {round_name}/{role}: semantic {task_id_field} is not evidence-bound")
        achieved = "process_recorded"
        if profile == "strict":
            required_claims = set(policy.get("strict_required_host_claims", HOST_CLAIMS))
            strict_ok = True
            for role in expected_roles:
                completion_path = session_dir / "completions" / f"{role}.json"
                if not completion_path.exists():
                    strict_ok = False
                    continue
                completion = read_json(completion_path, "strict completion")
                claims = completion.get("host_verification", {}).get("claims", {})
                if any(claims.get(claim) != "verified" for claim in required_claims):
                    strict_ok = False
            if strict_ok:
                achieved = "host_verified"
            else:
                issues.append(f"round {round_name}: strict profile requires host_verified claims")
        if selected.get("achieved_assurance") != achieved:
            issues.append(f"round {round_name}: achieved_assurance must equal verifier result {achieved}")
        computed_rounds[round_name] = {"session_id": session_id, "achieved_assurance": achieved}
        previous_active_round = round_name
        previous_round_completed = len(completion_event_indices) == len(expected_roles)
        previous_last_completion_index = (
            max(completion_event_indices) if completion_event_indices else None
        )
    result = {"profile": profile, "attempt_epoch": current_epoch, "rounds": computed_rounds}
    return result, issues


def review_status(project: Path, contract: dict, state: dict, phase_id: str) -> dict:
    """Describe registered, orphaned, active, completed, and aborted sessions."""
    phase, policy = phase_policy(contract, phase_id)
    _, root = evidence_root(project, policy)
    registrations = [
        event for event in state.get("review_evidence_history", [])
        if isinstance(event, dict)
        and event.get("event") == SESSION_EVENT
        and str(event.get("phase_id")) == str(phase_id)
    ]
    registered_ids = {str(event.get("session_id")) for event in registrations}
    disk_ids = {
        path.name for path in root.iterdir()
        if root.exists() and path.is_dir() and not path.is_symlink()
    } if root.exists() else set()
    current_epoch = int(state.get("review_attempt_epochs", {}).get(str(phase_id), 0))
    sessions = []
    for session_id in sorted(registered_ids | disk_ids):
        session_dir = root / session_id
        session_path = session_dir / "session.json"
        matching = [event for event in registrations if str(event.get("session_id")) == session_id]
        diagnostics = []
        session = None
        try:
            session = read_json(session_path, "review session")
        except EvidenceError as exc:
            diagnostics.append(str(exc))
        registered = len(matching) == 1
        if not registered:
            diagnostics.append("session is not registered exactly once in project state")
        elif session is not None and matching[0].get("reservation_sha256") != sha256_file(session_path):
            diagnostics.append("registered review session digest mismatch")
        abort_events = _events(state, ABORT_EVENT, phase_id=phase_id, session_id=session_id)
        abort_marker = session_dir / "aborted.json"
        aborted = bool(abort_events)
        abort_pending_publication = abort_marker.is_file() and not aborted
        if abort_marker.is_symlink():
            diagnostics.append("review abort record must not be a symlink")
        reservations = session.get("reservations", []) if isinstance(session, dict) else []
        roles = []
        for reservation in reservations if isinstance(reservations, list) else []:
            if not isinstance(reservation, dict):
                continue
            role = str(reservation.get("role", ""))
            completion_path = session_dir / "completions" / f"{role}.json"
            events = _events(
                state, COMPLETION_EVENT, phase_id=phase_id,
                session_id=session_id, role=role,
            )
            roles.append({
                "role": role,
                "completion_file_present": completion_path.is_file(),
                "registered_completion_events": len(events),
            })
        complete = bool(roles) and all(
            item["completion_file_present"] and item["registered_completion_events"] == 1
            for item in roles
        )
        stale = isinstance(session, dict) and session.get("attempt_epoch") != current_epoch
        if abort_pending_publication:
            lifecycle = "abort_pending_publication"
            action = "retry the same abort command to publish the state event"
        elif aborted:
            lifecycle = "aborted"
            action = "begin a fresh session for this round"
        elif not registered:
            lifecycle = "orphan_unregistered"
            action = "retire this directory and begin a fresh session"
        elif diagnostics:
            lifecycle = "invalid"
            action = "abort this session and begin a fresh session"
        elif stale:
            lifecycle = "stale"
            action = "begin a fresh session in the current attempt epoch"
        elif complete:
            lifecycle = "completed"
            action = "bind this session in the canonical phase output and verify"
        else:
            lifecycle = "active"
            action = "complete each pending reservation or abort the session"
        sessions.append({
            "session_id": session_id,
            "round": session.get("round") if isinstance(session, dict) else None,
            "attempt_epoch": session.get("attempt_epoch") if isinstance(session, dict) else None,
            "lifecycle": lifecycle,
            "roles": roles,
            "diagnostics": diagnostics,
            "next_action": action,
        })
    _, verification_issues = validate_phase_evidence(project, phase, state)
    return {
        "schema_version": SCHEMA,
        "phase_id": str(phase_id),
        "profile": state.get("review_assurance_profile", "normal"),
        "minimum_assurance": policy.get("minimum_assurance"),
        "attempt_epoch": current_epoch,
        "sessions": sessions,
        "verification_ready": not verification_issues,
        "verification_diagnostics": verification_issues,
    }


def _main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    verify = sub.add_parser("verify")
    verify.add_argument("--project", required=True)
    verify.add_argument("--phase", required=True)
    verify.add_argument("--contract", required=True)
    status = sub.add_parser("status")
    status.add_argument("--project", required=True)
    status.add_argument("--phase", required=True)
    status.add_argument("--contract", required=True)
    args = parser.parse_args()
    project = Path(args.project)
    contract = json.loads(Path(args.contract).read_text(encoding="utf-8"))
    state = read_json(project / ".auto-research" / "state.json", "project state")
    if args.command == "status":
        print(json.dumps(review_status(project, contract, state, args.phase), sort_keys=True))
        return 0
    phase, _ = phase_policy(contract, args.phase)
    result, issues = validate_phase_evidence(project, phase, state)
    print(json.dumps({"result": result, "issues": issues}, sort_keys=True))
    return 1 if issues else 0


if __name__ == "__main__":
    try:
        raise SystemExit(_main())
    except EvidenceError as exc:
        print(f"REVIEW_EVIDENCE_ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
