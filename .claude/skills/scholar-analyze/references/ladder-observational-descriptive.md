# Ladder — Observational-Descriptive (default)

**When this ladder applies:** DESIGN_TYPE = `observational-descriptive`. Cross-sectional or longitudinal association papers targeting ASR/AJS/Demography/Social Forces. The M1→M4 progression is a publication convention these reviewers expect (coefficient-stability diagnostic, Altonji-Elder-Taber / Oster-δ logic, control-saturation disclosure).

**Authority:** This is the historical default; preserved verbatim from `component-a-regression.md` (A3) and `scholar-design/SKILL.md` Step 5c (Presentation sequence).

---

## Specification set

| spec_id | Rung | Formula | Purpose |
|---|---|---|---|
| `descriptive:M1` | M1 — bivariate | `Y ~ X` | Raw association |
| `descriptive:M2` | M2 — +controls | `Y ~ X + controls` | Does association survive confounders? |
| `descriptive:M3` | M3 — +FE / ID layer | `Y ~ X + controls | unit + time` (fixest) | Within-unit / within-time identification |
| `descriptive:M4` | M4 — +interaction (optional) | `Y ~ X * moderator + controls` | Moderator hypothesis — include ONLY if pre-registered in Phase 3 |

Estimator tables (OLS, feols FE, logit, ordered logit, GLMM, Cox PH, NB) are in `component-a-regression.md` — do not re-implement here.

---

## Required robustness battery

Write these into `spec-registry.csv` as separate spec_ids:

- `descriptive:robust:oster-delta` — `sensemakr::sensemakr()` with the strongest observed covariate as benchmark; report δ and R²-threshold.
- `descriptive:robust:e-value` — `EValue::evalues.OLS()` (or `evalues.HR()` / `evalues.OR()` per outcome).
- `descriptive:robust:alt-sample` — at least one meaningful sample restriction (e.g., exclude imputed cases, restrict to complete cases, exclude outliers via Cook's D > 4/N).
- `descriptive:robust:alt-operationalization` — at least one alternative coding of X or Y.

---

## Adjudication

- **Focal model:** M3 by default. Promote M4 to focal only when the moderator is the primary hypothesis.
- **Hypothesis → spec_id mapping** (written to `adjudication-log.csv`):
  - H1 (main effect) → `descriptive:M3`
  - H2 (attenuation / robustness to controls) → `descriptive:M1` vs `descriptive:M2` comparison + Oster δ
  - H3 (moderator) → `descriptive:M4`
- Apply `adjudication-rule.md` per hypothesis with the per-spec focal coefficient.

---

## Manuscript Table 2 convention

Columns: `Bivariate` | `+Controls` | `+FE` | `+Interaction (if any)`. AME reported below each column for any non-linear link (see `component-a-regression.md` A4). HC3 SEs for OLS; clustered SEs when clustering level is pre-specified.

---

## Script header contract

```r
# Ladder: ladder-observational-descriptive.md
# Design Type: observational-descriptive (from ${PROJ}/logs/project-state.md)
# Specs emitted: descriptive:M1, descriptive:M2, descriptive:M3 [, descriptive:M4]
```
