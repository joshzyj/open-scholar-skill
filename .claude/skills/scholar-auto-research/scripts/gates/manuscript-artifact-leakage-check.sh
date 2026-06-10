#!/usr/bin/env bash
# manuscript-artifact-leakage-check.sh — block pipeline/data-dictionary leakage in manuscripts.
#
# Manuscripts may describe variables, measures, tables, and models, but must
# not expose internal artifact vocabulary such as "variable dictionary",
# "reader-facing translations", "results registry", or "source hashes".

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: manuscript-artifact-leakage-check.sh <project_dir>"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$PROJ" <<'PY'
import re
import os
import sys
from pathlib import Path

proj = Path(sys.argv[1])
phase = os.environ.get("AUTO_RESEARCH_VERIFY_PHASE", "").strip()
if phase in {"13", "18"}:
    paths = [proj / "manuscript" / "manuscript-draft.md"]
else:
    paths = [
        proj / "manuscript" / "manuscript-draft.md",
        proj / "final" / "manuscript-final.md",
        proj / "submission" / "manuscript-submission.md",
    ]
    drafts_dir = proj / "drafts"
    if drafts_dir.is_dir():
        for pat in ("manuscript-final-*.md", "manuscript-submission-*.md", "draft-manuscript-*.md"):
            matches = sorted(drafts_dir.glob(pat), key=lambda p: p.stat().st_mtime, reverse=True)
            if matches:
                paths.append(matches[0])
present = [p for p in paths if p.exists()]
if not present and (proj / "drafts").is_dir():
    skip = ("scholar-lrh-", "scholar-write-log-", "scholar-polish-",
            "manuscript-tables-figures-captions-", "manuscript-section-")
    candidates = [
        f for f in (proj / "drafts").glob("manuscript-*.md")
        if not any(f.name.startswith(s) for s in skip)
    ]
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    present = candidates[:1]
if not present:
    print("YELLOW:no_manuscript_files_yet")
    raise SystemExit

patterns = {
    "variable_dictionary": r"\bvariable\s+dictionary\b",
    "reader_facing_translation": r"\breader[-\s]+facing\s+(?:translation|label|term|name|wording)s?\b",
    "artifact_label_fields": r"\b(?:display_label|table_stub_label|manuscript_term|levels_display|construct_type)\b",
    "registry_artifact": r"\b(?:results|spec|specification|figure|table)[-\s]+registr(?:y|ies)(?:\.csv)?\b",
    "hash_or_manifest": r"\b(?:source_hash|output_hash|sha-?256|manifest|lock(?:ed)? artifact|lock coverage)\b",
    "trace_or_anchor": r"\b(?:trace anchor|claim row|claim-source map|source locator)\b",
    "pipeline_scaffold": r"\b(?:pipeline|phase\s+\d+|gate|verifier|route back|auto-research|auto-improve)\b",
    "construction_files": r"\bconstruction\s+files?\b",
    "model_ladder": r"\bmodel\s+ladder\b",
    "claim_scaffold": r"\b(?:claim strength|bounded claim)\b",
    "project_metadata_block": r"\b(?:Project slug|Target journal|Manuscript word target)\b",
    "workflow_review_markers": r"\b(?:pre[- ]mortem|post[- ]execution code review|reviewer flagged|amendment\s+[A-Z]?\d+|logged\s+\d{4}-\d{2}-\d{2})\b",
    "replication_trace_leakage": r"\b(?:raw outputs|verification logs|AI-tool conversation log|conversation log|process log)\b",
}

issues = []
for path in present:
    text = path.read_text(encoding="utf-8", errors="replace")
    visible = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
    for label, pattern in patterns.items():
        for m in re.finditer(pattern, visible, re.I):
            line = visible[:m.start()].count("\n") + 1
            rel = path.relative_to(proj)
            issues.append(f"{rel}:{line}:{label}:{m.group(0)[:80]}")
            break

if issues:
    print("RED:" + ";".join(issues[:40]))
else:
    print(f"GREEN:{len(present)}")
PY
)

echo "PROJECT=${PROJ}"
case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=no_manuscript_artifact_leakage"
    echo "DETAIL: checked=${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=manuscript_artifact_leakage"
    echo "DETAIL: ${result#RED:}"
    exit 1 ;;
  YELLOW:*)
    echo "STATUS=YELLOW"
    echo "REASON=${result#YELLOW:}"
    exit 2 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
