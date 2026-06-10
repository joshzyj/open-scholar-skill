#!/usr/bin/env bash
# manuscript-title-check.sh — Phase 13 / 19 / 20 structural gate.
#
# Rationale: a run can ship manuscript-draft.md, manuscript-final.md, AND
# manuscript-submission.md all opening directly at `## Abstract` with no
# manuscript title. No
# Phase 12 / 13 / 19 / 20 contract required a title field, so the gap
# was invisible to every existing gate. Existing title-* gates
# (title-outcome-check, title-claim-vs-headline-stat-check) PRESUME a
# title exists and audit its claims; they cannot detect absence.
#
# Contract
# --------
# Every produced manuscript Markdown must declare a title in one of:
#   - YAML frontmatter `title:` field (must come before any `##` line);
#   - top-level `# <Title>` H1 line BEFORE the first `## Abstract`;
#   - LaTeX `\title{...}` command (for .tex derivatives, when checked).
#
# A document whose first non-comment, non-frontmatter, non-blank line is
# `## Abstract` (or any `## ...` heading) is RED — the manuscript has
# no title.
#
# Title content rules
# -------------------
# YELLOW if the title is present but is placeholder-ish:
#   - exactly `<TITLE>` / `<title>` / `TBD` / `TODO` / `Untitled`;
#   - bracketed placeholder `[...]` with no other content;
#   - shorter than 12 characters.
#
# Inputs
# ------
#   $1   project directory (required)
#
# The gate scans both pipelines' canonical manuscript locations:
#   scholar-auto-research:
#     - manuscript/manuscript-draft.md
#     - final/manuscript-final.md
#     - submission/manuscript-submission.md
#   scholar-full-paper:
#     - drafts/manuscript-final-<slug>-<date>.md
#     - drafts/manuscript-submission-<slug>-<date>.md
#     - drafts/draft-manuscript-<slug>-<date>.md
#     - drafts/manuscript-*.md (generic fallback for hand-named drafts)
# Missing files are skipped (YELLOW) — a downstream phase has not yet run.
#
# Exit
# ----
#   0  STATUS=GREEN   all present manuscripts have a real title
#   1  STATUS=RED     at least one manuscript begins at `## Abstract`
#   2  STATUS=YELLOW  placeholder title OR no manuscripts present yet

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage: manuscript-title-check.sh <project_dir>"
  exit 2
fi

CANDIDATES=(
  "$PROJ/manuscript/manuscript-draft.md"
  "$PROJ/final/manuscript-final.md"
  "$PROJ/submission/manuscript-submission.md"
)

PRESENT_FILES=()
for f in "${CANDIDATES[@]}"; do
  [ -f "$f" ] && PRESENT_FILES+=("$f")
done

# scholar-full-paper layout: drafts/<canonical-pattern>.md. Use find -print0
# to be safe with spaces in paths (Google-Drive-mounted projects). Take the
# newest file matching each canonical pattern; the gate then audits each
# present manuscript independently.
_mtc_newest() {
  local dir="$1" pat="$2"
  [ -d "$dir" ] || { printf ''; return 0; }
  local newest="" newest_mt=0 mt
  while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    if stat --version >/dev/null 2>&1; then
      mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    else
      mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
    fi
    mt=${mt:-0}
    if [ "$mt" -gt "$newest_mt" ]; then newest_mt=$mt; newest=$f; fi
  done < <(find "$dir" -maxdepth 1 -type f -name "$pat" -print0 2>/dev/null)
  printf '%s' "$newest"
}

for pat in "manuscript-final-*.md" "manuscript-submission-*.md" "draft-manuscript-*.md"; do
  cand=$(_mtc_newest "$PROJ/drafts" "$pat")
  if [ -n "$cand" ]; then
    PRESENT_FILES+=("$cand")
  fi
done

# Generic fallback: hand-named drafts/manuscript-*.md (e.g., user's
# experimental v2 outputs). Only fires if no canonical match was found
# above. Excludes scholar-write logs and section-level fragments.
if [ "${#PRESENT_FILES[@]}" -eq 0 ] && [ -d "$PROJ/drafts" ]; then
  newest_mt=0; newest=""
  while IFS= read -r -d '' f; do
    base=$(basename "$f")
    case "$base" in
      scholar-lrh-*|scholar-write-log-*|scholar-polish-*) continue ;;
      manuscript-tables-figures-captions-*|manuscript-section-*) continue ;;
    esac
    if stat --version >/dev/null 2>&1; then
      mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    else
      mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
    fi
    mt=${mt:-0}
    if [ "$mt" -gt "$newest_mt" ]; then newest_mt=$mt; newest=$f; fi
  done < <(find "$PROJ/drafts" -maxdepth 1 -type f -name "manuscript-*.md" -print0 2>/dev/null)
  [ -n "$newest" ] && PRESENT_FILES+=("$newest")
fi

if [ "${#PRESENT_FILES[@]}" -eq 0 ]; then
  echo "STATUS=YELLOW"
  echo "REASON=no_manuscript_files_yet"
  exit 2
fi

RED_HITS=()
YELLOW_HITS=()

for ms in "${PRESENT_FILES[@]}"; do
  rel="${ms#$PROJ/}"

  # Use python3 for robust YAML / first-non-trivial-line parsing.
  result=$(python3 - "$ms" <<'PY'
import re, sys, pathlib

ms_path = pathlib.Path(sys.argv[1])
text = ms_path.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()

# Strip leading blank lines + HTML comments (locked-artifact markers, etc.)
i = 0
n = len(lines)
in_html_comment = False
while i < n:
    s = lines[i]
    stripped = s.strip()
    if not stripped:
        i += 1; continue
    if in_html_comment:
        if "-->" in s:
            in_html_comment = False
        i += 1; continue
    if stripped.startswith("<!--") and "-->" not in stripped:
        in_html_comment = True
        i += 1; continue
    if stripped.startswith("<!--") and stripped.endswith("-->"):
        i += 1; continue
    break

# Detect YAML frontmatter title
yaml_title = None
if i < n and lines[i].strip() == "---":
    j = i + 1
    while j < n and lines[j].strip() != "---":
        m = re.match(r"^title\s*:\s*(.+?)\s*$", lines[j])
        if m:
            yaml_title = m.group(1).strip().strip("'\"")
        j += 1
    if j < n:
        i = j + 1
        # skip blank lines after closing ---
        while i < n and not lines[i].strip():
            i += 1

# Detect H1 BEFORE any `##` heading. Continue scanning even if YAML
# title was found — a body H1 alongside YAML title is the dual-title
# defect that produced two visible titles in pandoc-rendered output.
h1_title = None
k = i
while k < n:
    s = lines[k]
    stripped = s.strip()
    if not stripped:
        k += 1; continue
    if stripped.startswith("<!--") and stripped.endswith("-->"):
        k += 1; continue
    if stripped.startswith("# ") and not stripped.startswith("##"):
        h1_title = stripped[2:].strip()
        break
    # First non-trivial line is a `##` heading or anything else; stop.
    break

# Adjudicate
if yaml_title and h1_title:
    # Dual title failure mode: both a YAML title and an H1 title are present.
    # Pandoc renders both; reviewers see two titles. RED.
    snippet = (h1_title[:60] + "...") if len(h1_title) > 60 else h1_title
    print(f"RED:dual_title:yaml_and_h1::{snippet}")
    sys.exit(0)

title = yaml_title or h1_title
title_source = "yaml" if yaml_title else ("h1" if h1_title else None)

if title is None:
    print("RED:no_title")
    sys.exit(0)

# Placeholder detection
placeholders = {"<title>", "tbd", "todo", "untitled"}
if title.lower() in placeholders:
    print(f"YELLOW:placeholder:{title}")
    sys.exit(0)
if re.fullmatch(r"\[\s*[^\]]*\s*\]", title):
    print(f"YELLOW:bracket_placeholder:{title}")
    sys.exit(0)
if len(title) < 12:
    print(f"YELLOW:short_title:{title}")
    sys.exit(0)

print(f"GREEN:{title_source}:{title}")
PY
)
  if [[ "$result" == RED:* ]]; then
    RED_HITS+=("$rel: ${result#RED:}")
  elif [[ "$result" == YELLOW:* ]]; then
    YELLOW_HITS+=("$rel: ${result#YELLOW:}")
  fi
done

echo "PROJECT=${PROJ}"
echo "CHECKED_FILES=${#PRESENT_FILES[@]}"

if [ "${#RED_HITS[@]}" -gt 0 ]; then
  echo "STATUS=RED"
  # Distinguish the two RED reasons in the verdict line so phase-verify
  # back-route can route to a specific remediation.
  if printf '%s\n' "${RED_HITS[@]}" | grep -q 'dual_title'; then
    echo "REASON=dual_title"
  else
    echo "REASON=missing_title"
  fi
  printf 'DETAIL: %s\n' "${RED_HITS[@]}"
  cat >&2 <<EOF
FAIL: manuscript title check — at least one manuscript file fails the
single-title rule. A publication manuscript must declare EXACTLY ONE
title, via either:
  - YAML frontmatter \`title: ...\` field, OR
  - top-level \`# <Title>\` H1 line BEFORE the first section heading.
Declaring BOTH (YAML title AND a body H1) renders two visible titles in
pandoc-converted DOCX/PDF — the dual-title defect.
EOF
  exit 1
fi

if [ "${#YELLOW_HITS[@]}" -gt 0 ]; then
  echo "STATUS=YELLOW"
  echo "REASON=placeholder_or_short_title"
  printf 'DETAIL: %s\n' "${YELLOW_HITS[@]}"
  exit 2
fi

echo "STATUS=GREEN"
echo "REASON=titles_present"
exit 0
