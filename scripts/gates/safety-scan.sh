#!/usr/bin/env bash
# Safety Scan Gate — PII/HIPAA/Restricted Data Detection
# Usage: bash scripts/gates/safety-scan.sh <file_path>
# Output: prints GREEN / YELLOW / RED to stdout with details
# Exit codes: 0 = GREEN (safe), 1 = RED (sensitive data found), 2 = YELLOW (review needed)
# This script runs LOCALLY — file contents are never sent to any API.
# Covers 10 sensitivity categories per sensitivity-patterns.md
#
# Detection backends (tried in order):
#   1. Presidio (NER + patterns) — if presidio-analyzer is installed
#   2. Regex fallback — always available, no dependencies
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

# Fail CLOSED on unreadable files. The grep probes below all use
# `2>/dev/null`, which suppresses permission-denied errors — without
# this check a chmod 000 file would silently return GREEN. A file we
# cannot inspect must be treated as YELLOW (NEEDS_REVIEW), not safe.
if [ ! -r "$FILE" ]; then
  echo "YELLOW: File exists but is not readable by the scanner — cannot verify contents"
  echo "  YELLOW: check file permissions, or treat as LOCAL_MODE / HALTED per policy"
  exit 2
fi

# ── Binary-format short-circuit ──────────────────────────────────────
# The regex fallback scanner (below) is plain `grep` over raw bytes.
# Binary formats like .xlsx, .parquet, .dta, .sav, .rds, .sqlite, .feather
# store their data zlib-compressed or in a proprietary encoding, so the
# regex patterns match nothing and the scanner would return GREEN — a
# fail-open on exactly the file types the plugin is supposed to protect.
#
# For these formats, short-circuit to YELLOW with a clear explanation.
# The caller (pretooluse-data-guard.sh) will then block the Read and ask
# the user to choose LOCAL_MODE (analyze via Rscript/python3), ANONYMIZE,
# OVERRIDE (with rationale), or HALT.
#
# Presidio is still attempted first below when available, because some
# Presidio backends can unpack Office documents. But the binary check
# runs before the fallback regex path, so even on Presidio failure we
# don't silently return GREEN on a zipped spreadsheet.
LOWER_FILE="$(printf '%s' "$FILE" | tr '[:upper:]' '[:lower:]')"
BINARY_EXT="${LOWER_FILE##*.}"
case "$BINARY_EXT" in
  xlsx|xls|ods|parquet|feather|arrow|dta|sav|rds|rdata|sqlite|db|\
  h5|hdf5|mat|pkl|npy|npz|pickle|\
  wav|mp3|flac|m4a|ogg|aac|aiff|\
  mp4|mov|avi|mkv|webm|\
  jpg|jpeg|png|tiff|tif|heic|heif|bmp|webp|gif|\
  pdf|doc|docx|xlsm|pptx|ppt)
    BINARY_SHORTCUT=1
    ;;
  *)
    BINARY_SHORTCUT=0
    ;;
esac

# ── Try Presidio backend first ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRESIDIO_SCRIPT="$SCRIPT_DIR/safety-scan-presidio.py"

if [ -f "$PRESIDIO_SCRIPT" ] && python3 -c "from presidio_analyzer import AnalyzerEngine; AnalyzerEngine()" 2>/dev/null; then
  # Presidio available and functional — use it
  # Capture output; if Presidio crashes (exit code > 2), fall through to regex
  PRESIDIO_OUT=$(python3 "$PRESIDIO_SCRIPT" "$FILE" 2>&1) || true
  PRESIDIO_EXIT=${PIPESTATUS[0]:-$?}
  # Re-derive exit code from output (0=GREEN, 1=RED, 2=YELLOW) since || true masks it
  if echo "$PRESIDIO_OUT" | grep -q "^RED:"; then
    PRESIDIO_EXIT=1
  elif echo "$PRESIDIO_OUT" | grep -q "^YELLOW:"; then
    PRESIDIO_EXIT=2
  elif echo "$PRESIDIO_OUT" | grep -q "^GREEN:"; then
    PRESIDIO_EXIT=0
  else
    # No recognizable output — Presidio crashed, fall through to regex
    echo "WARNING: Presidio scanner failed, using regex fallback" >&2
    PRESIDIO_EXIT=99
  fi
  if [ "$PRESIDIO_EXIT" -le 2 ]; then
    # Binary-format promotion: if this is a known binary format and Presidio
    # returned GREEN, we can't trust it — text scanners (including Presidio's
    # regex+NER on raw bytes) can't inspect zlib-compressed content. Promote
    # to YELLOW so the caller requires LOCAL_MODE. Keep RED/YELLOW as-is.
    if [ "$BINARY_SHORTCUT" = 1 ] && [ "$PRESIDIO_EXIT" = 0 ]; then
      echo "YELLOW: Binary format (.$BINARY_EXT) — Presidio scan returned GREEN but binary content cannot be inspected by text-based analyzers"
      echo "  YELLOW: File extension '.$BINARY_EXT' is a binary/compressed format"
      echo "  YELLOW: Recommend LOCAL_MODE: analyze via Rscript -e / python3 -c"
      echo "  YELLOW: without transmitting row-level data to the API."
      exit 2
    fi
    echo "$PRESIDIO_OUT"
    exit $PRESIDIO_EXIT
  fi
fi

# ── Regex fallback ───────────────────────────────────────────────────
# If Presidio is not installed, fall back to pattern matching.
# Install Presidio for NER-based detection: pip install presidio-analyzer spacy && python3 -m spacy download en_core_web_lg

RED_COUNT=0
YELLOW_COUNT=0
ISSUES=""

# ── Category 1: Direct Identifiers (SSN, DOB, Phone) ───────────────────────

# SSN
if grep -qEi '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Social Security Number pattern detected"
fi

# Phone numbers (US format — require separators and leading boundary to avoid version strings)
if grep -qE '(^|[^0-9.])\+?1?[-. ]?\(?[0-9]{3}\)?[-. ][0-9]{3}[-. ][0-9]{4}([^0-9.]|$)' "$FILE" 2>/dev/null; then
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

# Street addresses (require house number + optional direction + street type — excludes
# generic mentions like "north street" in prose by requiring a leading number)
if grep -qEi '\b[0-9]{1,5}\s+(north|south|east|west|n\.|s\.|e\.|w\.)?\s*(street|st\.|avenue|ave\.|road|rd\.|boulevard|blvd\.|drive|dr\.|lane|ln\.|court|ct\.)\b' "$FILE" 2>/dev/null; then
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Street address pattern detected — review for actual PII"
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
# Only flag when terms appear near data indicators (column headers, variable names, id/score patterns)
# to avoid flagging literature reviews or theory sections that discuss these topics

if grep -qEi '\b(suicid(e|al|ality)|self.?harm|bipolar|schizophren(ia|ic)|psychosis|eating.?disorder)\b' "$FILE" 2>/dev/null; then
  # High-sensitivity terms: always flag as YELLOW for review
  YELLOW_COUNT=$((YELLOW_COUNT + 1))
  ISSUES="${ISSUES}\n  YELLOW: Mental health term detected — review whether this is data or prose"
fi
# Common terms (depression, ptsd, anxiety, psychiatric) only flag when near data markers
if grep -qEi '\b(patient|subject|respondent|participant|score|scale|diagnosis|_id|_code)\b.*(depression|ptsd|anxiety.?disorder|psychiatric|mental.?health.?diagnosis)\b' "$FILE" 2>/dev/null || \
   grep -qEi '\b(depression|ptsd|anxiety.?disorder|psychiatric|mental.?health.?diagnosis)\b.*(patient|subject|respondent|participant|score|scale|diagnosis|_id|_code)\b' "$FILE" 2>/dev/null; then
  RED_COUNT=$((RED_COUNT + 1))
  ISSUES="${ISSUES}\n  RED: Mental health data with individual identifiers detected"
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

# --- Binary-format promotion ---
# If this is a known binary format, promote the decision to at least YELLOW.
# A regex-clean binary file is NOT evidence that the file is safe — it is
# evidence that text grep cannot inspect compressed/encoded content. We
# surface this honestly to the caller so the user can choose LOCAL_MODE.
if [ "$BINARY_SHORTCUT" = 1 ]; then
  if [ "$RED_COUNT" = 0 ] && [ "$YELLOW_COUNT" = 0 ]; then
    echo "YELLOW: Binary format (.$BINARY_EXT) — text-grep scanner cannot inspect"
    echo -e "  YELLOW: File extension '.$BINARY_EXT' is a binary/compressed format"
    echo -e "  YELLOW: The regex fallback scanner can only inspect plain text"
    echo -e "  YELLOW: Recommend LOCAL_MODE: analyze via Rscript -e / python3 -c"
    echo -e "  YELLOW: without transmitting row-level data to the API."
    exit 2
  fi
  # If RED or YELLOW already triggered on ancillary text content (e.g. metadata
  # embedded in the filename or an adjacent manifest), fall through to the
  # normal report below — the existing findings are still useful.
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
