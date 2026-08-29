#!/usr/bin/env python3
"""Host-neutral runtime closure check for scholar-auto-research.

This checker is intentionally independent of Claude/Codex setup.  Every host
can run it before state or review work, while host-specific installers may
reuse it as their first step.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import sys


SCHEMA = "scholar-auto-research-runtime/v1"


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def safe_list(value: object, label: str) -> list[str]:
    if not isinstance(value, list) or not value:
        fail(f"runtime dependency manifest {label} must be a non-empty list")
    if any(not isinstance(item, str) or not item.strip() for item in value):
        fail(f"runtime dependency manifest {label} contains a blank/non-string entry")
    result = [str(item).strip() for item in value]
    if len(result) != len(set(result)):
        fail(f"runtime dependency manifest {label} contains duplicate entries")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skill-dir", type=Path)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    skill = (args.skill_dir or Path(__file__).resolve().parent.parent).resolve()
    manifest_path = skill / "references" / "runtime-dependencies.json"
    if not manifest_path.is_file() or not os.access(manifest_path, os.R_OK):
        fail("required runtime dependency missing/unreadable: references/runtime-dependencies.json")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        fail(f"runtime dependency manifest schema mismatch: expected {SCHEMA}")
    if manifest.get("schema_version") != SCHEMA:
        fail(f"runtime dependency manifest schema mismatch: expected {SCHEMA}")

    commands = safe_list(manifest.get("required_commands"), "required_commands")
    files = safe_list(manifest.get("required_packaged_files"), "required_packaged_files")
    for command in commands:
        if "/" in command or command in {".", ".."}:
            fail(f"runtime dependency manifest has unsafe command name: {command}")
        if shutil.which(command) is None:
            fail(f"required runtime command unavailable: {command}")

    for relative in files:
        rel = Path(relative)
        if rel.is_absolute() or ".." in rel.parts:
            fail(f"runtime dependency manifest has unsafe path: {relative}")
        candidate = skill / rel
        try:
            candidate.resolve().relative_to(skill)
        except (OSError, ValueError):
            fail(f"required runtime dependency escapes skill root: {relative}")
        if not candidate.is_file() or not os.access(candidate, os.R_OK):
            fail(f"required runtime dependency missing/unreadable: {relative}")

    if not args.quiet:
        print("RUNTIME_PREFLIGHT=PASS")
        print(f"RUNTIME_SCHEMA={SCHEMA}")
        print(f"REQUIRED_COMMANDS={len(commands)}")
        print(f"REQUIRED_PACKAGED_FILES={len(files)}")


if __name__ == "__main__":
    main()
