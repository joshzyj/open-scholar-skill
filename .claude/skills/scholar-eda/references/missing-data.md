# Missing Data Reference

## Diagnosing the Missing Data Mechanism

### Little's MCAR Test
```r
library(naniar)
mcar_test(df)
# p < .05 → NOT MCAR → imputation likely needed
# p > .05 → MCAR not rejected → listwise deletion acceptable
```

### Comparing Observed vs. Missing Cases
```r
library(tableone)
# Create indicator for missing on outcome
df$miss_y <- as.integer(is.na(df$outcome))
CreateTableOne(vars = c("age","female","education","income"),
               strata = "miss_y", data = df, test = TRUE)
# If significant differences → MAR or MNAR
```

### Shadow Matrix / Missingness as Outcome
```r
# Predict missingness from observed covariates
df$miss_x <- as.integer(is.na(df$key_predictor))
logit_miss <- glm(miss_x ~ age + female + education + income,
                  data = df, family = binomial)
summary(logit_miss)
# Significant predictors indicate MAR (or possibly MNAR)
```

---

## Multiple Imputation Reference

### When to Use MI
- MAR assumption is reasonable (missingness explained by observed covariates)
- Missing on key predictor or outcome variable > 5%
- Journal requires MI (Demography, NHB increasingly expect this)

### Mice Package (R) — Full Workflow
```r
library(mice)
library(mitools)

# Step 1: Inspect missing data pattern
md.pattern(df[, c("y","x1","x2","age","female","educ")])

# Step 2: Impute (m = number of imputations; 20–50 typical for social science)
imp <- mice(df, m = 20, seed = 42,
            method = c("pmm",   # y: predictive mean matching (continuous)
                       "pmm",   # x1
                       "logreg", # x2: logistic regression (binary)
                       "",       # age: not missing, skip
                       "",       # female: not missing
                       "polr"))  # educ: proportional odds (ordered)

# Step 3: Analyze on each imputed dataset
fit <- with(imp, lm(y ~ x1 + x2 + age + female + educ))

# Step 4: Pool using Rubin's rules
pooled <- pool(fit)
summary(pooled)
```

**Imputation method selection**:
| Variable type | Method |
|--------------|--------|
| Continuous, symmetric | `pmm` (predictive mean matching) |
| Continuous, skewed | `pmm` with transformed variable |
| Binary | `logreg` |
| Unordered categorical | `polyreg` |
| Ordered categorical | `polr` |
| Count | `pmm` or `cart` |

**Number of imputations**: m = max(% missing × 100, 20). For 15% missing, use m = 20. For 30% missing, use m = 30.

### Reporting MI in Paper
> "We used multiple imputation by chained equations (MICE; van Buuren & Groothuis-Oudshoorn 2011) to handle missing data on [variables] (range: [X]%–[Y]% missing). We created [m] imputed datasets and combined estimates using Rubin's rules. Results were consistent across imputed and complete-case analyses (Appendix Table A[X])."

---

## MNAR Sensitivity Analysis

When MNAR is plausible (missingness related to the missing value itself — e.g., high-income respondents less likely to report income):

### Selection Model (Heckman)
```r
library(sampleSelection)
# Two-equation model:
# Selection equation: Z (instrument) → missing indicator
# Outcome equation: X → Y (only for observed)

heck <- selection(
  selection = ~z + age + female,   # Z must predict selection but not outcome
  outcome   = y ~ x + age + female,
  data = df
)
summary(heck)
```

### Pattern Mixture Model
```r
# Compare results for observed cases vs. imputed cases
# If coefficients differ substantially → MNAR concern
m_obs <- lm(y ~ x, data = df[!is.na(df$y), ])
m_imp <- lm(y ~ x, data = complete(imp, 1))  # one imputed dataset
# Report both; discuss divergence
```

### Sensitivity Analysis via Delta Method
```r
# How sensitive are results to assumed level of MNAR?
# Manually shift imputed values by delta and refit
for (delta in c(-2, -1, 0, 1, 2)) {
  imp_delta <- imp
  imp_delta$imp$y <- imp$imp$y + delta  # shift imputed values
  fit_delta <- with(imp_delta, lm(y ~ x))
  cat("Delta =", delta, "; coef =", summary(pool(fit_delta))$estimate[2], "\n")
}
```

Report: "We conducted a sensitivity analysis assuming imputed values of [outcome] are [delta] units lower/higher than predicted (to simulate MNAR where high values are systematically missing). Results were robust to adjustments of ±[range] (Appendix Table A[X])."

---

## Tipping-Point / Bounds Analysis (MNAR)

When the missing data mechanism is plausibly MNAR, report a tipping-point: how extreme must the MNAR departure be to overturn the main finding?

### Manski (1990) Worst-Case Bounds (binary outcome)
```r
# If outcome Y is binary [0,1]:
# Lower bound: assign 0 to all missing Y
# Upper bound: assign 1 to all missing Y
df$y_lower <- ifelse(is.na(df$outcome), 0, df$outcome)
df$y_upper <- ifelse(is.na(df$outcome), 1, df$outcome)

m_lower <- glm(y_lower ~ predictor + control1, data = df, family = binomial)
m_upper <- glm(y_upper ~ predictor + control1, data = df, family = binomial)

cat("Lower bound OR:", exp(coef(m_lower)["predictor"]),
    " | Upper bound OR:", exp(coef(m_upper)["predictor"]), "\n")
# If both bounds have the same sign as the main estimate → robust to MNAR
```

### Reporting Template
> "To assess sensitivity to potentially non-ignorable missing data, we estimated worst-case Manski (1990) bounds by assigning the minimum and maximum possible values to all missing outcomes. The estimated effect of [X] on [Y] remained [positive/negative] across all bounds (lower: [β]; upper: [β]; main: [β]), suggesting the finding is robust to MNAR departures."
