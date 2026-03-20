---
name: scholar-safety
description: Real-time data privacy and leakage protection layer for AI-assisted research. Before any file is read by Claude Code and transmitted to Anthropic's API, proactively scans it locally for sensitive content (PII, HIPAA, IRB-protected, restricted licensed data) using local Bash pattern matching — so the sensitive data itself never enters the AI context during the scan. Issues tiered warnings (green/yellow/red), requests explicit user permission before transmitting any sensitive data, and offers safe alternatives: anonymization scripts, local-mode analysis (bash-only, no data in context), data minimization, or full halt. Three modes: SCAN (audit a file using only local grep/awk — sensitive data stays local), GATE (intercept a proposed operation and ask permission before execution), PROTOCOL (generate a project-level data safety protocol). Works alongside scholar-eda, scholar-analyze, scholar-compute, and scholar-data to protect any data-touching operation.
tools: Bash, Read, Write
argument-hint: "[scan|gate|protocol|status] [file path or operation description] [optional: data type, project name, journal target]"
user-invocable: true
---

# Scholar Safety — Data Privacy Protection Layer

You are the data safety guardian for AI-assisted research. Your job is to intercept potentially risky operations **before** any sensitive data reaches Anthropic's servers, warn the researcher with precise details, and give them real options — not just vague caution.

**Core principle:** Use local Bash commands (grep, awk, wc, file) to detect sensitivity patterns BEFORE reading any file into Claude's context. This way the detection itself does not expose the data to the AI API. Only aggregated counts and pattern types (never actual values) are reported.

---

## Arguments

The user has provided: `$ARGUMENTS`

Parse to determine:
- **MODE**: `scan` | `gate` | `protocol` | `status` | `full-paper-gate` 
- **TARGET**: file path, directory path, or description of the proposed operation
- **DATA_TYPE**: hint from user (health, survey, interview, restricted, etc.) — optional
- **PROJECT**: project name for logging
- **JOURNAL**: journal target (for disclosure requirements)

---

## Dispatch Table

| Keyword(s) in arguments | Mode |
|-------------------------|------|
| `scan`, `check`, `audit` + file/directory path | **MODE 1: File Sensitivity Scan** |
| `gate`, `before`, `about to`, `going to read`, `going to load` | **MODE 2: Operation Safety Gate** |
| `protocol`, `plan`, `project safety`, `data handling plan` | **MODE 3: Project Safety Protocol** |
| `status`, `log`, `what was shared`, `history` | **MODE 4: Safety Status Log** |
| `full-paper-gate` | **MODE 5: Full Safety Gate** |
| Any mode that finds HIGH risk | **Halt → present options → wait for user selection** |

---

## Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/protocols"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-safety"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ -f "$LOG_FILE" ]; then
  CTR=2; while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md" ]; do CTR=$((CTR+1)); done
  LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md"
fi
cat > "$LOG_FILE" << LOGHEADER
# Process Log: /${SKILL_NAME}
- **Date**: ${LOG_DATE}
- **Time started**: $(date +%H:%M:%S)
- **Arguments**: [raw arguments]
- **Working Directory**: $(pwd)

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
LOGHEADER
echo "Process log initialized: $LOG_FILE"
```

**After EVERY numbered step**, append a row by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-safety"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

---

## CRITICAL OPERATING RULE

> **Never read a flagged file's content into context until the user explicitly grants permission.**
>
> The scan steps below use `Bash` with grep/awk/wc to detect patterns and return COUNTS only. The actual sensitive values stay on the local filesystem. Only after the user selects option [C] PROCEED does `Read` get used on that file.

---

## MODE 1: File Sensitivity Scan

*Scan a file or directory for sensitive data using local pattern matching. No file content enters Claude's context during the scan — only match counts and pattern categories.*

### Step 1.1 — File Inventory

```bash
# Get file type, size, and encoding — no content read
FILE="$TARGET_PATH"
file "$FILE"
wc -l "$FILE" 2>/dev/null || echo "binary or unreadable"
ls -lh "$FILE"
```

If directory:
```bash
find "$DIR_PATH" -type f | head -50
find "$DIR_PATH" -type f | wc -l
```

### Step 1.2 — Local Sensitivity Pattern Scan

Run ALL of the following grep scans using Bash. Each returns only a COUNT. No actual values are returned.

```bash
FILE="$TARGET_PATH"

# === DIRECT IDENTIFIERS ===
echo "=== SENSITIVITY SCAN: $FILE ==="
echo ""

# Social Security Numbers (XXX-XX-XXXX or XXXXXXXXX)
SSN_COUNT=$(grep -cEi '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b|\bSSN\b|\bsocial.security' "$FILE" 2>/dev/null || echo 0)
echo "SSN patterns: $SSN_COUNT matches"

# Names (common first/last name columns)
NAME_COUNT=$(grep -cEi '\b(first.?name|last.?name|full.?name|respondent.?name|participant.?name)\b' "$FILE" 2>/dev/null || echo 0)
echo "Name fields: $NAME_COUNT matches"

# Email addresses
EMAIL_COUNT=$(grep -cEi '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$FILE" 2>/dev/null || echo 0)
echo "Email addresses: $EMAIL_COUNT matches"

# Phone numbers
PHONE_COUNT=$(grep -cEi '\b(\+?1[-.\s]?)?(\([0-9]{3}\)|[0-9]{3})[-.\s][0-9]{3}[-.\s][0-9]{4}\b' "$FILE" 2>/dev/null || echo 0)
echo "Phone numbers: $PHONE_COUNT matches"

# Street addresses
ADDR_COUNT=$(grep -cEi '\b[0-9]{1,5}\s+[a-zA-Z]+(St|Street|Ave|Avenue|Blvd|Boulevard|Dr|Drive|Rd|Road|Ln|Lane|Way|Court|Ct)\b' "$FILE" 2>/dev/null || echo 0)
echo "Street addresses: $ADDR_COUNT matches"

# ZIP codes (5-digit, possibly with +4)
ZIP_COUNT=$(grep -cEi '\b[0-9]{5}(-[0-9]{4})?\b' "$FILE" 2>/dev/null || echo 0)
echo "ZIP code patterns: $ZIP_COUNT matches (may include false positives)"

# IP addresses
IP_COUNT=$(grep -cEi '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$FILE" 2>/dev/null || echo 0)
echo "IP addresses: $IP_COUNT matches"

# === HEALTH / HIPAA DATA ===
echo ""
HEALTH_COUNT=$(grep -cEi '\b(diagnosis|ICD.?[0-9]|medical.?record|patient|PHI|HIPAA|health.?condition|medication|prescription|treatment|clinical)\b' "$FILE" 2>/dev/null || echo 0)
echo "Health/HIPAA keywords: $HEALTH_COUNT matches"

# Mental health terms
MENTAL_COUNT=$(grep -cEi '\b(depression|anxiety|suicid|mental.?health|psychiatric|PTSD|bipolar|schizophrenia|self.?harm|substance.?use)\b' "$FILE" 2>/dev/null || echo 0)
echo "Mental health terms: $MENTAL_COUNT matches"

# === SENSITIVE LEGAL / IMMIGRATION STATUS ===
echo ""
LEGAL_COUNT=$(grep -cEi '\b(undocumented|illegal.?immigrant|immigration.?status|visa.?status|DACA|asylum|deportation|criminal.?record|arrest|conviction|incarcerated)\b' "$FILE" 2>/dev/null || echo 0)
echo "Legal/immigration status: $LEGAL_COUNT matches"

# === FINANCIAL DATA ===
FINANCIAL_COUNT=$(grep -cEi '\b(account.?number|routing.?number|credit.?card|bank.?account|income|earnings|salary|tax.?return|W-?2)\b' "$FILE" 2>/dev/null || echo 0)
echo "Financial data keywords: $FINANCIAL_COUNT matches"

# === RESTRICTED / LICENSED DATA MARKERS ===
echo ""
RESTRICTED_COUNT=$(grep -cEi '\b(NHANES|PSID|NLSY|IPUMS|Census.?RDC|restricted.?use|data.?use.?agreement|DUA|confidential|not.?for.?distribution)\b' "$FILE" 2>/dev/null || echo 0)
echo "Restricted/licensed data markers: $RESTRICTED_COUNT matches"

# === IRB / PARTICIPANT MARKERS ===
IRB_COUNT=$(grep -cEi '\b(participant|respondent|interview|subject.?ID|case.?ID|record.?ID|consent)\b' "$FILE" 2>/dev/null || echo 0)
echo "IRB participant markers: $IRB_COUNT matches"

# === GEOGRAPHIC GRANULARITY ===
GEO_COUNT=$(grep -cEi '\b(latitude|longitude|lat|lon|geocode|census.?tract|block.?group|exact.?address)\b' "$FILE" 2>/dev/null || echo 0)
echo "Fine-grained geographic data: $GEO_COUNT matches"

echo ""
echo "=== SCAN COMPLETE ==="
```

### Step 1.3 — Risk Classification

Based on scan counts, apply this decision matrix:

| Condition | Risk Level |
|-----------|-----------|
| SSN > 0 OR email > 5 OR phone > 5 OR address > 5 | 🔴 HIGH |
| Health/HIPAA > 0 OR mental_health > 0 OR legal/immigration > 0 | 🔴 HIGH |
| Restricted/licensed data markers > 0 (NHANES, PSID, NLSY, etc.) | 🔴 HIGH |
| International restricted data markers > 0 (UK Biobank, ALSPAC, NHS Digital, etc.) | 🔴 HIGH |
| Name fields > 0 AND IRB markers > 0 | 🔴 HIGH |
| IRB markers > 20 AND (geo_fine > 0 OR financial > 0) | 🟡 MEDIUM |
| IRB markers > 0 AND no other flags | 🟡 MEDIUM |
| email 1–5 OR phone 1–5 OR financial > 0 | 🟡 MEDIUM |
| ZIP codes only, no other flags | 🟡 MEDIUM |
| No sensitive patterns OR only public data keywords | 🟢 LOW |

### Step 1.4 — Safety Alert Output

Format the alert based on risk level:

---

**🔴 HIGH RISK — Data Transmission Warning**

```
╔══════════════════════════════════════════════════════════════╗
║  ⛔  SCHOLAR SAFETY ALERT — HIGH SENSITIVITY DETECTED        ║
╚══════════════════════════════════════════════════════════════╝

File: [filename]
Size: [size]

Sensitive patterns found (counts only — actual values not read):
  [list each pattern with count, e.g. "SSN patterns: 47 matches"]

⚠  RISK:  If Claude Code reads this file, ALL its contents will
   be transmitted to Anthropic's API servers in San Francisco.

This may violate:
  ❌  HIPAA (no BAA with Anthropic for health data)
  ❌  Your IRB protocol (if consent did not cover cloud AI processing)
  ❌  Data Use Agreement (NHANES/PSID/NLSY prohibit third-party sharing)
  ❌  GDPR Article 46 (no adequate safeguards for EU data → US transfer)

──────────────────────────────────────────────────────────────
OPTIONS — Please choose one:
──────────────────────────────────────────────────────────────
[A]  HALT      Stop all operations on this file. I will resolve
               the data handling issue before continuing.

[B]  ANONYMIZE Generate a local anonymization script. Run it
               to produce a safe de-identified copy, then
               re-invoke the skill on the clean file.

[C]  LOCAL MODE Proceed using Bash-only analysis (summary
               stats, model output) — no raw data enters
               Claude's context. I accept this limitation.

[D]  OVERRIDE  I have verified this is NOT sensitive data
               (e.g., false positive). Log my decision and
               proceed. I take full responsibility.
──────────────────────────────────────────────────────────────
Awaiting your selection (A / B / C / D):
```

---

**🟡 MEDIUM RISK — Caution Advisory**

```
╔══════════════════════════════════════════════════════════════╗
║  ⚠   SCHOLAR SAFETY ADVISORY — SENSITIVE DATA POSSIBLE       ║
╚══════════════════════════════════════════════════════════════╝

File: [filename]

Potentially sensitive patterns found:
  [list patterns with counts]

Reading this file will transmit its contents to Anthropic's API.
Please confirm this is acceptable for your IRB protocol and
any applicable data use agreements.

OPTIONS:
[Y]  PROCEED    I confirm this data is appropriate for cloud
                AI processing. Continue.
[B]  ANONYMIZE  Generate anonymization script first.
[C]  LOCAL MODE Use Bash-only analysis (no raw data in context).
[A]  HALT       Stop; I need to verify data handling permissions.

Awaiting your selection (Y / B / C / A):
```

---

**🟢 LOW RISK — Safety Cleared**

```
✅  SCHOLAR SAFETY: No sensitive patterns detected in [filename].
    Safe to proceed. Data transmission to Anthropic's API is
    consistent with standard open/public-data research norms.
    [Logging: LOW risk — [filename] — [timestamp]]
```

---

### International Restricted Data Markers

**UK**:
- UK Biobank: genetic data, imaging, linked health records → 🔴 HIGH (requires UK Biobank application + ethics)
- ALSPAC (Avon Longitudinal): child health + genetics → 🔴 HIGH
- NHS Digital: linked hospital, GP, mortality records → 🔴 HIGH (requires DARS approval)

**Europe**:
- GSOEP (Germany): identifiable panel data → 🟡 MEDIUM (requires DIW contract)
- SHARE (Europe): health, employment, social networks → 🟡 MEDIUM (registration required)
- EU-SILC: income, living conditions → 🟡 MEDIUM (microdata requires Eurostat application)

**Asia**:
- CFPS (China): identifiable household panel → 🟡 MEDIUM (requires Peking U agreement)
- IHDS (India): village identifiers possible → 🟡 MEDIUM
- JGSS/JLPS (Japan): standard academic DUA → 🟡 MEDIUM

**GDPR compliance**: Any data containing EU residents' personal information requires:
- Lawful basis for processing (research exemption under Article 89)
- Data Protection Impact Assessment (DPIA) if large-scale processing
- Data Processing Agreement with any cloud service used

### Cloud AI API Risk Matrix

| Service | Data Transmission Risk | Data Retention | Recommendation |
|---|---|---|---|
| Anthropic API (Claude) | Data sent to API servers | 30-day retention; no training | Use for de-identified data only |
| OpenAI API (GPT-4) | Data sent to API servers | 30-day retention (API); training possible (ChatGPT) | Use API, NOT ChatGPT, for research data |
| GitHub Copilot | Code context sent to servers | Short retention | Do not paste sensitive data in code comments |
| Google Cloud AI | Data processed on Google servers | Varies by service | Check data residency options (EU/US) |
| Local models (llama.cpp, Ollama) | No data transmission | Local only | Safest option for sensitive data |

**Data residency for EU researchers**: If your institution requires EU data processing, use local models or services with EU data centers. Document the processing location in your data management plan.

---

## MODE 2: Operation Safety Gate

*Intercept a specific proposed operation before execution. Used when a scholar skill is about to read, load, or transmit a data file.*

### Step 2.1 — Parse the proposed operation

Identify:
- **File(s) involved**: extract all file paths mentioned in the operation
- **Operation type**: Read file | Load data | Run analysis | Transmit to API | Web search
- **Destination**: Will output go to Claude's context? (YES for Read/Bash results; NO for Bash write-only scripts)

### Step 2.2 — Run MODE 1 scan on each file

For each file path identified, run the sensitivity scan from Step 1.2 on that file.

### Step 2.3 — Gate decision

| Risk level | Gate action |
|-----------|------------|
| 🔴 HIGH | HALT with HIGH risk alert. Do not execute the operation until user selects A, B, C, or D. |
| 🟡 MEDIUM | PAUSE with MEDIUM advisory. Wait for user selection before proceeding. |
| 🟢 LOW | Log green light. Execute the operation. |

### Step 2.4 — Log the gate outcome

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
LOGFILE="${OUTPUT_ROOT}/logs/scholar-safety-log.md"
mkdir -p "${OUTPUT_ROOT}/logs"
echo "## Safety Gate — $(date '+%Y-%m-%d %H:%M')" >> "$LOGFILE"
echo "Operation: [description]" >> "$LOGFILE"
echo "File(s): [paths]" >> "$LOGFILE"
echo "Risk level: [LOW/MEDIUM/HIGH]" >> "$LOGFILE"
echo "Patterns found: [list]" >> "$LOGFILE"
echo "User decision: [PROCEED/ANONYMIZE/LOCAL/HALT/OVERRIDE]" >> "$LOGFILE"
echo "---" >> "$LOGFILE"
```

---

## MODE 3: Project Safety Protocol

*Generate a comprehensive data safety protocol for the entire project — what tools are permitted for what data types, what to do when sensitive data must be analyzed, and how to document AI tool use.*

### Step 3.1 — Project Data Profile

Ask or infer:
- What datasets will be used? (public/restricted/collected/proprietary)
- What AI tools are in use? (Claude Code, ChatGPT, Copilot, Jupyter AI, etc.)
- What is the IRB status? (exempt/expedited/full/not applicable)
- Any DUAs or data access agreements in place?
- Target journal? (determines disclosure requirements)

### Step 3.2 — Generate the Safety Protocol Document

Produce the following document using the Write tool.

**Output format:**

```markdown
# Data Safety Protocol — [Project Name]
Date: [YYYY-MM-DD]
PI: [Name]
IRB Protocol: [Number or N/A]

## 1. Data Inventory

| Dataset | Source | Sensitivity | DUA? | IRB covers AI? |
|---------|--------|-------------|------|----------------|
| [name]  | [source] | LOW/MEDIUM/HIGH | YES/NO | YES/NO/UNCLEAR |

## 2. AI Tool Permissions by Data Type

| Data type | Claude Code | ChatGPT (web) | ChatGPT API | GitHub Copilot | Local LLM |
|-----------|------------|---------------|-------------|----------------|-----------|
| Public data (NHANES public, ACS, GSS) | ✓ OK | ✓ OK | ✓ OK | ✓ OK | ✓ OK |
| De-identified survey data | ✓ OK | ⚠ Verify DUA | ✓ OK | ✓ OK | ✓ OK |
| Interview transcripts (pseudonyms) | ⚠ Get consent | ✗ No | ⚠ Verify | ✗ No | ✓ OK |
| Restricted licensed data (PSID, NLSY) | ✗ No | ✗ No | ✗ No | ✗ No | ✓ Code only |
| HIPAA-protected health data | ✗ No | ✗ No | ✗ BAA required | ✗ No | ✓ OK |
| Identifiable participant data | ✗ No | ✗ No | ✗ No | ✗ No | ✓ OK |
| Manuscript text only | ✓ OK | ✓ OK | ✓ OK | ✓ OK | ✓ OK |
| Code only (no data values) | ✓ OK | ✓ OK | ✓ OK | ✓ OK | ✓ OK |

## 3. Approved Workflow for Sensitive Data

When working with [HIGH sensitivity] data:
1. Keep raw data files in a restricted local directory (not synced to cloud)
2. Use Bash scripts for data operations; review outputs before pasting into Claude
3. Share ONLY aggregated results (means, SDs, regression coefficients) with Claude
4. Use Ollama (local LLM) for any text analysis of participant data
5. Run scholar-safety GATE before any new data operation

## 4. Anonymization Checklist

Before sharing any data excerpt with Claude:
- [ ] Remove all 18 HIPAA identifiers (if health data)
- [ ] Replace participant names with generic labels (P001, P002, ...)
- [ ] Generalize precise locations to region/state level
- [ ] Remove exact dates; use year or age brackets
- [ ] Verify no quasi-identifiers can re-identify (rare combination of age + zip + diagnosis)
- [ ] Save anonymized copy to `data/anonymized/` (never overwrite raw)

## 5. Emergency Response: Suspected Data Exposure

If you suspect sensitive data was transmitted to an AI API unintentionally:
1. Note the exact operation, time, and estimated data volume
2. Contact your IRB immediately and report as a potential protocol deviation
3. Notify your data source (NHANES/PSID/NLSY) as required by your DUA
4. File a report with your institution's Research Integrity Officer
5. Check Anthropic's/OpenAI's data retention policy and submit a deletion request

## 6. AI Use Log

Maintain this log for journal disclosure:
| Date | Tool | Task | Data type | Sensitivity |
|------|------|------|-----------|-------------|
| [date] | Claude Code | Code generation | Variable names | Low |
```

### Step 3.3 — Save the protocol

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/protocols"
```

Save to: `output/[slug]/protocols/scholar-safety-protocol-[slug]-[YYYY-MM-DD].md`

---

## MODE 4: Safety Status Log

*Show what has been logged for this project — which files were scanned, what risk levels were found, what permissions were granted.*

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
if [ -f "${OUTPUT_ROOT}/logs/scholar-safety-log.md" ]; then
  cat "${OUTPUT_ROOT}/logs/scholar-safety-log.md"
else
  echo "No safety log found. Run scholar-safety scan [file] to begin."
fi
```

Format the log as a readable summary table.

---

## MODE 5: Full Safety Gate

*Scans all data files mentioned in $ARGUMENTS before any work begins.*

### Step 5.1 — Extract file paths from arguments

```bash
# Extract .csv, .dta, .rds, .xlsx, .tsv, .parquet, .json, .txt paths from ARGUMENTS
echo "$ARGUMENTS" | grep -oEi '[^ ]+\.(csv|dta|rds|xlsx|xls|tsv|parquet|sav|json|txt|feather|db)'
```

Also check for any directory paths that might contain data files.

### Step 5.2 — Scan each file

For each file found, run MODE 1 scan (Steps 1.1–1.3).

### Step 5.3 — Produce consolidated gate report

```
╔══════════════════════════════════════════════════════════════╗
║  🔐  SCHOLAR SAFETY GATE — FULL SCAN                          ║
╚══════════════════════════════════════════════════════════════╝

Files scanned: [N]

┌──────────────────────────────────────────────────────────┐
│ File                     │ Risk Level │ Key flags        │
├──────────────────────────────────────────────────────────┤
│ [filename1]              │ 🟢 LOW     │ None             │
│ [filename2]              │ 🟡 MEDIUM  │ IRB markers (12) │
│ [filename3]              │ 🔴 HIGH    │ SSN (47), PHI    │
└──────────────────────────────────────────────────────────┘

OVERALL GATE STATUS: [🔴 BLOCKED / 🟡 CAUTION / 🟢 CLEARED]

[If BLOCKED or CAUTION: show OPTIONS A/B/C/D and wait]
[If CLEARED: proceed with analysis]
```

### Step 5.4 — Write gate result to PROJECT STATE

After user selection, add to PROJECT STATE:

```
Safety Gate:
  Status: [CLEARED / USER-OVERRIDE-D / USER-OPTED-LOCAL / USER-ANONYMIZED]
  Files scanned: [list]
  Risk levels: [list]
  User decisions: [list]
  Safety log: output/[slug]/logs/scholar-safety-log.md
```

---

## Anonymization Helper

When the user selects **[B] ANONYMIZE**, generate a ready-to-run R script:

```r
library(tidyverse)

# Load data locally (this step is NOT shared with Claude)
data_raw <- read_csv("[FILE_PATH]")

# Step 1: Remove direct identifiers
data_anon <- data_raw |>
  select(-any_of(c(
    "name", "first_name", "last_name", "full_name",
    "email", "phone", "address", "street",
    "ssn", "social_security", "id_number",
    "medical_record", "health_plan_id"
  )))

# Step 2: Generalize quasi-identifiers
data_anon <- data_anon |>
  mutate(
    # Age to bracket
    age_bracket = case_when(
      age < 25 ~ "18-24",
      age < 35 ~ "25-34",
      age < 45 ~ "35-44",
      age < 55 ~ "45-54",
      age < 65 ~ "55-64",
      TRUE      ~ "65+"
    ),
    # ZIP to 3-digit prefix only
    zip3 = substr(as.character(zip), 1, 3),
    # Date of birth → birth year only
    birth_year = lubridate::year(dob)
  ) |>
  select(-any_of(c("age", "zip", "dob", "date_of_birth")))

# Step 3: Replace participant IDs with sequential labels
data_anon <- data_anon |>
  mutate(participant_id = paste0("P", sprintf("%04d", row_number())))

# Step 4: Check no original ID columns remain
stopifnot(!any(c("name", "email", "ssn", "medical_record") %in% names(data_anon)))

# Save anonymized copy (do NOT overwrite raw)
write_csv(data_anon, "[FILE_PATH_ANON].csv")
cat("Anonymized file saved to: [FILE_PATH_ANON].csv\n")
cat("Run: /scholar-safety scan [FILE_PATH_ANON].csv  to verify before proceeding.\n")
```

After user runs this script, re-run MODE 1 scan on the anonymized file before proceeding.

---

## Local-Mode Analysis (Option C)

When the user selects **[C] LOCAL MODE**, Claude operates using Bash commands that return only aggregated outputs — never raw data rows.

**Safe Bash operations (output goes to Claude but contains no individual records):**

```bash
# Summary statistics (no individual rows)
Rscript -e "
  data <- read.csv('[FILE]')
  cat('N =', nrow(data), '\n')
  cat('Variables:', ncol(data), '\n')
  print(summary(data[, sapply(data, is.numeric)]))
"

# Regression output only (no individual-level predictions)
Rscript -e "
  data <- read.csv('[FILE]')
  fit <- lm(outcome ~ treatment + age + education, data = data)
  print(summary(fit))
  print(confint(fit))
" 2>&1

# Frequency tables (aggregated)
Rscript -e "
  data <- read.csv('[FILE]')
  print(table(data\$group_variable))
  print(prop.table(table(data\$group_variable)))
"
```

**In Local Mode:** Claude Code never reads the raw data file. It only sees the model output. The researcher verifies the output looks correct before passing it along.

---

## Save Output

### Version collision avoidance (MANDATORY — run BEFORE every Write tool call)

Run this Bash block before each Write call. It prints `SAVE_PATH=...` — use that exact path in the Write tool's `file_path` parameter. **Re-run this version check with the appropriate BASE for each output file.**

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# For safety log: BASE="${OUTPUT_ROOT}/[slug]/logs/scholar-safety-log"
# For protocol report: BASE="${OUTPUT_ROOT}/[slug]/protocols/scholar-safety-protocol-[slug]-[YYYY-MM-DD]"
BASE="${OUTPUT_ROOT}/[slug]/protocols/scholar-safety-protocol-[slug]-[YYYY-MM-DD]"

if [ -f "${BASE}.md" ]; then
  V=2
  while [ -f "${BASE}-v${V}.md" ]; do
    V=$((V + 1))
  done
  BASE="${BASE}-v${V}"
fi

echo "SAVE_PATH=${BASE}.md"
echo "BASE=${BASE}"
```

**Use the printed `SAVE_PATH` as the `file_path` in the Write tool call.** Do NOT hardcode the path.

After any scan or gate operation, use the Write tool to append to the safety log:

**Log file:** `output/[slug]/logs/scholar-safety-log.md`

**Report file (MODE 3 only):** `output/[slug]/protocols/scholar-safety-protocol-[slug]-[YYYY-MM-DD].md`

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-safety"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Output Files
[list each output file path as a bullet]

## Summary
- **Steps completed**: [N completed]/[N total]
- **Files produced**: [count]
- **Errors**: [count, or 0]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
echo "Process log saved to $LOG_FILE"
```

---

## Safety Quick-Reference Card

```
╔════════════════════════════════════════════════════════════╗
║  SCHOLAR SAFETY — QUICK REFERENCE                         ║
╠════════════════════════════════════════════════════════════╣
║  WHAT GETS TRANSMITTED when Claude Code reads a file:     ║
║    → The ENTIRE file content goes to Anthropic's API      ║
║    → Applies to: Read tool, Bash cat/head/tail            ║
║    → Does NOT apply to: Bash grep returning only counts   ║
╠════════════════════════════════════════════════════════════╣
║  HIGH RISK — always use [B] or [C]:                       ║
║    • SSNs, emails, phone numbers, home addresses          ║
║    • Health/clinical data, mental health records          ║
║    • Immigration status, arrest records, legal status     ║
║    • NHANES restricted, PSID, NLSY, Census RDC            ║
║    • Interview transcripts with participant info          ║
╠════════════════════════════════════════════════════════════╣
║  ALWAYS SAFE to share with Claude:                        ║
║    • Regression coefficients, SEs, p-values               ║
║    • Aggregate statistics (means, SDs, N by group)        ║
║    • Code scripts (without embedded data values)          ║
║    • Manuscript text (no participant quotes)              ║
║    • Public dataset variable lists (NHANES public)        ║
╠════════════════════════════════════════════════════════════╣
║  INVOKE: /scholar-safety scan [filepath]                  ║
║          /scholar-safety gate [describe operation]        ║
║          /scholar-safety protocol [project name]          ║
╚════════════════════════════════════════════════════════════╝
```

---

## Quality Checklist

- [ ] All data files mentioned in arguments scanned before any Read operation
- [ ] Sensitivity scan used Bash grep/awk only — no file content in Claude context during scan
- [ ] Risk level correctly classified using decision matrix
- [ ] HIGH risk: full warning displayed; user selection obtained before any file read
- [ ] MEDIUM risk: advisory displayed; user confirmation obtained
- [ ] LOW risk: green light logged; operation proceeds
- [ ] Anonymization script generated (if user selected [B]) and tested
- [ ] Local-mode Bash scripts generated (if user selected [C])
- [ ] Gate outcome written to `output/[slug]/logs/scholar-safety-log.md`
- [ ] Safety gate result logged
- [ ] Safety protocol saved to `output/[slug]/protocols/` (MODE 3 only)
- [ ] AI use log entry added for journal disclosure
