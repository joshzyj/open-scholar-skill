---
name: scholar-causal
description: Comprehensive causal inference toolkit for social science research. Covers DAG construction, method selection, and thirteen identification strategies (OLS, DiD, RD, IV, FE, matching/reweighting, synthetic control, causal mediation, staggered DiD, DML/causal forests, bunching estimation, shift-share/Bartik instruments, distributional/quantile methods) — each with assumptions, diagnostics, R code, Stata code, and a write-up template. Use when the user needs to select and justify a causal identification strategy, build a causal DAG, or write the identification argument in their Methods section. Works between /scholar-hypothesis and /scholar-design.
tools: Read, WebSearch
argument-hint: "[research question] [key variables: X, Y, possible confounders/mediators] [data structure: panel/cross-section/natural experiment]"
user-invocable: true
---

# Scholar Causal — Comprehensive Causal Inference Toolkit

You are an expert in causal inference applying the potential outcomes framework, Pearl's do-calculus, and modern quasi-experimental methods to social science research. You help researchers select the right identification strategy, build causal diagrams, run diagnostics, and write the identification argument for their Methods section.

## Arguments

The user has provided: `$ARGUMENTS`

Identify: (1) the causal question (effect of X on Y), (2) data structure (cross-sectional, panel, natural experiment), (3) candidate confounders and mechanisms.

---

## Setup

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
```

**Process Logging (REQUIRED):**

Initialize the process log NOW by running:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
mkdir -p "${OUTPUT_ROOT}/logs"
SKILL_NAME="scholar-causal"
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
SKILL_NAME="scholar-causal"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}"*.md 2>/dev/null | head -1)
fi
echo "| [step#] | $(date +%H:%M:%S) | [Step Name] | [1-line action summary] | [output files or —] | ✓ |" >> "$LOG_FILE"
```

**IMPORTANT:** Shell variables do NOT persist across Bash tool calls. Every step MUST re-derive LOG_FILE before appending.

---

## PART 1: DAG FUNDAMENTALS

### Core Concepts

**Nodes**: Variables (observed or unobserved)
**Arrows (directed edges)**: Causal relationships (X → Y means X causes Y)
**No arrow**: No direct causal relationship

**Three path types**:

| Path type | Structure | What it does |
|-----------|-----------|-------------|
| **Chain (pipe)** | X → M → Y | Causal path; M is a mediator |
| **Fork (common cause)** | X ← C → Y | Backdoor path; C is a confounder |
| **Collider** | X → C ← Y | Blocked by default; opens if you condition on C |

**d-separation rule**:
- A path is **blocked** by a non-collider you condition on
- A path is **blocked** by a collider you do NOT condition on
- A path is **open** when none of its non-colliders are conditioned on AND none of its colliders are conditioned on

**Backdoor criterion**: Block all backdoor paths (common cause paths) without conditioning on any collider or post-treatment variable.

**Frontdoor criterion**: When all backdoor paths cannot be blocked (unobserved U → X and U → Y) but there is a mediator M such that (1) X blocks all backdoor paths to M, (2) there are no unblocked backdoor paths from M to Y, and (3) X → M → Y is the only path from X to Y, then the total effect can be identified via M:

```
P(Y | do(X)) = Σ_m P(M=m | X) Σ_x P(Y | X=x, M=m) P(X=x)
```

*Example*: Smoking (X) → tar in lungs (M) → cancer (Y); unobserved genetics (U) → smoking and cancer. Cannot block U, but can use the frontdoor via tar deposits.

### 6-Step DAG Construction

**Step 1 — State the causal question**: "What is the effect of [X] on [Y] for [population P]?"

**Step 2 — List variables**: Exposure (X), Outcome (Y), pre-treatment variables, post-treatment variables (do NOT control), unobserved confounders (U), instruments (Z).

**Step 3 — Draw the DAG** (text notation):
```
X → Y           X causes Y
C → X, C → Y   C is a confounder
X → M → Y      M mediates the effect
U → X, U → Y  U is unobserved confounder
Z → X          Z is an instrument
```

**Step 4 — Identify all backdoor paths** from X to Y. List causal paths (keep open) and non-causal paths (must block).

**Step 5 — Select adjustment set**: Control for variables that block all backdoor paths without opening new ones. Never control for mediators (blocks indirect effect), colliders (opens spurious path), or post-treatment variables (post-treatment bias).

**Step 6 — Assess identification**: Are all adjustment-set variables observable? If unobserved confounders remain, select one of the eight strategies below.

### dagitty R Code

```r
library(dagitty); library(ggdag)
g <- dagitty('dag {
  X -> Y; C -> X; C -> Y
  U -> X [unobserved]; U -> Y [unobserved]
  X -> M -> Y
}')
adjustmentSets(g, exposure = "X", outcome = "Y")
instrumentalVariables(g, exposure = "X", outcome = "Y")
ggdag_adjustment_set(tidy_dagitty(g), exposure = "X", outcome = "Y") + theme_dag()
```

See [references/dag-patterns.md](references/dag-patterns.md) for 18 common DAG patterns.

---

## PART 1.5: POTENTIAL OUTCOMES FOUNDATIONS

### Core Framework (Rubin 1974; Neyman 1923)

Each unit i has two **potential outcomes**: Y¹ᵢ (outcome if treated) and Y⁰ᵢ (outcome if untreated). The fundamental problem of causal inference: we observe only one potential outcome per unit.

**Treatment effect parameters**:

| Estimand | Definition | When to target |
|----------|-----------|----------------|
| **ATE** (Average Treatment Effect) | E[Y¹ − Y⁰] | Policy relevant for whole population |
| **ATT** (Average Treatment Effect on Treated) | E[Y¹ − Y⁰ \| D=1] | Evaluating existing programs; matching estimators |
| **ATU** (Average Treatment Effect on Untreated) | E[Y¹ − Y⁰ \| D=0] | Targeting new interventions |
| **LATE** (Local ATE) | E[Y¹ − Y⁰ \| Complier] | IV estimand; near-cutoff for RD |

ATE = ATT only when treatment effects are homogeneous or treatment assignment is truly random. In most social science observational studies, ATT ≠ ATE because treatment selection is non-random.

### Selection Bias Decomposition

The naive simple difference in means decomposes as (Cunningham 2021):

```
E[Y|D=1] − E[Y|D=0]
= ATE
+ Selection bias:          E[Y⁰|D=1] − E[Y⁰|D=0]   ← pre-treatment baseline difference
+ Heterogeneous TE bias:   (1−P(D=1)) × (ATT − ATU)  ← effect varies by who selects in
```

This decomposition makes explicit why naive comparisons fail: treated and untreated groups differ in both baseline outcomes (selection bias) and in how much they benefit from treatment (effect heterogeneity).

**Implication for identification strategies**: Each strategy below eliminates one or more of these components under different assumptions.

### SUTVA (Stable Unit Treatment Value Assumption)

SUTVA requires:
1. **Homogeneous treatment**: No variation in treatment doses (D is binary and consistent)
2. **No spillovers**: Unit i's potential outcomes are unaffected by unit j's treatment status
3. **No general equilibrium effects**: Treatment effect at scale equals treatment effect at margin

SUTVA violations are common in social science: peer effects in job training programs, network contagion in health interventions, wage equilibrium effects of minimum wage changes. When SUTVA is violated, report spillover estimates alongside direct effects.

### Randomization Inference (Fisher 1935)

For small samples (or as a robustness check), use randomization-based inference rather than asymptotic tests:

1. Assert the **sharp null** (H₀: no treatment effect for any unit: Yᵢ¹ = Yᵢ⁰ for all i)
2. Under the sharp null, the unobserved potential outcome equals the observed outcome
3. Permute treatment assignment; recalculate test statistic for each permutation
4. Exact p-value = fraction of permutations producing a test statistic ≥ observed

```r
library(ri2)  # Randomization inference in R
ri_out <- conduct_ri(
  formula    = y ~ treat,
  assignment = "treat",
  declaration = declare_ra(N = nrow(df), prob = 0.5),
  sharp_hypothesis = 0,
  data = df,
  sims = 1000
)
summary(ri_out)

# Manual permutation test
obs_diff <- mean(df$y[df$treat==1]) - mean(df$y[df$treat==0])
perm_diffs <- replicate(10000, {
  perm_treat <- sample(df$treat)
  mean(df$y[perm_treat==1]) - mean(df$y[perm_treat==0])
})
p_value <- mean(abs(perm_diffs) >= abs(obs_diff))
cat("Exact p-value:", p_value, "\n")
```

**When to use**: Small N (< 50 treated units); policy contexts where exact p-values matter; when asymptotic approximation is suspect.

---

## PART 2: METHOD SELECTION DECISION TREE

| Data structure | Key variation | Core assumption | Best strategy |
|---------------|---------------|-----------------|---------------|
| RCT | Random assignment | SUTVA + compliance | OLS / ITT / LATE |
| Cross-section, rich controls | Selection on observables | CIA / unconfoundedness | OLS + Oster delta; Matching |
| Many confounders, large N | Selection on observables | CIA | Double ML (DML) |
| Exogenous shock, two periods | Treatment adoption | Parallel trends | 2×2 DiD |
| Staggered policy adoption | Treatment timing varies | Parallel trends (no forbidden comparisons) | Callaway-Sant'Anna; Sun-Abraham |
| Threshold-based assignment | Near-cutoff as-if-random | Continuity of potential outcomes | Sharp RD |
| Threshold-based take-up | Partial compliance at cutoff | Fuzzy RD / LATE | Fuzzy RD (2SLS at cutoff) |
| Exogenous instrument available | Unobservable confounders | Exclusion restriction + relevance | IV / 2SLS |
| Panel data | Time-invariant confounders | No time-varying confounding | Panel FE (TWFE) |
| Observational, no instrument | Covariate overlap/balance | Overlap + unconfoundedness | PSM / CEM / IPW / doubly robust |
| Few treated units, long pre-period | No valid controls | Synthetic control (pre-period fit) | Synth / SynthDiD |
| Mechanism/mediation question | Mediator identified | Sequential ignorability | Causal mediation (ACME) |
| Known threshold, agents sort around it | Bunching at kink/notch | Counterfactual density smooth | Bunching estimation |
| Local exposure to aggregate shocks | Shift-share (Bartik) structure | Exogenous shocks OR exogenous shares | Shift-share / Bartik IV |
| Effects across outcome distribution | Distributional heterogeneity | Quantile-specific assumptions | Quantile regression / RIF-OLS / CiC |

**Decision flow**:
1. Is treatment randomly assigned? → Use RCT estimator.
2. Is there a natural experiment (policy, cutoff, lottery)? → DiD / RD / IV.
3. Is there a plausible instrument? → IV.
4. Is there panel data? → Panel FE or DiD.
5. Is treatment based on a score/threshold? → RD.
6. Is the question about mechanisms? → Causal mediation.
7. Is there bunching at a known kink or notch? → Bunching estimation.
8. Is there local exposure variation to aggregate shocks? → Shift-share / Bartik IV.
9. Do you care about effects across the distribution, not just means? → Quantile / distributional methods.
10. Otherwise, rich observational data? → Matching/reweighting + sensitivity.

---

## PART 3: THIRTEEN STRATEGY DEEP-DIVES

---

### Strategy 1: OLS + Observational Controls

#### Assumptions
- **Conditional Independence (CIA)**: Treatment assignment is independent of potential outcomes conditional on observed controls X: (Y⁰, Y¹) ⊥ T | X
- **No unmeasured confounders**: All variables on backdoor paths are measured and included
- **Overlap**: Every unit has positive probability of treatment given X

#### Standard Workflow
1. Draw DAG; identify minimal adjustment set
2. Estimate OLS with full control set
3. Check robustness: add/drop controls; subset by groups
4. Report Oster (2019) sensitivity (delta)

#### Diagnostics
- Variance inflation factor (VIF < 10) for collinearity
- Residual plots for heteroscedasticity (Breusch-Pagan test)
- Influential observations: Cook's distance, leverage
- Balance check: compare treated/control means on all controls

#### R Code
```r
library(estimatr); library(sensemakr)

# Baseline OLS with robust SEs
m1 <- lm_robust(y ~ x + controls, data = df, se_type = "HC2")
summary(m1)

# Oster (2019) sensitivity: how much stronger must unobservables be?
m_uncontrolled <- lm(y ~ x, data = df)
m_controlled   <- lm(y ~ x + controls, data = df)
sens <- sensemakr(m_controlled, treatment = "x",
                  benchmark_covariates = "key_control",
                  kd = 1:3)
summary(sens)
plot(sens, type = "contour")

# Partial R2 and robustness value
sens$sensitivity_stats
```

#### Stata Code
```stata
* Baseline
regress y x controls, robust
estimates store m1

* Oster delta (psacalc package)
psacalc delta x, mcontrol(controls) rmax(1.3) beta(0)

* ATE with covariate adjustment
teffects ra (y controls) (x)
```

#### Write-up Template
> "We estimate the effect of [X] on [Y] using OLS regression. Identification rests on the conditional independence assumption: conditional on [list controls], we assume treatment assignment is as good as random. The primary threat is unmeasured confounders; we address [confounder 1] by including [proxy]. Following Oster (2019), the omitted variable would need to be [delta] times as strongly associated with [Y] as all observed controls combined to nullify our estimate (Table A[X]), a threshold we consider implausible because [reason]."

#### Common Pitfalls
- Controlling for mediators → blocks indirect effect (post-treatment bias)
- Controlling for colliders → opens spurious path
- Including too many controls with small N → overfitting; use regularization or theory-guided selection

---

### Strategy 2: Difference-in-Differences (DiD)

#### Assumptions
- **Parallel trends**: In the absence of treatment, treated and control units would have trended identically
- **No anticipation**: Treatment effects do not appear before treatment
- **SUTVA**: No spillovers between treated and control units
- **Stable composition**: Panel composition does not change in response to treatment

#### Standard Workflow

**Classic 2×2 DiD:**
1. Confirm two groups (treated/control) and two periods (pre/post)
2. Test parallel pre-trends (event study)
3. Estimate: Y_it = α + β(Treat_i × Post_t) + γ_i + δ_t + ε_it
4. Cluster SEs at the unit (state/firm) level
5. Report event study plot and falsification tests

**Staggered DiD (preferred for multi-period panel):**
1. Document treatment timing distribution across units
2. Estimate group-time ATTs: Callaway & Sant'Anna (2021) or Sun & Abraham (2021)
3. Aggregate to overall ATT or dynamic (event-study) ATTs
4. Avoid standard TWFE when treatment effects are heterogeneous (Roth et al. 2023)

#### Diagnostics
- Event study: coefficients on pre-treatment leads should be near zero
- Placebo test: run DiD on a "fake" treatment period in the pre-trend window
- Sensitivity to control group choice (never-treated vs. not-yet-treated)
- Parallel trends test for observable covariates
- Bacon decomposition (for staggered): identify weight on "forbidden comparisons"

#### R Code
```r
library(fixest); library(did); library(bacondecomp)

# Classic 2x2 DiD with unit + year FE
did_classic <- feols(y ~ i(year, treated, ref = -1) | unit + year,
                     data = df, cluster = ~unit)
iplot(did_classic, main = "Event Study: Pre-trends Test")

# Callaway & Sant'Anna (2021) for staggered adoption
cs <- att_gt(yname    = "y",
             tname    = "year",
             idname   = "id",
             gname    = "first_treat",   # 0 = never treated
             data     = df,
             control_group = "nevertreated",
             est_method    = "reg")
aggte(cs, type = "dynamic")   # Dynamic ATTs (event study)
aggte(cs, type = "simple")    # Average ATT across all groups/periods
ggdid(aggte(cs, type = "dynamic"))

# Sun & Abraham (2021) via fixest
sa <- feols(y ~ sunab(cohort, year) | unit + year,
            data = df, cluster = ~unit)
iplot(sa)

# Bacon decomposition: shows weight on each 2x2 comparison
bd <- bacon(y ~ treat_post, data = df, id_var = "unit", time_var = "year")
ggplot(bd, aes(x = weight, y = estimate, color = type)) + geom_point()
```

#### Stata Code
```stata
* Classic DiD with unit + year FE
reghdfe y i.treated##i.post, absorb(unit year) cluster(unit)

* Event study
gen rel_time = year - first_treat
reghdfe y ib(-1).rel_time, absorb(unit year) cluster(unit)
coefplot, keep(*.rel_time) vertical yline(0) xline(4.5)

* Callaway-Sant'Anna via csdid package
ssc install csdid, replace
csdid y, ivar(id) tvar(year) gvar(first_treat) notyet
csdid_plot, style(rspike)
```

#### Write-up Template
> "We use a difference-in-differences (DiD) design comparing [treated units] to [control units] before and after [policy/event] in [year]. Identification rests on the parallel trends assumption: absent treatment, treated and control units would have followed the same outcome trajectory. We provide evidence for this through an event study, which shows statistically indistinguishable pre-treatment trends (F-test for joint zero: F([k],[df]) = [X], p = [Y]; Figure [X]). [For staggered:] Because treatment adoption is staggered across [states/firms], we use the Callaway and Sant'Anna (2021) estimator to avoid biased estimates from 'forbidden comparisons' in which earlier-treated units serve as controls for later-treated units. Standard errors are clustered at the [unit] level."

#### Triple Differences (DDD) — when DiD parallel trends is under threat

When treated and control groups differ in pre-existing trends, adding a third comparison group can recover the treatment effect. DDD adds a within-state or within-group placebo comparison:

```
Y_ijt = α + β₁τ_t + β₂δ_j + β₃D_i + β₄(δ_j × τ_t) + β₅(τ_t × D_i) + β₆(δ_j × D_i)
        + β₇(δ_j × τ_t × D_i) + ε_ijt
```

β₇ is the DDD estimate; it controls for group-specific time trends that would otherwise violate the DiD parallel trends assumption.

*Example*: Studying minimum wage on low-wage workers (affected group, i=1) vs. high-wage workers (unaffected group, i=0) in treated states (j=1) vs. control states (j=0); the DDD removes state-level time trends that affect all workers.

```r
# Triple DiD in R via fixest
ddd <- feols(y ~ i(post, treat_group, ref = 0):i(treat_state, ref = 0) |
               unit + year + state^year, data = df, cluster = ~state)
summary(ddd)
```

#### Standard Error Correction (Bertrand, Duflo, Mullainathan 2004)

Serial correlation within units over time causes downward bias in clustered SEs when there are few groups. Solutions:

1. **Cluster at treatment-assignment level** (most common): `cluster = ~state` when treatment is state-level
2. **Block bootstrap**: Resample treatment units (states/firms) with replacement; compute BS distribution of β
3. **Collapse to single pre/post periods**: Average each unit into one pre-period and one post-period observation, then run standard DiD on two-period data
4. **Wild cluster bootstrap** (preferred when < 40 clusters): `boottest` Stata or `fwildclusterboot` R package

```r
library(fwildclusterboot)
# Wild cluster bootstrap when few treatment clusters
boot_did <- boottest(did_classic, clustid = "state", param = "treated::post",
                     B = 9999, seed = 42)
summary(boot_did)
```

#### First-Stage Validation

Before examining your main outcome, demonstrate that the treatment (policy/event) actually changed the proximate mechanism as expected. This strengthens credibility of the DiD design.

*Example* (Miller et al. 2019): Before showing ACA Medicaid expansion reduced mortality, first show it significantly increased Medicaid enrollment. A null first stage should prompt reconsideration of the design.

```r
# First stage: does treatment affect take-up/exposure?
first_stage <- feols(enrollment ~ i(year, treated, ref = -1) | unit + year,
                     data = df, cluster = ~unit)
iplot(first_stage, main = "First Stage: Treatment × Take-up")
```

#### Common Pitfalls
- Staggered adoption with heterogeneous effects → TWFE is biased; use CS-2021 or SA-2021
- Never testing pre-trends — always run event study
- Serial correlation in errors → cluster SEs at treatment-assignment level; use wild bootstrap if < 40 clusters
- Ignoring spillovers between treated and control units
- Pre-treatment similarities do not guarantee parallel *counterfactual* trends — they are suggestive but not sufficient

---

### Strategy 3: Regression Discontinuity (RD)

#### Sharp RD Assumptions
- **Continuity**: Potential outcomes are continuous at the cutoff
- **No manipulation**: Units cannot precisely sort around the cutoff (McCrary test)
- **Local randomization**: Near-cutoff units are as-good-as randomly assigned

#### Fuzzy RD Assumptions
- Continuity of potential outcomes
- First-stage discontinuity: treatment probability jumps at cutoff
- **Exclusion restriction**: Cutoff affects outcome only through treatment (LATE interpretation)

#### Standard Workflow
1. Plot raw data: bin scatter of Y on running variable; inspect for visual jump
2. Test no-manipulation: McCrary / `rddensity` density test
3. **Check for heaping**: Inspect running variable for artificial clustering at round numbers or regular intervals (e.g., birth year in administrative data, test scores in multiples of 5). Heaping indicates measurement error or strategic behavior — can invalidate continuity assumption
4. Test covariate continuity at cutoff (should be no discontinuity in predetermined covariates)
5. Select bandwidth: Calonico-Cattaneo-Titiunik (2014) optimal bandwidth
6. Estimate **local linear** regression (triangular kernel assigns more weight to near-cutoff observations; preferred over global polynomials)
7. [Fuzzy RD:] Two-stage: instrument = 1(running ≥ cutoff); endogenous var = treatment
8. Robustness: alternative bandwidths; polynomial order; donut hole (exclude near-cutoff); placebo cutoffs

**On polynomial order (Gelman & Imbens 2019)**: Use local linear or local quadratic only. High-order global polynomials produce poor boundary estimates and spurious results — this is a common mistake in applied work. Always prefer `rdrobust` (local polynomial) over `lm(y ~ poly(running, 4) + treat)`.

#### Diagnostics
- McCrary density test p-value (should be > 0.05)
- **Heaping check**: Histogram of running variable; any clustering at round numbers?
- Placebo cutoffs: run RD at fake cutoffs within the data; should find null results
- Bandwidth sensitivity plot (½h, ¾h, h, 2h)
- Covariate balance at cutoff (predetermined covariates should show zero discontinuity)

#### R Code
```r
library(rdrobust); library(rddensity); library(ggplot2)

# Optimal bandwidth + sharp RD estimate
rdd <- rdrobust(y = df$y, x = df$running, c = cutoff)
summary(rdd)
rdplot(y = df$y, x = df$running, c = cutoff,
       title = "RD Plot", x.label = "Running Variable", y.label = "Outcome")

# No-manipulation test (McCrary)
dens <- rddensity(X = df$running, c = cutoff)
summary(dens)  # p > 0.05 supports no manipulation
rdplotdensity(dens, df$running)

# Covariate balance at cutoff
for (cov in c("age", "female", "prior_y")) {
  rdd_cov <- rdrobust(y = df[[cov]], x = df$running, c = cutoff)
  cat(cov, ": coef =", round(rdd_cov$coef[1], 3),
      "p =", round(rdd_cov$pv[3], 3), "\n")
}

# Fuzzy RD: 2SLS using cutoff as instrument
library(AER)
df$above <- as.integer(df$running >= cutoff)
frdd <- ivreg(y ~ treatment + controls | above + controls, data = df)
summary(frdd, diagnostics = TRUE)

# Bandwidth sensitivity
bws <- c(rdd$bws[1]*0.5, rdd$bws[1]*0.75, rdd$bws[1], rdd$bws[1]*1.5)
for (h in bws) {
  r <- rdrobust(df$y, df$running, c = cutoff, h = h)
  cat("bw =", round(h,2), ": coef =", round(r$coef[1],3),
      "95% CI [", round(r$ci[1,1],3), ",", round(r$ci[1,2],3), "]\n")
}
```

#### Stata Code
```stata
* Sharp RD
rdrobust y running_var, c(cutoff)
rdplot y running_var, c(cutoff)

* McCrary density test
rddensity running_var, c(cutoff)

* Covariate balance
foreach cov in age female prior_y {
    rdrobust `cov' running_var, c(cutoff)
}

* Fuzzy RD (2SLS)
ivregress 2sls y controls (treatment = above_cutoff), robust
estat firststage
```

#### Write-up Template
> "We use a [sharp/fuzzy] regression discontinuity (RD) design exploiting the [cutoff value] threshold of [running variable]. Units scoring just above [below] the cutoff are assigned to [treatment]. Identification rests on the assumption that potential outcomes are continuous at the threshold, and that units cannot precisely manipulate their score. The McCrary (2008) density test finds no evidence of bunching (p = [X]; Figure A[X]). Predetermined covariates are continuous at the threshold (Table A[X]). We estimate the RD using local linear regression with the Calonico et al. (2014) optimal bandwidth (h = [X]). [Fuzzy:] Because compliance with the threshold is partial (first-stage discontinuity = [X], F = [X]), we use the fuzzy RD estimator, which identifies the LATE for compliers at the cutoff. Results are robust to alternative bandwidths (Table A[X])."

#### Honest Confidence Intervals (RDHonest)

When bandwidth is chosen based on data, standard CIs may undercover. Use `RDHonest` for valid CIs under weaker assumptions (Armstrong & Kolesár 2020):

```r
library(RDHonest)
rdhonest_out <- RDHonest(y ~ running, data = df, cutoff = cutoff,
                          kern = "triangular", M = 0.1)
print(rdhonest_out)  # CI guaranteed to cover at correct rate
```

#### Common Pitfalls
- Wide bandwidth that includes heterogeneous units far from cutoff
- Ignoring manipulation of running variable (always run McCrary / rddensity test)
- **High-degree global polynomials** → extrapolation and boundary artifacts; always use local linear/quadratic (Gelman & Imbens 2019)
- Not testing covariate continuity (essential falsification)
- Heaping in running variable → check for nonrandom rounding before proceeding
- Clustering SEs by running variable is incorrect (Kolesár & Rothe 2018); use HC robust SEs

---

### Strategy 4: Instrumental Variables (IV / 2SLS)

#### Assumptions (Angrist, Imbens & Rubin 1996 — five conditions)
1. **SUTVA**: Potential outcomes of unit i are unaffected by other units' instrument values
2. **Independence**: Z is independent of potential outcomes and treatments: {Y(D¹,1), Y(D⁰,0), D¹, D⁰} ⊥ Z
3. **Exclusion restriction**: Z affects Y only through D: Y(D,0) = Y(D,1) — no direct path Z → Y
4. **Relevance (first stage)**: E[D¹ − D⁰] ≠ 0; Z induces variation in D (F > 10 is the rule of thumb)
5. **Monotonicity**: For all units, Z weakly moves treatment in the same direction (no defiers); ensures LATE > 0 when ITT > 0

Under heterogeneous treatment effects, IV identifies the **LATE for compliers only** — units whose treatment status changes because of Z. LATE ≠ ATE when effect heterogeneity exists (common in social science).

**"Weird instrument" principle (Cunningham 2021)**: An instrument's strength partly comes from how counterintuitive the Z → D link seems at first glance. If the Z → Y relationship looks obviously logical without understanding the treatment pathway, the exclusion restriction likely fails. A good instrument "confuses people who don't know the mechanism." Ask: *Why would Z affect Y at all, if not through D?*

#### Standard Workflow
1. Argue for all three IV conditions; find pre-existing literature or institutional argument
2. Estimate first stage; check F-statistic (robust Kleibergen-Paap rk Wald F)
3. Report reduced form (Z → Y directly) for transparency
4. Estimate 2SLS; compare to OLS for Hausman test
5. Placebo tests: Z should not predict pre-treatment outcomes

#### Diagnostics
- First-stage F (Cragg-Donald Wald; Kleibergen-Paap rk Wald for robust)
- Sargan-Hansen J test for overidentification (if multiple instruments)
- Hausman test (OLS vs. IV consistency)
- Reduced form: if Z → Y reduced form is significant but 2SLS is not → weak instrument
- Placebo outcomes: test Z → Y for outcomes that should be unaffected

#### R Code
```r
library(AER); library(fixest); library(lfe)

# First stage
fs <- lm(x ~ z + controls, data = df)
summary(fs)
# Robust F: use sandwich SEs
library(lmtest); library(sandwich)
coeftest(fs, vcov = vcovHC(fs, "HC1"))

# 2SLS via AER
iv <- ivreg(y ~ x + controls | z + controls, data = df)
summary(iv, diagnostics = TRUE)
# diagnostics = TRUE shows: Weak instruments (F), Wu-Hausman, Sargan

# 2SLS via fixest (faster for panel + FE)
iv_fe <- feols(y ~ controls | id + year | x ~ z, data = df, cluster = ~id)
summary(iv_fe)
fitstat(iv_fe, ~ kpr + sargan)  # KP rk Wald F; Sargan J

# LATE interpretation
cat("LATE =", coef(iv)["x"],
    "interpreted as effect for compliers (units induced by Z from untreated to treated)\n")
```

#### Stata Code
```stata
* First stage (check F-stat)
regress x z controls, robust
estat firststage

* 2SLS
ivregress 2sls y controls (x = z), robust first
estat endogenous   // Wu-Hausman test
estat overid       // Sargan-Hansen (if over-identified)

* With fixed effects (ivreg2 + reghdfe)
ivreg2 y controls (x = z), cluster(id) robust first
```

#### Write-up Template
> "We address the endogeneity of [X] using [Z] as an instrumental variable. [Z] satisfies the relevance condition: a one-unit increase in [Z] increases [X] by [b] units (F = [X] in the first stage, exceeding the Stock-Yogo 10% bias critical value of [CV]; Table A[X]). The exclusion restriction requires [Z] to affect [Y] only through [X]; this is plausible because [Z is determined by X / predates outcomes by Y years / is administratively set without reference to individual outcomes]. Independence requires [Z] to be uncorrelated with confounders of X–Y; [provide evidence: geographic/administrative determination, randomization, placebo tests]. We present the reduced form alongside IV estimates. The Hausman test [rejects/does not reject] OLS consistency (χ²([df]) = [X], p = [Y])."

#### Weak Instrument Remedies

When F < 10, 2SLS is badly biased toward OLS. Options:

```r
# LIML (Limited Information Maximum Likelihood) — less biased than 2SLS with weak instruments
library(ivreg)
iv_liml <- ivreg(y ~ x + controls | z + controls, data = df,
                 method = "LIML")
summary(iv_liml, diagnostics = TRUE)

# Anderson-Rubin test (valid CI regardless of instrument strength)
library(ivmodel)
iv_mod <- ivmodel(Y = df$y, D = df$x, Z = df$z,
                  intercept = TRUE, beta0 = 0)
AR.test(iv_mod)  # AR confidence interval — robust to weak instruments
```

#### Common Pitfalls
- Weak instruments (F < 10) → 2SLS biased; use LIML or Anderson-Rubin CI; "real solution is to get better instruments" (Bound, Jaeger & Baker 1995)
- Exclusion restriction is untestable — rely on theoretical argument, reduced form, and placebo outcomes
- LATE ≠ ATE: IV identifies only complier LATE; discuss whether compliers are the relevant policy population
- Overloading the model with many instruments (e.g., 30 quarter-of-birth × cohort dummies) weakens identification despite high F — just-identified designs (one instrument) are most credible
- A strong first stage does not guarantee a valid exclusion restriction

---

### Strategy 5: Panel Fixed Effects (TWFE)

#### Assumptions
- **Strict exogeneity**: E[ε_it | X_i1, …, X_iT, α_i] = 0 (no feedback from past Y to current X)
- **Sufficient within-unit variation**: X must change within units over time
- **No time-varying confounders**: Time-varying variables that co-move with X must be controlled

#### Standard Workflow
1. Verify within-unit variation in X (within SD > 0; % of units with change)
2. Estimate TWFE: Y_it = βX_it + γ_t + α_i + ε_it
3. Add time-varying controls for observable time-varying confounders
4. Check: does coefficient change substantially when time-varying controls are added?
5. First-difference model as robustness check (eliminates unit FE differently)
6. Hausman test: compare FE vs. RE if variation is mainly between units

#### Diagnostics
- Within-variation check (meaningful within-person change in X?)
- Wooldridge autocorrelation test for panel data
- Cross-sectional dependence (Pesaran CD test for macro panels)
- Sensitivity to control additions

#### R Code
```r
library(fixest); library(plm)

# Two-way FE (unit + year)
fe_twfe <- feols(y ~ x + time_varying_ctrl | id + year,
                 data = df, cluster = ~id)
summary(fe_twfe)

# First differences (robust to serial correlation)
fe_fd <- feols(y ~ x + time_varying_ctrl | year,
               data = df %>% arrange(id, year) %>%
               group_by(id) %>% mutate(across(c(y,x), ~. - lag(.))),
               cluster = ~id)

# Check within variation
df %>% group_by(id) %>%
  summarise(within_sd = sd(x, na.rm=T)) %>%
  summarise(pct_varying = mean(within_sd > 0, na.rm=T))

# Hausman test FE vs RE
fe_plm <- plm(y ~ x + time_varying_ctrl, data = df,
              index = c("id","year"), model = "within", effect = "twoways")
re_plm <- plm(y ~ x + time_varying_ctrl, data = df,
              index = c("id","year"), model = "random", effect = "twoways")
phtest(fe_plm, re_plm)
```

#### Stata Code
```stata
* Two-way FE
reghdfe y x time_varying_ctrl, absorb(id year) cluster(id)

* First differences
xtset id year
regress d.y d.x d.time_varying_ctrl, robust

* Check within variation
bysort id: egen sd_x = sd(x)
summarize sd_x if sd_x > 0

* Hausman test
xtreg y x, fe
estimates store fe
xtreg y x, re
estimates store re
hausman fe re
```

#### Write-up Template
> "We estimate person-level fixed effects (FE) models identifying the effect of [X] from within-[person/firm/state] variation over time. This absorbs all time-invariant confounders — including [ability, family background, personality, geographic context] — that might simultaneously predict [X] and [Y]. We include year fixed effects to remove common time shocks. The remaining identification threat is time-varying confounders that co-move with changes in [X]; we address this by controlling for [time-varying controls]. [X] varies sufficiently within [persons] to identify the effect (within-SD = [X]; [Y]% of [persons] exhibit any change). Standard errors are clustered at the [person] level."

#### Two Critical Caveats (Cunningham 2021)

**Caveat 1 — Reverse causality**: Strict exogeneity fails if past outcomes affect current treatment (Y_{t-1} → X_t). FE does not solve simultaneity bias. *Example*: Police presence and crime rates — more crime attracts more police, but more police may reduce crime; FE cannot disentangle this without an instrument or natural experiment.

**Caveat 2 — Time-varying unobserved heterogeneity**: FE only removes time-invariant confounders (α_i). If unobserved factors change over time and co-move with X (e.g., a person's health worsens and they simultaneously change their labor supply), demeaning creates a biased estimator. Always draw a time-varying DAG and assess whether unobserved time-varying confounders exist.

**Cluster rule of thumb**: Valid cluster-robust inference requires ≥ 30 clusters (treatment-assignment units). With fewer clusters, use the wild cluster bootstrap (`fwildclusterboot` in R, `boottest` in Stata).

#### Common Pitfalls
- FE removes time-invariant X (cannot estimate effect of race, sex, country of origin)
- Staggered treatment + heterogeneous effects → standard TWFE biased (use DiD estimators above)
- Reverse causality still possible if past Y → current X (strict exogeneity violation) — FE does not fix this
- Time-varying unobserved confounders invalidate FE — check your DAG for time-varying paths
- Attrition on unobservables biases FE estimates
- < 30 clusters → cluster SEs are too small; use wild bootstrap

---

### Strategy 6: Matching and Reweighting ← NEW

#### Core Logic
Matching and reweighting construct a comparison group that resembles the treated group on observed pre-treatment characteristics, making the conditional independence assumption (CIA) more credible by improving covariate balance.

#### Assumptions
- **Unconfoundedness / CIA**: (Y⁰, Y¹) ⊥ T | X (no unmeasured confounders)
- **Overlap (common support)**: 0 < P(T=1|X) < 1 for all X (every treated unit has comparable controls)
- **SUTVA**: Stable unit treatment value assumption

#### Family of Methods

| Method | Core idea | Best for |
|--------|-----------|----------|
| Propensity Score Matching (PSM) | Match on P(T=1\|X) | N moderate; easy to explain |
| Coarsened Exact Matching (CEM) | Exact match on coarsened X | Categorical/ordinal confounders |
| Entropy Balancing | Reweight controls to match treated moments | Flexible moment conditions |
| IPW / IPTW | Weight by 1/P(T=1\|X) | Marginal structural models; time-varying treatment |
| Doubly Robust (AIPW) | Combines outcome model + propensity score | Protection against one model misspecification |

#### Distance Metrics for Matching

| Metric | Formula | Notes |
|--------|---------|-------|
| Euclidean | √Σ(X_ni − X_nj)² | Scale-dependent; standardize first |
| Normalized Euclidean | √Σ(X_ni − X_nj)²/σ²_n | Scale-invariant |
| **Mahalanobis** | √(X_i−X_j)′Σ⁻¹(X_i−X_j) | Accounts for correlations between Xs; preferred for multivariate X |
| Propensity score | \|e(X_i) − e(X_j)\| | Balancing score: if CIA holds on X, it holds on e(X) |

**Bias-corrected matching (Abadie & Imbens 2006)**: When exact matching is impossible, approximate nearest-neighbor matching introduces bias because matched units differ slightly on X. The bias-corrected estimator subtracts this discrepancy:

```
δ̂_ATT^BC = (1/N_T) Σ_{D=1} [(Y_i − Y_j(i)) − (μ̂⁰(X_i) − μ̂⁰(X_j(i)))]
```

where μ̂⁰(X) is the fitted value from OLS of Y on X among controls. Use `Matching` package in R with `BiasAdjust = TRUE`.

#### Standard Workflow
1. Estimate propensity score (logistic regression or flexible ML)
2. Check overlap: histogram of p-scores for treated vs. control; **trim units without common support**
3. Match/reweight using preferred method (Mahalanobis or entropy balancing often outperform PSM)
4. Assess balance: standardized mean differences (SMD < 0.1 after matching); love plot
5. Estimate ATT on matched/weighted sample; consider bias correction for approximate matching
6. Sensitivity analysis: Rosenbaum bounds (Gamma)

**Canonical example (Lalonde 1986 / Dehejia-Wahba 2002)**: The NSW job training experiment provides the gold standard: true ATT = +$1,794 in earnings. Non-experimental comparisons using CPS/PSID controls give wildly biased estimates (often negative). Propensity score matching recovers $1,473–$1,774, close to the truth — but only after trimming the extreme right tail of the control propensity score distribution where no treated units exist.

#### Diagnostics
- Love plot (standardized mean differences before/after)
- SMD < 0.1 for all covariates after matching
- Overlap plot (common support)
- Effective sample size after weighting (should not be too small)
- Rosenbaum bounds for hidden bias sensitivity

#### R Code
```r
library(MatchIt); library(cobalt); library(WeightIt); library(rbounds)

# Propensity score matching (nearest neighbor, 1:1, caliper = 0.2 SD)
m_out <- matchit(treat ~ x1 + x2 + x3,
                 data = df, method = "nearest",
                 distance = "logit", ratio = 1,
                 caliper = 0.2, std.caliper = TRUE)
summary(m_out, un = FALSE)  # Balance summary
love.plot(m_out, threshold = 0.1, stars = "std")  # Love plot

# ATT on matched sample
m_data <- match.data(m_out)
att_psm <- lm(y ~ treat + x1 + x2 + x3, data = m_data, weights = weights)
summary(att_psm)

# Coarsened exact matching (CEM)
m_cem <- matchit(treat ~ x1 + x2 + x3,
                 data = df, method = "cem")
love.plot(m_cem, threshold = 0.1)

# Entropy balancing via WeightIt
w_eb <- weightit(treat ~ x1 + x2 + x3,
                 data = df, method = "ebal",
                 estimand = "ATT")
summary(w_eb)  # Effective N, balance
love.plot(w_eb, threshold = 0.1)
att_eb <- lm_weightit(y ~ treat, data = df, weightit = w_eb)
summary(att_eb)

# IPW
w_ipw <- weightit(treat ~ x1 + x2 + x3,
                  data = df, method = "ps",
                  estimand = "ATE")
att_ipw <- lm_weightit(y ~ treat, data = df, weightit = w_ipw)

# Doubly robust (AIPW) via WeightIt
w_dr <- weightit(treat ~ x1 + x2 + x3,
                 data = df, method = "ps", estimand = "ATE")
att_dr <- lm_weightit(y ~ treat + x1 + x2 + x3, data = df, weightit = w_dr)

# Rosenbaum bounds sensitivity
matched_y <- m_data$y[m_data$treat == 1]
control_y <- m_data$y[m_data$treat == 0]
psens(matched_y, control_y, Gamma = 3, GammaInc = 0.25)
# If result holds at Gamma > 2: robust to hidden bias that doubles treatment odds
```

#### Stata Code
```stata
* PSM via psmatch2
ssc install psmatch2
psmatch2 treat x1 x2 x3, outcome(y) neighbor(1) caliper(0.02) common
pstest x1 x2 x3, both graph

* CEM (coarsened exact matching)
ssc install cem
cem x1 (0 25 50 75 100) x2 x3, treatment(treat)
regress y treat [iweight=cem_weights], robust

* Entropy balancing (ebalance)
ssc install ebalance
ebalance treat x1 x2 x3, targets(1)
regress y treat [pweight=_webal], robust

* IPW via teffects
teffects ipw (y) (treat x1 x2 x3), ate
teffects ipwra (y x1 x2 x3) (treat x1 x2 x3), ate  // doubly robust IPWRA
```

#### Write-up Template
> "To improve covariate balance between [treated] and [control] units, we use [entropy balancing / propensity score matching / coarsened exact matching]. [Entropy balancing: Entropy balancing (Hainmueller 2012) reweights control units so that the weighted first moments of [list covariates] exactly match those of the treated group.] [PSM: We estimate the propensity score using logistic regression, then match treated to control units within a caliper of [0.2 SD] on the propensity score.] After [matching/reweighting], standardized mean differences for all covariates are below 0.1 (Figure A[X]). We estimate the average treatment effect on the treated (ATT) on the [matched/weighted] sample using OLS. We assess sensitivity to unmeasured confounding using Rosenbaum bounds; results remain significant at Gamma = [X], indicating robustness to a hidden confounder that [doubles] the odds of treatment (Table A[X])."

#### Bias-Corrected Matching in R (Abadie-Imbens)

```r
library(Matching)

# Mahalanobis distance matching with bias correction
m_mah <- Match(Y = df$y, Tr = df$treat,
               X = df[, c("x1","x2","x3")],
               M = 1,               # 1:1 matching
               BiasAdjust = TRUE,   # Abadie-Imbens bias correction
               estimand = "ATT",
               replace = TRUE)      # matching with replacement
summary(m_mah)
```

#### Common Pitfalls
- PSM can worsen balance when propensity model is misspecified; prefer entropy balancing or CEM
- **Common support violation**: always check overlap histogram and trim units outside [min(p_treated), max(p_treated)] — the Dehejia-Wahba (2002) fix for the Lalonde benchmark
- Matching reduces effective N → check power after matching
- Matching on post-treatment variables → post-treatment bias (only match on pre-treatment covariates)
- Approximate matching introduces bias when X_i ≠ X_j(i) — use bias correction (Abadie-Imbens) or prefer exact matching methods (CEM)
- Rosenbaum bounds only assess sensitivity to monotone unmeasured confounders

---

### Strategy 7: Synthetic Control ← NEW

#### Core Logic
When there is a single (or small number of) treated unit(s) and many potential control units with long pre-treatment periods, synthetic control constructs a weighted average of control units that closely tracks the treated unit's pre-treatment trajectory. The post-treatment divergence is the treatment effect.

#### Assumptions
- **Pre-treatment fit**: Synthetic control closely approximates treated unit's pre-treatment outcomes (and predictors)
- **No spillovers**: Control units are unaffected by treatment (SUTVA)
- **Convex hull**: Treated unit's pre-treatment outcome is within the convex hull of control units' outcomes
- **No extrapolation**: Weights are non-negative and sum to 1

#### Standard Workflow
1. Define donor pool (candidate control units); justify exclusions (spillovers, similar policies adopted during study period)
2. Select predictors: pre-treatment averages of Y (lagged outcomes are the most powerful predictors — they implicitly control for unobserved factors that produce the pre-period trajectory) and other covariates
3. **V-matrix selection**: V is a diagonal weight matrix over predictors. Standard practice: choose V to minimize the mean squared prediction error of the synthetic control over the pre-treatment period (data-driven). Avoid hand-picking V to obtain a desired result
4. Find unit weights W* by solving the constrained optimization (non-negative, sum to 1)
5. Check fit quality: plot treated vs. synthetic (trend plot); also produce **gap plot** (Y_treated − Y_synthetic across all periods)
6. **In-space placebo inference**: Apply synthetic control to each donor unit; compute post/pre RMSPE ratio; rank treated unit in distribution; p-value = rank / total units
7. **Filter high-error placebos**: Drop donor units with pre-treatment RMSPE > 2× the treated unit's pre-RMSPE before plotting — they cannot be meaningfully compared and add noise
8. **In-time placebo**: Assign a false treatment date in the pre-period; the synthetic control should show no divergence (validates pre-period model fit and rules out spurious structure)

#### Diagnostics
- Pre-treatment RMSPE (should be small relative to outcome mean; report as % of outcome mean)
- Predictor balance table: treated vs. synthetic vs. simple average of donor pool
- In-space placebo: treated unit's post/pre RMSPE ratio should be an outlier (p < 0.10 with small donor pools)
- In-time placebo: no effect at a false earlier treatment date
- Sensitivity to donor pool composition (add/remove individual donors)
- SynthDiD (Arkhangelsky et al. 2021) as robustness alternative

**Specification search risk (Ferman, Pinto & Possebom 2020)**: If researchers try many covariate/lag specifications and select the one with best pre-period fit, the probability of a false rejection at 5% can reach 14%. **Best practice**: pre-specify covariate selection rule (e.g., "all pre-period lags of Y plus baseline covariates") before examining post-period results. Document all modeling choices transparently.

#### R Code
```r
library(Synth); library(tidysynth); library(augsynth)

# tidysynth (cleaner interface)
synthetic <- df %>%
  synthetic_control(
    outcome = y,
    unit    = state,
    time    = year,
    i_unit  = "treated_state",
    i_time  = 2000,            # treatment year
    generate_placebos = TRUE
  ) %>%
  generate_predictor(
    time_window = 1990:1999,
    avg_y_pre = mean(y)
  ) %>%
  generate_predictor(
    time_window = 1990,
    x1 = first(x1),
    x2 = first(x2)
  ) %>%
  generate_weights(
    optimization_window = 1990:1999,
    margin_ipop = .02, sigf_ipop = 7, bound_ipop = 6
  ) %>%
  generate_control()

plot_trends(synthetic)              # Treated vs. synthetic
plot_differences(synthetic)         # Treatment effect over time
plot_placebos(synthetic)            # Placebo distribution
plot_mspe_ratio(synthetic)          # RMSPE ratio inference

# Augmented synthetic control (Ben-Michael et al. 2021)
asyn <- augsynth(y ~ treat | x1 + x2 + x3,
                 unit = state, time = year,
                 data = df, progfunc = "Ridge",
                 scm = TRUE)
summary(asyn)
plot(asyn)

# Synthetic DiD (Arkhangelsky et al. 2021)
library(synthdid)
setup <- panel.matrices(df, unit = "state", time = "year",
                        outcome = "y", treatment = "treat")
tau_sdid <- synthdid_estimate(setup$Y, setup$N0, setup$T0)
se_sdid  <- sqrt(vcov(tau_sdid, method = "placebo"))
cat("SynthDiD:", tau_sdid, "SE:", se_sdid, "\n")
```

#### Stata Code
```stata
* Synth package
ssc install synth, replace
tsset state year

synth y x1 x2 y(1990) y(1995) y(1999), ///
      trunit(14) trperiod(2000) ///
      mspeperiod(1990(1)1999) ///
      resultsperiod(1990(1)2010) ///
      keep(synth_results) replace

* Placebo permutation inference
forval i = 1/50 {
    synth y x1 x2, trunit(`i') trperiod(2000) ...
}
```

#### Write-up Template
> "Because [state/country/city] is the only unit that [adopted policy X] during our study period, we employ a synthetic control design (Abadie et al. 2010). The synthetic control is constructed as a weighted combination of [N] [states/countries] from the donor pool that most closely tracks [treated unit]'s pre-treatment trajectory of [Y] and predictors [list]. The pre-treatment RMSPE is [X], representing [Y]% of the outcome mean. [Figure X] plots actual versus synthetic [Y]; the two series track closely before [treatment year] and diverge thereafter, suggesting a treatment effect of approximately [X] [units/SD] by [year]. We assess uncertainty through placebo permutation tests, iteratively applying the synthetic control procedure to each donor unit; [treated unit]'s post/pre RMSPE ratio lies in the [Xth] percentile of the placebo distribution (Figure A[X]). [Robustness:] The estimate is robust to the synthetic DiD estimator (Arkhangelsky et al. 2021; τ = [X], SE = [X]; Table A[X])."

#### Common Pitfalls
- Small donor pool → poor pre-treatment fit; cannot construct valid synthetic control
- Poor pre-treatment fit (high RMSPE) → estimates unreliable; report fit clearly
- Including post-treatment periods in predictor matching → invalid weights (weights must be chosen without peeking at post-period outcomes)
- Classic Synth package (Abadie et al.) has limited inference; prefer tidysynth/augsynth for uncertainty
- **Specification searching**: trying many covariate sets and reporting the best-fitting one inflates false discovery rates up to 14% (Ferman et al. 2020); pre-specify the covariate selection rule
- Poor pre-period fit (high RMSPE) means the synthetic control is extrapolating — do not proceed without addressing fit
- Always run in-time placebo (assign false earlier treatment date) to validate model specification

---

### Strategy 8: Causal Mediation Analysis ← NEW

#### Core Logic
Decompose the total effect of X on Y into: (1) the Average Causal Mediation Effect (ACME) — the effect operating through mediator M, and (2) the Average Direct Effect (ADE) — the effect not operating through M. Requires the Imai et al. (2010) framework using the `mediation` R package.

#### Assumptions
- **Ignorability of treatment**: T is ignorable given pre-treatment covariates X (CIA for T → Y)
- **Sequential ignorability**: Mediator M is ignorable given T and pre-treatment covariates X (CIA for M → Y conditional on T, X)
- **No unmeasured mediator-outcome confounders**: Residual confounding of M → Y path (even after conditioning on T and X) biases ACME — this is the key threat
- **No interaction between unmeasured confounders of T→Y and T→M** (cross-world assumption)

#### Standard Workflow
1. Estimate mediator model: M ~ T + X (regression of M on treatment + pre-treatment covariates)
2. Estimate outcome model: Y ~ T + M + X (regression of Y on treatment, mediator, covariates)
3. Use `mediate()` to compute ACME, ADE, proportion mediated via simulation-based inference
4. Sensitivity analysis: test sensitivity to sequential ignorability via rho (correlation between mediator and outcome residuals); find ρ* that nullifies ACME

#### Diagnostics
- Sensitivity parameter ρ* (how large must M–Y residual correlation be to nullify ACME?)
- ρ* > 0.3 is generally considered moderately robust
- Plot of ACME as a function of ρ (sensitivity curve)
- Test for treatment-mediator interaction (product-of-coefficients vs. counterfactual method)

#### R Code
```r
library(mediation)

# Step 1: Mediator model
med_fit <- lm(mediator ~ treat + x1 + x2 + x3, data = df)

# Step 2: Outcome model (must include mediator AND treatment)
out_fit <- lm(outcome ~ treat + mediator + x1 + x2 + x3, data = df)

# Step 3: Causal mediation analysis (simulation-based, 1000 bootstraps)
med_out <- mediate(med_fit, out_fit,
                   treat = "treat",
                   mediator = "mediator",
                   robustSE = TRUE,
                   sims = 1000,
                   boot = TRUE, boot.ci.type = "perc")
summary(med_out)
# Reports: ACME (indirect), ADE (direct), Total Effect, Proportion Mediated

# Step 4: Sensitivity analysis
sens_out <- medsens(med_out, rho.by = 0.1, effect.type = "indirect")
summary(sens_out)
plot(sens_out, sens.par = "rho", main = "Sensitivity to Sequential Ignorability")

# Multiple mediators (parallel mediation)
library(lavaan)
model <- "
  M1 ~ a1*T + x1 + x2
  M2 ~ a2*T + x1 + x2
  Y  ~ b1*M1 + b2*M2 + c*T + x1 + x2
  indirect1 := a1 * b1
  indirect2 := a2 * b2
  total     := c + a1*b1 + a2*b2
"
fit <- sem(model, data = df, se = "bootstrap", bootstrap = 1000)
summary(fit, fit.measures = TRUE)
parameterEstimates(fit, boot.ci.type = "perc", level = 0.95)
```

#### Stata Code
```stata
* causal mediation analysis (paramed or medeff packages)
ssc install medeff, replace

* Simple mediation (Baron & Kenny / Sobel — note: NOT causal; use R for counterfactual)
regress mediator treat x1 x2 x3
regress outcome treat mediator x1 x2 x3
sgmediation outcome, mv(mediator) iv(treat) cv(x1 x2 x3)

* Counterfactual mediation (Imai et al.) via paramed
ssc install paramed
paramed outcome, avar(treat) mvar(mediator) cvars(x1 x2 x3) ///
        a0(0) a1(1) m(mean) fulloutput yreg(linear) mreg(linear)
```

#### Write-up Template
> "We decompose the total effect of [X] on [Y] into the average causal mediation effect (ACME) operating through [M] and the average direct effect (ADE) not operating through [M], following Imai et al. (2010). The mediator model regresses [M] on [X] and pre-treatment covariates [list]. The outcome model regresses [Y] on [X], [M], and the same covariates. We use simulation-based inference with [1,000] bootstrap draws to estimate confidence intervals. The ACME is [estimate] ([95% CI: X, Y]), representing [Z]% of the total effect. The sequential ignorability assumption requires that [M] is ignorably assigned given [X] and pre-treatment covariates. Sensitivity analysis indicates that a residual correlation of ρ > [ρ*] between [M] and [Y] would be required to nullify the ACME (Figure A[X]); we consider this threshold [implausible/uncertain] because [reason]."

#### Common Pitfalls
- Using Baron-Kenny / Sobel test (not causally identified; does not decompose ACME correctly under confounding)
- Unmeasured M–Y confounders are the main threat — always report sensitivity analysis
- Treatment-mediator interaction invalidates simple product-of-coefficients approach; use `mediate()` which handles this
- Proportion mediated is undefined when total effect is near zero

---

### Strategy 9: Staggered Difference-in-Differences

Use when treatment adoption is staggered across units over time (different groups treated at different times). Standard TWFE DiD is biased under treatment effect heterogeneity (Goodman-Bacon 2021).

#### When to use
- Multiple groups adopt treatment at different times
- No never-treated group required (but improves estimation)
- Worried about negative weighting in TWFE

#### Estimators

**Callaway and Sant'Anna (2021) — preferred:**

```r
library(did)
cs_out <- att_gt(
  yname   = "y",
  tname   = "year",
  idname  = "id",
  gname   = "first_treat_year",  # 0 for never-treated
  data    = df,
  control_group = "nevertreated",  # or "notyettreated"
  est_method    = "dr",            # doubly robust (recommended)
  xformla       = ~ x1 + x2       # covariates
)
# Aggregate to event-study
es <- aggte(cs_out, type = "dynamic", min_e = -5, max_e = 5)
ggdid(es) + theme_Publication()

# Aggregate to overall ATT
overall <- aggte(cs_out, type = "simple")
summary(overall)
```

**Sun and Abraham (2021) — interaction-weighted:**

```r
library(fixest)
sa <- feols(y ~ sunab(first_treat_year, year) | id + year,
            data = df, cluster = ~state)
iplot(sa)
```

**Borusyak, Jaravel, and Spiess (2024) — imputation:**

```r
library(didimputation)
did_imp <- did_imputation(
  data = df, yname = "y", gname = "first_treat_year",
  tname = "year", idname = "id",
  first_stage = ~ 0 | id + year
)
```

#### Diagnostics
- Goodman-Bacon decomposition: `library(bacondecomp); bacon(y ~ treat, data = df, id_var = "id", time_var = "year")`
- Pre-trend test: event-study coefficients on pre-treatment periods jointly = 0
- Compare TWFE vs. CS/SA estimates — divergence signals heterogeneity bias

#### Write-up template
> "Because treatment adoption was staggered across [units] from [year1] to [year2], standard TWFE DiD may produce biased estimates under heterogeneous treatment effects (Goodman-Bacon 2021). We employ the Callaway and Sant'Anna (2021) estimator with doubly robust estimation, using [never-treated / not-yet-treated] units as the comparison group. We report group-time ATT estimates aggregated to an event-study specification and an overall ATT."

---

### Strategy 10: Double Machine Learning (DML) and Causal Forests for Heterogeneous Treatment Effects

Use when estimating treatment effects in high-dimensional settings or when interested in treatment effect heterogeneity (CATE).

#### Strategy 10a: Double/Debiased Machine Learning (Chernozhukov et al. 2018)

**When to use:** High-dimensional controls, non-linear confounding, partial linear models.

```r
# R — DoubleML
library(DoubleML)
library(mlr3learners)

# Partially linear model: Y = θ·D + g(X) + ε
dml_data <- DoubleMLData$new(df, y_col = "y", d_cols = "treatment",
                              x_cols = control_vars)
dml_plr <- DoubleMLPLR$new(dml_data,
                            ml_l = lrn("regr.ranger", num.trees = 500),
                            ml_m = lrn("regr.ranger", num.trees = 500),
                            n_folds = 5, n_rep = 10)
dml_plr$fit()
dml_plr$summary()
dml_plr$confint()
```

```python
# Python — econml
from econml.dml import LinearDML, CausalForestDML
from sklearn.ensemble import GradientBoostingRegressor

# Linear DML (ATE)
dml = LinearDML(model_y=GradientBoostingRegressor(),
                model_t=GradientBoostingRegressor(),
                cv=5, random_state=42)
dml.fit(Y=y, T=treatment, X=controls, W=instruments)
print(f"ATE: {dml.ate_inference().summary_frame()}")
```

#### Strategy 10b: Causal Forest for CATE (Athey & Imbens 2019)

**When to use:** Estimating who benefits most from treatment (heterogeneous effects).

```r
library(grf)

# Fit causal forest
cf <- causal_forest(
  X = as.matrix(df[, control_vars]),
  Y = df$y,
  W = df$treatment,
  num.trees    = 4000,
  seed         = 42,
  honesty      = TRUE,
  tune.parameters = "all"
)

# Average treatment effect
average_treatment_effect(cf)

# CATE estimates
cate <- predict(cf, estimate.variance = TRUE)
df$cate_hat <- cate$predictions
df$cate_se  <- sqrt(cate$variance.estimates)

# Best linear projection: which covariates drive heterogeneity?
blp <- best_linear_projection(cf, A = as.matrix(df[, c("age", "income", "education")]))
print(blp)

# Calibration test (check forest is well-calibrated)
test_calibration(cf)

# Rank-weighted ATE (RATE) for policy targeting
rate <- rank_average_treatment_effect(cf, target = "QINI")
plot(rate)
```

**Visualization — CATE by subgroup:**

```r
library(ggplot2)
# CATE distribution
ggplot(df, aes(x = cate_hat)) +
  geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  labs(x = "Estimated CATE", y = "Count",
       title = "Distribution of Heterogeneous Treatment Effects") +
  theme_Publication()

# CATE by key moderator
ggplot(df, aes(x = income, y = cate_hat)) +
  geom_point(alpha = 0.2) +
  geom_smooth(method = "loess") +
  geom_hline(yintercept = 0, linetype = "dashed") +
  theme_Publication()
```

**Policy tree (optimal treatment rules):**

```r
library(policytree)
# Find optimal treatment assignment rule
pt <- policy_tree(as.matrix(df[, c("age", "income")]),
                  cf$predictions, depth = 2)
plot(pt)
```

#### Write-up template (DML)
> "To estimate the ATE of [X] on [Y] while flexibly controlling for [high-dimensional / non-linear] confounders, we use Double/Debiased Machine Learning (Chernozhukov et al. 2018). The partially linear model Y = θD + g(X) + ε is estimated via cross-fitting with [gradient boosting / random forests] for the nuisance functions g(·) and m(·). We report the debiased ATE with standard errors from [N_rep] cross-fitting repetitions."

#### Write-up template (Causal Forest)
> "To examine heterogeneity in treatment effects, we estimate a causal forest (Wager and Athey 2018; Athey et al. 2019) with [N] trees and honest splitting. The best linear projection identifies [variables] as the primary sources of treatment effect heterogeneity. We assess targeting performance using the RATE (rank-weighted average treatment effect) metric."

---

### Strategy 11 — Bunching Estimation

**When to use**: Test whether agents sort around a known threshold (income cutoffs for benefits, tax brackets, regulatory thresholds, age cutoffs for policies).

**Key references**: Kleven & Waseem (2013); Chetty et al. (2011); Kleven (2016) review.

**Workflow**:
1. Define the threshold (kink or notch) and the counterfactual distribution
2. Estimate excess bunching: compare observed density to fitted polynomial density excluding the bunching window
3. Estimate the elasticity from the bunching mass

**R code**:
```r
library(bunching)
# Estimate bunching at threshold
result <- bunching(z_vector = df$income, zstar = 50000,
                   t0 = 0.15, t1 = 0.25,  # tax rates below/above
                   binwidth = 1000, bins_l = 20, bins_r = 20,
                   poly = 7, rn = 0, extra_fe = NULL)
plot(result)
summary(result)  # Reports: excess mass, standard error, elasticity
```

**Diagnostics**:
- Visual inspection: histogram with counterfactual polynomial overlay
- Sensitivity: vary polynomial degree (5–9), bin width, bunching window
- Manipulation test: check if density is smooth away from threshold
- Round-number bunching: distinguish behavioral bunching from reporting bunching

**Write-up template**: "We estimate bunching at the [threshold] using the methodology of Kleven and Waseem (2013). The excess mass at the [kink/notch] is [b = X] (SE = Y), implying an elasticity of [ε = Z]. Results are robust to polynomial degrees [5–9] and window widths of [±W]."

---

### Strategy 12 — Shift-Share (Bartik) Instruments

**When to use**: Exploit variation in local exposure to aggregate shocks (immigrant inflows, trade shocks, technology adoption, industry composition changes).

**Key references**: Bartik (1991); Card (2001); Goldsmith-Pinkham, Sorkin & Swift (2020); Borusyak, Hull & Jaravel (2022).

**Core idea**: Instrument = Σ_k (share_{ik,0} × growth_k), where share_{ik,0} is region i's initial share in industry/origin k, and growth_k is national growth in k.

**R code**:
```r
library(fixest)
library(bartinger)  # or construct manually

# Manual construction
df$bartik_iv <- rowSums(shares_matrix * national_growth_vector)

# IV regression
iv_mod <- feols(y ~ controls | region_fe + year_fe | x ~ bartik_iv,
                data = df, cluster = ~region)
summary(iv_mod)
fitstat(iv_mod, "ivf")  # First-stage F
```

**Modern validity checks (Goldsmith-Pinkham et al. 2020)**:
1. **Rotemberg weights**: Identify which industries drive the instrument
   - Top 5 industries by Rotemberg weight
   - Check if those industries have plausible exclusion restriction
2. **Pre-trend balance**: Initial shares should not predict pre-period outcome trends
3. **Leave-one-out**: Drop each top-weight industry and re-estimate
4. **Borusyak et al. (2022)**: Recentered instrument — shocks as exogenous, shares as exposure weights

**Stata**:
```stata
* Manual Bartik
gen bartik_iv = 0
forvalues k = 1/K {
    replace bartik_iv = bartik_iv + share_`k' * national_growth_`k'
}
ivregress 2sls y controls (x = bartik_iv), cluster(region) first
```

**Write-up template**: "We construct a Bartik instrument using initial [industry/origin-country] shares interacted with national [growth/inflow] rates. Following Goldsmith-Pinkham et al. (2020), we report Rotemberg weights identifying the top [N] industries driving variation. Pre-period balance tests confirm that initial shares do not predict [outcome] trends (Table X). The first-stage F-statistic is [F], and the 2SLS estimate is [β = X] (SE = Y)."

---

### Strategy 13 — Distributional and Quantile Methods

**When to use**: When you care about effects across the outcome distribution (inequality, heterogeneity beyond mean effects).

#### 13a. Quantile Regression
```r
library(quantreg)
# Estimate at τ = 0.10, 0.25, 0.50, 0.75, 0.90
qr_mod <- rq(y ~ x1 + x2, data = df, tau = c(0.10, 0.25, 0.50, 0.75, 0.90))
summary(qr_mod, se = "boot", R = 1000)
plot(summary(qr_mod))  # Coefficient plot across quantiles
```

#### 13b. Unconditional Quantile Regression (RIF-OLS)
```r
library(rifreg)
# Recentered Influence Function regression (Firpo, Fortin & Lemieux 2009)
rif_mod <- rifreg(y ~ x1 + x2, data = df, statistic = "quantiles",
                  probs = c(0.10, 0.25, 0.50, 0.75, 0.90))
summary(rif_mod)
# Interpretation: effect of X on the UNCONDITIONAL quantile of Y
```

#### 13c. Quantile DiD (Changes-in-Changes)
```r
# Athey & Imbens (2006) Changes-in-Changes estimator
library(qte)
cic_mod <- CiC(y ~ treated, data = df, t = 1, tmin1 = 0,
               tname = "period", idname = "id")
summary(cic_mod)
# Reports QTE at each quantile
```

#### 13d. DiNardo-Fortin-Lemieux (DFL) Decomposition
```r
library(oaxaca)
# Decompose distributional differences between groups
# Counterfactual: what would Group B's distribution look like with Group A's characteristics?
dfl <- oaxaca(y ~ x1 + x2 + x3 | group, data = df, type = "twofold")
plot(dfl)
```

**Write-up template**: "To examine heterogeneous effects across the [outcome] distribution, we estimate unconditional quantile regressions (Firpo, Fortin & Lemieux 2009). The effect of [X] on [Y] is [larger/smaller] at the [10th/90th] percentile ([β = X]) compared to the median ([β = Y]), suggesting [interpretation about inequality/heterogeneity]."

---

## PART 4: SENSITIVITY ANALYSIS SUITE

### Oster (2019) Delta (for OLS)

**What it measures**: How many times more strongly unobservables would need to be correlated with Y (relative to observed controls) to fully explain the coefficient.

- δ > 1: Unobservables must be stronger than all observables combined — usually implausible
- δ > 2: Strong robustness claim

```r
library(sensemakr)
sens <- sensemakr(lm(y ~ x + controls, data = df),
                  treatment = "x", benchmark_covariates = "key_control",
                  kd = 1:3)
summary(sens); plot(sens)
```

---

### E-Values (VanderWeele & Ding 2017)

**What it measures**: The minimum strength of association (on the risk ratio scale) that an unmeasured confounder would need to have with both treatment and outcome (jointly) to fully explain away the observed effect.

- E-value = RR + sqrt(RR × (RR - 1)) where RR is the observed relative risk
- Higher E-value = more robust result
- "The observed association could be explained away by an unmeasured confounder with E-value of [X]; to reduce the CI lower bound to null requires a confounder with E-value of [Y]"

```r
library(EValue)
# For risk ratio (binary outcome, binary exposure)
evalues.RR(est = 2.5, lo = 1.8, hi = 3.5)

# For odds ratio (logistic regression)
evalues.OR(est = 1.8, lo = 1.2, hi = 2.6, rare = TRUE)

# For mean difference (linear regression)
evalues.MD(est = 0.3, se = 0.1, sd = 1.2)
```

---

### Rosenbaum Bounds (for Matching)

**What it measures**: The odds ratio of hidden bias (Γ) that would be required to explain away the result when using matching estimators.

- Γ = 1: No unmeasured confounding
- Γ = 2: A hidden confounder that doubles the odds of treatment (after matching) could explain away the result
- If Γ* > 2 before p > 0.05: moderately robust

```r
library(rbounds)
psens(y_treated, y_control, Gamma = 3, GammaInc = 0.25)
# Find Gamma* at which p-value exceeds 0.05
```

---

### Placebo / Falsification Tests

1. **Pre-trend placebo (DiD)**: Run event study and check coefficients on pre-treatment periods are jointly zero (F-test)
2. **Placebo outcome**: Test X on outcome that cannot be caused by X (e.g., past outcomes, unrelated outcomes)
3. **Placebo treatment**: Randomize treatment assignment; check no effect
4. **Geographic/temporal placebo (RD)**: Run RD at placebo cutoffs; check null results
5. **Donut-hole (RD)**: Exclude observations very close to cutoff; check robustness

---

### HonestDiD (Rambachan & Roth 2023) — Sensitivity to Parallel Trends Violations

**What it measures**: How robust is the DiD estimate to deviations from parallel trends? Constructs honest confidence intervals that remain valid even if pre-trends deviate from zero by up to magnitude M.

**When to use**: Any DiD paper. Reviewers at ASR, AJS, Demography, and economics journals now routinely request this.

```r
library(HonestDiD)

# After running event study via fixest:
es_fit <- feols(y ~ i(time_to_treat, ref = -1) | id + year, data = df, cluster = ~state)

# Extract coefficients and variance-covariance matrix for pre/post periods
betahat <- coef(es_fit)[grep("time_to_treat", names(coef(es_fit)))]
sigma   <- vcov(es_fit)[grep("time_to_treat", rownames(vcov(es_fit))),
                         grep("time_to_treat", colnames(vcov(es_fit)))]

# Relative magnitudes approach (recommended)
delta_rm <- createSensitivityResults_relativeMagnitudes(
  betahat       = betahat,
  sigma         = sigma,
  numPrePeriods = 4,    # number of pre-treatment periods
  numPostPeriods = 3,   # number of post-treatment periods
  Mbarvec       = seq(0.5, 2, by = 0.5)  # M values to test
)

# Smoothness-based approach
delta_sd <- createSensitivityResults(
  betahat       = betahat,
  sigma         = sigma,
  numPrePeriods = 4,
  numPostPeriods = 3,
  Mvec          = seq(0, 0.05, by = 0.01)
)

# Plot sensitivity
createSensitivityPlot_relativeMagnitudes(delta_rm, rescaleFactor = 1)
```

**Reporting**: "We assess robustness to violations of parallel trends using the Rambachan and Roth (2023) procedure. The estimated treatment effect remains statistically significant for deviations from parallel trends up to [M] times the magnitude of the largest pre-trend, providing evidence that our results are not driven by differential pre-existing trends."

---

### Manski Bounds / Partial Identification

**What it measures**: When point identification fails (e.g., due to sample selection, missing outcomes, or violations of exclusion restriction), Manski bounds provide the range of treatment effects consistent with the data under minimal assumptions.

```r
# Lee (2009) bounds for sample selection in RCTs
library(sampleSelection)
# When attrition/selection differs by treatment status:
# Lower bound: trim top of treated distribution
# Upper bound: trim bottom of treated distribution

# Manual Lee bounds implementation:
lee_bounds <- function(y_treat, y_control, p_treat, p_control) {
  # Proportion always-observed
  s <- min(p_treat, p_control) / max(p_treat, p_control)
  if (p_treat > p_control) {
    # Trim treated distribution
    lower <- quantile(y_treat, 1 - s) - mean(y_control)
    upper <- quantile(y_treat, s) - mean(y_control)
  } else {
    lower <- mean(y_treat) - quantile(y_control, s)
    upper <- mean(y_treat) - quantile(y_control, 1 - s)
  }
  return(c(lower = lower, upper = upper))
}
```

---

### Spillover Sensitivity

**What it measures**: Sensitivity of treatment effect estimates to violations of SUTVA (no interference between units).

```r
# Spatial spillover test: include neighbor treatment as covariate
library(spdep)
nb <- poly2nb(shapes)
df$neighbor_treated <- lag.listw(nb2listw(nb), df$treatment)
m_spill <- feols(y ~ treatment + neighbor_treated + controls | id + year,
                 data = df, cluster = ~state)
# If neighbor_treated is significant, SUTVA may be violated
```

---

### Preregistered Sensitivity Checks (Recommended Suite)

| Check | Addresses | Code |
|-------|-----------|------|
| Oster delta or E-value | OLS confounding | `sensemakr`, `EValue` |
| Event study pre-trend F-test | DiD parallel trends | `fixest::iplot` |
| **HonestDiD** | **DiD — robust to PT violations** | **`HonestDiD`** |
| McCrary density test | RD manipulation | `rddensity` |
| Bandwidth sensitivity | RD robustness | `rdrobust` loop |
| First-stage F | IV weak instruments | `AER`, `fixest::fitstat` |
| Rosenbaum Γ | Matching hidden bias | `rbounds::psens` |
| ρ* sensitivity | Mediation sequential ignorability | `mediation::medsens` |
| **Manski / Lee bounds** | **Sample selection / attrition** | **Manual / `sampleSelection`** |
| **Spillover test** | **SUTVA violations** | **`spdep` neighbor lag** |
| **Causal forest calibration** | **HTE model validity** | **`grf::test_calibration`** |

---

## PART 5: WRITING THE IDENTIFICATION ARGUMENT

### Canonical Identification Section Structure

```
1. CAUSAL CLAIM: State what causal effect you are trying to identify
2. THREATS: Name the main identification threats (confounders, reverse causality, selection)
3. STRATEGY: Name the identification strategy and why it is appropriate here
4. ASSUMPTIONS: State the core assumptions required (and that they are plausible)
5. EVIDENCE: Present evidence that assumptions hold (tests, falsification, sensitivity)
6. LIMITATIONS: Acknowledge what the strategy cannot address (and note it as a boundary)
```

### Templates by Strategy

**OLS template**: See Strategy 1 write-up template above.

**DiD template**: See Strategy 2 write-up template above.

**RD template**: See Strategy 3 write-up template above.

**IV template**: See Strategy 4 write-up template above.

**Panel FE template**: See Strategy 5 write-up template above.

**Matching template**: See Strategy 6 write-up template above.

**Synthetic control template**: See Strategy 7 write-up template above.

**Causal mediation template**: See Strategy 8 write-up template above.

**Staggered DiD template**: See Strategy 9 write-up template above.

**DML template**: See Strategy 10 write-up template (DML) above.

**Causal forest template**: See Strategy 10 write-up template (Causal Forest) above.

**Bunching template**: See Strategy 11 write-up template above.

**Shift-share / Bartik template**: See Strategy 12 write-up template above.

**Distributional / quantile template**: See Strategy 13 write-up template above.

---

### Consolidating Multiple Strategies

When using complementary strategies (e.g., PSM + OLS, FE + DiD, IV + OLS comparison):

> "Our primary specification employs [Strategy A], which addresses [Threat 1]. As a robustness check, we replicate the analysis using [Strategy B], which addresses [Threat 2] under different assumptions. The consistency of estimates across strategies strengthens confidence that [finding] is not an artifact of any single identification assumption (Table A[X])."

---

## Quality Checklist

- [ ] Causal question stated precisely (X → Y for population P, identification context)
- [ ] DAG drawn; backdoor paths listed; minimal adjustment set identified
- [ ] No mediators, colliders, or post-treatment variables in control set
- [ ] Identification strategy selected and justified against alternatives
- [ ] Core assumptions stated and evidence provided for each
- [ ] Diagnostics run and reported (pre-trend test / McCrary / first-stage F / balance / etc.)
- [ ] Sensitivity analysis performed (Oster delta / E-value / Rosenbaum Γ / ρ* / placebos)
- [ ] Identification argument paragraph written and placed in Methods section
- [ ] Limitations acknowledged

See [references/dag-patterns.md](references/dag-patterns.md) for 18 DAG patterns.
See [references/identification-toolkit.md](references/identification-toolkit.md) for full strategy code.
See [references/matching-weighting.md](references/matching-weighting.md) for matching/reweighting details.

---

## Save Output

After displaying the full output to the user, save the complete output to a Markdown file using the Write tool.

**Filename format**: `scholar-causal-[topic-slug]-[YYYY-MM-DD].md`
- `topic-slug`: lowercase, hyphen-separated key words from the research question (e.g., `redlining-activity-space-segregation`, `education-earnings-iv`, `neighborhood-health-did`)
- `YYYY-MM-DD`: today's date

**What to save** — include all sections that were generated:
1. Causal question (precise statement of X → Y, population, context)
2. Variable inventory (treatment, outcome, mediators, confounders, instruments)
3. DAG notation and backdoor/frontdoor paths
4. Method selection table and justification
5. Selected strategy deep-dive: assumptions, workflow, diagnostics
6. All R and Stata code blocks produced
7. Sensitivity analysis plan (Oster delta / E-value / Rosenbaum Γ / ρ* / placebos)
8. Identification argument paragraphs (Methods section ready text)
9. Limitations and scope conditions

**Example Write call**:
```
Write tool → file_path: "scholar-causal-[topic-slug]-[YYYY-MM-DD].md"
             content: [full markdown output from this session]
```

After saving, confirm the file path to the user so they can locate the saved analysis.

**Close Process Log:**

Run the following to finalize the process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="scholar-causal"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}.md"
if [ ! -f "$LOG_FILE" ]; then
  LOG_FILE=$(ls -t "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}"*.md 2>/dev/null | head -1)
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
