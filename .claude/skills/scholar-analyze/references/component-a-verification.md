### A9 — Analysis Verification (Subagent)

After completing A1–A8 (including any applicable A8a–A8p extended methods), launch a **verification subagent** via the Task tool (`subagent_type: general-purpose`) to audit all analytic work before proceeding to visualization.

**Prompt the subagent with the following context:**
- Full list of analytic decisions (model type, SE type, sample exclusions, variables)
- Bash output from `ls ${OUTPUT_ROOT}/tables/` showing saved files
- Target journal
- Summary of model results (coefficients, SEs, p-values, AME if applicable)

**The subagent performs these checks and returns a VERIFICATION REPORT:**

```
ANALYSIS VERIFICATION REPORT
=============================

MODEL SPECIFICATION
[ ] Correct model family for outcome type
    - Binary outcome → logit/probit (not OLS)
    - Count outcome → negative binomial (not Poisson unless mean ≈ variance)
    - Count with excess zeros → zero-inflated or hurdle model (A8c)
    - Proportion (0,1) → beta regression (A8d)
    - Ordered outcome → polr (not OLS)
    - Time-to-event → Cox PH (not linear)
    - Time-to-event with competing risks → Fine-Gray (A8e)
    - Latent subgroups → LCA/mixture (A8a); BIC-based class selection
    - Distributional effects → quantile regression (A8b)
    - Latent constructs → CFA/SEM (A8h); fit indices reported
    - Panel reciprocal paths → RI-CLPM (A8f); between/within decomposition
    - Trajectory data → sequence analysis (A8g); OM + clustering
[ ] Progressive model ladder present (M1 baseline → M2 +controls → M3 extended)
[ ] Multiple testing correction applied if > 5 simultaneous tests (A8i)

STANDARD ERRORS
[ ] HC3 robust SEs used for OLS (or justification given for default SEs)
[ ] Clustered SEs used when observations are nested within units
[ ] lmerTest loaded for p-values in lme4 multilevel models

MARGINAL EFFECTS
[ ] AME computed via avg_slopes() for ALL logistic / ordered logit models
[ ] Raw log-odds NOT reported as main estimates in sociology journals
[ ] AME table saved (table2-ame.html/.tex/.docx)

DIAGNOSTICS
[ ] VIF < 10 for all predictors (car::vif run)
[ ] Heteroskedasticity test run (bptest) — if significant, HC3 SEs confirmed
[ ] For panel: Hausman test and serial correlation test run
[ ] For Cox PH: cox.zph() Schoenfeld residuals checked

REPORTING STANDARDS (journal-specific)
[ ] For ASR/AJS: AME reported; SE in parentheses; stars + exact p in text
[ ] For Demography: decomposition run if comparing group means
[ ] For NHB/Science Advances: exact test stat + df + p included
[ ] No "trend toward significance" language (p = .07 is NOT significant)
[ ] Reference categories documented for all categorical predictors
[ ] Sample size N reported for each model
[ ] Effect sizes (β, AME, HR, IRR) reported alongside p-values

SENSITIVITY
[ ] Robustness table generated (tableA1-robustness)
[ ] Oster delta (sensemakr) run if OLS and any causal language used
[ ] Oster delta > 1 or reported with exact value
[ ] Specification curve analysis (A8o) run if >3 reasonable alternative specifications exist

ML BRIDGE (if triggered)
[ ] High-dimensional controls (>20) detected → DML bridge (A8k) invoked
[ ] DML estimate compared across ≥2 ML learners (RF, Lasso, XGBoost)
[ ] DML sensitivity analysis run (Chernozhukov et al. 2022)

EXTENDED MODELS (if applicable)
[ ] GAMLSS (A8j): distribution selection via fitDist(); worm plot residuals checked
[ ] Growth curve (A8l): random slope significance tested; model comparison (linear vs. quadratic)
[ ] MSEM (A8m): fit indices reported (CFI, TLI, RMSEA, SRMR within/between)
[ ] FMR (A8n): BIC comparison across K=2,3,4; class characterization table produced
[ ] Specification curve (A8o): N specifications reported; median + range of estimates; % significant
[ ] BART (A8p): posterior convergence checked; variable importance reported; CATE plot produced

TABLE OUTPUT FORMATS
[ ] modelsummary tables saved in HTML + TeX + docx
[ ] gt tables saved (if requested) — HTML format via gtsave()
[ ] Stata .do files generated alongside R scripts (if requested)

CELL-BY-CELL TABLE VERIFICATION
[ ] For each regression table: re-extract key coefficients from model object, compare to table cells
[ ] Verify: coefficient sign matches prose interpretation
[ ] Verify: SE in table matches SE from model summary (within rounding)
[ ] Verify: stars match p-value thresholds consistently across all tables
[ ] Verify: N in table footer matches nobs() from model object
[ ] Verify: R² / pseudo-R² matches summary() output

FILES ON DISK
[ ] output/[slug]/tables/table1-descriptives.html + .tex + .docx
[ ] output/[slug]/tables/table2-regression.html + .tex + .docx
[ ] output/[slug]/tables/table2-ame.html + .tex + .docx  (if logit)
[ ] output/[slug]/tables/tableA1-robustness.html + .tex + .docx
[ ] output/[slug]/tables/ — gt versions present (if requested)

RESULT: [PASS / NEEDS REVISION]

Issues to fix before proceeding:
1. [Specific issue + corrected code if applicable]
```

If the verification subagent returns **NEEDS REVISION**, fix all flagged issues and re-export affected tables before proceeding to Component B.

---

