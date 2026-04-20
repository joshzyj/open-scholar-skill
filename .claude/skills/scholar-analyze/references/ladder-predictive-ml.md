# Ladder — Predictive / ML

**When this ladder applies:** DESIGN_TYPE = `predictive-ML`. The research goal is prediction / classification / measurement, not causal inference. Includes: supervised classifiers, LLM annotation, topic models, text-as-data pipelines, network prediction, embedding-based retrieval.

**Why no ladder:** Model selection is governed by out-of-sample performance on a held-out test set, not by progressive covariate addition. "Add more controls" is an ill-defined operation for gradient-boosted trees, transformers, or topic models. The canonical ML presentation is a CV workflow + held-out test metrics + baseline comparison + ablation.

**Existing reusable code:** `component-a-specialized.md` and the `/scholar-compute` skill for heavy NLP/ML; this ladder file formalizes the spec-registry contract.

---

## Specification set

| spec_id | Role | Purpose |
|---|---|---|
| `ML:holdout-split` | Protocol | Pre-registered train/val/test split ratios, random seed, temporal split if time-series |
| `ML:baseline` | Required comparison | Simple baseline (majority class / logistic / mean) — focal MUST beat this |
| `ML:focal-v1` | Focal candidate | Primary model (e.g., gradient boosting, fine-tuned BERT) |
| `ML:focal-v2`, `...` | Alt model classes | Comparators (at least 1) |
| `ML:ablation:<component>` | Sensitivity | Drop one feature set / one pipeline step; measure degradation |
| `ML:calibration` | Validity | Calibration plot / Brier score / reliability diagram |
| `ML:subgroup-metrics` | Fairness / generalizability | Per-group metrics (race, gender, time period) |
| `ML:error-analysis` | Qualitative | Confusion-matrix-driven review of N ≥ 100 errors |

---

## Required reporting

1. **Pre-registered split** — test set MUST NOT be touched before final evaluation. Document random seed and split proportions in the PAP.
2. **Primary metric named BEFORE any training** — e.g., "macro-F1 on held-out test". Post-hoc metric swaps require disclosure.
3. **Cross-validation on train set only** — never use test set for hyperparameter tuning.
4. **Baseline comparison** — focal metric vs. `ML:baseline`. If focal < baseline + 0.02, reviewers will ask why.
5. **Ablation table** — at least one dropped-component comparison per major design decision.
6. **Subgroup metrics** — break out performance by demographics / time where applicable.
7. **Inter-rater agreement** — if labels are human-coded, report Cohen's κ or Krippendorff's α (target ≥ 0.70 for primary label).

---

## For LLM annotation specifically

- Document prompt version (hash it), model ID, temperature, seed.
- Validate against N ≥ 200 gold-standard human labels.
- Report confidence-conditional accuracy (high-conf vs. low-conf).
- Cost-per-1000-items disclosed for reproducibility scope.

---

## Adjudication

- **Hypothesis → spec_id:**
  - H1 (the model predicts better than baseline) → test-set comparison of `ML:focal-v1` vs `ML:baseline`.
  - H2 (the model is well-calibrated) → `ML:calibration` Brier / calibration curve.
  - H3 (performance is equitable across subgroups) → `ML:subgroup-metrics` with explicit fairness criterion (TPR parity / equal opportunity / etc.).
- **No coefficient-stability / Oster δ / E-value.** Those are causal-inference tools and do not apply.

---

## Manuscript Table convention

- **Table 2:** held-out test metrics (focal vs. alt model classes vs. baseline). Metric names in column headers, models in rows.
- **Table 3:** ablation results.
- **Figure:** calibration plot or precision-recall curve as the inferential object.

---

## What the router catches (anti-cargo-cult)

If a Phase 5 script for DESIGN_TYPE `predictive-ML` tries to emit `M1 ~ bivariate`, `M2 ~ +controls`, that is a **drift error**. The auto-improve A11 check flags it. For ML work, the ladder-rungs concept does not apply and the spec-registry MUST use `ML:*` spec_ids only.

---

## Script header contract

```r
# Ladder: ladder-predictive-ml.md
# Design Type: predictive-ML
# Specs emitted: ML:holdout-split, ML:baseline, ML:focal-v1 [, ML:focal-v2, ML:ablation:*, ML:calibration, ML:subgroup-metrics]
```
