#!/usr/bin/env python3
"""Build deterministic publication-quality verifier fixtures.

The builder copies test inputs only.  Semantic decisions remain exclusively in
scripts/auto-research-verify.sh.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
from pathlib import Path


PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)

# apply_patch necessarily terminates added text files with a newline.  These
# five hash-bound source artifacts intentionally do not have one, so restore
# their canonical bytes after copying the vendored seed.
NO_FINAL_NEWLINE = {
    "analysis/analysis-plan.md",
    "design/design-blueprint.md",
    "literature/lit-theory.md",
    "literature/references.bib",
    "verify/runtime-sanity.md",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_digest(value: object) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def copy_new(source: Path, destination: Path) -> None:
    if destination.exists():
        raise SystemExit(f"fixture destination already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, destination)


def build_phase23(skill_dir: Path, destination: Path) -> None:
    source = skill_dir / "tests" / "fixtures" / "phase5-seed"
    copy_new(source, destination)

    # Phase 3 enforces the production revision chronology.  Version-control
    # checkout times are not meaningful, so normalize only fixture mtimes.
    base = 1_788_000_000
    for rel in (
        "design/design-blueprint.md",
        "design/identification-strategy.json",
        "design/model-specs.json",
    ):
        os.utime(destination / rel, (base, base))
    for rel in (
        "design/design-manifest.json",
        "design/design-evaluation.json",
        "design/design-evaluation.md",
    ):
        os.utime(destination / rel, (base + 1, base + 1))
    for rel in (
        "design/design-revision-log.json",
        "design/design-revision-log.md",
    ):
        os.utime(destination / rel, (base + 2, base + 2))


def build_phase1215(skill_dir: Path, destination: Path) -> None:
    source = skill_dir / "tests" / "fixtures" / "publication-quality-seed"
    metadata_path = source / "fixture-metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    generation = metadata.get("source_generation")
    if not isinstance(generation, dict):
        raise SystemExit("publication fixture source-generation record is missing")
    if canonical_digest(generation) != metadata.get("source_generation_sha256"):
        raise SystemExit("publication fixture source-generation record digest mismatch")
    if generation.get("source_kind") != "vendored_snapshot":
        raise SystemExit("publication fixture source generation must be a vendored snapshot")
    if generation.get("payload_inventory_sha256") != metadata.get("payload_inventory_sha256"):
        raise SystemExit("publication fixture source generation is not bound to the payload inventory")
    copy_new(source, destination)
    (destination / "fixture-metadata.json").unlink()

    for rel in NO_FINAL_NEWLINE:
        path = destination / rel
        data = path.read_bytes()
        if not data.endswith(b"\n"):
            raise SystemExit(f"expected transport newline in vendored fixture: {rel}")
        path.write_bytes(data[:-1])

    for rel in (
        "figures/event-study.png",
        "results-locked/LOCK-20260429-001/figures/event-study.png",
    ):
        path = destination / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(PNG_1X1)

    expected = metadata["payload_sha256"]
    actual_paths = {
        path.relative_to(destination).as_posix()
        for path in destination.rglob("*")
        if path.is_file()
    }
    if actual_paths != set(expected):
        missing = sorted(set(expected) - actual_paths)
        extra = sorted(actual_paths - set(expected))
        raise SystemExit(f"publication fixture inventory mismatch: missing={missing} extra={extra}")
    mismatches = [
        rel for rel, digest in sorted(expected.items())
        if sha256(destination / rel) != digest
    ]
    if mismatches:
        raise SystemExit(f"publication fixture digest mismatch: {mismatches}")
    inventory = "".join(f"{rel}\0{digest}\n" for rel, digest in sorted(expected.items()))
    inventory_digest = hashlib.sha256(inventory.encode("utf-8")).hexdigest()
    if inventory_digest != metadata["payload_inventory_sha256"]:
        raise SystemExit("publication fixture aggregate inventory digest mismatch")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("phase23", "phase1215"))
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    skill_dir = Path(__file__).resolve().parents[2]
    if args.kind == "phase23":
        build_phase23(skill_dir, args.destination)
    else:
        build_phase1215(skill_dir, args.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
