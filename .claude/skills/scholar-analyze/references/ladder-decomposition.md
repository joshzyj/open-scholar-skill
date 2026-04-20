# Ladder — Decomposition

**When this ladder applies:** DESIGN_TYPE = `decomposition:<Oaxaca|Kitagawa|KHB|APC>`. The research question is a *decomposition* question (how much of a gap is composition vs. coefficient; how much of a mediated effect is direct vs. indirect; how much of an outcome trend is period vs. cohort).

**Why no progressive controls ladder:** Oaxaca-Blinder, Kitagawa, KHB, IE, and HAPC are **different estimators answering different questions**. Staging them as M1→M4 hides the paper's real structure. Each estimator gets its own `spec_id`; the "ladder" is a **peer suite** indexed by decomposition target, not by control set.

**Existing reusable code:** `component-a-specialized.md` (A8 Oaxaca-Blinder, A8b KHB) and `decomposition-formulas.md` (Kitagawa, Oaxaca formulas). This ladder file *references* them — do not re-implement.

---

## Sub-type: Oaxaca-Blinder

### Specification set

| spec_id | Role | Purpose |
|---|---|---|
| `Oaxaca:threefold-pooled` | Focal | Threefold decomposition (endowments / coefficients / interaction) with pooled reference coefficients |
| `Oaxaca:twofold-groupA` | Alt | Twofold using group-A coefficients as reference |
| `Oaxaca:twofold-groupB` | Alt | Twofold using group-B coefficients |
| `Oaxaca:detailed` | Detailed | Variable-level contributions to endowments and coefficients |
| `Oaxaca:bootstrap-SE` | Sensitivity | Bootstrapped SEs and CIs (n_boot ≥ 1000) |

**Focal for adjudication:** `Oaxaca:threefold-pooled` with % endowment / % coefficient / % interaction as the headline quantities.

---

## Sub-type: Kitagawa

### Specification set

| spec_id | Role | Purpose |
|---|---|---|
| `Kitagawa:rate-decomp` | Focal | Rate decomposition: composition vs. rate component |
| `Kitagawa:alt-base` | Sensitivity | Alt standardization base population |
| `Kitagawa:bootstrap-SE` | Sensitivity | Bootstrapped SEs |

---

## Sub-type: KHB (Karlson-Holm-Breen)

### Specification set

| spec_id | Role | Purpose |
|---|---|---|
| `KHB:total-direct-indirect` | Focal | Total / direct / indirect effect with rescaling |
| `KHB:mediator-share` | Focal | % mediated by each candidate mediator |
| `KHB:alt-ordering` | Sensitivity | Alt causal ordering of mediators (if theory permits multiple) |

**Focal for adjudication:** `KHB:mediator-share`. Report the % mediated; if > 1 mediator, report individual contributions and joint.

---

## Sub-type: APC (Age-Period-Cohort)

### Specification set

| spec_id | Role | Purpose |
|---|---|---|
| `APC:IE` | Focal (triangulate with HAPC) | Intrinsic Estimator |
| `APC:HAPC` | Focal (triangulate with IE) | Hierarchical APC (random cohorts + periods) |
| `APC:Fosse-Winship-bounds` | Sensitivity | Bounds analysis (Fosse & Winship 2019) |
| `APC:IE-HAPC-overlay` | Visualization | Plot IE and HAPC period effects with 95% bands |
| `APC:reference-point` | Sensitivity | Alt IE reference-point choices |

**Focal for adjudication:** IE and HAPC **both** must be reported and triangulated via the Fosse-Winship rule. A single-estimator claim is insufficient.

---

## Required presentation

1. **Headline quantity first** — the % decomposition share should appear in the abstract (second or third sentence), not buried in Table 5. E.g.: "Composition accounts for ~99% of the Black-White gap, ~67% of the Hispanic-White gap, and ~77% of the Asian/Other-White gap."
2. **Figure before Table** — a stacked bar plot of components is the inferential object; the table is the appendix-style backup.
3. **No fake ladder** — do NOT stage Oaxaca/KHB/APC as "Model 5, Model 6, Model 7" in the same table. Separate tables, one per estimator.

---

## Optional "reviewer-compatibility" appendix

Some Demography reviewers still expect a regression ladder. If needed, include an **appendix Table** with M1 (bivariate) → M2 (+controls) → M3 (+interactions), clearly labeled "Associational models (appendix)" and referenced once from the main text: "See Table A1 for conventional regression specifications underlying the decomposition." This keeps genre convention without muddying the main structure.

---

## Adjudication

- **Hypothesis → spec_id:**
  - H1 (gap exists) → descriptive means (Table 1); not a ladder hypothesis.
  - H2 (composition dominates / coefficients dominate) → `<sub>:focal`.
  - H3 (heterogeneity across time/subgroups) → refit `<sub>:focal` within stratum; add `<sub>:focal:<stratum>` rows.

---

## Script header contract

```r
# Ladder: ladder-decomposition.md
# Design Type: decomposition:<Oaxaca|Kitagawa|KHB|APC>  (from ${PROJ}/logs/project-state.md)
# Specs emitted: [sub-type-specific list]
```
