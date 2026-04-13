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

**Multiple testing.** When `H` is part of a family tested with BH/Holm, `p` above is the **adjusted** p-value. Record both raw and adjusted in the log.

**Equivalence tests** (for `d = =0`): use TOST with pre-registered SESOI; `SUPPORTED_NULL` only if both one-sided tests reject at α.

---

## Required output: `adjudication-log.csv`

Every `scholar-analyze` run in DATA-AVAILABLE MODE must emit this file to `${PROJ}/tables/adjudication-log.csv`:

```
hypothesis_id, statement, direction_hypothesized, model, focal_coef_name,
  beta, se, p_raw, p_adj, ci_low, ci_high, ame, alpha, adjudication_code,
  prose_verb, table_ref, figure_ref, script, notes
```

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
