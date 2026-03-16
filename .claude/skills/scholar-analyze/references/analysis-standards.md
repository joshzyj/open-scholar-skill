# Analysis and Reporting Standards by Journal

## Universal Reporting Standards (All Journals)

### What Must Always Be Reported
1. **Sample size** (N) for each model
2. **Effect estimates** with standard errors or 95% confidence intervals
3. **Exact p-values** (e.g., p = .034, not p < .05) — APA 7th ed. standard
4. **Model fit statistics** appropriate to the estimator
5. **Reference categories** for all categorical variables
6. **How missing data are handled**

### Statistical Significance Notation (Stars)
```
* p < .05
** p < .01
*** p < .001
Note: Standard errors in parentheses.
```
Report exact p-values in text; stars in tables are visual aids only.

### Effect Sizes
Always report effect sizes alongside significance:
- OLS: Standardized β; R² change; partial η²
- Logistic: Average Marginal Effects (AME); OR with CI
- Survival: Hazard ratio (HR) with 95% CI
- Count: Incidence rate ratio (IRR)

---

## Journal-Specific Reporting Requirements

### American Sociological Review (ASR)

**Statistical reporting preferences**:
- **Strongly prefer AME** over odds ratios for logistic regression; odds ratios may be reported as supplementary
- Standard errors in parentheses (not confidence intervals unless review requires it)
- F-tests or chi-square tests for joint significance when comparing nested models
- Present unstandardized OLS coefficients; note standardized in footnote if space allows

**Table format**:
- Minimize asterisks — use exact p-values in text
- Column labels should indicate the dependent variable and model number
- Horizontal lines only (no vertical lines in tables)
- All tables and figures placed at end of manuscript, after references

**Figures**:
- Increasingly expected for interactions and marginal effects
- Predicted probabilities / predicted values plots preferred over raw coefficients
- 300 DPI minimum; EPS or TIFF preferred for print

**Multiple hypothesis testing**:
- With many outcomes or subgroups, use Bonferroni correction or FDR correction
- Acknowledge the multiplicity issue in text

**Mediation reporting (Imai et al. framework)**:
```
Total effect: β_total (SE) p = .xxx
Direct effect: β_direct (SE) p = .xxx
Indirect effect (via M): β_indirect (SE) p = .xxx [bootstrapped CI: lower, upper]
Proportion mediated: xx%
```

---

### American Journal of Sociology (AJS)

**Statistical reporting preferences**:
- Similar to ASR; slightly more tolerant of displaying odds ratios for logistic regression
- AJS publishes more qualitative work; quantitative papers expected to be methodologically conservative

**Notes on computational papers**:
- AJS accepts computational methods papers, but they must have strong theoretical grounding
- Computational findings should connect explicitly to sociological theory

---

### Demography

**Statistical reporting preferences**:
- **Very detailed methods sections** expected; reviewers are methodologists
- Demographic decomposition (Kitagawa, Oaxaca-Blinder) expected when comparing group means
- Life table and survival analyses: Report at multiple percentiles of survival distribution, not just median
- For fertility/mortality: Report both absolute (rates) and relative (rate ratios)

**Required tables**:
1. Descriptive statistics by key group
2. Regression results with progressive model buildup
3. Sensitivity/robustness check tables (may go in supplement)

**Online supplement (mandatory)**:
- Full variable coding
- Sensitivity analyses
- Additional models not in main text

**Data availability**:
- Code and data deposit to ICPSR or similar required at publication

---

### Science Advances (AAAS)

**Statistical reporting preferences**:
- Align with journal-specific methods — computational and quantitative
- Error bars must always be explicitly labeled in figures (SEM vs. SD vs. 95% CI)
- P-values: report exact; use ≤ or ≥ for thresholds
- For behavioral data: individual subject data points shown in figures when N is small

**Figure standards**:
- All panel labels in uppercase (A, B, C...)
- Figure legends must be self-explanatory (do not rely on main text to interpret figure)
- Color: use colorblind-accessible palettes (ColorBrewer); do not use red-green together
- Statistical test markers on figures: use ns (p > .05), * (p ≤ .05), ** (p ≤ .01), *** (p ≤ .001)

**Reproducibility statement**:
- Materials and Methods must have enough detail for exact replication
- Code deposited on GitHub; version archived with Zenodo DOI

---

### Nature Human Behaviour (NHB)

**Statistical reporting requirements** (from Life Sciences Reporting Summary):
- For each statistical test: exact test used, test statistic value, degrees of freedom, p-value, effect size
- Power calculation or justification for sample size
- How normality of data was tested (or state that it was assumed)
- Multiple comparisons corrections used
- For experiments: randomization and blinding procedures

**Preferred figure format**:
- Show individual data points for small samples (N < 30 per group)
- Show violin plots or box plots (not just bar graphs with error bars)
- Effect sizes on figures with 95% CI

**Preregistration**:
- Strongly preferred; state in methods: "This study was preregistered at OSF [URL]."
- If not preregistered, state: "This study was not preregistered."

**Transparency checklists** (required as supplementary):
- Reporting Summary (downloadable from Nature website)
- For surveys: full questionnaire wording
- For computational models: model specification and training details

**Maximum 50 references** in main text for standard articles

---

### Nature Computational Science (NCS)

**Additional computational reporting requirements**:
- Algorithm description: pseudocode or step-by-step description
- Computational complexity: O(n) notation for key algorithms
- Comparison to baseline/state-of-the-art: quantitative benchmarking required
- Hyperparameter reporting: all hyperparameters, search space, and selection method
- Random seeds: specify all random seeds used
- Hardware: GPU/CPU specifications and compute time

**Code deposit requirements** (mandatory):
- GitHub repository with clear README
- Zenodo DOI archived at submission
- Conda environment or Docker file for reproducibility
- Unit tests for key functions

**NCS Peer Review Transfer**: Papers rejected from Nature can be transferred to NCS with reviews if computational methods are the key contribution

---

## Robustness and Sensitivity Standards

### Minimum robustness checks for top journals:

| Check Type | When Required | How to Present |
|-----------|---------------|----------------|
| Alternative operationalization | Main IV measured multiple ways | Supplementary table |
| Alternative sample restriction | Ambiguous exclusion criteria | Supplementary table |
| Alternative model specification | Controls could be over/under | Supplementary table |
| Placebo test | Causal claims | Supplementary table or figure |
| Sensitivity to functional form | Non-linear relationships plausible | Main or supplement |
| Attrition analysis | Panel data with dropout | Methods section |
| Bounding exercise | Causal claims from OLS | Methods or supplement |

### Oster (2019) test for OLS omitted variable bias:
Reports the "delta" value: how much stronger must selection on unobservables be relative to selection on observables to explain away the finding?
- Delta > 1 is typically considered strong evidence
- Report: "Following Oster (2019), we estimate delta = X, suggesting unobserved confounders would need to be X times more predictive of [Y] than our observed controls to explain our finding."

**Stata**: `psacalc`
**R**: `sensemakr`

---

## Common Reporting Errors to Avoid

1. **Interpreting odds ratios as probabilities**: Never say "odds ratio of 2 means twice as likely"
2. **Not reporting AME** for logistic regression in sociology journals
3. **Omitting reference category** in tables
4. **"Trend toward significance"**: p = .08 is not significant; report it as non-significant
5. **Reporting R² for logistic regression** without noting it is pseudo-R²
6. **Cherry-picking models**: Show all models, including those with smaller effects
7. **Ignoring clustering** when units are nested
8. **Not reporting effect sizes**: p < .001 without β is uninterpretable

---

## Modern Marginal Effects Packages

### `marginaleffects` (R) — current standard (2022–present)

`marginaleffects` replaces the older `margins` package and provides a uniform API across virtually all model classes (GLMs, `fixest` panel models, `lme4` multilevel, `survival`, `brms` Bayesian, etc.).

**Key functions:**

| Function | Purpose |
|----------|---------|
| `avg_slopes(model)` | Average Marginal Effects (AME) — averaged over all observations; report in tables |
| `slopes(model, newdata = datagrid(...))` | Marginal effects at representative/specified values |
| `avg_comparisons(model)` | Average Treatment Contrasts (e.g., factor level A vs. B) |
| `marginal_means(model)` | Marginal means (EMMs) by group |
| `plot_slopes(model, variables, condition)` | Publication-ready marginal effects plot |
| `plot_predictions(model, condition)` | Predicted values / probabilities plot |
| `hypotheses(...)` | Linear and nonlinear hypothesis tests on marginal quantities |

**Installation:**
```r
install.packages("marginaleffects")
library(marginaleffects)
```

**Typical workflow for logit (ASR/AJS):**
```r
m_logit <- glm(y ~ x + controls, family = binomial, data = df)

# Report AME in tables (not raw log-odds)
ame <- avg_slopes(m_logit)
print(ame)

# Export
modelsummary(ame, output = paste0(output_root, "/tables/table2-ame.html"),
             notes = "Average marginal effects; 95% CIs in brackets.")

# Figure
plot_slopes(m_logit, variables = "x") +
  geom_hline(yintercept = 0, linetype = "dashed") +
  theme_Publication()
```

**Notes:**
- For `fixest` panel models: `avg_slopes(feols_model)` correctly handles clustered SEs
- For `lme4` mixed models: `avg_slopes(lmer_model)` marginalizes over random effects by default
- For interaction terms: use `plot_slopes(model, variables="x", condition="moderator")` to plot marginal effects across the moderator's range

---

## Python Statistical Equivalents

### OLS / GLM

```python
import statsmodels.formula.api as smf

# OLS with HC3 robust SEs
ols = smf.ols('y ~ x + controls', data=df).fit(cov_type='HC3')
print(ols.summary())

# Logit
logit = smf.logit('y ~ x + controls', data=df).fit(cov_type='HC3')
print(logit.summary())

# Probit
probit = smf.probit('y ~ x + controls', data=df).fit(cov_type='HC3')
```

### Fixed Effects Panel (linearmodels)

```python
from linearmodels.panel import PanelOLS, RandomEffects
import numpy as np

df_panel = df.set_index(['unit_id', 'year'])

# Two-way fixed effects
fe = PanelOLS.from_formula(
    'y ~ x + controls + EntityEffects + TimeEffects',
    data=df_panel
).fit(cov_type='clustered', cluster_entity=True)
print(fe.summary)

# Hausman test (compare FE vs RE)
re = RandomEffects.from_formula('y ~ x + controls', data=df_panel).fit()
# Compare manually via Wu-Hausman statistic
```

### Marginal Effects (Python port)

```python
# marginaleffects Python package (same API as R)
from marginaleffects import avg_slopes, slopes, plot_slopes

ame = avg_slopes(logit_model)
print(ame.to_frame())

# At representative values
mer = slopes(logit_model, newdata={'x': [0, 1], 'female': [0, 1]})
```

### Survival Analysis (lifelines)

```python
from lifelines import CoxPHFitter, KaplanMeierFitter

# Cox PH
cph = CoxPHFitter()
cph.fit(df, duration_col='time', event_col='event',
        formula='x + controls')
cph.print_summary()

# Schoenfeld residuals (PH test)
cph.check_assumptions(df, p_value_threshold=0.05)

# Kaplan-Meier
kmf = KaplanMeierFitter()
for grp in df['group'].unique():
    d = df[df['group']==grp]
    kmf.fit(d['time'], d['event'], label=grp)
    kmf.plot_survival_function()
```

### Export Tables (statsmodels)

```python
from statsmodels.iolib.summary2 import summary_col

# Multi-model table
table = summary_col(
    [ols_m1, ols_m2, ols_m3],
    model_names=["Baseline", "+Controls", "+FE"],
    stars=True,
    info_dict={'N': lambda x: "{0:d}".format(int(x.nobs)),
               'R²': lambda x: "{:.3f}".format(x.rsquared)}
)
print(table)
table.as_latex()   # LaTeX output
```
