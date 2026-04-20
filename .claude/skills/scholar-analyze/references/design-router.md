# Design Router — Model-Specification Strategy by DESIGN_TYPE

**Role:** Single source of truth that maps `Design Type` (from `${PROJ}/logs/project-state.md` when available; otherwise inferred from `scholar-design` blueprint or user input) to the correct ladder template, robustness battery, and adjudication hint. `scholar-analyze` consults this table before executing any regressions — both in standalone mode and when driven by an upstream orchestrator.

**Core philosophy (WHY this file exists):** The M1→M4 ladder is a publication convention for observational-descriptive sociology — not a universal inferential scaffold. Other designs need *different* specification sets (focal spec + sensitivity for DAG; unadjusted/covariate-adjusted for RCT; ID-specific robustness for quasi-exp; estimator suite for decomposition; CV workflow for ML). This router selects one branch per project.

---

## Routing table

| DESIGN_TYPE | Ladder template file (to `cat`) | Core specification set | Required robustness / sensitivity | Adjudication hint |
|---|---|---|---|---|
| `observational-descriptive` | `ladder-observational-descriptive.md` | M1 bivariate → M2 +controls → M3 +FE/ID → M4 +interaction (if pre-registered) | Oster δ or E-value; alt sample; alt operationalization | Focal = M3 (or M4 when moderator is primary H) |
| `observational-causal-with-DAG` | `ladder-observational-causal.md` | ONE focal spec driven by `${PROJ}/design/identification-strategy.json` `adjustment_set`; no progressive ladder | `sensemakr::sensemakr()` (Oster δ); `EValue::evalues.OLS()`; bounds (Manski) | Focal = the single DAG-implied spec; no attenuation comparison |
| `RCT` | `ladder-rct.md` | S1 unadjusted ITT → S2 covariate-adjusted (pre-registered covariates only) → S3 subgroup (if pre-registered) | Attrition sensitivity; Lee bounds; multiple-comparison adjustment | Focal = S1 (ITT unadjusted); S2 confirms precision, S3 is exploratory |
| `quasi-experimental:DiD` | `ladder-quasi-experimental.md` (DiD section) | Two-way FE spec + event-study | Pre-trend test, placebo period, Callaway-Sant'Anna / de Chaisemartin-D'Haultfœuille robust estimator, alt control group | Focal = event-study post-period; static TWFE is summary only |
| `quasi-experimental:RD` | `ladder-quasi-experimental.md` (RD section) | Local polynomial (Calonico-Cattaneo-Titiunik) | McCrary density test; bandwidth robustness (CCT, IK, ½×CCT, 2×CCT); placebo cutoff; donut-hole | Focal = CCT-optimal bandwidth, order-1 local linear |
| `quasi-experimental:IV` | `ladder-quasi-experimental.md` (IV section) | 2SLS + reduced form | First-stage F (≥10, report AR CI when F<104); over-id (Sargan/Hansen); LATE characterization | Focal = 2SLS; OLS reported for comparison only |
| `quasi-experimental:synth` | `ladder-quasi-experimental.md` (synth section) | Synthetic control weights | In-time placebo, in-space placebo, leave-one-out, permutation p-value | Focal = synth gap; RMSPE ratio drives inference |
| `decomposition:Oaxaca` | `ladder-decomposition.md` (Oaxaca section) | Oaxaca-Blinder threefold decomposition | Alt reference group; pooled vs. group-specific coefficients; bootstrap SE | Focal = endowments vs. coefficients split (not a rung) |
| `decomposition:Kitagawa` | `ladder-decomposition.md` (Kitagawa section) | Kitagawa rate decomposition | Bootstrap SE; alt standardization base | Focal = composition vs. rate component |
| `decomposition:KHB` | `ladder-decomposition.md` (KHB section) | KHB rescaled-logit mediation | Alt mediator ordering (if theory permits); direct vs. indirect share | Focal = % mediated |
| `decomposition:APC` | `ladder-decomposition.md` (APC section) | IE + HAPC triangulation (Fosse-Winship rule) | Fosse-Winship bounds; IE vs. HAPC overlay; reference-point sensitivity | Focal = period vs. cohort dominance claim (triangulated) |
| `predictive-ML` | `ladder-predictive-ml.md` | Train/test split + CV + held-out metric | Calibration plot; baseline comparison; ablation; subgroup metrics | Focal = held-out test metric; no ladder |

**Sub-type notation:** `quasi-experimental:DiD`, `decomposition:Oaxaca`, etc. The router reads everything after the first `:` as the sub-type selector.

---

## How callers use this table

```bash
# Phase 5 consumes this file like so:
DESIGN_TYPE=$(grep "^Design Type:" "${PROJ}/logs/project-state.md" | tail -1 | sed 's/^Design Type:[[:space:]]*//')
[ -z "$DESIGN_TYPE" ] && { DESIGN_TYPE=observational-descriptive; echo "WARN: Design Type not set, defaulting to observational-descriptive"; }

DT_MAIN="${DESIGN_TYPE%%:*}"    # everything before the first colon
DT_SUB="${DESIGN_TYPE#*:}"      # everything after (== $DT_MAIN if no colon)
[ "$DT_SUB" = "$DT_MAIN" ] && DT_SUB=""

LADDER_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-analyze/references"
case "$DT_MAIN" in
  observational-descriptive)      LADDER_FILE="${LADDER_DIR}/ladder-observational-descriptive.md" ;;
  observational-causal-with-DAG)  LADDER_FILE="${LADDER_DIR}/ladder-observational-causal.md" ;;
  RCT)                            LADDER_FILE="${LADDER_DIR}/ladder-rct.md" ;;
  quasi-experimental)             LADDER_FILE="${LADDER_DIR}/ladder-quasi-experimental.md" ;;
  decomposition)                  LADDER_FILE="${LADDER_DIR}/ladder-decomposition.md" ;;
  predictive-ML)                  LADDER_FILE="${LADDER_DIR}/ladder-predictive-ml.md" ;;
  *)                              echo "ERROR: unknown DESIGN_TYPE '$DESIGN_TYPE'"; exit 1 ;;
esac

echo "=== Loading ladder: $LADDER_FILE (sub-type: ${DT_SUB:-none}) ==="
cat "$LADDER_FILE"
```

Every Phase 5 analysis script (`${PROJ}/scripts/04-main-models.R`, etc.) MUST emit a header comment naming the ladder file it was built from:

```r
# Ladder: ladder-decomposition.md (sub-type: Oaxaca)
# Design Type: decomposition:Oaxaca (from ${PROJ}/logs/project-state.md)
```

The drift-gate A11 in `scholar-auto-improve/references/diagnostic-patterns.md` checks this header against the declared `Design Type`.

---

## Spec Registry contract

Every branch populates `${PROJ}/tables/spec-registry.csv` with one row per specification that appears in any manuscript table. Schema:

```csv
spec_id,description,estimator,se_type,sample,ladder_file,ladder_section,design_type,notes
```

- `spec_id` — short slug, e.g., `descriptive:M1`, `DAG:focal`, `RCT:ITT-unadjusted`, `DiD:event-study`, `Oaxaca:threefold-pooled`, `ML:holdout-v1`.
- The hypothesis-to-spec mapping (when assembled by `scholar-analyze` or an upstream orchestrator) references `spec_id`, not `M1`/`M2`/`M3`.

---

## Fallback behavior

| Condition | Behavior |
|---|---|
| `Design Type:` line missing in project-state.md | Default to `observational-descriptive`; emit WARN at analyze entry; still produce spec-registry.csv |
| `Design Type:` present but unrecognized | Hard ERROR — print valid values and abort |
| `observational-causal-with-DAG` declared but `${PROJ}/design/identification-strategy.json` missing | Hard ERROR — print "re-run `/scholar-causal` before `/scholar-analyze`" and abort |
| Sub-type missing (e.g., bare `quasi-experimental`) | Hard ERROR — sub-type required for this main type |
| Sub-type missing for `decomposition` | Default sub-type = `Oaxaca` with WARN |

---

## Maintenance invariants

- **All ladder files MUST exist** at the paths named in the routing table.
- **The router table is the only dispatch mechanism.** Ladder files never `cat` each other; they declare their own specifications.
- **New DESIGN_TYPE values** require: (1) a new row in this table, (2) a new `ladder-*.md` file, (3) an entry in the scholar-design inference block (scholar-design/SKILL.md Save Output step), (4) a test project.
