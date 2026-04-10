## COMPONENT A: Data Analytics

### A0 — Parse Arguments, Causal Gate, and Setup

**Step 1 — Detect input mode and data source:**
- File path given → load in A1 (file format: CSV / .dta / .rds / .parquet)
- Data pasted inline → write to temp file or reconstruct df from description (see A1)
- Online source named → fetch with appropriate R package in A1 (see A1 Online Data)

**Step 2 — Identify analytic variables:**
- Y (outcome), X (key predictor), C (controls), G (grouping/stratification variable)
- Panel ID and time variable if longitudinal

**Step 3 — Determine model type:**

| Outcome type | Default model | Section | Package (R) | Package (Stata) |
|---|---|---|---|---|
| Y continuous | OLS (+ HC3 SEs) | A3 | `lm`, `fixest::feols` | `regress, robust` |
| Y binary | Logit / Probit → AME | A3, A4 | `glm(family=binomial)` | `logit` / `margins` |
| Y ordered categorical | Ordered logit | A3 | `MASS::polr` | `ologit` |
| Y count | Negative binomial | A3 | `MASS::glm.nb` | `nbreg` |
| Y count (excess zeros) | Zero-inflated NB / Hurdle | A8c | `pscl::zeroinfl`, `glmmTMB` | `zinb` / `tnbreg` |
| Y proportion (0,1) | Beta regression | A8d | `betareg::betareg` | `betareg` (community) |
| Y time-to-event | Cox PH | A3 | `survival::coxph` | `stcox` |
| Y time-to-event (competing risks) | Fine-Gray subdistribution hazard | A8e | `cmprsk::crr`, `tidycmprsk` | `stcrreg` |
| Y latent classes / mixture | LCA / mixture model | A8a | `poLCA`, `tidyLCA` | `gsem` |
| Y continuous (distributional) | Quantile regression | A8b | `quantreg::rq` | `qreg` / `sqreg` |
| Panel ID + time vars | Fixed effects | A3 | `fixest::feols` | `xtreg, fe` |
| Panel + cross-lagged | RI-CLPM | A8f | `lavaan` | -- |
| Multilevel ID | Mixed effects | A3 | `lme4::lmer` | `mixed` |
| Latent constructs | Full SEM / CFA | A8h | `lavaan` | `sem` |
| Life-course trajectories | Sequence analysis | A8g | `TraMineR` | `sqtab` (community) |
| Bayesian | brms | A3b | `brms` | `bayesmh` |
| Y distributional (flexible) | GAMLSS | A8j | `gamlss` | — |
| High-dimensional controls, causal | Double ML / Causal Forest | A8k | `DoubleML`, `grf` | — (Python `econml`) |
| Growth / change over time | Growth Curve Models | A8l | `lme4`, `lavaan` | `mixed` / `sem` |
| Multilevel + latent | Multilevel SEM (MSEM) | A8m | `lavaan` (cluster), `Mplus` via `MplusAutomation` | `gsem` |
| Finite mixture of regressions | FMR | A8n | `flexmix`, `glmmTMB` | `fmm` |
| Specification robustness | Multiverse / Specification Curve | A8o | `specr`, `multiverse` | — |
| Nonparametric treatment effects | BART (Bayesian Additive Regression Trees) | A8p | `dbarts::bart`, `bartCause` | — |

Additional routing rules:
- Panel ID + time vars present → add FE options; multilevel ID → consider lme4
- Y count with excess zeros (>25% zeros) → consider zero-inflated or hurdle model (A8c)
- Y bounded on (0,1) (proportions, rates, indices) → beta regression (A8d)
- Competing events present → competing risks model (A8e)
- Latent subgroups suspected → LCA / mixture (A8a)
- Distributional heterogeneity in effects → quantile regression (A8b)
- Panel + reciprocal causal pathways → RI-CLPM (A8f)
- Life-course / trajectory data → sequence analysis (A8g)
- Latent constructs / factor structure → SEM/CFA (A8h)
- Multiple comparisons across many tests → apply p.adjust() correction (A8i)
- User requests Bayesian, informative priors, or posterior inference → brms (see A3b)
- Y has complex distributional shape (skew, kurtosis, heterogeneous variance) → GAMLSS (A8j)
- High-dimensional controls (>20 covariates) + causal question → auto-bridge to DML/Causal Forest (A8k) via `/scholar-compute MODULE 2 Step 5`
- Repeated measures + change trajectory → Growth Curve Models (A8l)
- Multilevel data + latent constructs → Multilevel SEM (A8m)
- Suspected unobserved population heterogeneity in regression slopes → Finite Mixture Regression (A8n)
- User requests specification curve, multiverse, or robustness across many specs → A8o
- Nonparametric treatment effect estimation, flexible response surface → BART (A8p)
- User requests `gt` tables → generate via `gt` alongside `modelsummary` (A6)
- User requests Stata code → generate `.do` file alongside R script (D1)

### Outcome-Type Quick Reference

| Outcome Type | Model | R Package | Stata | Key Diagnostic |
|---|---|---|---|---|
| Continuous | OLS | `lm()` / `fixest::feols()` | `reg` | VIF, Breusch-Pagan |
| Binary | Logit/Probit + AME | `glm(family=binomial)` | `logit` / `margins` | Hosmer-Lemeshow, ROC |
| Multinomial | Multinomial logit | `nnet::multinom()` | `mlogit` | IIA test (Hausman-McFadden) |
| Ordered | Ordered logit | `MASS::polr()` | `ologit` | Brant test (parallel lines) |
| Count | Poisson / NB | `glm(family=poisson)` / `MASS::glm.nb()` | `poisson` / `nbreg` | Overdispersion test |
| Zero-inflated count | ZINB / Hurdle | `pscl::zeroinfl()` / `glmmTMB()` | `zinb` / `tnbreg` | Vuong test |
| Truncated | Truncated regression | `truncreg::truncreg()` | `truncreg` | — |
| Censored (Tobit) | Tobit | `AER::tobit()` / `censReg` | `tobit` | — |
| Proportion (0,1) | Beta regression | `betareg::betareg()` | `betareg` | Link test |
| Duration/survival | Cox PH / AFT | `survival::coxph()` | `stcox` | Schoenfeld residuals |
| Competing risks | Fine-Gray | `tidycmprsk::crr()` | `stcrreg` | CIF plots |

**Step 4 — Causal design gate (CRITICAL):**

Scan the argument for causal design keywords. If ANY of the following are present — `causal`, `effect of`, `impact of`, `DiD`, `difference-in-differences`, `fixed effects` (used for causal ID), `RD`, `regression discontinuity`, `IV`, `instrumental variable`, `matching`, `synthetic control`, `mediation`, or if the research question asks whether X *causes* Y — **stop and invoke `/scholar-causal` first**:

```
CAUSAL DESIGN DETECTED: [describe the design]

Before running analysis, invoke:
/scholar-causal [treatment] → [outcome]; [design type]; [key confounder]

/scholar-causal will:
  1. Draw the DAG and identify backdoor paths
  2. Select the appropriate identification strategy
  3. Provide the exact model specification + diagnostics
  4. Run sensitivity analysis (Oster delta / E-values / placebo tests)

Resume /scholar-analyze once /scholar-causal has confirmed the identification strategy.
If /scholar-causal has already been run, paste its identification strategy here and proceed.
```

If the user confirms `/scholar-causal` was already run, or the analysis is purely descriptive/predictive (no causal claim), proceed directly.

**Step 5 — Confirm target journal** (drives reporting norms in Component C)

**Step 6 — Create output directories:**
```bash
# Re-derive ${PROJ} via the canonical helper so this writes to
# output/<slug>/ (scholar-init context) or output/_staging (legacy),
# NOT a bare `output/tables/` at the project root.
. "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"
mkdir -p "${PROJ}/tables" "${PROJ}/figures" "${PROJ}/scripts"
```

---

### A1 — Data Loading and Inspection

**PREREQUISITE:** Step 0 (Data Safety Gate) in SKILL.md must have run and `SAFETY_STATUS` must be set. If it is not set, STOP and run the gate. Do not load data without it.

#### Mode 1 — Local file

**Branch on `SAFETY_STATUS`.** The policy is defined in `.claude/skills/_shared/data-handling-policy.md` §3.

##### Mode 1a — CLEARED / ANONYMIZED / OVERRIDE (in-context loader)

When `SAFETY_STATUS ∈ {CLEARED, ANONYMIZED, OVERRIDE}`, the user has authorized the data to enter the Anthropic API. Standard loader applies.

**R:**
```r
library(tidyverse); library(haven); library(skimr); library(arrow)

df <- switch(tools::file_ext(data_path),
  "csv"     = readr::read_csv(data_path),
  "dta"     = haven::read_dta(data_path),
  "rds"     = readRDS(data_path),
  "parquet" = arrow::read_parquet(data_path)
)
```

**Python:**
```python
import pandas as pd
ext = data_path.rsplit('.', 1)[-1]
df = {'csv': pd.read_csv, 'dta': pd.read_stata,
      'parquet': pd.read_parquet}[ext](data_path)
```

##### Mode 1b — LOCAL_MODE (Bash-only loader, summary output only)

When `SAFETY_STATUS=LOCAL_MODE`, the data file must never enter Claude's context. Do NOT call the `Read` tool on the file, do NOT run the CLEARED loader above, do NOT print `head(df)` / `df.head()` / `print(df)` / `View(df)`.

Instead, wrap the load + entire analytic pipeline in a single `Rscript -e "..."` (or `python -c "..."`) Bash call. Only aggregated output may be printed to stdout.

**R — LOCAL_MODE template:**
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
    xlsx    = readxl::read_excel(path),
    xls     = readxl::read_excel(path),
    parquet = arrow::read_parquet(path),
    stop("Unsupported extension: ", ext)
  )
}

df <- load_data("[DATA_FILE_PATH]")

# Safe summary output ONLY
cat("N =", nrow(df), "\n")
cat("Variables =", ncol(df), "\n")
cat("Columns:\n", paste(names(df), collapse = ", "), "\n\n")
str(df, list.len = ncol(df), give.attr = FALSE)
cat("\n---- Missingness (%) ----\n")
print(round(colMeans(is.na(df)) * 100, 1))
cat("\n---- skimr summary ----\n")
print(skim(df))
# DO NOT: head(df), print(df), View(df), df[1:5,]
'
```

**Python — LOCAL_MODE template:**
```bash
python3 - << 'PY'
import pandas as pd, os, sys
path = "[DATA_FILE_PATH]"
ext = os.path.splitext(path)[1].lower().lstrip(".")
loaders = {"csv": pd.read_csv, "tsv": lambda p: pd.read_csv(p, sep="\t"),
           "dta": pd.read_stata, "xlsx": pd.read_excel, "xls": pd.read_excel,
           "parquet": pd.read_parquet}
if ext not in loaders:
    sys.exit(f"Unsupported extension: {ext}")
df = loaders[ext](path)
print(f"N = {len(df)}")
print(f"Variables = {df.shape[1]}")
print("Columns:", ", ".join(df.columns))
print(df.dtypes)
print("Missingness:")
print(df.isna().mean().round(3))
print(df.describe(include="all").T)
# DO NOT: df.head(), print(df), df.sample()
PY
```

**All downstream A3–A8 model code under LOCAL_MODE** must be appended to the SAME `Rscript -e` / `python3 -` heredoc and emit only coefficient tables, SEs, test statistics, and fit indices — never row-level output, never `broom::augment()` without aggregation. Save the script to `output/[slug]/scripts/` exactly as in CLEARED mode (the code is not sensitive, only the data is).

**Small-cell suppression.** When producing cross-tabs or group counts under LOCAL_MODE, suppress any cell with `n < 10`. Example:
```r
tab <- table(df$x, df$y)
tab[tab < 10] <- NA   # suppress small cells before printing
print(tab)
```

**Figures under LOCAL_MODE.** Save figures to `output/[slug]/figures/` as usual, but do NOT embed the image in the conversation. Report only the file path and the caption.

#### Mode 2 — Inline / pasted data

If the user pasted raw data (CSV rows, a markdown table, or a variable summary), write it to a temp file first, then load:

```r
# If user pasted CSV rows — write to temp and load
tmp <- tempfile(fileext = ".csv")
writeLines(c(
  "id,y,x,group",        # replace with actual header
  "1,3.2,1,A",           # replace with actual rows
  "2,4.1,0,B"
), tmp)
df <- readr::read_csv(tmp)

# If user described variable summaries only (no raw rows):
# Reconstruct illustrative data for code demonstration;
# note to user that results are illustrative pending actual data.
```

#### Mode 3 — Online data sources

Use the appropriate R package to fetch directly. Do NOT ask user to download manually.

**API key pre-check (run before fetch):** Some sources require API keys. Check `.Renviron` or env vars first:

```r
# Check if key is available
has_census_key <- nchar(Sys.getenv("CENSUS_API_KEY")) > 0
has_fred_key   <- nchar(Sys.getenv("FRED_API_KEY")) > 0
```

If the required key is missing, **ask the user to provide it** before falling back to CODE-TEMPLATE:

```
To download [ACS/FRED] data, I need an API key.
You can get a free key here: [signup URL]
Please provide your key, or I can produce code templates instead.
```

| Source | Env variable | Free key signup |
|--------|-------------|-----------------|
| ACS / Census (`tidycensus`) | `CENSUS_API_KEY` | https://api.census.gov/data/key_signup.html |
| FRED (`fredr`) | `FRED_API_KEY` | https://fred.stlouisfed.org/docs/api/api_key.html |

**Sources that need NO API key:** NHANES (`nhanesA`), GSS (`gssr`), World Bank (`WDI`), Google Trends (`gtrendsR`), BLS v1 (`blsAPI`), direct-URL datasets. Always attempt these without prompting.

If the user provides a key, set it and proceed:
```r
Sys.setenv(CENSUS_API_KEY = "[user-provided-key]")
census_api_key(Sys.getenv("CENSUS_API_KEY"), install = TRUE)  # persist for future sessions
```

**NHANES (CDC — health surveys):**
```r
library(nhanesA)
# List available tables for a cycle
nhanesTables('DEMO', 2017)

# Download specific tables and merge
demo  <- nhanes('DEMO_J')   # Demographics, 2017-18 cycle
bmx   <- nhanes('BMX_J')    # Body measures
paq   <- nhanes('PAQ_J')    # Physical activity
df    <- Reduce(function(a,b) merge(a, b, by="SEQN", all=FALSE),
                list(demo, bmx, paq))
cat("NHANES 2017-2018 merged N =", nrow(df), "\n")
```

**ACS / Decennial Census (tidycensus):**
```r
library(tidycensus)
# census_api_key("YOUR_KEY", install = TRUE)  # one-time setup

df <- get_acs(
  geography = "tract",
  variables = c(medinc = "B19013_001", pop = "B01003_001"),
  state     = "CA",
  year      = 2022,
  geometry  = FALSE
)
```

**GSS (General Social Survey):**
```r
library(gssr)
data(gss_all)        # all waves 1972–2022
df <- gss_all |>
  filter(year >= 2010) |>
  select(year, id, race, educ, income06, trust, polviews)
```

**World Bank (WDI):**
```r
library(WDI)
df <- WDI(
  country   = "all",
  indicator = c(gdppc = "NY.GDP.PCAP.KD", life_exp = "SP.DYN.LE00.IN"),
  start     = 2000, end = 2022,
  extra     = TRUE     # adds region, income group
)
```

**FRED (economic time series):**
```r
library(fredr)
# fredr_set_key("YOUR_FRED_KEY")   # one-time setup
df <- fredr(series_id = "UNRATE", observation_start = as.Date("2000-01-01"))
```

**IPUMS microdata (downloaded extract):**
```r
library(ipumsr)
ddi <- read_ipums_ddi("usa_00001.xml")   # from downloaded IPUMS extract
df  <- read_ipums_micro(ddi)
```

**Raw URL (GitHub, OSF, Dataverse, Dropbox direct link):**
```r
url <- "https://raw.githubusercontent.com/user/repo/main/data.csv"
df  <- readr::read_csv(url)
# For .dta files hosted online:
tmp <- tempfile(fileext = ".dta")
download.file(url, tmp, mode = "wb")
df  <- haven::read_dta(tmp)
```

**Python equivalents for online sources:**
```python
import pandas as pd

# Direct URL
df = pd.read_csv("https://raw.githubusercontent.com/.../data.csv")

# World Bank via wbgapi
import wbgapi as wb
df = wb.data.DataFrame(['NY.GDP.PCAP.KD', 'SP.DYN.LE00.IN'],
                        time=range(2000, 2023))

# FRED via fredapi
from fredapi import Fred
fred = Fred(api_key='YOUR_KEY')
df = fred.get_series('UNRATE').reset_index()
df.columns = ['date', 'unemployment']
```

#### Inspect after loading (all modes)

```r
glimpse(df)
skimr::skim(df)
cat("Dimensions:", nrow(df), "x", ncol(df), "\n")
cat("Missingness:\n"); print(colSums(is.na(df)))
```

```python
print(df.shape); print(df.info())
print(df.describe(include='all').T)
print(df.isnull().sum())
```

Output: dataset dimensions, variable types, missingness counts, distribution summaries.

---

### A2 — Descriptive Statistics Table (Table 1)

**R (primary — gtsummary):**
```r
library(gtsummary); library(gt)

tbl1 <- df |>
  select(all_of(c(outcome, key_vars, controls))) |>
  tbl_summary(
    by        = group_var,          # omit if no grouping
    statistic = list(
      all_continuous()  ~ "{mean} ({sd})",
      all_categorical() ~ "{n} ({p}%)"
    ),
    digits    = all_continuous() ~ 2,
    missing   = "ifany"
  ) |>
  add_overall() |>
  add_p() |>
  bold_labels()

# Export — HTML, TeX, and docx
tbl1 |> as_gt() |>
  gt::gtsave(paste0(output_root, "/tables/table1-descriptives.html"))
tbl1 |> as_kable_extra(format = "latex") |>
  writeLines(paste0(output_root, "/tables/table1-descriptives.tex"))
tbl1 |> as_flex_table() |>
  flextable::save_as_docx(path = paste0(output_root, "/tables/table1-descriptives.docx"))
```

**Alternative (modelsummary):**
```r
library(modelsummary)
datasummary_skim(df, output = paste0(output_root, "/tables/table1-descriptives.html"))
datasummary_skim(df, output = paste0(output_root, "/tables/table1-descriptives.docx"))
datasummary_balance(~ group_var, data = df,
                    output = paste0(output_root, "/tables/table1-balance.html"))
datasummary_balance(~ group_var, data = df,
                    output = paste0(output_root, "/tables/table1-balance.docx"))
```

---

### A2b — Multiple Imputation for Missing Data

**When to use**: If >5% missing on any key variable AND missingness is MAR (not MCAR). Run Little's MCAR test first (see scholar-eda). If MCAR, listwise deletion is defensible; if MAR, use MI.

**R workflow (mice)**:
```r
library(mice)

# 1. Inspect missingness pattern
md.pattern(df)

# 2. Run MI (m=20 imputations, predictive mean matching for continuous)
imp <- mice(df, m = 20, method = "pmm", seed = 42, maxit = 20)

# 3. Fit model on each imputed dataset
fit <- with(imp, lm(y ~ x1 + x2 + x3))

# 4. Pool results (Rubin's rules)
pooled <- pool(fit)
summary(pooled, conf.int = TRUE)

# 5. Diagnostics
densityplot(imp)       # Compare imputed vs. observed distributions
stripplot(imp)         # Strip plots by imputation
convergence: plot(imp) # Trace plots should show no trend
```

**Stata**:
```stata
mi set flong
mi register imputed x1 x2 x3
mi impute chained (pmm) x1 x2 (logit) x3_binary = y x4, add(20) rseed(42)
mi estimate: regress y x1 x2 x3 x4
```

**Reporting template**: "Missing data on [variables] ranged from [X%] to [Y%]. We used multiple imputation with chained equations (m = 20 datasets) under a missing-at-random assumption. Results were pooled using Rubin's (1987) rules."

**Sensitivity to MNAR**: Run Heckman selection model or delta-adjustment (shift imputed values by delta = 0.5 SD) to test sensitivity of key results.

---
