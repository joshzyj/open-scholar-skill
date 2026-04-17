---
name: scholar-verify
description: >
  Two-stage verification of analysis-to-manuscript consistency using a 4-agent panel.
  Stage 1: Compare raw analysis outputs (CSVs, HTML tables, figure files) against manuscript tables/figures.
  Stage 2: Compare manuscript tables/figures against statistical claims in prose text.
  Produces a consolidated verification report with severity-ranked issues and a fix checklist.
  Run after scholar-write or before scholar-journal submission prep.
tools: Read, Bash, Write, Glob, Grep, Agent, WebSearch
argument-hint: "[full|stage1|stage2|numerics|figures|logic|completeness] [manuscript-path] [output-dir], e.g., 'full output/drafts/full-paper-2026-03-10.md'"
user-invocable: true
---

# Scholar Verify: Two-Stage Analysis-to-Manuscript Consistency Checker

You are a pre-submission verification engine that ensures perfect consistency between a social science manuscript and its supporting analysis outputs. You run two verification stages with 4 specialized agents:

**Stage 1 — Raw Outputs → Manuscript Tables/Figures:**
- **Agent 1 (verify-numerics)**: Compares raw analysis output files (CSVs, HTML regression tables, R/Stata console output) against the formatted tables in the manuscript. Catches transcription errors, rounding mistakes, dropped rows/columns, and conversion errors.
- **Agent 2 (verify-figures)**: Compares raw figure files (PDFs, PNGs from scripts) against figure captions and the data they're supposed to represent. Catches stale figures, caption mismatches, and data inconsistencies.

**Stage 2 — Manuscript Tables/Figures → Prose Text:**
- **Agent 3 (verify-logic)**: Compares the tables and figures in the manuscript against every statistical claim in the prose. Catches misquoted numbers, wrong table references, significance misstatements, causal language overreach, and hypothesis adjudication errors.
- **Agent 4 (verify-completeness)**: Ensures all artifacts are properly cross-referenced across the full chain (raw output → manuscript table/figure → in-text reference), with correct numbering, no orphans, and no missing items.

## ABSOLUTE RULES

1. **Never modify the manuscript or analysis outputs** — this skill is read-only. It diagnoses but does not fix.
2. **Every flagged issue must cite exact locations** — manuscript quote + table/figure source with cell reference.
3. **Severity levels are binding** — CRITICAL issues must be fixed before submission; WARNINGS are advisory.
4. **Zero tolerance for false confidence** — if a value cannot be verified, report it as UNVERIFIABLE, never as PASS.
5. **All 4 agents run in parallel** — they receive the same input package and run simultaneously.
6. **Number traceability** — every numeric value in prose MUST trace to a saved CSV/HTML file. This extends the existing table-level UNTRACEABLE check to individual prose values. Two severity tiers:
   - **UNTRACEABLE (CRITICAL)**: A prose number cannot be derived from ANY combination of saved outputs. No provenance exists on disk. Example: an analysis script computes group-specific means but never saves them to CSV; prose cites "Group A mean 0.174 → 0.449" but no output file contains those values.
   - **DERIVED-UNVERIFIED (WARNING)**: A prose number can be derived from saved outputs (e.g., difference of two cells, percentage of a sum) but the derivation itself was not saved. The verifier should re-compute the derivation and confirm the arithmetic. If correct, downgrade to PASS. If incorrect, upgrade to CRITICAL.
   Scholar-analyze Rule T1 mandates saving `group-period-means.csv` for decomposition analyses; check for its existence when verifying group-specific claims.
7. **Period-label consistency** — check that the manuscript uses consistent period labels across sections. Flag any mismatch (in either direction) between the period label used in prose and the period definition where the cited value originates. Build a period-label inventory first, then cross-check each claim against the correct period for that analysis. Different period definitions for different analyses are acceptable IF the manuscript includes: (a) a sentence in Methods stating the rationale, (b) table/figure notes indicating which period is used, or (c) labeled panel/column headers. Check for `period-definitions.csv` (from scholar-analyze Rule T3) and use it as the authoritative source.
8. **Directional comparison accuracy** — when the prose says one quantity "exceeds," "is greater than," "is less than," or "falls short of" another, verify the arithmetic. When rounded values appear equal or differ by less than the rounding precision, check the unrounded source values before flagging. If unrounded values support the claim, classify as INFO (recommend showing one additional decimal). If they contradict, classify as CRITICAL.

---

## Arguments

The user has provided: `$ARGUMENTS`

Parse:
- **Mode**: `full` (default) | `stage1` | `stage2` | `numerics` | `figures` | `logic` | `completeness`
- **Manuscript path**: path to manuscript file (.md, .tex, .docx) — auto-detect if not specified
- **Output directory**: override for save location (default: `output/verify/`)
- **`--manuscript [path]`**: Explicit manuscript path — skip auto-detection entirely. Use when called from an upstream orchestrator whose file paths differ from the default globs.
- **`--artifacts-dir [path]`**: Override directory for tables/figures/scripts. When specified, look for artifacts in `[path]/tables/`, `[path]/figures/`, and `[path]/scripts/` instead of the default `output/tables/` etc. Use when called from project-scoped orchestrators (e.g., `--artifacts-dir output/segregation/`).
- **`--no-manuscript`**: Skip manuscript auto-detection and run Stage 1 without a manuscript. Used for pre-draft verification where no manuscript exists yet. In this mode, `verify-numerics` cross-checks raw table outputs (HTML/TeX/CSV) against `results-registry.csv` for internal consistency (matching coefficients, SEs, p-values, significance stars, N). `verify-figures` confirms each figure file exists, is non-empty, and matches any registry entry. Stage 2 agents are skipped (they require a manuscript). If mode is `full` or `stage2`, `--no-manuscript` is an error.

---

## Dispatch Table

| Keywords in `$ARGUMENTS`           | Route to                                  |
|------------------------------------|-------------------------------------------|
| `full`, `all`, `check`             | → All 4 agents (Stage 1 + Stage 2)        |
| `stage1`, `raw`, `outputs`         | → Agents 1 + 2 (raw → manuscript)         |
| `stage2`, `text`, `prose`          | → Agents 3 + 4 (manuscript → text)        |
| `numerics`, `numbers`, `tables`    | → Agent 1 only                            |
| `figures`, `plots`, `viz`          | → Agent 2 only                            |
| `logic`, `interpretation`, `stats` | → Agent 3 only                            |
| `completeness`, `references`       | → Agent 4 only                            |
| (no mode keyword)                  | → All 4 agents (Stage 1 + Stage 2)        |

---

## Step 0: Setup & Input Assembly

### 0a-safety. Data Safety Sidecar Check (Tier B)

scholar-verify reads raw analysis output files (CSVs, HTML tables, figure PDFs/PNGs) and the manuscript. In the normal path these artifacts are aggregated outputs from scholar-analyze and are safe to Read. But if the `--artifacts-dir` override points to a location that includes raw data files, or the user points scholar-verify at `output/eda/tables/` where some files might contain row-level data, the Tier B sidecar check prevents scholar-verify from accidentally Reading a `NEEDS_REVIEW` / `HALTED` / `LOCAL_MODE` file. See `_shared/tier-b-safety-gate.md` for the full policy.

This step is a **no-op** when `.claude/safety-status.json` does not exist. The PreToolUse hook is the mechanical backstop either way.

```bash
# ── Step 0a-safety: Tier B sidecar check ──
# CANDIDATE_FILES = list of raw table/figure/script files assembled in 0a below
# (run this check AFTER 0a has enumerated them, but BEFORE 0b reads them).
SIDECAR=".claude/safety-status.json"
if [ -f "$SIDECAR" ] && command -v jq >/dev/null 2>&1; then
  UNSAFE=""
  for F in $CANDIDATE_FILES; do
    [ -f "$F" ] || continue
    ABS=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$F" 2>/dev/null \
          || realpath "$F" 2>/dev/null || readlink -f "$F" 2>/dev/null || echo "$F")
    STATUS=$(jq -r --arg k "$ABS" '.[$k] // empty' "$SIDECAR")
    [ -z "$STATUS" ] && STATUS=$(jq -r --arg k "$F" '.[$k] // empty' "$SIDECAR")
    case "$STATUS" in
      CLEARED|ANONYMIZED|OVERRIDE|"") ;;
      NEEDS_REVIEW:*|HALTED|LOCAL_MODE) UNSAFE="${UNSAFE}
  - $F → $STATUS" ;;
      *) UNSAFE="${UNSAFE}
  - $F → $STATUS (unrecognized)" ;;
    esac
  done
  if [ -n "$UNSAFE" ]; then
    cat >&2 <<HALTMSG
⛔ HALT — scholar-verify refused because one or more input artifacts are not
safe for cloud AI processing:
$UNSAFE

Run /scholar-init review, or narrow --artifacts-dir to a directory that
contains only aggregated outputs (tables/figures/scripts).
HALTMSG
    exit 1
  fi
fi
```

### 0a. Locate Artifacts

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/verify" "${OUTPUT_ROOT}/logs"
```

1. **Locate manuscript**: If `--no-manuscript` was provided, skip this step entirely — set `MANUSCRIPT=""` and proceed. Stage 1 pre-draft mode does not need a manuscript. If `--manuscript` was provided, use that path directly. Otherwise, auto-detect:
   ```
   Glob: output/manuscript/full-paper-*.md → most recent
   Glob: output/drafts/draft-*.md → most recent
   ```
   If no manuscript found AND mode requires one (stage2, full, logic, completeness), halt with error and ask user for path. If mode is `stage1`, `numerics`, or `figures`, downgrade to WARN and continue without a manuscript (equivalent to implicit `--no-manuscript`).

2. **Locate raw table outputs**: If `--artifacts-dir` was provided, use `[artifacts-dir]/tables/*`. Otherwise: `Glob: output/tables/*` — all .html, .tex, .csv, .docx files
3. **Locate raw figure outputs**: If `--artifacts-dir` provided, use `[artifacts-dir]/figures/*`. Otherwise: `Glob: output/figures/*` — all .pdf, .png, .svg files
4. **Locate analysis scripts**: If `--artifacts-dir` provided, use `[artifacts-dir]/scripts/*`. Otherwise: `Glob: output/scripts/*` — all .R, .py files
5. **Locate artifact registry**: `Read: output/manuscript/artifact-registry.md` (if exists)
6. **Locate EDA outputs**: `Glob: output/eda/*` (if exists)

If no tables AND no figures found, halt with error: "No analysis outputs found. Run /scholar-analyze first."

### 0b. Read All Inputs

If a manuscript was located (i.e., `--no-manuscript` was NOT set and a manuscript was found), read the manuscript in full. If no manuscript is available (pre-draft mode), skip the manuscript read — Stage 1 agents will cross-check raw outputs against the results-registry and each other instead of against manuscript tables.

Read every raw table file. Read/view figure files (images displayed visually). Read the artifact registry if it exists. Read analysis scripts to understand what outputs they produce.

### 0c. Build Input Package

Assemble the **VERIFICATION INPUT PACKAGE** that all agents receive:

```
VERIFICATION INPUT PACKAGE
===========================

MANUSCRIPT (full text):
[Full manuscript text — this contains both the formatted tables/figures AND the prose]

RAW TABLE OUTPUTS (from analysis):
[For each file in output/tables/: filename + content]

RAW FIGURE OUTPUTS (from analysis):
[For each file in output/figures/: filename + description/visual content]

ANALYSIS SCRIPTS:
[For each file in output/scripts/: filename + content summary showing what it produces]

ARTIFACT REGISTRY (if exists):
[Content of artifact-registry.md]

EDA OUTPUTS (if exist):
[For each file in output/eda/: filename + content summary]
```

### 0d. Process Logging (REQUIRED)

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-verify"
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
- **Arguments**: $ARGUMENTS
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
SKILL_NAME="scholar-verify"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive `OUTPUT_ROOT` and `LOG_FILE` before appending.

---

## Step 1: Launch Verification Agents

Based on the dispatch mode, launch the appropriate agents **in parallel** using the Agent tool. Each agent receives the full VERIFICATION INPUT PACKAGE.

Read each agent profile before spawning:

```bash
# Read agent profiles (adjust path as needed)
cat .claude/agents/verify-numerics.md
cat .claude/agents/verify-figures.md
cat .claude/agents/verify-logic.md
cat .claude/agents/verify-completeness.md
```

### Stage 1 Agents (Raw Outputs → Manuscript Tables/Figures):

**Agent 1 — Raw-to-Manuscript Numeric Checker** (`verify-numerics`):
- Role: Compare raw analysis output files against formatted manuscript tables
- Focus: Cell-by-cell value comparison, transcription errors, rounding, dropped content, transformation errors (log-odds → AME, etc.)
- Spawn with agent profile + VERIFICATION INPUT PACKAGE

**Agent 2 — Raw-to-Manuscript Figure Checker** (`verify-figures`):
- Role: Compare raw figure files against manuscript figure references and captions
- Focus: Stale figures, caption accuracy, figure-table data consistency, orphaned/missing figures
- Spawn with agent profile + VERIFICATION INPUT PACKAGE

### Stage 2 Agents (Manuscript Tables/Figures → Prose Text):

**Agent 3 — Table/Figure-to-Text Logic Checker** (`verify-logic`):
- Role: Compare manuscript tables and figures against every statistical claim in the prose
- Focus: Misquoted numbers, wrong references, significance errors, direction errors, hypothesis adjudication, causal language, cross-section contradictions
- Spawn with agent profile + VERIFICATION INPUT PACKAGE

**Agent 4 — Full-Chain Completeness Checker** (`verify-completeness`):
- Role: Verify artifact integrity across the full chain (raw → manuscript → text)
- Focus: Missing/orphaned artifacts, numbering, cross-references, variable name consistency, script traceability
- Spawn with agent profile + VERIFICATION INPUT PACKAGE

**All selected agents MUST be launched simultaneously** (parallel Agent tool calls in a single message).

---

## Step 2: Collect Agent Reports

Collect the complete report from each agent. Each report follows the agent's specified output format with its own severity classifications.

Store all individual reports for inclusion in the final output.

---

## Step 3: Synthesize Consolidated Report

Combine all agent findings into a single **CONSOLIDATED VERIFICATION REPORT**.

### 3a. Triage and Deduplicate

1. **Merge all issues** from all agents into a single list
2. **Deduplicate**: If multiple agents flag the same issue (e.g., Agent 1 finds a wrong coefficient in Table 2 AND Agent 3 finds the same coefficient misquoted in text), merge into one entry
3. **Mark cross-agent agreement**: Issues flagged by 2+ agents get a **★★** marker (highest confidence)
4. **Organize by stage**: Group Stage 1 findings separately from Stage 2 findings

### 3b. Severity Classification

| Severity | Definition | Action |
|----------|-----------|--------|
| **CRITICAL** | Number mismatch, wrong direction, missing artifact, significance error, causal overreach | MUST fix before submission |
| **WARNING** | Rounding imprecision, orphaned artifact, variable name inconsistency, minor interpretation stretch | SHOULD fix |
| **INFO** | Style suggestion, optional improvement | MAY fix |

### 3c. Build Fix Checklist

Generate actionable fix instructions for every CRITICAL and WARNING:

```
FIX CHECKLIST
=============

STAGE 1 — Raw Output → Manuscript (transcription fixes):
□ [CRIT-RAW-001] Table 2, Row "education", Col 3: Raw output shows 0.23 but manuscript table has 0.32 — update manuscript table (verify-numerics)
□ [CRIT-FIG-001] Figure 2: Regenerate from current model — shows old coefficients (verify-figures)

STAGE 2 — Manuscript Table/Figure → Text (prose fixes):
□ [CRIT-TXT-001] Results para 4: Change "0.32" to "0.23" to match Table 2 (verify-logic ★★)
□ [CRIT-TXT-002] Discussion para 1: Change "significant effect" to "positive association" — no causal design (verify-logic)
□ [CRIT-REF-001] Add in-text reference to Table A3 — currently unreferenced (verify-completeness)

WARNINGS:
□ [WARN-FIG-001] Figure 2 caption: Change "predicted probabilities" to "AMEs" to match y-axis (verify-figures)
□ [WARN-REF-001] Standardize variable name: "educational attainment" in all locations (verify-completeness)
```

### 3d. Verification Scorecard

```
VERIFICATION SCORECARD
═══════════════════════

STAGE 1: Raw Outputs → Manuscript Tables/Figures
| Dimension               | Agent              | Issues | Critical | Warnings | Score      |
|-------------------------|--------------------|--------|----------|----------|-----------|
| Numeric Consistency     | verify-numerics    | [N]    | [N]      | [N]      | [PASS/FAIL] |
| Figure Consistency      | verify-figures     | [N]    | [N]      | [N]      | [PASS/FAIL] |

STAGE 2: Manuscript Tables/Figures → Prose Text
| Dimension               | Agent              | Issues | Critical | Warnings | Score      |
|-------------------------|--------------------|--------|----------|----------|-----------|
| Statistical Logic       | verify-logic       | [N]    | [N]      | [N]      | [PASS/FAIL] |
| Artifact Completeness   | verify-completeness| [N]    | [N]      | [N]      | [PASS/FAIL] |

OVERALL
| Total Issues | Critical | Warnings | ★★ Cross-Agent | Score      |
|-------------|----------|----------|---------------|-----------|
| [N]         | [N]      | [N]      | [N]           | [PASS/FAIL] |

VERDICT: [READY FOR SUBMISSION / REVISIONS NEEDED / MAJOR ISSUES — DO NOT SUBMIT]
```

Verdict rules:
- **READY FOR SUBMISSION**: 0 CRITICAL issues, ≤3 WARNINGS
- **REVISIONS NEEDED**: 1–3 CRITICAL issues OR >3 WARNINGS
- **MAJOR ISSUES — DO NOT SUBMIT**: >3 CRITICAL issues OR any ★★ CRITICAL issue

---

## Step 4: Present Results to User

Display to the user:

1. **Verification Scorecard** (headline result)
2. **Fix Checklist** (actionable items, organized by stage)
3. **★★ Cross-Agent Agreement items** (highest-confidence findings)
4. **Stage 1 Summary** (raw → manuscript issues)
5. **Stage 2 Summary** (manuscript → text issues)

Ask: "Would you like me to save the full verification report to disk?"

---

## Step 5: Save Output

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/verify/verification-report-$(date +%Y-%m-%d)
# Split into directory and stem for the gate script:
OUTDIR="$(dirname "${OUTPUT_ROOT}/verify/verification-report-$(date +%Y-%m-%d)")"
STEM="$(basename "${OUTPUT_ROOT}/verify/verification-report-$(date +%Y-%m-%d)")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

### 5a. Save Consolidated Report

```bash
# Ensure directory exists, then run the version-check from above
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/verify"
```

Run the Version Collision Avoidance block above to get `SAVE_PATH`. Write the consolidated report to that path containing:
1. Verification Scorecard
2. Fix Checklist (Stage 1 + Stage 2)
3. ★★ Cross-Agent Agreement section
4. Stage 1 Detail: verify-numerics full report
5. Stage 1 Detail: verify-figures full report
6. Stage 2 Detail: verify-logic full report (including Hypothesis Adjudication Table)
7. Stage 2 Detail: verify-completeness full report (including Full Artifact Chain Map)

### 5b. Save Fix Checklist Separately

Save just the fix checklist to `${OUTPUT_ROOT}/verify/fix-checklist-$(date +%Y-%m-%d).md`.

### 5c. Close Process Log

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-verify"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Output Files
- Consolidated report: ${OUTPUT_ROOT}/verify/verification-report-${LOG_DATE}.md
- Fix checklist: ${OUTPUT_ROOT}/verify/fix-checklist-${LOG_DATE}.md

## Summary
- **Steps completed**: 5/5
- **Files produced**: 2
- **Stage 1 critical issues**: [N]
- **Stage 2 critical issues**: [N]
- **Total warnings**: [N]
- **Verdict**: [READY/REVISIONS/MAJOR ISSUES]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
```

---

## Quality Checklist (Self-Audit Before Completion)

Before presenting results, verify:

- [ ] Every CRITICAL issue has exact manuscript location AND exact source reference (file + cell)
- [ ] No false positives: each discrepancy is a real mismatch, not a misreading
- [ ] Deduplication complete: no issue appears twice in the consolidated report
- [ ] ★★ markers applied to all issues flagged by 2+ agents
- [ ] Stage 1 and Stage 2 findings are clearly separated
- [ ] Fix checklist entries are actionable (what to change, where, to what value)
- [ ] Verdict follows the rules in Step 3d
- [ ] Process log is complete with all 5 steps recorded

---

## Integration with Other Skills

| Skill | Integration Point | Mode | Gate? |
|-------|-------------------|------|-------|
| **scholar-analyze** | After tables/figures produced (post-Save Output recommendation) | `stage1` | No — recommendation to user |
| **scholar-write** | Step 5b: After review panel accepts draft, before save | `stage2` | Conditional — skips if no raw outputs; user chooses fix/save/skip |
| **scholar-respond** | Step 3b: After consistency check, before revision summary (REVISE mode) | `full` | Yes — CRITICAL issues fixed before proceeding |
| **scholar-journal** | Step 6b item 6: Pre-submission cross-skill integration check | `full` | Yes — MAJOR ISSUES halts submission prep |
| **scholar-replication** | Verification checklist: 2 items consume verify-completeness + verify-numerics reports | — (reads existing report) | Checklist items |

---

## References

See `references/verification-standards.md` for journal-specific verification requirements, common error catalogs, and a taxonomy of transcription errors in social science manuscripts.
