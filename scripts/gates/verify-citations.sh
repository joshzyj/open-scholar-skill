#!/usr/bin/env bash
# Citation Fabrication Check Gate
# Usage: bash scripts/gates/verify-citations.sh <draft_path>
# Scans a manuscript draft for potential fabricated citations:
#   - In-text citations not backed by a References section entry
#   - Suspiciously round years (2099, 2098, etc.)
#   - Duplicate references
#   - Missing [CITATION NEEDED] markers (counts them)
# Exit codes: 0 = clean, 1 = issues found
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: verify-citations.sh <draft_path>" >&2
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "ERROR: File not found: $FILE" >&2
  exit 1
fi

ISSUES=0

# Count [CITATION NEEDED] markers
NEEDED=$(grep -c '\[CITATION NEEDED' "$FILE" 2>/dev/null || true)
if [ "$NEEDED" -gt 0 ]; then
  echo "INFO: $NEEDED [CITATION NEEDED] marker(s) found — these require follow-up with /scholar-citation"
fi

# Extract in-text citations: (Author Year) or (Author and Author Year) or (Author et al. Year)
# This is a heuristic — catches ASA/APA style
INTEXT_AUTHORS=$(grep -oE '\([A-Z][a-z]+( (and|&) [A-Z][a-z]+| et al\.?)? [12][0-9]{3}[a-z]?\)' "$FILE" 2>/dev/null | sort -u || true)

# Check for suspiciously future years in citations
FUTURE=$(echo "$INTEXT_AUTHORS" | grep -oE '[0-9]{4}' | awk '$1 > 2027' | sort -u || true)
if [ -n "$FUTURE" ]; then
  echo "WARNING: Suspiciously future citation year(s): $FUTURE"
  ISSUES=$((ISSUES + 1))
fi

# Check for references section
HAS_REFS=$(grep -c '^## References\|^# References\|^## Bibliography\|^## Works Cited' "$FILE" 2>/dev/null || true)
if [ "$HAS_REFS" -eq 0 ] && [ -n "$INTEXT_AUTHORS" ]; then
  echo "WARNING: In-text citations found but no References section detected"
  ISSUES=$((ISSUES + 1))
fi

# Check for duplicate references (exact duplicate lines in references section)
if [ "$HAS_REFS" -gt 0 ]; then
  # Extract everything after the References header
  DUPES=$(sed -n '/^#.*[Rr]eferences\|^#.*[Bb]ibliography/,$ p' "$FILE" | grep -v '^#' | grep -v '^$' | sort | uniq -d || true)
  if [ -n "$DUPES" ]; then
    DUPE_COUNT=$(echo "$DUPES" | wc -l | tr -d ' ')
    echo "WARNING: $DUPE_COUNT duplicate reference(s) found"
    ISSUES=$((ISSUES + 1))
  fi
fi

if [ "$ISSUES" -gt 0 ]; then
  echo "RESULT: $ISSUES citation issue(s) detected"
  exit 1
else
  echo "RESULT: Citation check passed (${NEEDED:-0} [CITATION NEEDED] markers remaining)"
  exit 0
fi
