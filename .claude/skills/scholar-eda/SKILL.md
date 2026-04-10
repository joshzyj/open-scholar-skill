---
name: scholar-eda
description: Conduct exploratory data analysis (EDA) before hypothesis testing. Run when the user has a dataset and needs to load data, build the analytic sample, diagnose missing data, inspect distributions, visualize relationships, check collinearity, and produce a publication-ready Table 1 and pre-analysis memo. Produces figures (PDF/PNG) and tables (HTML/docx/TeX). Saves output to disk. Works after /scholar-data and before /scholar-analyze.
tools: Read, Bash, Write, Agent
argument-hint: "[dataset path or 'paste data below'] [outcome variable(s)] [optional: key predictor, causal design, journal, panel/cross-sectional]"
user-invocable: true
---

# Scholar Exploratory Data Analysis

You are an expert quantitative social scientist conducting rigorous, reproducible pre-analysis exploration. Your goal: understand the data structure, document every analytic decision transparently, and produce clean code + figures + a pre-analysis memo before any hypothesis test is run.

## Arguments

The user has provided: `$ARGUMENTS`

Parse into:
- **Data input**: file path | pasted/inline data | online source (see Phase 0)
- **Outcome variable(s)** Y
- **Key predictor(s)** X
- **Design keywords**: look for DiD, difference-in-differences, FE, fixed effects, RD, regression discontinuity, IV, instrumental variable, matching, mediation, synthetic control → triggers causal gate
- **Data structure**: cross-sectional | panel/longitudinal | multilevel | survey-weighted
- **Target journal** (optional — affects Table 1 format and reporting standards)

---

## Phase 0: Parse Arguments + Data Loading + Causal Gate

### 0a. Create output directories

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/eda/figures" "${OUTPUT_ROOT}/eda/tables" "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/scripts"
```

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# Initialize script tracking for replication package (if not already created by prior skills)
if [ ! -f "${OUTPUT_ROOT}/scripts/coding-decisions-log.md" ]; then
cat > "${OUTPUT_ROOT}/scripts/coding-decisions-log.md" << 'LOGEOF'
# Analytic Decisions Log

| Timestamp | Step | Decision | Alternatives Considered | Rationale | Variables | Script |
|-----------|------|----------|------------------------|-----------|-----------|--------|
LOGEOF
fi

if [ ! -f "${OUTPUT_ROOT}/scripts/script-index.md" ]; then
cat > "${OUTPUT_ROOT}/scripts/script-index.md" << 'IDXEOF'
# Script Index — Run Order

| Order | Script | Description | Input | Output | Produces |
|-------|--------|-------------|-------|--------|----------|
IDXEOF
fi
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-eda"
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
SKILL_NAME="scholar-eda"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

### 0a-safety. Data Safety Gate (MANDATORY, blocking)

Before any data loading, follow the mandatory gate defined in `.claude/skills/_shared/data-handling-policy.md`. The gate is REQUIRED for Mode 1 (local file) and Mode 2 (pasted data written to a temp file). Mode 3 (online public data fetched by tidycensus/nhanesA/gssr/WDI/URL) may skip the gate.

**Exception:** If invoked from `scholar-full-paper` and `SAFETY_STATUS` is already set in `PROJECT_STATE`, read that status instead of re-running. Never downgrade (LOCAL_MODE → CLEARED is forbidden).

```bash
# ── Step 0a-safety: Safety Gate ──
# See _shared/data-handling-policy.md §1-§2 for the full spec.
GATE_SCRIPT="${SCHOLAR_SKILL_DIR:-.}/scripts/gates/safety-scan.sh"
for FILE in [DATA_FILE_PATHS]; do
  [ -f "$FILE" ] || { echo "missing: $FILE"; continue; }
  bash "$GATE_SCRIPT" "$FILE"
  echo "gate exit: $?  file: $FILE"
done
```

Set `SAFETY_STATUS` ∈ {`CLEARED`, `LOCAL_MODE`, `ANONYMIZED`, `OVERRIDE`, `HALTED`} per the state machine. Present gate results to the user and **wait for their selection** when the gate is YELLOW or RED. Log the outcome to the process log.

Downstream branching in Phase 0b and all of Phases 1–7:
- `SAFETY_STATUS ∈ {CLEARED, ANONYMIZED, OVERRIDE}` → use the in-context loader (Mode 1a below).
- `SAFETY_STATUS = LOCAL_MODE` → use the Bash-only loader (Mode 1b below); every subsequent phase must wrap its analysis in a single `Rscript -e "..."` or `python3 - << 'PY'` heredoc, emit summary-only output, and suppress small cells (n<10).
- `SAFETY_STATUS = HALTED` → stop the skill.

When this skill invokes `/scholar-causal` or `/scholar-analyze`, pass `SAFETY_STATUS` forward so the sub-skill inherits the constraint.

### 0b. Detect data input mode

#### Mode 1 — Local file (CSV, .dta, .rds, .parquet, .xlsx)

**Mode 1a — CLEARED / ANONYMIZED / OVERRIDE (standard in-context loader):**
```r
library(haven); library(readr); library(arrow); library(readxl)

# Auto-detect format and load. Mirrors policy §3a — keep in sync.
ext <- tolower(tools::file_ext("path/to/data.ext"))
df <- switch(ext,
  "csv"     = readr::read_csv("path/to/data.csv", show_col_types = FALSE),
  "tsv"     = readr::read_tsv("path/to/data.tsv", show_col_types = FALSE),
  "dta"     = haven::read_dta("path/to/data.dta"),
  "sav"     = haven::read_sav("path/to/data.sav"),
  "rds"     = readRDS("path/to/data.rds"),
  "rdata"   = { e <- new.env(); load("path/to/data.RData", envir = e); as.list(e)[[1]] },
  "parquet" = arrow::read_parquet("path/to/data.parquet"),
  "feather" = arrow::read_feather("path/to/data.feather"),
  "xlsx"    = readxl::read_excel("path/to/data.xlsx"),
  "xls"     = readxl::read_excel("path/to/data.xls"),
  stop("Unsupported format: ", ext)
)
```

**Mode 1b — LOCAL_MODE (Bash-only, summary output only):**

When `SAFETY_STATUS=LOCAL_MODE`, do NOT use the `Read` tool on the data file, do NOT run the Mode 1a loader above in an inline R REPL that prints `head()`, and do NOT call `print(df)` / `df.head()` / `View(df)` / `df[1:5,]`. Wrap the load and all subsequent EDA steps in a single `Rscript -e "..."` (or `python3 -` heredoc) Bash call:

```bash
Rscript -e '
suppressPackageStartupMessages({
  library(tidyverse); library(haven); library(arrow); library(readxl); library(skimr)
})
load_data <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    csv     = readr::read_csv(path, show_col_types = FALSE),
    tsv     = readr::read_tsv(path, show_col_types = FALSE),
    dta     = haven::read_dta(path),
    sav     = haven::read_sav(path),
    rds     = readRDS(path),
    rdata   = { e <- new.env(); load(path, envir = e); as.list(e)[[1]] },
    xlsx    = readxl::read_excel(path),
    xls     = readxl::read_excel(path),
    parquet = arrow::read_parquet(path),
    feather = arrow::read_feather(path),
    stop("Unsupported extension: ", ext)
  )
}
df <- load_data("[DATA_FILE_PATH]")

# Safe summary-only output
cat("N =", nrow(df), "\n")
cat("Variables =", ncol(df), "\n")
cat("Columns:\n", paste(names(df), collapse = ", "), "\n\n")
str(df, list.len = ncol(df), give.attr = FALSE)
cat("\n---- Missingness (%) ----\n")
print(round(colMeans(is.na(df)) * 100, 1))
cat("\n---- skim summary ----\n")
print(skim(df))
# DO NOT call head(df), print(df), View(df), df[1:5,], df.head(), df.sample()
'
```

All Phase 1–7 EDA operations under LOCAL_MODE must be appended to the SAME heredoc and emit summary-level output only (counts, means, SDs, quantiles, correlations, regression coefficients). When building Table 1 or crosstabs, suppress any cell with `n < 10` before printing. Save figures to `output/[slug]/eda/figures/` but do NOT embed them in the conversation — report only the filepath and caption.

**Forbidden under LOCAL_MODE (R and Python):** `head(df)`, `print(df)`, `View(df)`, `df[1:5,]`, `df.head()`, `df.sample()`, `df.iloc[...]`, `df %>% slice(...)`, `df %>% sample_n(...)`, `broom::augment(model)` without aggregation, any per-row output. See `_shared/data-handling-policy.md` §3 rule 4 for the complete list.

#### Mode 2 — Inline / pasted data (user pastes CSV text)

**Mode 2a — CLEARED path:**
```r
df <- readr::read_csv(I("col1,col2,col3\n1,2,3\n4,5,6"))
```

**Mode 2b — LOCAL_MODE path:** Pasted data is already in Claude's context by definition (the user put it in the argument), so `SAFETY_STATUS=LOCAL_MODE` is not meaningful here. Warn the user that pasting sensitive data into the argument already transmits it; offer to write the text to a local temp file, re-run the gate on that file, and then proceed under LOCAL_MODE for all downstream steps.

#### Mode 3 — Online public data (fetch directly; gate may be skipped)
```r
# ACS via tidycensus
library(tidycensus)
df <- get_acs(geography="tract", variables=c("B19013_001","B03002_003"), year=2022, state="CA")

# NHANES via nhanesA
library(nhanesA); df <- nhanes("DEMO_J")

# GSS via gssr
library(gssr); data(gss_all); df <- gss_all

# World Bank via WDI
library(WDI); df <- WDI(indicator=c("NY.GDP.PCAP.KD","SP.POP.TOTL"), start=2000)

# Raw URL
df <- readr::read_csv("https://example.com/data.csv")
```

**Python equivalents (Mode 1a / Mode 3):**
```python
import pandas as pd
df = pd.read_csv("data.csv")       # CSV
df = pd.read_stata("data.dta")     # Stata
df = pd.read_parquet("data.parquet") # Parquet
df = pd.read_excel("data.xlsx")    # Excel
```

### 0c. Causal gate

Scan `$ARGUMENTS` for causal design keywords:
- **Keywords**: DiD, difference-in-differences, fixed effects, FE, regression discontinuity, RD, instrumental variable, IV, matching, synthetic control, mediation, propensity score

If any keyword is detected:
> **CAUSAL GATE TRIGGERED.** This dataset involves a causal identification strategy. Before proceeding with EDA, invoke `/scholar-causal` to:
> - Draw the causal DAG and identify the adjustment set
> - Select the appropriate identification strategy
> - Run strategy-specific diagnostics (pre-trend, McCrary, first-stage F, balance)
> After `/scholar-causal` completes, return here and continue with Phase 1.

If no causal keyword → proceed directly to Phase 1.

### Script Archive Protocol (MANDATORY — for replication package)

Follow the script version control protocol defined in `.claude/skills/_shared/script-version-check.md`. **NEVER overwrite an existing script.**

After EVERY major EDA code block is executed in Steps 1–7, save the complete script to `output/[slug]/scripts/[NN]-[name].R` (or `.py`). Use the EDA numbering range `E01`–`E09`:

| Step | Script prefix | Example filename |
|------|--------------|-----------------|
| Step 1 — Data Loading | `E01` | `${OUTPUT_ROOT}/scripts/E01-load-data.R` |
| Step 2 — Sample Construction | `E02` | `${OUTPUT_ROOT}/scripts/E02-construct-sample.R` |
| Step 3 — Missing Data | `E03` | `${OUTPUT_ROOT}/scripts/E03-missing-data.R` |
| Step 4 — Distributions | `E04` | `${OUTPUT_ROOT}/scripts/E04-distributions.R` |
| Step 5 — Bivariate | `E05` | `${OUTPUT_ROOT}/scripts/E05-bivariate.R` |
| Step 6 — Multicollinearity | `E06` | `${OUTPUT_ROOT}/scripts/E06-collinearity.R` |
| Step 6b — Measurement Validation | `E06b` | `${OUTPUT_ROOT}/scripts/E06b-measurement-validation.R` |
| Step 7 — Table 1 | `E07` | `${OUTPUT_ROOT}/scripts/E07-table1.R` |

**Version-check before EVERY script save** — run this Bash block before the Write tool call:
```bash
# MANDATORY: Replace SCRIPT_NAME with actual (e.g., E01-load-data)
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SCRIPT_NAME="E01-load-data"  # Replace with actual
EXT="R"
SCRIPT_DIR="${OUTPUT_ROOT}/scripts"
mkdir -p "$SCRIPT_DIR"
SCRIPT_BASE="${SCRIPT_DIR}/${SCRIPT_NAME}"
if [ -f "${SCRIPT_BASE}.${EXT}" ]; then
  V=2; while [ -f "${SCRIPT_BASE}-v${V}.${EXT}" ]; do V=$((V + 1)); done
  SCRIPT_BASE="${SCRIPT_BASE}-v${V}"
fi
echo "SCRIPT_PATH=${SCRIPT_BASE}.${EXT}"
```
**Use the printed `SCRIPT_PATH` as `file_path` in the Write tool call.** Shell variables do NOT persist — re-derive in every call. Include a `# Version: vN` and `# Changes:` line in the script header for v2+.

**After each script save**, append a row to `${OUTPUT_ROOT}/scripts/script-index.md` (use the versioned filename):
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "| [order] | E0[N]-[name][-vN].R | [description] | [input file] | [output files] | [Table/Figure produced] |" >> "${OUTPUT_ROOT}/scripts/script-index.md"
```

**After each analytic decision** (e.g., choosing listwise deletion vs. MI, choosing bin widths, sample restrictions), append a row to `${OUTPUT_ROOT}/scripts/coding-decisions-log.md`:
```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "| $(date '+%Y-%m-%d %H:%M') | Step [N] | [decision] | [alternatives] | [rationale] | [variables] | E0[N]-[name][-vN].R |" >> "${OUTPUT_ROOT}/scripts/coding-decisions-log.md"
```

---

## Phase 1: Dataset Orientation

### 1a. First look

```r
library(skimr)
library(dplyr)

dim(df)           # N rows × K columns
skim(df)          # distributions, missing %, histograms in console
glimpse(df)       # variable types + first values
```

```python
df.shape
df.info()
df.describe(include='all').T
df.isnull().sum().sort_values(ascending=False)
```

### 1b. Document the structure

**Record:**
- Unit of analysis (person / household / firm / country-year / dyad)
- Total N; K variables
- Panel structure: `xtset id year` (Stata) or `plm::pdim(pdata)` (R) — balanced or unbalanced?
- Date range / wave structure
- Unique identifiers — are they actually unique?

```r
# Check ID uniqueness
df %>% count(id) %>% filter(n > 1)  # should return 0 rows for cross-sectional

# Panel structure
library(plm)
pdata <- pdata.frame(df, index = c("id", "year"))
pdim(pdata)  # reports: N units, T periods, balanced/unbalanced
```

### 1c. Red flags — flag immediately

```r
# Duplicate rows
sum(duplicated(df))

# Observations outside expected time range or population
range(df$year, na.rm = TRUE)
table(df$country)
```

- [ ] Duplicate rows present → investigate + deduplicate before proceeding
- [ ] ID not unique within units → merge / reshape error upstream
- [ ] Wrong population (wrong year, country, age range) → filter before EDA

---

## Phase 2: Sample Construction

Define the **analytic sample** before any analysis. Every exclusion must be documented with N before and N after.

```r
cat("Starting N:", nrow(df), "\n")

df <- df %>%
  filter(!is.na(outcome))           # (1) drop missing outcome
cat("After dropping missing outcome:", nrow(df), "\n")

df <- df %>%
  filter(age >= 25 & age <= 65)     # (2) restrict to working-age adults
cat("After age restriction:", nrow(df), "\n")

df <- df %>%
  filter(country == "United States") # (3) restrict to target country
cat("After country restriction:", nrow(df), "\n")

# ... continue for each exclusion criterion
cat("Final analytic N:", nrow(df), "\n")
```

**Exclusion flow table (fill in):**

| Step | Criterion | N before | N after | N dropped |
|------|-----------|----------|---------|-----------|
| 0 | Raw data | [N] | — | — |
| 1 | Drop missing outcome | [N] | [N] | [N] |
| 2 | Age restriction | [N] | [N] | [N] |
| … | … | … | … | … |
| Final | Analytic sample | — | **[N]** | — |

**Post-treatment variable check:** For any covariate measured after the treatment/intervention, flag it — including it in the model risks post-treatment bias. Document explicitly.

**Survey weights:** If using a complex survey design (ANES, GSS, ACS, SIPP):
```r
library(survey)
svy_design <- svydesign(ids = ~psu, strata = ~strata, weights = ~weight, data = df, nest = TRUE)
# All subsequent summaries use svymean(), svytable(), svyglm() etc.
```

---

## Phase 3: Missing Data Diagnosis

### 3a. Missingness map

```r
library(naniar)
miss_var_summary(df) %>% arrange(desc(pct_miss))  # % missing per variable
miss_case_summary(df) %>% arrange(desc(pct_miss)) # % missing per row

# Visualize
gg_miss_var(df, show_pct = TRUE)
ggsave(paste0(Sys.getenv("OUTPUT_ROOT", "output"), "/eda/figures/fig-missing-by-var.png"), dpi = 300, width = 7, height = 5)

gg_miss_upset(df)  # co-missingness pattern (which variables are missing together)
ggsave(paste0(Sys.getenv("OUTPUT_ROOT", "output"), "/eda/figures/fig-missing-upset.png"), dpi = 300, width = 8, height = 5)
```

```python
import missingno as msno
import os; _OR = os.environ.get("OUTPUT_ROOT", "output")
msno.matrix(df); plt.savefig(f"{_OR}/eda/figures/fig-missing-matrix.png", dpi=300)
msno.heatmap(df); plt.savefig(f"{_OR}/eda/figures/fig-missing-heatmap.png", dpi=300)
```

### 3b. Diagnose the mechanism

| Mechanism | Description | Implication |
|-----------|-------------|-------------|
| **MCAR** | Missingness unrelated to any observed or unobserved variable | Listwise deletion unbiased |
| **MAR** | Missingness related to observed X but not to unobserved Y | Multiple imputation valid |
| **MNAR** | Missingness related to the unobserved value of the missing variable | Sensitivity analysis required |

```r
# Little's MCAR test (p < .05 → NOT MCAR → proceed to MAR/MNAR assessment)
naniar::mcar_test(df)

# Shadow matrix: does missingness predict itself from observed covariates?
df$miss_y <- as.integer(is.na(df$outcome))
glm(miss_y ~ age + female + education + income, data = df, family = binomial) |> summary()
# Significant predictors → MAR (or MNAR)
```

### 3c. Decision rules

| % Missing on key variable | Action |
|--------------------------|--------|
| < 5% | Listwise deletion acceptable; document |
| 5–20% | Multiple imputation (MICE) preferred; compare with complete-case |
| > 20% | Flag as major limitation; assess MNAR risk; sensitivity analysis required |
| > 50% | Variable likely unusable; consider dropping |

### 3d. Multiple imputation (when MAR assumed)

```r
library(mice)

# m = max(% missing × 100, 20) — e.g., 15% missing → m=20; 30% → m=30
imp <- mice(df, m = 20, seed = 42,
            method = c("pmm",    # continuous
                       "logreg", # binary
                       "polr",   # ordered categorical
                       "polyreg")) # unordered categorical

# Inspect imputed values
densityplot(imp)  # compare observed vs. imputed distributions

# Analyze and pool
fit <- with(imp, lm(outcome ~ predictor + control1 + control2))
summary(pool(fit))
```

**Reporting template:**
> "We used multiple imputation by chained equations (MICE; van Buuren & Groothuis-Oudshoorn 2011) to address missing data on [variables] (range: X%–Y% missing). We created 20 imputed datasets and combined estimates using Rubin's rules. Results were consistent across imputed and complete-case analyses (Appendix Table A[X])."

See [references/missing-data.md](references/missing-data.md) for MNAR sensitivity analysis (delta shift, Heckman selection model).

---

## Phase 4: Univariate Distributions + Visualizations

### 4a. Source the Publication theme

```r
SKILL_DIR <- Sys.getenv("SCHOLAR_SKILL_DIR", unset = ".")
SKILL_DIR <- file.path(SKILL_DIR, ".claude", "skills")
viz_path <- file.path(SKILL_DIR, "scholar-analyze/references/viz_setting.R")
if (file.exists(viz_path)) source(viz_path) else stop("viz_setting.R not found at ", viz_path, " — do NOT define theme_Publication inline")
# Loads: theme_Publication(), scale_fill_Publication(), scale_colour_Publication()

# ── VISUALIZATION RULES (MANDATORY) ──────────────────────────────
# 1. NEVER use ggtitle() or labs(title = ...) — titles go in manuscript captions
# 2. ALWAYS use theme_Publication() — never theme_minimal(), theme_bw(), etc.
# 3. ALWAYS use scale_colour_Publication() or palette_cb for colors
# 4. ALWAYS save both PDF (cairo_pdf) and PNG (300 DPI) via save_fig()
# 5. Axis labels in plain language, not raw variable names
# ──────────────────────────────────────────────────────────────────

palette_main <- c("#0072B2","#E69F00","#009E73","#CC79A7","#56B4E9","#F0E442","#D55E00","#000000")

OR <- Sys.getenv("OUTPUT_ROOT", "output")
save_fig <- function(p, name, width = 6, height = 4.5, dpi = 300) {
  ggplot2::ggsave(paste0(OR, "/eda/figures/", name, ".pdf"),
                  plot = p, device = cairo_pdf, width = width, height = height)
  ggplot2::ggsave(paste0(OR, "/eda/figures/", name, ".png"),
                  plot = p, dpi = dpi, width = width, height = height)
  message("Saved: ", OR, "/eda/figures/", name)
}
```

### 4b. Continuous variables

```r
library(ggplot2); library(moments)

# Summary statistics
summary(df$outcome)
cat("Skewness:", skewness(df$outcome, na.rm = TRUE),
    " | Kurtosis:", kurtosis(df$outcome, na.rm = TRUE), "\n")

# Histogram + density
p_hist <- ggplot(df, aes(x = outcome)) +
  geom_histogram(aes(y = after_stat(density)), bins = 40, fill = palette_main[1], alpha = 0.7) +
  geom_density(linewidth = 0.8, color = "black") +
  labs(x = "Outcome", y = "Density") +
  theme_Publication()
save_fig(p_hist, "fig-dist-outcome")

# Q-Q plot (normality check)
p_qq <- ggplot(df, aes(sample = outcome)) +
  stat_qq(color = palette_main[1]) + stat_qq_line() +
  labs(x = "Theoretical Quantiles", y = "Sample Quantiles") + theme_Publication()
save_fig(p_qq, "fig-qq-outcome")
```

**Transform decision table:**

| Distribution problem | Solution |
|---------------------|---------|
| Right-skewed + positive (income, counts) | `log(x + 1)` |
| Left-skewed | Reflect + log: `log(max(x, na.rm=T) + 1 - x)` |
| Bimodal | Check for subgroup structure; consider splitting |
| Heavy-tailed, not log-transformable | Winsorize at 1st/99th percentile |
| Binary with rare event (< 5% positive) | Note for model choice; consider penalized logistic |
| Bounded [0,1] proportions | Logit or beta regression |

```r
# Winsorize
q <- quantile(df$income, c(0.01, 0.99), na.rm = TRUE)
df$income_w <- pmin(pmax(df$income, q[1]), q[2])

# Log transform
df$ln_income <- log(df$income + 1)
```

### 4c. Categorical and binary variables

```r
# Frequency table
df %>% count(race) %>% mutate(pct = n / sum(n)) %>% arrange(desc(pct))

# Bar chart with percentages
p_bar <- df %>% count(education) %>% mutate(pct = n / sum(n)) %>%
  ggplot(aes(x = reorder(education, -pct), y = pct)) +
  geom_col(fill = palette_main[1], alpha = 0.85) +
  scale_y_continuous(labels = scales::percent) +
  labs(x = "Education", y = "Proportion") +
  theme_Publication()
save_fig(p_bar, "fig-bar-education")

# Set reference category (largest or theoretically meaningful)
df$race <- relevel(factor(df$race), ref = "White")
```

**Document:** sparse categories (< 5% of sample) — consider collapsing before modeling.

---

## Phase 5: Bivariate Relationships + Visualizations

### 5a. Outcome × continuous predictor

```r
# Scatter with LOESS smoother (checks linearity)
p_scatter <- ggplot(df, aes(x = predictor, y = outcome)) +
  geom_point(alpha = 0.3, size = 0.8, color = palette_main[1]) +
  geom_smooth(method = "loess", se = TRUE, color = "black", linewidth = 1) +
  geom_smooth(method = "lm", se = FALSE, color = palette_main[2], linetype = "dashed") +
  labs(x = "Predictor", y = "Outcome") +
  theme_Publication()
save_fig(p_scatter, "fig-scatter-y-x")
```

### 5b. Outcome × categorical/group predictor

```r
# Violin + boxplot (shows distribution + median + IQR)
p_violin <- ggplot(df, aes(x = group, y = outcome, fill = group)) +
  geom_violin(alpha = 0.6, trim = FALSE) +
  geom_boxplot(width = 0.12, fill = "white", outlier.size = 0.8) +
  scale_fill_Publication() +
  labs(x = "Group", y = "Outcome") +
  guides(fill = "none") +
  theme_Publication()
save_fig(p_violin, "fig-violin-outcome-by-group")

# Grouped means table
df %>% group_by(group) %>%
  summarise(mean = mean(outcome, na.rm = TRUE),
            sd   = sd(outcome, na.rm = TRUE),
            n    = n(), .groups = "drop")
```

### 5c. Correlation heatmap (all continuous predictors)

```r
library(ggcorrplot)

df_num <- df %>% select(where(is.numeric)) %>% select(-any_of(c("id","year","weight")))
cor_mat <- cor(df_num, use = "pairwise.complete.obs")

p_corr <- ggcorrplot(cor_mat, type = "lower", lab = TRUE, lab_size = 3,
                     colors = c(palette_main[7], "white", palette_main[1])) +
  theme_Publication(base_size = 10)
save_fig(p_corr, "fig-corr-heatmap", width = 7, height = 6)
```

### 5d. Python equivalents

```python
import seaborn as sns
import matplotlib.pyplot as plt

# Scatter + LOESS
import os; _OR = os.environ.get("OUTPUT_ROOT", "output")
sns.regplot(data=df, x='predictor', y='outcome', lowess=True, scatter_kws={'alpha':0.3})
plt.savefig(f"{_OR}/eda/figures/fig-scatter-y-x.png", dpi=300, bbox_inches='tight')

# Violin
sns.violinplot(data=df, x='group', y='outcome', palette='colorblind')
plt.savefig(f"{_OR}/eda/figures/fig-violin-outcome-by-group.png", dpi=300, bbox_inches='tight')

# Correlation heatmap
sns.heatmap(df.select_dtypes('number').corr(), annot=True, fmt='.2f', cmap='coolwarm', center=0)
plt.savefig(f"{_OR}/eda/figures/fig-corr-heatmap.png", dpi=300, bbox_inches='tight')
```

**Note preliminary patterns:**
- Does the bivariate relationship go in the predicted direction?
- Is there nonlinearity (LOESS curves away from OLS line)?
- Are there obvious subgroup differences that suggest moderation?

---

## Phase 6: Multicollinearity Check

```r
library(car)

# Pairwise correlations: flag pairs > 0.8
high_cor <- which(abs(cor_mat) > 0.8 & cor_mat != 1, arr.ind = TRUE)
if (nrow(high_cor) > 0) {
  cat("High-correlation pairs (> 0.8):\n")
  print(data.frame(var1 = rownames(cor_mat)[high_cor[,1]],
                   var2 = colnames(cor_mat)[high_cor[,2]],
                   r    = cor_mat[high_cor]))
}

# VIF after fitting preliminary model
m_vif <- lm(outcome ~ predictor + control1 + control2 + control3, data = df)
vif(m_vif)
```

**Decision rules:**

| VIF | Action |
|-----|--------|
| < 5 | Acceptable |
| 5–10 | Concerning — investigate; consider dropping or composite |
| > 10 | Serious multicollinearity — must address |

Options if collinear: (1) drop the less theoretically central variable; (2) create a composite index (`psych::principal()`); (3) use ridge regression or LASSO as robustness check.

### Step 6b: Measurement Validation (conditional)

**Trigger:** Run this step if the study involves latent constructs (scales, indices, composite measures) or cross-group comparisons (race, gender, country subgroups).

**Skip if:** All variables are directly observed single-item measures (e.g., binary callback, continuous income, categorical education level).

```r
# --- Confirmatory Factor Analysis (CFA) for latent constructs ---
library(lavaan)

# Define the measurement model (adapt to your constructs)
cfa_model <- '
  construct1 =~ item1 + item2 + item3 + item4
  construct2 =~ item5 + item6 + item7
'
cfa_fit <- cfa(cfa_model, data = df, estimator = "MLR")
summary(cfa_fit, fit.measures = TRUE, standardized = TRUE)

# Fit indices: CFI >= .95, TLI >= .95, RMSEA <= .06, SRMR <= .08
fitMeasures(cfa_fit, c("cfi", "tli", "rmsea", "srmr"))

# --- Measurement Invariance (if comparing groups) ---
# Configural (same structure)
config <- cfa(cfa_model, data = df, group = "group_var")
# Metric (equal loadings)
metric <- cfa(cfa_model, data = df, group = "group_var", group.equal = "loadings")
# Scalar (equal intercepts)
scalar <- cfa(cfa_model, data = df, group = "group_var", group.equal = c("loadings", "intercepts"))

# Compare: delta CFI < .01 and delta RMSEA < .015 supports invariance
anova(config, metric, scalar)

# --- Reliability ---
library(psych)
alpha(df[, c("item1", "item2", "item3", "item4")])  # Cronbach's alpha
omega(df[, c("item1", "item2", "item3", "item4")])   # McDonald's omega (preferred)
```

**For computational measures** (NLP-derived, ML predictions):
```r
# Report precision, recall, F1 against gold-standard human coding
library(caret)
cm <- confusionMatrix(factor(predicted), factor(gold_standard))
cm$byClass[c("Precision", "Recall", "F1")]
# Inter-annotator agreement: Cohen's kappa or Krippendorff's alpha
library(irr)
kappa2(cbind(coder1, coder2))
```

**Decision rules:**

| Metric | Threshold | Action |
|--------|-----------|--------|
| CFI < .90 | Poor fit — revise measurement model |
| Alpha / Omega < .70 | Weak reliability — note limitation; consider dropping weak items |
| Metric invariance fails (delta CFI > .01) | Cannot compare group means directly — note limitation |
| F1 < .70 for computational measure | Weak prediction — note measurement error in limitations |

**Condition number** (complement to VIF):
```r
# Condition number of design matrix
X <- model.matrix(~ x1 + x2 + x3, data = df)
kappa(X)  # κ < 30: acceptable; κ > 30: severe multicollinearity

# Variance decomposition (Belsley, Kuh & Welsch 1980)
library(perturb)
colldiag(X)  # Identifies WHICH variables are involved in collinearity
```

---

## Phase 7: Panel / Longitudinal Data Checks (Conditional)

Run only if data are panel/longitudinal.

```r
library(plm)
pdata <- pdata.frame(df, index = c("id", "year"))
pdim(pdata)  # balanced? T, N, obs

# Between vs. within variation on key predictor
# FE requires within-person (over-time) variation
between_sd <- sd(tapply(df$predictor, df$id, mean, na.rm = TRUE), na.rm = TRUE)
within_sd  <- sd(df$predictor - ave(df$predictor, df$id, FUN = function(x) mean(x, na.rm=TRUE)), na.rm=TRUE)
cat("Between SD:", round(between_sd, 3), " | Within SD:", round(within_sd, 3), "\n")
# If Within SD ≈ 0: FE cannot estimate the effect of this variable
```

```stata
xtset id year
xtdescribe             // balanced panel?
xtsum outcome predictor control1  // between vs. within SD
```

**Attrition analysis:**
```r
# Compare baseline characteristics of completers vs. attritors
df_baseline <- df %>% filter(year == min(year))
df_baseline$attritor <- !(df_baseline$id %in% df$id[df$year == max(df$year)])
t.test(age ~ attritor, data = df_baseline)
# If significant differences → selective attrition; discuss as limitation
```

**Pre-trend check placeholder** (if DiD): plot group means by year before treatment; should be parallel pre-treatment. (Handled fully by `/scholar-causal`.)

---

## Phase 8: Outlier and Influential Observations

```r
# Fit preliminary model for diagnostics
m_diag <- lm(outcome ~ predictor + control1 + control2, data = df)

# Diagnostic values
df$cooks_d  <- cooks.distance(m_diag)
df$leverage <- hatvalues(m_diag)
df$std_res  <- rstandard(m_diag)

thr_cook  <- 4 / nrow(df)
thr_lever <- 2 * length(coef(m_diag)) / nrow(df)

outliers <- df %>% filter(cooks_d > thr_cook | abs(std_res) > 3)
cat("N influential observations:", nrow(outliers), "\n")
```

```r
# ggplot2 diagnostic plot: Cook's D
p_cook <- ggplot(df %>% mutate(obs = row_number()), aes(x = obs, y = cooks_d)) +
  geom_point(aes(color = cooks_d > thr_cook), size = 0.7) +
  geom_hline(yintercept = thr_cook, linetype = "dashed", color = palette_main[7]) +
  scale_color_manual(values = c("FALSE" = "grey50", "TRUE" = palette_main[7])) +
  labs(x = "Observation", y = "Cook's D") +
  guides(color = "none") + theme_Publication()
save_fig(p_cook, "fig-cooks-d")
```

**Decision protocol:**
- Cook's D > 4/N or |std residual| > 3: investigate — data entry error? Genuine extreme case? Different population?
- **Never delete outliers solely because they weaken your result** — that is p-hacking
- Run primary analysis with outliers; show robustness without in appendix
- Document every exclusion transparently

**Coefficient-level influence diagnostics**:
```r
# DFBETAS: influence of each observation on each coefficient
dfb <- dfbetas(mod)
# Flag: |DFBETAS| > 2/√N
apply(abs(dfb), 2, function(x) which(x > 2/sqrt(nrow(df))))

# DFFITS: influence on fitted values
dff <- dffits(mod)
# Flag: |DFFITS| > 2√(p/N)
which(abs(dff) > 2 * sqrt(ncol(model.matrix(mod)) / nrow(df)))
```

**Multivariate outlier detection**:
```r
# Mahalanobis distance
md <- mahalanobis(df[, numeric_vars], colMeans(df[, numeric_vars]),
                  cov(df[, numeric_vars]))
# Flag: χ²(p) critical value at α = 0.001
which(md > qchisq(0.999, df = length(numeric_vars)))
```

---

## Phase 8b: Panel / Time-Series Diagnostics

Run when data are panel, longitudinal, or time-series.

**Autocorrelation**:
```r
# Durbin-Watson test (OLS residuals)
library(lmtest)
dwtest(mod)  # DW ≈ 2: no autocorrelation; DW < 1.5 or > 2.5: concern

# Wooldridge test for serial correlation in panel FE
library(plm)
pbgtest(fe_mod)  # p < 0.05 → serial correlation present → cluster SEs

# ACF/PACF plots
acf(residuals(mod), main = "ACF of Residuals")
pacf(residuals(mod), main = "PACF of Residuals")
```

**Stationarity** (for time series or long panels):
```r
library(tseries)
adf.test(df$y)    # Augmented Dickey-Fuller: p < 0.05 → stationary
kpss.test(df$y)   # KPSS: p > 0.05 → stationary (note reversed null)
```

**Cross-sectional dependence** (macro panels):
```r
library(plm)
pcdtest(fe_mod, test = "cd")  # Pesaran CD test: p < 0.05 → dependence
# If detected: use Driscoll-Kraay SEs
library(sandwich)
vcovDK <- vcovSCC(fe_mod)
coeftest(fe_mod, vcov = vcovDK)
```

**Heteroscedasticity**:
```r
library(lmtest)
bptest(mod)  # Breusch-Pagan: p < 0.05 → heteroscedastic → use HC3 SEs
# White's test (more general):
bptest(mod, ~ fitted(mod) + I(fitted(mod)^2))
```

---

## Phase 8c: Formal Distribution Tests

**Normality tests** (complement to visual Q-Q):
```r
shapiro.test(df$y)          # Shapiro-Wilk (N < 5000)
nortest::ad.test(df$y)      # Anderson-Darling
jarque.bera.test(df$y)      # Jarque-Bera (skewness + kurtosis)
```

**Bimodality detection**:
```r
library(diptest)
dip.test(df$y)  # Hartigan's dip test: p < 0.05 → multimodal
# If multimodal: consider finite mixture models or subgroup analysis
```

---

## Phase 9: Pre-Analysis Decisions Memo

Write this memo **before running any hypothesis tests**. Date-stamp it. If pre-registered, this is already public.

```r
today <- format(Sys.Date(), "%Y-%m-%d")
cat("Pre-Analysis Memo Date:", today, "\n")
```

**Memo template** (fill in from Phases 1–8):

```
PRE-ANALYSIS PLAN MEMO
─────────────────────────────────────────
Project: [Title]
Analyst: [Name]
Date: [YYYY-MM-DD — fill before outcome analysis]

1. ANALYTIC SAMPLE
   Start N: [X]
   Exclusions: [list each; N remaining after each]
   Final N: [X]
   Post-treatment variables at risk of post-treatment bias: [list or "none"]

2. DEPENDENT VARIABLE
   Name: [var]
   Type: continuous / binary / count / ordinal
   Operationalization: [how measured]
   Distribution: [skewness, floor/ceiling effects]
   Transformation: [none / log / winsorize — reason]

3. KEY INDEPENDENT VARIABLE
   Name: [var]
   Operationalization: [how measured]
   Variation: [% treated / SD; within vs. between SD for panel]

4. CONTROLS
   List: [var1 (rationale), var2 (rationale) ...]
   Survey weights used: [yes / no — design object]

5. MISSING DATA
   % missing on outcome: [X%]
   % missing on key IV: [X%]
   Mechanism (MCAR/MAR/MNAR): [based on Little's test + shadow matrix]
   Treatment: [listwise deletion / MICE m=[M] / other]

6. MODEL SPECIFICATION
   Primary estimator: [OLS / logit / panel FE / Cox / multilevel / etc.]
   SE type: [HC3 robust / clustered by [unit] / bootstrapped]
   Hypothesis tested in which coefficient: [β for [var] in Model [M]]

7. HYPOTHESES
   H1: [X positively/negatively associated with Y — direction]
   H2: [moderation / mediation — if applicable]

8. PLANNED ROBUSTNESS CHECKS
   1. [Alternative operationalization of X]
   2. [Alternative sample restriction]
   3. [Alternative model specification]
   4. [Placebo / falsification test]

9. EXPLORATORY ANALYSES (not prespecified)
   [List any analyses planned that are exploratory — label as exploratory in paper]

10. PREREGISTERED: [Yes — OSF URL / No — memo date-stamped before outcome analysis]
```

---

## Phase 10: Descriptive Statistics Table (Table 1)

### 10a. R — gtsummary (primary)

```r
library(gtsummary)
library(flextable)

# Full sample Table 1
tbl1 <- df %>%
  select(outcome, predictor, control1, control2, control3, group) %>%
  tbl_summary(
    by = group,                                  # column by group (remove if no comparison)
    statistic = list(
      all_continuous()  ~ "{mean} ({sd})",
      all_categorical() ~ "{n} ({p}%)"
    ),
    digits = all_continuous() ~ 2,
    missing_text = "Missing"
  ) %>%
  add_overall() %>%
  add_p(pvalue_fun = ~style_pvalue(., digits = 3)) %>%
  bold_labels() %>%
  modify_caption("**Table 1. Descriptive Statistics**")

# Export
OR <- Sys.getenv("OUTPUT_ROOT", "output")
tbl1 %>% as_gt() %>% gt::gtsave(paste0(OR, "/eda/tables/table1-descriptives.html"))
tbl1 %>% as_kable_extra(format = "latex") %>% writeLines(paste0(OR, "/eda/tables/table1-descriptives.tex"))
tbl1 %>% as_flex_table() %>% flextable::save_as_docx(path = paste0(OR, "/eda/tables/table1-descriptives.docx"))
```

### 10b. R — skimr + modelsummary (alternatives)

```r
library(skimr)
skim(df %>% select(outcome, predictor, control1, control2, group))

library(modelsummary)
OR <- Sys.getenv("OUTPUT_ROOT", "output")
datasummary_balance(~group, data = df,
                    output = paste0(OR, "/eda/tables/table1-balance.html"))
```

### 10c. Python — tableone

```python
from tableone import TableOne
columns = ['outcome', 'predictor', 'control1', 'control2']
groupby = 'group'
mytable = TableOne(df, columns=columns, groupby=groupby, pval=True)
import os; _OR = os.environ.get("OUTPUT_ROOT", "output")
mytable.to_html(f"{_OR}/eda/tables/table1-descriptives.html")
print(mytable.tabulate(tablefmt='pipe'))
```

**Journal standards:**
- ASR / AJS / Demography: Table 1 required; N must be reported; analytic sample described in note
- Nature journals / Science Advances: summary statistics in Methods; sometimes Supplementary
- Always: note the exact analytic sample the table describes; use footnotes for abbreviations

---

## Verification (Optional — Run Before Handing Off to /scholar-analyze)

Spawn a Task subagent to check EDA coherence:

```
Task tool — subagent_type: general-purpose
Prompt:
  "You are a senior quantitative social scientist reviewing an EDA report before analysis begins.
   Check the following EDA decisions for internal coherence:

   EDA SUMMARY:
   - Analytic N: [N]
   - Outcome distribution: [description + transformation applied]
   - Missing data: [% missing, mechanism, treatment]
   - Key correlations: [correlations between predictors]
   - VIF max: [value]
   - Measurement validation: [CFA fit / reliability alpha/omega / invariance — or N/A if single-item measures]
   - Influential observations: [N flagged, action taken]
   - Pre-analysis memo: [locked / not yet locked]
   - Table 1: [saved / not yet saved]

   Flag any of the following issues:
   1. VIF > 10 without a stated resolution
   2. > 20% missing on key variable without MI or sensitivity analysis
   3. Missing pre-analysis memo
   4. Transformation applied without justification
   5. Outliers excluded without documentation
   6. Post-treatment controls in the model specification
   7. Table 1 not saved

   Return: PASS / FAIL with specific issues and recommended fixes."
```

---

## Save Output

After completing all phases, save a summary document using the Write tool.

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/eda/scholar-eda-[topic-slug]-[YYYY-MM-DD]
# Split into directory and stem for the gate script:
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/eda/scholar-eda-[topic-slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/eda/scholar-eda-[topic-slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).

**Filename:** `scholar-eda-[topic-slug]-[YYYY-MM-DD].md`

**Contents:**
```markdown
# EDA Report: [topic]
*Generated by /scholar-eda on [YYYY-MM-DD]*

## Data Source
- File: [path or source]
- Input mode: local file / inline / online ([package + query])
- Raw N: [N]; Final analytic N: [N]

## Sample Construction
[Exclusion flow table — all rows filled in]

## Missing Data Summary
- Variables with > 5% missing: [list]
- Mechanism assessment: [MCAR/MAR/MNAR — test result]
- Treatment: [listwise / MICE m=[M]]

## Distributional Findings
- Outcome [var]: [mean, SD, skewness, transformation applied]
- Key predictor [var]: [mean, SD, within/between SD for panel]
- Sparse categories: [list any collapsed]

## Bivariate Preview
- [X] vs. [Y]: [direction, linearity assessment]
- Max pairwise correlation among predictors: [r=X between var1 and var2]
- Max VIF: [value — pass/fail]

## Pre-Analysis Decisions Memo
[Full memo from Phase 9 — pasted here]

## File Inventory
output/[slug]/eda/figures/fig-missing-by-var.pdf/.png
output/[slug]/eda/figures/fig-missing-upset.pdf/.png
output/[slug]/eda/figures/fig-dist-outcome.pdf/.png
output/[slug]/eda/figures/fig-qq-outcome.pdf/.png
output/[slug]/eda/figures/fig-scatter-y-x.pdf/.png
output/[slug]/eda/figures/fig-violin-outcome-by-group.pdf/.png
output/[slug]/eda/figures/fig-corr-heatmap.pdf/.png
output/[slug]/eda/figures/fig-cooks-d.pdf/.png
output/[slug]/eda/tables/table1-descriptives.html/.tex/.docx
output/[slug]/scripts/E01-*.R through E07-*.R — EDA analysis scripts (for replication package)
output/[slug]/scripts/script-index.md — script run order (appended)
output/[slug]/scripts/coding-decisions-log.md — analytic decisions (appended)
```

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-eda"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
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

Confirm saved file path to user after Write tool completes.

---

## EDA Quality Checklist

- [ ] Output directories created (`output/[slug]/eda/figures/`, `output/[slug]/eda/tables/`)
- [ ] Data loaded successfully; format and encoding confirmed
- [ ] Causal gate checked — if causal design detected, /scholar-causal invoked first
- [ ] Unit of analysis and ID uniqueness confirmed
- [ ] Analytic sample defined with exclusion flow table (N before/after each step)
- [ ] Post-treatment controls identified and documented
- [ ] Missing data % documented for all key variables
- [ ] Missing data mechanism assessed (Little's MCAR test + shadow matrix)
- [ ] MI applied if > 5% missing on key variable (or listwise deletion justified)
- [ ] Outcome distribution inspected; transformation justified and applied if needed
- [ ] All key figures saved to `output/[slug]/eda/figures/` (PDF + PNG, 300 DPI)
- [ ] Bivariate relationships previewed (direction, linearity, LOESS)
- [ ] Correlation heatmap produced; high-correlation pairs flagged (> 0.8)
- [ ] VIF checked; max VIF < 10 (or addressed if higher)
- [ ] Measurement validation completed if latent constructs used (CFA fit indices, reliability, invariance if cross-group)
- [ ] Panel within-variation confirmed if FE planned (within SD > 0)
- [ ] Outlier/influential observations checked; exclusion decisions documented
- [ ] Pre-analysis decisions memo written and date-stamped
- [ ] Table 1 produced with gtsummary + saved as HTML/docx/TeX
- [ ] All EDA scripts saved to `output/[slug]/scripts/E01-*.R` through `E07-*.R`
- [ ] `output/[slug]/scripts/script-index.md` updated with run order for each script
- [ ] `output/[slug]/scripts/coding-decisions-log.md` updated with analytic decisions
- [ ] EDA summary saved to `scholar-eda-[slug]-[date].md`

See [references/cleaning-guide.md](references/cleaning-guide.md) for variable-specific cleaning code.
See [references/missing-data.md](references/missing-data.md) for MICE full workflow and MNAR sensitivity analysis.
