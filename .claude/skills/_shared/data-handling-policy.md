# Data Handling Policy — Single Source of Truth

**Referenced by:** `scholar-analyze`, `scholar-eda`, `scholar-compute`, `scholar-ling`, `scholar-qual`, `scholar-brainstorm` (DATA mode), `scholar-causal`, and any other skill that receives a user-supplied data file.

**Purpose.** Prevent raw row-level data from entering the Anthropic API unless the user has made an informed, explicit decision to allow it. This file defines the mandatory Step 0 safety gate, the `SAFETY_STATUS` state machine, and the `LOCAL_MODE` execution rules that replace direct `Read` of data files.

---

## 0. The core rule

> **Never use the `Read` tool on a user-supplied data file until Step 0 has run and `SAFETY_STATUS` has been set to a value that explicitly permits it.**

"Data file" means any file that may contain row-level observations, transcripts, corpora, speech, image annotations, or other research material: `.csv`, `.tsv`, `.dta`, `.sav`, `.rds`, `.RData`, `.parquet`, `.feather`, `.xlsx`, `.xls`, `.json`, `.jsonl`, `.db`, `.sqlite`, `.txt`, `.rtf`, `.docx`, `.wav`, `.mp3`, `.flac`, `.mp4`, corpus archives, and directories of same.

Small *metadata* files (codebooks, questionnaires, data dictionaries, schema descriptions) are **not** covered by this rule and may be read with `Read` as usual, because they describe the data rather than contain it.

---

## 1. Step 0 — Mandatory safety gate

Every skill that accepts a data-file argument MUST run this block before any other step that could load, sample, or summarize the data. If multiple files are provided, run the gate once per file in a single Bash call.

```bash
# ── Step 0: Data Safety Gate ──────────────────────────────────────────
# Runs LOCALLY. No file content is transmitted to the API.
# Exit codes from safety-scan.sh: 0=GREEN, 1=RED, 2=YELLOW
SAFETY_STATUS=""           # one of: CLEARED | LOCAL_MODE | ANONYMIZED | OVERRIDE | HALTED
SAFETY_FILES=()            # track every file that passed through the gate
SAFETY_LEVELS=()           # parallel array of per-file levels

for FILE in [DATA_FILE_PATHS]; do
  if [ ! -f "$FILE" ]; then
    echo "ERROR: file not found: $FILE" >&2
    continue
  fi
  GATE_SCRIPT="${SCHOLAR_SKILL_DIR:-.}/scripts/gates/safety-scan.sh"
  if [ ! -x "$GATE_SCRIPT" ] && [ ! -f "$GATE_SCRIPT" ]; then
    echo "FATAL: safety-scan.sh not found at $GATE_SCRIPT" >&2
    exit 1
  fi
  bash "$GATE_SCRIPT" "$FILE"
  LEVEL=$?     # 0=GREEN 1=RED 2=YELLOW
  SAFETY_FILES+=("$FILE")
  SAFETY_LEVELS+=("$LEVEL")
  echo "gate: $FILE → exit=$LEVEL"
done
```

Report a short table back to the user:

```
┌──────────────────────────────────────────────────────────┐
│ File                    │ Level   │ Action                │
├──────────────────────────────────────────────────────────┤
│ data/survey.csv         │ YELLOW  │ Awaiting user choice  │
│ data/interviews.txt     │ RED     │ Awaiting user choice  │
└──────────────────────────────────────────────────────────┘
```

Then set `SAFETY_STATUS` using the state machine below. **Do not skip this block.** If the skill is invoked inside an upstream orchestrator that has already produced a `SAFETY_STATUS`, read that state from `PROJECT_STATE` instead of re-running — never downgrade an existing status.

---

## 2. The SAFETY_STATUS state machine

| Gate result | User choice | SAFETY_STATUS | What Claude is allowed to do |
|-------------|-------------|---------------|------------------------------|
| 🟢 GREEN (exit 0) | auto | `CLEARED` | May `Read` the file and use in-context data frames. |
| 🟡 YELLOW (exit 2) | `[Y] PROCEED` | `CLEARED` | May `Read` the file. User has confirmed cloud processing is OK. |
| 🟡 YELLOW | `[C] LOCAL MODE` | `LOCAL_MODE` | Bash-only. See Section 3. |
| 🟡 YELLOW | `[B] ANONYMIZE` | `ANONYMIZED` (after re-scan passes GREEN) | Treat the anonymized file as CLEARED. Never read the key/original. |
| 🔴 RED (exit 1) | `[C] LOCAL MODE` | `LOCAL_MODE` | **Default for RED.** Bash-only. See Section 3. |
| 🔴 RED | `[B] ANONYMIZE` | `ANONYMIZED` | Same as above — operate on the anonymized copy. |
| 🔴 RED | `[D] OVERRIDE` | `OVERRIDE` | User has certified this is a false positive. Log verbatim rationale to the process log, then treat as `CLEARED`. |
| 🔴 RED | `[A] HALT` | `HALTED` | Stop the skill entirely. Do not continue. |
| any | not yet made | `NEEDS_REVIEW:<level>` | **Block.** File has been ingested by `scholar-init` but the user has not yet reviewed it. Run `/scholar-init review` to resolve. See §2a. |

**Defaults when the user has not yet chosen:**

- 🟢 GREEN → auto-advance to `CLEARED`, no prompt needed.
- 🟡 YELLOW → prompt with `[Y] PROCEED | [C] LOCAL MODE | [B] ANONYMIZE | [A] HALT`, default suggestion `[C]`.
- 🔴 RED → prompt with `[C] LOCAL MODE | [B] ANONYMIZE | [D] OVERRIDE | [A] HALT`, default suggestion `[C]`. **Never auto-select `[D]`.**

**Wait for user response before continuing.** Do not bundle the gate with downstream steps in the same assistant turn when the gate is not GREEN.

### Binary-format YELLOW promotion

`safety-scan.sh` is a text-grep scanner. On binary / compressed formats (`.xlsx`, `.xls`, `.ods`, `.parquet`, `.feather`, `.arrow`, `.dta`, `.sav`, `.rds`, `.rdata`, `.sqlite`, `.db`, `.h5`, `.hdf5`, `.mat`, `.pkl`, `.pdf`, `.docx`, `.pptx`, and media formats), the regex patterns never match the compressed bytes — an xlsx containing an SSN column returns "no patterns detected" to a naive text scanner. That would be fail-open.

The scanner therefore **promotes any binary format to YELLOW unconditionally**, even when the regex pass returns clean:

1. If Presidio ran and returned `GREEN` on a binary extension → promote to `YELLOW`.
2. If the regex fallback returned `RED` or `YELLOW` on ancillary text (filename, adjacent manifest), honor that.
3. Otherwise the binary short-circuit forces `YELLOW`.

A YELLOW result on a binary file means the user must choose `LOCAL_MODE` (analyze via `Rscript`/`python3` that reads the file natively), `ANONYMIZE`, `OVERRIDE` (with rationale), or `HALT`. The guard refuses `CLEARED` auto-advancement for binary formats, because "no text patterns detected" is not evidence of "no sensitive content" when the scanner cannot read the content.

---

## 2a. Project directory convention and the NEEDS_REVIEW status

When a user starts a new research project with `/scholar-init` (or `bash scripts/init-project.sh`), the initializer creates a standardized directory and writes `.claude/safety-status.json` with an entry per ingested file. This sidecar is the source of truth for the PreToolUse hook (`scripts/gates/pretooluse-data-guard.sh`).

### Standard project layout

```
<project-slug>/
├── README.md                ← auto-generated, teaches the user the layout
├── .gitignore               ← excludes data/, .claude/safety-status.json, output/, logs/
├── .claude/
│   └── safety-status.json   ← per-file SAFETY_STATUS decisions
├── data/
│   ├── raw/                 ← original files, immutable after init
│   ├── interim/             ← cleaned/subsetted (scripts write here)
│   └── processed/           ← analytic datasets used by models
├── materials/               ← codebooks, questionnaires, protocols
├── output/
│   └── <slug>/              ← scholar-init populates this
└── logs/
    └── init-report.md       ← permanent ingest record + OVERRIDE rationales
```

The PreToolUse hook's path classifier is aligned with this layout:

- `data/raw/*`, `data/interim/*`, `data/processed/*` → data extensions are inspected by `safety-scan.sh`; image extensions are **blocked** because grep can't inspect pixels.
- `materials/*` → codebooks and protocols. Usually safe to `Read`, but still scanned.
- `output/<slug>/figures/*`, `output/<slug>/tables/*` → analytical outputs, image extensions allowed.
- Anywhere else → default pass-through for screenshots, icons, UI docs.

### The NEEDS_REVIEW status

When `scholar-init` ingests a new file:

- 🟢 GREEN scan → written as `CLEARED` in `safety-status.json`. Claude can `Read` it immediately.
- 🟡 YELLOW scan → written as `NEEDS_REVIEW:YELLOW`. The hook **blocks** until the user runs `/scholar-init review` and picks CLEARED / LOCAL_MODE / ANONYMIZED / HALTED.
- 🔴 RED scan → written as `NEEDS_REVIEW:RED`. The hook blocks; the user can upgrade to LOCAL_MODE, ANONYMIZED, OVERRIDE, or HALTED — but not plain CLEARED without a typed rationale logged to `logs/init-report.md`.

`NEEDS_REVIEW` is a **pending** state: the scanner has run, but the human has not yet made a decision. It exists specifically so that the init script can pre-populate the sidecar non-destructively: no data reaches Claude until every file has an explicit status.

### Incremental ingestion

If the user drops a new file into `data/raw/` after init, the PreToolUse hook will (a) find no entry in the sidecar, (b) run `safety-scan.sh` on demand, and (c) block with the usual YELLOW/RED refusal message. The user should then either:

1. Run `/scholar-init add <path>` to walk through the single-file scan + decision, OR
2. Manually `bash scripts/gates/safety-scan.sh <path>` and add the result to `.claude/safety-status.json`.

The init script's `--force` flag rebuilds the whole sidecar from scratch and will **overwrite** prior OVERRIDE decisions — use it only on fresh projects.

---

## 3. LOCAL_MODE — the Bash-only execution contract

When `SAFETY_STATUS=LOCAL_MODE`, the following rules apply for the remainder of the skill and for any sub-skill invoked afterward, until the user explicitly ends the session or re-invokes the gate on a different file:

1. **Never call the `Read` tool on the data file.** Not for previews, not for `head()`-style checks, not for "just this once."
2. **All data operations go through a single `Rscript -e "..."` or `python -c "..."` Bash call** that loads the data, runs the analysis, and prints only aggregated output. One long heredoc is preferred over many short calls.
3. **Allowed output** (safe to print to stdout — it enters Claude's context):
   - Dimensions: `nrow`, `ncol`, number of unique values
   - Variable names and classes (no values)
   - Missingness percentages per column
   - `summary()` / `skimr::skim()` output (five-number summaries)
   - Coefficients, standard errors, test statistics, p-values
   - Model fit indices, AIC/BIC
   - Counts per category (as long as the smallest cell is above a safe threshold; see rule 6)
4. **Forbidden output** (must not be printed):
   - `head(df)`, `print(df)`, `tail(df)`, `View(df)`, `df[1:5, ]`
   - Any row-level string or free-text column
   - `df %>% slice(...)`, `df %>% sample_n(...)`
   - Coordinates, addresses, names, IDs
   - Any `cat(paste(df$col, collapse=...))` pattern
5. **Scripts are saved to disk** under `output/[slug]/scripts/` exactly as in CLEARED mode. The analysis script is the artifact — the data never leaves the user's machine, but the code does.
6. **Small-cell suppression.** When reporting crosstabs or group counts, suppress any cell with `n < 10` (replace with `<10`). This prevents re-identification through cell-size leakage when the underlying file is sensitive.
7. **Figures.** Generate figures with R/Python as usual, save to `output/[slug]/figures/`, but do NOT embed them in the conversation when the underlying data is sensitive — just report that the file was written. Image contents sent back through the conversation are equivalent to `Read`.
8. **Sub-skill propagation.** When a LOCAL_MODE skill invokes another skill (e.g., `scholar-analyze` → `scholar-causal`), it MUST pass `SAFETY_STATUS=LOCAL_MODE` forward so the downstream skill inherits the constraint.
9. **Intermediate data files.** When an R/Python script processes LOCAL_MODE data and needs to save an intermediate dataset for reuse by downstream scripts (e.g., a cleaned analytic sample), the file MUST be saved to `data/interim/` or `data/processed/` — NEVER to `output/`, `scripts/`, or the project root. After saving, auto-register the file in `.claude/safety-status.json` with `LOCAL_MODE` status so the PreToolUse hook blocks `Read` on it. Use this bash block immediately after the Rscript call:
   ```bash
   # Auto-register derived data file in safety sidecar (inherit LOCAL_MODE from source)
   DERIVED_FILE="data/interim/data_analytic.rds"  # adjust path
   if [ -f "$DERIVED_FILE" ] && [ -f ".claude/safety-status.json" ]; then
     ABS_PATH="$(cd "$(dirname "$DERIVED_FILE")" && pwd)/$(basename "$DERIVED_FILE")"
     jq --arg k "$ABS_PATH" --arg v "LOCAL_MODE" \
       '.[$k] = $v' .claude/safety-status.json > .claude/safety-status.json.new \
       && mv .claude/safety-status.json.new .claude/safety-status.json
     echo "Registered $DERIVED_FILE as LOCAL_MODE in safety sidecar"
   fi
   ```
   Downstream scripts then load from `data/interim/` (fast, ~1s) instead of re-reading the large raw file. Claude still cannot `Read` the intermediate file because the hook enforces LOCAL_MODE.

### 3a. LOCAL_MODE loader template (R)

Use this template as the opening block of any script that runs under LOCAL_MODE. Wrap the whole pipeline in a single `Rscript -e` Bash call; do not split across multiple calls.

```r
# ── LOCAL_MODE loader — summary-only, no row-level output ──
suppressPackageStartupMessages({
  library(tidyverse); library(haven); library(arrow); library(readxl); library(skimr)
})

load_data <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    csv     = readr::read_csv(path, show_col_types = FALSE),
    tsv     = readr::read_tsv(path, show_col_types = FALSE),
    dta     = haven::read_dta(path),
    sav     = haven::read_sav(path),
    rds     = readRDS(path),
    rdata   = { e <- new.env(); load(path, envir = e); as.list(e)[[1]] },
    xlsx    = readxl::read_excel(path),
    xls     = readxl::read_excel(path),
    parquet = arrow::read_parquet(path),
    feather = arrow::read_feather(path),
    stop("Unsupported extension: ", ext)
  )
}

df <- load_data("[DATA_FILE_PATH]")

# Safe summary output ONLY — nothing row-level
cat("N =", nrow(df), "\n")
cat("Variables =", ncol(df), "\n")
cat("Column names:\n", paste(names(df), collapse = ", "), "\n\n")
str(df, list.len = ncol(df), give.attr = FALSE)   # classes only, no values
# Do NOT call: head(df), print(df), View(df)
```

### 3b. LOCAL_MODE loader template (Python)

```python
# ── LOCAL_MODE loader — summary-only, no row-level output ──
import pandas as pd, os, sys
path = "[DATA_FILE_PATH]"
ext = os.path.splitext(path)[1].lower().lstrip(".")
loaders = {
    "csv":     pd.read_csv,
    "tsv":     lambda p: pd.read_csv(p, sep="\t"),
    "dta":     pd.read_stata,
    "sav":     lambda p: pd.read_spss(p),
    "xlsx":    pd.read_excel,
    "xls":     pd.read_excel,
    "parquet": pd.read_parquet,
    "feather": pd.read_feather,
    "json":    pd.read_json,
}
if ext not in loaders:
    sys.exit(f"Unsupported extension: {ext}")
df = loaders[ext](path)

print(f"N = {len(df)}")
print(f"Variables = {df.shape[1]}")
print("Columns:", ", ".join(df.columns))
print(df.dtypes)                 # classes only, no values
print(df.isna().mean().round(3)) # missingness per column
# Do NOT call: df.head(), print(df), df.sample()
```

### 3c. Allowed summary verbs (cheat sheet)

| Task | Allowed under LOCAL_MODE | Forbidden |
|------|--------------------------|-----------|
| Inspect structure | `str(df)`, `df.dtypes`, `names(df)` | `head(df)`, `df.head()` |
| Describe distributions | `summary(df)`, `skimr::skim(df)`, `df.describe()` | `print(df[1:10, ])` |
| Crosstab | `table(df$x, df$y)` (suppress n<10) | Pivoting raw IDs |
| Missingness | `colSums(is.na(df))`, `df.isna().sum()` | Listing which rows are missing |
| Regression | Full model output (coefs, SEs, p-values) | `augment(model)` without suppression |
| Preview | **Not allowed at all** | Every preview variant |

---

## 4. Qualitative data — additional rules

Qualitative data (interview transcripts, field notes, open-ended survey responses) carries additional risk because anonymization is hard to verify with pattern matching alone. For these files:

- `scholar-qual`'s anonymization gate (`anonymize-presidio.py`) is **mandatory** before any `Read`. LOCAL_MODE alone is not sufficient because qualitative analysis usually requires reading text, not just summarizing it.
- If the user declines anonymization, the only permitted path is `[A] HALT`. Do not offer `[D] OVERRIDE` for qualitative data.
- The pseudonym key produced by anonymization MUST be saved to a local path outside `output/` and MUST NEVER be read by Claude.

---

## 5. What still requires the Read tool

LOCAL_MODE applies to the *data file*. These ancillary files remain readable with `Read`:

- Codebooks, data dictionaries, questionnaires (`.pdf`, `.docx`, `.md`)
- Variable label exports (`haven::print_labels()` saved to a text file)
- Aggregated tables that the skill itself has produced and written to `output/tables/`
- The analysis scripts in `output/scripts/` (code is not data)
- The process log

If a user pastes a codebook excerpt inline, that text is safe — it is metadata, not data.

---

## 6. Audit trail

Every gate run, every user choice, and every `SAFETY_STATUS` transition must be appended to the skill's process log:

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
SKILL_NAME="[skill-name]"
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE=$(ls -t "${OUTPUT_ROOT}/logs/process-log-${SKILL_NAME}-${LOG_DATE}"*.md 2>/dev/null | head -1)
echo "| 0 | $(date +%H:%M:%S) | Safety Gate | file=[path] level=[GREEN/YELLOW/RED] choice=[Y/C/B/D/A] status=[...] | — | ✓ |" >> "$LOG_FILE"
```

When `SAFETY_STATUS=OVERRIDE` is selected, also append the user's rationale verbatim to the log. This is the audit record for an IRB protocol or a data use agreement review.

**OVERRIDE rationale requirements (enforced by `scholar-init`):**

- **Minimum length: 20 characters.** One-word answers like "ok", "n/a", "false positive" are rejected. The rationale must name the specific scanner finding and explain why it is a false positive (e.g., "The 'SSN' column is a synthetic participant ID generated via `paste0('P', 1:n)`, not a real Social Security Number — verified with PI Dr. Smith on 2026-04-09.").
- **Never accepted on qualitative data** — audio (`wav`/`mp3`/`flac`/`m4a`/`ogg`/`aac`/`aiff`), video (`mp4`/`mov`/`avi`/`mkv`/`webm`), or interview transcripts (`eaf`/`textgrid`/`trs`/`cha`/`praat`). Voiceprints are biometric PII and transcripts quote participants verbatim — there is no rationale that makes these "false positives." For qualitative data the only valid resolutions are `LOCAL_MODE`, `ANONYMIZED`, or `HALTED`. See §4.
- **Logged verbatim to `logs/init-report.md`** in the "Decision history" section under the file path and timestamp. The log is append-only and git-ignored by default (to keep rationales out of public repos), so local storage is the single source of truth.

## 7. Image path classification (reference)

The PreToolUse hook classifies image files (`jpg jpeg png tiff tif heic heif bmp webp gif`) by path segment rather than content, because the text-grep scanner cannot inspect pixels for faces, license plates, medical imagery, or identifying text.

**Raw-data path segments that trigger a block:**

Both the `*/segment/*` form (segment appears as a directory component with children) AND the bare `*/segment` form (segment is the leaf directory itself) are blocked. The hook's `is_rawdata_path()` enforces both shapes.

```
*/data/raw         */data/raw/*         */raw         */raw/*
*/data/interim     */data/interim/*     */data/processed   */data/processed/*
*/data             */data/*             */input       */input/*
*/inputs           */inputs/*           */datasets    */datasets/*
*/dataset          */dataset/*          */corpus      */corpus/*
*/corpora          */corpora/*
*/photos           */photos/*           */subjects    */subjects/*
*/participants     */participants/*     */respondents */respondents/*
*/media            */media/*            */imagery     */imagery/*
*/scans            */scans/*            */originals   */originals/*
*/source_images    */source_images/*
```

**Paths that pass through (unless an explicit sidecar entry says otherwise):**

- `output/<slug>/figures/*`, `output/<slug>/tables/*`, `output/<slug>/eda/figures/*` — analytical outputs
- `~/Desktop/*`, `~/Downloads/*`, `~/Pictures/*` — screenshots and personal photos outside a project
- Any path that doesn't match a raw-data segment

**To override** a block on an image that is actually safe (e.g., a published figure from another paper you're reviewing, a public logo), add an `OVERRIDE` entry to `.claude/safety-status.json` via `jq` — see §2 for the syntax.

## 8. Inheritance from `scholar-init`

When a project was created by `scholar-init`, every file in `data/raw/`, `data/interim/`, `data/processed/`, and `materials/` already has an entry in `.claude/safety-status.json`. Downstream skills (`scholar-analyze`, `scholar-eda`, `scholar-compute`, `scholar-ling`, `scholar-qual`) **inherit these decisions** rather than re-running the gate:

- The PreToolUse hook reads `.claude/safety-status.json` on every `Read` and enforces the existing status.
- If a new file appears in `data/raw/` without a sidecar entry, the hook runs `safety-scan.sh` on it on-demand and blocks with a "run `/scholar-init add <path>`" message.
- Sub-skills invoked from within an init project should NOT duplicate the scan — they should trust the sidecar and proceed under the inherited `SAFETY_STATUS`.

Skills that want to verify the inheritance explicitly can run:

```bash
if [ -f ".claude/safety-status.json" ]; then
  echo "Inherited safety-status.json with $(jq 'length' .claude/safety-status.json) entries."
  jq -r 'to_entries | group_by(.value) | map("\(length) × \(.[0].value)") | .[]' .claude/safety-status.json
fi
```

---

## 11. How to reference this policy from a skill

Any data-touching SKILL.md should contain, near the top of its workflow (as Step 0 / Phase 0 / Module 0, whatever the skill's numbering is), the following short block:

```markdown
### Step 0 — Data Safety Gate (MANDATORY)

Before any data-loading step, follow the mandatory gate defined in
`.claude/skills/_shared/data-handling-policy.md`. Run the gate against every
data-file argument; set `SAFETY_STATUS` per the state machine; if the status
is `LOCAL_MODE`, all downstream data loading in this skill MUST use the
Bash-only loader template from Section 3a / 3b of that file — no `Read` on
the data file, no `head()` / `print(df)` output. Sub-skills invoked from
here inherit `SAFETY_STATUS`.
```

The skill's own data-loading section should then branch:

```markdown
If SAFETY_STATUS is CLEARED, ANONYMIZED, or OVERRIDE → use the in-context loader below.
If SAFETY_STATUS is LOCAL_MODE → wrap the entire loader + analysis in a single
  `Rscript -e "..."` Bash call and emit summary-only output per the policy.
If SAFETY_STATUS is HALTED → the skill must have already stopped.
```

---

## 9. Known limitations

The data-handling policy is implemented as a PreToolUse hook plus a collection of Bash helpers. This design has real safety value but also real limits that users should understand.

**TOCTOU between scan and Read.** The PreToolUse hook fires *before* Claude's `Read` tool call but cannot atomically hand off the verified state to the Read itself. Between the moment `safety-scan.sh` finishes and the moment Claude's Read actually opens the file, an attacker (or an accidental file swap) could replace the file contents. The gap is narrow in practice — sub-second on a non-contended machine — but it is not zero. Mitigations in place:

- The hook resolves symlinks via `realpath` before scanning, so a symlink-swap between `safety-scan.sh` runs and `Read` will be visible in the sidecar lookup.
- The hook refuses canonical paths that resolve into `/etc`, `/dev`, `/proc`, `/sys`, `/System`, `/var/db`, `/var/log`, or their `/private/` aliases (§4a of the guard).
- The sidecar is keyed by absolute canonical path, not by file content or inode, so a file whose contents change between runs will either (a) still be blocked if it remains a known data extension, or (b) produce a fresh scan that reflects the new contents.

A determined local attacker can still win the race if they can write to the project directory. The guard is not a defense against a compromised local user account; it is a defense against accidental or policy-violating data transmission.

**Sidecar keys are strict absolute paths — no basename fallback.** The guard looks up `.claude/safety-status.json` entries by canonical path first, then raw path. It does NOT fall back to basename matching. This means:

- A hand-edited sidecar must use absolute paths. `{"foo.csv": "OVERRIDE"}` will be ignored.
- An OVERRIDE for `/path/A/foo.csv` will NOT apply to `/path/B/foo.csv` in a different project — no cross-project collision.
- If you move a project directory, the sidecar entries must be updated to the new paths (or re-run `/scholar-init review`).

**OVERRIDE rationale length is not hook-enforced.** The policy requires ≥20-character rationale for any `OVERRIDE` decision (§6), logged verbatim to `logs/init-report.md`. `scholar-init` enforces this interactively, but the PreToolUse hook does not cross-reference `init-report.md` — it trusts the sidecar value directly. What the hook *does* enforce at read-time:

- OVERRIDE on audio / video / interview-transcript extensions is refused (§4).
- Only `CLEARED`, `ANONYMIZED`, or `OVERRIDE` statuses allow the Read; any other value (including unknown future values) blocks.

A user who bypasses `scholar-init` and hand-edits the sidecar with a blank rationale can still set `OVERRIDE` on a tabular file. This is by design: the hook is a technical safeguard, not a replacement for institutional review.

**`jq` is required for reliable payload parsing.** When `jq` is absent, the guard falls back to a `sed`-based parser that cannot reliably handle escaped quotes, Unicode, or multiline fields in the hook payload. In that case the guard fails *closed* on any gated tool call (Read / NotebookRead / NotebookEdit / Grep / Glob) whose `file_path` or `path` argument could not be extracted. The practical effect: if jq is missing, the user will see a clear "install jq" message on every data-file read. Install jq before using this plugin.

---

## 10. Non-goals

- This policy does not prevent the user from reading their own sensitive data outside of Claude. It only governs what Claude sends through the API.
- It is not a substitute for IRB review, a data use agreement, or institutional data-handling policy — it is a technical backstop that enforces the minimum the skill can verify.
- It does not cover third-party model providers the user might invoke from their own scripts (e.g., a `call_openai()` call inside an R script). That is the user's responsibility.

---

## Changelog

- v1 (initial) — promotes the LOCAL_MODE pattern first introduced in `scholar-brainstorm/references/mode-data.md` to a cross-skill policy. Adds small-cell suppression rule, figure-output restriction, sub-skill propagation, and the explicit forbidden-verb list.
