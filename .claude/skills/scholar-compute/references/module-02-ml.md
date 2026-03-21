## MODULE 2: Machine Learning for Social Science

### Step 1 — Goal Gate

Before choosing a model, be explicit about the goal:

| Goal | Appropriate method |
|------|--------------------|
| Does X *cause* Y? | Causal identification strategy → `/scholar-causal` |
| Predict Y as accurately as possible | ML (RF, XGBoost, NN) |
| Classify records / text into categories | Supervised ML with held-out test set |
| Causal effect with many confounders | Double ML / Causal Forest (Step 4) |

**Do NOT interpret ML feature importance as a causal effect.**

### Step 2 — Causal Gate

If the research question involves causal inference AND the user is not already running DML/Causal Forest as the primary estimator: invoke `/scholar-causal` first.

### Step 3 — Supervised Learning Workflow

```python
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.model_selection import StratifiedKFold, cross_validate
from sklearn.metrics import make_scorer, f1_score, roc_auc_score
import joblib

# Define pipeline
pipe = Pipeline([
    ("scaler", StandardScaler()),
    ("clf",    GradientBoostingClassifier(
                   n_estimators=200, max_depth=4,
                   learning_rate=0.05, random_state=42))
])

# 5-fold stratified cross-validation
cv      = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
scoring = {"auc": "roc_auc",
           "f1":  make_scorer(f1_score, average="weighted"),
           "acc": "accuracy"}
results = cross_validate(pipe, X_train, y_train, cv=cv, scoring=scoring)

print(f"CV AUC: {results['test_auc'].mean():.3f} ± {results['test_auc'].std():.3f}")
print(f"CV F1:  {results['test_f1'].mean():.3f}  ± {results['test_f1'].std():.3f}")

# Fit on full training set; evaluate on held-out test set
pipe.fit(X_train, y_train)
joblib.dump(pipe, "${OUTPUT_ROOT}/models/clf_final.pkl")

from sklearn.metrics import classification_report
print(classification_report(y_test, pipe.predict(X_test)))
```

### Step 4 — Hyperparameter Tuning (Optuna)

```python
import optuna
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import cross_val_score, StratifiedKFold

def objective(trial):
    params = {
        "n_estimators":  trial.suggest_int("n_estimators", 100, 500),
        "max_depth":     trial.suggest_int("max_depth", 2, 6),
        "learning_rate": trial.suggest_float("learning_rate", 1e-3, 0.3, log=True),
        "subsample":     trial.suggest_float("subsample", 0.6, 1.0),
        "random_state":  42
    }
    clf    = GradientBoostingClassifier(**params)
    cv     = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    scores = cross_val_score(clf, X_train, y_train, cv=cv, scoring="roc_auc")
    return scores.mean()

study = optuna.create_study(direction="maximize",
                             sampler=optuna.samplers.TPESampler(seed=42))
study.optimize(objective, n_trials=100, show_progress_bar=True)

print("Best AUC:", study.best_value)
print("Best params:", study.best_params)

# Report: "Hyperparameters were selected via Bayesian optimization (Optuna;
# Akiba et al. 2019) with 100 trials and 5-fold CV; best AUC = [X]."
```

### Step 5 — Double ML / Causal Forests

For causal estimation with high-dimensional controls. Covers: (5a) R DoubleML package — PLR, IV, and IPLR models; (5a-py) Python EconML — LinearDML, CausalForestDML; (5a-robust) robustness protocol across ML learners; (5a-sensitivity) sensitivity analysis; (5a-het) heterogeneous treatment effects with Causal Forest + visualization; (5a-report) reporting template.

**When to use:** You have a causal question (effect of X on Y), many potential confounders (W), and selection-on-observables is the identification strategy. DML flexibly controls for W using ML while producing root-N consistent estimates with valid CIs. For designs with an instrument, use IV-DML (PLIV model).

**Decision table:**

| Design | DML Model | R class | Python class |
|--------|-----------|---------|-------------|
| Selection on observables (OLS-like) | Partially Linear (PLR) | `DoubleMLPLR` | `LinearDML` |
| Instrumental variables | Partially Linear IV (PLIV) | `DoubleMLPLIV` | `DMLIV` |
| Interactive treatment (heterogeneous by X) | Interactive Regression (IRM) | `DoubleMLIRM` | `CausalForestDML` |
| IV + interactive treatment | Interactive IV (IIVM) | `DoubleMLIIVM` | `DMLIV` + `CausalForestDML` |

#### 5a. R DoubleML Package — Full Implementation

```r
# ── 30-dml-estimation.R ──
# Double/Debiased Machine Learning via R DoubleML package
# Reference: Chernozhukov et al. (2018) Econometrics Journal
# Package: Bach et al. (2022) JMLR
library(DoubleML)
library(mlr3)
library(mlr3learners)
library(mlr3tuning)
library(data.table)
library(ggplot2)

set.seed(42)

# ── Load and prepare data ──────────────────────────────────────────
df <- read.csv("data/survey_data.csv")

# Define variable roles
Y_COL  <- "wages"                    # outcome
D_COL  <- "job_training"             # treatment
Z_COL  <- NULL                       # instrument (set if IV design)
X_COLS <- setdiff(names(df), c(Y_COL, D_COL, "person_id", "weight"))

# Create DoubleML data object
dml_data <- DoubleMLData$new(
  data      = as.data.table(df),
  y_col     = Y_COL,
  d_cols    = D_COL,
  x_cols    = X_COLS
  # z_cols  = Z_COL  # uncomment for IV design
)
cat("N =", nrow(df), "| Controls =", length(X_COLS), "\n")

# ── Define ML learners for nuisance functions ──────────────────────
# E[Y|W] = ml_g (regression); E[D|W] = ml_m (classification if binary D)

# Learner 1: Random Forest
ml_g_rf <- lrn("regr.ranger",
  num.trees = 500, min.node.size = 5, mtry = floor(sqrt(length(X_COLS))))
ml_m_rf <- lrn("classif.ranger",
  num.trees = 500, min.node.size = 5, predict_type = "prob")

# Learner 2: Lasso (cross-validated lambda)
ml_g_lasso <- lrn("regr.cv_glmnet", s = "lambda.min", alpha = 1)
ml_m_lasso <- lrn("classif.cv_glmnet", s = "lambda.min", alpha = 1,
                    predict_type = "prob")

# Learner 3: Gradient Boosting
ml_g_xgb <- lrn("regr.xgboost",
  nrounds = 200, max_depth = 4, eta = 0.1, subsample = 0.8,
  verbose = 0)
ml_m_xgb <- lrn("classif.xgboost",
  nrounds = 200, max_depth = 4, eta = 0.1, subsample = 0.8,
  verbose = 0, predict_type = "prob")

# ── Model 1: Partially Linear Regression (PLR) ────────────────────
# Y = θD + g(W) + ε,  D = m(W) + v
# θ is the treatment effect (ATE under selection on observables)

dml_plr <- DoubleMLPLR$new(
  data      = dml_data,
  ml_g      = ml_g_rf,       # E[Y|W] learner
  ml_m      = ml_m_rf,       # E[D|W] learner
  n_folds   = 5,             # K-fold cross-fitting
  n_rep     = 10,            # repeat cross-fitting 10 times for stability
  score     = "partialling out"  # Frisch-Waugh-Lovell orthogonalization
)

dml_plr$fit()
dml_plr$summary()
cat("\nATE:", round(dml_plr$coef, 4),
    "SE:", round(dml_plr$se, 4),
    "95% CI: [", round(dml_plr$confint()[1], 4), ",",
    round(dml_plr$confint()[2], 4), "]\n")

# ── Model 2: Partially Linear IV (PLIV) — if instrument available ──
# Y = θD + g(W) + ε,  D = r(W,Z) + v
# Uses instrument Z to address endogeneity of D

# dml_data_iv <- DoubleMLData$new(
#   data   = as.data.table(df),
#   y_col  = Y_COL,
#   d_cols = D_COL,
#   x_cols = X_COLS,
#   z_cols = Z_COL  # instrument(s)
# )
#
# ml_r <- lrn("regr.ranger", num.trees = 500)  # E[D|W,Z] learner
#
# dml_pliv <- DoubleMLPLIV$new(
#   data   = dml_data_iv,
#   ml_g   = ml_g_rf,   # E[Y|W]
#   ml_m   = ml_m_rf,   # E[Z|W] — instrument residual
#   ml_r   = ml_r,      # E[D|W,Z]
#   n_folds = 5,
#   n_rep   = 10
# )
# dml_pliv$fit()
# dml_pliv$summary()

# ── Model 3: Interactive Regression Model (IRM) ───────────────────
# For binary treatment with potentially heterogeneous propensity scores
# ATE = E[Y(1) - Y(0)] via doubly-robust AIPW score

dml_irm <- DoubleMLIRM$new(
  data    = dml_data,
  ml_g    = ml_g_rf,     # E[Y|D,W] — outcome model
  ml_m    = ml_m_rf,     # E[D|W] — propensity score
  n_folds = 5,
  n_rep   = 10,
  score   = "ATE"        # or "ATTE" for ATT
)
dml_irm$fit()
dml_irm$summary()
```

#### 5a-robust. Robustness Protocol — Compare Across ML Learners

```r
# ── 31-dml-robustness.R ──
# Robustness: re-estimate with different ML learners for nuisance functions
# If θ is stable across learners, the result is credible

learner_configs <- list(
  "Random Forest"       = list(g = ml_g_rf,    m = ml_m_rf),
  "Lasso"               = list(g = ml_g_lasso,  m = ml_m_lasso),
  "Gradient Boosting"   = list(g = ml_g_xgb,    m = ml_m_xgb)
)

results <- data.frame(
  Learner = character(), ATE = numeric(), SE = numeric(),
  CI_low = numeric(), CI_high = numeric(), stringsAsFactors = FALSE
)

for (name in names(learner_configs)) {
  cfg <- learner_configs[[name]]
  dml_fit <- DoubleMLPLR$new(
    data    = dml_data,
    ml_g    = cfg$g,
    ml_m    = cfg$m,
    n_folds = 5,
    n_rep   = 10,
    score   = "partialling out"
  )
  dml_fit$fit()
  ci <- dml_fit$confint()
  results <- rbind(results, data.frame(
    Learner = name,
    ATE     = dml_fit$coef,
    SE      = dml_fit$se,
    CI_low  = ci[1],
    CI_high = ci[2]
  ))
}

print(results)

# ── Robustness plot: coefficient comparison across learners ────────
ggplot(results, aes(x = Learner, y = ATE)) +
  geom_point(size = 3) +
  geom_errorbar(aes(ymin = CI_low, ymax = CI_high), width = 0.2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  labs(title = "DML Treatment Effect: Robustness Across ML Learners",
       y = "Average Treatment Effect (θ)", x = "") +
  coord_flip() +
  theme_Publication()
ggsave(paste0(output_root, "/figures/fig-dml-robustness.pdf"), width = 8, height = 4)

# ── Nuisance model quality check ──────────────────────────────────
# Report out-of-sample R² for each nuisance model
# Bad nuisance fits → unreliable DML estimates
cat("\n=== Nuisance Model Quality ===\n")
for (name in names(learner_configs)) {
  cfg <- learner_configs[[name]]
  dml_fit <- DoubleMLPLR$new(dml_data, cfg$g, cfg$m, n_folds=5, n_rep=1)
  dml_fit$fit()
  cat(sprintf("%s: g-model RMSE = %.4f, m-model RMSE = %.4f\n",
      name, dml_fit$rmses["ml_g"], dml_fit$rmses["ml_m"]))
}
```

#### 5a-sensitivity. Sensitivity Analysis for Unobserved Confounding

```r
# ── 32-dml-sensitivity.R ──
# Sensitivity analysis: how much unobserved confounding would be needed
# to overturn the DML estimate?
# Uses Chernozhukov et al. (2022) sensitivity framework built into DoubleML

# ── Method 1: DoubleML built-in sensitivity (Chernozhukov et al. 2022) ──
# Computes bounds on θ under departures from conditional exogeneity
# Parameters: cf.y = R² of omitted variable on Y residual
#             cf.d = R² of omitted variable on D residual

dml_plr$sensitivity(cf.y = 0.03, cf.d = 0.03)
# Interpretation: if an unobserved confounder explains 3% of residual
# variation in both Y and D, the bounds on θ are [lo, hi]

# ── Sensitivity contour plot ──────────────────────────────────────
# Vary cf.y and cf.d on a grid; plot where θ changes sign
cf_grid <- expand.grid(
  cf_y = seq(0.01, 0.15, by = 0.01),
  cf_d = seq(0.01, 0.15, by = 0.01)
)
cf_grid$theta_lower <- NA
cf_grid$theta_upper <- NA

for (i in 1:nrow(cf_grid)) {
  sens <- dml_plr$sensitivity(cf.y = cf_grid$cf_y[i], cf.d = cf_grid$cf_d[i])
  cf_grid$theta_lower[i] <- sens$ci[1]
  cf_grid$theta_upper[i] <- sens$ci[2]
}
cf_grid$sign_change <- cf_grid$theta_lower <= 0 & cf_grid$theta_upper >= 0

ggplot(cf_grid, aes(x = cf_d, y = cf_y, fill = sign_change)) +
  geom_tile() +
  scale_fill_manual(values = c("FALSE" = "steelblue", "TRUE" = "firebrick"),
                    labels = c("θ remains significant", "θ could be zero"),
                    name = "") +
  labs(title = "DML Sensitivity: Robustness to Unobserved Confounding",
       x = expression(R^2 ~ "of omitted variable on D residual" ~ (cf[D])),
       y = expression(R^2 ~ "of omitted variable on Y residual" ~ (cf[Y]))) +
  theme_Publication()
ggsave(paste0(output_root, "/figures/fig-dml-sensitivity.pdf"), width = 8, height = 6)

# ── Method 2: Oster delta (for comparison with conventional approach) ──
# See /scholar-causal for Oster (2019) implementation
# DML sensitivity (above) is preferred because it accounts for
# the ML-based nuisance estimation
```

#### 5a-py. Python EconML — Full Implementation

```python
# ── 33-dml-econml.py ──
# Double ML via EconML (Microsoft Research)
# Covers: LinearDML (ATE), CausalForestDML (CATE), DMLIV (instruments)
import numpy as np
import pandas as pd
from econml.dml import LinearDML, CausalForestDML
from econml.iv.dml import DMLIV
from econml.cate_interpreter import SingleTreeCATEInterpreter
from sklearn.ensemble import (GradientBoostingRegressor,
                               GradientBoostingClassifier,
                               RandomForestRegressor,
                               RandomForestClassifier)
from sklearn.linear_model import LassoCV, LogisticRegressionCV
import matplotlib.pyplot as plt

np.random.seed(42)
df = pd.read_csv("data/survey_data.csv")

Y = df["wages"].values
T = df["job_training"].values
W = df[[c for c in df.columns
        if c not in ["wages", "job_training", "person_id"]]].values
feature_names = [c for c in df.columns
                 if c not in ["wages", "job_training", "person_id"]]

# ── ATE via LinearDML ──────────────────────────────────────────────
dml = LinearDML(
    model_y=GradientBoostingRegressor(n_estimators=200, max_depth=4,
                                       random_state=42),
    model_t=GradientBoostingClassifier(n_estimators=200, max_depth=4,
                                        random_state=42),
    discrete_treatment=True,
    cv=5,
    random_state=42
)
dml.fit(Y=Y, T=T, X=None, W=W)
ate = dml.ate()
ate_lo, ate_hi = dml.ate_interval(alpha=0.05)
print(f"ATE = {ate:.4f}, 95% CI = [{ate_lo:.4f}, {ate_hi:.4f}]")

# ── Robustness: compare learners (Python version) ─────────────────
learner_configs = {
    "Gradient Boosting": (
        GradientBoostingRegressor(n_estimators=200, max_depth=4, random_state=42),
        GradientBoostingClassifier(n_estimators=200, max_depth=4, random_state=42)),
    "Random Forest": (
        RandomForestRegressor(n_estimators=500, min_samples_leaf=5, random_state=42),
        RandomForestClassifier(n_estimators=500, min_samples_leaf=5, random_state=42)),
    "Lasso / Logistic": (
        LassoCV(cv=5, random_state=42),
        LogisticRegressionCV(cv=5, max_iter=1000, random_state=42)),
}

robust_results = []
for name, (my, mt) in learner_configs.items():
    est = LinearDML(model_y=my, model_t=mt, discrete_treatment=True,
                     cv=5, random_state=42)
    est.fit(Y=Y, T=T, X=None, W=W)
    lo, hi = est.ate_interval(alpha=0.05)
    robust_results.append({"Learner": name, "ATE": est.ate(),
                           "CI_low": lo, "CI_high": hi})
robust_df = pd.DataFrame(robust_results)
print("\n=== Robustness Across Learners ===")
print(robust_df.to_string(index=False))

# ── IV-DML (if instrument available) ──────────────────────────────
# Z = df["instrument"].values  # instrument
# dml_iv = DMLIV(
#     model_y_xw=GradientBoostingRegressor(random_state=42),
#     model_t_xw=GradientBoostingClassifier(random_state=42),
#     model_t_xwz=GradientBoostingClassifier(random_state=42),
#     discrete_treatment=True,
#     cv=5
# )
# dml_iv.fit(Y=Y, T=T, Z=Z, X=None, W=W)
# ate_iv = dml_iv.ate()
# print(f"IV-DML ATE = {ate_iv:.4f}")

# ── Heterogeneous effects via Causal Forest ────────────────────────
# X_moderators = variables you suspect moderate the treatment effect
X_mod_cols = ["age", "education", "female", "race_black"]
X_mod = df[X_mod_cols].values

cf = CausalForestDML(
    model_y=GradientBoostingRegressor(n_estimators=200, random_state=42),
    model_t=GradientBoostingClassifier(n_estimators=200, random_state=42),
    n_estimators=1000,
    discrete_treatment=True,
    random_state=42
)
cf.fit(Y=Y, T=T, X=X_mod, W=W)

# Interpretable summary tree
interp = SingleTreeCATEInterpreter(max_depth=3)
interp.interpret(cf, X_mod)
fig, ax = plt.subplots(figsize=(14, 8))
interp.plot(feature_names=X_mod_cols, ax=ax)
fig.savefig(f"{output_root}/figures/fig-dml-cate-tree.pdf",
            bbox_inches="tight", dpi=300)

# CATE distribution plot
cate_preds = cf.effect(X_mod)
fig, ax = plt.subplots(figsize=(8, 5))
ax.hist(cate_preds, bins=50, edgecolor="white", alpha=0.8)
ax.axvline(x=0, color="red", linestyle="--", label="Zero effect")
ax.axvline(x=np.mean(cate_preds), color="blue", linestyle="-",
           label=f"Mean CATE = {np.mean(cate_preds):.4f}")
ax.set_xlabel("Conditional Average Treatment Effect (CATE)")
ax.set_ylabel("Count")
ax.set_title("Distribution of Heterogeneous Treatment Effects")
ax.legend()
fig.savefig(f"{output_root}/figures/fig-dml-cate-dist.pdf",
            bbox_inches="tight", dpi=300)

# Subgroup treatment effects
for col_idx, col_name in enumerate(X_mod_cols):
    median_val = np.median(X_mod[:, col_idx])
    above = cate_preds[X_mod[:, col_idx] > median_val]
    below = cate_preds[X_mod[:, col_idx] <= median_val]
    print(f"{col_name}: CATE above median = {above.mean():.4f}, "
          f"below = {below.mean():.4f}, diff = {above.mean()-below.mean():.4f}")
```

#### 5a-r-grf. Causal Forest in R (grf Package)

```r
# ── 34-causal-forest-grf.R ──
# Causal Forest via grf package (Athey, Tibshirani, Wager 2019)
library(grf)
library(ggplot2)

set.seed(42)

X <- as.matrix(df[, x_cols])
Y <- df[[y_col]]
W <- df[[d_col]]

# ── Fit Causal Forest ──────────────────────────────────────────────
cf <- causal_forest(
  X = X, Y = Y, W = W,
  num.trees        = 4000,
  honesty          = TRUE,      # honest estimation (split sample)
  honesty.fraction = 0.5,
  min.node.size    = 5,
  seed             = 42
)

# ── ATE with standard error ───────────────────────────────────────
ate <- average_treatment_effect(cf, target.sample = "all")
cat(sprintf("ATE = %.4f, SE = %.4f, 95%% CI = [%.4f, %.4f]\n",
    ate[1], ate[2], ate[1] - 1.96*ate[2], ate[1] + 1.96*ate[2]))

# ATT (effect on treated only)
att <- average_treatment_effect(cf, target.sample = "treated")
cat(sprintf("ATT = %.4f, SE = %.4f\n", att[1], att[2]))

# ── Best Linear Projection: which variables drive heterogeneity? ──
blp <- best_linear_projection(cf, X)
print(blp)

# ── CATE predictions + calibration test ───────────────────────────
cate <- predict(cf)$predictions

# Calibration test (Chernozhukov et al. 2020 "Generic ML inference")
test_calibration(cf)
# "mean.forest.prediction" should be significant
# "differential.forest.prediction" significant → meaningful heterogeneity

# ── Variable importance ───────────────────────────────────────────
varimp <- variable_importance(cf)
varimp_df <- data.frame(
  Variable   = x_cols,
  Importance = as.numeric(varimp)
)
varimp_df <- varimp_df[order(-varimp_df$Importance), ]

ggplot(head(varimp_df, 15), aes(x = reorder(Variable, Importance), y = Importance)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  labs(title = "Causal Forest: Variables Driving Treatment Effect Heterogeneity",
       x = "", y = "Variable Importance") +
  theme_Publication()
ggsave(paste0(output_root, "/figures/fig-cf-varimp.pdf"), width = 8, height = 6)

# ── CATE by subgroup (e.g., by education) ─────────────────────────
df$cate <- cate
library(dplyr)
subgroup_effects <- df %>%
  group_by(education_group) %>%
  summarise(
    mean_cate = mean(cate),
    se_cate   = sd(cate) / sqrt(n()),
    n         = n()
  )

ggplot(subgroup_effects, aes(x = education_group, y = mean_cate)) +
  geom_point(size = 3) +
  geom_errorbar(aes(ymin = mean_cate - 1.96*se_cate,
                     ymax = mean_cate + 1.96*se_cate), width = 0.2) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  labs(title = "Treatment Effect Heterogeneity by Education",
       y = "Conditional Average Treatment Effect", x = "") +
  theme_Publication()
ggsave(paste0(output_root, "/figures/fig-cf-subgroup.pdf"), width = 8, height = 5)

# ── Overlap check (propensity score) ──────────────────────────────
e_hat <- cf$W.hat  # estimated propensity scores
hist(e_hat, breaks = 50, main = "Propensity Score Distribution",
     xlab = "P(D=1|X)", col = "steelblue")
# Trim observations with extreme propensity (< 0.05 or > 0.95)
overlap_mask <- e_hat > 0.05 & e_hat < 0.95
cat(sprintf("Overlap: %d of %d (%.1f%%) observations retained\n",
    sum(overlap_mask), length(overlap_mask), 100*mean(overlap_mask)))
```

#### 5a-report. Reporting Templates

**DML (PLR model):**
> "We estimate the average treatment effect of [X] on [Y] using Double/Debiased Machine Learning (Chernozhukov et al. 2018). The partially linear model Y = θD + g(W) + ε flexibly controls for [N] potential confounders W using [primary learner: random forest / gradient boosting / lasso] to estimate the nuisance functions E[Y|W] and E[D|W], while producing a root-N consistent, asymptotically normal estimate of θ via Neyman-orthogonal score functions and 5-fold cross-fitting with 10 repetitions. We find θ = [X] (95% CI = [[lo], [hi]]; p [</>] 0.05). As a robustness check, we re-estimate using [learner 2] and [learner 3] for the nuisance functions; estimates are substantively unchanged ([Table N]). Sensitivity analysis following Chernozhukov et al. (2022) indicates that an unobserved confounder would need to explain at least [X]% of residual variation in both treatment and outcome to reduce the estimate to zero."

**Causal Forest (heterogeneous effects):**
> "To examine treatment effect heterogeneity, we estimate a Causal Forest (Athey, Tibshirani, and Wager 2019) with 4,000 trees using honest estimation (50% honesty fraction). The omnibus calibration test confirms significant heterogeneity (differential forest prediction: t = [X], p < [Y]). Variable importance analysis identifies [top variables] as the primary drivers of heterogeneity. The average treatment effect is [X] (SE = [Y]), with effects ranging from [min CATE] to [max CATE] across the population. [Subgroup finding, e.g., 'Effects are concentrated among individuals with less than a college education (CATE = [X]) and are near zero for college graduates (CATE = [Y])']."

**IV-DML:**
> "Because [treatment] is potentially endogenous (due to [reason]), we use [instrument] as an instrumental variable within the Double ML framework (PLIV model; Chernozhukov et al. 2018). The instrument satisfies the relevance condition (first-stage F = [X]) and is plausibly exogenous because [argument]. The IV-DML estimate is θ = [X] (95% CI = [[lo], [hi]]), compared to the OLS-DML estimate of [Y], consistent with [upward/downward] bias from [source of endogeneity]."

### Step 5b — Bayesian Regression with brms / Stan

**When to use over frequentist regression**: (1) Small N with sparse data where MLE estimates are unstable; (2) Complex hierarchical / cross-classified models that are hard to fit with `lme4`; (3) Uncertainty propagation is important (posterior predictive checks); (4) Informative priors are available from prior literature or meta-analyses; (5) Estimating full posterior distributions for complex quantities (e.g., ratios, products of parameters).

**Not needed when**: N is large, standard MLE converges, and credible intervals ≈ confidence intervals.

```r
library(brms)
library(tidybayes)
library(bayesplot)
library(ggplot2)

# ── Step 1: Specify model ─────────────────────────────────────────────
# brms uses lme4-style formula syntax; priors specified with prior()
# bf(): brmsformula; allows custom non-linear or mixture models

# Example: multilevel logistic regression (cross-classified by state + year)
m_bayes <- brm(
  formula  = outcome ~ treatment + education + income + (1 | state) + (1 | year),
  data     = df,
  family   = bernoulli(link = "logit"),
  prior    = c(
    prior(normal(0, 1),   class = b),           # weakly informative for fixed effects
    prior(normal(0, 0.5), class = Intercept),   # logit scale
    prior(exponential(1), class = sd)            # half-exponential for random effect SDs
  ),
  chains   = 4,
  iter     = 4000,
  warmup   = 2000,
  cores    = 4,
  seed     = 42,
  backend  = "cmdstanr",   # faster than rstan; install: install.packages("cmdstanr")
  file     = "${OUTPUT_ROOT}/models/brms-multilevel-logit"  # cache — skip refit if unchanged
)

# ── Step 2: Check convergence ─────────────────────────────────────────
summary(m_bayes)   # check Rhat ≈ 1.00; Bulk_ESS and Tail_ESS > 400

# Trace plots (visual convergence check)
mcmc_trace(m_bayes, pars = c("b_treatment", "b_education"))
ggsave("${OUTPUT_ROOT}/figures/bayes-trace.pdf", width=10, height=6)

# ── Step 3: Posterior predictive check ───────────────────────────────
pp_check(m_bayes, ndraws=100, type="dens_overlay")
ggsave("${OUTPUT_ROOT}/figures/bayes-ppc.pdf", width=8, height=5)

# ── Step 4: Extract and summarize posterior ───────────────────────────
# Posterior draws for all parameters
draws <- as_draws_df(m_bayes)

# Credible intervals (95% central CI)
posterior_summary(m_bayes, probs=c(0.025, 0.975))[, c("Estimate","Q2.5","Q97.5")]

# Probability of direction (P(β > 0))
hypothesis(m_bayes, "treatment > 0")

# ── Step 5: Marginal effects / conditional means ──────────────────────
library(marginaleffects)
# Average marginal effect (AME) on the probability scale
avg_slopes(m_bayes, variables="treatment")

# Conditional effects plot
conditional_effects(m_bayes, effects="treatment:education") |>
  plot(points=FALSE)

# ── Step 6: Model comparison ──────────────────────────────────────────
# LOO-CV (leave-one-out cross-validation; preferred over WAIC for finite N)
loo_m1 <- loo(m_bayes)
loo_m0 <- loo(m_bayes_null)
loo_compare(loo_m1, loo_m0)   # elpd_diff > 4 SE units → clear preference

# ── Step 7: Table export ──────────────────────────────────────────────
library(modelsummary)
modelsummary(m_bayes,
             statistic    = "conf.int",  # report 95% CIs instead of SEs
             conf_level   = 0.95,
             output       = "${OUTPUT_ROOT}/tables/table-bayes.html")
```

**Prior selection guidance**:
| Parameter | Weakly informative prior | Informative prior (if meta-analysis available) |
|-----------|--------------------------|------------------------------------------------|
| Fixed effect (log-odds scale) | `normal(0, 1)` | `normal(μ_meta, σ_meta)` |
| Fixed effect (standardized continuous) | `normal(0, 0.5)` | From prior literature |
| Intercept (logit) | `normal(0, 1.5)` | Based on base rate |
| Random effect SD | `exponential(1)` | `half-normal(0, σ)` |
| Correlation of random effects | `lkj(2)` (regularizing) | Default |

**Reporting template:**
> "We fit a Bayesian multilevel logistic regression using `brms` (Bürkner 2017) with `cmdstanr` as the backend. We specified weakly informative priors: normal(0, 1) for fixed effects (log-odds scale), exponential(1) for random-effect standard deviations. We ran 4 chains of 4,000 iterations (2,000 warmup), with all chains showing convergence (R̂ ≤ 1.01; bulk ESS > 400 for all parameters). Posterior predictive checks confirmed adequate model fit. We report posterior means and 95% central credible intervals (CI). The average marginal effect of [treatment] on the probability of [outcome] was [X] (95% CI = [[lo], [hi]]), indicating [interpretation]."

### Step 5c — Conformal Prediction: Distribution-Free Uncertainty Quantification

**When to use**: When you need calibrated uncertainty estimates for ML predictions without distributional assumptions. Conformal prediction provides **prediction sets** (classification) or **prediction intervals** (regression) with guaranteed finite-sample coverage, regardless of the underlying model. This is valuable for: (1) Reporting honest uncertainty around ML-based classifications in social science; (2) Identifying ambiguous cases that need human review; (3) Communicating prediction reliability to non-technical audiences; (4) Complementing point predictions with principled intervals for policy-relevant research.

**Not needed when**: You already use Bayesian methods (brms/Stan) that produce posterior credible intervals, or when the goal is purely causal inference (use `/scholar-causal`).

| Task | Method | Package |
|------|--------|---------|
| Classification prediction sets | Split conformal, APS, RAPS | `mapie` (Python) |
| Regression prediction intervals | Split conformal, CV+ | `mapie` (Python) |
| Classification (R) | Split conformal, jackknife+ | `conformalInference` |
| Regression (R) | Conformal intervals | `conformalInference`, `cfcausal` |
| Conditional coverage | Mondrian conformal | `mapie` with grouping |

**Installation:**

```bash
# Python
pip install mapie

# R
# install.packages("conformalInference")
# Or from GitHub for latest: devtools::install_github("ryantibs/conformal/conformalInference")
```

**Option A — Conformal classification (Python, MAPIE):**

```python
# pip install mapie
from mapie.classification import MapieClassifier
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import f1_score
import numpy as np, pandas as pd

SEED = 42
np.random.seed(SEED)

# Split: train (60%), calibration (20%), test (20%)
X_trainval, X_test, y_trainval, y_test = train_test_split(
    X, y, test_size=0.2, random_state=SEED, stratify=y
)
X_train, X_calib, y_train, y_calib = train_test_split(
    X_trainval, y_trainval, test_size=0.25, random_state=SEED, stratify=y_trainval
)

# Fit base classifier on training set
base_clf = GradientBoostingClassifier(n_estimators=200, max_depth=4,
                                       random_state=SEED)
base_clf.fit(X_train, y_train)

# Wrap with MAPIE for conformal prediction sets
# method="score": Adaptive Prediction Sets (APS); provides smaller sets
mapie_clf = MapieClassifier(estimator=base_clf, cv="prefit", method="score")
mapie_clf.fit(X_calib, y_calib)

# Predict with coverage guarantee (1 - alpha)
alpha = 0.10   # target 90% coverage
y_pred, y_sets = mapie_clf.predict(X_test, alpha=alpha)
# y_sets: boolean array (N_test, N_classes, 1) — True = class in prediction set

# Evaluate
empirical_coverage = y_sets[np.arange(len(y_test)), y_test, 0].mean()
avg_set_size       = y_sets[:, :, 0].sum(axis=1).mean()
print(f"Target coverage: {1-alpha:.0%}")
print(f"Empirical coverage: {empirical_coverage:.3f}")
print(f"Average prediction set size: {avg_set_size:.2f}")
print(f"Point prediction F1 (macro): {f1_score(y_test, y_pred, average='macro'):.3f}")

# Identify ambiguous cases (prediction set size > 1)
ambiguous_mask = y_sets[:, :, 0].sum(axis=1) > 1
print(f"Ambiguous cases (set size > 1): {ambiguous_mask.sum()} / {len(y_test)} "
      f"({ambiguous_mask.mean():.1%})")

# Save results
results_df = pd.DataFrame({
    "y_true": y_test,
    "y_pred": y_pred,
    "set_size": y_sets[:, :, 0].sum(axis=1),
    "ambiguous": ambiguous_mask,
    **{f"class_{c}_in_set": y_sets[:, c, 0] for c in range(y_sets.shape[1])}
})
results_df.to_csv("${OUTPUT_ROOT}/tables/conformal-classification.csv", index=False)
```

**Option B — Conformal regression intervals (Python, MAPIE):**

```python
from mapie.regression import MapieRegressor
from sklearn.ensemble import GradientBoostingRegressor

# Fit base regressor
base_reg = GradientBoostingRegressor(n_estimators=200, max_depth=4,
                                      random_state=SEED)

# CV+ method: uses cross-validation residuals (no separate calibration set needed)
mapie_reg = MapieRegressor(estimator=base_reg, cv=5, method="plus")
mapie_reg.fit(X_train, y_train)

# Predict with 90% prediction interval
alpha = 0.10
y_pred, y_intervals = mapie_reg.predict(X_test, alpha=alpha)
# y_intervals: (N_test, 2, 1) — lower and upper bounds

lower = y_intervals[:, 0, 0]
upper = y_intervals[:, 1, 0]

# Evaluate coverage and interval width
coverage      = ((y_test >= lower) & (y_test <= upper)).mean()
avg_width     = (upper - lower).mean()
median_width  = np.median(upper - lower)
print(f"Target coverage: {1-alpha:.0%}")
print(f"Empirical coverage: {coverage:.3f}")
print(f"Mean interval width: {avg_width:.3f}")
print(f"Median interval width: {median_width:.3f}")

# Save
pd.DataFrame({
    "y_true": y_test, "y_pred": y_pred,
    "lower": lower, "upper": upper,
    "width": upper - lower
}).to_csv("${OUTPUT_ROOT}/tables/conformal-regression.csv", index=False)

# Visualization: prediction intervals sorted by predicted value
import matplotlib.pyplot as plt
order = np.argsort(y_pred)
fig, ax = plt.subplots(figsize=(10, 5))
ax.fill_between(range(len(y_pred)), lower[order], upper[order],
                alpha=0.3, color=PALETTE_CB[2], label=f"{1-alpha:.0%} prediction interval")
ax.scatter(range(len(y_pred)), y_test[order], s=8, color=PALETTE_CB[0],
           label="Observed", zorder=3)
ax.plot(range(len(y_pred)), y_pred[order], color=PALETTE_CB[1],
        linewidth=1, label="Predicted")
ax.set_xlabel("Test observations (sorted by prediction)")
ax.set_ylabel("Outcome")
ax.legend()
plt.savefig("${OUTPUT_ROOT}/figures/conformal-intervals.pdf", dpi=300, bbox_inches="tight")
plt.savefig("${OUTPUT_ROOT}/figures/conformal-intervals.png", dpi=300, bbox_inches="tight")
```

**Option C — Conformal prediction in R (conformalInference):**

```r
# install.packages("conformalInference")
library(conformalInference)
library(randomForest)
library(tidyverse)

set.seed(42)

# Define training and prediction functions for conformalInference
train_fn   <- function(x, y, ...) randomForest(x, y, ntree = 500)
predict_fn <- function(obj, newx, ...) predict(obj, newx)

# Split conformal regression intervals
conf_result <- conformal.pred.split(
  x      = as.matrix(X_train),
  y      = y_train,
  x0     = as.matrix(X_test),
  train.fun   = train_fn,
  predict.fun = predict_fn,
  alpha  = 0.10   # 90% coverage
)

# Results
test_results <- tibble(
  y_true = y_test,
  y_pred = conf_result$pred,
  lower  = conf_result$lo,
  upper  = conf_result$up,
  width  = conf_result$up - conf_result$lo
)

coverage <- mean(test_results$y_true >= test_results$lower &
                 test_results$y_true <= test_results$upper)
cat(sprintf("Empirical coverage: %.3f\n", coverage))
cat(sprintf("Mean interval width: %.3f\n", mean(test_results$width)))

write_csv(test_results, "${OUTPUT_ROOT}/tables/conformal-regression-r.csv")

# Conditional coverage by subgroup (Mondrian-style)
# Check if coverage is uniform across key groups
test_results$group <- X_test_df$race   # example grouping variable
test_results |>
  group_by(group) |>
  summarize(
    n        = n(),
    coverage = mean(y_true >= lower & y_true <= upper),
    avg_width = mean(width)
  ) |>
  write_csv("${OUTPUT_ROOT}/tables/conformal-conditional-coverage.csv")
```

**Validation approach:**
- Report empirical coverage on the test set; it should match the nominal level (e.g., 90% +/- 2%)
- Report average and median prediction set size (classification) or interval width (regression)
- Check conditional coverage across key subgroups (race, gender, SES) to detect unfairness
- Compare conformal intervals to naive percentile bootstrap intervals and Bayesian credible intervals
- For classification, report the fraction of ambiguous cases (set size > 1) and analyze what makes them ambiguous

**Reporting template:**
> "We quantify prediction uncertainty using conformal prediction (Vovk et al. 2005), which provides distribution-free prediction [sets / intervals] with finite-sample coverage guarantees. We use the [APS / CV+ / split conformal] method implemented in `mapie` (Taquet et al. 2022) [/ `conformalInference` (Tibshirani et al. 2019)]. At the 90% nominal coverage level, the empirical coverage on the held-out test set (N = [X]) is [X]%, with an average prediction [set size of [X] classes / interval width of [X] units]. [X]% of test observations have ambiguous prediction sets (size > 1), suggesting [interpretation about boundary cases]. Conditional coverage across [demographic subgroups] ranges from [X]% to [X]%, indicating [uniform / non-uniform] reliability across groups. All models use seed = 42."

---

### Step 6 — SHAP Interpretability

Required by NCS and Science Advances for ML-based findings:

```python
import shap

explainer   = shap.TreeExplainer(pipe["clf"])
shap_values = explainer.shap_values(X_test)

# Summary plot: feature importance + direction
shap.summary_plot(shap_values, X_test, feature_names=feature_names,
                  show=False)
import matplotlib.pyplot as plt
plt.savefig("${OUTPUT_ROOT}/figures/fig-shap-summary.pdf", bbox_inches="tight", dpi=300)

# Dependence plot for key feature
shap.dependence_plot("education", shap_values, X_test,
                     feature_names=feature_names, show=False)
plt.savefig("${OUTPUT_ROOT}/figures/fig-shap-education.pdf", bbox_inches="tight", dpi=300)
```

### Step 7 — ML Verification (Subagent)

```
ML VERIFICATION REPORT
=======================

GOAL / METHOD ALIGNMENT
[ ] Prediction goal → ML used; causal goal → /scholar-causal invoked or DML used
[ ] Feature importances NOT interpreted as causal effects

VALIDATION
[ ] Train/val/test split documented (ratios reported)
[ ] Cross-validation used (not train-set performance)
[ ] F1 (macro + weighted), AUC-ROC reported on test set
[ ] Accuracy NOT reported as sole metric for imbalanced classes
[ ] N per class reported alongside metrics

HYPERPARAMETERS
[ ] All hyperparameters and search space reported
[ ] Selection method documented (grid search / Optuna / random)
[ ] Best hyperparameters tabulated in supplementary

SHAP
[ ] SHAP values computed and saved
[ ] Summary plot saved to output/[slug]/figures/
[ ] Direction of SHAP effects discussed in text

DOUBLE ML / CAUSAL FOREST (if used)
[ ] Nuisance model specifications reported
[ ] Cross-fitting folds specified (cv=5)
[ ] ATE with 95% CI reported
[ ] CATE heterogeneity plot saved

BAYESIAN brms (if used)
[ ] Rhat ≤ 1.01 for all parameters
[ ] Bulk ESS and Tail ESS > 400 for all key parameters
[ ] Trace plots saved (visual convergence check)
[ ] Posterior predictive check (pp_check) run and saved
[ ] Prior specifications documented and justified
[ ] LOO-CV used for model comparison (not WAIC alone)
[ ] 95% credible intervals reported (not p-values)
[ ] file= argument set to cache model (avoid refitting)

CONFORMAL PREDICTION (if used)
[ ] Separate calibration set held out (or CV+ method used)
[ ] Nominal coverage level stated (e.g., 90%)
[ ] Empirical coverage on test set reported and matches nominal level (±2%)
[ ] Average prediction set size (classification) or interval width (regression) reported
[ ] Conditional coverage checked across key subgroups
[ ] Ambiguous cases (set size > 1) analyzed and reported
[ ] Prediction interval figure saved to output/[slug]/figures/
[ ] Comparison to alternative UQ methods (bootstrap / Bayesian) if applicable

SEEDS AND MODELS
[ ] random_state=42 / seed=42 set in all stochastic objects
[ ] Fitted model saved to output/[slug]/models/

RESULT: [PASS / NEEDS REVISION]
Issues: [list]
```

---

