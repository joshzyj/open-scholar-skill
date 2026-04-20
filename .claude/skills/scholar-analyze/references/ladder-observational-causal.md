# Ladder — Observational-Causal-with-DAG

**When this ladder applies:** DESIGN_TYPE = `observational-causal-with-DAG`. The design team ran `/scholar-causal`, identified a minimal adjustment set via the backdoor criterion, and committed to it. The "ladder" is **one focal specification + sensitivity**, not a progression of rungs.

**Why no progressive ladder:** Adding "M1 bivariate" introduces confounding that the DAG explicitly diagnosed; adding mediators or colliders breaks identification. Reviewers at Demography/Sociological Methodology understand this (see Elwert & Winship 2014, Hernán & Robins). Progressive disclosure for observational-causal claims is *theoretical regression*, not transparency.

---

## Required upstream artifact

`${PROJ}/design/identification-strategy.json` MUST exist (emitted by `scholar-causal` at Save Output; see the "Emit `identification-strategy.json`" block in `scholar-causal/SKILL.md`). `scholar-analyze` hard-errors if missing when `Design Type: observational-causal-with-DAG`. Schema:

```json
{
  "design_type": "observational-causal-with-DAG",
  "identification_strategy": "OLS + backdoor adjustment",
  "treatment_variable": "X",
  "outcome_variable": "Y",
  "adjustment_set": ["C1", "C2", "C3"],
  "mediators_excluded": ["M1"],
  "colliders_excluded": ["K1"],
  "assumptions": ["no unmeasured confounding", "positivity", "SUTVA"],
  "robustness_battery": ["oster_delta", "e_value", "bounds_manski"]
}
```

---

## Specification set

| spec_id | Role | Formula | Purpose |
|---|---|---|---|
| `DAG:focal` | Focal | `Y ~ X + <adjustment_set>` (+ FE/cluster per `identification_strategy`) | The identification-set-implied estimand |
| `DAG:sensitivity:oster` | Sensitivity | `sensemakr::sensemakr(focal, treatment=X, benchmark_covariates=<strongest element of adjustment_set>)` | Bound on unmeasured confounding (Oster δ, R² threshold) |
| `DAG:sensitivity:evalue` | Sensitivity | `EValue::evalues.OLS(est=β, se=SE)` | Minimum E-value to explain away the effect |
| `DAG:sensitivity:bounds` | Sensitivity | Manski or Lee bounds if missing-outcome or selection concerns | Non-parametric bound |
| `DAG:placebo` | Validity | Replace Y with a pre-treatment outcome; refit | Spurious association check |

**No bivariate / progressive-controls rows.** Reviewers should see the focal spec, then the sensitivity envelope. Anything else is noise.

---

## Execution skeleton

```r
spec <- jsonlite::fromJSON(file.path(Sys.getenv("PROJ"), "design", "identification-strategy.json"))
controls <- paste(spec$adjustment_set, collapse = " + ")
f <- as.formula(paste(spec$outcome_variable, "~", spec$treatment_variable, "+", controls))

focal <- lm(f, data = df)
coeftest(focal, vcov = sandwich::vcovHC(focal, type = "HC3"))

# Sensitivity
library(sensemakr)
sens <- sensemakr(model = focal,
                  treatment = spec$treatment_variable,
                  benchmark_covariates = spec$adjustment_set[1],
                  kd = 1:3)
ovb_minimal_reporting(sens)

library(EValue)
evalues.OLS(est = coef(focal)[spec$treatment_variable],
            se  = sqrt(diag(vcov(focal)))[spec$treatment_variable])
```

For IPW, entropy-balancing, or matching variants of the same adjustment set, add `DAG:focal:<variant>` rows to `spec-registry.csv` — still one conceptual focal estimand, just different estimators of it.

---

## Adjudication

- **Focal model:** `DAG:focal`.
- **Hypothesis → spec_id:** H1 → `DAG:focal`; H2 (if present) is typically a *heterogeneity* claim → `DAG:focal` refit within strata.
- **No Oster-δ / E-value gating** of the headline claim; report them as descriptive sensitivity, not as a pass/fail filter.

---

## Manuscript Table convention

**Table 2:** one row of focal coefficients (plus any heterogeneity rows). NOT a 4-column progression.
**Table 3:** sensitivity summary (Oster δ, E-value, bounds) — one row per check.

---

## Script header contract

```r
# Ladder: ladder-observational-causal.md
# Design Type: observational-causal-with-DAG
# Upstream: ${PROJ}/design/identification-strategy.json
# Specs emitted: DAG:focal, DAG:sensitivity:oster, DAG:sensitivity:evalue [, DAG:sensitivity:bounds, DAG:placebo]
```
