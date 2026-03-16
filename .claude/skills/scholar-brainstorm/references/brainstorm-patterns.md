# Brainstorm Patterns: Data-Driven Research Question Generation

## Contents

1. Material Type Detection
2. Variable Taxonomy
3. Combinatorial RQ Generation Strategies
4. RQ Formula Library (adapted for data-first workflow)
5. Cross-Domain Puzzle Templates
6. Variable Pairing Heuristics
7. Common Pitfalls in Data-First RQ Development
8. Quick Empirical Signal Test Protocols (DATA mode)

## 1) Material Type Detection

Identify the input material type to determine the extraction strategy:

| Material Type | Detection Signals | Extraction Focus |
|---------------|-------------------|------------------|
| **Codebook** | Variable names, value labels, skip patterns, universe descriptions, question text references | Variable inventory, measurement scales, skip logic (reveals subpopulations), derived variables |
| **Survey questionnaire** | Question stems, response options, section headers, routing instructions | Constructs measured, question ordering (reveals theoretical model), filter questions (reveal target populations) |
| **Raw data file** (CSV/Stata/R/SPSS) | Column headers, data types, value distributions | Variable names, missingness patterns, sample size, unit of analysis, panel structure |
| **Data dictionary** | Variable name + label + type + values in tabular format | Same as codebook but typically more concise |
| **Study documentation** (user guide, methodology report) | Sampling design, field procedures, weighting, response rates | Population, temporal coverage, geographic scope, known limitations |
| **Multiple files** | Mix of above | Cross-reference: questionnaire constructs → codebook variables → data columns |

## 2) Variable Taxonomy

Classify every extracted variable into one of these analytic roles:

| Role | Description | Examples | RQ Position |
|------|-------------|----------|-------------|
| **Outcome (Y)** | States, behaviors, or events to be explained | Income, health status, attitudes, educational attainment, mortality, fertility | Dependent variable |
| **Predictor (X)** | Conditions, exposures, or statuses hypothesized to affect Y | Immigration status, neighborhood type, policy exposure, social media use | Independent variable |
| **Mechanism (M)** | Intermediate processes linking X → Y | Social networks, stress, information access, identity, aspirations | Mediator |
| **Moderator (W)** | Conditions that alter the X → Y relationship | Gender, race, class, cohort, region, institutional context | Interaction term |
| **Confounder (C)** | Variables that cause both X and Y | Age, education, parental SES, selection into treatment | Control variable |
| **Context (Z)** | Higher-level conditions (geographic, temporal, institutional) | State, country, time period, policy regime, labor market conditions | Level-2 variable |
| **Demographic (D)** | Background characteristics | Age, sex, race/ethnicity, marital status, nativity | Stratification / subgroup |

**Assignment heuristics:**
- Variables measured BEFORE the focal time period → likely X, C, or D
- Variables measured AT the focal time period → could be Y, M, or W
- Variables that are states (income, health) → likely Y
- Variables that are conditions/exposures → likely X
- Variables that are attitudes/perceptions → could be M or Y depending on RQ
- Geographic/institutional identifiers → likely Z
- Variables with clear temporal ordering help establish X → M → Y chains

## 3) Combinatorial RQ Generation Strategies

### Strategy A: Y-First (Outcome-Driven)
1. Identify the most interesting/policy-relevant outcome variables (Y)
2. For each Y, scan for plausible predictors (X) that have theoretical grounding
3. Look for mechanism variables (M) that could explain the X→Y link
4. Check for moderators (W) that create heterogeneity

### Strategy B: X-First (Exposure-Driven)
1. Identify unique or underexploited predictor variables (X) — especially those novel to the dataset
2. For each X, brainstorm what outcomes (Y) it might affect
3. Map mechanisms and moderators

### Strategy C: Gap-Driven (Missing Link)
1. Identify pairs of variables that are theoretically related but rarely studied together
2. Look for mechanism variables that could fill a known theoretical gap
3. Prioritize variables that enable causal identification (panel structure, natural experiments, instruments)

### Strategy D: Heterogeneity-Driven (Subgroup Variation)
1. Identify demographic/contextual moderators (W, Z)
2. For established X→Y relationships, ask: "Does this relationship vary by [W]?"
3. Prioritize intersectional combinations (race × gender, class × nativity)

### Strategy E: Temporal/Change-Driven
1. If panel or repeated cross-section: identify variables measured at multiple time points
2. Ask: "How has [X→Y] changed over time? What explains the change?"
3. Look for cohort effects, period effects, or policy discontinuities

### Strategy F: Methodological Innovation
1. Identify variables that enable a stronger identification strategy than prior work
2. Look for natural experiments, instruments, discontinuities in the data
3. Ask: "Can I answer an old question with better causal leverage using this data?"

## 4) RQ Formula Library (Data-First)

Adapted from scholar-idea patterns for bottom-up, variable-driven generation:

- **Direct-effect form:**
  `Using [DATASET], what is the association between [X variable] and [Y variable] among [population defined by data], net of [available confounders C]?`

- **Mechanism form:**
  `Does [M variable] mediate the relationship between [X] and [Y] in [DATASET]? What proportion of the total effect operates through this pathway?`

- **Heterogeneity form:**
  `Does the [X]→[Y] relationship vary by [W: race/gender/class/cohort/region] in [DATASET]? What explains this variation?`

- **Temporal form:**
  `How has the [X]→[Y] relationship changed across [waves/years] in [DATASET], and what structural factors account for this change?`

- **Comparative form:**
  `How does the [X]→[Y] relationship differ between [Group A] and [Group B] in [DATASET], and do [M variables] explain this gap?`

- **Decomposition form:**
  `How much of the [Group A]–[Group B] gap in [Y] is attributable to differences in [X1, X2, X3] vs. differences in returns to those characteristics?`

- **Contextual form:**
  `How do [Z: area/institutional-level variables] moderate the [X]→[Y] relationship at the individual level?`

## 5) Cross-Domain Puzzle Templates

When examining data, look for these publishable puzzle structures:

| Puzzle Type | Template | Example |
|-------------|----------|---------|
| **Anomaly** | [X] should predict [Y] based on [theory], but the data shows [unexpected pattern] | Education increases income but NOT life satisfaction in group Z |
| **Divergent trends** | [Y1] and [Y2] should co-move but they diverge after [event/period] | Marriage rates decline but cohabitation doesn't fully compensate |
| **Surprising null** | Despite strong theoretical expectations, [X] has no effect on [Y] for [subgroup] | Neighborhood effects vanish for second-generation immigrants |
| **Reversal** | The [X]→[Y] relationship reverses sign for [subgroup W] | Returns to education are negative for undocumented workers |
| **Mechanism mismatch** | The expected mechanism [M1] doesn't explain [X]→[Y]; instead [M2] does | Discrimination → health operates through vigilance, not material deprivation |
| **Persistence** | [Y] differences persist even after accounting for all available [X, C] | Racial wealth gap persists net of income, education, and inheritance |
| **Emergence** | [Relationship] only appears when examining [subgroup] or [context] that is typically aggregated | Gender pay gap only emerges in specific occupational niches |

## 6) Variable Pairing Heuristics

### High-Potential Pairings
- **Novel X × established Y**: A newly measured exposure predicting a well-studied outcome
- **Established X × novel Y**: A well-studied predictor applied to an understudied outcome
- **Mechanism test**: X and Y are well-established; the dataset uniquely has M
- **Intersectional moderator**: Dataset has both race AND class AND gender for interaction analysis
- **Cross-level**: Dataset links individual variables to area-level context (ZIP, county, state)
- **Longitudinal leverage**: Same variables measured at T1 and T2 enabling within-person/fixed-effects

### Low-Potential Pairings (avoid)
- Two demographic variables (e.g., age and race) with no clear causal direction
- Tautological relationships (e.g., "employment" predicting "income")
- Variables with >70% missing data in the target subpopulation
- Cross-sectional relationships that require panel data for identification
- Highly correlated variables (r > 0.8) that are essentially measuring the same construct

## 7) Common Pitfalls in Data-First RQ Development

| Pitfall | Description | Fix |
|---------|-------------|-----|
| **Fishing expedition** | Testing every possible X→Y pair without theoretical motivation | Ground each RQ in a specific theoretical puzzle or debate |
| **Data-driven HARKing** | Exploring data, finding a result, then writing a theory to fit | Pre-commit to RQs before analysis; flag exploratory findings honestly |
| **Measurement conflation** | Treating a proxy as the construct itself | Name what the variable actually measures vs. what you claim it captures |
| **Causal overreach** | Making causal claims from cross-sectional observational data | Match language to design: "associated with" for cross-sectional, "effect of" only for credible quasi-experiments |
| **Kitchen-sink models** | Including every available control without theoretical justification | Use DAGs to decide what to control and what not to (collider bias) |
| **Subgroup cherry-picking** | Testing 20 subgroups and reporting the 2 that are significant | Pre-specify subgroups; adjust for multiple comparisons; report all tests |
| **Ignoring selection** | Failing to account for who is in the sample and why | Map the selection process: who responds? who attrites? who is in the universe? |

## 8) Quick Empirical Signal Test Protocols (DATA mode)

When the user provides actual data files (.csv, .dta, .sav, .rds, .xlsx, .tsv, .parquet), run quick bivariate tests on each candidate RQ to check for empirical signal. These tests inform the ranking but are NOT final analyses.

### Test Selection Matrix

Select the appropriate test based on the Y-type × X-type combination for each candidate RQ:

| Y type | X type | R Test | Effect Size | R Code Snippet |
|--------|--------|--------|-------------|----------------|
| Continuous | Continuous | `cor.test(df$Y, df$X)` | Pearson r | `cor.test(df$Y, df$X, use="complete.obs")` |
| Continuous | Binary | `t.test(Y ~ X, data=df)` | Cohen's d | `effectsize::cohens_d(Y ~ X, data=df)` |
| Continuous | Categorical (3+) | `aov(Y ~ X, data=df)` | η² (eta-squared) | `effectsize::eta_squared(aov(Y ~ factor(X), data=df))` |
| Binary | Continuous | `glm(Y ~ X, family=binomial, data=df)` | AME | `marginaleffects::avg_slopes(fit, variables="X")` |
| Binary | Binary | `chisq.test(table(df$Y, df$X))` | Cramér's V | `effectsize::cramers_v(table(df$Y, df$X))` |
| Binary | Categorical (3+) | `chisq.test(table(df$Y, df$X))` | Cramér's V | `effectsize::cramers_v(table(df$Y, df$X))` |
| Count | Continuous | `glm(Y ~ X, family=poisson, data=df)` | IRR | `exp(coef(fit)["X"])` |
| Count | Categorical | `glm(Y ~ factor(X), family=poisson, data=df)` | IRR | `exp(coef(fit))` |
| Any | Mechanism M | Correlation chain | r(X,M) + r(M,Y) | `cor(df[,c("X","M","Y")], use="complete.obs")` |
| Any | Moderator W | Interaction term | p(X:W) | `summary(lm(Y ~ X * W, data=df))` or `summary(glm(Y ~ X * W, family=binomial, data=df))` |

### Effect Size Thresholds (Cohen's Conventions)

| Effect Size | Small | Medium | Large |
|-------------|-------|--------|-------|
| r (Pearson) | 0.10 | 0.30 | 0.50 |
| Cohen's d | 0.20 | 0.50 | 0.80 |
| η² (eta-squared) | 0.01 | 0.06 | 0.14 |
| AME (average marginal effect) | 0.02 | 0.05 | 0.10 |
| Cramér's V (df=1) | 0.10 | 0.30 | 0.50 |
| Cramér's V (df=2+) | 0.07 | 0.21 | 0.35 |
| IRR (incidence rate ratio) | 1.1 / 0.9 | 1.5 / 0.67 | 2.0 / 0.50 |
| log(IRR) | 0.10 | 0.30 | 0.50 |

### Signal Rating Criteria

| Rating | Criteria | Interpretation |
|--------|----------|----------------|
| **STRONG** | p < 0.01 AND medium+ effect size | Clear bivariate association; likely to survive controls |
| **MODERATE** | p < 0.05 AND small+ effect size | Detectable association; may weaken with controls |
| **MECHANISM PLAUSIBLE** | For M-chain tests: both r(X,M) and r(M,Y) significant at p < 0.10 | Mediation pathway exists bivariately |
| **MODERATION DETECTED** | Interaction term X:W significant at p < 0.10 | Heterogeneous effects by subgroup |
| **WEAK** | p < 0.10 but trivially small effect size | Barely detectable; likely underpowered or substantively meaningless |
| **NULL** | p ≥ 0.10 | No bivariate association detected |
| **UNTESTABLE** | Key variable missing, constant, or error in test | Cannot evaluate empirically with available data |

### Signal Scoring for Step 6 Ranking (DATA mode only)

| Signal Rating | Score (0-5) |
|---------------|-------------|
| STRONG | 5 |
| MECHANISM PLAUSIBLE | 4 |
| MODERATE | 3 |
| MODERATION DETECTED | 3 |
| UNTESTABLE | 2 |
| WEAK | 1 |
| NULL | 0 |

### Interpretation Guardrails

**CRITICAL: These are bivariate screening tests, not final analyses. Adhere to these 6 rules:**

1. **Bivariate ≠ causal.** A strong bivariate signal may be entirely confounded. A NULL signal may emerge as significant after adjusting for suppressors. Do not use signal results to make causal claims.

2. **Multiple testing.** Running 15-20 tests at α=0.05 produces ~1 expected false positive. Do not over-interpret individual p-values. Focus on effect sizes and patterns across related RQs.

3. **NULL ≠ uninteresting.** A null bivariate result may reflect (a) underpowered test with small N, (b) nonlinear or threshold effects, (c) context-dependent relationship that only appears in subgroups, or (d) a genuinely important null finding. Do not drop RQs solely for NULL signal.

4. **Effect size > p-value.** For ranking purposes, prioritize effect size magnitude over statistical significance. A large effect with p=0.08 (N=200) is more promising than a tiny effect with p<0.001 (N=50,000).

5. **Missing data caution.** Compare N in the signal table against total dataset N. Large drop-off (>30%) suggests systematic missingness that may bias the bivariate test. Flag in the signal table.

6. **LOCAL_MODE limitation.** When running in LOCAL_MODE (sensitive data), the R script runs via `Rscript -e` and only aggregated output enters context. Data cannot be visually inspected for outliers, coding errors, or distributional anomalies that might produce misleading signal results.

### R Package Requirements

**Minimum (always available):**
- `tidyverse` (includes dplyr, ggplot2, readr, tidyr, purrr)
- `haven` (for .dta, .sav)
- `readxl` (for .xlsx, .xls)

**Recommended (for effect sizes and AMEs):**
- `effectsize` — Cohen's d, eta_squared, cramers_v, and other standardized effect sizes
- `marginaleffects` — average marginal effects (AME) for logistic and other GLMs
- `skimr` — variable profiling in Step 2b-DATA

**Install check** (prepend to R script if needed):
```r
required_pkgs <- c("tidyverse", "haven", "readxl", "effectsize", "marginaleffects", "skimr")
missing <- required_pkgs[!sapply(required_pkgs, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) {
  install.packages(missing, repos = "https://cloud.r-project.org")
}
```
