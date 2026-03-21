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

### A3b — Bayesian Regression

**Bayesian analysis is in a separate loadable file.** Load `component-a-bayesian.md` when Bayesian methods are needed:

```bash
cat "${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-analyze/references/component-a-bayesian.md"
```

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

