#!/usr/bin/env bash
# Safety Scan Gate — Local PII/HIPAA/Restricted Data Detection
# Usage: bash scripts/gates/safety-scan.sh <file_path>
# Output: prints GREEN / YELLOW / RED to stdout with details
# Exit codes: 0 = GREEN (safe), 1 = RED (sensitive data found), 2 = YELLOW (review needed)
# This script runs LOCALLY — file contents are never sent to any API.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: safety-scan.sh <file_path>" >&2
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "ERROR: File not found: $FILE" >&2
  exit 1
fi

RED_COUNT=0
YELLOW_COUNT=0
ISSUES=""

# --- RED patterns: PII/HIPAA identifiers ---
# SSN
if grep -qEi '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Social Security Number pattern detected"
fi

# Email addresses
if grep -qEi '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Email address pattern detected"
fi

# Phone numbers (US format)
if grep -qEi '\b(\+?1[-.]?)?\(?[0-9]{3}\)?[-. ][0-9]{3}[-. ][0-9]{4}\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Phone number pattern detected"
fi

# IP addresses
if grep -qE '\b[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: IP address pattern detected"
fi

# Date of birth patterns
if grep -qEi '\b(date.?of.?birth|dob|birth.?date)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Date of birth field detected"
fi

# HIPAA identifiers
if grep -qEi '\b(medical.?record|patient.?id|mrn|health.?plan|beneficiary)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: HIPAA identifier pattern detected"
fi

# Restricted dataset markers
if grep -qEi '\b(restricted.?use|confidential|under.?embargo|data.?use.?agreement|DUA)\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Restricted data marker detected"
fi

# Geographic identifiers below state level
if grep -qEi '\b(census.?tract|block.?group|zip.?code|street.?address|latitude|longitude|geocode)\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Sub-state geographic identifier detected"
fi

# --- Report ---
if [ "$RED_COUNT" -gt 0 ]; then
  echo "RED: $RED_COUNT critical issue(s) found — DO NOT transmit to AI without review"
  echo -e "$ISSUES"
  exit 1
elif [ "$YELLOW_COUNT" -gt 0 ]; then
  echo "YELLOW: $YELLOW_COUNT issue(s) found — review before transmitting"
  echo -e "$ISSUES"
  exit 2
else
  echo "GREEN: No sensitive data patterns detected"
  exit 0
fi
