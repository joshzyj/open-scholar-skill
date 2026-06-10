#!/usr/bin/env bash
# abstract-boilerplate-check.sh — block defensive limitation boilerplate in empirical abstracts.
#
# Empirical sociology abstracts should state the problem, data/design, main findings,
# and contribution. They should not spend scarce abstract space on defensive
# scope boilerplate such as "not causal estimates" or "observational associations
# only." Those boundaries belong in Data/Methods, Results, or Discussion unless a
# target journal explicitly requires a limitation sentence in the abstract.

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: abstract-boilerplate-check.sh <project_dir>"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$PROJ" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])
phase = os.environ.get("AUTO_RESEARCH_VERIFY_PHASE", "").strip()

def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}

def section_body(text, heading):
    m = re.search(rf"^##\s+{re.escape(heading)}\s*$([\s\S]*?)(?=^##\s+|\Z)", text, re.I | re.M)
    return m.group(1).strip() if m else ""

def strip_comments(text):
    return re.sub(r"<!--.*?-->", " ", text, flags=re.S)

def word_count(text):
    return len(re.findall(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)?", text))

claim_strength = ""
design_json = load_json(proj / "design" / "design-blueprint.json")
if isinstance(design_json.get("analytic_strategy"), dict):
    claim_strength = str(design_json["analytic_strategy"].get("claim_strength") or "").lower()
if not claim_strength:
    claim_strength = str(load_json(proj / "design" / "identification-strategy.json").get("claim_strength") or "").lower()

allow_abstract_limitations = False
journal_spec = load_json(proj / "manuscript" / "journal-spec.json")
if isinstance(journal_spec.get("abstract_policy"), dict):
    allow_abstract_limitations = bool(journal_spec["abstract_policy"].get("allow_limitation_sentence"))

if phase in {"13", "18"}:
    manuscripts = [proj / "manuscript" / "manuscript-draft.md"]
else:
    manuscripts = [
        proj / "manuscript" / "manuscript-draft.md",
        proj / "final" / "manuscript-final.md",
        proj / "submission" / "manuscript-submission.md",
    ]
    drafts_dir = proj / "drafts"
    if drafts_dir.is_dir():
        for pat in ("manuscript-final-*.md", "manuscript-submission-*.md", "draft-manuscript-*.md"):
            matches = sorted(drafts_dir.glob(pat), key=lambda p: p.stat().st_mtime, reverse=True)
            if matches:
                manuscripts.append(matches[0])
present = [p for p in manuscripts if p.exists()]
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

boilerplate = [
    ("not_causal_estimates", r"\bnot\s+causal\s+(?:estimates?|effects?|claims?)\b"),
    ("observational_only", r"\bobservational\s+associations?\s+only\b"),
    ("evidence_as_associational", r"\btreat(?:s|ing)?\s+the\s+evidence\s+as\s+associational\b"),
    ("defensive_associational_sentence", r"\b(?:these|the)\s+(?:results|findings|estimates|evidence)\s+(?:are|is|remain)\s+(?:only\s+)?(?:associational|observational)\b"),
    ("causal_limitation_sentence", r"\b(?:cannot|do\s+not|does\s+not)\s+(?:establish|identify|support)\s+(?:causal|causality|effects?)\b"),
    ("scope_boundary_boilerplate", r"\b(?:claim\s+strength|scope\s+remains|bounded\s+claim|language\s+discipline)\b"),
    ("display_artifact_callout", r"\b(?:Table|Figure)\s+\d+[A-Za-z]?\b"),
    ("procedural_modeling_voice", r"\bI\s+estimate\s+adjusted\s+(?:survey\s+)?models?\b"),
]

issues = []
move_patterns = {
    "purpose_or_question": r"\b(asks?|examines?|investigates?|stud(?:y|ies)|question|whether|why|how)\b",
    "data_or_method": r"\b(using|analy[sz]e|data|survey|sample|respondents?|regression|model|estimate|method|design)\b",
    "findings": r"\b(find|finds|show|shows|reveal|reveals|results?|associated|association|estimate|evidence)\b",
    "contribution": r"\b(contribut\w*|advance\w*|clarif\w*|implication\w*|demonstrat\w*|underscore\w*|reframe\w*)\b",
}
for path in present:
    text = path.read_text(encoding="utf-8", errors="replace")
    abstract = strip_comments(section_body(text, "Abstract"))
    if not abstract:
        continue
    if word_count(abstract) < 80:
        continue
    if allow_abstract_limitations:
        continue
    # For causal or quasi-experimental designs, an abstract may legitimately
    # state identifying variation. This gate targets defensive noncausal
    # boilerplate in associational/observational manuscripts.
    if claim_strength and claim_strength not in {"associational", "descriptive", "observational"}:
        continue
    for label, pattern in boilerplate:
        if re.search(pattern, abstract, re.I):
            rel = path.relative_to(proj)
            issues.append(f"{rel}:{label}")
    missing_moves = [name for name, pattern in move_patterns.items() if not re.search(pattern, abstract, re.I)]
    if missing_moves:
        rel = path.relative_to(proj)
        issues.append(f"{rel}:missing_abstract_moves={','.join(missing_moves)}")

if issues:
    print("RED:" + ";".join(issues))
else:
    print(f"GREEN:{len(present)}")
PY
)

echo "PROJECT=${PROJ}"
case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=abstract_free_of_defensive_boilerplate"
    echo "DETAIL: checked=${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=abstract_defensive_boilerplate"
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
