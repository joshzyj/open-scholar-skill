# Preregistration Reference

## Platform Quick Comparison

| Platform | Templates | Embargo | DOI | Best for |
|----------|-----------|---------|-----|---------|
| OSF Preregistrations | 15+ templates | Yes (4 years) | Yes | Social science general; flexible |
| AsPredicted | Simple 9-question form | Yes (until publication) | No | Quick confirmatory |
| EGAP | Field experiments | Yes | Yes | Political science / RCTs |
| AEA RCT Registry | Structured for RCTs | Yes | Yes | Economics / social science RCTs |
| OSF Registered Reports | RR Stage 1 + 2 | No | Yes | Pre-results peer review |
| Aspredicted.org | 9-question | Yes | No | Fast; any design |

---

## Registered Reports (RR) — Full Reference

### What Are Registered Reports?

A publishing format where **peer review occurs before data collection** (Stage 1),
and **acceptance is conditional on the question and design, not the results** (Stage 2).

**Advantages**:
- Eliminates publication bias: results published regardless of direction / significance
- Prevents HARKing: analysis plan locked before data collection
- Growing list of accepting journals: NHB, PLOS ONE, AMPPS, Collabra, Social Psychology

**When to use**:
- Original data collection studies where null results are scientifically meaningful
- Replication studies
- Studies in under-powered domains where effect sizes are uncertain

### RR Workflow

```
Step 1: Write Stage 1 manuscript
  ├── Introduction (full theory + hypotheses)
  ├── Methods (complete design, measures, sampling, analysis plan)
  ├── Power analysis (justify N; minimum detectable effect)
  └── No Results section

Step 2: Submit Stage 1 to journal
  ├── Reviewers evaluate: Is the question important? Is the design rigorous?
  ├── One of: Accept / Revise & Resubmit / Reject
  └── If accepted → In-Principle Acceptance (IPA) letter issued

Step 3: Preregister on OSF
  ├── Upload Stage 1 manuscript + IPA letter
  ├── Register → cannot be modified
  └── OSF URL = permanent preregistration record

Step 4: Collect data per protocol

Step 5: Write Stage 2 manuscript
  ├── Introduction (unchanged from Stage 1)
  ├── Methods (unchanged; note any NECESSARY deviations + justification)
  ├── Results (new)
  └── Discussion (new)

Step 6: Submit Stage 2
  ├── Journal verifies you followed the registered protocol
  └── Accepts: results published regardless of direction/significance
```

### Stage 1 Methods Section Requirements

```
Design rationale:
  - Why this design (observational vs. experimental vs. computational)?
  - Why this population / sampling frame?
  - What threats to validity and how addressed?

Participants / Data:
  - Target population; inclusion/exclusion criteria
  - Sampling procedure
  - Expected N (from power analysis); stopping rule

Materials and procedure:
  - All measures with source citations
  - Exact question wording (survey items in appendix)
  - Manipulation checks (if experimental)

Analysis plan:
  - Primary model (exact equation)
  - Covariates and justification
  - SE type; clustering level
  - Inference criteria (α = .05 two-tailed)
  - Handling of missing data
  - Sensitivity analyses

Power analysis:
  - Effect size estimate (from prior literature / MDES)
  - α = .05; power = 0.80 (or 0.90 for higher bar)
  - Software: pwr::pwr.t.test() / simr / G*Power
  - Report: "N = [X] achieves [80/90]% power to detect [effect size]"
```

---

## AsPredicted Preregistration (9 Questions)

```
1. Data collection. Have any data been collected for this study already?
   → [No, no data have been collected]
   → [Yes, at least some data collected, but I have not yet looked at any
      variable in a fashion that could be considered confirmatory analysis]

2. Hypothesis. What's the main question being asked or hypothesis being tested?
   H1: [State directional prediction — "X is positively associated with Y"]
   H2: [If applicable]

3. Dependent variable. Describe the key dependent variable(s) specifying
   how they will be measured.
   [Variable name; scale; operationalization; reference period]

4. Conditions. How many and which conditions will participants be assigned to?
   [Observational: N/A | Experimental: T1 = [description], T2 = [description]]

5. Analyses. Specify exactly which analyses you will conduct to evaluate
   the main question/hypothesis.
   [Model type; control variables; SE type; exact test for each hypothesis]

6. Outliers and exclusions. Describe exactly how outliers will be defined
   and handled, and your exclusion criteria.
   [All inclusion/exclusion criteria; outlier definition; missing data handling]

7. Sample size. How many observations will be collected or what will
   determine sample size?
   [N = X from power analysis: 80% power to detect d = Y at α = .05]
   [OR: secondary data analysis; PSID 2022, N = X]

8. Other. Anything else you would like to pre-register?
   [Exploratory analyses; planned subgroup analyses; robustness checks]

9. Name. Give a title to your preregistration.
   [Preregistration of: Paper Title]
```

---

## OSF Preregistration (Sociology / CSS) — Analysis Plan Detail

### Hypothesis section — before you see any data

```
H1 (main effect):
  Claim: [Variable X] is positively/negatively associated with [Outcome Y]
  among [Population Z].

  Theoretical rationale: [2–4 sentences from theory section]

  Direction: Positive / Negative / Curvilinear [specify shape if non-linear]

  Test: β₁ significantly different from zero in the primary model, in the
  predicted direction (one-tailed p < .05 OR two-tailed p < .05 — specify)

H2 (moderation):
  Claim: The effect of X on Y is [stronger/weaker] for [Group A] vs. [Group B].

  Rationale: [2–4 sentences]

  Direction: Positive interaction (effect larger for Group A)

  Test: β₃ (X × Group interaction) significantly positive in the extended model

H3 (null hypothesis as finding):
  Claim: There is no association between [X] and [Y] controlling for [Z].
  Rationale: [Why null is theoretically expected, not just failure to find]
  Test: β₁ not significantly different from zero; equivalence test (TOST)
  confirms effect < [minimum meaningful effect size]
```

### Analysis plan section — be as specific as possible

```
Primary analysis:
  Model type: [OLS / logistic / panel FE / Cox / MLM / negative binomial]
  Equation:   Y_it = β₀ + β₁X_it + β₂C₁ + β₃C₂ + α_i + ε_it
  SE type:    [Robust (HC3) / Clustered at [level] / Bootstrapped (B=1000)]
  AME: Use marginaleffects::avg_slopes() for discrete predictors and
       logistic models — report as AME, not odds ratios
  Test H1:    β₁ > 0 at p < .05 (two-tailed)
  Test H2:    β₃ ≠ 0 at p < .05 (two-tailed); marginal interaction plotted

Sample restrictions:
  Include: [Age 25–64; employed; U.S.-born; non-institutionalized]
  Exclude: [Missing on outcome (N ≈ ?); extreme outliers (|z| > 4)]

Covariates (justify each):
  - Age, age² : controls for non-linear life course effects on Y
  - Female    : controls for gender gap in Y unrelated to X
  - Race/ethnicity : controls for stratification confounds
  - Education : controls for human capital differences
  - Year FE   : removes secular trends in all variables

Transformations:
  - Income: natural log (after adding $1)
  - All continuous predictors: standardized (mean=0, SD=1) for comparability

Missing data:
  - Listwise deletion as primary (report % missing per variable)
  - Sensitivity: multiple imputation (m=20; mice; methods per variable type)
  - If results differ by method: report both; discuss implications

Multiple comparisons:
  - We test [N] pre-registered hypotheses; [apply Bonferroni correction /
    report BH-FDR q-values / no correction — hypotheses from single theory
    and are not independent]

Exploratory analyses (not pre-specified; labeled "exploratory" in paper):
  - Heterogeneity by race/ethnicity (4-way interaction)
  - Time trend analysis by cohort
  - Alternative operationalization of X ([alternative measure])
```

---

## Secondary Data Preregistration Reference

### Three-Tier Framework

| Access tier | What you've done | Registration option |
|-------------|-----------------|-------------------|
| **Tier 1** | Downloaded; no analysis yet | Full preregistration on OSF |
| **Tier 2** | Checked descriptives / frequencies only | Partial preregistration; note what you've seen |
| **Tier 3** | Run exploratory / confirmatory analyses | Cannot preregister those analyses; label all results exploratory |

### Language Templates

**Full secondary data preregistration (Tier 1)**:
```
Methods section:
"Although this study uses secondary data ([Dataset name, year]), we
preregistered our hypotheses and analysis plan before conducting any
confirmatory analyses (OSF: https://osf.io/[code], registered [date]).
At the time of registration, we had downloaded but not opened the dataset.
We followed the preregistered plan with the following exceptions: (1)
[deviation and reason]. The preregistered specification is reported in
Appendix Table A[X]."
```

**Partial secondary data preregistration (Tier 2)**:
```
"This study uses secondary data ([Dataset]). We preregistered our hypotheses
and analysis plan prior to conducting confirmatory analyses (OSF: https://osf.io/
[code]). We had previously examined descriptive statistics (means, distributions)
but had not tested any directional hypotheses prior to registration."
```

**No preregistration possible (Tier 3)**:
```
"This study uses secondary data and was not preregistered. All results should
be interpreted as exploratory. To guard against inflated Type I error due to
specification searching, we: (1) report exact p-values rather than thresholds;
(2) apply [Bonferroni correction / BH-FDR] to the family of [N] tests;
(3) validate key findings in a held-out sample ([Year] wave, N = [X])."
```

---

## Reporting Preregistration in the Paper

### Methods section citation (preregistered)
```
"This study was preregistered at the Open Science Framework prior to
[data collection / confirmatory analysis] (https://osf.io/[code],
registered [date]). The preregistered analysis plan specified [brief
summary of model and hypotheses]. We followed the preregistered plan
with the following exceptions: (1) [deviation 1, with rationale]; (2)
[deviation 2, with rationale]. The preregistered specification is
reported in Appendix Table A[X] and yields [consistent / slightly
different] results."
```

### Methods section note (not preregistered)
```
[NHB/NCS requirement]: "This study was not preregistered."

[More informative version]:
"This study was not preregistered. Accordingly, all results should be
interpreted as exploratory and treated as hypothesis-generating for
future confirmatory research."
```

### Reporting deviations template
```
"Our preregistered analysis plan specified [X — e.g., OLS regression
with robust SEs]. We deviate from this plan in the following ways:
(1) We added [covariate] not included in the preregistration because
    [reviewers in a prior round flagged it / we discovered it was a
    strong confounder during data cleaning]. The preregistered
    specification (Table A1, Column 1) yields [consistent] results.
(2) We changed [specification] because [data structure / ethical
    concern not anticipated at preregistration]. The original
    specification is in Appendix Table A[X]."
```

---

## Power Analysis Reference (for preregistration)

### R code for common designs

```r
library(pwr)

# Independent samples t-test (d = Cohen's d)
pwr.t.test(d = 0.20, sig.level = 0.05, power = 0.80, type = "two.sample")

# OLS regression — partial R² for focal predictor
# f² = R²_full - R²_restricted / (1 - R²_full)
pwr.f2.test(u = 1,           # numerator df = number of predictors tested
            f2 = 0.02,       # f² for small-medium effect
            sig.level = 0.05, power = 0.80)

# Chi-square test of independence
pwr.chisq.test(w = 0.10,     # w = small effect
               df = 3,
               sig.level = 0.05, power = 0.80)

# Logistic regression (use simr or manual simulation)
library(simr)
# [see scholar-design for full simr workflow]

# Minimum detectable effect size given N
pwr.t.test(n = 500, sig.level = 0.05, power = 0.80, type = "two.sample")$d
```

### Common effect size benchmarks (social science)

| Effect size type | Small | Medium | Large | Notes |
|-----------------|-------|--------|-------|-------|
| Cohen's d | 0.20 | 0.50 | 0.80 | Mean difference / SD |
| f² (R² increment) | 0.02 | 0.15 | 0.35 | For regression |
| Cohen's w (χ²) | 0.10 | 0.30 | 0.50 | Contingency tables |
| r (correlation) | 0.10 | 0.30 | 0.50 | Bivariate |
| Odds Ratio | 1.5 | 2.5 | 4.0 | Logistic models |

**Social science note**: Effects in large-N observational studies are often
smaller than classical benchmarks; consider domain-specific priors from
meta-analyses rather than generic small/medium/large labels.

---

## Common Preregistration Mistakes

1. **Too vague**: "We will regress Y on X with controls" is insufficient.
   Specify exact controls, SE type, and transformation.

2. **No direction**: "X is associated with Y" is not a preregistered hypothesis.
   "X is positively associated with Y" is.

3. **Forgetting exploratory analyses**: Not listing any exploratory analyses invites
   accusations of fishing when you present post-hoc results.

4. **Registering after looking at data**: Even accidentally checking outcome
   distributions after data access can compromise the preregistration.
   Solution: register before downloading, or use Tier 2 language.

5. **Not documenting deviations**: Every deviation must be noted in the paper
   and the preregistered version reported in appendix.

6. **Over-constraining exploratory subgroups**: Preregistering exploratory
   subgroup analyses as "confirmatory" leaves you explaining "failures."

7. **Forgetting to embargo**: If data aren't ready for public release, set
   an embargo on the OSF registration (up to 4 years).

8. **Missing software and seed**: Preregistration is incomplete without exact
   software version and random seed(s).
