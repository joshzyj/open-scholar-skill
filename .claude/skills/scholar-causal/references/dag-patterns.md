# Common DAG Patterns in Social Science Research

## Quick Reference Checklists

### Before running any regression, check:
1. Is each control variable a pre-treatment confounder (C → X AND C → Y)?
2. Could any control be on the causal path (X → M → Y)? If so, **do not include it** for total effect.
3. Could any control be a collider (X → C ← Y)? If so, **do not include it**.
4. Is there an unobserved confounder? If so, what identification strategy addresses it?

---

## Pattern Library

### Pattern 1: Simple Confounder
**Structure**: X ← C → Y; X → Y
**Control for**: C
**Example**: SES confounds education (X) → health (Y); SES → both education and health
**Do not control for**: mediators between X and Y

---

### Pattern 2: Chain of Confounders (Confounder of Confounder)
**Structure**: A → C → X → Y; A → Y
**Control for**: A (or C, or both — either blocks the backdoor path)
**Sociological example**: Parental education (A) → SES (C) → own education (X) → earnings (Y); parental education also directly → earnings

---

### Pattern 3: Mediation with Confounder
**Structure**: X → M → Y; X → Y (direct); C → M; C → Y (M-Y confounder)
**Warning**: If C is unobserved, even with an RCT on X, mediation analysis is biased
**Solution**: Must control for C to get unbiased mediation; if C is unobserved, sensitivity analysis for mediator-outcome confounding (Imai et al. 2010)
**Example**: Education (X) → occupation (M) → earnings (Y); but unobserved ability (C) → occupation AND earnings

---

### Pattern 4: Collider (Selection Bias)
**Structure**: X → C ← Y; X → Y
**Never control for C**: conditioning on collider C opens spurious path between X and Y
**Example**: Studying the X–Y relationship *only among employed people* (C = employed) when both X (employer's perception of ability) and Y (job quality) affect employment
**Example 2**: "Survivorship bias" — studying only successful firms; success is a collider of quality and luck

---

### Pattern 5: M-Bias (Butterfly Bias)
**Structure**: A → C ← B; A → X; B → Y; X → Y
**Do NOT control for C**: C is a collider on the path A → C ← B, and controlling for it opens the path X ← A → C ← B → Y (spurious)
**Practical implication**: Variables that precede X in time can still be colliders; check the causal structure, not just the time order

---

### Pattern 6: Instrumental Variable
**Structure**: Z → X → Y; U → X; U → Y; Z ⊥ U
**Valid instrument requires**: (1) Z → X (strong), (2) Z ↛ Y directly (exclusion), (3) Z ⊥ U (independence)
**Classic examples**:
- Compulsory schooling laws (Z) → years of education (X) → earnings (Y) — Acemoglu & Angrist
- Distance to nearest college (Z) → college attendance (X) → wages (Y) — Card 1995
- Vietnam draft lottery (Z) → military service (X) → earnings (Y) — Angrist 1990
**Test**: First-stage F > 10; reduced form should show intent-to-treat effect

---

### Pattern 7: Regression Discontinuity
**Structure**: Running variable (R) → Cutoff (C) → Treatment (T) → Outcome (Y)
**Identifying assumption**: All other determinants of Y are continuous at the cutoff
**Valid when**: Assignment is truly based on the cutoff value; no manipulation
**Example**: GPA cutoff → scholarship (T) → graduation (Y); poverty score cutoff → program eligibility → health
**Threats**: Bunching/sorting at cutoff; other policy changes at same cutoff; spillovers

---

### Pattern 8: Difference-in-Differences
**Structure**: Unit FE + Time FE + Treatment × Post → Outcome
**DAG**: Treat (binary) → Y; Time → Y; Treat × Time → Y (the DiD coefficient); U_unit → Treat + Y (absorbed by unit FE); U_time → Y (absorbed by time FE)
**Identifying assumption**: Parallel trends (no arrow from Treat × U_time to Y)
**Example**: Policy change in some states (Treat) → wages (Y); compare treated states to untreated states before/after

---

### Pattern 9: Fixed Effects (Within)
**Structure**: X_it → Y_it; alpha_i → X_it + Y_it; epsilon_it → Y_it
**FE removes**: All time-invariant individual-level confounders (alpha_i = everything stable about person i)
**Cannot estimate**: Effect of time-invariant X (race, sex) — absorbed into FE
**Example**: Changing education over time → changing earnings; within-person variation identifies effect; removes unobserved stable traits (personality, genetics)

---

### Pattern 10: Bad Control (Post-Treatment Bias)
**Structure**: X → M → Y; researcher adds M as control; M has backdoor path M ← U → Y
**Result**: Controlling for M opens the backdoor path through U; biases estimate of X → Y
**Example**:
- Estimating effect of gender on wages; control for occupation — but occupation is a mediator of gender → wages; AND there are unobserved confounders of occupation → wages → bias!
- Estimating effect of incarceration on reemployment; control for criminal record post-release — but criminal record is a consequence of incarceration

---

### Pattern 11: Negative Control (Falsification)
**Design**: Test a "placebo" where the treatment cannot have an effect
- If coefficient ≠ 0 for the placebo outcome → suggests confounding is present
- If coefficient = 0 → increases confidence in identification

**Example**:
- DiD test: check if treatment predicts outcome in pre-treatment period (should be null)
- If education → earnings, test whether education in 2020 predicts earnings in 2000 (impossible)
- If income → health, test income → car accidents involving other people (income shouldn't affect this)

---

### Pattern 12: Proxy Control
**Structure**: U → X (confounder); W → U (proxy for U); include W in regression
**Use when**: U is unobserved but W is a measured proxy correlated with U
**Condition for validity**: W satisfies the "proxy condition" (W ⊥ X | U) — W affects X only through U
**Example**: IQ test as proxy for unobserved ability; proxying family SES with parental occupation when income is missing
**Limitation**: Attenuation bias if proxy is imperfect; use with sensitivity analysis

---

### Pattern 13: Heterogeneous Treatment Effects / Effect Modification
**Structure**: X → Y; Z moderates X → Y (the Z × X interaction)
**DAG representation**: Add Z → Y and X × Z → Y (interaction node)
**Example**: Effect of education on earnings differs by race (Z = race); test X × Z interaction
**Identification**: Z must not be a post-treatment variable; must be exogenous to X

---

### Pattern 14: Spillover / SUTVA Violation
**Structure**: Treatment of unit i affects outcome of unit j (stable unit treatment value assumption violated)
**Example**: Studying effect of job training on employment when trained workers displace untrained workers (negative spillover)
**Solutions**: Use design that minimizes spillovers; estimate direct + spillover effects with two-level DiD; test for spillovers explicitly

---

### Pattern 15: Measurement Error in X (Attenuation Bias)
**Structure**: X* (true, unobserved) → Y; X (observed, measured with error) = X* + ε_m; ε_m ⊥ Y
**Effect**: Classical measurement error in X biases coefficient toward zero (attenuation bias) and reduces precision
**Correction approaches**:
- IV where the instrument is a second measurement of X* (TSLS)
- SIMEX (simulation-extrapolation) method
- Bayesian measurement error models
**For categorical X**: Misclassification leads to complex bias; direction depends on structure

---

### Pattern 16: Causal Mediation (ACME Notation) ← NEW
**Structure**:
```
X → M → Y     (indirect path through mediator)
X → Y          (direct path)
U_MX → M      (unmeasured mediator-outcome confounder)
U_MX → Y
```
**Key notation (Imai et al. 2010)**:
- ACME (Average Causal Mediation Effect) = E[Y(t, M(1)) − Y(t, M(0))] — the effect operating through M
- ADE (Average Direct Effect) = E[Y(1, m) − Y(0, m)] — the effect not operating through M
- Total effect = ACME + ADE

**Critical assumption**: Sequential ignorability — M is ignorably assigned conditional on T and pre-treatment X. Violated if U_MX is unmeasured.

**Why this pattern matters**: Even in an RCT for X, unobserved confounders of M → Y (U_MX) bias mediation estimates. The DAG makes this threat explicit and motivates sensitivity analysis (ρ*).

**Example**: Residential segregation (X) → neighborhood social disorder (M) → health (Y); but unobserved poverty concentration (U_MX) → both social disorder and health. Controlling for M opens the U_MX path.

**Solution**: Use `mediation` package with sensitivity analysis; report ρ* (correlation threshold). Alternatively, use an IV for M (instrumental variable mediation).

---

### Pattern 17: Staggered Adoption DiD ← NEW
**Structure**:
```
Unit i receives treatment at time g_i (first treatment cohort)
Some units never treated: g_i = ∞
Standard TWFE regression: Y_it = β(Treated × Post) + α_i + γ_t + ε_it
```
**The problem — forbidden comparisons (Callaway & Sant'Anna 2021)**:
In staggered adoption, TWFE uses already-treated units as controls for later-treated units. When treatment effects are heterogeneous (dynamic or unit-varying), this creates "forbidden comparisons" that bias TWFE estimates — sometimes reversing the sign.

**Decomposition (Goodman-Bacon 2021)**: β_TWFE = weighted average of all 2×2 DiD comparisons, where the weights depend on group sizes and treatment timing. Some comparisons are valid (never-treated or not-yet-treated as control); others are forbidden (earlier-treated as control for later-treated).

**DAG representation for staggered adoption**:
```
G_i (cohort) → Post_it (post-treatment indicator) → Y_it
G_i → Y_it (direct: cohort-level heterogeneity)
Time_t → Y_it (common time trend)
U_i → G_i, U_i → Y_it  (unit-level unobservable, absorbed by unit FE)
```

**Solutions**:
- **Callaway & Sant'Anna (2021)**: Estimate group-time ATTs (ATT(g,t)) using only never-treated or not-yet-treated controls; aggregate cleanly
- **Sun & Abraham (2021)**: Interaction-weighted estimator; estimate within-cohort ATTs and aggregate
- **Roth et al. (2023)**: Review and practical guidance; use `staggered` R package or `did` package

**Key diagnostics**:
- Bacon decomposition: identify weights on each 2×2 pair; flag negative weights
- Event study from CS-2021 / SA-2021: confirm pre-trends are flat
- Compare TWFE estimate to CS-2021 estimate; large divergence signals heterogeneity

**R Code**:
```r
library(did); library(fixest); library(bacondecomp)
# Bacon decomposition
bd <- bacon(y ~ treat_post, data = df, id_var = "unit", time_var = "year")
# CS-2021
cs <- att_gt(yname="y", tname="year", idname="id", gname="first_treat",
             data=df, control_group="nevertreated", est_method="reg")
aggte(cs, type="dynamic"); aggte(cs, type="simple")
# SA-2021 via fixest
feols(y ~ sunab(cohort, year) | unit + year, data=df, cluster=~unit)
```

**Example**: State-level minimum wage increases adopted at different times across states → worker earnings. TWFE will be biased if early-adopting states (which benefited more) serve as controls for late-adopting states.

---

### Pattern 18: Synthetic Control ← NEW
**Structure**:
```
Donor pool: J control units (states/countries/cities), never treated
Treated unit: single unit (or few units) that adopted treatment
Synthetic control: weighted combination w*_j of donor units
Pre-period: T₀ periods before treatment; post-period: T₁ periods after
```
**Key elements**:
- **Weights w***: Non-negative, sum to 1; found by minimizing pre-treatment RMSPE between treated unit and synthetic control
- **Predictor matrix**: Pre-treatment averages of Y and other predictors used to construct weights
- **Convex hull requirement**: Treated unit's pre-treatment outcomes must lie within convex hull of donors; otherwise synthetic control extrapolates

**DAG representation**:
```
Donor_pool (convex combination) → Synthetic_Y_pretreated
Treated_Y_pretreated vs. Synthetic_Y_pretreated → Fit quality (RMSPE)
Treatment → Post_treated_Y − Post_synthetic_Y = Treatment effect
U_treated → Y_treated  (unobservables absorbed by pre-period matching)
```

**Why this works**: If the synthetic control closely tracks the treated unit in the pre-period — including through common unobservable factors captured by the donor pool — then any post-treatment divergence can be attributed to treatment.

**Key inference**: No standard SE formula. Use **placebo permutation tests**: apply synthetic control to each donor unit; compare treated unit's post/pre RMSPE ratio to the permutation distribution.

**Extensions**:
- **Augmented SC (Ben-Michael et al. 2021)**: Adds a bias correction term via regularized regression; performs better when pre-period fit is imperfect
- **Synthetic DiD (Arkhangelsky et al. 2021)**: Combines DiD (time weights) with synthetic control (unit weights); valid even with many treated units; has valid SE formula via placebo

**Example**: California Proposition 99 (tobacco tax) → cigarette sales. California is the treated unit; other states form the donor pool. Abadie, Diamond, and Hainmueller (2010) classic application.

---

### Pattern 19: Frontdoor Criterion ← NEW
**Structure**:
```
X → M → Y     (treatment causes mediator causes outcome)
U → X          (unobserved confounder causes treatment)
U → Y          (unobserved confounder causes outcome)
No direct X → Y path (treatment affects outcome only through M)
No backdoor paths from M to Y
```
**Key insight**: When ALL backdoor paths from X to Y are unblockable (because U is unobserved), but there exists a mediator M such that:
1. X blocks all paths from X to M (i.e., the only path X → M is direct)
2. There are no unblocked back-door paths from M to Y
3. All paths from X to Y go through M

then the total effect P(Y | do(X)) can still be identified via the **frontdoor formula**:

```
P(Y | do(X)) = Σ_m P(M=m | X) × Σ_x P(Y | x, M=m) P(X=x)
```

**Classic example**: Smoking (X) → tar deposits in lungs (M) → lung cancer (Y). Unobserved genetics U → smoking and cancer, so the backdoor path X ← U → Y cannot be blocked. But:
1. Only smoking causes tar deposits (M); U does not independently affect M
2. No unblocked backdoor paths from M (tar) to Y (cancer) except through X
3. The entire effect of smoking on cancer runs through tar

**Social science examples**:
- X = neighborhood poverty → M = local crime rates → Y = individual health; if poverty-health unobservable exists but crime is the only channel
- X = network centrality → M = information access → Y = wages; if ability is an unobserved confounder of centrality and wages
- X = racial discrimination → M = occupational attainment → Y = wealth; if unobserved factors (genetics, family) affect both race (proxy) and wealth but not occupation independently

**Rarity in practice**: Frontdoor identification requires strong structural assumptions about M — specifically that no unobserved variable affects both M and Y independently of X. This is rarely satisfied in social science observational data. When available (e.g., molecular mediators in biology, specific institutional channels), it is a powerful identification strategy that does not require an instrument.

**Contrast with backdoor and IV**:
| Strategy | Unobserved U → X, U → Y? | Mediator required? | Instrument required? |
|----------|--------------------------|-------------------|---------------------|
| Backdoor | Must block via observables | No | No |
| IV | Yes — instrument bypasses U | No | Yes |
| Frontdoor | Yes — identified through M | Yes (strict conditions) | No |

---

## dagitty R Code Library

```r
library(dagitty)
library(ggdag)

# Build and analyze any DAG
g <- dagitty('dag {
  SES -> Education
  SES -> Earnings
  Ability [unobserved]
  Ability -> Education
  Ability -> Earnings
  Education -> Occupation -> Earnings
  Education -> Earnings
}')

# What to control for?
adjustmentSets(g, exposure = "Education", outcome = "Earnings",
               type = "minimal")
# Returns: {SES} — controlling for SES blocks all backdoor paths
# Note: Ability cannot be controlled (unobserved) — flag for sensitivity analysis

# Is X d-separated from Y given Z?
dseparated(g, "Education", "Earnings", c("SES"))

# Find instruments for Education
instrumentalVariables(g, exposure = "Education", outcome = "Earnings")

# Plot
ggdag(tidy_dagitty(g), layout = "nicely") +
  theme_dag()

# Visualize adjustment sets
ggdag_adjustment_set(tidy_dagitty(g),
                     exposure = "Education", outcome = "Earnings") +
  theme_dag()
```
