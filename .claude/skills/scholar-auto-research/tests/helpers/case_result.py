#!/usr/bin/env python3
"""Authoritative case records and closure snapshots for auto-research tests.

This module intentionally uses only the Python standard library.  The shell
harness is the public assertion interface; this helper supplies deterministic
digests, exact state-delta evaluation, and atomic exact-once records.
"""

from __future__ import annotations

import argparse
from collections import Counter
import datetime as dt
import fnmatch
import glob
import hashlib
import hmac
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import stat
import sys
from typing import Any, Iterable


SCHEMA_VERSION = "1.2.0"
CASE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SENTINEL_NAME = ".scholar-auto-research-owned-root.json"
RESULT_FIELDS = {
    "schema_version", "run_id", "run_nonce", "case_nonce", "case_id",
    "test_path", "runner_label", "suite_mode", "suite_order",
    "manifest_sha256", "source_generation_sha256", "production_entrypoint",
    "observed_exit", "observed_exact_diagnostic", "observed_exact_diagnostic_count",
    "stdout_sha256", "stderr_sha256", "transcript_verdict", "transcript_reason",
    "postcondition_verdict", "postcondition_evidence", "postcondition_evidence_sha256",
    "mutation_verdict", "state_delta_verdict", "terminal_status", "recorded_at",
    "record_mac_sha256",
}


class HarnessError(RuntimeError):
    pass


def fail(code: str, detail: str) -> "None":
    raise HarnessError(f"{code}: {detail}")


def canonical_json(value: Any) -> bytes:
    try:
        text = json.dumps(
            value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
            allow_nan=False,
        )
    except (TypeError, ValueError) as exc:
        fail("HARNESS_JSON_INVALID", f"noncanonical value: {exc}")
    return (text + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def strict_json_loads(payload: str, label: str) -> Any:
    def reject_duplicate(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                fail("HARNESS_JSON_INVALID", f"{label}: duplicate key {key!r}")
            result[key] = value
        return result

    def reject_constant(value: str) -> "None":
        fail("HARNESS_JSON_INVALID", f"{label}: non-finite number {value}")

    try:
        return json.loads(
            payload, object_pairs_hook=reject_duplicate, parse_constant=reject_constant,
        )
    except json.JSONDecodeError as exc:
        fail("HARNESS_JSON_INVALID", f"{label}: {exc}")


def require_regular_nonsymlink(path: Path, label: str) -> None:
    try:
        info = path.lstat()
    except OSError as exc:
        fail("HARNESS_FILE_INVALID", f"{label}: {path}: {exc}")
    if not stat.S_ISREG(info.st_mode):
        fail("HARNESS_FILE_INVALID", f"{label}: {path}: regular non-symlink file required")


def load_json(path: Path) -> Any:
    require_regular_nonsymlink(path, "json")
    try:
        return strict_json_loads(path.read_text(encoding="utf-8"), str(path))
    except (OSError, UnicodeDecodeError) as exc:
        fail("HARNESS_JSON_INVALID", f"{path}: {exc}")


def require_sha256(value: str, label: str) -> None:
    if not SHA256_RE.fullmatch(value):
        fail("HARNESS_BINDING_INVALID", f"{label} must be a lowercase sha256")


def safe_relative(value: str, label: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if (
        path.is_absolute() or ".." in path.parts or value in {"", "/"}
        or any(ord(char) < 32 for char in value)
    ):
        fail("HARNESS_PATH_UNSAFE", f"{label}={value!r}")
    return path


def contained_path(root: Path, relative: str, label: str) -> Path:
    rel = safe_relative(relative, label)
    root_real = root.resolve(strict=True)
    candidate = (root_real / Path(*rel.parts)).resolve(strict=True)
    try:
        candidate.relative_to(root_real)
    except ValueError:
        fail("HARNESS_PATH_ESCAPE", f"{label}={relative!r}")
    return candidate


def reviewed_source_projection(manifest: dict[str, Any]) -> dict[str, str]:
    value = manifest.get("reviewed_test_sources")
    if not isinstance(value, dict) or not value:
        fail("HARNESS_REVIEWED_SOURCE_SCHEMA", "reviewed_test_sources must be a nonempty object")
    cases = manifest.get("cases")
    declared_paths = {
        case.get("path") for case in cases.values() if isinstance(case, dict)
    } if isinstance(cases, dict) else set()
    projection: dict[str, str] = {}
    for raw_path, digest in value.items():
        if not isinstance(raw_path, str):
            fail("HARNESS_REVIEWED_SOURCE_SCHEMA", "reviewed source path must be a string")
        relative = safe_relative(raw_path, "reviewed_test_sources path")
        canonical = relative.as_posix()
        if canonical != raw_path or any(part in {"", "."} for part in relative.parts):
            fail("HARNESS_REVIEWED_SOURCE_PATH", raw_path)
        if raw_path not in declared_paths:
            fail("HARNESS_REVIEWED_SOURCE_UNDECLARED", raw_path)
        if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            fail("HARNESS_REVIEWED_SOURCE_DIGEST", raw_path)
        projection[raw_path] = digest
    return dict(sorted(projection.items()))


def reviewed_source_projection_digest(manifest: dict[str, Any]) -> str:
    return sha256_bytes(canonical_json(reviewed_source_projection(manifest)))


def hash_reviewed_source(source_root: Path, relative: str) -> str:
    """Hash one reviewed source from a stable no-follow descriptor."""
    rel = safe_relative(relative, "reviewed source")
    root = source_root.resolve(strict=True)
    current = root
    for part in rel.parts[:-1]:
        current = current / part
        try:
            info = current.lstat()
        except OSError as exc:
            fail("HARNESS_REVIEWED_SOURCE_FILE", f"{relative}: {exc}")
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            fail("HARNESS_REVIEWED_SOURCE_FILE", f"{relative}: non-symlink directory required")
    path = root / Path(*rel.parts)
    try:
        leaf = path.lstat()
    except OSError as exc:
        fail("HARNESS_REVIEWED_SOURCE_FILE", f"{relative}: {exc}")
    if stat.S_ISLNK(leaf.st_mode) or not stat.S_ISREG(leaf.st_mode):
        fail("HARNESS_REVIEWED_SOURCE_FILE", f"{relative}: regular non-symlink file required")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        fail("HARNESS_REVIEWED_SOURCE_FILE", f"{relative}: {exc}")
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            fail("HARNESS_REVIEWED_SOURCE_FILE", f"{relative}: regular file required")
        digest = hashlib.sha256()
        while True:
            block = os.read(descriptor, 1024 * 1024)
            if not block:
                break
            digest.update(block)
        after = os.fstat(descriptor)
        if (before.st_dev, before.st_ino, before.st_size) != (
            after.st_dev, after.st_ino, after.st_size,
        ):
            fail("HARNESS_REVIEWED_SOURCE_RACE", relative)
        try:
            pathname = path.lstat()
        except OSError as exc:
            fail("HARNESS_REVIEWED_SOURCE_RACE", f"{relative}: {exc}")
        if (
            not stat.S_ISREG(pathname.st_mode)
            or (pathname.st_dev, pathname.st_ino) != (after.st_dev, after.st_ino)
        ):
            fail("HARNESS_REVIEWED_SOURCE_RACE", relative)
        current = root
        for part in rel.parts[:-1]:
            current = current / part
            info = current.lstat()
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
                fail("HARNESS_REVIEWED_SOURCE_RACE", relative)
        return digest.hexdigest()
    except OSError as exc:
        fail("HARNESS_REVIEWED_SOURCE_FILE", f"{relative}: {exc}")
    finally:
        os.close(descriptor)


def validate_reviewed_sources(source_root: Path, manifest: dict[str, Any]) -> str:
    projection = reviewed_source_projection(manifest)
    for relative, expected in projection.items():
        observed = hash_reviewed_source(source_root, relative)
        if not secrets.compare_digest(observed, expected):
            fail("HARNESS_REVIEWED_SOURCE_BINDING", relative)
    return sha256_bytes(canonical_json(projection))


def read_manifest(path: Path) -> dict[str, Any]:
    data = load_json(path)
    if not isinstance(data, dict):
        fail("HARNESS_MANIFEST_SCHEMA", "manifest must be an object")
    if data.get("schema_version") != SCHEMA_VERSION:
        fail("HARNESS_MANIFEST_SCHEMA", f"expected schema_version={SCHEMA_VERSION}")
    if not isinstance(data.get("cases"), dict):
        fail("HARNESS_MANIFEST_SCHEMA", "cases must be an object")
    checkpoints = data.get("execution_checkpoints")
    if not isinstance(checkpoints, list) or any(
        not isinstance(item, str) or not CASE_ID_RE.fullmatch(item) for item in checkpoints
    ):
        fail("HARNESS_CHECKPOINT_SCHEMA", "execution_checkpoints must be an ordered name list")
    duplicate = next((item for item, count in Counter(checkpoints).items() if count > 1), None)
    if duplicate is not None:
        fail("HARNESS_CHECKPOINT_DUPLICATE", duplicate)
    reviewed_source_projection(data)
    for case_id, case in data["cases"].items():
        if not isinstance(case_id, str) or not isinstance(case, dict):
            fail("HARNESS_CASE_SCHEMA", repr(case_id))
        if case.get("polarity") == "structural" and any(
            field in case for field in ("execution_checkpoint", "postconditions", "transcript_policy")
        ):
            fail("HARNESS_STRUCTURAL_CASE_SEMANTIC", case_id)
        checkpoint = case.get("execution_checkpoint")
        if checkpoint is not None and checkpoint not in checkpoints:
            fail("HARNESS_CASE_CHECKPOINT_UNKNOWN", f"{case_id}: {checkpoint!r}")
        validate_postcondition_schema(case.get("postconditions"), case_id)
    return data


def read_case(manifest: dict[str, Any], case_id: str) -> dict[str, Any]:
    if not CASE_ID_RE.fullmatch(case_id):
        fail("HARNESS_CASE_ID_INVALID", case_id)
    case = manifest["cases"].get(case_id)
    if not isinstance(case, dict):
        fail("HARNESS_CASE_UNEXPECTED", case_id)
    required = {
        "path",
        "runner_label",
        "production_entrypoint",
        "polarity",
        "expected_exit",
        "diagnostic_match",
        "mutation_policy",
    }
    missing = sorted(required - set(case))
    if missing:
        fail("HARNESS_CASE_SCHEMA", f"{case_id}: missing {','.join(missing)}")
    for field in ("path", "runner_label", "production_entrypoint", "polarity"):
        if not isinstance(case.get(field), str) or not case[field]:
            fail("HARNESS_CASE_SCHEMA", f"{case_id}: {field}")
    expected_exit = case.get("expected_exit")
    if (
        not isinstance(expected_exit, dict)
        or set(expected_exit) != {"kind", "value"}
        or expected_exit.get("kind") != "exact"
        or type(expected_exit.get("value")) is not int
    ):
        fail("HARNESS_CASE_SCHEMA", f"{case_id}: expected_exit")
    diagnostic = case.get("diagnostic_match")
    if (
        not isinstance(diagnostic, dict)
        or set(diagnostic) != {"kind", "value"}
        or diagnostic.get("kind") not in {"exact", "none"}
        or not isinstance(diagnostic.get("value"), str)
        or (diagnostic.get("kind") == "none" and diagnostic.get("value") != "")
        or (diagnostic.get("kind") == "exact" and not diagnostic.get("value"))
    ):
        fail("HARNESS_CASE_SCHEMA", f"{case_id}: diagnostic_match")
    policy = case["mutation_policy"]
    if not isinstance(policy, dict) or not isinstance(policy.get("authoritative_closure"), list):
        fail("HARNESS_MUTATION_POLICY_MISSING", case_id)
    if policy.get("mode") not in {"unchanged", "declared_delta"}:
        fail("HARNESS_MUTATION_POLICY_INVALID", f"{case_id}: mode")
    checkpoint = case.get("execution_checkpoint")
    if checkpoint is not None:
        if not isinstance(checkpoint, str) or checkpoint not in manifest["execution_checkpoints"]:
            fail("HARNESS_CASE_CHECKPOINT_UNKNOWN", f"{case_id}: {checkpoint!r}")
    validate_postcondition_schema(case.get("postconditions"), case_id)
    return case


def read_capture(path: Path, label: str) -> tuple[bytes, list[str]]:
    try:
        payload = path.read_bytes()
        text = payload.decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        fail("HARNESS_TRANSCRIPT_CAPTURE_INVALID", f"{label}: {exc}")
    return payload, text.splitlines()


def transcript_expectations(case: dict[str, Any], case_id: str) -> dict[str, list[str]] | None:
    policy = case.get("transcript_policy")
    if policy is None:
        return None
    if not isinstance(policy, dict) or set(policy) != {"mode", "stdout", "stderr"}:
        fail("HARNESS_TRANSCRIPT_POLICY_SCHEMA", case_id)
    if policy.get("mode") != "exact_lines":
        fail("HARNESS_TRANSCRIPT_POLICY_SCHEMA", f"{case_id}: mode")
    for stream in ("stdout", "stderr"):
        lines = policy.get(stream)
        if not isinstance(lines, list) or any(
            not isinstance(line, str) or "\n" in line or "\r" in line for line in lines
        ):
            fail("HARNESS_TRANSCRIPT_POLICY_SCHEMA", f"{case_id}: {stream}")
    return {"stdout": policy["stdout"], "stderr": policy["stderr"]}


def snapshot_entry(snapshot_data: dict[str, Any], relative: str, label: str) -> dict[str, Any]:
    safe_relative(relative, label)
    entry = snapshot_data.get("entries", {}).get(relative)
    if not isinstance(entry, dict):
        fail("HARNESS_SNAPSHOT_PATH_MISSING", f"{label}={relative!r}")
    if entry.get("type") == "symlink":
        fail("HARNESS_SNAPSHOT_SYMLINK", f"{label}={relative!r}")
    return entry


def descriptor_digest_from_snapshot(snapshot_data: dict[str, Any], relative: str) -> str:
    entry = snapshot_entry(snapshot_data, relative, "descriptor path")
    if entry.get("type") == "file":
        digest = entry.get("sha256")
        if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            fail("HARNESS_DESCRIPTOR_DIGEST", relative)
        return digest
    if entry.get("type") != "directory":
        fail("HARNESS_DESCRIPTOR_PATH_TYPE", relative)
    prefix = relative.rstrip("/") + "/"
    digest = hashlib.sha256()
    descendants = sorted(
        (path, item) for path, item in snapshot_data.get("entries", {}).items()
        if path.startswith(prefix)
    )
    for path, item in descendants:
        child_relative = path[len(prefix):]
        if item.get("type") == "directory":
            digest.update(f"D\0{child_relative}\0".encode())
        elif item.get("type") == "file":
            child_digest = item.get("sha256")
            if not isinstance(child_digest, str) or not SHA256_RE.fullmatch(child_digest):
                fail("HARNESS_DESCRIPTOR_DIGEST", path)
            digest.update(f"F\0{child_relative}\0{child_digest}\0".encode())
        else:
            fail("HARNESS_DESCRIPTOR_PATH_TYPE", path)
    return digest.hexdigest()


def snapshot_pattern_map(
    snapshot_data: dict[str, Any], patterns: list[Any], *, required: bool,
) -> dict[str, str]:
    def production_glob_match(relative: str, pattern: str) -> bool:
        # Production calls glob.glob(path) without recursive=True.  Match each
        # path segment independently: '*' and '**' are therefore both a
        # single-segment wildcard, and hidden segments require a dot-leading
        # pattern segment under glob's default include_hidden=False behavior.
        path_parts = PurePosixPath(relative).parts
        pattern_parts = PurePosixPath(pattern).parts
        if len(path_parts) != len(pattern_parts):
            return False
        for path_part, pattern_part in zip(path_parts, pattern_parts):
            if path_part.startswith(".") and not pattern_part.startswith("."):
                return False
            if not fnmatch.fnmatchcase(path_part, pattern_part):
                return False
        return True

    result: dict[str, str] = {}
    paths = sorted(snapshot_data.get("entries", {}))
    for raw_pattern in patterns:
        if not isinstance(raw_pattern, str):
            fail("HARNESS_DESCRIPTOR_CONTRACT", "descriptor pattern must be a string")
        safe_relative(raw_pattern, "descriptor pattern")
        matches = [
            path for path in paths if production_glob_match(path, raw_pattern)
        ]
        if required and not matches:
            fail("HARNESS_DESCRIPTOR_REQUIRED_OUTPUT_MISSING", raw_pattern)
        for relative in matches:
            result[relative] = descriptor_digest_from_snapshot(snapshot_data, relative)
    return dict(sorted(result.items()))


def expected_descriptor(
    source_root: Path, project_root: Path, after_snapshot: dict[str, Any], phase_id: str,
) -> dict[str, Any]:
    source_root = source_root.resolve(strict=True)
    project_root = project_root.resolve(strict=True)
    if after_snapshot.get("project_root") != str(project_root):
        fail("HARNESS_SNAPSHOT_BINDING", "descriptor project root differs from after snapshot")
    contract_path = contained_path(source_root, "references/phase-contract.json", "phase contract")
    contract = load_json(contract_path)
    phases = contract.get("phases") if isinstance(contract, dict) else None
    if not isinstance(phases, list):
        fail("HARNESS_DESCRIPTOR_CONTRACT", "phases")
    phase = next((item for item in phases if isinstance(item, dict) and str(item.get("id")) == phase_id), None)
    if phase is None:
        fail("HARNESS_DESCRIPTOR_PHASE", phase_id)
    outputs = phase.get("required_outputs", [])
    inputs = phase.get("required_inputs", [])
    if not isinstance(outputs, list) or not isinstance(inputs, list):
        fail("HARNESS_DESCRIPTOR_CONTRACT", phase_id)
    return {
        "schema_version": "scholar-auto-research-verification-descriptor/v1",
        "phase_id": phase_id,
        "verdict": "PASS",
        "contract_sha256": sha256_file(contract_path),
        "required_outputs": snapshot_pattern_map(after_snapshot, outputs, required=True),
        "required_inputs": snapshot_pattern_map(after_snapshot, inputs, required=False),
    }


def typed_transcript_expectations(
    case: dict[str, Any], case_id: str, source_root: Path, project_root: Path,
    after_snapshot: dict[str, Any],
) -> dict[str, list[str]] | None:
    policy = case.get("transcript_policy")
    if policy is None:
        return None
    if not isinstance(policy, dict) or set(policy) != {"mode", "stdout", "stderr"}:
        fail("HARNESS_TRANSCRIPT_POLICY_SCHEMA", case_id)
    if policy.get("mode") == "exact_lines":
        return transcript_expectations(case, case_id)
    if policy.get("mode") != "typed_lines":
        fail("HARNESS_TRANSCRIPT_POLICY_SCHEMA", f"{case_id}: mode")
    expected: dict[str, list[str]] = {"stdout": [], "stderr": []}
    dynamic_count = 0
    for stream in ("stdout", "stderr"):
        items = policy.get(stream)
        if not isinstance(items, list):
            fail("HARNESS_TRANSCRIPT_POLICY_SCHEMA", f"{case_id}: {stream}")
        for item in items:
            if not isinstance(item, dict):
                fail("HARNESS_TRANSCRIPT_ITEM_SCHEMA", f"{case_id}: {stream}")
            kind = item.get("kind")
            if kind == "exact" and set(item) == {"kind", "value"}:
                value = item.get("value")
                if (
                    not isinstance(value, str) or "\n" in value or "\r" in value
                    or value.startswith("VERIFICATION_DESCRIPTOR_JSON=")
                ):
                    fail("HARNESS_TRANSCRIPT_ITEM_SCHEMA", f"{case_id}: exact")
                expected[stream].append(value)
            elif kind == "owned_project_path" and set(item) == {"kind", "prefix", "suffix"}:
                prefix, suffix = item.get("prefix"), item.get("suffix")
                if not isinstance(prefix, str) or "\n" in prefix or "\r" in prefix or not isinstance(suffix, str):
                    fail("HARNESS_TRANSCRIPT_ITEM_SCHEMA", f"{case_id}: owned_project_path")
                safe_relative(suffix, "owned project suffix")
                dynamic_count += 1
                expected[stream].append(f"{prefix}{project_root.resolve(strict=True)}/{suffix}")
            elif kind == "verification_descriptor" and set(item) == {
                "kind", "phase_id", "required_output_path",
            }:
                phase_id, required_output = item.get("phase_id"), item.get("required_output_path")
                if not isinstance(phase_id, str) or not re.fullmatch(r"(?:0|[1-9][0-9]*)", phase_id):
                    fail("HARNESS_TRANSCRIPT_ITEM_SCHEMA", f"{case_id}: verification_descriptor phase")
                if not isinstance(required_output, str):
                    fail("HARNESS_TRANSCRIPT_ITEM_SCHEMA", f"{case_id}: verification_descriptor output")
                safe_relative(required_output, "verification descriptor required output")
                descriptor = expected_descriptor(source_root, project_root, after_snapshot, phase_id)
                if required_output not in descriptor["required_outputs"]:
                    fail("HARNESS_DESCRIPTOR_REQUIRED_OUTPUT_MISSING", required_output)
                dynamic_count += 1
                expected[stream].append(
                    "VERIFICATION_DESCRIPTOR_JSON="
                    + canonical_json(descriptor).decode().rstrip("\n")
                )
            else:
                fail("HARNESS_TRANSCRIPT_ITEM_SCHEMA", f"{case_id}: {kind!r}")
    if dynamic_count > 1:
        fail("HARNESS_TRANSCRIPT_DYNAMIC_COUNT", case_id)
    return expected


def transcript_mismatch(
    expected: dict[str, list[str]], actual: dict[str, list[str]],
) -> str | None:
    if actual == expected:
        return None
    expected_all = Counter(expected["stdout"] + expected["stderr"])
    actual_all = Counter(actual["stdout"] + actual["stderr"])
    if actual_all == expected_all:
        if Counter(actual["stdout"]) != Counter(expected["stdout"]):
            return "HARNESS_TRANSCRIPT_WRONG_STREAM"
        return "HARNESS_TRANSCRIPT_ORDER"
    if any(actual_all[line] > count for line, count in expected_all.items()):
        return "HARNESS_TRANSCRIPT_DUPLICATE"
    expected_count = sum(expected_all.values())
    actual_count = sum(actual_all.values())
    if actual_count < expected_count:
        return "HARNESS_TRANSCRIPT_MISSING"
    if actual_count > expected_count:
        return "HARNESS_TRANSCRIPT_EXTRA"
    return "HARNESS_TRANSCRIPT_MISMATCH"


def evaluate_transcript(
    case: dict[str, Any], case_id: str, stdout_path: Path, stderr_path: Path,
    source_root: Path, project_root: Path, after_path: Path,
) -> tuple[str, str | None, bytes, bytes]:
    stdout_payload, stdout_lines = read_capture(stdout_path, "stdout")
    stderr_payload, stderr_lines = read_capture(stderr_path, "stderr")
    after_snapshot = load_json(after_path)
    expected = typed_transcript_expectations(
        case, case_id, source_root, project_root, after_snapshot,
    )
    if expected is None:
        return "not_applicable", None, stdout_payload, stderr_payload
    actual = {"stdout": stdout_lines, "stderr": stderr_lines}
    if case.get("transcript_policy", {}).get("mode") == "typed_lines":
        expected_descriptors = [
            line for stream in ("stdout", "stderr") for line in expected[stream]
            if line.startswith("VERIFICATION_DESCRIPTOR_JSON=")
        ]
        normalized_actual: dict[str, list[str]] = {"stdout": [], "stderr": []}
        for stream in ("stdout", "stderr"):
            for line in actual[stream]:
                if not line.startswith("VERIFICATION_DESCRIPTOR_JSON="):
                    normalized_actual[stream].append(line)
                    continue
                if len(expected_descriptors) != 1:
                    return "FAIL", "HARNESS_TRANSCRIPT_DESCRIPTOR_UNDECLARED", stdout_payload, stderr_payload
                try:
                    observed_descriptor = strict_json_loads(
                        line.removeprefix("VERIFICATION_DESCRIPTOR_JSON="),
                        "verification descriptor",
                    )
                    required_descriptor = strict_json_loads(
                        expected_descriptors[0].removeprefix("VERIFICATION_DESCRIPTOR_JSON="),
                        "required verification descriptor",
                    )
                except HarnessError:
                    return "FAIL", "HARNESS_TRANSCRIPT_DESCRIPTOR_JSON", stdout_payload, stderr_payload
                if not isinstance(observed_descriptor, dict) or observed_descriptor != required_descriptor:
                    return "FAIL", "HARNESS_TRANSCRIPT_DESCRIPTOR_BINDING", stdout_payload, stderr_payload
                normalized_actual[stream].append(expected_descriptors[0])
        actual = normalized_actual
    reason = transcript_mismatch(expected, actual)
    return ("PASS" if reason is None else "FAIL"), reason, stdout_payload, stderr_payload


def inventory_tree(root: Path) -> list[dict[str, Any]]:
    root = root.resolve(strict=True)
    entries: list[dict[str, Any]] = []

    def visit(path: Path, rel: PurePosixPath) -> None:
        info = path.lstat()
        # Ignore only actual Python cache directories.  Symlinks and files
        # named __pycache__ remain authoritative inventory entries.
        if rel.name == "__pycache__" and stat.S_ISDIR(info.st_mode):
            return
        mode = stat.S_IMODE(info.st_mode)
        item: dict[str, Any] = {"path": rel.as_posix(), "mode": f"{mode:04o}"}
        if stat.S_ISLNK(info.st_mode):
            item.update(type="symlink", target=os.readlink(path))
        elif stat.S_ISDIR(info.st_mode):
            item["type"] = "directory"
        elif stat.S_ISREG(info.st_mode):
            item.update(type="file", sha256=sha256_file(path), size=info.st_size)
        else:
            fail("HARNESS_SOURCE_SPECIAL_FILE", rel.as_posix())
        entries.append(item)
        if item["type"] == "directory":
            for child in sorted(path.iterdir(), key=lambda p: os.fsencode(p.name)):
                child_rel = PurePosixPath(child.name) if rel == PurePosixPath(".") else rel / child.name
                visit(child, child_rel)

    for child in sorted(root.iterdir(), key=lambda p: os.fsencode(p.name)):
        visit(child, PurePosixPath(child.name))
    return entries


def source_digest(root: Path) -> str:
    return sha256_bytes(canonical_json({"schema_version": SCHEMA_VERSION, "entries": inventory_tree(root)}))


def path_matches(path: str, patterns: Iterable[str]) -> bool:
    pure = PurePosixPath(path)
    for pattern in patterns:
        safe_relative(pattern.split("#", 1)[0], "ephemeral path")
        if fnmatch.fnmatchcase(path, pattern) or pure.match(pattern):
            return True
    return False


def expand_closure(root: Path, declarations: list[str], ephemeral: list[str]) -> dict[str, dict[str, Any]]:
    root = root.resolve(strict=True)
    found: dict[str, dict[str, Any]] = {}
    for declaration in declarations:
        rel = safe_relative(declaration, "authoritative closure")
        pattern = str(root / Path(*rel.parts))
        matches = sorted(glob.glob(pattern, recursive=True))
        if not matches and not glob.has_magic(declaration):
            relative = rel.as_posix()
            if not path_matches(relative, ephemeral):
                found[relative] = {"path": relative, "type": "missing"}
            continue
        for match in matches:
            start = Path(match)
            candidates = [start]
            if start.is_dir() and not start.is_symlink():
                candidates.extend(sorted(start.rglob("*"), key=lambda p: os.fsencode(p.as_posix())))
            for candidate in candidates:
                relative = candidate.relative_to(root).as_posix()
                if path_matches(relative, ephemeral):
                    continue
                info = candidate.lstat()
                item: dict[str, Any] = {
                    "path": relative,
                    "mode": f"{stat.S_IMODE(info.st_mode):04o}",
                }
                if stat.S_ISLNK(info.st_mode):
                    item.update(type="symlink", target=os.readlink(candidate))
                elif stat.S_ISDIR(info.st_mode):
                    item["type"] = "directory"
                elif stat.S_ISREG(info.st_mode):
                    item.update(type="file", sha256=sha256_file(candidate), size=info.st_size)
                    if candidate.suffix == ".json":
                        try:
                            item["json"] = strict_json_loads(
                                candidate.read_text(encoding="utf-8"), str(candidate),
                            )
                        except (UnicodeDecodeError, HarnessError):
                            pass
                else:
                    item["type"] = "special"
                found[relative] = item
    return found


def snapshot(manifest_path: Path, case_id: str, project_root: Path) -> dict[str, Any]:
    manifest = read_manifest(manifest_path)
    case = read_case(manifest, case_id)
    policy = case["mutation_policy"]
    declarations = policy["authoritative_closure"]
    ephemeral = policy.get("ephemeral", [])
    if not declarations:
        fail("HARNESS_CLOSURE_EMPTY", case_id)
    if not isinstance(ephemeral, list):
        fail("HARNESS_MUTATION_POLICY_INVALID", f"{case_id}: ephemeral")
    return {
        "schema_version": SCHEMA_VERSION,
        "case_id": case_id,
        "project_root": str(project_root.resolve(strict=True)),
        "entries": expand_closure(project_root, declarations, ephemeral),
    }


def json_pointer_escape(value: str) -> str:
    return value.replace("~", "~0").replace("/", "~1")


def json_leaf_map(value: Any, pointer: str = "") -> dict[str, Any]:
    if isinstance(value, dict):
        if not value:
            return {pointer or "/": {}}
        result: dict[str, Any] = {}
        for key in sorted(value):
            result.update(json_leaf_map(value[key], f"{pointer}/{json_pointer_escape(str(key))}"))
        return result
    if isinstance(value, list):
        if not value:
            return {pointer or "/": []}
        result = {}
        for index, item in enumerate(value):
            result.update(json_leaf_map(item, f"{pointer}/{index}"))
        return result
    return {pointer or "/": value}


POSTCONDITION_FIELDS = {
    "json_exact": {"kind", "path", "pointer", "value"},
    "json_absent": {"kind", "path", "pointer"},
    "json_sha256_equals_file": {"kind", "path", "pointer", "source_path"},
    "json_digest_equals_path": {"kind", "path", "pointer", "source_path", "source_type"},
    "json_iso8601_utc": {"kind", "path", "pointer"},
    "json_pointer_equal": {"kind", "path", "pointer", "other_path", "other_pointer"},
}


def validate_json_pointer(pointer: Any, label: str) -> str:
    if not isinstance(pointer, str) or (pointer and not pointer.startswith("/")):
        fail("HARNESS_POSTCONDITION_POINTER", label)
    for token in pointer.split("/")[1:] if pointer else []:
        if re.search(r"~(?![01])", token):
            fail("HARNESS_POSTCONDITION_POINTER", label)
    return pointer


def validate_postcondition_schema(value: Any, case_id: str) -> list[dict[str, Any]] | None:
    if value is None:
        return None
    if not isinstance(value, list):
        fail("HARNESS_POSTCONDITION_SCHEMA", case_id)
    result: list[dict[str, Any]] = []
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            fail("HARNESS_POSTCONDITION_SCHEMA", f"{case_id}:{index}")
        kind = item.get("kind")
        if kind not in POSTCONDITION_FIELDS or set(item) != POSTCONDITION_FIELDS[kind]:
            fail("HARNESS_POSTCONDITION_SCHEMA", f"{case_id}:{index}:{kind!r}")
        path = item.get("path")
        if not isinstance(path, str) or not path.endswith(".json"):
            fail("HARNESS_POSTCONDITION_PATH", f"{case_id}:{index}")
        safe_relative(path, "postcondition path")
        validate_json_pointer(item.get("pointer"), f"{case_id}:{index}:pointer")
        if kind in {"json_sha256_equals_file", "json_digest_equals_path"}:
            source_path = item.get("source_path")
            if not isinstance(source_path, str):
                fail("HARNESS_POSTCONDITION_PATH", f"{case_id}:{index}:source_path")
            safe_relative(source_path, "postcondition source path")
            if kind == "json_digest_equals_path" and item.get("source_type") not in {"file", "directory"}:
                fail("HARNESS_POSTCONDITION_SOURCE_TYPE", f"{case_id}:{index}")
        elif kind == "json_pointer_equal":
            other_path = item.get("other_path")
            if not isinstance(other_path, str) or not other_path.endswith(".json"):
                fail("HARNESS_POSTCONDITION_PATH", f"{case_id}:{index}:other_path")
            safe_relative(other_path, "postcondition other path")
            validate_json_pointer(item.get("other_pointer"), f"{case_id}:{index}:other_pointer")
        result.append(item)
    return result


_MISSING = object()


def pointer_value(document: Any, pointer: str) -> Any:
    if pointer == "":
        return document
    current = document
    for raw in pointer.split("/")[1:]:
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(current, dict):
            if token not in current:
                return _MISSING
            current = current[token]
        elif isinstance(current, list) and re.fullmatch(r"(?:0|[1-9][0-9]*)", token):
            index = int(token)
            if index >= len(current):
                return _MISSING
            current = current[index]
        else:
            return _MISSING
    return current


def json_identical(left: Any, right: Any) -> bool:
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return set(left) == set(right) and all(json_identical(left[key], right[key]) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(
            json_identical(left_item, right_item) for left_item, right_item in zip(left, right)
        )
    return left == right


def postcondition_document(snapshot_data: dict[str, Any], relative: str) -> Any:
    entry = snapshot_entry(snapshot_data, relative, "postcondition path")
    if entry.get("type") != "file" or "json" not in entry:
        fail("HARNESS_POSTCONDITION_JSON", relative)
    return entry["json"]


def evaluate_postconditions(
    case: dict[str, Any], case_id: str, project_root: Path, after_path: Path,
) -> tuple[str, list[dict[str, Any]], str]:
    declarations = validate_postcondition_schema(case.get("postconditions"), case_id)
    if declarations is None:
        evidence: list[dict[str, Any]] = []
        return "not_applicable", evidence, sha256_bytes(canonical_json(evidence))
    snapshot_data = load_json(after_path)
    if snapshot_data.get("case_id") != case_id:
        fail("HARNESS_SNAPSHOT_BINDING", f"{case_id}: postcondition case")
    if snapshot_data.get("project_root") != str(project_root.resolve(strict=True)):
        fail("HARNESS_SNAPSHOT_BINDING", f"{case_id}: postcondition project root")
    evidence = []
    for item in declarations:
        kind, relative, pointer = item["kind"], item["path"], item["pointer"]
        document = postcondition_document(snapshot_data, relative)
        observed = pointer_value(document, pointer)
        if kind == "json_exact":
            expected = item["value"]
            if observed is _MISSING or not json_identical(observed, expected):
                fail("HARNESS_POSTCONDITION_VALUE", f"{case_id}:{relative}#{pointer}")
            evidence.append({
                "kind": kind, "path": relative, "pointer": pointer,
                "expected": expected, "observed": observed,
            })
        elif kind == "json_absent":
            if observed is not _MISSING:
                fail("HARNESS_POSTCONDITION_PRESENT", f"{case_id}:{relative}#{pointer}")
            evidence.append({
                "kind": kind, "path": relative, "pointer": pointer,
                "expected": "absent", "observed": "absent",
            })
        elif kind == "json_sha256_equals_file":
            source_path = item["source_path"]
            source = snapshot_entry(snapshot_data, source_path, "postcondition source path")
            source_digest_value = source.get("sha256") if source.get("type") == "file" else None
            if (
                observed is _MISSING or not isinstance(observed, str)
                or not isinstance(source_digest_value, str)
                or not SHA256_RE.fullmatch(observed)
                or not SHA256_RE.fullmatch(source_digest_value)
                or not secrets.compare_digest(observed, source_digest_value)
            ):
                fail("HARNESS_POSTCONDITION_DIGEST", f"{case_id}:{relative}#{pointer}")
            evidence.append({
                "kind": kind, "path": relative, "pointer": pointer,
                "source_path": source_path, "expected_sha256": source_digest_value,
                "observed": observed,
            })
        elif kind == "json_digest_equals_path":
            source_path = item["source_path"]
            source_type = item["source_type"]
            source = snapshot_entry(snapshot_data, source_path, "postcondition source path")
            if source.get("type") != source_type:
                fail("HARNESS_POSTCONDITION_SOURCE_TYPE", f"{case_id}:{source_path}")
            source_digest_value = descriptor_digest_from_snapshot(snapshot_data, source_path)
            if (
                observed is _MISSING or not isinstance(observed, str)
                or not SHA256_RE.fullmatch(observed)
                or not secrets.compare_digest(observed, source_digest_value)
            ):
                fail("HARNESS_POSTCONDITION_DIGEST", f"{case_id}:{relative}#{pointer}")
            evidence.append({
                "kind": kind, "path": relative, "pointer": pointer,
                "source_path": source_path, "source_type": source_type,
                "expected_sha256": source_digest_value, "observed": observed,
            })
        elif kind == "json_iso8601_utc":
            if not isinstance(observed, str) or re.search(r"(?:Z|\+00:00)$", observed) is None:
                fail("HARNESS_POSTCONDITION_UTC", f"{case_id}:{relative}#{pointer}")
            try:
                parsed = dt.datetime.fromisoformat(observed.replace("Z", "+00:00"))
            except ValueError:
                fail("HARNESS_POSTCONDITION_UTC", f"{case_id}:{relative}#{pointer}")
            if parsed.tzinfo is None or parsed.utcoffset() != dt.timedelta(0):
                fail("HARNESS_POSTCONDITION_UTC", f"{case_id}:{relative}#{pointer}")
            evidence.append({
                "kind": kind, "path": relative, "pointer": pointer,
                "expected": "explicit_utc_iso8601", "observed": observed,
            })
        elif kind == "json_pointer_equal":
            other_path, other_pointer = item["other_path"], item["other_pointer"]
            other = pointer_value(postcondition_document(snapshot_data, other_path), other_pointer)
            if observed is _MISSING or other is _MISSING or not json_identical(observed, other):
                fail("HARNESS_POSTCONDITION_EQUALITY", f"{case_id}:{relative}#{pointer}")
            evidence.append({
                "kind": kind, "path": relative, "pointer": pointer,
                "other_path": other_path, "other_pointer": other_pointer,
                "observed": observed, "other_observed": other,
            })
    evidence_payload = canonical_json(evidence)
    if str(project_root.resolve(strict=True)).encode() in evidence_payload:
        fail("HARNESS_POSTCONDITION_EVIDENCE_ABSOLUTE", case_id)
    return "PASS", evidence, sha256_bytes(evidence_payload)


def calculate_delta(before: dict[str, Any], after: dict[str, Any]) -> dict[str, list[str]]:
    if before.get("case_id") != after.get("case_id") or before.get("project_root") != after.get("project_root"):
        fail("HARNESS_SNAPSHOT_BINDING", "before/after snapshot mismatch")
    old = before["entries"]
    new = after["entries"]
    added = list(sorted(set(new) - set(old)))
    removed = list(sorted(set(old) - set(new)))
    changed: list[str] = []
    for path in sorted(set(old) & set(new)):
        if old[path] == new[path]:
            continue
        old_item, new_item = old[path], new[path]
        if old_item.get("type") == new_item.get("type") == "file" and "json" in old_item and "json" in new_item:
            old_leaves = json_leaf_map(old_item["json"])
            new_leaves = json_leaf_map(new_item["json"])
            json_added = sorted(set(new_leaves) - set(old_leaves))
            json_removed = sorted(set(old_leaves) - set(new_leaves))
            added.extend(f"{path}#{pointer}" for pointer in json_added)
            removed.extend(f"{path}#{pointer}" for pointer in json_removed)
            changed_pointers = sorted(
                pointer for pointer in set(old_leaves) & set(new_leaves)
                if old_leaves[pointer] != new_leaves[pointer]
            )
            if changed_pointers:
                changed.extend(f"{path}#{pointer}" for pointer in changed_pointers)
            elif old_item.get("sha256") != new_item.get("sha256") and not json_added and not json_removed:
                changed.append(path)
        else:
            changed.append(path)
    return {"added": sorted(added), "changed": sorted(changed), "removed": sorted(removed)}


def validate_pattern_list(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        fail("HARNESS_MUTATION_POLICY_INVALID", label)
    for item in value:
        safe_relative(item.split("#", 1)[0], label)
    return value


def evaluate_delta(manifest_path: Path, case_id: str, before_path: Path, after_path: Path) -> dict[str, Any]:
    manifest = read_manifest(manifest_path)
    case = read_case(manifest, case_id)
    before = load_json(before_path)
    after = load_json(after_path)
    delta = calculate_delta(before, after)
    policy = case["mutation_policy"]
    mode = policy["mode"]
    reasons: list[str] = []
    if mode == "unchanged":
        if any(delta.values()):
            reasons.append("unchanged policy observed authoritative delta")
    else:
        permitted = policy.get("permitted")
        if not isinstance(permitted, dict):
            fail("HARNESS_MUTATION_POLICY_INVALID", f"{case_id}: permitted")
        forbidden = validate_pattern_list(policy.get("forbidden", ["*"]), f"{case_id}: forbidden")
        for category in ("added", "changed", "removed"):
            expected = validate_pattern_list(permitted.get(category, []), f"{case_id}: permitted.{category}")
            observed = delta[category]
            unmatched = [item for item in observed if not path_matches(item, expected)]
            unmet = [pattern for pattern in expected if not any(path_matches(item, [pattern]) for item in observed)]
            prohibited = [
                item for item in observed
                if path_matches(item, forbidden) and not path_matches(item, expected)
            ]
            if unmatched:
                reasons.append(f"undeclared {category}: {','.join(unmatched)}")
            if unmet:
                reasons.append(f"missing declared {category}: {','.join(unmet)}")
            if prohibited:
                reasons.append(f"forbidden {category}: {','.join(prohibited)}")
    return {"verdict": "PASS" if not reasons else "FAIL", "delta": delta, "reasons": reasons}


def atomic_write_new(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(path, flags, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
    except Exception:
        try:
            path.unlink()
        except FileNotFoundError:
            pass
        raise


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def init_run(args: argparse.Namespace) -> str:
    result_dir = Path(args.result_dir)
    source_root = Path(args.source_root).resolve(strict=True)
    manifest_path = Path(args.manifest).resolve(strict=True)
    require_sha256(args.manifest_sha256, "manifest_sha256")
    require_sha256(args.source_generation_sha256, "source_generation_sha256")
    if sha256_file(manifest_path) != args.manifest_sha256:
        fail("HARNESS_MANIFEST_BINDING", "coordinator digest differs from manifest")
    if source_digest(source_root) != args.source_generation_sha256:
        fail("HARNESS_SOURCE_BINDING", "coordinator digest differs from source tree")
    manifest = read_manifest(manifest_path)
    reviewed_sources_sha256 = validate_reviewed_sources(source_root, manifest)
    try:
        result_dir.mkdir(mode=0o700, parents=False)
    except FileExistsError:
        fail("HARNESS_RESULTS_NOT_FRESH", str(result_dir))
    except FileNotFoundError:
        fail("HARNESS_RESULTS_PARENT_MISSING", str(result_dir.parent))
    result_real = result_dir.resolve(strict=True)
    try:
        result_real.relative_to(source_root)
    except ValueError:
        pass
    else:
        fail("HARNESS_RESULTS_INSIDE_SOURCE", str(result_real))
    capability = secrets.token_hex(32)
    context = {
        "schema_version": SCHEMA_VERSION,
        "run_id": args.run_id,
        "run_nonce": args.run_nonce,
        "suite_mode": args.suite_mode,
        "suite_order": args.suite_order,
        "manifest_path": str(manifest_path),
        "manifest_sha256": args.manifest_sha256,
        "source_root": str(source_root),
        "source_generation_sha256": args.source_generation_sha256,
        "reviewed_test_sources_sha256": reviewed_sources_sha256,
        "capability_sha256": sha256_bytes(capability.encode()),
    }
    atomic_write_new(result_real / ".run-context.json", canonical_json(context))
    fsync_directory(result_real)
    return capability


def read_context(result_dir: Path, capability: str) -> tuple[Path, dict[str, Any]]:
    result_dir = result_dir.resolve(strict=True)
    context = load_json(result_dir / ".run-context.json")
    expected_fields = {
        "schema_version", "run_id", "run_nonce", "suite_mode", "suite_order",
        "manifest_path", "manifest_sha256", "source_root",
        "source_generation_sha256", "reviewed_test_sources_sha256",
        "capability_sha256",
    }
    if not isinstance(context, dict) or set(context) != expected_fields:
        fail("HARNESS_CONTEXT_SCHEMA", str(result_dir))
    for field in expected_fields:
        if not isinstance(context.get(field), str) or not context[field]:
            fail("HARNESS_CONTEXT_SCHEMA", f"{result_dir}: {field}")
    for field in (
        "manifest_sha256", "source_generation_sha256",
        "reviewed_test_sources_sha256", "capability_sha256",
    ):
        if not SHA256_RE.fullmatch(context[field]):
            fail("HARNESS_CONTEXT_SCHEMA", f"{result_dir}: {field}")
    if context.get("schema_version") != SCHEMA_VERSION:
        fail("HARNESS_CONTEXT_SCHEMA", str(result_dir))
    if not secrets.compare_digest(context.get("capability_sha256", ""), sha256_bytes(capability.encode())):
        fail("HARNESS_DIRECT_RECORD_FORBIDDEN", "missing or invalid harness capability")
    return result_dir, context


def verify_context_bindings(context: dict[str, Any]) -> tuple[Path, Path, dict[str, Any]]:
    source_root = Path(context["source_root"]).resolve(strict=True)
    manifest_path = Path(context["manifest_path"]).resolve(strict=True)
    if sha256_file(manifest_path) != context["manifest_sha256"]:
        fail("HARNESS_MANIFEST_BINDING", "manifest changed after run initialization")
    if source_digest(source_root) != context["source_generation_sha256"]:
        fail("HARNESS_SOURCE_BINDING", "source tree changed after run initialization")
    manifest = read_manifest(manifest_path)
    observed_projection = validate_reviewed_sources(source_root, manifest)
    if not secrets.compare_digest(observed_projection, context["reviewed_test_sources_sha256"]):
        fail("HARNESS_REVIEWED_SOURCE_CONTEXT", "reviewed source projection changed")
    return source_root, manifest_path, manifest


def normalize_relative_actual(source_root: Path, actual: Path, label: str) -> str:
    resolved = actual.resolve(strict=True)
    try:
        return resolved.relative_to(source_root).as_posix()
    except ValueError:
        fail("HARNESS_PATH_ESCAPE", f"{label}={resolved}")


def check_case_binding(
    source_root: Path,
    manifest: dict[str, Any],
    case_id: str,
    test_path: Path,
    runner_label: str,
    polarity: str | None = None,
) -> dict[str, Any]:
    case = read_case(manifest, case_id)
    if case.get("polarity") == "structural":
        fail("HARNESS_STRUCTURAL_CASE_STATIC_ONLY", case_id)
    actual_test = normalize_relative_actual(source_root, test_path, "test_path")
    if case["path"] != actual_test:
        fail("HARNESS_TEST_PATH_BINDING", f"{case_id}: expected {case['path']}, observed {actual_test}")
    if case["runner_label"] != runner_label:
        fail("HARNESS_RUNNER_BINDING", f"{case_id}: expected {case['runner_label']}, observed {runner_label}")
    if polarity is not None and case["polarity"] != polarity:
        fail("HARNESS_POLARITY_BINDING", f"{case_id}: expected {case['polarity']}, invoked {polarity}")
    return case


MUTATION_CASE_RE = re.compile(
    r"^(?P<family>(?:l3\.[A-Za-z0-9_.-]+|f20\.mutation\.[A-Za-z0-9_.-]+))\."
    r"(?P<role>pristine_positive|pristine_negative|mutant_valid|mutant_kill)$"
)

MUTATION_TARGETS = {
    "l3.source_roles": "scripts/auto-research-verify.sh",
    "l3.design_continuity": "scripts/auto-research-verify.sh",
    "l3.publication_readiness": "scripts/auto-research-verify.sh",
    "l3.drafting_plan": "scripts/auto-research-verify.sh",
    "l3.self_critique": "scripts/auto-research-verify.sh",
    "l3.source_roles_callsite": "scripts/auto-research-verify.sh",
    "f20.mutation.bridge_obligation": "scripts/auto-research-verify.sh",
    "f20.mutation.paragraph_scope": "scripts/auto-research-verify.sh",
    "f20.mutation.raw_global_scope": "scripts/auto-research-verify.sh",
    "f20.mutation.whole_table_membership": "scripts/auto-research-verify.sh",
    "f20.mutation.unordered_token_bag": "scripts/auto-research-verify.sh",
    "f20.mutation.sign_preservation": "scripts/auto-research-verify.sh",
    "f20.mutation.display_comparison": "scripts/auto-research-verify.sh",
    "f20.mutation.phase14_partial": "scripts/auto-research-verify.sh",
    "f20.mutation.phase15_partial": "scripts/auto-research-verify.sh",
    "f20.mutation.manifest_masking": "scripts/auto-research-verify.sh",
    "f20.mutation.remove_complete_pending_transition": "scripts/auto-research-state.sh",
}


def validate_mutation_verdict(case_id: str, verdict: Any) -> dict[str, str] | None:
    if not isinstance(verdict, str):
        fail("HARNESS_RESULT_MUTATION", f"{case_id}: verdict type")
    match = MUTATION_CASE_RE.fullmatch(case_id)
    if match is None:
        # No current registered case uses the legacy bare PASS marker.  It is
        # therefore not accepted as evidence for an ordinary assertion.
        if verdict != "not_applicable":
            fail("HARNESS_RESULT_MUTATION", case_id)
        return None
    family, role = match.group("family"), match.group("role")
    target = MUTATION_TARGETS.get(family)
    if target is None:
        fail("HARNESS_RESULT_MUTATION", f"{case_id}: unknown family")
    operator = family.removeprefix("l3.").removeprefix("f20.mutation.")
    if role.startswith("pristine_"):
        expected_prefix = "pristine:"
        if not verdict.startswith(expected_prefix):
            fail("HARNESS_RESULT_MUTATION", case_id)
        pristine = verdict.removeprefix(expected_prefix)
        if not SHA256_RE.fullmatch(pristine):
            fail("HARNESS_RESULT_MUTATION", case_id)
        return {"family": family, "role": role, "pristine": pristine}
    expected_prefix = "valid_control:" if role == "mutant_valid" else "killed:"
    if not verdict.startswith(expected_prefix):
        fail("HARNESS_RESULT_MUTATION", case_id)
    payload = verdict.removeprefix(expected_prefix)
    binding_re = re.compile(
        rf"operator={re.escape(operator)},target_matches=1,"
        rf"changed={re.escape(target)},"
        r"before=(?P<before>[0-9a-f]{64}),after=(?P<after>[0-9a-f]{64})"
    )
    binding = binding_re.fullmatch(payload)
    if binding is None or binding.group("before") == binding.group("after"):
        fail("HARNESS_RESULT_MUTATION", case_id)
    return {
        "family": family, "role": role, "binding": payload,
        "before": binding.group("before"), "after": binding.group("after"),
    }


def validate_record_types(record: dict[str, Any], label: str) -> None:
    if set(record) != RESULT_FIELDS:
        fail("HARNESS_RECORD_SCHEMA", label)
    string_fields = {
        "schema_version", "run_id", "run_nonce", "case_nonce", "case_id",
        "test_path", "runner_label", "suite_mode", "suite_order",
        "manifest_sha256", "source_generation_sha256", "stdout_sha256",
        "stderr_sha256", "transcript_verdict", "postcondition_verdict",
        "postcondition_evidence_sha256", "mutation_verdict",
        "state_delta_verdict", "terminal_status", "recorded_at",
        "record_mac_sha256",
    }
    for field in string_fields:
        if not isinstance(record.get(field), str):
            fail("HARNESS_RECORD_SCHEMA", f"{label}: {field}")
    if type(record.get("observed_exit")) is not int:
        fail("HARNESS_RECORD_SCHEMA", f"{label}: observed_exit")
    if type(record.get("observed_exact_diagnostic_count")) is not int:
        fail("HARNESS_RECORD_SCHEMA", f"{label}: observed_exact_diagnostic_count")
    if record.get("observed_exact_diagnostic") is not None and not isinstance(
        record.get("observed_exact_diagnostic"), str,
    ):
        fail("HARNESS_RECORD_SCHEMA", f"{label}: observed_exact_diagnostic")
    if record.get("transcript_reason") is not None and not isinstance(record.get("transcript_reason"), str):
        fail("HARNESS_RECORD_SCHEMA", f"{label}: transcript_reason")
    if not isinstance(record.get("postcondition_evidence"), list):
        fail("HARNESS_RECORD_SCHEMA", f"{label}: postcondition_evidence")
    entrypoint = record.get("production_entrypoint")
    if not isinstance(entrypoint, dict) or set(entrypoint) != {"path", "resolved_path", "sha256"}:
        fail("HARNESS_RECORD_SCHEMA", f"{label}: production_entrypoint")
    if any(not isinstance(entrypoint.get(field), str) for field in entrypoint):
        fail("HARNESS_RECORD_SCHEMA", f"{label}: production_entrypoint")


def record_case(args: argparse.Namespace) -> Path:
    if os.environ.get("SCHOLAR_HARNESS_INTERNAL_CALL") != "1":
        fail("HARNESS_DIRECT_RECORD_FORBIDDEN", "recorder is callable only through harness assertions")
    result_dir, context = read_context(Path(args.result_dir), args.capability)
    source_root, manifest_path, manifest = verify_context_bindings(context)
    case = check_case_binding(source_root, manifest, args.case_id, Path(args.test_path), args.runner_label)
    entrypoint = contained_path(source_root, case["production_entrypoint"], "production_entrypoint")
    expected_exit = case["expected_exit"]
    if expected_exit.get("kind") != "exact" or type(expected_exit.get("value")) is not int:
        fail("HARNESS_CASE_SCHEMA", f"{args.case_id}: expected_exit")
    validate_mutation_verdict(args.case_id, args.mutation_verdict)
    if args.terminal_status not in {"PASS", "FAIL"} or args.state_delta_verdict not in {"PASS", "FAIL"}:
        fail("HARNESS_RECORD_SCHEMA", args.case_id)
    diagnostic = case["diagnostic_match"]
    diagnostic_ok = diagnostic.get("kind") == "none"
    if diagnostic.get("kind") == "exact":
        diagnostic_ok = (
            args.diagnostic_count == 1
            and args.observed_exact_diagnostic == diagnostic.get("value")
        )
    elif diagnostic.get("kind") != "none":
        fail("HARNESS_CASE_SCHEMA", f"{args.case_id}: diagnostic_match")
    project_root = Path(args.project_root).resolve(strict=True)
    after_path = Path(args.after).resolve(strict=True)
    transcript_verdict, transcript_reason, stdout_payload, stderr_payload = evaluate_transcript(
        case, args.case_id, Path(args.stdout_file), Path(args.stderr_file),
        source_root, project_root, after_path,
    )
    postcondition_verdict, postcondition_evidence, postcondition_evidence_sha256 = evaluate_postconditions(
        case, args.case_id, project_root, after_path,
    )
    if sha256_bytes(stdout_payload) != args.stdout_sha256 or sha256_bytes(stderr_payload) != args.stderr_sha256:
        fail("HARNESS_TRANSCRIPT_DIGEST_MISMATCH", args.case_id)
    assertion_ok = (
        args.observed_exit == expected_exit["value"]
        and diagnostic_ok
        and args.state_delta_verdict == "PASS"
        and transcript_verdict in {"PASS", "not_applicable"}
        and postcondition_verdict in {"PASS", "not_applicable"}
    )
    expected_status = "PASS" if assertion_ok else "FAIL"
    if args.terminal_status != expected_status:
        fail(
            "HARNESS_TERMINAL_STATUS_INVALID",
            f"{args.case_id}: expected {expected_status}, observed {args.terminal_status}",
        )
    record = {
        "schema_version": SCHEMA_VERSION,
        "run_id": context["run_id"],
        "run_nonce": context["run_nonce"],
        "case_nonce": secrets.token_hex(32),
        "case_id": args.case_id,
        "test_path": case["path"],
        "runner_label": case["runner_label"],
        "suite_mode": context["suite_mode"],
        "suite_order": context["suite_order"],
        "manifest_sha256": context["manifest_sha256"],
        "source_generation_sha256": context["source_generation_sha256"],
        "production_entrypoint": {
            "path": case["production_entrypoint"],
            "resolved_path": str(entrypoint),
            "sha256": sha256_file(entrypoint),
        },
        "observed_exit": args.observed_exit,
        "observed_exact_diagnostic": args.observed_exact_diagnostic or None,
        "observed_exact_diagnostic_count": args.diagnostic_count,
        "stdout_sha256": args.stdout_sha256,
        "stderr_sha256": args.stderr_sha256,
        "transcript_verdict": transcript_verdict,
        "transcript_reason": transcript_reason,
        "postcondition_verdict": postcondition_verdict,
        "postcondition_evidence": postcondition_evidence,
        "postcondition_evidence_sha256": postcondition_evidence_sha256,
        "mutation_verdict": args.mutation_verdict,
        "state_delta_verdict": args.state_delta_verdict,
        "terminal_status": args.terminal_status,
        "recorded_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    record["record_mac_sha256"] = hmac.new(
        args.capability.encode(), canonical_json(record), hashlib.sha256,
    ).hexdigest()
    final = result_dir / f"{args.case_id}.json"
    temp = result_dir / f".{args.case_id}.{secrets.token_hex(16)}.tmp"
    atomic_write_new(temp, canonical_json(record))
    try:
        os.link(temp, final)
        fsync_directory(result_dir)
    except FileExistsError:
        fail("HARNESS_DUPLICATE_CASE", args.case_id)
    finally:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass
    return final


def validate_results(args: argparse.Namespace) -> int:
    result_dir, context = read_context(Path(args.result_dir), args.capability)
    source_root, _, manifest = verify_context_bindings(context)
    if args.phase_through is not None and args.checkpoint is not None:
        fail("HARNESS_SELECTOR_AMBIGUOUS", "--phase-through and --checkpoint are mutually exclusive")
    phase_through: int | None = None
    checkpoint_index: int | None = None
    if args.phase_through is not None:
        if not isinstance(args.phase_through, str) or not re.fullmatch(r"(?:0|[1-9][0-9]*)", args.phase_through):
            fail("HARNESS_PHASE_THROUGH_INVALID", repr(args.phase_through))
        phase_through = int(args.phase_through)
        if phase_through > 20:
            fail("HARNESS_PHASE_THROUGH_INVALID", args.phase_through)
    if args.checkpoint is not None:
        if args.checkpoint not in manifest["execution_checkpoints"]:
            fail("HARNESS_CHECKPOINT_UNKNOWN", args.checkpoint)
        checkpoint_index = manifest["execution_checkpoints"].index(args.checkpoint)
    actual_test = normalize_relative_actual(source_root, Path(args.test_path), "test_path")
    if not isinstance(args.runner_label, str) or not args.runner_label:
        fail("HARNESS_RUNNER_BINDING", "runner label must be nonempty")
    expected_cases: set[str] = set()
    for case_id, case in manifest["cases"].items():
        if not isinstance(case, dict) or case.get("gating") is not True:
            continue
        if case.get("polarity") == "structural":
            continue
        if case.get("path") != actual_test or case.get("runner_label") != args.runner_label:
            continue
        phase_ids = case.get("phase_ids", [])
        if phase_ids:
            if not isinstance(phase_ids, list) or any(
                not isinstance(phase, str) or phase not in {str(i) for i in range(21)}
                for phase in phase_ids
            ):
                fail("HARNESS_CASE_SCHEMA", f"{case_id}: phase_ids")
        case_checkpoint = case.get("execution_checkpoint")
        if case_checkpoint is not None and case_checkpoint not in manifest["execution_checkpoints"]:
            fail("HARNESS_CASE_CHECKPOINT_UNKNOWN", f"{case_id}: {case_checkpoint!r}")
        if phase_through is not None:
            if case_checkpoint is not None:
                continue
            if any(int(phase) > phase_through for phase in phase_ids):
                continue
        elif checkpoint_index is not None and case_checkpoint is not None:
            if manifest["execution_checkpoints"].index(case_checkpoint) > checkpoint_index:
                continue
        expected_cases.add(case_id)
    if not expected_cases:
        selector = (
            f"phase-through={phase_through}" if phase_through is not None
            else f"checkpoint={args.checkpoint}" if args.checkpoint is not None
            else "all"
        )
        fail("HARNESS_EXPECTED_CASE_SET_EMPTY", f"{actual_test}:{args.runner_label}:{selector}")
    seen: set[str] = set()
    mutation_groups: dict[str, dict[str, dict[str, str]]] = {}
    for path in sorted(result_dir.glob("*.json")):
        if path.name == ".run-context.json":
            continue
        record = load_json(path)
        if not isinstance(record, dict):
            fail("HARNESS_RECORD_SCHEMA", path.name)
        supplied_mac = record.get("record_mac_sha256")
        unsigned_record = dict(record)
        unsigned_record.pop("record_mac_sha256", None)
        expected_mac = hmac.new(
            args.capability.encode(), canonical_json(unsigned_record), hashlib.sha256,
        ).hexdigest()
        if not isinstance(supplied_mac, str) or not secrets.compare_digest(supplied_mac, expected_mac):
            fail("HARNESS_RESULT_MAC", path.name)
        validate_record_types(record, path.name)
        case_id = record.get("case_id")
        if not isinstance(case_id, str) or case_id not in manifest["cases"]:
            fail("HARNESS_RESULT_UNEXPECTED", path.name)
        if case_id in seen:
            fail("HARNESS_DUPLICATE_CASE", case_id)
        seen.add(case_id)
        expected_name = f"{case_id}.json"
        if path.name != expected_name:
            fail("HARNESS_RESULT_FILENAME", path.name)
        for field in (
            "schema_version", "run_id", "run_nonce", "suite_mode", "suite_order",
            "manifest_sha256", "source_generation_sha256",
        ):
            expected = SCHEMA_VERSION if field == "schema_version" else context[field]
            if record.get(field) != expected:
                fail("HARNESS_RESULT_STALE", f"{case_id}: {field}")
        case = check_case_binding(
            source_root,
            manifest,
            case_id,
            Path(source_root / record.get("test_path", "__invalid__")),
            record.get("runner_label", ""),
        )
        entrypoint = contained_path(source_root, case["production_entrypoint"], "production_entrypoint")
        entry = record["production_entrypoint"]
        if entry.get("path") != case["production_entrypoint"] or entry.get("resolved_path") != str(entrypoint):
            fail("HARNESS_RESULT_ENTRYPOINT", case_id)
        if entry.get("sha256") != sha256_file(entrypoint):
            fail("HARNESS_RESULT_ENTRYPOINT", f"{case_id}: digest")
        expected_exit = case.get("expected_exit", {})
        if record.get("observed_exit") != expected_exit.get("value"):
            fail("HARNESS_RESULT_EXIT", case_id)
        diagnostic = case.get("diagnostic_match", {})
        if diagnostic.get("kind") == "exact":
            if (
                record.get("observed_exact_diagnostic") != diagnostic.get("value")
                or record.get("observed_exact_diagnostic_count") != 1
            ):
                fail("HARNESS_RESULT_DIAGNOSTIC", case_id)
        elif diagnostic.get("kind") == "none":
            if record.get("observed_exact_diagnostic") is not None or record.get("observed_exact_diagnostic_count") != 0:
                fail("HARNESS_RESULT_DIAGNOSTIC", case_id)
        else:
            fail("HARNESS_CASE_SCHEMA", f"{case_id}: diagnostic_match")
        required_transcript = "PASS" if case.get("transcript_policy") is not None else "not_applicable"
        if record.get("transcript_verdict") != required_transcript:
            fail("HARNESS_RESULT_TRANSCRIPT", case_id)
        if record.get("transcript_reason") is not None:
            fail("HARNESS_RESULT_TRANSCRIPT", f"{case_id}: reason")
        required_postcondition = "PASS" if case.get("postconditions") is not None else "not_applicable"
        if record.get("postcondition_verdict") != required_postcondition:
            fail("HARNESS_RESULT_POSTCONDITION", case_id)
        evidence = record.get("postcondition_evidence")
        if not isinstance(evidence, list):
            fail("HARNESS_RESULT_POSTCONDITION", f"{case_id}: evidence")
        if record.get("postcondition_evidence_sha256") != sha256_bytes(canonical_json(evidence)):
            fail("HARNESS_RESULT_POSTCONDITION_EVIDENCE", case_id)
        if record.get("state_delta_verdict") != "PASS":
            fail("HARNESS_RESULT_STATE_DELTA", case_id)
        mutation = validate_mutation_verdict(case_id, record.get("mutation_verdict"))
        if mutation is not None:
            mutation_groups.setdefault(mutation["family"], {})[mutation["role"]] = mutation
        if record.get("terminal_status") != "PASS":
            fail("HARNESS_RESULT_TERMINAL", case_id)
        for digest_field in ("stdout_sha256", "stderr_sha256"):
            if not isinstance(record.get(digest_field), str) or not SHA256_RE.fullmatch(record[digest_field]):
                fail("HARNESS_RECORD_SCHEMA", f"{case_id}: {digest_field}")
        if not isinstance(record.get("case_nonce"), str) or not SHA256_RE.fullmatch(record["case_nonce"]):
            fail("HARNESS_RECORD_SCHEMA", f"{case_id}: case_nonce")
        recorded_at_value = record["recorded_at"]
        if re.search(r"(?:Z|\+00:00)$", recorded_at_value) is None:
            fail("HARNESS_RECORD_SCHEMA", f"{case_id}: recorded_at")
        try:
            recorded_at = dt.datetime.fromisoformat(recorded_at_value.replace("Z", "+00:00"))
        except ValueError:
            fail("HARNESS_RECORD_SCHEMA", f"{case_id}: recorded_at")
        if recorded_at.tzinfo is None or recorded_at.utcoffset() != dt.timedelta(0):
            fail("HARNESS_RECORD_SCHEMA", f"{case_id}: recorded_at")
    for case_id in sorted(expected_cases - seen):
        fail("HARNESS_RESULT_MISSING", case_id)
    unexpected_for_binding = seen - expected_cases
    if unexpected_for_binding:
        fail("HARNESS_RESULT_OUTSIDE_EXPECTED_SET", sorted(unexpected_for_binding)[0])
    for family, roles in sorted(mutation_groups.items()):
        pristine_values = {
            item["pristine"] for role, item in roles.items() if role.startswith("pristine_")
        }
        bindings = {
            item["binding"] for role, item in roles.items() if role in {"mutant_valid", "mutant_kill"}
        }
        if len(pristine_values) != 1 or len(bindings) != 1:
            fail("HARNESS_RESULT_MUTATION", f"{family}: inconsistent family binding")
        pristine = next(iter(pristine_values))
        for role in ("mutant_valid", "mutant_kill"):
            item = roles.get(role)
            if item is None or item.get("before") != pristine:
                fail("HARNESS_RESULT_MUTATION", f"{family}: {role} baseline binding")
    return len(seen)


def check_run(args: argparse.Namespace) -> None:
    _, context = read_context(Path(args.result_dir), args.capability)
    verify_context_bindings(context)
    expected = {
        "run_id": args.run_id,
        "run_nonce": args.run_nonce,
        "suite_mode": args.suite_mode,
        "suite_order": args.suite_order,
        "manifest_sha256": args.manifest_sha256,
        "source_generation_sha256": args.source_generation_sha256,
    }
    for field, value in expected.items():
        if context.get(field) != value:
            fail("HARNESS_CONTEXT_BINDING", f"{field}: expected {value!r}, observed {context.get(field)!r}")


def prepare_owned_root(tmpdir: Path, prefix: str) -> tuple[Path, str, Path]:
    if not prefix or "/" in prefix or "\x00" in prefix or any(ord(char) < 32 for char in prefix):
        fail("HARNESS_TEMP_PREFIX_INVALID", repr(prefix))
    if any(ord(char) < 32 for char in str(tmpdir)):
        fail("HARNESS_TMPDIR_INVALID", repr(str(tmpdir)))
    try:
        tmpdir_real = tmpdir.resolve(strict=True)
    except FileNotFoundError:
        fail("HARNESS_TMPDIR_MISSING", str(tmpdir))
    if not tmpdir_real.is_dir():
        fail("HARNESS_TMPDIR_INVALID", str(tmpdir_real))
    if tmpdir_real == Path(tmpdir_real.anchor):
        fail("HARNESS_TMPDIR_UNSAFE", str(tmpdir_real))
    if not os.access(tmpdir_real, os.W_OK | os.X_OK):
        fail("HARNESS_TMPDIR_UNWRITABLE", str(tmpdir_real))
    nonce = secrets.token_hex(32)
    candidate = tmpdir_real / f"{prefix}.{nonce[:16]}"
    if candidate.exists() or candidate.is_symlink():
        fail("HARNESS_TEMP_COLLISION", str(candidate))
    return candidate, nonce, tmpdir_real


def write_owned_sentinel(root: Path, nonce: str, tmp_parent: Path | None = None) -> None:
    root_real = root.resolve(strict=True)
    parent_real = (tmp_parent or root_real.parent).resolve(strict=True)
    if root_real.parent != parent_real:
        fail("HARNESS_ROOT_CONTAINMENT", f"{root_real} is not an immediate child of {parent_real}")
    payload = {
        "schema_version": SCHEMA_VERSION,
        "root": str(root_real),
        "tmp_parent": str(parent_real),
        "nonce": nonce,
    }
    atomic_write_new(root_real / SENTINEL_NAME, canonical_json(payload))


def create_owned_root(root: Path, nonce: str, tmp_parent: Path) -> None:
    parent_real = tmp_parent.resolve(strict=True)
    root_parent = root.parent.resolve(strict=True)
    if parent_real != root_parent or parent_real == Path(parent_real.anchor):
        fail("HARNESS_ROOT_CONTAINMENT", str(root))
    try:
        root.mkdir(mode=0o700)
    except FileExistsError:
        fail("HARNESS_TEMP_COLLISION", str(root))
    write_owned_sentinel(root, nonce, parent_real)


def cleanup_owned_root(root: Path, nonce: str, tmp_parent: Path | None = None) -> None:
    root_real = root.resolve(strict=True)
    if root_real == Path(root_real.anchor):
        fail("HARNESS_CLEANUP_UNSAFE", str(root_real))
    parent_real = (tmp_parent or root_real.parent).resolve(strict=True)
    if parent_real == Path(parent_real.anchor) or root_real.parent != parent_real:
        fail("HARNESS_ROOT_CONTAINMENT", str(root_real))
    sentinel = root_real / SENTINEL_NAME
    data = load_json(sentinel)
    if data != {
        "schema_version": SCHEMA_VERSION,
        "root": str(root_real),
        "tmp_parent": str(parent_real),
        "nonce": nonce,
    }:
        fail("HARNESS_SENTINEL_MISMATCH", str(root_real))
    shutil.rmtree(root_real)


def logical_lines(text: str) -> list[tuple[int, str]]:
    result: list[tuple[int, str]] = []
    buffer = ""
    start = 1
    for number, line in enumerate(text.splitlines(), 1):
        if not buffer:
            start = number
        buffer += line
        if buffer.endswith("\\"):
            buffer = buffer[:-1] + " "
        else:
            result.append((start, buffer))
            buffer = ""
    if buffer:
        result.append((start, buffer))
    return result


def lint_files(manifest_path: Path, source_root: Path, paths: list[Path]) -> list[str]:
    manifest = read_manifest(manifest_path)
    source_root = source_root.resolve(strict=True)
    violations: list[str] = []
    registered = manifest["cases"]
    for path in paths:
        resolved = path.resolve(strict=True)
        relative = normalize_relative_actual(source_root, resolved, "lint_path")
        text = resolved.read_text(encoding="utf-8")
        for line_no, logical in logical_lines(text):
            if "HARNESS_LINT_NEGATIVE_CONTROL" in logical:
                continue
            stdout_null = bool(re.search(r"(?<![0-9])>\s*/dev/null", logical))
            stderr_null = bool(re.search(r"2>\s*/dev/null", logical))
            stderr_to_stdout = bool(re.search(r"2>\s*&1", logical))
            if re.search(r"auto-research-(?:verify|state)\.sh", logical) and (
                re.search(r"&>\s*/dev/null", logical)
                or (stdout_null and (stderr_null or stderr_to_stdout))
            ):
                violations.append(f"HARNESS_LINT_OUTPUT_DISCARD:{relative}:{line_no}")
            if resolved.name != "harness.sh" and re.search(r"case_result\.py[^\n]*\brecord\b", logical):
                violations.append(f"HARNESS_LINT_DIRECT_RECORD:{relative}:{line_no}")
            if re.search(r"(?:>|\btee\b)[^\n]*SCHOLAR_HARNESS_RESULTS_DIR", logical):
                violations.append(f"HARNESS_LINT_DIRECT_RESULT_WRITE:{relative}:{line_no}")
            if re.search(r"(?:ls\s+-t|find\s+(?:/tmp|\"?\$\{?TMPDIR))[\s\S]{0,240}(?:head\s+-1|sort\s+-r)", logical):
                violations.append(f"HARNESS_LINT_GLOBAL_LATEST:{relative}:{line_no}")
        if "mktemp" in text and "harness_make_temp_root" not in text and not re.search(r"\btrap\b[^\n]*\bEXIT\b", text):
            violations.append(f"HARNESS_LINT_UNTRAPPED_MKTEMP:{relative}:1")
        for match in re.finditer(r"(?:^|[;(&]\s*)expect_(?:pass|reject)\s+([^\s]+)", text, re.MULTILINE):
            token = match.group(1).strip("'\"")
            line = text.count("\n", 0, match.start()) + 1
            if not CASE_ID_RE.fullmatch(token):
                violations.append(f"HARNESS_LINT_DYNAMIC_CASE_ID:{relative}:{line}")
                continue
            case = registered.get(token)
            if not isinstance(case, dict) or not case.get("gating", False):
                violations.append(f"HARNESS_LINT_UNREGISTERED_CASE:{relative}:{line}:{token}")
            elif case.get("path") != relative:
                violations.append(f"HARNESS_LINT_CASE_PATH:{relative}:{line}:{token}")
    return violations


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)

    digest_file = commands.add_parser("digest-file")
    digest_file.add_argument("path")
    digest_source = commands.add_parser("source-digest")
    digest_source.add_argument("root")

    case_field = commands.add_parser("case-field")
    case_field.add_argument("--manifest", required=True)
    case_field.add_argument("--case-id", required=True)
    case_field.add_argument("--field", required=True)

    check = commands.add_parser("check-case")
    check.add_argument("--manifest", required=True)
    check.add_argument("--source-root", required=True)
    check.add_argument("--case-id", required=True)
    check.add_argument("--test-path", required=True)
    check.add_argument("--runner-label", required=True)
    check.add_argument("--polarity", choices=["positive", "negative", "structural"])

    init = commands.add_parser("init-run")
    for name in ("result-dir", "source-root", "manifest", "run-id", "run-nonce", "suite-mode", "suite-order", "manifest-sha256", "source-generation-sha256"):
        init.add_argument(f"--{name}", required=True)

    snap = commands.add_parser("snapshot")
    snap.add_argument("--manifest", required=True)
    snap.add_argument("--case-id", required=True)
    snap.add_argument("--project-root", required=True)
    snap.add_argument("--output", required=True)

    compare = commands.add_parser("compare")
    compare.add_argument("--manifest", required=True)
    compare.add_argument("--case-id", required=True)
    compare.add_argument("--before", required=True)
    compare.add_argument("--after", required=True)
    compare.add_argument("--output", required=True)

    record = commands.add_parser("record")
    for name in ("result-dir", "capability", "case-id", "test-path", "runner-label", "project-root", "after", "observed-exit", "observed-exact-diagnostic", "diagnostic-count", "stdout-file", "stderr-file", "stdout-sha256", "stderr-sha256", "mutation-verdict", "state-delta-verdict", "terminal-status"):
        record.add_argument(f"--{name}", required=True)

    transcript = commands.add_parser("validate-transcript")
    transcript.add_argument("--manifest", required=True)
    transcript.add_argument("--case-id", required=True)
    transcript.add_argument("--source-root", required=True)
    transcript.add_argument("--project-root", required=True)
    transcript.add_argument("--after", required=True)
    transcript.add_argument("--stdout-file", required=True)
    transcript.add_argument("--stderr-file", required=True)

    postconditions = commands.add_parser("validate-postconditions")
    postconditions.add_argument("--manifest", required=True)
    postconditions.add_argument("--case-id", required=True)
    postconditions.add_argument("--project-root", required=True)
    postconditions.add_argument("--after", required=True)

    validate = commands.add_parser("validate-results")
    validate.add_argument("--result-dir", required=True)
    validate.add_argument("--capability", required=True)
    validate.add_argument("--test-path", required=True)
    validate.add_argument("--runner-label", required=True)
    validate.add_argument("--phase-through")
    validate.add_argument("--checkpoint")

    check_run_parser = commands.add_parser("check-run")
    for name in ("result-dir", "capability", "run-id", "run-nonce", "suite-mode", "suite-order", "manifest-sha256", "source-generation-sha256"):
        check_run_parser.add_argument(f"--{name}", required=True)

    sentinel = commands.add_parser("write-sentinel")
    sentinel.add_argument("--root", required=True)
    sentinel.add_argument("--nonce", required=True)
    sentinel.add_argument("--tmp-parent")
    prepare = commands.add_parser("prepare-owned-root")
    prepare.add_argument("--tmpdir", required=True)
    prepare.add_argument("--prefix", required=True)
    create = commands.add_parser("create-owned-root")
    create.add_argument("--root", required=True)
    create.add_argument("--nonce", required=True)
    create.add_argument("--tmp-parent", required=True)
    cleanup = commands.add_parser("cleanup-owned-root")
    cleanup.add_argument("--root", required=True)
    cleanup.add_argument("--nonce", required=True)
    cleanup.add_argument("--tmp-parent")

    lint = commands.add_parser("lint")
    lint.add_argument("--manifest", required=True)
    lint.add_argument("--source-root", required=True)
    lint.add_argument("paths", nargs="+")
    return root


def nested_field(value: Any, field: str) -> Any:
    for part in field.split("."):
        if not isinstance(value, dict) or part not in value:
            fail("HARNESS_CASE_FIELD", field)
        value = value[part]
    return value


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "digest-file":
            print(sha256_file(Path(args.path)))
        elif args.command == "source-digest":
            print(source_digest(Path(args.root)))
        elif args.command == "case-field":
            case = read_case(read_manifest(Path(args.manifest)), args.case_id)
            value = nested_field(case, args.field)
            print(json.dumps(value) if not isinstance(value, str) else value)
        elif args.command == "check-case":
            check_case_binding(
                Path(args.source_root).resolve(strict=True),
                read_manifest(Path(args.manifest)),
                args.case_id,
                Path(args.test_path),
                args.runner_label,
                args.polarity,
            )
            print("HARNESS_CASE_BINDING=PASS")
        elif args.command == "init-run":
            print(init_run(args))
        elif args.command == "snapshot":
            atomic_write_new(Path(args.output), canonical_json(snapshot(Path(args.manifest), args.case_id, Path(args.project_root))))
        elif args.command == "compare":
            result = evaluate_delta(Path(args.manifest), args.case_id, Path(args.before), Path(args.after))
            atomic_write_new(Path(args.output), canonical_json(result))
            print(f"HARNESS_STATE_DELTA={result['verdict']}")
            for reason in result["reasons"]:
                print(f"HARNESS_STATE_DELTA_REASON={reason}")
            return 0 if result["verdict"] == "PASS" else 1
        elif args.command == "record":
            args.observed_exit = int(args.observed_exit)
            args.diagnostic_count = int(args.diagnostic_count)
            path = record_case(args)
            print(f"HARNESS_CASE_RECORD={path}")
        elif args.command == "validate-transcript":
            manifest = read_manifest(Path(args.manifest))
            case = read_case(manifest, args.case_id)
            verdict, reason, _, _ = evaluate_transcript(
                case, args.case_id, Path(args.stdout_file), Path(args.stderr_file),
                Path(args.source_root), Path(args.project_root), Path(args.after),
            )
            print(f"HARNESS_TRANSCRIPT_VERDICT={verdict}")
            if reason:
                print(f"{reason}: {args.case_id}")
                return 1
        elif args.command == "validate-postconditions":
            manifest = read_manifest(Path(args.manifest))
            case = read_case(manifest, args.case_id)
            verdict, _, evidence_digest = evaluate_postconditions(
                case, args.case_id, Path(args.project_root), Path(args.after),
            )
            print(f"HARNESS_POSTCONDITION_VERDICT={verdict}")
            print(f"HARNESS_POSTCONDITION_EVIDENCE_SHA256={evidence_digest}")
        elif args.command == "validate-results":
            count = validate_results(args)
            print(f"HARNESS_RESULT_RECORDS={count}")
        elif args.command == "check-run":
            check_run(args)
            print("HARNESS_RUN_BINDING=PASS")
        elif args.command == "write-sentinel":
            write_owned_sentinel(Path(args.root), args.nonce, Path(args.tmp_parent) if args.tmp_parent else None)
        elif args.command == "prepare-owned-root":
            candidate, nonce, parent = prepare_owned_root(Path(args.tmpdir), args.prefix)
            print(f"{candidate}\t{nonce}\t{parent}")
        elif args.command == "create-owned-root":
            create_owned_root(Path(args.root), args.nonce, Path(args.tmp_parent))
        elif args.command == "cleanup-owned-root":
            cleanup_owned_root(Path(args.root), args.nonce, Path(args.tmp_parent) if args.tmp_parent else None)
        elif args.command == "lint":
            violations = lint_files(Path(args.manifest), Path(args.source_root), [Path(path) for path in args.paths])
            for violation in violations:
                print(violation)
            return 1 if violations else 0
        else:
            fail("HARNESS_COMMAND_UNKNOWN", args.command)
    except HarnessError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(f"HARNESS_INTERNAL_ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
