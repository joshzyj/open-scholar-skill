#!/usr/bin/env bash
# data-sample-flow-check.sh — Methods Data/Sample sample-descent gate.
#
# Empirical manuscripts must tell readers how the source data became the
# analytic sample. This gate is intentionally manuscript-facing: it checks for
# original/source N, final analytic N, restriction/missingness logic, and a
# justification for the final analytic sample in the Data/Sample prose.

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: data-sample-flow-check.sh <project_dir>"
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

def has_structured_empirical_inputs():
    if (proj / "analysis" / "spec-registry.csv").exists():
        return True
    routing_text = "\n".join(
        read_text(p)
        for p in [
            proj / "design" / "design-manifest.json",
            proj / "design" / "design-blueprint.md",
            proj / "design" / "identification-strategy.json",
            proj / "analysis" / "analysis-plan.md",
        ]
    ).lower()
    return bool(
        re.search(
            r"\b(computational|machine learning|text-as-data|text as data|nlp|llm|network|"
            r"agent[- ]based|simulation|computer vision|audio|geospatial|sequence|survey|"
            r"panel|administrative|experiment|regression|observational|corpus|documents?)\b",
            routing_text,
        )
    )

if not has_structured_empirical_inputs():
    print("INERT:no_structured_empirical_inputs")
    raise SystemExit

if phase in {"13", "18"}:
    paths = [proj / "manuscript" / "manuscript-draft.md"]
else:
    # Path-adapt (master-plan-v4 P1+Update 6): include scholar-full-paper
    # drafts/ candidates so this gate works under both pipeline layouts.
    paths = [
        proj / "manuscript" / "manuscript-draft.md",
        proj / "final" / "manuscript-final.md",
        proj / "submission" / "manuscript-submission.md",
    ]
    drafts_dir = proj / "drafts"
    if drafts_dir.is_dir():
        # Pick newest match for each canonical full-paper pattern.
        for pat in ("manuscript-final-*.md", "manuscript-submission-*.md", "draft-manuscript-*.md"):
            matches = sorted(drafts_dir.glob(pat), key=lambda p: p.stat().st_mtime, reverse=True)
            if matches:
                paths.append(matches[0])
        # Generic fallback: hand-named experimental manuscripts (only if no
        # canonical match present in `present` after the loop below).
        # Done via a deferred check after `present` is computed.
present = [p for p in paths if p.exists()]
# Generic fallback for full-paper layout: if no canonical manuscript found
# but `drafts/manuscript-*.md` exist (hand-named experimental drafts),
# pick the newest excluding logs/sections/lit-review.
if not present and (proj / "drafts").is_dir():
    drafts_dir = proj / "drafts"
    skip = ("scholar-lrh-", "scholar-write-log-", "scholar-polish-",
            "manuscript-tables-figures-captions-", "manuscript-section-")
    candidates = []
    for f in drafts_dir.glob("manuscript-*.md"):
        if any(f.name.startswith(s) for s in skip): continue
        candidates.append(f)
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    if candidates:
        present = [candidates[0]]
if not present:
    print("YELLOW:no_manuscript_files_yet")
    raise SystemExit

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

def extract_data_sample_text(text):
    sections = parse_sections(text)
    methods = find_section(
        sections,
        r"^(data[, ]+measures[, ]+and methods|data and methods|data and method|"
        r"materials and methods|methods|method)$",
    )
    if not methods:
        return "", "missing_methods_section"
    children = child_sections(sections, methods)
    data_children = [
        sec
        for sec in children
        if re.search(
            r"\b(data(?: source)?|data and sample|sample|analytic sample|empirical setting|"
            r"corpus|study population|participants|cases)\b",
            sec["title"],
            re.I,
        )
    ]
    if data_children:
        first = min(data_children, key=lambda s: s["start"])
        return "\n\n".join(sec["title"] + "\n" + sec["body"] for sec in data_children), "data_subsection"
    return methods["body"], "methods_fallback"

def count_mentions(text):
    mentions = []
    rx1 = re.compile(r"\b[Nn]\s*(?:=|≈|~|:)\s*([0-9][0-9,]{1,})\b")
    rx2 = re.compile(
        r"\b([0-9][0-9,]{1,})\s+"
        r"(respondents?|participants?|individuals?|persons?|people|households?|families|"
        r"observations?|person[- ]years?|cases?|records?|documents?|articles?|posts?|tweets?|"
        r"messages?|images?|audio clips?|nodes?|edges?|dyads?|units?|interviews?|waves?)\b",
        re.I,
    )
    for rx in (rx1, rx2):
        for match in rx.finditer(text):
            raw = match.group(1).replace(",", "")
            try:
                value = int(raw)
            except Exception:
                continue
            if value < 20:
                continue
            start = max(0, match.start() - 180)
            stop = min(len(text), match.end() + 180)
            mentions.append((value, text[start:stop]))
    return mentions

original_re = re.compile(
    r"\b(original|initial|source|raw|starting|baseline|full sample|all respondents|"
    r"all households|all records|surveyed|interviewed|data contain|data include|"
    r"nationally representative|sampling frame|wave|corpus contain)\b",
    re.I,
)
final_re = re.compile(
    r"\b(final analytic sample|analytic sample|estimation sample|analysis sample|"
    r"final sample|complete[- ]case sample|matched sample|risk set|retained|"
    r"we analyze|analysis includes|models include|main models use|final corpus)\b",
    re.I,
)
restriction_re = re.compile(
    r"\b(restrict|restricted|restrictions?|exclude|excluded|exclusions?|drop|dropped|remove|removed|eligible|"
    r"inclusion|exclusion|nonmissing|non-missing|missing(?:ness)?|complete[- ]case|"
    r"valid response|structural skip|skip pattern|inapplicable|after omitting|"
    r"after applying|retained|available on|observed(?: on)?|harmoniz)\b",
    re.I,
)
justification_re = re.compile(
    r"\b(because|so that|to ensure|to align|aligns with|appropriate|eligible|risk set|"
    r"requires|requirement|research question|theoretical|theory|measurement|identification|"
    r"estimator|model|scope|population at risk|denominator|comparable|valid|available)\b",
    re.I,
)

issues = []
for path in present:
    text = strip_comments(read_text(path))
    sample_text, source = extract_data_sample_text(text)
    rel = path.relative_to(proj)
    if not sample_text.strip():
        issues.append(f"{rel}:missing_data_sample_text")
        continue
    wc = word_count(sample_text)
    mentions = count_mentions(sample_text)
    original_hits = [m for m in mentions if original_re.search(m[1])]
    final_hits = [m for m in mentions if final_re.search(m[1])]
    if wc < 90:
        issues.append(f"{rel}:data_sample_too_thin")
    if not mentions:
        issues.append(f"{rel}:no_sample_size_mentions")
    if len(mentions) < 2:
        issues.append(f"{rel}:needs_original_and_final_n")
    if not original_hits:
        issues.append(f"{rel}:missing_original_source_n")
    if not final_hits:
        issues.append(f"{rel}:missing_final_analytic_n")
    if not restriction_re.search(sample_text):
        issues.append(f"{rel}:missing_restriction_or_missingness_logic")
    if not justification_re.search(sample_text):
        issues.append(f"{rel}:missing_analytic_sample_justification")
    if source == "methods_fallback":
        issues.append(f"{rel}:missing_explicit_data_sample_subsection")

if issues:
    print("RED:" + ";".join(issues[:50]))
else:
    print(f"GREEN:{len(present)}")
PY
)

echo "PROJECT=${PROJ}"
case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=data_sample_flow_complete"
    echo "DETAIL: checked=${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=data_sample_flow_failure"
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
