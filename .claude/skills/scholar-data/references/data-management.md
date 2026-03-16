# Data Management Reference

## Codebook Template

### Variable-Level Documentation

```
Variable: educ_yrs
Label:     Years of formal education completed
Source:    Q14 in survey instrument ("What is the highest grade or year of
           school you have completed?")
Type:      Continuous (integer)
Range:     0–25 (capped at 25 for 5+ years graduate school)
Missing:   -99 = Refused; -98 = Don't know; -97 = Not applicable
Notes:     Recoded from original 5-category ordinal. Midpoints used:
           "Less than HS" = 8; "HS/GED" = 12; "Some college" = 14;
           "BA" = 16; "Graduate degree" = 18.
           Original variable: educ_cat (5 levels)
```

### Codebook Structure (Excel/CSV)

| var_name | var_label | type | values | missing_codes | source | notes |
|----------|-----------|------|--------|--------------|--------|-------|
| id | Unique respondent ID | string | — | — | Generated | Never use for analysis |
| educ_yrs | Years of education | integer | 0–25 | -99, -98, -97 | Q14 | Recoded from educ_cat |
| income_1k | Annual HH income ($1000s) | numeric | 0–999 | -99, -98 | Q22 | Top-coded at 250 |

---

## Data Cleaning Decision Log Template

Record every non-obvious data decision:

```
DATA CLEANING DECISION LOG
Project: [name]
Analyst: [name]
Date started: [date]
Date last updated: [date]

─────────────────────────────────────────────────
Entry [001] — Date: [date]

Variable: income_1k
Decision: Top-code at $250,000 (250 in $1000s)
Rationale: 23 respondents (0.5%) report income > $250K; extreme values
           distort OLS coefficients; results consistent with and without
           (see sensitivity_income.R)
Alternative considered: Log transformation (tested; similar results;
                        top-coding preferred for interpretability)
N affected: 23 (0.5% of sample)
─────────────────────────────────────────────────
Entry [002] — Date: [date]

Variable: marital_status
Decision: Collapse "separated" with "divorced" (merged into "divorced/separated")
Rationale: "Separated" N = 41 (0.9%); too small for separate category;
           theoretically similar in terms of household composition
N affected: 41
─────────────────────────────────────────────────
```

---

## Sample Construction Flow Template

Document every step of the sample construction, with N at each step:

```
SAMPLE CONSTRUCTION — [Study Name]

Starting universe: All respondents in [Data Source] [year/wave], N = 45,231

Exclusion 1: Age restriction (keep 25–64)
  N removed: 18,445
  Remaining: 26,786
  Rationale: Standard working-age sample to avoid school enrollment and
             retirement transitions confounding labor market outcomes

Exclusion 2: Missing on outcome variable (annual earnings)
  N removed: 3,212 (12.0% of remaining)
  Remaining: 23,574
  Note: Compare excluded to retained on demographics (see attrition_check.R)

Exclusion 3: Institutionalized (prison, nursing home)
  N removed: 287
  Remaining: 23,287

Exclusion 4: Missing on any control variable (listwise deletion)
  N removed: 1,089 (4.7% of remaining)
  Remaining: 22,198

FINAL ANALYTIC SAMPLE: N = 22,198

Demographics of final sample:
  Age: M = 41.3, SD = 11.2
  Female: 51.2%
  White: 64.8%; Black: 12.3%; Hispanic: 16.2%; Other: 6.7%
  College+: 38.1%
  Median income: $52,400
```

---

## Naming Conventions

### Variables
- All lowercase with underscores: `educ_yrs`, `inc_1k`, `female`
- No spaces, no special characters, no leading numbers
- Consistent suffixes: `_cat` (categorical), `_bin` (binary), `_ln` (log-transformed), `_std` (standardized)
- Prefixes for wave: `w1_`, `w2_` for panel data

### Files
- All lowercase with underscores or hyphens: `gss_2022_clean.rds`
- Include date in version-tracked files: `analysis_data_2024-01-15.rds`
- Never spaces in filenames

### Script files (numbered for order)
- `01_download.R` / `01_download.py`
- `02_clean.R`
- `03_eda.R`
- `04_main_models.R`
- `05_robustness.R`
- `06_figures.R`

---

## R Data Pipeline Template

```r
# 02_clean.R — Data cleaning script
# Input:  data/raw/gss_2022.csv
# Output: data/clean/gss_clean.rds
# Author: [name]; Date: [date]

library(tidyverse)
library(haven)   # for Stata/SPSS labels

# ---- Load raw data ----
raw <- read_csv("data/raw/gss_2022.csv")
cat("Raw data: N =", nrow(raw), "× K =", ncol(raw), "\n")

# ---- Set missing values ----
raw <- raw %>%
  mutate(across(c(income, educ, age),
                ~ ifelse(. %in% c(-99, -98, -97, 999), NA, .)))

# ---- Recode / derive variables ----
df <- raw %>%
  mutate(
    female   = as.integer(sex == 2),
    educ_yrs = case_when(
      educ == 1 ~ 8,   # Less than HS
      educ == 2 ~ 12,  # HS graduate
      educ == 3 ~ 14,  # Some college
      educ == 4 ~ 16,  # BA
      educ == 5 ~ 18,  # Graduate degree
      TRUE ~ NA_real_
    ),
    income_1k = pmin(income / 1000, 250)  # top-code at $250K
  )

# ---- Sample restrictions ----
n_before <- nrow(df)
df <- df %>%
  filter(age >= 25, age <= 64) %>%
  filter(!is.na(income_1k)) %>%
  filter(institutionalized == 0) %>%
  drop_na(educ_yrs, age, female, race)  # listwise deletion
cat("Analytic sample: N =", nrow(df), "(excluded:", n_before - nrow(df), ")\n")

# ---- Save ----
saveRDS(df, "data/clean/gss_clean.rds")
message("Clean data saved: data/clean/gss_clean.rds")
```

---

## Stata Data Pipeline Template

```stata
* 02_clean.do — Data cleaning
* Input:  data/raw/gss2022.dta
* Output: data/clean/gss_clean.dta

use "data/raw/gss2022.dta", clear
count  // N = 45,231

* ---- Set missing values ----
foreach var of varlist income educ age {
    replace `var' = . if inlist(`var', -99, -98, -97, 999)
}

* ---- Recode variables ----
gen female   = (sex == 2) if !missing(sex)
gen educ_yrs = .
replace educ_yrs = 8  if educ == 1
replace educ_yrs = 12 if educ == 2
replace educ_yrs = 14 if educ == 3
replace educ_yrs = 16 if educ == 4
replace educ_yrs = 18 if educ == 5

gen income_1k = min(income / 1000, 250)  // top-code

* ---- Sample restrictions ----
keep if age >= 25 & age <= 64
drop if missing(income_1k)
drop if institutionalized == 1
drop if missing(educ_yrs) | missing(female) | missing(race)

count  // Report final N

* ---- Label variables ----
label var female   "Female (1=yes)"
label var educ_yrs "Years of education"
label var income_1k "Annual HH income ($1000s, top-coded $250K)"

save "data/clean/gss_clean.dta", replace
```

---

## Git Workflow for Research Projects

```bash
# Initialize and first commit (scripts + docs only — never raw data)
git init
git add scripts/ docs/ Makefile README.md
git commit -m "Initial project structure"

# Day-to-day workflow
git add scripts/02_clean.R
git commit -m "Add recoding for education variable; top-code income at $250K"

# Before sharing or submitting: tag the analysis version
git tag -a v1.0 -m "Analysis as submitted to ASR 2024-06-15"
git push origin main --tags
```

**.gitignore template:**
```
# Data — never commit identified or raw data
data/raw/
data/clean/
data/analysis/
*.csv
*.dta
*.rds
*.parquet

# Credentials
.Renviron
.env
*.key
secrets/

# OS / editor
.DS_Store
.Rproj.user/
__pycache__/
*.pyc
*.Rhistory
```

## Makefile for Reproducible Pipeline

```makefile
# Makefile — run `make all` to reproduce entire analysis from raw data

all: data/analysis/analytic_sample.rds output/[slug]/tables/table1.html output/[slug]/figures/fig-coef.pdf

data/clean/gss_clean.rds: data/raw/gss_2022.csv scripts/02_clean.R
	Rscript scripts/02_clean.R

data/analysis/analytic_sample.rds: data/clean/gss_clean.rds scripts/03_eda.R
	Rscript scripts/03_eda.R

output/[slug]/tables/table1.html output/[slug]/figures/fig-coef.pdf: data/analysis/analytic_sample.rds scripts/04_main_models.R
	Rscript scripts/04_main_models.R

clean:
	rm -f data/clean/*.rds data/analysis/*.rds output/[slug]/tables/*.html output/[slug]/figures/*.pdf
```
