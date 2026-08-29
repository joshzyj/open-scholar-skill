#!/usr/bin/env python3
"""Discover production external-gate obligations without importing the verifier.

The verifier is a Bash entrypoint containing an embedded Python program.  This
helper deliberately recognizes only the invocation shapes used by that program:
literal gate tuples and literal ``consume_external_gate`` calls.  Variable-based
dispatch is attributed to the tuple that supplied the variable, so it does not
create a second, circular inventory.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


TUPLE_RE = re.compile(
    r'\(\s*"(?P<gate>[A-Za-z0-9._-]+\.sh)"\s*,\s*'
    r'"(?P<label>[^"]+)"(?P<tail>\s*,[^\n)]*)?\s*\)'
)
DIRECT_CONSUME_RE = re.compile(
    r'consume_external_gate\(\s*"(?P<gate>[A-Za-z0-9._-]+\.sh)"\s*,'
    r'(?P<body>.*?)(?=\n\s*\))\n\s*\)',
    re.DOTALL,
)
PHASE_LABEL_RE = re.compile(r'\bPhase\s+(?P<phase>\d+)\b')
PHASE_BLOCK_RE = re.compile(r'^if phase_id == "(?P<phase>\d+)":', re.MULTILINE)


class InventoryError(ValueError):
    pass


def _owning_phase(text: str, start: int, label: str) -> str:
    match = PHASE_LABEL_RE.search(label)
    if match:
        return match.group("phase")
    preceding = list(PHASE_BLOCK_RE.finditer(text, 0, start))
    if not preceding:
        raise InventoryError(f"cannot infer owning phase for external gate label: {label}")
    return preceding[-1].group("phase")


def inventory_text(text: str) -> dict[str, object]:
    rows: dict[tuple[str, str], dict[str, object]] = {}

    for match in TUPLE_RE.finditer(text):
        gate = match.group("gate")
        label = match.group("label")
        phase = _owning_phase(text, match.start(), label)
        key = (phase, gate)
        row = rows.setdefault(
            key,
            {"gate": gate, "owning_phase": phase, "labels": [], "invocation_shapes": []},
        )
        row["labels"].append(label)
        if "tuple_literal" not in row["invocation_shapes"]:
            row["invocation_shapes"].append("tuple_literal")

    for match in DIRECT_CONSUME_RE.finditer(text):
        gate = match.group("gate")
        body = match.group("body")
        label_match = re.search(r'"([^"]*Phase\s+\d+[^"]*)"', body)
        label = label_match.group(1) if label_match else gate
        phase = _owning_phase(text, match.start(), label)
        key = (phase, gate)
        row = rows.setdefault(
            key,
            {"gate": gate, "owning_phase": phase, "labels": [], "invocation_shapes": []},
        )
        if label not in row["labels"]:
            row["labels"].append(label)
        if "direct_consume_literal" not in row["invocation_shapes"]:
            row["invocation_shapes"].append("direct_consume_literal")

    obligations = []
    for key in sorted(rows, key=lambda item: (int(item[0]), item[1])):
        row = rows[key]
        row["labels"] = sorted(set(row["labels"]))
        row["invocation_shapes"] = sorted(row["invocation_shapes"])
        row["invariant_id"] = f"external_gate.phase_{row['owning_phase']}.{row['gate']}"
        obligations.append(row)
    return {
        "schema_version": "1.0.0",
        "supported_invocation_shapes": ["direct_consume_literal", "tuple_literal"],
        "obligations": obligations,
    }


def self_test() -> None:
    fixtures = {
        'if phase_id == "5":\n    consume_external_gate(\n        "control-variables-check.sh", proj, "Phase 5 controls",\n        failures, advisories,\n    )': ("5", "control-variables-check.sh", "direct_consume_literal"),
        'if phase_id == "18":\n    checks = [("effect-size-narrative-check.sh", "Phase 18 effects", ("18",))]': ("18", "effect-size-narrative-check.sh", "tuple_literal"),
        'if phase_id == "15":\n    checks = (("verify-citation-metadata.sh", "metadata authority", (bib,), True),)': ("15", "verify-citation-metadata.sh", "tuple_literal"),
    }
    for source, expected in fixtures.items():
        rows = inventory_text(source)["obligations"]
        if len(rows) != 1:
            raise InventoryError(f"shape self-test expected one obligation, found {len(rows)}")
        row = rows[0]
        got = (row["owning_phase"], row["gate"], row["invocation_shapes"][0])
        if got != expected:
            raise InventoryError(f"shape self-test mismatch: got {got!r}, expected {expected!r}")

        # BEFORE-style mutation: removing the invocation must erase the row.
        mutated = source.replace(expected[1], "not-a-shell-gate.txt")
        if inventory_text(mutated)["obligations"]:
            raise InventoryError(f"shape-removal mutation survived for {expected[2]}")

    prose = '# effect-size-narrative-check.sh is phase-aware\nlabel = f"Phase 18 gate"'
    if inventory_text(prose)["obligations"]:
        raise InventoryError("prose-only gate mention was treated as an invocation")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("verifier", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
        if args.verifier:
            print(json.dumps(inventory_text(args.verifier.read_text()), indent=2, sort_keys=True))
        elif not args.self_test:
            parser.error("verifier is required unless --self-test is used")
    except (OSError, InventoryError) as exc:
        print(f"EXTERNAL_GATE_INVENTORY_ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
