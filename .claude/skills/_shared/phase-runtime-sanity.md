# Phase 5C — Runtime Sanity Gate

Script-level review (5A.5, 5B-gate, 5.5) catches bugs in source code. Phase 5C catches bugs that appear at runtime: NaN propagation, implausible coefficients, non-determinism, direction flips across specifications, and pre-registration drift. Runs after 5.5 (post-execution code review has cleared scripts), before Phase 6.

> **⛔ ENTRY GATE — Confirm 5.5 is complete:**
> ```bash
> . "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"
> grep -q '\[VERIFIED' "${PROJ}/logs/project-state.md" || { echo "FAIL: Phase 5.5 not cleared"; exit 1; }
> test -f "${PROJ}/tables/results-registry.csv"   || { echo "FAIL: registry missing"; exit 1; }
> test -f "${PROJ}/tables/adjudication-log.csv"   || { echo "FAIL: adjudication missing"; exit 1; }
> ```

Execute all five checks in order. Any CRITICAL halts; ESCALATE to user. Save the consolidated report to `${PROJ}/verify/runtime-sanity-[date].md`.

---

## Check 1: Plausibility scan

Read `results-registry.csv` + `coefficients-*.csv` + `ame-*.csv` and reject rows with:

- `abs(ame) > 1` on probability outcomes (AME is percentage-point change; > 1 = impossible)
- `abs(beta / se) > 100` (t-statistic > 100 on social-science data almost always means wrong SE clustering, degenerate variable, or unit-of-measure bug)
- `n_obs == 0` or `n_obs` below Phase 4 estimated N × 0.5 (silently dropped most of the sample)
- NaN or Inf in `beta`, `se`, `p_raw`, `ci_low`, `ci_high`, `ame`, or `n_obs`
- `p_raw < 0` or `p_raw > 1`
- `ci_low > ci_high` (confidence interval inverted)
- `se <= 0`

Implementation:

```r
# phase5c-01-plausibility.R — append to ${PROJ}/scripts/
reg <- readr::read_csv(file.path(Sys.getenv("PROJ"), "tables", "results-registry.csv"))
flags <- reg %>%
  dplyr::mutate(
    flag_ame_impossible   = !is.na(ame) & abs(ame) > 1,
    flag_extreme_t        = !is.na(beta) & !is.na(se) & abs(beta/se) > 100,
    flag_zero_n           = n_obs == 0,
    flag_nan              = is.na(beta) | is.na(se) | is.na(p_raw),
    flag_bad_p            = !is.na(p_raw) & (p_raw < 0 | p_raw > 1),
    flag_ci_inverted      = !is.na(ci_low) & !is.na(ci_high) & ci_low > ci_high,
    flag_nonpos_se        = !is.na(se) & se <= 0
  ) %>%
  dplyr::filter(dplyr::if_any(dplyr::starts_with("flag_")))
readr::write_csv(flags, file.path(Sys.getenv("PROJ"), "verify", "plausibility-flags.csv"))
stopifnot(nrow(flags) == 0)
```

Any flagged row → CRITICAL. Re-dispatch to fix loop (adjudicate AUTO_FIX vs ESCALATE).

## Check 2: Direction consistency across specifications

For each hypothesis, compare `sign(beta)` across model specs M1 → M2 → M3 → M4.

```r
# phase5c-02-direction-consistency.R
reg <- readr::read_csv(file.path(Sys.getenv("PROJ"), "tables", "results-registry.csv"))
flips <- reg %>%
  dplyr::filter(!is.na(beta)) %>%
  dplyr::group_by(hypothesis_id) %>%
  dplyr::summarise(
    signs = list(unique(sign(beta))),
    n_signs = length(unique(sign(beta)))
  ) %>%
  dplyr::filter(n_signs > 1)
readr::write_csv(flips, file.path(Sys.getenv("PROJ"), "verify", "direction-flips.csv"))
```

Any hypothesis with `n_signs > 1` is flagged `DIRECTION_UNSTABLE`. This is NOT automatically CRITICAL (robustness flips sometimes are the finding), but the Results prose MUST address the flip explicitly. Append a block to `${PROJ}/verify/runtime-sanity-[date].md`:

```
DIRECTION_UNSTABLE hypotheses — prose must address:
  H1c: M1 (+0.03), M2 (−0.05), M3 (−0.13), M4 (+0.02)
       → Results section must explain which spec is primary (per Phase 3 blueprint) and why the others differ
```

Phase 7b `verify-logic` re-checks that the prose addresses every `DIRECTION_UNSTABLE` flag.

## Check 3: Clean-room re-run (opt-out for exploratory; default on for top journals)

Spin up a fresh R session, re-run `04-*.R` through `08-*.R` in order, diff the new `results-registry.csv` against the stored one.

```bash
# phase5c-03-cleanroom.sh
. "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"
TARGET_JOURNAL=$(grep -E "Target Journal" "${PROJ}/logs/project-state.md" | head -1)
case "$TARGET_JOURNAL" in
  *ASR*|*AJS*|*Demography*|*Nature*|*Science*) RUN_CLEANROOM=1 ;;
  *) RUN_CLEANROOM=${SCHOLAR_FORCE_CLEANROOM:-0} ;;
esac
if [ "$RUN_CLEANROOM" != "1" ]; then
  echo "Clean-room re-run: SKIPPED (non-top-journal; set SCHOLAR_FORCE_CLEANROOM=1 to run)"
  exit 0
fi

cp "${PROJ}/tables/results-registry.csv" "${PROJ}/verify/registry-original.csv"
mkdir -p "${PROJ}/verify/cleanroom"

# Run in an isolated R session with minimal envvars.
env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin" PROJ="$PROJ" \
  Rscript -e '
    setwd(Sys.getenv("PROJ"))
    for (s in sort(Sys.glob("scripts/0[4-8]-*.R"))) {
      cat("Running:", s, "\n"); source(s)
    }
  ' 2>&1 | tee "${PROJ}/verify/cleanroom/rerun.log"

diff <(sort "${PROJ}/verify/registry-original.csv") \
     <(sort "${PROJ}/tables/results-registry.csv") > "${PROJ}/verify/cleanroom/diff.txt"

if [ -s "${PROJ}/verify/cleanroom/diff.txt" ]; then
  echo "CRITICAL: clean-room re-run diverged from stored registry (non-determinism or uncommitted state)."
  cat "${PROJ}/verify/cleanroom/diff.txt"
  exit 1
fi
echo "Clean-room re-run: PASS"
```

Divergence → CRITICAL. Common causes: missing `set.seed()` (auto-fix via fix loop), hard-coded paths that drift between sessions (auto-fix), uncommitted interactive state (escalate — user did something outside the scripts).

## Check 4: Runtime invariants present in scripts

Grep each analysis script for at least one `stopifnot()` / `assertthat::assert_that()` call that asserts:

- `N > 0` after sample construction
- No NaN in focal predictor / outcome column after recoding

```bash
for s in "${PROJ}"/scripts/0[4-7]-*.R; do
  if ! grep -qE 'stopifnot\(|assert_that\(' "$s"; then
    echo "WARN: $s has no runtime assertions — auto-fix loop will insert stopifnot(nrow(df) > 0)"
  fi
done
```

Missing assertions → AUTO_FIX via fix loop (insert `stopifnot(nrow(df) > 0)` after sample construction). Not halting.

## Check 5: Pre-analysis-plan compliance (if PAP exists)

```bash
PAP=$(ls "${PROJ}/preregistration"/*.md 2>/dev/null | head -1)
if [ -n "$PAP" ]; then
  # Extract pre-registered hypothesis IDs + pre-registered model specs
  grep -oE 'H[0-9][a-z]?' "$PAP" | sort -u > "${PROJ}/verify/pap-hypotheses.txt"
  cut -d, -f1 "${PROJ}/tables/results-registry.csv" | sort -u > "${PROJ}/verify/registry-hypotheses.txt"

  # Hypotheses in PAP but missing from registry → MISSING_TEST
  comm -23 "${PROJ}/verify/pap-hypotheses.txt" "${PROJ}/verify/registry-hypotheses.txt" \
    > "${PROJ}/verify/missing-pap-tests.txt"
  if [ -s "${PROJ}/verify/missing-pap-tests.txt" ]; then
    echo "CRITICAL: pre-registered hypotheses not tested in registry:"
    cat "${PROJ}/verify/missing-pap-tests.txt"
    exit 1
  fi

  # Hypotheses in registry but not in PAP → label as EXPLORATORY (allowed, must be disclosed)
  comm -13 "${PROJ}/verify/pap-hypotheses.txt" "${PROJ}/verify/registry-hypotheses.txt" \
    > "${PROJ}/verify/exploratory-hypotheses.txt"
  if [ -s "${PROJ}/verify/exploratory-hypotheses.txt" ]; then
    echo "NOTE: unregistered hypotheses present — must be labeled EXPLORATORY in Results and disclosed in ethics statement:"
    cat "${PROJ}/verify/exploratory-hypotheses.txt"
  fi
fi
```

Missing tests → CRITICAL (re-run Phase 5B with corrected script or document the drop with justification). Extra tests → NOTE, recorded for Phase 9b ethics (AI/QRP disclosure) and Results prose labeling.

---

## Consolidated report

Write `${PROJ}/verify/runtime-sanity-[date].md`:

```markdown
# Runtime Sanity Report — [date]

## Check 1 — Plausibility: [PASS / N flags]
## Check 2 — Direction consistency: [PASS / N DIRECTION_UNSTABLE]
## Check 3 — Clean-room re-run: [PASS / SKIPPED / DIVERGED]
## Check 4 — Runtime invariants: [PASS / WARN: N scripts missing]
## Check 5 — PAP compliance: [PASS / MISSING tests: ... / EXPLORATORY: ...]

Overall verdict: [PASS / FIX LOOP / ESCALATE]
```

Append verdict + file path to PROJECT STATE as Phase 5C entry. Phase 7-PreGate reads this entry.
