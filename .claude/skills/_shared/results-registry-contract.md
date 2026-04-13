# Results Registry Contract

Purpose: eliminate the failure mode where a Task agent's prose return claims one result while disk files show another. After Phase 5 agents run, the orchestrator MUST read from disk — never from the agent's return text — and the disk artifacts below are the single source of truth.

---

## Required files after Phase 5 (DATA-AVAILABLE MODE)

Every Phase 5 analysis run must emit these, in addition to tables/figures/scripts:

| File | Path | Purpose |
|---|---|---|
| `results-registry.csv` | `${PROJ}/tables/results-registry.csv` | Machine-readable map: hypothesis ↔ coefficient ↔ table/figure |
| `adjudication-log.csv` | `${PROJ}/tables/adjudication-log.csv` | Per-hypothesis verdict from the coded adjudication rule |
| `ame-*.csv` | `${PROJ}/tables/ame-[model].csv` | AME table for every logit / probit / ordered logit model (mandatory) |
| `coefficients-*.csv` | `${PROJ}/tables/coefficients-[model].csv` | Raw coefficients + SEs + CIs for each model column |

If any of these is missing, Phase 5 is NOT complete and the orchestrator must re-dispatch the Task agent with explicit instructions to emit them.

---

## `results-registry.csv` schema

```
hypothesis_id, model_id, table_ref, figure_ref, focal_coef_name,
  beta, se, ci_low, ci_high, p_raw, p_adj, ame, ame_ci_low, ame_ci_high,
  n_obs, n_clusters, estimator, se_type, script, notes
```

- One row per (hypothesis × model specification). Robustness specs included.
- `table_ref` and `figure_ref` point to the numbered artifact in the ARTIFACT REGISTRY (e.g., `Table 2, col 3`, `Figure 3B`).
- `ame*` fields are required for logit/probit; left empty for OLS/linear.
- `estimator` names the function actually called (`feols`, `glm(family=binomial)`, `survey::svyglm`, etc.) — not a prose description.
- `se_type` is explicit (`HC3`, `CR1:state`, `conventional`, `bootstrap:1000`).

---

## `ame-[model].csv` schema (mandatory for logit/probit/ordered logit)

```
variable, contrast, estimate, std_error, statistic, p_value, ci_low, ci_high,
  n, model_id, script
```

Produced via `marginaleffects::avg_slopes()` or `avg_comparisons()` — not hand-computed from coefficients. This is the canonical AME artifact that Results prose must cite (ASR/AJS/Demography/NHB/NCS reporting norm).

---

## Post-agent reconciliation (orchestrator step, MANDATORY)

Immediately after each Phase 5 Task agent returns, BEFORE writing PROJECT STATE:

```bash
. "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/derive-proj.sh"

# 1. Confirm the contract artifacts exist on disk.
for f in results-registry.csv adjudication-log.csv; do
  if [ ! -f "${PROJ}/tables/$f" ]; then
    echo "CONTRACT VIOLATION: ${PROJ}/tables/$f missing — re-dispatch Task agent with emit instruction."
    exit 1
  fi
done

# 2. Confirm AME CSV for every logit/probit script.
for s in "${PROJ}"/scripts/*.R; do
  if grep -qE 'glm\(|feglm\(|clm\(|polr\(' "$s" 2>/dev/null; then
    base=$(basename "$s" .R)
    if ! ls "${PROJ}/tables/ame-"*.csv >/dev/null 2>&1; then
      echo "CONTRACT VIOLATION: $s appears to fit logit/probit but no ame-*.csv found."
      exit 1
    fi
  fi
done

# 3. Reconcile: Task agent return text vs. CSV truth.
echo "--- Results registry (DISK TRUTH) ---"
cat "${PROJ}/tables/results-registry.csv"
echo "--- Adjudication (DISK TRUTH) ---"
cat "${PROJ}/tables/adjudication-log.csv"
```

**Reconciliation rule.** When the agent's return prose disagrees with any row in `results-registry.csv` or `adjudication-log.csv`, the CSV is truth. The orchestrator:
- Writes the CSV values (β, SE, p, adjudication_code) into PROJECT STATE Phase 5.
- Does NOT copy the agent's prose summary verbatim.
- Logs the disagreement to `${PROJ}/logs/reconcile-[date].md` so we can audit why the agent hallucinated.

---

## Disk-citation discipline in PROJECT STATE

Every numeric claim the orchestrator writes into PROJECT STATE Phase 5 must carry a disk citation in the form:

```
H1c: β = -0.128, SE = 0.036, p = .0004 [results-registry.csv row=H1c model_id=M3]
```

Not this:

```
H1c: precisely negative effect, consistent with social-monitoring cost (from agent summary)
```

Phase 7 (drafting) refuses to read PROJECT STATE Phase 5 entries that lack a disk citation. This is a hard gate.

---

## PROVISIONAL tagging

All PROJECT STATE Phase 5 entries are tagged `[PROVISIONAL — pending Phase 5.5 code review]` when written. Phase 5.5 clears them to `[VERIFIED]` after code review passes. Phase 7 (drafting) refuses to read `[PROVISIONAL]` entries. This prevents a stale artifact (e.g., the H1c sign-flip caused by missing province FE and NA-as-0 recoding) from shaping manuscript framing before the code review catches it.
