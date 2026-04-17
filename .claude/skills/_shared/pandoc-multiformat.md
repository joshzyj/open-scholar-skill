# Pandoc Multi-Format Output (Shared)

All manuscript-producing skills that save output should generate 4 formats.

## Standard Conversion Block

After saving the primary .md file, run:

```bash
# Derive paths from the saved .md file
MD_FILE="[path to saved .md file]"
BASE="${MD_FILE%.md}"
OUTDIR="$(dirname "$MD_FILE")"

# Detect .bib file for citation processing (search output dir, then project root)
BIB_FILE=""
CITEPROC_FLAGS=""
for bib_candidate in "${OUTDIR}/references.bib" "${OUTDIR}/../citations/"*.bib "${OUTPUT_ROOT:-output}/citations/"*.bib; do
  if [ -f "$bib_candidate" ]; then
    BIB_FILE="$(cd "$(dirname "$bib_candidate")" && pwd)/$(basename "$bib_candidate")"
    CITEPROC_FLAGS="--citeproc --bibliography=\"$BIB_FILE\" --metadata reference-section-title=\"References\""
    echo "Found .bib file for citation processing: $BIB_FILE"
    break
  fi
done

# DOCX (with reference doc + citeproc if .bib available)
eval pandoc "$MD_FILE" -o "${BASE}.docx" \
  $CITEPROC_FLAGS \
  --reference-doc="$HOME/.pandoc/reference.docx" 2>/dev/null \
  || eval pandoc "$MD_FILE" -o "${BASE}.docx" $CITEPROC_FLAGS

# LaTeX
eval pandoc "$MD_FILE" -o "${BASE}.tex" --standalone \
  $CITEPROC_FLAGS \
  -V geometry:margin=1in -V fontsize=12pt

# PDF (requires xelatex for Unicode)
eval pandoc "$MD_FILE" -o "${BASE}.pdf" \
  --pdf-engine=xelatex \
  $CITEPROC_FLAGS \
  -V geometry:margin=1in -V fontsize=12pt 2>/dev/null \
  || echo "PDF generation requires xelatex"

echo "Converted: ${BASE}.md → .docx, .tex, .pdf"
if [ -n "$BIB_FILE" ]; then
  echo "Citations resolved via: $BIB_FILE"
fi
```

## Error Handling

- If pandoc is not installed: save .md only, log warning
- If xelatex is not installed: skip PDF, generate .md + .docx + .tex
- If reference.docx is missing: generate .docx without template (default formatting)

## Skills That MUST Generate Multi-Format

scholar-write, scholar-polish, scholar-lit-review, scholar-hypothesis, scholar-respond (response letter)

## Skills That MAY Generate Multi-Format

scholar-journal (cover letter)
