# Version Collision Avoidance Protocol

Every `/scholar-*` skill that saves output files MUST check for existing files and increment a version suffix to prevent overwriting previous work.

**This is not optional. Previous drafts are never expendable.**

---

## Critical: How to Use with the Write Tool

**Shell variables do NOT persist between Bash tool calls.** You cannot run the version check in one Bash call and use `$BASE` in a later Write tool call. Instead:

1. **Run the gate script below** — it prints `SAVE_PATH=...` to stdout
2. **Read the printed path** from the Bash output
3. **Use that exact path** as the `file_path` parameter in the Write tool call
4. **For pandoc conversions**, re-run the gate script in a new Bash call (variables reset each time)

**Do NOT skip this step and hardcode a path from the filename template.** The template (e.g., `draft-[section]-[slug]-[date].md`) shows the naming pattern, not the actual path to use.

---

## Version Check — Gate Script

Run this via the Bash tool BEFORE every Write tool call:

```bash
# MANDATORY: Replace [output_dir] and [filename_stem] with actuals
bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" \
  "[output_dir]" \
  "[filename_stem]"
# Example:
# bash "${SCHOLAR_SKILL_DIR:-.}/scripts/gates/version-check.sh" \
#   "output/drafts" \
#   "draft-intro-redlining-2026-03-21"
```

The script prints:
```
SAVE_PATH=output/drafts/draft-intro-redlining-2026-03-21.md
BASE=output/drafts/draft-intro-redlining-2026-03-21
```
(or `-v2`, `-v3`, etc. if prior versions exist)

**Use the printed `SAVE_PATH` in the Write tool call.**

---

## Rules

1. **NEVER overwrite an existing file.** Always increment the version suffix.
2. **ALL output formats (.md, .docx, .tex, .pdf) MUST share the same `$BASE` stem.** If the version check produces `-v2`, then the docx/tex/pdf also get `-v2`.
3. **Do NOT use a separate variable** for pandoc output filenames. Reuse `$BASE` throughout.
4. **Apply to ALL file types** — drafts, logs, response letters, compliance checklists, cover letters, manuscripts, etc.
5. **Apply the same logic to log files** in `${OUTPUT_ROOT}/logs/`.
6. **Re-derive `$BASE` in every new Bash call** — shell state resets between calls.

## Example

```
First run:   draft-intro-redlining-2026-03-05.md   (.docx, .tex, .pdf)
Second run:  draft-intro-redlining-2026-03-05-v2.md (.docx, .tex, .pdf)
Third run:   draft-intro-redlining-2026-03-05-v3.md (.docx, .tex, .pdf)
```

## Pandoc Conversion (CRITICAL)

**WARNING:** The gate script prints `BASE=...` to stdout as TEXT. It does NOT set `$BASE` as a shell variable. If you call `version-check.sh` and then reference `${BASE}`, it will be UNDEFINED and pandoc will overwrite wrong files.

**The correct approach:** Derive `$BASE` from the saved `.md` file path. You already know this path because you just used it in the Write tool call.

```bash
# CRITICAL: Replace [saved-md-path] with the EXACT path you used in the Write tool call.
MD_FILE="[saved-md-path]"
BASE="${MD_FILE%.md}"
OUTDIR="$(dirname "$MD_FILE")"
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"

# Detect .bib file for citation processing
BIB_FILE=""
CITEPROC_ARGS=()
for bib_candidate in "${OUTDIR}/references.bib" "${OUTPUT_ROOT}/citations/"*.bib "${OUTPUT_ROOT}/"*/citations/*.bib; do
  if [ -f "$bib_candidate" ]; then
    BIB_FILE="$(cd "$(dirname "$bib_candidate")" && pwd)/$(basename "$bib_candidate")"
    CITEPROC_ARGS=(--citeproc --bibliography="$BIB_FILE")
    break
  fi
done

# Convert — all use the same $BASE (array expansion handles paths with spaces)
pandoc "${BASE}.md" -o "${BASE}.docx" \
  "${CITEPROC_ARGS[@]}" \
  --reference-doc="$HOME/.pandoc/reference.docx" 2>/dev/null \
  || pandoc "${BASE}.md" -o "${BASE}.docx" "${CITEPROC_ARGS[@]}"

pandoc "${BASE}.md" -o "${BASE}.tex" --standalone \
  "${CITEPROC_ARGS[@]}" \
  -V geometry:margin=1in -V fontsize=12pt

pandoc "${BASE}.md" -o "${BASE}.pdf" \
  --pdf-engine=xelatex \
  "${CITEPROC_ARGS[@]}" \
  -V geometry:margin=1in -V fontsize=12pt 2>/dev/null \
  || echo "PDF generation requires a LaTeX engine"

echo "Converted: ${BASE}.md -> .docx, .tex, .pdf"
if [ -n "$BIB_FILE" ]; then echo "Citations resolved via: $BIB_FILE"; fi
```

**Why this matters:** If you use a different variable (like `DRAFT` or `FINAL`) that doesn't include the version suffix, pandoc will overwrite the previous `.docx`/`.tex`/`.pdf` files even though the `.md` was saved with a new version number.
