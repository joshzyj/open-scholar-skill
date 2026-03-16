# Quantitative Methods Reference for Social Sciences

## Model Selection Guide

### Regression Models by Outcome Type

| Outcome | Distribution | Model | Software command |
|---------|-------------|-------|-----------------|
| Continuous, normal | Gaussian | OLS | `lm()` R; `regress` Stata |
| Binary (0/1) | Bernoulli | Logistic | `glm(family=binomial)` R; `logit` Stata |
| Ordered categories | Ordinal | Ordered logit | `polr()` R; `ologit` Stata |
| Nominal categories | Multinomial | Multinomial logit | `multinom()` R; `mlogit` Stata |
| Count data | Poisson | Poisson / NB | `glm(family=poisson)` R; `poisson` / `nbreg` Stata |
| Time-to-event | Survival | Cox PH | `coxph()` R; `stcox` Stata |
| Discrete-time events | Bernoulli | Logistic / cloglog | `glm()` R; `logit` Stata |
| Panel, continuous | Gaussian | Fixed / random effects | `felm()` lfe R; `xtreg, fe` Stata |
| Panel, binary | Bernoulli | Conditional logit | `clogit()` R; `clogit` Stata |
| Multilevel | Mixed | HLM / LME | `lmer()` R; `mixed` Stata |

---

## Causal Identification Strategies

### Ordinary Least Squares (OLS) — Observational
**Assumption**: Selection on observables (no unmeasured confounding)
**When to use**: When you have a comprehensive set of controls and can argue selection is conditional on observables
**Threats**: Omitted variable bias, reverse causation, measurement error

**Strengthening OLS**:
- Include lagged dependent variable (pre-treatment outcome)
- Propensity score weighting to balance treatment/control
- Use Oster (2019) delta to bound omitted variable bias
- Sensitivity analysis: how large would omitted variable need to be to explain away results?

---

### Difference-in-Differences (DiD)
**Design**: Compares treatment vs. control group before and after treatment
**Assumption**: Parallel trends — in absence of treatment, treatment and control would have changed at same rate
**Equation**: Y_it = α + β(Treated_i × Post_t) + γ_i + δ_t + ε_it

**Standard DiD requirements**:
- At least one pre-period and one post-period
- Treatment is exogenous (not selected on outcome trends)
- No spillovers from treatment to control group

**Tests**:
- Pre-trend test: parallel trends in pre-treatment periods (F-test on pre-treatment interactions)
- Placebo DiD: falsification with fake treatment timing
- Event study plot: β_t for each time period, should be near 0 before treatment

**Recent advances** (2020+):
- Callaway and Sant'Anna (2021): Staggered DiD with heterogeneous treatment timing
- Sun and Abraham (2021): Decompose average treatment effects in staggered setting
- Avoid Goodman-Bacon (2021) issues with "forbidden comparisons"

**Staggered DiD R code (Callaway-Sant'Anna):**
```r
library(did)
# Group-time ATT(g, t) estimator
att_gt <- att_gt(yname = "outcome", tname = "year", idname = "unit_id",
                 gname = "first_treated",   # year unit first treated (0 if never)
                 data  = df,
                 control_group = "nevertreated",
                 est_method = "dr")          # doubly robust

# Aggregate to simple ATT
aggte(att_gt, type = "simple")
aggte(att_gt, type = "dynamic")  # event-study style

# Event study plot
ggdid(aggte(att_gt, type = "dynamic"))
```

**Stata**: `diff`, `xtdidregress`, `drdid`, `csdid`
**R**: `did`, `staggered`, `fixest::feols(... | sunab())` packages

---

### Instrumental Variables (IV)
**Design**: Use an exogenous instrument Z that affects X but affects Y only through X
**Requirements**:
1. Relevance: Z is strongly correlated with X (F-statistic > 10 in first stage)
2. Exclusion restriction: Z affects Y ONLY through X (not directly)
3. Independence: Z is as-good-as-random

**Classic instruments in sociology/demography**:
- Distance to nearest college (Card 1995) → education
- Sex composition of first two children (Angrist and Evans 1998) → fertility
- Draft lottery (Angrist 1990) → military service
- Monsoon rainfall → agricultural income → health/schooling
- Policy changes as natural experiments

**Reporting**: Always report first stage (F-statistic), reduced form, IV estimate together
**Weak instruments**: F < 10 in first stage; use Anderson-Rubin confidence sets

**Stata**: `ivregress 2sls`, `ivreg2`
**R**: `AER::ivreg()`, `estimatr::iv_robust()`

---

### Regression Discontinuity (RD)
**Design**: Units just above/below a threshold are compared (sharp) or weighting used (fuzzy)
**Assumption**: Assignment near threshold is as-good-as-random; potential outcomes are continuous at threshold

**Types**:
- Sharp RD: All units above threshold treated
- Fuzzy RD: Threshold affects probability of treatment (instrument)

**Bandwidth selection**: Use optimal bandwidth (Calonico et al. 2014 `rdrobust`)
**Validity tests**: Density test (McCrary 2008); covariate balance near cutoff; sensitivity to bandwidth

**Example cutoffs in education/demographics**:
- GPA thresholds for scholarships
- Age eligibility cutoffs (kindergarten entry, retirement)
- Test score cutoffs for program entry
- Income cutoffs for benefits eligibility

**Stata/R**: `rdrobust` package

---

### Fixed Effects (FE) Panel Models
**Design**: Within-person or within-unit variation eliminates all time-invariant unobserved confounders
**Assumption**: The confounding variable is time-invariant (e.g., personality, race, neighborhood growing up)

**Two-way FE**: Individual FE + time FE
Y_it = α_i + δ_t + βX_it + ε_it

**Limitations**:
- Cannot estimate effects of time-invariant variables (race, sex, country of birth)
- Requires variation in X over time within units
- Noisy with short panels

**Hybrid / within-between models**: Mundlak (1978) or Allison (2009) for interpreting both within and between effects

**Stata**: `xtreg, fe`, `reghdfe` (multi-way FE)
**R**: `lfe::felm()`, `fixest::feols()`

---

### Matching Methods
**Propensity Score Matching (PSM)**:
- Estimate propensity score p(X) = P(T=1|X) via logistic regression
- Match treated to control units with similar scores
- Issue: Only balances on observed covariates

**Coarsened Exact Matching (CEM)** (Iacus, King, Porro):
- Coarsen variables into bins; match exactly within bins
- Generally preferred over PSM for fewer model-dependence issues

**Inverse Probability Weighting (IPW)**:
- Weight observations by 1/p(X) for treated; 1/(1-p(X)) for control
- Creates pseudo-population where treatment is independent of covariates

**R**: `MatchIt`, `WeightIt`, `cobalt` packages
**Stata**: `psmatch2`, `cem`

---

## Demography-Specific Methods

### Decomposition Methods

**Kitagawa-Oaxaca-Blinder Decomposition**:
- Decomposes group difference in mean Y into:
  1. Explained: difference in X characteristics
  2. Unexplained: difference in returns to X (coefficients)
- Classic for racial/gender wage gap

**Stata**: `oaxaca`
**R**: `oaxaca` package

**Counterfactual Decomposition (DiNardo-Fortin-Lemieux)**:
- Decomposes distributional differences (not just means)
- Reweights distribution to counterfactual

### Demographic Rates and Life Tables
- Age-standardization: Compare rates controlling for age structure
- Life table construction: lx, qx, Lx, Tx, ex
- Decomposition of life expectancy differences by cause

### Population Projections
- Cohort-component method
- Lee-Carter model for mortality forecasting

---

## Reporting Standards

### What to report in tables:

**Regression table minimum**:
- Coefficient (unstandardized B)
- Standard error (in parentheses) OR 95% CI
- Stars for significance (*, **, ***)
- N per model
- Model fit: R² or pseudo-R², log-likelihood, AIC/BIC

**What NOT to do**:
- Do not report standardized beta without also reporting unstandardized
- For logistic regression: prefer AME over odds ratios (ASR strong preference)
- Do not hide null findings — report them

### Average Marginal Effects (AME) for logistic regression:
```r
# R: marginaleffects package (modern standard — replaces margins)
library(marginaleffects)
m <- glm(y ~ x + z, data = df, family = binomial)

# AME: averaged over all observations
avg_slopes(m)

# At representative values
slopes(m, newdata = datagrid(x = c(0, 1), female = c(0, 1)))

# Interaction / moderation
plot_slopes(m, variables = "x", condition = "z")

# Predicted probabilities by group
plot_predictions(m, condition = list("x", "group"))

# Stata
logit y x z
margins, dydx(*)
```

**Note:** `marginaleffects` (2022–present) supersedes the older `margins` package. It handles GLMs, FE models via `fixest`, multilevel models via `lme4`, and survival models via `survival`, all with a uniform API.

### Clustered standard errors:
Use when observations are clustered (students in schools, workers in firms):
```r
# R
library(estimatr)
lm_robust(y ~ x, data = df, clusters = school_id)

# Stata
regress y x, vce(cluster school_id)
```

---

## Software Reference

### R packages for social science
| Task | Package |
|------|---------|
| OLS/GLM | base `lm()`, `glm()` |
| Robust SEs | `estimatr::lm_robust()` |
| Panel FE | `fixest::feols()` |
| Survival | `survival::coxph()` |
| Mediation | `mediation::mediate()` |
| Matching | `MatchIt`, `WeightIt` |
| Marginal effects | `marginaleffects` |
| IV | `AER::ivreg()` |
| RD | `rdrobust` |
| Multilevel | `lme4::lmer()` |
| Decomposition | `oaxaca` |
| Tables | `modelsummary`, `stargazer` |
| Visualization | `ggplot2`, `ggeffects` |

### Stata commands reference
| Task | Command |
|------|---------|
| OLS | `regress y x, robust` |
| Logit AME | `logit y x` + `margins, dydx(*)` |
| Panel FE | `xtreg y x, fe robust` |
| Multi-way FE | `reghdfe y x, absorb(i j)` |
| Cox model | `stset time, failure(event)` + `stcox x` |
| IV 2SLS | `ivregress 2sls y (x = z)` |
| RD | `rdrobust y x, c(cutoff)` |
| DiD | `xtdidregress (y x) (treat), group(id) time(t)` |
| Decomposition | `oaxaca y x, by(group)` |

---

## Power Analysis and Sample Size

### Why Power Matters for Top Journals
Nature Human Behaviour and Science Advances require justification of sample size. Underpowered studies produce inflated effect sizes and irreproducible findings. A study with 80% power at α = .05 has a 20% chance of missing a true effect.

### Key Formula
Power = f(effect size, N, α, design)
- Larger N → more power
- Larger effect size → easier to detect
- Two-tailed α = .05 → less power than one-tailed, but required for most social science

### Power Analysis in R

```r
library(pwr)

# OLS / correlation
pwr.r.test(r = 0.2, sig.level = 0.05, power = 0.80)
# Minimum N to detect r = 0.2 with 80% power

# Two-group t-test (experimental / DiD)
pwr.t.test(d = 0.3, sig.level = 0.05, power = 0.80, type = "two.sample")
# d = Cohen's d; 0.2 small, 0.5 medium, 0.8 large

# Logistic regression (binary outcome)
library(WebPower)
wp.logistic(n = NULL, p0 = 0.3, p1 = 0.4,
            alpha = 0.05, power = 0.80, family = "normal")
# p0 = baseline probability; p1 = expected probability in treatment

# Multilevel / HLM
library(simr)
# Simulate power via simulation for complex designs

# Chi-square / cross-tabulation
pwr.chisq.test(w = 0.2, df = 2, sig.level = 0.05, power = 0.80)
```

### Effect Size Benchmarks for Social Science

| Domain | Small | Medium | Large | Typical in field |
|--------|-------|--------|-------|-----------------|
| Education interventions | d = 0.2 | d = 0.4 | d = 0.6 | d = 0.2–0.4 |
| Survey attitude change | d = 0.1 | d = 0.3 | d = 0.5 | d = 0.1–0.3 |
| Labor market returns to education | β ≈ 0.08–0.10 per year | | | IQ adj. β ≈ 0.06–0.08 |
| Network interventions | d = 0.15 | d = 0.3 | d = 0.5 | highly variable |

**Rule of thumb for sociology observational studies**: Plan for N such that you can detect β = 0.05 SD (standardized) — this is a "small" effect common in stratification research. For logistic regression, plan for AME = 2–3 percentage points.

### Reporting Power Analysis

```
"We conducted a power analysis using the `pwr` package in R (Champely 2020).
Assuming a small effect size (d = 0.25, based on prior work by [Author Year]),
two-tailed α = .05, and 80% power, our minimum required sample size is N = [X].
Our final analytic sample (N = [Y]) is [adequate / exceeds this requirement]."
```

For underpowered secondary data studies:
```
"Because our data are restricted to [specific population], our analytic sample
(N = [X]) may be underpowered to detect effects smaller than d = [Y] (80% power,
α = .05). We focus interpretation on effect sizes and confidence intervals rather
than binary significance testing."
```

---

## Experimental Design

### Survey Experiments (Vignette / Factorial)

Survey experiments randomly assign respondents to different versions of a vignette or question:

```r
# Qualtrics: use Display Logic with randomizer block
# R analysis: simple comparison of means across conditions

# Example: 2x2 factorial (race × gender of job applicant)
# Conditions: White Male, White Female, Black Male, Black Female
m <- lm(hiring_rating ~ race + gender + race*gender,
        data = survey_exp)
summary(m)
library(emmeans)
emmeans(m, ~race*gender)  # All four cell means
contrast(emmeans(m, ~race*gender), "pairwise")
```

**Reporting vignette experiments**:
- Show all condition versions in appendix
- Report N per condition; test for differential attrition
- Use ANOVA or regression; report η² or ω² as effect size

### List Experiments (Sensitive Items)

For sensitive behaviors (illegal activity, prejudice), list experiments allow truthful responding without direct disclosure:

```
Control group: "How many of the following have you done in the past year?"
  [ ] Voted in an election
  [ ] Donated to charity
  [ ] Volunteered for a cause

Treatment group: Same list + sensitive item:
  [ ] Voted in an election
  [ ] Donated to charity
  [ ] Volunteered for a cause
  [ ] [Sensitive behavior]

Estimate = mean(treatment count) − mean(control count)
```

```r
library(list)
# Fit list experiment model
fit <- ictreg(count ~ age + female + education,
              treat = "treatment",
              J = 3,  # number of non-sensitive items
              data = df,
              method = "lm")  # or "ml" for maximum likelihood
summary(fit)
```

### Conjoint Analysis (Preference Trade-offs)

Respondents choose between profiles defined by multiple attributes; estimates preferences through choice:

```r
library(cregg)
# Estimate average marginal component effects (AMCE)
# Each row is one profile evaluation
amce_results <- cj(df, formula = chosen ~ age + education + gender + race,
                   id = ~ respondent_id)
plot(amce_results, main = "AMCE: What factors affect hiring?")
```

---

## Sensitivity Analysis for Unmeasured Confounding

### Oster (2019) Delta — OVB Bounds

How large must unmeasured confounders be (relative to observed controls) to explain away the estimated effect?

```r
library(sensemakr)
sens <- sensemakr(
  model                = m3,             # fully-controlled model
  treatment            = "treatment",    # main predictor name
  benchmark_covariates = "educ_yrs",     # comparable observed covariate
  kd                   = 1:3             # 1×–3× as strong as benchmark
)
ovb_minimal_reporting(sens)
plot(sens)

# Key output: robustness_value — % of residual variance needed to explain away effect
# delta* — bias-adjusted effect at each kd level
# Report: "Results are robust to confounders [kd]× as strong as education (δ* = [X])."
```

### E-Value (VanderWeele and Ding 2017) — Risk Ratio Scale

Minimum strength of association (on risk ratio scale) an unmeasured confounder would need with both treatment and outcome to fully explain away the effect:

```r
library(EValue)
# For OLS (continuous outcome, standardized)
evalues.OLS(est = 0.15, se = 0.04, delta = 1, true = 0)

# For logistic (odds ratio)
evalues.OR(est.eff = 1.45, lo = 1.10, hi = 1.91)

# For risk ratio (RR)
evalues.RR(est.eff = 1.40, lo = 1.10, hi = 1.80)

# Reporting template:
# "The E-value for our main estimate (β = 0.15) is [X], meaning an unmeasured confounder
# would need to be associated with both [X] and [Y] by a risk ratio of [X] — above and
# beyond all measured covariates — to fully explain away the finding."
```

---

## Python Statistical Equivalents

For Python users, the following packages replicate R's core social science workflow:

```python
import pandas as pd
import statsmodels.formula.api as smf
from linearmodels import PanelOLS
from marginaleffects import avg_slopes

# OLS
m_ols = smf.ols("outcome ~ treatment + age + female + educ", data=df).fit(cov_type="HC3")
print(m_ols.summary())

# Logistic regression + AME
m_logit = smf.logit("outcome ~ treatment + age + female", data=df).fit()
ames = avg_slopes(m_logit)  # marginaleffects Python port

# Panel FE
df_panel = df.set_index(["unit_id", "year"])
m_fe = PanelOLS.from_formula(
    "outcome ~ treatment + age + EntityEffects + TimeEffects",
    data=df_panel
).fit(cov_type="clustered", cluster_entity=True)
print(m_fe.summary)

# Regression table export
from statsmodels.iolib.summary2 import summary_col
table = summary_col([m_ols, m_logit], stars=True)
table.as_latex()

# Survival analysis
from lifelines import CoxPHFitter
cph = CoxPHFitter()
cph.fit(df, duration_col="time", event_col="event",
        formula="treatment + age + female + educ")
cph.print_summary()
cph.check_assumptions(df)
```
