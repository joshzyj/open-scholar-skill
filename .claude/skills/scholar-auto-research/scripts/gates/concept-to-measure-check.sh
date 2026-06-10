#!/usr/bin/env bash
# concept-to-measure-check.sh — Phase 13 / 19 measurement-bridge gate.
#
# Rationale: a common failure is a Methods section that uses variable
# display labels and broad construct names but contains no paragraph or
# subsection linking each modeled variable family to its conceptualization
# and operationalization. The variable dictionary already carries
# `construct`, `display_label`, `levels_display`, and `operationalization`
# columns — they are simply left unused in prose. No skill contract
# required Methods to consume those fields; no gate checked for the bridge.
#
# Contract
# --------
# Every quantitative manuscript must contain a measurement bridge inside
# its Methods / Data and Methods / Materials and Methods section that
# operationalizes every modeled variable. The bridge may take the form of:
#   - a `### Measurement` (or `### Variable Construction` / `### Measures`)
#     subsection inside Methods;
#   - a paragraph block tagged `<!-- measurement-bridge -->`;
#   - a sequence of paragraphs in which each modeled variable's
#     display_label appears AND co-occurs (within the same paragraph)
#     with operationalization-derived language plus concrete measurement
#     detail (coding, scale/type, source item, range, or construction).
#
# Coverage rule:
#   - GREEN if ≥80% of modeled variables (excluding province_indicators
#     and survey_wave_indicators which are typically nuisance controls)
#     appear in the Methods section paired with operationalization-style
#     prose.
#   - RED below 80% (or zero hits at all). Earlier versions returned
#     YELLOW for 60-79%, but Phase 13/18 treated YELLOW as advisory and let
#     incomplete Variables/Measures sections pass.
#   - RED if the Methods section uses repeated dictionary-template prose
#     such as "conceptualized as ... operationalized as ..." instead of
#     reader-facing measurement prose.
#
# Inputs
# ------
#   $1   project directory (required)
#
# Exit codes
# ----------
#   0  STATUS=GREEN   measurement bridge present and ≥80% coverage
#   1  STATUS=RED     bridge missing or coverage <60%
#   2  STATUS=YELLOW  inputs missing or inconclusive
#   3  STATUS=INERT   no spec-registry / no manuscript / non-quant project

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: concept-to-measure-check.sh <project_dir>"
  exit 2
fi

SPEC="$PROJ/analysis/spec-registry.csv"
DICT="$PROJ/data/variable-dictionary.csv"

if [ ! -f "$SPEC" ] || [ ! -f "$DICT" ]; then
  echo "STATUS=INERT"
  echo "REASON=no_spec_or_dict"
  exit 3
fi

MS=""
for cand in "$PROJ/manuscript/manuscript-draft.md" "$PROJ/final/manuscript-final.md" "$PROJ/submission/manuscript-submission.md"; do
  if [ -f "$cand" ]; then
    MS="$cand"; break
  fi
done
if [ -z "$MS" ] && [ -d "$PROJ/drafts" ]; then
  while IFS= read -r -d '' cand; do
    base=$(basename "$cand")
    case "$base" in
      scholar-lrh-*|scholar-write-log-*|scholar-polish-*|manuscript-tables-figures-captions-*|manuscript-section-*) continue ;;
    esac
    MS="$cand"; break
  done < <(find "$PROJ/drafts" -maxdepth 1 -type f \( -name "manuscript-final-*.md" -o -name "manuscript-submission-*.md" -o -name "draft-manuscript-*.md" -o -name "manuscript-*.md" \) -print0 2>/dev/null)
fi

if [ -z "$MS" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_manuscript_yet"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$SPEC" "$DICT" "$MS" <<'PY'
import csv, re, sys, pathlib

spec_path, dict_path, ms_path = (pathlib.Path(p) for p in sys.argv[1:4])

OPERATIONALIZATION_WORDS = {
    "operationalize", "operationalized", "operationalization",
    "measure", "measured", "measures",
    "constructed", "constructing", "construct",
    "coded", "coding", "indicator", "scale",
    "categorical", "binary", "continuous", "ordinal",
    "items", "item", "index", "composite",
    "harmonized", "derived", "imputed",
}

MEASUREMENT_DETAIL_WORDS = {
    "binary", "categorical", "continuous", "ordinal", "nominal",
    "dummy", "indicator", "scale", "index", "score", "count",
    "duration", "years", "months", "days", "rate", "proportion",
    "percentage", "logged", "log", "category", "categories",
    "range", "ranging", "coded", "coding", "1 =", "0 =",
    "question", "questions", "item", "items",
    "summed", "averaged", "standardized", "reverse-coded",
}

def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s or "").lower()).strip()

# 1. Modeled variables (exclude nuisance controls)
NUISANCE = {"province_indicators", "survey_wave_indicators"}
modeled = set()
role_need = {"dependent": False, "independent": False, "control": False}
with spec_path.open(newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        for col in ("outcome",):
            cell = row.get(col, "") or ""
            for v in cell.split(";"):
                v = v.strip()
                if v and v not in NUISANCE:
                    modeled.add(v)
                    role_need["dependent"] = True
        for col in ("predictors",):
            cell = row.get(col, "") or ""
            for v in cell.split(";"):
                v = v.strip()
                if v and v not in NUISANCE and v not in {"no_added_controls"}:
                    modeled.add(v)
                    if "_x_" not in v and " x " not in v:
                        role_need["independent"] = True
        for col in ("covariates",):
            cell = row.get(col, "") or ""
            for v in cell.split(";"):
                v = v.strip()
                if v and v not in NUISANCE and v not in {"no_added_controls"}:
                    modeled.add(v)
                    role_need["control"] = True

# Also drop interaction terms (they aren't measured separately)
modeled = {v for v in modeled if "_x_" not in v}

if not modeled:
    print("INERT:no_modeled_variables")
    sys.exit(0)

# 2. Build display-label set per variable
labels_for = {}
with dict_path.open(newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        var = (row.get("variable") or "").strip()
        if not var or var not in modeled:
            continue
        role = norm(row.get("role") or "")
        if role in {"y", "outcome", "dependent", "dependent variable", "dv"}:
            role_need["dependent"] = True
        elif role in {"x", "predictor", "independent", "independent variable", "treatment", "exposure", "iv"}:
            role_need["independent"] = True
        elif role in {"control", "covariate", "covariates", "confounder", "fixed effect"}:
            role_need["control"] = True
        labels_for[var] = set()
        for field in ("display_label", "table_stub_label", "manuscript_term"):
            label = (row.get(field) or "").strip()
            if label and len(label) >= 3:
                labels_for[var].add(label)

# 3. Extract Methods section from manuscript
text = ms_path.read_text(encoding="utf-8", errors="replace")
methods_re = re.compile(
    r"^##\s+(?:Data,\s*Measures,\s*and Methods|Data and Methods|Data and Method|Materials and Methods|Methods)\s*$"
    r"([\s\S]*?)(?=^##\s+|\Z)",
    re.MULTILINE,
)
m = methods_re.search(text)
if not m:
    print("RED:no_methods_section")
    sys.exit(0)
methods_text = m.group(1)

# 4. Detect explicit subsection / tagged-block bridge
has_subsection = bool(re.search(
    r"^###\s+(?:Measurement|Measures|Variable Construction|Variables and Measures|Measurement and Variables)\s*$",
    methods_text, re.MULTILINE | re.IGNORECASE,
))
has_tagged_block = "<!-- measurement-bridge -->" in methods_text

# 5. Coverage: split Methods into paragraphs; for each modeled variable,
# check whether ANY paragraph contains a label match, ≥1 op-word, and
# concrete measurement detail. This rejects thin dictionary dumps that
# merely restate "X is operationalized as..." without saying how a reader
# should understand the measure.
paragraphs = [p.strip() for p in re.split(r"\n\s*\n", methods_text) if p.strip()]
para_lower = [p.lower() for p in paragraphs]

def has_op_word(plower):
    return any(w in plower for w in OPERATIONALIZATION_WORDS)

def has_measurement_detail(plower):
    if any(w in plower for w in MEASUREMENT_DETAIL_WORDS):
        return True
    if re.search(r"\b[01]\s*=", plower):
        return True
    if re.search(r"\b(range|ranging)\s+from\b", plower):
        return True
    return False

dictionary_dump_paragraphs = [
    p for p in paragraphs
    if re.search(r"\bconceptualized as\b[\s\S]{0,220}\boperationalized as\b|\boperationalized as\b[\s\S]{0,220}\bconceptualized as\b", p, re.I)
]
dictionary_dump_phrase_count = len(re.findall(r"\b(?:conceptualized|operationalized) as\b", methods_text, re.I))

covered = []
uncovered = []
for var, labels in labels_for.items():
    if not labels:
        # no display label in dictionary → can't check; skip
        continue
    hit = False
    for plower in para_lower:
        if not has_op_word(plower):
            continue
        if not has_measurement_detail(plower):
            continue
        for lab in labels:
            if lab.lower() in plower:
                hit = True; break
        if hit:
            break
    (covered if hit else uncovered).append(var)

total = len(covered) + len(uncovered)
if total == 0:
    print("INERT:no_labeled_variables")
    sys.exit(0)

pct = (len(covered) / total) * 100.0

bridge_signal = "explicit" if (has_subsection or has_tagged_block) else "implicit"

if len(dictionary_dump_paragraphs) >= 3 or dictionary_dump_phrase_count >= 6:
    print(f"RED:{pct:.1f}:{bridge_signal}:{total}:dictionary_dump_template")
    sys.exit(0)

role_patterns = {
    "dependent": r"(?mi)^#{3,6}\s+(?:dependent\s+variables?|outcomes?|dependent\s+variable|outcome\s+measures?)\b|\bdependent\s+variables?\b|\boutcomes?\b",
    "independent": r"(?mi)^#{3,6}\s+(?:independent\s+variables?|predictors?|treatment|exposure|focal\s+predictors?)\b|\bindependent\s+variables?\b|\bfocal\s+predictors?\b|\bkey\s+predictors?\b",
    "control": r"(?mi)^#{3,6}\s+(?:control\s+variables?|covariates?|adjustment\s+variables?)\b|\bcontrol\s+variables?\b|\bcovariates?\b",
}
missing_roles = [role for role, needed in role_need.items() if needed and not re.search(role_patterns[role], methods_text)]
if missing_roles:
    print(f"RED:{pct:.1f}:{bridge_signal}:{total}:missing_role_organization={','.join(missing_roles)}")
    sys.exit(0)

if pct >= 80.0:
    print(f"GREEN:{pct:.1f}:{bridge_signal}:{total}")
else:
    print(f"RED:{pct:.1f}:{bridge_signal}:{total}:" + ",".join(uncovered))
PY
)

echo "PROJECT=${PROJ}"
echo "MANUSCRIPT=${MS#$PROJ/}"

case "$result" in
  GREEN:*)
    rest="${result#GREEN:}"; pct="${rest%%:*}"
    echo "STATUS=GREEN"
    echo "REASON=measurement_bridge_present"
    echo "DETAIL: coverage=${pct}%"
    exit 0 ;;
  RED:*)
    rest="${result#RED:}"
    echo "STATUS=RED"
    if [[ "$rest" == "no_methods_section" ]]; then
      echo "REASON=no_methods_section"
    elif [[ "$rest" == *"dictionary_dump_template"* ]]; then
      pct="${rest%%:*}"
      echo "REASON=measurement_bridge_dictionary_dump"
      echo "DETAIL: coverage=${pct}%"
    elif [[ "$rest" == *"missing_role_organization"* ]]; then
      pct="${rest%%:*}"
      echo "REASON=measurement_role_organization_missing"
      echo "DETAIL: coverage=${pct}% ${rest##*:}"
    else
      pct="${rest%%:*}"
      echo "REASON=measurement_bridge_missing_or_thin"
      echo "DETAIL: coverage=${pct}%"
    fi
    cat >&2 <<EOF
FAIL: concept-to-measure bridge — the Methods section does not
operationalize every modeled variable. For each modeled variable family
the manuscript should pair the display label with operationalization-
style language plus concrete coding/type/source details (measured / coded /
constructed / binary / categorical / continuous / scale / index / etc.).
A \`### Measurement\` subsection or a \`<!-- measurement-bridge -->\`
tagged block satisfies this requirement explicitly. Repeated
"conceptualized as ... operationalized as ..." dictionary-template prose
does not satisfy the reader-facing measurement bridge.
EOF
    exit 1 ;;
  INERT:*)
    echo "STATUS=INERT"
    echo "REASON=${result#INERT:}"
    exit 3 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
