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

