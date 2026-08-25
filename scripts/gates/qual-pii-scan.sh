#!/usr/bin/env bash
# qual-pii-scan.sh — count-only PII scan for the scholar-qual regex fallback.
#
# CONTRACT (C-01 privacy fix, 2026-07-10):
#   * stdout/stderr carry ONLY category counts and a pass/fail summary.
#   * Matched PII VALUES are NEVER printed to stdout or stderr, because a
#     shell command's output is returned to the model. Printing matched
#     names/emails/phones/DOB/IDs defeats the "no data to AI" guarantee.
#   * When a DETAIL path is supplied, the matched values (which a human
#     coder legitimately needs to build the pseudonym key) are written to
#     that file with 0600 permissions. That artifact is human-review-only
#     and MUST NOT be Read into model context.
#
# Detection patterns are intentionally identical to the former inline
# scholar-qual regex block — only the output channel changed.
#
# Usage:   qual-pii-scan.sh <data_file> [detail_out_file]
# Exit:    0 = no PII candidates found
#          1 = PII candidates found (review DETAIL, build pseudonym key)
#          2 = usage / file error
set -u

FILE="${1:-}"
DETAIL="${2:-}"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "ERROR: qual-pii-scan.sh requires an existing data file path" >&2
  exit 2
fi

# Create the detail artifact up front with restrictive perms (0600) so the
# matched values are never world-readable. Fail closed if it cannot be made
# private.
if [ -n "$DETAIL" ]; then
  ( umask 077; : > "$DETAIL" ) || { echo "ERROR: cannot create detail file: $DETAIL" >&2; exit 2; }
  chmod 600 "$DETAIL" 2>/dev/null || true
  {
    echo "PII scan detail for: $FILE"
    echo "HUMAN REVIEW ONLY — do NOT read this file into any AI/model context."
    echo
  } >> "$DETAIL"
fi

TOTAL=0

# scan_cat <label> <grep-flags> <pattern>
#   Runs the category grep, counts unique matches, prints ONLY the count,
#   and (if DETAIL is set) appends the unique matched values to the 0600 file.
scan_cat() {
  _label="$1"; _flags="$2"; _pat="$3"
  _matches="$(grep $_flags "$_pat" "$FILE" 2>/dev/null | sort -u)"
  _n=0
  if [ -n "$_matches" ]; then
    _n="$(printf '%s\n' "$_matches" | grep -c .)"
  fi
  echo "  ${_label}: ${_n} candidate(s)"
  if [ -n "$DETAIL" ] && [ -n "$_matches" ]; then
    { echo "== ${_label} =="; printf '%s\n' "$_matches"; echo; } >> "$DETAIL"
  fi
  TOTAL=$((TOTAL + _n))
}

echo "=== PII SCAN (counts only): $(basename "$FILE") ==="
scan_cat "Person-name candidates (capitalized word pairs)" "-oE"  '\b[A-Z][a-z]+\s+[A-Z][a-z]+\b'
scan_cat "Email candidates"                                "-oiE" '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
scan_cat "Phone-number candidates"                         "-oE"  '(\+?1[-.\s]?)?(\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}'
scan_cat "Street-address candidates"                       "-oiE" '\d+\s+[A-Z][a-z]+\s+(St|Street|Ave|Avenue|Blvd|Boulevard|Rd|Road|Dr|Drive|Ln|Lane|Ct|Court|Way|Pl|Place)\b'
scan_cat "Date-of-birth candidates"                        "-oiE" '(born|DOB|date of birth|birthday)[:[:space:]]+.{5,20}'
scan_cat "SSN/ID-number candidates"                        "-oE"  '\b\d{3}-\d{2}-\d{4}\b'
scan_cat "Institution candidates"                          "-oiE" '(University|College|Hospital|Clinic|School|Church|Company|Inc\.|Corp\.|LLC) of [A-Z][a-z]+'
echo "=== END PII SCAN — ${TOTAL} total candidate(s) ==="

if [ -n "$DETAIL" ]; then
  echo "Matched values written (human review only, do NOT read into AI context): $DETAIL"
fi

[ "$TOTAL" -gt 0 ] && exit 1
exit 0
