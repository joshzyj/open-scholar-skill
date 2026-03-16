# Matching and Reweighting Reference

## Overview

Matching and reweighting estimators identify the Average Treatment Effect on the Treated (ATT) — or the ATE — by constructing a comparison group from control units that resembles the treated group on observed pre-treatment characteristics. The goal is to make the conditional independence assumption (CIA) more credible by achieving covariate balance, rather than relying solely on regression adjustment.

**When to use**: Observational data with rich pre-treatment covariates; no natural experiment; reasonably good common support between treated and control; treatment assignment mechanism can be modeled.

**What these methods cannot do**: Address unmeasured confounders (always perform sensitivity analysis); fix fundamental lack of common support; replace a valid natural experiment.

---

## The Conditional Independence Assumption (CIA)

All matching and reweighting methods rest on:

**(Y⁰, Y¹) ⊥ T | X**

Treatment assignment T is independent of potential outcomes (Y⁰, Y¹) conditional on observed covariates X. In practice, this means all variables that causally influence both treatment assignment and the outcome must be observed and included.

**Additional requirement — Overlap (Common Support)**:

**0 < P(T=1|X) < 1** for all X in the support

Every unit — regardless of covariate values — must have a non-zero probability of both receiving and not receiving treatment. Violations lead to off-support extrapolation.

---

## Method 1: Propensity Score Matching (PSM)

### What it does

Estimates the propensity score e(X) = P(T=1|X) via logistic regression, then matches each treated unit to one (or more) control units with similar e(X). Rosenbaum and Rubin (1983) showed that if CIA holds conditional on X, it also holds conditional on e(X).

### Procedure

1. Estimate logit model: `treat ~ x1 + x2 + x3 + ...`
2. Check overlap: histograms of propensity scores for treated vs. control (should overlap)
3. Match: nearest-neighbor within caliper (typically 0.2 × SD of logit propensity score)
4. Assess balance: standardized mean differences (SMD) < 0.1 for all covariates
5. Estimate ATT on matched sample

### Key parameters

- **Ratio**: 1:1 matching; 1:k nearest neighbors (k > 1 reduces variance, increases bias)
- **Caliper**: Exclude matches that are too distant (caliper = 0.2 × SD of logit(e) is standard)
- **Replacement**: Matching with replacement increases bias but improves matches for treated units with poor control overlap
- **Kernel matching**: Use all controls weighted by kernel density centered at treated unit's p-score

### R Code

```r
library(MatchIt); library(cobalt); library(marginaleffects)

# Estimate propensity scores + match
m_out <- matchit(treat ~ x1 + x2 + x3 + x4,
                 data         = df,
                 method       = "nearest",
                 distance     = "logit",
                 ratio        = 1,
                 caliper      = 0.2,
                 std.caliper  = TRUE,
                 replace      = FALSE)
summary(m_out, un = FALSE)  # Balance pre/post matching

# Love plot of standardized mean differences
love.plot(m_out, threshold = 0.1, binary = "std",
          title = "Covariate Balance: PSM")

# Overlap plot
plot(m_out, type = "density", which.xs = ~x1 + x2)

# ATT on matched sample
m_data <- match.data(m_out)
att_fit <- lm(y ~ treat + x1 + x2 + x3 + x4,
              data = m_data, weights = weights)
avg_comparisons(att_fit, variables = "treat",
                newdata = subset(m_data, treat == 1))
```

### Stata Code

```stata
ssc install psmatch2

* Estimate and match
psmatch2 treat x1 x2 x3 x4, outcome(y) neighbor(1) caliper(0.02) common logit

* Check balance
pstest x1 x2 x3 x4, both graph

* ATT
reg y treat x1 x2 x3 x4 [iweight=_weight], robust
```

### Strengths and limitations

**Strengths**: Transparent selection into comparison group; easy to explain; widely accepted in social science journals.

**Limitations**: Balance depends on correct propensity model specification; sensitive to model misspecification; can reduce sample size substantially; does not address unmeasured confounders.

---

## Method 2: Coarsened Exact Matching (CEM)

### What it does

CEM (Iacus, King, Porro 2012) coarsens continuous variables into bins, then exactly matches treated and control units within the same multivariate stratum. Any unmatched units are pruned. Weights are constructed so the weighted control distribution mirrors the treated distribution.

### Advantages over PSM

- No propensity model to specify or misspecify
- Exact balance within coarsened strata (by construction)
- Monotonic imbalance bounding: finer coarsening → better balance
- Typically retains more observations than caliper PSM

### R Code

```r
library(MatchIt)

# CEM with automatic binning
m_cem <- matchit(treat ~ x1 + x2 + x3 + x4,
                 data   = df,
                 method = "cem",
                 estimand = "ATT")
summary(m_cem, un = FALSE)
love.plot(m_cem, threshold = 0.1)

# Manual coarsening
m_cem_manual <- matchit(
  treat ~ x1 + x2 + x3,
  data   = df,
  method = "cem",
  cutpoints = list(x1 = c(0, 25, 50, 75, 100),
                   x2 = c(0, 10, 20, 30)),
  estimand = "ATT"
)

# ATT estimate
cem_data <- match.data(m_cem)
att_cem  <- lm(y ~ treat + x1 + x2 + x3,
               data = cem_data, weights = weights)
```

### Stata Code

```stata
ssc install cem

* CEM with manual cutpoints
cem x1 (0 25 50 75 100) x2 x3, treatment(treat)
summarize _cem_strata _cem_weight

* Weighted regression
regress y treat x1 x2 x3 [iweight=_cem_weight], robust
```

---

## Method 3: Entropy Balancing (Hainmueller 2012)

### What it does

Entropy balancing reweights control units — without discarding any — so that weighted moments (means, variances, skewness if desired) of control covariates exactly match those of the treated group. Weights are found by solving a convex optimization problem that maximizes weight entropy (minimizes weight variance) subject to the moment constraints.

### Advantages

- Exact balance on specified moments (by construction)
- Retains all observations (no pruning)
- Variance of weights is minimized → efficient
- No propensity model specification needed
- Can balance on higher moments (variance, skewness) as well as means

### R Code

```r
library(WeightIt); library(cobalt)

# Entropy balancing for ATT
w_eb <- weightit(treat ~ x1 + x2 + x3 + x4,
                 data      = df,
                 method    = "ebal",
                 estimand  = "ATT",
                 moments   = 1)   # 1 = means only; 2 = means+variances
summary(w_eb)
love.plot(w_eb, threshold = 0.1, title = "Covariate Balance: Entropy Balancing")

# Check effective sample size
w_eb$ESS  # ESS for controls after weighting (should not collapse to tiny N)

# Weighted outcome regression
library(lmw)
lmw_fit <- lmw(~ treat + x1 + x2 + x3, data = df,
               type = "MRI", estimand = "ATT")
lmw_est <- lmw_est(lmw_fit, outcome = "y")
summary(lmw_est)

# Alternatively: weighted OLS (HC2 SEs for weighted estimator)
att_eb <- lm_weightit(y ~ treat, data = df, weightit = w_eb)
summary(att_eb, ci = TRUE)
```

### Stata Code

```stata
ssc install ebalance

* Balance on means (moments = 1)
ebalance treat x1 x2 x3 x4, targets(1) gen(_eb_weight)
regress y treat x1 x2 x3 x4 [pweight=_eb_weight], robust

* Check balance
foreach v in x1 x2 x3 x4 {
    ttest `v' [iweight=_eb_weight], by(treat)
}
```

---

## Method 4: Inverse Probability Weighting (IPW / IPTW)

### What it does

IPW weights each unit by the inverse of its probability of receiving the treatment it actually received:

- Treated units: weight = 1 / e(X)
- Control units: weight = 1 / (1 − e(X))

This creates a pseudo-population in which treatment is independent of X, allowing consistent estimation of the ATE (or ATT with stabilized weights).

**Stabilized weights** (preferred for variance reduction):

- Treated: w = P(T=1) / e(X)
- Control: w = P(T=0) / (1 − e(X))

### R Code

```r
library(WeightIt); library(cobalt)

# IPW for ATE
w_ipw <- weightit(treat ~ x1 + x2 + x3 + x4,
                  data     = df,
                  method   = "ps",
                  estimand = "ATE",
                  stabilize = TRUE)
summary(w_ipw)
love.plot(w_ipw, threshold = 0.1)

# Trim extreme weights (> 99th percentile) to reduce variance
w_ipw_trim <- trim(w_ipw, at = 0.99, lower = TRUE)

# ATE via weighted regression
att_ipw <- lm_weightit(y ~ treat, data = df, weightit = w_ipw_trim)
summary(att_ipw, ci = TRUE)

# Marginal structural model (time-varying treatment)
# Construct IPTW weights across time points, then pool using GEE
library(geepack)
gee_fit <- geeglm(y ~ treat + time,
                  id     = df$id,
                  data   = df,
                  family = gaussian,
                  weights = df$iptw_weight,
                  corstr = "independence")
summary(gee_fit)
```

### Stata Code

```stata
* IPW for ATT
teffects ipw (y) (treat x1 x2 x3 x4), ate
teffects ipw (y) (treat x1 x2 x3 x4), atet  // ATT

* Manual stabilized IPW
logit treat x1 x2 x3 x4
predict ps_hat, pr
gen sw_treat = (treat == 1) * mean(treat)/ps_hat + ///
               (treat == 0) * (1-mean(treat))/(1-ps_hat)
regress y treat [pweight=sw_treat], robust
```

---

## Method 5: Doubly Robust Estimation (AIPW)

### What it does

The Augmented Inverse Probability Weighted (AIPW) estimator combines a propensity score model with an outcome regression model. It is **doubly robust**: consistent if *either* the propensity model *or* the outcome model is correctly specified (but not necessarily both).

AIPW estimator for ATE:

```
τ_AIPW = E[ T·Y/e(X) − (T−e(X))·m₁(X)/e(X) ] − E[ (1−T)·Y/(1−e(X)) + (T−e(X))·m₀(X)/(1−e(X)) ]
```

where m₁(X) and m₀(X) are outcome regression models for treated and control.

### R Code

```r
library(WeightIt); library(marginaleffects); library(SuperLearner)

# Doubly robust via WeightIt + outcome model
w_dr <- weightit(treat ~ x1 + x2 + x3 + x4,
                 data     = df,
                 method   = "ps",
                 estimand = "ATE")
att_dr <- lm_weightit(y ~ treat + x1 + x2 + x3 + x4,
                      data     = df,
                      weightit = w_dr)
summary(att_dr, ci = TRUE)

# AIPW with nonparametric nuisance models (via DoubleML)
library(DoubleML)
n <- nrow(df)
X <- as.matrix(df[, c("x1","x2","x3","x4")])
y_vec <- df$y
t_vec <- df$treat

# SuperLearner-based AIPW
dml_dat <- DoubleMLData$new(
  data = df, y_col = "y", d_cols = "treat",
  x_cols = c("x1","x2","x3","x4")
)
learner_reg <- lrn("regr.ranger", num.trees = 500)
learner_cls <- lrn("classif.ranger", num.trees = 500)
dml_irm <- DoubleMLIRM$new(
  dml_dat,
  ml_g = learner_reg,
  ml_m = learner_cls,
  n_folds = 5
)
dml_irm$fit()
dml_irm$summary()
```

### Stata Code

```stata
* Doubly robust IPWRA (inverse probability weighted regression adjustment)
teffects ipwra (y x1 x2 x3 x4) (treat x1 x2 x3 x4), ate
teffects ipwra (y x1 x2 x3 x4) (treat x1 x2 x3 x4), atet
```

---

## Balance Assessment

### Standardized Mean Differences (SMD)

**Formula**: SMD = (mean_treated − mean_control) / SD_pooled_pre-matching

- **Target**: SMD < 0.1 (ideally < 0.05) for all covariates after matching/weighting
- Rule of thumb: SMD < 0.1 indicates negligible imbalance (Austin 2011)

### Love Plot

A love plot displays SMDs for each covariate before and after matching. The `cobalt` package produces ggplot-compatible love plots:

```r
library(cobalt)
love.plot(m_out,  # or w_eb, w_ipw, etc.
          threshold = 0.1,
          abs       = TRUE,
          binary    = "std",
          title     = "Covariate Balance",
          colors    = c("red","blue"),
          shapes    = c("circle","triangle")) +
  theme_minimal()
```

### Overlap / Common Support

```r
# Histogram overlap
plot(m_out, type = "density", which.xs = ~x1 + x2,
     main = "Propensity Score Overlap")

# Or manually with ggplot2
ggplot(df, aes(x = ps, fill = factor(treat))) +
  geom_histogram(position = "identity", alpha = 0.5, bins = 40) +
  labs(title = "Propensity Score Distribution",
       fill = "Treatment") +
  theme_minimal()
```

### Effective Sample Size (ESS)

ESS quantifies the loss of information from weighting:

ESS = (Σ w_i)² / Σ w_i²

```r
# WeightIt reports ESS automatically
summary(w_eb)$effective.sample.size
```

ESS much smaller than N_control suggests extreme weights; consider trimming or switching to matching.

---

## Sensitivity Analysis for Matching

### Rosenbaum Bounds (rbounds package)

Tests sensitivity to hidden biases after matching. Reports Γ: the odds ratio of unmeasured confounding required to explain away the result.

```r
library(rbounds)
# After 1:1 matching
matched <- match.data(m_out)
treated_y <- matched$y[matched$treat == 1]
control_y <- matched$y[matched$treat == 0]
psens(treated_y, control_y, Gamma = 3, GammaInc = 0.25)
# Interpretations:
# Gamma = 1: no hidden bias; standard p-value
# Gamma = 2: result robust to confounder that doubles odds of treatment
# Gamma* (p > 0.05): minimum hidden bias to reverse significance
```

### Interpretation guide for Γ*

| Γ* | Robustness level |
|----|-----------------|
| Γ* < 1.25 | Very sensitive to hidden bias |
| Γ* = 1.25–1.5 | Modest robustness |
| Γ* = 1.5–2.0 | Moderate robustness |
| Γ* > 2.0 | Strong robustness |

---

## Choosing Among Methods

| Scenario | Recommended method |
|----------|--------------------|
| Need matched sample for subgroup analysis | PSM or CEM |
| Categorical/ordinal confounders dominate | CEM |
| Want exact balance, retain all obs | Entropy balancing |
| Estimand is ATE (not ATT) | IPW or AIPW |
| Rich ML covariate set, large N | AIPW / Double ML |
| Marginal structural model (time-varying T) | IPTW |
| Worried about propensity misspecification | AIPW (doubly robust) |

---

## Reporting Checklist

- [ ] CIA assumption stated; argument for why unobservables are unlikely to remain
- [ ] Propensity model / coarsening / entropy constraints specified
- [ ] Overlap plot shown (common support is adequate)
- [ ] Love plot shows SMD < 0.1 for all covariates after matching/weighting
- [ ] ATT (or ATE) estimate with confidence intervals reported
- [ ] Effective sample size (ESS) reported for weighting estimators
- [ ] Rosenbaum bounds (Γ*) or E-value reported for sensitivity
- [ ] Results robust to alternative matching method (e.g., CEM vs. entropy balancing)

---

## Key References

- Rosenbaum, P.R. & Rubin, D.B. (1983). The central role of the propensity score in observational studies for causal effects. *Biometrika*, 70(1), 41–55.
- Iacus, S.M., King, G., & Porro, G. (2012). Causal inference without balance checking: Coarsened exact matching. *Political Analysis*, 20(1), 1–24.
- Hainmueller, J. (2012). Entropy balancing for causal effects. *Political Analysis*, 20(1), 25–46.
- Robins, J.M., Hernán, M.A., & Brumback, B. (2000). Marginal structural models and causal inference in epidemiology. *Epidemiology*, 11(5), 550–560.
- Chernozhukov, V. et al. (2018). Double/debiased machine learning for treatment and structural parameters. *Econometrics Journal*, 21(1), C1–C68.
- Rosenbaum, P.R. (2002). *Observational Studies* (2nd ed.). Springer.
- Austin, P.C. (2011). An introduction to propensity score methods for reducing the effects of confounding in observational studies. *Multivariate Behavioral Research*, 46(3), 399–424.
