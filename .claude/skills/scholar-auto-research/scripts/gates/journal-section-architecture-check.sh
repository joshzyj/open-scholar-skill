#!/usr/bin/env bash
# journal-section-architecture-check.sh — manuscript architecture gate.
#
# Checks empirical manuscripts for journal-native structure that cannot be
# inferred from word counts alone:
#   - abstract states purpose/importance, data, method, findings, contribution;
#   - abstract does not cite reader-facing display labels such as Table 1;
#   - theory sections are organized by subheading or paired with a separate
#     motivated Hypotheses section;
#   - theory/hypothesis displays are theoretically motivated, not bare lists;
#   - quantitative Methods include Data/Sample, Variables/Measures, and
#     analytic-strategy subsections;
#   - Variables/Measures text clearly distinguishes outcomes/dependent
#     variables, predictors/independent variables, and controls/covariates
#     when those roles appear in the spec registry.
#
# Exit codes:
#   0  STATUS=GREEN   required architecture present
#   1  STATUS=RED     manuscript architecture fails
#   2  STATUS=YELLOW  inputs missing or inconclusive

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: journal-section-architecture-check.sh <project_dir>"
  exit 2
fi

MS=""
for cand in \
  "$PROJ/manuscript/manuscript-draft.md" \
  "$PROJ/final/manuscript-final.md" \
  "$PROJ/submission/manuscript-submission.md"
do
  if [ -f "$cand" ]; then
    MS="$cand"
    break
  fi
done

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

result=$(python3 - "$PROJ" "$MS" <<'PY'
import csv
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])
ms_path = Path(sys.argv[2])
text = ms_path.read_text(encoding="utf-8", errors="replace")


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s or "").lower()).strip()


def word_count(s):
    return len(re.findall(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)?", str(s or "")))


def parse_sections(markdown):
    headings = []
    for match in re.finditer(r"(?m)^(#{1,6})\s+(.+?)\s*$", markdown):
        raw = match.group(2).strip()
        clean = re.sub(r"^\d+(?:\.\d+)*\.?\s+", "", raw)
        clean = re.sub(r"\s+\{#.*?\}\s*$", "", clean).strip()
        headings.append(
            {
                "level": len(match.group(1)),
                "title": clean,
                "key": norm(clean),
                "start": match.start(),
                "end": match.end(),
            }
        )
    sections = []
    for i, heading in enumerate(headings):
        next_start = len(markdown)
        for later in headings[i + 1 :]:
            if later["level"] <= heading["level"]:
                next_start = later["start"]
                break
        sections.append({**heading, "body": markdown[heading["end"] : next_start], "stop": next_start})
    return sections


sections = parse_sections(text)
spec_path = proj / "analysis" / "spec-registry.csv"
dict_path = proj / "data" / "variable-dictionary.csv"
empirical_abstract_required = spec_path.exists()


def find_section(pattern):
    rx = re.compile(pattern, re.I)
    for sec in sections:
        if rx.search(sec["title"]):
            return sec
    return None


def child_headings(section, title_pattern=None):
    if not section:
        return []
    rx = re.compile(title_pattern, re.I) if title_pattern else None
    children = []
    for sec in sections:
        if sec["start"] <= section["start"] or sec["start"] >= section["stop"]:
            continue
        if sec["level"] <= section["level"]:
            continue
        if rx is None or rx.search(sec["title"]):
            children.append(sec)
    return children


issues = []

# Abstract: JMF/ASR-style empirical abstract moves, not display callouts.
abstract = find_section(r"^abstract$")
if not abstract:
    issues.append("abstract:missing")
else:
    abstract_text = re.sub(r"<!--.*?-->", " ", abstract["body"], flags=re.S).strip()
    abstract_norm = abstract_text.lower()
    if re.search(r"\b(?:table|figure|fig\.?)\s+[0-9ivx]+\b", abstract_text, re.I):
        issues.append("abstract:contains_table_or_figure_callout")
    move_patterns = {
        "purpose_or_importance": r"\b(examin|investigat|analy[sz]e|ask|assess|estimate|study|address|focus|relationship|association|link|gap|important|theor)",
        "contribution": r"\b(contribut\w*|advance\w*|provide evidence|evidence for|suggest\w*|implication\w*|understanding|literature|theory|theoretical|policy)\b",
    }
    if empirical_abstract_required:
        move_patterns.update(
            {
                "data": r"\b(data|survey|sample|panel|census|administrative|experiment|interview|respondent|household|cfps|gss|psid|nlsy|ipums|acs)\b",
                "method": r"\b(method|model|regression|logit|probit|ols|cox|hazard|matching|propensity|fixed effect|difference|estimate|analysis|weight|cluster|standard error|instrument|mediat)",
                "findings": r"\b(result|finding|find|show|suggest|reveal|indicat|demonstrat|evidence)\b",
            }
        )
    missing_moves = [name for name, pat in move_patterns.items() if not re.search(pat, abstract_norm, re.I)]
    if missing_moves:
        issues.append("abstract:missing_moves=" + ",".join(missing_moves))
    if empirical_abstract_required and word_count(abstract_text) < 80:
        issues.append("abstract:too_short_for_empirical_article")

# Displayed hypotheses are allowed for journals that use them, but they must
# be motivated by nearby theory rather than appearing as a naked checklist.
hypothesis_lines = []
for lineno, line in enumerate(text.splitlines(), start=1):
    stripped = line.strip()
    if re.search(r"^(?:[-*+]\s+)?(?:\*\*)?\s*(?:H\d+[A-Za-z]?|Hypothesis\s+\d+[A-Za-z]?)(?:\*\*)?\s*[:.)-]\s+\S", stripped, re.I):
        hypothesis_lines.append((lineno, stripped))
    elif re.search(r"^#{2,6}\s+(?:formal\s+)?hypoth(?:esis|eses)\s*$", stripped, re.I):
        hypothesis_lines.append((lineno, stripped))

if hypothesis_lines:
    lines = text.splitlines()
    for lineno, stripped in hypothesis_lines[:12]:
        prior = "\n".join(lines[max(0, lineno - 14) : max(0, lineno - 1)])
        prior_words = word_count(prior)
        has_theory_signal = re.search(
            r"\b(theor|mechanism|perspective|because|therefore|thus|prior|literature|argu|expect|predict|suggest|scope|condition)\b",
            prior,
            re.I,
        )
        if prior_words < 35 or not has_theory_signal:
            issues.append(f"hypotheses:bare_display_near_line_{lineno}")
            break

# Quantitative Methods architecture. Treat spec-registry as evidence that the
# manuscript is empirical/quantitative and should expose method substructure.
roles = {"outcome": set(), "predictor": set(), "covariate": set()}
if spec_path.exists():
    try:
        with spec_path.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                for col, role in (("outcome", "outcome"), ("predictors", "predictor"), ("covariates", "covariate")):
                    for var in (row.get(col, "") or "").split(";"):
                        var = var.strip()
                        if var:
                            roles[role].add(var)
    except Exception as exc:
        issues.append(f"methods:spec_registry_unreadable={exc}")

if dict_path.exists():
    try:
        with dict_path.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                var = (row.get("variable") or "").strip()
                role = norm(row.get("role") or "")
                if not var:
                    continue
                if role in {"y", "outcome", "dependent", "dependent variable", "dv"}:
                    roles["outcome"].add(var)
                elif role in {"x", "predictor", "independent", "independent variable", "treatment", "exposure", "iv"}:
                    roles["predictor"].add(var)
                elif role in {"control", "covariate", "covariates", "confounder", "fixed effect"}:
                    roles["covariate"].add(var)
    except Exception as exc:
        issues.append(f"methods:variable_dictionary_unreadable={exc}")

is_quant = any(roles.values())
if is_quant:
    theory = find_section(
        r"^(theory|theoretical framework|theoretical framework and hypotheses|"
        r"theory and hypotheses|theoretical background|conceptual framework|"
        r"literature review and theory|background)$"
    )
    hypothesis_section = find_section(r"^(formal\s+)?hypoth(?:esis|eses)$")
    if not theory:
        issues.append("theory:missing_theory_or_background_section")
    else:
        theory_children = [
            h
            for h in child_headings(theory)
            if not re.search(r"^(formal\s+)?hypoth(?:esis|eses)$", h["title"], re.I)
        ]
        theory_body = re.sub(r"^#{2,6}\s+.*$", " ", theory["body"], flags=re.M)
        theory_signals = re.search(
            r"\b(theor|mechanism|account|perspective|argument|because|therefore|expect|predict|"
            r"scope|condition|rival|alternative|hypothes|literature|prior research)\b",
            theory_body,
            re.I,
        )
        separate_hypotheses_with_motivation = (
            hypothesis_section is not None
            and word_count(theory_body) >= 250
            and theory_signals is not None
            and re.search(r"\bH\d+[A-Za-z]?\b|Hypothesis\s+\d+", hypothesis_section["body"], re.I)
        )
        if len(theory_children) < 2 and not separate_hypotheses_with_motivation:
            issues.append("theory:missing_subheadings_or_motivated_hypotheses_section")

    methods = find_section(r"^(data[, ]+measures[, ]+and methods|data and methods|data and method|materials and methods|methods)$")
    if not methods:
        issues.append("methods:missing_methods_section")
    else:
        headings = child_headings(methods)
        heading_text = "\n".join(h["title"] for h in headings)
        if not re.search(r"\b(data(?: source)?|sample|analytic sample|data and sample)\b", heading_text, re.I):
            issues.append("methods:missing_data_sample_subsection")
        if not re.search(r"\b(variables? and measures?|measures?|measurement|variable construction)\b", heading_text, re.I):
            issues.append("methods:missing_variables_measures_subsection")
            measures_text = ""
        else:
            measure_sec = next(
                (
                    h
                    for h in headings
                    if re.search(r"\b(variables? and measures?|measures?|measurement|variable construction)\b", h["title"], re.I)
                ),
                None,
            )
            measures_text = measure_sec["body"] if measure_sec else methods["body"]
        if not re.search(
            r"\b(analytic strategy|statistical analysis|analysis|model|models|estimation|regression|matching|survival analysis|fixed effects|identification strategy)\b",
            heading_text,
            re.I,
        ):
            issues.append("methods:missing_analytic_strategy_subsection")
        measures_norm = measures_text.lower()
        role_requirements = [
            ("outcome", r"\b(dependent variable|outcome|outcomes|response variable|timing|duration)\b"),
            ("predictor", r"\b(independent variable|predictor|treatment|exposure|focal variable|key variable)\b"),
            ("covariate", r"\b(control variable|control variables|covariate|covariates|adjust|controlled for|sociodemographic|fixed effect|regional)\b"),
        ]
        missing_roles = [
            role
            for role, pat in role_requirements
            if roles[role] and not re.search(pat, measures_norm, re.I)
        ]
        if missing_roles:
            issues.append("measures:missing_role_signposts=" + ",".join(missing_roles))

if issues:
    print("RED:" + ";".join(issues))
else:
    print("GREEN:journal_architecture_ok")
PY
)

echo "PROJECT=${PROJ}"
echo "MANUSCRIPT=${MS#$PROJ/}"

case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=journal_section_architecture_failed"
    echo "DETAIL: ${result#RED:}"
    exit 1 ;;
  *)
    echo "STATUS=YELLOW"
    echo "REASON=unexpected_python_output"
    echo "DETAIL: ${result}"
    exit 2 ;;
esac
