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

### A8j — GAMLSS (Generalized Additive Models for Location, Scale, and Shape)

**When to use:** Y has complex distributional properties — skewness, heavy tails, heterogeneous variance, or you need to model not just the mean but also variance, skewness, or kurtosis as functions of predictors. Common in income/wealth distributions, health outcomes with floor/ceiling effects, or any outcome where OLS residual assumptions fail badly.

```r
# ── 09j-gamlss.R ──
library(gamlss)
library(gamlss.dist)

# Fit GAMLSS: model both mu (location) and sigma (scale) as functions of X
m_gamlss <- gamlss(
  Y ~ X + C1 + C2,           # mu formula (location/mean)
  sigma.formula = ~ X + C1,  # sigma formula (scale/variance)
  # nu.formula = ~ 1,        # skewness (if using 3+ parameter distribution)
  family = BCTo(),            # Box-Cox t (handles skew + heavy tails)
  data = df,
  control = gamlss.control(n.cyc = 50)
)

summary(m_gamlss)
plot(m_gamlss)  # residual diagnostics: worm plot, Q-Q

# Compare distributions: which family fits best?
fits <- fitDist(df$Y, type = "realplus")  # auto-fit for positive continuous Y
fits$fits[1:5, ]  # top 5 by GAIC

# Centile curves (quantile regression-like output)
centiles(m_gamlss, xvar = df$X, cent = c(10, 25, 50, 75, 90))

# Export
library(modelsummary)
modelsummary(m_gamlss, output = paste0(output_root, "/tables/table-gamlss.html"))
```

**Reporting:** > "Because [Y] exhibits [substantial right-skew / heteroskedasticity / heavy tails], we estimated a GAMLSS model (Rigby and Stasinopoulos 2005) using a Box-Cox t distribution. Both the conditional mean and conditional variance of [Y] were modeled as functions of [X] and controls. [X] is associated with a [direction] in the mean of [Y] (b_mu = [b], SE = [SE], p = [p]) and a [direction] in the variance (b_sigma = [b], SE = [SE], p = [p]), indicating that [X] affects not only the level but also the dispersion of [Y]."

---

### A8k — Double ML / Causal Forest Bridge (Auto-Route to scholar-compute MODULE 2)

**When to use:** High-dimensional controls (>20 covariates) with a causal question. Instead of manually selecting controls for OLS, let ML handle the nuisance functions.

**This step bridges to `/scholar-compute MODULE 2 Step 5`.** When triggered (>20 controls + causal language), execute the full DML pipeline from scholar-compute:

```r
# ── 09k-dml-bridge.R ──
# Bridge to scholar-compute MODULE 2 Step 5
# See scholar-compute SKILL.md for full DML implementation
library(DoubleML)
library(mlr3); library(mlr3learners)

dml_data <- DoubleMLData$new(
  data = as.data.table(df),
  y_col = "Y", d_cols = "X",
  x_cols = setdiff(names(df), c("Y", "X", "id"))
)

# Primary: Random Forest nuisance learners
ml_g <- lrn("regr.ranger", num.trees = 500, min.node.size = 5)
ml_m <- lrn("classif.ranger", num.trees = 500, predict_type = "prob")

dml_plr <- DoubleMLPLR$new(dml_data, ml_g, ml_m, n_folds = 5, n_rep = 10)
dml_plr$fit()
dml_plr$summary()

# Robustness: Lasso + XGBoost (see scholar-compute Step 5a-robust for full protocol)
# Sensitivity: dml_plr$sensitivity(cf.y = 0.03, cf.d = 0.03)
# Heterogeneous effects: see scholar-compute Step 5a-r-grf for Causal Forest
```

For the full DML protocol (IV-DML, 3-learner robustness, sensitivity contour plots, Causal Forest heterogeneity), invoke `/scholar-compute dml` which runs the expanded MODULE 2 Step 5.

---

### A8l — Growth Curve Models

**When to use:** Panel/longitudinal data where the research question is about trajectories of change over time — how fast individuals change, whether change rates vary by group, and what predicts different growth trajectories.

```r
# ── 09l-growth-curve.R ──
library(lme4); library(lmerTest); library(ggplot2)

# ── Unconditional growth model (random intercept + random slope for time) ──
m_growth0 <- lmer(Y ~ time + (1 + time | id), data = df_long, REML = FALSE)
summary(m_growth0)

# ICC: proportion of variance between persons
VarCorr(m_growth0)
icc <- 0.0  # compute from VarCorr output

# ── Conditional growth model: predictors of intercept and slope ──
m_growth1 <- lmer(
  Y ~ time * group + time * X +     # group and X predict both intercept and slope
      C1 + C2 +                       # time-invariant controls
      (1 + time | id),                # random intercept + slope
  data = df_long, REML = FALSE
)
summary(m_growth1)

# ── Quadratic growth (if trajectory is nonlinear) ──
m_growth2 <- lmer(
  Y ~ time + I(time^2) + group * time + group * I(time^2) +
      (1 + time | id),
  data = df_long, REML = FALSE
)

# Compare: linear vs. quadratic
anova(m_growth1, m_growth2)

# ── Piecewise growth (different slopes before/after a knot) ──
df_long$time_pre  <- pmin(df_long$time, knot)
df_long$time_post <- pmax(df_long$time - knot, 0)
m_piecewise <- lmer(Y ~ time_pre + time_post + group * time_post +
                     (1 + time_pre + time_post | id), data = df_long)

# ── Spaghetti plot with group-level trends ──
ggplot(df_long, aes(x = time, y = Y, group = id)) +
  geom_line(alpha = 0.1) +
  geom_smooth(aes(group = group, color = group), method = "lm", se = TRUE) +
  labs(x = "Time", y = "Outcome") +
  theme_Publication()
ggsave(paste0(output_root, "/figures/fig-growth-curves.pdf"), width = 8, height = 6)

# ── Latent growth model in lavaan (alternative parameterization) ──
library(lavaan)
lgm_model <- '
  # latent intercept and slope
  intercept =~ 1*y1 + 1*y2 + 1*y3 + 1*y4
  slope     =~ 0*y1 + 1*y2 + 2*y3 + 3*y4
  # predict growth factors
  intercept ~ group + X
  slope     ~ group + X
  # variances
  intercept ~~ slope
'
lgm_fit <- growth(lgm_model, data = df_wide)
summary(lgm_fit, fit.measures = TRUE, standardized = TRUE)
```

**Reporting:** > "We estimated growth curve models to examine trajectories of [Y] over [T] time points (Table X). The unconditional model revealed significant between-person variance in both initial status (σ²_intercept = [X], p < .001) and rate of change (σ²_slope = [X], p = [p]). In the conditional model, [group] differences were evident in both intercept (b = [b], SE = [SE], p = [p]) and slope (b = [b], SE = [SE], p = [p]), indicating that [group] started [higher/lower] and [increased/decreased] [faster/slower] over time."

---

### A8m — Multilevel SEM (MSEM)

**When to use:** Data is nested (students in schools, employees in firms) AND you have latent constructs or want to decompose within- vs. between-cluster effects for structural paths.

```r
# ── 09m-multilevel-sem.R ──
library(lavaan)

# Two-level SEM: within-cluster and between-cluster structural models
msem_model <- '
  level: 1  # within
    # measurement model
    engagement =~ item1 + item2 + item3
    performance =~ grade1 + grade2
    # structural model (within)
    performance ~ engagement + ses_w

  level: 2  # between (school level)
    # measurement model
    school_climate =~ clim1 + clim2 + clim3
    school_perf    =~ grade1 + grade2
    # structural model (between)
    school_perf ~ school_climate + avg_ses
'

msem_fit <- sem(msem_model, data = df, cluster = "school_id",
                estimator = "MLR")  # robust ML for non-normal data
summary(msem_fit, fit.measures = TRUE, standardized = TRUE)
fitMeasures(msem_fit, c("cfi", "tli", "rmsea", "srmr.within", "srmr.between"))

# For complex models that lavaan can't handle: MplusAutomation bridge
# library(MplusAutomation)
# prepareMplusData(df, filename = "msem_data.dat")
# ... write and run .inp file
```

---

### A8n — Finite Mixture of Regressions (FMR)

**When to use:** You suspect unobserved population heterogeneity in regression coefficients — the effect of X on Y may differ across latent subgroups, but you don't know group membership a priori.

```r
# ── 09n-finite-mixture-regression.R ──
library(flexmix)
library(ggplot2)

# Fit 2-component mixture of linear regressions
fmr2 <- flexmix(Y ~ X + C1 + C2, data = df, k = 2,
                 model = FLXMRglm(family = "gaussian"))

# Fit 3-component
fmr3 <- flexmix(Y ~ X + C1 + C2, data = df, k = 3,
                 model = FLXMRglm(family = "gaussian"))

# Compare via BIC
BIC(fmr2, fmr3)

# Extract component-specific coefficients
summary(refit(fmr2))  # separate regression tables per component

# Posterior class probabilities
df$fmr_class <- clusters(fmr2)
df$fmr_prob  <- posterior(fmr2)[, 1]  # probability of class 1

# Characterize classes
table(df$fmr_class)
aggregate(. ~ fmr_class, data = df[, c("fmr_class", "X", "Y", "C1")], mean)

# Plot: separate regression lines per latent class
ggplot(df, aes(x = X, y = Y, color = factor(fmr_class))) +
  geom_point(alpha = 0.3, size = 0.5) +
  geom_smooth(method = "lm", se = TRUE) +
  labs(color = "Latent Class") +
  theme_Publication()
ggsave(paste0(output_root, "/figures/fig-fmr-classes.pdf"), width = 8, height = 6)
```

**Reporting:** > "Finite mixture regression identified [K] latent subpopulations with distinct [X]→[Y] relationships (Table X). In Class 1 ([X]% of the sample), [X] was positively associated with [Y] (b = [b], p = [p]), while in Class 2 ([X]%), the association was [negative/null] (b = [b], p = [p]). Classes differed primarily in [characteristic] (Class 1: mean [X] = [val]; Class 2: mean [X] = [val])."

---

### A8o — Specification Curve Analysis / Multiverse Analysis

**When to use:** To demonstrate that your finding is robust across a large set of reasonable analytic choices — not just the one specification you report. Required response to "researcher degrees of freedom" concerns. Increasingly expected at top journals.

```r
# ── 09o-specification-curve.R ──
library(specr)
library(ggplot2)

# Define the multiverse of reasonable specifications
specs <- setup(
  data = df,
  y = c("Y", "Y_alt"),                          # alternative DVs
  x = c("X", "X_binary"),                        # alternative IVs
  model = c("lm", "glm"),                        # model families
  controls = c("C1 + C2", "C1 + C2 + C3 + C4",  # control sets
               "C1 + C2 + C3 + C4 + C5"),
  subsets = list(
    full_sample = NULL,                           # no restriction
    no_outliers = "outlier == 0",                 # drop outliers
    age_restricted = "age >= 25 & age <= 65"      # age restriction
  )
)

# Run all specifications
results <- specr(specs)
summary(results)

# How many specifications? How many significant?
cat("Total specifications:", nrow(results), "\n")
cat("Significant (p < .05):", sum(results$p.value < 0.05), "\n")
cat("Median estimate:", median(results$estimate), "\n")
cat("Range:", range(results$estimate), "\n")

# ── Specification curve plot (the key figure) ──
plot(results, type = "curve") +
  labs(title = "Specification Curve Analysis",
       subtitle = paste0(nrow(results), " specifications; ",
                        sum(results$p.value < .05), " significant at p < .05")) +
  theme_Publication()
ggsave(paste0(output_root, "/figures/fig-specification-curve.pdf"), width = 12, height = 8)

# ── Inference: is the curve systematically different from zero? ──
# Permutation-based p-value for the median estimate
# (Simonsohn, Simmons & Nelson 2020)
```

**Reporting:** > "To assess the robustness of our findings to researcher degrees of freedom (Simonsohn, Simmons, and Nelson 2020), we conducted a specification curve analysis across [N] reasonable specifications, varying the operationalization of [X] ([list]), the control set ([list]), the sample restriction ([list]), and the model family ([list]). The median estimate is [X] (range: [lo] to [hi]); [X]% of specifications yield a statistically significant positive effect (p < .05). [Figure X] displays the full specification curve."

---

### A8p — BART (Bayesian Additive Regression Trees)

**When to use:** Nonparametric estimation of treatment effects or flexible response surfaces. BART handles nonlinearities and interactions automatically without specifying functional form. For causal inference, `bartCause` implements Bayesian causal forest with posterior uncertainty.

```r
# ── 09p-bart.R ──
library(dbarts)
library(bartCause)
library(ggplot2)

# ── Predictive BART (flexible regression) ──
bart_fit <- bart(
  x.train = as.matrix(df[, c("X", "C1", "C2", "C3")]),
  y.train = df$Y,
  ntree = 200, nskip = 500, ndpost = 1000,
  verbose = FALSE
)

# Variable importance (inclusion proportions)
var_counts <- colMeans(bart_fit$varcount) / ncol(bart_fit$varcount)
barplot(sort(var_counts, decreasing = TRUE), main = "BART Variable Importance")

# Partial dependence: effect of X on Y, averaged over other variables
pd_x <- pdbart(bart_fit, xind = 1, pl = FALSE)  # index 1 = X
plot(pd_x$levs[[1]], colMeans(pd_x$fd), type = "l",
     xlab = "X", ylab = "Partial Dependence", main = "BART: Partial Effect of X")

# ── Causal BART (treatment effect estimation) ──
# bartCause: estimates ITE (individual treatment effects) with posterior CIs
bc_fit <- bartc(
  response  = df$Y,
  treatment = df$X_binary,         # binary treatment
  confounders = df[, c("C1", "C2", "C3", "C4")],
  estimand = "ate",
  n.chains = 4, n.samples = 1000, n.burn = 500,
  verbose = FALSE
)

summary(bc_fit)
# ATE with 95% credible interval
ate <- summary(bc_fit)$estimate
cat(sprintf("BART ATE = %.4f, 95%% CI = [%.4f, %.4f]\n",
    ate["estimate"], ate["ci.lower"], ate["ci.upper"]))

# Individual treatment effects: who benefits most?
ite <- fitted(bc_fit, type = "ite")  # individual-level effects
df$ite_mean <- colMeans(ite)
df$ite_sd   <- apply(ite, 2, sd)

# CATE by subgroup
ggplot(df, aes(x = C1, y = ite_mean)) +
  geom_point(alpha = 0.2) +
  geom_smooth(method = "loess", color = "steelblue") +
  geom_hline(yintercept = 0, linetype = "dashed") +
  labs(x = "Covariate", y = "Individual Treatment Effect (BART)",
       title = "Treatment Effect Heterogeneity") +
  theme_Publication()
ggsave(paste0(output_root, "/figures/fig-bart-cate.pdf"), width = 8, height = 6)

# ── Sensitivity analysis: how much unmeasured confounding? ──
sens <- bartc(
  response = df$Y, treatment = df$X_binary,
  confounders = df[, c("C1", "C2", "C3", "C4")],
  estimand = "ate",
  p.scoreAsCovariate = TRUE,   # include propensity score
  n.chains = 4, n.samples = 500
)
```

**Reporting:** > "We estimated treatment effects using Bayesian Additive Regression Trees (BART; Chipman, George, and McCulloch 2010) via the `bartCause` package (Dorie 2020), which flexibly captures nonlinearities and interactions without parametric specification. The posterior mean ATE is [X] (95% credible interval = [[lo], [hi]]). Individual treatment effects vary substantially across the sample (SD of ITE = [X]); effects are concentrated among [subgroup description] (Figure X)."

---

