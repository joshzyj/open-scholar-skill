# Version Collision Avoidance Protocol

Every `/scholar-*` skill that saves output files MUST check for existing files and increment a version suffix to prevent overwriting previous work.

**This is not optional. Previous drafts are never expendable.**

---

## Critical: How to Use with the Write Tool

**Shell variables do NOT persist between Bash tool calls.** You cannot run the version check in one Bash call and use `$BASE` in a later Write tool call. Instead:

1. **Run the Bash block below** — it prints `SAVE_PATH=...` to stdout
2. **Read the printed path** from the Bash output
3. **Use that exact path** as the `file_path` parameter in the Write tool call
4. **For pandoc conversions**, re-run the same Bash logic in a new Bash call (variables reset each time)

**Do NOT skip this step and hardcode a path from the filename template.** The template (e.g., `draft-[section]-[slug]-[date].md`) shows the naming pattern, not the actual path to use.

---

## Version Check Script

Run this via the Bash tool BEFORE every Write tool call:

```bash
# MANDATORY: Replace [values] with actuals before running
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
BASE="${OUTPUT_ROOT}/drafts/draft-[section]-[slug]-[YYYY-MM-DD]"

if [ -f "${BASE}.md" ]; then
  V=2
  while [ -f "${BASE}-v${V}.md" ]; do
    V=$((V + 1))
  done
  BASE="${BASE}-v${V}"
fi

# USE THIS PATH in the Write tool call
echo "SAVE_PATH=${BASE}.md"
echo "BASE=${BASE}"
```

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

Since shell variables reset between Bash calls, you MUST re-derive `$BASE` before running pandoc:

```bash
# RE-DERIVE $BASE in the same Bash call as pandoc
OUTPUT_ROOT="${OUTPUT_ROOT:-output}"
BASE="${OUTPUT_ROOT}/drafts/draft-[section]-[slug]-[YYYY-MM-DD]"
if [ -f "${BASE}.md" ]; then
  # Find the latest existing version (the one we just saved)
  V=2
  while [ -f "${BASE}-v${V}.md" ]; do
    V=$((V + 1))
  done
  BASE="${BASE}-v$((V - 1))"
fi

# Convert — all use the same $BASE
pandoc "${BASE}.md" -o "${BASE}.docx" \
  --reference-doc="$HOME/.pandoc/reference.docx" 2>/dev/null \
  || pandoc "${BASE}.md" -o "${BASE}.docx"

pandoc "${BASE}.md" -o "${BASE}.tex" --standalone \
  -V geometry:margin=1in -V fontsize=12pt

pandoc "${BASE}.md" -o "${BASE}.pdf" \
  -V geometry:margin=1in -V fontsize=12pt 2>/dev/null \
  || echo "PDF generation requires a LaTeX engine"

echo "Converted: ${BASE}.md -> .docx, .tex, .pdf"
```

**Why this matters:** If you use a different variable (like `DRAFT` or `FINAL`) that doesn't include the version suffix, pandoc will overwrite the previous `.docx`/`.tex`/`.pdf` files even though the `.md` was saved with a new version number.
