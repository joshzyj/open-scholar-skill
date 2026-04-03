#!/usr/bin/env bash
# Safety Scan Gate — Local PII/HIPAA/Restricted Data Detection
# Usage: bash scripts/gates/safety-scan.sh <file_path>
# Output: prints GREEN / YELLOW / RED to stdout with details
# Exit codes: 0 = GREEN (safe), 1 = RED (sensitive data found), 2 = YELLOW (review needed)
# This script runs LOCALLY — file contents are never sent to any API.
# Covers 10 sensitivity categories per sensitivity-patterns.md
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

# ── Category 1: Direct Identifiers (SSN, DOB, Phone) ───────────────────────

# SSN
if grep -qEi '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Social Security Number pattern detected"
fi

# Phone numbers (US format — fixed regex for ERE)
if grep -qEi '\+?1?[-. ]?[0-9]{3}[-. ][0-9]{3}[-. ][0-9]{4}' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Phone number pattern detected"
fi

# Date of birth patterns
if grep -qEi '\b(date.?of.?birth|dob|birth.?date)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Date of birth field detected"
fi

# Name fields in structured data (column headers)
if grep -qEi '\b(first_?name|last_?name|full_?name|respondent_?name|participant_?name)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Personal name field detected in data"
fi

# ── Category 2: Contact Information (Email, Address) ───────────────────────

# Email addresses
if grep -qEi '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Email address pattern detected"
fi

# Street addresses
if grep -qEi '\b[0-9]+\s+(north|south|east|west|n\.|s\.|e\.|w\.)?\s*(street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|way|court|ct)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Street address pattern detected"
fi

# ── Category 3: Geographic Identifiers (sub-state) ────────────────────────

if grep -qEi '\b(census.?tract|block.?group|zip.?code|street.?address|latitude|longitude|geocode)\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Sub-state geographic identifier detected"
fi

# IP addresses (tightened: require at least one octet 1-255 to reduce false positives)
if grep -qE '\b(1?[0-9]{1,2}|2[0-4][0-9]|25[0-5])\.(1?[0-9]{1,2}|2[0-4][0-9]|25[0-5])\.(1?[0-9]{1,2}|2[0-4][0-9]|25[0-5])\.(1?[0-9]{1,2}|2[0-4][0-9]|25[0-5])\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: IP address pattern detected"
fi

# ── Category 4: Health / HIPAA Data ───────────────────────────────────────

if grep -qEi '\b(medical.?record|patient.?id|mrn|health.?plan|beneficiary)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: HIPAA identifier pattern detected"
fi

if grep -qEi '\b(diagnosis|icd.?[0-9]|prescription|medication|treatment.?plan|discharge.?summary)\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Clinical/health data terms detected"
fi

# ── Category 5: Mental Health ─────────────────────────────────────────────

if grep -qEi '\b(suicid|self.?harm|depression|bipolar|schizophren|ptsd|anxiety.?disorder|psychiatric|mental.?health.?diagnosis|psychosis|eating.?disorder)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Mental health sensitive data detected"
fi

# ── Category 6: Legal / Immigration Status ────────────────────────────────

if grep -qEi '\b(undocumented|immigration.?status|deportat|asylum.?seek|visa.?status|DACA|refugee.?status|legal.?status|citizenship.?status)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Immigration/legal status data detected"
fi

if grep -qEi '\b(arrest.?record|criminal.?record|conviction|incarcerat|parole|probation|mugshot|booking)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Criminal/legal history data detected"
fi

# ── Category 7: Sexual Orientation / Gender Identity ──────────────────────

if grep -qEi '\b(sexual.?orientation|gender.?identity|transgender|lgbtq|non.?binary|sexual.?preference|coming.?out)\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Sexual orientation/gender identity data detected"
fi

# ── Category 8: Religious / Political Beliefs ─────────────────────────────

if grep -qEi '\b(religious.?affiliation|political.?affiliation|party.?registration|church.?membership|mosque|synagogue|temple.?membership)\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Religious/political affiliation data detected"
fi

# ── Category 9: Financial Data ────────────────────────────────────────────

if grep -qEi '\b(credit.?card|account.?number|bank.?account|routing.?number|ssn|tax.?id|ein)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Financial account data detected"
fi

if grep -qEi '\b(income.?amount|salary|wage.?rate|net.?worth)\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Individual financial data detected"
fi

# ── Category 10: Restricted Data Markers / Biometric ──────────────────────

if grep -qEi '\b(restricted.?use|confidential|under.?embargo|data.?use.?agreement|DUA)\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Restricted data marker detected"
fi

if grep -qEi '\b(biometric|fingerprint|retina|facial.?recognition|dna.?sample|genetic.?data|genome)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Biometric/genetic data detected"
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
