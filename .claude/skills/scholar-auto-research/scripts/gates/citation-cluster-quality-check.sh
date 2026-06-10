#!/usr/bin/env bash
# citation-cluster-quality-check.sh — reject omnibus and duplicate citation clusters.
#
# Journal prose should attach sources to specific claims. This gate catches
# two failure modes that otherwise pass bibliography checks: huge all-purpose
# citation clusters and duplicated rendered author-year pairs such as
# "Yang 2021, 2021".

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: citation-cluster-quality-check.sh <project_dir>"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "STATUS=YELLOW"
  echo "REASON=no_python3"
  exit 2
fi

result=$(python3 - "$PROJ" <<'PY'
import os
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])
phase = os.environ.get("AUTO_RESEARCH_VERIFY_PHASE", "").strip()

def manuscripts(project):
    if phase in {"13", "18"}:
        return [project / "manuscript" / "manuscript-draft.md"]
    paths = [
        project / "manuscript" / "manuscript-draft.md",
        project / "final" / "manuscript-final.md",
        project / "submission" / "manuscript-submission.md",
    ]
    drafts = project / "drafts"
    if drafts.is_dir():
        for pat in ("manuscript-final-*.md", "manuscript-submission-*.md", "draft-manuscript-*.md"):
            matches = sorted(drafts.glob(pat), key=lambda p: p.stat().st_mtime, reverse=True)
            if matches:
                paths.append(matches[0])
    present = [p for p in paths if p.exists()]
    if not present and drafts.is_dir():
        skip = ("scholar-lrh-", "scholar-write-log-", "scholar-polish-",
                "manuscript-tables-figures-captions-", "manuscript-section-")
        candidates = [f for f in drafts.glob("manuscript-*.md")
                      if not any(f.name.startswith(s) for s in skip)]
        candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        present = candidates[:1]
    return present

def rel(path):
    try:
        return str(path.relative_to(proj))
    except ValueError:
        return str(path)

present = manuscripts(proj)
if not present:
    print("YELLOW:no_manuscript_files_yet")
    raise SystemExit

issues = []
for path in present:
    text = path.read_text(encoding="utf-8", errors="replace")
    visible = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
    for m in re.finditer(r"\(([^()\n]{12,1200})\)", visible):
        cluster = m.group(1)
        line = visible[:m.start()].count("\n") + 1
        semicolon_count = cluster.count(";")
        citekey_count = len(re.findall(r"@[A-Za-z0-9_:\-]+", cluster))
        author_year_count = len(re.findall(r"\b[A-Z][A-Za-z.\-]+(?:\s+et\s+al\.)?\s+\d{4}[a-z]?\b", cluster))
        if semicolon_count >= 10 or citekey_count >= 10 or author_year_count >= 12:
            issues.append(f"{rel(path)}:{line}:oversized_citation_cluster")
            continue
        if re.search(r"\b([A-Z][A-Za-z.\-]+(?:\s+et\s+al\.)?)\s+(\d{4}[a-z]?)\s*,\s*\2\b", cluster):
            issues.append(f"{rel(path)}:{line}:duplicate_author_year")
            continue
        if re.search(r"\b(?:broader literature|research repeatedly shows|literature supports)\b", visible[max(0, m.start()-180):m.start()+80], re.I):
            if semicolon_count >= 5 or citekey_count >= 5 or author_year_count >= 6:
                issues.append(f"{rel(path)}:{line}:omnibus_background_citation")

if issues:
    print("RED:" + ";".join(issues[:60]))
else:
    print(f"GREEN:{len(present)}")
PY
)

echo "PROJECT=${PROJ}"
case "$result" in
  GREEN:*)
    echo "STATUS=GREEN"
    echo "REASON=citation_clusters_specific"
    echo "DETAIL: checked=${result#GREEN:}"
    exit 0 ;;
  RED:*)
    echo "STATUS=RED"
    echo "REASON=citation_cluster_quality_failure"
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
