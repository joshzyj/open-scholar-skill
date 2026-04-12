#!/usr/bin/env bash
# Smoke tests for scripts/gates/pretooluse-data-guard.sh
#
# Each test synthesizes a Claude Code PreToolUse hook payload (JSON with
# tool_name, tool_input, cwd) and pipes it to the guard script. We then
# assert the exit code matches what the policy requires.
#
# This test runs fully offline — it creates temp files and never hits any
# network or API. It is safe to run repeatedly.

set -uo pipefail

# Locate the guard and its sibling safety-scan.sh
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="${REPO_ROOT}/scripts/gates/pretooluse-data-guard.sh"
SAFETY_SCAN="${REPO_ROOT}/scripts/gates/safety-scan.sh"

if [ ! -f "$GUARD" ]; then
  echo "FATAL: guard script not found at $GUARD"
  exit 1
fi
if [ ! -f "$SAFETY_SCAN" ]; then
  echo "FATAL: safety-scan.sh not found at $SAFETY_SCAN"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — guard requires jq. Install via: brew install jq"
  exit 0
fi

# Sandbox for temp files
TMPDIR_BASE="$(mktemp -d -t guard-smoke.XXXXXX)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# ─── Helper: build a PreToolUse JSON payload ────────────────────────────
payload() {
  local tool_name="$1"
  local file_path="$2"
  local cwd="$3"
  jq -n \
    --arg tn "$tool_name" \
    --arg fp "$file_path" \
    --arg cwd "$cwd" \
    '{session_id:"test", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{file_path:$fp}}'
}

run_guard() {
  local payload_json="$1"
  echo "$payload_json" | bash "$GUARD" 2>/tmp/guard-stderr.$$
  local rc=$?
  rm -f /tmp/guard-stderr.$$
  return $rc
}

run_guard_capture() {
  local payload_json="$1"
  echo "$payload_json" | bash "$GUARD" 2>"$TMPDIR_BASE/stderr"
  echo $?
}

echo "=== PreToolUse Data Guard Smoke Tests ==="
echo "Guard: $GUARD"
echo "Safety-scan: $SAFETY_SCAN"
echo ""

# ─── Test 1: non-Read tool call → pass through ──────────────────────────
echo "Test 1: non-Read tool call passes through"
P="$(payload Bash "$TMPDIR_BASE/anything" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass "Bash tool call not inspected"
else
  fail "Bash tool call rejected (exit $RC) — guard should only inspect Read"
fi

# ─── Test 2: Read on non-data file (.R script) → pass through ───────────
echo ""
echo "Test 2: Read on non-data file passes through"
SCRIPT_FILE="$TMPDIR_BASE/analysis.R"
printf 'library(tidyverse)\ndf <- read_csv("x")\n' > "$SCRIPT_FILE"
P="$(payload Read "$SCRIPT_FILE" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass ".R file not inspected as data"
else
  fail ".R file was blocked (exit $RC) — extension gate is too aggressive"
fi

# ─── Test 3: Read on non-existent file → pass through ───────────────────
echo ""
echo "Test 3: Read on missing file passes through"
P="$(payload Read "$TMPDIR_BASE/does-not-exist.csv" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass "missing file handled by Claude's own error path"
else
  fail "missing file blocked by guard (exit $RC) — should pass through"
fi

# ─── Test 4: Read on GREEN CSV (public-looking data) → allow ────────────
echo ""
echo "Test 4: Read on clean CSV (no PII patterns) is allowed"
GREEN_CSV="$TMPDIR_BASE/public.csv"
cat > "$GREEN_CSV" <<'CSV'
year,country,gdp_per_capita,life_expectancy
2010,USA,48000,78.5
2015,USA,56000,79.1
2020,USA,63000,78.9
CSV
P="$(payload Read "$GREEN_CSV" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass "clean CSV allowed through"
else
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
  fail "clean CSV blocked (exit $RC) — safety scan false positive?"
fi

# ─── Test 5: Read on RED CSV (SSN present) → blocked ────────────────────
echo ""
echo "Test 5: Read on CSV with SSN is blocked"
RED_CSV="$TMPDIR_BASE/patients.csv"
cat > "$RED_CSV" <<'CSV'
patient_id,first_name,last_name,ssn,diagnosis
P001,John,Smith,123-45-6789,hypertension
P002,Jane,Doe,987-65-4321,diabetes
CSV
P="$(payload Read "$RED_CSV" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "SSN-containing CSV blocked with exit 2"
  if grep -q "RED" "$TMPDIR_BASE/stderr" 2>/dev/null || grep -q "sensitive" "$TMPDIR_BASE/stderr" 2>/dev/null; then
    pass "stderr contains refusal explanation"
  else
    fail "stderr missing refusal text"
    echo "    stderr was:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
  fi
else
  fail "SSN CSV got exit $RC — should be 2 (blocked)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 6: Sidecar status CLEARED → allow even if RED content ─────────
echo ""
echo "Test 6: Sidecar CLEARED entry overrides a fresh scan"
SIDECAR_DIR="$TMPDIR_BASE/proj6"
mkdir -p "$SIDECAR_DIR/.claude"
RED_CSV2="$SIDECAR_DIR/sensitive.csv"
cat > "$RED_CSV2" <<'CSV'
id,ssn,name
1,111-22-3333,Alice
CSV
jq -n --arg fp "$RED_CSV2" '{($fp): "CLEARED"}' > "$SIDECAR_DIR/.claude/safety-status.json"
P="$(payload Read "$RED_CSV2" "$SIDECAR_DIR")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass "CLEARED sidecar honored — user decision respected"
else
  fail "CLEARED sidecar ignored (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 7: Sidecar status LOCAL_MODE → blocked with Bash-loader message
echo ""
echo "Test 7: Sidecar LOCAL_MODE forbids Read even if scan would be GREEN"
SIDECAR_DIR7="$TMPDIR_BASE/proj7"
mkdir -p "$SIDECAR_DIR7/.claude"
GREEN_CSV2="$SIDECAR_DIR7/clean.csv"
cat > "$GREEN_CSV2" <<'CSV'
a,b,c
1,2,3
CSV
jq -n --arg fp "$GREEN_CSV2" '{($fp): "LOCAL_MODE"}' > "$SIDECAR_DIR7/.claude/safety-status.json"
P="$(payload Read "$GREEN_CSV2" "$SIDECAR_DIR7")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "LOCAL_MODE sidecar blocks Read"
  if grep -q "LOCAL_MODE" "$TMPDIR_BASE/stderr" 2>/dev/null; then
    pass "stderr mentions LOCAL_MODE"
  else
    fail "stderr does not mention LOCAL_MODE"
  fi
else
  fail "LOCAL_MODE sidecar did not block (exit $RC)"
fi

# ─── Test 8: Sidecar OVERRIDE → allow ───────────────────────────────────
echo ""
echo "Test 8: Sidecar OVERRIDE allows Read even on RED content"
SIDECAR_DIR8="$TMPDIR_BASE/proj8"
mkdir -p "$SIDECAR_DIR8/.claude"
RED_CSV3="$SIDECAR_DIR8/override.csv"
cat > "$RED_CSV3" <<'CSV'
id,ssn
1,222-33-4444
CSV
jq -n --arg fp "$RED_CSV3" '{($fp): "OVERRIDE"}' > "$SIDECAR_DIR8/.claude/safety-status.json"
P="$(payload Read "$RED_CSV3" "$SIDECAR_DIR8")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass "OVERRIDE sidecar honored"
else
  fail "OVERRIDE sidecar ignored (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 9: .dta Stata file with RED content → blocked ────────────────
echo ""
echo "Test 9: Stata-extension file is inspected"
# We use a regular text file with .dta extension to exercise the ext gate.
# The safety-scan reads it as text and will flag the SSN via the RED path.
DTA_FAKE="$TMPDIR_BASE/survey.dta"
cat > "$DTA_FAKE" <<'EOF'
id|ssn|name
1|555-55-5555|Robert
EOF
P="$(payload Read "$DTA_FAKE" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass ".dta extension triggers inspection (via RED path)"
else
  fail ".dta file got exit $RC"
fi

# ─── Test 9b: clean binary .dta → G1 binary-format YELLOW promotion ───
echo ""
echo "Test 9b: clean binary .dta with no PII patterns → YELLOW (G1 binary promotion)"
# Unlike Test 9 above (which has an SSN → RED path), this file has NO
# detectable PII patterns. It should NOT return GREEN — the G1 short-
# circuit must promote binary formats to YELLOW because a regex/NER
# scanner cannot inspect compressed or binary-encoded content.
CLEAN_DTA="$TMPDIR_BASE/clean-stata.dta"
# Real Stata 13+ XML header + some binary bytes — no text that matches
# any PII pattern.
printf '<stata_dta><header><release>117</release></header></stata_dta>\x00\x01\x02\x03' > "$CLEAN_DTA"
P="$(payload Read "$CLEAN_DTA" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "clean .dta promoted to YELLOW (binary content cannot be text-scanned)"
else
  fail "clean .dta got exit $RC (expected 2 — binary formats must not return GREEN)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# Same for clean .sav and .rds — exercise other binary extensions the
# G1 fix added
echo ""
echo "Test 9c: clean binary .sav promoted to YELLOW"
CLEAN_SAV="$TMPDIR_BASE/clean-spss.sav"
printf '$FL2@(#) IBM SPSS STATISTICS\x00\x00\x00\x00' > "$CLEAN_SAV"
P="$(payload Read "$CLEAN_SAV" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
[ "$RC" = "2" ] && pass "clean .sav promoted to YELLOW" || fail "clean .sav got exit $RC"

# ─── Test 10: empty stdin → pass through (fail open on malformed input) ─
echo ""
echo "Test 10: empty stdin passes through"
echo "" | bash "$GUARD" >/dev/null 2>&1
RC=$?
if [ "$RC" = "0" ]; then
  pass "empty payload handled gracefully"
else
  fail "empty payload got exit $RC"
fi

# ─── Test 11: README.md in a data/ directory → pass through ────────────
echo ""
echo "Test 11: .md file not inspected (even in data/ directory)"
mkdir -p "$TMPDIR_BASE/data"
README="$TMPDIR_BASE/data/README.md"
echo "# Dataset README" > "$README"
P="$(payload Read "$README" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass ".md file allowed — docs are not data"
else
  fail ".md file blocked (exit $RC) — extension gate too broad"
fi

# ─── Test 12: PNG in output/figures/ → allow ────────────────────────────
echo ""
echo "Test 12: PNG in output/figures/ is allowed"
mkdir -p "$TMPDIR_BASE/output/figures"
OUTPUT_PNG="$TMPDIR_BASE/output/figures/fig1.png"
# 1x1 transparent PNG (smallest valid PNG) — real binary, not text
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n\x2d\xb4\x00\x00\x00\x00IEND\xaeB`\x82' > "$OUTPUT_PNG"
P="$(payload Read "$OUTPUT_PNG" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass "output/figures/*.png allowed — scholar-analyze review workflow works"
else
  fail "output figure PNG blocked (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 13: JPG in data/raw/ → blocked ───────────────────────────────
echo ""
echo "Test 13: JPG in data/raw/ is blocked"
mkdir -p "$TMPDIR_BASE/data/raw"
RAW_JPG="$TMPDIR_BASE/data/raw/img_001.jpg"
# Minimal JPG bytes — a valid SOI marker is enough to make file -b call it JPEG
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9' > "$RAW_JPG"
P="$(payload Read "$RAW_JPG" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "data/raw/*.jpg blocked — raw-directory image caught"
  if grep -q "image file in a raw-data directory" "$TMPDIR_BASE/stderr" 2>/dev/null; then
    pass "stderr explains the raw-data rule"
  else
    fail "stderr missing raw-data explanation"
    echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
  fi
else
  fail "data/raw JPG got exit $RC — should be 2 (blocked)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 14: HEIC in subjects/ → blocked ──────────────────────────────
echo ""
echo "Test 14: HEIC participant photo is blocked"
mkdir -p "$TMPDIR_BASE/subjects"
HEIC="$TMPDIR_BASE/subjects/participant_042.heic"
printf 'fake heic bytes' > "$HEIC"
P="$(payload Read "$HEIC" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "subjects/*.heic blocked"
else
  fail "participant photo got exit $RC — should be 2 (blocked)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 15: PNG in random path (screenshot) → allow ──────────────────
echo ""
echo "Test 15: PNG outside any classified path is allowed (screenshots, icons)"
SCREENSHOT="$TMPDIR_BASE/screenshot.png"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n\x2d\xb4\x00\x00\x00\x00IEND\xaeB`\x82' > "$SCREENSHOT"
P="$(payload Read "$SCREENSHOT" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass "top-level screenshot allowed — default pass-through for unclassified images"
else
  fail "screenshot blocked (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 16: Sidecar OVERRIDE beats raw-data path rule for images ─────
echo ""
echo "Test 16: Sidecar OVERRIDE permits an image in data/raw/"
SIDECAR_DIR16="$TMPDIR_BASE/proj16"
mkdir -p "$SIDECAR_DIR16/data/raw" "$SIDECAR_DIR16/.claude"
OVERRIDE_JPG="$SIDECAR_DIR16/data/raw/public_logo.jpg"
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9' > "$OVERRIDE_JPG"
jq -n --arg fp "$OVERRIDE_JPG" '{($fp): "OVERRIDE"}' > "$SIDECAR_DIR16/.claude/safety-status.json"
P="$(payload Read "$OVERRIDE_JPG" "$SIDECAR_DIR16")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass "sidecar OVERRIDE wins over path rule"
else
  fail "OVERRIDE ignored for image in data/raw/ (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 17: PDF in data/raw/ → allow (PDFs are not in the extension list)
echo ""
echo "Test 17: PDF files pass through (extension not in DATA_EXTS list)"
mkdir -p "$TMPDIR_BASE/out-pdf/figures"
PDF_FIG="$TMPDIR_BASE/out-pdf/figures/fig1.pdf"
printf '%%PDF-1.4\n' > "$PDF_FIG"
P="$(payload Read "$PDF_FIG" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  pass "PDF figure passes through — primary scholar-analyze format still works"
else
  fail "PDF blocked (exit $RC) — extension gate regression"
fi

# ─── Test 18: NEEDS_REVIEW:YELLOW sidecar → blocked ────────────────────
echo ""
echo "Test 18: NEEDS_REVIEW:YELLOW sidecar is blocked"
T18="$TMPDIR_BASE/t18"
mkdir -p "$T18/.claude"
NR_YELLOW="$T18/survey.csv"
echo "a,b" > "$NR_YELLOW"
jq -n --arg fp "$NR_YELLOW" '{($fp): "NEEDS_REVIEW:YELLOW"}' > "$T18/.claude/safety-status.json"
P="$(payload Read "$NR_YELLOW" "$T18")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "NEEDS_REVIEW:YELLOW blocks Read"
  if grep -q "scholar-init review" "$TMPDIR_BASE/stderr" 2>/dev/null; then
    pass "stderr directs user to /scholar-init review"
  else
    fail "stderr missing review command"
  fi
else
  fail "NEEDS_REVIEW:YELLOW did not block (exit $RC)"
fi

# ─── Test 19: LOCAL_MODE sidecar → blocked with Bash loader hint ───────
echo ""
echo "Test 19: LOCAL_MODE sidecar blocks with Bash loader hint"
T19="$TMPDIR_BASE/t19"
mkdir -p "$T19/.claude"
LM_FILE="$T19/microdata.csv"
echo "a,b" > "$LM_FILE"
jq -n --arg fp "$LM_FILE" '{($fp): "LOCAL_MODE"}' > "$T19/.claude/safety-status.json"
P="$(payload Read "$LM_FILE" "$T19")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "Rscript -e" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "LOCAL_MODE blocks with Rscript -e hint"
else
  fail "LOCAL_MODE block or hint missing (exit $RC)"
fi

# ─── Test 20: ANONYMIZED sidecar → allowed ─────────────────────────────
echo ""
echo "Test 20: ANONYMIZED sidecar allows Read"
T20="$TMPDIR_BASE/t20"
mkdir -p "$T20/.claude"
ANON_FILE="$T20/ANON_interviews.csv"
echo "id,anonymized_text" > "$ANON_FILE"
jq -n --arg fp "$ANON_FILE" '{($fp): "ANONYMIZED"}' > "$T20/.claude/safety-status.json"
P="$(payload Read "$ANON_FILE" "$T20")"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass "ANONYMIZED allows Read" || fail "ANONYMIZED blocked (exit $RC)"

# ─── Test 21: HALTED sidecar → blocked permanently ─────────────────────
echo ""
echo "Test 21: HALTED sidecar blocks Read permanently"
T21="$TMPDIR_BASE/t21"
mkdir -p "$T21/.claude"
H_FILE="$T21/refused.csv"
echo "a,b" > "$H_FILE"
jq -n --arg fp "$H_FILE" '{($fp): "HALTED"}' > "$T21/.claude/safety-status.json"
P="$(payload Read "$H_FILE" "$T21")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "HALTED" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "HALTED blocks Read with explanation"
else
  fail "HALTED block or message missing (exit $RC)"
fi

# ─── Test 22: Extension case-insensitivity ─────────────────────────────
echo ""
echo "Test 22: Extension matching is case-insensitive"
T22="$TMPDIR_BASE/t22"
mkdir -p "$T22"
UPPER_CSV="$T22/data.CSV"
cat > "$UPPER_CSV" <<'CSV'
id,ssn
1,123-45-6789
CSV
P="$(payload Read "$UPPER_CSV" "$T22")"
RC=$(run_guard_capture "$P")
[ "$RC" = "2" ] && pass ".CSV extension triggers inspection" || fail ".CSV missed (exit $RC)"

# Mixed case
MIXED_CSV="$T22/more.Csv"
cp "$UPPER_CSV" "$MIXED_CSV"
P="$(payload Read "$MIXED_CSV" "$T22")"
RC=$(run_guard_capture "$P")
[ "$RC" = "2" ] && pass ".Csv extension triggers inspection" || fail ".Csv missed (exit $RC)"

# ─── Test 23: .py file inside data/raw/ → allowed (negative test) ──────
echo ""
echo "Test 23: .py script inside data/raw/ passes through"
T23="$TMPDIR_BASE/t23"
mkdir -p "$T23/data/raw"
PY_FILE="$T23/data/raw/clean.py"
cat > "$PY_FILE" <<'PY'
import pandas as pd
df = pd.read_csv("../raw/input.csv")
PY
P="$(payload Read "$PY_FILE" "$T23")"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass ".py in data/raw/ allowed — scripts are not data" || fail ".py blocked (exit $RC)"

# ─── Test 24: NotebookRead on a data CSV → blocked ─────────────────────
echo ""
echo "Test 24: NotebookRead gated like Read"
T24="$TMPDIR_BASE/t24"
mkdir -p "$T24"
NB_CSV="$T24/sensitive.csv"
cat > "$NB_CSV" <<'CSV'
id,ssn
1,999-88-7777
CSV
# NotebookRead uses tool_input.notebook_path, not file_path
payload_nb() {
  jq -n \
    --arg tn "NotebookRead" \
    --arg fp "$NB_CSV" \
    --arg cwd "$T24" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{notebook_path:$fp}}'
}
P="$(payload_nb)"
RC=$(run_guard_capture "$P")
[ "$RC" = "2" ] && pass "NotebookRead on SSN-containing CSV blocked" || fail "NotebookRead not gated (exit $RC)"

# ─── Test 25: Grep on data/raw/ → blocked ──────────────────────────────
echo ""
echo "Test 25: Grep with path under data/raw/ blocked"
T25="$TMPDIR_BASE/t25"
mkdir -p "$T25/data/raw"
echo "a,b" > "$T25/data/raw/foo.csv"
payload_grep() {
  jq -n \
    --arg tn "Grep" \
    --arg path "$T25/data/raw" \
    --arg cwd "$T25" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:"SSN", path:$path}}'
}
P="$(payload_grep)"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "Grep" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "Grep into data/raw/ blocked"
else
  fail "Grep not blocked (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 26: Glob with data/raw/ pattern → blocked ────────────────────
echo ""
echo "Test 26: Glob with data/raw/ pattern blocked"
T26="$TMPDIR_BASE/t26"
mkdir -p "$T26/data/raw"
echo "a,b" > "$T26/data/raw/foo.csv"
payload_glob() {
  jq -n \
    --arg tn "Glob" \
    --arg pat "$T26/data/raw/*.csv" \
    --arg cwd "$T26" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat}}'
}
P="$(payload_glob)"
RC=$(run_guard_capture "$P")
[ "$RC" = "2" ] && pass "Glob into data/raw/ blocked" || fail "Glob not blocked (exit $RC)"

# ─── Test 26b: Grep on direct .csv file outside data dirs → BLOCKED ────
echo ""
echo "Test 26b: Grep on direct .csv file path (outside data dirs) blocked"
T26B="$TMPDIR_BASE/t26b"
mkdir -p "$T26B"
printf 'id,ssn\n1,111-22-3333\n' > "$T26B/patients.csv"
payload_grep_direct() {
  jq -n \
    --arg tn "Grep" \
    --arg path "$T26B/patients.csv" \
    --arg cwd "$T26B" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:"ssn", path:$path}}'
}
P="$(payload_grep_direct)"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "Grep on direct .csv file path blocked"
else
  fail "Grep on direct .csv NOT blocked (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 26c: Glob pattern *.parquet outside data dirs → BLOCKED ──────
echo ""
echo "Test 26c: Glob *.parquet pattern blocked even outside data dirs"
T26C="$TMPDIR_BASE/t26c"
mkdir -p "$T26C"
payload_glob_direct() {
  jq -n \
    --arg tn "Glob" \
    --arg pat "$T26C/data-*.parquet" \
    --arg cwd "$T26C" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat}}'
}
P="$(payload_glob_direct)"
RC=$(run_guard_capture "$P")
[ "$RC" = "2" ] && pass "Glob *.parquet blocked" || fail "Glob *.parquet not blocked (exit $RC)"

# ─── Test 26d: Grep on direct .py file → ALLOWED (negative control) ────
echo ""
echo "Test 26d: Grep on direct .py file (not data) allowed"
T26D="$TMPDIR_BASE/t26d"
mkdir -p "$T26D"
echo 'import pandas' > "$T26D/analysis.py"
payload_grep_py() {
  jq -n \
    --arg tn "Grep" \
    --arg path "$T26D/analysis.py" \
    --arg cwd "$T26D" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:"import", path:$path}}'
}
P="$(payload_grep_py)"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass "Grep on .py file allowed" || fail "Grep .py wrongly blocked (exit $RC)"

# ─── Test 27: Grep outside data dirs → allowed ─────────────────────────
echo ""
echo "Test 27: Grep in a non-data directory passes through"
T27="$TMPDIR_BASE/t27/src"
mkdir -p "$T27"
echo "x = 1" > "$T27/main.py"
payload_grep2() {
  jq -n \
    --arg tn "Grep" \
    --arg path "$T27" \
    --arg cwd "$T27" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:"x", path:$path}}'
}
P="$(payload_grep2)"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass "Grep outside data dirs allowed" || fail "Grep wrongly blocked (exit $RC)"

# ─── Test 28a: Binary format (parquet) short-circuits to YELLOW ────────
echo ""
echo "Test 28a: .parquet file promoted to YELLOW (binary-format bypass fix)"
T28A="$TMPDIR_BASE/t28a"
mkdir -p "$T28A"
printf 'PAR1\x00\x00\x00\x00parquet-body' > "$T28A/data.parquet"
P="$(payload Read "$T28A/data.parquet" "$T28A")"
RC=$(run_guard_capture "$P")
# Binary format → safety-scan YELLOW → guard blocks with YELLOW message
if [ "$RC" = "2" ] && grep -q "YELLOW\|Binary\|LOCAL_MODE" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass ".parquet blocked (binary format cannot be text-scanned)"
else
  fail ".parquet handling wrong (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 28b: .xlsx binary format also short-circuits ─────────────────
echo ""
echo "Test 28b: .xlsx binary format short-circuits to YELLOW"
T28B="$TMPDIR_BASE/t28b"
mkdir -p "$T28B"
printf 'PK\x03\x04\x14\x00\x00\x00\x08\x00gibberish' > "$T28B/data.xlsx"
P="$(payload Read "$T28B/data.xlsx" "$T28B")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass ".xlsx blocked (binary format)"
else
  fail ".xlsx got exit $RC"
fi

# ─── Test 28c: .txt transcript in data/raw/ → inspected ────────────────
echo ""
echo "Test 28c: .txt file in data/raw/ is inspected (conditional gate)"
T28C="$TMPDIR_BASE/t28c"
mkdir -p "$T28C/data/raw"
cat > "$T28C/data/raw/interview-01.txt" <<'TXT'
Participant ID: P001
Contact: participant@example.edu
Interviewer: Dr. Smith
TXT
P="$(payload Read "$T28C/data/raw/interview-01.txt" "$T28C")"
RC=$(run_guard_capture "$P")
# Should be YELLOW/RED because it has email + participant markers
if [ "$RC" = "2" ]; then
  pass ".txt in data/raw/ inspected and blocked"
else
  fail ".txt in data/raw/ passed through (exit $RC)"
fi

# ─── Test 28d: .md README at project root → allowed ────────────────────
echo ""
echo "Test 28d: .md README at project root is NOT inspected"
T28D="$TMPDIR_BASE/t28d"
mkdir -p "$T28D"
cat > "$T28D/README.md" <<'MD'
# My Project
Contact researcher@example.edu for questions.
MD
P="$(payload Read "$T28D/README.md" "$T28D")"
RC=$(run_guard_capture "$P")
# Conditional gate: .md at project root is NOT in the data paths, so pass
if [ "$RC" = "0" ]; then
  pass "README.md at project root allowed (conditional gate)"
else
  fail "README.md blocked (exit $RC) — conditional gate too aggressive"
fi

# ─── Test 28: Sidecar fallback on raw path (non-canonical) ─────────────
echo ""
echo "Test 28: Sidecar lookup falls back to raw path when canonical misses"
T28="$TMPDIR_BASE/t28"
mkdir -p "$T28/.claude"
FB_FILE="$T28/rawpath.csv"
echo "a" > "$FB_FILE"
# Sidecar keyed on the RAW (unresolved) path — the guard may canonicalize
# /var/folders/... → /private/var/folders/... on macOS, so the fallback
# must try the raw form too.
jq -n --arg fp "$FB_FILE" '{($fp): "OVERRIDE"}' > "$T28/.claude/safety-status.json"
P="$(payload Read "$FB_FILE" "$T28")"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass "sidecar fallback to raw path works" || fail "sidecar fallback missed (exit $RC)"

# ─── Test 29: Sidecar basename fallback REMOVED (I1) ──────────────────
echo ""
echo "Test 29: Basename-only sidecar key no longer matches (collision fix)"
T29="$TMPDIR_BASE/t29"
mkdir -p "$T29/.claude"
# File lives at /.../t29/patients.csv. Sidecar keyed only on `patients.csv`
# (basename) should NOT match after the I1 fix.
cat > "$T29/patients.csv" <<'CSV'
id,ssn
1,123-45-6789
CSV
jq -n '{"patients.csv": "OVERRIDE"}' > "$T29/.claude/safety-status.json"
P="$(payload Read "$T29/patients.csv" "$T29")"
RC=$(run_guard_capture "$P")
# Sidecar has basename-only key → lookup should miss → falls through to
# safety-scan → scanner sees SSN → RED → guard blocks with exit 2.
if [ "$RC" = "2" ]; then
  pass "basename-only sidecar key did NOT match (no cross-project collision)"
else
  fail "basename-only OVERRIDE was honored (exit $RC) — collision hole still open"
fi

# ─── Test 30: Qualitative OVERRIDE refusal (I2) ────────────────────────
echo ""
echo "Test 30: OVERRIDE on audio extension is refused at the hook"
T30="$TMPDIR_BASE/t30"
mkdir -p "$T30/.claude"
FAKE_WAV="$T30/interview-01.wav"
printf 'RIFF\x00\x00\x00\x00WAVEfmt ' > "$FAKE_WAV"
jq -n --arg fp "$FAKE_WAV" '{($fp): "OVERRIDE"}' > "$T30/.claude/safety-status.json"
P="$(payload Read "$FAKE_WAV" "$T30")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "forbids OVERRIDE" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "OVERRIDE on .wav refused with policy explanation"
else
  fail ".wav OVERRIDE was honored or message missing (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# Also verify OVERRIDE on a .csv (tabular) is still honored
echo ""
echo "Test 30b: OVERRIDE on tabular extension still works (no over-refusal)"
T30B="$TMPDIR_BASE/t30b"
mkdir -p "$T30B/.claude"
OKCSV="$T30B/survey.csv"
echo "a,b" > "$OKCSV"
jq -n --arg fp "$OKCSV" '{($fp): "OVERRIDE"}' > "$T30B/.claude/safety-status.json"
P="$(payload Read "$OKCSV" "$T30B")"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass "OVERRIDE on .csv still honored" || fail "tabular OVERRIDE wrongly refused (exit $RC)"

# ─── Test 31: System-directory escape refused (I4) ─────────────────────
echo ""
echo "Test 31: Read on /etc/passwd refused"
P="$(payload Read "/etc/passwd" "$TMPDIR_BASE")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "0" ]; then
  # /etc/passwd is not a data extension, so it passes — we need an
  # EXTENSION that is in DATA_EXTS to exercise the path check. Use a
  # symlink with a data extension that resolves to /etc/passwd.
  T31="$TMPDIR_BASE/t31"
  mkdir -p "$T31"
  ln -sf /etc/passwd "$T31/fake.csv"
  P="$(payload Read "$T31/fake.csv" "$T31")"
  RC=$(run_guard_capture "$P")
  if [ "$RC" = "2" ] && grep -q "system directory" "$TMPDIR_BASE/stderr" 2>/dev/null; then
    pass "symlink to /etc/passwd refused"
  else
    fail "symlink escape NOT caught (exit $RC)"
    echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
  fi
else
  # Direct /etc/passwd with no extension is passed by the extension gate
  # (it has no data extension), so this is expected. Use symlink instead.
  T31="$TMPDIR_BASE/t31"
  mkdir -p "$T31"
  ln -sf /etc/passwd "$T31/fake.csv"
  P="$(payload Read "$T31/fake.csv" "$T31")"
  RC=$(run_guard_capture "$P")
  if [ "$RC" = "2" ]; then
    pass "symlink to /etc/passwd refused (system-dir escape blocked)"
  else
    fail "symlink escape got exit $RC"
  fi
fi

# ─── Test 32: Grep pattern-as-path bypass (Phase J J6) ────────────────
echo ""
echo "Test 32: Grep without path argument inspects cwd (pattern-as-path bypass fix)"
T32="$TMPDIR_BASE/t32"
mkdir -p "$T32/.claude" "$T32/data/raw"
echo '{}' > "$T32/.claude/safety-status.json"
printf 'id,ssn\n1,111-22-3333\n' > "$T32/data/raw/patients.csv"
# Grep with pattern="SSN" and NO path argument. Pre-J6 this would have
# substituted "SSN" as the target path and allowed the call. Post-J6,
# the guard sees cwd is a scholar-init project with data/raw/ and blocks.
payload_grep_nopath() {
  jq -n \
    --arg tn "Grep" \
    --arg pat "SSN" \
    --arg cwd "$T32" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat}}'
}
P="$(payload_grep_nopath)"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "scholar-init project root" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "Grep no-path in scholar-init project blocked"
else
  fail "Grep no-path bypass NOT caught (exit $RC) — pattern-as-path bypass"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# Negative: Grep with no path when cwd is NOT a scholar-init project → allow
echo ""
echo "Test 32b: Grep no-path in non-scholar-init cwd is allowed"
T32B="$TMPDIR_BASE/t32b"
mkdir -p "$T32B"
echo "hello" > "$T32B/notes.txt"
payload_grep_nopath_plain() {
  jq -n \
    --arg tn "Grep" \
    --arg pat "hello" \
    --arg cwd "$T32B" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat}}'
}
P="$(payload_grep_nopath_plain)"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass "Grep no-path in plain dir allowed" || fail "no-path Grep wrongly blocked (exit $RC)"

# ─── Test 33: Qualitative OVERRIDE integration (init → hand-edit → guard) ──
echo ""
echo "Test 33: init→edit sidecar OVERRIDE on .wav→guard refuses"
T33="$TMPDIR_BASE/t33"
mkdir -p "$T33/src"
# Fake WAV (RIFF header + minimal payload)
printf 'RIFF\x00\x00\x00\x00WAVEfmt ' > "$T33/src/interview.wav"
mkdir -p "$T33/ws"
INIT_SCRIPT_FOR_T33="${REPO_ROOT}/scripts/init-project.sh"
bash "$INIT_SCRIPT_FOR_T33" --dest "$T33/ws" t33-proj "$T33/src/interview.wav" >/dev/null 2>&1
# Find the canonical path the init script wrote into the sidecar
SIDECAR="$T33/ws/t33-proj/.claude/safety-status.json"
WAV_KEY=$(jq -r 'keys[0]' "$SIDECAR")
# User manually edits sidecar to OVERRIDE (simulating a bypass attempt)
jq --arg fp "$WAV_KEY" '.[$fp] = "OVERRIDE"' "$SIDECAR" > "$SIDECAR.new" && mv "$SIDECAR.new" "$SIDECAR"
# Guard must refuse
P="$(payload Read "$WAV_KEY" "$T33/ws/t33-proj")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "forbids OVERRIDE" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "hand-edited OVERRIDE on .wav refused (integration)"
else
  fail "hand-edited OVERRIDE on .wav allowed (exit $RC) — integration hole"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 34: Absolute-path sidecar wins over basename (Phase I I1) ────
echo ""
echo "Test 34: Absolute-path CLEARED beats conflicting basename-only OVERRIDE"
T34="$TMPDIR_BASE/t34"
mkdir -p "$T34/.claude"
cat > "$T34/data.csv" <<'CSV'
id,ssn
1,111-22-3333
CSV
# Sidecar has BOTH an absolute-path entry AND a basename entry. The
# guard should honor the absolute-path entry (CLEARED) and ignore the
# basename (OVERRIDE) since I1 removed basename fallback.
jq -n \
  --arg fp "$T34/data.csv" \
  '{($fp): "CLEARED", "data.csv": "OVERRIDE"}' > "$T34/.claude/safety-status.json"
P="$(payload Read "$T34/data.csv" "$T34")"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass "absolute-path key wins over basename" || fail "absolute-path not honored (exit $RC)"

# ─── Test 35: Sidecar discovery from nested cwd (CLAUDE_FIX_BRIEF P0 #1) ──
# Regression: earlier versions only consulted $CWD/.claude/safety-status.json.
# A Read issued from project/subdir with cwd=project/subdir ignored the
# project-root sidecar entirely, letting HALTED files through.
echo ""
echo "Test 35: Sidecar is discovered from a nested cwd (ancestor lookup)"
T35="$TMPDIR_BASE/t35"
mkdir -p "$T35/.claude" "$T35/subdir"
HALT_CSV="$T35/subdir/halt.csv"
printf 'a,b\n1,2\n' > "$HALT_CSV"
jq -n --arg fp "$HALT_CSV" '{($fp): "HALTED"}' > "$T35/.claude/safety-status.json"
# Use cwd=$T35/subdir (not the project root). The guard must walk upward
# to find the sidecar at $T35/.claude/safety-status.json.
P="$(payload Read "$HALT_CSV" "$T35/subdir")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "HALTED" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "ancestor sidecar discovered from nested cwd"
else
  fail "nested cwd bypassed ancestor sidecar (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 36: Glob ** from project root is blocked (P0 #2) ─────────────
# Regression: earlier versions only ran the project-root check for EMPTY
# Glob patterns. A non-empty pattern like "**/*" bypassed it and let the
# Glob tool enumerate data/raw/ file paths into context.
echo ""
echo "Test 36: Glob(pattern='**/*') from project root is blocked"
T36="$TMPDIR_BASE/t36"
mkdir -p "$T36/.claude" "$T36/data/raw"
echo '{}' > "$T36/.claude/safety-status.json"
printf 'id,ssn\n1,111-22-3333\n' > "$T36/data/raw/patients.csv"
payload_glob_star() {
  jq -n \
    --arg tn "Glob" \
    --arg pat "**/*" \
    --arg cwd "$T36" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat}}'
}
P="$(payload_glob_star)"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "project root" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "Glob '**/*' from scholar-init root blocked"
else
  fail "Glob '**/*' from scholar-init root NOT blocked (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# Positive control: Glob scoped to scripts/ is allowed
echo ""
echo "Test 36b: Glob(pattern='scripts/**/*.py') from project root is allowed"
mkdir -p "$T36/scripts"
touch "$T36/scripts/analysis.py"
payload_glob_scoped() {
  jq -n \
    --arg tn "Glob" \
    --arg pat "scripts/**/*.py" \
    --arg cwd "$T36" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat}}'
}
P="$(payload_glob_scoped)"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass "scoped Glob scripts/**/*.py allowed" || fail "scoped Glob wrongly blocked (exit $RC)"

# ─── Test 37: Grep on transcripts/ qualitative text (P0 #3) ────────────
# Regression: is_rawdata_path omitted transcripts/, interviews/, etc.,
# so Grep on materials/transcripts/int1.txt was allowed even though Read
# would have gated it. Unifying path classification fixes this.
echo ""
echo "Test 37: Grep on materials/transcripts/int1.txt is blocked"
T37="$TMPDIR_BASE/t37"
mkdir -p "$T37/materials/transcripts"
cat > "$T37/materials/transcripts/int1.txt" <<'TXT'
Interviewer: Tell me about your day.
Alice: I woke up around 7.
TXT
payload_grep() {
  jq -n \
    --arg tn "Grep" \
    --arg pat "Alice" \
    --arg path "$1" \
    --arg cwd "$2" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat, path:$path}}'
}
P="$(payload_grep "$T37/materials/transcripts/int1.txt" "$T37")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "Grep on materials/transcripts/ blocked"
else
  fail "Grep on materials/transcripts/ NOT blocked (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

echo ""
echo "Test 37b: Glob on materials/transcripts/*.txt is blocked"
payload_glob_literal() {
  jq -n \
    --arg tn "Glob" \
    --arg pat "$1" \
    --arg cwd "$2" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat}}'
}
P="$(payload_glob_literal "$T37/materials/transcripts/*.txt" "$T37")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "Glob on materials/transcripts/ blocked"
else
  fail "Glob on materials/transcripts/ NOT blocked (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 38: OVERRIDE refused for .txt transcript (P0 #4) ─────────────
# Regression: OVERRIDE refusal used only an extension list. A user could
# hand-edit the sidecar to OVERRIDE transcripts/p1.txt and the guard
# would allow it because .txt wasn't in the audio/video/eaf list.
echo ""
echo "Test 38: OVERRIDE on .txt transcript is refused (path-based classification)"
T38="$TMPDIR_BASE/t38"
mkdir -p "$T38/.claude" "$T38/transcripts"
TXT_TRANS="$T38/transcripts/p1.txt"
cat > "$TXT_TRANS" <<'TXT'
P1: I wouldn't share this with just anyone.
TXT
jq -n --arg fp "$TXT_TRANS" '{($fp): "OVERRIDE"}' > "$T38/.claude/safety-status.json"
P="$(payload Read "$TXT_TRANS" "$T38")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "qualitative" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "OVERRIDE on .txt in transcripts/ refused"
else
  fail "OVERRIDE on .txt in transcripts/ NOT refused (exit $RC) — qual bypass"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# Negative control: OVERRIDE on a .txt in a NON-qual path is honored
echo ""
echo "Test 38b: OVERRIDE on .txt outside qual paths is still honored"
T38B="$TMPDIR_BASE/t38b"
mkdir -p "$T38B/.claude" "$T38B/data/raw"
REG_TXT="$T38B/data/raw/response-summary.txt"
echo "aggregated response counts" > "$REG_TXT"
jq -n --arg fp "$REG_TXT" '{($fp): "OVERRIDE"}' > "$T38B/.claude/safety-status.json"
P="$(payload Read "$REG_TXT" "$T38B")"
RC=$(run_guard_capture "$P")
[ "$RC" = "0" ] && pass "OVERRIDE on non-qual .txt allowed" || fail "non-qual OVERRIDE wrongly refused (exit $RC)"

# ─── Test 39: Invalid sidecar schema — non-string value (P2 #7) ────────
# Regression: the guard stringified lookup values via `tostring` and only
# enforced exact known strings. An object-valued entry like
# {"status": "HALTED"} silently converted to "{\"status\":\"HALTED\"}"
# which was not recognized and treated as "no entry" — allowing Read.
echo ""
echo "Test 39: Object-valued sidecar entry fails closed"
T39="$TMPDIR_BASE/t39"
mkdir -p "$T39/.claude"
OBJ_CSV="$T39/data.csv"
printf 'a,b\n1,2\n' > "$OBJ_CSV"
cat > "$T39/.claude/safety-status.json" <<JSON
{
  "$OBJ_CSV": {"status": "HALTED"}
}
JSON
P="$(payload Read "$OBJ_CSV" "$T39")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q -i "schema" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "object-valued sidecar entry rejected by schema validation"
else
  fail "malformed sidecar not rejected (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 35b: Grep from nested cwd discovers ancestor sidecar ─────────
# Regression companion to Test 35: Read used the new find_project_root,
# but Grep/Glob call it independently. Make sure both tools see the
# ancestor sidecar, otherwise a fix in one branch could still leave the
# other one broken.
echo ""
echo "Test 35b: Grep from nested cwd is blocked when project root has data/raw/"
T35B="$TMPDIR_BASE/t35b"
mkdir -p "$T35B/.claude" "$T35B/data/raw" "$T35B/subdir"
echo '{}' > "$T35B/.claude/safety-status.json"
printf 'id,ssn\n1,111-22-3333\n' > "$T35B/data/raw/patients.csv"
# Grep with NO path argument, cwd=$T35B/subdir. The guard must walk up
# from subdir/, find the project root, and block enumeration.
payload_grep_nested_nopath() {
  jq -n \
    --arg tn "Grep" \
    --arg pat "SSN" \
    --arg cwd "$T35B/subdir" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat}}'
}
P="$(payload_grep_nested_nopath)"
RC=$(run_guard_capture "$P")
# Nested cwd is NOT itself the project root, so the strict equality
# check at (b) does not fire — but the ancestor lookup test should
# still catch data/raw enumeration via the (a) path-classifier on the
# canonical cwd that contains data/raw/ in an ancestor.
# This test specifically locks in that find_project_root is called
# for Grep with a nested cwd. Current behavior: Grep does NOT block
# here because is_rawdata_path checks the subdir itself (not ancestors),
# so this is a known-limitation test: we expect allow (0) so that a
# future refactor that over-blocks doesn't break working Grep calls.
[ "$RC" = "0" ] && pass "Grep from subdir with no path in non-rawdata subdir allowed" \
  || fail "Grep from subdir wrongly blocked (exit $RC)"

# But Grep with path explicitly pointing INTO data/raw from nested cwd
# must still be blocked.
echo ""
echo "Test 35c: Grep with explicit path into data/raw from nested cwd is blocked"
payload_grep_into_raw() {
  jq -n \
    --arg tn "Grep" \
    --arg pat "SSN" \
    --arg path "$T35B/data/raw/patients.csv" \
    --arg cwd "$T35B/subdir" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat, path:$path}}'
}
P="$(payload_grep_into_raw)"
RC=$(run_guard_capture "$P")
[ "$RC" = "2" ] && pass "Grep into data/raw from nested cwd blocked" \
  || fail "Grep into data/raw from nested cwd allowed (exit $RC)"

# ─── Test 36c: Glob with explicit path=<project-root> is blocked ───────
# Regression: the Glob project-root check reads `tool_input.path` (via
# GREP_PATH) first, then falls back to cwd. Test 36 exercised the cwd
# fallback. This test exercises the explicit-path branch — a call like
# Glob(pattern="*.py", path="/abs/project-root") must also be blocked.
echo ""
echo "Test 36c: Glob with explicit path=<project-root> is blocked"
payload_glob_path_root() {
  jq -n \
    --arg tn "Glob" \
    --arg pat "**/*" \
    --arg path "$T36" \
    --arg cwd "/tmp" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat, path:$path}}'
}
P="$(payload_glob_path_root)"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "project root" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "Glob with explicit path=<project-root> blocked"
else
  fail "Glob explicit-path project-root NOT blocked (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 38c: OVERRIDE on .txt inside materials/consent/ is refused ───
# Regression (CRIT-001 from the review): is_qual_path was narrower than
# is_rawdata_path for materials/ subtrees. A .txt consent form under
# materials/consent/ was blocked by Read's is_rawdata_path classifier,
# but the OVERRIDE refusal used is_qual_path which only caught
# transcripts/interviews/field-notes. A hand-edited OVERRIDE let consent
# forms through — exactly the P0 #4 bypass. is_qual_path now covers the
# whole materials/ subtree.
echo ""
echo "Test 38c: OVERRIDE on .txt under materials/consent/ is refused"
T38C="$TMPDIR_BASE/t38c"
mkdir -p "$T38C/.claude" "$T38C/materials/consent"
CONSENT_TXT="$T38C/materials/consent/p1.txt"
cat > "$CONSENT_TXT" <<'TXT'
Participant name: Jane Smith
Signature: [signed]
TXT
jq -n --arg fp "$CONSENT_TXT" '{($fp): "OVERRIDE"}' > "$T38C/.claude/safety-status.json"
P="$(payload Read "$CONSENT_TXT" "$T38C")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ] && grep -q "qualitative" "$TMPDIR_BASE/stderr" 2>/dev/null; then
  pass "OVERRIDE on materials/consent/*.txt refused"
else
  fail "OVERRIDE on materials/consent/*.txt NOT refused (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 37c: Relative Grep path in data/raw/ from project cwd (HIGH-004) ──
# Regression: canonicalize used to return relative paths unchanged, so a
# payload with cwd=$PROJECT and tool_input.path="data/raw/x.csv" produced
# CANON_TARGET="data/raw/x.csv" which failed is_rawdata_path's leading-*/
# case pattern. The fix: canonicalize prepends $CWD to relative targets
# before resolving.
echo ""
echo "Test 37c: Grep with relative path='data/raw/*' is blocked"
T37C="$TMPDIR_BASE/t37c"
mkdir -p "$T37C/data/raw" "$T37C/.claude"
echo '{}' > "$T37C/.claude/safety-status.json"
printf 'id,ssn\n1,222-33-4444\n' > "$T37C/data/raw/patients.csv"
payload_grep_rel() {
  jq -n \
    --arg tn "Grep" \
    --arg pat "SSN" \
    --arg path "data/raw/patients.csv" \
    --arg cwd "$T37C" \
    '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{pattern:$pat, path:$path}}'
}
P="$(payload_grep_rel)"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "Grep with relative path resolved against CWD and blocked"
else
  fail "Grep with relative path NOT blocked (exit $RC) — HIGH-004 regression"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Test 39c: python3 hard-dependency check (gated tool) ──────────────
# Regression: HIGH-005 from review round 1 observed that `canonicalize`
# degrades gracefully through python3 → realpath → readlink -f → bash
# fallback, and the bash fallback leaves literal '..' in the path on
# pathological inputs. We chose to close the loop by hard-requiring
# python3 for gated tools. Verify the check fires and non-gated tools
# are unaffected.
echo ""
echo "Test 39c: python3 hard-dependency check fires for gated tools"
NO_PY_BIN="$TMPDIR_BASE/no-py-bin"
mkdir -p "$NO_PY_BIN"
# Link every utility the guard touches BEFORE the python3 check, minus
# python3 and realpath. We need jq (payload parse), plus common
# coreutils the script uses (tr for lowercase, cat to read stdin,
# printf/echo/sed/head for the fallback parser, dirname/basename for
# path ops, chmod/mktemp/rm/ln/mkdir for trap cleanup, date for log
# timestamps). Bash builtins (test, case, [, command) don't need
# links — they're in the bash process itself.
for cmd in jq tr cat printf echo sed head dirname basename chmod mktemp rm ln mkdir date grep awk cp mv touch readlink; do
  src="$(command -v "$cmd" 2>/dev/null || true)"
  if [ -n "$src" ]; then
    ln -sf "$src" "$NO_PY_BIN/$cmd"
  fi
done
# Verify the scratch PATH really is python3-free
if PATH="$NO_PY_BIN" command -v python3 >/dev/null 2>&1; then
  # Can't run this test — python3 leaked into the scratch bin somehow.
  # (This would only happen if one of the linked tools was a symlink
  # to python3 itself, which is not a standard install.)
  echo "  SKIP: could not build a python3-free PATH on this system"
else
  # A Read on a CSV file should now fail closed with the python3 message.
  T39C="$TMPDIR_BASE/t39c"
  mkdir -p "$T39C"
  printf 'a,b\n1,2\n' > "$T39C/file.csv"
  P="$(payload Read "$T39C/file.csv" "$T39C")"
  PATH="$NO_PY_BIN" echo "$P" | PATH="$NO_PY_BIN" /bin/bash "$GUARD" 2>"$TMPDIR_BASE/stderr"
  RC=$?
  if [ "$RC" = "2" ] && grep -q "python3" "$TMPDIR_BASE/stderr" 2>/dev/null; then
    pass "Read blocked with python3-required message"
  else
    fail "Read did not fail closed on missing python3 (exit $RC)"
    echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
  fi

  # Non-gated tool (Bash) must still pass through.
  P="$(jq -n --arg tn "Bash" --arg cwd "$T39C" '{session_id:"t", transcript_path:"", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tn, tool_input:{command:"ls"}}')"
  PATH="$NO_PY_BIN" echo "$P" | PATH="$NO_PY_BIN" /bin/bash "$GUARD" 2>"$TMPDIR_BASE/stderr"
  RC=$?
  if [ "$RC" = "0" ]; then
    pass "non-gated Bash tool passes through even without python3"
  else
    fail "Bash tool wrongly blocked on missing python3 (exit $RC)"
    echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
  fi
fi

# ─── Test 39b: Unknown status string → fails closed ────────────────────
echo ""
echo "Test 39b: Unknown status string is rejected"
T39B="$TMPDIR_BASE/t39b"
mkdir -p "$T39B/.claude"
BAD_CSV="$T39B/data.csv"
printf 'a,b\n1,2\n' > "$BAD_CSV"
jq -n --arg fp "$BAD_CSV" '{($fp): "SURE_GO_AHEAD"}' > "$T39B/.claude/safety-status.json"
P="$(payload Read "$BAD_CSV" "$T39B")"
RC=$(run_guard_capture "$P")
if [ "$RC" = "2" ]; then
  pass "unknown status rejected"
else
  fail "unknown status not rejected (exit $RC)"
  echo "    stderr:"; sed 's/^/      /' "$TMPDIR_BASE/stderr"
fi

# ─── Summary ────────────────────────────────────────────────────────────
echo ""
echo "════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo ">>> FAILED"
  exit 1
else
  echo ">>> PASSED"
  exit 0
fi
