# Ladder — Quasi-Experimental

**When this ladder applies:** DESIGN_TYPE = `quasi-experimental:<DiD|RD|IV|synth>`. The headline specification is pinned by the identification strategy; ladder discipline is replaced by an **ID-specific robustness battery**.

**Why no progressive controls ladder:** The causal claim rests on the identifying assumption (parallel trends, local continuity, exclusion restriction, convex-hull fit), not on coefficient stability across control sets. Robustness here means *stress-testing the assumption*, not adding covariates.

---

## Sub-type: DiD (Difference-in-Differences)

### Specification set

| spec_id | Role | Formula | Purpose |
|---|---|---|---|
| `DiD:event-study` | Focal | `feols(y ~ i(rel_time, treat, ref=-1) | unit + time, cluster=~unit)` | Pre/post event-time coefficients |
| `DiD:TWFE-static` | Summary | `feols(y ~ treat*post | unit + time, cluster=~unit)` | Single-coefficient summary; risky under heterogeneous effects |
| `DiD:CS` | Robust estimator | `did::att_gt()` (Callaway & Sant'Anna 2021) | Staggered-adoption-robust ATT |
| `DiD:dCDH` | Robust estimator | `DIDmultiplegt::did_multiplegt()` (de Chaisemartin & D'Haultfœuille) | Weight diagnostic for TWFE |
| `DiD:pre-trend` | Sensitivity | F-test of pre-period coefficients jointly = 0 | Parallel-trends plausibility |
| `DiD:placebo-period` | Sensitivity | Shift "treatment" date back; refit | Spurious timing |
| `DiD:alt-control` | Sensitivity | Drop neighboring states / re-weight controls | Control-group composition |

**Focal for adjudication:** `DiD:event-study` (look at post-period coefficients). `DiD:TWFE-static` is a descriptive summary — flag as unreliable if Goodman-Bacon/dCDH diagnostics show > 10% negative weights.

---

## Sub-type: RD (Regression Discontinuity)

### Specification set

| spec_id | Role | Formula | Purpose |
|---|---|---|---|
| `RD:local-linear-CCT` | Focal | `rdrobust::rdrobust(y, X, c=cutoff)` | CCT-optimal bandwidth, order-1 local linear |
| `RD:bandwidth:IK` | Sensitivity | IK bandwidth | Alt bandwidth selector |
| `RD:bandwidth:half-CCT` | Sensitivity | ½ × CCT | Narrower bandwidth |
| `RD:bandwidth:2x-CCT` | Sensitivity | 2 × CCT | Wider bandwidth |
| `RD:quadratic` | Sensitivity | order-2 polynomial | Functional form |
| `RD:mccrary` | Validity | `rddensity::rddensity(X)` | Manipulation at cutoff |
| `RD:donut-hole` | Sensitivity | Drop ±δ of cutoff | Sorting near cutoff |
| `RD:placebo-cutoff` | Sensitivity | Fake cutoff at different X value | Spurious jumps |
| `RD:covariate-balance` | Validity | Test for jumps in pre-determined covariates at cutoff | Continuity of potential outcomes |

**Focal for adjudication:** `RD:local-linear-CCT`. Report McCrary p-value in the abstract — if p < 0.10, reviewers will ask.

---

## Sub-type: IV (Instrumental Variables)

### Specification set

| spec_id | Role | Formula | Purpose |
|---|---|---|---|
| `IV:2SLS` | Focal | `feols(y ~ . | fe | d ~ z, data)` or `ivreg::ivreg()` | Local Average Treatment Effect |
| `IV:first-stage` | Validity | `summary(first_stage)` with F-stat | Weak-instrument check (F ≥ 10; if < 104, use AR CI) |
| `IV:reduced-form` | Validity | `lm(y ~ z + controls)` | Y-Z reduced form |
| `IV:AR-CI` | Sensitivity | Anderson-Rubin confidence interval | Weak-IV-robust inference |
| `IV:over-id` | Validity (if > 1 IV) | Sargan / Hansen J | Exclusion-restriction joint test |
| `IV:OLS-bias-direction` | Descriptive | OLS coefficient | Compare to IV to characterize bias |

**Focal for adjudication:** `IV:2SLS`. Report first-stage F prominently. `IV:OLS-bias-direction` is for interpretation only — never the focal claim.

---

## Sub-type: Synthetic Control

### Specification set

| spec_id | Role | Formula | Purpose |
|---|---|---|---|
| `synth:main` | Focal | `Synth::synth()` or `tidysynth` / `augsynth` | Counterfactual gap |
| `synth:in-time-placebo` | Sensitivity | Reassign treatment date to pre-period | Spurious gap detection |
| `synth:in-space-placebo` | Sensitivity | Treat each control unit as placebo; compute RMSPE ratio | Inference (permutation p) |
| `synth:leave-one-out` | Sensitivity | Drop each donor unit | Donor sensitivity |
| `synth:augmented` | Robust estimator | `augsynth::augsynth()` | Ridge-augmented for poor pre-fit |

**Focal for adjudication:** `synth:main` gap + `synth:in-space-placebo` RMSPE ratio as permutation p-value. Report pre-RMSPE-to-MSPE ratio for fit quality.

---

## Adjudication (all sub-types)

- **Focal model:** the first row in the sub-type's table.
- **Report the full robustness battery** — omitting any of the validity checks is a reviewer flag.
- **Divergence rule:** if ≥ 2 sensitivity specs materially contradict the focal, flag in the limitations paragraph and demote to "suggestive" in the abstract.

---

## Script header contract

```r
# Ladder: ladder-quasi-experimental.md
# Design Type: quasi-experimental:<DiD|RD|IV|synth>   (from ${PROJ}/logs/project-state.md)
# Specs emitted: [sub-type-specific list]
```
