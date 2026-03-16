# Machine Learning Methods for Social Science

## Prediction vs. Causal Inference Decision Tree

```
Goal: understand whether X causes Y?
  → Use causal identification strategy (see scholar-causal)
  → ML can assist as nuisance estimator (Double ML) if high-dimensional

Goal: predict Y given X as accurately as possible?
  → Use ML (Random Forest, XGBoost, neural nets)
  → Do NOT interpret feature importances as causal effects

Goal: classify text/images/records into categories?
  → Use supervised ML with human-labeled training data
  → Validate with held-out test set + human annotation
```

---

## Supervised Learning Reference

### Algorithm Selection

| Algorithm | Strengths | Weaknesses | Best when |
|-----------|-----------|------------|-----------|
| Logistic Regression | Interpretable; fast; well-calibrated | Assumes linearity | Baseline; high-dimensional sparse features |
| Random Forest | Non-linear; handles interactions; robust | Opaque; slow to tune | Tabular data; moderate N |
| Gradient Boosting (XGBoost/LightGBM) | Usually best accuracy on tabular data | Needs tuning; can overfit | Competition-grade prediction |
| SVM | Good for small N, high-dimensional | Slow at scale; opaque | Text classification with small labeled sets |
| Neural Networks (MLP) | Universal approximator | Data hungry; expensive; opaque | Large N (> 100K), raw features |
| BERT/RoBERTa | Best text classification | Expensive; needs GPU | Any text task with enough labels |
| LASSO/Ridge | Feature selection; regularized linear | Assumes linearity | High-dimensional linear prediction |

### Cross-Validation Standards

Always use cross-validation — never report train-set performance:

```python
from sklearn.model_selection import StratifiedKFold, cross_validate
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import make_scorer, f1_score, roc_auc_score

clf = GradientBoostingClassifier(n_estimators=200, max_depth=4,
                                  learning_rate=0.05, random_state=42)
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)

scoring = {
    'auc': 'roc_auc',
    'f1':  make_scorer(f1_score, average='weighted'),
    'accuracy': 'accuracy'
}

results = cross_validate(clf, X, y, cv=cv, scoring=scoring)

print(f"AUC:  {results['test_auc'].mean():.3f} ± {results['test_auc'].std():.3f}")
print(f"F1:   {results['test_f1'].mean():.3f} ± {results['test_f1'].std():.3f}")
```

### Reporting Standards

**What must be reported** (NCS/Science Advances):
```
Table X. Model Performance Metrics

                   Train    Val      Test
──────────────────────────────────────────
Accuracy           0.847    0.821    0.818
Precision (macro)  0.841    0.815    0.812
Recall (macro)     0.838    0.810    0.807
F1 (macro)         0.839    0.812    0.809
AUC-ROC            0.912    0.893    0.889

Note. Performance on 5-fold cross-validated validation set;
held-out test set N = 2,000 (20% of sample).
```

---

## Double Machine Learning (DML) Reference

DML (Chernozhukov et al. 2018, Econometrica) allows causal estimation when:
- X (treatment) is binary or continuous
- W (confounders) is high-dimensional (many controls)
- You want unbiased estimate of X → Y even with many controls

**Two-step procedure**:
1. Partial out W from Y using ML: ε_Y = Y − Ê(Y|W)
2. Partial out W from X using ML: ε_X = X − Ê(X|W)
3. Regress ε_Y on ε_X: coefficient = causal effect of X on Y

```python
from econml.dml import LinearDML, CausalForestDML
from sklearn.ensemble import GradientBoostingRegressor, GradientBoostingClassifier
from sklearn.linear_model import LassoCV

# For average treatment effect (ATE):
dml = LinearDML(
    model_y = GradientBoostingRegressor(random_state=42),   # E(Y|W)
    model_t = GradientBoostingClassifier(random_state=42),  # E(T|W)
    discrete_treatment = True,
    cv = 5,
    random_state = 42
)
dml.fit(Y=y, T=treatment, X=None, W=W_controls)

ate = dml.ate()
ate_ci = dml.ate_interval(alpha=0.05)
print(f"ATE = {ate:.4f}, 95% CI = [{ate_ci[0]:.4f}, {ate_ci[1]:.4f}]")
```

**Heterogeneous treatment effects** (who benefits most?):
```python
# Causal Forest DML: estimates CATE(X) = E[Y(1)-Y(0)|X]
cf_dml = CausalForestDML(
    model_y = GradientBoostingRegressor(random_state=42),
    model_t = GradientBoostingClassifier(random_state=42),
    n_estimators = 500,
    discrete_treatment = True,
    random_state = 42
)
cf_dml.fit(Y=y, T=treatment, X=X_moderators, W=W_controls)

# Individual-level effects
cate = cf_dml.effect(X_moderators)

# Linear summary of heterogeneity
cf_dml.const_marginal_ate()  # Average
cf_dml.const_marginal_effect(X_moderators).mean(axis=0)

# Which features most predict heterogeneity?
from econml.cate_interpreter import SingleTreeCATEInterpreter
interp = SingleTreeCATEInterpreter(max_depth=3)
interp.interpret(cf_dml, X_moderators)
interp.plot(feature_names=feature_names)
```

---

## Model Interpretability (SHAP)

Required by NCS/Science Advances for ML-based findings:

```python
import shap

# Fit a model
from sklearn.ensemble import RandomForestClassifier
clf = RandomForestClassifier(n_estimators=200, random_state=42)
clf.fit(X_train, y_train)

# Compute SHAP values
explainer = shap.TreeExplainer(clf)
shap_values = explainer.shap_values(X_test)

# Summary plot (feature importance + direction)
shap.summary_plot(shap_values[1], X_test,
                  feature_names=feature_names,
                  plot_type="bar")

# Dependence plot for one feature
shap.dependence_plot("education", shap_values[1], X_test,
                     feature_names=feature_names,
                     interaction_index="income")
```

**SHAP reporting template**:
> "To assess feature contributions, we computed SHAP (SHapley Additive exPlanations) values for each prediction (Lundberg & Lee 2017). Figure [X] shows the mean absolute SHAP value for each feature, representing its average contribution to the model's predictions. [Feature A] was the strongest predictor (mean |SHAP| = X), followed by [Feature B] (mean |SHAP| = Y). The direction of effects was consistent with our theoretical expectations: [explain direction for key features]."

---

## Evaluation Metrics Reference

| Metric | Formula | When to use |
|--------|---------|------------|
| Accuracy | (TP+TN)/N | Balanced classes only |
| Precision | TP/(TP+FP) | False positives costly |
| Recall | TP/(TP+FN) | False negatives costly |
| F1 (macro) | Harmonic mean P+R | Imbalanced classes |
| AUC-ROC | Area under ROC | Ranking quality; threshold-independent |
| AUC-PR | Area under precision-recall | Very imbalanced classes |
| Cohen's κ | (P_o - P_e)/(1 - P_e) | Comparing to baseline agreement |
| MCC | Balanced accuracy including TN | Preferred for binary imbalanced |

**Rule of thumb**:
- Report F1 (macro or weighted) + AUC-ROC for classification tasks in social science
- Always also report N per class to show imbalance
- Accuracy alone is misleading when classes are imbalanced (> 80/20 split)

---

## Hyperparameter Tuning with Optuna

Optuna (Akiba et al. 2019) provides Bayesian optimization (TPE sampler) for hyperparameter search. Preferred over grid search for models with many parameters.

### GradientBoosting / XGBoost / LightGBM

```python
import optuna
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import StratifiedKFold, cross_val_score

optuna.logging.set_verbosity(optuna.logging.WARNING)

def objective_gbt(trial):
    params = {
        "n_estimators":   trial.suggest_int("n_estimators", 100, 600),
        "max_depth":      trial.suggest_int("max_depth", 2, 7),
        "learning_rate":  trial.suggest_float("learning_rate", 1e-3, 0.3, log=True),
        "subsample":      trial.suggest_float("subsample", 0.5, 1.0),
        "min_samples_leaf": trial.suggest_int("min_samples_leaf", 1, 20),
        "random_state":   42
    }
    clf    = GradientBoostingClassifier(**params)
    cv     = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    return cross_val_score(clf, X_train, y_train, cv=cv, scoring="roc_auc").mean()

study = optuna.create_study(
    direction="maximize",
    sampler=optuna.samplers.TPESampler(seed=42)
)
study.optimize(objective_gbt, n_trials=100, show_progress_bar=True)

print(f"Best AUC: {study.best_value:.4f}")
print(f"Best params: {study.best_params}")

# Refit with best params
best_clf = GradientBoostingClassifier(**study.best_params, random_state=42)
best_clf.fit(X_train, y_train)
```

### Random Forest

```python
def objective_rf(trial):
    params = {
        "n_estimators":    trial.suggest_int("n_estimators", 100, 500),
        "max_depth":       trial.suggest_int("max_depth", 3, 20),
        "min_samples_split": trial.suggest_int("min_samples_split", 2, 20),
        "max_features":    trial.suggest_categorical("max_features", ["sqrt","log2",None]),
        "random_state":    42
    }
    from sklearn.ensemble import RandomForestClassifier
    clf = RandomForestClassifier(**params)
    cv  = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    return cross_val_score(clf, X_train, y_train, cv=cv, scoring="roc_auc").mean()
```

### LASSO / Ridge for Prediction (high-dimensional)

```python
from sklearn.linear_model import LassoCV, RidgeCV, LogisticRegressionCV
import numpy as np

# LASSO with cross-validated alpha (performs feature selection)
lasso = LassoCV(cv=5, random_state=42, max_iter=10000)
lasso.fit(X_train, y_train)
print(f"LASSO best alpha: {lasso.alpha_:.5f}")
n_nonzero = np.sum(lasso.coef_ != 0)
print(f"Non-zero features: {n_nonzero} / {X_train.shape[1]}")

# Logistic LASSO for classification
lasso_clf = LogisticRegressionCV(
    Cs=np.logspace(-4, 2, 20),
    cv=5, penalty="l1", solver="saga",
    scoring="roc_auc", random_state=42
)
lasso_clf.fit(X_train, y_train)
```

### Hyperparameter Reporting Standard (NCS / Science Advances)

Required supplementary table format:

```
Table SX. Hyperparameter Search Space and Selected Values

Parameter         | Search range           | Selected value | Selection method
------------------|------------------------|----------------|------------------
n_estimators      | [100, 600]             | [X]            | Optuna TPE, 100 trials
max_depth         | [2, 7]                 | [X]            |
learning_rate     | [0.001, 0.3] (log)     | [X]            |
subsample         | [0.5, 1.0]             | [X]            |
min_samples_leaf  | [1, 20]                | [X]            |

Note. Final model selected by maximizing 5-fold stratified CV AUC-ROC on training set.
Random seed: 42 for all stochastic components.
```

**Reporting template:**
> "Hyperparameters were selected via Bayesian optimization using the Optuna framework (Akiba et al. 2019) with the TPE sampler (seed = 42) over 100 trials. Candidate models were evaluated by 5-fold stratified cross-validation AUC-ROC on the training set. The optimal hyperparameter configuration (Table S[X]) achieved a CV AUC of [X ± Y]. Final model performance on the held-out test set: AUC = [X], F1 = [X] (Table [X])."
