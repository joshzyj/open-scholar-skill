#!/usr/bin/env bash
# theory-hypothesis-continuity-check.sh — keep Phase 2 theory/hypotheses
# ex ante during manuscript drafting.
#
# This gate catches the failure mode where Phase 13 rewrites the Theory
# section after seeing locked results: hypotheses become "expectations,"
# result-aware interpretation leaks into theory, and drafting-plan theory
# briefs instruct the writer to accommodate findings.
#
# Usage:
#   bash scripts/gates/theory-hypothesis-continuity-check.sh <project_dir>
#
# Exit codes:
#   0 GREEN  — theory/hypothesis continuity passes
#   1 RED    — post-results theory leakage or canonical hypothesis drift
#   2 YELLOW — manuscript or canonical Phase 2 hypotheses unavailable

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: theory-hypothesis-continuity-check.sh <project_dir>"
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
phase = str(os.environ.get("AUTO_RESEARCH_VERIFY_PHASE", "") or "").strip()


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s or "").lower()).strip()


def tokens(s):
    stop = {
        "the", "and", "for", "that", "with", "from", "this", "those", "these",
        "will", "would", "among", "greater", "lower", "higher", "more", "less",
        "associated", "association", "associations", "effect", "effects",
        "hypothesis", "expectation", "respondents", "variables",
    }
    return [
        t for t in re.findall(r"[a-z0-9]+", norm(s))
        if len(t) > 3 and t not in stop
    ]


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None


def load_target_journal():
    for path in (proj / "idea" / "journal-fit.json", proj / "idea" / "research-question.json"):
        obj = read_json(path)
        if not isinstance(obj, dict):
            continue
        values = []
        for key in ("primary_target", "target_journal", "journal", "primary"):
            value = obj.get(key)
            if isinstance(value, dict):
                values.extend(str(v) for v in value.values())
            elif value:
                values.append(str(value))
        if values:
            return " ".join(values)
    return ""


def asr_jmf_style_target():
    target = load_target_journal().lower()
    style_terms = (
        "american sociological review", "asr",
        "journal of marriage and family", "jmf",
        "american journal of sociology", "ajs",
        "demography", "social forces", "sociological methods",
    )
    return any(term in target for term in style_terms)


def load_hypotheses():
    candidates = []
    canonical_path = proj / "citations" / "hypotheses-canonical.json"
    if canonical_path.exists():
        obj = read_json(canonical_path)
        if isinstance(obj, dict) and isinstance(obj.get("hypotheses"), list):
            for row in obj["hypotheses"]:
                if not isinstance(row, dict):
                    continue
                hid = str(row.get("hypothesis_id") or row.get("id") or "").strip()
                statement = str(row.get("statement") or row.get("text") or "").strip()
                if hid and statement:
                    candidates.append({"id": hid, "statement": statement, "source": "citations/hypotheses-canonical.json"})
    if candidates:
        return candidates
    matrix_path = proj / "literature" / "literature-coverage-matrix.json"
    obj = read_json(matrix_path)
    if isinstance(obj, dict) and isinstance(obj.get("hypotheses"), list):
        for row in obj["hypotheses"]:
            if not isinstance(row, dict):
                continue
            hid = str(row.get("hypothesis_id") or row.get("id") or "").strip()
            statement = str(row.get("statement") or row.get("text") or "").strip()
            if hid and statement:
                candidates.append({"id": hid, "statement": statement, "source": "literature/literature-coverage-matrix.json"})
    return candidates


def heading_iter(text):
    for match in re.finditer(r"(?m)^(#{1,6})\s+(.+?)\s*$", text):
        raw = match.group(2).strip()
        clean = re.sub(r"\s+\{#.*?\}\s*$", "", raw).strip()
        clean = re.sub(r"^\d+(?:\.\d+)*\.?\s+", "", clean)
        yield {
            "level": len(match.group(1)),
            "title": clean,
            "key": norm(clean),
            "start": match.start(),
            "end": match.end(),
        }


def extract_theory_block(text):
    headings = list(heading_iter(text))
    if not headings:
        return ""
    theory_rx = re.compile(
        r"^(theory|theory and hypotheses|theoretical framework|"
        r"theoretical framework and hypotheses|theoretical background|"
        r"literature review and theory|background|conceptual framework)$",
        re.I,
    )
    stop_rx = re.compile(
        r"^(data|data and methods|data and method|methods|materials and methods|"
        r"results|findings|empirical results|discussion|conclusion)$",
        re.I,
    )
    for idx, heading in enumerate(headings):
        if not theory_rx.search(heading["title"]):
            continue
        stop = len(text)
        for later in headings[idx + 1:]:
            if later["level"] <= heading["level"] and stop_rx.search(later["title"]):
                stop = later["start"]
                break
            if later["level"] <= heading["level"] and theory_rx.search(later["title"]):
                stop = later["start"]
                break
        return text[heading["start"]:stop]
    return ""


def manuscript_paths_to_check():
    draft = proj / "manuscript" / "manuscript-draft.md"
    final = proj / "final" / "manuscript-final.md"
    submission = proj / "submission" / "manuscript-submission.md"
    if phase == "13":
        ordered = [draft]
    elif phase == "18":
        ordered = [draft, final]
    elif phase == "20":
        ordered = [submission, final]
    else:
        ordered = [draft, final, submission]
    return [path for path in ordered if path.exists()]


POST_RESULT_PATTERNS = [
    ("display_callout", re.compile(r"\b(?:Table|Figure|Model)\s+[0-9ivx]+\b", re.I)),
    ("inferential_statistic", re.compile(r"\bp\s*[<=>]\s*\.?\d|\b(coefficient|standard error|confidence interval|r[- ]?squared)\b", re.I)),
    ("evidence_revises_theory", re.compile(r"\b(?:the evidence|empirical pattern|findings|results)\b.{0,90}\b(?:revise|support|confirm|contradict|consistent|contrary|positive|negative|null-compatible|attenuation|estimate)", re.I | re.S)),
    ("estimate_language", re.compile(r"\b(?:positive|negative|mixed|null-compatible|weak)\b.{0,70}\b(?:estimate|estimates|result|results|evidence|model|attenuation)\b", re.I | re.S)),
    ("posthoc_payoff", re.compile(r"\b(theoretical payoff|opening expectation|hypothesis accounting|support for the paper does not require|allowed to revise|evidence is allowed to revise|null-compatible)\b", re.I)),
    ("opposite_pattern_escape", re.compile(r"\b(expectation|hypothesis)\b.{0,120}\bbut\b.{0,120}\b(opposite|either direction|positive or negative)\b", re.I | re.S)),
]


def check_theory_block(path, text, hypotheses, require_explicit_ids):
    issues = []
    block = extract_theory_block(text)
    rel = str(path.relative_to(proj))
    if not block:
        return [f"{rel}:theory_block_missing"]
    visible_block = re.sub(r"<!--.*?-->", " ", block, flags=re.S)
    for label, rx in POST_RESULT_PATTERNS:
        m = rx.search(visible_block)
        if m:
            snippet = re.sub(r"\s+", " ", m.group(0)).strip()[:160]
            issues.append(f"{rel}:theory_post_results_leakage:{label}:{snippet}")
            break
    block_norm = " " + norm(visible_block) + " "
    block_tokens = set(tokens(visible_block))
    missing = []
    missing_explicit = []
    for hyp in hypotheses:
        hid = hyp["id"]
        statement = hyp["statement"]
        id_present = re.search(rf"(?<![A-Za-z0-9]){re.escape(hid)}(?![A-Za-z0-9])", visible_block)
        stmt_tokens = set(tokens(statement))
        overlap = len(stmt_tokens & block_tokens) / max(1, len(stmt_tokens))
        statement_present = overlap >= 0.50 or norm(statement) in block_norm
        if not id_present and not statement_present:
            missing.append(hid)
        if require_explicit_ids and not id_present:
            missing_explicit.append(hid)
    if missing:
        issues.append(f"{rel}:canonical_hypotheses_missing_or_rewritten={','.join(missing)}")
    if missing_explicit:
        issues.append(f"{rel}:asr_jmf_target_requires_explicit_hypothesis_ids={','.join(missing_explicit)}")
    return issues


def check_drafting_plan():
    path = proj / "manuscript" / "drafting-plan.json"
    if not path.exists():
        return []
    obj = read_json(path)
    if not isinstance(obj, dict):
        return []
    risky = []
    section_briefs = obj.get("section_briefs")
    if isinstance(section_briefs, dict):
        theory_brief = section_briefs.get("theory") or section_briefs.get("literature review and theory")
        if isinstance(theory_brief, dict):
            risky.append(("section_briefs.theory", json.dumps(theory_brief, sort_keys=True)))
    paragraph_map = obj.get("paragraph_purpose_map")
    if isinstance(paragraph_map, list):
        theory_rows = [
            row for row in paragraph_map
            if isinstance(row, dict) and re.search(r"\b(theory|literature review and theory|hypothes)", str(row.get("section", "")), re.I)
        ]
        if theory_rows:
            risky.append(("paragraph_purpose_map[theory]", json.dumps(theory_rows, sort_keys=True)))
    leak_rx = re.compile(
        r"\b(locked|table\s+\d+|figure\s+\d+|results?|findings?|estimates?|positive generalized|"
        r"contrary to (?:the )?original|null-compatible|attenuation result|report H\d|focal adjusted)\b|"
        r"\b(?:tables|figures|results-locked)/",
        re.I,
    )
    issues = []
    for label, payload in risky:
        m = leak_rx.search(payload)
        if m:
            issues.append(f"manuscript/drafting-plan.json:{label}:theory_brief_uses_post_results_or_artifact_language:{m.group(0)}")
    return issues


hypotheses = load_hypotheses()
if not hypotheses:
    print("YELLOW:no_canonical_phase2_hypotheses")
    raise SystemExit(0)

paths = manuscript_paths_to_check()
if not paths:
    print("YELLOW:no_manuscript_to_check")
    raise SystemExit(0)

require_explicit = asr_jmf_style_target()
issues = []
for path in paths:
    text = path.read_text(encoding="utf-8", errors="replace")
    issues.extend(check_theory_block(path, text, hypotheses, require_explicit))
issues.extend(check_drafting_plan())

if issues:
    print("RED:" + ";".join(issues[:30]))
else:
    checked = ",".join(str(path.relative_to(proj)) for path in paths)
    source = hypotheses[0].get("source", "phase2")
    print(f"GREEN:checked={checked};hypotheses={len(hypotheses)};source={source};explicit_ids_required={str(require_explicit).lower()}")
PY
)

echo "PROJECT=${PROJ}"

case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=theory_hypothesis_continuity_failed"
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
