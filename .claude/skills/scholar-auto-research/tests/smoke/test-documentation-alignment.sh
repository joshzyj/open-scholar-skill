#!/usr/bin/env bash
# Regression for F17/F19: user-facing paths, phase ownership, recovery commands,
# and enforced gate documentation must agree with the machine contract.
set -euo pipefail

SKILL_DIR="${SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
REGISTRY="$SKILL_DIR/references/documentation-registry.json"
[ -f "$REGISTRY" ] || { echo "FAIL: missing references/documentation-registry.json" >&2; exit 1; }

python3 - "$SKILL_DIR" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
skill = (root / "SKILL.md").read_text()
contract = json.loads((root / "references/phase-contract.json").read_text())
registry = json.loads((root / "references/documentation-registry.json").read_text())
by_id = {str(p["id"]): p for p in contract["phases"]}
errors = []

if "rather than raw registry precision or scientific notation" in skill:
    errors.append("SKILL.md categorically forbids scientific notation instead of honoring numeric_reporting_policy")

stale = [
    "$PROJ/{design,analysis,reviews,logs,verify,...}/",
    "$PROJ/drafts/manuscript-final-[slug]-[date].{md,docx,tex,pdf}",
    "$PROJ/submission/manuscript-submission-[slug]-[date].*",
    "Replication package (Phase 19–20)",
]
for text in stale:
    if text in skill:
        errors.append(f"SKILL.md retains stale output text: {text}")
for text in (
    "$PROJ/review/",
    "$PROJ/verify/",
    "$PROJ/quality/",
    "$PROJ/final/manuscript-final.{md,docx,tex,pdf}",
    "$PROJ/submission/manuscript-submission.{md,docx,tex,pdf}",
    "Replication package (Phase 17)",
):
    if text not in skill:
        errors.append(f"SKILL.md missing canonical output text: {text}")

phase15 = skill[skill.index("## Phase 15 Citation And Claim Support"):skill.index("## Phase 16 Ethics And Open Science")]
if 'auto-research-verify.sh 14 "$PROJ"' not in phase15:
    errors.append("Phase 15 prerequisite must rerun Phase 14")
if 'auto-research-verify.sh 13 "$PROJ"' in phase15:
    errors.append("Phase 15 prerequisite still reruns Phase 13")

outputs = registry.get("canonical_outputs", {})
expected = {
    "review": ("review/", ["6", "7", "9"]),
    "verification": ("verify/", ["14"]),
    "quality": ("quality/", ["18"]),
    "final": ("final/manuscript-final.{md,docx,tex,pdf}", ["19"]),
    "submission": ("submission/manuscript-submission.{md,docx,tex,pdf}", ["20"]),
    "replication": ("replication-package/", ["17"]),
    "review_evidence": ("review-evidence/", ["6", "7", "9", "14", "18", "20"]),
}
for key, (path, owners) in expected.items():
    item = outputs.get(key, {})
    if item.get("path") != path or item.get("owner_phases") != owners:
        errors.append(f"documentation registry mismatch for {key}")
    prefix = path.split("{", 1)[0]
    if not prefix.endswith("/"):
        prefix = prefix.rsplit("/", 1)[0] + "/"
    for owner in item.get("owner_phases", []):
        phase_outputs = by_id.get(str(owner), {}).get("required_outputs", [])
        if not any(str(output).startswith(prefix) for output in phase_outputs):
            errors.append(f"registry owner Phase {owner} has no required output under {prefix}")
for path in ("final/manuscript-final.md", "final/manuscript-final.docx", "final/manuscript-final.tex", "final/manuscript-final.pdf"):
    if path not in by_id["19"]["required_outputs"]:
        errors.append(f"Phase 19 contract missing {path}")
for path in ("submission/manuscript-submission.md", "submission/manuscript-submission.docx", "submission/manuscript-submission.tex", "submission/manuscript-submission.pdf"):
    if path not in by_id["20"]["required_outputs"]:
        errors.append(f"Phase 20 contract missing {path}")

protocols = registry.get("protocols", {})
evidence = protocols.get("review_evidence", {})
if evidence != {
    "contract": "references/review-evidence-contract.md",
    "state_schema": "1.3.0",
    "default_profile": "normal",
    "default_assurance": "process_recorded",
    "migration_ids": ["f09-portable-review-evidence-v1", "f09-review-evidence-closure-v2"],
}:
    errors.append("documentation registry review-evidence protocol metadata is incomplete")
for doc in ("references/state-contract.md", "references/review-evidence-contract.md"):
    text = (root / doc).read_text()
    if '"<eligible-id-from-migration-status>"' not in text:
        errors.append(f"{doc} migration example must consume the ID reported by migration-status")
    if '"$PROJ" f09-' in text:
        errors.append(f"{doc} generic migration example hardcodes a predecessor-specific ID")
runtime = protocols.get("runtime", {})
if runtime != {
    "manifest": "references/runtime-dependencies.json",
    "preflight": "scripts/runtime-preflight.py",
}:
    errors.append("documentation registry runtime protocol metadata is incomplete")

gate = registry.get("gates", {}).get("regression-table-display-check.sh", {})
if gate.get("enforced_phases") != ["13", "18"] or gate.get("input") != "project_dir" or gate.get("recovery_phase") != "13":
    errors.append("regression-table display gate registry metadata is incomplete")
if gate.get("verdicts") != {"GREEN": 0, "RED": 1, "YELLOW": 2, "INERT": 3}:
    errors.append("regression-table display gate verdict registry is incorrect")
for doc in ("references/manuscript-drafting-contract.md", "references/quality-gate.md"):
    text = (root / doc).read_text()
    if "regression-table-display-check.sh" not in text:
        errors.append(f"{doc} does not document regression-table-display-check.sh")

# CASE_ID: f20.documentation.reject-v1-locked-claim-examples
claim_docs = {
    doc: (root / doc).read_text()
    for doc in (
        "references/manuscript-drafting-contract.md",
        "references/verification-contract.md",
        "references/citation-claim-contract.md",
    )
}
for doc, text in claim_docs.items():
    forbidden = {
        "reader-facing registry claim source": '"covered_sources": ["tables/results-registry.csv"]',
        "reader-facing CSV-only claim rule": "row-level claims for every reader-facing locked CSV result source",
        "value-containing anchor rule": "a manuscript anchor containing those values",
        "legacy row-index claim identity": '"claim_id": "tables/table1.csv#0:S1"',
        "empty locked-claim example": '"locked_result_claims": []',
        "vacuous Stage 2 example": '"claims_scanned": 0',
        "conditional results-registry display exception": "It may be discussed or displayed only when the article's substantive object is a registry/preregistration system",
    }
    for label, fragment in forbidden.items():
        if fragment in text:
            errors.append(f"{doc} retains {label}: {fragment}")

if errors:
    for error in errors:
        print(f"FAIL: {error}")
    raise SystemExit(1)
PY

if [[ "${SCHOLAR_DOCUMENTATION_ALIGNMENT_PROBE:-0}" != "1" ]]; then
  PROBE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scholar-doc-alignment.XXXXXX")"
  trap 'rm -rf "$PROBE_ROOT"' EXIT
  cp -R "$SKILL_DIR" "$PROBE_ROOT/skill"
  printf '\nIt may be discussed or displayed only when the article\047s substantive object is a registry/preregistration system\n' \
    >> "$PROBE_ROOT/skill/references/manuscript-drafting-contract.md"
  set +e
  SCHOLAR_DOCUMENTATION_ALIGNMENT_PROBE=1 \
    SCHOLAR_AUTO_RESEARCH_TEST_SKILL_DIR="$PROBE_ROOT/skill" \
    bash "$PROBE_ROOT/skill/tests/smoke/test-documentation-alignment.sh" \
    >"$PROBE_ROOT/probe.out" 2>&1
  PROBE_RC=$?
  set -e
  [ "$PROBE_RC" -ne 0 ] || { echo "FAIL: copied documentation probe accepted the conditional registry-display exception" >&2; exit 1; }
  grep -F "retains conditional results-registry display exception" "$PROBE_ROOT/probe.out" >/dev/null \
    || { echo "FAIL: copied documentation probe rejected for the wrong reason" >&2; cat "$PROBE_ROOT/probe.out" >&2; exit 1; }
fi

echo "PASS: documented paths, owners, recovery, and display-gate metadata align"
