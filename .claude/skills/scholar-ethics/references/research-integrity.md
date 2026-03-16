# Research Integrity: QRPs, P-Hacking, HARKing, and Authenticity

Reference guide for `scholar-ethics` MODE 3.

---

## 1. Questionable Research Practices (QRP) Taxonomy

Based on Simmons, Nelson & Simonsohn (2011) *Psychological Science* and Wicherts et al. (2016) *Frontiers in Psychology*.

### Category A: Data Collection QRPs

| QRP | Description | Detection | Remedy |
|-----|-------------|-----------|--------|
| **Optional stopping** | Collecting data, checking significance, stopping when p < .05 | Underpowered studies that just clear .05; N not power-justified | Pre-specify stopping rule; sequential testing corrections (alpha-spending) |
| **Selective exclusion** | Removing participants after seeing results | Exclusion criteria not in pre-registration | Pre-specify all exclusion criteria; report excluded N with reasons |
| **Post-hoc design change** | Altering study design after seeing data | Multiple "study 1 / study 2" with inconsistent designs | Document design changes openly; label later additions as exploratory |
| **Undisclosed attrition** | Not reporting dropout patterns | N in analysis ≠ N recruited without explanation | Full CONSORT-style participant flow diagram |

### Category B: Analysis QRPs

| QRP | Description | Detection | Remedy |
|-----|-------------|-----------|--------|
| **Specification searching** | Trying many model specs; reporting only significant one | Unusual sensitivity to minor spec changes | Multiverse analysis; report full spec curve |
| **Covariate fishing** | Adding/removing controls until p < .05 | Covariates change substantially across reported models | Justify all controls theoretically before analysis |
| **Outcome switching** | Measuring many DVs; reporting only significant | Protocol deviates from registration | Report all DVs; use FDR correction |
| **Transformation p-hacking** | Trying log, sqrt, winsorize until p < .05 | Unexplained transformations | Pre-specify; justify by distribution shape only |
| **Subgroup fishing** | Testing many subgroups; reporting only significant | Interaction tests added post-hoc | Pre-specify subgroups; adjust for multiple comparisons |
| **Outlier-based manipulation** | Excluding outliers only when they hurt significance | Outlier treatment changes significance | Pre-specify outlier criteria; report results both ways |

### Category C: Reporting QRPs

| QRP | Description | Detection | Remedy |
|-----|-------------|-----------|--------|
| **HARKing** | Presenting post-hoc hypotheses as a priori | Hypotheses match results suspiciously perfectly | Label post-hoc findings as exploratory |
| **Selective reporting** | Omitting non-significant outcomes | Registered outcomes not in paper | Include null results table in appendix |
| **Misleading significance language** | "Approaching significance" for p = .07 | Non-standard significance language | Report exact p-values; use "not significant" |
| **Insufficient precision** | No CIs, just p-values | Results section lacks effect sizes | Report β + SE + 95% CI + p + effect size |
| **Undisclosed data collection continuation** | Collecting more data after first analysis | Unusual N for a pre-registered study | Disclose all data collection phases |

---

## 2. P-Hacking: Diagnosis and Tests

### The p-curve (Simonsohn, Nelson & Simmons 2014)

A genuine effect produces a right-skewed p-curve (many p < .01, fewer .01–.05). A p-hacked literature produces a flat or left-skewed p-curve (p-values cluster just below .05).

**R code — p-curve analysis of your own results:**
```r
# Install pcurve from https://www.p-curve.com/
# Or use the web app at p-curve.com

# Manual check: extract all p-values from your paper
p_values <- c(0.032, 0.048, 0.019, 0.041, 0.008, 0.003, 0.067)

# Right-skewed (good): most p-values near 0, few near .05
# Flat or left-skewed (concerning): concentration near .05

hist(p_values[p_values < 0.05],
     breaks = 5,
     main = "P-curve of significant results",
     xlab = "p-value",
     col = "steelblue")
```

### Z-curve (Bartoš & Schimmack 2022)
Estimates replication rate and expected discovery rate from the distribution of z-values.

```r
install.packages("zcurve")
library(zcurve)

# Provide z-statistics for all tested hypotheses
z_stats <- c(2.1, 2.5, 3.2, 1.8, 2.9, 1.6)
fit <- zcurve(z = z_stats)
summary(fit)
plot(fit)   # ERR (expected replication rate) and EDR (expected discovery rate)
```

### GRIM test (Brown & Heathers 2017)
Checks whether reported means are consistent with reported N for integer-scale data.
- For a Likert scale (1–5) with N = 40, the mean must be a multiple of 1/40 = 0.025
- Mean = 3.33 with N = 40 is impossible (3.33 / 0.025 = 133.2, not integer)

```r
# GRIM test for one mean
grim_test <- function(mean_val, n, scale_min = 1, scale_max = 5) {
  granularity <- 1 / n
  # Check if mean is achievable with this N
  remainder <- (mean_val - scale_min) %% granularity
  abs(remainder) < 1e-10 | abs(remainder - granularity) < 1e-10
}
grim_test(3.33, 40)   # Returns FALSE = impossible mean
grim_test(3.325, 40)  # Returns TRUE = possible
```

---

## 3. HARKing: Detection and Remediation

**HARKing** (Kerr 1998): Hypothesizing After Results are Known — presenting post-hoc findings as predicted in advance.

### Detection signals
- Hypotheses are stated with perfect specificity that matches the exact result (direction, magnitude, interaction pattern)
- "As expected..." language for results that were not in the pre-registration
- Theoretical justification for interaction terms added only after the interaction was significant
- Results section findings have no corresponding hypothesis in the theory section

### Remediation options

| Situation | How to handle ethically |
|-----------|------------------------|
| Pre-analysis plan existed; result was predicted | State clearly: "Consistent with H2, we find..." |
| No pre-analysis plan; hypothesis is post-hoc | Label explicitly: "In an exploratory analysis, we find an unexpected positive association between X and Y. This pattern suggests [mechanism], which future pre-registered studies should test." |
| Mixed: some predictions confirmed, some new | Separate confirmatory and exploratory findings clearly in Results |
| Reviewer pressure to present as pre-specified | Do not comply; disclose honestly in cover letter to editor |

### Registered Reports as solution
Registered Reports (pre-registered before data collection, in-principle acceptance) are accepted at:
- *Comprehensive Results in Social Psychology*
- *Journal of Experimental Social Psychology*
- *Advances in Methods and Practices in Psychological Science*
- *Nature Human Behaviour* (registered report track)
- Increasingly at *Demography*, *PNAS*, and other top journals

---

## 4. Data Fabrication and Falsification

### Fabrication vs. Falsification
- **Fabrication**: making up data or results entirely
- **Falsification**: manipulating research materials, equipment, or processes; altering or omitting data to produce a misleading record

Both are federal research misconduct under 42 CFR Part 93 (US) and institutional misconduct policies.

### Self-check for data provenance

Run these checks on your own data before submission:

```r
# 1. Check for suspiciously uniform variance across groups
# Real data shows variance heterogeneity; fabricated data may have identical SDs
tapply(data$outcome, data$group, sd)

# 2. Check digit frequency (Benford's law for leading digits in large datasets)
library(benford.analysis)
bfd <- benford(data$continuous_var, number.of.digits = 1)
plot(bfd)
# Genuine data follows Benford distribution; fabricated data often does not

# 3. Check for too-perfect inter-rater reliability
# In real coding, κ rarely exceeds .85 without anchor training
irr_check <- function(kappa_value) {
  if (kappa_value == 1.0) warning("Perfect agreement — verify coding files are truly independent")
  if (kappa_value > 0.95) message("Very high agreement — document coding process carefully")
}

# 4. Reproduce descriptives from raw data
library(dplyr)
verification <- data |>
  group_by(group_var) |>
  summarise(
    n = n(),
    mean_outcome = mean(outcome, na.rm = TRUE),
    sd_outcome = sd(outcome, na.rm = TRUE)
  )
# Compare to Table 1 in manuscript — must match exactly
```

### After detecting an error in already-published data

1. Notify co-authors immediately
2. Assess severity: does it change the substantive conclusions?
3. If conclusions unchanged: submit a **Correction** to the journal
4. If conclusions change: submit a **Retraction** (partial or full)
5. Document everything in writing before contacting the journal

**Retraction Watch** (retractionwatch.com) tracks retractions and corrections; proactive correction is far better than post-publication discovery.

---

## 5. Misinterpretation of Results: Reference Guide

### Causal language in observational studies

**Prohibited without identification strategy:**
- "X causes Y"
- "X leads to Y"
- "X increases Y"
- "The effect of X on Y"

**Appropriate hedged language:**
- "X is associated with Y"
- "X predicts Y" (if using regression)
- "X is positively correlated with Y"
- "Models suggest a positive relationship between X and Y"

**Appropriate causal language** (only after establishing identification):
- "Using a difference-in-differences design, we estimate the causal effect of X on Y..."
- "Exploiting the quasi-random variation in X induced by Z (instrumental variable), we find..."

### Multiple comparisons corrections

| Correction method | When to use | R function |
|-------------------|-------------|-----------|
| **Bonferroni** | Very conservative; few comparisons; strong FWER control | `p.adjust(p_values, method = "bonferroni")` |
| **Benjamini-Hochberg (BH/FDR)** | Many comparisons; balance power and Type I error | `p.adjust(p_values, method = "BH")` |
| **Holm** | Stepdown; slightly more powerful than Bonferroni | `p.adjust(p_values, method = "holm")` |
| **None** | Single pre-specified primary outcome; clearly labeled | Report unadjusted, note it is a single test |

```r
# Apply FDR correction across all subgroup tests
p_raw <- c(0.04, 0.001, 0.08, 0.03, 0.12, 0.002, 0.045)
p_adjusted <- p.adjust(p_raw, method = "BH")
data.frame(raw = p_raw, adjusted = p_adjusted, significant = p_adjusted < 0.05)
```

### Effect size standards

| Statistic | Small | Medium | Large | Report with |
|-----------|-------|--------|-------|-------------|
| Cohen's d | 0.2 | 0.5 | 0.8 | 95% CI |
| Pearson r | 0.1 | 0.3 | 0.5 | 95% CI |
| Odds ratio | 1.5 | 2.5 | 4.0 | 95% CI |
| η² (ANOVA) | 0.01 | 0.06 | 0.14 | 95% CI |
| AME (logit) | Context-dependent | — | — | 95% CI + baseline rate |
| Variance explained (R²) | Interpret in context | — | — | Δ R² for added predictors |

---

## 6. Pre-Registration and Open Science as Integrity Safeguards

Pre-registration reduces QRPs by separating confirmatory from exploratory research.

**Where to pre-register:**
- **OSF (Open Science Framework)**: osf.io — most common in sociology; free; timestamps registration
- **AsPredicted.org**: quick 8-question template; automatically dated
- **PROSPERO**: for systematic reviews and meta-analyses
- **ClinicalTrials.gov**: for RCTs involving medical interventions
- **AEA RCT Registry**: for economic field experiments

**What to pre-register (minimum):**
1. Research question and hypotheses (directional)
2. Data source and collection method
3. Primary outcome variable(s)
4. Primary analysis model (covariates, sample restrictions, estimation method)
5. Subgroup analyses to be conducted
6. Stopping rule (for sequential designs)

**Registered Report format** (in-principle acceptance before data collection):
- Pre-register Stage 1 report (lit review + hypotheses + methods)
- Receive in-principle acceptance from journal
- Collect data and run pre-registered analyses
- Submit Stage 2 report (results + discussion)
- Paper accepted regardless of whether results are significant

---

## 7. Post-Submission Integrity Issues

### Responding to data integrity questions from reviewers or editors

If a reviewer or editor raises an integrity concern:
1. Do NOT dismiss — treat as a legitimate quality check
2. Run the cross-check protocol (Step 3.3 in SKILL.md)
3. Share relevant verification (re-run scripts, data provenance documentation)
4. If an error is found: disclose transparently, assess impact on conclusions, propose correction
5. Response language: "We thank the reviewer for the careful read. We verified our results by [X]. The reported figures are confirmed / We discovered [issue] and have [corrected / noted impact on conclusions]."

### Key institutional contacts for research integrity
- **Research Integrity Officer** (RIO) at your institution: first contact for any misconduct concern
- **ORI (Office of Research Integrity)** — US federal oversight for PHS-funded research: ori.hhs.gov
- **COPE (Committee on Publication Ethics)**: guidelines for editors and authors: publicationethics.org
- **Retraction Watch**: retractionwatch.com
