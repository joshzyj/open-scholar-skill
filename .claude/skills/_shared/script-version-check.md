# Script Version Control Protocol

Every `/scholar-*` skill that saves analysis scripts MUST check for existing scripts and increment a version suffix to prevent overwriting previous work. Previous script versions are never expendable — they document the evolution of analytic decisions.

**This applies to:** `scholar-analyze`, `scholar-compute`, `scholar-eda`, `scholar-ling`, and any skill that saves `.R`, `.py`, or `.do` scripts to `${OUTPUT_ROOT}/scripts/`.

---

## Critical: How to Use with the Write Tool

**Shell variables do NOT persist between Bash tool calls.** You cannot run the version check in one Bash call and use `$SCRIPT_PATH` in a later Write tool call. Instead:

1. **Run the Bash block below** — it prints `SCRIPT_PATH=...` to stdout
2. **Read the printed path** from the Bash output
3. **Use that exact path** as the `file_path` parameter in the Write tool call

**Do NOT skip this step and hardcode a path from the filename template.** The template (e.g., `04-main-models.R`) shows the naming pattern, not the actual path to use.

---

## Script Version Check

Run this via the Bash tool BEFORE every Write tool call that saves a script:

```bash
# MANDATORY: Replace SCRIPT_NAME and EXT with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SCRIPT_NAME="04-main-models"  # e.g., 04-main-models, E01-load-data, L07-context-embeddings
EXT="R"                        # R, py, do, jl
SCRIPT_DIR="${OUTPUT_ROOT}/scripts"
mkdir -p "$SCRIPT_DIR"

SCRIPT_BASE="${SCRIPT_DIR}/${SCRIPT_NAME}"

if [ -f "${SCRIPT_BASE}.${EXT}" ]; then
  V=2
  while [ -f "${SCRIPT_BASE}-v${V}.${EXT}" ]; do
    V=$((V + 1))
  done
  SCRIPT_BASE="${SCRIPT_BASE}-v${V}"
fi

# USE THIS PATH in the Write tool call
echo "SCRIPT_PATH=${SCRIPT_BASE}.${EXT}"
```

---

## Rules

1. **NEVER overwrite an existing script.** Always increment the version suffix (`-v2`, `-v3`, etc.).
2. **The first version has no suffix** — `04-main-models.R`. The second is `04-main-models-v2.R`, third is `04-main-models-v3.R`, etc.
3. **Paired files share the same version** — if `04-main-models-v2.R` exists, the Stata parallel should be `04-main-models-v2.do`.
4. **Re-derive `$SCRIPT_BASE` in every new Bash call** — shell state resets between calls.
5. **Update the script-index.md** to reflect the versioned filename (e.g., `04-main-models-v2.R`), not the base template name.
6. **Update the coding-decisions-log.md** with the versioned filename and a note about what changed from the prior version.
7. **The standard script header MUST include a Version line:**

```r
# ============================================================
# Script: [SCRIPT_NAME]-[version].R
# Version: [v1 | v2 | v3 ...]
# Purpose: [one-line description]
# Input:   [data file or prior script output]
# Output:  [tables, figures, or objects produced]
# Date:    [YYYY-MM-DD]
# Seed:    set.seed(42)
# Changes: [if v2+, one-line summary of what changed from prior version]
# Notes:   [SE type, sample restrictions, key parameters]
# ============================================================
```

## Example

```
First run:   04-main-models.R    (original)
Second run:  04-main-models-v2.R (added interaction term)
Third run:   04-main-models-v3.R (switched to clustered SEs)
```

## Script Index Update

When saving a versioned script, update `script-index.md` to show the latest version and archive previous:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
# Append the new version row
echo "| 4 | 04-main-models-v2.R | Main regression ladder — added X*Z interaction | data/analysis_data.rds | ${OUTPUT_ROOT}/tables/table2-regression.html | Table 2 |" >> "${OUTPUT_ROOT}/scripts/script-index.md"
```

## Coding Decisions Log Update

When saving a versioned script, log what changed:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
echo "| $(date '+%Y-%m-%d %H:%M') | A3 | Revised model: added X*Z interaction | Prior: main effects only (v1) | Theory predicts moderation; reviewer requested | X, Z, X*Z | 04-main-models-v2.R |" >> "${OUTPUT_ROOT}/scripts/coding-decisions-log.md"
```
