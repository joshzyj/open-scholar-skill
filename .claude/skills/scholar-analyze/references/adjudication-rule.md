# Hypothesis Adjudication Rule (Deterministic, Coded)

Prose adjudication ("consistent with", "directionally supportive") drifts. This file defines the **single coded rule** every `scholar-analyze` run must apply to every pre-registered hypothesis. The rule is applied by the analysis script, written to `adjudication-log.csv`, and cited verbatim in Results prose — the prose must NOT invent a different verdict.

---

## The Rule

For each hypothesis `H` with a hypothesized direction `d ∈ {+, −, ≠0, =0}`, a test statistic on the focal coefficient `β` (or AME for logit/probit) with two-sided p-value `p`, 95% CI `[lo, hi]`, and pre-registered α (default α = 0.05):

| Condition | `adjudication_code` | Required prose verb |
|---|---|---|
| `p < α` AND `sign(β) == d` (for + / − hypotheses) | `SUPPORTED` | "supports" / "is consistent with" |
| `p < α` AND `sign(β) ≠ d` | `CONTRADICTED` | "contradicts" (report the opposite-sign effect explicitly) |
| `p ≥ α` AND `d = =0` (null hypothesis pre-registered) | `SUPPORTED_NULL` | "supports the null expectation"; require equivalence bounds or Bayes factor |
| `α ≤ p < 0.10` AND `sign(β) == d` | `AMBIGUOUS` | "directionally consistent but imprecise"; must NOT call this "supported" |
| `p ≥ 0.10` AND `d ∈ {+, −, ≠0}` | `NOT_SUPPORTED` | "not supported" / "null" — report β, SE, p, and CI in full |
| CI crosses zero but `p < α` (computational disagreement) | `INCONSISTENT_FLAG` | halt and re-check SE/CI computation before drafting |

**Two-sided tests by default.** One-sided tests are only permitted if pre-registered in Phase 3 AND the direction `d` is specified before looking at results.

**Multiple testing (MANDATORY when K ≥ 3).** When `H` is part of a pre-registered family of K ≥ 3 sub-hypotheses (heterogeneity panel of K modifiers, K-arm dose-response contrasts, K outcomes for the same treatment, etc.), the analysis script MUST:

1. Call `p.adjust(p_raw_vector, method = ...)` with one of `holm`, `BH`, `BY`, or `bonferroni`. The choice (and α) is fixed at design time in the Phase 3 blueprint and cited in Methods.
2. Record BOTH `p_raw` and `p_adj` in `adjudication-log.csv` (the schema below already includes both columns; `p_adj` is `NA` only when K = 1 or K = 2).
3. Emit a per-family audit file `${PROJ}/verify/family-correction-<HID>.csv` (one file per family) with the schema:
   ```
   family_id, k, raw_p, adj_method, adj_p, alpha, n_survive
   ```
   - `k` = the number of sub-hypotheses in the family
   - `n_survive` = count of cells where `adj_p < alpha`
   - One row per sub-hypothesis (so the file has `k` rows)

4. The hypothesis verdict (`adjudication_code` for the family) MUST be derived from `p_adj`, not `p_raw`. Specifically:
   - `n_survive ≥ 1` AND sign matches → `SUPPORTED` (cite the surviving cell verbatim)
   - `n_survive == 0` → `NOT_SUPPORTED` (any "PARTIAL support" or "directionally consistent" framing of an uncorrected single-cell `p_raw < α` is forbidden — review-code-statistics flags this as CRIT-STAT)

5. Add a `family_id` column to `adjudication-log.csv` so family membership is groupable on the record. If a hypothesis is NOT part of a family (K = 1), set `family_id = hypothesis_id` (singleton family).

**Family-correction self-check (MANDATORY before drafting).** Group `adjudication-log.csv` by `family_id`; for every group with K ≥ 3, `verify/family-correction-<family_id>.csv` must exist with the required columns BEFORE any Results prose is drafted. A missing or malformed file means the family's verdict rests on uncorrected p-values — stop and fix. (The motivating failure: a K = 9 moderator panel whose single uncorrected `p_raw < 0.05` cell shipped as "PARTIAL support"; under this rule that family adjudicates `NOT_SUPPORTED` unless a cell survives correction.)

**Equivalence tests** (for `d = =0`): use TOST with pre-registered SESOI; `SUPPORTED_NULL` only if both one-sided tests reject at α.

---

## Required output: `adjudication-log.csv`

Every `scholar-analyze` run in DATA-AVAILABLE MODE must emit this file to `${PROJ}/tables/adjudication-log.csv`:

```
hypothesis_id, family_id, statement, direction_hypothesized, model, focal_coef_name,
  beta, se, p_raw, p_adj, ci_low, ci_high, ame, alpha, adjudication_code,
  prose_verb, table_ref, figure_ref, script, notes
```

`family_id`: mandatory column. Singleton hypotheses set `family_id = hypothesis_id`; multi-sub-hypothesis families share a `family_id` (e.g., all nine rows of an H3 moderator panel share `family_id = H3`). The family-correction self-check above groups by this column to detect K ≥ 3 families that need correction emission.

- One row per hypothesis. Every `H` (or RQ + expected pattern in INTEGRATED-RQ mode) listed in PROJECT STATE Phase 2 must appear.
- `adjudication_code` is computed by code, not prose. Any Results paragraph discussing hypothesis `H1` must cite `adjudication-log.csv` row `H1` and use its `prose_verb` — not a synonym chosen by the writer.
- If a hypothesis is tested by multiple specifications (main + robustness), emit one row per spec and mark the pre-registered primary with `notes=primary`.

---

## Implementation (R, using `marginaleffects` + `broom`)

```r
# One helper, reused across all hypothesis tests.
adjudicate <- function(beta, se, p_raw, ci_low, ci_high, direction_hypothesized,
                       alpha = 0.05, p_adj = NA_real_) {
  p_use <- if (!is.na(p_adj)) p_adj else p_raw
  dir_sign <- switch(direction_hypothesized, `+` = 1, `-` = -1, `!=0` = NA, `=0` = 0)
  if (!is.na(dir_sign) && dir_sign == 0) {
    # Null hypothesis case — SUPPORTED_NULL requires explicit equivalence test elsewhere.
    if (p_use >= alpha) return("SUPPORTED_NULL_CANDIDATE")
    return("NOT_SUPPORTED")
  }
  if (!is.na(p_use) && p_use < alpha) {
    if (is.na(dir_sign) || sign(beta) == dir_sign) return("SUPPORTED")
    return("CONTRADICTED")
  }
  if (!is.na(p_use) && p_use < 0.10 &&
      (is.na(dir_sign) || sign(beta) == dir_sign)) return("AMBIGUOUS")
  "NOT_SUPPORTED"
}

prose_verb <- c(
  SUPPORTED = "is consistent with",
  SUPPORTED_NULL = "supports the null expectation",
  SUPPORTED_NULL_CANDIDATE = "is consistent with the null (equivalence test required)",
  AMBIGUOUS = "is directionally consistent but imprecise",
  CONTRADICTED = "contradicts",
  NOT_SUPPORTED = "is not supported by"
)
```

---

## How Results prose must cite the log

When drafting paragraph ¶2 (MAIN FINDINGS) in the Results section, every statement about `H_k` must be backed by a row in `adjudication-log.csv` and must:

1. State the `adjudication_code` verdict in the verb chosen by the code (use `prose_verb[code]`).
2. Report full statistics: `β = [value], SE = [value], 95% CI = [lo, hi], p = [value]`, AME for logit/probit.
3. Cite the table/figure reference stored in the log (no free-hand references).

**Forbidden drift patterns:**
- "Directionally consistent with H1" when `adjudication_code = AMBIGUOUS`. Use "imprecise" or "not supported at conventional levels" — never let AMBIGUOUS read as SUPPORTED.
- Omitting the p-value and reporting only a sign ("H1 is negative"). Always carry full statistics.
- Rewriting a `NOT_SUPPORTED` as "suggestive" unless the adjudication code is `AMBIGUOUS`.

Phase 7b `verify-logic` agent reads `adjudication-log.csv` and greps the draft for hypothesis mentions that deviate from the coded verdict; any mismatch is ★★ CRITICAL.
