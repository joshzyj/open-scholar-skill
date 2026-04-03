# Code Review Standards Reference

## Severity Classification

| Level | Definition | Action Required |
|-------|-----------|-----------------|
| CRITICAL | Produces wrong results silently (merge errors, wrong variable, inverted sign) | Must fix before any analysis runs |
| MAJOR | Likely produces wrong results under some conditions (edge cases, missing NA handling) | Fix before finalizing results |
| MINOR | Code works but has quality issues (style, efficiency, readability) | Fix before replication package |
| INFO | Suggestions for improvement, not errors | Optional |

## Common Error Catalogs

### 1. Statistical Implementation Errors
- Off-by-one in lag/lead construction (panel data)
- Wrong reference category in factor variables
- Missing cluster/robust SE specification when data is clustered
- Incorrect degrees of freedom for small-sample corrections
- Applying log() to variables with zeros without adding 1 or using asinh()
- Using OLS when outcome is binary/count (should be logit/Poisson)
- Reporting odds ratios when AME is required (ASR/AJS convention)
- Wrong variance estimator for DiD with few clusters (should use wild bootstrap)
- Failing to account for multiple hypothesis testing (Bonferroni/BH correction)
- Misspecified fixed effects (absorbing the variable of interest)
- Using predict() without specifying type="response" for GLMs

### 2. AI-Generated Code Anti-Patterns
- Hallucinated function names (packages that don't export the function)
- Deprecated API usage (e.g., `aes_string()` instead of `aes()` with `.data[[]]`)
- Overly verbose variable assignments instead of piped operations
- Unnecessary `as.data.frame()` calls on tibbles
- Redundant `library()` calls or conflicting package loads
- Comments that restate the code rather than explain intent
- Creating helper functions for one-time operations
- Over-engineered error handling for impossible conditions
- Using `print()` instead of `message()` for status output
- Hardcoded file paths instead of relative paths or here::here()

### 3. Data Handling Errors
- Miscoded categorical variables (numeric codes treated as continuous)
- Wrong handling of missing values (listwise deletion when MI appropriate)
- Sample restriction errors (filtering before vs. after merge)
- Incorrect variable recoding (inverted scales, wrong cutpoints)
- Unintended NA introduction from joins (left_join creating NAs)
- Merge key mismatches (character vs. numeric ID types)
- Silent observation loss from inner joins
- Not verifying merge completeness (m:1, 1:m, m:m)
- Applying transformations to the wrong variable (copy-paste errors)
- Not checking for duplicate observations after merge

### 4. Reproducibility Errors
- Missing set.seed() before any stochastic operation
- Platform-dependent file paths (backslash vs. forward slash)
- Missing package version pinning (no renv.lock or requirements.txt)
- Non-deterministic ordering (relying on hash-based ordering)
- Hardcoded absolute paths instead of project-relative paths
- Missing sessionInfo() or session_info() at end of script
- Not documenting R/Python version requirements
- Using <<- or global assignment instead of explicit return values

## Verification Checklists

### Pre-Analysis Script Checklist
- [ ] Raw data loaded from read-only source (never modified in place)
- [ ] All variable construction steps documented with comments
- [ ] Sample restrictions applied in documented order
- [ ] Missing data patterns diagnosed before modeling
- [ ] Variable distributions inspected (no impossible values)
- [ ] Merge completeness verified (expected N matches actual N)

### Post-Analysis Script Checklist
- [ ] All reported numbers traceable to specific code lines
- [ ] Coefficient signs match theoretical expectations (or explained)
- [ ] Standard errors appropriate for data structure (cluster, HC, bootstrap)
- [ ] Figures have labeled axes, titles, and uncertainty intervals
- [ ] Tables formatted for target journal (modelsummary/stargazer settings)
- [ ] All scripts run end-to-end from clean environment

## Journal-Specific Computational Reproducibility Requirements

| Journal | Requirements |
|---------|-------------|
| Nature Computational Science | Docker/Singularity container; all code on GitHub/Zenodo with DOI; random seeds documented; Life Sciences Reporting Summary |
| Science Advances | Code availability statement; data deposition; computational methods fully described in Methods |
| NHB | Code availability; Reporting Summary; data availability statement; statistical methods described |
| ASR / AJS | Replication package encouraged; code sharing increasingly expected; AEA-style README |
| Demography | Replication materials required; AEA-style README; data availability statement |
| APSR | Replication archive at Harvard Dataverse; all code and data (or synthetic data if restricted) |
| Sociological Methods & Research | Full code availability; detailed computational appendix |

## R Package Compatibility Notes

| Package | Common Issues |
|---------|--------------|
| fixest | `feols()` not `felm()`; `etable()` not `summary()`; use `i()` for interactions |
| modelsummary | `output="gt"` for HTML; `output="latex"` for TeX; `stars=c('*'=.05)` for significance |
| mice | Complete all imputations before pooling; use `pool()` then `summary()` |
| brms | Set `seed` in `brm()` call; check convergence with `rhat` and `ess` |
| survival | `Surv()` requires time AND event; `coxph()` needs `cluster()` for robust SE |
| lme4 | `glmer()` convergence: try `bobyqa` optimizer; check singular fit warnings |
| sandwich | `vcovCL()` for cluster-robust; `vcovHC()` for heteroskedasticity-robust |

## Python Package Compatibility Notes

| Package | Common Issues |
|---------|--------------|
| statsmodels | Use `sm.OLS().fit(cov_type='HC3')` for robust SE; `add_constant()` required |
| linearmodels | `PanelOLS` needs entity/time effects specified; use `fit(cov_type='clustered')` |
| scikit-learn | Set `random_state` everywhere; use `Pipeline` to prevent data leakage |
| pytorch | Set `torch.manual_seed()` AND `torch.cuda.manual_seed_all()` for full reproducibility |
