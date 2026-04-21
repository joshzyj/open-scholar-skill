# Methods-Section Prose Examples — Before (AI tell) / After (human)

This file is loaded by scholar-write whenever §4 Analytic Strategy, §5 Results robustness paragraphs, or any methods-like section is being drafted. It shows the target prose style concretely.

**Operating principle**: A specification registry or a design pre-mortem table lists models and robustness checks as flat enumerations because machine-readable enumeration is those artifacts' job. The **manuscript** translates those registries into flowing prose. Never mirror the registry structure into the manuscript.

---

## Example 1 — Model ladder

### BAD (enumerated — do not emit)

```
We estimate a ladder of six models (Table 2):

• M1 (unconditional trend): CHLDIDEL = α + β·year_c.
• M2 (baseline with controls and period linear): adds all controls and log(REALINC) but no SES × year interaction.
• M3 (focal H1 test): adds education × year_c interaction.
• M4 (H2a test): adds log(REALINC) × year_c interaction.
• M5 (H2b test): adds a top-income-quintile × post-2008 interaction, with year-block fixed effects.
• M6 (H3 test): education × 5-year cohort interactions with period fixed effects.

All models use WTSSALL as the weight.
```

Why it reads as AI-generated: bulleted `Mn (label): formula` structure, inline equations in bullets, "ladder" in a subsection header, mechanical reproduction of the spec-registry. No JMF/ASR/Demography author writes this way.

### GOOD (narrative — emit this)

Our baseline regresses CHLDIDEL on completed schooling, a centered linear year trend, and their interaction, with controls for age, age-squared, sex, race, region, marital status, and log real family income (Table 2, M3). All specifications use the WTSSALL cumulative weight. To distinguish a general-SES story from an education-specific one, we add log real income × year (M4). M5 adds a post-2008 × top-quintile term with year-block fixed effects, testing the asymmetric-constraint prediction. M6 replaces the period linear with five-year-cohort × education interactions and period fixed effects to probe the cohort-replacement channel. An unconditional-trend specification (M1) and a controls-only baseline (M2) appear in Table 2 for readers who want to see the raw trend and the pre-interaction fit.

Why this works: each model ID appears inline as a parenthetical; Stage 2 verifier still grep-matches `(M3)`, `(M4)`, etc.; equations go in the replication scripts, not the prose; the paragraph reads as a paper, not a lecture note.

---

## Example 2 — Robustness battery

### BAD (enumerated — do not emit)

```
We re-estimate M3 under eight specification variations (Table 3):

• R1: outcome is chldidel_drop (non-numeric "as many" responses dropped).
• R2: outcome is chldidel_cap4 (upper-tail recoded to 4).
• R3a: unweighted estimation.
• R3b: WTSSNR weights, restricted to 2004+ waves where this weight is defined.
• R4a / R4b: sex-stratified estimation.
• R5: reproductive-age-restricted subsample (ages 18–44).
• R6: DEGREE × year interaction replacing the linear EDUC × year interaction.
• R7: pre-2018 subsample (formally identical to the analytic file, since CHLDIDEL was not asked after 2018; retained as a pre-registered placeholder).
```

### GOOD (narrative — emit this)

We probe the main result's sensitivity on four fronts (Table 3). On measurement, we drop the 6–8% of respondents who report "as many as they want" rather than a numeric value (R1) and top-code the outcome at four children (R2). On weighting, we re-estimate unweighted (R3a) and under the post-2004 non-response-adjusted weight (R3b). On population coverage, we estimate separately for men and women (R4a, R4b) and restrict to respondents of reproductive age, 18–44 (R5). On functional form, we replace the continuous EDUC × year interaction with a categorical DEGREE × year (R6). The attenuation to near-zero under R5 is substantive — the flattening is concentrated among respondents past reproductive age — and we return to it in §6.2.

Why this works: robustness checks are organized by *theme* (measurement / weighting / population / functional form), not by registry index; R5's substantive import is flagged inline; all seven registry IDs survive as parenthetical tags for Stage 2 verification.

---

## Example 3 — Language-discipline signaling

### BAD (named subsection — do not emit)

```
### 4.3 Language discipline

Throughout the paper we use associational rather than causal language
("education is associated with," "the gradient has flattened," "cohorts
differ in"). We avoid formulations that imply direct intervention or
counterfactual ("education lowers," "rising education causes"). This
restraint reflects the research design: the GSS is observational,
cross-sectional, and without exogenous variation in SES; the paper's
contribution is descriptive benchmarking of a long-run association.
```

Why it reads as AI-generated: naming a subsection "Language Discipline" is compliance-signaling as paper structure. Humans don't label their word choices with headers. The existence of a subsection that promises not to use causal language is itself a tell.

### GOOD (folded into prose — emit one of these)

**Option A — closing sentence of §4**:

Because the GSS is observational and offers no exogenous variation in schooling, we use associational language throughout; the paper's contribution is descriptive benchmarking of a long-run gradient, not a causal effect estimate.

**Option B — opening sentence of §4**:

We describe long-run variation in the educational gradient of fertility ideals, using associational language throughout given the observational design.

Both are one or two sentences, never a subsection.

---

## Example 4 — Standard-error / inference discussion

### BAD (enumerated — do not emit)

```
We report three SE frameworks:

• HC1: heteroskedasticity-consistent (benchmark).
• Cluster-year: BDM (2004) with G=27.
• Cluster-VPSU: GSS design-appropriate.
```

### GOOD (narrative — emit this)

Our primary standard errors cluster by survey year (G = 27), following Bertrand, Duflo, and Mullainathan (2004), on the reasoning that within-wave respondents share exposure to common aggregate shocks. Because 27 clusters is modest, we report heteroskedasticity-robust (HC1) and design-based cluster-VPSU alternatives alongside the primary (Table 2, Panel B); the sign of the focal coefficient is invariant across frameworks, though p-values shift.

---

## Quick checklist before emitting §4

Run through this mentally before the Methods draft leaves scholar-write:

- [ ] No bulleted lists of `M1`, `M2`, ... `Mn` items.
- [ ] No bulleted lists of `R1`, `R2`, ... `Rn` items.
- [ ] No inline equations inside bullets.
- [ ] No subsection headers matching `Language|Discipline|Commitment|Principles|Framing|Hygiene|Protocol`.
- [ ] At most two subsections under §4 Methods (typically: Main specification, Robustness).
- [ ] Paragraph count ≥ 3 in §4. Bullet count in §4 ≤ paragraph count.
- [ ] Each model ID and robustness ID appears at least once as a parenthetical tag in prose so Stage 2 can find it.
- [ ] Word target for §4 is 600–1000 words of prose. Under 400 = outline, expand; over 1200 = collapse subsections.

If any checkbox fails, rewrite before advancing.

---

## Why the registry must not be mirrored

`spec-registry.csv` stores rows like:

```csv
spec_id,description,estimator,weight,se_cluster,outcome,sample
M1,unconditional trend,OLS,WTSSALL,year,CHLDIDEL,full
M3,education × year focal,OLS,WTSSALL,year,CHLDIDEL,full
R5,reproductive-age restriction,OLS,WTSSALL,year,CHLDIDEL,18-44
```

This is grep-friendly machinery for downstream verification (e.g., `scholar-verify` Stage 2). It is *not* a drafting template. Reproducing its flat structure in §4 of a manuscript is the single largest prose-quality defect observed in AI-drafted output. Translate each row into a clause; preserve the spec_id as a parenthetical so the verifier can still trace.
