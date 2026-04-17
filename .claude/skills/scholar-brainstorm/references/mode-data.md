# Mode: DATA — Steps 0, 1, 2, 3, 4, 4b

This file contains the DATA mode workflow steps. MATERIALS mode reuses Steps 1-4 (skipping Step 0 safety gate and Step 4b empirical signal tests).

---

### Step 0: Safety Gate (DATA mode only)

**If MATERIALS mode: skip this step entirely.** Note in the process log: "Step 0 skipped — MATERIALS mode (no data files)." Set `SAFETY_STATUS=N/A` and proceed to Step 1.

**If DATA mode:** Before running the in-skill grep scan below, first check whether the project was initialized via `/scholar-init`. If so, inherit the sidecar decisions and skip the re-scan — this is the scholar-init → scholar-brainstorm handshake.

**Step 0a — scholar-init handshake (skip rescan if sidecar exists):**

```bash
# ── Step 0a: scholar-init sidecar handshake ──
# If .claude/safety-status.json already classifies every input file, inherit
# the decisions and skip the redundant in-skill scan below. The PreToolUse
# hook (scripts/gates/pretooluse-data-guard.sh) remains the mechanical backstop.
SIDECAR=".claude/safety-status.json"
SKIP_RESCAN=0
INHERITED_STATUS=""
if [ -f "$SIDECAR" ] && command -v jq >/dev/null 2>&1; then
  ALL_REGISTERED=1
  HAS_UNSAFE=0
  for F in $DATA_FILES; do
    [ -f "$F" ] || continue
    ABS=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$F" 2>/dev/null \
          || realpath "$F" 2>/dev/null || readlink -f "$F" 2>/dev/null || echo "$F")
    S=$(jq -r --arg k "$ABS" '.[$k] // empty' "$SIDECAR")
    [ -z "$S" ] && S=$(jq -r --arg k "$F" '.[$k] // empty' "$SIDECAR")
    if [ -z "$S" ]; then
      ALL_REGISTERED=0; break
    fi
    case "$S" in
      NEEDS_REVIEW:*|HALTED) HAS_UNSAFE=1 ;;
    esac
    # Remember the most-restrictive status seen; LOCAL_MODE wins over CLEARED.
    case "$S" in
      LOCAL_MODE) INHERITED_STATUS="LOCAL_MODE" ;;
      ANONYMIZED) [ "$INHERITED_STATUS" != "LOCAL_MODE" ] && INHERITED_STATUS="ANONYMIZED" ;;
      OVERRIDE)   [ -z "$INHERITED_STATUS" ] && INHERITED_STATUS="OVERRIDE" ;;
      CLEARED)    [ -z "$INHERITED_STATUS" ] && INHERITED_STATUS="CLEARED" ;;
    esac
  done
  if [ "$HAS_UNSAFE" -eq 1 ]; then
    cat >&2 <<HALTMSG
⛔ HALT — scholar-brainstorm DATA mode refused because .claude/safety-status.json
contains NEEDS_REVIEW or HALTED entries for one or more input files.

Run:  /scholar-init review
…then re-invoke /scholar-brainstorm.
HALTMSG
    exit 1
  fi
  if [ "$ALL_REGISTERED" -eq 1 ]; then
    SKIP_RESCAN=1
    echo "✓ scholar-init sidecar covers all DATA files — inheriting SAFETY_STATUS=$INHERITED_STATUS"
    echo "  Skipping the in-skill grep re-scan below."
  fi
fi
```

If `SKIP_RESCAN=1`, set `SAFETY_STATUS=$INHERITED_STATUS`, log `"Step 0 inherited from .claude/safety-status.json (scholar-init handshake)"` to the process log, and jump directly to Step 1. Otherwise, proceed with the grep scan below.

**Step 0b — In-skill grep scan (fallback when no sidecar exists):**

Before reading any data file into context, run a local grep-only scan to detect PII, HIPAA, and restricted data markers. This reuses the scholar-safety SCAN pattern — only match counts are returned, never actual sensitive values.

**Run this scan for EACH data file** (single Bash block for all files):

```bash
# ── Safety Gate: grep-only sensitivity scan ──
for FILE in [DATA_FILE_PATHS]; do

echo ""
echo "=== SAFETY SCAN: $FILE ==="
echo ""

# === DIRECT IDENTIFIERS ===
SSN_COUNT=$(grep -cEi '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b|\bSSN\b|\bsocial.security' "$FILE" 2>/dev/null || echo 0)
echo "SSN patterns: $SSN_COUNT"

NAME_COUNT=$(grep -cEi '\b(first.?name|last.?name|full.?name|respondent.?name|participant.?name)\b' "$FILE" 2>/dev/null || echo 0)
echo "Name fields: $NAME_COUNT"

EMAIL_COUNT=$(grep -cEi '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$FILE" 2>/dev/null || echo 0)
echo "Email addresses: $EMAIL_COUNT"

PHONE_COUNT=$(grep -cEi '\b(\+?1[-.\s]?)?(\([0-9]{3}\)|[0-9]{3})[-.\s][0-9]{3}[-.\s][0-9]{4}\b' "$FILE" 2>/dev/null || echo 0)
echo "Phone numbers: $PHONE_COUNT"

ADDR_COUNT=$(grep -cEi '\b[0-9]{1,5}\s+[a-zA-Z]+(St|Street|Ave|Avenue|Blvd|Boulevard|Dr|Drive|Rd|Road|Ln|Lane|Way|Court|Ct)\b' "$FILE" 2>/dev/null || echo 0)
echo "Street addresses: $ADDR_COUNT"

# === HEALTH / HIPAA ===
HEALTH_COUNT=$(grep -cEi '\b(diagnosis|ICD.?[0-9]|medical.?record|patient|PHI|HIPAA|health.?condition|medication|prescription|treatment|clinical)\b' "$FILE" 2>/dev/null || echo 0)
echo "Health/HIPAA keywords: $HEALTH_COUNT"

MENTAL_COUNT=$(grep -cEi '\b(depression|anxiety|suicid|mental.?health|psychiatric|PTSD|bipolar|schizophrenia|self.?harm|substance.?use)\b' "$FILE" 2>/dev/null || echo 0)
echo "Mental health terms: $MENTAL_COUNT"

# === LEGAL / IMMIGRATION ===
LEGAL_COUNT=$(grep -cEi '\b(undocumented|illegal.?immigrant|immigration.?status|visa.?status|DACA|asylum|deportation|criminal.?record|arrest|conviction|incarcerated)\b' "$FILE" 2>/dev/null || echo 0)
echo "Legal/immigration status: $LEGAL_COUNT"

# === RESTRICTED DATA MARKERS ===
RESTRICTED_COUNT=$(grep -cEi '\b(NHANES|PSID|NLSY|IPUMS|Census.?RDC|restricted.?use|data.?use.?agreement|DUA|confidential|not.?for.?distribution|UK.?Biobank|ALSPAC|NHS.?Digital|GSOEP|SHARE)\b' "$FILE" 2>/dev/null || echo 0)
echo "Restricted/licensed data markers: $RESTRICTED_COUNT"

# === IRB / PARTICIPANT MARKERS ===
IRB_COUNT=$(grep -cEi '\b(participant|respondent|interview|subject.?ID|case.?ID|record.?ID|consent)\b' "$FILE" 2>/dev/null || echo 0)
echo "IRB participant markers: $IRB_COUNT"

# === GEOGRAPHIC GRANULARITY ===
GEO_COUNT=$(grep -cEi '\b(latitude|longitude|lat|lon|geocode|census.?tract|block.?group|exact.?address)\b' "$FILE" 2>/dev/null || echo 0)
echo "Fine-grained geographic data: $GEO_COUNT"

echo ""
echo "=== SCAN COMPLETE: $FILE ==="

done
```

**Risk Classification** (same matrix as scholar-safety):

| Condition | Risk Level |
|-----------|-----------|
| SSN > 0 OR email > 5 OR phone > 5 OR address > 5 | 🔴 HIGH |
| Health/HIPAA > 0 OR mental_health > 0 OR legal/immigration > 0 | 🔴 HIGH |
| Restricted/licensed data markers > 0 | 🔴 HIGH |
| Name fields > 0 AND IRB markers > 0 | 🔴 HIGH |
| IRB markers > 20 AND (geo_fine > 0 OR financial > 0) | 🟡 MEDIUM |
| IRB markers > 0 AND no other flags | 🟡 MEDIUM |
| email 1–5 OR phone 1–5 | 🟡 MEDIUM |
| No sensitive patterns | 🟢 LOW |

**Gate Output:**

```
╔══════════════════════════════════════════════════════════════╗
║  🔐  SCHOLAR BRAINSTORM — SAFETY GATE (Step 0)               ║
╚══════════════════════════════════════════════════════════════╝

Files scanned: [N]

┌──────────────────────────────────────────────────────────┐
│ File                     │ Risk Level │ Key flags        │
├──────────────────────────────────────────────────────────┤
│ [filename1]              │ 🟢 LOW     │ None             │
│ [filename2]              │ 🟡 MEDIUM  │ IRB markers (12) │
└──────────────────────────────────────────────────────────┘

OVERALL GATE STATUS: [🔴 BLOCKED / 🟡 CAUTION / 🟢 CLEARED]
```

**If 🔴 HIGH detected:**

```
⛔  HIGH SENSITIVITY DETECTED — data cannot be read into AI context.

OPTIONS:
[A]  HALT       Stop. Resolve data handling before continuing.
[B]  ANONYMIZE  Generate a local anonymization script. Run it,
                then re-invoke /scholar-brainstorm on the clean file.
[C]  LOCAL MODE Proceed using Bash-only analysis (Rscript -e).
                No raw data enters Claude's context. Empirical
                signal tests will run via Rscript; only aggregated
                output (coefficients, p-values) returned.
[D]  OVERRIDE   I confirm this is not sensitive data (false positive).
                Log my decision and proceed.

Awaiting your selection (A / B / C / D):
```

**WAIT for user response.** Do NOT proceed until user selects an option.

**If 🟡 MEDIUM detected:**

```
⚠  Potentially sensitive patterns found. Reading this file will
transmit its contents to Anthropic's API. Please confirm.

OPTIONS:
[Y]  PROCEED    I confirm this data is appropriate for cloud AI processing.
[B]  ANONYMIZE  Generate anonymization script first.
[C]  LOCAL MODE Use Bash-only analysis (no raw data in context).
[A]  HALT       Stop; I need to verify data handling permissions.

Awaiting your selection (Y / B / C / A):
```

**WAIT for user response.**

**If 🟢 LOW:** Proceed automatically.

**Set `SAFETY_STATUS` based on user selection:**
- 🟢 LOW or user selects [Y] PROCEED → `SAFETY_STATUS=CLEARED`
- User selects [C] LOCAL MODE → `SAFETY_STATUS=LOCAL_MODE`
- User selects [B] ANONYMIZE → generate R anonymization script (same as scholar-safety), then `SAFETY_STATUS=ANONYMIZED` after re-scan passes
- User selects [D] OVERRIDE → `SAFETY_STATUS=OVERRIDE`
- User selects [A] HALT → **stop the skill entirely**

**LOCAL_MODE constraints** (when `SAFETY_STATUS=LOCAL_MODE`):
- Never use the Read tool on data files
- All data operations via `Rscript -e "..."` in Bash — only aggregated output (summary stats, coefficients, p-values) enters context
- Step 1 data loading: summary only (no `head()` output)
- Step 2 variable profiling: `skimr::skim()` output only
- Step 4b empirical tests: write the R script to `${PROJ}/scripts/brainstorm-signal-tests.R` via the Write tool, then execute via `Rscript <path>` (file-based, NOT `Rscript -e` heredoc). The script itself must not call `head(df)`, `print(df)`, or any other forbidden verb — only the aggregated `signal_results` tibble prints to stdout, which is the only thing that enters Claude's context.

---

### Step 1: Ingest and Classify Materials

**(DATA and MATERIALS modes only — PAPER mode skips to Step 5 after Step 0b)**

Read all provided files using the Read tool (or Bash for data files like .csv/.dta/.sav).

**1a. Detect material type:**

| Material | Action |
|----------|--------|
| **Codebook / data dictionary** (.pdf, .md, .txt, .html, .docx) | Read directly; extract variable inventory |
| **Survey questionnaire** (.pdf, .md, .docx) | Read directly; extract constructs, sections, and routing logic |
| **Data file** (.csv, .tsv) | `head -1` for column names; `wc -l` for N; sample 20 rows for value inspection |
| **Stata file** (.dta) | `stata -b -e "describe using FILE"` or use R: `haven::read_dta()` to extract variable labels |
| **R data** (.rds, .RData) | Use R to load and run `str()`, `names()`, `dim()` |
| **SPSS** (.sav) | Use R: `haven::read_sav()` to extract variable labels and value labels |
| **URL** | Use WebFetch; then classify the downloaded content |
| **Multiple files** | Read each; cross-reference variable names across files |

**1a-DATA (DATA mode only):** If `SAFETY_STATUS` is CLEARED or OVERRIDE, load the data in R to extract structure:

```r
# ── Data loading: auto-detect format ──
library(tidyverse)
library(haven)
library(readxl)

load_data <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    csv  = read_csv(path, show_col_types = FALSE),
    tsv  = read_tsv(path, show_col_types = FALSE),
    dta  = read_dta(path),
    sav  = read_sav(path),
    rds  = readRDS(path),
    xlsx = read_excel(path),
    xls  = read_excel(path),
    parquet = arrow::read_parquet(path),
    stop(paste("Unsupported format:", ext))
  )
}

df <- load_data("[DATA_FILE_PATH]")
cat("N =", nrow(df), "\n")
cat("Variables =", ncol(df), "\n")
cat("Column names:\n")
cat(paste(names(df), collapse = ", "), "\n")
str(df, list.len = ncol(df))
head(df, 5)
```

If `SAFETY_STATUS=LOCAL_MODE`, wrap the above in `Rscript -e "..."` via Bash and **omit the `head()` call** — only `str()` and `cat()` summary output enters context.

**1b. Extract metadata:**
- **Dataset name** (if identifiable)
- **Unit of analysis** (individual, household, firm, country, etc.)
- **Sample size** (N) and sample design (random, stratified, convenience)
- **Population** (who is represented)
- **Geographic scope** (national, regional, cross-national)
- **Temporal coverage** (single cross-section, repeated cross-section, panel; years)
- **Panel structure** (if longitudinal: how many waves, attrition rates)
- **Weighting** (survey weights available?)
- **Known limitations** (response rates, coverage gaps, item nonresponse patterns)

Present the metadata as a summary table:

```
===== MATERIAL SUMMARY =====

| Field | Value |
|-------|-------|
| Operating mode | [DATA / MATERIALS] |
| Safety status | [CLEARED / LOCAL_MODE / ANONYMIZED / OVERRIDE / N/A] |
| Material type | [codebook / questionnaire / data / mixed] |
| Dataset name | [name or "unidentified"] |
| Unit of analysis | [individual / household / etc.] |
| Sample size (N) | [number or "unknown"] |
| Population | [description] |
| Geographic scope | [description] |
| Temporal coverage | [years, waves] |
| Panel structure | [cross-section / panel (K waves) / repeated cross-section] |
| Weighting available | [Yes / No / Unknown] |
```

### Step 2: Variable Inventory and Classification

Extract ALL variables from the materials and classify each into analytic roles.

**2a. Build the full variable inventory:**

For each variable, record:
- Variable name (as in data)
- Label / description
- Type (continuous, categorical, ordinal, binary, count, string, date)
- Possible values / range
- Missingness (if detectable from the codebook or data)

**2b. Classify variables into analytic roles:**

Use [references/brainstorm-patterns.md](references/brainstorm-patterns.md) Section 2 (Variable Taxonomy) to assign each variable to one or more roles:

| Role | Variables |
|------|-----------|
| **Outcomes (Y)** | [list] |
| **Predictors (X)** | [list] |
| **Mechanisms (M)** | [list] |
| **Moderators (W)** | [list] |
| **Confounders (C)** | [list] |
| **Context (Z)** | [list] |
| **Demographics (D)** | [list] |

Some variables may appear in multiple roles depending on the RQ.

**2b-DATA (DATA mode only):** Run `skimr::skim()` for empirical variable profiling:

```r
# ── Empirical variable profiling ──
library(skimr)

df <- load_data("[DATA_FILE_PATH]")  # or re-load as needed

# Profile all variables
skim_output <- skim(df)
print(skim_output)

# Empirical type detection
var_types <- tibble(
  variable = names(df),
  r_class = sapply(df, function(x) class(x)[1]),
  n_unique = sapply(df, n_distinct),
  pct_missing = sapply(df, function(x) mean(is.na(x)) * 100)
) |>
  mutate(
    empirical_type = case_when(
      r_class %in% c("numeric", "double", "integer") & n_unique == 2 ~ "binary",
      r_class %in% c("numeric", "double", "integer") & n_unique <= 7 ~ "categorical/ordinal",
      r_class %in% c("numeric", "double", "integer") & n_unique <= 20 ~ "count_or_ordinal",
      r_class %in% c("numeric", "double", "integer") ~ "continuous",
      r_class %in% c("factor", "character", "haven_labelled") & n_unique == 2 ~ "binary",
      r_class %in% c("factor", "character", "haven_labelled") & n_unique <= 10 ~ "categorical",
      r_class %in% c("factor", "character", "haven_labelled") ~ "high_cardinality_string",
      r_class %in% c("Date", "POSIXct", "POSIXlt") ~ "date",
      TRUE ~ "other"
    )
  )

print(var_types, n = Inf)
```

Use the empirical types to refine Y/X/M/W role classification:
- Binary variables → natural Y for logistic models or natural W for subgroup analysis
- Count variables → Y for Poisson/negative binomial models
- Continuous variables → Y for linear models or X for dose-response
- High-cardinality strings → likely ID or context variables, not analytic
- Variables with >50% missing → flag for caution in data readiness ratings

If `SAFETY_STATUS=LOCAL_MODE`, wrap the entire script in `Rscript -e "..."` via Bash.

**2c. Identify "star variables"** — variables that are:
- Rarely available in other datasets (unique to this data)
- Measured with unusual precision or granularity
- Enable causal identification (instruments, pre-treatment measures, panel variation)
- Capture mechanisms that are typically unobserved

Flag these as HIGH-POTENTIAL for RQ generation.

Present a summary:

```
===== VARIABLE INVENTORY =====

Total variables: [N]
- Outcomes (Y): [count] — [top 5 listed]
- Predictors (X): [count] — [top 5 listed]
- Mechanisms (M): [count] — [top 5 listed]
- Moderators (W): [count] — [top 5 listed]
- Confounders (C): [count]
- Context (Z): [count]
- Demographics (D): [count]

★ Star variables (high-potential):
1. [variable] — [why it's special]
2. [variable] — [why it's special]
...
```

### Step 3: Thematic Clustering

Group variables into **thematic clusters** — sets of variables that naturally belong together and could form the core of a research question.

For each cluster:
- **Cluster name** (e.g., "Labor market outcomes", "Social network measures", "Health behaviors")
- **Variables included** (list)
- **Theoretical domain** (which subfield does this cluster speak to)
- **Potential role** (is this cluster mostly Y-type, X-type, M-type?)

Aim for 5-8 clusters. Within each cluster, note which variables are the strongest candidates for Ys, Xs, and Ms.

### Step 4: Combinatorial RQ Generation

Use [references/brainstorm-patterns.md](references/brainstorm-patterns.md) Sections 3-6 to systematically generate candidate research questions.

**Apply ALL SIX generation strategies** from the reference file:
- **Strategy A (Y-First):** Start from the strongest outcome variables; identify the most theoretically interesting predictors
- **Strategy B (X-First):** Start from star variables and unique predictors; brainstorm outcomes
- **Strategy C (Gap-Driven):** Find variable pairs rarely studied together but theoretically linked
- **Strategy D (Heterogeneity-Driven):** Take established relationships; add moderators available in the data
- **Strategy E (Temporal/Change-Driven):** If panel data, exploit longitudinal structure
- **Strategy F (Methodological Innovation):** Find natural experiments, instruments, or discontinuities in the data

**Also apply Cross-Domain Puzzle Templates** (Section 5): look for anomalies, divergent trends, surprising nulls, reversals, and mechanism mismatches that the data could reveal.

**Generate 15-20 candidate RQs.** For each candidate:
- State the RQ using a formula from [references/brainstorm-patterns.md](references/brainstorm-patterns.md) Section 4
- Name the specific variables: X, Y, M (if applicable), W (if applicable)
- Name the generation strategy used (A-F)
- Assign a preliminary **theoretical motivation** (1-2 sentences: what debate or gap does this address?)
- Rate **data readiness**: HIGH (all key variables available and well-measured), MEDIUM (key variables available but proxied or noisy), LOW (important variable missing or severely limited)

Present as a numbered table:

```
===== CANDIDATE RESEARCH QUESTIONS (15-20) =====

| # | RQ | X → Y (via M, mod W) | Strategy | Domain | Data Readiness | Theoretical Motivation |
|---|----|-----------------------|----------|--------|----------------|----------------------|
| 1 | [full RQ text] | [X] → [Y] via [M], mod [W] | [A-F] | [domain] | [H/M/L] | [1-2 sentences] |
| 2 | ... | ... | ... | ... | ... | ... |
...
```

### Step 4b: Quick Empirical Signal Tests (DATA mode only)

**If MATERIALS mode: skip this step entirely.** Display:

```
===== EMPIRICAL SIGNAL TABLE =====

⏭  Skipped — MATERIALS mode (no data files provided).
   Scoring in Step 6 will use 5-criterion weights (no empirical signal weight).
```

**If DATA mode:** Run quick bivariate tests on the actual data for each of the 15-20 candidate RQs to check for empirical signal. These are exploratory, bivariate-only tests — not final analyses.

Use [references/brainstorm-patterns.md](references/brainstorm-patterns.md) Section 8 for test selection and effect size thresholds.

**MANDATORY: Save the signal-test script to disk BEFORE executing it.** Every DATA-mode invocation must leave behind a reproducible, protocol-compliant R script at:

```
${PROJ}/scripts/brainstorm-signal-tests.R
```

This holds in every `SAFETY_STATUS` branch — `CLEARED`, `OVERRIDE`, `ANONYMIZED`, **and `LOCAL_MODE`**. The script is then executed via `Rscript <path>` (file-based, never via `Rscript -e "..."` heredoc), so the exact code that produced the Empirical Signal Table is preserved for:
- scholar-replication BUILD (which expects analysis scripts under `${PROJ}/scripts/`)
- scholar-code-review (which audits all analysis scripts in a project)
- Any downstream re-running or debugging of the signal tests

**Why this is MANDATORY even though Step 4b is exploratory:** the broader scholar-skill ecosystem assumes every data-touching operation leaves a persistent script. An inline Rscript heredoc produces correct numbers but no auditable artifact, which silently breaks reproducibility downstream.

**Protocol-compliance checklist — every generated script MUST satisfy ALL of:**

1. Uses `effectsize::cohens_d()`, `effectsize::eta_squared()`, `effectsize::cramers_v()` (NOT base R shortcuts). Pearson `r` may use `cor.test()`.
2. Every test is wrapped in `tryCatch()` so a single failing candidate cannot crash the rest of the run — failed tests are recorded with `test_type = "ERROR"` and `signal = paste("Error:", e$message)`.
3. Builds the `signal_results` tibble with the EXACT columns specified below: `rq`, `x_var`, `y_var`, `test_type`, `estimate`, `effect_size`, `effect_value`, `p_value`, `n_obs`, `signal`.
4. Applies the EXACT signal-rating thresholds from the `case_when()` block below — do NOT rate by eye. The thresholds are:
   - **STRONG**: `p < 0.01` AND medium-or-larger effect (|r|≥0.3, |d|≥0.5, η²≥0.06, |AME|≥0.05, V≥0.3, |log(IRR)|≥0.3)
   - **MODERATE**: `p < 0.05` AND small-or-larger effect (|r|≥0.1, |d|≥0.2, η²≥0.01, |AME|≥0.02, V≥0.1, |log(IRR)|≥0.1)
   - **MECHANISM PLAUSIBLE**: `test_type == "correlation_chain"` AND `p < 0.10`
   - **MODERATION DETECTED**: `test_type == "interaction"` AND `p < 0.10`
   - **WEAK**: `p < 0.10` with effect below MODERATE thresholds
   - **NULL**: `p ≥ 0.10`
   - **UNTESTABLE**: `p_value` or `effect_value` is `NA`

**Test selection matrix** (Y-type × X-type → test + effect size):

| Y type | X type | Test | Effect size |
|--------|--------|------|-------------|
| Continuous | Continuous | Pearson r | r |
| Continuous | Binary | Welch t-test | Cohen's d |
| Continuous | Categorical (3+) | One-way ANOVA | η² |
| Binary | Continuous | Logistic GLM + AME | AME |
| Binary | Categorical | Chi-squared | Cramér's V |
| Count | Continuous | Poisson GLM | IRR |
| Count | Categorical | Poisson GLM | IRR |
| Any | Mechanism M | Correlation chain | r(X,M) + r(M,Y) |
| Any | Moderator W | Interaction term | p(X:W) |

**Generate a SINGLE R script** that tests all 15-20 candidates (not 20 separate Bash calls). Each test is wrapped in `tryCatch()` for graceful error handling.

**Step 4b.i — Derive the output path and create the scripts directory:**

```bash
# ── Derive ${PROJ} via the canonical helper ──
. "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"
mkdir -p "${PROJ}/scripts"
echo "Signal-test script will be saved to: ${PROJ}/scripts/brainstorm-signal-tests.R"
```

**Step 4b.ii — Write the script to disk using the Write tool** (NOT via Bash heredoc). The Write tool call must target exactly `${PROJ}/scripts/brainstorm-signal-tests.R`. The script body is the protocol-compliant template below, with one `tryCatch()` block per candidate RQ filled in from the test-selection matrix:

```r
# ── Quick Empirical Signal Tests ──
library(tidyverse)
library(haven)
library(effectsize)  # for cohens_d, eta_squared, cramers_v
library(marginaleffects)  # for AME on logistic models

df <- load_data("[DATA_FILE_PATH]")

# Initialize results table
signal_results <- tibble(
  rq = character(),
  x_var = character(),
  y_var = character(),
  test_type = character(),
  estimate = numeric(),
  effect_size = character(),
  effect_value = numeric(),
  p_value = numeric(),
  n_obs = integer(),
  signal = character()
)

# ── RQ1: [X] → [Y] ──
tryCatch({
  # [Appropriate test based on Y-type × X-type from matrix above]
  # Example for continuous Y, binary X:
  test <- t.test([Y] ~ [X], data = df)
  es <- cohens_d([Y] ~ [X], data = df)
  signal_results <- bind_rows(signal_results, tibble(
    rq = "RQ1", x_var = "[X]", y_var = "[Y]",
    test_type = "Welch t-test", estimate = test$estimate[1] - test$estimate[2],
    effect_size = "Cohen's d", effect_value = abs(as.numeric(es$Cohens_d)),
    p_value = test$p.value, n_obs = sum(!is.na(df$[Y]) & !is.na(df$[X])),
    signal = ""
  ))
}, error = function(e) {
  signal_results <<- bind_rows(signal_results, tibble(
    rq = "RQ1", x_var = "[X]", y_var = "[Y]",
    test_type = "ERROR", estimate = NA, effect_size = NA_character_,
    effect_value = NA, p_value = NA, n_obs = NA_integer_,
    signal = paste("Error:", e$message)
  ))
})

# ── Repeat for RQ2 through RQ[N] ──
# [Each RQ gets its own tryCatch block with the appropriate test]

# ── Assign signal ratings ──
signal_results <- signal_results |>
  mutate(signal = case_when(
    is.na(p_value) | is.na(effect_value) ~ "UNTESTABLE",
    # Strong: p < 0.01 AND medium+ effect size
    p_value < 0.01 & (
      (effect_size == "r" & abs(effect_value) >= 0.3) |
      (effect_size == "Cohen's d" & abs(effect_value) >= 0.5) |
      (effect_size == "eta_sq" & effect_value >= 0.06) |
      (effect_size == "AME" & abs(effect_value) >= 0.05) |
      (effect_size == "Cramer's V" & effect_value >= 0.3) |
      (effect_size == "IRR" & abs(log(effect_value)) >= 0.3)
    ) ~ "STRONG",
    # Moderate: p < 0.05 AND small+ effect size
    p_value < 0.05 & (
      (effect_size == "r" & abs(effect_value) >= 0.1) |
      (effect_size == "Cohen's d" & abs(effect_value) >= 0.2) |
      (effect_size == "eta_sq" & effect_value >= 0.01) |
      (effect_size == "AME" & abs(effect_value) >= 0.02) |
      (effect_size == "Cramer's V" & effect_value >= 0.1) |
      (effect_size == "IRR" & abs(log(effect_value)) >= 0.1)
    ) ~ "MODERATE",
    # Mechanism plausible: for M-chain tests
    test_type == "correlation_chain" & p_value < 0.10 ~ "MECHANISM PLAUSIBLE",
    # Moderation detected: for interaction tests
    test_type == "interaction" & p_value < 0.10 ~ "MODERATION DETECTED",
    # Weak: p < 0.10 but tiny effect
    p_value < 0.10 ~ "WEAK",
    # Null: p >= 0.10
    TRUE ~ "NULL"
  ))

# Print results
cat("\n===== EMPIRICAL SIGNAL TABLE =====\n\n")
print(signal_results |> select(rq, x_var, y_var, test_type, effect_size, effect_value, p_value, n_obs, signal), n = Inf)
```

**Step 4b.iii — Execute the saved script** (same invocation in every `SAFETY_STATUS` branch, including `LOCAL_MODE`):

```bash
# ── Derive ${PROJ} again — shell variables do NOT persist across Bash calls ──
. "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"
SCRIPT_PATH="${PROJ}/scripts/brainstorm-signal-tests.R"
LOG_PATH="${PROJ}/scripts/brainstorm-signal-tests.log"

# Execute the file (NOT Rscript -e heredoc) so the persistent artifact is
# exactly what ran, and stdout is teed to a log for the process record.
Rscript "${SCRIPT_PATH}" 2>&1 | tee "${LOG_PATH}"
```

**LOCAL_MODE note:** file-based execution satisfies the LOCAL_MODE contract — only the aggregated `signal_results` tibble printed by the script enters Claude's context; raw rows never do, because the script itself does not call `head(df)`, `print(df)`, or any forbidden verb. The persistent script path (`${PROJ}/scripts/brainstorm-signal-tests.R`) is REQUIRED even in LOCAL_MODE; the old "wrap in `Rscript -e` heredoc" pattern is deprecated because it left no auditable artifact for scholar-replication or scholar-code-review.

**Present the results:**

```
===== EMPIRICAL SIGNAL TABLE =====

| RQ | X | Y | Test | Effect Size | Value | p | N | Signal |
|----|---|---|------|-------------|-------|---|---|--------|
| RQ1 | [X] | [Y] | Welch t | Cohen's d | 0.42 | 0.003 | 2,847 | MODERATE |
| RQ2 | [X] | [Y] | Pearson r | r | 0.31 | <0.001 | 3,102 | STRONG |
| RQ3 | [X] | [Y] | Logistic+AME | AME | 0.08 | 0.021 | 2,953 | MODERATE |
...

Signal ratings: STRONG (p<0.01 + medium+ effect) | MODERATE (p<0.05 + small+ effect) |
MECHANISM PLAUSIBLE (M-chain p<0.10) | MODERATION DETECTED (interaction p<0.10) |
WEAK (p<0.10, tiny effect) | NULL (p≥0.10) | UNTESTABLE (error or missing vars)

⚠  CAVEATS (read before interpreting):
1. Bivariate only — no controls for confounders. Signal ≠ causal effect.
2. Multiple testing: 15-20 tests → expect ~1 false positive at α=0.05.
3. NULL ≠ uninteresting — may be underpowered, nonlinear, or context-dependent.
4. Effect sizes matter more than p-values for ranking.
5. Missing data may bias estimates — check N column for drop-off.
6. LOCAL_MODE limitation: data not inspected for outliers/coding errors.
```
