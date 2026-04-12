#!/usr/bin/env bash
# Claim Verification Gate
# Usage: bash scripts/gates/verify-claims.sh <draft_path>
# Scans a manuscript draft for prose claims that attribute findings to cited sources
# and flags potential mischaracterization patterns:
#   - CLAIM-REVERSED markers (critical errors — finding direction wrong)
#   - CLAIM-MISCHARACTERIZED markers (finding meaningfully different from source)
#   - CLAIM-OVERCAUSAL markers (causal language for correlational findings)
#   - CLAIM-WRONG-POPULATION markers (population/context mismatch)
#   - CLAIM-UNSUPPORTED markers (source doesn't address the claim)
#   - CLAIM-IMPRECISE markers (overstated/simplified)
#   - CLAIM-NOT-CHECKABLE markers (could not verify)
#   - Causal language patterns without hedging near citation contexts
#   - Strong directional claims ("proves", "demonstrates conclusively") near citations
#
# This gate checks for MARKERS left by scholar-citation Step V-3.5.
# It also does heuristic detection of risky prose patterns.
#
# Exit codes: 0 = clean, 1 = issues found
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: verify-claims.sh <draft_path>" >&2
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "ERROR: File not found: $FILE" >&2
  exit 1
fi

# Reject binary files (docx, pdf, etc.)
if file --brief "$FILE" | grep -qiE 'binary|zip|pdf|microsoft'; then
  echo "ERROR: Binary file detected. Convert to .md or .txt first." >&2
  exit 1
fi

if [ ! -s "$FILE" ]; then
  echo "WARNING: File is empty" >&2
fi

ISSUES=0
WARNINGS=0

# === Check for claim verification markers (left by Step V-3.5) ===
# Note: || true handles grep exit code 1 (no match) under set -e.
# We do NOT suppress stderr — real I/O errors should surface.

REVERSED=$(grep -c '\[CLAIM-REVERSED[]:]' "$FILE" || true)
if [ "$REVERSED" -gt 0 ]; then
  echo "CRITICAL: $REVERSED [CLAIM-REVERSED] marker(s) — cited source contradicts the claim direction"
  ISSUES=$((ISSUES + REVERSED))
fi

MISCHAR=$(grep -c '\[CLAIM-MISCHARACTERIZED[]:]' "$FILE" || true)
if [ "$MISCHAR" -gt 0 ]; then
  echo "ERROR: $MISCHAR [CLAIM-MISCHARACTERIZED] marker(s) — finding meaningfully different from source"
  ISSUES=$((ISSUES + MISCHAR))
fi

OVERCAUSAL=$(grep -c '\[CLAIM-OVERCAUSAL[]:]' "$FILE" || true)
if [ "$OVERCAUSAL" -gt 0 ]; then
  echo "ERROR: $OVERCAUSAL [CLAIM-OVERCAUSAL] marker(s) — causal language for correlational finding"
  ISSUES=$((ISSUES + OVERCAUSAL))
fi

WRONGPOP=$(grep -c '\[CLAIM-WRONG-POPULATION[]:]' "$FILE" || true)
if [ "$WRONGPOP" -gt 0 ]; then
  echo "WARNING: $WRONGPOP [CLAIM-WRONG-POPULATION] marker(s) — population/context mismatch"
  WARNINGS=$((WARNINGS + WRONGPOP))
fi

UNSUPPORTED=$(grep -c '\[CLAIM-UNSUPPORTED[]:]' "$FILE" || true)
if [ "$UNSUPPORTED" -gt 0 ]; then
  echo "ERROR: $UNSUPPORTED [CLAIM-UNSUPPORTED] marker(s) — source doesn't address claim"
  ISSUES=$((ISSUES + UNSUPPORTED))
fi

IMPRECISE=$(grep -c '\[CLAIM-IMPRECISE[]:]' "$FILE" || true)
if [ "$IMPRECISE" -gt 0 ]; then
  echo "WARNING: $IMPRECISE [CLAIM-IMPRECISE] marker(s) — claim overstated or simplified"
  WARNINGS=$((WARNINGS + IMPRECISE))
fi

NOTCHECK=$(grep -c '\[CLAIM-NOT-CHECKABLE[]:]' "$FILE" || true)
if [ "$NOTCHECK" -gt 0 ]; then
  echo "INFO: $NOTCHECK [CLAIM-NOT-CHECKABLE] marker(s) — author must manually verify"
fi

# === Heuristic: detect risky causal language near citations ===
# Look for strong causal verbs within ~80 chars of a citation pattern (Author Year).
# Uses a single grep pass with alternation to avoid double-counting lines where
# a causal verb appears on both sides of a citation.
# These are patterns that Step V-3.5 should have flagged — if they remain without
# a CLAIM-VERIFIED or CLAIM-OVERCAUSAL tag, they're suspicious.

CAUSAL_WORDS='proves|causes|leads to|produces|results in|demonstrates conclusively|establishes that|confirms that'
# Match citation forms broadly: any parenthesized text ending in a 4-digit year,
# or a capitalized name followed by (year). Handles multi-word surnames, APA commas,
# ASA spaces, signal-phrase, and et al.
CITE_PAT='(\([A-Za-z][A-Za-z '"'"' &.,-]+ [12][0-9]{3}[a-z]?\)|[A-Z][A-Za-z'"'"'-]+( (and|&) [A-Z][A-Za-z'"'"'-]+)?( et al\.?)? \([12][0-9]{3}[a-z]?\))'
TOTAL_CAUSAL=$(grep -cE "(${CAUSAL_WORDS}).{0,80}${CITE_PAT}|${CITE_PAT}.{0,80}(${CAUSAL_WORDS})" "$FILE" || true)

if [ "$TOTAL_CAUSAL" -gt 0 ]; then
  echo "WARNING: $TOTAL_CAUSAL instance(s) of strong causal language near citations — verify these passed Step V-3.5 claim check"
  WARNINGS=$((WARNINGS + TOTAL_CAUSAL))
fi

# === Summary ===
TOTAL_MARKERS=$((REVERSED + MISCHAR + OVERCAUSAL + UNSUPPORTED + WRONGPOP + IMPRECISE + NOTCHECK))

if [ "$TOTAL_MARKERS" -eq 0 ] && [ "$TOTAL_CAUSAL" -eq 0 ]; then
  echo "RESULT: Claim verification gate passed — no markers or risky patterns found"
  exit 0
fi

if [ "$ISSUES" -gt 0 ]; then
  echo ""
  echo "RESULT: FAIL — $ISSUES critical/error claim issue(s) must be resolved before submission"
  echo "  Run /scholar-citation verify on the draft to correct these errors"
  exit 1
else
  # Only warnings/not-checkable markers remain — does not block submission
  echo ""
  echo "RESULT: PASS with $WARNINGS warning(s) and $NOTCHECK not-checkable claim(s)"
  echo "  Warnings require author review but do not block submission"
  exit 0
fi
