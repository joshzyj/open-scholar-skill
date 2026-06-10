#!/usr/bin/env bash
# analytic-formula-specificity-check.sh — method-family technical-detail gate.
#
# Blocks Methods sections that name an estimator or algorithm without telling
# readers what was estimated or computed. Quantitative papers need real
# variable/model detail; computational papers need a readable method pipeline,
# validation, and interpretation bridge for social scientists.

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: analytic-formula-specificity-check.sh <project_dir>"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$PROJ" <<'PY'
import csv
import json
import os
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])
phase = os.environ.get("AUTO_RESEARCH_VERIFY_PHASE", "").strip()

def read_text(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""

def strip_comments(text):
    return re.sub(r"<!--.*?-->", " ", text, flags=re.S)

def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s or "").lower()).strip()

def word_count(s):
    return len(re.findall(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)?", str(s or "")))

def parse_sections(markdown):
    headings = []
    for match in re.finditer(r"(?m)^(#{1,6})\s+(.+?)\s*$", markdown):
        title = re.sub(r"^\d+(?:\.\d+)*\.?\s+", "", match.group(2).strip())
        title = re.sub(r"\s+\{#.*?\}\s*$", "", title).strip()
        headings.append(
            {
                "level": len(match.group(1)),
                "title": title,
                "key": norm(title),
                "start": match.start(),
                "end": match.end(),
            }
        )
    sections = []
    for i, heading in enumerate(headings):
        stop = len(markdown)
        for later in headings[i + 1 :]:
            if later["level"] <= heading["level"]:
                stop = later["start"]
                break
        sections.append({**heading, "body": markdown[heading["end"] : stop], "stop": stop})
    return sections

def find_section(sections, pattern):
    rx = re.compile(pattern, re.I)
    for sec in sections:
        if rx.search(sec["title"]):
            return sec
    return None

def child_sections(sections, parent):
    if not parent:
        return []
    return [
        sec
        for sec in sections
        if sec["start"] > parent["start"]
        and sec["start"] < parent["stop"]
        and sec["level"] > parent["level"]
    ]

def extract_strategy_text(text):
    sections = parse_sections(text)
    methods = find_section(
        sections,
        r"^(data[, ]+measures[, ]+and methods|data and methods|data and method|"
        r"materials and methods|methods|method)$",
    )
    if not methods:
        return "", "missing_methods_section"
    children = child_sections(sections, methods)
    strategy_children = [
        sec
        for sec in children
        if re.search(
            r"\b(analytic strategy|statistical analysis|analysis|estimation|model|models|"
            r"regression|fixed effects|difference|survival|cox|matching|propensity|"
            r"machine learning|computational|text|nlp|llm|network|simulation|"
            r"computer vision|audio|geospatial|sequence|validation)\b",
            sec["title"],
            re.I,
        )
    ]
    if strategy_children:
        return "\n\n".join(sec["title"] + "\n" + sec["body"] for sec in strategy_children), "strategy_subsections"
    return methods["body"], "methods_fallback"

def split_vars(value):
    return [v.strip() for v in re.split(r"[;|,]", str(value or "")) if v.strip()]

spec_path = proj / "analysis" / "spec-registry.csv"
dict_path = proj / "data" / "variable-dictionary.csv"
spec_text_parts = []
outcome_vars = set()
predictor_vars = set()
covariate_vars = set()
estimator_text = ""

if spec_path.exists():
    try:
        with spec_path.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                estimator_text += " " + " ".join(str(row.get(c, "")) for c in row.keys())
                for var in split_vars(row.get("outcome")):
                    outcome_vars.add(var)
                for var in split_vars(row.get("predictors")):
                    predictor_vars.add(var)
                for var in split_vars(row.get("covariates")):
                    covariate_vars.add(var)
    except Exception:
        pass

label_map = {}
if dict_path.exists():
    try:
        with dict_path.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                raw = (row.get("variable") or row.get("name") or "").strip()
                if not raw:
                    continue
                labels = {raw}
                for col in (
                    "display_label",
                    "table_stub_label",
                    "manuscript_term",
                    "construct",
                    "operationalization",
                    "measure",
                    "label",
                ):
                    val = (row.get(col) or "").strip()
                    if val:
                        labels.add(val)
                label_map[raw] = labels
                role = norm(row.get("role") or "")
                if role in {"y", "outcome", "dependent", "dependent variable", "dv"}:
                    outcome_vars.add(raw)
                elif role in {"x", "predictor", "independent", "independent variable", "treatment", "exposure", "iv"}:
                    predictor_vars.add(raw)
                elif role in {"control", "covariate", "covariates", "confounder", "fixed effect"}:
                    covariate_vars.add(raw)
    except Exception:
        pass

context_text = "\n".join(
    [
        estimator_text,
        read_text(proj / "design" / "model-specs.json"),
        read_text(proj / "design" / "identification-strategy.json"),
        read_text(proj / "design" / "design-manifest.json"),
        read_text(proj / "design" / "design-blueprint.md"),
        read_text(proj / "analysis" / "analysis-plan.md"),
    ]
).lower()

if not spec_path.exists() and not re.search(
    r"\b(computational|machine learning|text-as-data|text as data|nlp|llm|network|"
    r"agent[- ]based|simulation|computer vision|audio|geospatial|sequence|topic model|"
    r"embedding|classifier|supervised)\b",
    context_text,
):
    print("INERT:no_quantitative_or_computational_method_detected")
    raise SystemExit

if phase in {"13", "18"}:
    paths = [proj / "manuscript" / "manuscript-draft.md"]
else:
    # Path-adapt (master-plan-v4 P1+Update 6): include scholar-full-paper
    # drafts/ canonical patterns + generic fallback.
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
# Generic fallback for non-canonical experimental manuscripts.
if not present and (proj / "drafts").is_dir():
    drafts_dir = proj / "drafts"
    skip = ("scholar-lrh-", "scholar-write-log-", "scholar-polish-",
            "manuscript-tables-figures-captions-", "manuscript-section-")
    candidates = [f for f in drafts_dir.glob("manuscript-*.md")
                  if not any(f.name.startswith(s) for s in skip)]
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    if candidates:
        present = [candidates[0]]
if not present:
    print("YELLOW:no_manuscript_files_yet")
    raise SystemExit

def add_family(families, name, pattern):
    if re.search(pattern, context_text, re.I):
        families.add(name)

families = set()
add_family(
    families,
    "fixed_effects_panel_did",
    r"\b(unit fixed effects?|individual fixed effects?|respondent fixed effects?|"
    r"unit effects?|individual effects?|respondent effects?|"
    r"within[- ]estimator|difference[- ]in[- ]differences|did|event study|"
    r"panel (?:regression|model|fixed effects?|within)|longitudinal fixed effects?)\b",
)
add_family(families, "survival_cox", r"\b(cox|survival|hazard|duration|event history|censor)\b")
add_family(families, "matching_psm", r"\b(propensity score|psm|matching|matched sample|nearest neighbor|caliper|common support|iptw|inverse probability|entropy balancing)\b")
add_family(families, "logit_probit_count", r"\b(logit|logistic|probit|poisson|negative binomial|count model|binary outcome)\b")
add_family(families, "supervised_ml", r"\b(supervised|machine learning|classifier|classification|prediction model|random forest|gradient boosting|svm|support vector|lasso|elastic net|xgboost|train(?:ing)? set|test set|cross[- ]validation)\b")
add_family(
    families,
    "text_nlp",
    r"\b(text-as-data|text as data|nlp|topic model|lda|embedding|bert|word2vec|transformer|corpus|tokeni[sz]|sentiment|named entit)\b|"
    r"\b(?:document|documents|textual)\s+(?:corpus|data|analysis|coding|classification|embedding|features?)\b",
)
add_family(families, "llm_coding", r"\b(llm|large language model|gpt|claude|prompt|prompting|zero-shot|few-shot)\b")
add_family(
    families,
    "network_analysis",
    r"\b(network (?:analysis|model|models|data|measure|measures|ties|centrality|community|structure|structures)|"
    r"nodes?|edges?|ties?|centrality|community detection|egocentric|sociometric)\b",
)
add_family(families, "simulation_abm", r"\b(agent[- ]based|abm|simulation|simulated|calibration|monte carlo|sensitivity analysis)\b")
add_family(families, "vision_audio_geo_sequence", r"\b(computer vision|image|images|audio|speech|acoustic|geospatial|gis|sequence analysis|sequence model|trajectory)\b")

if spec_path.exists() and not families.intersection({"fixed_effects_panel_did", "survival_cox", "matching_psm", "logit_probit_count"}):
    families.add("generic_quantitative")

generic_placeholders = re.compile(
    r"(\[[^\]]*(?:Y|X|outcome|predictor|control|unit|time)[^\]]*\]|"
    r"\{[^\}]*(?:Y|X|outcome|predictor|control|unit|time)[^\}]*\}|"
    r"\b(?:outcome|predictor|controls?|unit|time)\s*[_\[]\s*(?:it|i|t)?\s*[\]=])",
    re.I,
)

prose_formula_surrogates = re.compile(
    r"\b(?:main\s+specification\s+can\s+be\s+written\s+in\s+reader\s+terms|"
    r"written\s+in\s+reader\s+terms|"
    r"equals\s+an\s+intercept\s+plus|"
    r"logit\s+Pr\([^)]+\)\s+equals)\b",
    re.I,
)

def labels_for(vars_):
    labels = set()
    for var in vars_:
        labels.update(label_map.get(var, {var}))
    cleaned = set()
    generic = {
        "outcome",
        "predictor",
        "control",
        "controls",
        "covariate",
        "covariates",
        "model",
        "sample",
        "index",
        "scale",
    }
    for label in labels:
        n = norm(label)
        if len(n) >= 3 and n not in generic:
            cleaned.add(n)
    return cleaned

outcome_labels = labels_for(outcome_vars)
predictor_labels = labels_for(predictor_vars)
covariate_labels = labels_for(covariate_vars)

def any_label_present(labels, text_norm):
    return any(label in text_norm for label in labels)

def has_real_variable_pair(strategy):
    s_norm = norm(strategy)
    if outcome_labels and not any_label_present(outcome_labels, s_norm):
        return False
    if predictor_labels and not any_label_present(predictor_labels, s_norm):
        return False
    return True

def formal_equation_chunks(strategy):
    chunks = []
    patterns = [
        r"\$\$([\s\S]{20,900}?)\$\$",
        r"\\\[([\s\S]{20,900}?)\\\]",
        r"\\begin\{equation\*?\}([\s\S]{20,900}?)\\end\{equation\*?\}",
    ]
    for pattern in patterns:
        chunks.extend(match.group(1) for match in re.finditer(pattern, strategy, re.I))
    # Also accept a compact inline estimating equation when it is visibly
    # symbolic rather than a prose translation ("equals an intercept plus").
    for line in re.split(r"[\n.;]", strategy):
        if 20 <= len(line) <= 700 and "=" in line:
            if re.search(r"\b(?:logit|log|Pr\s*\(|Y_[it]?|[A-Za-z][A-Za-z0-9]+_[it])\b", line):
                chunks.append(line)
    return chunks

def has_formal_model_specification(strategy):
    if prose_formula_surrogates.search(strategy):
        return False
    for chunk in formal_equation_chunks(strategy):
        if "=" not in chunk:
            continue
        if not re.search(r"(\\beta|\\gamma|\\delta|\\alpha|beta|gamma|delta|alpha|β|γ|δ|α|\+)", chunk):
            continue
        if re.search(r"\b(?:logit|log|Pr\s*\(|Y_[it]?|[A-Za-z][A-Za-z0-9]+_[it])\b", chunk):
            return True
    return False

def require_components(strategy, components):
    missing = []
    for name, pattern in components:
        if not re.search(pattern, strategy, re.I | re.S):
            missing.append(name)
    return missing

issues = []
for path in present:
    text = strip_comments(read_text(path))
    strategy, source = extract_strategy_text(text)
    rel = path.relative_to(proj)
    if not strategy.strip():
        issues.append(f"{rel}:missing_analytic_strategy_text")
        continue
    if word_count(strategy) < 100:
        issues.append(f"{rel}:analytic_strategy_too_thin_for_method_specificity")
    if generic_placeholders.search(strategy):
        issues.append(f"{rel}:placeholder_formula_or_generic_equation")
    if prose_formula_surrogates.search(strategy):
        issues.append(f"{rel}:prose_only_formula_surrogate")
    if source == "methods_fallback":
        issues.append(f"{rel}:missing_explicit_analytic_strategy_subsection")

    for family in sorted(families):
        if family in {"generic_quantitative", "logit_probit_count"}:
            missing = require_components(
                strategy,
                [
                    ("estimator_or_model", r"\b(ols|linear|logit|logistic|probit|poisson|negative binomial|regression|model|estimate)\b"),
                    ("estimator_rationale", r"\b(because|appropriate|suited|fits|allows|use .* to|data structure|research question|theoretical question)\b"),
                    ("controls_or_adjustment", r"\b(controls?|covariates?|adjust(?:ed|ment)?|confound(?:er|ing)?|fixed effects?|baseline characteristics?)\b"),
                    ("inference", r"\b(standard errors?|cluster|robust|hc[0-9]?|confidence intervals?|bootstrap|survey weights?|weights?)\b"),
                    ("robustness_or_sensitivity", r"\b(robustness|sensitivity|alternative|diagnostic|specification check|supplement)\b"),
                ],
            )
            if missing:
                issues.append(f"{rel}:{family}:missing={','.join(missing)}")
            if not has_real_variable_pair(strategy):
                issues.append(f"{rel}:{family}:missing_actual_outcome_or_predictor_labels")
            if not has_formal_model_specification(strategy):
                issues.append(f"{rel}:{family}:missing_formal_estimating_equation")

        elif family == "fixed_effects_panel_did":
            missing = require_components(
                strategy,
                [
                    ("equation_or_specification", r"(=|as a function of|regress(?:ed)? on)"),
                    ("unit_fixed_effects", r"\b(individual|respondent|person|household|firm|province|county|unit)\b[\s\S]{0,120}\bfixed effects?\b|\bfixed effects?\b[\s\S]{0,120}\b(individual|respondent|person|household|firm|province|county|unit)\b"),
                    ("time_fixed_effects", r"\b(year|wave|period|time)\b[\s\S]{0,120}\bfixed effects?\b|\bfixed effects?\b[\s\S]{0,120}\b(year|wave|period|time)\b"),
                    ("uncertainty", r"\b(cluster(?:ed)?|standard errors?|robust|hc[0-9]?|confidence intervals?)\b"),
                    ("coefficient_interpretation", r"\b(coefficient|beta|estimate|association|effect)\b[\s\S]{0,180}\b(interpre|represents|captures|compares|within)\b"),
                ],
            )
            if missing:
                issues.append(f"{rel}:fixed_effects_panel_did:missing={','.join(missing)}")
            if not has_real_variable_pair(strategy):
                issues.append(f"{rel}:fixed_effects_panel_did:missing_actual_outcome_or_predictor_labels")

        elif family == "survival_cox":
            missing = require_components(
                strategy,
                [
                    ("hazard_specification", r"\b(hazard|cox|h_i\s*\(|survival)\b"),
                    ("event_definition", r"\b(event|failure|transition|marital dissolution|divorce|onset|exit|entry)\b"),
                    ("time_scale", r"\b(time scale|duration|spell|person[- ]years?|age|months?|years?|risk period)\b"),
                    ("censoring", r"\b(censor|censored|right[- ]censor|risk set)\b"),
                    ("covariates", r"\b(covariate|control|adjust|predictor)\b"),
                    ("assumptions", r"\b(proportional hazards?|assumption|schoenfeld|baseline hazard|stratif)\b"),
                ],
            )
            if missing:
                issues.append(f"{rel}:survival_cox:missing={','.join(missing)}")

        elif family == "matching_psm":
            missing = require_components(
                strategy,
                [
                    ("treatment", r"\b(treatment|treated|exposure|selection into|focal predictor)\b"),
                    ("propensity_model", r"\b(propensity score|logit|probit|treatment model)\b"),
                    ("matching_algorithm", r"\b(nearest neighbor|caliper|kernel|matching|matched|weighting|iptw|common support)\b"),
                    ("covariates", r"\b(covariate|pretreatment|baseline|observed characteristics|confound)\b"),
                    ("balance_common_support", r"\b(balance|standardized difference|common support|overlap)\b"),
                    ("post_match_analysis", r"\b(post[- ]match|matched sample|after matching|outcome model|treatment effect)\b"),
                ],
            )
            if missing:
                issues.append(f"{rel}:matching_psm:missing={','.join(missing)}")

        elif family in {"supervised_ml", "text_nlp", "llm_coding", "network_analysis", "simulation_abm", "vision_audio_geo_sequence"}:
            base_missing = require_components(
                strategy,
                [
                    ("social_science_bridge", r"\b(substantive|theoretical|social|research question|construct|measure|interpret|meaning|captures|represents|proxy)\b"),
                    ("input_data_or_unit", r"\b(corpus|documents?|posts?|tweets?|messages?|articles?|records?|cases?|users?|respondents?|nodes?|edges?|dyads?|agents?|images?|audio|locations?|sequences?|unit of analysis)\b"),
                    ("preprocessing_or_features", r"\b(preprocess|clean|tokeni[sz]|feature|embedding|representation|coding|extract|construct|transform|normalize|segment)\b"),
                    ("model_or_algorithm", r"\b(model|algorithm|classifier|topic model|embedding|bert|llm|network measure|centrality|community|simulation|agent[- ]based|extractor)\b"),
                    ("validation_or_error", r"\b(validation|validate|cross[- ]validation|held[- ]out|human[- ]coded|intercoder|reliability|accuracy|precision|recall|f1|auc|error analysis|sensitivity|calibration|balance|audit sample|robustness)\b"),
                    ("interpretation_or_output_use", r"\b(prediction|class|classification|topic|embedding|score|index|network|simulation output|aggregate|variable|measure|used as|enters? the|interpreted as)\b"),
                ],
            )
            if base_missing:
                issues.append(f"{rel}:{family}:missing={','.join(base_missing)}")

            family_components = {
                "supervised_ml": [
                    ("label_or_target", r"\b(label|labeled|target|ground truth|training outcome|class)\b"),
                    ("train_test_design", r"\b(train(?:ing)?|test|held[- ]out|cross[- ]validation|validation set)\b"),
                    ("performance_metric", r"\b(accuracy|precision|recall|f1|auc|rmse|mae|performance)\b"),
                ],
                "text_nlp": [
                    ("corpus_or_document_unit", r"\b(corpus|documents?|texts?|articles?|posts?|tweets?|messages?)\b"),
                    ("text_processing", r"\b(tokeni[sz]|preprocess|stemming|lemmati[sz]|stop words?|embedding|dictionary|topic model)\b"),
                    ("text_validation", r"\b(validation|human[- ]coded|read(?:ing)? sample|intercoder|reliability|topic coherence|error analysis)\b"),
                ],
                "llm_coding": [
                    ("prompt_or_coding_scheme", r"\b(prompt|coding scheme|codebook|instruction|few-shot|zero-shot)\b"),
                    ("model_or_version", r"\b(model|version|gpt|claude|llm|large language model)\b"),
                    ("human_or_audit_validation", r"\b(human[- ]coded|audit sample|validation|intercoder|reliability|privacy|leakage)\b"),
                ],
                "network_analysis": [
                    ("nodes", r"\bnodes?\b"),
                    ("edges_or_ties", r"\b(edges?|ties?|links?|dyads?)\b"),
                    ("boundary_rules", r"\b(boundary|bounded|network definition|include|exclude|tie definition)\b"),
                ],
                "simulation_abm": [
                    ("agents", r"\bagents?\b"),
                    ("rules", r"\b(rules?|behavior|decision rule|transition)\b"),
                    ("calibration_or_sensitivity", r"\b(calibration|sensitivity|parameter|validation|scenario)\b"),
                ],
                "vision_audio_geo_sequence": [
                    ("source_material", r"\b(images?|video|audio|speech|geospatial|coordinates?|locations?|sequences?|trajectories?)\b"),
                    ("extractor_or_preprocessing", r"\b(preprocess|extractor|feature|segmentation|geocod|sequence alignment|embedding)\b"),
                    ("measurement_error_or_aggregation", r"\b(measurement error|validation|accuracy|aggregate|aggregation|sensitivity|manual audit)\b"),
                ],
            }.get(family, [])
            missing = require_components(strategy, family_components)
            if missing:
                issues.append(f"{rel}:{family}:missing_family_specific={','.join(missing)}")

if issues:
    print("RED:" + ";".join(issues[:80]))
else:
    print("GREEN:" + ",".join(sorted(families)) + f":checked={len(present)}")
PY
)

echo "PROJECT=${PROJ}"
case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=method_specific_analytic_detail_complete"
    echo "DETAIL: ${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=method_specific_analytic_detail_failure"
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
