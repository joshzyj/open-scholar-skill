---
name: scholar-design
description: Plan a rigorous research design, run power analysis, specify variables, select an analytic strategy, design computational studies (NLP/ML/networks/ABM), write a pre-analysis plan, and draft the Data and Methods section for social science research. Produces a design blueprint saved to disk. Use after /scholar-hypothesis and before /scholar-data and /scholar-analyze.
tools: Read, WebSearch, Write, Bash
argument-hint: "[quant|qual|mixed|experiment|power|methods-section|pap|computational|NLP|ML|network|ABM] [research question] [optional: data source, design type, journal target]"
user-invocable: true
---

# Scholar Research Design

You are an expert methodologist in quantitative and qualitative social science. Help the user plan a rigorous, publishable study and produce a complete design blueprint — including power analysis, variable specification, analytic strategy, robustness plan, optional pre-analysis plan (PAP), and a draft Data and Methods section — meeting ASR, AJS, Demography, or Nature journal standards.

## Arguments

The user has provided: `$ARGUMENTS`

Parse to determine:
1. **Claim type**: Descriptive / causal / predictive / interpretive
2. **Design**: Observational (cross-sectional, panel, DiD, RD, IV, matching) / Experimental (RCT, survey experiment, conjoint) / Qualitative / Mixed
3. **Data availability**: Existing dataset name, or new primary collection needed
4. **Journal target**: ASR / AJS / Demography / Science Advances / NHB / NCS (infer from topic if unstated)

---

## Dispatch Table

Route to the relevant steps based on arguments. Run all applicable steps; always run **Step 11 (Internal Review Panel)** before ending with **Save Output** — except for narrow single-step requests (`power`, `methods-section`, `pap` alone), where Step 11 is optional.

| Keyword(s) in arguments | Steps to run |
|------------------------|-------------|
| `quant`, `quantitative`, `regression`, `survey data`, `panel`, `observational` | Steps 0 → 1 → Causal Gate → 3 → 4 → 5 → 6 → 7 → **11** |
| `causal`, `DiD`, `FE`, `RD`, `IV`, `matching`, `natural experiment`, `DAG` | Steps 0 → 1 → **Causal Gate** (invoke /scholar-causal) → 3 → 5 → 6 → 7 → **11** |
| `qual`, `qualitative`, `interview`, `ethnography`, `case study` | Steps 0 → 1 → 4 (qual path) → 7 (qual template) → **11** |
| `mixed`, `mixed-methods`, `multi-method` | All steps; flag integration point in Step 7; run **11** |
| `experiment`, `RCT`, `vignette`, `conjoint`, `list experiment` | Steps 0 → 1 → 2 (experimental) → 3 (power) → 5 → 7 → **11** |
| `cluster RCT`, `cluster randomized`, `group randomized` | Steps 0 → 1 → 2d (cluster RCT) → 3e (cluster power) → 5 → 7 → **11** |
| `audit`, `correspondence`, `audit study`, `resume audit`, `field experiment discrimination` | Steps 0 → 1 → 2e (audit design) → 3f (audit power) → 5 → 7 → **11** |
| `stepped-wedge`, `stepped wedge`, `sequential rollout` | Steps 0 → 1 → 2f (stepped-wedge) → 3g (SW power) → 5 → 7 → **11** |
| `SMART`, `adaptive intervention`, `DTR`, `dynamic treatment regime` | Steps 0 → 1 → 2g (SMART) → 3h (SMART power) → 5 → 7 → **11** |
| `Bayesian`, `Bayesian design`, `prior elicitation`, `assurance` | Steps 0 → 1 → **Step 10** (Bayesian Design) → 7 → **11** |
| `power`, `sample size`, `MDES`, `minimum detectable` | Step 2 (power only); Step 11 optional |
| `methods section`, `write methods`, `data section` | Step 7 (write directly); Step 11 optional |
| `pap`, `pre-analysis plan`, `preregistration`, `OSF` | Step 6 (PAP only); Step 11 optional |
| `computational`, `NLP`, `text`, `ML`, `machine learning`, `network`, `ABM`, `simulation`, `corpus`, `annotation`, `topic model`, `classifier` | Steps 0 → 1 → **Step 9** (Computational Design) → 7 (NCS/SA template) → **11** |

---

## Step 0: Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p ${OUTPUT_ROOT}/design ${OUTPUT_ROOT}/logs
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p ${OUTPUT_ROOT}/logs
SKILL_NAME="scholar-design"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ -f "$LOG_FILE" ]; then
  CTR=2; while [ -f "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md" ]; do CTR=$((CTR+1)); done
  LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}-${CTR}.md"
fi
cat > "$LOG_FILE" << LOGHEADER
# Process Log: /${SKILL_NAME}
- **Date**: ${LOG_DATE}
- **Time started**: $(date +%H:%M:%S)
- **Arguments**: [raw arguments]
- **Working Directory**: $(pwd)

## Steps

| # | Timestamp | Step | Action | Output | Status |
|---|-----------|------|--------|--------|--------|
LOGHEADER
echo "Process log initialized: $LOG_FILE"
```

**After EVERY numbered step**, append a row by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-design"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

Confirm with user:
- RQ and hypotheses (from /scholar-hypothesis or /scholar-lit-review-hypothesis)
- Any data constraints (available dataset, budget, timeline)
- Target journal (shapes method expectations and word budget)

---

## Step 1: Design Selection Decision Tree

Recommend the strongest defensible design given the claim and available data:

| Goal | Data structure | Treatment assignment | Recommended design | Journal fit |
|------|---------------|---------------------|--------------------|-------------|
| Causal effect of discrete X | Panel, repeated measures | Natural variation | Two-way FE (unit + time) | ASR, AJS, Demography |
| Causal effect of policy | Panel, staggered adoption | Policy rollout | Staggered DiD (Callaway-Sant'Anna) | ASR, Demography |
| Causal effect near threshold | Cross-sectional or panel | Rule-based cutoff | RD (sharp or fuzzy) | ASR, AJS, Science Advances |
| Causal effect with instrument | Cross-sectional or panel | Exogenous IV | 2SLS / IV | AJS, Demography |
| Causal effect of treatment | RCT, field or lab | Random | OLS / ATE with Lin estimator | Science Advances, NHB |
| Causal effect, clustered units | Cluster RCT (schools, clinics) | Random by cluster | GEE / multilevel with ICC adjustment | Science Advances, NHB, Demography |
| Discrimination / disparate treatment | Audit / correspondence study | Matched-pair randomization | Within-pair analysis / conditional logit | ASR, AJS, Science Advances |
| Causal effect, sequential rollout | Stepped-wedge trial | Phased cluster crossover | Mixed model with period + exposure effects | Science Advances, NHB |
| Adaptive intervention optimization | SMART design | Sequential random assignment | DTR estimation / Q-learning | NHB, Science Advances |
| Causal effect, survey setting | Survey experiment | Randomized vignette/conjoint | AMCE / OLS clustered | ASR, AJS, NHB |
| Descriptive (distribution, trend) | Cross-section / panel | N/A | OLS + decomposition | Demography, AJS |
| Mechanism/process | Qualitative, N < 60 | N/A | In-depth interviews / ethnography | AJS, ASR (mixed) |
| Large-scale classification | Text or digital data | N/A | ML / NLP (→ /scholar-compute) | NCS, Science Advances |
| Prediction / profiling | Survey or admin | N/A | Regularized regression / RF | NCS, Science Advances |

**Causal gate**: If the claim requires causal inference (DiD, FE, RD, IV, matching, mediation, natural experiment), invoke `/scholar-causal` at this point for full DAG construction, strategy deep-dive, and identification argument. Return here after that skill completes.

---

## Step 2: Experimental Design Module

Run this step when the design involves randomization (RCT, survey experiment, conjoint, list experiment).

### 2a. Randomized Controlled Trial (RCT)

**Core requirements:**
- Random assignment to conditions (document procedure: computer-generated, block randomization by strata)
- Pre-registration on OSF or AEA registry before data collection
- Balance check after randomization (Table 1 comparison)
- Intent-to-treat (ITT) vs. treatment-on-the-treated (TOT) — pre-specify which is primary

**Analysis:**
```r
library(estimatr)
# Lin (2013) estimator: OLS + treatment × demeaned covariates interaction
# More efficient than simple OLS in small RCTs
m_itt <- lm_lin(outcome ~ treatment, covariates = ~ age + female + educ,
                data = df, clusters = block_id)
tidy(m_itt)

# LATE (TOT) when compliance < 100%: use treatment assignment as IV for treatment received
library(AER)
m_iv <- ivreg(outcome ~ treatment_received | treatment_assigned, data = df)
```

### 2b. Survey Experiment (Vignette / Factorial)

See `/scholar-data` WORKFLOW 2 Step 6a for full vignette template and cregg code.

**Analysis:**
```r
library(cregg)
amce <- cj(df, outcome ~ attr1 + attr2 + attr3, id = ~respondent_id, estimate = "amce")
plot(amce) + geom_vline(xintercept = 0, linetype = "dashed") + theme_Publication()

# Subgroup AMCE
amce_by <- cj(df, outcome ~ attr1, id = ~respondent_id,
              by = ~respondent_race, estimate = "amce")
```

**Minimum sample size for conjoint:**
- AMCE of 5 pp (δ = 0.05), 80% power: N ≥ 500 respondents × 5 tasks = 2,500 observations
- Rule of thumb: 1,000 respondents × 5 tasks → ±3% precision for each AMCE

### 2c. List Experiment

See `/scholar-data` WORKFLOW 2 Step 6b for list experiment template.

**Minimum N:** ≥ 500 per arm (1,000 total) for ±5% precision.

### 2d. Cluster Randomized Trial (Cluster RCT)

Run this step when randomization occurs at the group level (schools, clinics, villages, firms) rather than the individual level.

**Core requirements:**
- Randomization unit is the **cluster** (e.g., school, clinic, village), not the individual
- All individuals within a cluster receive the same treatment
- Pre-registration with cluster-level randomization documented
- Balance check at cluster level (Table 1 compares cluster-level means)
- Report intraclass correlation coefficient (ICC) for primary outcome

**Key design parameters:**
```
Cluster RCT Design Specification
─────────────────────────────────────
Randomization unit:  [school / clinic / village / firm / classroom]
Number of clusters:  [K total; K/2 per arm for two-arm trial]
Cluster size:        [m individuals per cluster; fixed / variable]
ICC (ρ):             [estimated from pilot data or literature]
DEFF:                [1 + (m̄ - 1) × ρ]  ← design effect
Stratification:      [block by: region / size / baseline outcome]
Matching:            [matched pairs of clusters on: [variables]]
```

**ICC benchmarks for social science:**

| Domain | Typical ICC (ρ) | Notes |
|--------|----------------|-------|
| Students in schools (academic outcomes) | 0.05–0.25 | Higher for school-level interventions |
| Patients in clinics (health outcomes) | 0.01–0.05 | Lower for individual-level outcomes |
| Workers in firms (earnings) | 0.05–0.15 | Varies by firm size |
| Households in neighborhoods | 0.02–0.10 | Spatial clustering |
| Survey respondents in PSUs | 0.01–0.05 | Design effect for complex surveys |

**Analysis strategy — GEE vs. Multilevel:**

```r
# Option 1: GEE (population-averaged effects) — preferred when K ≥ 40
library(geepack)
m_gee <- geeglm(outcome ~ treatment + baseline_covariates,
                 id = cluster_id, data = df,
                 family = gaussian, corstr = "exchangeable")
summary(m_gee)
# Use robust (sandwich) SEs — valid even if correlation structure is misspecified

# Option 2: Multilevel / mixed model — preferred when K < 40 or ICC is of interest
library(lme4)
m_mlm <- lmer(outcome ~ treatment + baseline_covariates + (1 | cluster_id),
              data = df)
# Small-sample correction for few clusters
library(lmerTest)
summary(m_mlm, ddf = "Kenward-Roger")

# Option 3: Cluster-level analysis (aggregate to cluster means) — simplest, valid for any K
cluster_means <- df %>%
  group_by(cluster_id, treatment) %>%
  summarise(mean_outcome = mean(outcome), .groups = "drop")
t.test(mean_outcome ~ treatment, data = cluster_means)

# Compute ICC from fitted model
library(performance)
icc(m_mlm)
```

**Key assumptions and diagnostics:**
- [ ] ICC estimated and reported (use pilot data or literature)
- [ ] Design effect (DEFF) computed: DEFF = 1 + (m̄ - 1) × ρ
- [ ] Minimum clusters: K ≥ 20 total (10 per arm) for GEE; K ≥ 8 for MLM with small-sample corrections
- [ ] Cluster size variation: if CV of cluster sizes > 0.50, use harmonic mean m̃ in DEFF
- [ ] Balance check at cluster level (not individual level)
- [ ] No contamination across clusters (individuals cannot switch clusters)

**Write-up template:**
> "We conducted a cluster randomized trial in which [K] [clusters] were randomly assigned to [treatment description] (K = [X]) or [control description] (K = [Y]). Randomization was stratified by [strata variables] using [procedure]. Each cluster contained an average of [m̄] participants (range: [min]–[max]; total N = [N]). The intraclass correlation for the primary outcome was ρ = [X] (design effect = [DEFF]). We estimated treatment effects using [GEE with exchangeable correlation and robust standard errors / multilevel models with random intercepts for clusters], adjusting for [covariates]. Power analysis (see Step 3e) indicated [X]% power to detect an effect of d = [Y] given the observed ICC."

### 2e. Audit / Correspondence Study Design

Run this step when the study tests for discrimination by sending matched applications (resumes, housing inquiries, loan applications) that differ only on a signal of group membership.

**Core requirements:**
- Matched-pair design: each "audit" sends two (or more) applications to the same target, varying only the demographic signal
- Signal manipulation must be validated (e.g., names signaling race/ethnicity via pre-testing)
- Within-pair randomization of application order and minor attributes
- IRB approval required — address deception of employers/landlords
- Pre-registration strongly recommended

**Design template:**
```
Audit / Correspondence Study Design
─────────────────────────────────────
Domain:              [hiring / housing / lending / healthcare / retail]
Unit of observation: [employer-applicant pair / landlord-inquiry pair]
Treatment signal:    [name signaling race/ethnicity / gender / age / disability / criminal record]
Signal validation:   [pre-test with N = [X] respondents; [Y]% correct classification]
Matched pairs:       [each target receives K = [2/3/4] applications]
Within-pair variation: [randomize: application order, resume template, minor attributes]
Outcome:             [callback (binary) / response (binary) / interview offer / response quality]
Coding protocol:     [who codes responses; double-coding rate; operational definitions]

Templates by domain:
  Resume audit:   [job title, experience level, qualification tier]
  Housing audit:  [inquiry text, stated income, household composition]
  Lending audit:  [loan amount, credit profile, stated purpose]
```

**Signal manipulation — validated name lists:**

| Signal | Common sources | Key citations |
|--------|---------------|---------------|
| Race (Black/White) | Bertrand & Mullainathan (2004) name lists; Gaddis (2017) validated names | Gaddis (2017) |
| Race (Hispanic/White) | Crabtree (2018); Gaddis (2017) | Gaddis (2017) |
| Gender | Clearly gendered first names | — |
| Social class | Name + resume details | Rivera & Tilcsik (2016) |
| Religion | Name signals (e.g., Mohammed, Cohen) | Wallace et al. (2014) |
| Criminal record | "Have you been convicted" checkbox manipulation | Pager (2003) |

**Analysis — within-pair:**

```r
# Primary analysis: within-pair difference (matched-pair design)
# Binary outcome (callback): McNemar's test or conditional logistic regression
library(survival)

# Each pair = one stratum; compare callback rates within pair
m_clogit <- clogit(callback ~ minority + strata(pair_id), data = df)
summary(m_clogit)

# Linear probability model with pair fixed effects (simpler interpretation)
library(fixest)
m_fe <- feols(callback ~ minority | pair_id, data = df, vcov = "hetero")
summary(m_fe)

# Callback rate ratio
tab <- df %>%
  group_by(minority) %>%
  summarise(callback_rate = mean(callback), n = n())
# Discrimination ratio = callback_white / callback_minority

# Subgroup analysis: does discrimination vary by job type, geography, etc.?
m_het <- feols(callback ~ minority * job_sector | pair_id, data = df, vcov = "hetero")

# For multi-arm designs (3+ groups per pair): multinomial or pairwise comparisons
```

**IRB considerations for deception:**
- [ ] Deception justified: no feasible non-deceptive alternative
- [ ] Minimal burden on targets (applications are brief; no in-person time wasted)
- [ ] No individual identifiers collected or published
- [ ] Debriefing plan (if required by IRB): post-study notification to targets
- [ ] Data destruction timeline specified
- [ ] Cite precedent: Bertrand & Mullainathan (2004), Pager (2003), Edelman et al. (2017)

**Key assumptions and diagnostics:**
- [ ] Signal validity: pre-test confirms names/signals are perceived as intended
- [ ] Template equivalence: multiple resume/inquiry templates rotated; no template drives results
- [ ] No contamination: targets do not recognize multiple applications from same study
- [ ] Order effects controlled: randomize which application arrives first
- [ ] Response coding reliability: double-code at least 20% of responses; report κ

**Write-up template:**
> "We conducted a correspondence audit study to measure [racial/gender/etc.] discrimination in [domain]. We sent [N] pairs of [applications/inquiries] to [targets] in [location(s)] between [dates]. Each pair consisted of [two/three] [applications] identical in qualifications but differing in [signal] (manipulated via [name / explicit signal]). Names were drawn from [validated list (Author Year)], pre-tested with [N] respondents ([X]% correct identification). Within each pair, we randomized [application order, resume template, minor details]. Our primary outcome is [callback / positive response], coded by [procedure]. We estimate the effect of [minority status] on [outcome] using [conditional logistic regression / linear probability models with pair fixed effects], with pair-level stratification. [IRB approval: protocol #[X] at [institution]; waiver of informed consent granted because [rationale]]."

### 2f. Stepped-Wedge Design

Run this step when all clusters will eventually receive the intervention but are randomized to different start times (sequential rollout). Common in policy evaluations where withholding treatment from all clusters is not feasible.

**Core requirements:**
- All clusters eventually receive the intervention (crossover from control to treatment)
- Clusters are randomized to the timing of crossover (not whether they receive treatment)
- At least 3 "steps" (time points at which new clusters cross over)
- Repeated measurement at each time point in every cluster

**Design template:**
```
Stepped-Wedge Design Specification
─────────────────────────────────────
Clusters:           [K total clusters]
Steps:              [S steps (sequences); at each step, K/S clusters cross over]
Periods:            [T = S + 1 total measurement periods (including baseline)]
Cluster size:       [m individuals per cluster per period]
Crossover:          [irreversible: once a cluster starts treatment, it stays treated]
Measurement timing: [continuous enrollment / repeated cross-sections / closed cohort]

Design matrix (example with K=6, S=3):
  Period:    1    2    3    4
  Cluster 1: C    T    T    T
  Cluster 2: C    T    T    T
  Cluster 3: C    C    T    T
  Cluster 4: C    C    T    T
  Cluster 5: C    C    C    T
  Cluster 6: C    C    C    T
  (C = control, T = treatment)
```

**Analysis — Hussey & Hughes (2007) model:**

```r
# Standard stepped-wedge analysis: mixed model with period and treatment effects
library(lme4)
library(lmerTest)

# Hussey & Hughes model: Y_ijk = μ + α_j (period FE) + θ X_ij + u_i + e_ijk
# where X_ij = 1 if cluster i is treated at period j
m_sw <- lmer(outcome ~ treatment + factor(period) + (1 | cluster_id),
             data = df)
summary(m_sw, ddf = "Kenward-Roger")

# With exposure time (time since treatment started) — richer model
df <- df %>%
  mutate(exposure_time = ifelse(treatment == 1, period - crossover_period, 0))

m_sw_exposure <- lmer(outcome ~ treatment + exposure_time +
                        factor(period) + (1 | cluster_id),
                      data = df)

# GEE alternative (population-averaged)
library(geepack)
m_sw_gee <- geeglm(outcome ~ treatment + factor(period),
                    id = cluster_id, data = df,
                    family = gaussian, corstr = "exchangeable")

# Permutation test for few clusters (robust to model misspecification)
# Permute treatment sequences across clusters; recompute treatment coefficient
set.seed(42)
n_perm <- 1000
obs_coef <- fixef(m_sw)["treatment"]
perm_coefs <- replicate(n_perm, {
  df$treatment_perm <- sample(df$treatment)  # permute within structure
  coef(lmer(outcome ~ treatment_perm + factor(period) + (1 | cluster_id),
            data = df))["treatment_perm"]
})
p_perm <- mean(abs(perm_coefs) >= abs(obs_coef))
```

**Key assumptions and diagnostics:**
- [ ] Secular trend: period fixed effects capture time trends common to all clusters
- [ ] No anticipation: clusters do not change behavior before their scheduled crossover
- [ ] Immediate treatment effect (or model exposure time explicitly)
- [ ] No carry-over: pre-treatment outcomes are not affected by future treatment status
- [ ] Cluster-period interaction: test whether within-cluster correlation decays over time (use `lmer(... + (1 + period | cluster_id))` if decay is suspected)
- [ ] Minimum: K ≥ 6 clusters, S ≥ 3 steps; fewer clusters → use permutation test

**Write-up template:**
> "We used a stepped-wedge cluster randomized design in which [K] [clusters] were randomized to begin [intervention] at one of [S] time points, with all clusters receiving the intervention by [end date]. At each step, [K/S] clusters crossed over from control to treatment. [Measurement approach: continuous enrollment / repeated cross-sections with [m] individuals per cluster per period / closed cohort]. We estimated the treatment effect using a linear mixed model with fixed effects for period and treatment status and a random intercept for cluster (Hussey and Hughes 2007), with Kenward-Roger degrees of freedom for small-sample correction. [The ICC was ρ = [X]; the within-period cluster-level correlation was [Y].] We [additionally modeled exposure time to capture time-varying treatment effects / confirmed robustness using a permutation test with [1,000] permutations]."

### 2g. SMART (Sequential Multiple Assignment Randomized Trial)

Run this step when the goal is to build and compare adaptive interventions (dynamic treatment regimes, DTRs) — treatment strategies that adapt based on participant response at intermediate time points.

**Core requirements:**
- At least 2 stages of randomization
- At each stage, participants are randomized to different treatment options
- Responders and non-responders at Stage 1 may be re-randomized differently at Stage 2
- The estimand is the mean outcome under each embedded DTR (adaptive strategy), not individual treatment effects
- Pre-registration of all embedded DTRs, response criteria, and primary comparison

**Design template:**
```
SMART Design Specification
─────────────────────────────────────
Stage 1 treatments:    [A1 vs. A2 (e.g., intensive vs. standard)]
Response criterion:    [definition of "responder" at Stage 1; timing of assessment]
Stage 2 (responders):  [continue vs. reduce / maintain vs. augment]
Stage 2 (non-responders): [augment vs. switch / intensify vs. add component]

Embedded DTRs (adaptive strategies):
  DTR 1: Start A1 → if respond: continue A1; if not respond: augment with B1
  DTR 2: Start A1 → if respond: continue A1; if not respond: switch to B2
  DTR 3: Start A2 → if respond: continue A2; if not respond: augment with B1
  DTR 4: Start A2 → if respond: continue A2; if not respond: switch to B2

Primary comparison:    [DTR 1 vs. DTR 3 (does initial treatment matter for non-responders?)]
Primary outcome:       [end-of-study outcome measured at time T]
Response rate (expected): [R = X% based on pilot / literature]
```

**Analysis — DTR estimation:**

```r
# Weighted and replicated estimation for SMART (Murphy 2005; Nahum-Shani et al. 2012)

# Method 1: Inverse probability weighting (IPW) for comparing embedded DTRs
# Each participant is weighted by the inverse of the probability of receiving
# the treatments they received, consistent with each DTR being compared

library(DTRreg)
library(DynTxRegime)

# Q-learning: work backward from Stage 2 to Stage 1
# Stage 2 model (among non-responders only)
q2_model <- lm(final_outcome ~ stage2_treatment * tailoring_var,
               data = df_nonresponders)

# Optimal Stage 2 rule: choose treatment maximizing predicted outcome
df_nonresponders$opt_stage2 <- ifelse(
  predict(q2_model, newdata = mutate(df_nonresponders, stage2_treatment = 1)) >
    predict(q2_model, newdata = mutate(df_nonresponders, stage2_treatment = 0)),
  1, 0
)

# Stage 1 model: regress final outcome (with optimal Stage 2 imputed) on Stage 1 treatment
# For responders: final outcome is observed directly
# For non-responders: use predicted outcome under optimal Stage 2 from Q2
q1_model <- lm(pseudo_outcome ~ stage1_treatment * baseline_var, data = df_all)

# Method 2: Marginal mean comparison of embedded DTRs using replicate-and-weight
# Replicate observations consistent with multiple DTRs; weight by 1/P(assigned treatment)
library(geepack)

# Create replicated dataset: each person appears once per DTR they are consistent with
df_rep <- create_dtr_replicated_data(df, dtrs = list(
  dtr1 = c("A1", "B1"), dtr2 = c("A1", "B2"),
  dtr3 = c("A2", "B1"), dtr4 = c("A2", "B2")
))

# Compare DTR means using weighted GEE
m_dtr <- geeglm(final_outcome ~ dtr_indicator,
                 id = subject_id, data = df_rep,
                 weights = ipw_weight,
                 family = gaussian, corstr = "independence")
summary(m_dtr)

# Pairwise contrasts between DTRs
library(emmeans)
emmeans(m_dtr, pairwise ~ dtr_indicator)
```

**Key assumptions and diagnostics:**
- [ ] Sequential randomization assumption (SRA): at each stage, treatment is randomized conditional on history
- [ ] Positivity: every participant has a non-zero probability of receiving each treatment at each stage
- [ ] Response criterion is pre-specified, clinically/theoretically meaningful, and measured before Stage 2 randomization
- [ ] No interference: one participant's treatment does not affect another's outcome
- [ ] Consistency: the DTR is well-defined (same treatment strategy → same outcome distribution)
- [ ] Response rate: if response rate is very high (> 90%) or very low (< 10%), Stage 2 comparisons are underpowered

**Write-up template:**
> "We conducted a Sequential Multiple Assignment Randomized Trial (SMART) to develop and compare adaptive interventions for [outcome]. At Stage 1 (baseline), participants (N = [X]) were randomized 1:1 to [A1] or [A2]. After [duration], participants were classified as responders (defined as [criterion]; [R]% responded) or non-responders based on [assessment]. Non-responders were re-randomized 1:1 to [B1] or [B2]; responders [continued / were re-randomized to maintenance options]. This design embeds [4] DTRs. Our primary comparison is [DTR 1 vs. DTR 3], estimated using [Q-learning / inverse probability weighted estimation / weighted and replicated GEE (Nahum-Shani et al. 2012)]. Sample size was determined for this primary comparison (see Step 3h)."

---

## Step 3: Power Analysis

Run before finalizing sample size for any primary data collection; report in Methods for all NHB/Science Advances submissions.

### 3a. Standard Power Analysis (R — `pwr` package)

```r
library(pwr)

# OLS / two-group comparison (RCT, DiD contrast)
pwr.t.test(d = 0.3, sig.level = 0.05, power = 0.80, type = "two.sample")
# d = 0.2 small; 0.3–0.4 typical sociology; 0.5 medium; 0.8 large

# Correlation / regression coefficient
pwr.r.test(r = 0.15, sig.level = 0.05, power = 0.80)

# Binary outcome — logistic regression
library(WebPower)
wp.logistic(n = NULL, p0 = 0.20, p1 = 0.27,   # 7 pp AME
            alpha = 0.05, power = 0.80, family = "normal")

# Chi-square / cross-tab
pwr.chisq.test(w = 0.20, df = 3, sig.level = 0.05, power = 0.80)

# One-way ANOVA (experimental with multiple arms)
pwr.anova.test(k = 3, f = 0.20, sig.level = 0.05, power = 0.80)
```

### 3b. Multilevel / HLM Power (simulation — `simr`)

Use when data have nested structure (students in schools, workers in firms):

```r
library(simr)
library(lme4)

# Step 1: Fit pilot model or specify hypothetical model
m_pilot <- lmer(outcome ~ treatment + (1 | school_id), data = pilot_df)

# Step 2: Set effect size of interest
fixef(m_pilot)["treatment"] <- 0.25   # specify hypothesized effect

# Step 3: Extend sample size and simulate power
m_extended <- extend(m_pilot, along = "school_id", n = 60)   # 60 schools
powerSim(m_extended, test = fixed("treatment"), nsim = 200)

# Step 4: Power curve across sample sizes
power_curve <- powerCurve(m_extended, test = fixed("treatment"),
                          along = "school_id", breaks = c(20, 30, 40, 60))
plot(power_curve)
```

### 3c. Minimum Detectable Effect Size (MDES)

When using secondary data with a fixed N, compute the smallest effect detectable at 80% power:

```r
library(pwr)
# What is the smallest d detectable with N=400 per group, 80% power?
pwr.t.test(n = 400, sig.level = 0.05, power = 0.80, type = "two.sample")
# → d = [output]; interpret relative to literature benchmarks below
```

**Effect size benchmarks for social science:**

| Domain | Typical effect | Notes |
|--------|---------------|-------|
| Labor market returns to education | β ≈ 0.07–0.10 per year of schooling | IQ-adjusted β ≈ 0.06–0.08 |
| Survey attitude experiments | d = 0.10–0.30 | Framing effects often d = 0.10–0.20 |
| Discrimination audit / vignette | d = 0.20–0.50 | Race gaps in hiring ≈ d = 0.30 |
| Neighborhood effects | d = 0.10–0.25 | MTO housing experiments |
| Health interventions | d = 0.20–0.40 | Behavioral interventions |
| Network exposure effects | d = 0.10–0.30 | Highly variable |

### 3d. Power Reporting Templates

**For primary data collection:**
> "We conducted an a priori power analysis using the `pwr` package (Champely 2020). Assuming a small-to-medium effect size (d = [X], based on [Author Year]), two-tailed α = .05, and 80% power, the minimum required sample size is N = [X] per arm. Our target sample (N = [Y]) provides [Z]% power."

**For secondary data with fixed N:**
> "Our analytic sample (N = [X]) provides 80% power to detect effects of d ≥ [Y] (α = .05, two-tailed). We focus interpretation on effect sizes and confidence intervals given this constraint."

### 3e. Cluster RCT Power Analysis

Power for cluster RCTs must account for the design effect (DEFF) from intraclass correlation. Use `clusterPower` or `CRTSize` packages.

```r
# Method 1: clusterPower package (recommended)
library(clusterPower)

# Continuous outcome: compare means between two arms of clusters
cps.normal(
  m = 30,           # individuals per cluster
  K = NULL,         # solve for number of clusters per arm
  d = 0.30,         # standardized effect size (Cohen's d)
  ICC = 0.05,       # intraclass correlation
  alpha = 0.05,
  power = 0.80,
  method = "analytic"
)

# Binary outcome: compare proportions between two arms
cps.binary(
  m = 30,           # individuals per cluster
  K = NULL,         # solve for K
  p1 = 0.20,        # control group proportion
  p2 = 0.30,        # treatment group proportion (10 pp effect)
  ICC = 0.05,
  alpha = 0.05,
  power = 0.80
)

# Method 2: CRTSize package
library(CRTSize)
n4means(delta = 0.30,       # effect size (raw units)
        sigma = 1.0,         # SD of outcome
        m = 30,              # cluster size
        ICC = 0.05,
        alpha = 0.05,
        power = 0.80)

# Method 3: Manual DEFF-based calculation
# DEFF = 1 + (m - 1) * ICC
# N_cluster = N_individual / DEFF * (1/K_clusters)
# Required individual N (from pwr) inflated by DEFF
library(pwr)
n_ind <- pwr.t.test(d = 0.30, sig.level = 0.05, power = 0.80,
                    type = "two.sample")$n
m <- 30           # cluster size
rho <- 0.05       # ICC
DEFF <- 1 + (m - 1) * rho   # = 1 + 29 * 0.05 = 2.45
n_adj <- ceiling(n_ind * DEFF)  # inflated total per arm
K_per_arm <- ceiling(n_adj / m)  # clusters per arm
cat("DEFF =", DEFF, "\nClusters per arm =", K_per_arm,
    "\nTotal clusters =", 2 * K_per_arm, "\nTotal N =", 2 * K_per_arm * m)

# Power curve across ICC values
icc_vals <- seq(0.01, 0.20, by = 0.01)
power_by_icc <- sapply(icc_vals, function(rho) {
  deff <- 1 + (m - 1) * rho
  n_eff <- (K_per_arm * m) / deff  # effective sample size per arm
  pwr.t.test(n = n_eff, d = 0.30, sig.level = 0.05, type = "two.sample")$power
})
plot(icc_vals, power_by_icc, type = "b", xlab = "ICC", ylab = "Power",
     main = "Power as a function of ICC (K fixed)")
abline(h = 0.80, lty = 2, col = "red")
```

**Reporting template:**
> "Power was computed for a cluster randomized trial with [K] clusters per arm, [m] individuals per cluster, and an assumed ICC of ρ = [X] (based on [source]). The design effect was DEFF = 1 + ([m] − 1) × [ρ] = [DEFF]. At α = .05 (two-tailed), this design provides [X]% power to detect a standardized effect of d = [Y]. We used the `clusterPower` package (Kleinman and Huang 2022) for power calculations."

### 3f. Audit / Correspondence Study Power Analysis

Power for matched-pair audit studies focuses on the within-pair difference in callback rates.

```r
# McNemar's test power for matched-pair binary outcomes
library(pwr)

# Parameters: p_discordant = proportion of pairs with different outcomes
# OR = odds ratio of discordant pairs (callback_majority / callback_minority)
# Under H1: if majority callback = 0.30 and minority callback = 0.20,
# discordant proportion ≈ 0.30*(1-0.20) + 0.20*(1-0.30) = 0.38
# OR among discordant = 0.30*(1-0.20) / (0.20*(1-0.30)) = 1.71

# Method 1: Exact McNemar power
power.mcnemar.test <- function(n_pairs, p10, p01, alpha = 0.05) {
  # p10 = P(majority callback, minority no callback)
  # p01 = P(minority callback, majority no callback)
  disc <- p10 + p01
  z_alpha <- qnorm(1 - alpha / 2)
  z <- (abs(p10 - p01) * sqrt(n_pairs) - z_alpha * sqrt(disc)) / sqrt(disc - (p10 - p01)^2)
  pnorm(z)
}

# Example: 10 pp discrimination gap (majority 30% vs. minority 20%)
p10 <- 0.30 * (1 - 0.20)  # = 0.24 (majority yes, minority no)
p01 <- 0.20 * (1 - 0.30)  # = 0.14 (minority yes, majority no)

# Search for required N pairs
n_pairs <- seq(100, 2000, by = 50)
powers <- sapply(n_pairs, function(n) power.mcnemar.test(n, p10, p01))
min_n <- n_pairs[which(powers >= 0.80)[1]]
cat("Minimum pairs for 80% power:", min_n, "\n")

# Method 2: Using pwr for two-proportions (conservative, ignores pairing)
pwr.2p.test(h = ES.h(0.30, 0.20), sig.level = 0.05, power = 0.80)

# Method 3: Simulation-based power (most flexible)
set.seed(42)
sim_power <- function(n_pairs, p_majority, p_minority, nsim = 2000) {
  reject <- replicate(nsim, {
    majority_callback <- rbinom(n_pairs, 1, p_majority)
    minority_callback <- rbinom(n_pairs, 1, p_minority)
    tab <- table(factor(majority_callback, 0:1), factor(minority_callback, 0:1))
    mcnemar.test(tab)$p.value < 0.05
  })
  mean(reject)
}
sim_power(n_pairs = 500, p_majority = 0.30, p_minority = 0.20)
```

**Reporting template:**
> "We conducted an a priori power analysis for a matched-pair correspondence audit. Assuming a callback rate of [X]% for majority-group applicants and [Y]% for minority-group applicants (a [Z] percentage point gap, based on [Author Year]), two-tailed α = .05 and 80% power, we require a minimum of [N] matched pairs. Our target sample of [N] pairs provides [X]% power (McNemar's test). We used simulation ([2,000] iterations) to confirm analytic results."

### 3g. Stepped-Wedge Power Analysis

Power for stepped-wedge designs depends on the number of clusters, steps, cluster size, ICC, and the within-cluster correlation over time.

```r
# Method 1: swCRTdesign package (recommended)
library(swCRTdesign)

# Hussey & Hughes (2007) closed-form power
# K = total clusters, S = steps, m = cluster-period size, ICC = rho
sw_power <- swPwr(
  design   = swDsn(clusters = rep(2, 3)),  # 3 steps, 2 clusters per step = 6 total
  distn    = "gaussian",
  n        = 30,           # individuals per cluster per period
  mu0      = 0,            # control mean
  mu1      = 0.30,         # treatment mean (effect size in raw units)
  sigma    = 1.0,          # within-cluster SD
  tau      = sqrt(0.05),   # between-cluster SD (related to ICC)
  alpha    = 0.05,
  retDATA  = TRUE
)
cat("Power:", sw_power$power, "\n")

# Method 2: Simulation-based power (handles complex designs)
# Simulate data under Hussey-Hughes model, fit model, check rejection rate
set.seed(42)
sim_sw_power <- function(K, S, m, effect, icc, sigma = 1, nsim = 500) {
  tau <- sqrt(icc * sigma^2 / (1 - icc))  # between-cluster SD
  T_periods <- S + 1
  clusters_per_step <- K / S

  reject <- replicate(nsim, {
    # Generate design matrix
    df_sim <- expand.grid(cluster = 1:K, period = 1:T_periods, ind = 1:m)
    df_sim$step <- ceiling(df_sim$cluster / clusters_per_step)
    df_sim$treatment <- as.integer(df_sim$period > df_sim$step)

    # Generate outcome: Y = period_effect + treatment_effect + cluster RE + error
    cluster_re <- rnorm(K, 0, tau)
    df_sim$y <- 0.1 * df_sim$period +            # secular trend
                effect * df_sim$treatment +        # treatment effect
                cluster_re[df_sim$cluster] +       # cluster random effect
                rnorm(nrow(df_sim), 0, sigma)      # individual error

    # Fit Hussey-Hughes model
    m_fit <- lme4::lmer(y ~ treatment + factor(period) + (1 | cluster),
                        data = df_sim)
    # Test treatment coefficient
    coef_summary <- summary(m_fit)$coefficients
    p_val <- coef_summary["treatment", "Pr(>|t|)"]
    p_val < 0.05
  })
  mean(reject)
}

# Example: 12 clusters, 4 steps, 25 per cluster-period, ICC = 0.05, effect = 0.3
sim_sw_power(K = 12, S = 4, m = 25, effect = 0.30, icc = 0.05)

# Method 3: Woertman et al. (2013) design effect formula
# DEFF_SW = DEFF_parallel * (3 * (1 - rho)) / (2 * t * (S - 1/S))
# where t = S + 1 periods, S = steps
# This gives the ratio of sample sizes: N_SW / N_individual_RCT
```

**Reporting template:**
> "Power was computed for a stepped-wedge cluster randomized design with [K] clusters randomized across [S] steps (plus one baseline period), [m] individuals per cluster per period, and an assumed ICC of ρ = [X]. Using the `swCRTdesign` package (Hughes et al. 2020) [/ simulation with [500] iterations], this design provides [X]% power to detect an effect of [Y] [units / d] at α = .05 (two-tailed). We assumed a [constant / linearly increasing] treatment effect and accounted for secular trends via period fixed effects."

### 3h. SMART Power Analysis

Power for SMART designs targets the comparison between two embedded DTRs.

```r
# Power for comparing two embedded DTRs in a SMART
# Key parameters: response rate (R), Stage 1 and Stage 2 effect sizes

# Method 1: Oetting et al. (2011) formula for two-arm SMART
# Comparing DTR1 (A1 → if NR → B1) vs DTR3 (A2 → if NR → B1)
# Difference driven by Stage 1 treatment effect
smart_power <- function(n_total, delta, sigma, R, alpha = 0.05) {
  # Effective sample size depends on response rate and DTR structure
  # Var(mean under DTR) ≈ sigma^2 / n * (1 + (1-R) * (1 + variance_inflation))
  # Simplified: variance inflation ≈ 4 for typical SMART
  var_dtr <- sigma^2 * 4 / n_total
  se_diff <- sqrt(2 * var_dtr)
  z_alpha <- qnorm(1 - alpha / 2)
  z_power <- delta / se_diff - z_alpha
  pnorm(z_power)
}

# Method 2: Simulation-based (recommended — handles complex designs)
set.seed(42)
sim_smart_power <- function(n_total, d_stage1, d_stage2, response_rate,
                             sigma = 1, nsim = 1000) {
  reject <- replicate(nsim, {
    n <- n_total
    # Stage 1: randomize to A1 vs A2
    a1 <- rbinom(n, 1, 0.5)

    # Response (depends on Stage 1 treatment + noise)
    p_respond <- response_rate + 0.05 * a1  # slightly higher response if A1
    responded <- rbinom(n, 1, p_respond)

    # Stage 2: re-randomize non-responders to B1 vs B2
    b1 <- rep(NA, n)
    nr_idx <- which(responded == 0)
    b1[nr_idx] <- rbinom(length(nr_idx), 1, 0.5)

    # Outcome under each DTR
    y <- 0 +
      d_stage1 * a1 +                              # Stage 1 effect
      d_stage2 * ifelse(!responded & b1 == 1, 1, 0) +  # Stage 2 effect (NR only)
      rnorm(n, 0, sigma)

    # Assign DTR membership (each person consistent with 1-2 DTRs)
    # DTR1: A1 → NR → B1
    # DTR3: A2 → NR → B1
    # Compare mean Y for DTR1-consistent vs DTR3-consistent individuals
    # Use IPW: weight = 1/P(received observed treatment | consistent with DTR)
    dtr1_consistent <- (a1 == 1 & responded == 1) | (a1 == 1 & b1 == 1)
    dtr3_consistent <- (a1 == 0 & responded == 1) | (a1 == 0 & b1 == 1)

    if (sum(dtr1_consistent) < 5 | sum(dtr3_consistent) < 5) return(FALSE)

    mean_dtr1 <- mean(y[dtr1_consistent])
    mean_dtr3 <- mean(y[dtr3_consistent])
    se <- sqrt(var(y[dtr1_consistent]) / sum(dtr1_consistent) +
               var(y[dtr3_consistent]) / sum(dtr3_consistent))
    z <- (mean_dtr1 - mean_dtr3) / se
    abs(z) > qnorm(0.975)
  })
  mean(reject)
}

# Example: N=300, d=0.3 for Stage 1, d=0.2 for Stage 2, 60% response rate
sim_smart_power(n_total = 300, d_stage1 = 0.3, d_stage2 = 0.2,
                response_rate = 0.60)

# Method 3: Sample size table (rules of thumb from Nahum-Shani et al. 2012)
# For comparing two DTRs differing in Stage 1 treatment (most common primary aim):
# d = 0.3, response rate 50%, 80% power → N ≈ 250–350
# d = 0.3, response rate 70%, 80% power → N ≈ 200–300
# d = 0.5, response rate 50%, 80% power → N ≈ 100–150
# Rule of thumb: N_SMART ≈ 2–4x N_standard_RCT for same effect size
```

**Reporting template:**
> "Sample size was determined for the primary comparison of [DTR 1] vs. [DTR 3], which differ in [Stage 1 treatment / Stage 2 treatment for non-responders]. Based on simulation ([1,000] iterations), assuming a Stage 1 effect of d = [X], a response rate of [R]% (based on [source]), and α = .05 (two-tailed), N = [X] participants provides [Y]% power. This accounts for the variance inflation inherent in DTR estimation from SMART data (Nahum-Shani et al. 2012). We inflate the target by [Z]% for anticipated attrition, yielding a recruitment target of N = [W]."

### 3i. Multilevel / 3-Level Power Analysis

**Multilevel / 3-level power analysis**:
```r
# Students nested in classrooms nested in schools
library(simr)
# Step 1: Specify model with expected effect sizes
model <- makeLmer(y ~ treatment + (1 | school/classroom),
                  fixef = c(0, 0.3),  # intercept, treatment effect
                  VarCorr = list(school = 0.5, classroom = 0.2),
                  sigma = 1, data = sim_data)
# Step 2: Simulate power
powerSim(model, nsim = 500, test = fixed("treatment"))
# Step 3: Power curve across sample sizes
pc <- powerCurve(model, within = "school + classroom",
                 breaks = c(10, 20, 30, 50), nsim = 200)
plot(pc)
```

**Design effect for cluster designs**: DEFF = 1 + (m̄ − 1) × ICC, where m̄ = average cluster size. Effective N = N_total / DEFF.

**ICC sensitivity**: Report power at ICC = 0.01, 0.05, 0.10 (most social science contexts).

### 3j. DiD / RD / Mediation Power Analysis

**DiD power (simulation-based)**:
```r
library(DeclareDesign)
did_design <- declare_model(
  units = add_level(N = 200, U = rnorm(N)),
  periods = add_level(N = 2, nest = FALSE),
  treatment = ifelse(units_ID > 100 & periods_ID == 2, 1, 0),
  Y = 0.3 * treatment + U + rnorm(N * 2)
) + declare_estimator(Y ~ treatment + factor(units_ID) + factor(periods_ID))
diagnose_design(did_design, sims = 500)
```

**RD power (rdpower)**:
```r
library(rdpower)
# Power for detecting effect τ at cutoff c
rdpower(data = df$running_var, cutoff = 0, tau = 0.2,
        alpha = 0.05, nsamples = c(500, 1000, 2000))
```

**Mediation power (indirect effect)**:
```r
library(pwr2ppl)
# Power for ACME (average causal mediation effect)
# Requires: a-path (X→M), b-path (M→Y), sample size
medjs(a = 0.3, b = 0.2, cp = 0.1, n = 500, alpha = 0.05, rep = 1000)
```

### 3k. SEM/CFA Sample Size Guidance

**SEM/CFA sample size rules of thumb**:
- Minimum: N ≥ 200 (Kline 2016)
- Per-parameter rule: N ≥ 10 × number of free parameters
- For complex models (>30 parameters): N ≥ 500
- Monte Carlo simulation: `simsem::sim()` for exact power by model

---

## Step 4: Variable Specification

### 4a. Variable dictionary

Document every analytic variable before touching data. Use this format:

| Role | Variable name | Construct | Operationalization | Data source / question | Type | Range | Notes |
|------|--------------|-----------|-------------------|-----------------------|------|-------|-------|
| Y (Outcome) | `earnings_ln` | Annual earnings | Log annual earnings ($) | PSID annual_earn | Continuous | 0–∞ | Top-code at 99th pct |
| X (Predictor) | `immigrant` | Immigrant status | Born outside US (1=yes) | ACS NATIVITY | Binary | 0/1 | — |
| M (Mediator) | `english_prof` | English proficiency | 4-point self-report | CPS SPEAKENG | Ordinal | 1–4 | — |
| W (Moderator) | `race_eth` | Race/ethnicity | 5-category self-ID | ACS RACE + HISPAN | Categorical | 5 cats | ref = White |
| C (Control) | `educ_yrs` | Education | Years (recoded from categories) | ACS EDUC | Continuous | 0–20 | Midpoints |
| FE / cluster | `state` | State | FIPS code | ACS STATEFIP | Categorical | 51 | FE or cluster |

For post-treatment variables, flag explicitly: "POTENTIAL POST-TREATMENT — confirm with DAG before including."

### 4b. Measurement validity checklist

For each key construct (Y and primary X):
- [ ] **Face validity**: Does operationalization obviously capture the concept?
- [ ] **Content validity**: Are all facets of the construct covered?
- [ ] **Construct validity**: Has this measure been validated in prior work? Cite.
- [ ] **Measurement equivalence**: Does the measure mean the same thing across compared groups?
- [ ] **Missing data**: How much missingness? What is the likely mechanism (MCAR/MAR/MNAR)?

### 4c. DAG sketch

List at minimum:
- **Direct causes of X**: [confounders to control for]
- **Direct causes of Y (besides X)**: [additional confounders]
- **Potential mediators M** (should generally NOT control for unless mediation is the goal)
- **Potential colliders** (should NOT control for — introduce bias)

For full DAG construction → invoke `/scholar-causal` Step 1.

---

## Step 5: Analytic Strategy

### 5a. Model selection

| Outcome type | Distribution | Primary model | Key options |
|-------------|-------------|--------------|-------------|
| Continuous (normal) | Gaussian | OLS | Robust SEs (HC3); cluster by group |
| Continuous (skewed) | Log-normal | OLS on log(Y) | Back-transform for interpretation |
| Binary (0/1) | Bernoulli | Logistic → **report AME** | `marginaleffects::avg_slopes()` |
| Ordered categories (3–7) | Ordinal | Ordered logit → **report AME** | `MASS::polr()` + `avg_slopes()` |
| Nominal categories | Multinomial | Multinomial logit | `nnet::multinom()` |
| Count (no excess zeros) | Poisson / NB | Negative binomial | Test overdispersion first |
| Count (excess zeros) | Zero-inflated | ZINB or hurdle | `pscl::zeroinfl()` |
| Time-to-event | Survival | Cox PH | Test PH assumption with `cox.zph()` |
| Panel, continuous | Gaussian | Two-way FE (`fixest::feols`) | Cluster SEs by unit |
| Panel, binary | Bernoulli | Conditional logit | `survival::clogit()` |
| Multilevel (nested) | Gaussian | HLM (`lme4::lmer`) | Report ICC |
| Multilevel, binary | Bernoulli | GLMM (`lme4::glmer`) | Report ICC + AME |

**Key rule:** For logistic, ordered logit, and GLMM in sociology journals — **always report AME, never raw log-odds or odds ratios** (strong ASR/AJS preference).

```r
library(marginaleffects)
# AME: average over all observations
avg_slopes(model)

# At representative values
slopes(model, newdata = datagrid(x = c(0, 1), female = c(0, 1)))

# Interaction effects
plot_slopes(model, variables = "treatment", condition = "race_eth")
```

### 5b. Standard errors and clustering

| Design | SE type | Command |
|--------|---------|---------|
| Cross-sectional, no clustering | HC3 robust | `sandwich::vcovHC(m, "HC3")` |
| Clustered (students in schools) | Clustered by group | `feols(y ~ x, cluster = ~school_id)` |
| Two-way clustering (unit + time) | Two-way cluster | `feols(y ~ x, cluster = ~unit + year)` |
| Survey data with weights | Survey-weighted | `svyglm()` from `survey` package |
| RCT with block randomization | Block-clustered | `lm_robust(y ~ x, clusters = block)` |

### 5c. Presentation sequence

Present models progressively — reviewers expect this:

1. **Model 1**: Outcome ~ Key predictor (bivariate or with minimal covariates)
2. **Model 2**: + Full set of controls
3. **Model 3**: + Fixed effects or identification strategy
4. **Model 4** (if applicable): + Interaction / moderator
5. **Appendix models**: Robustness checks (see Step 6)

Use `modelsummary::modelsummary()` for regression table output:
```r
library(modelsummary)
modelsummary(
  list("Bivariate" = m1, "+Controls" = m2, "+FE" = m3, "+Interaction" = m4),
  stars     = c("*" = .05, "**" = .01, "***" = .001),
  gof_map   = c("nobs", "r.squared", "adj.r.squared"),
  notes     = "HC3 robust standard errors.",
  output    = paste0(Sys.getenv("OUTPUT_ROOT", "output"), "/design/table-model-spec.html")
)
```

---

## Step 6: Robustness Plan

Pre-specify these before seeing results to avoid specification searching. List all planned checks in the PAP and Methods section.

### Standard robustness battery

| Check | What it tests | Command |
|-------|--------------|---------|
| Alternative operationalization of X or Y | Measurement dependency | `update(m2, . ~ . - x + x_alt)` |
| Add / remove controls | Omitted variable sensitivity | `update(m2, . ~ . + extra_control)` |
| Alternative sample restriction | Sample composition | `filter(df, age >= 30)` then refit |
| Remove outliers / influential cases | Influential observations | Cook's D > 4/N → exclude, refit |
| Placebo outcome | Spurious association | Replace Y with pre-treatment outcome |
| Placebo treatment | Spurious timing | Replace DiD treatment with fake timing |
| Oster (2019) delta — OVB bound | Unmeasured confounding | `sensemakr` package |
| E-value — unmeasured confounding bound | Unmeasured confounding | `EValue::evalues.OLS()` |

### Oster (2019) delta

```r
library(sensemakr)
sens <- sensemakr(
  model              = m3,          # full model
  treatment          = "treatment", # variable name
  benchmark_covariates = "educ_yrs", # comparable observed confounder
  kd = 1:3                           # 1x–3x as strong as benchmark
)
ovb_minimal_reporting(sens)
# Interprets: how large must omitted variable be (relative to educ_yrs) to drive β to 0?
```

### E-value (unmeasured confounding)

```r
library(EValue)
# For OLS: evalue(est=coef, se=SE, type="OLS")
evalues.OLS(est = 0.15, se = 0.04, delta = 1, true = 0)
# Minimum E-value to fully explain away the effect
```

---

## Step 7: Pre-Analysis Plan (PAP)

Required for RCTs and survey experiments; increasingly expected for observational studies at NHB and Science Advances. Register on OSF before data collection.

### PAP template

```
PRE-ANALYSIS PLAN — [Project Title]
PI: [Name] | Institution: [Name] | Date: [Date]
OSF Registration: https://osf.io/[ID]

1. RESEARCH QUESTIONS AND HYPOTHESES
   H1: [Directional statement — matches /scholar-hypothesis output]
   H2: [Moderator hypothesis, if any]
   H3: [Mechanism hypothesis, if any]

2. DESIGN
   Type: [RCT / observational / quasi-experimental]
   Treatment: [Description of treatment assignment procedure]
   Randomization unit: [Person / household / school / county]
   Randomization procedure: [Block by: strata variables]

3. PRIMARY OUTCOME
   Variable: [name + operationalization]
   Measurement: [instrument / survey item / administrative record]
   Timing: [pre / post / panel waves]

4. COVARIATES AND CONTROLS
   [List all controls + rationale for each]
   Post-treatment variables: [list and confirm NOT controlled for]

5. PRIMARY ANALYSIS
   Estimator: [OLS / Logit + AME / FE / DiD / RD / IV]
   Standard errors: [HC3 / clustered by X / two-way cluster]
   Software: [R version + packages / Stata version]
   Code: [will be deposited at osf.io/[ID] upon data collection]

6. SUBGROUP / HETEROGENEITY ANALYSES
   [Pre-specified moderators + rationale]

7. ROBUSTNESS CHECKS
   [List all planned checks from Step 6]

8. MULTIPLE COMPARISONS CORRECTION
   - Number of primary hypotheses: [K]
   - Correction method: Bonferroni (α/K), Benjamini-Hochberg FDR, or Westfall-Young permutation
   - Pre-specify which outcomes are primary (corrected) vs. exploratory (uncorrected)
   - Report both corrected and uncorrected p-values

9. DEVIATIONS POLICY
   Deviations from this plan will be documented in the paper with rationale.
   All deviations will be flagged in a "Comparison to PAP" appendix table.

10. SAMPLE SIZE
   Target N: [X] [cite power analysis from Step 3]
   Stopping rule: [pre-specified or data availability]
```

**OSF registration checklist:**
- [ ] PAP text uploaded to OSF (or aspredicted.org)
- [ ] OSF project set to "Private" until registration is submitted
- [ ] Registration submitted → component is time-stamped (cannot be modified)
- [ ] OSF URL included in Methods section of paper

---

## Step 8: Write Data and Methods Section

Produce a full draft Methods section using the Write tool. Match structure and length to target journal.

### 8a. Structure templates by design type

**Observational (cross-sectional / panel / FE / DiD):**
```
DATA AND METHODS

Data
  "[Dataset name] is a [nationally representative / population-based / cross-sectional / panel]
  survey of [population] collected [by organization] in [year(s)]. [Key feature relevant to RQ].
  We restrict the analytic sample to [restriction criteria], resulting in N = [X] [units]
  ([demographic description]). Appendix Table A1 describes the sample construction."

Measures
  Dependent variable: "[Y variable] is measured as [operationalization]. [Distribution note:
  mean = X, SD = Y / XX% endorse]."

  Key independent variable: "[X variable] is [operationalization]. [Validity note or citation]."

  Controls: "We include standard sociodemographic controls: [list]. [Domain-specific controls:
  list with brief rationale]."

Analytic Strategy
  "We estimate [OLS / logistic / FE / DiD] models of the form:
    Y_[it] = α + β[X_it] + [γ_i + δ_t +] X'Γ + ε_[it]
  where [define all terms]. [SE type]: standard errors are [HC3 robust / clustered by X / two-way
  clustered by X and Y]. [Causal identification sentence: 'By including [unit / time] fixed
  effects, we identify the effect of X using within-[unit] variation, which absorbs all
  time-invariant confounders.']

  [For logistic] We report average marginal effects (AME) rather than odds ratios, averaged
  over the observed distribution of covariates (Mize 2019; Long and Freese 2014).

  [Robustness] We assess sensitivity to [list checks] in Appendix Tables A[X]–A[Y]."
```

**Qualitative (interviews / ethnography):**
```
DATA AND METHODS

Data and Site
  "We draw on [N] semi-structured interviews / [months] of ethnographic fieldwork at [site].
  [Access and recruitment description]. [Sampling strategy: purposive / theoretical / snowball]
  targeting [key variation]. Interviews lasted [range] minutes and were [recorded and transcribed
  verbatim / transcribed from detailed field notes]. [IRB approval note]."

Sample
  "[Table X presents participant characteristics.] We continued sampling until theoretical
  saturation was reached (Strauss and Corbin 1998), when new interviews yielded no
  conceptually distinct material (N = [X])."

Analytic Approach
  "We analyzed transcripts using [thematic analysis (Braun and Clarke 2006) / grounded theory
  (Charmaz 2014) / interpretive phenomenological analysis]. [Author 1] conducted open coding;
  themes were refined through iterative memo writing and discussion among the research team.
  We use [Atlas.ti / NVivo / Dedoose] for data management. [Reflexivity note: 'The first
  author [positionality statement]; we discuss implications for interpretation in Appendix X.']"
```

### 8b. Journal-specific norms

| Journal | Methods length | Structure | Key requirements |
|---------|---------------|-----------|-----------------|
| ASR | 1,000–2,000 words | Data → Measures → Analytic Strategy | AME for logit; defend causal design; report pre-trends if DiD |
| AJS | 1,000–2,000 words | Data → Methods | Strong theory-design linkage; qual papers allowed; AME preferred |
| Demography | 1,500–2,500 words | Very detailed; decomposition expected | Report all N exclusions; demographic methods section |
| Science Advances | 800–1,200 words main; full in STAR Methods | STAR Methods in supplement | Power analysis; pre-registration if experimental; code/data availability |
| NHB | 800–1,200 words main; full in Methods | Methods after Results (NCS format OK) | Power analysis; Reporting Summary; OSF pre-reg if experimental |
| NCS | 800–1,200 words main; full in Methods | Results → Methods (NCS section order) | Computational reproducibility; model architecture; cross-validation |

### 8c. Checklist before writing

- [ ] Confirm N of final analytic sample (from /scholar-eda if available)
- [ ] All variables in variable dictionary (Step 4a) accounted for
- [ ] Identification strategy stated and defended (one sentence each: what, why, assumption)
- [ ] Model equation written out with all terms defined
- [ ] SE type specified and justified
- [ ] Robustness checks listed by name
- [ ] PAP URL included (if registered)
- [ ] Code/data availability statement drafted (required: Science Advances, NHB, NCS)

---

## Step 9: Computational Methods Design

Run this step when the study uses NLP / text-as-data, machine learning, network analysis, agent-based modeling, or large-scale digital data. Pair with `/scholar-compute` for execution; this step covers design decisions that must be made before analysis begins.

### 9a. Computational Claim Type

Specify which type of computational claim the study makes — this determines the right validation strategy and reporting standard:

| Claim type | Description | Primary validity concern | Example |
|-----------|-------------|------------------------|---------|
| **Measurement** | Use computation to operationalize a latent construct at scale | Construct validity: does the measure capture the concept? | BERT topic scores as proxy for political ideology |
| **Description / Discovery** | Characterize patterns in large corpora or networks | Coverage and representativeness of corpus | Topic trends in news 1990–2020 |
| **Prediction** | Forecast an outcome (not causal) | Out-of-sample generalization; no causal interpretation | Predict dropout from clickstream data |
| **Causal (data as treatment/outcome)** | Use computational measure as X or Y in causal design | All of the above + identification assumption | DiD with text-derived polarization index |

**Lin & Zhang (2025) four-risk framework** for LLM-assisted coding: (1) validity risk — does the LLM measure what you intend? (2) reliability risk — are results stable across runs/prompts? (3) replicability risk — are prompts, models, and outputs archived? (4) transparency risk — is the annotation process legible to readers?

---

### 9b. Corpus / Dataset Design

Before collecting or finalizing any text or digital dataset, specify:

**Population definition:**
```
What is the universe of documents/observations this corpus should represent?
  Unit:      [tweet / article / speech / post / user / dyad]
  Population: [all English tweets mentioning X / all NYT articles 2010–2020 / all Reddit posts in r/Y]
  Time frame: [start date] to [end date]
  Language:  [English only / multilingual — specify languages]
  Exclusions: [retweets / bots / duplicates / non-original content]
```

**Minimum corpus size by method:**

| Method | Minimum N (documents) | Recommended N | Notes |
|--------|----------------------|--------------|-------|
| Dictionary / LIWC | Any | > 1,000 | Bias from small samples |
| LDA / STM topic model | 1,000 | 5,000–50,000 | More docs → more stable topics |
| BERT fine-tuning (supervised) | 500 labeled | 2,000+ labeled | With data augmentation; 500 is a floor |
| Zero-shot / LLM annotation | Any | — | Validate on 200–500 sample regardless |
| Word embeddings (Word2Vec) | 50,000 tokens | 1M+ tokens | Sparse vocab below this |
| conText embedding regression | 500 per group | 2,000+ per group | Token-level sample |
| Network analysis | 50 nodes | 200+ nodes | Below 50 → descriptive only |

**Sampling strategy:**
- **Random sample**: Take a stratified random sample by time period and/or source if corpus is too large to process fully
- **Purposive sample**: Include all documents in defined population (e.g., all Congressional speeches); document coverage rate
- **Temporal balance**: Ensure time periods of interest are adequately represented; document any gaps

---

### 9c. Annotation Design (Supervised ML / LLM Validation)

When training a classifier or validating LLM-based coding:

**Codebook development:**
1. Draft operational definitions for each category
2. Include positive examples, negative examples, and boundary cases
3. Pilot on 50 documents with 2 coders → revise definitions
4. Finalize codebook before main annotation round

**Annotation protocol:**
```
Annotation Design
─────────────────────────────────────
Task:              [binary / multi-class / ordinal / span extraction]
Categories:        [list with operational definitions]
Unit of analysis:  [sentence / paragraph / document / post]
Coders:           [N coders; background description]
Training:          [codebook review + 30-item practice set + calibration discussion]
Assignment:        [double-code all / double-code 20% for IRR; single-code remainder]
Adjudication:      [majority vote / third coder resolves disagreement / consensus discussion]
```

**Inter-rater reliability (IRR) targets:**

| IRR measure | Minimum acceptable | Preferred | When to use |
|------------|-------------------|-----------|-------------|
| Cohen's κ | 0.70 | ≥ 0.80 | Binary or nominal categories, 2 coders |
| Krippendorff's α | 0.70 | ≥ 0.80 | Any scale, any N coders; preferred for ordinal |
| Percent agreement | 80% | ≥ 90% | Simple binary; always report alongside κ |
| ICC | 0.75 | ≥ 0.90 | Continuous / ordinal ratings |

```r
library(irr)
# Cohen's kappa (2 coders, nominal)
kappa2(cbind(coder1, coder2))

# Krippendorff's alpha (N coders, any level)
kripp.alpha(t(coding_matrix), method = "nominal")   # or "ordinal", "interval"

# Percent agreement
agree(cbind(coder1, coder2))
```

**Annotation sample size for validation:** Minimum N = 200 labeled items for binary classification; N = 400–500 for 3+ categories or rare events (< 10% base rate).

---

### 9d. Train / Test / Validation Split Strategy

Pre-specify and document the split before seeing model results.

**Standard splits:**

| Scenario | Recommended split | Notes |
|----------|-----------------|-------|
| Large corpus (N > 5,000) | 70% train / 15% val / 15% test | Val for hyperparameter tuning; test held out until final evaluation |
| Medium corpus (N = 1,000–5,000) | 60% train / 20% val / 20% test | — |
| Small corpus (N < 1,000) | 5-fold or 10-fold CV | No separate test set; report CV mean ± SD |
| Time-series / panel text | Temporal split (train on t < T; test on t ≥ T) | Never shuffle time — prevents leakage |
| Multi-source corpus | Source-stratified split | Ensure all sources represented in train and test |
| Imbalanced classes | Stratified split | Maintain class proportions in each fold |

```python
from sklearn.model_selection import train_test_split, StratifiedKFold

# Stratified train/val/test split
X_train, X_temp, y_train, y_temp = train_test_split(
    X, y, test_size=0.30, stratify=y, random_state=42)
X_val, X_test, y_val, y_test = train_test_split(
    X_temp, y_temp, test_size=0.50, stratify=y_temp, random_state=42)

# Temporal split for text/panel data
cutoff = int(len(df) * 0.70)
df_train = df.iloc[:cutoff]
df_test  = df.iloc[cutoff:]

# K-fold CV (small N)
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
```

**Critical rule:** The test set must be held out until all model and hyperparameter decisions are finalized. If you evaluate on the test set more than once, it is no longer a valid holdout.

---

### 9e. Evaluation Metrics Pre-Specification

Choose and pre-specify primary metric before training. Report all secondary metrics in appendix.

| Task | Primary metric | Secondary metrics | When to prefer |
|------|--------------|-----------------|---------------|
| Binary classification (balanced) | F1 | Accuracy, AUC-ROC, precision, recall | Standard |
| Binary classification (imbalanced) | F1 or AUC-PR | Precision, recall by class | Rare events (< 20% positive) |
| Multi-class classification | Macro F1 | Per-class F1, confusion matrix | Equal class weight |
| Ordinal regression | Spearman ρ or QWK | MAE, rank correlation | Ordered categories |
| Regression / scoring | RMSE | MAE, R², MAPE | Penalizes large errors |
| Topic model | C_v coherence | UMass coherence, NPMI, human interpretability | Always validate qualitatively |
| Embedding / similarity | Cosine similarity vs. human judgment | — | Compare to gold standard |
| Generative / extraction | ROUGE-L, BERTScore | Human evaluation (fluency, faithfulness) | Summarization, extraction |

```python
from sklearn.metrics import (classification_report, f1_score,
                              roc_auc_score, confusion_matrix)

# Full classification report
print(classification_report(y_test, y_pred, digits=3))

# Macro F1 (recommended for imbalanced multi-class)
f1_macro = f1_score(y_test, y_pred, average="macro")

# AUC-ROC (binary)
auc = roc_auc_score(y_test, y_prob[:, 1])
```

---

### 9f. Network Study Design

Pre-specify before data collection:

**Boundary specification (most critical decision in network studies):**
```
Network Boundary Specification
─────────────────────────────────────
Node definition:   [person / organization / country / keyword]
Edge definition:   [tie / interaction / co-occurrence / citation]
Edge direction:    [directed / undirected]
Edge weight:       [binary / frequency / strength]
Temporal structure: [static snapshot at T / dynamic (time-stamped edges)]
Boundary rule:     [complete network: all nodes in [population] /
                    ego network: up to [K] alters /
                    component: largest connected component]
Missing ties:      [how handled: survey non-response / API limits / thresholding]
```

**Data requirements by method:**

| Method | Minimum network size | Data type | Notes |
|--------|---------------------|-----------|-------|
| Descriptive metrics (density, degree) | Any | Static | Report with confidence intervals if sampled |
| Community detection (Louvain, etc.) | N ≥ 50 nodes | Static | Report modularity Q |
| ERGM | N = 50–1,000 nodes | Static, undirected | Degeneracy risk for large N |
| SAOM / RSiena | N = 20–500 nodes | Panel (2+ waves) | Requires panel data with same nodes |
| Relational event model (goldfish) | N ≥ 100 events | Timestamped events | See /scholar-compute MODULE 3 |
| Diffusion / contagion | N ≥ 100 nodes | Dynamic | Define exposure threshold |

**Boundary documentation in Methods:**
> "We define the network as [description]. Nodes are [definition]; directed ties represent [definition] occurring between [dates]. We apply a [minimum activity threshold] to exclude [low-activity nodes], resulting in a network of N = [X] nodes and E = [Y] edges. [X]% of possible ties are observed."

---

### 9g. Agent-Based Model (ABM) Design — ODD Protocol

All ABMs must be described using the ODD (Overview, Design concepts, Details) protocol (Grimm et al. 2020). Pre-specify before implementation:

```
ODD PROTOCOL — [Model Name]

OVERVIEW
  Purpose:         [What social process does this model represent?]
  Entities:        [Agents: persons / firms / neighborhoods; Environment: grid / network / continuous]
  State variables: [Per agent: age, status, threshold, opinion; Per environment: resource level]
  Scales:          [Spatial: N/A / grid size; Temporal: [N] ticks = [real unit]]

DESIGN CONCEPTS
  Basic principles:  [Theory driving agent behavior — cite]
  Emergence:         [What macro pattern should emerge from micro rules?]
  Adaptation:        [Do agents update behavior based on feedback? How?]
  Stochasticity:     [Where is randomness? Seed all RNG.]
  Observation:       [What is recorded? At what frequency?]

DETAILS
  Initialization:    [Starting conditions: N agents, initial state distribution]
  Input data:        [External data feeding the model, if any]
  Submodels:         [Step-by-step specification of each behavioral rule]
```

**Parameter space and sensitivity analysis:**
```python
# Latin Hypercube Sampling (LHS) for parameter sweep — SALib
from SALib.sample import latin
from SALib.analyze import sobol

problem = {
    "num_vars": 3,
    "names":    ["threshold", "rewiring_prob", "initial_adopters"],
    "bounds":   [[0.1, 0.9], [0.0, 0.5], [0.01, 0.20]]
}
param_values = latin.sample(problem, N=500, seed=42)
# Run model for each param set; compute Sobol indices on output
```

---

### 9h. Reproducibility Standards for Computational Work

| Requirement | R | Python |
|-------------|---|--------|
| Lock package versions | `renv::snapshot()` → `renv.lock` | `pip freeze > requirements.txt` or `conda env export` |
| Set all seeds | `set.seed(42)` at top of every script | `random.seed(42); np.random.seed(42); torch.manual_seed(42)` |
| Document compute environment | `sessionInfo()` in output | `platform.python_version(); uname()` |
| Container (full reproducibility) | Rocker Docker image | `Dockerfile` with pinned base image |
| Version control | git tag release; DOI via Zenodo | same |

```r
# R reproducibility header (paste at top of every analysis script)
set.seed(42)
library(renv)
renv::snapshot()           # lock dependencies
sessionInfo()              # log R + package versions
```

```python
# Python reproducibility header
import random, numpy as np, torch, platform
random.seed(42); np.random.seed(42)
if torch.cuda.is_available(): torch.manual_seed(42)
print(platform.platform(), platform.python_version())
```

**Archive policy:** All code + model weights (if < 1 GB) + processed data + this ODD/design document deposited to GitHub + Zenodo DOI before submission.

---

### 9i. Computational Methods Section Template (NCS / Science Advances)

```
DATA AND METHODS

Data
  "We collected [N] [documents / posts / nodes / events] from [source] spanning [date range].
  [Corpus construction: sampling procedure, exclusion criteria, final N].
  [For networks: node and edge definitions, boundary rule, N nodes, E edges, density].
  [For admin/digital data: API or scraping procedure; see /scholar-data WORKFLOW 7]."

Computational Pipeline
  "We processed text using [tokenization / sentence segmentation / normalization procedure].
  [Model choice and rationale: 'We use [RoBERTa-base / STM / conText] because [reason].']
  [Training procedure: fine-tuned on N = [X] labeled examples; learning rate [X]; [X] epochs;
  batch size [X]; hardware: [GPU model]].
  [Validation: held-out test set (N = [X]); primary metric: [metric]; score: [value (95% CI)].
  Inter-rater reliability on annotation sample: κ = [X] / α = [X] (N = [X] items).]"

Statistical Analysis
  "[How computational measures feed into downstream regression/causal models — see Step 5.]
  [Calibration / uncertainty: how measurement error in the computed variable is handled.]"

Reproducibility
  "All code, trained model weights, and processed data are available at [GitHub URL] (DOI: [Zenodo]).
  We used [R version / Python version] with package versions recorded in [renv.lock / requirements.txt].
  All stochastic operations used seed [42]. [Compute environment: [CPU/GPU spec]]."
```

**NCS / Science Advances reporting requirements:**
- Report model architecture (layers, parameters, pretraining corpus)
- Report all hyperparameters (learning rate, batch size, epochs, dropout, optimizer)
- Report cross-validation strategy and all evaluation metrics
- Report compute time and hardware
- Deposit code and data (mandatory at NCS; expected at Science Advances)
- Reporting Summary must address statistical reporting (NHB/NCS)

See [references/computational-design.md](references/computational-design.md) for extended templates: corpus sampling code, annotation codebook structure, ML evaluation suite, network boundary templates, ODD protocol examples, and reproducibility checklist.

---

## Step 10: Bayesian Design

Run this step when the user requests Bayesian inference, prior elicitation, Bayesian sample size determination, or design analysis via simulation. This approach is complementary to frequentist power analysis (Step 3) and is increasingly expected at journals like Science Advances and NHB for complex models.

### 10a. When to Use Bayesian Design

| Scenario | Why Bayesian | Journal fit |
|----------|-------------|-------------|
| Small samples (N < 100) with informative prior literature | Priors regularize estimates; avoids separation in logistic models | Any |
| Complex hierarchical / multilevel models | Natural framework for partial pooling | Demography, ASR |
| Sequential data collection (can update as data arrive) | Posterior updating; optional stopping is principled | Science Advances, NHB |
| Prior information is substantively important | Can formally incorporate meta-analytic priors | Any |
| Multivariate / structural equation models | Avoids convergence issues of frequentist SEM | NHB, NCS |
| Measurement model + structural model jointly estimated | Full uncertainty propagation | NCS, Science Advances |

### 10b. Prior Elicitation

Priors must be justified — never use flat / improper priors without justification. Document the source and rationale for every prior.

**Prior elicitation workflow:**

```
Prior Specification
─────────────────────────────────────
For each parameter θ in the model:
  1. Source:       [meta-analysis / expert elicitation / pilot data / weakly informative default]
  2. Distribution: [Normal / Student-t / Half-Cauchy / LKJ / Dirichlet]
  3. Location:     [center of prior — best guess from literature]
  4. Scale:        [spread — reflects uncertainty about the parameter]
  5. Rationale:    [one-sentence justification citing source]
  6. Sensitivity:  [will check: tighter prior, wider prior, diffuse prior]
```

**Recommended default priors (weakly informative — Gelman et al. 2020):**

| Parameter | Recommended prior | Notes |
|-----------|------------------|-------|
| Regression coefficients (standardized X, Y) | Normal(0, 1) or Student-t(3, 0, 2.5) | Weakly informative; rules out implausibly large effects |
| Intercept | Normal(ȳ, 10 × SD_y) or Student-t(3, 0, 10) | Centered on outcome mean |
| SD of random effects (σ_u) | Half-Cauchy(0, 1) or Exponential(1) | Must be positive; Half-Cauchy allows large values |
| Correlation matrix (Ω) | LKJ(2) | Slightly favors uncorrelated; LKJ(1) = uniform on correlations |
| Variance (σ²) | Inverse-Gamma(1, 1) or Half-Cauchy(0, 5) | Half-Cauchy preferred for hierarchical models |
| Probability / proportion | Beta(1, 1) = Uniform or Beta(2, 2) | Weakly informative |
| Ordinal thresholds | Induced Dirichlet | See Bürkner & Vuorre (2019) |

**Informative priors from meta-analysis:**

```r
# Example: derive prior from meta-analytic estimate
# Meta-analysis reports: d = 0.25, 95% CI [0.10, 0.40]
# → Normal(0.25, SD = (0.40 - 0.10) / (2 * 1.96)) = Normal(0.25, 0.077)

meta_mean <- 0.25
meta_se   <- (0.40 - 0.10) / (2 * 1.96)  # ≈ 0.077
cat("Informative prior: Normal(", meta_mean, ",", meta_se, ")\n")

# Skeptical prior: center at zero, same spread (tests whether data overwhelm skepticism)
# Normal(0, 0.077)
```

### 10c. Bayesian Model Fitting with brms

```r
library(brms)

# --- Example 1: Linear regression with weakly informative priors ---
priors_lm <- c(
  prior(normal(0, 1), class = "b"),                # coefficients
  prior(student_t(3, 0, 2.5), class = "Intercept"),# intercept
  prior(exponential(1), class = "sigma")            # residual SD
)

m_bayes <- brm(
  outcome ~ treatment + age + female + educ,
  data    = df,
  family  = gaussian(),
  prior   = priors_lm,
  chains  = 4, iter = 4000, warmup = 1000,
  cores   = 4, seed = 42,
  control = list(adapt_delta = 0.95)
)

summary(m_bayes)
plot(m_bayes)                         # trace plots + posterior densities
pp_check(m_bayes, ndraws = 100)       # posterior predictive check

# --- Example 2: Multilevel logistic regression ---
priors_mlm <- c(
  prior(normal(0, 1), class = "b"),
  prior(student_t(3, 0, 2.5), class = "Intercept"),
  prior(exponential(1), class = "sd")               # SD of random effects
)

m_bayes_mlm <- brm(
  callback ~ minority + job_quality + (1 | employer_id),
  data    = df,
  family  = bernoulli(),
  prior   = priors_mlm,
  chains  = 4, iter = 4000, warmup = 1000,
  cores   = 4, seed = 42
)

# Posterior summaries and credible intervals
posterior_summary(m_bayes_mlm, pars = "b_minority")
hypothesis(m_bayes_mlm, "minority < 0")   # directional test: P(β < 0 | data)

# --- Example 3: Informative prior from meta-analysis ---
priors_inform <- c(
  prior(normal(0.25, 0.08), class = "b", coef = "treatment"),  # meta-analytic prior
  prior(normal(0, 1), class = "b"),                             # other coefficients
  prior(exponential(1), class = "sigma")
)

m_inform <- brm(
  outcome ~ treatment + controls,
  data = df, family = gaussian(),
  prior = priors_inform,
  chains = 4, iter = 4000, warmup = 1000, cores = 4, seed = 42
)
```

### 10d. Bayesian Diagnostics

```r
# Convergence diagnostics (must pass ALL before interpreting results)
# 1. R-hat < 1.01 for all parameters
rhat(m_bayes)  # all should be < 1.01

# 2. Effective sample size (ESS) > 400 for bulk and tail
neff_ratio(m_bayes)  # ratio of ESS to total draws; want > 0.1

# 3. Trace plots: chains should mix well (no trends, no stickiness)
mcmc_trace(as.array(m_bayes), pars = c("b_treatment", "sigma"))

# 4. Posterior predictive check: simulated data should resemble observed
pp_check(m_bayes, type = "dens_overlay", ndraws = 100)
pp_check(m_bayes, type = "stat_2d", stat = c("mean", "sd"))  # check mean + SD

# 5. Prior sensitivity analysis: compare posteriors under different priors
m_diffuse <- update(m_bayes,
                    prior = c(prior(normal(0, 10), class = "b"),
                              prior(student_t(3, 0, 10), class = "Intercept"),
                              prior(exponential(0.1), class = "sigma")))

m_tight <- update(m_bayes,
                  prior = c(prior(normal(0, 0.5), class = "b"),
                            prior(student_t(3, 0, 1), class = "Intercept"),
                            prior(exponential(2), class = "sigma")))

# Compare posteriors visually
library(bayesplot)
mcmc_areas(as.array(m_bayes), pars = "b_treatment", prob = 0.95) +
  ggtitle("Default prior")
mcmc_areas(as.array(m_diffuse), pars = "b_treatment", prob = 0.95) +
  ggtitle("Diffuse prior")
mcmc_areas(as.array(m_tight), pars = "b_treatment", prob = 0.95) +
  ggtitle("Tight prior")

# 6. LOO cross-validation for model comparison
library(loo)
loo_m1 <- loo(m_bayes)
loo_m2 <- loo(m_bayes_alt)
loo_compare(loo_m1, loo_m2)  # lower ELPD difference = better model
```

### 10e. Bayesian Sample Size Determination (Design Analysis / Assurance)

Bayesian "power" is computed via **assurance** (probability of achieving a desired posterior conclusion given prior + design) or **design analysis** (simulation of the full data-generating + analysis pipeline).

```r
# Method 1: Design analysis via simulation (brms — recommended)
# Simulate data under assumed DGP, fit Bayesian model, check how often
# the posterior excludes zero (or achieves desired precision)

library(brms)

bayesian_design_analysis <- function(n_per_group, true_effect, sigma = 1,
                                      prior_sd = 1, nsim = 200, seed = 42) {
  set.seed(seed)
  results <- data.frame(
    sim      = 1:nsim,
    post_mean = NA, post_lower = NA, post_upper = NA,
    excludes_zero = NA, width_95 = NA
  )

  for (i in 1:nsim) {
    # Simulate data
    df_sim <- data.frame(
      treatment = rep(0:1, each = n_per_group),
      outcome   = c(rnorm(n_per_group, 0, sigma),
                     rnorm(n_per_group, true_effect, sigma))
    )

    # Fit Bayesian model (suppress output for speed)
    m <- brm(outcome ~ treatment, data = df_sim, family = gaussian(),
             prior = c(prior(normal(0, prior_sd), class = "b"),
                       prior(exponential(1), class = "sigma")),
             chains = 2, iter = 2000, warmup = 500, cores = 2,
             seed = seed + i, silent = 2, refresh = 0)

    # Extract posterior for treatment
    post <- as_draws_df(m)
    results$post_mean[i]      <- mean(post$b_treatment)
    results$post_lower[i]     <- quantile(post$b_treatment, 0.025)
    results$post_upper[i]     <- quantile(post$b_treatment, 0.975)
    results$excludes_zero[i]  <- (results$post_lower[i] > 0) | (results$post_upper[i] < 0)
    results$width_95[i]       <- results$post_upper[i] - results$post_lower[i]
  }

  cat("=== Bayesian Design Analysis ===\n")
  cat("N per group:", n_per_group, "\n")
  cat("True effect:", true_effect, "\n")
  cat("Assurance (P(95% CI excludes 0)):", mean(results$excludes_zero), "\n")
  cat("Mean 95% CI width:", mean(results$width_95), "\n")
  cat("Mean posterior estimate:", mean(results$post_mean), "\n")
  return(results)
}

# Example: 100 per group, true d = 0.3
res <- bayesian_design_analysis(n_per_group = 100, true_effect = 0.30)

# Assurance curve across sample sizes
n_vals <- c(50, 100, 150, 200, 300)
assurance <- sapply(n_vals, function(n) {
  r <- bayesian_design_analysis(n, true_effect = 0.30, nsim = 100)
  mean(r$excludes_zero)
})
plot(n_vals, assurance, type = "b", xlab = "N per group", ylab = "Assurance",
     main = "Bayesian assurance curve")
abline(h = 0.80, lty = 2, col = "red")

# Method 2: Precision-based sample size (target a maximum CI width)
# Find N such that the average 95% posterior interval width ≤ target_width
target_width <- 0.30  # e.g., want CI width ≤ 0.30 for practical precision
for (n in c(50, 100, 200, 300, 500)) {
  r <- bayesian_design_analysis(n, true_effect = 0.30, nsim = 100)
  cat("N =", n, "→ Mean CI width:", round(mean(r$width_95), 3), "\n")
}

# Method 3: SampleSizeMeans (conjugate normal, closed-form)
# For simple normal mean comparison with known prior
bayes_n_normal <- function(delta, prior_sd, sigma, target_assurance = 0.80) {
  # Closed-form for normal prior, normal likelihood
  # Posterior SD = 1 / sqrt(1/prior_sd^2 + n/sigma^2)
  # Assurance ≈ P(|posterior mean| > 1.96 * posterior SD)
  n_search <- 10:1000
  for (n in n_search) {
    post_sd <- 1 / sqrt(1 / prior_sd^2 + n / sigma^2)
    post_mean_dist_sd <- sigma / sqrt(n)  # variability of posterior mean across samples
    # P(95% CI excludes 0) ≈ P(|Z| > 1.96 * post_sd / (delta + post_mean_dist_sd * Z))
    assurance <- pnorm(delta / sqrt(post_sd^2 + post_mean_dist_sd^2) - 1.96)
    if (assurance >= target_assurance) return(n)
  }
  return(NA)
}
```

### 10f. Bayesian Reporting and Write-Up Template

**Key reporting requirements:**
- [ ] All priors listed and justified (source, distribution, parameters)
- [ ] Convergence diagnostics reported (R-hat, ESS, trace plots in appendix)
- [ ] Posterior predictive checks shown (at least one figure)
- [ ] Prior sensitivity analysis performed (at least 2 alternative prior specifications)
- [ ] Results reported as posterior means/medians with 95% credible intervals (not p-values)
- [ ] If comparing models: LOO-IC or WAIC reported
- [ ] Software and version documented (brms, Stan, R version)

**Write-up template:**
> "We estimated [model description] using Bayesian inference implemented in `brms` (Bürkner 2017) with the Stan probabilistic programming language (Stan Development Team 2023). We specified [weakly informative / informative] priors: [β ~ Normal(0, 1) for regression coefficients; σ ~ Exponential(1) for the residual standard deviation; τ ~ Half-Cauchy(0, 1) for random effect standard deviations]. [For the treatment effect, we used an informative prior of Normal([μ], [σ]) derived from a meta-analysis of [K] prior studies (Author Year).] We ran [4] Hamiltonian Monte Carlo chains for [4,000] iterations ([1,000] warmup), yielding [12,000] posterior draws. All parameters achieved R-hat < 1.01 and effective sample sizes > [1,000] (see Appendix Table A[X]). Posterior predictive checks confirmed adequate model fit (Appendix Figure A[Y]). [Prior sensitivity: results were robust to [diffuse / skeptical] alternative priors (Appendix Table A[Z]).] We report posterior means with 95% credible intervals. [Bayesian sample size determination: a design analysis with [200] simulated datasets indicated [X]% assurance of obtaining a 95% credible interval excluding zero given our sample size and prior (see Step 10e).]"

---

## Step 11: Internal Review Panel (MANDATORY before Save)

**Purpose:** Before the design blueprint is saved to disk, run a 5-agent internal review panel on the assembled design (Steps 1–10 outputs plus the Methods section draft from Step 8). Each reviewer evaluates from a distinct methodological lens. A synthesizer aggregates consensus flags, a reviser produces an improved blueprint, and the user accepts the revision before Save Output.

This step is REQUIRED for all design modes. Skip only if arguments specify `power`, `methods-section`, or `pap` alone (narrow single-step requests).

### Phase A — Assemble the Review Package

Compile the following materials into a single **REVIEW PACKAGE** (in-memory, not saved yet):

1. **Design Overview**: claim type, design, dataset, journal target (from Step 1)
2. **Power Analysis**: assumptions, MDES / required N, citation grounding effect size (Step 3)
3. **Variable Dictionary**: full Y/X/M/W table with operationalizations (Step 4)
4. **Analytic Strategy**: estimator, SE type, model sequence, AME plan (Step 5)
5. **Robustness Plan**: list of pre-specified checks (Step 6)
6. **PAP** (if drafted): registered hypotheses + decision rules (Step 7)
7. **Methods Section Draft**: full prose from Step 8
8. **Specialized Design Details**: cluster RCT / audit / stepped-wedge / SMART / Bayesian / computational (Steps 2d–2g, 9, 10)

### Phase B — Spawn Five Parallel Reviewer Subagents

Use the Task tool to run all 5 reviewers **in parallel** (five simultaneous tool calls). Fill in `[journal]` and `[REVIEW PACKAGE]` in each prompt.

---

**R1 — Methodological Rigor Reviewer**

Spawn a `general-purpose` agent:

> "You are a rigorous methodologist reviewing a research design blueprint targeting [journal]. Critique whether the chosen design supports the claim strength. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Claim-design match**: Does the design support the strength of claim (causal vs. descriptive vs. predictive)? Flag any causal claim made with a design that cannot identify causal effects.
> 2. **Identification strategy**: For causal designs, are identifying assumptions (parallel trends, exclusion restriction, SUTVA, ignorability, monotonicity, etc.) stated explicitly? Are they defensible for the empirical setting?
> 3. **Threats to validity**: What internal and external validity threats are NOT addressed? (Selection, measurement error, attrition, spillovers, Hawthorne effects, interference, compound treatments.)
> 4. **Design-specific pitfalls**: If DiD — is parallel trends testable? If IV — is the instrument plausibly exogenous and relevant? If RD — is the running variable manipulable? If matching — is common support documented?
> 5. **Alternative designs**: Is there a stronger design the author should consider? (e.g., within-subject design, instrumental variable, cluster-randomized variant.)
>
> End with your single most important suggestion for strengthening the design.
>
> REVIEW PACKAGE: [paste package]"

---

**R2 — Power & Sample Size Reviewer**

Spawn a `general-purpose` agent:

> "You are a statistician specializing in study design and sample size reviewing a research design blueprint targeting [journal]. Critique the power analysis and whether N is adequate. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Effect size assumption**: Is the assumed effect size grounded in prior literature (with citation) or justified as a minimum clinically/substantively meaningful effect? Flag any uncited 'Cohen's d = 0.5' defaults.
> 2. **Power calculation correctness**: Does the power calculation match the planned estimator? (e.g., cluster RCT power must account for ICC and DEFF; interaction tests need 4× the sample of main effects; multilevel designs need level-2 N.)
> 3. **MDES reporting**: For secondary data with fixed N, is the Minimum Detectable Effect Size computed and compared to literature effect sizes to assess whether the study is informative?
> 4. **Multiple testing**: If multiple hypotheses or outcomes, is correction (Bonferroni, Holm, FDR, pre-registered primary outcome) planned?
> 5. **Assurance vs. power**: If Bayesian, is assurance computed? If frequentist, is the 80% power level justified for the stakes of the decision?
>
> End with a verdict: Is the study adequately powered for its primary claim?
>
> REVIEW PACKAGE: [paste package]"

---

**R3 — Measurement & Variable Specification Reviewer**

Spawn a `general-purpose` agent:

> "You are a measurement and survey methodologist reviewing a research design blueprint targeting [journal]. Critique variable construction, operationalization, and data handling. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Construct validity**: Does each operationalization (coding rule, scale, index) validly measure the intended construct? Flag any proxy that conflates multiple constructs.
> 2. **Post-treatment bias**: Are any 'controls' actually post-treatment (measured after exposure, on the causal pathway)? List each control and classify as pre-treatment / contemporaneous / post-treatment.
> 3. **Missingness strategy**: Is missing data handled appropriately (MI, FIML, complete-case with justification)? Is MNAR considered for sensitive outcomes?
> 4. **Measurement reliability**: For scales/indices, are α / ω / test-retest or IRR planned? For qualitative coding, is κ ≥ 0.70 target set?
> 5. **Categorization decisions**: Are categorical collapses, top/bottom coding, and reference categories pre-specified and justified? Flag arbitrary cutpoints.
>
> End with your single most important suggestion for improving measurement.
>
> REVIEW PACKAGE: [paste package]"

---

**R4 — Journal Fit & Reporting Standards Reviewer**

Spawn a `general-purpose` agent:

> "You are a former associate editor at [journal] reviewing a research design blueprint. Evaluate whether the design and methods draft meet [journal]'s specific expectations. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Reporting standards**: Does the plan meet [journal]'s reporting requirements? (ASR/AJS: AME preferred over ORs for binary outcomes. Demography: decomposition/standardization when appropriate. Nature journals: Reporting Summary, data/code availability, CRediT.)
> 2. **Methods section structure**: Is the Methods draft the right length and structure for [journal]? (Demography: extended sample construction. NHB/NCS: concise Methods with detailed Supplementary Information. ASR/AJS: methods after theory, hypotheses stated numerically.)
> 3. **Preregistration expectations**: Does [journal]'s norm require/recommend preregistration for this design type? (RCTs and survey experiments: required at many outlets. Observational: increasingly encouraged.)
> 4. **Open science requirements**: Are data availability, code sharing, and materials sharing planned? Flag any proprietary data constraints that must be disclosed upfront.
> 5. **Format red flags**: Are there choices (missing CONSORT, no AME, no robustness appendix, no limitations statement) that would trigger methodological desk review or revision at [journal]?
>
> End with your single most important suggestion for improving journal fit.
>
> REVIEW PACKAGE: [paste package]"

---

**R5 — Feasibility & Replicability Reviewer**

Spawn a `general-purpose` agent:

> "You are a pragmatic senior researcher reviewing a research design blueprint targeting [journal]. Critique whether the design is actually executable and replicable — independent of theoretical ambition. Evaluate each item as **Strong / Adequate / Weak** and give 3–5 specific, actionable comments:
>
> 1. **Data access feasibility**: Is the proposed data actually obtainable? (Restricted-access datasets with multi-month IRB / DUA processes; proprietary data; API rate limits; archival access.) Flag any data dependency not yet secured.
> 2. **Sample recruitment realism**: If primary collection, is the target N achievable within stated resources? Is the sampling frame defined (not 'convenience sample from social media')?
> 3. **Computational feasibility**: For computational designs, is the compute budget realistic? (LLM API costs; GPU time for fine-tuning; storage for large corpora.)
> 4. **Replication readiness**: Are seeds, package versions (renv.lock / requirements.txt / environment.yml), and a public repository planned? Is the preregistration specific enough that a replicator could reproduce the analytic decisions?
> 5. **Ethical and IRB risk**: Are IRB, consent, deception (for audit studies), vulnerable populations, and data-handling concerns flagged? Is the design likely to pass IRB in a reasonable timeframe?
>
> End with a verdict: Is this design feasible as specified, or does it need scope reduction?
>
> REVIEW PACKAGE: [paste package]"

---

### Phase C — Synthesize Into Design Review Scorecard

After all 5 reviewers return, produce a **Design Review Scorecard**:

```
===== INTERNAL DESIGN REVIEW PANEL — [Topic] — [Journal] =====

Panel: R1 (Rigor) | R2 (Power) | R3 (Measurement) | R4 (Journal Fit) | R5 (Feasibility)

| Dimension | R1 | R2 | R3 | R4 | R5 | Consensus |
|-----------|----|----|----|----|----|-----------|
| Claim-design match | [S/A/W] | — | — | — | — | [S/A/W] |
| Identification strategy | [S/A/W] | — | — | — | — | [S/A/W] |
| Threats to validity | [S/A/W] | — | — | — | — | [S/A/W] |
| Effect size grounding | — | [S/A/W] | — | — | — | [S/A/W] |
| Power calculation | — | [S/A/W] | — | — | — | [S/A/W] |
| MDES / multiple testing | — | [S/A/W] | — | — | — | [S/A/W] |
| Construct validity | — | — | [S/A/W] | — | — | [S/A/W] |
| Post-treatment bias | — | — | [S/A/W] | — | — | [S/A/W] |
| Missingness / reliability | — | — | [S/A/W] | — | — | [S/A/W] |
| Reporting standards | — | — | — | [S/A/W] | — | [S/A/W] |
| Methods section fit | — | — | — | [S/A/W] | — | [S/A/W] |
| Open science / preregistration | — | — | — | [S/A/W] | — | [S/A/W] |
| Data feasibility | — | — | — | — | [S/A/W] | [S/A/W] |
| Replication readiness | — | — | — | — | [S/A/W] | [S/A/W] |
| IRB / ethics risk | — | — | — | — | [S/A/W] | [S/A/W] |
| **Weak items count** | [N] | [N] | [N] | [N] | [N] | **[total]** |

★★ Cross-agent agreement (raised by 2+ reviewers — highest priority):
1. [Issue] — flagged by [R1, R3] — [summary]
2. [Issue] — flagged by [R2, R4] — [summary]
...

Top suggestion from each reviewer:
- R1: [suggestion]
- R2: [verdict on power adequacy + top fix]
- R3: [suggestion]
- R4: [suggestion]
- R5: [feasibility verdict + top fix]

OVERALL VERDICT: [Ready to save / Revise before save / Fundamental redesign needed]
```

Log this phase:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-design"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| 11B | $(date +%H:%M:%S) | Review Scorecard | 5-agent panel synthesized | scorecard in-memory | ✓ |" >> "$LOG_FILE"
```

---

### Phase D — Reviser Subagent (sequential, after Phase C)

Spawn a **reviser subagent** to produce the improved blueprint:

> "You are an expert research methodologist revising a design blueprint for [journal]. You have feedback from a 5-agent review panel covering methodological rigor, power, measurement, journal fit, and feasibility. Produce a revised blueprint that addresses all valid concerns while preserving the author's research question and scientific contribution.
>
> **Instructions**:
> 1. Address every ★★ item (cross-agent agreement) first — these are highest priority
> 2. Address every item rated **Weak** from any reviewer, unless doing so would alter the core research question — note any skipped items with a brief reason
> 3. Do not change anything rated **Strong** by 2+ reviewers — preserve those elements
> 4. If R1 or R5 flagged fundamental problems (e.g., design cannot identify the claim; data not obtainable), produce a **Design Change Recommendation** block at the top summarizing what must change before proceeding
> 5. Revise the Methods section draft from Step 8 so it reflects the updated design
> 6. Mark each substantive revision inline: `[REV: reason]` (use in the Methods draft and variable dictionary)
> 7. After the revised blueprint, append a **Revision Notes** block:
>    - ★★ items addressed (bulleted)
>    - Other changes made (bulleted)
>    - Reviewer comments not acted on and why
>    - Any open questions requiring user decision
>
> **Original REVIEW PACKAGE**: [paste package]
> **Design Review Scorecard**: [paste scorecard from Phase C]
> **R1 feedback**: [paste R1 output]
> **R2 feedback**: [paste R2 output]
> **R3 feedback**: [paste R3 output]
> **R4 feedback**: [paste R4 output]
> **R5 feedback**: [paste R5 output]"

---

### Phase E — Accept the Revision

After the reviser returns:

1. Present the **Design Review Scorecard**, **Revision Notes**, and a summary of the revised blueprint to the user
2. Ask: **"Accept revised design blueprint? (`yes` / `accept with edits` / `keep original` / `redesign`)"**
   - `yes`: Use the revised blueprint as the final version for Save Output
   - `accept with edits`: Apply user's specific edits, then proceed to Save Output
   - `keep original`: Use the pre-review blueprint and append the Review Scorecard + Revision Notes as an appendix in the saved file
   - `redesign`: Return to Step 1 with the reviser's Design Change Recommendation as input — do NOT save
3. Log the user decision

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-design"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
echo "| 11E | $(date +%H:%M:%S) | Accept Revision | [user decision: yes/edits/keep/redesign] | — | ✓ |" >> "$LOG_FILE"
```

**HARD STOP**: Do NOT proceed to Save Output until the user has accepted a version (yes / accept with edits / keep original). If `redesign`, loop back to Step 1.

---

## Save Output

After completing all relevant steps — including the user-accepted output from **Step 11 (Internal Review Panel)** — save the design blueprint using the Write tool. Use the **accepted revised blueprint** from Step 11 Phase E as the source of truth (or the pre-review version if the user chose `keep original`, with the Review Scorecard + Revision Notes appended as an appendix).

### Version Collision Avoidance (MANDATORY)

**Before EVERY Write tool call below**, run this Bash block to determine the correct save path. Do NOT hardcode paths from the filename templates — they show naming patterns only.

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# BASE pattern: ${OUTPUT_ROOT}/[slug]/design/scholar-design-[topic-slug]-[YYYY-MM-DD]
# Split into directory and stem for the gate script:
OUTDIR="$(dirname "${OUTPUT_ROOT}/[slug]/design/scholar-design-[topic-slug]-[YYYY-MM-DD]")"
STEM="$(basename "${OUTPUT_ROOT}/[slug]/design/scholar-design-[topic-slug]-[YYYY-MM-DD]")"
mkdir -p "$OUTDIR"
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" "$OUTDIR" "$STEM"
```

**Use the printed `SAVE_PATH` as `file_path` in the Write tool call.** Re-run this block (with the appropriate BASE) for each additional file. The same version suffix must be used for all related output files (.md, .docx, .tex, .pdf).


**Filename:** `scholar-design-[topic-slug]-[YYYY-MM-DD].md`

**Contents:**

```markdown
# Design Blueprint: [topic]
*Generated by /scholar-design on [YYYY-MM-DD]*

## Design Overview
- Claim type: [descriptive / causal / predictive / interpretive]
- Design: [observational cross-sectional / panel FE / DiD / RD / IV / RCT / qual interviews / mixed]
- Dataset: [name, N, time period, unit of analysis]
- Journal target: [journal]

## Power Analysis
[Key result: minimum N, assumed effect size, power level; or MDES for secondary data]

## Variable Dictionary
[Full table from Step 4a: Role | Variable name | Construct | Operationalization | Source | Type]

## Analytic Strategy
- Primary model: [estimator + SE type]
- Model sequence: Model 1 → Model 2 → ... [with what each adds]
- AME reported for: [list binary/ordered outcomes]

## Robustness Plan
[List all pre-specified checks from Step 6]

## Pre-Analysis Plan
[PAP text or link to OSF registration]

## Methods Section Draft
[Full draft from Step 8]

## Specialized Design Details (if applicable)
### Cluster RCT: K = [X] clusters, m = [Y] per cluster, ICC = [ρ], DEFF = [Z], analysis: [GEE / MLM]
### Audit Study: domain = [hiring/housing], signal = [race/gender], N pairs = [X], within-pair analysis: [clogit / FE LPM]
### Stepped-Wedge: K = [X] clusters, S = [Y] steps, T = [Z] periods, model: [Hussey-Hughes / exposure time]
### SMART: N = [X], Stage 1 = [A1/A2], response criterion = [def], Stage 2 NR = [B1/B2], primary comparison = [DTR1 vs DTR3]
### Bayesian: priors = [list], software = [brms/Stan], chains = [X], diagnostics = [R-hat, ESS], assurance = [X]%

## Computational Design (if applicable)
- Claim type: [measurement / description / prediction / causal]
- Corpus: [source, N documents, time range, sampling strategy]
- Method: [STM / BERT fine-tune / zero-shot LLM / network ERGM / ABM Mesa]
- Split: [70/15/15 / k-fold / temporal]
- Primary eval metric: [F1 / RMSE / coherence / modularity]
- IRR: [κ = X / α = X on N = Y items]
- Reproducibility: [seed, renv.lock / requirements.txt, repo URL]

## Internal Review Panel Summary (Step 11)
- Panel outcome: [Ready to save / Revised / Kept original / Redesign triggered]
- Weak items flagged (total across 5 reviewers): [N]
- Cross-agent ★★ issues addressed: [N]
- User decision: [yes / accept with edits / keep original / redesign]
- Review Scorecard and Revision Notes: [embedded below OR appended as appendix if kept original]

[If user chose `keep original`, paste the full Design Review Scorecard and Revision Notes here as an appendix.]

## File Inventory
output/[slug]/design/          ← design blueprint (this file)
output/[slug]/design/table-model-spec.html  ← model specification table
[Additional outputs]
```

Confirm saved file path to user after Write completes.

**Emit Design Type to PROJECT STATE (MANDATORY):**

`scholar-analyze` branches its model-specification strategy on the `Design Type` line in `project-state.md` (see `scholar-analyze/references/design-router.md`). At end-of-workflow, infer the type from the keyword dispatch above and the finalized blueprint, then write it to the shared project state.

```bash
# Derive PROJ (respect standard project-layout conventions)
. "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh" 2>/dev/null || PROJ="${OUTPUT_ROOT:-output}/${PROJ_SLUG:-.}"
STATE_FILE="${PROJ}/logs/project-state.md"

# Infer DESIGN_TYPE from the arguments / dispatched steps.
# Precedence (most specific wins):
#   RCT keywords         → RCT
#   DiD/RD/IV/synth      → quasi-experimental:<sub>
#   Oaxaca/Kitagawa/
#     KHB/APC/decomp     → decomposition:<sub>
#   ML/NLP/network/ABM   → predictive-ML
#   DAG/causal/matching/
#     FE (causal intent) → observational-causal-with-DAG
#   else                 → observational-descriptive
ARGS_LC=$(echo "$ARGUMENTS" | tr '[:upper:]' '[:lower:]')
DESIGN_TYPE=""
DESIGN_REASON=""
case "$ARGS_LC" in
  *rct*|*randomized*controlled*|*field\ experiment*|*vignette*|*conjoint*|*list\ experiment*)
    DESIGN_TYPE="RCT"; DESIGN_REASON="keyword: RCT/experiment" ;;
  *stepped-wedge*|*stepped\ wedge*|*smart*|*cluster\ rct*|*audit*|*correspondence*)
    DESIGN_TYPE="RCT"; DESIGN_REASON="keyword: specialized experimental" ;;
  *did*|*difference-in-differences*|*diff-in-diff*)
    DESIGN_TYPE="quasi-experimental:DiD"; DESIGN_REASON="keyword: DiD" ;;
  *regression\ discontinuity*|*rdd*|*\ rd\ *)
    DESIGN_TYPE="quasi-experimental:RD"; DESIGN_REASON="keyword: RD" ;;
  *instrumental*|*\ iv\ *|*2sls*)
    DESIGN_TYPE="quasi-experimental:IV"; DESIGN_REASON="keyword: IV" ;;
  *synthetic\ control*|*synth*)
    DESIGN_TYPE="quasi-experimental:synth"; DESIGN_REASON="keyword: synth" ;;
  *oaxaca*|*blinder*)
    DESIGN_TYPE="decomposition:Oaxaca"; DESIGN_REASON="keyword: Oaxaca" ;;
  *kitagawa*)
    DESIGN_TYPE="decomposition:Kitagawa"; DESIGN_REASON="keyword: Kitagawa" ;;
  *khb*|*karlson*)
    DESIGN_TYPE="decomposition:KHB"; DESIGN_REASON="keyword: KHB" ;;
  *apc*|*age-period-cohort*|*hapc*)
    DESIGN_TYPE="decomposition:APC"; DESIGN_REASON="keyword: APC" ;;
  *decomposition*|*decompose*)
    DESIGN_TYPE="decomposition:Oaxaca"; DESIGN_REASON="keyword: decomposition (default sub=Oaxaca)" ;;
  *nlp*|*machine\ learning*|*\ ml\ *|*classifier*|*topic\ model*|*bert*|*transformer*|*network\ analysis*|*ergm*|*abm*|*agent-based*|*simulation*)
    DESIGN_TYPE="predictive-ML"; DESIGN_REASON="keyword: computational/ML" ;;
  *causal*|*dag*|*matching*|*fe\ causal*|*propensity*)
    DESIGN_TYPE="observational-causal-with-DAG"; DESIGN_REASON="keyword: causal/DAG" ;;
  *)
    DESIGN_TYPE="observational-descriptive"; DESIGN_REASON="fallback (no specific keyword matched)" ;;
esac

# Write to project-state.md (append; later entries override earlier ones by virtue of `tail -1` readers)
mkdir -p "$(dirname "$STATE_FILE")"
cat >> "$STATE_FILE" << STATEEOF

<!-- Emitted by scholar-design Save Output ($(date +%Y-%m-%d\ %H:%M)) -->
Design Type: ${DESIGN_TYPE}
Design Type Inference: ${DESIGN_REASON}
STATEEOF
echo "Design Type set to '${DESIGN_TYPE}' (${DESIGN_REASON}) in $STATE_FILE"
```

If the inferred DESIGN_TYPE is wrong, instruct the user: "Edit `${STATE_FILE}` and replace the `Design Type:` line before running `/scholar-analyze`. Valid values: observational-descriptive | observational-causal-with-DAG | RCT | quasi-experimental:<DiD|RD|IV|synth> | decomposition:<Oaxaca|Kitagawa|KHB|APC> | predictive-ML."

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-design"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t ${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}*.md 2>/dev/null | head -1)
fi
cat >> "$LOG_FILE" << LOGFOOTER

## Output Files
[list each output file path as a bullet]

## Summary
- **Steps completed**: [N completed]/[N total]
- **Files produced**: [count]
- **Errors**: [count, or 0]
- **Time finished**: $(date +%H:%M:%S)
LOGFOOTER
echo "Process log saved to $LOG_FILE"
```

---

## Quality Checklist

- [ ] Design matches the strength of claim (causal claim → causal design justified)
- [ ] Causal gate: /scholar-causal invoked for any DiD/FE/RD/IV/matching design
- [ ] Power analysis completed and MDES / required N reported
- [ ] Effect size assumption grounded in prior literature (citation provided)
- [ ] Variable dictionary complete: Y, X, M, W, all controls — every role populated
- [ ] Post-treatment variables identified and excluded from baseline controls
- [ ] Model selection justified by outcome type (not arbitrary)
- [ ] AME specified for any binary or ordered outcome
- [ ] SE type matches data structure (clustering level specified)
- [ ] Model presentation sequence planned (bivariate → full controls → FE → interaction)
- [ ] At least 3 robustness checks pre-specified; Oster delta or E-value included
- [ ] PAP registered on OSF (required for RCT/survey experiments; recommended for observational)
- [ ] Methods draft matches target journal word budget and structure
- [ ] Code/data availability statement present for Nature journals
- [ ] Design blueprint saved to `scholar-design-[slug]-[date].md`
- [ ] If computational: claim type specified (measurement / description / prediction / causal)
- [ ] If computational: corpus population defined and minimum N verified for chosen method
- [ ] If supervised ML or LLM annotation: annotation protocol documented; IRR target set (κ ≥ 0.70)
- [ ] If ML: train/test/validation split pre-specified; temporal split for time-series data
- [ ] If ML: primary evaluation metric pre-specified before training
- [ ] If network: boundary specification documented (node/edge definitions, missing tie strategy)
- [ ] If ABM: ODD protocol drafted; parameter space and sensitivity analysis planned
- [ ] If computational: all random seeds set; package versions locked (renv.lock / requirements.txt)
- [ ] If NCS / Science Advances: Computational Methods section drafted (Step 9i template)
- [ ] If cluster RCT: ICC estimated and reported; DEFF computed; analysis strategy (GEE vs. MLM) justified; minimum K ≥ 20 clusters
- [ ] If audit/correspondence: signal validity pre-tested; template equivalence verified; within-pair analysis specified; IRB deception protocol documented
- [ ] If stepped-wedge: design matrix documented; Hussey-Hughes model specified; period effects included; minimum K ≥ 6 clusters, S ≥ 3 steps
- [ ] If SMART: embedded DTRs enumerated; response criterion pre-specified; primary DTR comparison identified; Q-learning or IPW estimator chosen
- [ ] If Bayesian: all priors listed with justification; convergence diagnostics passed (R-hat < 1.01, ESS > 400); posterior predictive checks shown; prior sensitivity analysis performed; design analysis / assurance computed for sample size
- [ ] **Internal Review Panel (Step 11)**: 5 reviewer subagents (rigor / power / measurement / journal fit / feasibility) spawned in parallel
- [ ] **Review Scorecard** produced with per-dimension consensus ratings and ★★ cross-agent agreement flags
- [ ] **Reviser subagent** produced revised blueprint addressing all ★★ items and Weak ratings (or noted reasons for skipping)
- [ ] **User decision recorded**: yes / accept with edits / keep original / redesign (logged in process log at Step 11E)
- [ ] Saved blueprint reflects the user-accepted version; if `keep original`, Review Scorecard + Revision Notes appended as appendix

See [references/quant-methods.md](references/quant-methods.md) for detailed quantitative methods, causal identification code, and reporting standards.
See [references/qual-methods.md](references/qual-methods.md) for qualitative and mixed-methods approaches, credibility criteria, and reporting templates.
See [references/computational-design.md](references/computational-design.md) for corpus sampling code, annotation codebook structure, ML evaluation suite, network boundary templates, ODD protocol, and reproducibility checklist.
