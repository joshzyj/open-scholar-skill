#!/usr/bin/env bash
# analytic-strategy-quality-check.sh — journal-quality Analytic Strategy gate.
#
# A quantitative article's Analytic Strategy must explain the estimator,
# model sequence, adjustment logic, missing-data/denominator handling,
# survey-weight/design decision, robustness checks, and claim boundary in
# coherent prose. Existing methods-role gates only prove that variable roles
# are visible; this gate blocks generic or scaffold-leaking strategy prose.

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: analytic-strategy-quality-check.sh <project_dir>"
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
quant = (proj / "analysis" / "spec-registry.csv").exists()
if not quant:
    print("INERT:no_spec_registry")
    raise SystemExit

if phase in {"13", "18"}:
    paths = [proj / "manuscript" / "manuscript-draft.md"]
else:
    paths = [
        proj / "manuscript" / "manuscript-draft.md",
        proj / "final" / "manuscript-final.md",
        proj / "submission" / "manuscript-submission.md",
    ]
present = [p for p in paths if p.exists()]
if not present:
    print("YELLOW:no_manuscript_files_yet")
    raise SystemExit

def strip_comments(text):
    return re.sub(r"<!--.*?-->", " ", text, flags=re.S)

def word_count(text):
    return len(re.findall(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)?", text))

def extract_strategy(text):
    m = re.search(
        r"^###\s+Analytic Strategy\s*$([\s\S]*?)(?=^###\s+|^##\s+|\Z)",
        text,
        flags=re.I | re.M,
    )
    return m.group(1).strip() if m else ""

required = {
    "estimator_inference": r"\b(?:ols|linear|logit|probit|regression|model(?:s|ed)?|estimate[ds]?)\b[\s\S]{0,240}\b(?:standard errors?|robust|hc1|cluster|confidence interval|vcov)\b",
    "adjustment_logic": r"\b(?:adjust(?:ed|ment)?|control(?:s|led)?|covariates?|stratification|confound(?:er|ing)?)\b",
    "model_sequence": r"\b(?:first|second|third|next|then|primary|main|sequence|family|set of models|parallel|robustness)\b",
    "missing_denominator": r"\b(?:complete[-\s]?case|missing(?:ness)?|denominator|nonmissing|sample restriction|item missing)\b",
    "weights_design": r"\b(?:weight(?:ed|s)?|unweighted|survey design|public-use files|sampling)\b",
    "robustness_sensitivity": r"\b(?:robustness|sensitivity|bounded|alternative|component|heterogeneity|interaction|comparable[-\s]?wave)\b",
    "claim_boundary": r"\b(?:observational|descriptive|associat(?:ion|ional)|not establish|do not establish|cannot establish|reverse ordering|unmeasured)\b",
}

banned = {
    "artifact_leakage": r"\b(?:variable dictionary|reader[-\s]+facing|display_label|table_stub_label|manuscript_term|results registry|spec registry|construction files?)\b",
    "scaffold_terms": r"\b(?:model ladder|claim strength|language discipline|phase\s+\d+|pipeline|gate|verifier)\b",
    "fragment_boilerplate": r"(?m)^\s*(?:Observational associations only|Unweighted HC1 estimates due to|Complete-case denominators vary by specification|Privacy-governance constructs remain excluded).*$",
}

issues = []
for path in present:
    text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
    strategy = extract_strategy(text)
    rel = path.relative_to(proj)
    if not strategy:
        issues.append(f"{rel}:missing_analytic_strategy")
        continue
    if word_count(strategy) < 170:
        issues.append(f"{rel}:analytic_strategy_too_thin")
    missing = [name for name, pat in required.items() if not re.search(pat, strategy, re.I)]
    if missing:
        issues.append(f"{rel}:missing_components={','.join(missing)}")
    for name, pat in banned.items():
        if re.search(pat, strategy, re.I):
            issues.append(f"{rel}:{name}")
    # Repeated full sentences are a strong sign of stitched boilerplate.
    sentences = [
        re.sub(r"\s+", " ", s.strip()).lower()
        for s in re.split(r"(?<=[.!?])\s+", strategy)
        if word_count(s) >= 8
    ]
    seen = set()
    dupes = set()
    for s in sentences:
        if s in seen:
            dupes.add(s)
        seen.add(s)
    if dupes:
        issues.append(f"{rel}:duplicate_sentences")

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
    echo "REASON=analytic_strategy_complete_and_reader_facing"
    echo "DETAIL: checked=${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=analytic_strategy_quality_failure"
    echo "DETAIL: ${result#RED:}"
    exit 1 ;;
  INERT:*)
    echo "STATUS=INERT"
    echo "REASON=${result#INERT:}"
    exit 3 ;;
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
