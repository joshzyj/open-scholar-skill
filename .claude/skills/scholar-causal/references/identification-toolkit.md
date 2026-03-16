# Identification Strategy Toolkit

## Strategy Selection Guide

| Variation available | Confounding structure | Best strategy |
|--------------------|----------------------|---------------|
| Random assignment | Any | RCT (gold standard) |
| Exogenous policy change, 2×2 | Time-invariant + some time-varying | DiD |
| Staggered policy adoption | Time-invariant + time-varying + heterogeneous effects | Callaway-Sant'Anna; Sun-Abraham |
| Parallel trends threatened by group-level time trends | Time-varying group shocks | Triple DiD (DDD) |
| Cutoff-based assignment (sharp) | Near-cutoff as-if-random | Sharp RD |
| Cutoff-based assignment (fuzzy) | Near-cutoff + partial compliance | Fuzzy RD (LATE) |
| Exogenous instrument | Unobserved confounders | IV / 2SLS |
| Repeated measures, individual | Time-invariant confounders | Panel FE (TWFE) |
| Repeated measures + policy change | Time-invariant + time trend | DiD with FE |
| Single treated unit, long pre-period | Absorb via synthetic match | Synthetic control |
| Unobserved U → X and U → Y; known mediator M | Frontdoor conditions met | Frontdoor criterion |
| Only observational data | Selection on observables | OLS + Oster sensitivity |
| Many confounders, large N | Selection on observables | Double ML (DML) |
| Covariate imbalance, observational | Selection on observables | Matching / entropy balancing |
| Mechanism / mediation question | Sequential ignorability | Causal mediation (ACME) |
| Small N; exact inference needed | Any | Fisher randomization inference |

---

## Method Vintage: Historical Layers of the Causal Toolkit

| Era | Methods introduced | Key works |
|-----|-------------------|-----------|
| Classic (1970s–1980s) | OLS regression with controls; 2SLS IV | Angrist 1990; Card 1995 |
| Natural experiment era (1990s–2000s) | DiD; Sharp RD; Panel FE | Angrist & Evans 1998; Hahn et al. 2001 |
| Matching era (2000s) | PSM; CEM | Rosenbaum & Rubin 1983; Iacus et al. 2012 |
| Modern causal era (2010s) | Synthetic control; causal mediation; entropy balancing | Abadie et al. 2010; Imai et al. 2010; Hainmueller 2012 |
| Robust/heterogeneous era (2020s) | Staggered DiD (CS-2021; SA-2021); Augmented SC; Double ML; SynthDiD | Callaway & Sant'Anna 2021; Chernozhukov et al. 2018; Arkhangelsky et al. 2021 |

---

## Writing Identification Arguments by Strategy

### OLS — Observational

**Key claim**: Selection on observables (conditional independence assumption)

**Template paragraph**:
> "We estimate the association between [X] and [Y] using OLS regression. Our identification rests on the assumption that, conditional on [list controls], treatment assignment is as good as random. The main threats to this assumption are [unobserved confounder 1] and [unobserved confounder 2]. We address [confounder 1] by including [proxy control]; we cannot directly address [confounder 2], but we note that [argument for why it is unlikely to explain the result: prior studies, direction of bias, sensitivity analysis]. Following Oster (2019), we estimate that the omitted variable would need to be [delta] times more strongly associated with [Y] than all observed controls combined to explain our result, which we consider implausible given [reason]."

**Oster delta in R**:
```r
library(sensemakr)
model <- lm(y ~ x + controls, data = df)
sens <- sensemakr(model, treatment = "x",
                  benchmark_covariates = "control_1",
                  kd = 1:3)
summary(sens)
plot(sens)
```

---

### Difference-in-Differences

**Key claim**: Parallel trends + no anticipation + SUTVA

**Template paragraph**:
> "We use a difference-in-differences (DiD) design, comparing outcomes for [treated units] to [control units] before and after [policy/event] in [year]. Identification rests on the parallel trends assumption: absent the treatment, [treated] and [control] units would have followed the same outcome trajectory. We provide evidence for this assumption through an event-study design, which shows that [treated] and [control] units had statistically indistinguishable outcome trends in the [N] years prior to [treatment], [F-test: F(N-1, df) = X, p = Y; Figure A1]. We further test for anticipation effects in the year prior to treatment. [Report result.] Standard errors are clustered at the [state/firm/school] level to account for within-unit serial correlation."

**Pre-trend test in R**:
```r
library(fixest)
# Event study: interact treatment with year dummies
es <- feols(y ~ i(year, treated, ref = -1) | unit + year,
            data = df, cluster = ~unit)
iplot(es, main = "Event Study: Pre-trends Test")
# Reference year = -1 (one year before treatment)
# Coefficients for years < 0 should be near zero
```

---

### Staggered DiD (Callaway & Sant'Anna 2021)

**Key claim**: Parallel trends holds for each cohort-period comparison (using only never-treated or not-yet-treated as controls); no forbidden comparisons

**Template paragraph**:
> "Because treatment adoption is staggered — units adopted [policy] at different times between [year₁] and [year₂] — we use the Callaway and Sant'Anna (2021) estimator rather than standard two-way fixed effects (TWFE). Standard TWFE can produce biased estimates when treatment effects are heterogeneous across cohorts, because early-treated units serve as implicit controls for later-treated units ('forbidden comparisons'). We confirm this concern using the Goodman-Bacon (2021) decomposition, which shows that [X]% of the TWFE weight is placed on forbidden comparisons (Figure A[X]). The CS-2021 estimator constructs group-time ATTs using only never-treated (or not-yet-treated) units as controls; we aggregate these to an overall ATT and a dynamic event-study. Pre-treatment coefficients are jointly indistinguishable from zero (χ²([k]) = [X], p = [Y]), supporting the parallel trends assumption."

**CS-2021 in R**:
```r
library(did); library(fixest); library(bacondecomp)

# Bacon decomposition
bd <- bacon(y ~ treat_post, data = df, id_var = "unit", time_var = "year")
ggplot(bd, aes(x = weight, y = estimate, color = type)) + geom_point() +
  labs(title = "Bacon Decomposition")

# CS-2021
cs <- att_gt(yname = "y", tname = "year", idname = "id",
             gname = "first_treat",
             data = df, control_group = "nevertreated",
             est_method = "reg")
aggte(cs, type = "dynamic")  # Event study ATTs
aggte(cs, type = "simple")   # Overall ATT
ggdid(aggte(cs, type = "dynamic"))

# Sun & Abraham (2021) via fixest
sa <- feols(y ~ sunab(cohort, year) | unit + year,
            data = df, cluster = ~unit)
iplot(sa, main = "Sun-Abraham Event Study")
```

---

### Instrumental Variables

**Key claim**: Relevance + exclusion restriction + independence

**Template paragraph**:
> "We address the endogeneity of [X] using [Z] as an instrumental variable. [Z] satisfies the relevance condition: a one-unit increase in [Z] is associated with a [b]-unit increase in [X] (F-statistic = [X] in the first-stage regression, exceeding the conventional threshold of 10; Table A[X]). The exclusion restriction requires that [Z] affects [Y] only through its effect on [X]. We argue this is plausible because [detailed argument: Z is determined by X / Z predates Y by many years / Z is geographically/administratively determined and unrelated to individual outcomes]. We cannot directly test the exclusion restriction, but note that [supporting evidence or falsification test]. Independence requires [Z] to be uncorrelated with unobserved determinants of [Y]. [Provide evidence: randomization, geographic exogeneity, placebo outcomes.] We present reduced form estimates alongside IV estimates for transparency."

**2SLS in R**:
```r
library(AER)
# First stage
fs <- lm(x ~ z + controls, data = df)
summary(fs)  # Check F-stat; should be > 10

# IV estimate
iv <- ivreg(y ~ x + controls | z + controls, data = df)
summary(iv, diagnostics = TRUE)
# Diagnostics: Weak instruments test (Cragg-Donald); Hausman test
```

---

### Regression Discontinuity

**Key claim**: Continuity of potential outcomes at cutoff; no manipulation; local randomization

**Template paragraph**:
> "We use a sharp regression discontinuity (RD) design exploiting the [cutoff value] threshold of [running variable]. Units with [running variable] just above (below) the threshold are assigned to [treatment]; those just below (above) are not. Identification rests on the assumption that units cannot precisely manipulate [running variable] around the threshold, and that all potential outcomes are continuous at the threshold. We test the no-manipulation assumption using the McCrary (2008) density test, which finds no evidence of bunching at the threshold (p = [X]; Figure A[X]). We also test whether predetermined covariates are continuous at the threshold; we find no significant discontinuities in [list covariates] (Table A[X]), consistent with local randomization. We select bandwidth using the optimal data-driven procedure of Calonico, Cattaneo, and Titiunik (2014), which yields a bandwidth of [h]; we show robustness to alternative bandwidths in Table A[X]."

**RD in R**:
```r
library(rdrobust)
# Optimal bandwidth + local polynomial RD estimate
rdd <- rdrobust(y = df$outcome, x = df$running_var, c = cutoff)
summary(rdd)

# Density test (McCrary)
library(rddensity)
dens <- rddensity(X = df$running_var, c = cutoff)
summary(dens)
rdplotdensity(dens, df$running_var)

# Covariate balance at cutoff
for (cov in c("age","female","educ")) {
  rdd_cov <- rdrobust(y = df[[cov]], x = df$running_var, c = cutoff)
  cat(cov, ": coef =", rdd_cov$coef[1], "p =", rdd_cov$pv[1], "\n")
}
```

---

### Fixed Effects (Panel)

**Key claim**: Time-invariant confounders absorbed; time-varying confounders controlled or minor

**Template paragraph**:
> "We estimate person-level fixed effects (FE) models that identify the effect of [X] from within-person variation over time. This approach absorbs all time-invariant confounders — including stable characteristics such as cognitive ability, personality, and family background — that might simultaneously predict changes in [X] and [Y]. We include year fixed effects to absorb common time trends. The remaining threat to identification is time-varying confounders that co-move with changes in [X]; we address this by including [time-varying controls]. We verify that [X] varies sufficiently within persons to identify the effect (within-person SD = [X]; [Y]% of persons exhibit any change in [X] across waves). Standard errors are clustered at the person level."

**FE in R**:
```r
library(fixest)
fe_model <- feols(y ~ x + time_varying_control | id + year,
                  data = pdata, cluster = ~id)
summary(fe_model)

# Check within variation
library(dplyr)
within_var <- pdata %>%
  group_by(id) %>%
  summarise(within_sd = sd(x, na.rm = TRUE))
mean(within_var$within_sd > 0, na.rm = TRUE)  # % with any change
```

---

### Synthetic Control (Abadie et al. 2010)

**Key claim**: Pre-treatment fit of synthetic control is close; post-treatment divergence attributed to treatment; confirmed by placebo permutation inference

**Template paragraph**:
> "We employ a synthetic control design (Abadie, Diamond, and Hainmueller 2010) because [treated unit] is the only [state/country] that [adopted policy X] during our study period. The synthetic control is a weighted average of [N] donor units from [donor pool description] that minimizes the pre-treatment RMSPE. The pre-treatment fit is [X] (RMSPE = [Y], [Z]% of the outcome mean). [Figure X] shows the treated and synthetic control trajectories; they track closely from [start year] to [treatment year] and diverge subsequently. The estimated cumulative treatment effect is [X] [units] by [end year]. We conduct placebo permutation inference by iterating the procedure over all donor units; the treated unit's post/pre RMSPE ratio ranks in the [Xth] percentile of the placebo distribution, yielding an estimated p-value of [Y] (Figure A[X])."

**Synthetic control in R**:
```r
library(tidysynth); library(augsynth); library(synthdid)

# tidysynth
synthetic <- df %>%
  synthetic_control(
    outcome = y, unit = state, time = year,
    i_unit = "treated_state", i_time = 2000,
    generate_placebos = TRUE
  ) %>%
  generate_predictor(time_window = 1990:1999, avg_y = mean(y)) %>%
  generate_weights(optimization_window = 1990:1999) %>%
  generate_control()

plot_trends(synthetic)
plot_placebos(synthetic)
plot_mspe_ratio(synthetic)

# Augmented SC (bias-corrected)
asyn <- augsynth(y ~ treat | x1 + x2,
                 unit = state, time = year, data = df,
                 progfunc = "Ridge", scm = TRUE)
summary(asyn); plot(asyn)

# Synthetic DiD
library(synthdid)
setup <- panel.matrices(df, unit="state", time="year",
                        outcome="y", treatment="treat")
tau <- synthdid_estimate(setup$Y, setup$N0, setup$T0)
se  <- sqrt(vcov(tau, method="placebo"))
cat("SynthDiD:", tau, "±", se, "\n")
```

---

### Double ML (Debiased Machine Learning — Chernozhukov et al. 2018)

**Key claim**: CIA holds; nuisance parameters (propensity score, outcome regression) estimated via flexible ML to remove regularization bias; cross-fitting removes overfitting bias

**When to use**: Rich high-dimensional confounder set (many Xs); selection on observables but OLS will be biased because correct functional form is unknown; large N.

**Template paragraph**:
> "Because [X] may be confounded by many [demographic/contextual] characteristics, we use the Double/Debiased ML (DML) estimator (Chernozhukov et al. 2018). DML estimates [β] in the partially linear model Y = βT + g(X) + ε while allowing the nuisance functions (outcome regression g(X) and propensity score m(X)) to be estimated flexibly using [Random Forests / Lasso / XGBoost]. Cross-fitting (K = [5] folds) prevents overfitting bias from contaminating the [β] estimate. The DML estimate [β̂ = X, SE = Y, 95% CI: (A, B)] is comparable to/differs from the OLS estimate of [Z], suggesting [interpretation]. We report median estimates and SEs across [50] repeated cross-fits to reduce Monte Carlo variance."

**Double ML in R**:
```r
library(DoubleML); library(mlr3); library(mlr3learners)

# Data setup
dml_data <- DoubleMLData$new(
  data   = df,
  y_col  = "y",
  d_cols = "treat",
  x_cols = c("x1","x2","x3","x4","x5")
)

# Learners (Random Forest for both nuisance functions)
learner_r <- lrn("regr.ranger",  num.trees = 500, min.node.size = 5)
learner_c <- lrn("classif.ranger", num.trees = 500, min.node.size = 5)

# Partially linear regression model (PLR)
dml_plr <- DoubleMLPLR$new(
  dml_data,
  ml_l = learner_r,  # outcome nuisance
  ml_m = learner_c,  # treatment nuisance
  n_folds = 5,
  n_rep   = 50       # repeated cross-fitting
)
dml_plr$fit()
dml_plr$summary()

# Interactive regression model (for heterogeneous effects / ATE)
dml_irm <- DoubleMLIRM$new(
  dml_data,
  ml_g = learner_r,
  ml_m = learner_c,
  n_folds = 5
)
dml_irm$fit()
dml_irm$summary()

# Compare to OLS
ols <- feols(y ~ treat + x1 + x2 + x3 + x4 + x5, data = df)
cat("OLS:", coef(ols)["treat"], "\n")
cat("DML:", dml_plr$coef, "\n")
```

---

### Causal Mediation Analysis (Imai et al. 2010)

**Key claim**: Sequential ignorability; treatment-mediator interaction handled; ACME identified with sensitivity analysis for sequential ignorability violations

**Template paragraph**:
> "We decompose the total effect of [X] on [Y] into the average causal mediation effect (ACME) through [M] and the average direct effect (ADE), following Imai et al. (2010). The mediator model regresses [M] on [X] and pre-treatment covariates [list]. The outcome model regresses [Y] on [X], [M], and the same covariates. ACME estimation uses simulation-based inference with 1,000 bootstrapped draws. The ACME is [estimate] ([95% CI: A, B]), representing [proportion]% of the total effect. Sensitivity analysis indicates the sequential ignorability assumption would require a residual correlation of ρ ≥ [ρ*] between [M] and [Y] to be violated before the ACME becomes indistinguishable from zero (Figure A[X])."

**Mediation in R**:
```r
library(mediation)

med_fit <- lm(mediator ~ treat + x1 + x2, data = df)
out_fit <- lm(outcome  ~ treat + mediator + x1 + x2, data = df)

med_out <- mediate(med_fit, out_fit,
                   treat = "treat", mediator = "mediator",
                   robustSE = TRUE, sims = 1000,
                   boot = TRUE, boot.ci.type = "perc")
summary(med_out)  # ACME, ADE, Total Effect, Prop. Mediated

# Sensitivity analysis (sequential ignorability)
sens <- medsens(med_out, rho.by = 0.05, effect.type = "indirect")
summary(sens)
plot(sens, sens.par = "rho")
```

---

### Triple Differences (DDD)

**Key claim**: Parallel trends holds after differencing out group-level time trends via a third comparison group that is unaffected by treatment

**When to use**: Standard DiD parallel trends is threatened by group-specific time shocks (e.g., treated states were trending differently even before the policy). Adding a within-state or within-group "placebo" group that should be unaffected by treatment absorbs these group-time shocks.

**Specification**:

```
Y_ijt = α + β₁τ_t + β₂δ_j + β₃D_i + β₄(δ_j × τ_t) + β₅(τ_t × D_i) + β₆(δ_j × D_i)
        + β₇(δ_j × τ_t × D_i) + controls_ijt + ε_ijt
```

- i = treatment group indicator (1 = affected, 0 = unaffected placebo)
- j = state/region indicator (1 = treated state, 0 = control state)
- t = post-treatment period indicator
- β₇ = DDD estimate: removes state-specific time shocks captured by β₄ and group-specific trends captured by β₅

**Template paragraph**:
> "We implement a triple differences (DDD) design because [treated states] may have been experiencing differential trends in [outcome] unrelated to [policy]. Our design adds [high-wage workers / elderly population / unaffected demographic group] as a within-state placebo group (D_i = 0) who should not be affected by [policy]. The DDD estimate β₇ differences out [state-specific time trends] that would otherwise confound the standard DiD estimate. Pre-period coefficients on the triple interaction are jointly zero (F([k],[df]) = [X], p = [Y]), supporting the validity of our within-state placebo."

**R code**:
```r
library(fixest)
# DDD: treat_group = affected vs. unaffected; treat_state = treated vs. control state; post = period
ddd <- feols(y ~ i(post, treat_group, ref = 0):i(treat_state, ref = 0) |
               unit + year + state^year,
             data = df, cluster = ~state)
summary(ddd)

# Event study version of DDD
ddd_es <- feols(y ~ i(rel_year, treat_group, ref = -1):i(treat_state, ref = 0) |
                  unit + year + state^year,
                data = df, cluster = ~state)
iplot(ddd_es)
```

**Stata code**:
```stata
gen triple = treat_group * treat_state * post
reghdfe y i.treat_group##i.treat_state##i.post, ///
        absorb(unit year state#year) cluster(state)
```

---

### Fisher Randomization Inference (Exact p-values)

**Key claim**: Under the sharp null hypothesis (no treatment effect for any unit), the observed test statistic is no more extreme than would be expected by chance under all possible random assignments

**When to use**:
- Small N (< 50 treated units) where asymptotic approximations are unreliable
- Policy evaluation with few treated clusters/units (e.g., 5 treated states)
- RCTs or natural experiments with clear randomization mechanism
- As a robustness check alongside standard p-values for any design

**Six-step procedure (Fisher 1935; Cunningham 2021)**:
1. State the sharp null: H₀: Yᵢ¹ = Yᵢ⁰ for all i (zero individual treatment effect)
2. Under the sharp null, observed Y = Y⁰; treat Y_obs as the complete schedule of potential outcomes
3. Enumerate all possible treatment assignments (or draw B random permutations)
4. For each permutation, compute the test statistic (difference in means, regression coefficient, or rank statistic)
5. Compare observed statistic to the permutation distribution
6. Exact p-value = fraction of permutations producing a statistic ≥ observed

**Test statistic choices** (Cunningham 2021):
- Simple difference in means: easy but sensitive to outliers
- Rank-based statistics (Wilcoxon): robust to skewed distributions
- Kolmogorov-Smirnov: detects distributional differences beyond location shifts
- Regression coefficient: preserves covariate adjustment

```r
library(ri2)

# Declare randomization scheme (probability sample)
declaration <- declare_ra(N = nrow(df), prob = 0.5)

# Conduct randomization inference
ri_out <- conduct_ri(
  formula           = y ~ treat + x1 + x2,
  assignment        = "treat",
  declaration       = declaration,
  sharp_hypothesis  = 0,
  data              = df,
  sims              = 5000,
  p                 = "two-tailed"
)
summary(ri_out)
plot(ri_out)

# Manual permutation test (for cluster-level randomization)
obs_stat <- coef(feols(y ~ treat | unit + year, data = df, cluster = ~state))["treat"]
perm_stats <- replicate(5000, {
  df_perm <- df
  # Permute at state level (treatment-assignment level)
  state_treat <- df %>% distinct(state, treat)
  state_treat$treat_perm <- sample(state_treat$treat)
  df_perm <- df_perm %>% left_join(state_treat %>% select(state, treat_perm), by = "state")
  coef(feols(y ~ treat_perm | unit + year, data = df_perm, cluster = ~state))["treat_perm"]
})
p_exact <- mean(abs(perm_stats) >= abs(obs_stat))
cat("Exact p-value:", p_exact, "\n")
```

**Write-up template**:
> "Because our design includes only [N_treat] [treated states/units], standard asymptotic inference may be unreliable. We supplement cluster-robust standard errors with Fisher randomization inference. Under the sharp null of no treatment effect, we permute treatment assignment [5,000] times at the [state] level (the unit of treatment assignment), compute the [regression coefficient / difference in means] for each permutation, and compare the observed statistic to the resulting distribution. The exact p-value is [X], confirming that our estimate is unlikely to arise by chance."

---

## Sensitivity Analysis Quick Reference

### Oster (2019) Bounding (for OLS)
Reports delta: the required ratio of selection on unobservables to selection on observables to nullify the result.
- Delta > 1: unobservables would need to be stronger than all observables combined (usually implausible)
- Delta > 2: very strong evidence for robustness

### E-Values (VanderWeele & Ding 2017)
Reports the minimum RR-scale association an unmeasured confounder must have with *both* treatment and outcome to explain away the effect.

```r
library(EValue)
evalues.RR(est = 2.5, lo = 1.8, hi = 3.5)
evalues.OR(est = 1.8, lo = 1.2, hi = 2.6, rare = TRUE)
evalues.MD(est = 0.3, se = 0.1, sd = 1.2)
```

### Rosenbaum Bounds (for matching)
Reports Gamma: the required odds ratio of hidden bias to explain away the result at p = .05.
- Gamma > 2: result robust to hidden confounders that double the odds of treatment

```r
library(rbounds)
psens(matched_y_treated, matched_y_control, Gamma = 2, GammaInc = 0.1)
```

### Callaway & Sant'Anna (2021) for Staggered DiD
When treatment timing varies across units, standard 2×2 DiD can give biased estimates due to "forbidden comparisons." Use:

```r
library(did)
cs <- att_gt(yname = "y", tname = "year", idname = "id",
             gname = "first_treat",  # year of first treatment (0 = never treated)
             data = df,
             control_group = "nevertreated",
             est_method = "reg")
aggte(cs, type = "dynamic")  # Event study
aggte(cs, type = "simple")   # Average ATT
```

### Sequential Ignorability Sensitivity (Causal Mediation)
Reports ρ*: the residual correlation between M and Y errors that would nullify ACME.

```r
library(mediation)
sens <- medsens(med_out, rho.by = 0.05, effect.type = "indirect")
summary(sens)
```
