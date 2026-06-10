#!/usr/bin/env bash
# front-matter-check.sh — title / abstract / keywords gate.
#
# ASR- and JMF-style exemplars both use article front matter as part
# of the scholarly argument: a real title, a compact empirical abstract, and
# keywords. A manuscript that starts at `## Abstract`, lacks keywords for an
# ASR/JMF-style target, or puts Table/Figure callouts in the abstract is not
# submission-shaped even if later sections exist.

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: front-matter-check.sh <project_dir>"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$PROJ" <<'PY'
import json
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])

manuscripts = [
    proj / "manuscript" / "manuscript-draft.md",
    proj / "final" / "manuscript-final.md",
    proj / "submission" / "manuscript-submission.md",
]
present = [path for path in manuscripts if path.exists()]
if not present:
    print("YELLOW:no_manuscript_files_yet")
    raise SystemExit


def norm(value):
    return re.sub(r"[^a-z0-9]+", " ", str(value or "").lower()).strip()


def word_count(value):
    return len(re.findall(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)?", str(value or "")))


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def target_journal():
    candidates = [
        load_json(proj / "manuscript" / "journal-spec.json").get("target_journal"),
        load_json(proj / "manuscript" / "manuscript-blueprint.json").get("target_journal"),
        load_json(proj / "idea" / "journal-fit.json").get("primary_target"),
    ]
    rq = load_json(proj / "idea" / "research-question.json")
    if isinstance(rq.get("target_journal"), dict):
        candidates.append(rq["target_journal"].get("primary"))
    for candidate in candidates:
        if str(candidate or "").strip():
            return norm(candidate)
    return ""


KEYWORD_JOURNALS = {
    "american sociological review",
    "asr",
    "american journal of sociology",
    "ajs",
    "journal of marriage and family",
    "jmf",
    "demography",
    "social forces",
    "social problems",
    "population and development review",
    "pdr",
    "poetics",
    "sociological methods and research",
    "smr",
}

journal = target_journal()
keywords_required = any(j == journal or (len(j) > 3 and j in journal) for j in KEYWORD_JOURNALS)
empirical = (proj / "analysis" / "spec-registry.csv").exists()


def strip_leading_comments(lines):
    i = 0
    in_html_comment = False
    while i < len(lines):
        stripped = lines[i].strip()
        if not stripped:
            i += 1
            continue
        if in_html_comment:
            if "-->" in stripped:
                in_html_comment = False
            i += 1
            continue
        if stripped.startswith("<!--"):
            if "-->" not in stripped:
                in_html_comment = True
            i += 1
            continue
        break
    return i


def parse_title(text):
    lines = text.splitlines()
    i = strip_leading_comments(lines)
    title = ""
    if i < len(lines) and lines[i].strip() == "---":
        j = i + 1
        while j < len(lines) and lines[j].strip() != "---":
            m = re.match(r"^title\s*:\s*(.+?)\s*$", lines[j])
            if m:
                title = m.group(1).strip().strip("'\"")
            j += 1
        if title:
            return title
        if j < len(lines):
            i = j + 1
    while i < len(lines):
        stripped = lines[i].strip()
        if not stripped or stripped.startswith("<!--"):
            i += 1
            continue
        if stripped.startswith("# ") and not stripped.startswith("##"):
            return stripped[2:].strip()
        return ""
    return ""


def section_body(text, heading):
    pattern = re.compile(rf"^##\s+{re.escape(heading)}\s*$([\s\S]*?)(?=^##\s+|\Z)", re.I | re.M)
    match = pattern.search(text)
    return match.group(1).strip() if match else ""


def keyword_count(text):
    # YAML one-line or list form.
    yaml_match = re.search(r"(?ms)^---\s*(.*?)^---", text)
    if yaml_match:
        yaml = yaml_match.group(1)
        one_line = re.search(r"(?m)^keywords?\s*:\s*(.+?)\s*$", yaml, re.I)
        if one_line:
            value = one_line.group(1).strip().strip("[]")
            return len([x for x in re.split(r"[,;]", value) if x.strip()])
        block = re.search(r"(?ms)^keywords?\s*:\s*\n((?:\s*-\s+.+\n?)+)", yaml, re.I)
        if block:
            return len(re.findall(r"(?m)^\s*-\s+\S", block.group(1)))
    section = section_body(text, "Keywords")
    if section:
        return len([x for x in re.split(r"[,;\n]", section) if x.strip()])
    line = re.search(r"(?im)^keywords?\s*:\s*(.+?)\s*$", text)
    if line:
        return len([x for x in re.split(r"[,;]", line.group(1)) if x.strip()])
    return 0


issues = []
for path in present:
    rel = str(path.relative_to(proj))
    text = path.read_text(encoding="utf-8", errors="replace")
    title = parse_title(text)
    if len(title) < 12 or norm(title) in {"untitled", "todo", "tbd", "title"}:
        issues.append(f"{rel}:missing_or_placeholder_title")
    abstract = section_body(text, "Abstract")
    if not abstract:
        issues.append(f"{rel}:missing_abstract")
    else:
        if empirical and word_count(abstract) < 80:
            issues.append(f"{rel}:abstract_too_short")
        if re.search(r"\b(?:Table|Figure|Fig\.?)\s+[0-9ivx]+\b", abstract, re.I):
            issues.append(f"{rel}:abstract_contains_display_callout")
    if keywords_required and keyword_count(text) < 3:
        issues.append(f"{rel}:missing_keywords_for_{journal or 'target_journal'}")

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
    echo "REASON=front_matter_complete"
    echo "DETAIL: checked=${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=front_matter_incomplete"
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
