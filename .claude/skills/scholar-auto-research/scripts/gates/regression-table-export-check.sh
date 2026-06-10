#!/usr/bin/env bash
# regression-table-export-check.sh — Phase 5 / Phase 8 gate (audit 2026-05-03).
#
# Problem this gate solves
# ------------------------
# Both scholar-full-paper Phase 5 and scholar-auto-research Phase 8 contracts
# require regression results to be exported as publication-quality tables in
# HTML + TeX + docx (and CSV for replication), produced by `modelsummary` or
# an equivalent engine. The contract is enforced only at the *declaration*
# level: the auto-research verifier checks that `analysis_stack.table_engine
# == "modelsummary"` and that `modelsummary` appears in `packages_used`. It
# does NOT check that the analysis scripts actually CALL `modelsummary()` or
# that any rich-format file lands in `tables/`.
#
# Result: projects can ship `tables/` with only `*-registry.csv` and
# coefficient-frame CSVs and no rendered tables. Typical failure shapes:
#   - a tables/ dir with several .csv files but 0 .html / .tex / .docx
#   - a tables/ dir with focal-coef / results-registry / spec-registry CSVs
#       only, 0 .html / .tex / .docx, and `library(modelsummary)` absent
#       from the focal-models script entirely
# Downstream Phase 11 manuscript assembly cannot embed publication-quality
# regression tables; the LLM either hand-crafts a markdown table from the
# CSV or skips it.
#
# Fallback policy (the part missing from the original contract)
# -------------------------------------------------------------
# `modelsummary` does not cover every model class. When a script uses a
# model that `modelsummary` cannot tidy (e.g., custom S4 classes, certain
# survey designs, hand-fit Bayesian draws, `lavaan` SEMs in some modes),
# the writer may fall back to one of:
#   - stargazer        — robust for lm/glm/lme4
#   - texreg / htmlreg — broad coverage; supports lavaan, plm, custom S4
#   - huxtable::huxreg — modern alternative to stargazer
#   - gtsummary::tbl_regression + gt::gtsave
#   - fixest::etable   — for fixest models
#   - kableExtra::kable on a hand-built coefficient frame, written to .html
#     or .tex (last-resort escape hatch for unsupported models)
# This gate accepts any of these. The required artifact is at least one
# rich-format file (`.html` / `.tex` / `.docx`) inside `tables/`.
#
# What this gate does
# -------------------
# 1. Detect project layout (full-paper vs auto-research).
# 2. Detect whether quantitative regression work was performed by checking
#    for canonical artifacts: tables/results-registry.csv with focal rows,
#    tables/focal-coefs.csv, tables/model-coefficients.csv, OR a regression
#    fit call (feols/lm/glm/svyglm/polr/glmer) in any analysis R script.
# 3. If no quant work, exit GREEN (nothing to enforce).
# 4. Count rich-format files in tables/: *.html, *.tex, *.docx. Excludes
#    spec/results/figure registries (those are metadata, not regression
#    tables) by extension — registries are CSV by contract.
# 5. Inspect R scripts for any supported export-engine call.
# 6. Emit STATUS:
#    - GREEN  — ≥1 rich-format file in tables/
#    - YELLOW — supported engine called but zero rich-format files
#               (engine output likely failed silently — investigate)
#    - RED    — no rich-format files AND no supported engine call
#               (the canonical "wrote CSV only" bug)
#
# Usage
# -----
#   regression-table-export-check.sh <project_dir>
#
# Exit codes
# ----------
#   0 GREEN  — rich-format regression tables present (or no quant work)
#   1 RED    — no rich-format tables and no supported engine ever called
#   2 YELLOW — engine called but no artifact, missing tools, or usage err

set -uo pipefail
export LC_ALL=C

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=usage"
  echo "WARN: usage: regression-table-export-check.sh <project_dir>" >&2
  exit 2
fi

TABLES_DIR="${PROJ}/tables"
if [ ! -d "$TABLES_DIR" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=tables_dir_missing"
  echo "WARN: ${TABLES_DIR} does not exist; analysis has not produced tables yet." >&2
  exit 2
fi

# ── Detect project layout: where do analysis R scripts live? ───────────
# scholar-full-paper writes to ${PROJ}/scripts/p5-*.R (and other p5-*).
# scholar-auto-research writes to ${PROJ}/analysis/scripts/*.R.
# Some projects use both (e.g., when a Phase 5 retry adds scripts to
# analysis/scripts/). Collect from both.
SCRIPT_PATHS=()
if [ -d "${PROJ}/scripts" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] && SCRIPT_PATHS+=("$path")
  done < <(find "${PROJ}/scripts" -maxdepth 2 -type f -name '*.R' 2>/dev/null)
fi
if [ -d "${PROJ}/analysis/scripts" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] && SCRIPT_PATHS+=("$path")
  done < <(find "${PROJ}/analysis/scripts" -maxdepth 2 -type f -name '*.R' 2>/dev/null)
fi

if [ ${#SCRIPT_PATHS[@]} -eq 0 ]; then
  echo "STATUS=GREEN"
  echo "REASON=no_r_scripts"
  echo "DETAIL: no .R analysis scripts found; nothing to enforce."
  exit 0
fi

# ── Detect whether quantitative regression work was performed ──────────
QUANT_DETECTED=0
QUANT_EVIDENCE=""

if [ -f "${TABLES_DIR}/results-registry.csv" ]; then
  if [ "$(wc -l < "${TABLES_DIR}/results-registry.csv" 2>/dev/null || echo 0)" -gt 1 ]; then
    QUANT_DETECTED=1
    QUANT_EVIDENCE="results-registry.csv has rows"
  fi
fi
if [ -f "${TABLES_DIR}/focal-coefs.csv" ] || [ -f "${TABLES_DIR}/model-coefficients.csv" ]; then
  QUANT_DETECTED=1
  if [ -z "$QUANT_EVIDENCE" ]; then
    QUANT_EVIDENCE="focal-coefs.csv or model-coefficients.csv present"
  fi
fi

# Fall back to grepping for regression fit calls in scripts (case-insensitive)
if [ "$QUANT_DETECTED" -eq 0 ]; then
  REGEX='(^|[^a-zA-Z._])(feols|lm|glm|svyglm|polr|glmer|lmer|coxph|survreg|brm|stan_glm|gamlss)\s*\('
  for script in "${SCRIPT_PATHS[@]}"; do
    if grep -E -q "$REGEX" "$script" 2>/dev/null; then
      QUANT_DETECTED=1
      QUANT_EVIDENCE="regression fit call detected in $(basename "$script")"
      break
    fi
  done
fi

if [ "$QUANT_DETECTED" -eq 0 ]; then
  echo "STATUS=GREEN"
  echo "REASON=no_quant_work"
  echo "DETAIL: no regression artifacts or fit calls; nothing to enforce."
  exit 0
fi

# ── Count rich-format files in tables/ ─────────────────────────────────
# Only count top-level files; sub-directories (e.g. tables/raw/) are
# producer-internal and not the publication artifacts.
RICH_HTML=0; RICH_TEX=0; RICH_DOCX=0
RICH_FILES=()
while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in
    *.html) RICH_HTML=$((RICH_HTML + 1)); RICH_FILES+=("$(basename "$path")") ;;
    *.tex)  RICH_TEX=$((RICH_TEX + 1));   RICH_FILES+=("$(basename "$path")") ;;
    *.docx) RICH_DOCX=$((RICH_DOCX + 1)); RICH_FILES+=("$(basename "$path")") ;;
  esac
done < <(find "$TABLES_DIR" -maxdepth 1 -type f \( -name '*.html' -o -name '*.tex' -o -name '*.docx' \) 2>/dev/null)

RICH_TOTAL=$((RICH_HTML + RICH_TEX + RICH_DOCX))

# ── Inspect R scripts for any supported export-engine call ─────────────
# Each pattern matches a function call (followed by '('), which is more
# robust than matching `library(...)` since some writers load the package
# but never call it.
#
# Note: parallel arrays (not associative) for bash 3.2 compatibility — macOS
# ships /bin/bash 3.2 and `declare -A` fails there. Order of names and
# patterns must match index-for-index.
ENGINE_NAMES=(
  "modelsummary"
  "stargazer"
  "texreg"
  "huxtable"
  "gtsummary"
  "gt"
  "fixest_etable"
  "kableExtra"
)
ENGINE_PATTERNS=(
  '(^|[^a-zA-Z._])(modelsummary|msummary)\s*\('
  '(^|[^a-zA-Z._])stargazer\s*\('
  '(^|[^a-zA-Z._])(texreg|htmlreg|screenreg)\s*\('
  '(^|[^a-zA-Z._])(huxreg|hux_to_(html|latex|docx)|quick_html|quick_pdf|quick_docx)\s*\('
  '(^|[^a-zA-Z._])(tbl_regression|tbl_summary)\s*\('
  '(^|[^a-zA-Z._])(gt|gtsave)\s*\('
  '(^|[^a-zA-Z._])etable\s*\('
  '(^|[^a-zA-Z._])(kable|kbl)\s*\('
)

# Descriptive-only engines:
# `modelsummary::datasummary_df()` and `datasummary()` produce display
# tables from data frames, NOT regression tables from fitted model objects.
# A `tables/table-main-regression.*` file produced solely by these engines
# is a focal extract or hand-built summary, not a publication regression
# table — even though the `modelsummary` PACKAGE is loaded.
DESCRIPTIVE_ONLY_ENGINE_PATTERNS=(
  '(^|[^a-zA-Z._])datasummary(_df|_skim|_correlation|_balance)?\s*\('
  '(^|[^a-zA-Z._])tbl_summary\s*\('
)

DESCRIPTIVE_ONLY_CALLED=0
for pattern in "${DESCRIPTIVE_ONLY_ENGINE_PATTERNS[@]}"; do
  for script in "${SCRIPT_PATHS[@]}"; do
    if grep -E -q "$pattern" "$script" 2>/dev/null; then
      DESCRIPTIVE_ONLY_CALLED=1
      break 2
    fi
  done
done

ENGINES_CALLED=()
i=0
while [ $i -lt ${#ENGINE_NAMES[@]} ]; do
  engine="${ENGINE_NAMES[$i]}"
  pattern="${ENGINE_PATTERNS[$i]}"
  for script in "${SCRIPT_PATHS[@]}"; do
    if grep -E -q "$pattern" "$script" 2>/dev/null; then
      ENGINES_CALLED+=("$engine")
      break
    fi
  done
  i=$((i + 1))
done

# Deduplicate (already deduped per-engine, but stable-sort).
# Guard the array expansion: under `set -u`, "${ENGINES_CALLED[@]}" is an
# unbound-variable error when the array is empty (bash 3.2 + 4.x).
if [ "${#ENGINES_CALLED[@]}" -gt 0 ]; then
  ENGINES_LIST=$(printf '%s\n' "${ENGINES_CALLED[@]}" | sort -u | paste -sd, -)
else
  ENGINES_LIST=""
fi

# ── Emit STATUS + exit ─────────────────────────────────────────────────
echo "PROJECT=${PROJ}"
echo "QUANT_EVIDENCE=${QUANT_EVIDENCE}"
echo "RICH_HTML=${RICH_HTML}"
echo "RICH_TEX=${RICH_TEX}"
echo "RICH_DOCX=${RICH_DOCX}"
echo "ENGINES_CALLED=${ENGINES_LIST}"

# ── Regression-engine purity (audit 2026-05-06) ────────────────────────
# If a file named like a main regression table exists in tables/, AND no
# regression-grade engine was called, AND a descriptive-only engine WAS
# called, the regression table was produced from a hand-built data frame
# rather than from fitted model objects. That is a focal extract, not a
# publication regression table — RED.
MAIN_REG_FILES=()
while IFS= read -r path; do
  [ -z "$path" ] && continue
  MAIN_REG_FILES+=("$(basename "$path")")
done < <(find "$TABLES_DIR" -maxdepth 1 -type f \
           \( -iname 'table-main-regression.*' -o -iname 'table-regression.*' \
              -o -iname 'regression-table.*' -o -iname 'main-regression-table.*' \) 2>/dev/null)

REGRESSION_ENGINE_CALLED=0
for engine in "${ENGINES_CALLED[@]:-}"; do
  case "$engine" in
    modelsummary|stargazer|texreg|huxtable|fixest_etable) REGRESSION_ENGINE_CALLED=1 ;;
    gtsummary)
      for script in "${SCRIPT_PATHS[@]}"; do
        if grep -E -q '(^|[^a-zA-Z._])tbl_regression\s*\(' "$script" 2>/dev/null; then
          REGRESSION_ENGINE_CALLED=1; break
        fi
      done
      ;;
  esac
done

if [ "${#MAIN_REG_FILES[@]}" -gt 0 ] \
     && [ "$REGRESSION_ENGINE_CALLED" -eq 0 ] \
     && [ "$DESCRIPTIVE_ONLY_CALLED" -eq 1 ]; then
  echo "STATUS=RED"
  echo "REASON=regression_table_from_descriptive_engine"
  echo "DETAIL: ${MAIN_REG_FILES[*]}"
  cat >&2 <<EOF
FAIL: regression tables export — a main regression table file is present
(${MAIN_REG_FILES[*]}), but no regression-grade engine (modelsummary(),
msummary(), stargazer(), texreg(), huxreg(), tbl_regression(), etable())
was called by any analysis script. Only a descriptive-only engine
(datasummary_df / datasummary / tbl_summary) was called. A regression
table built from a hand-constructed data frame is a focal extract, not a
publication regression table; the engine must consume fitted model
objects to produce predictor rows, standard-error layout, and a goodness-
of-fit block.
EOF
  exit 1
fi

if [ "$RICH_TOTAL" -ge 1 ]; then
  echo "STATUS=GREEN"
  echo "REASON=rich_format_present"
  echo "DETAIL: ${RICH_TOTAL} rich-format file(s) in tables/: ${RICH_FILES[*]}"
  exit 0
fi

if [ -n "$ENGINES_LIST" ]; then
  echo "STATUS=YELLOW"
  echo "REASON=engine_called_no_artifact"
  cat >&2 <<EOF
WARN: regression tables export — supported engine(s) (${ENGINES_LIST}) were
called in analysis scripts, but tables/ contains zero .html / .tex / .docx
files. The engine call probably failed silently (wrong output path, missing
package dependency, or incompatible model class). Inspect script logs and
re-run; if the engine cannot tidy the model, declare a fallback engine in
analysis_stack.table_engine_fallback.
EOF
  exit 2
fi

echo "STATUS=RED"
echo "REASON=no_rich_format_no_engine"
cat >&2 <<EOF
FAIL: regression tables export — analysis produced regression artifacts
(${QUANT_EVIDENCE}), but tables/ contains zero .html / .tex / .docx files
AND no supported export engine (modelsummary, stargazer, texreg, huxtable,
gtsummary, gt, fixest::etable, kableExtra) is called by any R script. The
contract requires regression tables to be exported as publication-quality
HTML/TeX/docx, not just CSV. Add a modelsummary() call (or a justified
fallback engine like stargazer for unsupported model classes) to the
analysis script and re-run.
EOF
exit 1
