---
name: scholar-brainstorm
description: "Generate research questions from existing materials — codebooks, survey questionnaires, datasets, or published papers/abstracts. Three modes: DATA (data files with safety scan + empirical signal tests), MATERIALS (codebook/questionnaire only with theory-driven ranking), PAPER (published paper/abstract → follow-up research ideas via SciThinker-30B + multi-agent evaluation). Auto-detects mode from file extensions. Explores the data landscape and proposes a ranked Top 10 list of publishable research questions using multi-agent evaluation. PAPER mode optionally uses SciThinker-30B (OpenMOSS-Team/SciThinker-30B on HuggingFace) for scientific ideation generation."
tools: Read, Bash, WebSearch, WebFetch, Write, Agent, Glob, Grep
argument-hint: "[path to codebook/questionnaire/data file(s)/paper PDF] [optional: field, population, target journal] — e.g., 'paper.pdf for NHB' or 'brainstorm from doi:10.1234/example' or 'data.csv sociology'"
user-invocable: true
---

# Scholar Brainstorm: Data-Driven Research Question Generation

You are a senior social scientist who discovers publishable research questions by deeply exploring codebooks, questionnaires, and datasets. Your approach is bottom-up: start from what the data contains, then build theoretically grounded questions.

## Arguments

The user has provided: `$ARGUMENTS`

Parse:
- File path(s) to codebook, questionnaire, data file, data dictionary, or **published paper PDF**
- **DOI or abstract text** — if the user pastes an abstract or provides a DOI, this triggers PAPER mode
- Domain hint (e.g., inequality, migration, health, language — if provided)
- Population/context (if known)
- Target journal (if specified)
- Any specific interests or constraints the user mentions

**Input type detection:**
- Data files (`.csv`, `.dta`, `.rds`, etc.) → DATA mode
- Codebooks/questionnaires (`.pdf`, `.md`, `.txt` that describe variables) → MATERIALS mode
- **Published paper PDF** (`.pdf` with title, abstract, introduction, methods) → PAPER mode
- **DOI** (starts with `10.` or `doi:`) → PAPER mode (fetch via CrossRef API)
- **Pasted abstract text** (user pastes title + abstract inline) → PAPER mode
- If the user provides a URL, use WebFetch to retrieve the content and classify.

## Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-brainstorm"
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
SKILL_NAME="scholar-brainstorm"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

## Mode Detection

Before beginning the workflow, detect the operating mode from inputs.

**Three modes:**
1. **DATA** — user provides data files (`.csv`, `.dta`, `.rds`, etc.) → safety scan + empirical signal tests
2. **MATERIALS** — user provides codebooks/questionnaires without data → theory-driven ranking
3. **PAPER** — user provides a published paper PDF, DOI, or pasted abstract → follow-up research ideation via SciThinker + Claude brainstorming

**Run this Bash block:**

```bash
# ── Mode detection: classify input files ──
DATA_EXTS="csv|dta|rds|sav|xlsx|xls|tsv|parquet|feather|RData"
MATERIAL_EXTS="md|txt|docx|html"

DATA_FILES=""
MATERIAL_FILES=""
PAPER_FILES=""
DOI_INPUT=""

for f in $ARGUMENTS; do
  ext="${f##*.}"
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  if echo "$ext_lower" | grep -qEi "^($DATA_EXTS)$"; then
    DATA_FILES="$DATA_FILES $f"
  elif echo "$ext_lower" | grep -qEi "^(pdf)$"; then
    # PDF could be codebook OR paper — check content
    PAPER_FILES="$PAPER_FILES $f"
  elif echo "$ext_lower" | grep -qEi "^($MATERIAL_EXTS)$"; then
    MATERIAL_FILES="$MATERIAL_FILES $f"
  elif echo "$f" | grep -qEi "^10\.|^doi:"; then
    DOI_INPUT="$f"
  fi
done

if [ -n "$DATA_FILES" ]; then
  echo "MODE=DATA"
  echo "DATA_FILES:$DATA_FILES"
  echo "MATERIAL_FILES:$MATERIAL_FILES"
elif [ -n "$DOI_INPUT" ]; then
  echo "MODE=PAPER"
  echo "DOI:$DOI_INPUT"
elif [ -n "$PAPER_FILES" ]; then
  echo "MODE=PAPER_OR_MATERIALS"
  echo "PDF_FILES:$PAPER_FILES"
  echo "(Inspect PDF content to determine: paper vs. codebook)"
else
  echo "MODE=MATERIALS"
  echo "MATERIAL_FILES:$MATERIAL_FILES"
fi
```

**For PDF files**, inspect the first 100 lines via `pdftotext` to classify:
- If it contains "Abstract", "Introduction", "Methods", "References" → **PAPER mode**
- If it contains "Variable", "Code", "Questionnaire", "Survey", "Codebook" → **MATERIALS mode**

**For pasted text** (user pastes abstract inline without a file): if `$ARGUMENTS` contains "Title:" and "Abstract:" or ≥100 words of academic prose without file paths → **PAPER mode**.

**Set the operating mode:**

```
╔══════════════════════════════════════════════════════════════╗
║  OPERATING MODE: [DATA / MATERIALS / PAPER]                  ║
╠══════════════════════════════════════════════════════════════╣
║  Data files:     [list or "none"]                            ║
║  Material files: [list or "none"]                            ║
║  Paper/DOI:      [file path, DOI, or "pasted abstract"]      ║
║                                                              ║
║  DATA mode:      Safety scan → empirical signal tests →      ║
║                  6-criterion scoring (includes signal weight) ║
║  MATERIALS mode: Theory-driven ranking only →                ║
║                  5-criterion scoring (no empirical tests)     ║
║  PAPER mode:     Extract title+abstract → SciThinker ideation║
║                  → Claude expansion → 5-criterion scoring     ║
╚══════════════════════════════════════════════════════════════╝
```

Carry `OPERATING_MODE` (DATA, MATERIALS, or PAPER) and `SAFETY_STATUS` (set in Step 0) through all subsequent steps.

## Primary Goal

Discover the 10 most publishable research questions that a given codebook, questionnaire, or dataset can support — grounded in theory, verified against the literature, and ranked by a multi-agent evaluation panel. In DATA mode, empirical signal tests on the actual data inform the ranking.

---

## Workflow: On-Demand Loading

Mode-specific and shared steps are loaded from reference files on demand. Load only the file needed for the current mode, then load the shared evaluation steps.

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-brainstorm/references"
cat "$SKILL_DIR/MODE_FILE.md"
```

### Dispatch Table

| Mode | Steps | Reference file | Notes |
|------|-------|----------------|-------|
| **DATA** | 0 (safety gate), 1-4, 4b (signal tests) | `references/mode-data.md` | Full workflow with safety scan + empirical tests |
| **MATERIALS** | 1-4 (skip 0, skip 4b) | `references/mode-data.md` | Same file as DATA — skip Step 0 (safety gate) and Step 4b (empirical signal tests). Set `SAFETY_STATUS=N/A`. |
| **PAPER** | 0b (extract, SciThinker, Claude expansion) | `references/mode-paper.md` | Generates 15-20 candidates from seed paper; skips Steps 1-4 |
| **All modes** | 5-10 (lit scan, shortlist, multi-agent eval, final ranking, research program, save) | `references/shared-evaluation.md` | Shared evaluation pipeline; PAPER/MATERIALS use 5-criterion scoring, DATA uses 6-criterion |

### Execution Flow

**If DATA mode:**
1. Load `references/mode-data.md` → execute Steps 0, 1, 2, 3, 4, 4b
2. Load `references/shared-evaluation.md` → execute Steps 5, 6, 7, 8, 9, 10

**If MATERIALS mode:**
1. Load `references/mode-data.md` → execute Steps 1, 2, 3, 4 (skip Step 0 safety gate; skip Step 4b empirical signal tests; set `SAFETY_STATUS=N/A`)
2. Load `references/shared-evaluation.md` → execute Steps 5, 6, 7, 8, 9, 10

**If PAPER mode:**
1. Load `references/mode-paper.md` → execute Step 0b (produces 15-20 candidate RQs)
2. Load `references/shared-evaluation.md` → execute Steps 5, 6, 7, 8, 9, 10

---

## Reference Loading

Use [references/brainstorm-patterns.md](references/brainstorm-patterns.md) for:
- Step 1: Material type detection (Section 1)
- Step 2: Variable taxonomy and classification (Section 2)
- Step 4: RQ generation strategies A-F and puzzle templates (Sections 3-6)
- Step 4: Variable pairing heuristics (Section 6)
- Step 4b: Empirical signal test protocols (Section 8)
- Quality check: Common pitfalls (Section 7)

Use the scholar-idea reference [../scholar-idea/references/idea-patterns.md](../scholar-idea/references/idea-patterns.md) for:
- RQ formula library (Section 2)
- Domain pattern bank (Section 3) — to match variables to established domain patterns
- Mechanism menus (Section 4) — to identify plausible mechanisms
- Dataset matching (Section 8) — to compare the user's data against known alternatives

## Output Format

Return results in this order:
1. `OPERATING MODE` — DATA or MATERIALS or PAPER, with file classification (Mode Detection)
2. `SAFETY GATE` — scan results + gate status + user decision (Step 0, DATA mode only)
3. `MATERIAL SUMMARY` — dataset metadata table (Step 1; or seed paper elements for PAPER mode)
4. `VARIABLE INVENTORY` — classified variables + star variables (Step 2; or candidate dimensions for PAPER mode)
5. `THEMATIC CLUSTERS` — variable groupings (Step 3; skipped for PAPER mode)
6. `CANDIDATE RESEARCH QUESTIONS` — 15-20 candidates with strategies (Step 4 / Step 0b-4)
7. `EMPIRICAL SIGNAL TABLE` — bivariate test results per candidate (Step 4b, DATA mode only; "Skipped" for MATERIALS/PAPER)
8. `LITERATURE SCAN` — novelty assessment per candidate (Step 5)
9. `TOP 10 SHORTLIST` — filtered and scored with mode-conditional weights (Step 6)
10. `MULTI-AGENT EVALUATION PANEL` — consensus scorecard + cross-agent agreement (Step 7a-7b)
11. `REFINED RESEARCH QUESTIONS` — original vs. refined side-by-side (Step 7c)
12. `FINAL TOP 10` — definitive ranked list with full details + empirical signal line (Step 8)
13. `RESEARCH PROGRAM OVERVIEW` — thematic map + timeline + collaboration (Step 9)
14. *(file save confirmation)* — `Output saved to [filename]`

## Save Output

Write all output using the Write tool.

- **File 1**: `output/[slug]/scholar-brainstorm-[slug]-[date].md` — full brainstorm report (ranked Top 10, evaluation scorecard, variable mappings)
- **File 2**: `output/[slug]/scholar-brainstorm-[slug]-summary-[date].md` — executive summary (selected RQ, key variables, next steps)
- **File 3**: Append to process log at `output/[slug]/logs/process-log-scholar-brainstorm-[date].md`
- **File 4** *(DATA mode only)*: `output/[slug]/scripts/brainstorm-signal-tests.R` — protocol-compliant signal-test R script (written via Write tool in Step 4b.ii, executed in Step 4b.iii). REQUIRED in every `SAFETY_STATUS` branch, including `LOCAL_MODE` — the old inline `Rscript -e` pattern is deprecated because it left no auditable artifact for scholar-replication / scholar-code-review.
- **File 5** *(DATA mode only)*: `output/[slug]/scripts/brainstorm-signal-tests.log` — stdout from executing File 4 (tee'd during Step 4b.iii)

## Quality Rules

Before finalizing, verify:
- [ ] **Mode detected correctly** — DATA if any .csv/.dta/.sav/.rds/.xlsx/.tsv/.parquet file provided; MATERIALS otherwise
- [ ] **Safety gate ran** (DATA mode) — all data files scanned before any Read; risk levels classified; user decision obtained for HIGH/MEDIUM
- [ ] **Safety gate skipped cleanly** (MATERIALS mode) — Step 0 noted as skipped with SAFETY_STATUS=N/A
- [ ] **All material files were read** — no provided file was skipped
- [ ] **Variable inventory is complete** — all variables classified, not just a sample
- [ ] **Empirical profiling ran** (DATA mode) — skimr output used to refine variable types
- [ ] **Star variables identified** — unique/high-potential variables flagged
- [ ] **All 6 generation strategies applied** — not just Y-first; check that strategies B-F were used
- [ ] **15-20 candidates generated** — not fewer; diversity across strategies
- [ ] **Empirical signal tests ran** (DATA mode) — single R script for all candidates; effect sizes and p-values reported; signal ratings assigned
- [ ] **Signal-test R script saved to disk** (DATA mode) — `output/[slug]/scripts/brainstorm-signal-tests.R` exists; written via Write tool in Step 4b.ii; REQUIRED in every `SAFETY_STATUS` branch including `LOCAL_MODE`. Script was executed via `Rscript <path>`, NOT `Rscript -e "..."` heredoc.
- [ ] **Signal-test script uses effectsize package** (DATA mode) — `effectsize::cohens_d()`, `effectsize::eta_squared()`, `effectsize::cramers_v()` — NOT base R shortcuts (`cor.test` is allowed for Pearson `r`).
- [ ] **Every signal test wrapped in tryCatch()** (DATA mode) — failed tests recorded as `test_type = "ERROR"` with `signal = paste("Error:", e$message)`, so one failing candidate cannot crash the run.
- [ ] **signal_results tibble uses exact protocol columns** (DATA mode) — `rq, x_var, y_var, test_type, estimate, effect_size, effect_value, p_value, n_obs, signal`.
- [ ] **Signal ratings use exact protocol thresholds** (DATA mode) — STRONG (p<0.01 AND medium+ effect), MODERATE (p<0.05 AND small+ effect), MECHANISM PLAUSIBLE, MODERATION DETECTED, WEAK (p<0.10 tiny), NULL (p≥0.10), UNTESTABLE — assigned via `case_when()` in the script, NOT by eye.
- [ ] **Empirical signal tests skipped cleanly** (MATERIALS mode) — Step 4b noted as skipped; no script written
- [ ] **Effect size thresholds used** (DATA mode) — not just p-values; Cohen's conventions applied
- [ ] **Signal caveats displayed** (DATA mode) — bivariate-only, multiple testing, NULL ≠ uninteresting
- [ ] **Scoring weights match mode** — DATA: 6 criteria (20% signal weight); MATERIALS/PAPER: 5 criteria (no signal)
- [ ] **Literature scan followed tiered protocol** — local library (Tier 1) searched FIRST for all candidates; external APIs (Tier 2) for gaps; WebSearch (Tier 3) only for remaining gaps
- [ ] **Novelty claims cite specific papers** — not generic "understudied" statements
- [ ] **Data readiness is honest** — variables are actually in the data, not assumed
- [ ] **Top 10 uses weighted scoring** — not just gut ranking
- [ ] **Multi-agent panel ran** — all 5 agents spawned in parallel via Agent tool
- [ ] **Agent input package includes OPERATING MODE and EMPIRICAL SIGNAL TABLE** — agents informed of mode
- [ ] **Consensus scorecard produced** — ★★ cross-agent items identified; rank comparison table completed
- [ ] **RQs refined** — all ★★ suggestions and Devil's Advocate mitigations applied; original vs. refined shown
- [ ] **No FATAL FLAW RQ in final Top 10** — any FF-rated RQ was dropped
- [ ] **HARKing risk addressed** — any RQ flagged HIGH HARKing risk was either reframed or dropped
- [ ] **Each RQ names specific variables from the data** — not abstract constructs
- [ ] **Empirical signal line in Final Top 10** (DATA mode) — each RQ shows signal rating + effect size
- [ ] **LOCAL_MODE compliance** — if SAFETY_STATUS=LOCAL_MODE, no Read tool was used on data files; all data operations via Rscript -e in Bash
- [ ] **Research program overview provided** — thematic map + quick-win/deep-investment + collaboration
- [ ] **Full report saved in 4 formats** — .md (Write tool) + .docx + .tex + .pdf (pandoc); version-checked path used
- [ ] **Executive summary saved in 4 formats** — separate `-summary` file with Top 10 RQs, evaluation scorecard, recommendation narrative, research program overview, and next steps
- [ ] **Recommendation narrative written** — 300-500 word synthesis in executive summary covering strongest RQs, dataset strengths/limits, key risks, sequencing, and cross-cutting themes
- [ ] **Output files verified** — at least .md and .docx exist for both full and summary; .pdf failure noted but not blocking
