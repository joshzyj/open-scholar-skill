---
name: scholar-replication
description: >
  Build, document, test, and validate a journal-ready replication package for
  social science research. Six modes: (1) BUILD — assemble scripts, data,
  documentation into structured replication directory from output/[slug]/scripts/ and
  project artifacts; (2) DOCUMENT — generate comprehensive README (AEA template),
  codebook, data dictionary, computational requirements, dependency graph;
  (3) TEST — execute clean-run validation in isolated environment (fresh renv/conda,
  Docker optional), compare reproduced outputs against published tables/figures;
  (4) VERIFY — paper-to-code correspondence audit ensuring every table, figure,
  and in-text statistic has a producing script; (5) ARCHIVE — create versioned
  release, Zenodo DOI, GitHub integration, repository deposit preparation;
  (6) FULL — run all modes sequentially. Consumes output/[slug]/scripts/ from
  scholar-analyze/scholar-compute. Targets ASR, AJS,
  Demography, Science Advances, NHB, NCS, APSR.
tools: Read, Write, Bash, WebSearch, Glob, Grep
argument-hint: "[BUILD|DOCUMENT|TEST|VERIFY|ARCHIVE|FULL] [project description or journal name]"
user-invocable: true
---

# scholar-replication — Replication Package Builder and Validator

> **Key differentiation from scholar-open:**
> - `scholar-open` = open science *declarations* (preregistration, data sharing policies, code sharing templates, audit checklists)
> - `scholar-replication` = replication package *construction and validation* (assemble, document, test, verify, archive)
>
> scholar-open produces templates and compliance checklists. scholar-replication **actively builds the directory on disk, copies and renumbers scripts, generates documentation, runs clean-run tests, audits paper-to-code correspondence, and prepares archive deposits.**

---

## Step 0: Argument Parsing & Inventory

### 0a. Parse mode and arguments

Parse `$ARGUMENTS` to determine:
- **MODE**: BUILD | DOCUMENT | TEST | VERIFY | ARCHIVE | FULL
- **JOURNAL** target (determines compliance tier): ASR, AJS, Demography, NHB, NCS, Science Advances, APSR, AJPS, or general
- **PROJECT_DIR**: project root directory (default: current working directory)

### 0b. Dispatch table

| If `$ARGUMENTS` contains | Route to |
|--------------------------|----------|
| `build` / `assemble` / `package` | Step 1 (Build) |
| `document` / `readme` / `codebook` / `docs` | Step 2 (Document) |
| `test` / `clean-run` / `clean run` / `validate` / `execute` | Step 3 (Test) |
| `verify` / `audit` / `correspondence` / `check` | Step 4 (Verify) |
| `archive` / `zenodo` / `deposit` / `doi` / `release` | Step 5 (Archive) |
| `full` / default (no keyword) | Steps 1 → 2 → 3 → 4 → 5 in order |

### 0c. Artifact inventory scan

Use Bash + Glob to scan for existing project artifacts:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"

# Script archive from scholar-analyze/compute/full-paper
ls -la "${OUTPUT_ROOT}/scripts/" 2>/dev/null
cat "${OUTPUT_ROOT}/scripts/script-index.md" 2>/dev/null
cat "${OUTPUT_ROOT}/scripts/coding-decisions-log.md" 2>/dev/null

# Produced outputs — main pipeline
ls -la "${OUTPUT_ROOT}/tables/" 2>/dev/null
ls -la "${OUTPUT_ROOT}/figures/" 2>/dev/null

# Produced outputs — EDA pipeline (from scholar-eda)
ls -la "${OUTPUT_ROOT}/eda/tables/" 2>/dev/null
ls -la "${OUTPUT_ROOT}/eda/figures/" 2>/dev/null

# Artifact Registry (from scholar-write — single source of truth for table/figure numbering)
cat "${OUTPUT_ROOT}/manuscript/artifact-registry.md" 2>/dev/null || \
  cat "${OUTPUT_ROOT}/artifact-registry.md" 2>/dev/null || \
  echo "No artifact registry found"

# Citation verification reports
ls -la "${OUTPUT_ROOT}/citations/" 2>/dev/null

# Manuscript files
ls -la "${OUTPUT_ROOT}/manuscript/" 2>/dev/null
```

Also scan for:
- `renv.lock` or `environment.yml` (existing environment captures)
- `Makefile` or `_targets.R` (existing pipeline orchestrators)
- `Dockerfile` (existing containerization)
- `README.md` in project root (existing documentation)
- `CITATION.cff` (existing citation metadata)
- Any `.R`, `.py`, `.do`, `.jl` scripts in `code/` or project root

### 0d. Print project state header

```
╔══════════════════════════════════════════════════════════════╗
║  SCHOLAR-REPLICATION — Replication Package Builder          ║
║  Mode:    [BUILD|DOCUMENT|TEST|VERIFY|ARCHIVE|FULL]         ║
║  Journal: [target journal or general]                        ║
║  Date:    [YYYY-MM-DD]                                       ║
╠══════════════════════════════════════════════════════════════╣
║  Artifact Inventory                                          ║
║  Scripts in output/[slug]/scripts/:     [N]                  ║
║  Script index present:           [yes/no]                    ║
║  Coding decisions log present:   [yes/no]                    ║
║  Tables in output/[slug]/tables/:       [N]                  ║
║  Figures in output/[slug]/figures/:     [N]                  ║
║  EDA tables in output/[slug]/eda/tables/:  [N]               ║
║  EDA figures in output/[slug]/eda/figures/: [N]              ║
║  Artifact Registry (scholar-write): [yes/no]                 ║
║  Manuscript files:               [N]                         ║
║  Environment lockfile:           [renv.lock/environment.yml/none] ║
║  Existing Makefile:              [yes/no]                    ║
║  Existing Dockerfile:            [yes/no]                    ║
╚══════════════════════════════════════════════════════════════╝
```

Dispatch to the appropriate step(s) based on MODE.

### 0e. Create directory tree (MANDATORY — runs BEFORE readiness gate)

> **CRITICAL**: Always create the replication-package directory structure first, regardless of readiness gate outcome. This ensures the directory exists even if later steps encounter warnings or errors.

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
REPL_DIR="replication-package"
mkdir -p "$REPL_DIR"/{data/{raw,processed,codebook},code/utils,output/{tables,figures,models,eda/tables,eda/figures},paper}
mkdir -p "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/replication" "${OUTPUT_ROOT}/scripts"
echo "Created replication-package/ directory structure"
ls -d "$REPL_DIR"/*/
```

### 0f. Replication readiness gate

Evaluate the artifact inventory from 0c to determine build completeness:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# Count artifacts
N_SCRIPTS=$(ls "${OUTPUT_ROOT}/scripts/"*.R "${OUTPUT_ROOT}/scripts/"*.py "${OUTPUT_ROOT}/scripts/"*.do 2>/dev/null | wc -l)
N_TABLES=$(ls "${OUTPUT_ROOT}/tables/"* 2>/dev/null | wc -l)
N_FIGURES=$(ls "${OUTPUT_ROOT}/figures/"* 2>/dev/null | wc -l)
N_EDA_TABLES=$(ls "${OUTPUT_ROOT}/eda/tables/"* 2>/dev/null | wc -l)
N_EDA_FIGURES=$(ls "${OUTPUT_ROOT}/eda/figures/"* 2>/dev/null | wc -l)
N_TOTAL=$((N_SCRIPTS + N_TABLES + N_FIGURES + N_EDA_TABLES + N_EDA_FIGURES))
echo "REPLICATION READINESS: $N_SCRIPTS scripts, $N_TABLES tables, $N_FIGURES figures, $N_EDA_TABLES EDA tables, $N_EDA_FIGURES EDA figures (total: $N_TOTAL)"
```

**Decision logic:**

| Condition | Action |
|-----------|--------|
| `N_SCRIPTS = 0` AND `N_TABLES = 0` AND `N_FIGURES = 0` | **WARN + fallback extraction** — Attempt to recover scripts from upstream outputs (see 0g below). After recovery, re-count and re-evaluate. If recovery still yields all zeros, log warning: "Replication package will contain directory structure only — no scripts, tables, or figures found. Re-run analysis skills to populate." **Always proceed to Step 1** (the directory already exists from 0e). |
| `N_SCRIPTS = 0` but tables/figures exist | **WARN** — Report: "WARNING: No scripts found in `output/[slug]/scripts/`. Tables and figures exist but cannot be traced to producing scripts. The replication package will be incomplete — consider running analysis skills with Script Archive Protocol enabled." Proceed to Step 1 with warning logged. |
| `N_SCRIPTS > 0` but `N_TABLES = 0` AND `N_FIGURES = 0` | **WARN** — Report: "WARNING: Scripts found but no output tables or figures. The replication package will contain code but no reproducible outputs." Proceed to Step 1 with warning logged. |
| All counts > 0 | **PASS** — Proceed normally. |

Also check for artifact registry:
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
if [ -f "${OUTPUT_ROOT}/manuscript/artifact-registry.md" ] || [ -f "${OUTPUT_ROOT}/artifact-registry.md" ]; then
  echo "ARTIFACT REGISTRY: found"
else
  echo "ARTIFACT REGISTRY: NOT FOUND — paper-to-code correspondence (Step 4) will be limited"
fi
```

### 0g. Fallback script extraction (runs when 0f finds N_SCRIPTS = 0)

If no scripts are found, attempt to recover from upstream outputs:

**Source 1 — Analysis logs:** Scan `output/[slug]/logs/scholar-analyze-*.md` and `output/[slug]/logs/scholar-eda-*.md` for fenced code blocks (` ```r `, ` ```python `, ` ```stata `).

**Source 2 — Manuscript drafts:** Scan `output/[slug]/manuscript/*.md` and `output/[slug]/drafts/*.md` for `[CODE-TEMPLATE]` blocks or fenced code blocks.

**Source 3 — Project root scripts:** Scan project root and `code/` directory for any `.R`, `.py`, `.do`, `.jl` files that were not in `output/[slug]/scripts/`.

**Extraction procedure:**
1. `mkdir -p "${OUTPUT_ROOT}/scripts"`
2. For each discovered code block, save to `${OUTPUT_ROOT}/scripts/` with sequential numbering and descriptive name (e.g., `01-data-loading.R`, `02-main-models.R`)
3. Add header: `# Recovered by scholar-replication fallback | Source: [filename:line] | Date: [date]`
4. Create `${OUTPUT_ROOT}/scripts/script-index.md` listing all recovered scripts

**After extraction, re-count:**
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
N_SCRIPTS=$(ls "${OUTPUT_ROOT}/scripts/"*.R "${OUTPUT_ROOT}/scripts/"*.py "${OUTPUT_ROOT}/scripts/"*.do 2>/dev/null | wc -l | tr -d ' ')
echo "Post-recovery script count: $N_SCRIPTS"
```

**Always proceed to Step 1** — the directory structure already exists from 0e. The readiness gate determines *completeness warnings*, not whether to build.

---

## Step 1: BUILD — Assemble Replication Package

Populate the replication package directory (created in Step 0e) with scripts, data, and outputs.

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-replication"
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
SKILL_NAME="scholar-replication"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}"*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

Target structure:

```
replication-package/
├── README.md                      (comprehensive documentation — Step 2)
├── LICENSE                        (dual: MIT for code, CC-BY-4.0 for data/docs)
├── CITATION.cff                   (machine-readable citation metadata)
├── DECISIONS.md                   (from coding-decisions-log.md)
├── Makefile                       (pipeline orchestrator with dependency-aware targets)
├── renv.lock / environment.yml    (environment lockfile)
├── Dockerfile                     (if computational / NCS — conditional)
├── data/
│   ├── README.md                  (data documentation: sources, access, format)
│   ├── raw/                       (raw data files OR download instructions)
│   ├── processed/                 (analytic datasets if shareable)
│   └── codebook/                  (variable dictionaries, value labels)
├── code/
│   ├── 00_master.R                (master controller script)
│   ├── 01_clean.R                 (from output/[slug]/scripts/ renumbered)
│   ├── 02_construct.R             (sample construction)
│   ├── 03_analysis.R              (main analysis)
│   ├── 04_robustness.R            (robustness checks)
│   ├── 05_figures.R               (figure generation)
│   └── utils/                     (shared helper functions)
├── output/
│   ├── tables/                    (reproduced tables — HTML/TeX/docx)
│   ├── figures/                   (reproduced figures — PDF/PNG)
│   ├── eda/
│   │   ├── tables/                (EDA tables from scholar-eda — Table 1, missingness, etc.)
│   │   └── figures/               (EDA figures from scholar-eda — distributions, correlations, etc.)
│   ├── models/                    (saved model weights if applicable)
│   └── artifact-registry.md       (from scholar-write — table/figure numbering map)
└── paper/                         (manuscript source if available)
```

### 1a. Copy and renumber scripts

Read `${OUTPUT_ROOT}/scripts/script-index.md` to determine run order. If no index exists, scan script filenames for ordering cues (date stamps, numeric prefixes, dependency comments).

For each script in `${OUTPUT_ROOT}/scripts/`:

1. **Assign a two-digit prefix** based on execution order: `01_`, `02_`, `03_`, ...
2. **Give a descriptive name**: `01_clean_data.R`, `02_construct_sample.R`, `03_main_analysis.R`, `04_robustness_checks.R`, `05_generate_figures.R`
3. **Copy to `replication-package/code/`**
4. **Fix paths**: replace any absolute paths with relative paths

```bash
# Example: detect and fix absolute paths
grep -rn '/Users\|/home\|C:\\' replication-package/code/ || echo "No absolute paths found"
```

5. **Generate `00_master.R`** (or `00_master.py` for Python projects):

```r
# 00_master.R — Master controller for replication package
# This script runs all analysis scripts in sequence.
# Expected runtime: [estimated total] minutes
# Last tested: [date]

cat("========================================\n")
cat("Replication Package — Master Controller\n")
cat("========================================\n\n")

# Set working directory to project root
# (Assumes this script is run from replication-package/)
setwd(here::here())

# Record start time
t0 <- Sys.time()

# --- Script sequence ---
scripts <- c(
  "code/01_clean_data.R",
  "code/02_construct_sample.R",
  "code/03_main_analysis.R",
  "code/04_robustness_checks.R",
  "code/05_generate_figures.R"
)

for (s in scripts) {
  cat(sprintf("\n>>> Running %s ...\n", s))
  t_start <- Sys.time()
  source(s, echo = FALSE)
  t_end <- Sys.time()
  cat(sprintf("    Completed in %.1f seconds\n", difftime(t_end, t_start, units = "secs")))
}

# Report total runtime
cat(sprintf("\n========================================\n"))
cat(sprintf("All scripts completed in %.1f minutes\n",
            difftime(Sys.time(), t0, units = "mins")))
cat(sprintf("========================================\n"))
```

For Python projects, generate `00_master.py`:

```python
#!/usr/bin/env python3
"""Master controller for replication package."""
import subprocess, time, sys

scripts = [
    "code/01_clean_data.py",
    "code/02_construct_sample.py",
    "code/03_main_analysis.py",
    "code/04_robustness_checks.py",
    "code/05_generate_figures.py",
]

t0 = time.time()
for s in scripts:
    print(f"\n>>> Running {s} ...")
    t_start = time.time()
    result = subprocess.run([sys.executable, s], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"    FAILED: {result.stderr[:500]}")
        sys.exit(1)
    print(f"    Completed in {time.time() - t_start:.1f} seconds")

print(f"\nAll scripts completed in {(time.time() - t0)/60:.1f} minutes")
```

### 1b. Copy coding decisions log

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
if [ -f "${OUTPUT_ROOT}/scripts/coding-decisions-log.md" ]; then
  cp "${OUTPUT_ROOT}/scripts/coding-decisions-log.md" replication-package/DECISIONS.md
  echo "  ✓ Copied coding decisions log"
else
  echo "  ⚠ No coding-decisions-log.md found — creating template"
fi
```

If no decisions log exists, generate a template:

```markdown
# Analytic Decisions Log

This document records key decisions made during data analysis.

| Decision | Options considered | Choice | Rationale | Script |
|----------|-------------------|--------|-----------|--------|
| Sample restriction | Full sample vs. age 18+ | Age 18+ | Match prior literature | 01_clean_data.R |
| Missing data | Listwise vs. MICE | MICE (m=20) | MAR assumption supported by Little's test | 02_construct_sample.R |
| Standard errors | OLS vs. HC3 vs. cluster | Cluster by state | Clustered treatment assignment | 03_main_analysis.R |
```

### 1c. Copy output files (tables, figures, EDA outputs, artifact registry) from `${OUTPUT_ROOT}/`

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# Copy main pipeline tables and figures (with explicit logging)
if ls "${OUTPUT_ROOT}/tables/"* 1>/dev/null 2>&1; then
  cp -r "${OUTPUT_ROOT}/tables/"* replication-package/output/tables/
  echo "  ✓ Copied $(ls "${OUTPUT_ROOT}/tables/"* | wc -l | tr -d ' ') table files"
else
  echo "  ⚠ WARNING: ${OUTPUT_ROOT}/tables/ is empty or missing — no tables to copy"
fi

if ls "${OUTPUT_ROOT}/figures/"* 1>/dev/null 2>&1; then
  cp -r "${OUTPUT_ROOT}/figures/"* replication-package/output/figures/
  echo "  ✓ Copied $(ls "${OUTPUT_ROOT}/figures/"* | wc -l | tr -d ' ') figure files"
else
  echo "  ⚠ WARNING: ${OUTPUT_ROOT}/figures/ is empty or missing — no figures to copy"
fi

# Copy EDA pipeline tables and figures (from scholar-eda)
if ls "${OUTPUT_ROOT}/eda/tables/"* 1>/dev/null 2>&1; then
  cp -r "${OUTPUT_ROOT}/eda/tables/"* replication-package/output/eda/tables/
  echo "  ✓ Copied $(ls "${OUTPUT_ROOT}/eda/tables/"* | wc -l | tr -d ' ') EDA table files"
else
  echo "  ⚠ No EDA tables found (${OUTPUT_ROOT}/eda/tables/) — skipping"
fi

if ls "${OUTPUT_ROOT}/eda/figures/"* 1>/dev/null 2>&1; then
  cp -r "${OUTPUT_ROOT}/eda/figures/"* replication-package/output/eda/figures/
  echo "  ✓ Copied $(ls "${OUTPUT_ROOT}/eda/figures/"* | wc -l | tr -d ' ') EDA figure files"
else
  echo "  ⚠ No EDA figures found (${OUTPUT_ROOT}/eda/figures/) — skipping"
fi

# Copy artifact registry (from scholar-write — maps table/figure numbers to files)
if [ -f "${OUTPUT_ROOT}/manuscript/artifact-registry.md" ]; then
  cp "${OUTPUT_ROOT}/manuscript/artifact-registry.md" replication-package/output/artifact-registry.md
  echo "  ✓ Copied artifact registry from ${OUTPUT_ROOT}/manuscript/"
elif [ -f "${OUTPUT_ROOT}/artifact-registry.md" ]; then
  cp "${OUTPUT_ROOT}/artifact-registry.md" replication-package/output/artifact-registry.md
  echo "  ✓ Copied artifact registry from ${OUTPUT_ROOT}/"
else
  echo "  ⚠ WARNING: No artifact-registry.md found — paper-to-code mapping will be incomplete"
fi

# Copy manuscript source if available
if ls "${OUTPUT_ROOT}/manuscript/"*.md 1>/dev/null 2>&1 || ls "${OUTPUT_ROOT}/manuscript/"*.tex 1>/dev/null 2>&1; then
  cp "${OUTPUT_ROOT}/manuscript/"*.md replication-package/paper/ 2>/dev/null
  cp "${OUTPUT_ROOT}/manuscript/"*.tex replication-package/paper/ 2>/dev/null
  echo "  ✓ Copied manuscript source files to paper/"
else
  echo "  ⚠ No manuscript files found in ${OUTPUT_ROOT}/manuscript/"
fi
```

**Table/figure format inventory** — verify all outputs are present in viewable formats:

```bash
echo "=== Table/Figure Format Inventory ==="

echo "--- Main tables ---"
for tbl in replication-package/output/tables/*; do
  [ -f "$tbl" ] || continue
  echo "  $(basename "$tbl")"
done

echo "--- Main figures ---"
for fig in replication-package/output/figures/*; do
  [ -f "$fig" ] || continue
  echo "  $(basename "$fig")"
done

echo "--- EDA tables ---"
for tbl in replication-package/output/eda/tables/*; do
  [ -f "$tbl" ] || continue
  echo "  $(basename "$tbl")"
done

echo "--- EDA figures ---"
for fig in replication-package/output/eda/figures/*; do
  [ -f "$fig" ] || continue
  echo "  $(basename "$fig")"
done

# Check that each table has at least one renderable format
echo ""
echo "--- Format coverage check ---"
for base in $(ls replication-package/output/tables/ replication-package/output/eda/tables/ 2>/dev/null | sed 's/\.[^.]*$//' | sort -u); do
  formats=""
  for ext in html tex docx; do
    [ -f "replication-package/output/tables/${base}.${ext}" ] && formats="${formats} ${ext}"
    [ -f "replication-package/output/eda/tables/${base}.${ext}" ] && formats="${formats} ${ext}"
  done
  if [ -z "$formats" ]; then
    echo "  WARN: $base — no HTML/TeX/docx format found"
  else
    echo "  OK: $base —$formats"
  fi
done

# Verify figure formats are standard
for fig in replication-package/output/figures/* replication-package/output/eda/figures/*; do
  [ -f "$fig" ] || continue
  ext="${fig##*.}"
  case "$ext" in
    pdf|png|jpg|jpeg|svg|eps|tiff) ;;
    *) echo "  WARN: unusual figure format: $(basename "$fig")" ;;
  esac
done

# Artifact registry status
if [ -f replication-package/output/artifact-registry.md ]; then
  echo ""
  echo "--- Artifact Registry ---"
  echo "  Present: yes"
  grep -c "^[0-9]\|^Table\|^Figure\|^Appendix" replication-package/output/artifact-registry.md 2>/dev/null | \
    xargs -I{} echo "  Registered items: {}"
else
  echo ""
  echo "  WARN: No artifact registry found — table/figure numbering may be incomplete"
fi
```

### 1d. Data handling decision tree

Assess data availability and apply the correct strategy:

| Data status | Action | Location |
|-------------|--------|----------|
| **Public dataset** (NHANES, ACS, GSS, WDI, etc.) | Download instructions + script in `data/raw/` | `data/README.md` with URLs + `code/00a_download_data.R` |
| **Author-collected, shareable** | Copy analytic dataset to `data/processed/` | Include codebook in `data/codebook/` |
| **Restricted access** (PSID, NLSY, Census RDC, IPUMS) | Access instructions only | `data/README.md` with: application URL, DUA requirements, expected timeline, cost, contact |
| **Sensitive / IRB-protected** | Generate synthetic/mock dataset | Use `fabricatr::fabricate()` or `synthpop::syn()` in `code/00b_generate_mock_data.R`; document in `data/README.md` |
| **Social media** (Twitter/X, Reddit, etc.) | IDs-only approach per platform TOS | `data/raw/tweet_ids.txt` or `data/raw/post_ids.csv`; rehydration script in `code/00c_rehydrate.R` |
| **Computational** (model weights, embeddings) | Download script + HuggingFace Hub pointer | `code/00d_download_models.sh` with `huggingface-cli download` |

For **restricted data**, generate a detailed `data/README.md`:

```markdown
# Data Access Instructions

## [Dataset Name]

- **Provider**: [organization]
- **Application URL**: [URL]
- **Access type**: [restricted-use / DUA / application required]
- **Expected processing time**: [weeks/months]
- **Cost**: [if applicable]
- **Contact**: [email or office]

### What the replicator receives
After access is granted, the replicator will receive [describe files].
Place these files in `data/raw/` and run `code/01_clean_data.R`.

### Mock data for code review
`data/raw/mock_data.csv` contains a synthetic dataset with the same
variable names, types, and approximate distributions as the restricted
data. All scripts will run on this mock data to verify code correctness,
but reproduced results will differ from published results.
```

For **synthetic/mock data generation**:

```r
# 00b_generate_mock_data.R — Generate synthetic data for code testing
library(fabricatr)

mock <- fabricate(
  N = 5000,
  age = round(rnorm(N, 45, 15)),
  female = draw_binary(prob = 0.52, N),
  education = draw_ordered(x = rnorm(N), breaks = c(-1, 0, 1),
                           break_labels = c("< HS", "HS", "Some College", "BA+")),
  income = round(rlnorm(N, 10.5, 0.8)),
  outcome = 0.5 + 0.02 * age - 0.3 * female + 0.1 * as.numeric(education) +
            rnorm(N, 0, 1)
)
write.csv(mock, "data/raw/mock_data.csv", row.names = FALSE)
cat("Mock dataset written: data/raw/mock_data.csv\n")
cat(sprintf("  N = %d, %d variables\n", nrow(mock), ncol(mock)))
```

### 1e. Capture environment

```bash
# R projects: snapshot renv
cd replication-package
Rscript -e "if (!requireNamespace('renv', quietly=TRUE)) install.packages('renv'); renv::init(); renv::snapshot()" 2>/dev/null

# Python projects: export conda or pip
conda env export --no-builds > environment.yml 2>/dev/null || \
  pip freeze > requirements.txt 2>/dev/null
```

If an existing `renv.lock` or `environment.yml` is found in the project root, copy it:

```bash
cp renv.lock replication-package/ 2>/dev/null
cp environment.yml replication-package/ 2>/dev/null
cp requirements.txt replication-package/ 2>/dev/null
```

### 1f. Generate LICENSE

Write a dual-license file:

```
MIT License (for code)

Copyright (c) [YEAR] [AUTHOR]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

---

Creative Commons Attribution 4.0 International (CC-BY-4.0) (for data and documentation)

You are free to share and adapt the data and documentation in this package,
provided you give appropriate credit, provide a link to the license, and
indicate if changes were made.

Full license text: https://creativecommons.org/licenses/by/4.0/legalcode
```

### 1g. Generate CITATION.cff

```yaml
cff-version: 1.2.0
message: "If you use this replication package, please cite the associated paper."
type: dataset
title: "Replication Data and Code for: [PAPER TITLE]"
authors:
  - family-names: [LAST]
    given-names: [FIRST]
    orcid: "https://orcid.org/[ORCID]"
date-released: "[YYYY-MM-DD]"
version: "1.0.0"
doi: "[DOI — fill after deposit]"
license: MIT
repository-code: "[GitHub URL — fill after push]"
preferred-citation:
  type: article
  authors:
    - family-names: [LAST]
      given-names: [FIRST]
  title: "[PAPER TITLE]"
  journal: "[JOURNAL]"
  year: [YEAR]
  doi: "[PAPER DOI]"
```

### 1h. Generate Makefile

```makefile
# Makefile — Replication Package Pipeline
# Run: make all
# Individual targets: make data, make analysis, make figures, make clean

.PHONY: all data analysis figures clean

all: data analysis figures
	@echo "=== All targets completed ==="

data: output/tables/.data_done
output/tables/.data_done: code/01_clean_data.R code/02_construct_sample.R
	Rscript code/01_clean_data.R
	Rscript code/02_construct_sample.R
	@touch $@

analysis: output/tables/.analysis_done
output/tables/.analysis_done: output/tables/.data_done code/03_main_analysis.R code/04_robustness_checks.R
	Rscript code/03_main_analysis.R
	Rscript code/04_robustness_checks.R
	@touch $@

figures: output/figures/.figures_done
output/figures/.figures_done: output/tables/.analysis_done code/05_generate_figures.R
	Rscript code/05_generate_figures.R
	@touch $@

clean:
	rm -f output/tables/.data_done output/tables/.analysis_done output/figures/.figures_done
	rm -f output/tables/*.html output/tables/*.tex output/tables/*.docx
	rm -f output/figures/*.pdf output/figures/*.png
	@echo "=== Cleaned all outputs ==="
```

For Python projects, adapt targets to use `python` instead of `Rscript`.

### 1i. Generate Dockerfile (conditional)

Generate a Dockerfile if:
- Target journal is NCS (always requires computational reproducibility)
- Paper uses computational methods (NLP, ML, deep learning, ABM, CV)
- User explicitly requests Docker

```dockerfile
# Dockerfile — Replication Package
# Build: docker build -t replication-[slug] .
# Run:   docker run --rm -v $(pwd)/output:/replication/output replication-[slug]

FROM rocker/r-ver:4.4.0

# System dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy lockfile and restore
WORKDIR /replication
COPY renv.lock renv.lock
RUN Rscript -e "install.packages('renv'); renv::consent(provided=TRUE); renv::restore()"

# Copy project files
COPY . .

# Run pipeline
CMD ["Rscript", "code/00_master.R"]
```

For Python projects:

```dockerfile
FROM python:3.11-slim

WORKDIR /replication
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
CMD ["python", "code/00_master.py"]
```

**Build deliverable:** `replication-package/` directory fully assembled on disk.

---

## Step 2: DOCUMENT — Comprehensive Documentation

### 2a. README.md — AEA Social Science Data Editors Template

Generate `replication-package/README.md` based on the AEA gold-standard template (see `references/replication-standards.md` for full template). The README has 9 sections:

### AEA-Style README Template (Full 9 Sections)

```markdown
# Replication Package: [Paper Title]

## 1. Overview
Brief description of the paper, data, and code. List authors, date, and corresponding author contact.

## 2. Data Availability and Provenance
| Data Source | Files | Provided | Access |
|---|---|---|---|
| [Survey name] | `data/raw/survey.csv` | Yes | Public download at [URL] |
| [Admin data] | `data/raw/admin.dta` | No (DUA) | Apply at [URL]; expected wait: [X weeks] |

For each data source: cite the original source; document the license/terms of use; provide download instructions.

## 3. Dataset List
| Filename | Source | Notes | Provided |
|---|---|---|---|
| `data/raw/survey.csv` | [Source] | Downloaded [date] | Yes |
| `data/cleaned/analytic_sample.csv` | Constructed | Output of `01-clean.R` | Yes |

## 4. Computational Requirements
- **Software**: R 4.3.2, Stata 18, Python 3.11
- **Packages**: See `renv.lock` (R), `requirements.txt` (Python)
- **Hardware**: [X] GB RAM minimum; analyses completed on [machine description]
- **Runtime**: Total approximate runtime: [X hours/minutes]
- **Random seed**: Set to 42 in all stochastic procedures

## 5. Description of Programs/Code
| Script | Input | Output | Purpose |
|---|---|---|---|
| `code/01-clean.R` | `data/raw/survey.csv` | `data/cleaned/analytic_sample.csv` | Sample construction and variable coding |
| `code/02-descriptives.R` | `data/cleaned/analytic_sample.csv` | `output/tables/table1.html` | Table 1 descriptive statistics |
| `code/03-main-models.R` | `data/cleaned/analytic_sample.csv` | `output/tables/table2.html`, `output/figures/fig1.pdf` | Main regression results |
| `code/04-robustness.R` | `data/cleaned/analytic_sample.csv` | `output/tables/tableA1-A3.html` | Robustness checks (Appendix) |

## 6. Instructions for Replicators
\`\`\`bash
# Step 1: Install dependencies
Rscript -e "renv::restore()"
# Step 2: Run all analyses
Rscript code/run_all.R
# Or run individual scripts in order: 01 → 02 → 03 → 04
\`\`\`

## 7. List of Tables and Figures
| Exhibit | Script | Output File | Notes |
|---|---|---|---|
| Table 1 | `02-descriptives.R` | `output/tables/table1.html` | |
| Table 2 | `03-main-models.R` | `output/tables/table2.html` | Main results |
| Figure 1 | `03-main-models.R` | `output/figures/fig1.pdf` | Coefficient plot |

## 8. References
Cite data sources, software packages, and computational methods used.

## 9. Appendix: Reproducibility Verification
- [ ] All scripts run without error on a clean environment
- [ ] Output files match published tables/figures within rounding tolerance (±0.001 for coefficients)
- [ ] Random seed produces identical results across runs
- [ ] No hardcoded file paths (all paths relative to project root)
```

**Additional detail guidance for each section** (populate from project state):

**Section 1 — Overview**

```markdown
# Replication Package for "[PAPER TITLE]"

**Authors**: [names with ORCID links]
**Journal**: [target journal]
**Date**: [YYYY-MM-DD]

## Overview

This package contains the data and code necessary to reproduce all tables,
figures, and in-text statistics reported in "[PAPER TITLE]" published in
[JOURNAL] ([YEAR]).

**Estimated total runtime**: [N] minutes on a [spec] machine
**Last successfully run**: [date] on [OS, R version]
```

**Section 2 — Data Availability and Provenance Statements**

For each data source used:

```markdown
## Data Availability and Provenance Statements

### [Dataset 1 Name]
- **Source**: [organization / URL]
- **How obtained**: [downloaded / applied / purchased / collected]
- **Date accessed**: [date]
- **Registration required**: [yes/no — details]
- **Cost**: [free / fee amount]
- **Redistribution rights**: [can redistribute / cannot — access instructions]
- **Format**: [CSV / DTA / RDS / Parquet]
- **Citation**: [full citation for dataset]
```

**Section 3 — Dataset List**

```markdown
## Dataset List

| File | Source | Format | Rows x Cols | Provided | Notes |
|------|--------|--------|-------------|----------|-------|
| `data/raw/main_data.csv` | [source] | CSV | N x K | Yes | Main analytic dataset |
| `data/raw/supplementary.csv` | [source] | CSV | N x K | Yes | Supplementary variables |
| `data/raw/mock_data.csv` | Synthetic | CSV | N x K | Yes | For code testing only |
```

**Section 4 — Computational Requirements**

```markdown
## Computational Requirements

### Software
- R version [X.Y.Z] (packages listed in `renv.lock`)
- Key packages: [list top 5-10 with versions]

### Hardware
- **OS tested**: [macOS / Linux / Windows]
- **RAM**: [minimum required] GB
- **Disk**: [space needed] GB
- **GPU**: [not required / model + VRAM if applicable]

### Runtime
| Script | Estimated runtime |
|--------|------------------|
| `01_clean_data.R` | [N] min |
| `02_construct_sample.R` | [N] min |
| `03_main_analysis.R` | [N] min |
| `04_robustness_checks.R` | [N] min |
| `05_generate_figures.R` | [N] min |
| **Total** | **[N] min** |

### Controlled Randomness
| Script | Seed value | Purpose |
|--------|-----------|---------|
| `03_main_analysis.R` | `set.seed(42)` | Bootstrap SEs |
| `04_robustness_checks.R` | `set.seed(123)` | MICE imputation |
```

**Section 5 — Description of Programs**

```markdown
## Description of Programs

Scripts are numbered in execution order. Run `code/00_master.R` to execute
the full pipeline, or run scripts individually:

| Script | Description | Inputs | Outputs |
|--------|------------|--------|---------|
| `00_master.R` | Runs all scripts in sequence | — | — |
| `01_clean_data.R` | Loads raw data, applies exclusions, recodes | `data/raw/` | `data/processed/clean.rds` |
| `02_construct_sample.R` | Builds analytic sample, merges datasets | `data/processed/clean.rds` | `data/processed/analytic.rds` |
| `03_main_analysis.R` | Tables 1-3: descriptives + main models | `data/processed/analytic.rds` | `output/tables/table1-3.*` |
| `04_robustness_checks.R` | Appendix tables: robustness + sensitivity | `data/processed/analytic.rds` | `output/tables/tableA1-A3.*` |
| `05_generate_figures.R` | Figures 1-3: main visualizations | `data/processed/analytic.rds` | `output/figures/fig1-3.*` |
```

**Section 6 — Instructions to Replicators**

```markdown
## Instructions to Replicators

### Quick start (recommended)
```
```bash
# 1. Clone or download this package
git clone [URL] && cd replication-package

# 2. Restore R environment
Rscript -e "renv::restore()"

# 3. Configure data paths (if using restricted data)
# Edit code/00_config.R to set DATA_DIR

# 4. Run the full pipeline
Rscript code/00_master.R
# OR
make all
```
```

### Using Docker (if Dockerfile provided)
```
```bash
docker build -t replication .
docker run --rm -v $(pwd)/output:/replication/output replication
```
```

### Step-by-step
1. Install R [version] from https://cran.r-project.org/
2. Open R in the `replication-package/` directory
3. Run `renv::restore()` to install all packages
4. [If restricted data: describe how to place data files]
5. Run `source("code/00_master.R")`
6. Compare outputs in `output/` against published tables/figures
```

**Section 7 — Output Correspondence Table**

If an **Artifact Registry** file exists (from `scholar-write`), use it as the authoritative mapping of table/figure numbers to output files. Otherwise, build the table manually from script inspection.

```markdown
## Output Correspondence Table

### Main Tables and Figures

| Paper element | Script | Output file | Formats |
|--------------|--------|-------------|---------|
| Table 1: Descriptive statistics | `03_main_analysis.R` | `output/tables/table1-descriptives.*` | HTML, TeX, docx |
| Table 2: Main regression results | `03_main_analysis.R` | `output/tables/table2-regression.*` | HTML, TeX, docx |
| Table 3: Marginal effects | `03_main_analysis.R` | `output/tables/table3-ame.*` | HTML, TeX, docx |
| Figure 1: Distribution of outcome | `05_generate_figures.R` | `output/figures/fig1-distribution.pdf` | PDF |
| Figure 2: Coefficient plot | `05_generate_figures.R` | `output/figures/fig2-coef-plot.pdf` | PDF |

### Appendix / EDA Outputs

| Paper element | Script | Output file | Formats |
|--------------|--------|-------------|---------|
| Appendix Table A1: Robustness | `04_robustness_checks.R` | `output/tables/tableA1-robustness.*` | HTML, TeX, docx |
| Appendix Table A2: Sample descriptives (Table 1) | `scholar-eda` pipeline | `output/eda/tables/table1-*.html` | HTML |
| Appendix Figure A1: Missing data pattern | `scholar-eda` pipeline | `output/eda/figures/missing-*.pdf` | PDF |

### In-text Statistics

| Statistic | Script | Location |
|-----------|--------|----------|
| "N = [X]" (p. [Y]) | `03_main_analysis.R` | Console output line [N] |
```

**Section 8 — Known Limitations**

```markdown
## Known Limitations

- [If applicable: stochastic results — bootstrap/MCMC may produce slightly different point estimates across runs; reported estimates used seed [X]]
- [If applicable: restricted data — mock dataset included for code review; published results require access to [dataset]]
- [If applicable: long runtime — script [X] takes [N] hours on [hardware]; consider running overnight]
- [If applicable: platform dependency — tested on [OS]; [specific package] may behave differently on Windows]
```

**Section 9 — References & Contact**

```markdown
## References

[Full citation for the paper]
[Citations for key datasets]
[Citations for key software packages]

## Contact

[Author name] — [email] — [institutional affiliation]
For questions about the code, please open an issue on the GitHub repository.
```

### 2b. Data codebook

Generate `replication-package/data/codebook/codebook.md`:

If data is available on disk, generate the codebook automatically:

```r
library(skimr)
library(labelled)

df <- readRDS("data/processed/analytic.rds")

# Variable dictionary
codebook <- data.frame(
  variable = names(df),
  label = sapply(names(df), function(v) {
    lbl <- var_label(df[[v]])
    if (is.null(lbl)) return("—")
    lbl
  }),
  type = sapply(df, class),
  n_missing = sapply(df, function(x) sum(is.na(x))),
  pct_missing = sprintf("%.1f%%", sapply(df, function(x) mean(is.na(x)) * 100)),
  unique_values = sapply(df, function(x) length(unique(x))),
  example = sapply(df, function(x) paste(head(unique(x), 3), collapse = ", "))
)
```

If no data is available, generate a codebook template:

```markdown
# Codebook

## Variable Dictionary

| Variable | Label | Type | Values | Source | Missingness |
|----------|-------|------|--------|--------|-------------|
| [var1] | [description] | [numeric/factor/character] | [range or levels] | [dataset] | [N (pct)] |
```

### 2c. Computational requirements document

Generate a standalone `replication-package/COMPUTATIONAL-REQUIREMENTS.md` (supplements the README Section 4):

```markdown
# Computational Requirements

## System Configuration (tested)
- **OS**: [macOS 14.x / Ubuntu 22.04 / Windows 11]
- **R version**: [4.4.0]
- **Python version**: [3.11.x] (if applicable)

## Package Versions
[Extract from renv.lock or requirements.txt — list all packages with exact versions]

## Hardware Requirements
- **RAM**: [minimum] GB (peak usage in script [X])
- **Disk**: [total package size] + [space for outputs]
- **CPU**: [any / multicore recommended for script X]
- **GPU**: [not required / NVIDIA with CUDA X.Y and N GB VRAM]

## Random Seeds
| Script | Line | Seed | Purpose |
|--------|------|------|---------|
| [script] | [line number] | [seed value] | [what is randomized] |

## Runtime Estimates
| Script | Wall clock (M1 Mac) | Wall clock (Linux server) |
|--------|---------------------|--------------------------|
| [script] | [time] | [time] |

## Known Platform Dependencies
- [Any OS-specific notes]
- [Any package installation issues on specific platforms]
```

### 2d. Dependency graph

Generate a textual dependency graph of script execution order:

```markdown
# Script Dependency Graph

## Execution Order (DAG)

```
[raw data files]
    │
    ▼
01_clean_data.R ──► data/processed/clean.rds
    │
    ▼
02_construct_sample.R ──► data/processed/analytic.rds
    │
    ├──────────────────────┐
    ▼                      ▼
03_main_analysis.R     04_robustness_checks.R
    │                      │
    ▼                      ▼
output/tables/         output/tables/
table1-3.*             tableA1-A3.*
    │
    ▼
05_generate_figures.R ──► output/figures/fig1-3.*
```

## Input-Output Mapping

| Script | Reads | Writes |
|--------|-------|--------|
| `01_clean_data.R` | `data/raw/*.csv` | `data/processed/clean.rds` |
| `02_construct_sample.R` | `data/processed/clean.rds` | `data/processed/analytic.rds` |
| ... | ... | ... |
```

Also generate a pre-flight input checker script (`code/utils/check_inputs.R`):

```r
# check_inputs.R — Verify all expected input files exist before running pipeline
expected_files <- c(
  "data/raw/main_data.csv",
  "data/processed/clean.rds",
  "data/processed/analytic.rds"
)

missing <- expected_files[!file.exists(expected_files)]
if (length(missing) > 0) {
  cat("ERROR: Missing input files:\n")
  cat(paste(" -", missing), sep = "\n")
  stop("Cannot proceed. See data/README.md for data access instructions.")
} else {
  cat("All expected input files present.\n")
}
```

**Document deliverables:**
- `replication-package/README.md` — comprehensive 9-section AEA-template README
- `replication-package/data/codebook/codebook.md` — variable dictionary
- `replication-package/COMPUTATIONAL-REQUIREMENTS.md` — system + hardware + seeds
- Dependency graph embedded in README or as separate file

---

## Step 3: TEST — Clean-Run Validation

The most critical step — actually testing that the package reproduces results.

### 3a. Pre-flight checks

Run all checks via Bash:

**Check 1 — File existence:**
```bash
# Verify all files referenced in README exist
echo "=== File existence check ==="
while IFS= read -r f; do
  if [ ! -f "replication-package/$f" ]; then
    echo "MISSING: $f"
  fi
done < <(grep -oP '`[^`]+\.(R|py|csv|rds|dta|txt)`' replication-package/README.md | tr -d '`')
```

**Check 2 — Syntax validation:**
```bash
# R scripts: parse without executing
echo "=== Syntax check ==="
for f in replication-package/code/*.R; do
  Rscript -e "parse('$f')" 2>&1 && echo "PASS: $f" || echo "FAIL: $f"
done

# Python scripts: compile check
for f in replication-package/code/*.py; do
  python -m py_compile "$f" 2>&1 && echo "PASS: $f" || echo "FAIL: $f"
done
```

**Check 3 — No absolute paths:**
```bash
echo "=== Absolute path check ==="
grep -rn '/Users\|/home\|C:\\\\' replication-package/code/ && echo "FAIL: absolute paths found" || echo "PASS: no absolute paths"
```

**Check 4 — Script headers:**
```bash
echo "=== Script header check ==="
for f in replication-package/code/*.R; do
  head -5 "$f" | grep -q "^#" && echo "PASS: $f has header" || echo "WARN: $f missing header comment"
done
```

**Check 5 — Random seeds:**
```bash
echo "=== Random seed check ==="
for f in replication-package/code/*.R; do
  if grep -q "sample\|boot\|mice\|mcmc\|rnorm\|rbinom\|runif" "$f"; then
    grep -q "set.seed" "$f" && echo "PASS: $f has seed" || echo "WARN: $f uses randomness but no set.seed()"
  fi
done
```

**Check 6 — README completeness:**
```bash
echo "=== README section check ==="
for section in "Overview" "Data Availability" "Dataset List" "Computational Requirements" "Description of Programs" "Instructions to Replicators" "Output Correspondence" "Known Limitations" "References"; do
  grep -q "$section" replication-package/README.md && echo "PASS: $section" || echo "MISSING: $section"
done
```

### 3b. Environment isolation test

Test that the environment can be restored from the lockfile:

**Option A — renv (R projects):**
```bash
echo "=== renv restore test ==="
mkdir -p test-run
cp -r replication-package/ test-run/replication-package/
cd test-run/replication-package
Rscript -e "renv::restore()" 2>&1 | tee ../renv-restore-log.txt
RESTORE_STATUS=$?
cd ../..
echo "renv restore exit code: $RESTORE_STATUS"
```

**Option B — conda (Python projects):**
```bash
echo "=== conda restore test ==="
conda env create -f replication-package/environment.yml -n repl-test 2>&1 | tee test-run/conda-restore-log.txt
RESTORE_STATUS=$?
echo "conda restore exit code: $RESTORE_STATUS"
```

**Option C — Docker:**
```bash
echo "=== Docker build test ==="
cd replication-package
docker build -t repl-test . 2>&1 | tee ../test-run/docker-build-log.txt
BUILD_STATUS=$?
cd ..
echo "Docker build exit code: $BUILD_STATUS"
```

Report: environment restored? All packages installed? Any errors?

### 3c. Execution test

Run the master script and capture results:

```bash
echo "=== Execution test ==="
cd test-run/replication-package

# Time each script individually
for script in code/[0-9]*.R; do
  echo "--- Running $script ---"
  START=$(date +%s)
  Rscript "$script" > "../log_$(basename $script .R).txt" 2>&1
  STATUS=$?
  END=$(date +%s)
  RUNTIME=$((END - START))
  echo "$script: exit=$STATUS, runtime=${RUNTIME}s" >> "../execution-summary.txt"
done

cd ../..
```

For Python:
```bash
for script in code/[0-9]*.py; do
  echo "--- Running $script ---"
  START=$(date +%s)
  python "$script" > "../log_$(basename $script .py).txt" 2>&1
  STATUS=$?
  END=$(date +%s)
  RUNTIME=$((END - START))
  echo "$script: exit=$STATUS, runtime=${RUNTIME}s" >> "../execution-summary.txt"
done
```

### 3d. Output comparison

Compare reproduced outputs against original outputs (main pipeline AND EDA pipeline):

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "=== Output comparison ==="

# Tables: diff reproduced vs. original (main + EDA)
for dir_pair in "${OUTPUT_ROOT}/tables:test-run/replication-package/output/tables" \
                "${OUTPUT_ROOT}/eda/tables:test-run/replication-package/output/eda/tables"; do
  orig_dir="${dir_pair%%:*}"
  repro_dir="${dir_pair##*:}"
  [ -d "$orig_dir" ] || continue
  echo "--- Comparing $orig_dir ---"
  for orig in "$orig_dir"/*; do
    [ -f "$orig" ] || continue
    fname=$(basename "$orig")
    repro="$repro_dir/$fname"
    if [ -f "$repro" ]; then
      if diff -q "$orig" "$repro" > /dev/null 2>&1; then
        echo "MATCH: $fname"
      else
        echo "MISMATCH: $fname"
        diff "$orig" "$repro" | head -20
      fi
    else
      echo "MISSING: $fname not reproduced"
    fi
  done
done

# Figures: check existence and reasonable file size (main + EDA)
for dir_pair in "${OUTPUT_ROOT}/figures:test-run/replication-package/output/figures" \
                "${OUTPUT_ROOT}/eda/figures:test-run/replication-package/output/eda/figures"; do
  orig_dir="${dir_pair%%:*}"
  repro_dir="${dir_pair##*:}"
  [ -d "$orig_dir" ] || continue
  echo "--- Comparing $orig_dir ---"
  for orig in "$orig_dir"/*; do
    [ -f "$orig" ] || continue
    fname=$(basename "$orig")
    repro="$repro_dir/$fname"
    if [ -f "$repro" ]; then
      orig_size=$(stat -f%z "$orig" 2>/dev/null || stat -c%s "$orig")
      repro_size=$(stat -f%z "$repro" 2>/dev/null || stat -c%s "$repro")
      ratio=$(echo "scale=2; $repro_size / $orig_size" | bc)
      echo "PRESENT: $fname (size ratio: ${ratio}x)"
    else
    echo "MISSING: $fname not reproduced"
    fi
  done
done
```

### Numerical Reproducibility Tolerances

Use the following tolerances when comparing reproduced outputs against published results:

| Quantity | Tolerance | Notes |
|---|---|---|
| Regression coefficients | +/-0.001 | Due to floating-point precision |
| Standard errors | +/-0.002 | Sensitive to optimization convergence |
| P-values | +/-0.005 | Especially near thresholds (0.05, 0.01) |
| Confidence intervals | +/-0.005 | |
| Bootstrap results | +/-0.05 | Set seed; report B= |
| MCMC/Bayesian | +/-0.01 | Set seed; report chains, iterations, warmup |
| Figures | Visual match | Exact pixel match not required; key patterns must be identical |

When comparing outputs in Step 3d, apply these tolerances rather than requiring exact binary matches. Flag any discrepancy that exceeds these thresholds as a reproducibility failure requiring investigation.

### 3e. Test report

Generate `replication-package/TEST-REPORT.md`:

```markdown
# Clean-Run Test Report

**Date**: [YYYY-MM-DD]
**Tester**: [automated / name]
**Environment**: [OS, R version, hardware]

## Pre-flight Checks

| Check | Status |
|-------|--------|
| All referenced files exist | [PASS/FAIL: N missing] |
| All scripts parse without errors | [PASS/FAIL: N failures] |
| No absolute paths | [PASS/FAIL] |
| All scripts have headers | [PASS/WARN: N missing] |
| Random seeds set where needed | [PASS/WARN: N missing] |
| README has all 9 sections | [PASS/FAIL: N missing] |

## Environment Restoration

| Method | Status | Notes |
|--------|--------|-------|
| [renv/conda/Docker] | [SUCCESS/FAIL] | [any errors] |

## Script Execution

| Script | Status | Runtime | Output files |
|--------|--------|---------|-------------|
| `01_clean_data.R` | [PASS/FAIL] | [N] sec | [list] |
| `02_construct_sample.R` | [PASS/FAIL] | [N] sec | [list] |
| `03_main_analysis.R` | [PASS/FAIL] | [N] sec | [list] |
| `04_robustness_checks.R` | [PASS/FAIL] | [N] sec | [list] |
| `05_generate_figures.R` | [PASS/FAIL] | [N] sec | [list] |
| **Total** | | **[N] sec** | |

## Output Comparison

| Output | Status | Notes |
|--------|--------|-------|
| Table 1 | [MATCH/MISMATCH/MISSING] | [details] |
| Table 2 | [MATCH/MISMATCH/MISSING] | [details] |
| Figure 1 | [PRESENT/MISSING] | [size: N KB] |

## Overall Verdict

**[PASS]** — All scripts completed without errors; all outputs reproduced.
**[PARTIAL]** — Scripts completed but [N] output mismatches detected.
**[FAIL]** — [N] scripts failed; see execution log for details.

## Remediation Notes

- [If any failures: specific guidance on what to fix]
```

---

## Step 4: VERIFY — Paper-to-Code Correspondence

### 4a. Extract paper claims

**Step 4a.1 — Consume Artifact Registry (if available):**

If an artifact registry exists (generated by `scholar-write`), use it as the **authoritative source of truth** for table/figure numbering. This registry maps every pipeline-generated artifact to its paper number and source file:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# Check for artifact registry
ARTIFACT_REG=""
for candidate in replication-package/output/artifact-registry.md "${OUTPUT_ROOT}/manuscript/artifact-registry.md" "${OUTPUT_ROOT}/artifact-registry.md"; do
  if [ -f "$candidate" ]; then
    ARTIFACT_REG="$candidate"
    echo "=== Artifact Registry found: $candidate ==="
    cat "$candidate"
    break
  fi
done

if [ -z "$ARTIFACT_REG" ]; then
  echo "WARN: No artifact registry found — building claims inventory from manuscript text"
fi
```

**Step 4a.2 — Extract table/figure references from manuscript:**

Parse the manuscript file (`.md`, `.tex`, or `.docx`) to build an inventory of all claims that require code support:

**Tables:**
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# Extract table references from manuscript
grep -oP 'Table\s+\d+' "${OUTPUT_ROOT}/manuscript/"*.md | sort -u
grep -oP 'Table\s+[A-Z]\d+' "${OUTPUT_ROOT}/manuscript/"*.md | sort -u  # Appendix tables
```

**Figures:**
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
grep -oP 'Figure\s+\d+' "${OUTPUT_ROOT}/manuscript/"*.md | sort -u
grep -oP 'Figure\s+[A-Z]\d+' "${OUTPUT_ROOT}/manuscript/"*.md | sort -u  # Appendix figures
```

**Placement markers** (from `scholar-write` artifact integration):
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# Extract placement markers — these indicate where tables/figures appear in the manuscript
grep -oP '\[Table \d+ about here\]' "${OUTPUT_ROOT}/manuscript/"*.md | sort -u
grep -oP '\[Figure \d+ about here\]' "${OUTPUT_ROOT}/manuscript/"*.md | sort -u
grep -oP '\[Appendix Table [A-Z]\d+ about here\]' "${OUTPUT_ROOT}/manuscript/"*.md | sort -u
grep -oP '\[Appendix Figure [A-Z]\d+ about here\]' "${OUTPUT_ROOT}/manuscript/"*.md | sort -u
```

**In-text statistics:** Search for patterns like:
- Coefficients: `β = 0.XX`, `b = X.XX`, `OR = X.XX`, `HR = X.XX`
- P-values: `p < 0.XX`, `p = 0.XX`
- Sample sizes: `N = X,XXX`, `n = X,XXX`
- Effect sizes: `d = X.XX`, `η² = X.XX`, `AME = X.XX`
- Percentages: `XX.X%` in results context
- Confidence intervals: `95% CI [X.XX, X.XX]`

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# Extract in-text statistics
grep -oP '(β|b|OR|HR|AME|RR)\s*=\s*[-−]?\d+\.\d+' "${OUTPUT_ROOT}/manuscript/"*.md
grep -oP '[Nn]\s*=\s*[\d,]+' "${OUTPUT_ROOT}/manuscript/"*.md
grep -oP 'p\s*[<=]\s*0\.\d+' "${OUTPUT_ROOT}/manuscript/"*.md
grep -oP '\d+\.\d+%' "${OUTPUT_ROOT}/manuscript/"*.md
```

Build a claims inventory table:

```markdown
| # | Claim type | Paper element | Location | Value |
|---|-----------|---------------|----------|-------|
| 1 | Table | Table 1 | p. 12 | Descriptive statistics |
| 2 | Table | Table 2 | p. 15 | Main regression results |
| 3 | Figure | Figure 1 | p. 18 | Distribution of outcome |
| 4 | Statistic | β coefficient | p. 16 | β = 0.34, p < 0.01 |
| 5 | Statistic | Sample size | p. 11 | N = 4,200 |
```

### 4b. Map claims to scripts

Cross-reference the claims inventory against:
1. `${OUTPUT_ROOT}/scripts/script-index.md` — paper-element correspondence from scholar-analyze/compute
2. `replication-package/README.md` Section 7 — output correspondence table
3. Script comments and output filenames

For each claim, identify:
- **Producing script**: which script generates this result
- **Output file**: which file contains the reproduced output
- **Specific location**: line number or section in the script

Assign mapping status:

| Status | Definition |
|--------|-----------|
| **MAPPED** | Script identified, output file exists, result matches |
| **PARTIAL** | Script exists but doesn't clearly produce this specific number |
| **UNMAPPED** | No script found that produces this claim |
| **SUPPLEMENT** | Maps to supplementary materials, not main code |

### 4c. Completeness audit

Check coverage systematically:

```markdown
## Completeness Audit

### Tables
| Table | Script | Output file | Status |
|-------|--------|-------------|--------|
| Table 1 | 03_main_analysis.R:L45 | output/tables/table1.html | MAPPED |
| Table 2 | 03_main_analysis.R:L89 | output/tables/table2.html | MAPPED |
| Table A1 | 04_robustness.R:L12 | output/tables/tableA1.html | MAPPED |

### Figures
| Figure | Script | Output file | Status |
|--------|--------|-------------|--------|
| Figure 1 | 05_figures.R:L20 | output/figures/fig1.pdf | MAPPED |

### In-text Statistics
| Statistic | Script | Line | Status |
|-----------|--------|------|--------|
| N = 4,200 | 02_construct.R:L55 | Console output | MAPPED |
| β = 0.34 | 03_main_analysis.R:L92 | Table 2, row 1 | MAPPED |

### EDA / Appendix Outputs
| Output | Script | Output file | Status |
|--------|--------|-------------|--------|
| Table 1 (descriptives) | scholar-eda pipeline | output/eda/tables/table1-*.html | MAPPED |
| Missing data figure | scholar-eda pipeline | output/eda/figures/missing-*.pdf | MAPPED |

### Artifact Registry Cross-Check (if registry exists)
| Registry entry | Output file exists? | Referenced in manuscript? | Status |
|---------------|--------------------|--------------------------|---------
| [artifact name] | [yes/no] | [yes/no — cite location] | [MAPPED/MISSING/ORPHAN] |

> **ORPHAN** = artifact file exists but is not referenced in the manuscript.
> **MISSING** = referenced in manuscript but no corresponding output file found.

### Decision Log Coverage
| Decision | Documented in DECISIONS.md? |
|----------|----------------------------|
| Sample restriction | Yes |
| Missing data treatment | Yes |
| Standard error specification | Yes |
```

### 4d. Verification report

Generate `replication-package/VERIFICATION-REPORT.md`:

```markdown
# Paper-to-Code Correspondence Report

**Paper**: [TITLE]
**Date**: [YYYY-MM-DD]

## Summary

| Category | Total | Mapped | Partial | Unmapped |
|----------|-------|--------|---------|----------|
| Main tables | [N] | [N] | [N] | [N] |
| Main figures | [N] | [N] | [N] | [N] |
| EDA tables | [N] | [N] | [N] | [N] |
| EDA figures | [N] | [N] | [N] | [N] |
| In-text statistics | [N] | [N] | [N] | [N] |
| Appendix items | [N] | [N] | [N] | [N] |
| **Overall** | **[N]** | **[N]** | **[N]** | **[N]** |

**Artifact Registry status**: [consumed / not found]
**Orphan artifacts** (file exists, not referenced in paper): [N]

**Completeness score**: [N/M] = [XX%]

## Detailed Mapping

[Full claims inventory table with mapping status — see 4c above]

## Unmapped Items

[List of any claims without corresponding scripts, with recommendations]

| # | Claim | Recommendation |
|---|-------|----------------|
| [N] | [description] | [add script / document source / mark as external] |

## Decision Log Completeness

[N/M] key analytic decisions documented in DECISIONS.md.
Missing: [list any undocumented decisions]
```

---

## Step 5: ARCHIVE — Repository Deposit & DOI

### 5a. Pre-deposit cleanup

```bash
echo "=== Pre-deposit cleanup ==="

# Remove test artifacts
rm -rf test-run/
rm -f replication-package/**/.DS_Store
rm -rf replication-package/**/__pycache__
rm -f replication-package/**/.Rhistory
rm -f replication-package/**/.RData

# Check .gitignore
if [ ! -f replication-package/.gitignore ]; then
  cat > replication-package/.gitignore << 'EOF'
# OS files
.DS_Store
Thumbs.db

# R
.Rhistory
.RData
.Rproj.user/

# Python
__pycache__/
*.pyc
.ipynb_checkpoints/

# Environment (tracked via lockfile)
renv/library/
.venv/

# Sensitive data (never commit)
data/raw/restricted_*
data/raw/*_restricted*
*.key
*.pem
EOF
fi

# Report package size
echo "Total package size:"
du -sh replication-package/
echo ""
echo "Largest files:"
find replication-package/ -type f -exec du -h {} + | sort -rh | head -10
```

Warn if total size exceeds common limits:
- GitHub: 100 MB per file, 1 GB recommended max
- Zenodo: 50 GB
- Harvard Dataverse: 2.5 GB per file
- ICPSR: 30 GB

### 5b. Repository selection guide

| Journal | Recommended repository | Alternative | Notes |
|---------|----------------------|-------------|-------|
| ASR, AJS | AJS Dataverse / Zenodo | Harvard Dataverse | AJS has its own Dataverse |
| Demography | Zenodo / Harvard Dataverse | ICPSR | |
| Science Advances | Zenodo + CodeOcean | Dryad | Requires DOI for data |
| NHB | Zenodo | figshare | Nature recommends Zenodo |
| NCS | Zenodo + CodeOcean | GitHub + Zenodo | Computational reproducibility required |
| APSR | Harvard Dataverse | ICPSR | APSR requires Dataverse |
| AJPS | AJPS Dataverse | Harvard Dataverse | AJPS has its own Dataverse |
| AEA journals | openICPSR | — | AEA requires openICPSR |
| General | Zenodo | Harvard Dataverse | Free, DOI minting, GitHub integration |

Decision tree:
- Public data + code → **Zenodo** (free, DOI, GitHub webhook)
- Restricted data → **ICPSR** (controlled access + DUA support)
- Qualitative data → **QDR** (de-identification + restricted access)
- Computational + models → **Zenodo + HuggingFace Hub**
- Journal-specific requirement → follow journal policy (see table)

### 5c. GitHub release preparation

```bash
echo "=== GitHub release preparation ==="

# Initialize git if not already
cd replication-package
git init 2>/dev/null
git add -A
git commit -m "Initial replication package release (v1.0.0)"

# Tag release
git tag -a v1.0.0 -m "Replication package for [PAPER TITLE]"

echo ""
echo "Next steps (manual):"
echo "1. Create GitHub repository: gh repo create [name] --public"
echo "2. Push: git remote add origin [URL] && git push -u origin main --tags"
echo "3. Enable Zenodo webhook at https://zenodo.org/account/settings/github/"
echo "4. Create release on GitHub — Zenodo will auto-mint a DOI"
echo "5. Add DOI badge to README.md"
```

Zenodo badge template:
```markdown
[![DOI](https://zenodo.org/badge/DOI/[DOI].svg)](https://doi.org/[DOI])
```

### 5d. Deposit metadata template

Generate `replication-package/DEPOSIT-METADATA.md`:

```markdown
# Repository Deposit Metadata

**Title**: Replication Data and Code for: "[PAPER TITLE]"

**Authors**:
- [Name 1], [Affiliation], ORCID: [ORCID]
- [Name 2], [Affiliation], ORCID: [ORCID]

**Abstract**: This replication package contains the data and code necessary to reproduce all results reported in "[PAPER TITLE]" published in [JOURNAL] ([YEAR]). The package includes [N] R/Python scripts, [data description], and comprehensive documentation.

**Keywords**: [topic keywords], replication, reproducibility, [method keywords]

**Related publication**:
- DOI: [paper DOI]
- Citation: [full citation]

**License**: MIT (code), CC-BY-4.0 (data and documentation)

**Subject**: Social and Behavioral Sciences > [subfield]

**Date**: [YYYY-MM-DD]

**Version**: 1.0.0

**Language**: English

**Funding**: [grant number if applicable]
```

### 5e. Post-deposit checklist

```markdown
## Post-Deposit Checklist

- [ ] DOI minted and added to:
  - [ ] CITATION.cff (`doi:` field)
  - [ ] README.md (badge + text)
  - [ ] Manuscript data availability statement
  - [ ] Manuscript code availability statement
  - [ ] Cover letter
- [ ] Repository is publicly accessible (or access-controlled for restricted data)
- [ ] Landing page displays correct metadata (title, authors, abstract)
- [ ] Download link works — downloaded package matches uploaded package
- [ ] Version tag matches across GitHub, Zenodo, CITATION.cff
- [ ] All co-authors listed with correct affiliations and ORCIDs
```

---

## Step 6: Save Output

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-replication"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}"*.md 2>/dev/null | head -1)
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

### Version collision avoidance (MANDATORY — run BEFORE every Write tool call)

Run this Bash block before each Write call. It prints `SAVE_PATH=...` — use that exact path in the Write tool's `file_path` parameter. **Re-run this version check with the appropriate BASE for each output file.**

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
BASE="${OUTPUT_ROOT}/replication/replication-report-[slug]-[YYYY-MM-DD]"

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

**Use the printed `SAVE_PATH` as the `file_path` in the Write tool call.** Do NOT hardcode the path. The same `BASE` must be used for pandoc conversions (.docx, .tex, .pdf).

Save 3–4 files via the Write tool:

### File 1: README

```
replication-package/README.md
```
The comprehensive 9-section AEA-template README generated in Step 2a.

### File 2: Internal report

```
${OUTPUT_ROOT}/replication/replication-report-[slug]-[YYYY-MM-DD].md
```

Contents:
- Mode executed (BUILD / DOCUMENT / TEST / VERIFY / ARCHIVE / FULL)
- Artifact inventory from Step 0
- Build summary (files copied, scripts renumbered, data handling strategy)
- Documentation checklist (README sections, codebook, requirements doc)
- Test results summary (pre-flight checks, execution status, output comparison)
- Verification results (claims mapped / unmapped, completeness score)
- Archive status (repository, DOI, post-deposit checklist)
- Quality checklist results (all items)

### File 3: Test report (if TEST mode ran)

```
replication-package/TEST-REPORT.md
```
Clean-run test results from Step 3e.

### File 4: Verification report (if VERIFY mode ran)

```
replication-package/VERIFICATION-REPORT.md
```
Paper-to-code correspondence audit from Step 4d.

---

## Quality Checklist

### Structure (6 items)

- [ ] Directory follows gold-standard layout (`code/`, `data/`, `output/`, README, LICENSE, CITATION.cff)
- [ ] All scripts numbered and named descriptively (`01_clean_data.R`, not `script1.R`)
- [ ] Master controller script (`00_master.R` or `00_master.py`) present and runs all scripts in order
- [ ] Makefile present with dependency-aware targets (`make all`, `make clean`)
- [ ] No absolute paths in any script (all paths relative to project root)
- [ ] All random seeds set and documented in README + COMPUTATIONAL-REQUIREMENTS.md

### Documentation (6 items)

- [ ] README follows AEA Social Science Data Editors template (9 sections present)
- [ ] Data availability statement with per-source provenance (source, access method, cost, redistribution rights)
- [ ] Codebook/variable dictionary for all analytic datasets (`data/codebook/codebook.md`)
- [ ] Computational requirements documented (software versions, hardware, runtime estimates, seeds)
- [ ] Output correspondence table complete (every script → paper element mapping)
- [ ] DECISIONS.md present with key analytic decisions documented (from `coding-decisions-log.md`)

### Testing (5 items)

- [ ] All scripts parse without syntax errors (R: `parse()`; Python: `py_compile`)
- [ ] Environment lockfile present and restorable (`renv.lock` or `environment.yml` or `requirements.txt`)
- [ ] Clean-run test executed: all scripts complete without error in isolated environment
- [ ] Output comparison: reproduced outputs match originals (tables exact; figures present)
- [ ] TEST-REPORT.md documents all test results with per-script status and runtime

### Tables and Figures (5 items)

- [ ] All tables from `output/[slug]/tables/` AND `output/[slug]/eda/tables/` copied to replication package
- [ ] All figures from `output/[slug]/figures/` AND `output/[slug]/eda/figures/` copied to replication package
- [ ] Each table has at least one renderable format (HTML, TeX, or docx)
- [ ] Each figure is in a standard format (PDF, PNG, SVG, EPS)
- [ ] Artifact Registry (from `scholar-write`) consumed if present — all registered items verified in package

### Verification (6 items)

- [ ] Every table in the paper has a producing script (MAPPED status)
- [ ] Every figure in the paper has a producing script (MAPPED status)
- [ ] In-text statistics traceable to scripts (at least 80% mapped)
- [ ] VERIFICATION-REPORT.md with completeness score and unmapped item remediation
- [ ] **scholar-verify completeness check**: If a `scholar-verify` report exists at `output/[slug]/verify/verification-report-*.md`, consume the verify-completeness agent's findings (artifact chain map, orphaned/missing items) and cross-check against the replication package contents. Flag any artifacts listed in the verification report that are missing from the package.
- [ ] **scholar-verify numerics check**: If a `scholar-verify` report exists, consume the verify-numerics agent's findings and confirm that all raw output files flagged with transcription issues have been corrected in the replication package's `output/` directory (i.e., the replication package contains the corrected versions, not the stale ones).

### Archival (4 items)

- [ ] Package deposited in appropriate repository (or deposit instructions generated)
- [ ] DOI minted and cited in manuscript + README + CITATION.cff (or DOI placeholder noted)
- [ ] LICENSE file present with dual license (MIT for code, CC-BY-4.0 for data/docs)
- [ ] `.gitignore` excludes sensitive/temporary files (`.Rhistory`, `.DS_Store`, `__pycache__`, restricted data)

### Journal-Specific Compliance

| Journal | Required | Status |
|---------|----------|--------|
| **ASR / AJS** | Data + code availability statement in manuscript | [ ] |
| **Demography** | Replication package with documented README | [ ] |
| **Science Advances** | Data/code DOI in manuscript; Reporting Summary | [ ] |
| **NHB** | Data/code availability; Nature Reporting Summary | [ ] |
| **NCS** | Full computational reproducibility (Docker recommended); Code Ocean optional | [ ] |
| **APSR** | Harvard Dataverse deposit required | [ ] |
| **AJPS** | AJPS Dataverse deposit; replication code + data or access instructions | [ ] |
| **AEA journals** | openICPSR deposit; AEA README template; pre-acceptance verification | [ ] |

---

## Reference

See `references/replication-standards.md` for:
- Full journal requirements comparison table (9 journals × 6 dimensions)
- Complete AEA Template README
- Common replication failures (from AEA Data Editor experience)
- Clean-run testing protocol (5 levels from Vilhuber)
- Data documentation standards
- Restricted data protocols
- Environment capture reference (renv, conda, Docker, Makefile)
- Dependency graph generation patterns
