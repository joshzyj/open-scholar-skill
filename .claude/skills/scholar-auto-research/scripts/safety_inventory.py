"""Canonical, metadata-only Phase 0 inventory helpers.

This module never opens research-data files. It inventories regular file paths
under the safety-sensitive roots and hashes only the normalized safety receipt.
Content-digest validation remains the responsibility of the safety producer.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path


DATA_LIKE_EXTS = frozenset({
    "csv", "tsv", "dta", "sav", "por", "rds", "rdata", "rda", "xlsx", "xls",
    "xlsm", "ods", "parquet", "feather", "arrow", "db", "sqlite", "sqlite3",
    "h5", "hdf5", "mat", "pkl", "pickle", "npy", "npz", "jsonl", "ndjson",
    "wav", "mp3", "flac", "m4a", "ogg", "aac", "aiff", "mp4", "mov", "avi",
    "mkv", "webm", "jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "bmp",
    "webp", "gif", "eaf", "textgrid", "trs", "cha", "praat", "shp", "geojson",
    "kml", "gpx",
})

SENSITIVE_DATA_DIRS = (
    "data/raw", "data/interim", "data/processed", "materials", "transcripts",
    "interviews", "corpus", "corpora", "subjects", "participants", "respondents",
    "field-notes", "fieldnotes", "field_notes",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonicalize_status_mapping(project: Path, status_by_file: dict) -> tuple[dict[str, str], list[str]]:
    project_root = project.resolve()
    identities: set[str] = set()
    mapping: dict[str, str] = {}
    issues: list[str] = []
    for raw_key in status_by_file:
        raw_path = str(raw_key).strip()
        candidate = Path(raw_path)
        try:
            if candidate.is_absolute():
                relative = candidate.resolve().relative_to(project_root)
            else:
                relative = Path(os.path.normpath(raw_path))
                if not raw_path or relative.is_absolute() or ".." in relative.parts:
                    raise ValueError("path is empty, absolute, or traverses outside the project")
                resolved_relative = (project / relative).resolve().relative_to(project_root)
                if resolved_relative.as_posix() != relative.as_posix().lstrip("./"):
                    raise ValueError("path resolves through a symlink or alias")
            canonical = relative.as_posix().lstrip("./")
            if not canonical or canonical == ".":
                raise ValueError("path does not identify a project file")
        except (OSError, ValueError) as exc:
            issues.append(f"{raw_key}: not a canonical in-project path ({exc})")
            continue
        if canonical in identities:
            issues.append(f"{raw_key}: duplicate normalized identity {canonical}")
        identities.add(canonical)
        mapping[str(raw_key)] = canonical
    return mapping, issues


def canonicalize_status_paths(project: Path, status_by_file: dict) -> tuple[set[str], list[str]]:
    mapping, issues = canonicalize_status_mapping(project, status_by_file)
    return set(mapping.values()), issues


def discover_data_inventory(project: Path) -> tuple[list[str], list[str]]:
    discovered: set[str] = set()
    issues: list[str] = []
    for relative_root in SENSITIVE_DATA_DIRS:
        root = project / relative_root
        if not root.is_dir():
            continue
        for path in root.rglob("*"):
            if path.suffix.lower().lstrip(".") not in DATA_LIKE_EXTS:
                continue
            if path.is_symlink():
                issues.append(f"{path.relative_to(project).as_posix()}: symlinked data inputs are unsupported")
            elif path.is_file():
                discovered.add(path.relative_to(project).as_posix())
    return sorted(discovered), sorted(issues)


def discover_data_paths(project: Path) -> list[str]:
    paths, issues = discover_data_inventory(project)
    if issues:
        raise ValueError("; ".join(issues))
    return paths


def inventory_observation(project: Path, safety_path: Path) -> dict:
    paths, issues = discover_data_inventory(project)
    safety_digest = sha256_file(safety_path) if safety_path.is_file() else None
    content_hashes = {
        relative: sha256_file(project / relative)
        for relative in paths
    }
    canonical = json.dumps(
        {
            "paths": paths,
            "content_sha256": content_hashes,
            "safety_sha256": safety_digest,
            "issues": issues,
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return {
        "paths": paths,
        "content_sha256": content_hashes,
        "safety_sha256": safety_digest,
        "issues": issues,
        "digest": hashlib.sha256(canonical).hexdigest(),
    }
