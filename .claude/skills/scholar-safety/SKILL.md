---
name: scholar-safety
description: Real-time data privacy and leakage protection layer for AI-assisted research. Before any file is read by Claude Code and transmitted to Anthropic's API, proactively scans it locally for sensitive content (PII, HIPAA, IRB-protected, restricted licensed data) using local Bash pattern matching — so the sensitive data itself never enters the AI context during the scan. Issues tiered warnings (green/yellow/red), requests explicit user permission before transmitting any sensitive data, and offers safe alternatives: anonymization scripts, local-mode analysis (bash-only, no data in context), data minimization, or full halt. Four modes: SCAN (audit a file using only local grep/awk — sensitive data stays local), GATE (intercept a proposed operation and ask permission before execution), PROTOCOL (generate a project-level data safety protocol), STATUS (safety status log). Works alongside scholar-eda, scholar-analyze, scholar-compute, and scholar-data to protect any data-touching operation.
tools: Bash, Read, Write
argument-hint: "[scan|gate|protocol|status|level] [file path / operation description / level name] [optional: data type, project name, journal target]"
user-invocable: true
---

# Scholar Safety — Data Privacy Protection Layer

You are the data safety guardian for AI-assisted research. Your job is to intercept potentially risky operations **before** any sensitive data reaches Anthropic's servers, warn the researcher with precise details, and give them real options — not just vague caution.

**Core principle:** Use local Bash commands (grep, awk, wc, file) to detect sensitivity patterns BEFORE reading any file into Claude's context. This way the detection itself does not expose the data to the AI API. Only aggregated counts and pattern types (never actual values) are reported.

---

## Arguments

The user has provided: `$ARGUMENTS`

Parse to determine:
- **MODE**: `scan` | `gate` | `protocol` | `status` | `level`
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
| `level` + `standard`/`strict`/`lockdown` | **MODE 5: Set Safety Level** |
| Any mode that finds HIGH risk | **Halt → present options → wait for user selection** |

---

## Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/protocols"
```

**Process Logging (REQUIRED) — Reasoning · Action · Observation trace:**

This skill emits an append-only RAO trace at `${OUTPUT_ROOT}/logs/trace-scholar-safety-<date>.ndjson` — the source of truth. The human-readable `process-log-scholar-safety-<date>.md` is *rendered* from it. Full protocol + privacy rule: `_shared/process-logger.md`.

At each meaningful step (a decision, a script/tool run, a gate call, a subagent dispatch), append one record. `emit-trace.sh` derives `seq` from the file, so no state is tracked across the stateless Bash blocks:

```bash
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/emit-trace.sh" --skill scholar-safety --step "<label>" \
  --reasoning "<the WHY — stated rationale, 1–2 lines>" \
  --action "<the WHAT — tool/script/gate call + key args>" \
  --observation "<the RESULT — verdict/metric/count/error/file ref>" --status ok    # ok|fail|skipped
```

At the end (Save Output), render the human-readable log and self-check:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/render-trace.sh" "${OUTPUT_ROOT}/logs/trace-scholar-safety-$(date +%Y-%m-%d).ndjson"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/trace-coverage-check.sh" "${OUTPUT_ROOT}" --skill scholar-safety
```

Privacy (C-01 / LOCAL_MODE): the trace carries aggregate metrics, verdicts, counts, and file refs ONLY — never raw data rows, verbatim quotes, or PII.

---

## CRITICAL OPERATING RULE

> **Never read a flagged file's content into context until the user explicitly grants permission.**
>
> The scan steps below use `Bash` with grep/awk/wc to detect patterns and return COUNTS only. The actual sensitive values stay on the local filesystem. `Read` is used on a flagged file ONLY after the user selects **[Y] PROCEED** (cloud analysis approved) or **[D] OVERRIDE** (confirmed not sensitive). **[C] LOCAL MODE is the opposite of permission to Read** — it means Bash-only analysis with NO raw data in context, so a `[C]` selection must NEVER trigger a `Read`.

---

## MODE 1: File Sensitivity Scan

*Scan a file or directory for sensitive data using local pattern matching. No file content enters Claude's context during the scan — only match counts and pattern categories.*

### Step 1.0 — Quick Gate Check (REQUIRED)

Before the detailed scan, run the gate script for a fast RED/YELLOW/GREEN triage:

```bash
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/safety-scan.sh" "[FILE_PATH]"
```

- **GREEN (exit 0)**: No sensitive patterns detected — proceed to Step 1.1 for detailed scan or skip to MODE 2/3.
- **YELLOW (exit 2)**: Review needed — proceed to detailed scan below.
- **RED (exit 1)**: Sensitive data detected — proceed to detailed scan to get per-category counts, then apply Step 1.4 options.

> **Risk is a FLOOR, never lowered by the detailed scan.** `safety-scan.sh` fails closed (exit 1 = RED on a missing target; exit 2 = YELLOW on an unreadable one — both non-GREEN, so neither can silently clear). The detailed scan below may ADD specificity and RAISE the level, but it MUST NOT downgrade a Step 1.0 RED/YELLOW to a lower level. An empty per-category count set is only meaningful if the detailed scan actually read the file — see the fail-closed preamble in Step 1.3, which exits with RISK 🔴 HIGH when the target cannot be read. A "0 across the board" result from an unreadable/nonexistent/binary target is a SCAN FAILURE, not a 🟢 LOW.

### Step 1.1 — File Inventory

```bash
# Get file type, size, and encoding — no content read
FILE="$TARGET_PATH"
# FAIL-CLOSED FIRST: a missing/unreadable target must HALT here, before any
# counting step (1.2+) can emit empty counts that read as "nothing found".
# (Same rule as the Step 1.3 preamble; directories use the branch below.)
if [ ! -e "$FILE" ] || [ ! -r "$FILE" ]; then
  echo "SCAN-ERROR: unscannable target: $FILE"
  echo "RISK: 🔴 HIGH — treat as restricted; do NOT report LOW/CLEARED."
  exit 1
fi
file "$FILE"
wc -l "$FILE" 2>/dev/null || echo "binary or unreadable"
ls -lh "$FILE"
```

If directory (use `-L` to follow symlinks — a bare `find -type f` skips symlinked
data files entirely, since a symlink's own type is `l`, not `f`; a directory of
symlinked `.dta` files would enumerate as empty/near-empty and the scan would
silently cover nothing):
```bash
find -L "$DIR_PATH" -type f | head -50
find -L "$DIR_PATH" -type f | wc -l
```

### Step 1.2 — Detect Data Type (Quantitative vs. Qualitative)

Before scanning, determine whether the file is structured/quantitative data or qualitative text data. This determines which anonymization procedure to offer in Step 1.4.

```bash
FILE="$TARGET_PATH"
EXT="${FILE##*.}"
IS_QUAL="false"

# Qualitative file indicators (by extension)
case "$EXT" in
  txt|rtf|docx|doc|odt|md|tex) IS_QUAL="likely" ;;
  csv|tsv|dta|rds|xlsx|xls|sav|parquet|feather|db|json) IS_QUAL="false" ;;
  *) IS_QUAL="unknown" ;;
esac

# Qualitative content indicators (by content patterns — counts only, no data exposed)
if [ "$IS_QUAL" != "false" ]; then
  QUAL_MARKERS=$(grep -cEi '\b(interviewer|interviewee|respondent|Q:|A:|INTERVIEWER:|PARTICIPANT:|field.?note|memo|transcript|focus.?group|ethnograph|informant)\b' "$FILE" 2>/dev/null)
  NARRATIVE_LINES=$(awk 'length > 200' "$FILE" 2>/dev/null | wc -l | tr -d ' ')
  echo "Qualitative content markers: $QUAL_MARKERS"
  echo "Long narrative lines (>200 chars): $NARRATIVE_LINES"
  if [ "${QUAL_MARKERS:-0}" -gt 5 ] || [ "${NARRATIVE_LINES:-0}" -gt 20 ]; then
    IS_QUAL="true"
  fi
fi

# CSV/TSV can also contain qualitative data (open-ended survey responses)
if [ "$IS_QUAL" = "false" ] && [[ "$EXT" =~ ^(csv|tsv)$ ]]; then
  OPENENDED_MARKERS=$(grep -cEi '\b(open.?ended|verbatim|comment|narrative|response.?text|free.?text|transcript)\b' "$FILE" 2>/dev/null)
  if [ "${OPENENDED_MARKERS:-0}" -gt 3 ]; then
    IS_QUAL="true"
    echo "Note: Structured file with qualitative content (open-ended responses detected)"
  fi
fi

echo "Data type classification: IS_QUAL=$IS_QUAL"
```

### Step 1.3 — Local Sensitivity Pattern Scan

Run ALL of the following grep scans using Bash. Each returns only a COUNT. No actual values are returned.

```bash
FILE="$TARGET_PATH"

# === FAIL-CLOSED PREAMBLE (2026-07-03) ===
# The counters below are plaintext greps. If the target cannot be read, every count
# is 0 — which must NEVER be mistaken for "no sensitive data → LOW". A scan that
# cannot see its target ESCALATES.
if [ ! -e "$FILE" ]; then
  echo "SCAN-ERROR: target does not exist: $FILE"
  echo "RISK: 🔴 HIGH — unscannable path; treat as restricted until a real, readable path is supplied. Do NOT report LOW/CLEARED."
  exit 1
fi
if [ ! -r "$FILE" ] || [ -d "$FILE" ]; then
  echo "SCAN-ERROR: target not a readable file: $FILE"
  echo "RISK: 🔴 HIGH — unscannable; treat as restricted."
  exit 1
fi
# Opaque/binary/compressed formats (.dta .sav .rds .parquet .xlsx .zip …) cannot be
# grep-scanned for PII; the counters would read 0 and mislabel them LOW. Establish a
# floor of 🟡 NEEDS_REVIEW for any non-plaintext target — resolved by extension /
# provenance / DUA, never by a 🟢 LOW inferred from empty counts.
FILE_KIND="$(file -b "$FILE" 2>/dev/null)"
BINARY_FLOOR="no"
case "$FILE_KIND" in
  *[Tt]ext*|*ASCII*|*UTF-8*|*JSON*|*CSV*|*empty*) : ;;
  *) BINARY_FLOOR="yes"
     echo "NOTE: non-plaintext format ($FILE_KIND) — plaintext PII counters cannot see inside it."
     echo "RISK FLOOR: 🟡 NEEDS_REVIEW (never 🟢 LOW on counts alone; classify by extension/provenance)." ;;
esac

# === DIRECT IDENTIFIERS ===
echo "=== SENSITIVITY SCAN: $FILE ==="
echo ""

# Social Security Numbers (XXX-XX-XXXX or XXXXXXXXX)
SSN_COUNT=$(grep -cEi '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b|\bSSN\b|\bsocial.security' "$FILE" 2>/dev/null)
echo "SSN patterns: $SSN_COUNT matches"

# Names (common first/last name columns)
NAME_COUNT=$(grep -cEi '\b(first.?name|last.?name|full.?name|respondent.?name|participant.?name)\b' "$FILE" 2>/dev/null)
echo "Name fields: $NAME_COUNT matches"

# Email addresses
EMAIL_COUNT=$(grep -cEi '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$FILE" 2>/dev/null)
echo "Email addresses: $EMAIL_COUNT matches"

# Phone numbers
PHONE_COUNT=$(grep -cEi '\b(\+?1[-.\s]?)?(\([0-9]{3}\)|[0-9]{3})[-.\s][0-9]{3}[-.\s][0-9]{4}\b' "$FILE" 2>/dev/null)
echo "Phone numbers: $PHONE_COUNT matches"

# Street addresses
ADDR_COUNT=$(grep -cEi '\b[0-9]{1,5}\s+[a-zA-Z]+(St|Street|Ave|Avenue|Blvd|Boulevard|Dr|Drive|Rd|Road|Ln|Lane|Way|Court|Ct)\b' "$FILE" 2>/dev/null)
echo "Street addresses: $ADDR_COUNT matches"

# ZIP codes (5-digit, possibly with +4)
ZIP_COUNT=$(grep -cEi '\b[0-9]{5}(-[0-9]{4})?\b' "$FILE" 2>/dev/null)
echo "ZIP code patterns: $ZIP_COUNT matches (may include false positives)"

# IP addresses
IP_COUNT=$(grep -cEi '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$FILE" 2>/dev/null)
echo "IP addresses: $IP_COUNT matches"

# === HEALTH / HIPAA DATA ===
echo ""
HEALTH_COUNT=$(grep -cEi '\b(diagnosis|ICD.?[0-9]|medical.?record|patient|PHI|HIPAA|health.?condition|medication|prescription|treatment|clinical)\b' "$FILE" 2>/dev/null)
echo "Health/HIPAA keywords: $HEALTH_COUNT matches"

# Mental health terms
MENTAL_COUNT=$(grep -cEi '\b(depression|anxiety|suicid|mental.?health|psychiatric|PTSD|bipolar|schizophrenia|self.?harm|substance.?use)\b' "$FILE" 2>/dev/null)
echo "Mental health terms: $MENTAL_COUNT matches"

# === SENSITIVE LEGAL / IMMIGRATION STATUS ===
echo ""
LEGAL_COUNT=$(grep -cEi '\b(undocumented|illegal.?immigrant|immigration.?status|visa.?status|DACA|asylum|deportation|criminal.?record|arrest|conviction|incarcerated)\b' "$FILE" 2>/dev/null)
echo "Legal/immigration status: $LEGAL_COUNT matches"

# === FINANCIAL DATA ===
FINANCIAL_COUNT=$(grep -cEi '\b(account.?number|routing.?number|credit.?card|bank.?account|income|earnings|salary|tax.?return|W-?2)\b' "$FILE" 2>/dev/null)
echo "Financial data keywords: $FINANCIAL_COUNT matches"

# === RESTRICTED / LICENSED DATA MARKERS ===
echo ""
RESTRICTED_COUNT=$(grep -cEi '\b(NHANES|PSID|NLSY|IPUMS|Census.?RDC|restricted.?use|data.?use.?agreement|DUA|confidential|not.?for.?distribution)\b' "$FILE" 2>/dev/null)
echo "Restricted/licensed data markers: $RESTRICTED_COUNT matches"

# International / in-house restricted panels (backs the "International restricted data
# markers" row in the Step 1.4 matrix — previously that row had NO detector). Note:
# binary survey formats (.dta/.sav/.rds) rarely carry these strings, so the binary
# floor above is the real backstop for those; this catches plaintext/codebook mentions.
# SHARE / HILDA / Add Health are matched CASE-SENSITIVELY in a second pass:
# under -i they collide with ordinary prose and names ("income share", "add
# health insurance", "Hilda").
INTL_COUNT=$(grep -cEi '\b(UK ?Biobank|ALSPAC|NHS ?Digital|GSOEP|SOEP|EU-?SILC|CFPS|CHARLS|CGSS|CLHLS|IHDS|JGSS|JLPS|Understanding ?Society|KLoSA)\b' "$FILE" 2>/dev/null)
INTL_CS_COUNT=$(grep -cE '\b(SHARE|HILDA|Add ?Health)\b' "$FILE" 2>/dev/null)
INTL_COUNT=$(( ${INTL_COUNT:-0} + ${INTL_CS_COUNT:-0} ))
echo "International/in-house restricted dataset markers: $INTL_COUNT matches"

# === IRB / PARTICIPANT MARKERS ===
IRB_COUNT=$(grep -cEi '\b(participant|respondent|interview|subject.?ID|case.?ID|record.?ID|consent)\b' "$FILE" 2>/dev/null)
echo "IRB participant markers: $IRB_COUNT matches"

# === GEOGRAPHIC GRANULARITY ===
GEO_COUNT=$(grep -cEi '\b(latitude|longitude|lat|lon|geocode|census.?tract|block.?group|exact.?address)\b' "$FILE" 2>/dev/null)
echo "Fine-grained geographic data: $GEO_COUNT matches"

echo ""
echo "=== SCAN COMPLETE ==="
```

### Step 1.4 — Risk Classification

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
| `BINARY_FLOOR=yes` (non-plaintext target — counts are blind) | 🟡 MEDIUM (NEEDS_REVIEW) — never LOW |
| No sensitive patterns **AND** `BINARY_FLOOR=no` (a real plaintext scan ran) | 🟢 LOW |

The `International restricted data markers` row is backed by `INTL_COUNT` (Step 1.3); the `🟢 LOW` row requires that the fail-closed preamble did NOT exit and the target was plaintext — a 0-count from an unreadable/binary target is a scan failure (🔴/🟡), not LOW.

### Step 1.5 — Safety Alert Output

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

For each file path identified, run the MODE 1 sensitivity scan (Steps 1.1–1.4) on that file.

### Step 2.3 — Gate decision

| Risk level | Gate action |
|-----------|------------|
| 🔴 HIGH | HALT with HIGH risk alert. Do not execute the operation until user selects A, B, C, or D. |
| 🟡 MEDIUM | PAUSE with MEDIUM advisory. Wait for user selection before proceeding. |
| 🟢 LOW | Log green light. Execute the operation. |

### Step 2.4 — Log the gate outcome

```bash
# Canonical log location is PROJECT-scoped (${PROJ}/logs/) — the same file
# MODE 4 status reads and the Save Output section documents (output/[slug]/logs/).
# (Was ${OUTPUT_ROOT}/logs/, which diverged from the slug-scoped path.)
. "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"
LOGFILE="${PROJ}/logs/scholar-safety-log.md"
mkdir -p "${PROJ}/logs"
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

> **Template content below** — the `## 1. Data Inventory` through `## 6. AI Use Log` headings inside the fenced code block are section headings for the *generated protocol document*, not subsections of this SKILL.md. Substitute project-specific values; do not emit the literal bracketed placeholders.

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

### Step 4.1 — Read and format the safety log

```bash
# Same project-scoped location Step 2.4 writes (${PROJ}/logs/).
. "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"
if [ -f "${PROJ}/logs/scholar-safety-log.md" ]; then
  cat "${PROJ}/logs/scholar-safety-log.md"
else
  echo "No safety log found at ${PROJ}/logs/. Run scholar-safety scan [file] to begin."
fi
```

Format the log as a readable summary table before returning it to the user. If the log is empty or missing, tell the user how to populate it (`/scholar-safety scan <file>`) rather than returning a silent empty result.

---

## MODE 5: Set Safety Level

*Choose how strongly the data-safety enforcement layer protects this project. The level is stored per-project as the `_safety_level` key in `.claude/safety-status.json` and is consulted by the PostToolUse output redactor via `resolve_safety_level` (`scripts/gates/sidecar-schema.sh`). The PreToolUse guard does NOT read the level — its standard-tier gates run unconditionally at every level; the level only switches the extra strict/lockdown layers on.*

### The three levels — honest guarantees

| Level | What it enforces | Stops accidental/cooperative leakage | Stops a determined/adversarial agent |
|-------|------------------|:---:|:---:|
| **standard** (default) | PreToolUse Bash dump-verb gate (`cat`/`head`/`sed`/`awk`/`grep`-rows/`sqlite3`/python·R row dumps on a sensitive path) + Edit/Write sidecar-tamper guard | ✅ | ❌ — it is a denylist; other interpreters, encodings, and variable-assembled paths bypass it |
| **strict** | standard **+** a PostToolUse hook that redacts PII / bulk-row Bash **output** before it reaches context (any verb). Activation preconditions: the hook must be registered in `~/.claude/settings.json` (installed by `setup.sh` — installs predating the redactor need a re-run; Step 5.2 verifies) AND the sidecar must hold ≥1 `LOCAL_MODE`/`HALTED`/`NEEDS_REVIEW` entry — an all-`CLEARED`/`ANONYMIZED` project gets no redaction (nothing restricted to protect) | ✅ stronger | ❌ — evadable by encoding (`base64`/`gzip`/`hex`) and by `cp`-to-benign-path → Read |
| **lockdown** | strict **+** an OS sandbox read-deny on the data dirs, auto-generated per-project by `generate-lockdown-config.sh` (Claude Code: `sandbox.filesystem.denyRead` w/ `allowUnsandboxedCommands:false`; Codex: `[permissions]` `"data"="deny"`) so subprocess reads of data are blocked at the kernel (Seatbelt/Landlock) | ✅ | ✅ — a real boundary (the only one) |

Standard and strict are **cooperative-agent guardrails, not walls** — say so when you set them. Only lockdown is a containment boundary, and it imposes real friction (data analysis must run through the sanctioned runner / an explicit unsandboxed escalation). Lockdown is **auto-generated** for the detected host (Claude Code and/or Codex) by Step 5.1b — verified against Claude Code (`cat data/raw/*` → `Operation not permitted`, 0 leak) and Codex (`blocked by the active permission profile`).

### Step 5.1 — Write the level

```bash
LVL="$(printf '%s' "$ARGUMENTS" | tr 'A-Z' 'a-z' | grep -oE '\b(standard|strict|lockdown)\b' | head -1)"
[ -n "$LVL" ] || { echo "Usage: /scholar-safety level <standard|strict|lockdown>"; exit 0; }
SIDE=".claude/safety-status.json"
[ -f "$SIDE" ] || { mkdir -p .claude; echo '{}' > "$SIDE"; }
TMP="$(mktemp)"
if jq --arg l "$LVL" '. + {"_safety_level":$l}' "$SIDE" > "$TMP" 2>/dev/null; then
  mv "$TMP" "$SIDE"
  echo "Safety level set to '$LVL' in $SIDE"
else
  rm -f "$TMP"; echo "ERROR: could not update $SIDE (is it valid JSON? is jq installed?)"
fi
```

### Step 5.1b — Generate the OS sandbox config (lockdown only)

When `LVL=lockdown`, generate the host-appropriate OS-enforced read-deny config. **This is what makes lockdown a real wall** rather than just a recorded intent — it writes a kernel-enforced deny on the data dirs (Claude Code: `sandbox.filesystem.denyRead` in `<proj>/.claude/settings.json`; Codex: a `[permissions]` `deny` profile in `<proj>/.codex/config.toml`). Verified against Claude Code (Seatbelt) and Codex.

```bash
if [ "$LVL" = "lockdown" ]; then
  # Default is the HARD wall (allowUnsandboxedCommands:false). Pass
  # --allow-escalation ONLY if the user must run LOCAL_MODE analysis while locked.
  # --allow-escalation weakens the OS sandbox (the real wall). Require the LITERAL flag
  # token as a whitespace-delimited word — NEVER infer it from prose like "escalate",
  # which also matches "no escalation" / "don't allow-unsandboxed" (the old grep did,
  # silently weakening lockdown exactly when the user asked for the strongest setting).
  ESC=""
  case " $ARGUMENTS " in
    *" --allow-escalation "*|*" --allow-unsandboxed "*) ESC="--allow-escalation" ;;
  esac
  bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/generate-lockdown-config.sh" "$(pwd)" --host auto $ESC
fi
```

Surface the generator's output verbatim — it prints the denied paths, the restart (Claude) / trust (Codex) reminder, and the **LOCAL_MODE-analysis caveat** (denyRead blocks the sanctioned `Rscript` too, so run analysis before locking or use `--allow-escalation`).

### Step 5.2 — Report honestly

When the level is `strict` or `lockdown`, verify the PostToolUse redactor is actually registered before telling the user they have it:

```bash
if grep -q "posttooluse-output-guard.sh" "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "PostToolUse redactor: registered"
else
  echo "WARNING: PostToolUse redactor NOT registered in ~/.claude/settings.json —"
  echo "the strict tier's output redaction is inert. Re-run: bash setup.sh"
fi
```

- Confirm the level written and **what it actually enforces today** (use the table above — standard/strict are not walls, and strict's redactor only acts when the activation preconditions in the table hold).
- **Hook config is snapshotted at session start** — tell the user the change takes effect after they **restart Claude Code** (Codex: after they **trust the project**).
- For **lockdown**: Step 5.1b has now written the OS-sandbox config into the **project** (`<proj>/.claude/settings.json` and/or `<proj>/.codex/config.toml`) — it is no longer a manual step. Remind the user it activates on restart (Claude) / trust (Codex), and that it blocks ALL reads of `data/` including LOCAL_MODE analysis scripts (run analysis first, or re-run with `--allow-escalation`). If the generator printed a WARN (foreign `[permissions]` / non-JSON settings), relay it verbatim.
- Global default: a machine-wide default can be set via the `SCHOLAR_SAFETY_LEVEL` env var; the per-project `_safety_level` key overrides it.

---

## Anonymization Helper

When the user selects **[B] ANONYMIZE**, determine the data type from Step 1.2 and route to the appropriate procedure:

### Route A: Quantitative / Structured Data (IS_QUAL = "false")

Generate a ready-to-run R script:

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

### Route B: Qualitative / Text Data (IS_QUAL = "true" or "likely")

**Qualitative data requires a different anonymization approach** — text data (interview transcripts, field notes, open-ended responses, focus group recordings) contains identifiers embedded in narrative prose, not in structured columns. Dropping columns does not work; you need pseudonym replacement + residual scrubbing.

**Preferred: Use Presidio-based anonymizer** when installed (NER-based person/location/institution detection):

```bash
SCHOLAR_SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}"
ANON_SCRIPT="$SCHOLAR_SKILL_DIR/scripts/gates/anonymize-presidio.py"
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
if [ -f "$ANON_SCRIPT" ] && python3 -c "import presidio_analyzer, presidio_anonymizer" 2>/dev/null; then
  python3 "$ANON_SCRIPT" scan "$DATA_FILE"                                    # Step A: detect PII
  python3 "$ANON_SCRIPT" keygen "$DATA_FILE" --out "${OUTPUT_ROOT}/qual/anonymized"  # Step B: generate key
  # USER REVIEWS KEY HERE — then:
  python3 "$ANON_SCRIPT" anonymize "$DATA_FILE" --out "${OUTPUT_ROOT}/qual/anonymized"  # Step C: anonymize
  python3 "$ANON_SCRIPT" verify "${OUTPUT_ROOT}/qual/anonymized/ANON_$(basename "$DATA_FILE")"  # Step D: verify
else
  echo "Presidio not installed — using regex fallback (see scholar-qual for procedure)"
  echo "Install: pip install presidio-analyzer presidio-anonymizer spacy && python3 -m spacy download en_core_web_lg"
fi
```

**Fallback: Execute the `scholar-qual` MANDATORY PRE-STEP: Data Anonymization Gate.** Read and follow the full procedure from `scholar-qual`:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills"
sed -n '/^## MANDATORY PRE-STEP: Data Anonymization Gate/,/^## WORKFLOW 0:/p' "$SKILL_DIR/scholar-qual/SKILL.md" | sed '$d'
```

The procedure has 5 steps — all run locally, no data sent to AI:

1. **Step A — PII scan**: Presidio NER (preferred) or local grep for names, emails, phones, addresses, institutions, DOBs in the text files (returns counts/detections only, no data sent to AI)
2. **Step B — Pseudonym mapping table**: Auto-generated by Presidio `keygen` (or manually created) as `pseudonym-key-DO-NOT-SHARE.csv` mapping real names → P01, institutions → ORG01, locations → LOC01, etc. User MUST review and edit before anonymizing
3. **Step C — Automated replacement**: Presidio `anonymize` (or Python script) applies the mapping to produce `ANON_*` copies, plus residual scrubbing of emails/phones/SSNs
4. **Step D — Verification**: Presidio `verify` (or re-run PII scan) on anonymized files to confirm nothing slipped through
5. **Step E — Path swap**: All subsequent workflows use `ANON_*` files only; originals are never read by Claude Code

**Critical rules for qualitative anonymization:**
- The pseudonym key file must NEVER be read by Claude Code or any AI service
- Add it to `.gitignore` immediately
- Anonymize not just participant names but also **third-party names** (advisors, family members, colleagues mentioned in interviews), **institutions** (schools, churches, clinics), **geographic identifiers** (neighborhoods, street names, small towns), and **unique life events** that could re-identify participants
- For **sociolinguistic data**: preserve linguistic features (dialect markers, code-switching, prosodic notation) while removing identifiers — do NOT normalize speech to standard English during anonymization, as the linguistic variation is the data
- For **CSV/TSV with open-ended columns**: apply the Python replacement script to the open-ended text columns only; apply Route A (R script) to the structured columns

After anonymization, re-run MODE 1 scan on the anonymized files before proceeding.

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

After any scan or gate operation, use the Write tool to append to the safety log:

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [slug] and [YYYY-MM-DD] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/protocols/scholar-safety-protocol-[slug]-[YYYY-MM-DD]
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/protocols/scholar-safety-protocol-[slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/protocols/scholar-safety-protocol-[slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
BASE=$(bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM" | awk -F= '/^BASE=/{print $2; exit}')
mkdir -p "$(dirname "$BASE")"
echo "SAVE_PATH=${BASE}.md"
echo "BASE=${BASE}"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

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
- [ ] Data type correctly classified (quantitative vs. qualitative) in Step 1.2
- [ ] Anonymization script generated (if user selected [B]) — Route A (R script) for quantitative data, Route B (scholar-qual pseudonym procedure) for qualitative/text data
- [ ] For qualitative data: pseudonym key generated, replacements applied, residual PII scrubbed, verification scan passed, `ANON_*` files used for all subsequent operations
- [ ] Sociolinguistic data: linguistic features (dialect, code-switching, prosody) preserved during anonymization — only identifiers removed, not linguistic variation
- [ ] Local-mode Bash scripts generated (if user selected [C])
- [ ] Gate outcome written to `output/[slug]/logs/scholar-safety-log.md`
- [ ] Safety protocol saved to `output/[slug]/protocols/` (MODE 3 only)
- [ ] AI use log entry added for journal disclosure
