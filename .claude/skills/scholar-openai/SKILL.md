---
name: scholar-openai
description: >
  External review via OpenAI Codex CLI agents. Spawns multiple parallel Codex agents
  (codex exec) to independently review analysis scripts, verify manuscript-to-output
  consistency, check statistical logic, and audit reproducibility. Each agent writes
  a review report to disk. Claude reads all reports, synthesizes a consolidated review
  with severity-ranked issues, and presents a fix checklist. Read-only — diagnoses but
  does not modify any project files.
tools: Read, Bash, Write, Glob, Grep, Agent
argument-hint: "[code|stats|logic|full|custom] [manuscript-path] [scripts-dir], e.g., 'full output/drafts/full-paper-2026-03-10.md'"
user-invocable: true
---

# Scholar OpenAI: External Multi-Agent Review via Codex CLI

You are a review orchestrator that spawns independent OpenAI Codex agents to review a social science research project. Each Codex agent runs non-interactively (`codex exec`), reads project files in a sandbox, and writes a structured review to disk. You then synthesize their reports into a consolidated review.

## ABSOLUTE RULES

1. **Never modify the manuscript, scripts, or analysis outputs** — this skill is read-only. It diagnoses but does not fix.
2. **Every flagged issue must cite exact locations** — file path, line number, manuscript quote, or table cell.
3. **Severity levels are binding** — CRITICAL must be fixed; WARNINGS are advisory.
4. **Zero tolerance for false confidence** — if Codex output is unclear or a finding cannot be verified, report as UNVERIFIABLE.
5. **All Codex agents run in parallel** — spawned simultaneously as background processes.

---

## Arguments

The user has provided: `$ARGUMENTS`

Parse:
- **Mode**: `code` | `stats` | `logic` | `full` (default) | `custom`
- **Manuscript path**: path to manuscript file (.md, .tex, .docx) — auto-detect if not specified
- **Scripts directory**: path to analysis scripts — default: `output/[slug]/scripts/` or `output/scripts/`
- **Custom prompts**: for `custom` mode, user provides review instructions

If mode is ambiguous, default to `full`.

---

## ABSOLUTE RULE — NEVER Fabricate Citations

> **ZERO TOLERANCE FOR CITATION FABRICATION.** Any reference cited in Codex-agent review reports, remediation notes, or synthesis produced by this skill MUST be verified against Tier 0 (knowledge graph), Tier 1 (local library: Zotero/Mendeley/BibTeX/EndNote), or Tier 2 (CrossRef / Semantic Scholar / OpenAlex). Unverified references MUST be flagged `[CITATION NEEDED: describe required evidence]`. NEVER invent author names, titles, years, volumes, pages, or DOIs; NEVER cite packages or methods papers from Claude's training data without verifying they exist in the declared form.

Load the full verification protocol on first use:

```bash
cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/_shared/citation-verification-protocol.md"
```

---

## Dispatch Table

| Keywords in `$ARGUMENTS`                      | Route to                                          |
|-----------------------------------------------|---------------------------------------------------|
| `code`, `scripts`, `review code`              | → Code Review Agents (A1 + A2 + A3)               |
| `stats`, `numbers`, `consistency`, `verify`   | → Stats Consistency Agent (A4)                     |
| `logic`, `interpretation`, `prose`            | → Logic & Interpretation Agent (A5)                |
| `full`, `all`                                 | → All 5 Agents                                     |
| `custom`                                      | → User-defined prompt(s) sent to Codex             |
| (no mode keyword)                             | → All 5 Agents (full)                              |

---

## Step 0: Setup & Prerequisite Check

### 0a. Verify Codex CLI

```bash
if ! command -v codex &>/dev/null; then
  echo "ERROR: codex CLI not found. Install with: npm install -g @anthropic-ai/codex (or see https://github.com/openai/codex)"
  exit 1
fi
echo "codex version: $(codex --version 2>&1)"
```

If Codex is not installed, halt and instruct the user.

### 0b. Locate Project Artifacts

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/reviews/codex" "${OUTPUT_ROOT}/logs"
```

1. **Manuscript**: Check user-provided path. If not provided, auto-detect:
   ```
   Glob: output/manuscript/full-paper-*.md → most recent
   Glob: output/drafts/draft-*.md → most recent
   ```
2. **Analysis scripts**: `Glob: output/**/scripts/*.{R,py,do,stata}` or user-provided path
3. **Raw table outputs**: `Glob: output/tables/*` — .html, .tex, .csv, .docx
4. **Raw figure outputs**: `Glob: output/figures/*` — .pdf, .png, .svg
5. **EDA outputs**: `Glob: output/eda/*` (if exists)

If no scripts AND no manuscript found, halt with error.

### 0c. Determine Working Directory for Codex

Codex needs a `-C` directory. Use the project root (where the `output/` folder lives):

```bash
CODEX_WORKDIR="$(pwd)"
echo "Codex working directory: $CODEX_WORKDIR"
```

### 0d. Process Logging (REQUIRED)

Initialize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-openai"
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

---

## Step 1: Build Review Prompts

For each agent, construct a detailed prompt that includes:
- The file paths it should read (relative to project root)
- What to look for (specific checklist)
- Output format (structured markdown with severity tags)

### Agent Definitions

Load agent-specific prompts from reference file:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}"
cat "$SKILL_DIR/.claude/skills/scholar-openai/references/codex-review-prompts.md"
```

The 5 agents and their roles:

**A1 — Code Correctness** (mode: `code`, `full`)
- Review all R/Python/Stata scripts for logical errors, wrong variable references, off-by-one errors, silent coercion bugs, incorrect function arguments, data manipulation mistakes
- Output: severity-ranked issue list with file:line references

**A2 — Code Robustness** (mode: `code`, `full`)
- Check for fragile patterns, missing error handling, hardcoded assumptions, edge cases, silent failures, non-portable paths
- Output: severity-ranked issue list with file:line references

**A3 — Reproducibility** (mode: `code`, `full`)
- Evaluate whether scripts form a complete, self-contained pipeline: dependency management, execution order, environment specification, documentation
- Output: reproducibility checklist with PASS/FAIL per item

**A4 — Stats Consistency** (mode: `stats`, `full`)
- Compare every number in the manuscript tables against raw analysis outputs (CSVs, HTML tables, console output). Flag transcription errors, rounding mistakes, dropped rows/columns
- Output: table-by-table comparison with cell-level match/mismatch

**A5 — Logic & Interpretation** (mode: `logic`, `full`)
- Compare statistical claims in prose against manuscript tables/figures. Flag misquoted numbers, wrong references, significance misstatements, causal overreach, hypothesis adjudication errors
- Output: claim-by-claim verification with PASS/FAIL/UNVERIFIABLE

---

## Step 2: Spawn Codex Agents in Parallel

For each selected agent, launch `codex exec` as a **background process**. Each agent writes its review to a separate output file.

**CRITICAL**: All agents MUST be spawned in a single bash block so they run truly in parallel.

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
REVIEW_DIR="${OUTPUT_ROOT}/reviews/codex"
CODEX_WORKDIR="$(pwd)"
mkdir -p "$REVIEW_DIR"

# E1 hard control "B": on a LOCAL_MODE project, point codex at a DATA-FREE
# MIRROR instead of the live tree. `-s read-only` / `disk-full-read-access` do
# NOT confine reads — codex can `cat` any absolute path — so the mirror, not the
# sandbox flag, is what keeps restricted microdata off the cloud reviewer. The
# scripts read data by RELATIVE path, so from cwd=mirror `read_dta("data/raw/..")`
# resolves to <mirror>/data/.. which does not exist → codex reports the data
# UNVERIFIABLE while still reviewing the scripts. Helper:
# scripts/phases/build-codex-mirror.sh (grep-guards absolute data paths → RED;
# rsync-excludes data/ + microdata extensions). On CLEARED projects reading data
# is not a violation, so the mirror is LOCAL_MODE-only (avoids the copy cost).
# LOCAL_MODE detection fails TOWARD building the mirror (a false negative would
# silently let codex read restricted data); robust detection (subtree find +
# ancestor walk-up over sidecar AND project-state.md) lives in
# local-mode-detect.sh, with an inline bare-LOCAL_MODE grep as fallback.
_DETECT="${SCHOLAR_SKILL_DIR:-.}/scripts/phases/local-mode-detect.sh"
_LOCAL_MODE=0
if [ -f "$_DETECT" ]; then
  bash "$_DETECT" "${PROJ:-.}" "$(pwd)" && _LOCAL_MODE=1 || _LOCAL_MODE=0
else
  for _f in "${PROJ:-.}/.claude/safety-status.json" "$(pwd)/.claude/safety-status.json" \
            "${PROJ:-.}/logs/project-state.md" "$(pwd)/logs/project-state.md"; do
    [ -f "$_f" ] && grep -qi 'LOCAL_MODE' "$_f" 2>/dev/null && { _LOCAL_MODE=1; break; }
  done; unset _f
fi
if [ "$_LOCAL_MODE" = "1" ]; then
  _MK="${SCHOLAR_SKILL_DIR:-.}/scripts/phases/build-codex-mirror.sh"
  if [ -x "$_MK" ] || [ -f "$_MK" ]; then
    _MERRF="$(mktemp)"
    _MOUT="$(bash "$_MK" "$(pwd)" "${PROJ:-.}" 2>"$_MERRF")"; _MRC=$?
    if [ "$_MRC" -eq 0 ]; then
      CODEX_WORKDIR="$(printf '%s' "$_MOUT" | sed -n 's/^MIRROR=//p' | tail -1)"
      # CRIT guard: an empty/invalid mirror path would make `codex exec -C ""`
      # fall back to the LIVE tree → data exposure. Fail CLOSED on a LOCAL_MODE
      # project — never the live tree.
      if [ -z "$CODEX_WORKDIR" ] || [ ! -d "$CODEX_WORKDIR" ]; then
        echo "HALT: mirror build reported success but path is empty/invalid ('$CODEX_WORKDIR')." >&2
        echo "      Refusing to dispatch codex at the live tree on a LOCAL_MODE project." >&2
        rm -f "$_MERRF"; exit 1
      fi
      echo "LOCAL_MODE: codex -C → data-free mirror: $CODEX_WORKDIR"
    elif [ "$_MRC" -eq 1 ]; then
      echo "HALT: build-codex-mirror.sh RED — a script hard-codes an ABSOLUTE data path." >&2
      cat "$_MERRF" >&2
      echo "Refusing to dispatch codex (restricted data could reach the cloud reviewer)." >&2
      echo "Rewrite the path as RELATIVE (file.path(DATA,\"x.dta\")) then re-run." >&2
      rm -f "$_MERRF"; exit 1
    else
      # Fail-closed: a mirror that could not be built (rc=2: rsync missing, etc.)
      # MUST NOT degrade to dispatching codex at the live tree — codex runs with
      # disk-full-read and would expose data/raw to the cloud reviewer. The
      # prompt-prohibition prefix alone is not an enforced control.
      echo "HALT: data-free mirror unavailable ($(tail -1 "$_MERRF" 2>/dev/null)) on a LOCAL_MODE" >&2
      echo "      project — refusing to dispatch codex at the live tree (would expose data/raw to a" >&2
      echo "      disk-full-read cloud agent). Install rsync / fix the mirror builder and re-run, or" >&2
      echo "      run the review against a non-LOCAL_MODE copy." >&2
      rm -f "$_MERRF"; exit 1
    fi
    rm -f "$_MERRF"
  else
    # Fail-closed: no mirror builder on a LOCAL_MODE project → do NOT fall back
    # to the live tree. The prompt prohibition is a belt, not a wall.
    echo "HALT: build-codex-mirror.sh not found at $_MK on a LOCAL_MODE project — refusing to" >&2
    echo "      dispatch codex at the live tree (data exposure). Restore the mirror builder and re-run." >&2
    exit 1
  fi
fi

# Timestamp for this review run
RUN_TS=$(date +%Y-%m-%d-%H%M%S)

# --- Build file lists for Codex prompts ---
SCRIPT_FILES=$(find "${OUTPUT_ROOT}" -type f \( -name "*.R" -o -name "*.py" -o -name "*.do" \) 2>/dev/null | head -20 | tr '\n' ', ')
TABLE_FILES=$(find "${OUTPUT_ROOT}" -type f \( -name "*.html" -o -name "*.csv" -o -name "*.tex" \) -path "*/tables/*" 2>/dev/null | head -20 | tr '\n' ', ')
MANUSCRIPT_FILE="[MANUSCRIPT_PATH]"  # <-- replace with detected path from Step 0b

echo "Spawning Codex review agents at $(date +%H:%M:%S)..."
echo "Scripts: $SCRIPT_FILES"
echo "Tables: $TABLE_FILES"
echo "Manuscript: $MANUSCRIPT_FILE"
```

**Data Access Prohibition (E1) — MANDATORY prompt prefix.** `codex exec` is spawned with `sandbox_permissions=["disk-full-read-access"]`, so it *can* read the dataset; `-s read-only` / the sandbox flag restrict writes, not read scope (codex can `cat` any absolute path). Two controls apply:

1. **Belt — prompt prohibition.** Before every prompt you send, **PREPEND the verbatim "DATA ACCESS PROHIBITION (BINDING)" block from the top of `references/codex-review-prompts.md`** so the Codex agent is instructed never to open `data/`, `data/raw/`, or any row-level data file and to report **UNVERIFIABLE** rather than read the data.
2. **Suspenders — data-free mirror.** On a LOCAL_MODE project the Step 2 block above builds a mirror with no `data/` and no microdata files and points `codex exec -C` at it (`$CODEX_WORKDIR`), so a relative data read cannot resolve. This is the *enforced* control (the prompt prohibition alone is not). The mirror builder also HALTs the dispatch if a script hard-codes an absolute data path. On a LOCAL_MODE project, **do not dispatch a codex review without both.**

Then spawn each agent. Example for Agent A1 (Code Correctness):

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
REVIEW_DIR="${OUTPUT_ROOT}/reviews/codex"
RUN_TS="[TIMESTAMP]"  # re-derive or hardcode from Step 2 above
# CODEX_WORKDIR is set by the Step 2 block (the data-free mirror on LOCAL_MODE
# projects). Fail closed rather than let `-C` default to the live tree.
: "${CODEX_WORKDIR:?run the Step 2 LOCAL_MODE/mirror block first — do not point codex -C at the live tree}"

codex exec \
  -C "$CODEX_WORKDIR" \
  -c 'sandbox_permissions=["disk-full-read-access"]' \
  -o "${REVIEW_DIR}/A1-code-correctness-${RUN_TS}.md" \
  "You are a code review agent for a social science research project.

Review ALL analysis scripts in this project for:
1. Logical errors and incorrect function usage
2. Wrong variable references or off-by-one errors
3. Silent coercion bugs and type mismatches
4. Data manipulation mistakes (wrong merges, filters, aggregations)
5. Incorrect statistical function arguments

Scripts to review: Look in the output/ directory for .R and .py files.

FORMAT your output as:

# Code Correctness Review

## CRITICAL Issues
- [CRIT-CODE-NNN] file:line — description — severity justification

## WARNING Issues
- [WARN-CODE-NNN] file:line — description

## INFO
- [INFO-CODE-NNN] file:line — description

## Summary
- Files reviewed: N
- Critical: N | Warnings: N | Info: N
" &

echo "A1 (Code Correctness) spawned — PID: $!"
```

**Spawn ALL selected agents using the same pattern**, each as a background process (`&`), each with `-o` pointing to a unique output file:

- `A1-code-correctness-${RUN_TS}.md`
- `A2-code-robustness-${RUN_TS}.md`
- `A3-reproducibility-${RUN_TS}.md`
- `A4-stats-consistency-${RUN_TS}.md`
- `A5-logic-interpretation-${RUN_TS}.md`

After spawning all, wait:

```bash
echo "Waiting for all Codex agents to complete..."
wait
echo "All agents finished at $(date +%H:%M:%S)"
```

**Timeout**: Set a timeout of 300 seconds (5 minutes) per agent. If an agent hangs, kill it and note the failure.

```bash
# Alternative: use timeout wrapper
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
REVIEW_DIR="${OUTPUT_ROOT}/reviews/codex"
RUN_TS="[TIMESTAMP]"
: "${CODEX_WORKDIR:?run the Step 2 LOCAL_MODE/mirror block first — do not point codex -C at the live tree}"

# Spawn with timeout (5 min each)
timeout 300 codex exec \
  -C "$CODEX_WORKDIR" \
  -c 'sandbox_permissions=["disk-full-read-access"]' \
  -o "${REVIEW_DIR}/A1-code-correctness-${RUN_TS}.md" \
  "[PROMPT]" &
PID_A1=$!

# ... repeat for A2-A5 ...

# Wait for all with status check
for PID in $PID_A1 $PID_A2 $PID_A3 $PID_A4 $PID_A5; do
  wait $PID
  STATUS=$?
  if [ $STATUS -eq 124 ]; then
    echo "WARNING: Agent PID $PID timed out"
  elif [ $STATUS -ne 0 ]; then
    echo "WARNING: Agent PID $PID exited with status $STATUS"
  fi
done
echo "All agents complete at $(date +%H:%M:%S)"
```

---

## Step 3: Collect & Read Agent Reports

After all agents finish, read every report file:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
REVIEW_DIR="${OUTPUT_ROOT}/reviews/codex"
echo "=== Review files ==="
ls -la "${REVIEW_DIR}/"*.md 2>/dev/null
```

Read each report using the Read tool. If a report file is empty or missing, note the agent as FAILED in the consolidated report.

---

## Step 4: Synthesize Consolidated Review

Combine all Codex agent findings into a single **CONSOLIDATED CODEX REVIEW**.

### 4a. Triage and Deduplicate

1. **Merge all issues** from all agents into a single list
2. **Deduplicate**: If multiple agents flag the same issue, merge into one entry
3. **Mark cross-agent agreement**: Issues flagged by 2+ agents get a **cross** marker (highest confidence)
4. **Organize by domain**: Code → Stats → Logic

### 4b. Severity Classification

| Severity | Definition | Action |
|----------|-----------|--------|
| **CRITICAL** | Wrong results, data loss, incorrect statistics, number mismatch, causal overreach | MUST fix |
| **WARNING** | Fragile code, rounding imprecision, missing docs, minor interpretation stretch | SHOULD fix |
| **INFO** | Style, naming conventions, optional improvements | MAY fix |

### 4c. Build Fix Checklist

```
FIX CHECKLIST (from Codex Review)
==================================

CODE ISSUES:
[ ] [CRIT-CODE-001] scripts/analysis.R:45 — wrong merge key produces duplicate rows (A1)
[ ] [WARN-CODE-001] scripts/models.R:112 — hardcoded path will break on other machines (A2)

STATS ISSUES:
[ ] [CRIT-STAT-001] Table 2, Row 3, Col 2: manuscript shows 0.32, raw output is 0.23 (A4)

LOGIC ISSUES:
[ ] [CRIT-LOG-001] Results para 4: claims p<0.01 but Table 3 shows p=0.06 (A5)

REPRODUCIBILITY:
[ ] [WARN-REPR-001] No renv.lock or requirements.txt — dependencies undocumented (A3)
```

### 4d. Review Scorecard

```
CODEX REVIEW SCORECARD
=======================

| Domain                | Agent | Issues | Critical | Warnings | Score      |
|-----------------------|-------|--------|----------|----------|------------|
| Code Correctness      | A1    | [N]    | [N]      | [N]      | [PASS/FAIL] |
| Code Robustness       | A2    | [N]    | [N]      | [N]      | [PASS/FAIL] |
| Reproducibility       | A3    | [N]    | [N]      | [N]      | [PASS/FAIL] |
| Stats Consistency     | A4    | [N]    | [N]      | [N]      | [PASS/FAIL] |
| Logic & Interpretation| A5    | [N]    | [N]      | [N]      | [PASS/FAIL] |

OVERALL
| Total Issues | Critical | Warnings | Cross-Agent | Agents Succeeded | Score      |
|-------------|----------|----------|-------------|------------------|------------|
| [N]         | [N]      | [N]      | [N]         | [N]/5            | [PASS/FAIL] |

VERDICT: [CLEAN / REVISIONS NEEDED / MAJOR ISSUES]
```

Verdict rules:
- **CLEAN**: 0 CRITICAL, ≤3 WARNINGS, all agents succeeded
- **REVISIONS NEEDED**: 1–3 CRITICAL or >3 WARNINGS
- **MAJOR ISSUES**: >3 CRITICAL or any cross-agent CRITICAL

---

## Step 5: Present Results to User

Display:

1. **Review Scorecard** (headline)
2. **Fix Checklist** (actionable items)
3. **Cross-Agent Agreement items** (highest confidence findings)
4. **Per-agent summaries** (collapsible detail)

This is a read-only review. Ask: "Would you like me to save the full review report? Any issues you'd like me to address with `/scholar-write` or by editing the scripts directly?"

---

## Step 6: Save Output

### Version Collision Avoidance (MANDATORY)

Before EVERY Write tool call, run:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
OUTDIR="${OUTPUT_ROOT}/reviews/codex"
STEM="codex-review-consolidated-$(date +%Y-%m-%d)"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

Use the printed `SAVE_PATH` as the file path.

### 6a. Save Consolidated Report

Write the full consolidated report containing:
1. Review Scorecard
2. Fix Checklist
3. Cross-Agent Agreement section
4. Per-agent detailed reports (A1–A5)
5. Agent metadata (codex version, model, timestamps, success/failure)

### 6b. Close Process Log

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-openai"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Output Files
- Consolidated report: ${OUTPUT_ROOT}/reviews/codex/codex-review-consolidated-${LOG_DATE}.md
- Individual agent reports: ${OUTPUT_ROOT}/reviews/codex/A[1-5]-*-${LOG_DATE}*.md

## Summary
- **Steps completed**: 6/6
- **Agents spawned**: [N]
- **Agents succeeded**: [N]
- **Critical issues**: [N]
- **Warnings**: [N]
- **Verdict**: [CLEAN/REVISIONS/MAJOR ISSUES]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
```

---

## Quality Checklist (Self-Audit Before Completion)

- [ ] Codex CLI was verified as installed before spawning
- [ ] DATA ACCESS PROHIBITION block was prepended to every prompt
- [ ] On a LOCAL_MODE project: `codex exec -C` pointed at the data-free mirror (`$CODEX_WORKDIR`), NOT the live tree — and the dispatch HALTed if the mirror could not be built (never fell back to the live tree)
- [ ] All agents ran with `sandbox_permissions=["disk-full-read-access"]` (note: this flag does not confine reads; the LOCAL_MODE mirror is the enforced control)
- [ ] Each agent's output file was checked for existence and non-emptiness
- [ ] Failed agents are clearly marked in the consolidated report
- [ ] Every CRITICAL issue has exact location (file:line or manuscript quote)
- [ ] Deduplication complete — no issue appears twice
- [ ] Cross-agent markers applied to issues flagged by 2+ agents
- [ ] Fix checklist entries are actionable
- [ ] Verdict follows the rules in Step 4d
- [ ] Process log is complete

---

## Integration with Other Skills

| Skill | When to use scholar-openai | Recommended mode | Integration point |
|-------|---------------------------|-----------------|-------------------|
| **scholar-verify** | Complementary — scholar-verify uses Claude agents; scholar-openai uses Codex agents. Run both for maximum coverage | `full` | Run scholar-openai after scholar-verify; cross-reference findings |
| **scholar-respond** | Step 3c (after R&R verification gate) | `code` / `stats` / `full` | Optional; triggered by CRITICAL issues in Step 3b |
| **scholar-analyze** | After scripts are written, before manuscript drafting | `code` | Standalone use |
| **scholar-compute** | After computational analysis scripts produced | `code` | Standalone use |
| **scholar-replication** | After replication package is built, before archiving | `code` | Standalone use |

---

## Notes on Codex Configuration

- **Model**: Codex defaults to its configured model. Override with `-c model="o3"` or `-c model="o4-mini"` if needed.
- **Sandbox**: Agents need read access to project files. Use `-c 'sandbox_permissions=["disk-full-read-access"]'` to grant this.
- **Timeout**: Default 5 minutes per agent. Increase for large projects with many scripts.
- **Cost**: Each agent is an independent API call. `full` mode spawns 5 agents. Monitor usage.
