---
name: scholar-analyze
description: "Run data analytics and produce publication-quality tables and visualizations for social science research. Saves regression tables (HTML/TeX/docx), figures (PDF/PNG), an internal analysis log, and a publication-ready Results document (prose + table notes + figure captions). Accepts file paths, inline/pasted data, or fetches from online sources (NHANES, IPUMS, GSS, World Bank, etc.). Runs A9/B9 verification subagents to check analytic and visualization correctness. For causal designs, invokes /scholar-causal first. Use after /scholar-design."
tools: Read, Bash, Write, WebSearch
argument-hint: "[data source + model spec, e.g., 'NHANES 2017-2018, OLS of BMI on physical activity by race for Demography' or 'data.csv, fixed effects of education on earnings for ASR']"
user-invocable: true
---

# Scholar Data Analysis and Results

You are an expert quantitative sociologist who **runs executable analyses**, produces publication-quality tables and figures, and writes journal-ready Results sections. You follow reporting standards for ASR, AJS, Demography, Science Advances, and Nature journals.

## Arguments

The user has provided: `$ARGUMENTS`

Parse this carefully across **three possible input modes**:

**Mode 1 — File path:** a local path to a dataset (`.csv`, `.dta`, `.rds`, `.parquet`). Load directly in A1.

**Mode 2 — Inline/pasted data:** the user has pasted rows of data, a data frame summary, or variable descriptions directly in the argument. Write the data to a temp file or reconstruct the data frame from the description, then proceed to A1.

**Mode 3 — Online source:** the user names a public dataset (NHANES, IPUMS, GSS, ACS/Census, FRED, World Bank, etc.) without providing a local file. Fetch the data in A1 using the appropriate R package or API (see A1 Online Data section). Confirm the fetch succeeded before proceeding.

Regardless of mode, identify: outcome variable (Y), key predictor(s) (X), controls (C), grouping variable (G), and target journal.

## Setup

Create output directories before any analysis:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/tables" "${OUTPUT_ROOT}/figures" "${OUTPUT_ROOT}/scripts" "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-analyze"
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
SKILL_NAME="scholar-analyze"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}"/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

---

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
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/tables" "${OUTPUT_ROOT}/figures" "${OUTPUT_ROOT}/scripts"
```

---

### A1 — Data Loading and Inspection

#### Mode 1 — Local file

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

### A3 — Regression Models

Run a progressive model ladder: M1 (baseline — Y ~ X), M2 (+ controls), M3 (+ interactions or FE).

**OLS with HC3 robust SEs:**
```r
library(sandwich); library(lmtest)

m1 <- lm(y ~ x, data = df)
m2 <- lm(y ~ x + controls, data = df)
m3 <- lm(y ~ x * moderator + controls, data = df)

# Robust SEs
coeftest(m2, vcov = vcovHC(m2, type = "HC3"))
```

**OLS with two-way fixed effects (fixest — preferred for panel):**
```r
library(fixest)

m_fe <- feols(y ~ x + controls | unit_id + year,
              data    = df,
              cluster = ~unit_id)
summary(m_fe)
```

**Random effects (RE) panel**:
```r
library(plm)
re_mod <- plm(y ~ x1 + x2, data = pdata, model = "random")
summary(re_mod)

# Hausman test: FE vs. RE
phtest(fe_mod, re_mod)  # p < 0.05 → use FE
```

**Arellano-Bond dynamic panel (GMM)**:
```r
library(plm)
ab_mod <- pgmm(y ~ lag(y, 1) + x1 + x2 | lag(y, 2:99),
               data = pdata, effect = "twoways", model = "twosteps")
summary(ab_mod)
# AR(1) should be significant, AR(2) should NOT be significant
# Sargan/Hansen J test: p > 0.05 (instruments are valid)
```

**Stata**:
```stata
xtabond2 y L.y x1 x2, gmm(L.y, lag(2 .)) iv(x1 x2) twostep robust
estat abond   // AR tests
estat sargan  // overidentification
```

**Logit / probit — ALWAYS compute AME (see A4), never report raw log-odds in sociology journals:**
```r
m_logit  <- glm(y ~ x + controls, family = binomial(link = "logit"),  data = df)
m_probit <- glm(y ~ x + controls, family = binomial(link = "probit"), data = df)
```

**Ordered logit:**
```r
library(MASS)
m_ologit <- polr(as.factor(y) ~ x + controls, data = df, Hess = TRUE)
```

**Multilevel / mixed effects:**
```r
library(lme4); library(lmerTest); library(performance)

m_mlm <- lmer(y ~ x + controls + (1 | group_id), data = df)
summary(m_mlm)
performance::icc(m_mlm)   # intraclass correlation
```

**Crossed random effects** (e.g., students in schools AND neighborhoods):
```r
crossed_mod <- lmer(y ~ x1 + x2 + (1 | school_id) + (1 | neighborhood_id), data = df)
summary(crossed_mod)
# ICC for each grouping:
performance::icc(crossed_mod)
```

**Survival (Cox PH):**
```r
library(survival)

m_cox <- coxph(Surv(time, event) ~ x + controls, data = df, robust = TRUE)
cox.zph(m_cox)   # test proportional hazards assumption
```

**Negative binomial (count outcome):**
```r
library(MASS)
m_nb <- glm.nb(y ~ x + controls, data = df)
```

---

### A3b — Bayesian Regression (brms / rstanarm)

Use when: (1) user explicitly requests Bayesian analysis, (2) small-sample inference where frequentist CIs are unreliable, (3) informative priors from prior literature, (4) complex multilevel structures, (5) posterior predictive checks for model adequacy. Increasingly accepted in top sociology journals (ASR, AJS, Demography) and required for some Bayesian-focused submissions (e.g., *Sociological Methodology*).

**Step 1 — Prior specification:**
```r
library(brms)

# Weakly informative priors (default recommendation)
priors_weak <- c(
  prior(normal(0, 5),   class = "b"),          # regression coefficients
  prior(student_t(3, 0, 2.5), class = "Intercept"),
  prior(exponential(1), class = "sigma")        # residual SD
)

# Informative priors from prior literature
# Example: prior study found beta = 0.3, SE = 0.1
priors_informed <- c(
  prior(normal(0.3, 0.1), class = "b", coef = "x"),
  prior(normal(0, 5),     class = "b"),  # other coefficients: weakly informative
  prior(student_t(3, 0, 2.5), class = "Intercept"),
  prior(exponential(1),   class = "sigma")
)

# Prior predictive check (ALWAYS run before fitting)
m_prior <- brm(y ~ x + controls, data = df,
               prior = priors_weak,
               sample_prior = "only",
               chains = 4, iter = 2000, seed = 42)
pp_check(m_prior, ndraws = 100)  # do simulated outcomes look reasonable?
```

**Step 2 — Fit model:**
```r
# Gaussian (continuous Y)
m_bayes <- brm(y ~ x + controls, data = df,
               prior   = priors_weak,
               chains  = 4,
               iter    = 4000,
               warmup  = 1000,
               cores   = 4,
               seed    = 42,
               backend = "cmdstanr")   # faster than default rstan

# Logistic (binary Y)
m_bayes_logit <- brm(y ~ x + controls, data = df,
                     family = bernoulli(link = "logit"),
                     prior  = priors_weak,
                     chains = 4, iter = 4000, warmup = 1000,
                     cores = 4, seed = 42, backend = "cmdstanr")

# Multilevel
m_bayes_mlm <- brm(y ~ x + controls + (1 + x | group_id), data = df,
                   prior  = priors_weak,
                   chains = 4, iter = 4000, warmup = 1000,
                   cores = 4, seed = 42, backend = "cmdstanr",
                   control = list(adapt_delta = 0.95))

# Ordinal
m_bayes_ord <- brm(y ~ x + controls, data = df,
                   family = cumulative("logit"),
                   chains = 4, iter = 4000, warmup = 1000,
                   cores = 4, seed = 42, backend = "cmdstanr")

# Count (negative binomial)
m_bayes_nb <- brm(y ~ x + controls, data = df,
                  family = negbinomial(),
                  chains = 4, iter = 4000, warmup = 1000,
                  cores = 4, seed = 42, backend = "cmdstanr")

# Zero-inflated
m_bayes_zi <- brm(bf(y ~ x + controls, zi ~ x), data = df,
                  family = zero_inflated_negbinomial(),
                  chains = 4, iter = 4000, warmup = 1000,
                  cores = 4, seed = 42, backend = "cmdstanr")

# Survival (Cox)
m_bayes_surv <- brm(time | cens(censored) ~ x + controls, data = df,
                    family = cox(),
                    chains = 4, iter = 4000, warmup = 1000,
                    cores = 4, seed = 42, backend = "cmdstanr")
```

**Step 3 — Convergence diagnostics (MANDATORY before interpreting):**
```r
# Rhat and ESS (must be Rhat < 1.01, bulk ESS > 400)
summary(m_bayes)

# Trace plots — chains should mix well
plot(m_bayes, type = "trace")

# Rank histograms (more sensitive than trace plots)
mcmc_rank_overlay(as.array(m_bayes))

# Divergent transitions check
nuts_params(m_bayes) |> filter(Parameter == "divergent__", Value == 1) |> nrow()
# If divergent > 0: increase adapt_delta to 0.99, increase max_treedepth
```

**Step 4 — Posterior predictive check:**
```r
pp_check(m_bayes, ndraws = 100)               # density overlay
pp_check(m_bayes, type = "stat", stat = "mean")  # posterior of mean
pp_check(m_bayes, type = "stat_2d")            # mean vs sd
pp_check(m_bayes, type = "intervals")          # prediction intervals per observation
```

**Step 5 — Model comparison (LOO-CV):**
```r
library(loo)
m1_loo <- loo(m_bayes_m1, moment_match = TRUE)
m2_loo <- loo(m_bayes_m2, moment_match = TRUE)
loo_compare(m1_loo, m2_loo)   # negative elpd_diff favors first model
# Report: ELPD difference and SE
```

**Step 6 — Posterior summaries and reporting:**
```r
# Posterior medians and 95% credible intervals
fixef(m_bayes)

# Probability of direction (pd) — analog of p-value
library(bayestestR)
p_direction(m_bayes)

# Region of Practical Equivalence (ROPE)
rope(m_bayes, range = c(-0.1, 0.1))   # % of posterior in negligible region

# Bayes Factor (point null)
bayesfactor_parameters(m_bayes)

# Marginal effects (same marginaleffects package)
library(marginaleffects)
avg_slopes(m_bayes)
plot_predictions(m_bayes, condition = list("x", "group"))
```

**Step 7 — Sensitivity to prior choice:**
```r
# Re-fit with vague priors
m_vague <- update(m_bayes, prior = prior(normal(0, 100), class = "b"))
# Re-fit with skeptical priors (centered at 0, tight)
m_skeptic <- update(m_bayes, prior = prior(normal(0, 0.5), class = "b"))

# Compare posteriors
library(tidybayes)
bind_rows(
  spread_draws(m_bayes,   b_x) |> mutate(prior = "Weakly informative"),
  spread_draws(m_vague,   b_x) |> mutate(prior = "Vague"),
  spread_draws(m_skeptic, b_x) |> mutate(prior = "Skeptical")
) |>
  ggplot(aes(x = b_x, fill = prior)) +
  geom_density(alpha = 0.4) +
  labs(x = "Posterior of β(x)", y = "Density") +  # NO title — goes in caption
  theme_Publication() +
  scale_fill_Publication()
ggsave(paste0(output_root, "/figures/fig-prior-sensitivity.pdf"), width = 8, height = 5)
```

**Bayesian reporting table format:**

| Parameter | Median | 95% CrI | pd | ROPE % | Prior |
|-----------|--------|---------|-----|--------|-------|
| X | 0.32 | [0.12, 0.53] | 99.8% | 2.1% | N(0, 5) |
| Control₁ | −0.15 | [−0.38, 0.07] | 91.2% | 18.4% | N(0, 5) |

*Notes: CrI = Credible Interval; pd = Probability of Direction; ROPE = Region of Practical Equivalence [−0.1, 0.1]. Estimated via brms with 4 chains × 4000 iterations (1000 warmup). All Rhat < 1.01, bulk ESS > 1000.*

**Bayesian write-up template:**
> We estimated [model type] using Bayesian regression via the brms package in R (Bürkner 2017), which interfaces with Stan (Carpenter et al. 2017). We specified [weakly informative / informative] priors: [describe priors and justification]. We ran 4 chains of 4,000 iterations each (1,000 warmup), yielding [X] effective samples. All parameters achieved Rhat < 1.01 with no divergent transitions. Posterior predictive checks confirmed adequate model fit. [Key parameter] had a posterior median of [β] (95% CrI: [lower, upper]), with [pd]% probability of the hypothesized direction. Prior sensitivity analysis with vague and skeptical priors yielded substantively similar conclusions [or: "showed sensitivity to prior choice, which we discuss in the limitations"]. Model comparison via LOO-CV favored [Model X] (ΔELPD = [value], SE = [value]).

**rstanarm alternative** (simpler syntax, pre-compiled models):
```r
library(rstanarm)
m_stan <- stan_glm(y ~ x + controls, data = df,
                   prior = normal(0, 5),
                   prior_intercept = normal(0, 10),
                   chains = 4, iter = 4000, seed = 42)
```

---

### A4 — Average Marginal Effects (REQUIRED for logistic / ordered logit in sociology journals)

`marginaleffects` is the modern standard (replaces `margins` package). Use for ANY non-linear model.

```r
library(marginaleffects)

# AME — averaged over all observations (report this in tables)
ame <- avg_slopes(m_logit)
print(ame)

# MER — at representative values
mer <- slopes(m_logit,
              newdata = datagrid(x = c(0, 1), female = c(0, 1)))

# Interaction: marginal effect of X conditional on moderator
plot_slopes(m_logit, variables = "x", condition = "moderator")

# Predicted probabilities / predicted values
plot_predictions(m_logit, condition = list("x", "group")) +
  scale_color_Publication()
```

**Key functions:**
- `avg_slopes(model)` — AME for all predictors
- `slopes(model, newdata = datagrid(...))` — effects at specified covariate values
- `avg_comparisons(model)` — average treatment contrasts
- `plot_slopes()` / `plot_predictions()` — publication-ready marginal plots
- Works uniformly across GLMs, fixest FE models, lme4, survival

---

### A5 — Model Diagnostics

**OLS:**
```r
library(car); library(lmtest)

car::vif(m2)                         # multicollinearity (VIF > 10 = problem)
lmtest::bptest(m2)                   # Breusch-Pagan heteroskedasticity test
plot(m2, which = 4)                  # Cook's D influential observations
par(mfrow = c(2,2)); plot(m2)        # residuals vs. fitted, Q-Q, scale-location
```

**Logit:**
```r
library(ResourceSelection); library(pROC)

ResourceSelection::hoslem.test(m_logit$y, fitted(m_logit))   # Hosmer-Lemeshow
pROC::auc(m_logit$y, fitted(m_logit))                        # ROC-AUC
```

**Panel:**
```r
library(plm)

plm::phtest(m_fe, m_re)              # Hausman FE vs. RE test
plm::pbgtest(m_panel)                # Wooldridge serial correlation test
```

**Survival:**
```r
schoenfeld <- cox.zph(m_cox)
print(schoenfeld)
plot(schoenfeld)                     # Schoenfeld residuals by variable
```

**Model diagnostic plots** (required for reviewer requests):
```r
# Q-Q plot for normality of residuals
qqnorm(residuals(mod)); qqline(residuals(mod))

# Scale-location plot (heteroscedasticity)
plot(fitted(mod), sqrt(abs(rstandard(mod))), main = "Scale-Location")
abline(h = mean(sqrt(abs(rstandard(mod)))), col = "red")

# Residuals vs. fitted (Tukey-Anscombe)
plot(fitted(mod), residuals(mod), main = "Residuals vs Fitted")
abline(h = 0, col = "red")

# Cook's distance
plot(cooks.distance(mod), type = "h", main = "Cook's Distance")
abline(h = 4/nrow(df), col = "red", lty = 2)

# All four in one:
par(mfrow = c(2, 2)); plot(mod); par(mfrow = c(1, 1))
```

**RESET test** (functional form misspecification):
```r
library(lmtest)
resettest(mod, power = 2:3, type = "fitted")
# p < 0.05 → functional form may be misspecified; consider quadratic terms or log transform
```

---

### A6 — Export Regression Tables

**modelsummary (primary — HTML + LaTeX + docx):**
```r
library(modelsummary)

models <- list("Baseline" = m1, "+Controls" = m2, "+Interaction" = m3)
ms_args <- list(
  stars     = c("*" = .05, "**" = .01, "***" = .001),
  gof_map   = c("nobs", "r.squared", "adj.r.squared"),
  coef_omit = "Intercept",
  notes     = "HC3 robust SEs in parentheses."
)

modelsummary(models, output = paste0(output_root, "/tables/table2-regression.html"), !!!ms_args)
modelsummary(models, output = paste0(output_root, "/tables/table2-regression.tex"),  !!!ms_args)
modelsummary(models, output = paste0(output_root, "/tables/table2-regression.docx"), !!!ms_args)
```

**AME table (for logit / ordered logit):**
```r
ame_args <- list(
  stars  = c("*" = .05, "**" = .01, "***" = .001),
  notes  = "Average marginal effects; 95% CIs in brackets."
)
modelsummary(avg_slopes(m_logit), output = paste0(output_root, "/tables/table2-ame.html"),  !!!ame_args)
modelsummary(avg_slopes(m_logit), output = paste0(output_root, "/tables/table2-ame.tex"),   !!!ame_args)
modelsummary(avg_slopes(m_logit), output = paste0(output_root, "/tables/table2-ame.docx"),  !!!ame_args)
```

---

### A7 — Robustness Checks

```r
library(sensemakr)

# Alternative sample
m_rob1 <- update(m2, data = filter(df, !outlier_flag))

# Alternative specification
m_rob2 <- update(m2, . ~ . - treatment + treatment_alt)

# Oster (2019) delta — OVB sensitivity for OLS
sm <- sensemakr(model               = m2,
                treatment            = "x",
                benchmark_covariates = "education",
                kd                   = 1:3)
ovb_minimal_reporting(sm)

# Export robustness table — HTML + TeX + docx
rob_models <- list("Main" = m2, "No outliers" = m_rob1, "Alt measure" = m_rob2)
rob_args   <- list(
  stars = c("*" = .05, "**" = .01, "***" = .001),
  notes = "HC3 robust SEs. Column 3 uses alternative treatment measure."
)
modelsummary(rob_models, output = paste0(output_root, "/tables/tableA1-robustness.html"), !!!rob_args)
modelsummary(rob_models, output = paste0(output_root, "/tables/tableA1-robustness.tex"),  !!!rob_args)
modelsummary(rob_models, output = paste0(output_root, "/tables/tableA1-robustness.docx"), !!!rob_args)
```

**E-values for unmeasured confounding** (VanderWeele & Ding 2017):
```r
library(EValue)
# For point estimate (RR or OR):
evalues.RR(est = 1.5, lo = 1.2, hi = 1.9)
# Interpretation: An unmeasured confounder would need to be associated with
# both treatment and outcome by a risk ratio of [E-value] to explain away
# the observed effect. Compare to plausible confounders.
```

---

### A8 — Oaxaca-Blinder Decomposition (Demography / stratification papers)

```r
library(oaxaca)

ob <- oaxaca(outcome ~ predictors | group_var, data = df, R = 100)
summary(ob)
plot(ob)
```

Reports: overall gap, endowment component (explained), coefficient component (unexplained), interaction component.

---

### A8a — Latent Class Analysis (LCA) / Mixture Models

Use when the research question asks about unobserved subgroups or typologies (e.g., "What distinct patterns of health behavior exist among older adults?"). Common in Demography, ASR, and NHB.

**R (poLCA — categorical indicators):**
```r
library(poLCA)

# Define formula: all manifest indicators, no covariates in class model
f_lca <- cbind(item1, item2, item3, item4, item5) ~ 1

# Fit models with 2–6 classes and compare BIC
lca_results <- list()
for (k in 2:6) {
  set.seed(42)
  lca_results[[k]] <- poLCA(f_lca, data = df, nclass = k, nrep = 20,
                             maxiter = 5000, verbose = FALSE)
}

# BIC comparison table for class selection
bic_table <- data.frame(
  Classes = 2:6,
  AIC     = sapply(lca_results[2:6], \(m) m$aic),
  BIC     = sapply(lca_results[2:6], \(m) m$bic),
  Entropy = sapply(lca_results[2:6], function(m) {
    pp <- m$posterior
    1 - (-sum(pp * log(pp + 1e-10)) / (nrow(pp) * log(ncol(pp))))
  }),
  LogLik  = sapply(lca_results[2:6], \(m) m$llik)
)
print(bic_table)

# Select best model (lowest BIC; entropy > 0.8 preferred)
best_k <- bic_table$Classes[which.min(bic_table$BIC)]
m_lca  <- lca_results[[best_k]]

# Class-specific item probabilities
plot(m_lca)

# Posterior class assignment
df$lca_class <- factor(m_lca$predclass)

# 3-step approach: relate class membership to covariates
# (avoids bias from simultaneous estimation)
library(nnet)
m_3step <- multinom(lca_class ~ age + female + education, data = df)
summary(m_3step)
```

**R (tidyLCA — continuous indicators / Gaussian mixture):**
```r
library(tidyLPA)

# Fit profiles with 2–5 classes, varying model specifications
lpa_fit <- df |>
  select(var1, var2, var3, var4) |>
  estimate_profiles(2:5,
    variances  = "varying",
    covariances = "zero"  # Model 2 in Mplus; use "varying" for Model 6
  )

# Compare fit indices
get_fit(lpa_fit)

# Extract best model
best_lpa <- get_data(lpa_fit) |> filter(classes_number == best_k)
```

**Stata:**
```stata
* Gaussian mixture (LPA)
gsem (var1 var2 var3 var4 <- ), lclass(C 3) startvalues(randomid, draws(50))
estat lcprob         // class probabilities
estat lcmean         // class-specific means

* BIC comparison across class solutions
forvalues k = 2/6 {
  gsem (var1 var2 var3 var4 <- ), lclass(C `k') startvalues(randomid, draws(50))
  estimates store lca_`k'
}
estimates stats lca_*
```

**Diagnostics:**
- BIC curve: plot BIC by number of classes; select "elbow" or minimum
- Entropy > 0.8 indicates clean class separation; > 0.6 acceptable
- No class < 5% of sample (too small to interpret or replicate)
- Check convergence: multiple random starts (nrep >= 20) should yield same log-likelihood
- Examine class-specific item probabilities for substantive interpretability

**Publication table format:**
```
Table X. Latent Class Model Fit Comparison
Classes | Log-likelihood | AIC    | BIC    | Entropy | Smallest class (%)
2       | -XXXX.X        | XXXX.X | XXXX.X | 0.XX    | XX.X%
3       | -XXXX.X        | XXXX.X | XXXX.X | 0.XX    | XX.X%
...
Note: Bold indicates selected model. N = X. Models estimated with 20 random starts.

Table X+1. Class-Specific Item Response Probabilities (K-Class Model)
Item          | Class 1 (XX%) | Class 2 (XX%) | Class 3 (XX%)
Item 1 = Yes  | 0.XX          | 0.XX          | 0.XX
...
Note: Probabilities of endorsing each item conditional on class membership.
```

**Write-up template:**
> "Latent class analysis identified [K] distinct classes based on [item descriptions] (Table X). A [K]-class solution provided the best fit (BIC = [X]; entropy = [X]). Class 1 ([X]% of the sample) was characterized by [high/low patterns]; Class 2 ([X]%) by [patterns]; Class 3 ([X]%) by [patterns]. In the 3-step multinomial regression, [covariate] was associated with [higher/lower] odds of membership in Class [X] relative to the reference class (RRR = [X], 95% CI = [[lo], [hi]], p = [p])."

**Export tables:**
```r
modelsummary(m_3step,
  exponentiate = TRUE,
  stars = c("*" = .05, "**" = .01, "***" = .001),
  notes = "Relative risk ratios; 95% CIs in brackets. Reference class: Class 1.",
  output = paste0(output_root, "/tables/table-lca-covariates.html"))
modelsummary(m_3step, exponentiate = TRUE,
  output = paste0(output_root, "/tables/table-lca-covariates.tex"))
modelsummary(m_3step, exponentiate = TRUE,
  output = paste0(output_root, "/tables/table-lca-covariates.docx"))
```

---

### A8b — Quantile Regression

Use when the effect of X on Y may differ across the outcome distribution (e.g., "Does education affect earnings differently at the 10th vs. 90th percentile?"). Valuable when OLS masks heterogeneity.

**R (quantreg):**
```r
library(quantreg)

# Single quantile
m_q50 <- rq(y ~ x + controls, data = df, tau = 0.5)  # median regression
summary(m_q50, se = "boot", R = 1000)

# Simultaneous quantile estimation across the distribution
taus <- seq(0.1, 0.9, by = 0.1)
m_qr  <- rq(y ~ x + controls, data = df, tau = taus)
qr_summary <- summary(m_qr, se = "boot", R = 1000)

# Coefficient plot across quantiles
plot(qr_summary, parm = "x",
     main = "Effect of X across quantiles",
     xlab = "Quantile", ylab = "Coefficient")
abline(h = coef(lm(y ~ x + controls, data = df))["x"],
       lty = 2, col = "red")  # OLS reference

# Publication-quality ggplot version
library(broom)
qr_coefs <- purrr::map_dfr(taus, function(tau) {
  m <- rq(y ~ x + controls, data = df, tau = tau)
  s <- summary(m, se = "boot", R = 1000)
  tibble(
    tau       = tau,
    estimate  = coef(s)["x", "Value"],
    std.error = coef(s)["x", "Std. Error"],
    conf.low  = estimate - 1.96 * std.error,
    conf.high = estimate + 1.96 * std.error
  )
})

# OLS comparison line
ols_coef <- coef(lm(y ~ x + controls, data = df))["x"]

p_qr <- ggplot(qr_coefs, aes(x = tau, y = estimate)) +
  geom_ribbon(aes(ymin = conf.low, ymax = conf.high), alpha = 0.2, fill = palette_cb[1]) +
  geom_line(color = palette_cb[1], linewidth = 1) +
  geom_point(color = palette_cb[1], size = 2) +
  geom_hline(yintercept = ols_coef, linetype = "dashed", color = palette_cb[7]) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  annotate("text", x = 0.85, y = ols_coef, label = "OLS", color = palette_cb[7], vjust = -1) +
  labs(x = "Quantile (tau)", y = "Coefficient of X") +
  theme_Publication()
save_fig(p_qr, "fig-quantile-regression", width = 7, height = 5)
```

**With clustered SEs:**
```r
# Clustered bootstrap for panel / grouped data
m_qr_clust <- rq(y ~ x + controls, data = df, tau = 0.5)
summary(m_qr_clust, se = "boot", R = 1000,
        cluster = df$cluster_id)  # requires quantreg >= 5.98
```

**Stata:**
```stata
* Simultaneous quantile regression
sqreg y x controls, quantiles(10 25 50 75 90) reps(1000)
estimates table

* Individual quantile
qreg y x controls, quantile(.5)

* Coefficient plot
grqreg x, ci ols
```

**Diagnostics:**
- Compare quantile coefficients to OLS: if they differ substantially, OLS masks distributional effects
- Test equality of coefficients across quantiles: `anova(m_qr)` (joint F-test)
- Bootstrap SEs (R >= 1000) preferred over asymptotic SEs for inference
- Check for crossing quantile curves (violation if fitted quantiles cross)

**Publication table format:**
```
Table X. Quantile Regression Estimates: [Y] on [X]
                | Q10     | Q25     | Q50     | Q75     | Q90     | OLS
X               | b (SE)  | b (SE)  | b (SE)  | b (SE)  | b (SE)  | b (SE)
Control 1       | ...     | ...     | ...     | ...     | ...     | ...
N               | X       | X       | X       | X       | X       | X
Note: Bootstrap SEs (1,000 replications) in parentheses. * p < .05, ** p < .01, *** p < .001.
```

**Write-up template:**
> "Quantile regression reveals that the association between [X] and [Y] varies across the outcome distribution (Table X; Figure X). At the 10th percentile, a one-unit increase in [X] is associated with a [b] change in [Y] (b = [b], SE = [SE], p = [p]), whereas at the 90th percentile the effect is [larger/smaller/reversed] (b = [b], SE = [SE], p = [p]). The OLS estimate of [b] obscures this heterogeneity."

**Export tables:**
```r
# Collect quantile models into named list
qr_models <- setNames(
  lapply(taus, function(t) rq(y ~ x + controls, data = df, tau = t)),
  paste0("Q", taus * 100)
)
qr_models[["OLS"]] <- lm(y ~ x + controls, data = df)

modelsummary(qr_models,
  stars = c("*" = .05, "**" = .01, "***" = .001),
  notes = "Bootstrap SEs (1,000 reps) for quantile models; HC3 for OLS.",
  output = paste0(output_root, "/tables/table-quantile-regression.html"))
modelsummary(qr_models, output = paste0(output_root, "/tables/table-quantile-regression.tex"))
modelsummary(qr_models, output = paste0(output_root, "/tables/table-quantile-regression.docx"))
```

---

### A8c — Zero-Inflated and Hurdle Models

Use when Y is a count variable with excess zeros (e.g., number of arrests, doctor visits, publications). If > 25% of observations are zeros, standard Poisson/NB may be inappropriate.

**Choosing between zero-inflated vs. hurdle:**
- **Zero-inflated**: Two processes generate zeros — structural zeros (never-at-risk) and sampling zeros (at-risk but zero by chance). E.g., nonsmokers (structural) vs. smokers who did not smoke today (sampling).
- **Hurdle**: All zeros come from one process (participation decision), then counts from another. E.g., decision to visit doctor (binary) then number of visits (truncated count).

**R (pscl — zero-inflated):**
```r
library(pscl)

# Zero-inflated negative binomial
m_zinb <- zeroinfl(y ~ x + controls | z_inflate_vars,
                   data = df, dist = "negbin")
summary(m_zinb)

# Zero-inflated Poisson (if no overdispersion)
m_zip <- zeroinfl(y ~ x + controls | z_inflate_vars,
                  data = df, dist = "poisson")

# Vuong test: ZI model vs. standard model
vuong(m_zinb, glm.nb(y ~ x + controls, data = df))
```

**R (glmmTMB — preferred for random effects / complex models):**
```r
library(glmmTMB)

# Zero-inflated NB with random intercept
m_zinb_re <- glmmTMB(y ~ x + controls + (1 | group_id),
                     ziformula = ~ z_inflate_vars,
                     family = nbinom2, data = df)
summary(m_zinb_re)

# Hurdle model (truncated NB for counts, binomial for zeros)
m_hurdle <- glmmTMB(y ~ x + controls,
                    ziformula = ~ z_inflate_vars,
                    family = truncated_nbinom2, data = df)
summary(m_hurdle)
```

**Stata:**
```stata
* Zero-inflated negative binomial
zinb y x controls, inflate(z_inflate_vars)
margins, dydx(x)

* Vuong test is reported automatically in zinb output
* Hurdle (two-part) model
tpm y x controls, firstpart(probit) secondpart(nbreg)
```

**Diagnostics:**
```r
# Compare standard NB vs. ZIP vs. ZINB
m_nb   <- glm.nb(y ~ x + controls, data = df)
m_zip  <- zeroinfl(y ~ x + controls | z_inflate_vars, data = df, dist = "poisson")
m_zinb <- zeroinfl(y ~ x + controls | z_inflate_vars, data = df, dist = "negbin")

# AIC/BIC comparison
AIC(m_nb, m_zip, m_zinb)
BIC(m_nb, m_zip, m_zinb)

# Vuong test
vuong(m_zinb, m_nb)   # significant → ZI model preferred

# Predicted vs. observed zero counts
pred_zeros <- sum(predict(m_zinb, type = "prob")[, 1])
obs_zeros  <- sum(df$y == 0)
cat("Predicted zeros:", round(pred_zeros), "Observed zeros:", obs_zeros, "\n")

# Rootogram (visual check of count fit)
library(countreg)
rootogram(m_zinb)
```

**Publication table format:**
```
Table X. Zero-Inflated Negative Binomial Estimates: [Y]
                    | Count process (NB) | Zero-inflation (logit)
                    | IRR (95% CI)       | OR (95% CI)
X                   | X.XX [X.XX, X.XX]  | X.XX [X.XX, X.XX]
Control 1           | ...                | ...
N                   | X
Nonzero obs         | X
Zero obs            | X
Vuong test (z)      | X.XX (p = .XXX)
Note: Incidence rate ratios (count process) and odds ratios (zero-inflation process).
* p < .05, ** p < .01, *** p < .001.
```

**Write-up template:**
> "Given the excess zeros in [Y] ([X]% of observations; overdispersion parameter alpha = [X]), we estimated a zero-inflated negative binomial model (Table X). The Vuong test confirmed superiority of the zero-inflated specification over standard negative binomial (z = [X], p = [p]). In the count process, [X] was associated with a [X]% [increase/decrease] in expected [Y] (IRR = [X], 95% CI = [[lo], [hi]], p = [p]). In the zero-inflation process, [Z] [increased/decreased] the probability of being a structural zero (OR = [X], 95% CI = [[lo], [hi]], p = [p])."

**Export tables:**
```r
# For ZINB, modelsummary handles both components
modelsummary(m_zinb, exponentiate = TRUE,
  stars = c("*" = .05, "**" = .01, "***" = .001),
  notes = "Count process: IRR. Zero-inflation: OR. 95% CIs in brackets.",
  output = paste0(output_root, "/tables/table-zinb.html"))
modelsummary(m_zinb, exponentiate = TRUE,
  output = paste0(output_root, "/tables/table-zinb.tex"))
modelsummary(m_zinb, exponentiate = TRUE,
  output = paste0(output_root, "/tables/table-zinb.docx"))
```

---

### A8c2 — Truncated and Tobit (Censored) Regression

**Truncated regression** (outcome observed only above/below threshold):
```r
library(truncreg)
trunc_mod <- truncreg(y ~ x1 + x2, data = df, point = 0, direction = "left")
summary(trunc_mod)
# Use when: wages (>0), duration data, amounts conditional on participation
```

**Tobit (censored regression)** (outcome censored at boundary):
```r
library(AER)
tobit_mod <- tobit(y ~ x1 + x2, data = df, left = 0)
summary(tobit_mod)
# Marginal effects: marginaleffects::avg_slopes(tobit_mod)
```

**Stata**:
```stata
truncreg y x1 x2, ll(0)
tobit y x1 x2, ll(0)
margins, dydx(*)
```

---

### A8d — Beta Regression

Use when Y is a continuous proportion bounded on (0,1) — e.g., Gini coefficient, percent of income spent on housing, vote share, proportion of time in activity. OLS is inappropriate because it can predict values outside [0,1] and assumes homoskedastic errors for bounded data.

**R (betareg):**
```r
library(betareg)

# Basic beta regression (logit link for mean, log link for precision)
m_beta <- betareg(y_prop ~ x + controls, data = df, link = "logit")
summary(m_beta)

# Variable precision model (phi varies with covariates)
m_beta_vp <- betareg(y_prop ~ x + controls | precision_vars, data = df)
summary(m_beta_vp)

# Compare constant vs. variable precision
lrtest(m_beta, m_beta_vp)

# AME (marginaleffects works with betareg)
library(marginaleffects)
ame_beta <- avg_slopes(m_beta)
print(ame_beta)
```

**Handling exact 0s and 1s:**
```r
# Beta distribution requires y in (0,1), not [0,1]
# Smithson & Verkuilen (2006) transformation:
n <- nrow(df)
df$y_prop_adj <- (df$y_prop * (n - 1) + 0.5) / n
# Now y_prop_adj is strictly in (0,1)
```

**Stata:**
```stata
* Beta regression
betareg y_prop x controls, link(logit)
margins, dydx(x)

* Variable precision
betareg y_prop x controls, link(logit) zvar(precision_vars) zlink(log)
```

**Diagnostics:**
```r
# Residual plots
plot(m_beta, which = 1:4)

# Link test — check functional form
library(lmtest)
resettest(m_beta)

# Compare link functions
m_beta_probit <- betareg(y_prop ~ x + controls, data = df, link = "probit")
m_beta_cloglog <- betareg(y_prop ~ x + controls, data = df, link = "cloglog")
AIC(m_beta, m_beta_probit, m_beta_cloglog)

# Pseudo R-squared
m_beta$pseudo.r.squared
```

**Publication table format:**
```
Table X. Beta Regression Estimates: [Y Proportion]
                | (1) Constant phi | (2) Variable phi
                | Mean model       | Mean model | Precision model
X               | b (SE)           | b (SE)     | b (SE)
Control 1       | ...              | ...        | ...
Precision (phi) | X.XX             | —          | —
N               | X                | X
Pseudo R-sq     | X.XX             | X.XX
Log-lik         | X.XX             | X.XX
Note: Logit link for mean model; log link for precision.
AME of X on Y: [X.XX] percentage points. * p < .05, ** p < .01, *** p < .001.
```

**Write-up template:**
> "Because the outcome is a bounded proportion (mean = [M], SD = [SD]), we estimated beta regression with a logit link (Table X). [X] is associated with a [direction] in [Y] (b = [b], SE = [SE], p = [p]). The average marginal effect indicates that a one-unit increase in [X] corresponds to a [AME] percentage-point change in [Y proportion] (AME = [AME], 95% CI = [[lo], [hi]]). [If variable precision: The precision parameter varies significantly with [Z] (b = [b], p = [p]), indicating [greater/less] variation in [Y] for [description].]"

**Export tables:**
```r
modelsummary(list("Constant phi" = m_beta, "Variable phi" = m_beta_vp),
  stars = c("*" = .05, "**" = .01, "***" = .001),
  notes = "Beta regression, logit link. SEs in parentheses.",
  output = paste0(output_root, "/tables/table-beta-regression.html"))
modelsummary(list("Constant phi" = m_beta, "Variable phi" = m_beta_vp),
  output = paste0(output_root, "/tables/table-beta-regression.tex"))
modelsummary(list("Constant phi" = m_beta, "Variable phi" = m_beta_vp),
  output = paste0(output_root, "/tables/table-beta-regression.docx"))
```

---

### A8e — Competing Risks Models

Use when multiple event types can occur and each precludes the others (e.g., exit from unemployment via employment vs. disability vs. retirement; marriage dissolution via divorce vs. widowhood). Standard Cox PH treats competing events as censored, which biases cumulative incidence estimates.

**R (tidycmprsk — tidy interface):**
```r
library(tidycmprsk)
library(survival)

# Event variable must be a factor: 0 = censored, 1 = event of interest, 2 = competing event
df$event_type <- factor(df$event_type, levels = c("censored", "event1", "event2"))

# Cumulative incidence function (CIF)
cif <- cuminc(Surv(time, event_type) ~ group, data = df)
cif

# Fine-Gray subdistribution hazard model
m_fg <- crr(Surv(time, event_type) ~ x + controls, data = df, failcode = "event1")
summary(m_fg)

# Tidy output
broom::tidy(m_fg, conf.int = TRUE, exponentiate = TRUE)
```

**R (cmprsk — classic interface):**
```r
library(cmprsk)

# CIF estimation
cif_classic <- cuminc(ftime = df$time, fstatus = df$event_code, group = df$group)
plot(cif_classic, xlab = "Time", ylab = "Cumulative Incidence")

# Fine-Gray model
m_crr <- crr(ftime = df$time, fstatus = df$event_code,
             cov1 = model.matrix(~ x + controls, data = df)[, -1],
             failcode = 1, cencode = 0)
summary(m_crr)
```

**Stacked CIF plot (publication quality):**
```r
library(ggsurvfit)

p_cif <- cuminc(Surv(time, event_type) ~ group, data = df) |>
  ggcuminc(outcome = c("event1", "event2")) +
  scale_color_manual(values = palette_cb[1:4]) +
  scale_fill_manual(values = palette_cb[1:4]) +
  labs(x = "Time", y = "Cumulative Incidence") +
  theme_Publication() +
  add_confidence_interval() +
  add_risktable()
save_fig(p_cif, "fig-cumulative-incidence", width = 8, height = 6)

# Stacked CIF plot
p_stacked <- cuminc(Surv(time, event_type) ~ 1, data = df) |>
  ggcuminc(outcome = c("event1", "event2")) +
  geom_area(aes(fill = outcome), position = "stack", alpha = 0.7) +
  scale_fill_manual(values = palette_cb[1:2],
                    labels = c("Event 1", "Competing Event")) +
  labs(x = "Time", y = "Cumulative Incidence (Stacked)") +
  theme_Publication()
save_fig(p_stacked, "fig-cif-stacked", width = 7, height = 5)
```

**Stata:**
```stata
* Competing risks regression (Fine-Gray)
stset time, failure(event_code == 1)
stcrreg x controls, compete(event_code == 2)

* Cumulative incidence function
stcompet ci = ci, compet1(2) by(group)
```

**Diagnostics:**
```r
# Test proportional subdistribution hazards (analogous to cox.zph)
# Visual: plot log(-log(CIF)) vs. log(time) — should be parallel
# Schoenfeld-type residuals for Fine-Gray are not standard; use time interactions:
m_fg_time <- crr(Surv(time, event_type) ~ x + controls + x:log(time),
                 data = df, failcode = "event1")
# Significant time interaction → violation of proportional subdistribution hazards

# Compare cause-specific hazard vs. subdistribution hazard
m_cs <- coxph(Surv(time, event_type == "event1") ~ x + controls, data = df)
# Report both if results differ — they answer different questions
```

**Publication table format:**
```
Table X. Competing Risks Regression: [Event of Interest]
                | Cause-specific HR (95% CI) | Subdistribution HR (95% CI)
X               | X.XX [X.XX, X.XX]          | X.XX [X.XX, X.XX]
Control 1       | ...                        | ...
Events          | X (event1) / X (event2)
Person-time     | X
N               | X
Note: Cause-specific hazard ratios from Cox PH; subdistribution hazard ratios from
Fine-Gray model. Competing event: [description]. * p < .05, ** p < .01, *** p < .001.
```

**Write-up template:**
> "We estimated competing risks models to account for [competing event] (Table X). The cumulative incidence of [event of interest] at [T] years was [X]% (95% CI = [[lo]%, [hi]%]) (Figure X). In the Fine-Gray subdistribution hazard model, [X] was associated with a [X]% [higher/lower] subdistribution hazard of [event] (SHR = [X], 95% CI = [[lo], [hi]], p = [p]). Results were consistent when estimated via cause-specific hazard models (HR = [X], 95% CI = [[lo], [hi]])."

**Export tables:**
```r
models_cr <- list(
  "Cause-specific" = m_cs,
  "Fine-Gray" = m_fg
)
modelsummary(models_cr, exponentiate = TRUE,
  stars = c("*" = .05, "**" = .01, "***" = .001),
  notes = "Hazard ratios. 95% CIs in brackets.",
  output = paste0(output_root, "/tables/table-competing-risks.html"))
modelsummary(models_cr, exponentiate = TRUE,
  output = paste0(output_root, "/tables/table-competing-risks.tex"))
modelsummary(models_cr, exponentiate = TRUE,
  output = paste0(output_root, "/tables/table-competing-risks.docx"))
```

---

### A8f — RI-CLPM (Random-Intercept Cross-Lagged Panel Model)

Use for panel data when examining reciprocal causal dynamics between two variables across time (e.g., "Does self-esteem drive academic performance, or vice versa?"). The RI-CLPM (Hamaker, Kuiper, & Grasman, 2015) separates stable between-person differences from within-person dynamics, addressing a key limitation of standard CLPM.

**R (lavaan):**
```r
library(lavaan)

# Data should be in wide format: x1, x2, x3, ... y1, y2, y3, ...
# (subscript = wave number)

# RI-CLPM specification
riclpm_model <- '
  # Random intercepts (between-person stable trait)
  RI_x =~ 1*x1 + 1*x2 + 1*x3 + 1*x4
  RI_y =~ 1*y1 + 1*y2 + 1*y3 + 1*y4

  # Within-person centered variables at each wave
  wx1 =~ 1*x1; wx2 =~ 1*x2; wx3 =~ 1*x3; wx4 =~ 1*x4
  wy1 =~ 1*y1; wy2 =~ 1*y2; wy3 =~ 1*y3; wy4 =~ 1*y4

  # Autoregressive paths (within-person stability)
  wx2 ~ a*wx1;  wx3 ~ a*wx2;  wx4 ~ a*wx3
  wy2 ~ b*wy1;  wy3 ~ b*wy2;  wy4 ~ b*wy3

  # Cross-lagged paths (within-person cross-effects)
  wy2 ~ c*wx1;  wy3 ~ c*wx2;  wy4 ~ c*wx3   # X -> Y
  wx2 ~ d*wy1;  wx3 ~ d*wy2;  wx4 ~ d*wy3   # Y -> X

  # Within-person residual covariances (contemporaneous)
  wx1 ~~ wy1; wx2 ~~ wy2; wx3 ~~ wy3; wx4 ~~ wy4

  # Between-person variance and covariance
  RI_x ~~ RI_x; RI_y ~~ RI_y; RI_x ~~ RI_y

  # Constrain within-person residual variances equal across time (optional)
  wx1 ~~ vx*wx1; wx2 ~~ vx*wx2; wx3 ~~ vx*wx3; wx4 ~~ vx*wx4
  wy1 ~~ vy*wy1; wy2 ~~ vy*wy2; wy3 ~~ vy*wy3; wy4 ~~ vy*wy4
'

m_riclpm <- sem(riclpm_model, data = df, estimator = "MLR", missing = "fiml")
summary(m_riclpm, fit.measures = TRUE, standardized = TRUE)

# Standard CLPM for comparison (no random intercepts)
clpm_model <- '
  x2 ~ a*x1 + d*y1;  x3 ~ a*x2 + d*y2;  x4 ~ a*x3 + d*y3
  y2 ~ b*y1 + c*x1;  y3 ~ b*y2 + c*x2;  y4 ~ b*y3 + c*x3
  x1 ~~ y1; x2 ~~ y2; x3 ~~ y3; x4 ~~ y4
'
m_clpm <- sem(clpm_model, data = df, estimator = "MLR", missing = "fiml")

# Model comparison
anova(m_clpm, m_riclpm)  # chi-sq difference test
fitmeasures(m_riclpm, c("cfi", "tli", "rmsea", "srmr"))
fitmeasures(m_clpm,   c("cfi", "tli", "rmsea", "srmr"))
```

**Diagnostics:**
- Fit indices: CFI > .95, TLI > .95, RMSEA < .06, SRMR < .08
- Compare RI-CLPM vs. CLPM: significant chi-sq difference favors RI-CLPM
- Check if random intercept variances are significant (if not, CLPM may suffice)
- Test stationarity: compare constrained (equal paths across time) vs. freed model
- Minimum 3 waves required; 4+ waves preferred for identifiability

**Publication table format:**
```
Table X. Cross-Lagged Panel Model Estimates (Standardized)
                              | CLPM         | RI-CLPM
Autoregressive paths
  X(t) -> X(t+1)             | b (SE)       | b (SE)
  Y(t) -> Y(t+1)             | b (SE)       | b (SE)
Cross-lagged paths
  X(t) -> Y(t+1)             | b (SE) ***   | b (SE)
  Y(t) -> X(t+1)             | b (SE)       | b (SE)
Random intercept variance
  RI_X                        | —            | b (SE) ***
  RI_Y                        | —            | b (SE) ***
  RI_X ~~ RI_Y (r)            | —            | X.XX
Fit indices
  CFI / TLI                   | X.XX / X.XX  | X.XX / X.XX
  RMSEA [90% CI]              | X.XX [X,X]   | X.XX [X,X]
  SRMR                        | X.XX         | X.XX
  Chi-sq (df)                 | X.XX (X)     | X.XX (X)
Note: Standardized estimates. MLR estimator with FIML for missing data.
* p < .05, ** p < .01, *** p < .001. N = X across T = X waves.
```

**Write-up template:**
> "We estimated a random-intercept cross-lagged panel model (RI-CLPM; Hamaker et al., 2015) to separate stable between-person differences from within-person dynamics across [T] waves (Table X). The RI-CLPM fit the data well (CFI = [X], RMSEA = [X], SRMR = [X]) and significantly improved over the standard CLPM (Delta-chi-sq = [X], df = [X], p = [p]). At the within-person level, [X at time t] [predicted / did not predict] [Y at time t+1] (b = [b], SE = [SE], p = [p]), while the reverse path from [Y] to [X] was [significant/nonsignificant] (b = [b], SE = [SE], p = [p]). [Substantial/Negligible] between-person variance in both variables was captured by the random intercepts (Var(RI_X) = [X], p < .001)."

**Export tables:**
```r
# lavaan models require custom extraction for modelsummary
library(modelsummary)
modelsummary(list("CLPM" = m_clpm, "RI-CLPM" = m_riclpm),
  output = paste0(output_root, "/tables/table-riclpm.html"))
modelsummary(list("CLPM" = m_clpm, "RI-CLPM" = m_riclpm),
  output = paste0(output_root, "/tables/table-riclpm.tex"))
modelsummary(list("CLPM" = m_clpm, "RI-CLPM" = m_riclpm),
  output = paste0(output_root, "/tables/table-riclpm.docx"))
```

---

### A8g — Sequence Analysis

Use for life-course data with ordered sequences of states across time (e.g., employment trajectories, residential mobility patterns, family formation sequences). Common in Demography, ASR, and European sociology. Based on Optimal Matching (Abbott & Tsay, 2000) and the TraMineR package (Gabadinho et al., 2011).

**R (TraMineR):**
```r
library(TraMineR)
library(cluster)

# Define state sequence object
# Data in wide format: columns = time points, values = state codes
state_labels <- c("Employed", "Unemployed", "Education", "Inactive")
state_codes  <- c("E", "U", "D", "I")

seq_obj <- seqdef(df[, paste0("state_t", 1:20)],   # columns for time 1-20
                  states  = state_codes,
                  labels  = state_labels,
                  cpal    = palette_cb[1:4])

# --- Descriptive sequence analysis ---

# State distribution plot (cross-sectional view)
p_dist <- seqdplot(seq_obj, border = NA, with.legend = "right",
                    main = "State Distribution by Age/Time")

# Sequence index plot (individual trajectories)
p_idx <- seqiplot(seq_obj, border = NA, with.legend = "right",
                   main = "Individual Sequences (first 100)",
                   tlim = 1:100, sortv = "from.start")

# Sequence frequency plot (most common sequences)
seqfplot(seq_obj, border = NA, with.legend = "right",
         main = "10 Most Frequent Sequences")

# Entropy curve (complexity over time)
ent <- seqstatd(seq_obj)
p_entropy <- plot(ent$Entropy, type = "l", xlab = "Time", ylab = "Shannon Entropy",
                  main = "Longitudinal Entropy")

# Transition rate matrix
seqtrate(seq_obj)

# --- Optimal Matching and Clustering ---

# Compute distance matrix (OM with substitution cost = 2, indel = 1)
dist_om <- seqdist(seq_obj, method = "OM", sm = "TRATE", indel = 1)

# Alternative distance: Hamming (position-specific, no time warping)
dist_ham <- seqdist(seq_obj, method = "HAM", sm = "TRATE")

# Ward hierarchical clustering
hc <- hclust(as.dist(dist_om), method = "ward.D2")

# Determine number of clusters (silhouette + ASW)
asw <- numeric(8)
for (k in 2:8) {
  cl <- cutree(hc, k = k)
  asw[k] <- summary(silhouette(cl, dist_om))$avg.width
}
plot(2:8, asw[2:8], type = "b", xlab = "Number of clusters", ylab = "ASW")
best_k <- which.max(asw)

# Assign clusters
df$seq_cluster <- factor(cutree(hc, k = best_k))

# Plot sequences by cluster
seqdplot(seq_obj, group = df$seq_cluster, border = NA)
seqiplot(seq_obj, group = df$seq_cluster, border = NA, sortv = "from.start")
```

**Relating clusters to covariates:**
```r
# Multinomial regression of cluster membership on covariates
library(nnet)
m_seq <- multinom(seq_cluster ~ cohort + gender + education + race, data = df)
summary(m_seq)

# Relative risk ratios
exp(coef(m_seq))
```

**Diagnostics:**
- Average silhouette width (ASW) > 0.5 = strong clustering; 0.25-0.5 = reasonable
- Compare OM vs. Hamming vs. LCS distances for robustness
- Test sensitivity to substitution cost matrix (theory-based vs. TRATE vs. constant)
- Ensure no cluster has < 5% of observations
- Report sequence complexity metrics: entropy, turbulence, number of transitions

**Publication table format:**
```
Table X. Sequence Cluster Characteristics
                 | Cluster 1   | Cluster 2   | Cluster 3   | Total
                 | "Label"     | "Label"     | "Label"     |
N (%)            | X (XX%)     | X (XX%)     | X (XX%)     | X
Dominant state   | [state]     | [state]     | [state]     |
Mean transitions | X.X         | X.X         | X.X         | X.X
Mean entropy     | X.XX        | X.XX        | X.XX        | X.XX

Table X+1. Multinomial Logit: Cluster Membership on Covariates
                | Cluster 2 vs. 1   | Cluster 3 vs. 1
                | RRR (95% CI)      | RRR (95% CI)
Female          | X.XX [X.XX, X.XX] | X.XX [X.XX, X.XX]
Education       | X.XX [X.XX, X.XX] | X.XX [X.XX, X.XX]
Note: Reference cluster: Cluster 1. * p < .05, ** p < .01, *** p < .001.
```

**Write-up template:**
> "Sequence analysis using optimal matching with transition-rate-based substitution costs identified [K] distinct [trajectory/career/life-course] typologies (Table X; Figure X). Cluster 1 ('[label],' [X]% of the sample) was characterized by [description of dominant states and transitions]. Cluster 2 ('[label],' [X]%) exhibited [description]. The average silhouette width of [X.XX] indicates [strong/reasonable] cluster separation. Multinomial regression reveals that [covariate] is associated with [higher/lower] relative risk of following the '[cluster label]' trajectory compared to '[reference cluster]' (RRR = [X], 95% CI = [[lo], [hi]], p = [p])."

**Export tables:**
```r
modelsummary(m_seq, exponentiate = TRUE,
  stars = c("*" = .05, "**" = .01, "***" = .001),
  notes = "Relative risk ratios. Reference: Cluster 1.",
  output = paste0(output_root, "/tables/table-sequence-clusters.html"))
modelsummary(m_seq, exponentiate = TRUE,
  output = paste0(output_root, "/tables/table-sequence-clusters.tex"))
modelsummary(m_seq, exponentiate = TRUE,
  output = paste0(output_root, "/tables/table-sequence-clusters.docx"))
```

---

### A8h — Full SEM / CFA (Structural Equation Modeling)

Use when the research design involves latent constructs measured by multiple indicators (e.g., "cultural capital" measured by 5 survey items). CFA establishes the measurement model; SEM adds structural paths between latent variables.

**R (lavaan):**
```r
library(lavaan)

# ============================
# Step 1: Confirmatory Factor Analysis (CFA)
# ============================

cfa_model <- '
  # Measurement model — define latent factors
  cultural_capital =~ cc1 + cc2 + cc3 + cc4 + cc5
  social_capital   =~ sc1 + sc2 + sc3 + sc4
  wellbeing        =~ wb1 + wb2 + wb3 + wb4 + wb5 + wb6
'

m_cfa <- cfa(cfa_model, data = df, estimator = "MLR", missing = "fiml")
summary(m_cfa, fit.measures = TRUE, standardized = TRUE)

# Fit indices
fitmeasures(m_cfa, c("chisq", "df", "pvalue",
                      "cfi", "tli", "rmsea", "rmsea.ci.lower", "rmsea.ci.upper",
                      "srmr"))

# Factor loadings
standardizedSolution(m_cfa) |>
  filter(op == "=~") |>
  select(lhs, rhs, est.std, se, pvalue)

# Modification indices (for model improvement — use sparingly)
modindices(m_cfa, sort = TRUE, minimum.value = 10)

# Reliability
library(semTools)
reliability(m_cfa)  # omega, alpha per factor

# ============================
# Step 2: Measurement Invariance Testing (if comparing groups)
# ============================

# Configural invariance (same factor structure)
mi_config <- cfa(cfa_model, data = df, group = "group_var",
                 estimator = "MLR", missing = "fiml")

# Metric invariance (equal factor loadings)
mi_metric <- cfa(cfa_model, data = df, group = "group_var",
                 group.equal = "loadings",
                 estimator = "MLR", missing = "fiml")

# Scalar invariance (equal intercepts)
mi_scalar <- cfa(cfa_model, data = df, group = "group_var",
                 group.equal = c("loadings", "intercepts"),
                 estimator = "MLR", missing = "fiml")

# Compare models (use Delta-CFI rather than chi-sq for large N)
library(semTools)
compareFit(mi_config, mi_metric, mi_scalar)
# Delta-CFI < .01 and Delta-RMSEA < .015 → invariance holds (Chen, 2007)

# ============================
# Step 3: Structural Model (SEM)
# ============================

sem_model <- '
  # Measurement model
  cultural_capital =~ cc1 + cc2 + cc3 + cc4 + cc5
  social_capital   =~ sc1 + sc2 + sc3 + sc4
  wellbeing        =~ wb1 + wb2 + wb3 + wb4 + wb5 + wb6

  # Structural paths
  wellbeing ~ cultural_capital + social_capital + age + female
  social_capital ~ cultural_capital + education

  # Covariance
  cultural_capital ~~ social_capital
'

m_sem <- sem(sem_model, data = df, estimator = "MLR", missing = "fiml")
summary(m_sem, fit.measures = TRUE, standardized = TRUE)

# Path diagram
library(semPlot)
semPaths(m_sem, what = "std", layout = "tree2",
         edge.label.cex = 0.8, residuals = FALSE,
         sizeMan = 6, sizeLat = 10)
```

**Stata:**
```stata
* CFA
sem (CulturalCapital -> cc1 cc2 cc3 cc4 cc5) ///
    (SocialCapital -> sc1 sc2 sc3 sc4) ///
    (Wellbeing -> wb1 wb2 wb3 wb4 wb5 wb6), ///
    method(mlmv) standardized
estat gof, stats(all)

* SEM with structural paths
sem (CulturalCapital -> cc1 cc2 cc3 cc4 cc5) ///
    (SocialCapital -> sc1 sc2 sc3 sc4) ///
    (Wellbeing -> wb1 wb2 wb3 wb4 wb5 wb6) ///
    (Wellbeing <- CulturalCapital SocialCapital age female) ///
    (SocialCapital <- CulturalCapital education), ///
    method(mlmv) standardized
estat gof, stats(all)

* Measurement invariance
sem ..., group(group_var)                    // configural
sem ..., group(group_var) ginvariant(mcoef)  // metric
sem ..., group(group_var) ginvariant(mcoef mcons) // scalar
```

**Diagnostics:**
```r
# Fit index thresholds (Hu & Bentler, 1999)
# CFI >= .95 (good), >= .90 (acceptable)
# TLI >= .95 (good), >= .90 (acceptable)
# RMSEA <= .06 (good), <= .08 (acceptable); report 90% CI
# SRMR <= .08 (good)

# Check for Heywood cases (negative variances or loadings > 1)
inspect(m_sem, "est")$psi |> diag()  # all should be positive

# Residual correlation matrix
residuals(m_cfa, type = "cor")$cov
# Large residuals (> |0.10|) suggest misspecification

# Discriminant validity (AVE > shared variance between factors)
library(semTools)
AVE <- reliability(m_cfa)  # Average Variance Extracted per factor
```

**Publication table format:**
```
Table X. CFA Factor Loadings (Standardized)
Item              | Cultural Capital | Social Capital | Wellbeing
cc1               | 0.XX***          |                |
cc2               | 0.XX***          |                |
...
sc1               |                  | 0.XX***        |
...
wb1               |                  |                | 0.XX***
...
Composite reliability (omega) | 0.XX | 0.XX          | 0.XX
AVE               | 0.XX             | 0.XX           | 0.XX

Table X+1. SEM Structural Path Estimates
Path                               | b (SE)    | Beta   | p
Cultural Capital -> Wellbeing      | X.XX (X.XX) | 0.XX | .XXX
Social Capital -> Wellbeing        | X.XX (X.XX) | 0.XX | .XXX
Cultural Capital -> Social Capital | X.XX (X.XX) | 0.XX | .XXX
...
Fit: chi-sq(df) = X.XX(X), CFI = X.XX, TLI = X.XX,
     RMSEA = X.XX [X.XX, X.XX], SRMR = X.XX
Note: MLR estimator with FIML for missing data. N = X.
* p < .05, ** p < .01, *** p < .001.

Table X+2. Measurement Invariance (if applicable)
Model       | chi-sq (df)  | CFI   | RMSEA | Delta-CFI | Delta-RMSEA
Configural  | X.XX (X)     | X.XX  | X.XX  | —         | —
Metric      | X.XX (X)     | X.XX  | X.XX  | X.XXX     | X.XXX
Scalar      | X.XX (X)     | X.XX  | X.XX  | X.XXX     | X.XXX
Note: Delta-CFI < .01 and Delta-RMSEA < .015 support invariance (Chen, 2007).
```

**Write-up template:**
> "Confirmatory factor analysis established the measurement model for [constructs] (Table X). All factor loadings exceeded [.40/.50] and were statistically significant (p < .001). The CFA model fit the data well (chi-sq([df]) = [X], CFI = [X], TLI = [X], RMSEA = [X], 90% CI = [[lo], [hi]], SRMR = [X]). Composite reliability ranged from [X] to [X], exceeding the .70 threshold. [If invariance tested: Measurement invariance across [groups] was supported at the [configural/metric/scalar] level (Delta-CFI = [X], Delta-RMSEA = [X]).]

> In the structural model (Table X+1), [latent predictor] was positively associated with [latent outcome] (b = [b], SE = [SE], beta = [beta], p = [p]), controlling for [covariates]. [Indirect effect if mediation: The indirect effect of [X] on [Y] through [M] was significant (b_indirect = [b], 95% CI = [[lo], [hi]].]"

**Export tables:**
```r
modelsummary(list("CFA" = m_cfa, "SEM" = m_sem),
  output = paste0(output_root, "/tables/table-sem.html"))
modelsummary(list("CFA" = m_cfa, "SEM" = m_sem),
  output = paste0(output_root, "/tables/table-sem.tex"))
modelsummary(list("CFA" = m_cfa, "SEM" = m_sem),
  output = paste0(output_root, "/tables/table-sem.docx"))
```

---

### A8i — Multiple Testing Correction

Apply whenever the analysis involves multiple hypothesis tests (e.g., testing the same predictor across subgroups, multiple outcomes, multiple pairwise comparisons). Required by Nature journals; strongly recommended for any paper with > 5 simultaneous tests.

**When to use each method:**

| Method | R function | Use when | Strictness |
|---|---|---|---|
| Bonferroni | `p.adjust(p, "bonferroni")` | Small number of tests; want maximum protection against any false positive | Most conservative |
| Holm | `p.adjust(p, "holm")` | Default recommendation; uniformly more powerful than Bonferroni | Conservative |
| Benjamini-Hochberg (BH) | `p.adjust(p, "BH")` | Many tests; willing to tolerate some false positives; controlling FDR | Moderate |
| Benjamini-Yekutieli (BY) | `p.adjust(p, "BY")` | Tests are dependent (correlated outcomes); controlling FDR | Moderate-conservative |

**R code:**
```r
# Given a vector of p-values from multiple tests
p_values <- c(0.001, 0.013, 0.042, 0.049, 0.085, 0.120, 0.310)
test_labels <- c("H1a", "H1b", "H2a", "H2b", "H3a", "H3b", "H3c")

# Apply corrections
correction_table <- data.frame(
  Hypothesis    = test_labels,
  p_raw         = p_values,
  p_bonferroni  = p.adjust(p_values, method = "bonferroni"),
  p_holm        = p.adjust(p_values, method = "holm"),
  p_bh_fdr      = p.adjust(p_values, method = "BH"),
  p_by_fdr      = p.adjust(p_values, method = "BY")
)

# Add significance flags
correction_table <- correction_table |>
  mutate(
    sig_raw  = ifelse(p_raw < .05, "*", ""),
    sig_holm = ifelse(p_holm < .05, "*", ""),
    sig_fdr  = ifelse(p_bh_fdr < .05, "*", "")
  )
print(correction_table)

# For pairwise comparisons (e.g., post-hoc after ANOVA)
pairwise.t.test(df$y, df$group, p.adjust.method = "BH")

# For emmeans contrasts
library(emmeans)
emm <- emmeans(m2, pairwise ~ group, adjust = "tukey")
summary(emm$contrasts)
```

**Stata:**
```stata
* After running multiple tests, adjust manually or use:
* Bonferroni in post-hoc
oneway y group, bonferroni

* Holm-Bonferroni (via community package)
* ssc install qqvalue
qqvalue p_var, method(simes) // BH/FDR adjustment
```

**Diagnostics:**
- Count the total number of independent tests performed (the "family" of tests)
- Report both raw and adjusted p-values
- If Bonferroni renders everything nonsignificant but BH retains findings, discuss the trade-off
- For pre-registered primary hypotheses, correction may not be needed (each test is confirmatory)
- For exploratory subgroup analyses, correction is mandatory

**Publication table format:**
```
Table X. Multiple Testing Correction
Hypothesis | Estimate | SE   | Raw p | Holm p | BH (FDR) p | Sig (FDR < .05)
H1a        | X.XX     | X.XX | .001  | .007   | .007       | ***
H1b        | X.XX     | X.XX | .013  | .065   | .046       | *
H2a        | X.XX     | X.XX | .042  | .168   | .098       |
H2b        | X.XX     | X.XX | .049  | .168   | .098       |
H3a        | X.XX     | X.XX | .085  | .255   | .149       |
Note: [X] tests adjusted simultaneously. BH = Benjamini-Hochberg false discovery rate.
* FDR-adjusted p < .05, ** FDR-adjusted p < .01, *** FDR-adjusted p < .001.
```

**Write-up template:**
> "To account for [X] simultaneous tests, we applied [Benjamini-Hochberg false discovery rate / Holm-Bonferroni] correction (Table X). After adjustment, [X] of [Y] hypotheses remained statistically significant at the FDR < .05 threshold. Specifically, [H1a] survived correction (raw p = [p], adjusted p = [p_adj]), while [H2a] did not (raw p = [p], adjusted p = [p_adj]). [If Nature journal: All reported p-values are two-sided and adjusted for multiple comparisons unless otherwise noted.]"

**Export tables:**
```r
library(gt)
correction_table |>
  gt() |>
  fmt_number(columns = starts_with("p_"), decimals = 3) |>
  tab_header(title = "Multiple Testing Correction") |>
  gtsave(paste0(output_root, "/tables/table-multiple-testing.html"))

# Also save as docx
library(flextable)
flextable(correction_table) |>
  colformat_double(j = 2:6, digits = 3) |>
  save_as_docx(path = paste0(output_root, "/tables/table-multiple-testing.docx"))
```

---

### A9 — Analysis Verification (Subagent)

After completing A1–A8 (including any applicable A8a–A8i extended methods), launch a **verification subagent** via the Task tool (`subagent_type: general-purpose`) to audit all analytic work before proceeding to visualization.

**Prompt the subagent with the following context:**
- Full list of analytic decisions (model type, SE type, sample exclusions, variables)
- Bash output from `ls ${OUTPUT_ROOT}/tables/` showing saved files
- Target journal
- Summary of model results (coefficients, SEs, p-values, AME if applicable)

**The subagent performs these checks and returns a VERIFICATION REPORT:**

```
ANALYSIS VERIFICATION REPORT
=============================

MODEL SPECIFICATION
[ ] Correct model family for outcome type
    - Binary outcome → logit/probit (not OLS)
    - Count outcome → negative binomial (not Poisson unless mean ≈ variance)
    - Count with excess zeros → zero-inflated or hurdle model (A8c)
    - Proportion (0,1) → beta regression (A8d)
    - Ordered outcome → polr (not OLS)
    - Time-to-event → Cox PH (not linear)
    - Time-to-event with competing risks → Fine-Gray (A8e)
    - Latent subgroups → LCA/mixture (A8a); BIC-based class selection
    - Distributional effects → quantile regression (A8b)
    - Latent constructs → CFA/SEM (A8h); fit indices reported
    - Panel reciprocal paths → RI-CLPM (A8f); between/within decomposition
    - Trajectory data → sequence analysis (A8g); OM + clustering
[ ] Progressive model ladder present (M1 baseline → M2 +controls → M3 extended)
[ ] Multiple testing correction applied if > 5 simultaneous tests (A8i)

STANDARD ERRORS
[ ] HC3 robust SEs used for OLS (or justification given for default SEs)
[ ] Clustered SEs used when observations are nested within units
[ ] lmerTest loaded for p-values in lme4 multilevel models

MARGINAL EFFECTS
[ ] AME computed via avg_slopes() for ALL logistic / ordered logit models
[ ] Raw log-odds NOT reported as main estimates in sociology journals
[ ] AME table saved (table2-ame.html/.tex/.docx)

DIAGNOSTICS
[ ] VIF < 10 for all predictors (car::vif run)
[ ] Heteroskedasticity test run (bptest) — if significant, HC3 SEs confirmed
[ ] For panel: Hausman test and serial correlation test run
[ ] For Cox PH: cox.zph() Schoenfeld residuals checked

REPORTING STANDARDS (journal-specific)
[ ] For ASR/AJS: AME reported; SE in parentheses; stars + exact p in text
[ ] For Demography: decomposition run if comparing group means
[ ] For NHB/Science Advances: exact test stat + df + p included
[ ] No "trend toward significance" language (p = .07 is NOT significant)
[ ] Reference categories documented for all categorical predictors
[ ] Sample size N reported for each model
[ ] Effect sizes (β, AME, HR, IRR) reported alongside p-values

SENSITIVITY
[ ] Robustness table generated (tableA1-robustness)
[ ] Oster delta (sensemakr) run if OLS and any causal language used
[ ] Oster delta > 1 or reported with exact value

FILES ON DISK
[ ] output/[slug]/tables/table1-descriptives.html + .tex + .docx
[ ] output/[slug]/tables/table2-regression.html + .tex + .docx
[ ] output/[slug]/tables/table2-ame.html + .tex + .docx  (if logit)
[ ] output/[slug]/tables/tableA1-robustness.html + .tex + .docx

RESULT: [PASS / NEEDS REVISION]

Issues to fix before proceeding:
1. [Specific issue + corrected code if applicable]
```

If the verification subagent returns **NEEDS REVISION**, fix all flagged issues and re-export affected tables before proceeding to Component B.

---

## COMPONENT B: Data Visualization

### B0 — Base Theme and Export Helper

```r
# Source the publication theme
viz_path <- file.path(Sys.getenv("SCHOLAR_SKILL_DIR", unset = "."), ".claude/skills/scholar-analyze/references/viz_setting.R")
if (file.exists(viz_path)) source(viz_path) else message("viz_setting.R not found at ", viz_path, " — define theme inline")
# Provides: theme_Publication(), scale_fill_Publication(), scale_colour_Publication()

# Output root — set by orchestrator or default to "output"
output_root <- Sys.getenv("OUTPUT_ROOT", "output")

# ── VISUALIZATION RULES (MANDATORY) ──────────────────────────────
# 1. NEVER use ggtitle() or labs(title = ...) — titles go in manuscript captions
# 2. ALWAYS use theme_Publication() — never theme_minimal(), theme_bw(), etc.
# 3. ALWAYS use scale_colour_Publication() or palette_cb for colors
# 4. ALWAYS save both PDF (cairo_pdf) and PNG (300 DPI) via save_fig()
# 5. Axis labels in plain language, not raw variable names
# ──────────────────────────────────────────────────────────────────

# Export helper — saves PDF (vector) + PNG (300 DPI)
save_fig <- function(p, name, width = 6, height = 4.5, dpi = 300) {
  ggsave(paste0(output_root, "/figures/", name, ".pdf"),
         plot = p, device = cairo_pdf, width = width, height = height)
  ggsave(paste0(output_root, "/figures/", name, ".png"),
         plot = p, dpi = dpi, width = width, height = height)
  message("Saved: ", output_root, "/figures/", name, " (.pdf + .png)")
}

# Colorblind-safe 8-color palette (Wong 2011)
palette_cb <- c("#0072B2","#E69F00","#009E73","#CC79A7",
                "#56B4E9","#F0E442","#D55E00","#000000")
```

---

### B1 — Descriptive Plots

**Distribution:**
```r
p_dist <- ggplot(df, aes(x = outcome)) +
  geom_histogram(aes(y = after_stat(density)), bins = 30, fill = palette_cb[1], alpha = 0.7) +
  geom_density(linewidth = 0.8) +
  labs(x = "Outcome", y = "Density") +
  theme_Publication()
save_fig(p_dist, "fig-dist-outcome")
```

**Grouped violin + boxplot (preferred for NHB):**
```r
p_violin <- ggplot(df, aes(x = group, y = outcome, fill = group)) +
  geom_violin(alpha = 0.6) +
  geom_boxplot(width = 0.1, fill = "white", outlier.shape = NA) +
  scale_fill_Publication() +
  labs(x = NULL, y = "Outcome") +
  theme_Publication() + theme(legend.position = "none")
save_fig(p_violin, "fig-violin-by-group")
```

**Bar chart with percentages:**
```r
p_bar <- df |>
  count(group, category) |>
  mutate(pct = n / sum(n), .by = group) |>
  ggplot(aes(x = group, y = pct, fill = category)) +
  geom_col(position = "dodge") +
  scale_y_continuous(labels = scales::percent) +
  scale_fill_Publication() +
  labs(x = NULL, y = "Percent") +
  theme_Publication()
save_fig(p_bar, "fig-bar-grouped")
```

**Correlation heatmap:**
```r
library(ggcorrplot)
p_corr <- ggcorrplot(cor(select(df, where(is.numeric)), use = "pairwise"),
                     lab = TRUE, type = "lower",
                     colors = c(palette_cb[1], "white", palette_cb[7])) +
  theme_Publication()
save_fig(p_corr, "fig-correlation-heatmap", width = 7, height = 6)
```

---

### B2 — Coefficient / Forest Plot

**Single model:**
```r
library(modelsummary)

p_coef <- modelplot(m2, coef_omit = "Intercept") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  labs(x = "Coefficient (HC3 SE)", y = NULL) +
  theme_Publication()
save_fig(p_coef, "fig-coef-plot")
```

**Multi-model comparison:**
```r
p_coef_multi <- modelplot(
  list("Baseline" = m1, "+Controls" = m2, "+FE" = m_fe),
  coef_omit = "Intercept"
) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  scale_color_Publication() +
  theme_Publication()
save_fig(p_coef_multi, "fig-coef-multimodel", width = 7, height = 5)
```

---

### B3 — Marginal Effects Plots

```r
library(marginaleffects)

# AME with CIs — for all key predictors
p_ame <- plot_slopes(m_logit, variables = "x") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  labs(x = "Covariate Value", y = "Marginal Effect on P(Y=1)") +
  theme_Publication()
save_fig(p_ame, "fig-ame-x")

# Interaction — effect of X conditional on moderator
p_int <- plot_slopes(m_logit, variables = "x", condition = "moderator") +
  scale_color_Publication() + scale_fill_Publication() +
  theme_Publication()
save_fig(p_int, "fig-interaction-ame")

# Predicted probabilities by group
p_pred <- plot_predictions(m_logit, condition = list("x", "group")) +
  scale_color_Publication() + scale_fill_Publication() +
  theme_Publication()
save_fig(p_pred, "fig-predicted-prob")
```

---

### B4 — Event Study Plot (DiD)

```r
library(fixest)

# Estimate event study
m_es <- feols(y ~ i(year_rel, treated, ref = -1) | unit_id + year,
              data    = df,
              cluster = ~unit_id)

# Extract coefficients and CIs
es_df <- broom::tidy(m_es, conf.int = TRUE) |>
  filter(str_detect(term, "year_rel")) |>
  mutate(year_rel = as.numeric(str_extract(term, "-?\\d+")))

p_es <- ggplot(es_df, aes(x = year_rel, y = estimate)) +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = conf.low, ymax = conf.high), width = 0.2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "red") +
  labs(x = "Years Relative to Treatment", y = "Estimated Effect (95% CI)") +
  theme_Publication()
save_fig(p_es, "fig-event-study")
```

---

### B5 — RD Plot

```r
library(rdrobust); library(rddensity)

# Main RD plot
rdplot(y = df$outcome, x = df$running_var, c = cutoff,
       title = "RD Plot", x.label = "Running Variable", y.label = "Outcome")

# McCrary density test for manipulation
rdd <- rddensity(df$running_var, c = cutoff)
rdplotdensity(rdd, df$running_var)
```

---

### B6 — Balance / Love Plot (Matching)

```r
library(MatchIt); library(cobalt)

# After running matchit:
# m_match <- matchit(treatment ~ x1 + x2 + x3, data = df, method = "nearest")

p_love <- love.plot(m_match,
                    thresholds  = c(m = 0.1),
                    abs         = TRUE,
                    var.order   = "standardized",
                    colors      = palette_cb[c(1,7)]) +
  theme_Publication()
save_fig(p_love, "fig-love-plot")
```

---

### B7 — Kaplan-Meier Survival Plot

```r
library(survival); library(survminer)

km_fit <- survfit(Surv(time, event) ~ group, data = df)

ggsurvplot(km_fit,
           pval         = TRUE,
           conf.int     = TRUE,
           risk.table   = TRUE,
           palette      = palette_cb[1:2],
           legend.labs  = levels(df$group),
           ggtheme      = theme_Publication())
# Save manually via ggsave after ggsurvplot renders
```

---

### B8 — Python Figure Equivalents

```python
import os, matplotlib.pyplot as plt
import seaborn as sns

output_root = os.environ.get("OUTPUT_ROOT", "output")

# Distribution with KDE
sns.histplot(df, x='outcome', hue='group', kde=True, palette='colorblind')
plt.savefig(f"{output_root}/figures/fig-dist.pdf", dpi=300, bbox_inches='tight')

# Coefficient plot via statsmodels
import statsmodels.formula.api as smf
model = smf.ols('y ~ x + controls', data=df).fit(cov_type='HC3')
coef_df = model.params.to_frame('coef').join(model.conf_int().rename(columns={0:'lo',1:'hi'}))
fig, ax = plt.subplots()
ax.errorbar(coef_df['coef'], coef_df.index,
            xerr=[coef_df['coef']-coef_df['lo'], coef_df['hi']-coef_df['coef']],
            fmt='o', color='steelblue')
ax.axvline(0, linestyle='--', color='gray')
plt.savefig(f"{output_root}/figures/fig-coef.pdf", dpi=300, bbox_inches='tight')

# Marginal effects (marginaleffects Python port)
from marginaleffects import avg_slopes
ame = avg_slopes(model)
print(ame)

# Survival
from lifelines import KaplanMeierFitter
kmf = KaplanMeierFitter()
kmf.fit(df['time'], df['event'])
ax = kmf.plot_survival_function()
plt.savefig(f"{output_root}/figures/fig-km.pdf", dpi=300, bbox_inches='tight')
```

---

### B9 — Visualization Verification (Subagent)

After completing B0–B8, launch a **visualization verification subagent** via the Task tool (`subagent_type: general-purpose`) to audit all figures before writing results.

**Prompt the subagent with the following context:**
- Full list of figures generated (filenames + figure types)
- The ggplot2 / Python code used for each figure
- Bash output from `ls ${OUTPUT_ROOT}/figures/` showing saved files
- Target journal

**The subagent performs these checks and returns a VISUALIZATION REPORT:**

```
VISUALIZATION VERIFICATION REPORT
===================================

FILE EXPORT
[ ] save_fig() called for every ggplot figure (or equivalent savefig for Python)
[ ] Every figure exists in both .pdf and .png in output/[slug]/figures/
[ ] PNG DPI = 300 confirmed (check ggsave dpi= argument)
[ ] PDF uses cairo_pdf device (vector, embeds fonts correctly)
[ ] Interactive figures (plotly) saved as .html via htmlwidgets::saveWidget()

COLORBLIND SAFETY
[ ] scale_colour_Publication() or palette_cb (Wong 2011) used — not default ggplot2 colors
[ ] No red-green pair used together (#FF0000 + #00FF00 or similar)
[ ] Continuous scales use viridis or ColorBrewer diverging (not rainbow)

LABELS AND LEGIBILITY
[ ] X-axis and Y-axis labels present and human-readable (not raw variable names like "inc_log")
[ ] Legend title and levels labeled clearly (not "0 / 1" or raw factor codes)
[ ] Error bars explicitly labeled in caption: "Error bars = 95% CI" (or SEM / SD)
[ ] Figure caption is self-explanatory without reading main text

JOURNAL-SPECIFIC REQUIREMENTS
[ ] ASR/AJS: predicted probability or marginal effect plots used (not raw odds ratio forest plots)
[ ] Science Advances: panel labels in uppercase (A, B, C, …) for multi-panel figures
[ ] Science Advances: error bar type (SEM / SD / 95% CI) labeled in figure or legend
[ ] NHB: violin plot or boxplot used for group comparisons (not bar + error bar)
[ ] NHB: individual data points overlaid when N < 30 per group (geom_jitter or geom_point)
[ ] NHB: panel labels uppercase if multi-panel

FIGURE TYPE CORRECTNESS
[ ] Distribution: density/histogram appropriate; not a pie chart
[ ] Coefficient plot: reference line at zero present
[ ] Marginal effect plot: zero reference line present; y-axis labeled as AME or Pr(Y=1)
[ ] Event study: vertical dotted line at treatment onset (year_rel = -0.5); zero hline
[ ] RD plot: cutoff marked; separate trend lines each side
[ ] Love plot: threshold lines at ±0.1; pre- and post-match shown
[ ] Choropleth: legend shows units (%, $, rate); NA counties handled (fill="gray90")
[ ] Interactive: tooltip text informative; not just raw variable value

FILES ON DISK
[ ] output/[slug]/figures/ directory has at least one PDF and one PNG
[ ] All figure filenames follow fig-[type]-[variable] convention

RESULT: [PASS / NEEDS REVISION]

Issues to fix before proceeding:
1. [Specific issue + corrected code if applicable]
```

If the verification subagent returns **NEEDS REVISION**, fix all flagged issues and re-save affected figures before proceeding to Component C.

---

## COMPONENT C: Results Section Writing

Using the actual numerical results from Components A and B, **write complete, publication-ready prose**. Replace every placeholder with real values. No brackets should remain in the final text.

### Journal-Specific Reporting Norms

| Journal | Effect estimate | Uncertainty | Significance | Target length |
|---------|----------------|-------------|--------------|---------------|
| ASR | AME required for logit | SE in parentheses | Stars in tables + exact p in text | 1,500–2,500 words |
| AJS | AME preferred | SE in parentheses | Stars | 1,500–2,500 words |
| Demography | AME or OR + decomposition | Either | Stars | 2,000–3,000 words |
| Science Advances | AME preferred | 95% CI | Stars + `ns` marker | 1,500–2,000 words (main) |
| NHB | AME preferred | 95% CI + test stat + df | Stars + `ns` marker | 1,500–2,000 words (main) |

---

### Sentence Templates by Model Type

**OLS:**
> "A one-unit increase in [X] is associated with a [β]-unit change in [Y], holding other variables constant (b = [β], SE = [SE], p = [p])."

**AME from logit (ASR/AJS/Demography):**
> "A one-unit increase in [X] is associated with a [β×100] percentage point change in the probability of [Y] (AME = [β], 95% CI = [[lo], [hi]])."

**AME from logit (NHB/Science Advances):**
> "A one-unit increase in [X] is associated with a [β×100] percentage point increase in the probability of [Y] (AME = [β], 95% CI = [[lo], [hi]], z = [z], p = [p])."

**Fixed effects:**
> "Among [units] that changed [X] over time, a one-unit increase is associated with a [β]-unit change in [Y] (b = [β], SE = [SE], p = [p])."

**Interaction:**
> "The effect of [X] on [Y] is [β₁] for [Group A] and [β₂] for [Group B]; this difference is [significant/not distinguishable from zero] (b_interaction = [Δβ], SE = [SE], p = [p])."

**Null result:**
> "We find no statistically significant association between [X] and [Y] (b = [β], SE = [SE], p = [p])."

**Practical significance:**
> "While statistically significant, the effect (b = [β]) represents [X]% of the outcome's SD, a [small/moderate/large] magnitude."

**Robustness:**
> "Results are robust to [alternative sample restriction / alternative operationalization / alternative specification] (Table A1). Following Oster (2019), we estimate δ = [X], indicating that unobserved confounders would need to be [X] times more predictive of [Y] than our observed controls to explain away the finding."

**LCA / Mixture models:**
> "Latent class analysis identified [K] distinct [typologies/profiles] based on [indicators] (Table X). A [K]-class solution provided the best fit (BIC = [X]; entropy = [X]). Class 1 ([X]%) was characterized by [pattern]; Class 2 ([X]%) by [pattern]."

**Quantile regression:**
> "Quantile regression reveals that the association between [X] and [Y] varies across the outcome distribution (Table X; Figure X). At the 10th percentile, [X] is associated with [b] (SE = [SE], p = [p]), whereas at the 90th percentile the effect is [b] (SE = [SE], p = [p]). The OLS estimate of [b] masks this heterogeneity."

**Zero-inflated / Hurdle:**
> "Given the excess zeros in [Y] ([X]% of observations), we estimated a zero-inflated negative binomial model (Table X). In the count process, [X] was associated with a [X]% [increase/decrease] in expected [Y] (IRR = [X], 95% CI = [[lo], [hi]], p = [p]). In the zero-inflation process, [Z] [increased/decreased] the probability of being a structural zero (OR = [X], 95% CI = [[lo], [hi]], p = [p])."

**Beta regression:**
> "Because [Y] is a bounded proportion, we estimated beta regression (Table X). [X] is associated with a [direction] in [Y] (b = [b], SE = [SE], p = [p]). The average marginal effect indicates a [AME] percentage-point change per one-unit increase in [X] (AME = [AME], 95% CI = [[lo], [hi]])."

**Competing risks:**
> "The cumulative incidence of [event] at [T] years was [X]% (95% CI = [[lo]%, [hi]%]). In the Fine-Gray model, [X] was associated with a [X]% [higher/lower] subdistribution hazard of [event] (SHR = [X], 95% CI = [[lo], [hi]], p = [p]), accounting for the competing risk of [competing event]."

**RI-CLPM:**
> "The RI-CLPM (Hamaker et al., 2015) separated stable between-person differences from within-person dynamics across [T] waves (Table X). At the within-person level, [X at time t] [predicted/did not predict] [Y at t+1] (b = [b], SE = [SE], p = [p]), while the reverse path was [significant/nonsignificant] (b = [b], SE = [SE], p = [p])."

**Sequence analysis:**
> "Sequence analysis with optimal matching identified [K] distinct [trajectory] typologies (Table X; Figure X). Cluster 1 ('[label],' [X]%) was characterized by [pattern]. [Covariate] was associated with [higher/lower] odds of following the '[label]' trajectory (RRR = [X], 95% CI = [[lo], [hi]], p = [p])."

**SEM / CFA:**
> "Confirmatory factor analysis established the measurement model (Table X). All loadings exceeded [.40] (p < .001). The model fit well (CFI = [X], TLI = [X], RMSEA = [X] [90% CI: [lo], [hi]], SRMR = [X]). In the structural model, [latent predictor] was [positively/negatively] associated with [latent outcome] (b = [b], beta = [beta], p = [p])."

**Multiple testing correction:**
> "To account for [X] simultaneous tests, we applied [Benjamini-Hochberg / Holm] correction (Table X). After adjustment, [X] of [Y] hypotheses remained significant at FDR < .05."

---

### Results Section Structure

Write the following four paragraph types in order. Each must contain actual numbers.

```
¶1 SAMPLE DESCRIPTION
   Overall N; group sizes if stratified; means and SDs for key variables; reference Table 1.
   Note exclusions and reason.

¶2 MAIN FINDINGS (H1 test)
   State whether H1 is supported. Report focal coefficient with full statistics.
   Describe attenuation (or lack thereof) from M1 → M2. Reference Table 2.

¶3 EXTENDED MODEL (H2/moderation/mediation if applicable)
   M3 results; conditional effects at key moderator values; reference the marginal effects figure.
   Skip if no moderation/mediation hypothesis.

¶4 ROBUSTNESS
   2–4 sentences summarizing Table A1. Confirm main finding holds.
   Report Oster delta if OLS + causal language.
```

**Writing rules:**
- Lead every paragraph with the substantive finding, not a method description
- Report exact p-values in text (p = .034); use stars only in tables
- Reference tables and figures inline: "(Table 2, Column 3)"; "(Figure 2)"
- Report effect sizes alongside p-values — p < .001 without β is uninterpretable
- Avoid "proves" — use "is consistent with," "supports," "suggests"
- Null findings must be reported with full statistics, not just "not significant"
- No passive voice constructions ("was found to be") — active voice only

---

## COMPONENT D: Script Archiving and Coding Decisions

This component runs **cross-cuttingly** throughout Components A and B. It ensures every executed code block is saved as a self-contained script, every analytic decision is logged with rationale, and a master script index maps scripts to paper elements — so that building a replication package later (via `/scholar-open`) requires assembly, not reconstruction.

### D0 — Initialize Script Log Files

Run at the start of every `scholar-analyze` session, immediately after `mkdir`:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"

# Initialize coding decisions log
cat > "${OUTPUT_ROOT}/scripts/coding-decisions-log.md" << 'LOGEOF'
# Coding Decisions Log
<!-- Append-only log. Each entry records one analytic decision with rationale. -->

| Timestamp | Step | Decision | Alternatives Considered | Rationale | Variables Affected | Script |
|-----------|------|----------|------------------------|-----------|-------------------|--------|
LOGEOF

# Initialize script index
cat > "${OUTPUT_ROOT}/scripts/script-index.md" << 'IDXEOF'
# Script Index

## Run Order

| # | Script | Purpose | Input | Output | Paper Element |
|---|--------|---------|-------|--------|---------------|
IDXEOF
```

### D1 — Script Save Protocol

After each code block is executed (or written as `[CODE-TEMPLATE]`) in steps A1–A8 and B0–B8, save the complete script to `${OUTPUT_ROOT}/scripts/[NN]-[name].[ext]`.

**Standard script header** (prepend to every saved script):
```r
# ============================================================
# Script: [NN]-[name].R
# Purpose: [one-line description]
# Input:   [data file or prior script output]
# Output:  [tables, figures, or objects produced]
# Date:    [YYYY-MM-DD]
# Seed:    set.seed(42)
# Notes:   [SE type, sample restrictions, key parameters]
# ============================================================
```

**Scripts must be self-contained**: include explicit `library()` calls, data loading (`readRDS()`/`read_csv()`), and `set.seed()`. No reliance on in-memory objects from prior scripts.

**Step-to-filename mapping:**

| Step | Script name | Description |
|------|-------------|-------------|
| A1 | `01-data-loading.R` | Load + inspect data |
| A2 | `03-descriptives-table1.R` | Descriptive statistics table |
| A3 | `04-main-models.R` | Regression model ladder |
| A4 | `05-marginal-effects.R` | AME computation |
| A5 | `06-diagnostics.R` | VIF, BP test, Cook's D |
| A6 | `07-export-tables.R` | modelsummary export |
| A7 | `08-robustness.R` | Robustness checks + Oster |
| A8 | `09-decomposition.R` | Oaxaca-Blinder (if applicable) |
| A8a | `09a-lca-mixture.R` | Latent class analysis (if applicable) |
| A8b | `09b-quantile-regression.R` | Quantile regression (if applicable) |
| A8c | `09c-zero-inflated.R` | Zero-inflated / hurdle models (if applicable) |
| A8d | `09d-beta-regression.R` | Beta regression (if applicable) |
| A8e | `09e-competing-risks.R` | Competing risks models (if applicable) |
| A8f | `09f-riclpm.R` | RI-CLPM (if applicable) |
| A8g | `09g-sequence-analysis.R` | Sequence analysis (if applicable) |
| A8h | `09h-sem-cfa.R` | Full SEM / CFA (if applicable) |
| A8i | `09i-multiple-testing.R` | Multiple testing correction (if applicable) |
| B0 | `10-viz-setup.R` | Theme + palette + save_fig() |
| B1 | `11-viz-descriptive.R` | Distribution + violin + bar |
| B2 | `12-viz-coefficient.R` | Coefficient / forest plot |
| B3 | `13-viz-marginal.R` | AME + interaction + predicted |
| B4 | `14-viz-event-study.R` | Event study (if DiD) |
| B5 | `15-viz-rd.R` | RD plot (if RD) |
| B6 | `16-viz-balance.R` | Love plot (if matching) |
| B7 | `17-viz-survival.R` | Kaplan-Meier (if survival) |
| B8 | `18-viz-python.py` | Python figures (if used) |

**No-data mode:** Save with `# [CODE-TEMPLATE] — run when data available` as the first line after the header.

### D2 — Coding Decisions Log Protocol

After EVERY analytic step in A0–A8, append an entry to `${OUTPUT_ROOT}/scripts/coding-decisions-log.md` via Bash `>>`. Each entry records one decision:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "| $(date '+%Y-%m-%d %H:%M') | A3 | OLS with HC3 robust SEs | Default SEs, clustered SEs | HC3 chosen because heteroskedasticity detected (BP p < .05) | Y, X, C1-C4 | 04-main-models.R |" >> "${OUTPUT_ROOT}/scripts/coding-decisions-log.md"
```

**Required decision categories** (log at least one entry for each when applicable):
- **Model type selection**: Why OLS vs. logit vs. FE vs. MLM
- **Standard error type**: Why HC3 vs. clustered vs. default
- **Control variable selection**: Which controls included and why; which excluded and why
- **Sample restrictions**: Any observations dropped; rationale
- **Missing data strategy**: Listwise deletion vs. MI; justification
- **Robustness design**: Which alternative specs and why they test the right threat

This incremental-persistence pattern protects against context compaction — decisions are on disk the moment they are made.

### D3 — Script Index Update

After each script is saved in D1, append a row to the run-order table in `${OUTPUT_ROOT}/scripts/script-index.md`:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "| 4 | 04-main-models.R | Main regression ladder (M1-M3) | data/analysis_data.rds | ${OUTPUT_ROOT}/tables/table2-regression.html | Table 2 |" >> "${OUTPUT_ROOT}/scripts/script-index.md"
```

At the end of the run, finalize `script-index.md` by appending:

```markdown
## Dependencies
- Scripts 03–09 depend on 01-data-loading.R output
- Scripts 10–18 depend on model objects from 04 and 05

## Seeds
All scripts use `set.seed(42)`.

## Paper-Element Correspondence
| Paper element | Script(s) | Output file(s) |
|---------------|-----------|----------------|
| Table 1 | 03-descriptives-table1.R | output/[slug]/tables/table1-descriptives.html/.tex/.docx |
| Table 2 | 04-main-models.R, 07-export-tables.R | output/[slug]/tables/table2-regression.html/.tex/.docx |
| Figure 1 | 11-viz-descriptive.R | output/[slug]/figures/fig-dist-outcome.pdf/.png |
| ... | ... | ... |

## Coding Decisions
See [coding-decisions-log.md](coding-decisions-log.md) for the full decision rationale log.
```

---

## Quality Checklist

- [ ] Output directories created (`output/[slug]/tables/`, `output/[slug]/figures/`, `output/[slug]/scripts/`)
- [ ] Data loaded successfully (file / inline / online fetch confirmed)
- [ ] **Causal gate**: if causal design detected, `/scholar-causal` invoked (or confirmed already run)
- [ ] Table 1 descriptives saved as HTML + TeX + docx
- [ ] Regression table saved as HTML + TeX + docx
- [ ] AME table saved (HTML + TeX + docx) for any logit/ordered logit model
- [ ] Robustness table saved as HTML + TeX + docx
- [ ] **A9 Analysis Verification subagent run** — PASS confirmed (or all issues fixed)
- [ ] At least one figure saved as PDF + PNG (300 DPI)
- [ ] All figures use colorblind-safe palette; no red-green pairs
- [ ] **B9 Visualization Verification subagent run** — PASS confirmed (or all issues fixed)
- [ ] Each hypothesis has a corresponding results paragraph
- [ ] Effect sizes reported alongside significance
- [ ] Journal's reporting norms applied (AME / SE / CI / star format)
- [ ] Null findings reported honestly
- [ ] No causal language without causal design
- [ ] **Scripts saved** for every executed code block in `output/[slug]/scripts/` (D1)
- [ ] **Script headers present**: every script has purpose, input, output, date, seed (D1)
- [ ] **Coding decisions log** has entries for model selection, SE type, variable selection, sample restrictions, missing data, robustness design (D2)
- [ ] **Script index** has rows for all scripts + paper-element correspondence table (D3)
- [ ] **Internal log saved** (`scholar-analyze-log-[topic]-[date].md`) — decisions, verification, file inventory
- [ ] **Publication-ready results saved** (`scholar-analyze-results-[topic]-[date].md`) — Results prose + table notes + figure captions; no brackets remaining

---

## Save Output

Use the Write tool to save **two separate files** after completing all components.

---

### File 1 — Internal Analysis Log

**Filename:** `scholar-analyze-log-[topic-slug]-[YYYY-MM-DD].md`

**Purpose:** Technical record for your own reference — decisions, verification results, file inventory. Not for submission.

**Template:**
```markdown
# Analysis Log: [Topic] — [YYYY-MM-DD]

## Data Source
- Mode: [1 / 2 / 3]
- Source: [file path / inline description / package + dataset name + citation]
- N (raw): [X]; N (analytic): [X]; exclusions: [reason]

## Analytic Decisions
- Outcome (Y): [variable name + measurement]
- Key predictor (X): [variable name + measurement]
- Controls: [list]
- Model type: [OLS / logit / FE / Cox / etc.]
- SE type: [HC3 / clustered by unit / default]
- Causal design: [/scholar-causal invoked: yes/no; strategy: DiD / RD / IV / none]

## Verification Results
- A9 Analysis Verification: [PASS / issues fixed: ...]
- B9 Visualization Verification: [PASS / issues fixed: ...]

## Key Estimates (Quick Reference)
| Predictor | β / AME | SE / 95% CI | p |
|-----------|---------|-------------|---|
| [X]       | [β]     | [SE]        | [p] |
| ...       |         |             |   |

## Robustness Summary
- No outliers: [β, p] vs. main [β, p] — [holds / attenuates]
- Alt measure: [β, p] vs. main [β, p] — [holds / attenuates]
- Oster δ: [X] — [interpretation]

## File Inventory
output/[slug]/tables/table1-descriptives.html / .tex / .docx
output/[slug]/tables/table2-regression.html / .tex / .docx
output/[slug]/tables/table2-ame.html / .tex / .docx       (if logit)
output/[slug]/tables/tableA1-robustness.html / .tex / .docx
output/[slug]/figures/fig-dist-outcome.pdf / .png
output/[slug]/figures/fig-coef-plot.pdf / .png
output/[slug]/figures/fig-ame-[x].pdf / .png              (if plotted)
output/[slug]/figures/fig-event-study.pdf / .png          (if DiD)
[list all actual figures generated]

## Script Archive
output/[slug]/scripts/coding-decisions-log.md
output/[slug]/scripts/script-index.md
output/[slug]/scripts/[list all saved scripts, e.g.:]
  01-data-loading.R
  03-descriptives-table1.R
  04-main-models.R
  05-marginal-effects.R
  [... etc.]
```

---

### File 2 — Publication-Ready Results Document

**Filename:** `scholar-analyze-results-[topic-slug]-[YYYY-MM-DD].md`

**Purpose:** Drop-in material for the manuscript. Contains the complete Results section prose, table notes, and figure captions — all formatted for the target journal. Ready to paste into `/scholar-write`.

**Template — fill every placeholder with actual values before saving:**

```markdown
# Results: [Paper Title or Topic]
*Target journal: [ASR / AJS / Demography / Science Advances / NHB]*
*Word count: ~[XXX] words (target: [journal limit])*

---

## Results

[¶1 — SAMPLE DESCRIPTION]
The analytic sample comprises [N] [units/respondents/observations] drawn from [data source].
[Key group sizes if stratified.] Table 1 presents descriptive statistics. [Outcome variable]
averages [M] (SD = [SD]) overall[; Group A: M = [Ma], Group B: M = [Mb], p = [p]].
[Note any exclusions and reason.]

[¶2 — MAIN FINDINGS]
[State H1 support.] [Focal predictor] is [positively/negatively] associated with [outcome]
after adjusting for [list key controls] (b = [β], SE = [SE], p = [p]; Table 2, Column 2).
[For logit:] The average marginal effect indicates a [β×100] percentage point [increase/decrease]
in the probability of [outcome] per one-unit increase in [X] (AME = [β], 95% CI = [[lo], [hi]]).
[Describe coefficient stability M1 → M2.] [Reference figure if applicable: Figure 1.]

[¶3 — EXTENDED MODEL / INTERACTION / MEDIATION — omit if not applicable]
[M3 results. Conditional effects at key moderator values. Reference Figure X.]

[¶4 — ROBUSTNESS]
Results are robust to [alternative sample restriction / alternative operationalization /
alternative specification] (Table A1, Columns 2–3). [Report Oster delta if applicable:
Following Oster (2019), we estimate δ = [X], indicating that unobserved confounders
would need to be [X] times more predictive of [Y] than our observed controls to
explain away the finding.]

---

## Table Notes

**Table 1. Descriptive Statistics[, by Group]**
*Note.* [Describe statistics shown (mean/SD or N/%); sample; any weighting applied.]
[N = X.]

**Table 2. [Regression Results / Average Marginal Effects]: [Outcome] on [Predictor(s)]**
*Note.* [SE type] in parentheses. [Reference category for key categorical predictors.]
[Sample description.] [Significance: * p < .05, ** p < .01, *** p < .001.]
[N = X per column or as shown.]

**Table A1. Robustness Checks**
*Note.* Column 1 replicates the main model (Table 2, Column [X]).
Column 2 [description of restriction/change]. Column 3 [description].
[SE type] in parentheses. * p < .05, ** p < .01, *** p < .001.

---

## Figure Captions

**Figure 1. [Descriptive title: what is shown and for whom]**
[Self-explanatory caption: describe what each axis represents, what the shading/color codes, what error bars show (95% CI / SE / SD), data source, and analytic sample. Do not rely on main text to interpret.] N = [X].

**Figure 2. [Title]**
[Caption.] [Error bars = 95% CI.] N = [X].

[Add one caption block per figure generated in Component B.]
```

---

Confirm all three output paths to user at end of run.

---

See [references/analysis-standards.md](references/analysis-standards.md) for journal-specific reporting requirements and [references/viz-standards.md](references/viz-standards.md) for figure type guide and export standards.

**Output files produced by this skill:**
- `output/[slug]/tables/` — regression tables and descriptive stats (.html / .tex / .docx)
- `output/[slug]/figures/` — all figures (.pdf / .png; interactive as .html)
- `output/[slug]/scripts/` — self-contained analysis scripts (`[NN]-[name].R/.py`), `coding-decisions-log.md`, `script-index.md`
- `scholar-analyze-log-[topic]-[date].md` — internal technical log (decisions, verification, file inventory)
- `scholar-analyze-results-[topic]-[date].md` — **publication-ready**: Results section prose + table notes + figure captions; ready to paste into `/scholar-write`

**Post-analysis verification (recommended):**

After all tables and figures are produced, suggest to the user:

> "Analysis outputs saved. Run `/scholar-verify stage1` to verify raw outputs (tables, figures) are internally consistent before writing. This catches stale figures, mismatched table formats, and missing outputs early — before they propagate into the manuscript."

This is a recommendation, not a gate — the user may proceed directly to `/scholar-write` if preferred. If run, `scholar-verify stage1` launches verify-numerics and verify-figures on the raw outputs in `output/tables/` and `output/figures/`.

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-analyze"
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
