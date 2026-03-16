# Data Cleaning and EDA Reference

## Variable-Type Cleaning Decisions

### Continuous Variables
```r
# Check distribution
hist(df$income, breaks = 50)
summary(df$income)
# Skewness
library(moments); skewness(df$income, na.rm = TRUE)

# Log transform if right-skewed and bounded below by 0
df$ln_income <- log(df$income + 1)  # +1 to handle zeros

# Winsorize extreme values (cap at 1st/99th percentile)
q <- quantile(df$income, c(0.01, 0.99), na.rm = TRUE)
df$income_w <- pmin(pmax(df$income, q[1]), q[2])
```

**Decision tree**:
- Right-skewed + positive → log transform
- Bounded [0,1] → logit transform for regression input
- Negative skew → reflect + log
- Not transformable → winsorize + note in paper

### Binary Variables
```r
# Check coding: must be 0/1, not 1/2
table(df$female)
df$female <- as.integer(df$sex == 2)  # recode 1/2 → 0/1

# Check rare events
prop.table(table(df$y_binary))
# If < 5% positive: flag; consider rare events logistic (ReLogit) or penalized
```

### Categorical Variables
```r
# Check frequencies; collapse sparse categories
table(df$race)
# If "other" < 3% of sample → discuss in paper; may collapse or exclude from FE models

# Set reference category explicitly
df$race <- relevel(factor(df$race), ref = "White")
```

### Panel / Longitudinal Variables
```r
library(plm)
pdata <- pdata.frame(df, index = c("id","year"))

# Check within-person variation on key predictor
# (Required if using FE)
cat("Between SD:", sd(tapply(df$x, df$id, mean, na.rm=TRUE), na.rm=TRUE))
cat("Within SD:", sd(df$x - ave(df$x, df$id, FUN=function(x) mean(x,na.rm=TRUE)), na.rm=TRUE))
```

---

## Outlier Decision Protocol

**Step 1: Identify**
```r
model <- lm(y ~ x1 + x2 + x3, data = df)
df$cooks  <- cooks.distance(model)
df$lever  <- hatvalues(model)
df$stdres <- rstandard(model)

# Flag: Cook's D > 4/N, leverage > 2*(k+1)/N, |stdres| > 3
threshold_cook  <- 4 / nrow(df)
threshold_lever <- 2 * (ncol(model.matrix(model))) / nrow(df)
outliers <- df[df$cooks > threshold_cook | abs(df$stdres) > 3, ]
nrow(outliers)
```

**Step 2: Investigate**
- Are these data entry errors? (Fix or exclude with documentation)
- Are they genuine but extreme cases? (Report sensitivity without them)
- Do they represent a different population? (Consider separate analysis)

**Step 3: Decision and reporting**
- NEVER delete outliers just because they weaken your result
- If you exclude them: state exactly why and how many; show results with and without
- Preferred approach: run primary analysis with outliers; show robustness without in appendix

### String and Date Variables
```r
library(stringr); library(lubridate)

# Standardize string variable
df$name_clean <- str_squish(str_to_lower(df$name))  # lowercase + trim whitespace

# Parse dates (common formats)
df$date_parsed <- lubridate::mdy(df$date_raw)   # "01/15/2020"
df$year  <- lubridate::year(df$date_parsed)
df$month <- lubridate::month(df$date_parsed)

# Extract year from messy string field
df$year <- as.integer(str_extract(df$date_str, "\\d{4}"))
```

### Survey-Weighted Variables
```r
library(survey)

# Define complex survey design
svy <- svydesign(
  ids     = ~psu,          # primary sampling unit
  strata  = ~strata,       # stratification variable
  weights = ~weight,       # sampling weight
  data    = df,
  nest    = TRUE
)

# Weighted descriptive statistics
svymean(~outcome, svy, na.rm = TRUE)
svyby(~outcome, ~group, svy, svymean)

# Weighted table
svytable(~race + education, svy)

# Note: all subsequent models should use svyglm() not glm()
m_svy <- svyglm(outcome ~ predictor + control1, design = svy, family = gaussian())
```

---

## Standard Descriptive Statistics Functions

### R (modelsummary + tableone)
```r
library(modelsummary)
library(tableone)

# Full descriptive table
datasummary_skim(df[, c("y","x1","x2","age","female","educ_yrs","income_1k")])

# By-group comparison table (Table 1 style)
tab1 <- CreateTableOne(
  vars = c("y","x1","age","female","educ_yrs","income_1k"),
  strata = "treatment",
  data = df,
  factorVars = c("female")
)
print(tab1, smd = TRUE)  # SMD = standardized mean difference
```

### Stata
```stata
* Overall descriptives
tabstat y x1 age female educ_yrs income_1k, stats(mean sd min max p25 p50 p75 n) col(stats)

* By group
tabstat y x1 age female educ_yrs, by(treatment) stats(mean sd n)

* Test balance
ttest y, by(treatment)
```

---

## Pre-Analysis Plan Memo Template (Internal)

```
PRE-ANALYSIS PLAN MEMO
─────────────────────────────────────────
Project: [Title]
Analyst: [Name]
Date: [Date — before any outcome analysis]

1. ANALYTIC SAMPLE
   Start: N = [X]
   Exclusions:
   [1. Reason → N remaining]
   [2. Reason → N remaining]
   Final N: [X]

2. DEPENDENT VARIABLE
   Name: [var]
   Operationalization: [how measured]
   Type: [continuous / binary / count / ordinal]
   Distribution: [expected; normal / skewed / bounded]
   Transformation planned: [none / log / winsorize]

3. KEY INDEPENDENT VARIABLE
   Name: [var]
   Operationalization: [how measured]
   Variation: [% treated / SD; within vs. between for panel]

4. CONTROLS
   List: [var1 (rationale), var2 (rationale), ...]
   Any risk of post-treatment bias? [check for each]

5. MISSING DATA
   % missing on outcome: [X%]
   % missing on key IV: [X%]
   Treatment: [listwise / multiple imputation / other]

6. MODEL SPECIFICATION
   Primary model: [OLS / logit / panel FE / Cox / etc.]
   Standard errors: [robust / clustered (level) / bootstrapped]
   Hypothesis tested in which coefficient: [beta for var X in model M]

7. HYPOTHESES
   H1: [X associated with Y, direction]
   H2: [moderation / mediation if applicable]

8. PLANNED ROBUSTNESS CHECKS
   [1. Alternative operationalization of X]
   [2. Alternative sample]
   [3. Alternative model]
   [4. Placebo test]

9. EXPLORATORY ANALYSES (not prespecified)
   [List any analyses planned that are exploratory]

10. PREREGISTERED? [Yes — OSF URL / No]
```
