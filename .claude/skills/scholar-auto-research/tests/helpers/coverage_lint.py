#!/usr/bin/env python3
"""Fail-closed static coverage lint for scholar-auto-research tests.

L0 freezes identities and bidirectional discovery.  It intentionally does not
accept test result records; authoritative execution accounting begins in L1.
"""

from __future__ import annotations

import argparse
import ast
import copy
from functools import lru_cache
import hashlib
import json
import os
import re
import shlex
import sys
import tempfile
from pathlib import Path
from pathlib import PurePosixPath
from typing import Optional

from external_gate_inventory import InventoryError, inventory_text, self_test as external_self_test


FINDINGS = {f"F{i:02d}" for i in range(1, 21)}
PHASES = {str(i) for i in range(21)}
TRUST_BOUNDARIES = {
    "safety_inventory",
    "ordered_state",
    "completion_authority",
    "review_evidence_protocol",
    "actual_independent_worker_execution",
    "citation_authority",
    "deliverable_authenticity",
    "contract_alignment",
    "runtime_alignment",
    "documentation_alignment",
    "harness_integrity",
}
CASE_FIELDS = {
    "path", "anchor", "runner_label", "tier", "gating", "production_entrypoint",
    "polarity", "expected_exit", "diagnostic_match", "mutation_policy",
    "finding_ids", "phase_ids", "invariant_selectors", "trust_boundary_ids",
    "setup_authority", "diagnostic_provenance", "transcript_policy",
    "execution_checkpoint", "postconditions",
}

DIAGNOSTIC_PROVENANCE_FIELDS = {
    "entrypoint_detail": {"mode"},
    "imported_detail": {"mode", "path"},
    "external_gate_detail": {"mode", "path", "gate", "label", "reason", "detail"},
}
TRANSCRIPT_POLICY_FIELDS = {"mode", "stdout", "stderr"}
POSTCONDITION_FIELDS = {
    "json_exact": {"kind", "path", "pointer", "value"},
    "json_absent": {"kind", "path", "pointer"},
    "json_sha256_equals_file": {"kind", "path", "pointer", "source_path"},
    "json_digest_equals_path": {"kind", "path", "pointer", "source_path", "source_type"},
    "json_iso8601_utc": {"kind", "path", "pointer"},
    "json_pointer_equal": {"kind", "path", "pointer", "other_path", "other_pointer"},
}
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
ADVISORY_RE = re.compile(
    r"^ADVISORY: external gate not GREEN \(non-fatal\) — "
    r"(?P<label>.+): (?P<status>YELLOW|INERT) \((?P<reason>[^()]*)\)$"
)
PINNED_EXTERNAL_GATE_CASE = "l2.p13.reject.table-callout"
PINNED_EXTERNAL_GATE_PROVENANCE = {
    "mode": "external_gate_detail",
    "path": "scripts/gates/descriptive-table-display-check.sh",
    "gate": "descriptive-table-display-check.sh",
    "label": "Phase 13 descriptive table display",
    "reason": "descriptive_table_not_reader_facing",
    "detail": "no_descriptive_table_artifact_or_display",
}
PINNED_EXTERNAL_GATE_TRANSCRIPT = {
    "mode": "exact_lines",
    "stdout": [
        "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 concept-to-measure bridge: INERT (no_labeled_variables)",
        "FAIL: Phase 13 external manuscript gates failed",
        "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display",
    ],
    "stderr": [],
}
STATE_TAIL_MARKER = "# L4_COMPLETION_TAIL_START"
POST_STOP20_START_MARKER = "# P10_REVIEWED_POST_STOP20_START"
STOP20_BOUNDARY = '''if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "20" ]]; then
  harness_validate_results --phase-through 20 >/dev/null
  progress "phases 0 to 20 authoritative harness assertions passed"
  exit 0
fi

'''
REVIEWED_FIXTURE_PATH = "scripts/auto-research-fixture-test.sh"
PINNED_REVIEWED_FIXTURE_SHA256 = "8fffbb540452c705d4c9457fe98212a80b139de91fda1fc2a4a288329474c7cd"
REVIEWED_HITL_PATH = "tests/smoke/test-human-in-loop.sh"
PINNED_REVIEWED_HITL_SHA256 = "cf6754fb6649627a1a56a5a296adffe525dd66ba9866a401458d8188a58bc3d6"
PINNED_REVIEWED_TEST_SOURCES_SHA256 = "48d7401fce881658bd2845343bc8ce1a9d6d8011567ff139b1d7792f270cc6db"
PINNED_POST_STOP20_INVENTORY_SHA256 = "cfea07522d2226a4fcbfea60777e912fb1a62a7e635e0f46f3a9e6f6b82444f3"
POST_STOP20_ROW_FIELDS = {
    "id", "region", "tool", "classification", "case_id", "stream_policy",
    "closure_status", "source_order", "stanza_sha256",
}
POST_STOP20_TOOLS = {
    "scripts/auto-research-state.sh": "auto-research-state.sh",
    "scripts/auto-research-verify.sh": "auto-research-verify.sh",
    "scripts/setup-project-claudemd.sh": "setup-project-claudemd.sh",
    "inline-python3": "python3 -",
}
STATE_TAIL_PROJECTION_FIELDS = (
    "expected_exit", "diagnostic_match", "diagnostic_provenance",
    "transcript_policy", "postconditions", "mutation_policy", "finding_ids",
    "phase_ids", "invariant_selectors", "trust_boundary_ids",
    "execution_checkpoint",
)
PINNED_STATE_TAIL_ASSERTION_CONTRACTS = {
    "phase.0.negative": "ebd4bada7778f84dbd93e054cb6745fe22f8f7070b0db1e1da44e6505a2355c4",
    "l2.p0.state.reject.hash-check-stale-safety": "bdb6f3319bce7be21066765de8d78f6124ba1c790c7373d7f450713b1295aee2",
    "l2.p0.state.accept.next-stale-safety": "8a865ec107298fc989ed3bf2d0849ce92adc55e229c2c86b070d30b4703422f2",
    "l2.p0.state.accept.import-local-mode": "6abbe25540013a5809c2a3d172208225372d59d77b68fc135e05afce74b4b100",
    "l2.p0.accept.imported-local-mode": "8123018fbee41d7ab5f490b1bc32542371025d4a8ca81859d57d2eb96f14a0f5",
    "l2.p0.state.reject.import-needs-review": "12224a7fb183bd6777bc36b7a49d90a005355866d9b9760107e272b9b91e08d6",
    "l2.p0.reject.imported-unresolved": "57bd01fb2d768644e989939b35bede9696b72ff9e2cebd70dda0937d0e32ae91",
    "l2.p0.state.reject.import-bare-override": "7b8e531cd2a9e945af9c145a524744f779ef7f0052c39a8f72a201a3240af8a8",
    "l2.p0.state.accept.import-meta-cleared": "12ea593e4bf84d8caf710ecd904c950cd1622bdcb336d343b15cfce7c0a46dde",
    "l2.p0.accept.import-meta-cleared": "51991232db6f33b3e1fc31efda53625b3a75af617aa56c19a4de16892cb4583d",
    "l2.p0.state.accept.import-meta-only": "fbe82d4d282a999c0e02b8d662b41b9fc30f519c52a3c434ddc850c72ec56a15",
    "l2.p0.state.reject.import-meta-needs-review": "a31d5dd1bf6e4f3903f9ed58fd3230b5135dbc7b5b6dd618cfd69f205e336b17",
    "l2.p0.reject.zero-scan-undeclared": "f7c7b6edc316a2f0cecd64cba13d11e82498e3c9d1dcc732dd4829ed323cd6cd",
    "l2.p0.reject.unscanned-data": "9fc2780820a0b0eb45c2f16e0ed15251c7b62fefb567bbdd6f963017384eefe6",
    "l2.p0.accept.data-free": "bee0c83d34213324d3297d8baddf308c8042d5b5708c14d8f3a1535eb37efd42",
    "l2.p0.reject.partial-scan": "e4fa58cd09a9bdd88527602c107b2cf2738efbd26e2aa8fe39293d2564715ddb",
}
PINNED_COMPLETION_TAIL_ASSERTION_CONTRACTS = {
    "l4.f9.accept.complete-without-prior-stamp": "7703ee78bb1bc5ecf66e226bbc070ebbbce77d159c5825d401374832ae04cedb",
    "l4.f9.reject.stale-stamp-completion": "b2b3847acba34682e9f69f4e4f6716a61d65b78f38e808ba5fc03e15e5158998",
    "l4.chain.accept.complete-phase-0": "9fd19dc795fa04343176526c678ef87290d14c04725f9947d253f6567a0458f7",
    "l4.chain.accept.complete-phase-1": "c6a6e41da626adb1647e78738beeba8b170b12a745742dbda8e35b61ccbdeefb",
    "l4.chain.accept.complete-phase-2": "2c8c509c25970a36e0ec56c1e7676b1f6f03ef4e77aa64b88811d413e2d3902a",
    "l4.chain.accept.complete-phase-3": "83f60fac85775c63fd33380045992be182c56a2cd05f36bb2c98cbcc12b24a35",
    "l4.chain.accept.complete-phase-4": "a80f06836d5c175797b719717ca1d18d801a99b0758d986d7dbd2919bd725cd7",
    "l4.chain.accept.complete-phase-5": "340455aa018e139c1caa34a81c116f0fa9a4efde7abd949da6b3a09ae2c3e50c",
    "l4.chain.accept.complete-phase-6": "bbb5ebe9c8516491193f56ef87be37d41ef744452cdbecbff9dc1d428a46db80",
    "l4.chain.accept.complete-phase-7": "f9a6f9d977313b556e13c4a647a2d85d47ad4d7bc90b550e87ed2048be78bb8c",
    "l4.chain.accept.complete-phase-8": "17ade3df32abc0c9a3fe74cad33e7f262eceeeb67ecf99210e96226477b1bcbf",
    "l4.chain.accept.complete-phase-9": "e5f55c9eb79b9e1a092738b27fb650c3de3170833fe3323f1c8189f5239a45f1",
    "l4.chain.accept.complete-phase-10": "48162b8d8e39e99d411189473cfe1ba01a369163123e8b95eb03bd077bda36bb",
    "l4.chain.accept.complete-phase-11": "2f5e9a1d28708d6af74f320aff97d43e3187d2eb288633db98ed4d2a1dfa405d",
    "l4.chain.accept.complete-phase-12": "db519920ef833a9661512795770c38d22719c1215938884508198aadeccd785d",
    "l4.chain.accept.complete-phase-13": "f5af43261be7c196a36d5d5c4579329e8c763b9e269858f6bbfb5bea7e41405d",
    "l4.chain.accept.complete-phase-14": "e56b12b507425943c4fb876f2262e444031da57f44ef91640426ddbc77172684",
    "l4.chain.accept.complete-phase-15": "2cf04b82ed91706a0e283ff461e80cda5b78146a5e47499b813fd16c66c0f910",
    "l4.chain.accept.complete-phase-16": "62e7d956031eb9c58fc7102842f598198a1b1142830e4d92a7e7dd02bf3fecba",
    "l4.chain.accept.complete-phase-17": "4401699445e1afe13d07660e639d117eb92818542c44239d799a3d2f9f8eac48",
    "l4.chain.accept.complete-phase-18": "1b0e7276ccf24546bc7bc256aa85b04e50cec174f4de1b92bda18293d7d45c97",
    "l4.chain.accept.complete-phase-19": "dc371c34b5287b6a7b4df603dc0df8b8b7c666aa2cb0e440a61ac944c077cfcc",
    "l4.chain.accept.complete-phase-20": "8a43db67aed937cb9b8444ebfc47de211e6b7941536420e5424457f0d7fa03ca",
    "l4.chain.accept.next-done": "83deda5038b568f6d9a36e2091044385bec7eab2ab7b0fdc8893d31d279f8055",
}


def canonical_digest(value: object) -> str:
    payload = json.dumps(value, indent=2, sort_keys=True) + "\n"
    return hashlib.sha256(payload.encode()).hexdigest()


def compact_canonical_digest(value: object) -> str:
    payload = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
        allow_nan=False,
    ) + "\n"
    return hashlib.sha256(payload.encode()).hexdigest()


def strict_json_loads(payload: str, label: str) -> object:
    def reject_duplicate(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"{label}: duplicate key {key!r}")
            result[key] = value
        return result

    def reject_constant(value: str) -> None:
        raise ValueError(f"{label}: non-finite number {value}")

    return json.loads(
        payload, object_pairs_hook=reject_duplicate, parse_constant=reject_constant,
    )


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def state_tail_projection(case_id: str, case: dict[str, object]) -> dict[str, object]:
    return {
        "case_id": case_id,
        **{field: case.get(field) for field in STATE_TAIL_PROJECTION_FIELDS},
    }


def validate_pinned_state_tail_cases(manifest: dict[str, object]) -> list[str]:
    cases = manifest.get("cases", {})
    actual = {
        case_id for case_id, case in cases.items()
        if case_id == "phase.0.negative"
        or isinstance(case, dict) and case.get("execution_checkpoint") == "state-tail"
    }
    expected = set(PINNED_STATE_TAIL_ASSERTION_CONTRACTS)
    if actual != expected:
        return ["PINNED_STATE_TAIL_CASE_SET_MISMATCH"]
    errors: list[str] = []
    for case_id, digest in PINNED_STATE_TAIL_ASSERTION_CONTRACTS.items():
        case = cases.get(case_id)
        if not isinstance(case, dict) or canonical_digest(state_tail_projection(case_id, case)) != digest:
            errors.append(f"PINNED_STATE_TAIL_CONTRACT_MISMATCH:{case_id}")
    return errors


def completion_tail_projection(case_id: str, case: dict[str, object]) -> dict[str, object]:
    # Pin the entire registered case. This includes discovery, execution,
    # mapping, transcript, mutation, and postcondition authority.
    return {"case_id": case_id, **case}


def validate_pinned_completion_tail_cases(manifest: dict[str, object]) -> list[str]:
    cases = manifest.get("cases", {})
    actual = {
        case_id for case_id, case in cases.items()
        if isinstance(case, dict) and case.get("execution_checkpoint") == "completion-tail"
    }
    expected = set(PINNED_COMPLETION_TAIL_ASSERTION_CONTRACTS)
    if actual != expected:
        return ["PINNED_COMPLETION_TAIL_CASE_SET_MISMATCH"]
    errors: list[str] = []
    for case_id, digest in PINNED_COMPLETION_TAIL_ASSERTION_CONTRACTS.items():
        case = cases.get(case_id)
        if not isinstance(case, dict) or canonical_digest(completion_tail_projection(case_id, case)) != digest:
            errors.append(f"PINNED_COMPLETION_TAIL_CONTRACT_MISMATCH:{case_id}")
    return errors


def validate_reviewed_test_sources(
    manifest: dict[str, object], skill_dir: Path,
) -> list[str]:
    value = manifest.get("reviewed_test_sources")
    expected = {
        REVIEWED_FIXTURE_PATH: PINNED_REVIEWED_FIXTURE_SHA256,
        REVIEWED_HITL_PATH: PINNED_REVIEWED_HITL_SHA256,
    }
    errors: list[str] = []
    if not isinstance(value, dict) or not value:
        return ["REVIEWED_TEST_SOURCES_SCHEMA"]
    if value != expected:
        errors.append("REVIEWED_TEST_SOURCES_PRODUCTION_SET_MISMATCH")
    if compact_canonical_digest(value) != PINNED_REVIEWED_TEST_SOURCES_SHA256:
        errors.append("REVIEWED_TEST_SOURCES_PROJECTION_PIN_MISMATCH")
    declared_paths = {
        case.get("path") for case in manifest.get("cases", {}).values()
        if isinstance(case, dict)
    }
    for relative, digest in value.items():
        if (
            not isinstance(relative, str) or not safe_manifest_relative(relative)
            or relative != PurePosixPath(relative).as_posix()
        ):
            errors.append(f"REVIEWED_TEST_SOURCE_PATH:{relative}")
            continue
        if relative not in declared_paths:
            errors.append(f"REVIEWED_TEST_SOURCE_UNDECLARED:{relative}")
        if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            errors.append(f"REVIEWED_TEST_SOURCE_DIGEST:{relative}")
            continue
        path = skill_dir / relative
        try:
            current = skill_dir
            component_invalid = False
            for part in PurePosixPath(relative).parts:
                current = current / part
                if current.is_symlink():
                    component_invalid = True
                    break
            if component_invalid or not path.is_file():
                errors.append(f"REVIEWED_TEST_SOURCE_FILE:{relative}")
            elif file_digest(path) != digest:
                errors.append(f"REVIEWED_TEST_SOURCE_DIGEST_MISMATCH:{relative}")
        except OSError:
            errors.append(f"REVIEWED_TEST_SOURCE_FILE:{relative}")
    return errors


def extract_post_stop20_stanzas(fixture_source: str) -> tuple[list[tuple[str, str, int, int]], list[str]]:
    errors: list[str] = []
    marker_pattern = re.compile(
        r"(?m)^# POST_STOP20_CALL_(BEGIN|END) ([A-Za-z0-9_.-]+)\n"
    )
    stanzas: list[tuple[str, str, int, int]] = []
    opened: tuple[str, int] | None = None
    begin_count = end_count = 0
    for match in marker_pattern.finditer(fixture_source):
        kind, stanza_id = match.group(1), match.group(2)
        if kind == "BEGIN":
            begin_count += 1
            if opened is not None:
                errors.append(f"POST_STOP20_STANZA_OVERLAP:{opened[0]}:{stanza_id}")
                continue
            opened = (stanza_id, match.start())
            continue
        end_count += 1
        if opened is None:
            errors.append(f"POST_STOP20_CALL_END_UNPAIRED:{stanza_id}")
            continue
        if opened[0] != stanza_id:
            errors.append(f"POST_STOP20_CALL_ID_CROSSING:{opened[0]}:{stanza_id}")
            opened = None
            continue
        start = opened[1]
        stanzas.append((stanza_id, fixture_source[start:match.end()], start, match.end()))
        opened = None
    if opened is not None:
        errors.append(f"POST_STOP20_CALL_BEGIN_UNPAIRED:{opened[0]}")
    if fixture_source.count("# POST_STOP20_CALL_BEGIN ") != begin_count:
        errors.append("POST_STOP20_CALL_BEGIN_UNPAIRED")
    if fixture_source.count("# POST_STOP20_CALL_END ") != end_count:
        errors.append("POST_STOP20_CALL_END_UNPAIRED")
    if len({item[0] for item in stanzas}) != len(stanzas):
        errors.append("POST_STOP20_CALL_ID_DUPLICATE")
    return stanzas, errors


def validate_post_stop20_inventory(
    manifest: dict[str, object], fixture_source: str,
) -> list[str]:
    errors: list[str] = []
    inventory = manifest.get("post_stop20_call_inventory")
    required_top = {"schema_version", "fixture_path", "start_marker", "l4_marker", "rows"}
    if not isinstance(inventory, dict) or set(inventory) != required_top:
        return ["POST_STOP20_INVENTORY_SCHEMA"]
    if inventory.get("schema_version") != "scholar-auto-research-post-stop20-call-inventory/v1":
        errors.append("POST_STOP20_INVENTORY_VERSION")
    if inventory.get("fixture_path") != REVIEWED_FIXTURE_PATH:
        errors.append("POST_STOP20_INVENTORY_FIXTURE_PATH")
    if inventory.get("start_marker") != POST_STOP20_START_MARKER:
        errors.append("POST_STOP20_INVENTORY_START_MARKER")
    if inventory.get("l4_marker") != STATE_TAIL_MARKER:
        errors.append("POST_STOP20_INVENTORY_L4_MARKER")
    boundary_count = fixture_source.count(STOP20_BOUNDARY)
    if boundary_count != 1:
        errors.append("POST_STOP20_FIXED_BOUNDARY_COUNT")
        return errors
    boundary_start = fixture_source.index(STOP20_BOUNDARY)
    scan_start = boundary_start + len(STOP20_BOUNDARY)
    if fixture_source.count(POST_STOP20_START_MARKER) != 1:
        errors.append("POST_STOP20_START_MARKER_COUNT")
        return errors
    if fixture_source.count(STATE_TAIL_MARKER) != 1:
        errors.append("L4_COMPLETION_TAIL_MARKER_COUNT")
        return errors
    start_pos = fixture_source.index(POST_STOP20_START_MARKER)
    l4_pos = fixture_source.index(STATE_TAIL_MARKER)
    start_end = start_pos + len(POST_STOP20_START_MARKER)
    l4_end = l4_pos + len(STATE_TAIL_MARKER)
    if start_pos != scan_start:
        errors.append("POST_STOP20_START_NOT_ATTACHED_TO_FIXED_BOUNDARY")
    if start_pos >= l4_pos:
        errors.append("POST_STOP20_MARKER_ORDER")
    stanzas, stanza_errors = extract_post_stop20_stanzas(fixture_source)
    errors.extend(stanza_errors)
    rows = inventory.get("rows")
    if not isinstance(rows, list) or len(rows) != 90:
        errors.append("POST_STOP20_INVENTORY_ROW_COUNT")
        rows = []
    if len(stanzas) != 90:
        errors.append("POST_STOP20_STANZA_COUNT")
    for index, row in enumerate(rows, 1):
        if not isinstance(row, dict) or set(row) != POST_STOP20_ROW_FIELDS:
            errors.append(f"POST_STOP20_ROW_SCHEMA:{index}")
            continue
        if row.get("source_order") != index:
            errors.append(f"POST_STOP20_ROW_ORDER:{index}")
        if index > len(stanzas):
            continue
        stanza_id, stanza, stanza_start, stanza_end = stanzas[index - 1]
        if row.get("id") != stanza_id:
            errors.append(f"POST_STOP20_ROW_ID:{index}")
        declared_region = row.get("region")
        if stanza_start < start_pos < stanza_end:
            errors.append(f"POST_STOP20_STANZA_CROSSES_START:{stanza_id}")
        elif stanza_start < start_end:
            errors.append(f"POST_STOP20_STANZA_BEFORE_START:{stanza_id}")
        if stanza_start < l4_pos < stanza_end:
            errors.append(f"POST_STOP20_STANZA_CROSSES_L4:{stanza_id}")
        if declared_region == "p10_state_tail" and stanza_end > l4_pos:
            errors.append(f"POST_STOP20_P10_STANZA_OUTSIDE_REGION:{stanza_id}")
        if declared_region == "l4_completion_tail" and stanza_start < l4_end:
            errors.append(f"POST_STOP20_L4_STANZA_OUTSIDE_REGION:{stanza_id}")
        expected_region = "p10_state_tail" if start_end <= stanza_start and stanza_end <= l4_pos else "l4_completion_tail"
        if row.get("region") != expected_region:
            errors.append(f"POST_STOP20_ROW_REGION:{stanza_id}")
        digest = row.get("stanza_sha256")
        if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            errors.append(f"POST_STOP20_ROW_DIGEST:{stanza_id}")
        elif hashlib.sha256(stanza.encode()).hexdigest() != digest:
            errors.append(f"POST_STOP20_STANZA_DIGEST_MISMATCH:{stanza_id}")
        tool = row.get("tool")
        basename = POST_STOP20_TOOLS.get(tool)
        if basename is None or stanza.count(basename) != 1:
            errors.append(f"POST_STOP20_ROW_TOOL:{stanza_id}")
        classification = row.get("classification")
        case_id = row.get("case_id")
        stream = row.get("stream_policy")
        closure = row.get("closure_status")
        stanza_lines = stanza.splitlines()
        body = "\n".join(stanza_lines[1:-1])
        if classification in {"p10_harnessed_semantic", "l4_harnessed_semantic"}:
            expected_closure = "l2_closed" if classification.startswith("p10_") else "l4_closed"
            expected_semantic_region = "p10_state_tail" if classification.startswith("p10_") else "l4_completion_tail"
            if (
                expected_region != expected_semantic_region or not isinstance(case_id, str)
                or stanza.count(f"# CASE_ID: {case_id}") != 1
                or re.search(rf"(?m)^expect_(?:pass|reject) {re.escape(case_id)} ", stanza) is None
                or stream != "harness_captured" or closure != expected_closure
                or re.fullmatch(
                    rf"# CASE_ID: {re.escape(case_id)}\n"
                    rf"expect_(?:pass|reject) {re.escape(case_id)} [^\n]+ -- \\\n"
                    rf"  bash \"\$SCRIPT_DIR/{re.escape(basename or '')}\" [^\n]+",
                    body,
                ) is None
            ):
                errors.append(f"POST_STOP20_SEMANTIC_ROW:{stanza_id}")
        elif classification == "p10_prerequisite":
            if case_id is not None or expected_region != "p10_state_tail" or closure != "prerequisite_only":
                errors.append(f"POST_STOP20_PREREQUISITE_ROW:{stanza_id}")
        elif classification == "l4_prerequisite":
            if case_id is not None or expected_region != "l4_completion_tail" or closure != "prerequisite_only":
                errors.append(f"POST_STOP20_L4_PREREQUISITE_ROW:{stanza_id}")
        else:
            errors.append(f"POST_STOP20_ROW_CLASSIFICATION:{stanza_id}")
        if stream == "stdout_discarded_stderr_observed_fail_closed":
            if (
                ">/dev/null" not in stanza
                or "2>/dev/null" in stanza or "2>&1" in stanza
                or "&>/dev/null" in stanza or ">&/dev/null" in stanza
                or "|| true" in stanza
            ):
                errors.append(f"POST_STOP20_STREAM_POLICY:{stanza_id}")
        elif stream == "harness_captured":
            if classification not in {"p10_harnessed_semantic", "l4_harnessed_semantic"} or ">/dev/null" in stanza:
                errors.append(f"POST_STOP20_STREAM_POLICY:{stanza_id}")
        else:
            errors.append(f"POST_STOP20_STREAM_POLICY:{stanza_id}")
    if rows:
        from collections import Counter
        classification_counts = Counter(row.get("classification") for row in rows if isinstance(row, dict))
        stream_counts = Counter(row.get("stream_policy") for row in rows if isinstance(row, dict))
        tool_counts = Counter(row.get("tool") for row in rows if isinstance(row, dict))
        if classification_counts != {
            "p10_harnessed_semantic": 15, "p10_prerequisite": 11,
            "l4_harnessed_semantic": 24, "l4_prerequisite": 40,
        }:
            errors.append("POST_STOP20_CLASSIFICATION_COUNTS")
        if stream_counts != {
            "harness_captured": 39,
            "stdout_discarded_stderr_observed_fail_closed": 51,
        }:
            errors.append("POST_STOP20_STREAM_COUNTS")
        if tool_counts != {
            "scripts/auto-research-state.sh": 71,
            "scripts/auto-research-verify.sh": 8,
            "scripts/setup-project-claudemd.sh": 10,
            "inline-python3": 1,
        }:
            errors.append("POST_STOP20_TOOL_COUNTS")
    # Exact supported-form closure: every production/setup token in the
    # reviewed region must belong to one and only one content-addressed stanza.
    masked = list(fixture_source[scan_start:])
    for _, _, absolute_start, absolute_end in stanzas:
        relative_start = absolute_start - scan_start
        relative_end = absolute_end - scan_start
        if relative_start < 0 or relative_end < relative_start or relative_end > len(masked):
            errors.append("POST_STOP20_MASK_RANGE_INVALID")
            continue
        for position in range(relative_start, relative_end):
            masked[position] = " "
    remainder = "".join(masked)
    for basename in POST_STOP20_TOOLS.values():
        if basename in remainder:
            errors.append(f"POST_STOP20_UNINVENTORIED_TOKEN:{basename}")
    if compact_canonical_digest(inventory) != PINNED_POST_STOP20_INVENTORY_SHA256:
        errors.append("POST_STOP20_INVENTORY_PIN_MISMATCH")
    return errors


def validate_execution_checkpoint_calls(
    manifest: dict[str, object], fixture_source: str,
) -> list[str]:
    errors: list[str] = []
    registry = manifest.get("execution_checkpoints", [])
    if not isinstance(registry, list):
        return errors
    calls = list(re.finditer(
        r"(?m)^[ \t]*harness_validate_results --checkpoint "
        r"([A-Za-z0-9][A-Za-z0-9_.-]*)[ \t]*(?:>/dev/null)?[ \t]*$",
        fixture_source,
    ))
    called = [match.group(1) for match in calls]
    for name in called:
        if name not in registry:
            errors.append(f"EXECUTION_CHECKPOINT_CALL_UNKNOWN:{name}")
    for name in registry:
        count = called.count(name)
        if count == 0:
            errors.append(f"EXECUTION_CHECKPOINT_CALL_MISSING:{name}")
        elif count != 1:
            errors.append(f"EXECUTION_CHECKPOINT_CALL_DUPLICATE:{name}")
    if "state-tail" not in registry or "completion-tail" not in registry:
        return errors
    marker_count = fixture_source.count(STATE_TAIL_MARKER)
    if marker_count != 1:
        errors.append("L4_COMPLETION_TAIL_MARKER_COUNT")
        return errors
    state_calls = [match for match in calls if match.group(1) == "state-tail"]
    completion_calls = [match for match in calls if match.group(1) == "completion-tail"]
    if len(state_calls) != 1 or len(completion_calls) != 1:
        return errors
    marker_pos = fixture_source.index(STATE_TAIL_MARKER)
    anchor_positions = []
    for case in manifest.get("cases", {}).values():
        if isinstance(case, dict) and case.get("execution_checkpoint") == "state-tail":
            anchor = case.get("anchor")
            if isinstance(anchor, str):
                anchor_positions.append(fixture_source.find(anchor))
    if (
        len(anchor_positions) != 15 or any(position < 0 for position in anchor_positions)
        or not max(anchor_positions) < state_calls[0].start() < marker_pos
    ):
        errors.append("EXECUTION_CHECKPOINT_CALL_ORDER:state-tail")
    completion_anchor_positions = []
    for case in manifest.get("cases", {}).values():
        if isinstance(case, dict) and case.get("execution_checkpoint") == "completion-tail":
            anchor = case.get("anchor")
            if isinstance(anchor, str):
                completion_anchor_positions.append(fixture_source.find(anchor))
    if (
        len(completion_anchor_positions) != 24
        or any(position < 0 for position in completion_anchor_positions)
        or not marker_pos < min(completion_anchor_positions)
        or not max(completion_anchor_positions) < completion_calls[0].start()
    ):
        errors.append("EXECUTION_CHECKPOINT_CALL_ORDER:completion-tail")
    checkpoint_line = "harness_validate_results --checkpoint state-tail"
    progress_line = 'progress "state-tail authoritative harness assertions passed"'
    completion_checkpoint_line = "harness_validate_results --checkpoint completion-tail"
    completion_progress_line = 'progress "completion-tail authoritative harness assertions passed"'
    final_line = "harness_validate_results"
    if sum(line == checkpoint_line for line in fixture_source.splitlines()) != 1:
        errors.append("EXECUTION_CHECKPOINT_RECEIPT_CALL_COUNT:state-tail")
    if sum(line == progress_line for line in fixture_source.splitlines()) != 1:
        errors.append("EXECUTION_CHECKPOINT_PROGRESS_COUNT:state-tail")
    if sum(line == completion_checkpoint_line for line in fixture_source.splitlines()) != 1:
        errors.append("EXECUTION_CHECKPOINT_RECEIPT_CALL_COUNT:completion-tail")
    if sum(line == completion_progress_line for line in fixture_source.splitlines()) != 1:
        errors.append("EXECUTION_CHECKPOINT_PROGRESS_COUNT:completion-tail")
    top_final = list(re.finditer(r"(?m)^harness_validate_results$", fixture_source))
    if len(top_final) != 1:
        errors.append("EXECUTION_FINAL_RECEIPT_CALL_COUNT")
    else:
        checkpoint_pos = fixture_source.index(checkpoint_line)
        progress_pos = fixture_source.index(progress_line) if progress_line in fixture_source else -1
        stop_pos = fixture_source.find('if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "state-tail" ]]', checkpoint_pos)
        completion_checkpoint_pos = fixture_source.index(completion_checkpoint_line)
        completion_progress_pos = fixture_source.index(completion_progress_line) if completion_progress_line in fixture_source else -1
        completion_stop_pos = fixture_source.find('if [[ "${SCHOLAR_FIXTURE_STOP_AFTER_PHASE:-}" == "completion-tail" ]]', completion_checkpoint_pos)
        if not (
            checkpoint_pos < progress_pos < stop_pos < marker_pos
            < completion_checkpoint_pos < completion_progress_pos < completion_stop_pos
            < top_final[0].start()
        ):
            errors.append("EXECUTION_RECEIPT_ORDER")
    return errors


def _flatten(prefix: str, value: object) -> list[str]:
    if isinstance(value, dict):
        out: list[str] = []
        for key in sorted(value):
            out.extend(_flatten(f"{prefix}.{key}", value[key]))
        return out
    if isinstance(value, list):
        out = []
        for index, item in enumerate(value):
            suffix = str(item) if not isinstance(item, (dict, list)) else str(index)
            out.extend(_flatten(f"{prefix}.{suffix}", item))
        return out
    return [prefix]


def derive_phase_invariants(contract: dict[str, object]) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for phase in contract.get("phases", []):
        phase_id = str(phase["id"])
        prefix = f"phase.{phase_id}"
        ids: set[str] = set()
        for value in phase.get("required_outputs", []):
            ids.add(f"{prefix}.required_output.{value}")
        for value in phase.get("pass_schema", []):
            ids.add(f"{prefix}.pass_schema.{value}")
        for value in phase.get("hash_dependencies", []):
            ids.add(f"{prefix}.hash_dependency.{value}")
        if phase_id == "0":
            for value in phase.get("non_overridable_failures", []):
                ids.add(f"{prefix}.non_overridable_failures.{value}")
        for key in ("conditional_requirements", "conditional_pass_schema", "review_evidence_policy"):
            if key in phase:
                ids.update(_flatten(f"{prefix}.{key}", phase[key]))
        result[phase_id] = ids
    return result


def discover_packaged(skill_dir: Path) -> set[str]:
    smoke = {p.relative_to(skill_dir).as_posix() for p in (skill_dir / "tests/smoke").glob("test-*.sh")}
    fixed = {
        "scripts/auto-research-contract-lint.sh",
        "scripts/auto-research-system-gate-smoke.sh",
        "scripts/auto-research-publication-quality-fixture-test.sh",
        "scripts/auto-research-fixture-test.sh",
    }
    return smoke | fixed


def normalize_runner_path(value: str) -> str | None:
    """Normalize one quoted runner path from the closed approved vocabulary."""
    prefixes = (
        ("$SKILL_SCRIPTS/", "scripts/"),
        ("${SKILL_SCRIPTS}/", "scripts/"),
        ("$SKILL_TESTS/", "tests/smoke/"),
        ("${SKILL_TESTS}/", "tests/smoke/"),
    )
    normalized = value
    for prefix, replacement in prefixes:
        if value.startswith(prefix):
            normalized = replacement + value[len(prefix):]
            break
    if normalized.startswith(("$", "/")) or any(token in normalized for token in ("*", "?", "[", "]", "\\")):
        return None
    path = PurePosixPath(normalized)
    if normalized in {"", "."} or path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        return None
    result = path.as_posix()
    if not (result.startswith("scripts/") or result.startswith("tests/smoke/")):
        return None
    return result


def discover_runner_bindings(path: Path) -> tuple[dict[str, dict[str, str]], list[str]]:
    """Parse top-level run_test/run_heavy calls without trusting shell evaluation."""
    if not path.exists():
        return {}, ["RUNNER_PATH_MISSING"]
    bindings: dict[str, dict[str, str]] = {}
    errors: list[str] = []
    call_pattern = re.compile(r'^run_(test|heavy)[ \t]+"([^"]+)"[ \t]+"([^"]+)"[ \t]*$')
    function_pattern = re.compile(r'^run_(?:test|heavy)\(\)[ \t]*\{')
    for line_number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if not line.startswith("run_") or function_pattern.match(line):
            continue
        match = call_pattern.fullmatch(line)
        if not match:
            errors.append(f"RUNNER_INVOCATION_UNPARSED:{line_number}")
            continue
        kind, label, raw_path = match.groups()
        normalized_path = normalize_runner_path(raw_path)
        if normalized_path is None:
            errors.append(f"RUNNER_PATH_UNPARSED:{label}:{raw_path}")
            continue
        if label in bindings:
            errors.append(f"RUNNER_LABEL_DUPLICATE:{label}")
            continue
        bindings[label] = {
            "tier": "heavy" if kind == "heavy" else "fast",
            "path": normalized_path,
        }
    return bindings, errors


def expand_selectors(selectors: list[str], universe: set[str]) -> set[str]:
    selected: set[str] = set()
    for selector in selectors:
        if selector.endswith(".*"):
            prefix = selector[:-1]
            selected.update(item for item in universe if item.startswith(prefix))
        elif selector in universe:
            selected.add(selector)
    return selected


class DiagnosticSourceParseError(ValueError):
    """A source region that must be Python did not parse as Python."""


DiagnosticTemplate = tuple[tuple[str, ...], bool, bool, bool]


def _legacy_string_templates(source: str) -> list[DiagnosticTemplate]:
    """Extract isolated one-line shell literals outside all heredoc bodies."""
    result: list[DiagnosticTemplate] = []
    pattern = re.compile(r"(?<![A-Za-z0-9_])(?P<prefix>[rRuUbBfF]{0,2})(?P<quote>['\"])(?P<body>.*?)(?<!\\)(?P=quote)")
    for raw_line in source.splitlines():
        quote = ""
        escaped = False
        kept: list[str] = []
        for char in raw_line:
            if escaped:
                kept.append(char)
                escaped = False
                continue
            if char == "\\" and quote:
                kept.append(char)
                escaped = True
                continue
            if char in "'\"":
                if not quote:
                    quote = char
                elif quote == char:
                    quote = ""
                kept.append(char)
                continue
            if char == "#" and not quote:
                break
            kept.append(char)
        line = "".join(kept)
        for match in pattern.finditer(line):
            prefix = match.group("prefix").lower()
            body = match.group("body")
            is_fstring = "f" in prefix
            if not is_fstring:
                try:
                    body = ast.literal_eval(match.group(0))
                except (SyntaxError, ValueError):
                    continue
                if not isinstance(body, str):
                    continue
                result.append(((body,), False, False, False))
                continue
            parts = tuple(part for part in re.split(r"\{[^{}]*\}", body) if part)
            result.append((
                parts,
                re.match(r"^\{[^{}]*\}", body) is not None,
                re.search(r"\{[^{}]*\}$", body) is not None,
                True,
            ))
    return result


def _python_string_templates(source: str, label: str) -> list[DiagnosticTemplate]:
    """Extract complete Python string expressions with AST adjacency semantics."""
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        location = f"{exc.lineno}:{exc.offset}" if exc.lineno is not None else "unknown"
        raise DiagnosticSourceParseError(f"{label}:{location}:{exc.msg}") from exc

    result: list[DiagnosticTemplate] = []

    class StringVisitor(ast.NodeVisitor):
        def visit_JoinedStr(self, node: ast.JoinedStr) -> None:
            parts: list[str] = []
            leading_dynamic = bool(node.values and isinstance(node.values[0], ast.FormattedValue))
            trailing_dynamic = bool(node.values and isinstance(node.values[-1], ast.FormattedValue))
            for value in node.values:
                if isinstance(value, ast.Constant) and isinstance(value.value, str):
                    if value.value:
                        parts.append(value.value)
                # FormattedValue is wholly dynamic.  In particular, do not
                # visit constants in its expression or its format_spec tree.
            result.append((tuple(parts), leading_dynamic, trailing_dynamic, True))

        def visit_Constant(self, node: ast.Constant) -> None:
            if isinstance(node.value, str):
                result.append(((node.value,), False, False, False))

    StringVisitor().visit(tree)
    return result


HeredocHeader = tuple[int, int, str, bool, bool, Optional[str], bool]


def _heredoc_headers(line: str) -> list[HeredocHeader]:
    """Return heredoc-looking spans, including inert spans in shell comments."""
    result: list[HeredocHeader] = []
    index = 0
    quote = ""
    in_comment = False
    while index < len(line):
        char = line[index]
        if quote and not in_comment:
            if char == quote:
                quote = ""
            elif char == "\\" and quote == '"':
                index += 1
            index += 1
            continue
        if not in_comment and char == "#" and (index == 0 or line[index - 1] in " \t;|&()"):
            in_comment = True
            index += 1
            continue
        if not in_comment and char in "'\"":
            quote = char
            index += 1
            continue
        if not line.startswith("<<", index) or line.startswith("<<<", index):
            index += 1
            continue
        operator_start = index
        fd_start = index
        while fd_start > 0 and line[fd_start - 1].isdigit():
            fd_start -= 1
        fd = line[fd_start:operator_start] or None
        start = fd_start
        index += 2
        strip_tabs = index < len(line) and line[index] == "-"
        if strip_tabs:
            index += 1
        while index < len(line) and line[index] in " \t":
            index += 1
        quoted = index < len(line) and line[index] in "'\""
        delimiter_quote = line[index] if quoted else ""
        if quoted:
            index += 1
            delimiter_start = index
            while index < len(line) and line[index] != delimiter_quote:
                index += 1
            if index >= len(line):
                continue
            delimiter = line[delimiter_start:index]
            index += 1
        else:
            delimiter_start = index
            while index < len(line) and line[index] not in " \t\r\n;|&<>()":
                index += 1
            delimiter = line[delimiter_start:index]
        if delimiter:
            result.append((start, index, delimiter, quoted, strip_tabs, fd, in_comment))
    return result


def _standalone_python_stdin_command(line: str, header: HeredocHeader) -> bool:
    """Recognize only Python whose sole effective stdin source is this heredoc."""
    headers = _heredoc_headers(line)
    if (
        len(headers) != 1
        or not header[3]
        or header[4]
        or header[5] not in {None, "0"}
        or header[6]
    ):
        return False
    # Reject every compound-command/control construct outside quotes. The
    # approved grammar is one simple physical command, not a pipeline,
    # sequence, background job, subshell, or command substitution.
    masked = list(line)
    quote = ""
    index = 0
    input_operators = 0
    while index < len(line):
        char = line[index]
        if quote:
            if quote == '"' and (char == "`" or (char == "$" and index + 1 < len(line) and line[index + 1] == "(")):
                return False
            if char == quote:
                quote = ""
            elif char == "\\" and quote == '"':
                index += 1
            index += 1
            continue
        if char in "'\"":
            quote = char
            index += 1
            continue
        if char == "#" and (index == 0 or line[index - 1] in " \t;|&()"):
            break
        if char in ";|&()`" or (char == "$" and index + 1 < len(line) and line[index + 1] == "("):
            return False
        if char == "<":
            input_operators += 1
            while index + 1 < len(line) and line[index + 1] in "<-&":
                index += 1
        index += 1
    if input_operators != 1:
        return False
    for position in range(header[0], header[1]):
        masked[position] = " "
    try:
        tokens = shlex.split("".join(masked), posix=True)
    except ValueError:
        return False
    if not tokens or not re.fullmatch(r"python(?:[0-9]+(?:\.[0-9]+)*)?", PurePosixPath(tokens[0]).name):
        return False
    # Frozen authority: the standalone stdin script operand is immediate.
    # No interpreter-option vocabulary is inferred or accepted.
    return len(tokens) >= 2 and tokens[1] == "-"


def _shell_string_templates(source: str) -> list[DiagnosticTemplate]:
    """Partition shell heredocs, parsing only authoritative Python program bodies."""
    lines = source.splitlines(keepends=True)
    fallback = list(lines)
    python_bodies: list[tuple[str, str]] = []
    line_index = 0
    while line_index < len(lines):
        headers = _heredoc_headers(lines[line_index])
        if not headers:
            line_index += 1
            continue
        command_line = lines[line_index]
        body_index = line_index + 1
        for header_index, header in enumerate(headers):
            body_start = body_index
            delimiter = header[2]
            while body_index < len(lines):
                candidate = lines[body_index].rstrip("\r\n")
                if header[4]:
                    candidate = candidate.lstrip("\t")
                if candidate == delimiter:
                    break
                body_index += 1
            body_end = body_index
            # Every heredoc body is inert to the legacy extractor. Recognized
            # Python bodies are parsed independently and never fall back.
            for offset in range(body_start, min(body_index + 1, len(lines))):
                fallback[offset] = "\n" if lines[offset].endswith("\n") else ""
            closed = body_index < len(lines)
            if closed and len(headers) == 1 and _standalone_python_stdin_command(command_line, header):
                body = "".join(lines[body_start:body_end])
                python_bodies.append((body, f"python-heredoc-line-{line_index + 1}"))
            if body_index < len(lines):
                body_index += 1
        line_index = max(line_index + 1, body_index)
    result = _legacy_string_templates("".join(fallback))
    for body, label in python_bodies:
        result.extend(_python_string_templates(body, label))
    return result


@lru_cache(maxsize=64)
def _string_templates(source: str, source_kind: str = "auto") -> tuple[DiagnosticTemplate, ...]:
    """Extract declarations from direct Python or partitioned packaged shell."""
    if source_kind == "python":
        return tuple(_python_string_templates(source, "python-source"))
    if source_kind == "shell":
        return tuple(_shell_string_templates(source))
    try:
        return tuple(_python_string_templates(source, "python-source"))
    except DiagnosticSourceParseError:
        return tuple(_shell_string_templates(source))


def source_declares_diagnostic(source: str, diagnostic: str, source_kind: str = "auto") -> bool:
    """Bind an exact line to a substantive literal/f-string declaration."""
    for parts, leading_dynamic, trailing_dynamic, is_dynamic in _string_templates(source, source_kind):
        if not is_dynamic:
            if parts and parts[0] == diagnostic:
                return True
            continue
        # A pure formatting emitter such as f"  - {item}" is not provenance.
        if not re.search(r"[A-Za-z0-9]", "".join(parts)):
            continue
        if not parts:
            continue
        if not leading_dynamic and not diagnostic.startswith(parts[0]):
            continue
        offset = 0
        for index, part in enumerate(parts):
            found = diagnostic.find(part, offset)
            if found < 0 or (index == 0 and not leading_dynamic and found != 0):
                break
            offset = found + len(part)
        else:
            if trailing_dynamic or diagnostic.endswith(parts[-1]):
                return True
    return False


def normalize_packaged_path(value: object, prefix: str, suffix: str | None = None) -> str | None:
    if not isinstance(value, str) or value.startswith(("/", "$")) or any(c in value for c in "*?[]\\"):
        return None
    path = PurePosixPath(value)
    if value in {"", "."} or any(part in {"", ".", ".."} for part in path.parts):
        return None
    normalized = path.as_posix()
    if not normalized.startswith(prefix) or (suffix is not None and not normalized.endswith(suffix)):
        return None
    return normalized


def entrypoint_imports_path(source: str, packaged_path: str) -> bool:
    module = packaged_path.removeprefix("scripts/").removesuffix(".py").replace("/", ".")
    patterns = (
        rf"^\s*from\s+{re.escape(module)}\s+import\s+",
        rf"^\s*import\s+{re.escape(module)}(?:\s|$)",
    )
    return any(re.search(pattern, source, re.MULTILINE) for pattern in patterns)


def packaged_source_path(skill_dir: Path, normalized: str) -> Path | None:
    candidate = skill_dir / normalized
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(skill_dir.resolve(strict=True))
    except (OSError, ValueError):
        return None
    return resolved if resolved.is_file() else None


def derive_external_gate_source_paths(
    manifest: dict[str, object], external: dict[str, object],
) -> tuple[set[str], list[str]]:
    """Derive the closed source-pin set from claims, never from the pin map."""
    required: set[str] = set()
    errors: list[str] = []
    for case_id, case in manifest.get("cases", {}).items():
        if not isinstance(case, dict):
            continue
        provenance = case.get("diagnostic_provenance")
        if isinstance(provenance, dict) and provenance.get("mode") == "external_gate_detail":
            normalized = normalize_packaged_path(provenance.get("path"), "scripts/gates/", ".sh")
            if normalized is not None:
                required.add(normalized)
        transcript = case.get("transcript_policy")
        if not isinstance(transcript, dict):
            continue
        for stream in ("stdout", "stderr"):
            lines = transcript.get(stream, [])
            if not isinstance(lines, list):
                continue
            for line in lines:
                if not isinstance(line, str) or not line.startswith("ADVISORY:"):
                    continue
                match = ADVISORY_RE.fullmatch(line)
                if not match:
                    continue
                candidates = [
                    row for row in external.get("obligations", [])
                    if match.group("label") in row.get("labels", [])
                ]
                if len(candidates) != 1:
                    errors.append(f"EXTERNAL_GATE_SOURCE_ADVISORY_RESOLUTION:{case_id}")
                    continue
                normalized = normalize_packaged_path(
                    f"scripts/gates/{candidates[0].get('gate', '')}", "scripts/gates/", ".sh",
                )
                if normalized is None:
                    errors.append(f"EXTERNAL_GATE_SOURCE_ADVISORY_PATH:{case_id}")
                else:
                    required.add(normalized)
    return required, errors


def nonsymlink_packaged_gate_path(skill_dir: Path, normalized: str) -> Path | None:
    """Resolve one canonical in-skill gate without accepting any symlink hop."""
    candidate = skill_dir
    for part in PurePosixPath(normalized).parts:
        candidate = candidate / part
        if candidate.is_symlink():
            return None
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(skill_dir.resolve(strict=True))
    except (OSError, ValueError):
        return None
    return candidate if candidate.is_file() else None


def validate_external_gate_source_map(
    manifest: dict[str, object], skill_dir: Path, external: dict[str, object],
) -> list[str]:
    errors: list[str] = []
    required, derive_errors = derive_external_gate_source_paths(manifest, external)
    errors.extend(derive_errors)
    source_map = manifest.get("external_gate_source_sha256")
    if not isinstance(source_map, dict) or any(not isinstance(key, str) for key in source_map):
        return errors + ["EXTERNAL_GATE_SOURCE_MAP_SCHEMA"]
    if set(source_map) != required:
        errors.append("EXTERNAL_GATE_SOURCE_KEY_SET_MISMATCH")
    for raw_path, digest in source_map.items():
        normalized = normalize_packaged_path(raw_path, "scripts/gates/", ".sh")
        if normalized is None or normalized != raw_path:
            errors.append(f"EXTERNAL_GATE_SOURCE_PATH:{raw_path}")
            continue
        if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            errors.append(f"EXTERNAL_GATE_SOURCE_DIGEST:{raw_path}")
            continue
        source_path = nonsymlink_packaged_gate_path(skill_dir, normalized)
        if source_path is None:
            errors.append(f"EXTERNAL_GATE_SOURCE_FILE:{raw_path}")
            continue
        if file_digest(source_path) != digest:
            errors.append(f"EXTERNAL_GATE_SOURCE_DIGEST_MISMATCH:{raw_path}")
    return errors


def validate_pinned_external_gate_case(manifest: dict[str, object]) -> list[str]:
    case = manifest.get("cases", {}).get(PINNED_EXTERNAL_GATE_CASE)
    if not isinstance(case, dict):
        return ["PINNED_EXTERNAL_GATE_CASE_MISSING"]
    errors: list[str] = []
    if case.get("diagnostic_provenance") != PINNED_EXTERNAL_GATE_PROVENANCE:
        errors.append("PINNED_EXTERNAL_GATE_PROVENANCE_MISMATCH")
    if case.get("transcript_policy") != PINNED_EXTERNAL_GATE_TRANSCRIPT:
        errors.append("PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH")
    return errors


def validate_diagnostic_provenance(
    case_id: str, case: dict[str, object], skill_dir: Path, entrypoint_source: str,
    external: dict[str, object],
) -> list[str]:
    errors: list[str] = []
    diagnostic = case.get("diagnostic_match", {}).get("value", "")
    provenance = case.get("diagnostic_provenance")
    is_detail = isinstance(diagnostic, str) and diagnostic.startswith("  - ")
    if not is_detail:
        if provenance is not None:
            errors.append(f"CASE_DIAGNOSTIC_PROVENANCE_UNEXPECTED:{case_id}")
        elif isinstance(diagnostic, str) and diagnostic and not source_declares_diagnostic(entrypoint_source, diagnostic, "shell"):
            errors.append(f"CASE_DIAGNOSTIC_NOT_IN_ENTRYPOINT:{case_id}")
        return errors
    if not isinstance(provenance, dict):
        return [f"CASE_DIAGNOSTIC_PROVENANCE_REQUIRED:{case_id}"]
    mode = provenance.get("mode")
    expected_fields = DIAGNOSTIC_PROVENANCE_FIELDS.get(mode)
    if expected_fields is None or set(provenance) != expected_fields:
        return [f"CASE_DIAGNOSTIC_PROVENANCE_SCHEMA:{case_id}"]
    stripped = diagnostic[4:]
    if not stripped or not re.search(r"[A-Za-z0-9]", stripped):
        return [f"CASE_DIAGNOSTIC_PROVENANCE_NONSUBSTANTIVE:{case_id}"]
    if mode == "entrypoint_detail":
        if not source_declares_diagnostic(entrypoint_source, stripped, "shell"):
            errors.append(f"CASE_DIAGNOSTIC_PROVENANCE_ENTRYPOINT:{case_id}")
    elif mode == "imported_detail":
        normalized = normalize_packaged_path(provenance.get("path"), "scripts/", ".py")
        if normalized is None:
            errors.append(f"CASE_DIAGNOSTIC_PROVENANCE_PATH:{case_id}")
        else:
            source_path = packaged_source_path(skill_dir, normalized)
            if source_path is None or not entrypoint_imports_path(entrypoint_source, normalized):
                errors.append(f"CASE_DIAGNOSTIC_PROVENANCE_IMPORT:{case_id}")
            elif not source_declares_diagnostic(source_path.read_text(errors="replace"), stripped, "python"):
                errors.append(f"CASE_DIAGNOSTIC_PROVENANCE_IMPORTED_SOURCE:{case_id}")
    elif mode == "external_gate_detail":
        normalized = normalize_packaged_path(provenance.get("path"), "scripts/gates/")
        gate = provenance.get("gate")
        label = provenance.get("label")
        reason = provenance.get("reason")
        detail = provenance.get("detail")
        reconstructed = f"  - {label}: reason={reason} detail={detail}"
        rows = [row for row in external.get("obligations", []) if row.get("gate") == gate and label in row.get("labels", [])]
        if normalized is None or PurePosixPath(normalized).name != gate:
            errors.append(f"CASE_DIAGNOSTIC_PROVENANCE_GATE_PATH:{case_id}")
        elif reconstructed != diagnostic:
            errors.append(f"CASE_DIAGNOSTIC_PROVENANCE_GATE_PAYLOAD:{case_id}")
        elif not rows:
            errors.append(f"CASE_DIAGNOSTIC_PROVENANCE_GATE_CALL:{case_id}")
    return errors


def validate_transcript_policy(
    case_id: str, case: dict[str, object], skill_dir: Path,
    entrypoint_source: str, external: dict[str, object], contract: dict[str, object],
) -> list[str]:
    policy = case.get("transcript_policy")
    if policy is None:
        return []
    diagnostic_spec = case.get("diagnostic_match", {})
    if not isinstance(policy, dict) or set(policy) != TRANSCRIPT_POLICY_FIELDS:
        return [f"CASE_TRANSCRIPT_POLICY_SCHEMA:{case_id}"]
    mode = policy.get("mode")
    if mode == "typed_lines":
        errors: list[str] = []
        dynamic_count = 0
        literal_lines: list[str] = []
        for stream in ("stdout", "stderr"):
            items = policy.get(stream)
            if not isinstance(items, list):
                return [f"CASE_TRANSCRIPT_POLICY_SCHEMA:{case_id}:{stream}"]
            for index, item in enumerate(items):
                if not isinstance(item, dict):
                    errors.append(f"CASE_TRANSCRIPT_ITEM_SCHEMA:{case_id}:{stream}:{index}")
                    continue
                kind = item.get("kind")
                if kind == "exact" and set(item) == {"kind", "value"}:
                    value = item.get("value")
                    if (
                        not isinstance(value, str) or "\n" in value or "\r" in value
                        or value.startswith("VERIFICATION_DESCRIPTOR_JSON=")
                    ):
                        errors.append(f"CASE_TRANSCRIPT_ITEM_SCHEMA:{case_id}:{stream}:{index}")
                    else:
                        literal_lines.append(value)
                elif kind == "owned_project_path" and set(item) == {"kind", "prefix", "suffix"}:
                    prefix, suffix = item.get("prefix"), item.get("suffix")
                    if (
                        not isinstance(prefix, str) or "\n" in prefix or "\r" in prefix
                        or not isinstance(suffix, str) or not safe_manifest_relative(suffix)
                    ):
                        errors.append(f"CASE_TRANSCRIPT_ITEM_SCHEMA:{case_id}:{stream}:{index}")
                    dynamic_count += 1
                elif kind == "verification_descriptor" and set(item) == {
                    "kind", "phase_id", "required_output_path",
                }:
                    phase_id, output_path = item.get("phase_id"), item.get("required_output_path")
                    if (
                        phase_id not in PHASES or not isinstance(output_path, str)
                        or not safe_manifest_relative(output_path)
                    ):
                        errors.append(f"CASE_TRANSCRIPT_ITEM_SCHEMA:{case_id}:{stream}:{index}")
                    else:
                        phase = next(
                            (row for row in contract.get("phases", []) if str(row.get("id")) == phase_id),
                            None,
                        )
                        patterns = phase.get("required_outputs", []) if isinstance(phase, dict) else []
                        if phase_id not in case.get("phase_ids", []) or not any(
                            fnmatch_path(output_path, pattern) for pattern in patterns if isinstance(pattern, str)
                        ):
                            errors.append(f"CASE_TRANSCRIPT_DESCRIPTOR_CONTRACT:{case_id}:{stream}:{index}")
                    dynamic_count += 1
                else:
                    errors.append(f"CASE_TRANSCRIPT_ITEM_SCHEMA:{case_id}:{stream}:{index}")
        if dynamic_count > 1:
            errors.append(f"CASE_TRANSCRIPT_DYNAMIC_COUNT:{case_id}")
        if case.get("polarity") == "negative" and diagnostic_spec.get("kind") == "exact":
            if literal_lines.count(diagnostic_spec.get("value")) != 1:
                errors.append(f"CASE_TRANSCRIPT_DIAGNOSTIC_COUNT:{case_id}")
        return errors
    if mode != "exact_lines":
        return [f"CASE_TRANSCRIPT_POLICY_SCHEMA:{case_id}"]
    if case.get("polarity") != "negative" or diagnostic_spec.get("kind") != "exact":
        return [f"CASE_TRANSCRIPT_POLICY_SCOPE:{case_id}"]
    for stream in ("stdout", "stderr"):
        lines = policy.get(stream)
        if not isinstance(lines, list) or any(not isinstance(line, str) or "\n" in line or "\r" in line for line in lines):
            return [f"CASE_TRANSCRIPT_POLICY_SCHEMA:{case_id}:{stream}"]
    diagnostic = diagnostic_spec.get("value", "")
    all_lines = policy["stdout"] + policy["stderr"]
    if all_lines.count(diagnostic) != 1:
        return [f"CASE_TRANSCRIPT_DIAGNOSTIC_COUNT:{case_id}"]
    errors: list[str] = []
    for line in all_lines:
        if line.startswith("ADVISORY:"):
            if any(char in line for char in "*?[]"):
                errors.append(f"CASE_TRANSCRIPT_ADVISORY_PATTERN:{case_id}")
                continue
            match = ADVISORY_RE.fullmatch(line)
            if not match:
                errors.append(f"CASE_TRANSCRIPT_ADVISORY_SCHEMA:{case_id}")
                continue
            candidates = [
                row for row in external.get("obligations", [])
                if match.group("label") in row.get("labels", [])
            ]
            if len(candidates) != 1:
                errors.append(f"CASE_TRANSCRIPT_ADVISORY_CALL:{case_id}")
                continue
            normalized = normalize_packaged_path(
                f"scripts/gates/{candidates[0].get('gate', '')}", "scripts/gates/", ".sh",
            )
            if normalized is None:
                errors.append(f"CASE_TRANSCRIPT_ADVISORY_SOURCE:{case_id}")
        elif line == diagnostic:
            continue
        elif line.startswith("FAIL:"):
            if not source_declares_diagnostic(entrypoint_source, line, "shell"):
                errors.append(f"CASE_TRANSCRIPT_FAILURE_PROVENANCE:{case_id}")
        elif line.startswith("  - "):
            # Only the declared exact detail is supported in the initial closed
            # vocabulary. Multiple detail lines need independent provenance.
            errors.append(f"CASE_TRANSCRIPT_DETAIL_UNDECLARED:{case_id}")
        else:
            errors.append(f"CASE_TRANSCRIPT_LINE_UNSUPPORTED:{case_id}")
    return errors


def safe_manifest_relative(value: str) -> bool:
    path = PurePosixPath(value)
    return (
        bool(value) and not path.is_absolute() and ".." not in path.parts
        and not any(ord(char) < 32 for char in value)
    )


def fnmatch_path(value: str, pattern: str) -> bool:
    import fnmatch
    return fnmatch.fnmatchcase(value, pattern) or PurePosixPath(value).match(pattern)


def valid_json_pointer(value: object) -> bool:
    if not isinstance(value, str) or (value and not value.startswith("/")):
        return False
    return not any(re.search(r"~(?![01])", token) for token in value.split("/")[1:])


def validate_postconditions(case_id: str, case: dict[str, object]) -> list[str]:
    declarations = case.get("postconditions")
    if declarations is None:
        return []
    if not isinstance(declarations, list):
        return [f"CASE_POSTCONDITION_SCHEMA:{case_id}"]
    errors: list[str] = []
    for index, item in enumerate(declarations):
        if not isinstance(item, dict):
            errors.append(f"CASE_POSTCONDITION_SCHEMA:{case_id}:{index}")
            continue
        kind = item.get("kind")
        if kind not in POSTCONDITION_FIELDS or set(item) != POSTCONDITION_FIELDS[kind]:
            errors.append(f"CASE_POSTCONDITION_SCHEMA:{case_id}:{index}")
            continue
        path = item.get("path")
        if not isinstance(path, str) or not path.endswith(".json") or not safe_manifest_relative(path):
            errors.append(f"CASE_POSTCONDITION_PATH:{case_id}:{index}")
        if not valid_json_pointer(item.get("pointer")):
            errors.append(f"CASE_POSTCONDITION_POINTER:{case_id}:{index}")
        if kind in {"json_sha256_equals_file", "json_digest_equals_path"}:
            source_path = item.get("source_path")
            if not isinstance(source_path, str) or not safe_manifest_relative(source_path):
                errors.append(f"CASE_POSTCONDITION_SOURCE_PATH:{case_id}:{index}")
            if kind == "json_digest_equals_path" and item.get("source_type") not in {"file", "directory"}:
                errors.append(f"CASE_POSTCONDITION_SOURCE_TYPE:{case_id}:{index}")
        if kind == "json_pointer_equal":
            other_path = item.get("other_path")
            if not isinstance(other_path, str) or not other_path.endswith(".json") or not safe_manifest_relative(other_path):
                errors.append(f"CASE_POSTCONDITION_OTHER_PATH:{case_id}:{index}")
            if not valid_json_pointer(item.get("other_pointer")):
                errors.append(f"CASE_POSTCONDITION_OTHER_POINTER:{case_id}:{index}")
    return errors


def validate(
    manifest: dict[str, object], skill_dir: Path, suite_runner: Path | None = None,
    repo_root: Path | None = None,
) -> list[str]:
    errors: list[str] = []
    contract_path = skill_dir / "references/phase-contract.json"
    verifier_path = skill_dir / "scripts/auto-research-verify.sh"
    try:
        contract = strict_json_loads(contract_path.read_text(), str(contract_path))
        external = inventory_text(verifier_path.read_text())
    except (OSError, json.JSONDecodeError, InventoryError) as exc:
        return [f"SOURCE_INVENTORY_ERROR: {exc}"]

    schema_version = manifest.get("schema_version")
    if schema_version != "1.2.0":
        errors.append("MANIFEST_SCHEMA_VERSION_MISMATCH")
    checkpoints = manifest.get("execution_checkpoints")
    if not isinstance(checkpoints, list) or any(
        not isinstance(item, str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", item) is None
        for item in checkpoints
    ):
        errors.append("EXECUTION_CHECKPOINTS_SCHEMA")
        checkpoints = []
    elif len(set(checkpoints)) != len(checkpoints):
        errors.append("EXECUTION_CHECKPOINTS_DUPLICATE")
    if set(manifest.get("findings", {})) != FINDINGS:
        errors.append("FINDING_SET_MISMATCH")
    if set(manifest.get("phases", {})) != PHASES:
        errors.append("PHASE_SET_MISMATCH")
    if set(manifest.get("trust_boundaries", {})) != TRUST_BOUNDARIES:
        errors.append("TRUST_BOUNDARY_SET_MISMATCH")
    if manifest.get("phase_contract_sha256") != file_digest(contract_path):
        errors.append("CONTRACT_DIGEST_MISMATCH")
    if manifest.get("external_gate_inventory_sha256") != canonical_digest(external):
        errors.append("EXTERNAL_GATE_INVENTORY_DIGEST_MISMATCH")
    errors.extend(validate_external_gate_source_map(manifest, skill_dir, external))
    errors.extend(validate_pinned_external_gate_case(manifest))
    errors.extend(validate_pinned_state_tail_cases(manifest))
    errors.extend(validate_pinned_completion_tail_cases(manifest))
    fixture_path = skill_dir / "scripts/auto-research-fixture-test.sh"
    if fixture_path.is_file():
        fixture_source = fixture_path.read_text(errors="replace")
        errors.extend(validate_reviewed_test_sources(manifest, skill_dir))
        errors.extend(validate_post_stop20_inventory(manifest, fixture_source))
        errors.extend(validate_execution_checkpoint_calls(
            manifest, fixture_source,
        ))
    else:
        errors.append("EXECUTION_CHECKPOINT_FIXTURE_MISSING")

    phase_invariants = derive_phase_invariants(contract)
    counts = {phase: len(ids) for phase, ids in phase_invariants.items()}
    if manifest.get("phase_invariant_counts") != counts:
        errors.append("PHASE_INVARIANT_COUNT_MISMATCH")
    external_ids = {row["invariant_id"] for row in external["obligations"]}
    if manifest.get("external_gate_invariant_count") != len(external_ids):
        errors.append("EXTERNAL_GATE_INVARIANT_COUNT_MISMATCH")
    universe = set().union(*phase_invariants.values()) | external_ids

    cases = manifest.get("cases", {})
    selected: set[str] = set()
    anchors: set[tuple[str, str]] = set()
    for case_id, case in cases.items():
        if not isinstance(case, dict):
            errors.append(f"CASE_SCHEMA_INVALID:{case_id}")
            continue
        missing = CASE_FIELDS - set(case)
        # Provenance, transcript, checkpoint, and postcondition declarations
        # are optional closed extensions; every other field remains required.
        missing -= {"diagnostic_provenance", "transcript_policy", "execution_checkpoint", "postconditions"}
        if missing:
            errors.append(f"CASE_FIELDS_MISSING:{case_id}:{','.join(sorted(missing))}")
            continue
        unknown = set(case) - CASE_FIELDS
        if unknown:
            errors.append(f"CASE_FIELDS_UNKNOWN:{case_id}:{','.join(sorted(unknown))}")
            continue
        rel = Path(case["path"])
        path = skill_dir / rel
        try:
            path.resolve().relative_to(skill_dir.resolve())
        except ValueError:
            errors.append(f"CASE_PATH_ESCAPE:{case_id}")
            continue
        if not path.is_file():
            errors.append(f"CASE_PATH_MISSING:{case_id}")
        else:
            anchor = str(case["anchor"])
            count = path.read_text(errors="replace").count(anchor)
            if count == 0:
                errors.append(f"CASE_ANCHOR_MISSING:{case_id}")
            elif count != 1:
                errors.append(f"CASE_ANCHOR_NOT_UNIQUE:{case_id}")
            key = (case["path"], anchor)
            if key in anchors:
                errors.append(f"CASE_ANCHOR_REUSED:{case_id}")
            anchors.add(key)
        entrypoint = skill_dir / case["production_entrypoint"]
        entrypoint_source = ""
        try:
            entrypoint.resolve().relative_to(skill_dir.resolve())
        except ValueError:
            errors.append(f"CASE_ENTRYPOINT_ESCAPE:{case_id}")
        if not entrypoint.is_file():
            errors.append(f"CASE_ENTRYPOINT_MISSING:{case_id}")
        else:
            entrypoint_source = entrypoint.read_text(errors="replace")
        if case["tier"] not in {"fast", "heavy"} or not isinstance(case["gating"], bool):
            errors.append(f"CASE_TIER_OR_GATING_INVALID:{case_id}")
        if case["polarity"] not in {"positive", "negative", "structural"}:
            errors.append(f"CASE_POLARITY_INVALID:{case_id}")
        if case["polarity"] == "structural":
            if any(field in case for field in ("execution_checkpoint", "postconditions", "transcript_policy")):
                errors.append(f"CASE_STRUCTURAL_SEMANTIC_FIELD:{case_id}")
            if str(case.get("anchor", "")).lstrip().startswith("# CASE_ID:"):
                errors.append(f"CASE_STRUCTURAL_HARNESS_MARKER:{case_id}")
        mutation_match = re.fullmatch(
            r"(?P<family>(?:l3\.[A-Za-z0-9_.-]+|f20\.mutation\.[A-Za-z0-9_.-]+))\."
            r"(?:pristine_positive|pristine_negative|mutant_valid|mutant_kill)",
            case_id,
        )
        if mutation_match is not None:
            family = mutation_match.group("family")
            expected_target = MUTATION_TARGETS.get(family)
            if expected_target is None:
                errors.append(f"CASE_MUTATION_FAMILY_UNKNOWN:{case_id}")
            else:
                case_source = skill_dir / str(case.get("path", ""))
                source_text = case_source.read_text(errors="replace") if case_source.is_file() else ""
                if PurePosixPath(expected_target).name not in source_text:
                    errors.append(f"CASE_MUTATION_TARGET_MISMATCH:{case_id}")
        expected_exit = case["expected_exit"]
        diagnostic = case["diagnostic_match"]
        if expected_exit.get("kind") != "exact" or not isinstance(expected_exit.get("value"), int):
            errors.append(f"CASE_EXIT_INVALID:{case_id}")
        if case["polarity"] == "negative":
            if expected_exit.get("value") == 0 or diagnostic.get("kind") != "exact" or not diagnostic.get("value"):
                errors.append(f"CASE_NEGATIVE_CONTRACT_INVALID:{case_id}")
            else:
                errors.extend(validate_diagnostic_provenance(
                    case_id, case, skill_dir, entrypoint_source, external,
                ))
        elif diagnostic.get("kind") != "none":
            errors.append(f"CASE_NONNEGATIVE_DIAGNOSTIC_INVALID:{case_id}")
        elif case.get("diagnostic_provenance") is not None:
            errors.append(f"CASE_DIAGNOSTIC_PROVENANCE_UNEXPECTED:{case_id}")
        errors.extend(validate_transcript_policy(
            case_id, case, skill_dir, entrypoint_source, external, contract,
        ))
        errors.extend(validate_postconditions(case_id, case))
        checkpoint = case.get("execution_checkpoint")
        if checkpoint is not None and checkpoint not in checkpoints:
            errors.append(f"CASE_EXECUTION_CHECKPOINT_UNKNOWN:{case_id}:{checkpoint}")
        if schema_version != "1.2.0" and (
            "execution_checkpoint" in case or "postconditions" in case
        ):
            errors.append(f"CASE_SCHEMA_1_1_FIELD_UNDER_OLDER_SCHEMA:{case_id}")
        policy = case["mutation_policy"]
        if policy.get("mode") not in {"unchanged", "declared_delta"}:
            errors.append(f"CASE_MUTATION_POLICY_INVALID:{case_id}")
        for field in ("authoritative_closure", "permitted", "forbidden", "ephemeral"):
            if field not in policy:
                errors.append(f"CASE_MUTATION_POLICY_MISSING:{case_id}:{field}")
        if set(case["finding_ids"]) - FINDINGS or set(case["phase_ids"]) - PHASES:
            errors.append(f"CASE_MAPPING_UNKNOWN:{case_id}")
        if set(case["trust_boundary_ids"]) - TRUST_BOUNDARIES:
            errors.append(f"CASE_TRUST_BOUNDARY_UNKNOWN:{case_id}")
        selected.update(expand_selectors(case["invariant_selectors"], universe))

    if selected != universe:
        errors.append("DERIVED_INVARIANT_COVERAGE_MISMATCH")
    for phase in sorted(PHASES, key=int):
        phase_cases = [c for c in cases.values() if phase in c.get("phase_ids", []) and c.get("gating")]
        if not any(c.get("polarity") == "positive" and c.get("setup_authority") == "production_entrypoint" for c in phase_cases):
            errors.append(f"PHASE_POSITIVE_MISSING:{phase}")
        if not any(c.get("polarity") == "negative" and c.get("diagnostic_match", {}).get("kind") == "exact" for c in phase_cases):
            errors.append(f"PHASE_EXACT_NEGATIVE_MISSING:{phase}")

    for finding, mapped in manifest.get("findings", {}).items():
        if not mapped or any(case_id not in cases for case_id in mapped):
            errors.append(f"FINDING_CASE_MISSING:{finding}")
        for case_id in mapped:
            if case_id in cases and finding not in cases[case_id].get("finding_ids", []):
                errors.append(f"FINDING_REVERSE_MAPPING_MISSING:{finding}:{case_id}")
    for case_id, case in cases.items():
        for finding in case.get("finding_ids", []):
            if case_id not in manifest.get("findings", {}).get(finding, []):
                errors.append(f"CASE_FINDING_MAPPING_STALE:{case_id}:{finding}")
    for phase, spec in manifest.get("phases", {}).items():
        declared = set(spec.get("positive_case_ids", [])) | set(spec.get("negative_case_ids", []))
        actual = {case_id for case_id, case in cases.items() if phase in case.get("phase_ids", [])}
        if declared != actual:
            errors.append(f"PHASE_CASE_MAPPING_MISMATCH:{phase}")
    for boundary, spec in manifest.get("trust_boundaries", {}).items():
        status = spec.get("scope_status")
        mapped = spec.get("case_ids", [])
        if status not in {"gating", "host_evidence", "explicit_nonclaim"}:
            errors.append(f"TRUST_BOUNDARY_STATUS_INVALID:{boundary}")
        if status == "gating" and (not mapped or any(case_id not in cases for case_id in mapped)):
            errors.append(f"TRUST_BOUNDARY_CASE_MISSING:{boundary}")
        if status == "explicit_nonclaim" and (not spec.get("justification") or mapped):
            errors.append(f"TRUST_BOUNDARY_NONCLAIM_INVALID:{boundary}")
        for case_id in mapped:
            if case_id in cases and boundary not in cases[case_id].get("trust_boundary_ids", []):
                errors.append(f"TRUST_BOUNDARY_REVERSE_MAPPING_MISSING:{boundary}:{case_id}")
    for case_id, case in cases.items():
        for boundary in case.get("trust_boundary_ids", []):
            if case_id not in manifest.get("trust_boundaries", {}).get(boundary, {}).get("case_ids", []):
                errors.append(f"CASE_TRUST_BOUNDARY_MAPPING_STALE:{case_id}:{boundary}")

    registry = manifest.get("suite_registry", {})
    registered_paths = {row["path"] for row in registry.values()}
    discovered_paths = discover_packaged(skill_dir)
    if registered_paths != discovered_paths:
        errors.append("PACKAGED_TEST_PATH_SET_MISMATCH")
    case_labels = {case["runner_label"] for case in cases.values() if case.get("gating")}
    if set(registry) - case_labels:
        errors.append("REGISTERED_RUNNER_WITHOUT_CASE")
    if case_labels - set(registry):
        errors.append("CASE_RUNNER_LABEL_STALE")
    for label, spec in registry.items():
        if not any(case.get("runner_label") == label and case.get("path") == spec.get("path") for case in cases.values()):
            errors.append(f"RUNNER_PATH_WITHOUT_CASE:{label}")
    for case_id, case in cases.items():
        if case.get("gating") and case.get("path") not in registered_paths:
            errors.append(f"CASE_PATH_NOT_REGISTERED:{case_id}")
        label = case.get("runner_label")
        if case.get("gating") and label in registry and registry[label].get("path") != case.get("path"):
            errors.append(f"CASE_RUNNER_PATH_MISMATCH:{case_id}")
    if suite_runner:
        runner_bindings, runner_errors = discover_runner_bindings(suite_runner)
        errors.extend(runner_errors)
        if set(runner_bindings) != set(registry):
            errors.append("RUNNER_LABEL_SET_MISMATCH")
        for label, binding in runner_bindings.items():
            if label in registry and registry[label].get("tier") != binding["tier"]:
                errors.append(f"RUNNER_TIER_MISMATCH:{label}")
            if label in registry and registry[label].get("path") != binding["path"]:
                errors.append(f"RUNNER_PATH_MISMATCH:{label}")

    if repo_root:
        source_specs = manifest.get("source_release_inventory", {})
        discovered = {p.relative_to(repo_root).as_posix() for p in (repo_root / "tests/smoke").glob("test-auto-research*.sh")}
        if set(source_specs) != discovered:
            errors.append("SOURCE_RELEASE_AUTO_RESEARCH_SET_MISMATCH")
        for rel, spec in source_specs.items():
            source = repo_root / rel
            if not source.is_file():
                errors.append(f"SOURCE_RELEASE_PATH_MISSING:{rel}")
                continue
            if spec.get("role") == "aggregate":
                continue
            target = skill_dir / spec.get("packaged_equivalent", "")
            if not target.is_file():
                errors.append(f"SOURCE_RELEASE_EQUIVALENT_MISSING:{rel}")
                continue
            body = source.read_text(errors="replace")
            if target.name not in body or len(body.splitlines()) > 35:
                errors.append(f"SOURCE_RELEASE_NOT_THIN_DELEGATE:{rel}")

        gate_to_phases: dict[str, set[str]] = {}
        for row in external["obligations"]:
            gate_to_phases.setdefault(row["gate"], set()).add(row["owning_phase"])
        for gate, owning_phases in gate_to_phases.items():
            root_test = repo_root / "tests/smoke" / f"test-{gate}"
            if root_test.is_file():
                for phase in owning_phases:
                    needed = f"external_gate.phase_{phase}.{gate}"
                    if needed not in selected:
                        errors.append(f"SOURCE_RELEASE_GATE_WITHOUT_PACKAGED_COVERAGE:{root_test.name}:{needed}")

    return errors


def run_self_test(manifest: dict[str, object], skill_dir: Path, suite_runner: Path) -> list[str]:
    failures: list[str] = []
    if source_declares_diagnostic('print(f"  - {item}")', "  - totally fabricated F20 detail"):
        failures.append("SELF_TEST_MUTATION_SURVIVED:formatting-only-f-string-provenance")
    if not source_declares_diagnostic('print(f"FAIL: Phase {phase} exact refusal")', "FAIL: Phase 13 exact refusal"):
        failures.append("SELF_TEST_VALID_CONTROL_REJECTED:substantive-f-string-provenance")
    if not source_declares_diagnostic(
        'agent_issues.append(f"{role}: verification_scope missing {sorted(required_scope - declared_scope)}")',
        "verify-logic: verification_scope missing ['phase9_constraints']",
    ):
        failures.append("SELF_TEST_VALID_CONTROL_REJECTED:leading-dynamic-f-string-provenance")
    if source_declares_diagnostic('print(f"FAIL: Phase {phase}")', "spoof FAIL: Phase 13"):
        failures.append("SELF_TEST_MUTATION_SURVIVED:literal-f-string-start-not-anchored")
    if source_declares_diagnostic('print(f"{role}: exact refusal")', "verify-logic: exact refusal spoof"):
        failures.append("SELF_TEST_MUTATION_SURVIVED:literal-f-string-end-not-anchored")

    phase18_diagnostic = (
        "FAIL: Phase 18 authoritative method_orientation requires a fifth "
        "method-specialized reviewer (family=computational)"
    )
    phase18_source = '''if specialist_review_needed:
    fail(
        "FAIL: Phase 18 authoritative method_orientation requires a fifth "
        f"method-specialized reviewer (family={specialist_family})",
        sorted(allowed_specialist_roles),
    )
'''
    if not source_declares_diagnostic(phase18_source, phase18_diagnostic, "python"):
        failures.append("SELF_TEST_VALID_CONTROL_REJECTED:phase18-adjacent-python-declaration")
    synthetic_diagnostic = "FAIL: adjacent template value=verified"
    synthetic_source = 'message = ("FAIL: adjacent template " f"value={value}")\n'
    if not source_declares_diagnostic(synthetic_source, synthetic_diagnostic, "python"):
        failures.append("SELF_TEST_VALID_CONTROL_REJECTED:synthetic-adjacent-python-declaration")
    synthetic_shell = "python3 - <<'PY'\n" + synthetic_source + "PY\n"
    if not source_declares_diagnostic(synthetic_shell, synthetic_diagnostic, "shell"):
        failures.append("SELF_TEST_VALID_CONTROL_REJECTED:quoted-python-heredoc-declaration")
    fd0_shell = "python3 - 0<<\"PY\"\n" + synthetic_source + "PY\n"
    if not source_declares_diagnostic(fd0_shell, synthetic_diagnostic, "shell"):
        failures.append("SELF_TEST_VALID_CONTROL_REJECTED:explicit-fd0-python-heredoc")
    quoted_controls_shell = "python3 - ';|&()$()`' <<'PY'\n" + synthetic_source + "PY\n"
    if not source_declares_diagnostic(quoted_controls_shell, synthetic_diagnostic, "shell"):
        failures.append("SELF_TEST_VALID_CONTROL_REJECTED:quoted-ordinary-control-characters")

    state_source = (skill_dir / "scripts/auto-research-state.sh").read_text(errors="replace")
    state_diagnostics = (
        "STALE_PHASES=0,1,2,3",
        "HUMAN_DECISION_REQUIRED: pending transition to Phase 1 must be approved before completing Phase 1",
        'IMPORT_INIT_BLOCKED: reason=needs_review path_json="data/raw/b.csv"',
    )
    for diagnostic in state_diagnostics:
        if not source_declares_diagnostic(state_source, diagnostic, "shell"):
            failures.append(f"SELF_TEST_VALID_CONTROL_REJECTED:state-standalone-heredoc:{diagnostic}")
    state_header = 'python3 - "$CONTRACT" "$CMD" "$PROJ" "$@" <<\'PY\''
    if state_source.count(state_header) != 1:
        failures.append("SELF_TEST_STATE_HEREDOC_HEADER_DRIFT")
    else:
        compound_state_source = state_source.replace(
            state_header, state_header + " || _ARS_RC=$?", 1,
        )
        for diagnostic in state_diagnostics:
            if source_declares_diagnostic(compound_state_source, diagnostic, "shell"):
                failures.append(f"SELF_TEST_MUTATION_SURVIVED:state-compound-heredoc:{diagnostic}")

    provenance_negatives = (
        (
            "separate-standalone-strings",
            '"FAIL: adjacent template "\nf"value={value}"\n',
            "python",
        ),
        (
            "comma-separated-arguments",
            'fail("FAIL: adjacent template ", f"value={value}")\n',
            "python",
        ),
        (
            "comment-separated-tokens",
            '"FAIL: adjacent template "  # f"value={value}"\nf"value={value}"\n',
            "python",
        ),
        (
            "arbitrary-cross-line-tokens",
            'message = ("FAIL: adjacent template "\n           + f"value={value}")\n',
            "python",
        ),
        (
            "formatting-only-adjacent-emitter",
            'message = ("  - " f"{item}")\n',
            "python",
        ),
        (
            "cat-heredoc",
            "cat <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "unquoted-python-heredoc",
            "python3 - <<PY\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "python-c-inert-stdin",
            "python3 -c 'pass' <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "python-m-inert-stdin",
            "python3 -m module <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "python-script-inert-stdin",
            "python3 script.py <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "python-overridden-stdin",
            "python3 - <<'PY' < /dev/null\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "python-multiple-heredocs",
            "python3 - <<'ONE' <<'TWO'\nmessage = 'FAIL: adjacent template value=verified'\nONE\nmessage = 'FAIL: adjacent template value=verified'\nTWO\n",
            "shell",
        ),
        (
            "wrong-owner-semicolon",
            "python3 - ; cat <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "wrong-owner-and",
            "python3 - && cat <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "wrong-owner-or",
            "python3 - || cat <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "wrong-owner-pipeline",
            "python3 - | cat <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "wrong-owner-background",
            "python3 - & cat <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "compound-heredoc-or",
            "python3 - <<'PY' || rc=$?\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "compound-heredoc-and",
            "python3 - <<'PY' && true\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "compound-heredoc-pipeline",
            "python3 - <<'PY' | cat\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "compound-heredoc-sequence",
            "python3 - <<'PY'; true\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "compound-heredoc-background",
            "python3 - <<'PY' &\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "subshell-heredoc",
            "( python3 - <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n)\n",
            "shell",
        ),
        (
            "active-command-substitution",
            "python3 - $(printf arg) <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "active-command-substitution-double-quoted",
            "python3 - \"$(printf arg)\" <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "active-backticks",
            "python3 - `printf arg` <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "active-backticks-double-quoted",
            "python3 - \"`printf arg`\" <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "assignment-command-substitution-envelope",
            "result=$(python3 - <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n)\n",
            "shell",
        ),
        (
            "commented-heredoc-operator",
            "python3 - # harmless <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "unterminated-heredoc",
            "python3 - <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\n",
            "shell",
        ),
        (
            "tab-stripping-single-quoted-heredoc",
            "python3 - <<-'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "tab-stripping-double-quoted-heredoc",
            "python3 - <<-\"PY\"\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "nonstdin-fd1-heredoc",
            "python3 - 1<<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "nonstdin-fd2-heredoc",
            "python3 - 2<<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "nonstdin-fd3-heredoc",
            "python3 - 3<<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "nonstdin-fd10-heredoc",
            "python3 - 10<<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "invalid-long-interpreter-option",
            "python3 --definitely-invalid - <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "invalid-short-interpreter-option",
            "python3 -Z - <<'PY'\nmessage = 'FAIL: adjacent template value=verified'\nPY\n",
            "shell",
        ),
        (
            "formatted-expression-constant",
            'message = f"{\'FAIL: adjacent template value=verified\'}"\n',
            "python",
        ),
        (
            "format-spec-constant",
            'message = f"{value:FAIL: adjacent template value=verified}"\n',
            "python",
        ),
    )
    for name, source, source_kind in provenance_negatives:
        diagnostic = "  - fabricated detail" if name == "formatting-only-adjacent-emitter" else synthetic_diagnostic
        if source_declares_diagnostic(source, diagnostic, source_kind):
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:{name}")

    malformed_heredoc = """python3 - <<'PY'
message = 'FAIL: adjacent template value=verified'
if
PY
"""
    try:
        source_declares_diagnostic(malformed_heredoc, synthetic_diagnostic, "shell")
    except DiagnosticSourceParseError:
        pass
    else:
        failures.append("SELF_TEST_MUTATION_SURVIVED:malformed-recognized-python-failed-open")

    try:
        source_declares_diagnostic("message = 'plausible diagnostic'\nif\n", "plausible diagnostic", "python")
    except DiagnosticSourceParseError:
        pass
    else:
        failures.append("SELF_TEST_MUTATION_SURVIVED:malformed-direct-python-failed-open")

    mutations = []
    m = copy.deepcopy(manifest); m["findings"].pop("F20"); mutations.append(("finding", m, "FINDING_SET_MISMATCH"))
    m = copy.deepcopy(manifest); m["phases"].pop("20"); mutations.append(("phase", m, "PHASE_SET_MISMATCH"))
    m = copy.deepcopy(manifest); m["phase_invariant_counts"]["20"] -= 1; mutations.append(("invariant", m, "PHASE_INVARIANT_COUNT_MISMATCH"))
    m = copy.deepcopy(manifest); m["trust_boundaries"].pop("harness_integrity"); mutations.append(("trust", m, "TRUST_BOUNDARY_SET_MISMATCH"))
    trust_case = manifest["trust_boundaries"]["harness_integrity"]["case_ids"][0]
    m = copy.deepcopy(manifest); m["cases"][trust_case]["trust_boundary_ids"].remove("harness_integrity"); mutations.append(("trust-reverse", m, f"TRUST_BOUNDARY_REVERSE_MAPPING_MISSING:harness_integrity:{trust_case}"))
    m = copy.deepcopy(manifest); m["trust_boundaries"]["harness_integrity"]["case_ids"].remove(trust_case); mutations.append(("trust-stale", m, f"CASE_TRUST_BOUNDARY_MAPPING_STALE:{trust_case}:harness_integrity"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.positive"]["anchor"] = "anchor deleted by self-test"; mutations.append(("anchor", m, "CASE_ANCHOR_MISSING:phase.0.positive"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.positive"]["path"] = "tests/smoke/not-present.sh"; mutations.append(("path", m, "CASE_PATH_MISSING:phase.0.positive"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.negative"]["diagnostic_match"]["value"] = "F20 diagnostic exists only in an unrelated test file"; m["cases"]["phase.0.negative"].pop("diagnostic_provenance"); mutations.append(("entrypoint-diagnostic", m, "CASE_DIAGNOSTIC_NOT_IN_ENTRYPOINT:phase.0.negative"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.positive"]["invented_field"] = True; mutations.append(("unknown-case-field", m, "CASE_FIELDS_UNKNOWN:phase.0.positive:invented_field"))
    m = copy.deepcopy(manifest); m.pop("execution_checkpoints"); mutations.append(("checkpoint-registry-missing", m, "EXECUTION_CHECKPOINTS_SCHEMA"))
    m = copy.deepcopy(manifest); m["execution_checkpoints"] = ["state-tail", "state-tail"]; mutations.append(("checkpoint-registry-duplicate", m, "EXECUTION_CHECKPOINTS_DUPLICATE"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.positive"]["execution_checkpoint"] = "absent"; mutations.append(("checkpoint-tag-unknown", m, "CASE_EXECUTION_CHECKPOINT_UNKNOWN:phase.0.positive:absent"))
    m = copy.deepcopy(manifest); m["schema_version"] = "1.0.0"; m["cases"]["phase.0.positive"]["postconditions"] = []; mutations.append(("schema-old-postconditions", m, "CASE_SCHEMA_1_1_FIELD_UNDER_OLDER_SCHEMA:phase.0.positive"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.positive"]["postconditions"] = [{"kind": "shell_callback", "path": "x.json", "pointer": ""}]; mutations.append(("postcondition-executable-kind", m, "CASE_POSTCONDITION_SCHEMA:phase.0.positive:0"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.positive"]["postconditions"] = [{"kind": "json_exact", "path": "../x.json", "pointer": "", "value": {}}]; mutations.append(("postcondition-path-escape", m, "CASE_POSTCONDITION_PATH:phase.0.positive:0"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.positive"]["postconditions"] = [{"kind": "json_digest_equals_path", "path": "x.json", "pointer": "/digest", "source_path": "x", "source_type": "special"}]; mutations.append(("postcondition-source-type-invalid", m, "CASE_POSTCONDITION_SOURCE_TYPE:phase.0.positive:0"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.positive"]["postconditions"] = [{"kind": "json_digest_equals_path", "path": "x.json", "pointer": "/digest", "source_path": "x"}]; mutations.append(("postcondition-source-type-missing", m, "CASE_POSTCONDITION_SCHEMA:phase.0.positive:0"))
    structural_id = "f20.migration.direct-to-final.pure"
    m = copy.deepcopy(manifest); m["cases"][structural_id]["transcript_policy"] = {"mode": "typed_lines", "stdout": [], "stderr": []}; mutations.append(("structural-semantic-field", m, f"CASE_STRUCTURAL_SEMANTIC_FIELD:{structural_id}"))
    mutation_id = "l3.source_roles.mutant_kill"
    m = copy.deepcopy(manifest); m["cases"][mutation_id]["path"] = "tests/smoke/test-human-in-loop.sh"; mutations.append(("mutation-target-swap", m, f"CASE_MUTATION_TARGET_MISMATCH:{mutation_id}"))
    m = copy.deepcopy(manifest); unknown = copy.deepcopy(m["cases"][mutation_id]); m["cases"]["f20.mutation.unknown_family.mutant_kill"] = unknown; mutations.append(("mutation-family-unknown", m, "CASE_MUTATION_FAMILY_UNKNOWN:f20.mutation.unknown_family.mutant_kill"))
    m = copy.deepcopy(manifest); m["cases"]["phase.0.positive"]["runner_label"] = "harness-self-test"; mutations.append(("case-label-path", m, "CASE_RUNNER_PATH_MISMATCH:phase.0.positive"))
    m = copy.deepcopy(manifest); m["suite_registry"]["contract-lint"]["path"] = "tests/smoke/test-harness.sh"; mutations.append(("registry-label-path", m, "CASE_RUNNER_PATH_MISMATCH:runner.contract-lint"))
    m = copy.deepcopy(manifest); m["suite_registry"].pop("coverage-manifest"); mutations.append(("forwarding", m, "RUNNER_LABEL_SET_MISMATCH"))

    detail_case = "phase.13.negative"
    m = copy.deepcopy(manifest)
    m["cases"][detail_case]["diagnostic_match"]["value"] = "  - totally fabricated F20 detail"
    mutations.append(("fabricated-detail", m, f"CASE_DIAGNOSTIC_PROVENANCE_REQUIRED:{detail_case}"))
    m = copy.deepcopy(manifest)
    m["cases"][detail_case]["diagnostic_match"]["value"] = "  - totally fabricated F20 detail"
    m["cases"][detail_case]["diagnostic_provenance"] = {"mode": "entrypoint_detail"}
    mutations.append(("formatting-emitter", m, f"CASE_DIAGNOSTIC_PROVENANCE_ENTRYPOINT:{detail_case}"))

    imported_diagnostic = "  - round verification_panel: semantic reviewer roles do not match completed evidence roles"
    imported_base = copy.deepcopy(manifest)
    imported_base["cases"][detail_case]["diagnostic_match"]["value"] = imported_diagnostic
    imported_base["cases"][detail_case]["diagnostic_provenance"] = {
        "mode": "imported_detail", "path": "scripts/review_evidence.py",
    }
    m = copy.deepcopy(imported_base); m["cases"][detail_case]["diagnostic_provenance"]["path"] = "/tmp/review_evidence.py"; mutations.append(("detail-absolute-source", m, f"CASE_DIAGNOSTIC_PROVENANCE_PATH:{detail_case}"))
    m = copy.deepcopy(imported_base); m["cases"][detail_case]["diagnostic_provenance"]["path"] = "scripts/../review_evidence.py"; mutations.append(("detail-traversal-source", m, f"CASE_DIAGNOSTIC_PROVENANCE_PATH:{detail_case}"))
    m = copy.deepcopy(imported_base); m["cases"][detail_case]["diagnostic_provenance"]["path"] = "scripts/runtime-preflight.py"; mutations.append(("detail-unimported-source", m, f"CASE_DIAGNOSTIC_PROVENANCE_IMPORT:{detail_case}"))

    external_diagnostic = "  - Phase 13 descriptive table display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"
    external_base = copy.deepcopy(manifest)
    external_base["cases"][detail_case]["diagnostic_match"]["value"] = external_diagnostic
    external_base["cases"][detail_case]["diagnostic_provenance"] = {
        "mode": "external_gate_detail",
        "path": "scripts/gates/descriptive-table-display-check.sh",
        "gate": "descriptive-table-display-check.sh",
        "label": "Phase 13 descriptive table display",
        "reason": "descriptive_table_not_reader_facing",
        "detail": "no_descriptive_table_artifact_or_display",
    }
    m = copy.deepcopy(external_base); m["cases"][detail_case]["diagnostic_provenance"]["label"] = "Phase 13 spoofed display"; m["cases"][detail_case]["diagnostic_match"]["value"] = "  - Phase 13 spoofed display: reason=descriptive_table_not_reader_facing detail=no_descriptive_table_artifact_or_display"; mutations.append(("detail-wrong-gate-label", m, f"CASE_DIAGNOSTIC_PROVENANCE_GATE_CALL:{detail_case}"))

    transcript_base = copy.deepcopy(external_base)
    transcript_base["cases"][detail_case]["transcript_policy"] = {
        "mode": "exact_lines",
        "stdout": [
            "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 concept-to-measure bridge: INERT (no_labeled_variables)",
            "FAIL: Phase 13 external manuscript gates failed",
            external_diagnostic,
        ],
        "stderr": [],
    }
    m = copy.deepcopy(transcript_base); m["cases"][detail_case]["transcript_policy"]["stdout"][0] = "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 spoofed bridge: INERT (no_labeled_variables)"; mutations.append(("transcript-spoofed-advisory", m, f"CASE_TRANSCRIPT_ADVISORY_CALL:{detail_case}"))
    m = copy.deepcopy(transcript_base); m["cases"][detail_case]["transcript_policy"]["stdout"][0] += "*"; mutations.append(("transcript-advisory-pattern", m, f"CASE_TRANSCRIPT_ADVISORY_PATTERN:{detail_case}"))

    descriptive_gate_path = "scripts/gates/descriptive-table-display-check.sh"
    concept_gate_path = "scripts/gates/concept-to-measure-check.sh"
    m = copy.deepcopy(manifest); m["external_gate_source_sha256"].pop(concept_gate_path); mutations.append(("external-source-key-missing", m, "EXTERNAL_GATE_SOURCE_KEY_SET_MISMATCH"))
    m = copy.deepcopy(manifest); m["external_gate_source_sha256"]["scripts/gates/extra-check.sh"] = "0" * 64; mutations.append(("external-source-key-extra", m, "EXTERNAL_GATE_SOURCE_KEY_SET_MISMATCH"))
    m = copy.deepcopy(manifest); value = m["external_gate_source_sha256"].pop(concept_gate_path); m["external_gate_source_sha256"]["scripts/gates/../concept-to-measure-check.sh"] = value; mutations.append(("external-source-path-escape", m, "EXTERNAL_GATE_SOURCE_PATH:scripts/gates/../concept-to-measure-check.sh"))
    m = copy.deepcopy(manifest); value = m["external_gate_source_sha256"].pop(concept_gate_path); m["external_gate_source_sha256"]["scripts/gates/descriptive-table-display-check-copy.sh"] = value; mutations.append(("external-source-wrong-path", m, "EXTERNAL_GATE_SOURCE_KEY_SET_MISMATCH"))
    m = copy.deepcopy(manifest); m["external_gate_source_sha256"][concept_gate_path] = "A" * 64; mutations.append(("external-source-digest-uppercase", m, f"EXTERNAL_GATE_SOURCE_DIGEST:{concept_gate_path}"))
    m = copy.deepcopy(manifest); m["external_gate_source_sha256"][concept_gate_path] = "0" * 63; mutations.append(("external-source-digest-malformed", m, f"EXTERNAL_GATE_SOURCE_DIGEST:{concept_gate_path}"))
    m = copy.deepcopy(manifest); m["external_gate_source_sha256"][concept_gate_path] = "0" * 64; mutations.append(("external-source-digest-wrong", m, f"EXTERNAL_GATE_SOURCE_DIGEST_MISMATCH:{concept_gate_path}"))
    m = copy.deepcopy(manifest); m["external_gate_source_sha256"][concept_gate_path], m["external_gate_source_sha256"][descriptive_gate_path] = m["external_gate_source_sha256"][descriptive_gate_path], m["external_gate_source_sha256"][concept_gate_path]; mutations.append(("external-source-digest-swap", m, f"EXTERNAL_GATE_SOURCE_DIGEST_MISMATCH:{concept_gate_path}"))

    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE].pop("diagnostic_provenance"); mutations.append(("pinned-provenance-missing", m, "PINNED_EXTERNAL_GATE_PROVENANCE_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["diagnostic_provenance"]["reason"] = "reworded"; mutations.append(("pinned-provenance-reworded", m, "PINNED_EXTERNAL_GATE_PROVENANCE_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["diagnostic_provenance"]["extra"] = "forged"; mutations.append(("pinned-provenance-extra", m, "PINNED_EXTERNAL_GATE_PROVENANCE_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE].pop("transcript_policy"); mutations.append(("pinned-transcript-missing", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"].pop(0); mutations.append(("pinned-advisory-line-missing", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"][0] = "ADVISORY: external gate not GREEN (non-fatal) — Phase 13 concept-to-measure bridge: INERT (reworded)"; mutations.append(("pinned-advisory-line-reworded", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"].pop(2); mutations.append(("pinned-detail-line-missing", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"][2] += " reworded"; mutations.append(("pinned-detail-line-reworded", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stderr"].append("forged"); mutations.append(("pinned-transcript-stderr-extra", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["extra"] = []; mutations.append(("pinned-transcript-field-extra", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"][0], m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"][1] = m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"][1], m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"][0]; mutations.append(("pinned-transcript-order", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    for field in PINNED_EXTERNAL_GATE_PROVENANCE:
        m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["diagnostic_provenance"].pop(field); mutations.append((f"pinned-provenance-field-missing-{field}", m, "PINNED_EXTERNAL_GATE_PROVENANCE_MISMATCH"))
        m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["diagnostic_provenance"][field] = f"reworded-{field}"; mutations.append((f"pinned-provenance-field-reworded-{field}", m, "PINNED_EXTERNAL_GATE_PROVENANCE_MISMATCH"))
    for field in PINNED_EXTERNAL_GATE_TRANSCRIPT:
        m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"].pop(field); mutations.append((f"pinned-transcript-field-missing-{field}", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    for index in range(len(PINNED_EXTERNAL_GATE_TRANSCRIPT["stdout"])):
        m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"].pop(index); mutations.append((f"pinned-transcript-line-missing-{index}", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
        m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"][index] += " reworded"; mutations.append((f"pinned-transcript-line-reworded-{index}", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))
    m = copy.deepcopy(manifest); m["cases"][PINNED_EXTERNAL_GATE_CASE]["transcript_policy"]["stdout"].pop(0); m["external_gate_source_sha256"].pop(concept_gate_path); mutations.append(("pinned-derived-key-set-shrink", m, "PINNED_EXTERNAL_GATE_TRANSCRIPT_MISMATCH"))

    pinned_ids = list(PINNED_STATE_TAIL_ASSERTION_CONTRACTS)
    m = copy.deepcopy(manifest); m["cases"].pop(pinned_ids[0]); mutations.append(("state-tail-pinned-case-deleted", m, "PINNED_STATE_TAIL_CASE_SET_MISMATCH"))
    for case_id in pinned_ids:
        case = manifest["cases"][case_id]
        policy = case.get("transcript_policy")
        if isinstance(policy, dict):
            for stream in ("stdout", "stderr"):
                items = policy.get(stream, [])
                for index in range(len(items)):
                    m = copy.deepcopy(manifest)
                    m["cases"][case_id]["transcript_policy"][stream].pop(index)
                    mutations.append((
                        f"state-tail-transcript-delete-{case_id}-{stream}-{index}", m,
                        f"PINNED_STATE_TAIL_CONTRACT_MISMATCH:{case_id}",
                    ))
                    m = copy.deepcopy(manifest)
                    target = m["cases"][case_id]["transcript_policy"][stream][index]
                    field = (
                        "value" if "value" in target else
                        "prefix" if "prefix" in target else "required_output_path"
                    )
                    target[field] = str(target[field]) + " reworded"
                    mutations.append((
                        f"state-tail-transcript-reword-{case_id}-{stream}-{index}", m,
                        f"PINNED_STATE_TAIL_CONTRACT_MISMATCH:{case_id}",
                    ))
                    if len(items) > 1:
                        other = index - 1 if index else 1
                        m = copy.deepcopy(manifest)
                        rows = m["cases"][case_id]["transcript_policy"][stream]
                        rows[index], rows[other] = rows[other], rows[index]
                        mutations.append((
                            f"state-tail-transcript-reorder-{case_id}-{stream}-{index}", m,
                            f"PINNED_STATE_TAIL_CONTRACT_MISMATCH:{case_id}",
                        ))
        postconditions = case.get("postconditions")
        if isinstance(postconditions, list):
            for index in range(len(postconditions)):
                m = copy.deepcopy(manifest)
                m["cases"][case_id]["postconditions"].pop(index)
                mutations.append((
                    f"state-tail-postcondition-delete-{case_id}-{index}", m,
                    f"PINNED_STATE_TAIL_CONTRACT_MISMATCH:{case_id}",
                ))
                m = copy.deepcopy(manifest)
                target = m["cases"][case_id]["postconditions"][index]
                target["path"] = target["path"].replace(".json", "-reworded.json")
                mutations.append((
                    f"state-tail-postcondition-reword-{case_id}-{index}", m,
                    f"PINNED_STATE_TAIL_CONTRACT_MISMATCH:{case_id}",
                ))
                if len(postconditions) > 1:
                    other = index - 1 if index else 1
                    m = copy.deepcopy(manifest)
                    rows = m["cases"][case_id]["postconditions"]
                    rows[index], rows[other] = rows[other], rows[index]
                    mutations.append((
                        f"state-tail-postcondition-reorder-{case_id}-{index}", m,
                        f"PINNED_STATE_TAIL_CONTRACT_MISMATCH:{case_id}",
                    ))

    phase20_id = "l4.chain.accept.complete-phase-20"
    phase20_history_matches = [
        index for index, item in enumerate(manifest["cases"][phase20_id]["postconditions"])
        if item.get("kind") == "json_absent"
        and item.get("path") == ".auto-research/state.json"
        and item.get("pointer") == "/review_evidence_history/30"
    ]
    if len(phase20_history_matches) != 1:
        failures.append("SELF_TEST_BASELINE_INVALID:phase20-review-history-closure")
    else:
        m = copy.deepcopy(manifest)
        m["cases"][phase20_id]["postconditions"].pop(phase20_history_matches[0])
        mutations.append((
            "completion-tail-phase20-history-closure-deleted", m,
            f"PINNED_COMPLETION_TAIL_CONTRACT_MISMATCH:{phase20_id}",
        ))
    for name, mutant, expected in mutations:
        got = validate(mutant, skill_dir, suite_runner=suite_runner)
        if expected not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:{name}:expected={expected}:got={got}")

    def altered_pin_value(value: object) -> object:
        if isinstance(value, bool):
            return not value
        if isinstance(value, int):
            return value + 1
        if isinstance(value, str):
            return value + "-mutated"
        if isinstance(value, list):
            return [*value, "__mutated__"]
        if isinstance(value, dict):
            return {**value, "__mutated__": True}
        return "__mutated__"

    def require_completion_pin(
        name: str, mutant: dict[str, object], expected: str,
    ) -> None:
        got = validate_pinned_completion_tail_cases(mutant)
        if expected not in got:
            failures.append(
                f"SELF_TEST_MUTATION_SURVIVED:{name}:expected={expected}:got={got}"
            )

    completion_ids = list(PINNED_COMPLETION_TAIL_ASSERTION_CONTRACTS)
    completion_baseline = validate_pinned_completion_tail_cases(manifest)
    if completion_baseline:
        failures.append(
            f"SELF_TEST_BASELINE_INVALID:completion-tail-pins:{completion_baseline}"
        )
    m = copy.deepcopy(manifest)
    m["cases"].pop(completion_ids[0])
    require_completion_pin(
        "completion-tail-case-deleted", m,
        "PINNED_COMPLETION_TAIL_CASE_SET_MISMATCH",
    )
    m = copy.deepcopy(manifest)
    m["cases"][completion_ids[0]]["execution_checkpoint"] = "state-tail"
    require_completion_pin(
        "completion-tail-case-retagged", m,
        "PINNED_COMPLETION_TAIL_CASE_SET_MISMATCH",
    )
    m = copy.deepcopy(manifest)
    m["cases"]["completion-tail-forged-extra"] = copy.deepcopy(
        m["cases"][completion_ids[0]]
    )
    require_completion_pin(
        "completion-tail-case-extra", m,
        "PINNED_COMPLETION_TAIL_CASE_SET_MISMATCH",
    )
    for case_id in completion_ids:
        expected = f"PINNED_COMPLETION_TAIL_CONTRACT_MISMATCH:{case_id}"
        case = manifest["cases"][case_id]
        for field in sorted(case):
            field_expected = (
                "PINNED_COMPLETION_TAIL_CASE_SET_MISMATCH"
                if field == "execution_checkpoint" else expected
            )
            m = copy.deepcopy(manifest)
            m["cases"][case_id].pop(field)
            require_completion_pin(
                f"completion-tail-field-delete-{case_id}-{field}", m, field_expected,
            )
            m = copy.deepcopy(manifest)
            m["cases"][case_id][field] = altered_pin_value(
                m["cases"][case_id][field]
            )
            require_completion_pin(
                f"completion-tail-field-alter-{case_id}-{field}", m, field_expected,
            )
        for field in sorted(CASE_FIELDS - set(case)):
            m = copy.deepcopy(manifest)
            m["cases"][case_id][field] = "__forged_optional_field__"
            require_completion_pin(
                f"completion-tail-field-add-{case_id}-{field}", m, expected,
            )
        policy = case.get("transcript_policy")
        if isinstance(policy, dict):
            for stream in ("stdout", "stderr"):
                rows = policy.get(stream, [])
                if not rows:
                    m = copy.deepcopy(manifest)
                    m["cases"][case_id]["transcript_policy"][stream].append(
                        {"kind": "exact", "value": "forged"}
                    )
                    require_completion_pin(
                        f"completion-tail-transcript-add-{case_id}-{stream}", m, expected,
                    )
                for index in range(len(rows)):
                    m = copy.deepcopy(manifest)
                    m["cases"][case_id]["transcript_policy"][stream].pop(index)
                    require_completion_pin(
                        f"completion-tail-transcript-delete-{case_id}-{stream}-{index}",
                        m, expected,
                    )
                    m = copy.deepcopy(manifest)
                    current = m["cases"][case_id]["transcript_policy"][stream][index]
                    m["cases"][case_id]["transcript_policy"][stream][index] = altered_pin_value(current)
                    require_completion_pin(
                        f"completion-tail-transcript-alter-{case_id}-{stream}-{index}",
                        m, expected,
                    )
                for index in range(max(0, len(rows) - 1)):
                    m = copy.deepcopy(manifest)
                    current = m["cases"][case_id]["transcript_policy"][stream]
                    current[index], current[index + 1] = current[index + 1], current[index]
                    require_completion_pin(
                        f"completion-tail-transcript-reorder-{case_id}-{stream}-{index}",
                        m, expected,
                    )
        postconditions = case.get("postconditions")
        if isinstance(postconditions, list):
            for index in range(len(postconditions)):
                m = copy.deepcopy(manifest)
                m["cases"][case_id]["postconditions"].pop(index)
                require_completion_pin(
                    f"completion-tail-postcondition-delete-{case_id}-{index}", m, expected,
                )
                m = copy.deepcopy(manifest)
                current = m["cases"][case_id]["postconditions"][index]
                m["cases"][case_id]["postconditions"][index] = altered_pin_value(current)
                require_completion_pin(
                    f"completion-tail-postcondition-alter-{case_id}-{index}", m, expected,
                )
            for index in range(max(0, len(postconditions) - 1)):
                m = copy.deepcopy(manifest)
                current = m["cases"][case_id]["postconditions"]
                current[index], current[index + 1] = current[index + 1], current[index]
                require_completion_pin(
                    f"completion-tail-postcondition-reorder-{case_id}-{index}", m, expected,
                )

    fixture_source = (skill_dir / "scripts/auto-research-fixture-test.sh").read_text()
    checkpoint_line = "harness_validate_results --checkpoint state-tail"
    last_anchor = manifest["cases"]["l2.p0.reject.partial-scan"]["anchor"]
    checkpoint_mutations = (
        ("checkpoint-call-delete", fixture_source.replace(checkpoint_line + "\n", "", 1), "EXECUTION_CHECKPOINT_CALL_MISSING:state-tail"),
        ("checkpoint-call-duplicate", fixture_source.replace(checkpoint_line, checkpoint_line + "\n" + checkpoint_line, 1), "EXECUTION_CHECKPOINT_CALL_DUPLICATE:state-tail"),
        ("checkpoint-call-rename", fixture_source.replace(checkpoint_line, "harness_validate_results --checkpoint renamed", 1), "EXECUTION_CHECKPOINT_CALL_UNKNOWN:renamed"),
        ("checkpoint-call-before-last-anchor", fixture_source.replace(checkpoint_line + "\n", "", 1).replace(last_anchor, checkpoint_line + "\n" + last_anchor, 1), "EXECUTION_CHECKPOINT_CALL_ORDER:state-tail"),
        ("checkpoint-call-after-marker", fixture_source.replace(checkpoint_line + "\n", "", 1).replace(STATE_TAIL_MARKER, STATE_TAIL_MARKER + "\n" + checkpoint_line, 1), "EXECUTION_CHECKPOINT_CALL_ORDER:state-tail"),
        ("checkpoint-marker-delete", fixture_source.replace(STATE_TAIL_MARKER, "", 1), "L4_COMPLETION_TAIL_MARKER_COUNT"),
        ("checkpoint-marker-duplicate", fixture_source.replace(STATE_TAIL_MARKER, STATE_TAIL_MARKER + "\n" + STATE_TAIL_MARKER, 1), "L4_COMPLETION_TAIL_MARKER_COUNT"),
    )
    for name, source, expected in checkpoint_mutations:
        got = validate_execution_checkpoint_calls(manifest, source)
        if expected not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:{name}:expected={expected}:got={got}")

    decoys = {
        "comment": "# harness_validate_results --checkpoint state-tail",
        "quoted-string": "printf '%s\\n' 'harness_validate_results --checkpoint state-tail'",
        "quoted-heredoc": "cat <<'EOF'\nharness_validate_results --checkpoint state-tail\nEOF",
        "unquoted-heredoc": "cat <<EOF\nharness_validate_results --checkpoint state-tail\nEOF",
        "uncalled-function": "checkpoint_decoy() {\n  harness_validate_results --checkpoint state-tail\n}",
        "false-branch": "if false; then\n  harness_validate_results --checkpoint state-tail\nfi",
        "after-exit": "exit 0\nharness_validate_results --checkpoint state-tail",
        "false-and": "false && harness_validate_results --checkpoint state-tail",
        "true-or": "true || harness_validate_results --checkpoint state-tail",
        "subshell": "( harness_validate_results --checkpoint state-tail )",
        "brace": "{ harness_validate_results --checkpoint state-tail; }",
        "pipeline": "harness_validate_results --checkpoint state-tail | cat",
        "sequence": "true; harness_validate_results --checkpoint state-tail",
        "background": "harness_validate_results --checkpoint state-tail &",
        "command-substitution": "value=$(harness_validate_results --checkpoint state-tail)",
        "case": "case never in always) harness_validate_results --checkpoint state-tail ;; esac",
    }
    for name, decoy in decoys.items():
        source = fixture_source.replace(checkpoint_line, decoy, 1)
        got = validate_execution_checkpoint_calls(manifest, source)
        if hashlib.sha256(source.encode()).hexdigest() == PINNED_REVIEWED_FIXTURE_SHA256:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:checkpoint-decoy-content-{name}")
        # The descriptive line/cardinality check is intentionally secondary;
        # whole-fixture authority, not partial shell interpretation, kills
        # nested/heredoc/dead-code decoys.
    for name, source in (
        ("redefine-join", fixture_source.replace(POST_STOP20_START_MARKER, "harness_validate_results() { :; }\n" + POST_STOP20_START_MARKER, 1)),
        ("exec-discard", fixture_source.replace(POST_STOP20_START_MARKER, "exec >/dev/null 2>&1\n" + POST_STOP20_START_MARKER, 1)),
        ("trap", fixture_source.replace(POST_STOP20_START_MARKER, "trap ':' EXIT\n" + POST_STOP20_START_MARKER, 1)),
        ("set-plus-e", fixture_source.replace(POST_STOP20_START_MARKER, "set +e\n" + POST_STOP20_START_MARKER, 1)),
        ("early-exit", fixture_source.replace(POST_STOP20_START_MARKER, "exit 0\n" + POST_STOP20_START_MARKER, 1)),
    ):
        if hashlib.sha256(source.encode()).hexdigest() == PINNED_REVIEWED_FIXTURE_SHA256:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:whole-fixture-{name}")
    receipt_mutations = (
        ("checkpoint-redirect", fixture_source.replace(checkpoint_line, checkpoint_line + " >/dev/null", 1), "EXECUTION_CHECKPOINT_RECEIPT_CALL_COUNT:state-tail"),
        ("progress-delete", fixture_source.replace('progress "state-tail authoritative harness assertions passed"\n', "", 1), "EXECUTION_CHECKPOINT_PROGRESS_COUNT:state-tail"),
        ("progress-duplicate", fixture_source.replace('progress "state-tail authoritative harness assertions passed"', 'progress "state-tail authoritative harness assertions passed"\nprogress "state-tail authoritative harness assertions passed"', 1), "EXECUTION_CHECKPOINT_PROGRESS_COUNT:state-tail"),
        ("final-redirect", fixture_source.replace("\nharness_validate_results\n\nEND_TS", "\nharness_validate_results >/dev/null\n\nEND_TS", 1), "EXECUTION_FINAL_RECEIPT_CALL_COUNT"),
    )
    for name, source, expected in receipt_mutations:
        got = validate_execution_checkpoint_calls(manifest, source)
        if expected not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:{name}:expected={expected}:got={got}")

    inventory_mutations: list[tuple[str, str, str]] = []
    stdout_control = 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" >/dev/null'
    for name, replacement in (
        ("discard-stdout-stderr", 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" >/dev/null 2>&1'),
        ("discard-fd-explicit", 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" 1>/dev/null 2>/dev/null'),
        ("discard-reordered", 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" 2>/dev/null >/dev/null'),
        ("discard-stderr-to-stdout", 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" 2>/dev/null 1>&2'),
        ("discard-ampersand", 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" &>/dev/null'),
        ("discard-legacy-ampersand", 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" >&/dev/null'),
        ("discard-continuation", 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" >\\\n/dev/null 2>&1'),
        ("wrapped-group", '{ bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ"; } >/dev/null 2>&1'),
        ("wrapped-subshell", '( bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" ) >/dev/null 2>&1'),
    ):
        inventory_mutations.append((name, fixture_source.replace(stdout_control, replacement, 1), "POST_STOP20_STREAM_POLICY:p10.hash.init"))
    semantic_control = 'expect_reject l2.p0.state.reject.hash-check-stale-safety "$HASH_STALE_PROJ" -- \\\n  bash "$SCRIPT_DIR/auto-research-state.sh" hash-check "$HASH_STALE_PROJ"'
    inventory_mutations.append((
        "semantic-raw-bash",
        fixture_source.replace(semantic_control, 'bash "$SCRIPT_DIR/auto-research-state.sh" hash-check "$HASH_STALE_PROJ"', 1),
        "POST_STOP20_SEMANTIC_ROW:p10.hash.reject-stale",
    ))
    inventory_mutations.append((
        "uninventoried-token-decoy",
        fixture_source.replace(POST_STOP20_START_MARKER, POST_STOP20_START_MARKER + "\n# auto-research-state.sh decoy", 1),
        "POST_STOP20_UNINVENTORIED_TOKEN:auto-research-state.sh",
    ))
    for name, decoy in (
        ("comment", '# bash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ" >/dev/null 2>&1'),
        ("quoted-string", 'printf \'%s\\n\' \'bash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ" >/dev/null 2>&1\''),
        ("heredoc", 'cat <<\'EOF\'\nbash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ" >/dev/null 2>&1\nEOF'),
        ("uncalled-function", 'inventory_decoy() { bash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ" >/dev/null 2>&1; }'),
        ("dead-branch", 'if false; then bash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ" >/dev/null 2>&1; fi'),
    ):
        inventory_mutations.append((
            f"uninventoried-{name}",
            fixture_source.replace(POST_STOP20_START_MARKER, POST_STOP20_START_MARKER + "\n" + decoy, 1),
            "POST_STOP20_UNINVENTORIED_TOKEN:auto-research-state.sh",
        ))
    for name, source, expected in inventory_mutations:
        got = validate_post_stop20_inventory(manifest, source)
        if expected not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:{name}:expected={expected}:got={got}")

    # The inventory lower bound is the exact end of the unchanged STOP20
    # branch, not the movable descriptive marker. Exercise the structural
    # validator directly so whole-fixture digest authority cannot mask a
    # boundary, interval, overlap, or masking defect.
    inventory_stanzas, inventory_stanza_errors = extract_post_stop20_stanzas(fixture_source)
    if inventory_stanza_errors or len(inventory_stanzas) != 90:
        failures.append(
            "SELF_TEST_BASELINE_INVALID:post-stop20-stanzas:"
            f"errors={inventory_stanza_errors}:count={len(inventory_stanzas)}"
        )
    else:
        first_id, first_stanza, _, _ = inventory_stanzas[0]
        first_l4 = next((item for item in inventory_stanzas if item[0] == "l4.f9.init"), None)
        first_begin = f"# POST_STOP20_CALL_BEGIN {first_id}\n"
        first_end = f"# POST_STOP20_CALL_END {first_id}\n"
        first_command = 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$HASH_STALE_PROJ" >/dev/null\n'

        direct_inventory_mutations: list[tuple[str, str, str]] = []
        moved_first = fixture_source.replace(first_stanza, "", 1).replace(
            POST_STOP20_START_MARKER,
            first_stanza + POST_STOP20_START_MARKER,
            1,
        )
        direct_inventory_mutations.append((
            "inventory-first-stanza-before-start",
            moved_first,
            f"POST_STOP20_STANZA_BEFORE_START:{first_id}",
        ))
        direct_inventory_mutations.extend((
            (
                "inventory-pre-marker-dual-discard",
                fixture_source.replace(
                    POST_STOP20_START_MARKER,
                    'bash "$SCRIPT_DIR/auto-research-state.sh" next "$PROJ" >/dev/null 2>&1\n'
                    + POST_STOP20_START_MARKER,
                    1,
                ),
                "POST_STOP20_UNINVENTORIED_TOKEN:auto-research-state.sh",
            ),
            (
                "inventory-pre-marker-token-comment",
                fixture_source.replace(
                    POST_STOP20_START_MARKER,
                    "# auto-research-state.sh pre-marker production-token decoy\n"
                    + POST_STOP20_START_MARKER,
                    1,
                ),
                "POST_STOP20_UNINVENTORIED_TOKEN:auto-research-state.sh",
            ),
            (
                "inventory-lower-boundary-insertion",
                fixture_source.replace(
                    POST_STOP20_START_MARKER,
                    "# lower-boundary insertion\n" + POST_STOP20_START_MARKER,
                    1,
                ),
                "POST_STOP20_START_NOT_ATTACHED_TO_FIXED_BOUNDARY",
            ),
            (
                "inventory-start-marker-duplicate",
                fixture_source.replace(
                    POST_STOP20_START_MARKER,
                    POST_STOP20_START_MARKER + "\n" + POST_STOP20_START_MARKER,
                    1,
                ),
                "POST_STOP20_START_MARKER_COUNT",
            ),
            (
                "inventory-start-marker-moved",
                fixture_source.replace(POST_STOP20_START_MARKER + "\n\n", "", 1).replace(
                    first_stanza,
                    first_stanza + POST_STOP20_START_MARKER + "\n\n",
                    1,
                ),
                "POST_STOP20_START_NOT_ATTACHED_TO_FIXED_BOUNDARY",
            ),
            (
                "inventory-l4-marker-duplicate",
                fixture_source.replace(
                    STATE_TAIL_MARKER,
                    STATE_TAIL_MARKER + "\n" + STATE_TAIL_MARKER,
                    1,
                ),
                "L4_COMPLETION_TAIL_MARKER_COUNT",
            ),
        ))

        p10_outside = fixture_source.replace(STATE_TAIL_MARKER + "\n", "", 1).replace(
            POST_STOP20_START_MARKER + "\n",
            POST_STOP20_START_MARKER + "\n\n" + STATE_TAIL_MARKER + "\n",
            1,
        )
        direct_inventory_mutations.append((
            "inventory-p10-outside-region",
            p10_outside,
            f"POST_STOP20_P10_STANZA_OUTSIDE_REGION:{first_id}",
        ))
        p10_crossing = fixture_source.replace(STATE_TAIL_MARKER + "\n", "", 1).replace(
            first_command,
            first_command + STATE_TAIL_MARKER + "\n",
            1,
        )
        direct_inventory_mutations.append((
            "inventory-p10-crosses-l4",
            p10_crossing,
            f"POST_STOP20_STANZA_CROSSES_L4:{first_id}",
        ))
        if first_l4 is None:
            failures.append("SELF_TEST_BASELINE_INVALID:post-stop20-l4-stanza")
        else:
            l4_id, l4_stanza, _, _ = first_l4
            l4_command = 'bash "$SCRIPT_DIR/auto-research-state.sh" init "$F9_PROJ" >/dev/null\n'
            l4_outside = fixture_source.replace(STATE_TAIL_MARKER + "\n", "", 1).replace(
                l4_stanza,
                l4_stanza + STATE_TAIL_MARKER + "\n",
                1,
            )
            direct_inventory_mutations.append((
                "inventory-l4-outside-region",
                l4_outside,
                f"POST_STOP20_L4_STANZA_OUTSIDE_REGION:{l4_id}",
            ))
            l4_crossing = fixture_source.replace(STATE_TAIL_MARKER + "\n", "", 1).replace(
                l4_command,
                l4_command + STATE_TAIL_MARKER + "\n",
                1,
            )
            direct_inventory_mutations.append((
                "inventory-l4-crosses-marker",
                l4_crossing,
                f"POST_STOP20_STANZA_CROSSES_L4:{l4_id}",
            ))

        overlapping = fixture_source.replace(
            first_stanza,
            first_stanza.replace(
                first_begin,
                first_begin + "# POST_STOP20_CALL_BEGIN nested.overlap\n",
                1,
            ).replace(
                first_end,
                "# POST_STOP20_CALL_END nested.overlap\n" + first_end,
                1,
            ),
            1,
        )
        direct_inventory_mutations.append((
            "inventory-stanza-overlap",
            overlapping,
            f"POST_STOP20_STANZA_OVERLAP:{first_id}:nested.overlap",
        ))
        mask_safety = fixture_source.replace(first_stanza, "", 1).replace(
            STOP20_BOUNDARY,
            first_stanza + STOP20_BOUNDARY,
            1,
        )
        direct_inventory_mutations.append((
            "inventory-mask-negative-index",
            mask_safety,
            "POST_STOP20_MASK_RANGE_INVALID",
        ))
        for name, source, expected in direct_inventory_mutations:
            got = validate_post_stop20_inventory(manifest, source)
            if expected not in got:
                failures.append(
                    f"SELF_TEST_MUTATION_SURVIVED:{name}:expected={expected}:got={got}"
                )

    inventory_manifest_mutations: list[tuple[str, dict[str, object], str]] = []
    m = copy.deepcopy(manifest); m["post_stop20_call_inventory"]["rows"][0]["source_order"] = 2; inventory_manifest_mutations.append(("inventory-row-order", m, "POST_STOP20_ROW_ORDER:1"))
    m = copy.deepcopy(manifest); m["post_stop20_call_inventory"]["rows"][0]["classification"] = "l4_prerequisite"; inventory_manifest_mutations.append(("inventory-row-class", m, "POST_STOP20_L4_PREREQUISITE_ROW:p10.hash.init"))
    m = copy.deepcopy(manifest); m["post_stop20_call_inventory"]["rows"].pop(); inventory_manifest_mutations.append(("inventory-row-delete", m, "POST_STOP20_INVENTORY_ROW_COUNT"))
    m = copy.deepcopy(manifest); m["post_stop20_call_inventory"]["rows"].append(copy.deepcopy(m["post_stop20_call_inventory"]["rows"][-1])); inventory_manifest_mutations.append(("inventory-row-duplicate", m, "POST_STOP20_INVENTORY_ROW_COUNT"))
    for name, mutant, expected in inventory_manifest_mutations:
        got = validate_post_stop20_inventory(mutant, fixture_source)
        if expected not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:{name}:expected={expected}:got={got}")
    m = copy.deepcopy(manifest); m["reviewed_test_sources"][REVIEWED_FIXTURE_PATH] = "0" * 64
    if "REVIEWED_TEST_SOURCES_PRODUCTION_SET_MISMATCH" not in validate_reviewed_test_sources(m, skill_dir):
        failures.append("SELF_TEST_MUTATION_SURVIVED:reviewed-source-manifest-digest")
    with tempfile.TemporaryDirectory(prefix="coverage-reviewed-source-") as temp_dir:
        root = Path(temp_dir)
        target = root / REVIEWED_FIXTURE_PATH
        target.parent.mkdir(parents=True)
        mutant_fixture = fixture_source.replace("set -euo pipefail", "set +e", 1)
        target.write_text(mutant_fixture, encoding="utf-8")
        got = validate_reviewed_test_sources(manifest, root)
        if f"REVIEWED_TEST_SOURCE_DIGEST_MISMATCH:{REVIEWED_FIXTURE_PATH}" not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:reviewed-fixture-only:got={got}")
        coordinated = copy.deepcopy(manifest)
        coordinated["reviewed_test_sources"][REVIEWED_FIXTURE_PATH] = file_digest(target)
        got = validate_reviewed_test_sources(coordinated, root)
        if "REVIEWED_TEST_SOURCES_PROJECTION_PIN_MISMATCH" not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:reviewed-fixture-manifest:got={got}")
        leaf_root = root / "leaf-symlink"
        (leaf_root / "scripts").mkdir(parents=True)
        (leaf_root / REVIEWED_FIXTURE_PATH).symlink_to(skill_dir / REVIEWED_FIXTURE_PATH)
        got = validate_reviewed_test_sources(manifest, leaf_root)
        if f"REVIEWED_TEST_SOURCE_FILE:{REVIEWED_FIXTURE_PATH}" not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:reviewed-static-leaf-symlink:got={got}")
        component_root = root / "component-symlink"
        component_root.mkdir()
        (component_root / "scripts").symlink_to(skill_dir / "scripts")
        got = validate_reviewed_test_sources(manifest, component_root)
        if f"REVIEWED_TEST_SOURCE_FILE:{REVIEWED_FIXTURE_PATH}" not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:reviewed-static-component-symlink:got={got}")
        fifo_root = root / "fifo"
        (fifo_root / "scripts").mkdir(parents=True)
        os.mkfifo(fifo_root / REVIEWED_FIXTURE_PATH)
        got = validate_reviewed_test_sources(manifest, fifo_root)
        if f"REVIEWED_TEST_SOURCE_FILE:{REVIEWED_FIXTURE_PATH}" not in got:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:reviewed-static-fifo:got={got}")
    coordinated = copy.deepcopy(manifest)
    coordinated_source = fixture_source.replace(stdout_control, stdout_control.replace("init", "init ", 1), 1)
    stanzas, _ = extract_post_stop20_stanzas(coordinated_source)
    coordinated["post_stop20_call_inventory"]["rows"][0]["stanza_sha256"] = hashlib.sha256(stanzas[0][1].encode()).hexdigest()
    got = validate_post_stop20_inventory(coordinated, coordinated_source)
    if "POST_STOP20_INVENTORY_PIN_MISMATCH" not in got:
        failures.append(f"SELF_TEST_MUTATION_SURVIVED:inventory-fixture-manifest:got={got}")
    for name, payload in (
        ("duplicate-json-key", '{"schema_version":"1.2.0","schema_version":"1.2.0"}'),
        ("nan-json", '{"value":NaN}'),
        ("infinity-json", '{"value":Infinity}'),
    ):
        try:
            strict_json_loads(payload, name)
        except ValueError:
            pass
        else:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:{name}")

    try:
        external_inventory = inventory_text((skill_dir / "scripts/auto-research-verify.sh").read_text())
    except InventoryError as exc:
        failures.append(f"SELF_TEST_EXTERNAL_PIN_INVENTORY_FAILED:{exc}")
        external_inventory = {"obligations": []}
    ambiguous_inventory = copy.deepcopy(external_inventory)
    concept_rows = [
        row for row in ambiguous_inventory.get("obligations", [])
        if "Phase 13 concept-to-measure bridge" in row.get("labels", [])
    ]
    if len(concept_rows) != 1:
        failures.append("SELF_TEST_EXTERNAL_PIN_FIXTURE_INVALID:concept-advisory")
    else:
        ambiguous_inventory["obligations"].append(copy.deepcopy(concept_rows[0]))
        _, ambiguous_errors = derive_external_gate_source_paths(manifest, ambiguous_inventory)
        if f"EXTERNAL_GATE_SOURCE_ADVISORY_RESOLUTION:{PINNED_EXTERNAL_GATE_CASE}" not in ambiguous_errors:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:external-source-ambiguous-advisory:got={ambiguous_errors}")

    with tempfile.TemporaryDirectory(prefix="coverage-external-source-self-test-") as temp_dir:
        temp_skill = Path(temp_dir) / "scholar-auto-research"
        for relative in (concept_gate_path, descriptive_gate_path):
            destination = temp_skill / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((skill_dir / relative).read_bytes())
        baseline_errors = validate_external_gate_source_map(manifest, temp_skill, external_inventory)
        if baseline_errors:
            failures.append(f"SELF_TEST_VALID_CONTROL_REJECTED:external-source-temp-baseline:got={baseline_errors}")

        concept_temp = temp_skill / concept_gate_path
        descriptive_temp = temp_skill / descriptive_gate_path
        concept_bytes = concept_temp.read_bytes()
        descriptive_bytes = descriptive_temp.read_bytes()
        concept_temp.write_bytes(concept_bytes + b"\n# stale-digest mutation\n")
        stale_errors = validate_external_gate_source_map(manifest, temp_skill, external_inventory)
        expected = f"EXTERNAL_GATE_SOURCE_DIGEST_MISMATCH:{concept_gate_path}"
        if expected not in stale_errors:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:external-source-bytes-stale-digest:got={stale_errors}")
        concept_temp.write_bytes(descriptive_bytes)
        descriptive_temp.write_bytes(concept_bytes)
        swap_errors = validate_external_gate_source_map(manifest, temp_skill, external_inventory)
        if not all(
            f"EXTERNAL_GATE_SOURCE_DIGEST_MISMATCH:{relative}" in swap_errors
            for relative in (concept_gate_path, descriptive_gate_path)
        ):
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:external-source-byte-swap:got={swap_errors}")
        concept_temp.write_bytes(concept_bytes)
        descriptive_temp.write_bytes(descriptive_bytes)
        descriptive_temp.unlink()
        descriptive_temp.symlink_to(concept_temp)
        symlink_errors = validate_external_gate_source_map(manifest, temp_skill, external_inventory)
        expected = f"EXTERNAL_GATE_SOURCE_FILE:{descriptive_gate_path}"
        if expected not in symlink_errors:
            failures.append(f"SELF_TEST_MUTATION_SURVIVED:external-source-symlink:got={symlink_errors}")
    runner_source = suite_runner.read_text(errors="replace")
    runner_line = next((line for line in runner_source.splitlines() if line.startswith('run_test "contract-lint" ')), "")
    if not runner_line:
        failures.append("SELF_TEST_RUNNER_FIXTURE_INVALID:contract-lint")
    else:
        with tempfile.TemporaryDirectory(prefix="coverage-runner-self-test-") as temp_dir:
            runner_mutations = (
                (
                    "runner-path",
                    runner_source.replace(runner_line, 'run_test "contract-lint" "$SKILL_TESTS/test-harness.sh"', 1),
                    "RUNNER_PATH_MISMATCH:contract-lint",
                ),
                (
                    "runner-unparsed",
                    runner_source.replace(runner_line, runner_line.replace("run_test", "run_unknown", 1), 1),
                    "RUNNER_INVOCATION_UNPARSED",
                ),
                (
                    "runner-unknown-path",
                    runner_source.replace(runner_line, 'run_test "contract-lint" "$UNKNOWN_ROOT/contract-lint.sh"', 1),
                    "RUNNER_PATH_UNPARSED:contract-lint:$UNKNOWN_ROOT/contract-lint.sh",
                ),
                (
                    "runner-skill-dir-path",
                    runner_source.replace(runner_line, 'run_test "contract-lint" "$SKILL_DIR/scripts/auto-research-contract-lint.sh"', 1),
                    "RUNNER_PATH_UNPARSED:contract-lint:$SKILL_DIR/scripts/auto-research-contract-lint.sh",
                ),
                (
                    "runner-braced-skill-dir-path",
                    runner_source.replace(runner_line, 'run_test "contract-lint" "${SKILL_DIR}/scripts/auto-research-contract-lint.sh"', 1),
                    "RUNNER_PATH_UNPARSED:contract-lint:${SKILL_DIR}/scripts/auto-research-contract-lint.sh",
                ),
                (
                    "runner-duplicate",
                    runner_source + "\n" + runner_line + "\n",
                    "RUNNER_LABEL_DUPLICATE:contract-lint",
                ),
            )
            for name, runner_mutant, expected in runner_mutations:
                mutant_path = Path(temp_dir) / f"{name}.sh"
                mutant_path.write_text(runner_mutant, encoding="utf-8")
                got = validate(manifest, skill_dir, suite_runner=mutant_path)
                if not any(error == expected or error.startswith(expected + ":") for error in got):
                    failures.append(f"SELF_TEST_MUTATION_SURVIVED:{name}:expected={expected}:got={got}")
    try:
        external_self_test()
    except InventoryError as exc:
        failures.append(f"SELF_TEST_EXTERNAL_INVENTORY_FAILED:{exc}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skill-dir", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--suite-runner", type=Path)
    parser.add_argument("--repo-root", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    skill_dir = args.skill_dir.resolve()
    manifest_path = args.manifest or skill_dir / "tests/coverage-manifest.json"
    suite_runner = args.suite_runner.resolve() if args.suite_runner else None
    try:
        manifest = strict_json_loads(manifest_path.read_text(), str(manifest_path))
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"COVERAGE_MANIFEST_READ_ERROR: {exc}", file=sys.stderr)
        return 1
    try:
        errors = validate(manifest, skill_dir, suite_runner=suite_runner, repo_root=args.repo_root)
    except DiagnosticSourceParseError as exc:
        errors = [f"DIAGNOSTIC_SOURCE_PARSE_ERROR:{exc}"]
    if args.self_test and not any(error.startswith("DIAGNOSTIC_SOURCE_PARSE_ERROR:") for error in errors):
        if not suite_runner:
            print("COVERAGE_SELF_TEST_REQUIRES_SUITE_RUNNER", file=sys.stderr)
            return 1
        errors.extend(run_self_test(manifest, skill_dir, suite_runner))
    if errors:
        print("coverage manifest lint: FAIL", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    phase_count = sum(manifest["phase_invariant_counts"].values())
    print("coverage manifest lint: PASS")
    print(f"  findings={len(FINDINGS)} phases={len(PHASES)} phase_invariants={phase_count}")
    print(f"  external_gates={manifest['external_gate_invariant_count']} cases={len(manifest['cases'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
