# Ladder — RCT / Field Experiment

**When this ladder applies:** DESIGN_TYPE = `RCT`. Includes individual-level RCTs, cluster RCTs (see `scholar-design` Step 2d), audit/correspondence studies (Step 2e), stepped-wedge trials (Step 2f), and SMART designs (Step 2g).

**Why no progressive controls ladder:** Randomization solves confounding. Adding M1 (unadjusted) → M2 (+controls) → M3 (+FE) invites reviewers to suspect specification search. The canonical RCT presentation is **ITT unadjusted** as headline + **pre-registered covariate-adjustment** for precision + optional pre-registered subgroup analysis.

---

## Specification set

| spec_id | Role | Formula | Purpose |
|---|---|---|---|
| `RCT:ITT-unadjusted` | Focal | `Y ~ T` | Intent-to-treat; the trial's answer |
| `RCT:ITT-adjusted` | Precision | `Y ~ T + <pre-registered covariates>` | ANCOVA-style precision gain; covariates from PAP only |
| `RCT:subgroup:<var>` | Exploratory or pre-registered | `Y ~ T * <moderator>` | One row per pre-registered subgroup; exploratory subgroups flagged |
| `RCT:CACE` | Secondary (if non-compliance) | 2SLS: `Y ~ D` instrumented by `T` | Complier Average Causal Effect |
| `RCT:attrition-lee` | Sensitivity | Lee (2009) bounds | Differential attrition bound |

**Do NOT** add `+controls` specs post-hoc that are not in the PAP. If the PAP didn't specify covariates, report only `RCT:ITT-unadjusted`.

---

## Design-specific variants

- **Cluster RCT:** use `lme4::lmer(y ~ T + (1 | cluster))` or `geepack::geeglm()`; report ICC and DEFF.
- **Audit / correspondence:** within-pair / pair-FE estimator (`clogit` or `feols(y ~ T | pair_id)`); dichotomous outcome AME required.
- **Stepped-wedge:** Hussey-Hughes mixed model with period and exposure-time fixed effects; report time-lagged exposure curves.
- **SMART:** stage-wise weighted regression per Murphy (2005); report dynamic treatment regime (DTR) comparisons.

All estimator details: `component-a-regression.md` and `component-a-specialized.md`.

---

## Required robustness / sensitivity

- `RCT:attrition-lee` — if attrition > 5% or differential attrition > 2pp, Lee bounds are mandatory.
- `RCT:balance-table` — Table 1 balance on all pre-treatment covariates; flag any imbalance with SMD > 0.10.
- `RCT:MHT-adjustment` — if > 1 primary outcome, apply Holm or BH; for subgroups, Westfall-Young or pre-registered.
- `RCT:placebo-outcome` — optional; only where a reasonable pre-treatment outcome exists.

---

## Adjudication

- **Focal model:** `RCT:ITT-unadjusted` (the trial's stated estimand).
- **Hypothesis → spec_id:**
  - H1 (primary outcome) → `RCT:ITT-unadjusted`; `RCT:ITT-adjusted` confirms.
  - H2 (secondary outcome) → same pair for that outcome; adjust for MHT.
  - H3 (subgroup) → `RCT:subgroup:<var>`; interpretation bounded by pre-registration status.
- **Divergence rule:** if `RCT:ITT-unadjusted` and `RCT:ITT-adjusted` differ in sign or move across significance threshold, report BOTH and flag as "precision estimate contradicts unadjusted ITT" — reviewers will ask.

---

## Manuscript Table convention

**Table 2:** one headline row per outcome — ITT-unadjusted coefficient, SE, p, N, adjusted mean difference. Covariate-adjusted row second. NOT a four-column progression.

---

## Script header contract

```r
# Ladder: ladder-rct.md
# Design Type: RCT
# Upstream: ${PROJ}/design/PAP.md (covariate list for ITT-adjusted spec)
# Specs emitted: RCT:ITT-unadjusted, RCT:ITT-adjusted [, RCT:subgroup:*, RCT:CACE, RCT:attrition-lee]
```
